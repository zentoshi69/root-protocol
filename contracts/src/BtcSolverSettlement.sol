// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IBitcoinOwnershipOracle} from "./interfaces/IBitcoinOwnershipOracle.sol";
import {IBtcSolverSettlement} from "./interfaces/IBtcSolverSettlement.sol";
import {IHoodPupOfferEscrow} from "./interfaces/IHoodPupOfferEscrow.sol";
import {IPayoutVault} from "./interfaces/IPayoutVault.sol";
import {PuppetTypes} from "./types/PuppetTypes.sol";

/// @title BtcSolverSettlement
/// @notice Bonded solvers pay a Bitcoin seller in exact native BTC and are reimbursed in ETH out of
///         the buyer's escrow.
/// @dev ────────────────────────────────────────────────────────────────────────────────────────
///      TRUST BOUNDARY — READ THIS FIRST.
///      Nothing here verifies Bitcoin consensus. This contract cannot see the Bitcoin chain, cannot
///      parse a transaction and cannot count confirmations. Every Bitcoin fact it acts on is
///      ASSERTED by a 3-of-5 quorum of independent attestor operators through
///      `BitcoinOwnershipOracle`. This is an attested settlement system, not a trustless bridge.
///      The original Bitcoin Puppet inscription never moves, is never wrapped and is never held in
///      custody or escrow by anything in this repository.
///      ────────────────────────────────────────────────────────────────────────────────────────
///
///      NO PRICE ORACLE. EVER.
///      `sellerSats` (what the Bitcoin holder must receive in BTC) and `sellerWei` (what the solver
///      is reimbursed in ETH) were BOTH fixed when the buyer created the offer, and the Bitcoin
///      holder signed both inside the BIP-322 authorization that produced the ownership
///      attestation. This contract therefore never needs to know a BTC/ETH exchange rate, and it
///      must never be given one. The solver's spread — the difference between the sats it pays and
///      the wei it collects — IS the market mechanism, priced by competing solvers at the moment
///      they choose to bond. Introducing a price feed here would add oracle manipulation,
///      staleness disputes and slippage arguments to a settlement path that currently has none of
///      them, and would buy nothing: the two legs are already fixed numbers signed by the two
///      parties who care about them.
///
///      THE SOLVER STATE MACHINE (one instance per `offerId`):
///
///          NONE ──reserve()──▶ ACTIVE ──settle()───────────▶ SETTLED   (terminal)
///                                │
///                                └──expireReservation()───▶ EXPIRED
///                                                              │
///                                                              └──reserve()──▶ ACTIVE  (re-bond)
///
///      SETTLED is terminal and unreachable from anywhere else. EXPIRED is re-enterable, which is
///      what lets a second solver rescue an offer whose first solver went dark.
///
///      THE BOND ACCOUNTING EQUATION, enforced on every state transition by
///      `_assertBondBooksBalance` and asserted continuously by the stateful campaign:
///
///          totalBondsPosted == totalActiveBondWei + totalBondsReturned + totalBondsSlashed
///          address(this).balance >= totalActiveBondWei
///
///      Every wei a solver posts is at all times in exactly ONE of three places: held here as the
///      liability of an ACTIVE reservation, already credited back to the solver in `PayoutVault`
///      (SETTLED), or already credited to the buyer and the protocol in `PayoutVault` (EXPIRED).
///      Bond wei is never burned, never retained beyond an active reservation, and never routed
///      anywhere an admin can choose per reservation.
///
///      NON-UPGRADEABLE. No proxy, no initializer, no delegatecall, no selfdestruct, no
///      `tx.origin`, no owner EOA, and no admin path that can seize a bond or reduce a credited
///      balance. `DEFAULT_ADMIN_ROLE` is meant for a multisig behind a `TimelockController`.
contract BtcSolverSettlement is IBtcSolverSettlement, AccessControl, Pausable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice May change the four economic parameters. Held by the timelock.
    /// @dev Deliberately separate from `DEFAULT_ADMIN_ROLE` (least privilege, matching the
    ///      precedent set by `BitcoinAttestorRegistry` and `FeeRouter`): parameter tuning and role
    ///      administration are different duties and can be delegated to different timelocks. Both
    ///      are granted to `admin` at construction so a single-timelock deployment works as is.
    ///      Neither role can touch a bond: see `_assertBondBooksBalance` and the absence of any
    ///      per-reservation admin function anywhere in this file.
    bytes32 public constant CONFIG_ADMIN_ROLE = keccak256("CONFIG_ADMIN_ROLE");

    /// @notice May pause NEW reservations. Nothing else.
    /// @dev Asymmetric with unpausing on purpose: pausing is the safe direction and may live on a
    ///      hot monitoring key that reacts in seconds, while `unpause` requires
    ///      `DEFAULT_ADMIN_ROLE` so restarting risk-taking is a governed act.
    ///      `docs/PAUSE_AND_RECOVERY.md` states that asymmetry as protocol policy.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Basis-point denominator for the slash split.
    uint16 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Shortest reservation window governance may configure.
    /// @dev A Bitcoin payment needs to be broadcast, mined and then observed by five independent
    ///      attestors under their confirmation policy. A window shorter than this would guarantee
    ///      that honest solvers are slashed for the chain's latency rather than for misbehaviour,
    ///      which would turn the bond from a liveness incentive into a tax.
    uint64 public constant MIN_RESERVATION_DURATION = 1 hours;

    /// @notice Longest reservation window governance may configure.
    /// @dev This is the bound on how long a buyer's escrow can stay locked past the offer's own
    ///      expiry (see the settlement grace window note on `settle`). It is a hard ceiling in
    ///      bytecode rather than a policy note precisely because the party it protects — the buyer
    ///      — is not the party that sets it.
    uint64 public constant MAX_RESERVATION_DURATION = 30 days;

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLE WIRING
    //////////////////////////////////////////////////////////////*/

    /// @notice The escrow that owns the offer lifecycle. Fixed at construction.
    /// @dev Immutable rather than settable: a repointable escrow would let an admin substitute a
    ///      contract that reports any offer terms it likes, which is an admin path to redirect a
    ///      solver's reimbursement. Repointing requires a redeploy and a fresh role grant.
    IHoodPupOfferEscrow public immutable ESCROW;

    /// @notice The 3-of-5 attestation oracle. Fixed at construction.
    IBitcoinOwnershipOracle public immutable ORACLE;

    /// @notice Pull-payment vault every wei of bond flows out through. Fixed at construction.
    IPayoutVault public immutable PAYOUT_VAULT;

    /*//////////////////////////////////////////////////////////////
                            ADDITIVE ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Raised when ETH is sent to this contract outside `reserve`.
    /// @dev Bond wei must always be attributable to exactly one reservation. An anonymous deposit
    ///      would be unattributable and therefore unrecoverable by its sender.
    error DirectDepositRejected();

    /// @notice Raised when a solver tries to bond an offer that has already expired.
    /// @dev Same name and argument shape as `IHoodPupOfferEscrow.OfferExpired`, so the two share a
    ///      selector and a decoder written against either ABI reads this correctly.
    error OfferExpired(bytes32 offerId, uint64 expiry);

    /// @notice Raised when a BTC offer is missing a field settlement depends on.
    error IncompleteBtcOffer(bytes32 offerId);

    /// @notice Raised when a governance write would not change anything.
    /// @dev House rule across this protocol: a timelock proposal executed twice must not emit a
    ///      second event describing a change that did not occur.
    error ConfigUnchanged();

    /// @notice Raised when `sweepForcedEth` is called with nothing to sweep.
    error NoForcedEth();

    /// @notice Raised if the bond books ever stop balancing. Should be unreachable.
    error BondAccountingBroken(uint256 posted, uint256 active, uint256 returned, uint256 slashed);

    /*//////////////////////////////////////////////////////////////
                            ADDITIVE EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, with the full genesis configuration.
    event SettlementDeployed(
        address indexed admin,
        address escrow,
        address oracle,
        address payoutVault,
        uint256 minimumBondWei,
        uint64 reservationDuration,
        uint16 buyerSlashBps,
        address protocolSlashRecipient
    );

    /// @notice Emitted when the minimum bond changes. Never affects an active reservation.
    event MinimumBondUpdated(uint256 previousWei, uint256 newWei);

    /// @notice Emitted when the reservation window changes. Never affects an active reservation.
    event ReservationDurationUpdated(uint64 previousDuration, uint64 newDuration);

    /// @notice Emitted when the buyer slash share changes. Never affects an active reservation.
    event BuyerSlashBpsUpdated(uint16 previousBps, uint16 newBps);

    /// @notice Emitted when the protocol slash destination changes.
    event ProtocolSlashRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);

    /// @notice Emitted when force-sent ETH is credited to the protocol slash recipient.
    event ForcedEthSwept(address indexed recipient, uint256 amount, address indexed caller);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Governed economic parameters. Every one of these is SNAPSHOTTED into a `Reservation`
    ///      at `reserve` time, so a change here can only ever affect reservations made after it
    ///      lands. The single exception is `_protocolSlashRecipient`; see `expireReservation`.
    uint256 private _minimumBondWei;

    // These three pack into one slot: 64 + 16 + 160 = 240 bits.
    uint64 private _reservationDuration;
    uint16 private _buyerSlashBps;
    address private _protocolSlashRecipient;

    mapping(bytes32 offerId => Reservation) private _reservations;

    /// @dev Roots this contract has itself settled, keyed to the offer that did it. Used as a
    ///      cheap pre-bond guard; see the honesty note on `settledOfferForRoot`.
    mapping(bytes32 rootKey => bytes32 offerId) private _settledOfferForRoot;

    /// @dev The three ledgers behind the bond accounting equation. Cumulative counters never
    ///      decrease, which makes an off-chain reconciliation a subtraction rather than a replay.
    uint256 private _totalActiveBondWei;
    uint256 private _totalBondsPosted;
    uint256 private _totalBondsReturned;
    uint256 private _totalBondsSlashed;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the bonded-solver settlement contract.
    /// @dev Argument list matches `docs/DEPLOYMENT.md` step 9 exactly. `HoodPups` is deliberately
    ///      NOT a constituent: this contract never mints, it asks the escrow to. That keeps
    ///      `MINTER_ROLE` in exactly one place.
    ///
    ///      No role beyond `DEFAULT_ADMIN_ROLE`, `CONFIG_ADMIN_ROLE` and `PAUSER_ROLE` exists, and
    ///      all three go to `admin`. Solvers are not a role: anyone who can post a bond can
    ///      reserve, and no admin may nominate one. That is the whole point of a bond.
    /// @param admin Timelocked address granted admin, config and pauser roles.
    /// @param escrow The `HoodPupOfferEscrow` this contract settles against.
    /// @param oracle The `BitcoinOwnershipOracle` that consumes payment attestations.
    /// @param payoutVault The `PayoutVault` every bond flows out through.
    /// @param minimumBondWei_ Minimum bond a solver must post. Must be non-zero.
    /// @param reservationDuration_ Exclusive window a solver gets to prove payment.
    /// @param buyerSlashBps_ Share of a slashed bond that compensates the buyer, in bps.
    /// @param protocolSlashRecipient_ Destination for the non-buyer share of a slashed bond.
    constructor(
        address admin,
        IHoodPupOfferEscrow escrow,
        IBitcoinOwnershipOracle oracle,
        IPayoutVault payoutVault,
        uint256 minimumBondWei_,
        uint64 reservationDuration_,
        uint16 buyerSlashBps_,
        address protocolSlashRecipient_
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (address(escrow) == address(0)) revert ZeroAddress();
        if (address(oracle) == address(0)) revert ZeroAddress();
        if (address(payoutVault) == address(0)) revert ZeroAddress();
        if (protocolSlashRecipient_ == address(0)) revert ZeroAddress();

        // A zero minimum bond would make reservations free, and a free reservation is a free
        // denial-of-service on every BTC offer: grab them all, never pay, lose nothing.
        if (minimumBondWei_ == 0) revert InvalidConfiguration();
        if (reservationDuration_ < MIN_RESERVATION_DURATION || reservationDuration_ > MAX_RESERVATION_DURATION) {
            revert InvalidConfiguration();
        }
        if (buyerSlashBps_ > BPS_DENOMINATOR) revert InvalidConfiguration();

        ESCROW = escrow;
        ORACLE = oracle;
        PAYOUT_VAULT = payoutVault;

        _minimumBondWei = minimumBondWei_;
        _reservationDuration = reservationDuration_;
        _buyerSlashBps = buyerSlashBps_;
        _protocolSlashRecipient = protocolSlashRecipient_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIG_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        emit SettlementDeployed(
            admin,
            address(escrow),
            address(oracle),
            address(payoutVault),
            minimumBondWei_,
            reservationDuration_,
            buyerSlashBps_,
            protocolSlashRecipient_
        );
    }

    /*//////////////////////////////////////////////////////////////
                                RESERVE
    //////////////////////////////////////////////////////////////*/

    /// @notice Post a bond and claim the exclusive right to pay this offer's seller in BTC.
    /// @dev The caller IS the solver. There is no argument for it and no admin function that can
    ///      nominate one, because a solver that somebody else chose is not bonded against its own
    ///      failure — it is bonded against whoever chose it.
    ///
    ///      EVERY ECONOMIC TERM IS SNAPSHOTTED HERE. `bondWei`, `reservationExpiry` and
    ///      `buyerSlashBpsSnapshot` are written into the `Reservation` and are the only values the
    ///      settle and expiry paths ever read. A timelocked change to `minimumBondWei`,
    ///      `reservationDuration` or `buyerSlashBps` therefore cannot retroactively shorten a live
    ///      solver's window or raise the penalty it already accepted. Governance can change the
    ///      deal on offer; it cannot change a deal already struck.
    ///
    ///      OVERPAYMENT IS KEPT, NOT REFUNDED. A solver may bond more than the minimum, and the
    ///      whole `msg.value` becomes the bond. Refunding the excess would mean a value-moving
    ///      external call in the middle of a reservation; keeping it is simpler, is fully
    ///      conserved by the same three ledgers, and is returned in full on settlement.
    /// @param offerId The escrow offer to reserve.
    function reserve(bytes32 offerId) external payable override nonReentrant whenNotPaused {
        uint256 required = _minimumBondWei;
        if (msg.value < required) revert InsufficientBond(msg.value, required);

        Reservation storage r = _reservations[offerId];
        uint8 status = r.status;
        if (status == uint8(ReservationStatus.ACTIVE)) revert AlreadyReserved(offerId, r.solver);

        PuppetTypes.Offer memory offer = ESCROW.getOffer(offerId);

        // A reservation that already settled means this very offer minted the Root. Reporting that
        // as "already reserved" would be a lie in the trace; the Root is gone, permanently.
        if (status == uint8(ReservationStatus.SETTLED)) revert RootAlreadyMinted(offer.rootKey);

        // A DIFFERENT offer for the same Root already settled through this contract. See the
        // honesty note on `settledOfferForRoot` for what this check does NOT cover.
        if (_settledOfferForRoot[offer.rootKey] != bytes32(0)) revert RootAlreadyMinted(offer.rootKey);

        if (offer.status != uint8(PuppetTypes.OfferStatus.BTC_APPROVED)) {
            revert OfferNotBtcApproved(offerId, offer.status);
        }
        // Inclusive: an offer is live through the whole second named by `expiry`.
        if (block.timestamp > offer.expiry) revert OfferExpired(offerId, offer.expiry);

        // The three fields settlement will compare the payment attestation against. Checking them
        // now means a solver can never bond against an offer that is structurally unpayable, and
        // discovers it before it has spent real BTC rather than after.
        if (offer.ownershipDigest == bytes32(0) || offer.btcPayoutScriptHash == bytes32(0) || offer.sellerSats == 0) {
            revert IncompleteBtcOffer(offerId);
        }

        uint64 expiry = uint64(block.timestamp) + _reservationDuration;
        uint16 slashBps = _buyerSlashBps;

        r.solver = msg.sender;
        r.bondWei = msg.value;
        r.reservedAt = uint64(block.timestamp);
        r.reservationExpiry = expiry;
        r.buyerSlashBpsSnapshot = slashBps;
        r.status = uint8(ReservationStatus.ACTIVE);

        _totalBondsPosted += msg.value;
        _totalActiveBondWei += msg.value;
        _assertBondBooksBalance();

        emit Reserved(offerId, msg.sender, msg.value, expiry, slashBps);

        // Interaction last. The escrow's own guard is the authority on whether this offer may move
        // to BTC_RESERVED; if it disagrees with the status we just read, the whole call reverts and
        // no bond is recorded.
        ESCROW.markBtcReserved(offerId, msg.sender, expiry);
    }

    /*//////////////////////////////////////////////////////////////
                                 SETTLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Prove the exact BTC payment happened, mint the HoodPup and take reimbursement.
    /// @dev WHY THIS FUNCTION IS NOT PAUSABLE. By the time it is callable the solver has already
    ///      broadcast an irreversible Bitcoin transaction paying the seller. A pause here would
    ///      leave that payment stranded while the reservation clock kept running toward a slash —
    ///      i.e. it would be a lever that confiscates a solver's BTC *and* its bond. The incident
    ///      lever the specification asks for exists, and it lives where the incident would be:
    ///      `BitcoinOwnershipOracle.pause()` stops `consumeBitcoinPayment` for every consumer at
    ///      once. Pausing the risk source is right; pausing the victim's exit is not.
    ///
    ///      THE SETTLEMENT GRACE WINDOW. Settlement is allowed while the RESERVATION is live, even
    ///      if the OFFER's own expiry has passed. That window is `reservationExpiry - offer.expiry`
    ///      when positive, and is bounded by the `reservationDuration` snapshotted at `reserve`.
    ///      It exists because the alternative is strictly worse: a solver that paid BTC minutes
    ///      before the offer expired would otherwise lose the BTC, lose the bond and watch the
    ///      buyer refund, while the seller keeps the payment. The buyer is not exposed during the
    ///      window — the escrow holds the offer in BTC_RESERVED and refuses to refund it until
    ///      `expireReservation` clears the reservation here.
    ///
    ///      DELIBERATELY NOT DUPLICATED HERE: the attestation's deadline, attestor epoch, policy
    ///      version, signature count, signer membership and signer ordering, and whether this
    ///      Bitcoin output was already consumed. All of those are the oracle's authority. Copying
    ///      them into this contract would create a second source of truth that can silently drift
    ///      from the first. What IS checked here is everything the oracle cannot know: which offer,
    ///      which solver, which script, which amount.
    /// @param offerId The reserved offer being settled.
    /// @param attestation The 3-of-5 attested Bitcoin payment.
    /// @param signatures Attestor signatures, strictly ascending by recovered signer.
    /// @return tokenId The HoodPup minted by the escrow.
    function settle(
        bytes32 offerId,
        PuppetTypes.BitcoinPaymentAttestation calldata attestation,
        bytes[] calldata signatures
    ) external override nonReentrant returns (uint256 tokenId) {
        Reservation storage r = _reservations[offerId];
        if (r.status != uint8(ReservationStatus.ACTIVE)) revert NoActiveReservation(offerId);

        address solver = r.solver;
        // Two separate checks, both required. `msg.sender == solver` stops a permissionless relayer
        // from driving somebody else's settlement (the bond and the seller share would land on the
        // reserved solver, but the relayer would control WHEN and could grief the timing).
        // `attestation.solver == solver` stops a valid attestation naming a different solver from
        // being spent here at all — the oracle would happily consume it, and the reimbursement
        // would then be redirected to whoever the attestors named.
        if (msg.sender != solver) revert NotReservedSolver(msg.sender, solver);
        if (attestation.solver != solver) revert NotReservedSolver(attestation.solver, solver);

        // Inclusive: the reservation is live through the whole second named by its expiry, which
        // is the same boundary convention `expireReservation` uses on the other side.
        if (block.timestamp > r.reservationExpiry) revert ReservationExpired(offerId, r.reservationExpiry);

        bytes32 rootKey = _requirePaymentMatchesOffer(offerId, attestation);

        uint256 bond = r.bondWei;

        // EFFECTS FIRST. The reservation is closed before any external call, so no callback can
        // re-enter settle for this offer even if `nonReentrant` were somehow removed.
        r.status = uint8(ReservationStatus.SETTLED);
        _totalActiveBondWei -= bond;
        _totalBondsReturned += bond;
        _settledOfferForRoot[rootKey] = offerId;
        _assertBondBooksBalance();

        // INTERACTIONS, in the only order that is safe.
        //
        // 1. Consume the payment. This is the authorization: it verifies the quorum, the freshness
        //    context and the deadline, and permanently burns both the digest and the Bitcoin
        //    output key so one real BTC payment can settle at most one offer, ever.
        bytes32 paymentDigest;
        (paymentDigest,) = ORACLE.consumeBitcoinPayment(attestation, signatures);

        // 2. Mint and route. The escrow pays the SELLER share to the solver, because the seller was
        //    already paid in BTC off chain. If this reverts — Root minted by a competing offer, a
        //    recipient that rejects ERC-721, a paused router — the entire transaction rolls back,
        //    including the oracle consumption above. Nothing is half-settled.
        tokenId = ESCROW.finalizeBtcSettlement(offerId, solver, paymentDigest);

        // 3. ONLY NOW is the bond reimbursed. Steps 1 and 2 have both succeeded, so the solver has
        //    provably delivered. Credited rather than pushed: a solver whose fallback reverts must
        //    not be able to brick its own settlement, and a pull payment keeps the ETH exit out of
        //    this contract's reentrancy surface entirely.
        PAYOUT_VAULT.credit{value: bond}(solver);

        _emitSettled(offerId, solver, paymentDigest, attestation, bond);
    }

    /// @dev Every equality the oracle structurally cannot check, because it knows nothing about
    ///      escrow offers. Split out of `settle` so the offer struct's memory lifetime ends before
    ///      the interaction sequence begins; that keeps the stack inside the EVM's 16-slot limit
    ///      without turning on via-IR for the whole workspace.
    /// @return rootKey The offer's canonical Root key, used to record the settlement.
    function _requirePaymentMatchesOffer(bytes32 offerId, PuppetTypes.BitcoinPaymentAttestation calldata attestation)
        private
        view
        returns (bytes32 rootKey)
    {
        PuppetTypes.Offer memory offer = ESCROW.getOffer(offerId);
        if (offer.status != uint8(PuppetTypes.OfferStatus.BTC_RESERVED)) {
            revert OfferNotBtcApproved(offerId, offer.status);
        }

        if (attestation.contextId != offerId) revert PaymentFieldMismatch("contextId");
        // The digest ties this payment to the exact ownership fact the escrow approved, which is
        // what binds the payment to the seller's signed terms rather than to a bare script hash.
        if (attestation.ownershipDigest != offer.ownershipDigest) revert PaymentFieldMismatch("ownershipDigest");
        if (attestation.recipientScriptHash != offer.btcPayoutScriptHash) {
            revert PaymentFieldMismatch("recipientScriptHash");
        }
        // EXACT equality, never "at least". An overpayment is the solver's business; an
        // underpayment must not be settleable, and a range check would make "how much did Bob
        // actually get" unanswerable from on-chain data alone.
        if (attestation.amountSats != offer.sellerSats) revert PaymentFieldMismatch("amountSats");

        rootKey = offer.rootKey;
    }

    /// @dev Emitting through a helper keeps eight event arguments off `settle`'s stack.
    function _emitSettled(
        bytes32 offerId,
        address solver,
        bytes32 paymentDigest,
        PuppetTypes.BitcoinPaymentAttestation calldata attestation,
        uint256 bond
    ) private {
        emit Settled(
            offerId,
            solver,
            paymentDigest,
            attestation.bitcoinTxid,
            attestation.outputIndex,
            attestation.amountSats,
            attestation.recipientScriptHash,
            bond
        );
    }

    /*//////////////////////////////////////////////////////////////
                            EXPIRY AND SLASHING
    //////////////////////////////////////////////////////////////*/

    /// @notice Permissionless: release a stale reservation and slash its bond.
    /// @dev PERMISSIONLESS BY DESIGN. The buyer, a competing solver, a watcher bot or a passer-by
    ///      may all call this. Gating it would make the buyer's refund depend on a privileged
    ///      party's liveness, and there is nothing to gate: the amounts and destinations are fully
    ///      determined by the snapshot, so the caller has no discretion whatsoever.
    ///
    ///      NOT PAUSABLE, EVER. Pausing may block new risk-taking; it must never block a path that
    ///      returns money. This is that path: it is what lets the buyer's escrow become refundable
    ///      again and what pays the buyer its compensation.
    ///
    ///      NO DISCRETIONARY FORGIVENESS EXISTS. There is no admin function that can cancel,
    ///      shorten, extend or waive an individual slash. Such a function would be a rug lever
    ///      wearing a customer-service badge: whoever holds it could privately promise one solver
    ///      immunity and thereby hand it a free option on every BTC offer in the system. If the
    ///      slash policy is too harsh for real Bitcoin confirmation latency, the honest fix is a
    ///      longer `reservationDuration` or a lower `buyerSlashBps` — both public, both timelocked,
    ///      and both applying only to reservations made after they land.
    ///
    ///      CONSERVATION IS EXACT. `protocolAmount` is the REMAINDER, never an independently
    ///      computed percentage, so `buyerCompensation + protocolAmount == bondWei` holds for every
    ///      bond and every bps value including the rounding-dust cases. Zero-valued shares are
    ///      filtered out rather than sent, because `PayoutVault` correctly rejects a zero credit.
    /// @param offerId The offer whose reservation has run out.
    function expireReservation(bytes32 offerId) external override nonReentrant {
        Reservation storage r = _reservations[offerId];
        if (r.status != uint8(ReservationStatus.ACTIVE)) revert NoActiveReservation(offerId);

        uint64 reservationExpiry = r.reservationExpiry;
        if (block.timestamp <= reservationExpiry) revert ReservationNotExpired(offerId, reservationExpiry);

        address solver = r.solver;
        uint256 bond = r.bondWei;
        uint16 slashBps = r.buyerSlashBpsSnapshot;

        // EFFECTS FIRST.
        r.status = uint8(ReservationStatus.EXPIRED);
        _totalActiveBondWei -= bond;
        _totalBondsSlashed += bond;
        _assertBondBooksBalance();

        // The buyer is read from the escrow rather than snapshotted because an offer's buyer is
        // immutable there; snapshotting it would duplicate a fact that cannot change.
        PuppetTypes.Offer memory offer = ESCROW.getOffer(offerId);

        uint256 buyerCompensation = (bond * slashBps) / BPS_DENOMINATOR;
        uint256 protocolAmount = bond - buyerCompensation;

        // Return the offer to BTC_APPROVED so another solver can bond it, or so the buyer can
        // refund it if it has since expired. Called without try/catch: the escrow only reaches
        // BTC_RESERVED through this contract and only leaves it through this contract, so a revert
        // here means the two are already inconsistent, and quietly proceeding would bury that.
        ESCROW.clearBtcReservation(offerId);

        emit ReservationExpiredAndSlashed(offerId, solver, bond, buyerCompensation, protocolAmount);

        _creditSlash(offer.buyer, buyerCompensation, _protocolSlashRecipient, protocolAmount);
    }

    /// @dev Pays out a slashed bond in at most one `PayoutVault` call.
    ///      Filtering zero shares matters more than it looks: `buyerSlashBps == 0` or `== 10000`
    ///      are both legitimate governance choices, and small bonds round one share to zero. A
    ///      naive two-entry batch would revert `ZeroAmount` on exactly those inputs and would make
    ///      an expiry — a refund path — permanently uncallable.
    function _creditSlash(address buyer, uint256 buyerCompensation, address protocolRecipient, uint256 protocolAmount)
        private
    {
        if (buyerCompensation != 0 && protocolAmount != 0) {
            address[] memory beneficiaries = new address[](2);
            uint256[] memory amounts = new uint256[](2);
            beneficiaries[0] = buyer;
            amounts[0] = buyerCompensation;
            beneficiaries[1] = protocolRecipient;
            amounts[1] = protocolAmount;
            PAYOUT_VAULT.creditBatch{value: buyerCompensation + protocolAmount}(beneficiaries, amounts);
        } else if (buyerCompensation != 0) {
            PAYOUT_VAULT.credit{value: buyerCompensation}(buyer);
        } else if (protocolAmount != 0) {
            PAYOUT_VAULT.credit{value: protocolAmount}(protocolRecipient);
        }
        // A zero bond is impossible (`minimumBondWei` is non-zero and immutable in effect for the
        // life of a reservation), so at least one branch always runs. The final `else` is left
        // unwritten rather than reverting, because a revert there would be unreachable code
        // pretending to be a guard.
    }

    /*//////////////////////////////////////////////////////////////
                              FORCED ETH
    //////////////////////////////////////////////////////////////*/

    /// @notice Credit any ETH that is not backing an active reservation to the protocol recipient.
    /// @dev Anyone may call this and nobody chooses the destination: it is read from the governed
    ///      `protocolSlashRecipient` at execution time and the amount is computed as
    ///      `balance - totalActiveBondWei`, so it is structurally incapable of touching a bond.
    ///      That is what keeps it from being the "hidden owner withdrawal" the protocol rules
    ///      forbid — there is no privileged caller and no discretion for a timelock to delay.
    ///
    ///      ETH can only get here by `selfdestruct` or a block reward, neither of which carries an
    ///      identifiable sender, so returning it is impossible rather than merely inconvenient.
    /// @return amount Wei credited.
    function sweepForcedEth() external nonReentrant returns (uint256 amount) {
        amount = address(this).balance - _totalActiveBondWei;
        if (amount == 0) revert NoForcedEth();

        address recipient = _protocolSlashRecipient;
        emit ForcedEthSwept(recipient, amount, msg.sender);
        PAYOUT_VAULT.credit{value: amount}(recipient);
    }

    /// @dev No plain ETH transfer is ever legitimate here; bond wei must arrive through `reserve`
    ///      so it is attributable to exactly one reservation.
    receive() external payable {
        revert DirectDepositRejected();
    }

    /// @dev Same reasoning as `receive`, and it also turns a mistyped selector into a clear revert
    ///      instead of a silent donation.
    fallback() external payable {
        revert DirectDepositRejected();
    }

    /*//////////////////////////////////////////////////////////////
                             CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the minimum bond required of future reservations.
    /// @dev Cannot affect an active reservation: the bond in force is the one snapshotted at
    ///      `reserve`, and this value is never read again after that.
    /// @param newMinimumBondWei New minimum, in wei. Must be non-zero.
    function setMinimumBondWei(uint256 newMinimumBondWei) external onlyRole(CONFIG_ADMIN_ROLE) {
        if (newMinimumBondWei == 0) revert InvalidConfiguration();
        uint256 previous = _minimumBondWei;
        if (previous == newMinimumBondWei) revert ConfigUnchanged();

        _minimumBondWei = newMinimumBondWei;
        emit MinimumBondUpdated(previous, newMinimumBondWei);
    }

    /// @notice Set the window future solvers get to prove payment.
    /// @dev Bounded by `MIN_RESERVATION_DURATION` / `MAX_RESERVATION_DURATION` in bytecode. The
    ///      lower bound protects solvers from being slashed for Bitcoin's latency; the upper bound
    ///      protects buyers from having their escrow locked indefinitely past an offer's expiry.
    /// @param newDuration New reservation window in seconds.
    function setReservationDuration(uint64 newDuration) external onlyRole(CONFIG_ADMIN_ROLE) {
        if (newDuration < MIN_RESERVATION_DURATION || newDuration > MAX_RESERVATION_DURATION) {
            revert InvalidConfiguration();
        }
        uint64 previous = _reservationDuration;
        if (previous == newDuration) revert ConfigUnchanged();

        _reservationDuration = newDuration;
        emit ReservationDurationUpdated(previous, newDuration);
    }

    /// @notice Set the share of a future slashed bond that compensates the buyer.
    /// @dev Both extremes are permitted. 10000 sends the whole bond to the buyer; 0 sends it all to
    ///      the protocol. Neither is a safety problem — conservation holds either way — and
    ///      forbidding them would be an aesthetic rule, not a security one.
    /// @param newBps New buyer share in basis points. Must be at most 10000.
    function setBuyerSlashBps(uint16 newBps) external onlyRole(CONFIG_ADMIN_ROLE) {
        if (newBps > BPS_DENOMINATOR) revert InvalidConfiguration();
        uint16 previous = _buyerSlashBps;
        if (previous == newBps) revert ConfigUnchanged();

        _buyerSlashBps = newBps;
        emit BuyerSlashBpsUpdated(previous, newBps);
    }

    /// @notice Set where the non-buyer share of a slashed bond goes.
    /// @dev THE ONE PARAMETER THAT IS NOT SNAPSHOTTED, and deliberately so. It is a protocol
    ///      destination, not a term of the solver's bargain: changing it cannot alter how much the
    ///      solver loses or how much the buyer receives, only which protocol address receives a
    ///      share the solver had already forfeited. Snapshotting it would freeze a possibly
    ///      compromised address into every live reservation, which is strictly worse.
    /// @param newRecipient New protocol destination. Must be non-zero.
    function setProtocolSlashRecipient(address newRecipient) external onlyRole(CONFIG_ADMIN_ROLE) {
        if (newRecipient == address(0)) revert ZeroAddress();
        address previous = _protocolSlashRecipient;
        if (previous == newRecipient) revert ConfigUnchanged();

        _protocolSlashRecipient = newRecipient;
        emit ProtocolSlashRecipientUpdated(previous, newRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                                  PAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice Stop new reservations. Settlement, expiry and slash credits stay live.
    /// @dev The complete list of things this blocks is one function: `reserve`. It cannot block a
    ///      solver from settling a payment it has already made, cannot block an expiry, cannot
    ///      block a buyer's compensation and cannot block a withdrawal (which lives in
    ///      `PayoutVault` and is unpausable there).
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Allow new reservations again.
    /// @dev `DEFAULT_ADMIN_ROLE`, not `PAUSER_ROLE`: a hot guardian key may stop risk in seconds,
    ///      but restarting it is a governed decision.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBtcSolverSettlement
    /// @param offerId The offer to look up.
    /// @return The reservation record. A never-reserved offer returns an all-zero struct with
    ///         `status == ReservationStatus.NONE`; this view never reverts.
    function reservationOf(bytes32 offerId) external view override returns (Reservation memory) {
        return _reservations[offerId];
    }

    /// @inheritdoc IBtcSolverSettlement
    function minimumBondWei() external view override returns (uint256) {
        return _minimumBondWei;
    }

    /// @inheritdoc IBtcSolverSettlement
    function reservationDuration() external view override returns (uint64) {
        return _reservationDuration;
    }

    /// @inheritdoc IBtcSolverSettlement
    function buyerSlashBps() external view override returns (uint16) {
        return _buyerSlashBps;
    }

    /// @inheritdoc IBtcSolverSettlement
    function protocolSlashRecipient() external view override returns (address) {
        return _protocolSlashRecipient;
    }

    /// @notice Sum of the bonds of every currently ACTIVE reservation.
    /// @return The contract's total bond liability in wei.
    function totalActiveBondWei() external view returns (uint256) {
        return _totalActiveBondWei;
    }

    /// @notice Cumulative wei ever posted as bonds. Never decreases.
    function totalBondsPosted() external view returns (uint256) {
        return _totalBondsPosted;
    }

    /// @notice Cumulative wei ever credited back to solvers on settlement. Never decreases.
    function totalBondsReturned() external view returns (uint256) {
        return _totalBondsReturned;
    }

    /// @notice Cumulative wei ever slashed and split on expiry. Never decreases.
    function totalBondsSlashed() external view returns (uint256) {
        return _totalBondsSlashed;
    }

    /// @notice The offer that settled a Root through THIS contract, or zero.
    /// @dev HONESTY NOTE: this records only settlements this contract performed. A Root minted
    ///      through the ETH path (`HoodPupOfferEscrow.settlePaidEvm`) or by a self-cast is
    ///      invisible here, because the deployment-pinned constructor gives this contract no
    ///      `HoodPups` reference to ask. A solver MUST therefore check `HoodPups.rootMinted`
    ///      off chain before bonding; the guard in `reserve` catches the competing-BTC-offer case
    ///      only. The authoritative one-Root-one-HoodPup rule is enforced where the mint happens,
    ///      in `HoodPups.mintRooted`, and a settlement that races it reverts in full.
    /// @param rootKey Canonical Root key.
    /// @return offerId The settling offer id, or zero.
    function settledOfferForRoot(bytes32 rootKey) external view returns (bytes32 offerId) {
        return _settledOfferForRoot[rootKey];
    }

    /// @notice ETH held here that is not backing an active reservation.
    /// @dev Non-zero only when ETH has been forced in by `selfdestruct` or a block reward, since
    ///      `receive`/`fallback` reject every ordinary transfer.
    function forcedEthBalance() external view returns (uint256) {
        return address(this).balance - _totalActiveBondWei;
    }

    /// @notice True while the bond accounting equation holds. Should never be false.
    /// @dev Exposed so a monitoring service can assert the same equation the contract enforces
    ///      internally, without having to reconstruct it from four separate getters and risk
    ///      writing the equation down differently.
    function bondBooksBalance() external view returns (bool) {
        return _totalBondsPosted == _totalActiveBondWei + _totalBondsReturned + _totalBondsSlashed;
    }

    /// @inheritdoc IERC165
    /// @param interfaceId The ERC-165 identifier being queried.
    /// @return True if this contract implements `interfaceId`.
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return interfaceId == type(IBtcSolverSettlement).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Re-derives the bond accounting equation after every ledger write and reverts if it has
    ///      stopped holding. This is defence in depth, not a correctness requirement: the three
    ///      call sites are already written so that each bond moves between exactly two counters in
    ///      one statement pair. It is kept anyway, at the cost of four SLOADs on a value-moving
    ///      path, because "the books balanced when this transaction ended" is the single property
    ///      a solver's money depends on, and a future edit that adds a fourth ledger movement
    ///      should fail loudly rather than drift quietly. Clarity and safety over gas, explicitly.
    function _assertBondBooksBalance() private view {
        uint256 posted = _totalBondsPosted;
        uint256 active = _totalActiveBondWei;
        uint256 returned = _totalBondsReturned;
        uint256 slashed = _totalBondsSlashed;
        if (posted != active + returned + slashed) {
            revert BondAccountingBroken(posted, active, returned, slashed);
        }
    }
}
