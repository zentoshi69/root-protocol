// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {BitcoinAttestorRegistry} from "../../../src/BitcoinAttestorRegistry.sol";
import {BitcoinOwnershipOracle} from "../../../src/BitcoinOwnershipOracle.sol";
import {BtcSolverSettlement} from "../../../src/BtcSolverSettlement.sol";
import {IBtcSolverSettlement} from "../../../src/interfaces/IBtcSolverSettlement.sol";
import {PuppetHashing} from "../../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../../src/types/PuppetTypes.sol";
import {AttestorSet} from "../../helpers/AttestorSet.sol";
import {MockOfferEscrow} from "../../unit/BtcSolverSettlement.t.sol";

/// @title SolverBondHandler
/// @notice Bounded random driver for `BtcSolverSettlement`'s stateful bond-conservation campaign.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      WHY A HANDLER. Pointed straight at the settlement contract, a fuzzer would spend nearly
///      every call bouncing off `NoActiveReservation` and `OfferNotBtcApproved`, and the campaign
///      would prove only that the guards compile. This handler keeps its inputs inside the shapes
///      the contract can actually accept — real offers, real solvers, real 3-of-5 signatures — so
///      most calls mutate state, which is where the interesting interleavings live.
///
///      IT HOLDS `PAUSER_ROLE` AND `DEFAULT_ADMIN_ROLE` ON PURPOSE. The claims below are therefore
///      asserted against a maximally-privileged adversary that can pause and unpause at will
///      between any two actions. "No ordering, and no admin, can make a bond disappear" is an
///      uninteresting claim if the fuzzer never held the keys.
///
///      THE ORACLE HERE IS THE REAL `BitcoinOwnershipOracle`, backed by the real
///      `BitcoinAttestorRegistry` and real secp256k1 signatures from `AttestorSet`. Consumption of
///      the payment digest and of the Bitcoin output key is therefore genuine, which is what makes
///      "no BTC-mode mint without exactly one consumed unique payment output" a real claim rather
///      than a claim about a permissive stub.
///
///      THE ESCROW IS `MockOfferEscrow` (see its honesty note). Nothing in this campaign is
///      evidence about `HoodPupOfferEscrow`.
///
///      TWO DELIBERATE SIMPLIFICATIONS, both stated so a green campaign is not over-read:
///        1. Every campaign offer has `sellerWei == 0`, so the escrow credits nothing of its own.
///           That makes `PayoutVault.claimable` a pure function of BOND movement, which is what
///           lets the bucket invariants be flat equalities instead of hedged inequalities. The
///           seller share is escrow business and is covered in the unit suite.
///        2. There is no withdrawal action, so every `claimable` figure only ever grows and any
///           decrease at all is a bug rather than something to reconcile.
contract SolverBondHandler is CommonBase, StdUtils {
    /*//////////////////////////////////////////////////////////////
                                FIXTURES
    //////////////////////////////////////////////////////////////*/

    BtcSolverSettlement public immutable SETTLEMENT;
    MockOfferEscrow public immutable ESCROW;
    BitcoinOwnershipOracle public immutable ORACLE;
    BitcoinAttestorRegistry public immutable ATTESTOR_REGISTRY;
    AttestorSet public immutable ATTESTORS;

    address public immutable BUYER;
    address public immutable PROTOCOL_RECIPIENT;

    /// @dev Prefix on every fixture txid so nothing in this campaign can be mistaken for a real
    ///      Bitcoin transaction. The literal is exactly 16 bytes, so nothing is actually truncated.
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes16 private constant FIXTURE_MARKER = bytes16("FIXTURE-NOT-REAL");

    uint256 private constant SOLVER_COUNT = 4;
    uint256 private constant MAX_OFFERS = 8;

    address[] private _solvers;
    bytes32[] private _offerIds;

    /// @dev Bumped on every settlement attempt so no two payment attestations can collide on a
    ///      digest or on a Bitcoin output key.
    uint256 private _nonce;

    /*//////////////////////////////////////////////////////////////
                             GHOST ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Wei this handler believes has been posted as bonds.
    uint256 public ghostPosted;
    /// @notice Wei this handler believes has been returned to solvers.
    uint256 public ghostReturned;
    /// @notice Wei this handler believes has been slashed and split.
    uint256 public ghostSlashed;
    /// @notice Wei force-sent into the settlement contract by the campaign.
    uint256 public ghostForcedIn;
    /// @notice Wei swept back out of the settlement contract by `sweepForcedEth`.
    uint256 public ghostForcedSwept;

    /// @notice Accepted calls per action, so coverage can be measured rather than assumed.
    uint256 public reserveCount;
    uint256 public settleCount;
    uint256 public expireCount;
    uint256 public reReserveCount;

    /// @notice Payment output key consumed by each settlement, in settlement order.
    bytes32[] private _consumedOutputKeys;

    /// @notice True once an offer has settled. A settled offer must never move again.
    mapping(bytes32 => bool) public ghostEverSettled;

    constructor(
        BtcSolverSettlement settlement,
        MockOfferEscrow escrow,
        BitcoinOwnershipOracle oracle,
        BitcoinAttestorRegistry attestorRegistry,
        AttestorSet attestorSet,
        address buyer,
        address protocolRecipient
    ) {
        SETTLEMENT = settlement;
        ESCROW = escrow;
        ORACLE = oracle;
        ATTESTOR_REGISTRY = attestorRegistry;
        ATTESTORS = attestorSet;
        BUYER = buyer;
        PROTOCOL_RECIPIENT = protocolRecipient;

        for (uint256 i = 0; i < SOLVER_COUNT; i++) {
            address s = address(uint160(uint256(keccak256(abi.encode("HOODPUPS_CAMPAIGN_SOLVER", i)))));
            _solvers.push(s);
            vm.deal(s, 10_000 ether);
        }

        // One offer exists from the start so the very first fuzz call can do something real.
        _createOffer();
    }

    /*//////////////////////////////////////////////////////////////
                                 ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Add another BTC-approved offer, up to the cap.
    function createOffer() external {
        if (_offerIds.length >= MAX_OFFERS) return;
        _createOffer();
    }

    /// @notice Post a bond on an offer.
    function reserve(uint256 offerSeed, uint256 solverSeed, uint256 bondSeed) external {
        bytes32 offerId = _pickOffer(offerSeed);
        address who = _solvers[bound(solverSeed, 0, SOLVER_COUNT - 1)];
        uint256 bond = bound(bondSeed, SETTLEMENT.minimumBondWei(), SETTLEMENT.minimumBondWei() + 5 ether);

        uint8 before = SETTLEMENT.reservationOf(offerId).status;

        vm.prank(who);
        try SETTLEMENT.reserve{value: bond}(offerId) {
            ghostPosted += bond;
            reserveCount++;
            if (before == uint8(IBtcSolverSettlement.ReservationStatus.EXPIRED)) reReserveCount++;
        } catch {}
    }

    /// @notice Settle an offer as its reserved solver, with a real 3-of-5 quorum.
    function settle(uint256 offerSeed) external {
        bytes32 offerId = _pickOffer(offerSeed);
        IBtcSolverSettlement.Reservation memory r = SETTLEMENT.reservationOf(offerId);
        if (r.status != uint8(IBtcSolverSettlement.ReservationStatus.ACTIVE)) return;

        PuppetTypes.Offer memory offer = ESCROW.getOffer(offerId);
        bytes32 txid = keccak256(abi.encode("HOODPUPS_CAMPAIGN_PAYMENT", _nonce++));

        PuppetTypes.BitcoinPaymentAttestation memory a = _attestation(offerId, r.solver, txid, offer);
        bytes[] memory signatures = ATTESTORS.sign(ORACLE.hashBitcoinPaymentAttestation(a), 3);

        uint256 bond = r.bondWei;
        vm.prank(r.solver);
        try SETTLEMENT.settle(offerId, a, signatures) {
            ghostReturned += bond;
            settleCount++;
            ghostEverSettled[offerId] = true;
            _consumedOutputKeys.push(PuppetHashing.paymentOutputKey(txid, 0));
        } catch {}
    }

    /// @notice Expire a stale reservation and split its bond.
    function expire(uint256 offerSeed, uint256 callerSeed) external {
        bytes32 offerId = _pickOffer(offerSeed);
        IBtcSolverSettlement.Reservation memory r = SETTLEMENT.reservationOf(offerId);
        uint256 bond = r.bondWei;

        // Deliberately unprivileged and arbitrary: expiry must be caller independent.
        address caller = address(uint160(uint256(keccak256(abi.encode("CAMPAIGN_WATCHER", callerSeed)))));
        vm.prank(caller);
        try SETTLEMENT.expireReservation(offerId) {
            ghostSlashed += bond;
            expireCount++;
        } catch {}
    }

    /// @notice Move time forward, which is what makes reservations expirable.
    function warp(uint256 secondsSeed) external {
        vm.warp(block.timestamp + bound(secondsSeed, 1 minutes, 9 hours));
    }

    /// @notice Flip the pause. Pausing must never strand a bond.
    function togglePause() external {
        if (SETTLEMENT.paused()) {
            SETTLEMENT.unpause();
        } else {
            SETTLEMENT.pause();
        }
    }

    /// @notice Force ETH into the settlement contract, the way `selfdestruct` would.
    function forceEth(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 1, 3 ether);
        vm.deal(address(SETTLEMENT), address(SETTLEMENT).balance + amount);
        ghostForcedIn += amount;
    }

    /// @notice Sweep forced ETH out to the protocol recipient.
    function sweepForcedEth() external {
        uint256 expected = address(SETTLEMENT).balance - SETTLEMENT.totalActiveBondWei();
        try SETTLEMENT.sweepForcedEth() {
            ghostForcedSwept += expected;
        } catch {}
    }

    /*//////////////////////////////////////////////////////////////
                              GHOST READERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Every offer id the campaign has created.
    function offerIds() external view returns (bytes32[] memory) {
        return _offerIds;
    }

    /// @notice Every solver address the campaign bonds with.
    function solvers() external view returns (address[] memory) {
        return _solvers;
    }

    /// @notice Payment output keys consumed by settlements, in order.
    function consumedOutputKeys() external view returns (bytes32[] memory) {
        return _consumedOutputKeys;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _pickOffer(uint256 seed) private view returns (bytes32) {
        return _offerIds[bound(seed, 0, _offerIds.length - 1)];
    }

    /// @dev Every offer gets its OWN Root, so a settled Root can never make a later reservation
    ///      revert for a reason that has nothing to do with bond accounting.
    function _createOffer() private {
        // `index` is bounded by MAX_OFFERS (8), so every narrowing cast below is provably exact.
        uint256 index = _offerIds.length;

        // casting to 'bytes16' is safe because the truncation IS the point: the first half is the
        // literal "not a real Bitcoin txid" marker and only 16 bytes of entropy are needed here.
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes16 tail = bytes16(keccak256(abi.encode("campaign-root", index)));
        // casting to 'uint32' is safe because index < MAX_OFFERS == 8.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 inscriptionIndex = uint32(index);
        // casting to 'uint64' is safe because index < MAX_OFFERS == 8.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 sellerSats = 1_000_000 + uint64(index);
        // casting to 'uint160' is safe because the operand is a small literal plus index < 8.
        // forge-lint: disable-next-line(unsafe-typecast)
        address offerRecipient = address(uint160(0xB0B0000 + index));

        PuppetTypes.RootId memory root = PuppetTypes.RootId({
            inscriptionTxid: bytes32(abi.encodePacked(FIXTURE_MARKER, tail)), inscriptionIndex: inscriptionIndex
        });

        vm.deal(address(this), 1 ether);
        bytes32 offerId = ESCROW.seedApprovedBtcOffer(
            BUYER,
            offerRecipient,
            root,
            0, // sellerWei: see simplification 1 in the header
            sellerSats,
            uint64(block.timestamp) + 3650 days,
            keccak256(abi.encode("campaign-ownership-digest", index)),
            keccak256(abi.encode("campaign-seller-script", index))
        );
        _offerIds.push(offerId);
    }

    function _attestation(bytes32 offerId, address solver, bytes32 txid, PuppetTypes.Offer memory offer)
        private
        view
        returns (PuppetTypes.BitcoinPaymentAttestation memory)
    {
        (, uint64 epoch, uint32 policy) = ATTESTOR_REGISTRY.quorumContext();
        return PuppetTypes.BitcoinPaymentAttestation({
            contextId: offerId,
            ownershipDigest: offer.ownershipDigest,
            solver: solver,
            bitcoinTxid: txid,
            outputIndex: 0,
            recipientScriptHash: offer.btcPayoutScriptHash,
            amountSats: offer.sellerSats,
            bitcoinBlockHash: keccak256(abi.encode("campaign-block", txid)),
            bitcoinHeight: 900_000,
            authorizationId: txid,
            deadline: uint64(block.timestamp) + 1 hours,
            attestorEpoch: epoch,
            policyVersion: policy
        });
    }
}
