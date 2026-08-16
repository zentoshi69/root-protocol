// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IBitcoinOwnershipOracle} from "./interfaces/IBitcoinOwnershipOracle.sol";
import {IPayoutVault} from "./interfaces/IPayoutVault.sol";
import {IRootOwnershipRegistry} from "./interfaces/IRootOwnershipRegistry.sol";
import {PuppetHashing} from "./types/PuppetHashing.sol";
import {PuppetTypes} from "./types/PuppetTypes.sol";

/// @title RootOwnershipRegistry
/// @notice Records which Bitcoin controller is currently *attested* to own each Root, as a chain of
///         monotonic ownership epochs, and routes Root-linked value to that controller.
/// @dev WHAT THIS CONTRACT IS FOR. Recurring Root-linked value (tour revenue, protocol fee shares)
///      has to be paid to somebody. "Somebody" is whoever currently controls the Bitcoin Puppet
///      inscription. This contract is the only place in the protocol that answers that question,
///      and every answer it gives comes from exactly two sources:
///
///        1. a 3-of-5 quorum attestation consumed through `BitcoinOwnershipOracle`, or
///        2. the authorized escrow's `MINT_RECORDER_ROLE` call, made immediately after the escrow
///           itself consumed a mint ownership attestation through the same oracle.
///
///      There is no third source. No admin function assigns, reassigns or clears a beneficiary,
///      and there is no path by which governance can point a Root at an address of its choosing.
///
///      TRUST BOUNDARY — READ THIS BEFORE TRUSTING ANY VALUE THIS CONTRACT RETURNS. Nothing here
///      verifies Bitcoin consensus. Bitcoin facts are asserted by a 3-of-5 quorum of independent
///      attestor operators. This is an attested settlement system, not a trustless bridge. The
///      original Bitcoin Puppet never leaves Bitcoin: it is never bridged, wrapped, custodied or
///      escrowed, and nothing in this contract can move it.
///
///      THE STALE-WATCHER WINDOW — THE MOST IMPORTANT CAVEAT IN THIS FILE.
///      This registry records attested state, not live state. When Bob sells his Puppet on Bitcoin,
///      this contract keeps naming Bob until somebody submits a `RootSpendAttestation` proving the
///      recorded outpoint was spent. Between the Bitcoin spend and that submission, recurring
///      Root-linked value routed through `FeeRouter` is credited to Bob, and Charlie cannot recover
///      it. That window is unavoidable in an attested design; it can be made short, never zero.
///
///      Four properties bound the damage, and each one is enforced somewhere in this file or its
///      immediate neighbours:
///        * Only RECURRING value is exposed. A new mint needs a fresh ownership proof, which a
///          seller who no longer controls the inscription cannot produce.
///        * Once the epoch closes, future value accrues to `PayoutVault.pendingByRoot(rootKey)`
///          and is released to whoever next proves control — not to the stale beneficiary.
///        * `invalidateRoot` is PERMISSIONLESS. Charlie, who has the strongest possible incentive,
///          does not need anyone's permission to close Bob's epoch, and neither does a watcher bot.
///        * `bindRootOwner` is PERMISSIONLESS too, so Charlie's own bind can supersede an active
///          stale epoch directly (new outpoint, non-decreasing Bitcoin height) without waiting for
///          a separate invalidation.
///      The window is real. Front-end copy must say so; see `docs/TRUST_ASSUMPTIONS.md`.
///
///      MONEY ALREADY EARNED IS NEVER CLAWED BACK. Closing an epoch touches this contract's
///      bookkeeping only. Balances already credited inside `PayoutVault` belong to the address they
///      were credited to, permanently, and neither an invalidation nor a rebind can reduce them.
///      That is why the invalidation path writes no vault call at all.
///
///      PAUSING. `whenNotPaused` appears on `bindRootOwner` and `invalidateRoot` — the two
///      permissionless paths that consume attestations and take on new state — and NOWHERE else.
///      A pause cannot alter recorded state, cannot block any view, cannot block a `PayoutVault`
///      withdrawal, and cannot block `releasePendingRootCredit`, which only forwards value the
///      protocol already owes to an already-recorded owner. `recordMintOwnership` is deliberately
///      not pausable either: pausing this registry must never brick the escrow's settlement path,
///      which has its own pause and its own role gate.
///
///      NON-UPGRADEABLE by construction: no proxy, no initializer, no `delegatecall`, no
///      `selfdestruct`, no `tx.origin`, and no owner EOA — `DEFAULT_ADMIN_ROLE` is intended for a
///      `TimelockController` under multisig control.
contract RootOwnershipRegistry is IRootOwnershipRegistry, AccessControl, Pausable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role permitted to record the FIRST ownership epoch as part of a mint settlement.
    /// @dev Held by `HoodPupOfferEscrow` and nothing else. This role is trusted for one narrow
    ///      claim: "I have just consumed, through the oracle, an ownership attestation carrying
    ///      exactly these facts." It cannot rebind an existing Root, cannot invalidate one, and
    ///      cannot touch any epoch after the first — those checks live in `recordMintOwnership`
    ///      and are not waivable by any role.
    ///
    ///      Deliberately NOT granted at construction: the escrow does not exist yet at deployment
    ///      step 5, and pre-granting it to the deployer would create exactly the EOA-holds-
    ///      privilege state the timelock handover is meant to eliminate.
    bytes32 public constant MINT_RECORDER_ROLE = keccak256("MINT_RECORDER_ROLE");

    /// @notice Role permitted to halt new activations and invalidations.
    /// @dev Asymmetric on purpose, matching the rest of the protocol: `PAUSER_ROLE` may pause (the
    ///      safe direction, so it can be a hot guardian key that reacts in seconds) but only
    ///      `DEFAULT_ADMIN_ROLE` may unpause, because resuming attestation consumption is the
    ///      direction that re-enables risk.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              EXTRA ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when `recordMintOwnership` runs against a Root that already has an epoch.
    /// @dev Distinct from `RootAlreadyActive`, which covers a Root that is currently ACTIVE. A Root
    ///      whose epoch has been closed is not "already active", and reverting with that error
    ///      would be a lie in the trace. One canonical inscription mints at most one HoodPup ever,
    ///      so the mint recorder is single-use per Root either way.
    /// @param rootKey Canonical protocol key of the inscription.
    /// @param epoch The epoch that already exists.
    error RootEpochAlreadyExists(bytes32 rootKey, uint64 epoch);

    /// @notice Thrown when a `ROOT_BIND` attestation does not elect the EVM payout mode.
    /// @dev A `ROOT_BIND` binds an EVM address to a Root. A BTC (or NONE) payout mode carries no
    ///      EVM address to bind, so accepting one would mean inventing a beneficiary.
    /// @param payoutMode The `PuppetTypes.PayoutMode` value that was supplied.
    error UnsupportedPayoutMode(uint8 payoutMode);

    /// @notice Thrown when an activation supplies a zero inscription reveal txid.
    /// @dev The shape of a default-initialised struct reaching an activation path.
    error ZeroRootTxid();

    /// @notice Thrown when an activation supplies a zero Bitcoin outpoint hash.
    /// @dev A zero outpoint would make the `UnchangedOutpoint` guard and the invalidation
    ///      `previousOutpointHash` match meaningless, so it is rejected at both entry points.
    error ZeroOutpointHash();

    /// @notice Thrown when an activation supplies a zero owner script hash.
    error ZeroScriptHash();

    /// @notice Thrown when the mint recorder supplies a zero ownership digest.
    /// @dev The digest is the audit link from this epoch back to the attestation the escrow
    ///      consumed. Recording an epoch with no such link would make the history unverifiable.
    error ZeroOwnershipDigest();

    /// @notice Thrown when an attestation carries a zero authorization id.
    /// @dev Belt and braces: the real `BitcoinOwnershipOracle` rejects this too. It is repeated
    ///      here because it is cheap and because a mock oracle used in another suite may not.
    error ZeroAuthorizationId();

    /// @notice Thrown when a spend attestation carries a zero spending txid.
    error ZeroSpendingTxid();

    /// @notice Thrown when a `ROOT_BIND` attestation's `contextId` is neither zero nor the rootKey.
    /// @dev `PuppetTypes` defines `contextId` for `ROOT_BIND` as "zero-or-root-scoped". Enforcing
    ///      that keeps a `ROOT_BIND` signature raised inside some other subsystem's context from
    ///      being replayed here, and costs one comparison.
    /// @param contextId The context that was supplied.
    error InvalidBindContext(bytes32 contextId);

    /// @notice Thrown when the vault releases a different amount than it reported as pending.
    /// @dev Defensive: it can only fire if the vault's `pendingByRoot` view and its
    ///      `releaseRootCredit` accounting disagree, which would be a vault bug. Failing loudly
    ///      beats writing an activation event whose `releasedPending` figure is fiction.
    /// @param expected Amount `pendingByRoot` reported immediately before the release.
    /// @param released Amount `releaseRootCredit` actually moved.
    error PendingReleaseMismatch(uint256 expected, uint256 released);

    /// @notice Thrown when `releasePendingRootCredit` finds nothing to forward.
    /// @param rootKey Canonical protocol key of the inscription.
    error NoPendingRootBalance(bytes32 rootKey);

    /*//////////////////////////////////////////////////////////////
                              EXTRA EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, recording the immutable wiring of this registry.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param oracle The `BitcoinOwnershipOracle` every attestation is consumed through.
    /// @param payoutVault The `PayoutVault` pending Root balances are released from.
    event RegistryInitialized(address indexed admin, address indexed oracle, address indexed payoutVault);

    /// @notice Emitted when a fresh bind closes a still-active epoch without a spend attestation.
    /// @dev Distinct from `RootEpochInvalidated` on purpose. No spend was ever attested here, so
    ///      emitting the invalidation event with a zero `spendingTxid` would tell an indexer that
    ///      a Bitcoin spend happened when none was proven. This event says what actually occurred:
    ///      a newer, non-decreasing-height ownership proof for a DIFFERENT outpoint arrived while
    ///      the old epoch was still open.
    /// @param rootKey Canonical protocol key of the inscription.
    /// @param epoch The epoch being closed.
    /// @param previousBeneficiary Beneficiary that epoch named. Their credited balance is untouched.
    /// @param newEpoch The epoch that supersedes it.
    /// @param bitcoinHeight Bitcoin height of the superseding attestation.
    event RootEpochSuperseded(
        bytes32 indexed rootKey,
        uint64 indexed epoch,
        address indexed previousBeneficiary,
        uint64 newEpoch,
        uint64 bitcoinHeight
    );

    /*//////////////////////////////////////////////////////////////
                             INTERNAL TYPES
    //////////////////////////////////////////////////////////////*/

    /// @dev The seven Bitcoin-side facts an activation binds, carried as one memory struct.
    ///      Grouping them is not cosmetic: passing them individually pushes `_activate` past the
    ///      EVM's 16-slot stack limit with `via_ir` disabled, and enabling `via_ir` for one
    ///      function would change codegen for the whole protocol.
    struct ActivationFacts {
        address beneficiary;
        bytes32 outpointHash;
        bytes32 ownerScriptHash;
        bytes32 ownershipDigest;
        bytes32 bip322ProofHash;
        bytes32 bitcoinBlockHash;
        uint64 bitcoinHeight;
    }

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The oracle every attestation consumed by this registry passes through.
    /// @dev Immutable: a swappable oracle pointer would be an admin path to redefine what counts as
    ///      proof of Bitcoin control, which is the same thing as an admin path to assign ownership.
    ///      Replacing the oracle requires redeploying this registry and repointing its consumers.
    IBitcoinOwnershipOracle public immutable ORACLE;

    /// @notice The vault whose pending Root balances this registry releases.
    /// @dev Immutable for the same reason: the release target must not be governable.
    IPayoutVault public immutable PAYOUT_VAULT;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Current attested state per Root. Written only by `_activate` and `invalidateRoot`.
    mapping(bytes32 => PuppetTypes.RootState) private _rootState;

    /// @dev Per-epoch history. A record's activation fields are written exactly once, when the
    ///      epoch opens, and are never rewritten; only the two deactivation fields are filled in
    ///      later, exactly once, when it closes. That makes the full ownership history of a Root
    ///      reconstructible on chain, not only from events.
    mapping(bytes32 => mapping(uint64 => PuppetTypes.RootEpochInfo)) private _rootEpochInfo;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the registry against a fixed oracle and vault.
    /// @dev `MINT_RECORDER_ROLE` is intentionally left unassigned; see the role's own NatSpec.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`. Must be a
    ///        `TimelockController` in production — never an EOA.
    /// @param oracle Address of the deployed `BitcoinOwnershipOracle`.
    /// @param payoutVault Address of the deployed `PayoutVault`.
    constructor(address admin, address oracle, address payoutVault) {
        if (admin == address(0) || oracle == address(0) || payoutVault == address(0)) revert ZeroAddress();

        ORACLE = IBitcoinOwnershipOracle(oracle);
        PAYOUT_VAULT = IPayoutVault(payoutVault);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        emit RegistryInitialized(admin, oracle, payoutVault);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev Returns a zeroed struct for a Root that has never been activated. `beneficiary` and
    ///      `currentOutpointHash` survive an invalidation on purpose: they are the audit trail of
    ///      who was named and which outpoint was spent. `active` is the single field that decides
    ///      whether value may be paid, and consumers MUST read it rather than assuming a non-zero
    ///      beneficiary means "pay this address".
    /// @param rootKey Canonical protocol key of the inscription.
    function currentState(bytes32 rootKey) external view returns (PuppetTypes.RootState memory) {
        return _rootState[rootKey];
    }

    /// @inheritdoc IRootOwnershipRegistry
    /// @param rootKey Canonical protocol key of the inscription.
    function currentBeneficiary(bytes32 rootKey)
        external
        view
        returns (address beneficiary, bool active, uint64 epoch)
    {
        PuppetTypes.RootState storage s = _rootState[rootKey];
        return (s.beneficiary, s.active, s.epoch);
    }

    /// @inheritdoc IRootOwnershipRegistry
    /// @param rootKey Canonical protocol key of the inscription.
    function isActive(bytes32 rootKey) external view returns (bool) {
        return _rootState[rootKey].active;
    }

    /// @inheritdoc IRootOwnershipRegistry
    /// @param rootKey Canonical protocol key of the inscription.
    function epochOf(bytes32 rootKey) external view returns (uint64) {
        return _rootState[rootKey].epoch;
    }

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev Non-reverting for unknown roots and unknown epochs so integrators need no `try/catch`;
    ///      an unwritten record is all zeroes, and `beneficiary == address(0)` distinguishes it.
    /// @param rootKey Canonical protocol key of the inscription.
    /// @param epoch Epoch number to look up. Epoch numbering starts at 1.
    function epochInfo(bytes32 rootKey, uint64 epoch) external view returns (PuppetTypes.RootEpochInfo memory) {
        return _rootEpochInfo[rootKey][epoch];
    }

    /// @notice ERC-165 support, extended with this registry's own interface id.
    /// @param interfaceId The interface identifier being queried.
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return interfaceId == type(IRootOwnershipRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                          ACTIVATION FROM A MINT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev CALLER TRUST, STATED PRECISELY. This function does not re-verify a quorum; it binds the
    ///      facts it is handed. That is safe only because `MINT_RECORDER_ROLE` is held by the
    ///      escrow, which consumed the very same attestation through the oracle moments earlier in
    ///      the same transaction. The role is therefore trusted for the *provenance* of these
    ///      arguments and nothing else — every structural rule below still applies to it.
    ///
    ///      IT MAKES NO EXTERNAL CALLS, ON PURPOSE. A mint settlement must not be able to fail
    ///      because of the vault's state, its pause flag or a missing role grant, so this path
    ///      never touches `PayoutVault`. If a Root somehow already holds a pending balance when it
    ///      is first minted, that balance is not lost: the same owner can claim it later through
    ///      `bindRootOwner`, or anyone can forward it with `releasePendingRootCredit`.
    ///
    ///      IT IS NOT PAUSABLE, ON PURPOSE. Pausing this registry must never brick the escrow's
    ///      settlement path; the escrow has its own pause and its own role gate for that.
    /// @param rootKey Canonical protocol key of the inscription.
    /// @param beneficiary EVM address that should receive Root-linked value.
    /// @param outpointHash Bitcoin outpoint currently holding the inscription.
    /// @param ownerScriptHash keccak256 of the owning `scriptPubKey`.
    /// @param ownershipDigest Digest of the attestation the escrow consumed.
    /// @param bip322ProofHash Commitment to the normalized BIP-322 proof bytes.
    /// @param bitcoinBlockHash Bitcoin tip hash the attestors observed.
    /// @param bitcoinHeight Bitcoin tip height the attestors observed.
    /// @return epoch Always 1: this path only ever opens a Root's first epoch.
    function recordMintOwnership(
        bytes32 rootKey,
        address beneficiary,
        bytes32 outpointHash,
        bytes32 ownerScriptHash,
        bytes32 ownershipDigest,
        bytes32 bip322ProofHash,
        bytes32 bitcoinBlockHash,
        uint64 bitcoinHeight
    ) external onlyRole(MINT_RECORDER_ROLE) returns (uint64 epoch) {
        if (rootKey == bytes32(0)) revert ZeroRootKey();
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (outpointHash == bytes32(0)) revert ZeroOutpointHash();
        if (ownerScriptHash == bytes32(0)) revert ZeroScriptHash();
        if (ownershipDigest == bytes32(0)) revert ZeroOwnershipDigest();

        PuppetTypes.RootState storage s = _rootState[rootKey];

        // Two separate guards rather than one `epoch != 0`, so the revert reason distinguishes
        // "someone else currently owns this" from "this Root's history has already begun".
        // Neither is waivable, by any role, ever: this is the "do not silently overwrite a
        // different active owner" rule.
        if (s.active) revert RootAlreadyActive(rootKey, s.epoch);
        if (s.epoch != 0) revert RootEpochAlreadyExists(rootKey, s.epoch);

        epoch = _activate(
            rootKey,
            ActivationFacts({
                beneficiary: beneficiary,
                outpointHash: outpointHash,
                ownerScriptHash: ownerScriptHash,
                ownershipDigest: ownershipDigest,
                bip322ProofHash: bip322ProofHash,
                bitcoinBlockHash: bitcoinBlockHash,
                bitcoinHeight: bitcoinHeight
            })
        );
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONLESS REBINDING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev ORDERING. Cheap local checks run first so a doomed call cannot waste a quorum's work;
    ///      then the attestation is consumed through the oracle; then state is written; then the
    ///      vault is asked to release the Root's pending bucket. The oracle call precedes the state
    ///      writes because it IS the authorization — there is nothing to write until it succeeds —
    ///      and it is an immutable, trusted protocol contract. `nonReentrant` covers the residual
    ///      risk of any external call re-entering this function, so the deviation from textbook
    ///      checks-effects-interactions cannot be exploited.
    ///
    ///      A FAILED RELEASE FAILS THE WHOLE BIND, deliberately. The alternative — swallowing the
    ///      vault error and advancing the epoch anyway — would strand the Root's pending balance
    ///      with no path to release it, because releases are only ever driven from an epoch change.
    ///      An activation is all-or-nothing, including its money routing.
    /// @param attestation The ownership attestation. `purpose` must be `ROOT_BIND` and `payoutMode`
    ///        must be `EVM`; `evmPayout` becomes the new beneficiary.
    /// @param signatures Attestor signatures, forwarded verbatim to the oracle.
    /// @param collectionProof Merkle proof of collection membership, forwarded verbatim.
    /// @return epoch The newly opened epoch number.
    /// @return releasedPending Wei moved out of the Root's pending bucket into the new
    ///         beneficiary's claimable balance. Zero when the bucket was empty.
    function bindRootOwner(
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external nonReentrant whenNotPaused returns (uint64 epoch, uint256 releasedPending) {
        bytes32 rootKey = _validateBind(attestation);

        (bytes32 digest, bytes32 oracleRootKey) = ORACLE.consumeOwnership(attestation, signatures, collectionProof);
        // The oracle derives the rootKey from the same signed fields, so a disagreement means the
        // two contracts do not share a hashing definition. Refuse to record anything in that case.
        if (oracleRootKey != rootKey) revert RootMismatch(rootKey, oracleRootKey);

        epoch = _activate(
            rootKey,
            ActivationFacts({
                beneficiary: attestation.evmPayout,
                outpointHash: attestation.currentOutpointHash,
                ownerScriptHash: attestation.ownerScriptHash,
                ownershipDigest: digest,
                bip322ProofHash: attestation.bip322ProofHash,
                bitcoinBlockHash: attestation.bitcoinBlockHash,
                bitcoinHeight: attestation.bitcoinHeight
            })
        );

        releasedPending = _releasePending(rootKey, attestation.evmPayout);
    }

    /*//////////////////////////////////////////////////////////////
                        PERMISSIONLESS INVALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev THIS IS THE WATCHER'S FUNCTION AND IT IS OPEN TO EVERYONE, which is what keeps the
    ///      stale-watcher window short. It closes the current epoch and nothing else: no vault call,
    ///      no balance change, no beneficiary rewrite. Bob keeps every wei already credited to him;
    ///      only value that arrives AFTER this call is diverted, and it is diverted by `FeeRouter`
    ///      reading `active == false` and crediting `PayoutVault.pendingByRoot` instead.
    ///
    ///      `verifiedBitcoinHeight` is advanced to the spend height because the spend is the most
    ///      recent attested Bitcoin fact about this Root. That keeps the field monotonically
    ///      non-decreasing, which is what makes the "not older than" guard on the next bind mean
    ///      something: nobody can rebind using a proof of control from before the spend.
    /// @param attestation The spend attestation. Its `previousOutpointHash` must equal the recorded
    ///        `currentOutpointHash`, so an attestation about some other outpoint cannot close this
    ///        epoch.
    /// @param signatures Attestor signatures, forwarded verbatim to the oracle.
    /// @param collectionProof Merkle proof of collection membership, forwarded verbatim.
    function invalidateRoot(
        PuppetTypes.RootSpendAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external nonReentrant whenNotPaused {
        bytes32 rootKey = _validateSpend(attestation);

        (, bytes32 oracleRootKey) = ORACLE.consumeRootSpend(attestation, signatures, collectionProof);
        if (oracleRootKey != rootKey) revert RootMismatch(rootKey, oracleRootKey);

        PuppetTypes.RootState storage s = _rootState[rootKey];
        uint64 closingEpoch = s.epoch;
        address previousBeneficiary = s.beneficiary;

        s.active = false;
        s.invalidatingSpendTxid = attestation.spendingTxid;
        s.verifiedBitcoinHeight = attestation.bitcoinHeight;
        s.lastBitcoinBlockHash = attestation.bitcoinBlockHash;

        PuppetTypes.RootEpochInfo storage info = _rootEpochInfo[rootKey][closingEpoch];
        info.deactivatedAtBitcoinHeight = attestation.bitcoinHeight;
        info.deactivatedAtBlockTimestamp = uint64(block.timestamp);

        emit RootEpochInvalidated(
            rootKey, closingEpoch, previousBeneficiary, attestation.spendingTxid, attestation.bitcoinHeight
        );
    }

    /*//////////////////////////////////////////////////////////////
                       PENDING BALANCE FORWARDING
    //////////////////////////////////////////////////////////////*/

    /// @notice Forward a Root's pending vault balance to the beneficiary already recorded for it.
    /// @dev NOT IN THE FROZEN INTERFACE — an addition, and a deliberately powerless one. It cannot
    ///      choose a destination: it pays the address this registry already records, and only while
    ///      that record is active. It exists because a pending balance can otherwise sit until the
    ///      next epoch change, and a balance that is already owed to an identified address should
    ///      not need an ownership event to move.
    ///
    ///      WHY THIS OPENS NO NEW TRUST WINDOW: a pending bucket is only ever filled while a Root
    ///      is inactive, and an activation drains it atomically. So any pending balance on an
    ///      ACTIVE Root accrued after that Root's current epoch opened, and belongs to exactly the
    ///      beneficiary this function pays. It is not pausable, for the same reason a withdrawal is
    ///      not pausable: it moves value the protocol already owes.
    /// @param rootKey Canonical protocol key of the inscription.
    /// @return amount Wei moved into the beneficiary's claimable balance.
    function releasePendingRootCredit(bytes32 rootKey) external nonReentrant returns (uint256 amount) {
        PuppetTypes.RootState storage s = _rootState[rootKey];
        if (!s.active) revert RootNotActive(rootKey);

        address beneficiary = s.beneficiary;
        if (beneficiary == address(0)) revert InvalidBeneficiary();

        if (PAYOUT_VAULT.pendingByRoot(rootKey) == 0) revert NoPendingRootBalance(rootKey);

        amount = _releasePending(rootKey, beneficiary);
    }

    /*//////////////////////////////////////////////////////////////
                             PAUSE CONTROLS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stop consuming new ownership and spend attestations.
    /// @dev Incident response only. It freezes nothing that already exists: every view keeps
    ///      answering, every recorded epoch stays exactly as it was, `PayoutVault` withdrawals are
    ///      unaffected, and `releasePendingRootCredit` keeps working. The cost of pausing is that
    ///      the stale-watcher window cannot be closed while it lasts, so it must be short.
    function pauseActivations() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resume consuming attestations.
    /// @dev `DEFAULT_ADMIN_ROLE`, not `PAUSER_ROLE`: a hot guardian key may stop the protocol but
    ///      must not be able to restart it on its own.
    function unpauseActivations() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Every structural rule a `ROOT_BIND` must satisfy, in one place, before any external
    ///      call happens. Returns the canonical rootKey derived from the signed identity fields.
    function _validateBind(PuppetTypes.OwnershipAttestation calldata a) private view returns (bytes32 rootKey) {
        if (a.purpose != uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND)) revert UnsupportedPurpose(a.purpose);
        if (a.payoutMode != uint8(PuppetTypes.PayoutMode.EVM)) revert UnsupportedPayoutMode(a.payoutMode);
        if (a.evmPayout == address(0)) revert InvalidBeneficiary();
        if (a.rootTxid == bytes32(0)) revert ZeroRootTxid();
        if (a.currentOutpointHash == bytes32(0)) revert ZeroOutpointHash();
        if (a.ownerScriptHash == bytes32(0)) revert ZeroScriptHash();
        if (a.authorizationId == bytes32(0)) revert ZeroAuthorizationId();

        rootKey = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);
        if (a.contextId != bytes32(0) && a.contextId != rootKey) revert InvalidBindContext(a.contextId);

        PuppetTypes.RootState storage s = _rootState[rootKey];
        if (s.epoch != 0) {
            // Never accept a proof of control older than the newest Bitcoin fact already recorded
            // for this Root. Without this, a stale-but-valid attestation collected before a sale
            // could be replayed after it to reinstate the previous owner.
            if (a.bitcoinHeight < s.verifiedBitcoinHeight) {
                revert StaleBitcoinHeight(a.bitcoinHeight, s.verifiedBitcoinHeight);
            }
            // While a Root is active, only a MOVE of the inscription justifies a new epoch. Binding
            // the same outpoint again would let anyone holding a second valid attestation for the
            // current owner churn epochs (and re-point the beneficiary) without anything having
            // changed on Bitcoin. Once the Root is inactive this restriction lifts, because the
            // recorded outpoint is then known to be spent.
            if (s.active && a.currentOutpointHash == s.currentOutpointHash) {
                revert UnchangedOutpoint(a.currentOutpointHash);
            }
        }
    }

    /// @dev Every structural rule a `RootSpendAttestation` must satisfy, before any external call.
    function _validateSpend(PuppetTypes.RootSpendAttestation calldata a) private view returns (bytes32 rootKey) {
        if (a.rootTxid == bytes32(0)) revert ZeroRootTxid();
        if (a.previousOutpointHash == bytes32(0)) revert ZeroOutpointHash();
        if (a.spendingTxid == bytes32(0)) revert ZeroSpendingTxid();
        if (a.authorizationId == bytes32(0)) revert ZeroAuthorizationId();

        rootKey = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);

        PuppetTypes.RootState storage s = _rootState[rootKey];
        if (!s.active) revert RootNotActive(rootKey);
        if (a.previousOutpointHash != s.currentOutpointHash) {
            revert OutpointMismatch(s.currentOutpointHash, a.previousOutpointHash);
        }
        if (a.bitcoinHeight < s.verifiedBitcoinHeight) {
            revert StaleBitcoinHeight(a.bitcoinHeight, s.verifiedBitcoinHeight);
        }
    }

    /// @dev The single writer that opens an epoch. Both activation paths route through it so the
    ///      epoch counter, the history record and the event can never diverge between them.
    ///      Arithmetic is left checked: `epoch` is a security-relevant counter and clarity beats
    ///      the handful of gas an `unchecked` block would save.
    function _activate(bytes32 rootKey, ActivationFacts memory facts) private returns (uint64 epoch) {
        PuppetTypes.RootState storage s = _rootState[rootKey];

        if (s.active) {
            // A newer proof for a different outpoint arrived while the old epoch was still open —
            // the watcher never showed up, or the new owner simply got there first. Close the old
            // epoch's history record so no two records for one Root are ever open at once.
            PuppetTypes.RootEpochInfo storage outgoing = _rootEpochInfo[rootKey][s.epoch];
            outgoing.deactivatedAtBitcoinHeight = facts.bitcoinHeight;
            outgoing.deactivatedAtBlockTimestamp = uint64(block.timestamp);

            emit RootEpochSuperseded(rootKey, s.epoch, s.beneficiary, s.epoch + 1, facts.bitcoinHeight);
        }

        epoch = s.epoch + 1;

        s.epoch = epoch;
        s.active = true;
        s.currentOutpointHash = facts.outpointHash;
        s.ownerScriptHash = facts.ownerScriptHash;
        s.beneficiary = facts.beneficiary;
        s.ownershipDigest = facts.ownershipDigest;
        s.bip322ProofHash = facts.bip322ProofHash;
        s.verifiedBitcoinHeight = facts.bitcoinHeight;
        s.lastBitcoinBlockHash = facts.bitcoinBlockHash;
        // A live epoch must not carry the txid that killed the previous one, or a consumer reading
        // `invalidatingSpendTxid` would believe the current owner has already been dispossessed.
        s.invalidatingSpendTxid = bytes32(0);

        _rootEpochInfo[rootKey][epoch] = PuppetTypes.RootEpochInfo({
            beneficiary: facts.beneficiary,
            outpointHash: facts.outpointHash,
            ownerScriptHash: facts.ownerScriptHash,
            activatedAtBitcoinHeight: facts.bitcoinHeight,
            activatedAtBlockTimestamp: uint64(block.timestamp),
            deactivatedAtBitcoinHeight: 0,
            deactivatedAtBlockTimestamp: 0,
            ownershipDigest: facts.ownershipDigest
        });

        emit RootEpochActivated(
            rootKey,
            epoch,
            facts.beneficiary,
            facts.outpointHash,
            facts.ownerScriptHash,
            facts.bitcoinHeight,
            facts.ownershipDigest
        );
    }

    /// @dev Move the Root's pending bucket to `beneficiary`, if there is one. The bucket is read
    ///      first because `PayoutVault.releaseRootCredit` reverts on an empty bucket, and an empty
    ///      bucket is the normal case for a first activation — it must not fail the bind.
    function _releasePending(bytes32 rootKey, address beneficiary) private returns (uint256 amount) {
        amount = PAYOUT_VAULT.pendingByRoot(rootKey);
        if (amount == 0) return 0;

        uint256 released = PAYOUT_VAULT.releaseRootCredit(rootKey, beneficiary);
        if (released != amount) revert PendingReleaseMismatch(amount, released);

        emit RootPendingReleased(rootKey, beneficiary, released);
    }
}
