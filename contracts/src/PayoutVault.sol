// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {IPayoutVault} from "./interfaces/IPayoutVault.sol";
import {PuppetHashing} from "./types/PuppetHashing.sol";

/// @title PayoutVault
/// @notice Pull-payment accounting for every ETH obligation the protocol creates.
/// @dev WHY THIS CONTRACT EXISTS. Settlement must never depend on an arbitrary recipient's
///      fallback succeeding. If a mint pushed ETH straight at a seller whose payout address is a
///      contract that reverts on receive, that seller could permanently block every mint of their
///      Puppet — a griefing vector that costs the attacker nothing. Here, settlement only writes a
///      number; ETH moves later, on a withdrawal the beneficiary initiates (or authorizes).
///
///      THE INVARIANT, stated once and enforced everywhere below:
///
///          address(this).balance >= totalLiability()
///
///      Every credit raises a per-beneficiary (or per-Root) bucket AND `totalLiability` by exactly
///      the ETH that arrived with the call. Every withdrawal lowers the bucket AND `totalLiability`
///      by exactly the ETH about to leave, BEFORE the external call. `releaseRootCredit` moves value
///      between two buckets and therefore leaves `totalLiability` untouched. Nothing else writes
///      those three numbers. That is the whole accounting model.
///
///      TRUST BOUNDARY. This contract knows nothing about Bitcoin. It is told to credit an address
///      or a Root key by a holder of `CREDITOR_ROLE` (the fee router and the escrow), and it is
///      told which EVM address a Root's pending balance belongs to by a holder of
///      `ROOT_RELEASER_ROLE`. Those callers derive their facts from a 3-of-5 attestor quorum, which
///      is an attested settlement system, not a trustless bridge. The original Bitcoin Puppet never
///      leaves Bitcoin and is never escrowed, wrapped or custodied here — this vault holds ETH only.
///
///      PAUSING IS ONE-DIRECTIONAL BY DESIGN. `whenNotPaused` appears on ordinary credit functions
///      and nowhere else. A pause can stop the protocol taking on NEW liabilities; it cannot block
///      refunds, terminal credits for obligations already incurred, or withdrawals. Any pause that
///      could freeze one of those exits would be an admin path to seize user funds with extra steps.
///
///      NO ADMIN PATH REDUCES A USER'S BALANCE. `_claimable` is decreased in exactly one place —
///      `_debit`, reached only through the four withdrawal entry points, each of which either runs
///      as the beneficiary or carries the beneficiary's EIP-712 signature. There is no admin
///      clawback, no "rescue", no force-transfer, and `sweepExcess` is arithmetically incapable of
///      touching a liability. `test_NoAdminPathCanReduceClaimable` enumerates every role-gated
///      function and proves each one leaves `claimable` intact.
///
///      NON-UPGRADEABLE by construction: no proxy, no initializer, no `delegatecall`, no
///      `selfdestruct`, and no owner EOA anywhere — `DEFAULT_ADMIN_ROLE` is meant for a
///      `TimelockController` under multisig control.
contract PayoutVault is IPayoutVault, AccessControl, Pausable, ReentrancyGuard, EIP712 {
    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role permitted to create liabilities by sending ETH in.
    /// @dev Held by the fee router and the offer escrow. Deliberately NOT granted at construction:
    ///      nothing should be able to write into this vault's books until governance has pointed
    ///      the role at a reviewed contract address.
    bytes32 public constant CREDITOR_ROLE = keccak256("CREDITOR_ROLE");

    /// @notice Role permitted to assign a Root's pending balance to a verified beneficiary.
    /// @dev Held by the Root ownership registry / escrow, which learns the beneficiary from an
    ///      attestor quorum. This role can only ever move value TOWARDS a user, never away.
    bytes32 public constant ROOT_RELEASER_ROLE = keccak256("ROOT_RELEASER_ROLE");

    /// @notice Role permitted to schedule and execute a sweep of unaccounted ETH.
    /// @dev Constrained to `address(this).balance - totalLiability()` by arithmetic, not by policy.
    bytes32 public constant EXCESS_SWEEPER_ROLE = keccak256("EXCESS_SWEEPER_ROLE");

    /// @notice Role permitted to halt new credits.
    /// @dev Asymmetric on purpose: `PAUSER_ROLE` can pause (the safe direction, so it may be a hot
    ///      monitoring key that reacts in seconds), but only `DEFAULT_ADMIN_ROLE` can unpause,
    ///      because resuming liability creation is the direction that re-enables risk.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                            SWEEP TIMELOCK
    //////////////////////////////////////////////////////////////*/

    /// @notice Delay between scheduling an excess sweep and being allowed to execute it.
    /// @dev The sweep can only ever move ETH that is not owed to anyone, so this delay is not
    ///      protecting user balances — the arithmetic already does that. It protects against a
    ///      compromised `EXCESS_SWEEPER_ROLE` key quietly taking mis-sent ETH before anyone
    ///      notices: the schedule is a public, indexed event, and there is a two-day window in
    ///      which governance can revoke the role or call `cancelExcessSweep`.
    uint64 public constant SWEEP_DELAY = 2 days;

    /// @notice How long a matured sweep stays executable before it must be scheduled again.
    /// @dev Without an expiry, one schedule would be a standing authorization for the lifetime of
    ///      the contract, which defeats the point of announcing it in advance.
    uint64 public constant SWEEP_EXECUTION_WINDOW = 7 days;

    /*//////////////////////////////////////////////////////////////
                              EXTRA ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when `sweepExcess` runs with no schedule standing.
    error ExcessSweepNotScheduled();

    /// @notice Thrown when `sweepExcess` runs before its timelock has matured.
    /// @param readyAt Timestamp the schedule becomes executable.
    /// @param nowTs Current block timestamp.
    error ExcessSweepNotReady(uint64 readyAt, uint256 nowTs);

    /// @notice Thrown when a matured schedule has passed its execution window.
    /// @param expiresAt Timestamp the schedule stopped being executable.
    /// @param nowTs Current block timestamp.
    error ExcessSweepExpired(uint64 expiresAt, uint256 nowTs);

    /// @notice Thrown when `sweepExcess` names a different recipient than the one announced.
    /// @dev The recipient is bound at schedule time so the announcement is meaningful: an observer
    ///      must be able to see WHERE the ETH is going during the delay, not just that a sweep is
    ///      coming.
    /// @param scheduled Recipient bound by the standing schedule.
    /// @param provided Recipient passed to `sweepExcess`.
    error ExcessSweepRecipientMismatch(address scheduled, address provided);

    /*//////////////////////////////////////////////////////////////
                              EXTRA EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, recording the genesis admin.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE` and `EXCESS_SWEEPER_ROLE`.
    event VaultInitialized(address indexed admin);

    /// @notice Emitted when an excess sweep is announced.
    /// @param recipient Address the sweep will pay.
    /// @param readyAt Timestamp the sweep becomes executable.
    /// @param expiresAt Timestamp the sweep stops being executable.
    /// @param scheduler Caller that announced it.
    event ExcessSweepScheduled(address indexed recipient, uint64 readyAt, uint64 expiresAt, address indexed scheduler);

    /// @notice Emitted when a standing excess sweep schedule is withdrawn.
    /// @param recipient Recipient the cancelled schedule was bound to.
    /// @param canceller Caller that cancelled it.
    event ExcessSweepCancelled(address indexed recipient, address indexed canceller);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev ETH each beneficiary may withdraw right now. Decreased in exactly one function.
    mapping(address => uint256) private _claimable;

    /// @dev ETH held against a Root key whose EVM beneficiary is not yet established.
    mapping(bytes32 => uint256) private _pendingByRoot;

    /// @dev Next expected gasless-withdrawal nonce, per beneficiary. Strictly sequential rather
    ///      than a bitmap: sellers sign at most a handful of authorizations, and a sequential nonce
    ///      makes "the previous authorization is dead" trivially auditable off chain.
    mapping(address => uint256) private _withdrawalNonce;

    /// @dev `sum(_claimable) + sum(_pendingByRoot)`, maintained incrementally.
    uint256 private _totalLiability;

    /// @dev Recipient bound by the standing sweep schedule; zero when none stands.
    address payable private _scheduledSweepRecipient;

    /// @dev Timestamp the standing schedule matures. Packs into the slot above.
    uint64 private _sweepReadyAt;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the vault and bind its administrator.
    /// @dev `admin` MUST be a `TimelockController` governed by a multisig in production. Nothing
    ///      here can enforce that, so the deployment script is responsible for granting roles to
    ///      the timelock and revoking the deployer in the same batch.
    ///
    ///      `CREDITOR_ROLE` and `ROOT_RELEASER_ROLE` are intentionally left unassigned: they are
    ///      the two roles that write the books, and they belong to contract addresses that do not
    ///      exist yet at this point in the deployment. `EXCESS_SWEEPER_ROLE` is granted because it
    ///      cannot touch a liability and is additionally timelocked in-contract.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE` and `EXCESS_SWEEPER_ROLE`.
    constructor(address admin) EIP712("HoodPups PayoutVault", "1") {
        if (admin == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(EXCESS_SWEEPER_ROLE, admin);

        emit VaultInitialized(admin);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPayoutVault
    /// @param beneficiary Address whose withdrawable balance is read.
    /// @return ETH `beneficiary` may withdraw right now.
    function claimable(address beneficiary) external view returns (uint256) {
        return _claimable[beneficiary];
    }

    /// @inheritdoc IPayoutVault
    /// @param rootKey Canonical `PuppetHashing.rootKey` of the inscription.
    /// @return ETH held against that Root, not yet assigned to any address.
    function pendingByRoot(bytes32 rootKey) external view returns (uint256) {
        return _pendingByRoot[rootKey];
    }

    /// @inheritdoc IPayoutVault
    /// @return Sum of every obligation the vault owes.
    function totalLiability() external view returns (uint256) {
        return _totalLiability;
    }

    /// @inheritdoc IPayoutVault
    /// @param beneficiary Address whose nonce is read.
    /// @return Next nonce a gasless authorization from `beneficiary` must carry.
    function withdrawalNonce(address beneficiary) external view returns (uint256) {
        return _withdrawalNonce[beneficiary];
    }

    /// @inheritdoc IPayoutVault
    /// @dev Returns 0 rather than reverting in the (unreachable) case that the balance is below the
    ///      recorded liability. A view that reverts would break every UI reading it, and the
    ///      condition it would be reporting cannot arise: liabilities only ever grow by exactly the
    ///      ETH that arrived alongside them.
    /// @return Unaccounted ETH — force-sent via `selfdestruct` or block rewards — and nothing else.
    function excessBalance() public view returns (uint256) {
        uint256 balance = address(this).balance;
        uint256 liability = _totalLiability;
        return balance > liability ? balance - liability : 0;
    }

    /// @notice Recipient and maturity of the standing excess-sweep schedule.
    /// @dev Zero recipient means no sweep is scheduled.
    /// @return recipient Address the standing schedule will pay.
    /// @return readyAt Timestamp it becomes executable.
    /// @return expiresAt Timestamp it stops being executable.
    function scheduledSweep() external view returns (address recipient, uint64 readyAt, uint64 expiresAt) {
        recipient = _scheduledSweepRecipient;
        readyAt = _sweepReadyAt;
        expiresAt = readyAt == 0 ? 0 : readyAt + SWEEP_EXECUTION_WINDOW;
    }

    /// @notice EIP-712 digest a beneficiary must sign to authorize a gasless withdrawal.
    /// @dev Exposed so relayers and the SDK sign exactly what this contract verifies, rather than
    ///      re-deriving the domain separator and risking a silent mismatch. The struct hash comes
    ///      from `PuppetHashing.hashWithdrawal`, which is the single source of truth for the type.
    /// @param beneficiary Account whose balance is being spent.
    /// @param recipient Address that receives the ETH.
    /// @param amount Wei to move.
    /// @param nonce Expected value of `withdrawalNonce(beneficiary)` at execution time.
    /// @param deadline Last timestamp at which the authorization is valid.
    /// @return The EIP-712 digest to sign.
    function withdrawalDigest(address beneficiary, address recipient, uint256 amount, uint256 nonce, uint64 deadline)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(PuppetHashing.hashWithdrawal(beneficiary, recipient, amount, nonce, deadline));
    }

    /*//////////////////////////////////////////////////////////////
                                CREDITING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPayoutVault
    /// @dev Raises `_claimable[beneficiary]` and `_totalLiability` by exactly `msg.value`, so the
    ///      core invariant is preserved by construction: the ETH backing the new liability arrived
    ///      in the same call that created it.
    /// @param beneficiary Address to credit.
    function credit(address beneficiary) external payable onlyRole(CREDITOR_ROLE) whenNotPaused {
        _credit(beneficiary, msg.value);
        emit Credited(beneficiary, msg.value, msg.sender);
    }

    /// @notice Credit a refund. Deliberately NOT pausable.
    /// @dev Protocol invariant I12: pausing must never block a refund or a withdrawal.
    ///
    ///      The credit pause exists to stop the protocol taking on NEW obligations during an
    ///      incident. A refund is not a new obligation — it is the release of one the buyer already
    ///      holds, against ETH the escrow is already carrying on their behalf. Blocking it would not
    ///      protect anyone; it would strand the buyer's own money inside the escrow for exactly as
    ///      long as the incident lasted, which is when they most want it back.
    ///
    ///      This was found by the integration suite, not by this contract's own tests: `credit` is
    ///      correctly pausable, `withdraw` is correctly not, and the escrow's refund path correctly
    ///      survives an escrow pause. The violation only appeared once both contracts were wired
    ///      together and the VAULT was paused instead — see `test/integration/FullFlow.t.sol`.
    ///
    ///      Still `CREDITOR_ROLE`-gated, so only protocol contracts can reach it, and it moves no
    ///      more value than `credit` does.
    /// @param beneficiary The buyer being made whole. Must be non-zero.
    function creditRefund(address beneficiary) external payable onlyRole(CREDITOR_ROLE) {
        _credit(beneficiary, msg.value);
        emit Credited(beneficiary, msg.value, msg.sender);
        emit RefundCredited(beneficiary, msg.value, msg.sender);
    }

    /// @inheritdoc IPayoutVault
    /// @dev This is the accounting equivalent of `creditRefund`: the ETH backs an obligation that
    ///      was already created outside this transaction. For BTC settlement, the solver may have
    ///      irreversibly paid Bitcoin before an EVM pause is raised; for expiry, the bond already
    ///      belongs to its deterministic recipients. Pausing either terminal write would turn the
    ///      incident switch into a confiscation lever.
    function creditTerminal(address beneficiary) external payable onlyRole(CREDITOR_ROLE) {
        _credit(beneficiary, msg.value);
        emit Credited(beneficiary, msg.value, msg.sender);
        emit TerminalCredited(beneficiary, msg.value, msg.sender);
    }

    /// @inheritdoc IPayoutVault
    /// @dev Used when the protocol owes value to whoever controls a Bitcoin Puppet but does not yet
    ///      have an attested EVM address for them. The ETH is a liability from this moment, which
    ///      is why `_totalLiability` moves here and NOT in `releaseRootCredit`.
    /// @param rootKey Canonical `PuppetHashing.rootKey` of the inscription to credit.
    function creditRoot(bytes32 rootKey) external payable onlyRole(CREDITOR_ROLE) whenNotPaused {
        if (rootKey == bytes32(0)) revert ZeroRootKey();
        if (msg.value == 0) revert ZeroAmount();

        _pendingByRoot[rootKey] += msg.value;
        _totalLiability += msg.value;

        emit RootCredited(rootKey, msg.value, msg.sender);
    }

    /// @inheritdoc IPayoutVault
    /// @dev The sum of `amounts` must equal `msg.value` EXACTLY. A batch that under-spends would
    ///      leave ETH in the contract that no one is credited for — indistinguishable from
    ///      force-sent ETH, and therefore sweepable — and a batch that over-spends would create
    ///      liabilities with nothing behind them, breaking the core invariant. Both are rejected
    ///      rather than tolerated, because a partially-correct payout batch is a silent loss.
    /// @param beneficiaries Addresses to credit, in order.
    /// @param amounts Wei to credit each address.
    function creditBatch(address[] calldata beneficiaries, uint256[] calldata amounts)
        external
        payable
        onlyRole(CREDITOR_ROLE)
        whenNotPaused
    {
        _creditBatch(beneficiaries, amounts, false);
    }

    /// @inheritdoc IPayoutVault
    function creditTerminalBatch(address[] calldata beneficiaries, uint256[] calldata amounts)
        external
        payable
        onlyRole(CREDITOR_ROLE)
    {
        _creditBatch(beneficiaries, amounts, true);
    }

    /// @dev Shared exact-conservation implementation for ordinary and terminal batches.
    function _creditBatch(address[] calldata beneficiaries, uint256[] calldata amounts, bool terminal) private {
        uint256 length = beneficiaries.length;
        if (length != amounts.length) revert ArrayLengthMismatch(length, amounts.length);

        uint256 total;
        for (uint256 i = 0; i < length; i++) {
            address beneficiary = beneficiaries[i];
            uint256 amount = amounts[i];
            if (beneficiary == address(0)) revert ZeroAddress();
            // A zero entry is rejected rather than skipped: it is always a bug in the caller's
            // split arithmetic, and skipping it would emit a payout event for nothing.
            if (amount == 0) revert ZeroAmount();

            total += amount;
            _claimable[beneficiary] += amount;

            emit Credited(beneficiary, amount, msg.sender);
            if (terminal) emit TerminalCredited(beneficiary, amount, msg.sender);
        }

        // Also catches the empty-array call, whose total is 0.
        if (total == 0) revert ZeroAmount();
        if (total != msg.value) revert AmountMismatch(total, msg.value);

        _totalLiability += total;
    }

    /// @dev Shared single-beneficiary accounting. Events remain purpose-specific at the wrappers.
    function _credit(address beneficiary, uint256 amount) private {
        if (beneficiary == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _claimable[beneficiary] += amount;
        _totalLiability += amount;
    }

    /*//////////////////////////////////////////////////////////////
                              ROOT RELEASE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPayoutVault
    /// @dev PURE BOOKKEEPING. No ETH moves and `_totalLiability` is not written, because the
    ///      obligation already existed — `creditRoot` created it. All that changes is WHO may
    ///      withdraw it. Writing `_totalLiability` here would double-count the same wei and break
    ///      the invariant in the direction that lets the vault promise more than it holds;
    ///      `test_ReleaseRootCreditLeavesTotalLiabilityUnchanged` pins this.
    ///
    ///      The release is all-or-nothing, so the interface's `InsufficientPendingRoot` cannot
    ///      arise from this implementation; an empty bucket is reported as `ZeroAmount`. Partial
    ///      release is deliberately absent: splitting one Root's proceeds across addresses is an
    ///      off-chain policy decision that has no attested Bitcoin fact behind it.
    ///
    ///      Not `whenNotPaused`: this is the step that makes an existing obligation withdrawable,
    ///      and pausing it would freeze money the protocol already owes.
    /// @param rootKey Root whose pending bucket is being assigned.
    /// @param beneficiary Address that may now withdraw it.
    /// @return amount Wei moved from pending to claimable.
    function releaseRootCredit(bytes32 rootKey, address beneficiary)
        external
        onlyRole(ROOT_RELEASER_ROLE)
        returns (uint256 amount)
    {
        if (beneficiary == address(0)) revert ZeroAddress();
        if (rootKey == bytes32(0)) revert ZeroRootKey();

        amount = _pendingByRoot[rootKey];
        if (amount == 0) revert ZeroAmount();

        _pendingByRoot[rootKey] = 0;
        _claimable[beneficiary] += amount;

        emit RootCreditReleased(rootKey, beneficiary, amount);
    }

    /*//////////////////////////////////////////////////////////////
                               WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPayoutVault
    /// @dev No pause modifier, by design. See the contract-level notes.
    /// @param amount Wei to withdraw to `msg.sender`.
    function withdraw(uint256 amount) external nonReentrant {
        _debit(msg.sender, payable(msg.sender), amount);
    }

    /// @inheritdoc IPayoutVault
    /// @dev Reverts with `ZeroAmount` when there is nothing to withdraw, rather than succeeding as
    ///      a no-op that emits a payout event for zero wei.
    function withdrawAll() external nonReentrant {
        _debit(msg.sender, payable(msg.sender), _claimable[msg.sender]);
    }

    /// @inheritdoc IPayoutVault
    /// @dev Spends the CALLER's balance; `recipient` is only a destination and gains no standing
    ///      claim on the vault. This is what lets a hot wallet sweep earnings to cold storage.
    /// @param recipient Address that receives the ETH.
    /// @param amount Wei to withdraw.
    function withdrawTo(address payable recipient, uint256 amount) external nonReentrant {
        _debit(msg.sender, recipient, amount);
    }

    /// @inheritdoc IPayoutVault
    /// @dev THE ZERO-GAS PATH. A seller who has just sold their first Puppet may hold no ETH at
    ///      all, so they sign an authorization off chain and any relayer submits it.
    ///
    ///      Ordering is load bearing and matches checks-effects-interactions:
    ///        1. deadline, nonce and signature are checked;
    ///        2. the nonce is incremented — BEFORE any ETH moves, so a recipient that reenters
    ///           this function cannot replay the same authorization even if the reentrancy guard
    ///           were somehow absent;
    ///        3. `_debit` writes the balances, then makes the transfer.
    ///
    ///      `SignatureChecker.isValidSignatureNow` accepts both a 65-byte EOA signature and an
    ///      ERC-1271 response from a smart account. ERC-1271 validity is revocable — a wallet may
    ///      answer differently at a later block — which is precisely why the nonce and deadline are
    ///      enforced independently of the signature and not derived from it.
    /// @param beneficiary Account whose balance is spent.
    /// @param recipient Address that receives the ETH.
    /// @param amount Wei to withdraw.
    /// @param nonce Must equal the beneficiary's current `withdrawalNonce`.
    /// @param deadline Last timestamp at which the authorization is valid.
    /// @param signature EOA or ERC-1271 signature over `withdrawalDigest(...)`.
    function withdrawWithAuthorization(
        address beneficiary,
        address payable recipient,
        uint256 amount,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) external nonReentrant {
        if (beneficiary == address(0)) revert ZeroAddress();
        if (block.timestamp > deadline) revert ExpiredAuthorization(deadline, block.timestamp);

        uint256 expectedNonce = _withdrawalNonce[beneficiary];
        if (nonce != expectedNonce) revert InvalidNonce(expectedNonce, nonce);

        bytes32 digest = withdrawalDigest(beneficiary, recipient, amount, nonce, deadline);
        if (!SignatureChecker.isValidSignatureNow(beneficiary, digest, signature)) {
            revert InvalidAuthorizationSignature();
        }

        _withdrawalNonce[beneficiary] = expectedNonce + 1;

        _debit(beneficiary, recipient, amount);

        emit WithdrawnWithAuthorization(beneficiary, recipient, amount, nonce, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                               EXCESS ETH
    //////////////////////////////////////////////////////////////*/

    /// @notice Announce an excess sweep, starting its `SWEEP_DELAY` timelock.
    /// @dev Scheduling only binds a recipient and a time. The AMOUNT is computed at execution, so a
    ///      schedule can never authorize more than the excess standing at the moment it runs, and
    ///      can never be pre-armed to capture a future credit.
    /// @param recipient Address the sweep will pay. Overwrites any standing schedule.
    function scheduleExcessSweep(address payable recipient) external onlyRole(EXCESS_SWEEPER_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();

        uint64 readyAt = uint64(block.timestamp) + SWEEP_DELAY;
        _scheduledSweepRecipient = recipient;
        _sweepReadyAt = readyAt;

        emit ExcessSweepScheduled(recipient, readyAt, readyAt + SWEEP_EXECUTION_WINDOW, msg.sender);
    }

    /// @notice Withdraw a standing excess-sweep schedule.
    /// @dev Available to the sweeper role itself and to `DEFAULT_ADMIN_ROLE` via role revocation;
    ///      cancelling is always safe, so it is not itself timelocked.
    function cancelExcessSweep() external onlyRole(EXCESS_SWEEPER_ROLE) {
        address recipient = _scheduledSweepRecipient;
        if (recipient == address(0)) revert ExcessSweepNotScheduled();

        _scheduledSweepRecipient = payable(address(0));
        _sweepReadyAt = 0;

        emit ExcessSweepCancelled(recipient, msg.sender);
    }

    /// @inheritdoc IPayoutVault
    /// @dev EXISTS ONLY FOR ETH THAT NO ACCOUNTING PATH CREATED. `receive`/`fallback` reject direct
    ///      deposits, but the EVM has two paths that cannot be refused: a `selfdestruct` beneficiary
    ///      payment and a block-reward/withdrawal credit. That ETH must never silently become a
    ///      user liability (it has no owner), and must never be strandable either.
    ///
    ///      The amount is `address(this).balance - totalLiability()`, computed here, at execution.
    ///      It is arithmetically impossible for this function to move a single wei that any user is
    ///      owed, regardless of who holds the role: after the transfer the remaining balance is
    ///      exactly `totalLiability()`.
    /// @param recipient Must equal the recipient bound by the standing schedule.
    /// @return amount Wei swept.
    function sweepExcess(address payable recipient)
        external
        onlyRole(EXCESS_SWEEPER_ROLE)
        nonReentrant
        returns (uint256 amount)
    {
        address scheduled = _scheduledSweepRecipient;
        uint64 readyAt = _sweepReadyAt;

        if (scheduled == address(0)) revert ExcessSweepNotScheduled();
        if (recipient != scheduled) revert ExcessSweepRecipientMismatch(scheduled, recipient);
        if (block.timestamp < readyAt) revert ExcessSweepNotReady(readyAt, block.timestamp);

        uint64 expiresAt = readyAt + SWEEP_EXECUTION_WINDOW;
        if (block.timestamp > expiresAt) revert ExcessSweepExpired(expiresAt, block.timestamp);

        amount = excessBalance();
        if (amount == 0) revert NoExcess();

        // The schedule is consumed before the transfer: one announcement authorizes one sweep.
        _scheduledSweepRecipient = payable(address(0));
        _sweepReadyAt = 0;

        emit ExcessSwept(recipient, amount);

        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert WithdrawalFailed(recipient, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                 PAUSING
    //////////////////////////////////////////////////////////////*/

    /// @notice Stop the vault accepting new credits.
    /// @dev Withdrawals are unaffected. See the contract-level notes for why that is not
    ///      negotiable.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resume accepting credits.
    /// @dev Restricted to `DEFAULT_ADMIN_ROLE` (the timelock) rather than `PAUSER_ROLE`, so a
    ///      compromised fast-reaction key can stop the protocol but cannot restart it.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @dev The ONLY place `_claimable` is ever decreased, and the only place ETH leaves the vault
    ///      against a liability. Both callers reach it either as the beneficiary or with the
    ///      beneficiary's signature, which is what makes "no admin path can reduce a user's
    ///      balance" a structural property rather than a review promise.
    ///
    ///      Both subtractions use checked arithmetic even though the guard above each one already
    ///      proves they cannot underflow. The duplicated check costs a little gas and buys a hard
    ///      failure instead of a silent wrap if a future edit ever moves one of those guards; on a
    ///      path that moves user funds that is the right trade.
    /// @param beneficiary Account whose balance is spent.
    /// @param recipient Address that receives the ETH.
    /// @param amount Wei to move.
    function _debit(address beneficiary, address payable recipient, uint256 amount) private {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 available = _claimable[beneficiary];
        if (amount > available) revert InsufficientClaimable(beneficiary, amount, available);

        // EFFECTS: both sides of the invariant fall by the same amount, before any interaction.
        _claimable[beneficiary] = available - amount;
        _totalLiability -= amount;

        emit Withdrawn(beneficiary, recipient, amount);

        // INTERACTION. All remaining gas is forwarded rather than a 2300-gas stipend: a smart
        // account or a multisig legitimately needs more than that to accept ETH, and a payout the
        // recipient cannot receive is a payout that does not exist. Reentrancy is covered by the
        // guard on every external entry point, and the accounting above is already final.
        (bool ok,) = recipient.call{value: amount}("");
        // A rejecting recipient rolls the whole transaction back, so the balance is restored
        // automatically and the beneficiary can simply withdraw somewhere else.
        if (!ok) revert WithdrawalFailed(recipient, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          DIRECT DEPOSIT REJECTION
    //////////////////////////////////////////////////////////////*/

    /// @dev ETH with no beneficiary attached is not a donation, it is a mistake — most often a
    ///      settlement contract that forgot to call `credit`. Accepting it silently would make the
    ///      vault's books disagree with its balance in the one direction nobody audits (surplus),
    ///      and would leave a user's funds looking like sweepable excess. Both entry points revert.
    receive() external payable {
        revert DirectDepositRejected();
    }

    /// @dev Also catches calls to a selector this contract does not implement, which is very often
    ///      an integrator pointing at the wrong ABI or the wrong address.
    fallback() external payable {
        revert DirectDepositRejected();
    }
}
