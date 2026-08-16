// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IBitcoinOwnershipOracle} from "./interfaces/IBitcoinOwnershipOracle.sol";
import {IFeeRouter} from "./interfaces/IFeeRouter.sol";
import {IHoodPupOfferEscrow} from "./interfaces/IHoodPupOfferEscrow.sol";
import {IHoodPups} from "./interfaces/IHoodPups.sol";
import {IPayoutVault} from "./interfaces/IPayoutVault.sol";
import {IPuppetCollectionRegistry} from "./interfaces/IPuppetCollectionRegistry.sol";
import {IRootOwnershipRegistry} from "./interfaces/IRootOwnershipRegistry.sol";
import {PuppetHashing} from "./types/PuppetHashing.sol";
import {PuppetTypes} from "./types/PuppetTypes.sol";

/// @title HoodPupOfferEscrow
/// @notice Holds buyer ETH and runs the whole offer lifecycle: creation, Bitcoin ownership
///         approval, mint, fund routing and refund.
/// @dev TRUST BOUNDARY — READ THIS FIRST. Nothing in this contract verifies Bitcoin consensus.
///      Every Bitcoin fact it acts on is asserted by a 3-of-5 quorum of independent attestor
///      operators and is delivered through `BitcoinOwnershipOracle`. This is an attested
///      settlement system, not a trustless bridge. The original Bitcoin Puppet inscription never
///      leaves Bitcoin: it is never bridged, wrapped, custodied or escrowed, and nothing in this
///      file can move it. A HoodPup is a derived Robinhood Chain asset that references one
///      inscription; holding one confers no rights over the inscription itself.
///
///      WHY A BUYER CANNOT CANCEL AN OPEN OFFER. There is deliberately no `cancelOffer`. A Bitcoin
///      holder answering an offer may be partway through a cold-wallet BIP-322 signing ceremony
///      that takes minutes or hours — hardware in a safe, a second location, a co-signer. If the
///      buyer could withdraw at will, they could bait that signature out of the holder and then
///      pull the escrow the instant before it lands, turning every offer into a free option
///      written by the seller. The buyer's protection is bounded instead of instant: the offer
///      expires (`refundExpired`), or becomes immediately refundable the moment the Root is minted
///      by a competing offer (`refundUnfillable`). Both are permissionless and neither can be
///      blocked by governance.
///
///      THE PAYOUT ADDRESS IS WHATEVER THE BITCOIN HOLDER SIGNED, AND NOTHING ELSE. On the paid
///      EVM path the seller share is routed to `attestation.evmPayout` — a field inside the digest
///      the quorum signed, which itself commits to `offerTermsHash`. There is no stored seller
///      address, no admin override, and no setter. That binding is the entire point of the BIP-322
///      message: "I control this inscription, I accept these exact terms, pay me at this address."
///
///      THE ROOT BENEFICIARY IS ONLY EVER RECORDED FROM AN ATTESTATION THAT CARRIES A SIGNED EVM
///      ADDRESS. `settlePaidEvm` records the Root's first ownership epoch, because a
///      `PAID_EVM_MINT` attestation contains a holder-signed `evmPayout`. `settleSelfCast` and
///      `finalizeBtcSettlement` deliberately do NOT: a `SELF_CAST` attestation carries
///      `PayoutMode.NONE` and a `PAID_BTC_MINT` attestation carries `PayoutMode.BTC`, so in both
///      cases `evmPayout` is structurally zero and there is no EVM address the holder signed.
///      Inventing one — using `recipient`, or the caller, or the buyer — would break the invariant
///      above at exactly the point where it matters most, so those two paths require a separate,
///      permissionless `RootOwnershipRegistry.bindRootOwner` afterwards. Nothing is lost by
///      waiting: recurring Root value accrues into `PayoutVault.pendingByRoot` and is released to
///      whoever next proves Bitcoin control. See `docs/TRUST_ASSUMPTIONS.md`.
///
///      MONEY NEVER MOVES BY PUSH. Buyer refunds and seller payouts are both credited inside
///      `PayoutVault`. A seller (or buyer) whose address is a contract that reverts on receive can
///      therefore never block a settlement, a refund or anybody else's mint.
///
///      PAUSING. `whenNotPaused` guards paths that take on NEW risk. It appears on no refund path
///      and not on BTC finalization: once a solver reservation exists, the protocol must preserve
///      its terminal settlement and expiry routes even during an incident.
///
///      NON-UPGRADEABLE by construction: no proxy, no initializer, no `delegatecall`, no
///      `selfdestruct`, no `tx.origin`, no owner EOA, and no admin path that can seize, redirect or
///      reduce a user's escrow. `DEFAULT_ADMIN_ROLE` is intended for a `TimelockController` under
///      multisig control.
contract HoodPupOfferEscrow is IHoodPupOfferEscrow, AccessControl, Pausable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Narrow role held by `BtcSolverSettlement` and nothing else.
    /// @dev It can move an offer between `BTC_APPROVED` and `BTC_RESERVED`, and it can finalize a
    ///      reserved offer. It CANNOT create offers, settle the EVM or self-cast paths, refund,
    ///      pause, choose a mint recipient, or name a payout address other than the solver it
    ///      passes — and even that address must equal the solver already recorded on the offer.
    ///      Deliberately NOT granted at construction: `BtcSolverSettlement` does not exist yet at
    ///      the escrow's deployment step, and pre-granting it to the deployer would create exactly
    ///      the EOA-holds-privilege state the timelock handover is meant to eliminate.
    bytes32 public constant BTC_SETTLEMENT_ROLE = keccak256("BTC_SETTLEMENT_ROLE");

    /// @notice Role permitted to halt new offers and new settlements.
    /// @dev Asymmetric, matching the rest of the protocol: `PAUSER_ROLE` may pause (the safe
    ///      direction, so it can be a hot guardian key that reacts in seconds) but only
    ///      `DEFAULT_ADMIN_ROLE` may unpause, because resuming settlement re-enables risk.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Longest solver reservation this escrow will ever accept, in seconds.
    /// @dev A reservation freezes a buyer's escrow: while `BTC_RESERVED`, refunds are blocked so
    ///      that a solver who is mid-way through broadcasting a real Bitcoin payment cannot have
    ///      the offer pulled out from under them. That protection has to be bounded, or a buggy or
    ///      hostile `BtcSolverSettlement` could reserve with `reservationExpiry = type(uint64).max`
    ///      and freeze the escrow permanently. The value is shared with `BtcSolverSettlement`;
    ///      one definition
    ///      prevents governance from configuring a duration the escrow can never accept.
    uint64 public constant MAX_RESERVATION_WINDOW = PuppetTypes.MAX_BTC_RESERVATION_DURATION;

    /*//////////////////////////////////////////////////////////////
                          ERRORS BEYOND THE INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a settlement entry point is used on an offer of a different kind.
    /// @dev `settlePaidEvm`, `settleSelfCast` and `approvePaidBtc` each serve exactly one
    ///      `OfferKind`. Several of the field checks would incidentally catch a mismatch, but
    ///      relying on that would make the revert reason depend on which incidental check happened
    ///      to fire first. An explicit error keeps the trace honest.
    /// @param offerId The offer being acted on.
    /// @param actual The offer's `PuppetTypes.OfferKind`.
    /// @param expected The kind the entry point serves.
    error UnexpectedOfferKind(bytes32 offerId, uint8 actual, uint8 expected);

    /// @notice Thrown when the oracle's derived root key disagrees with the offer's stored key.
    /// @dev Unreachable while the oracle derives keys with `PuppetHashing.rootKey`, which is what
    ///      this contract uses at creation. It exists so that a future oracle whose hashing has
    ///      drifted aborts the settlement instead of minting against the wrong inscription.
    /// @param expected The key stored on the offer at creation.
    /// @param provided The key the oracle returned.
    error RootMismatch(bytes32 expected, bytes32 provided);

    /// @notice Thrown when a reservation window is zero-length, in the past, or too long.
    /// @param requested The expiry the solver contract asked for.
    /// @param earliestAllowed Exclusive lower bound: `block.timestamp`.
    /// @param latestAllowed Inclusive upper bound: `now + MAX_RESERVATION_WINDOW`.
    error ReservationWindowInvalid(uint64 requested, uint64 earliestAllowed, uint64 latestAllowed);

    /// @notice Thrown when finalizing a reservation whose window has already closed.
    /// @param offerId The offer being finalized.
    /// @param reservationExpiry The moment the exclusive window ended.
    error ReservationLapsed(bytes32 offerId, uint64 reservationExpiry);

    /// @notice Thrown when an inscription identity carries a zero reveal txid.
    /// @dev The shape of a default-initialised `RootId` reaching offer creation. Rejected because a
    ///      zero identity would still produce a well-formed `rootKey` and could be escrowed
    ///      against forever without ever being settleable.
    error ZeroRootTxid();

    /// @notice Thrown on any plain ETH transfer into this contract.
    /// @dev Escrow arrives only as `msg.value` on a creation function, where it is immediately
    ///      attributed to an offer. Accepting a bare transfer would create ETH that belongs to
    ///      nobody and that no code path can ever pay out.
    error DirectDepositRejected();

    /// @notice Thrown if governance tries to replace or remove the canonical solver coordinator.
    /// @dev Two reservation authorities are unsafe, while removing the only one would destroy the
    ///      permissionless terminal path. The coordinator is therefore bound by its first grant.
    error BtcSettlementCoordinatorImmutable(address active, address requested);

    /*//////////////////////////////////////////////////////////////
                         EVENTS BEYOND THE INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, recording the immutable wiring of this escrow.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param collectionRegistry Immutable manifest membership registry.
    /// @param ownershipOracle Immutable 3-of-5 attestation oracle.
    /// @param hoodPups Immutable HoodPups ERC-721 collection.
    /// @param feeRouter Immutable 50/25/25 router.
    /// @param payoutVault Immutable pull-payment vault.
    /// @param rootOwnershipRegistry Immutable Root ownership epoch registry.
    /// @param minimumOfferDuration Shortest life an offer may be created with.
    /// @param maximumOfferDuration Longest life an offer may be created with.
    event EscrowInitialized(
        address indexed admin,
        address collectionRegistry,
        address ownershipOracle,
        address hoodPups,
        address feeRouter,
        address payoutVault,
        address rootOwnershipRegistry,
        uint64 minimumOfferDuration,
        uint64 maximumOfferDuration
    );

    /// @notice Emitted when a solver's BTC payment discharges an offer.
    /// @dev Carries the payment digest as an opaque reference so an indexer can join this
    ///      settlement to the `BitcoinPaymentAttestation` the oracle consumed. No raw BIP-322 or
    ///      Bitcoin proof bytes are ever emitted by this contract.
    /// @param offerId The offer that settled.
    /// @param solver The bonded solver reimbursed in ETH.
    /// @param paymentDigest Digest of the consumed Bitcoin payment attestation.
    event BtcSettlementFinalized(bytes32 indexed offerId, address indexed solver, bytes32 indexed paymentDigest);

    /*//////////////////////////////////////////////////////////////
                             IMMUTABLE WIRING
    //////////////////////////////////////////////////////////////*/

    /// @dev Every protocol dependency is `immutable`. A swappable oracle pointer would be an admin
    ///      path to redefine what counts as proof of Bitcoin control; a swappable router would be
    ///      an admin path to redirect the 50/25/25 split; a swappable vault would be an admin path
    ///      to redirect refunds. None of those may exist, so none of these have setters.
    IPuppetCollectionRegistry private immutable _COLLECTION_REGISTRY;
    IBitcoinOwnershipOracle private immutable _OWNERSHIP_ORACLE;
    IHoodPups private immutable _HOOD_PUPS;
    IFeeRouter private immutable _FEE_ROUTER;
    IPayoutVault private immutable _PAYOUT_VAULT;
    IRootOwnershipRegistry private immutable _ROOT_OWNERSHIP_REGISTRY;

    uint64 private immutable _MINIMUM_OFFER_DURATION;
    uint64 private immutable _MAXIMUM_OFFER_DURATION;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(bytes32 => PuppetTypes.Offer) private _offers;
    mapping(address => uint256) private _buyerNonce;

    /// @dev Root-wide mutex for the irreversible Bitcoin-payment window. Every mint path checks
    ///      this mapping, reservation acquires it atomically, and only the canonical solver
    ///      coordinator clears it while resolving the matching bond.
    mapping(bytes32 => bytes32) private _activeBtcOfferForRoot;

    /// @dev Bound by the first `BTC_SETTLEMENT_ROLE` grant and immutable thereafter.
    address private _btcSettlementCoordinator;

    /// @dev Sum of `grossWei` over every offer that is currently OPEN, BTC_APPROVED or
    ///      BTC_RESERVED. Incremented once at creation and decremented once when the offer reaches
    ///      a terminal state, so it is exactly the ETH this contract still owes to somebody.
    uint256 private _lockedEscrowWei;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the escrow with its permanent protocol wiring.
    /// @dev `BTC_SETTLEMENT_ROLE` is intentionally left unassigned; see its NatSpec.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`. Must be a
    ///        `TimelockController` under multisig control in production.
    /// @param collectionRegistry_ Immutable manifest membership registry.
    /// @param ownershipOracle_ Immutable 3-of-5 attestation oracle.
    /// @param hoodPups_ Immutable HoodPups ERC-721 collection.
    /// @param feeRouter_ Immutable 50/25/25 router.
    /// @param payoutVault_ Immutable pull-payment vault.
    /// @param rootOwnershipRegistry_ Immutable Root ownership epoch registry.
    /// @param minimumOfferDuration_ Shortest life an offer may be created with, in seconds. Must be
    ///        non-zero: a zero-duration offer would be expired in the block that created it, which
    ///        no Bitcoin holder could ever answer.
    /// @param maximumOfferDuration_ Longest life an offer may be created with, in seconds.
    constructor(
        address admin,
        address collectionRegistry_,
        address ownershipOracle_,
        address hoodPups_,
        address feeRouter_,
        address payoutVault_,
        address rootOwnershipRegistry_,
        uint64 minimumOfferDuration_,
        uint64 maximumOfferDuration_
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (collectionRegistry_ == address(0)) revert ZeroAddress();
        if (ownershipOracle_ == address(0)) revert ZeroAddress();
        if (hoodPups_ == address(0)) revert ZeroAddress();
        if (feeRouter_ == address(0)) revert ZeroAddress();
        if (payoutVault_ == address(0)) revert ZeroAddress();
        if (rootOwnershipRegistry_ == address(0)) revert ZeroAddress();
        if (minimumOfferDuration_ == 0 || minimumOfferDuration_ > maximumOfferDuration_) {
            revert DurationBoundsInvalid(minimumOfferDuration_, maximumOfferDuration_);
        }

        _COLLECTION_REGISTRY = IPuppetCollectionRegistry(collectionRegistry_);
        _OWNERSHIP_ORACLE = IBitcoinOwnershipOracle(ownershipOracle_);
        _HOOD_PUPS = IHoodPups(hoodPups_);
        _FEE_ROUTER = IFeeRouter(feeRouter_);
        _PAYOUT_VAULT = IPayoutVault(payoutVault_);
        _ROOT_OWNERSHIP_REGISTRY = IRootOwnershipRegistry(rootOwnershipRegistry_);
        _MINIMUM_OFFER_DURATION = minimumOfferDuration_;
        _MAXIMUM_OFFER_DURATION = maximumOfferDuration_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        emit EscrowInitialized(
            admin,
            collectionRegistry_,
            ownershipOracle_,
            hoodPups_,
            feeRouter_,
            payoutVault_,
            rootOwnershipRegistry_,
            minimumOfferDuration_,
            maximumOfferDuration_
        );
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice The immutable manifest membership registry this escrow proves inclusion against.
    function collectionRegistry() external view returns (IPuppetCollectionRegistry) {
        return _COLLECTION_REGISTRY;
    }

    /// @notice The immutable oracle that turns a 3-of-5 quorum into a one-time authorization.
    function ownershipOracle() external view returns (IBitcoinOwnershipOracle) {
        return _OWNERSHIP_ORACLE;
    }

    /// @notice The immutable HoodPups collection this escrow mints from.
    function hoodPups() external view returns (IHoodPups) {
        return _HOOD_PUPS;
    }

    /// @notice The immutable router that applies the 50/25/25 split.
    function feeRouter() external view returns (IFeeRouter) {
        return _FEE_ROUTER;
    }

    /// @notice The immutable vault every refund and payout is credited into.
    function payoutVault() external view returns (IPayoutVault) {
        return _PAYOUT_VAULT;
    }

    /// @notice The immutable registry that records Root ownership epochs.
    function rootOwnershipRegistry() external view returns (IRootOwnershipRegistry) {
        return _ROOT_OWNERSHIP_REGISTRY;
    }

    /// @notice Shortest life an offer may be created with, in seconds.
    function minimumOfferDuration() external view returns (uint64) {
        return _MINIMUM_OFFER_DURATION;
    }

    /// @notice Longest life an offer may be created with, in seconds.
    function maximumOfferDuration() external view returns (uint64) {
        return _MAXIMUM_OFFER_DURATION;
    }

    /// @notice ETH this contract still owes: the sum of `grossWei` over all non-terminal offers.
    /// @dev `address(this).balance >= lockedEscrowWei()` is the escrow's solvency invariant. The
    ///      two can differ only by ETH forced in with `selfdestruct` or a block reward, which no
    ///      code path here can create and none can spend.
    function lockedEscrowWei() external view returns (uint256) {
        return _lockedEscrowWei;
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev Non-reverting for an unknown id: the zero struct carries `status == OfferStatus.NONE`,
    ///      which is unambiguous, and integrators should not need a try/catch to probe an id.
    function getOffer(bytes32 offerId) external view returns (PuppetTypes.Offer memory) {
        return _offers[offerId];
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function activeBtcOfferForRoot(bytes32 rootKey) external view returns (bytes32 offerId) {
        return _activeBtcOfferForRoot[rootKey];
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function btcSettlementCoordinator() external view returns (address) {
        return _btcSettlementCoordinator;
    }

    /// @dev The first BTC role grant permanently binds the sole coordinator. All other roles retain
    ///      standard OpenZeppelin AccessControl behavior.
    function grantRole(bytes32 role, address account) public override {
        if (role == BTC_SETTLEMENT_ROLE) {
            address active = _btcSettlementCoordinator;
            if (account == address(0)) revert ZeroAddress();
            if (active != address(0) && active != account) {
                revert BtcSettlementCoordinatorImmutable(active, account);
            }
            _btcSettlementCoordinator = account;
        }
        super.grantRole(role, account);
    }

    /// @dev The canonical coordinator cannot be removed after a solver may have accepted risk.
    function revokeRole(bytes32 role, address account) public override {
        if (role == BTC_SETTLEMENT_ROLE) {
            revert BtcSettlementCoordinatorImmutable(_btcSettlementCoordinator, account);
        }
        super.revokeRole(role, account);
    }

    /// @dev The coordinator cannot renounce itself and strand active reservations.
    function renounceRole(bytes32 role, address callerConfirmation) public override {
        if (role == BTC_SETTLEMENT_ROLE) {
            revert BtcSettlementCoordinatorImmutable(_btcSettlementCoordinator, callerConfirmation);
        }
        super.renounceRole(role, callerConfirmation);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function nextOfferId(address buyer) external view returns (bytes32) {
        return PuppetHashing.offerId(block.chainid, address(this), buyer, _buyerNonce[buyer]);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function buyerNonce(address buyer) external view returns (uint256) {
        return _buyerNonce[buyer];
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev `view` rather than `pure` because the hash binds `block.chainid` and this escrow's own
    ///      address, so one deployment's terms can never be replayed against another. The SDK and
    ///      the five attestor services must reproduce this exactly: they all check that the holder
    ///      signed the SAME terms the escrow stored, and a divergence here silently breaks that.
    /// @param offerId Deterministic offer identifier.
    /// @param kind `PuppetTypes.OfferKind` as uint8.
    /// @param rootKey Canonical protocol key of the inscription.
    /// @param buyer Address that escrowed the ETH.
    /// @param recipient Address that receives the HoodPup.
    /// @param grossWei Total wei escrowed.
    /// @param sellerWei Seller share in wei.
    /// @param sellerSats Exact satoshis the seller must receive on a BTC offer.
    /// @param expiry Unix timestamp after which the offer is refundable.
    function computeTermsHash(
        bytes32 offerId,
        uint8 kind,
        bytes32 rootKey,
        address buyer,
        address recipient,
        uint256 grossWei,
        uint256 sellerWei,
        uint64 sellerSats,
        uint64 expiry
    ) public view returns (bytes32) {
        return PuppetHashing.offerTermsHash(
            block.chainid,
            address(this),
            offerId,
            kind,
            rootKey,
            buyer,
            recipient,
            grossWei,
            sellerWei,
            sellerSats,
            expiry
        );
    }

    /// @notice ERC-165 support, extended with this escrow's own interface id.
    /// @param interfaceId The interface identifier being queried.
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return interfaceId == type(IHoodPupOfferEscrow).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                             OFFER CREATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev Multiple competing offers may exist for one Root at the same time, on purpose: the
    ///      Bitcoin holder should be able to pick the best one. Exactly one can ever settle,
    ///      because the Root mints at most once; every loser becomes immediately refundable
    ///      through `refundUnfillable`.
    /// @param root Canonical inscription identity.
    /// @param recipient Address that will receive the HoodPup.
    /// @param expiry Unix timestamp after which the buyer may reclaim the escrow.
    /// @param collectionProof Merkle proof of manifest membership.
    /// @return offerId The created offer's deterministic identifier.
    function createPaidEvmOffer(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 expiry,
        bytes32[] calldata collectionProof
    ) external payable whenNotPaused nonReentrant returns (bytes32 offerId) {
        if (msg.value == 0) revert PaidOfferRequiresValue();
        return _create(root, recipient, expiry, collectionProof, PuppetTypes.OfferKind.PAID_EVM, 0);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev The buyer fixes BOTH sides of the trade here: `msg.value` in ETH and `sellerSats` in
    ///      satoshis. There is no price oracle anywhere in this flow, so there is no oracle to
    ///      manipulate and no slippage to argue about — a bonded solver either finds the implied
    ///      rate attractive or ignores the offer, and the spread is the market.
    /// @param root Canonical inscription identity.
    /// @param recipient Address that will receive the HoodPup.
    /// @param sellerSats Exact satoshis the Bitcoin holder must be paid.
    /// @param expiry Unix timestamp after which the buyer may reclaim the escrow.
    /// @param collectionProof Merkle proof of manifest membership.
    /// @return offerId The created offer's deterministic identifier.
    function createPaidBtcOffer(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 sellerSats,
        uint64 expiry,
        bytes32[] calldata collectionProof
    ) external payable whenNotPaused nonReentrant returns (bytes32 offerId) {
        if (msg.value == 0) revert PaidOfferRequiresValue();
        if (sellerSats == 0) revert BtcOfferRequiresSats();
        return _create(root, recipient, expiry, collectionProof, PuppetTypes.OfferKind.PAID_BTC, sellerSats);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev Free mint for the Bitcoin controller themselves. The caller must equal the recipient:
    ///      a self-cast escrows nothing, so without that rule anyone could open unlimited free
    ///      offers naming an arbitrary recipient and spam the Root's offer book at no cost.
    ///
    ///      `SelfCastMustBeZeroValue` is declared on the interface but can never be emitted by
    ///      this implementation, because this function is not `payable` — the ABI rejects value
    ///      before any of this contract's code runs, which is a stronger guarantee than a check.
    /// @param root Canonical inscription identity.
    /// @param recipient Address that will receive the HoodPup. Must equal `msg.sender`.
    /// @param expiry Unix timestamp after which the offer may be closed out for clean state.
    /// @param collectionProof Merkle proof of manifest membership.
    /// @return offerId The created offer's deterministic identifier.
    function createSelfCastOffer(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 expiry,
        bytes32[] calldata collectionProof
    ) external whenNotPaused nonReentrant returns (bytes32 offerId) {
        if (msg.sender != recipient) {
            revert SelfCastRecipientMismatch(msg.sender, recipient);
        }
        return _create(root, recipient, expiry, collectionProof, PuppetTypes.OfferKind.SELF_CAST, 0);
    }

    /*//////////////////////////////////////////////////////////////
                             EVM SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev PERMISSIONLESS ON PURPOSE. Anybody may submit a quorum they have collected — a relayer,
    ///      the buyer, the seller's own tooling. Submitting it decides nothing: the recipient, the
    ///      payout address and every amount come from the signed attestation and the stored offer,
    ///      never from the caller.
    ///
    ///      ORDERING, AND WHY IT DEVIATES FROM TEXTBOOK CHECKS-EFFECTS-INTERACTIONS. Local checks
    ///      run first so a doomed call cannot burn a quorum's work. The oracle consumption then
    ///      precedes the state writes because it IS the authorization — there is nothing to record
    ///      until it succeeds — and the oracle is an immutable, trusted protocol contract fixed at
    ///      construction. Only then are the effects written, and only then does the contract talk
    ///      to anyone else.
    ///
    ///      THE MINT IS DELIBERATELY THE LAST EXTERNAL CALL. `mintRooted` uses `_safeMint`, so it
    ///      hands control to `recipient.onERC721Received`, which is the only untrusted code this
    ///      function can reach. By the time it runs, the offer is already SETTLED, the escrow
    ///      accounting is already decremented, the Root epoch is already recorded and the funds
    ///      are already routed — so even without `nonReentrant` there would be no half-finished
    ///      state to observe. The guard is kept anyway, as defence in depth.
    /// @param offerId The offer to settle.
    /// @param attestation The 3-of-5 attested ownership statement authorizing this exact offer.
    /// @param signatures Attestor signatures, forwarded verbatim to the oracle.
    /// @param collectionProof Merkle proof of manifest membership, forwarded verbatim.
    /// @return tokenId The minted HoodPup's token id.
    function settlePaidEvm(
        bytes32 offerId,
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external whenNotPaused nonReentrant returns (uint256 tokenId) {
        PuppetTypes.Offer storage o = _settleableOffer(offerId, PuppetTypes.OfferKind.PAID_EVM);
        _requireRootUnlocked(o.rootKey);
        _requireTermsMatch(offerId, o, attestation, PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT);

        // The seller share follows the address the Bitcoin holder signed, so that address must
        // exist and the BTC-side payout fields must be empty. A `PAID_EVM_MINT` that also carried a
        // BTC script hash would be one signed fact two contracts could read two different ways.
        if (attestation.payoutMode != uint8(PuppetTypes.PayoutMode.EVM)) {
            revert AttestationFieldMismatch("payoutMode");
        }
        if (attestation.evmPayout == address(0)) revert AttestationFieldMismatch("evmPayout");
        if (attestation.btcPayoutScriptHash != bytes32(0)) revert AttestationFieldMismatch("btcPayoutScriptHash");

        bytes32 digest = _consume(o.rootKey, attestation, signatures, collectionProof);

        // EFFECTS.
        o.status = uint8(PuppetTypes.OfferStatus.SETTLED);
        o.ownershipDigest = digest;
        _lockedEscrowWei -= o.grossWei;

        emit OwnershipApproved(offerId, digest, attestation.purpose, attestation.evmPayout);

        // INTERACTIONS, trusted protocol contracts first and the untrusted mint callback last.
        _recordFirstOwnershipEpoch(o.rootKey, digest, attestation);
        _FEE_ROUTER.routeMintEvm{value: o.grossWei}(o.rootKey, attestation.evmPayout, o.grossWei);
        tokenId = _mint(o);

        emit OfferSettled(offerId, o.rootKey, tokenId, o.recipient, attestation.evmPayout, o.grossWei, o.kind);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev No money exists on this path, so there is no `FeeRouter` call and no vault credit.
    ///
    ///      IT DELIBERATELY DOES NOT RECORD A ROOT BENEFICIARY. A `SELF_CAST` attestation carries
    ///      `PayoutMode.NONE` and a structurally zero `evmPayout`: the holder signed no EVM payout
    ///      address, so there is none to record. The alternatives — using `recipient`, or the
    ///      caller — would mean the protocol invented a beneficiary the Bitcoin controller never
    ///      signed, which is precisely the invariant this file exists to protect. The controller
    ///      binds their Root afterwards with a separate, permissionless
    ///      `RootOwnershipRegistry.bindRootOwner` carrying a `ROOT_BIND` attestation, which does
    ///      contain a signed EVM address. Nothing is lost in the meantime: recurring Root value
    ///      accrues into `PayoutVault.pendingByRoot` and is released to whoever next proves control.
    /// @param offerId The offer to settle.
    /// @param attestation The 3-of-5 attested ownership statement authorizing this exact offer.
    /// @param signatures Attestor signatures, forwarded verbatim to the oracle.
    /// @param collectionProof Merkle proof of manifest membership, forwarded verbatim.
    /// @return tokenId The minted HoodPup's token id.
    function settleSelfCast(
        bytes32 offerId,
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external whenNotPaused nonReentrant returns (uint256 tokenId) {
        PuppetTypes.Offer storage o = _settleableOffer(offerId, PuppetTypes.OfferKind.SELF_CAST);
        _requireRootUnlocked(o.rootKey);
        _requireTermsMatch(offerId, o, attestation, PuppetTypes.AuthorizationPurpose.SELF_CAST);

        if (attestation.payoutMode != uint8(PuppetTypes.PayoutMode.NONE)) {
            revert AttestationFieldMismatch("payoutMode");
        }
        if (attestation.evmPayout != address(0)) revert AttestationFieldMismatch("evmPayout");
        if (attestation.btcPayoutScriptHash != bytes32(0)) revert AttestationFieldMismatch("btcPayoutScriptHash");

        bytes32 digest = _consume(o.rootKey, attestation, signatures, collectionProof);

        // EFFECTS. `grossWei` is zero here, so `_lockedEscrowWei` is untouched by construction.
        o.status = uint8(PuppetTypes.OfferStatus.SETTLED);
        o.ownershipDigest = digest;

        emit OwnershipApproved(offerId, digest, attestation.purpose, address(0));

        tokenId = _mint(o);

        emit OfferSettled(offerId, o.rootKey, tokenId, o.recipient, address(0), 0, o.kind);
    }

    /*//////////////////////////////////////////////////////////////
                          BTC OWNERSHIP APPROVAL
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev Proves that the Bitcoin holder accepted these exact terms and named a Bitcoin payout
    ///      script, and nothing more. No HoodPup is minted and no ETH moves: the buyer's escrow is
    ///      still fully refundable at expiry, because at this point nobody has yet paid Bob
    ///      anything on the Bitcoin side.
    ///
    ///      Like `settleSelfCast`, this records no Root beneficiary — a `PAID_BTC_MINT`
    ///      attestation carries `PayoutMode.BTC` and a structurally zero `evmPayout`.
    /// @param offerId The offer to approve.
    /// @param attestation The 3-of-5 attested ownership statement authorizing this exact offer.
    /// @param signatures Attestor signatures, forwarded verbatim to the oracle.
    /// @param collectionProof Merkle proof of manifest membership, forwarded verbatim.
    function approvePaidBtc(
        bytes32 offerId,
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external whenNotPaused nonReentrant {
        PuppetTypes.Offer storage o = _settleableOffer(offerId, PuppetTypes.OfferKind.PAID_BTC);
        _requireTermsMatch(offerId, o, attestation, PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT);

        if (attestation.payoutMode != uint8(PuppetTypes.PayoutMode.BTC)) {
            revert AttestationFieldMismatch("payoutMode");
        }
        if (attestation.btcPayoutScriptHash == bytes32(0)) revert AttestationFieldMismatch("btcPayoutScriptHash");
        if (attestation.evmPayout != address(0)) revert AttestationFieldMismatch("evmPayout");

        bytes32 digest = _consume(o.rootKey, attestation, signatures, collectionProof);

        // EFFECTS. The escrow stays locked: this transition creates an obligation to a solver who
        // has not acted yet, not a payment.
        o.status = uint8(PuppetTypes.OfferStatus.BTC_APPROVED);
        o.ownershipDigest = digest;
        o.btcPayoutScriptHash = attestation.btcPayoutScriptHash;

        emit OwnershipApproved(offerId, digest, attestation.purpose, address(0));
        emit BtcOfferApproved(offerId, digest, attestation.btcPayoutScriptHash, attestation.sellerSats);
    }

    /*//////////////////////////////////////////////////////////////
                        AUTHORIZED BTC SOLVER HOOKS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev Grants one solver the exclusive right to pay Bob in BTC and be reimbursed here. While
    ///      reserved, the buyer's refund paths are closed, which is the whole point: a solver about
    ///      to broadcast an irreversible Bitcoin payment must not have the offer pulled from under
    ///      them mid-flight.
    ///
    ///      The freeze is bounded by the shared `MAX_RESERVATION_WINDOW`, but may extend beyond the
    ///      offer expiry. That grace period is essential: a solver that reserves a still-live
    ///      offer must retain the complete window it accepted to prove an irreversible payment.
    ///      The coordinator's permissionless expiry path releases both this mutex and the bond.
    /// @param offerId The approved offer being reserved.
    /// @param solver The bonded solver claiming the reservation.
    /// @param reservationExpiry Unix timestamp at which the exclusive window closes.
    function markBtcReserved(bytes32 offerId, address solver, uint64 reservationExpiry)
        external
        whenNotPaused
        onlyRole(BTC_SETTLEMENT_ROLE)
    {
        PuppetTypes.Offer storage o = _offerWithStatus(offerId, PuppetTypes.OfferStatus.BTC_APPROVED);
        if (solver == address(0)) revert ZeroAddress();
        if (block.timestamp > o.expiry) revert OfferExpired(offerId, o.expiry);
        if (_HOOD_PUPS.rootMinted(o.rootKey)) revert RootAlreadyMinted(o.rootKey);

        bytes32 activeOfferId = _activeBtcOfferForRoot[o.rootKey];
        if (activeOfferId != bytes32(0)) revert RootReservationActive(o.rootKey, activeOfferId);

        uint64 ceiling = uint64(block.timestamp) + MAX_RESERVATION_WINDOW;
        if (reservationExpiry <= block.timestamp || reservationExpiry > ceiling) {
            revert ReservationWindowInvalid(reservationExpiry, uint64(block.timestamp), ceiling);
        }

        _activeBtcOfferForRoot[o.rootKey] = offerId;
        o.status = uint8(PuppetTypes.OfferStatus.BTC_RESERVED);
        o.reservedSolver = solver;
        o.reservationExpiry = reservationExpiry;

        emit BtcReserved(offerId, solver, reservationExpiry);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev NOT pausable. This only ever moves an offer back towards refundability, so blocking it
    ///      during an incident could only ever hurt the buyer.
    /// @param offerId The reserved offer to release.
    function clearBtcReservation(bytes32 offerId) external onlyRole(BTC_SETTLEMENT_ROLE) {
        PuppetTypes.Offer storage o = _offerWithStatus(offerId, PuppetTypes.OfferStatus.BTC_RESERVED);
        _releaseReservation(offerId, o);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev BOB IS NEVER PAID IN ETH HERE. He was already paid the exact `sellerSats` in native
    ///      Bitcoin by the bonded solver, off this chain, and `BtcSolverSettlement` proved that
    ///      with a consumed `BitcoinPaymentAttestation` before calling. The 50% seller share
    ///      therefore reimburses the SOLVER that fronted it; routing it to a seller address as
    ///      well would pay for the same Puppet twice. The two treasury shares are unaffected.
    ///
    ///      The reservation must still be live. A lapsed window means anybody could already have
    ///      released the offer and refunded the buyer, so honouring it here would let two
    ///      irreconcilable outcomes race. The consequence for solvers is real and is stated in the
    ///      integration notes: do not broadcast a Bitcoin payment you cannot finalize inside your
    ///      own reservation window.
    /// @param offerId The reserved offer to finalize.
    /// @param solver The solver being reimbursed. Must equal the recorded reservation holder.
    /// @param paymentDigest Digest of the Bitcoin payment attestation the caller consumed.
    /// @return tokenId The minted HoodPup's token id.
    function finalizeBtcSettlement(bytes32 offerId, address solver, bytes32 paymentDigest)
        external
        nonReentrant
        onlyRole(BTC_SETTLEMENT_ROLE)
        returns (uint256 tokenId)
    {
        PuppetTypes.Offer storage o = _offerWithStatus(offerId, PuppetTypes.OfferStatus.BTC_RESERVED);
        if (solver != o.reservedSolver) revert NotReservedSolver(solver, o.reservedSolver);
        if (block.timestamp > o.reservationExpiry) revert ReservationLapsed(offerId, o.reservationExpiry);
        if (paymentDigest == bytes32(0)) revert ZeroValue();
        if (_HOOD_PUPS.rootMinted(o.rootKey)) revert RootAlreadyMinted(o.rootKey);
        bytes32 activeOfferId = _activeBtcOfferForRoot[o.rootKey];
        if (activeOfferId != offerId) revert RootReservationActive(o.rootKey, activeOfferId);

        // EFFECTS. `reservedSolver` and `reservationExpiry` are deliberately preserved: SETTLED is
        // terminal, so they cannot be reused, and they are the on-chain record of who was paid.
        delete _activeBtcOfferForRoot[o.rootKey];
        o.status = uint8(PuppetTypes.OfferStatus.SETTLED);
        _lockedEscrowWei -= o.grossWei;

        emit BtcSettlementFinalized(offerId, solver, paymentDigest);

        _FEE_ROUTER.routeMintBtc{value: o.grossWei}(o.rootKey, solver, o.grossWei);
        tokenId = _mintTerminal(o);

        emit OfferSettled(offerId, o.rootKey, tokenId, o.recipient, solver, o.grossWei, o.kind);
    }

    /*//////////////////////////////////////////////////////////////
                                 REFUNDS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev PERMISSIONLESS AND NEVER PAUSABLE. Only the buyer is ever credited, so there is nothing
    ///      for a caller to gain by triggering it — which is exactly why anybody may, including a
    ///      keeper acting for a buyer who has no gas. No role, no pause and no governance action
    ///      can stop, delay or redirect it.
    ///
    ///      `BTC_RESERVED` is rejected here rather than silently allowed: a solver may be
    ///      mid-broadcast. The offer must first return to `BTC_APPROVED` through the canonical,
    ///      permissionless `BtcSolverSettlement.expireReservation` path, which atomically resolves
    ///      the matching bond and releases the Root mutex.
    /// @param offerId The expired offer to refund.
    function refundExpired(bytes32 offerId) external nonReentrant {
        PuppetTypes.Offer storage o = _refundableOffer(offerId);
        if (block.timestamp <= o.expiry) revert OfferNotExpired(offerId, o.expiry);
        _refund(offerId, o, false);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev Competing offers are allowed, so exactly one of them wins the Root and every other one
    ///      becomes permanently unfillable the instant the mint lands. Making those refundable
    ///      immediately, rather than at expiry, is what keeps a competitive offer book cheap for
    ///      buyers.
    ///
    ///      `BTC_RESERVED` is deliberately rejected. Every legitimate mint path is blocked by the
    ///      Root mutex while that status is active, so a minted Root alongside an active
    ///      reservation signals broken role wiring rather than a condition this escrow may repair
    ///      by orphaning the solver's bond.
    /// @param offerId The unfillable offer to refund.
    function refundUnfillable(bytes32 offerId) external nonReentrant {
        PuppetTypes.Offer storage o = _offers[offerId];
        uint8 status = o.status;
        if (status == uint8(PuppetTypes.OfferStatus.NONE)) revert UnknownOffer(offerId);
        if (status != uint8(PuppetTypes.OfferStatus.OPEN) && status != uint8(PuppetTypes.OfferStatus.BTC_APPROVED)) {
            revert InvalidOfferStatus(offerId, status, uint8(PuppetTypes.OfferStatus.OPEN));
        }
        if (!_HOOD_PUPS.rootMinted(o.rootKey)) revert RootNotMinted(o.rootKey);
        _refund(offerId, o, true);
    }

    /*//////////////////////////////////////////////////////////////
                                 PAUSING
    //////////////////////////////////////////////////////////////*/

    /// @notice Halt new offers and new settlements. Refunds are unaffected.
    /// @dev Guardian-facing: fast to reach, and it cannot touch anybody's money.
    function pauseSettlement() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resume offers and settlements.
    /// @dev `DEFAULT_ADMIN_ROLE`, not `PAUSER_ROLE`: re-enabling risk is the direction that should
    ///      require the timelock. A guardian that could unpause could also un-do its own incident
    ///      response under duress.
    function unpauseSettlement() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL — CREATION
    //////////////////////////////////////////////////////////////*/

    /// @dev The terms of a new offer, carried as ONE memory pointer.
    ///      Solidity without via-IR can only reach 16 stack slots, and offer creation legitimately
    ///      handles more distinct values than that. Bundling them keeps the whole creation path
    ///      readable rather than splitting the security-critical checks across artificial helpers.
    struct NewOffer {
        address recipient;
        bytes32 rootTxid;
        uint32 rootIndex;
        uint64 sellerSats;
        uint64 expiry;
        uint8 kind;
    }

    /// @dev Shared body of the three creation entry points.
    function _create(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 expiry,
        bytes32[] calldata collectionProof,
        PuppetTypes.OfferKind kind,
        uint64 sellerSats
    ) private returns (bytes32 offerId) {
        if (recipient == address(0)) revert ZeroAddress();
        if (root.inscriptionTxid == bytes32(0)) revert ZeroRootTxid();
        _requireExpiryInWindow(expiry);

        // Membership is proven against the immutable manifest commitment, not asserted by anyone.
        bytes32 rootKey = _COLLECTION_REGISTRY.requireMember(root, collectionProof);
        if (_HOOD_PUPS.rootMinted(rootKey)) revert RootAlreadyMinted(rootKey);

        offerId = PuppetHashing.offerId(block.chainid, address(this), msg.sender, _buyerNonce[msg.sender]);
        unchecked {
            // One increment per offer; overflowing a uint256 nonce is not a reachable state.
            _buyerNonce[msg.sender] += 1;
        }

        _store(
            offerId,
            rootKey,
            NewOffer({
                recipient: recipient,
                rootTxid: root.inscriptionTxid,
                rootIndex: root.inscriptionIndex,
                sellerSats: sellerSats,
                expiry: expiry,
                kind: uint8(kind)
            })
        );
    }

    /// @dev Assert the requested expiry sits inside the configured window.
    ///      The window is measured from NOW, not from a stored anchor, so it bounds how long the
    ///      buyer's ETH can be locked before the refund path opens.
    function _requireExpiryInWindow(uint64 expiry) private view {
        uint64 minAllowed = uint64(block.timestamp) + _MINIMUM_OFFER_DURATION;
        uint64 maxAllowed = uint64(block.timestamp) + _MAXIMUM_OFFER_DURATION;
        if (expiry < minAllowed || expiry > maxAllowed) revert InvalidExpiry(expiry, minAllowed, maxAllowed);
    }

    /// @dev Snapshot the immutable terms, the exact 50/25/25 split and the terms commitment.
    ///      Everything written here is written once and never mutated again: only `status`,
    ///      `ownershipDigest`, `btcPayoutScriptHash` and the two reservation fields ever change.
    function _store(bytes32 offerId, bytes32 rootKey, NewOffer memory n) private {
        // The split is read from FeeRouter rather than recomputed here, so the 50/25/25 rule has
        // exactly one on-chain definition and the stored amounts can never drift from the amounts
        // that will actually be routed at settlement.
        (uint256 sellerWei, uint256 treasuryWei, uint256 protocolWei) = _FEE_ROUTER.quote(msg.value);

        bytes32 termsHash = computeTermsHash(
            offerId, n.kind, rootKey, msg.sender, n.recipient, msg.value, sellerWei, n.sellerSats, n.expiry
        );

        PuppetTypes.Offer storage o = _offers[offerId];
        o.buyer = msg.sender;
        o.recipient = n.recipient;
        o.rootKey = rootKey;
        o.rootTxid = n.rootTxid;
        o.rootIndex = n.rootIndex;
        o.grossWei = msg.value;
        o.sellerWei = sellerWei;
        o.treasuryWei = treasuryWei;
        o.protocolWei = protocolWei;
        o.sellerSats = n.sellerSats;
        o.createdAt = uint64(block.timestamp);
        o.expiry = n.expiry;
        o.kind = n.kind;
        o.status = uint8(PuppetTypes.OfferStatus.OPEN);
        o.termsHash = termsHash;

        _lockedEscrowWei += msg.value;

        emit OfferCreated(
            offerId, rootKey, msg.sender, n.recipient, n.kind, msg.value, sellerWei, n.sellerSats, n.expiry, termsHash
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL — LOOKUP AND GUARDS
    //////////////////////////////////////////////////////////////*/

    /// @dev Load an offer and assert its exact status.
    function _offerWithStatus(bytes32 offerId, PuppetTypes.OfferStatus expected)
        private
        view
        returns (PuppetTypes.Offer storage o)
    {
        o = _offers[offerId];
        uint8 status = o.status;
        if (status == uint8(PuppetTypes.OfferStatus.NONE)) revert UnknownOffer(offerId);
        if (status != uint8(expected)) revert InvalidOfferStatus(offerId, status, uint8(expected));
    }

    /// @dev Load an OPEN offer of `kind` that is unexpired and whose Root is still unminted.
    ///      Every attestation-consuming entry point starts here, so the four preconditions that
    ///      make an attestation worth verifying at all are checked in exactly one place.
    function _settleableOffer(bytes32 offerId, PuppetTypes.OfferKind kind)
        private
        view
        returns (PuppetTypes.Offer storage o)
    {
        o = _offerWithStatus(offerId, PuppetTypes.OfferStatus.OPEN);
        if (o.kind != uint8(kind)) revert UnexpectedOfferKind(offerId, o.kind, uint8(kind));
        // Inclusive: an offer is live through the whole second named as its expiry, and refundable
        // only strictly after it. The two conditions therefore partition time with no overlap and
        // no gap, so an offer can never be simultaneously settleable and refundable.
        if (block.timestamp > o.expiry) revert OfferExpired(offerId, o.expiry);
        if (_HOOD_PUPS.rootMinted(o.rootKey)) revert RootAlreadyMinted(o.rootKey);
    }

    /// @dev Load an offer that a refund path may act on. `BTC_RESERVED` is excluded on purpose.
    function _refundableOffer(bytes32 offerId) private view returns (PuppetTypes.Offer storage o) {
        o = _offers[offerId];
        uint8 status = o.status;
        if (status == uint8(PuppetTypes.OfferStatus.NONE)) revert UnknownOffer(offerId);
        if (status != uint8(PuppetTypes.OfferStatus.OPEN) && status != uint8(PuppetTypes.OfferStatus.BTC_APPROVED)) {
            revert InvalidOfferStatus(offerId, status, uint8(PuppetTypes.OfferStatus.OPEN));
        }
    }

    /// @dev Reject every mint path while a solver owns the Root-wide BTC reservation mutex.
    function _requireRootUnlocked(bytes32 rootKey) private view {
        bytes32 activeOfferId = _activeBtcOfferForRoot[rootKey];
        if (activeOfferId != bytes32(0)) revert RootReservationActive(rootKey, activeOfferId);
    }

    /// @dev Assert that every term the Bitcoin holder signed equals the term this escrow stored.
    ///      Each field gets its own named error so a failed settlement tells the relayer exactly
    ///      which value diverged, rather than a single opaque "mismatch".
    ///
    ///      `offerTermsHash` alone would cover most of these, since it commits to the offer id,
    ///      kind, root key, buyer, recipient, both amounts, the sats and the expiry. The individual
    ///      checks are kept anyway: they are what makes a divergence diagnosable, and they mean a
    ///      future change to `PuppetHashing.offerTermsHash` that dropped a field would be caught
    ///      here instead of silently widening what a signature authorizes.
    function _requireTermsMatch(
        bytes32 offerId,
        PuppetTypes.Offer storage o,
        PuppetTypes.OwnershipAttestation calldata a,
        PuppetTypes.AuthorizationPurpose purpose
    ) private view {
        if (a.purpose != uint8(purpose)) {
            revert UnexpectedPurpose(a.purpose, uint8(purpose));
        }
        if (a.contextId != offerId) revert AttestationFieldMismatch("contextId");
        if (a.offerTermsHash != o.termsHash) revert AttestationFieldMismatch("offerTermsHash");
        if (a.rootTxid != o.rootTxid) revert AttestationFieldMismatch("rootTxid");
        if (a.rootIndex != o.rootIndex) revert AttestationFieldMismatch("rootIndex");
        if (a.buyer != o.buyer) revert AttestationFieldMismatch("buyer");
        if (a.recipient != o.recipient) revert AttestationFieldMismatch("recipient");
        if (a.grossWei != o.grossWei) revert AttestationFieldMismatch("grossWei");
        if (a.sellerWei != o.sellerWei) revert AttestationFieldMismatch("sellerWei");
        if (a.sellerSats != o.sellerSats) revert AttestationFieldMismatch("sellerSats");
        // The two Bitcoin facts that `RootOwnershipRegistry` will be handed. A zero here would be
        // recorded as a real outpoint and would make a later spend attestation unmatchable.
        if (a.currentOutpointHash == bytes32(0)) revert AttestationFieldMismatch("currentOutpointHash");
        if (a.ownerScriptHash == bytes32(0)) revert AttestationFieldMismatch("ownerScriptHash");
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL — EFFECTS AND CALLS
    //////////////////////////////////////////////////////////////*/

    /// @dev Consume the attestation through the oracle and cross-check the identity it derived.
    function _consume(
        bytes32 expectedRootKey,
        PuppetTypes.OwnershipAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) private returns (bytes32 digest) {
        bytes32 derivedRootKey;
        (digest, derivedRootKey) = _OWNERSHIP_ORACLE.consumeOwnership(a, signatures, collectionProof);
        if (derivedRootKey != expectedRootKey) revert RootMismatch(expectedRootKey, derivedRootKey);
    }

    /// @dev Open the Root's first ownership epoch from the facts the quorum just signed.
    ///      Extracted into its own function purely to keep `settlePaidEvm` under the EVM's 16-slot
    ///      stack limit without enabling via-IR; it has exactly one call site.
    function _recordFirstOwnershipEpoch(bytes32 rootKey, bytes32 digest, PuppetTypes.OwnershipAttestation calldata a)
        private
    {
        _ROOT_OWNERSHIP_REGISTRY.recordMintOwnership(
            rootKey,
            a.evmPayout,
            a.currentOutpointHash,
            a.ownerScriptHash,
            digest,
            a.bip322ProofHash,
            a.bitcoinBlockHash,
            a.bitcoinHeight
        );
    }

    /// @dev Mint the single HoodPup for an offer's Root. Always the last external call on a
    ///      settlement path, because `_safeMint` hands control to the recipient.
    function _mint(PuppetTypes.Offer storage o) private returns (uint256 tokenId) {
        return _HOOD_PUPS.mintRooted(
            o.recipient, PuppetTypes.RootId({inscriptionTxid: o.rootTxid, inscriptionIndex: o.rootIndex})
        );
    }

    /// @dev BTC-only terminal mint. Ordinary EVM and self-cast paths never reach this bypass.
    function _mintTerminal(PuppetTypes.Offer storage o) private returns (uint256 tokenId) {
        return _HOOD_PUPS.mintRootedTerminal(
            o.recipient, PuppetTypes.RootId({inscriptionTxid: o.rootTxid, inscriptionIndex: o.rootIndex})
        );
    }

    /// @dev Return a reserved offer to `BTC_APPROVED` and clear the reservation fields.
    function _releaseReservation(bytes32 offerId, PuppetTypes.Offer storage o) private {
        address solver = o.reservedSolver;
        bytes32 activeOfferId = _activeBtcOfferForRoot[o.rootKey];
        if (activeOfferId != offerId) revert RootReservationActive(o.rootKey, activeOfferId);

        delete _activeBtcOfferForRoot[o.rootKey];
        o.status = uint8(PuppetTypes.OfferStatus.BTC_APPROVED);
        o.reservedSolver = address(0);
        o.reservationExpiry = 0;

        emit BtcReservationCleared(offerId, solver);
    }

    /// @dev Credit the buyer's escrow back inside `PayoutVault` and close the offer.
    ///      Checks-effects-interactions: the status is terminal and the escrow accounting is
    ///      decremented before the vault is touched, so a re-entrant refund finds nothing to refund.
    ///
    ///      A self-cast escrows nothing, so there is no credit to make. It still moves to REFUNDED
    ///      so that a Bitcoin holder who opened one and never signed does not leave a permanently
    ///      OPEN row in the offer book.
    function _refund(bytes32 offerId, PuppetTypes.Offer storage o, bool unfillable) private {
        uint256 amount = o.grossWei;
        address buyer = o.buyer;

        o.status = uint8(PuppetTypes.OfferStatus.REFUNDED);
        if (amount != 0) {
            _lockedEscrowWei -= amount;
        }

        emit OfferRefunded(offerId, buyer, amount, unfillable);

        if (amount != 0) {
            // Pull payment, never a push: a buyer whose address reverts on receive must not be able
            // to make their own refund — and therefore this offer — permanently unclosable.
            _PAYOUT_VAULT.creditRefund{value: amount}(buyer);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            NO STRAY ETH IN
    //////////////////////////////////////////////////////////////*/

    /// @dev ETH may only enter as `msg.value` on a creation function, where it is immediately
    ///      attributed to exactly one offer. There is no sweep for force-sent ETH, and that is
    ///      deliberate: a sweep needs a destination, a destination needs an authority to choose it,
    ///      and an authority that can move ETH out of an escrow is precisely the admin path this
    ///      protocol forbids. Dust forced in with `selfdestruct` is stranded and harmless — it is
    ///      never counted as anyone's escrow and can never be paid out to anyone.
    receive() external payable {
        revert DirectDepositRejected();
    }

    fallback() external payable {
        revert DirectDepositRejected();
    }
}
