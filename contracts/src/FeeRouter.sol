// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IFeeRouter} from "./interfaces/IFeeRouter.sol";
import {IPayoutVault} from "./interfaces/IPayoutVault.sol";
import {IRootOwnershipRegistry} from "./interfaces/IRootOwnershipRegistry.sol";

/// @title FeeRouter
/// @notice The immutable 50 / 25 / 25 HoodPups economic split, and the only contract allowed to
///         turn settlement value into `PayoutVault` liabilities.
/// @dev WHY THIS CONTRACT EXISTS AS A SEPARATE CONTRACT. The split is the single economic promise
///      the protocol makes to Bitcoin Puppet holders. Burying it inside the escrow would mean the
///      escrow's whole (large) attack surface stands between a reader and the arithmetic they came
///      to check. Here the entire economic policy is four constants and nine lines of arithmetic in
///      one file, with no setter, no proxy, no initializer and no `delegatecall`, so verifying
///      "50 / 25 / 25, forever" is a matter of reading a screen of code rather than auditing a
///      state machine.
///
///      THE SPLIT, stated once:
///
///          sellerAmount         = gross * 5000 / 10000     (floor)
///          puppetTreasuryAmount = gross * 2500 / 10000     (floor)
///          protocolAmount       = gross - seller - puppetTreasury
///
///      Both percentage terms floor, so up to 3 wei of rounding dust would otherwise vanish. The
///      protocol share is defined as the REMAINDER rather than as its own percentage, which makes
///      `seller + puppetTreasury + protocol == gross` an identity for every input — including 0, 1,
///      2 and 3 wei, where the percentage terms are zero. The protocol absorbing the dust (rather
///      than the seller or the ecosystem treasury) is the deliberate choice: dust must land
///      somewhere, and it should land on the party that wrote the rounding rule.
///
///      PERCENTAGES CANNOT CHANGE. They are `constant`, so they live in the deployed bytecode and
///      not in storage; there is no function on this contract that writes them and no upgrade path
///      that could replace the code. Only the two treasury DESTINATION addresses are governable,
///      and only by `TREASURY_ADMIN_ROLE`, which is meant to be a `TimelockController`.
///
///      THE ROUTER NEVER HOLDS VALUE. Every route forwards its entire `msg.value` into the vault in
///      the same transaction and then asserts that its own balance is unchanged from what it was
///      before the call. There is no owner withdrawal, no rescue function with a caller-chosen
///      destination, and no path by which a privileged account can redirect value that is already
///      in flight or already credited.
///
///      TRUST BOUNDARY. This contract knows nothing about Bitcoin. It is handed a `rootKey`, a
///      beneficiary and an amount by a holder of `ROUTER_CALLER_ROLE` (the offer escrow and the
///      solver settlement contract), which derive those facts from a 3-of-5 quorum of independent
///      attestors. That is an attested settlement system, not a trustless bridge. The original
///      Bitcoin Puppet never leaves Bitcoin and is never wrapped, escrowed or custodied anywhere in
///      this protocol; this contract moves ETH and nothing else.
contract FeeRouter is IFeeRouter, AccessControl, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE ECONOMICS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFeeRouter
    /// @dev The current Bitcoin controller's share. `constant`, in bytecode, with no setter.
    uint256 public constant SELLER_BPS = 5000;

    /// @inheritdoc IFeeRouter
    /// @dev The Bitcoin Puppets ecosystem treasury's share.
    uint256 public constant PUPPET_TREASURY_BPS = 2500;

    /// @inheritdoc IFeeRouter
    /// @dev The protocol treasury's nominal share. The amount actually credited is computed as the
    ///      remainder, so this constant is the floor of what the protocol receives, never a cap
    ///      applied after the fact — see `quote`.
    uint256 public constant PROTOCOL_BPS = 2500;

    /// @inheritdoc IFeeRouter
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                              ROUTE TAGS
    //////////////////////////////////////////////////////////////*/

    /// @notice `route` value emitted by `MintRouted` for an EVM-payout mint.
    /// @dev Deliberately equal to `uint8(PuppetTypes.OfferKind.PAID_EVM)` so one number means the
    ///      same thing in the escrow's offer records and in this contract's events. A unit test
    ///      pins the equality so a future reordering of that enum cannot silently desynchronise the
    ///      two without failing CI.
    uint8 public constant ROUTE_MINT_EVM = 0;

    /// @notice `route` value emitted by `MintRouted` for a native-BTC mint.
    /// @dev Equal to `uint8(PuppetTypes.OfferKind.PAID_BTC)`. See `ROUTE_MINT_EVM`.
    uint8 public constant ROUTE_MINT_BTC = 1;

    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role permitted to route settlement or activity value through the split.
    /// @dev Held by `HoodPupOfferEscrow` and `BtcSolverSettlement`. Deliberately NOT granted at
    ///      construction: those contracts do not exist yet at this point in the deployment, and
    ///      pre-granting it to the deployer would create exactly the privileged EOA the handover is
    ///      meant to eliminate. The role cannot move value that is already in the vault — it can
    ///      only ask this contract to split ETH the caller itself supplied in the same call.
    bytes32 public constant ROUTER_CALLER_ROLE = keccak256("ROUTER_CALLER_ROLE");

    /// @notice Role permitted to repoint the two treasury destination addresses.
    /// @dev Separated from `DEFAULT_ADMIN_ROLE` for least privilege: role administration and
    ///      treasury custody are different duties and may legitimately sit behind different
    ///      timelocks. Both are granted to `admin` at construction so a single-timelock deployment
    ///      works out of the box.
    ///
    ///      WHY THERE IS NO SECOND, IN-CONTRACT TIMELOCK ON THESE SETTERS. A treasury change only
    ///      affects value routed AFTER it lands. Value already credited sits in `PayoutVault` under
    ///      the OLD address and stays withdrawable by that address alone — this contract cannot
    ///      reach into the vault and move it. The blast radius of a bad update is therefore bounded
    ///      by "future revenue until the update is reverted", which is precisely the class of risk
    ///      an external `TimelockController` plus its public proposal queue is designed to cover.
    ///      Adding a second delay here would duplicate that control without shrinking the radius.
    bytes32 public constant TREASURY_ADMIN_ROLE = keccak256("TREASURY_ADMIN_ROLE");

    /*//////////////////////////////////////////////////////////////
                              EXTRA ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a route is handed the zero Root key.
    /// @dev Every route emits an event indexed on `rootKey`, and the recurring route uses it as the
    ///      vault's pending-bucket key. A zero key would produce an un-attributable payout record
    ///      and, on the recurring path, would be rejected by the vault anyway — failing here gives
    ///      the caller the accurate reason.
    error ZeroRootKey();

    /// @notice Thrown when a route is handed a gross of zero.
    /// @dev A free mint (`SELF_CAST`) must not call the router at all. Accepting a zero route would
    ///      emit a payout event describing a payment that never happened, which is worse than a
    ///      revert: indexers and accounting tools would faithfully record it.
    error ZeroGross();

    /// @notice Thrown when `sweepForcedEth` runs with no force-sent ETH present.
    error NoForcedEth();

    /// @notice Thrown when a treasury setter is asked to write the value already stored.
    /// @dev A governance proposal executed twice would otherwise emit a second `TreasuryUpdated`
    ///      event describing a change that did not occur, muddying the on-chain audit trail of who
    ///      controlled protocol revenue at which block.
    /// @param treasury The unchanged address.
    error TreasuryUnchanged(address treasury);

    /*//////////////////////////////////////////////////////////////
                              EXTRA EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, recording the immutable wiring.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `TREASURY_ADMIN_ROLE`.
    /// @param vault Vault every route credits.
    /// @param registry Registry consulted for recurring-route beneficiaries.
    /// @param puppetTreasury Genesis Bitcoin Puppets ecosystem treasury.
    /// @param protocolTreasury Genesis protocol treasury.
    event RouterInitialized(
        address indexed admin,
        address indexed vault,
        address indexed registry,
        address puppetTreasury,
        address protocolTreasury
    );

    /// @notice Emitted when force-sent ETH is pushed into the vault for the protocol treasury.
    /// @param protocolTreasury Destination, read from storage at execution time.
    /// @param amount Wei swept.
    /// @param caller Whoever called the permissionless sweep.
    event ForcedEthSwept(address indexed protocolTreasury, uint256 amount, address indexed caller);

    /*//////////////////////////////////////////////////////////////
                             IMMUTABLE WIRING
    //////////////////////////////////////////////////////////////*/

    /// @notice Vault that receives every wei this router splits.
    /// @dev `immutable`, so no governance action can repoint the router at a different vault and
    ///      strand or divert settlement funds. Repointing requires a redeployment plus regranting
    ///      `ROUTER_CALLER_ROLE`, which is a visible, reviewable operation.
    IPayoutVault public immutable PAYOUT_VAULT;

    /// @notice Registry consulted to find a Root's currently verified beneficiary.
    /// @dev `immutable` for the same reason as `PAYOUT_VAULT`. Read-only from this contract's point
    ///      of view: the router never writes Bitcoin state, it only asks who is currently attested.
    IRootOwnershipRegistry public immutable ROOT_REGISTRY;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Bitcoin Puppets ecosystem treasury. One of only two mutable words in this contract.
    address private _puppetTreasury;

    /// @dev Protocol treasury. The other one.
    address private _protocolTreasury;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the router and bind it permanently to a vault and a Root registry.
    /// @dev `admin` MUST be a `TimelockController` under multisig control in production. Nothing
    ///      here can enforce that, so the deployment script is responsible for granting to the
    ///      timelock and revoking the deployer in the same batch. `ROUTER_CALLER_ROLE` is left
    ///      unassigned on purpose.
    ///
    ///      Every address argument is rejected when zero. A zero vault would make every route
    ///      revert (funds stay safely in the escrow, but the protocol is bricked); a zero treasury
    ///      would make the vault reject the batch for the same reason. Both are unrecoverable
    ///      without redeployment, which is why they are checked rather than left to fail later.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `TREASURY_ADMIN_ROLE`.
    /// @param payoutVault_ Vault every route credits.
    /// @param rootRegistry_ Registry consulted on the recurring route.
    /// @param puppetTreasury_ Genesis Bitcoin Puppets ecosystem treasury address.
    /// @param protocolTreasury_ Genesis protocol treasury address.
    constructor(
        address admin,
        IPayoutVault payoutVault_,
        IRootOwnershipRegistry rootRegistry_,
        address puppetTreasury_,
        address protocolTreasury_
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (address(payoutVault_) == address(0)) revert ZeroAddress();
        if (address(rootRegistry_) == address(0)) revert ZeroAddress();
        if (puppetTreasury_ == address(0)) revert ZeroAddress();
        if (protocolTreasury_ == address(0)) revert ZeroAddress();

        PAYOUT_VAULT = payoutVault_;
        ROOT_REGISTRY = rootRegistry_;
        _puppetTreasury = puppetTreasury_;
        _protocolTreasury = protocolTreasury_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TREASURY_ADMIN_ROLE, admin);

        emit RouterInitialized(admin, address(payoutVault_), address(rootRegistry_), puppetTreasury_, protocolTreasury_);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFeeRouter
    /// @return Current Bitcoin Puppets ecosystem treasury address.
    function puppetTreasury() external view returns (address) {
        return _puppetTreasury;
    }

    /// @inheritdoc IFeeRouter
    /// @return Current protocol treasury address.
    function protocolTreasury() external view returns (address) {
        return _protocolTreasury;
    }

    /// @inheritdoc IFeeRouter
    /// @dev `public` rather than `external` so the three routes split with the exact same code path
    ///      a caller can quote off chain — there is deliberately no second, internal copy of this
    ///      arithmetic that could drift from the published one.
    ///
    ///      OVERFLOW BOUND, stated honestly: `gross * 5000` reverts with a checked-arithmetic panic
    ///      above `type(uint256).max / 5000`, which is roughly 2.3e73 wei — about 1e47 times every
    ///      wei that will ever exist. It is unreachable by any real value and by `msg.value`, which
    ///      is bounded by the chain's actual supply. The multiply-then-divide form is kept anyway
    ///      because it is the form the SDK, the indexer and the spec all state, and three
    ///      implementations agreeing character for character is worth more than removing a branch
    ///      that cannot be taken.
    /// @param gross Total wei to split.
    /// @return sellerAmount 50% of `gross`, floored.
    /// @return puppetTreasuryAmount 25% of `gross`, floored.
    /// @return protocolAmount Everything left over, so the three always sum to `gross` exactly.
    function quote(uint256 gross)
        public
        pure
        returns (uint256 sellerAmount, uint256 puppetTreasuryAmount, uint256 protocolAmount)
    {
        sellerAmount = (gross * SELLER_BPS) / BPS_DENOMINATOR;
        puppetTreasuryAmount = (gross * PUPPET_TREASURY_BPS) / BPS_DENOMINATOR;
        // The remainder, never an independent percentage. This is what makes conservation exact.
        protocolAmount = gross - sellerAmount - puppetTreasuryAmount;
    }

    /*//////////////////////////////////////////////////////////////
                                 ROUTING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFeeRouter
    /// @dev The seller is credited inside the vault rather than paid directly, because a seller
    ///      whose payout address is a contract that reverts on receive would otherwise be able to
    ///      block their own mint — and therefore every buyer's mint of that Puppet — at zero cost.
    ///      All three shares go in through ONE `creditBatch`, so the vault sees a single atomic
    ///      accounting event per settlement and a partially-applied split is impossible.
    /// @param rootKey Canonical `PuppetHashing.rootKey` of the inscription being minted against.
    /// @param seller Bitcoin controller's Robinhood Chain payout address.
    /// @param gross Total wei escrowed by the buyer; must equal `msg.value`.
    function routeMintEvm(bytes32 rootKey, address seller, uint256 gross)
        external
        payable
        onlyRole(ROUTER_CALLER_ROLE)
        nonReentrant
    {
        if (seller == address(0)) revert ZeroAddress();
        _checkRouteInputs(rootKey, gross);

        uint256 preExistingBalance = address(this).balance - msg.value;
        (uint256 sellerAmount, uint256 puppetAmount, uint256 protocolAmount) = quote(gross);

        // EFFECTS-equivalent: the payout record is emitted before any external call, so an event
        // log can never describe a split that a later revert undid halfway.
        emit MintRouted(rootKey, seller, ROUTE_MINT_EVM, gross, sellerAmount, puppetAmount, protocolAmount);

        _creditSplit(seller, sellerAmount, puppetAmount, protocolAmount, false);
        _assertNothingRetained(preExistingBalance);
    }

    /// @inheritdoc IFeeRouter
    /// @dev IDENTICAL SPLIT, DIFFERENT RECIPIENT FOR THE 50%. The Bitcoin controller has already
    ///      been paid in native BTC by a bonded solver, off this chain. The seller share therefore
    ///      reimburses the solver that fronted that BTC; paying the seller again here would pay for
    ///      the same Puppet twice. Which address counts as "the solver" is decided by
    ///      `BtcSolverSettlement` against an attested payment fact — this contract trusts its
    ///      authorized caller for that and binds exactly the address it is handed.
    /// @param rootKey Canonical `PuppetHashing.rootKey` of the inscription being minted against.
    /// @param solver Address of the bonded solver that already paid the seller in BTC.
    /// @param gross Total wei escrowed by the buyer; must equal `msg.value`.
    function routeMintBtc(bytes32 rootKey, address solver, uint256 gross)
        external
        payable
        onlyRole(ROUTER_CALLER_ROLE)
        nonReentrant
    {
        if (solver == address(0)) revert ZeroAddress();
        _checkRouteInputs(rootKey, gross);

        uint256 preExistingBalance = address(this).balance - msg.value;
        (uint256 solverAmount, uint256 puppetAmount, uint256 protocolAmount) = quote(gross);

        emit MintRouted(rootKey, solver, ROUTE_MINT_BTC, gross, solverAmount, puppetAmount, protocolAmount);

        // The solver may already have paid irreversible BTC. Route through the vault's terminal
        // accounting path so an ordinary credit pause cannot strand that cross-chain obligation.
        _creditSplit(solver, solverAmount, puppetAmount, protocolAmount, true);
        _assertNothingRetained(preExistingBalance);
    }

    /// @inheritdoc IFeeRouter
    /// @dev THE LAG PROBLEM, AND WHY THE PENDING BUCKET EXISTS. The registry records ATTESTED
    ///      Bitcoin ownership, not live Bitcoin ownership. Between the moment a Puppet changes
    ///      hands on Bitcoin and the moment a watcher submits the spend attestation, the registry
    ///      still names the previous owner and is marked inactive as soon as that spend is seen. If
    ///      the Root share were paid to a named address in that window it could reach the wrong
    ///      person irreversibly. Instead it goes to `PayoutVault.creditRoot(rootKey)`, where it is
    ///      already a liability of the vault but belongs to no address yet, and is released to
    ///      whoever next proves Bitcoin control. Nobody loses the money; it simply waits.
    ///
    ///      The two treasuries are paid in both branches. Their entitlement does not depend on who
    ///      controls the inscription, so withholding it would be an unnecessary second failure mode.
    ///
    ///      A registry that reports `active == true` with a zero beneficiary is treated as
    ///      inactive. That combination should be unreachable in the real registry, but the router
    ///      is the contract holding the money at that instant, and routing to the pending bucket is
    ///      recoverable whereas reverting the whole settlement is not.
    /// @param rootKey Canonical `PuppetHashing.rootKey` the recurring value is attached to.
    /// @param gross Total wei to split; must equal `msg.value`.
    function routeRecurring(bytes32 rootKey, uint256 gross) external payable onlyRole(ROUTER_CALLER_ROLE) nonReentrant {
        _checkRouteInputs(rootKey, gross);

        uint256 preExistingBalance = address(this).balance - msg.value;
        (uint256 rootAmount, uint256 puppetAmount, uint256 protocolAmount) = quote(gross);

        (address beneficiary, bool active,) = ROOT_REGISTRY.currentBeneficiary(rootKey);
        bool payBeneficiaryDirectly = active && beneficiary != address(0);

        emit RecurringRouted(
            rootKey,
            payBeneficiaryDirectly ? beneficiary : address(0),
            payBeneficiaryDirectly,
            gross,
            rootAmount,
            puppetAmount,
            protocolAmount
        );

        if (payBeneficiaryDirectly) {
            _creditSplit(beneficiary, rootAmount, puppetAmount, protocolAmount, false);
        } else {
            // `rootAmount` is zero only for a sub-2-wei gross; the vault rejects zero-value credits,
            // so the call is skipped rather than allowed to revert the whole settlement over dust.
            if (rootAmount > 0) {
                PAYOUT_VAULT.creditRoot{value: rootAmount}(rootKey);
            }
            _creditSplit(address(0), 0, puppetAmount, protocolAmount, false);
        }

        _assertNothingRetained(preExistingBalance);
    }

    /*//////////////////////////////////////////////////////////////
                            TREASURY GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Repoint the Bitcoin Puppets ecosystem treasury.
    /// @dev Affects future routes only. Value already credited under the previous address remains
    ///      that address's to withdraw from the vault; this contract has no ability to move it.
    /// @param next New ecosystem treasury address.
    function setPuppetTreasury(address next) external onlyRole(TREASURY_ADMIN_ROLE) {
        address previous = _puppetTreasury;
        if (next == address(0)) revert ZeroAddress();
        if (next == previous) revert TreasuryUnchanged(previous);

        _puppetTreasury = next;

        emit TreasuryUpdated(previous, next, false);
    }

    /// @notice Repoint the protocol treasury.
    /// @dev Same bounded blast radius as `setPuppetTreasury`. This address is also the fixed
    ///      destination of `sweepForcedEth`, which is why that function needs no destination
    ///      argument and therefore cannot be aimed by its caller.
    /// @param next New protocol treasury address.
    function setProtocolTreasury(address next) external onlyRole(TREASURY_ADMIN_ROLE) {
        address previous = _protocolTreasury;
        if (next == address(0)) revert ZeroAddress();
        if (next == previous) revert TreasuryUnchanged(previous);

        _protocolTreasury = next;

        emit TreasuryUpdated(previous, next, true);
    }

    /*//////////////////////////////////////////////////////////////
                               FORCED ETH
    //////////////////////////////////////////////////////////////*/

    /// @notice Push any force-sent ETH into the vault, credited to the protocol treasury.
    /// @dev WHY THIS IS PERMISSIONLESS AND HAS NO DESTINATION ARGUMENT. `receive` and `fallback`
    ///      both revert, but `selfdestruct` beneficiary payments and consensus-layer withdrawal
    ///      credits cannot be refused by any contract. That ETH is not in-flight settlement value —
    ///      routing forwards its whole `msg.value` and asserts a zero delta within the same
    ///      transaction, so between transactions the only ETH here is forced ETH.
    ///
    ///      The destination is read from storage at execution and is the governed protocol
    ///      treasury; the caller chooses nothing and receives nothing. That is what keeps this from
    ///      being the "generic owner withdrawal" the protocol rules forbid: there is no privileged
    ///      account, no discretion over where the money goes, and therefore nothing for a timelock
    ///      to delay. Forced ETH carries no identifiable sender, so returning it is not possible;
    ///      surfacing it through the normal accounting with a public event is the honest handling.
    ///
    ///      It cannot touch in-flight value: `nonReentrant` shares its slot with the three routes,
    ///      so this cannot execute inside a route, and outside a route there is no in-flight value.
    /// @return amount Wei swept into the vault.
    function sweepForcedEth() external nonReentrant returns (uint256 amount) {
        amount = address(this).balance;
        if (amount == 0) revert NoForcedEth();

        address treasury = _protocolTreasury;

        emit ForcedEthSwept(treasury, amount, msg.sender);

        PAYOUT_VAULT.credit{value: amount}(treasury);

        // The router is a conduit; it must be empty again the moment the call returns.
        _assertNothingRetained(0);
    }

    /*//////////////////////////////////////////////////////////////
                               ERC-165
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC-165 support, extended with `IFeeRouter`.
    /// @param interfaceId Interface identifier being queried.
    /// @return True when the interface is supported.
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeeRouter).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Input rules shared by all three routes. `msg.value == gross` is the one that matters:
    ///      the router splits what it was actually paid, and a caller that names a larger `gross`
    ///      than it sends would otherwise get a payout event and a `creditBatch` for money that is
    ///      not there (the batch would revert, but with the vault's error rather than the router's).
    /// @param rootKey Root key supplied by the caller.
    /// @param gross Gross supplied by the caller.
    function _checkRouteInputs(bytes32 rootKey, uint256 gross) private view {
        if (rootKey == bytes32(0)) revert ZeroRootKey();
        if (gross == 0) revert ZeroGross();
        if (msg.value != gross) revert ValueMismatch(gross, msg.value);
    }

    /// @dev Credits up to three beneficiaries in ONE `creditBatch`, skipping zero-valued entries.
    ///
    ///      WHY ZERO ENTRIES ARE SKIPPED RATHER THAN SENT. `PayoutVault.creditBatch` rejects a zero
    ///      amount, correctly: for the vault, a zero entry is always a bug in the caller's
    ///      arithmetic. For this router it is not a bug, it is the arithmetic working — a 1 wei
    ///      gross legitimately produces `(0, 0, 1)`. Filtering here is what lets tiny values route
    ///      successfully instead of reverting on dust, and it is safe because the value forwarded
    ///      is the sum of exactly the entries that were kept.
    ///
    ///      At least one entry always survives for a non-zero gross: the protocol share is at least
    ///      `ceil(gross / 4)`, hence at least 1 wei.
    /// @param primary Seller, solver or Root beneficiary. Ignored when `primaryAmount` is zero.
    /// @param primaryAmount The 50% share.
    /// @param puppetAmount The Puppet ecosystem treasury share.
    /// @param protocolAmount The protocol treasury share.
    function _creditSplit(
        address primary,
        uint256 primaryAmount,
        uint256 puppetAmount,
        uint256 protocolAmount,
        bool terminal
    ) private {
        // Defensive: the callers already reject a zero seller/solver/beneficiary, and the recurring
        // pending branch only ever passes a zero primary with a zero amount. Kept because this is a
        // value-moving path and a silent credit to address(0) would be an unrecoverable burn.
        if (primaryAmount > 0 && primary == address(0)) revert ZeroAddress();

        uint256 count;
        if (primaryAmount > 0) count++;
        if (puppetAmount > 0) count++;
        if (protocolAmount > 0) count++;
        if (count == 0) return;

        address[] memory beneficiaries = new address[](count);
        uint256[] memory amounts = new uint256[](count);

        uint256 i;
        if (primaryAmount > 0) {
            beneficiaries[i] = primary;
            amounts[i] = primaryAmount;
            i++;
        }
        if (puppetAmount > 0) {
            beneficiaries[i] = _puppetTreasury;
            amounts[i] = puppetAmount;
            i++;
        }
        if (protocolAmount > 0) {
            beneficiaries[i] = _protocolTreasury;
            amounts[i] = protocolAmount;
        }

        // The vault independently re-checks that the sum of `amounts` equals the value sent, so the
        // conservation property is enforced on both sides of this call rather than trusted once.
        uint256 total = primaryAmount + puppetAmount + protocolAmount;
        if (terminal) {
            PAYOUT_VAULT.creditTerminalBatch{value: total}(beneficiaries, amounts);
        } else {
            PAYOUT_VAULT.creditBatch{value: total}(beneficiaries, amounts);
        }
    }

    /// @dev Asserts the router forwarded every wei it was paid.
    ///
    ///      The comparison is DIFFERENTIAL — against the balance that existed before the call — not
    ///      against zero. An absolute `balance == 0` check would hand anyone a permanent denial of
    ///      service: one wei force-sent via `selfdestruct` would make every future route revert, and
    ///      because this contract is non-upgradeable and holds no sweep-to-arbitrary-address
    ///      function, the protocol would have to be redeployed. The differential form keeps the
    ///      real guarantee ("nothing that arrived with this call stayed here") while making the
    ///      griefing attempt inert. `test_ForcedEthDoesNotBrickRouting` pins that.
    /// @param preExistingBalance Balance the router held before `msg.value` arrived.
    function _assertNothingRetained(uint256 preExistingBalance) private view {
        uint256 retained = address(this).balance;
        // Reports the full remaining balance rather than the delta: in the unreachable case where
        // this fires, the auditor wants to know how much ETH is sitting in a contract that is
        // supposed to be empty.
        if (retained != preExistingBalance) revert RoutingResidue(retained);
    }

    /*//////////////////////////////////////////////////////////////
                          DIRECT DEPOSIT REJECTION
    //////////////////////////////////////////////////////////////*/

    /// @dev ETH arriving without a route is always a mistake — most often an integrator that meant
    ///      to call `routeMintEvm` and sent a bare transfer instead. Accepting it would leave value
    ///      in a contract that has no owner-withdrawal path, so the sender would be worse off than
    ///      if the transfer had simply failed.
    receive() external payable {
        revert DirectDepositRejected();
    }

    /// @dev Also catches calls to selectors this contract does not implement, which usually means
    ///      an integrator pointed at the wrong ABI or the wrong address.
    fallback() external payable {
        revert DirectDepositRejected();
    }
}
