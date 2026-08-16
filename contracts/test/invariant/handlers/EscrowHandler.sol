// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {HoodPupOfferEscrow} from "../../../src/HoodPupOfferEscrow.sol";
import {HoodPups} from "../../../src/HoodPups.sol";
import {PayoutVault} from "../../../src/PayoutVault.sol";
import {PuppetHashing} from "../../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../../src/types/PuppetTypes.sol";

/// @title EscrowHandler
/// @notice Bounded-random driver for `HoodPupOfferEscrow`'s stateful invariant campaign.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      HONESTY NOTE — WHAT THIS CAMPAIGN DOES AND DOES NOT PROVE. It runs against the REAL
///      escrow, the REAL `PayoutVault`, the REAL `FeeRouter`, the REAL `HoodPups` ERC-721 and the
///      REAL `PuppetCollectionRegistry`, so every money and uniqueness claim below is made against
///      production accounting. The ownership oracle is `MockOwnershipOracle`, which performs no
///      signature recovery, no quorum counting and no freshness checking. This campaign therefore
///      proves things about the escrow's STATE MACHINE and its MONEY CONSERVATION, and proves
///      nothing about quorum security — those properties belong to `BitcoinOwnershipOracle`'s own
///      suite, and the escrow's unit and fuzz suites drive the real oracle end to end.
///
///      The one oracle property this campaign leans on is permanent one-time digest consumption,
///      which the mock does enforce honestly, because "no offer settles twice" would be a hollow
///      claim against an oracle that let an authorization be reused.
///
///      THE HANDLER HOLDS EVERY PRIVILEGED ROLE THE ESCROW HAS (`BTC_SETTLEMENT_ROLE`,
///      `PAUSER_ROLE`, `DEFAULT_ADMIN_ROLE`). The invariants are therefore asserted against a
///      maximally-privileged adversary that is free to pause, unpause, reserve, clear and finalize
///      in any interleaving the fuzzer can find.
contract EscrowHandler is CommonBase, StdCheats, StdUtils {
    /*//////////////////////////////////////////////////////////////
                              THE SYSTEM
    //////////////////////////////////////////////////////////////*/

    HoodPupOfferEscrow public immutable ESCROW;
    HoodPups public immutable NFT;
    PayoutVault public immutable VAULT;

    PuppetTypes.RootId[] private _roots;
    bytes32[][] private _proofs;

    address[3] public actors;
    address[2] public solvers;
    address public constant SELLER_PAYOUT = address(uint160(uint256(keccak256("handler:bobEvmPayout"))));

    /*//////////////////////////////////////////////////////////////
                             GHOST STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Every offer id the campaign has created, in creation order.
    bytes32[] public offerIds;

    /// @notice Total wei ever escrowed by a creation call that succeeded.
    uint256 public ghostDeposited;
    /// @notice Total wei ever credited back to a buyer by a refund.
    uint256 public ghostRefunded;
    /// @notice Total wei ever routed out through `FeeRouter` by a settlement.
    uint256 public ghostDistributed;

    /// @notice Number of times each offer reached SETTLED. Must never exceed one.
    mapping(bytes32 => uint256) public ghostSettleCount;
    /// @notice Number of times each offer reached REFUNDED. Must never exceed one.
    mapping(bytes32 => uint256) public ghostRefundCount;
    /// @notice Offers that were settled through `finalizeBtcSettlement` specifically.
    mapping(bytes32 => bool) public ghostFinalizedViaBtc;
    /// @notice Highest terminal status each offer has ever been observed in, for stickiness checks.
    mapping(bytes32 => uint8) public ghostTerminalStatus;

    /// @notice Coverage counters. A campaign that never settles anything proves very little, so
    ///         these are asserted by a deterministic test rather than by an invariant (a coverage
    ///         claim is legitimately false on a shrunk single-call sequence).
    uint256 public settlementsSeen;
    uint256 public refundsSeen;
    uint256 public btcFinalizationsSeen;
    uint256 public reservationsSeen;
    uint256 public expiredReservationsSeen;
    uint256 public unfillableRefundsSeen;

    constructor(
        HoodPupOfferEscrow escrow_,
        HoodPups nft_,
        PayoutVault vault_,
        PuppetTypes.RootId[] memory roots_,
        bytes32[][] memory proofs_
    ) {
        ESCROW = escrow_;
        NFT = nft_;
        VAULT = vault_;
        for (uint256 i = 0; i < roots_.length; i++) {
            _roots.push(roots_[i]);
            _proofs.push(proofs_[i]);
        }

        actors[0] = address(uint160(uint256(keccak256("handler:actor0"))));
        actors[1] = address(uint160(uint256(keccak256("handler:actor1"))));
        actors[2] = address(uint160(uint256(keccak256("handler:actor2"))));
        solvers[0] = address(uint160(uint256(keccak256("handler:solver0"))));
        solvers[1] = address(uint160(uint256(keccak256("handler:solver1"))));

        for (uint256 i = 0; i < actors.length; i++) {
            vm.deal(actors[i], 100_000 ether);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function offerCount() external view returns (uint256) {
        return offerIds.length;
    }

    function rootCount() external view returns (uint256) {
        return _roots.length;
    }

    function rootKeyAt(uint256 index) external view returns (bytes32) {
        return PuppetHashing.rootKey(_roots[index].inscriptionTxid, _roots[index].inscriptionIndex);
    }

    /*//////////////////////////////////////////////////////////////
                                ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Open a paid EVM offer against a bounded-random Root.
    function createPaidEvm(uint256 actorSeed, uint256 rootSeed, uint256 priceSeed, uint256 expirySeed) external {
        uint256 rootIndex = _bound(rootSeed, 0, _roots.length - 1);
        address actor = actors[_bound(actorSeed, 0, actors.length - 1)];
        uint256 price = _bound(priceSeed, 1, 50 ether);
        uint64 expiry = _expiry(expirySeed);
        if (ESCROW.paused()) return;
        if (NFT.rootMinted(this.rootKeyAt(rootIndex))) return;

        vm.prank(actor);
        try ESCROW.createPaidEvmOffer{value: price}(_roots[rootIndex], actor, expiry, _proofs[rootIndex]) returns (
            bytes32 offerId
        ) {
            offerIds.push(offerId);
            ghostDeposited += price;
        } catch {}
    }

    /// @notice Open a paid BTC offer against a bounded-random Root.
    function createPaidBtc(uint256 actorSeed, uint256 rootSeed, uint256 priceSeed, uint256 expirySeed) external {
        uint256 rootIndex = _bound(rootSeed, 0, _roots.length - 1);
        address actor = actors[_bound(actorSeed, 0, actors.length - 1)];
        uint256 price = _bound(priceSeed, 1, 50 ether);
        uint64 expiry = _expiry(expirySeed);
        if (ESCROW.paused()) return;
        if (NFT.rootMinted(this.rootKeyAt(rootIndex))) return;

        vm.prank(actor);
        try ESCROW.createPaidBtcOffer{value: price}(
            _roots[rootIndex], actor, uint64(_bound(priceSeed, 1, 1e12)), expiry, _proofs[rootIndex]
        ) returns (
            bytes32 offerId
        ) {
            offerIds.push(offerId);
            ghostDeposited += price;
        } catch {}
    }

    /// @notice Open a free self-cast offer.
    function createSelfCast(uint256 actorSeed, uint256 rootSeed, uint256 expirySeed) external {
        uint256 rootIndex = _bound(rootSeed, 0, _roots.length - 1);
        address actor = actors[_bound(actorSeed, 0, actors.length - 1)];
        uint64 expiry = _expiry(expirySeed);
        if (ESCROW.paused()) return;
        if (NFT.rootMinted(this.rootKeyAt(rootIndex))) return;

        vm.prank(actor);
        try ESCROW.createSelfCastOffer(_roots[rootIndex], actor, expiry, _proofs[rootIndex]) returns (bytes32 offerId) {
            offerIds.push(offerId);
        } catch {}
    }

    /// @notice Settle a paid EVM offer with a well-formed attestation.
    function settlePaidEvm(uint256 offerSeed) external {
        (bytes32 offerId, PuppetTypes.Offer memory o, bool ok) = _pick(offerSeed);
        if (!ok || o.kind != uint8(PuppetTypes.OfferKind.PAID_EVM)) return;
        if (o.status != uint8(PuppetTypes.OfferStatus.OPEN)) return;

        PuppetTypes.OwnershipAttestation memory a = _attestation(offerId, o);
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.EVM);
        a.evmPayout = SELLER_PAYOUT;

        try ESCROW.settlePaidEvm(offerId, a, new bytes[](0), new bytes32[](0)) {
            ghostSettleCount[offerId] += 1;
            ghostTerminalStatus[offerId] = uint8(PuppetTypes.OfferStatus.SETTLED);
            ghostDistributed += o.grossWei;
            settlementsSeen++;
        } catch {}
    }

    /// @notice Settle a free self-cast offer.
    function settleSelfCast(uint256 offerSeed) external {
        (bytes32 offerId, PuppetTypes.Offer memory o, bool ok) = _pick(offerSeed);
        if (!ok || o.kind != uint8(PuppetTypes.OfferKind.SELF_CAST)) return;
        if (o.status != uint8(PuppetTypes.OfferStatus.OPEN)) return;

        PuppetTypes.OwnershipAttestation memory a = _attestation(offerId, o);
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.SELF_CAST);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.NONE);

        try ESCROW.settleSelfCast(offerId, a, new bytes[](0), new bytes32[](0)) {
            ghostSettleCount[offerId] += 1;
            ghostTerminalStatus[offerId] = uint8(PuppetTypes.OfferStatus.SETTLED);
            settlementsSeen++;
        } catch {}
    }

    /// @notice Prove Bitcoin ownership for a BTC offer without minting or paying.
    function approvePaidBtc(uint256 offerSeed) external {
        (bytes32 offerId, PuppetTypes.Offer memory o, bool ok) = _pick(offerSeed);
        if (!ok || o.kind != uint8(PuppetTypes.OfferKind.PAID_BTC)) return;
        if (o.status != uint8(PuppetTypes.OfferStatus.OPEN)) return;

        PuppetTypes.OwnershipAttestation memory a = _attestation(offerId, o);
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.BTC);
        a.btcPayoutScriptHash = keccak256(abi.encode("btc-script", offerId));

        try ESCROW.approvePaidBtc(offerId, a, new bytes[](0), new bytes32[](0)) {} catch {}
    }

    /// @notice Reserve an approved BTC offer for a bounded-random solver and window.
    function markBtcReserved(uint256 offerSeed, uint256 solverSeed, uint256 windowSeed) external {
        (bytes32 offerId, PuppetTypes.Offer memory o, bool ok) = _pick(offerSeed);
        if (!ok || o.status != uint8(PuppetTypes.OfferStatus.BTC_APPROVED)) return;
        if (block.timestamp >= o.expiry) return;

        uint64 cap = uint64(block.timestamp) + ESCROW.MAX_RESERVATION_WINDOW();
        uint64 ceiling = cap < o.expiry ? cap : o.expiry;
        uint64 window = uint64(_bound(windowSeed, block.timestamp + 1, ceiling));

        try ESCROW.markBtcReserved(offerId, solvers[_bound(solverSeed, 0, 1)], window) {
            reservationsSeen++;
        } catch {}
    }

    /// @notice Return a reserved offer to `BTC_APPROVED` through the authorized hook.
    function clearBtcReservation(uint256 offerSeed) external {
        (bytes32 offerId,, bool ok) = _pick(offerSeed);
        if (!ok) return;
        try ESCROW.clearBtcReservation(offerId) {} catch {}
    }

    /// @notice Release a lapsed reservation permissionlessly.
    function expireBtcReservation(uint256 offerSeed) external {
        (bytes32 offerId,, bool ok) = _pick(offerSeed);
        if (!ok) return;
        try ESCROW.expireBtcReservation(offerId) {
            expiredReservationsSeen++;
        } catch {}
    }

    /// @notice Finalize a reserved BTC offer, reimbursing the recorded solver.
    function finalizeBtcSettlement(uint256 offerSeed) external {
        (bytes32 offerId, PuppetTypes.Offer memory o, bool ok) = _pick(offerSeed);
        if (!ok || o.status != uint8(PuppetTypes.OfferStatus.BTC_RESERVED)) return;

        try ESCROW.finalizeBtcSettlement(offerId, o.reservedSolver, keccak256(abi.encode("payment", offerId))) {
            ghostSettleCount[offerId] += 1;
            ghostTerminalStatus[offerId] = uint8(PuppetTypes.OfferStatus.SETTLED);
            ghostFinalizedViaBtc[offerId] = true;
            ghostDistributed += o.grossWei;
            settlementsSeen++;
            btcFinalizationsSeen++;
        } catch {}
    }

    /// @notice Refund an expired offer.
    function refundExpired(uint256 offerSeed) external {
        (bytes32 offerId, PuppetTypes.Offer memory o, bool ok) = _pick(offerSeed);
        if (!ok) return;

        try ESCROW.refundExpired(offerId) {
            ghostRefundCount[offerId] += 1;
            ghostTerminalStatus[offerId] = uint8(PuppetTypes.OfferStatus.REFUNDED);
            ghostRefunded += o.grossWei;
            refundsSeen++;
        } catch {}
    }

    /// @notice Refund an offer whose Root was taken by a competitor.
    function refundUnfillable(uint256 offerSeed) external {
        (bytes32 offerId, PuppetTypes.Offer memory o, bool ok) = _pick(offerSeed);
        if (!ok) return;

        try ESCROW.refundUnfillable(offerId) {
            ghostRefundCount[offerId] += 1;
            ghostTerminalStatus[offerId] = uint8(PuppetTypes.OfferStatus.REFUNDED);
            ghostRefunded += o.grossWei;
            refundsSeen++;
            unfillableRefundsSeen++;
        } catch {}
    }

    /// @notice Move the clock forward so expiries and reservation windows actually elapse.
    function advanceTime(uint256 seed) external {
        vm.warp(block.timestamp + _bound(seed, 1 minutes, 8 hours));
    }

    /// @notice Flip the pause flag. Refund paths must keep working across every interleaving.
    function togglePause(uint256 seed) external {
        if (_bound(seed, 0, 1) == 0) {
            if (!ESCROW.paused()) ESCROW.pauseSettlement();
        } else {
            if (ESCROW.paused()) ESCROW.unpauseSettlement();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _expiry(uint256 seed) private view returns (uint64) {
        return uint64(
            _bound(
                seed,
                block.timestamp + ESCROW.minimumOfferDuration(),
                block.timestamp + ESCROW.minimumOfferDuration() + 2 days
            )
        );
    }

    function _pick(uint256 seed) private view returns (bytes32 offerId, PuppetTypes.Offer memory o, bool ok) {
        if (offerIds.length == 0) return (bytes32(0), o, false);
        offerId = offerIds[_bound(seed, 0, offerIds.length - 1)];
        o = ESCROW.getOffer(offerId);
        ok = true;
    }

    function _attestation(bytes32 offerId, PuppetTypes.Offer memory o)
        private
        view
        returns (PuppetTypes.OwnershipAttestation memory a)
    {
        a = PuppetTypes.OwnershipAttestation({
            purpose: 0,
            rootTxid: o.rootTxid,
            rootIndex: o.rootIndex,
            contextId: offerId,
            offerTermsHash: o.termsHash,
            currentOutpointHash: keccak256(abi.encode("outpoint", offerId)),
            ownerScriptHash: keccak256(abi.encode("script", offerId)),
            bip322ProofHash: keccak256(abi.encode("bip322", offerId)),
            buyer: o.buyer,
            recipient: o.recipient,
            payoutMode: 0,
            evmPayout: address(0),
            btcPayoutScriptHash: bytes32(0),
            sellerSats: o.sellerSats,
            grossWei: o.grossWei,
            sellerWei: o.sellerWei,
            bitcoinBlockHash: keccak256(abi.encode("block", offerId)),
            bitcoinHeight: 880_000,
            authorizationId: keccak256(abi.encode("auth", offerId)),
            deadline: uint64(block.timestamp) + 1 days,
            attestorEpoch: 1,
            policyVersion: 1
        });
    }
}
