// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {HoodPupOfferEscrow} from "../../src/HoodPupOfferEscrow.sol";
import {IHoodPupOfferEscrow} from "../../src/interfaces/IHoodPupOfferEscrow.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";

import {EscrowFixture} from "../unit/HoodPupOfferEscrow.t.sol";

/// @title HoodPupOfferEscrowFuzz
/// @notice Property-based coverage of the escrow, against the SAME full real-contract fixture the
///         unit suite uses (see `EscrowFixture` for why nothing here is mocked).
/// @dev Each test states one property that must hold for every input in a range, rather than for
///      the hand-picked values a unit test can reach. Where a property is about money, it is
///      asserted against `PayoutVault`'s real accounting, not against a recomputed expectation, so
///      a bug that corrupted both the escrow and the expectation cannot hide.
contract HoodPupOfferEscrowFuzzTest is EscrowFixture {
    /*//////////////////////////////////////////////////////////////
                        CREATION AND THE 50/25/25 SPLIT
    //////////////////////////////////////////////////////////////*/

    /// @notice For any price, the stored split is exactly the router's split and conserves gross.
    /// @dev The stored amounts are what the offer promises the seller and the treasuries. If they
    ///      could ever differ from what the router will actually pay, the offer book would be
    ///      lying to buyers.
    function testFuzz_StoredSplitAlwaysMatchesTheRouterAndConservesGross(uint128 price) public {
        price = uint128(bound(price, 1, 5000 ether));
        vm.deal(buyer, uint256(price) + 1 ether);

        bytes32 offerId = _createEvm(buyer, 0, price, recipient);
        PuppetTypes.Offer memory o = escrow.getOffer(offerId);

        (uint256 seller, uint256 puppet, uint256 protocol) = router.quote(price);
        assertEq(o.sellerWei, seller, "seller share");
        assertEq(o.treasuryWei, puppet, "puppet treasury share");
        assertEq(o.protocolWei, protocol, "protocol share");
        assertEq(o.sellerWei + o.treasuryWei + o.protocolWei, o.grossWei, "conservation");
        assertLe(o.sellerWei, uint256(price) / 2, "the seller never exceeds 50%");
        assertLe(o.treasuryWei, uint256(price) / 4, "the puppet treasury never exceeds 25%");
    }

    /// @notice Whatever the price, settlement distributes exactly the escrow and keeps nothing.
    /// @dev Includes the sub-4-wei prices where a share legitimately rounds to zero, which is the
    ///      exact input range that breaks a naive three-entry batch credit.
    function testFuzz_SettlementDistributesExactlyWhatWasEscrowed(uint128 price) public {
        price = uint128(bound(price, 1, 5000 ether));
        vm.deal(buyer, uint256(price) + 1 ether);

        bytes32 offerId = _createEvm(buyer, 0, price, recipient);
        _settleEvm(offerId, 0);

        assertEq(vault.totalLiability(), price, "every escrowed wei became a vault liability");
        assertEq(
            vault.claimable(sellerPayout) + vault.claimable(puppetTreasury) + vault.claimable(protocolTreasury),
            price,
            "and it is held by exactly the three intended parties"
        );
        assertEq(address(escrow).balance, 0, "escrow retains nothing");
        assertEq(escrow.lockedEscrowWei(), 0, "accounting cleared");
    }

    /// @notice Whatever the price, a refund returns exactly the escrow to exactly the buyer.
    function testFuzz_RefundReturnsExactlyTheEscrowToTheBuyer(uint128 price, uint64 delay) public {
        price = uint128(bound(price, 1, 5000 ether));
        vm.deal(buyer, uint256(price) + 1 ether);

        bytes32 offerId = _createEvm(buyer, 0, price, recipient);
        uint64 expiry = escrow.getOffer(offerId).expiry;
        vm.warp(uint256(expiry) + 1 + bound(delay, 0, 365 days));

        escrow.refundExpired(offerId);

        assertEq(vault.claimable(buyer), price, "buyer made whole");
        assertEq(vault.totalLiability(), price, "and nobody else was credited a wei");
        assertEq(address(escrow).balance, 0, "escrow retains nothing");
    }

    /// @notice Offer ids are unique across every buyer and every nonce.
    /// @dev Ids are the attestation `contextId`. A collision would let one quorum settle two
    ///      offers, so injectivity is a security property, not a convenience.
    function testFuzz_OfferIdsAreInjectiveOverBuyerAndNonce(address a, uint96 nonceA, address b, uint96 nonceB)
        public
        view
    {
        bytes32 idA = PuppetHashing.offerId(block.chainid, address(escrow), a, nonceA);
        bytes32 idB = PuppetHashing.offerId(block.chainid, address(escrow), b, nonceB);
        if (a == b && nonceA == nonceB) {
            assertEq(idA, idB, "same input, same id");
        } else {
            assertTrue(idA != idB, "different input, different id");
        }
    }

    /// @notice Only expiries strictly inside the configured window are ever accepted.
    function testFuzz_ExpiryWindowIsEnforcedExactly(uint64 expiry) public {
        uint64 minAllowed = uint64(block.timestamp) + MIN_DURATION;
        uint64 maxAllowed = uint64(block.timestamp) + MAX_DURATION;
        expiry = uint64(bound(expiry, 0, uint256(maxAllowed) + 365 days));

        bytes32[] memory p = _proof(0);
        if (expiry >= minAllowed && expiry <= maxAllowed) {
            vm.prank(buyer);
            bytes32 offerId = escrow.createPaidEvmOffer{value: PRICE}(roots[0], recipient, expiry, p);
            assertEq(escrow.getOffer(offerId).expiry, expiry, "accepted inside the window");
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(IHoodPupOfferEscrow.InvalidExpiry.selector, expiry, minAllowed, maxAllowed)
            );
            vm.prank(buyer);
            escrow.createPaidEvmOffer{value: PRICE}(roots[0], recipient, expiry, p);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         THE TIME PARTITION
    //////////////////////////////////////////////////////////////*/

    /// @notice At every instant an offer is settleable XOR refundable — never both, never neither.
    /// @dev This is the property that makes "the buyer's ETH is never stuck and never double
    ///      spent" true. It is asserted by actually attempting both operations at a fuzzed
    ///      timestamp and requiring exactly one of them to succeed.
    function testFuzz_SettleableAndRefundableNeverOverlapOrLeaveAGap(uint64 offsetSeed) public {
        bytes32 offerId = _createEvm(0);
        uint64 expiry = escrow.getOffer(offerId).expiry;
        uint256 target = bound(offsetSeed, block.timestamp, uint256(expiry) + 3 days);
        vm.warp(target);

        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);

        uint256 snapshot = vm.snapshotState();
        (bool settled,) = address(escrow).call(abi.encodeCall(IHoodPupOfferEscrow.settlePaidEvm, (offerId, a, sigs, p)));
        vm.revertToState(snapshot);
        (bool refunded,) = address(escrow).call(abi.encodeCall(IHoodPupOfferEscrow.refundExpired, (offerId)));
        vm.revertToState(snapshot);

        assertTrue(settled != refunded, "exactly one of settle / refund is legal at any instant");
        if (target <= expiry) {
            assertTrue(settled, "live through the expiry second");
        } else {
            assertTrue(refunded, "refundable strictly after it");
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ATTESTATION FIELD BINDING
    //////////////////////////////////////////////////////////////*/

    /// @notice No fuzzed payout address other than the signed one is ever credited.
    /// @dev The seller share follows `attestation.evmPayout` and nothing else — not the caller, not
    ///      the buyer, not the recipient, not any address the fuzzer can name.
    function testFuzz_OnlyTheSignedPayoutAddressIsEverCredited(address payout, address bystander) public {
        vm.assume(payout != address(0));
        vm.assume(payout != puppetTreasury && payout != protocolTreasury);
        vm.assume(bystander != payout && bystander != puppetTreasury && bystander != protocolTreasury);

        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, payout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        vm.prank(relayer);
        escrow.settlePaidEvm(offerId, a, sigs, p);

        assertEq(vault.claimable(payout), PRICE / 2, "the signed address, and only it, got the seller share");
        assertEq(vault.claimable(bystander), 0, "no bystander was credited");
    }

    /// @notice A quorum signed for one offer can never settle a different offer.
    /// @dev The `contextId` binding, exercised over fuzzed pairs of live offers rather than one
    ///      hand-picked pair.
    function testFuzz_AnAttestationNeverCrossesOfferBoundaries(uint8 aIndex, uint8 bIndex) public {
        uint256 i = bound(aIndex, 0, 4);
        uint256 j = bound(bIndex, 0, 4);
        vm.assume(i != j);

        bytes32 first = _createEvm(buyer, i, PRICE, recipient);
        bytes32 second = _createEvm(otherBuyer, j, PRICE, recipient);

        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(first, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(j);

        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.AttestationFieldMismatch.selector, "contextId"));
        escrow.settlePaidEvm(second, a, sigs, p);
    }

    /// @notice A sub-threshold quorum is rejected for every size below the registry's threshold,
    ///         and accepted for every size at or above it.
    function testFuzz_ThresholdIsRespectedExactly(uint8 signerCount) public {
        uint256 n = bound(signerCount, 0, 5);
        uint8 threshold = attestorRegistry.threshold();

        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _signN(a, n);
        bytes32[] memory p = _proof(0);

        if (n >= threshold) {
            escrow.settlePaidEvm(offerId, a, sigs, p);
            assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.SETTLED), "quorum met");
        } else {
            vm.expectRevert();
            escrow.settlePaidEvm(offerId, a, sigs, p);
            assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.OPEN), "quorum short, nothing changed");
        }
    }

    /*//////////////////////////////////////////////////////////////
                        AUTHORIZATION BOUNDARIES
    //////////////////////////////////////////////////////////////*/

    /// @notice No address without `BTC_SETTLEMENT_ROLE` can drive any BTC hook.
    function testFuzz_TheBtcHooksAreClosedToEveryoneElse(address caller) public {
        vm.assume(caller != btcSettlement);
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        uint64 window = uint64(block.timestamp) + 2 hours;

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, roleBtcSettlement)
        );
        vm.prank(caller);
        escrow.markBtcReserved(offerId, solver, window);

        _reserve(offerId, 2 hours);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, roleBtcSettlement)
        );
        vm.prank(caller);
        escrow.finalizeBtcSettlement(offerId, solver, keccak256("payment"));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, roleBtcSettlement)
        );
        vm.prank(caller);
        escrow.clearBtcReservation(offerId);
    }

    /// @notice Only the exact reserved solver is ever reimbursed, whoever the fuzzer proposes.
    function testFuzz_OnlyTheReservedSolverIsEverReimbursed(address proposed) public {
        vm.assume(proposed != solver);
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        _reserve(offerId, 2 hours);

        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.NotReservedSolver.selector, proposed, solver));
        vm.prank(btcSettlement);
        escrow.finalizeBtcSettlement(offerId, proposed, keccak256("payment"));

        assertEq(vault.claimable(proposed), 0, "nobody but the reserved solver is ever paid");
    }

    /// @notice A reservation can never outlive the offer, or the escrow's 24-hour ceiling.
    /// @dev The bound that makes "a buyer's escrow can never be frozen indefinitely" true. Any
    ///      accepted window must satisfy both caps; any rejected one must violate at least one.
    function testFuzz_ReservationWindowIsAlwaysBounded(uint64 requested) public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);

        uint64 offerExpiry = escrow.getOffer(offerId).expiry;
        uint64 cap = uint64(block.timestamp) + escrow.MAX_RESERVATION_WINDOW();
        uint64 ceiling = cap < offerExpiry ? cap : offerExpiry;
        requested = uint64(bound(requested, 0, uint256(offerExpiry) + 30 days));

        vm.prank(btcSettlement);
        if (requested > block.timestamp && requested <= ceiling) {
            escrow.markBtcReserved(offerId, solver, requested);
            uint64 stored = escrow.getOffer(offerId).reservationExpiry;
            assertEq(stored, requested, "stored verbatim, never silently clamped");
            assertLe(stored, offerExpiry, "never outlives the offer");
            assertLe(uint256(stored), block.timestamp + escrow.MAX_RESERVATION_WINDOW(), "never exceeds the ceiling");
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    HoodPupOfferEscrow.ReservationWindowInvalid.selector, requested, uint64(block.timestamp), ceiling
                )
            );
            escrow.markBtcReserved(offerId, solver, requested);
        }
    }

    /// @notice However long a reserved offer is left alone, the buyer can always get out.
    /// @dev Drives the worst realistic combination: the solver contract's role is revoked AND the
    ///      escrow is paused, then time passes by a fuzzed amount.
    function testFuzz_AReservedEscrowIsNeverPermanentlyTrapped(uint64 window, uint64 extraDelay) public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        uint64 offerExpiry = escrow.getOffer(offerId).expiry;
        uint64 cap = uint64(block.timestamp) + escrow.MAX_RESERVATION_WINDOW();
        uint64 ceiling = cap < offerExpiry ? cap : offerExpiry;
        uint64 chosen = uint64(bound(window, block.timestamp + 1, ceiling));
        _reserveAt(offerId, chosen);

        vm.prank(admin);
        escrow.revokeRole(roleBtcSettlement, btcSettlement);
        vm.prank(guardian);
        escrow.pauseSettlement();

        vm.warp(uint256(offerExpiry) + 1 + bound(extraDelay, 0, 400 days));

        escrow.expireBtcReservation(offerId);
        escrow.refundExpired(offerId);

        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.REFUNDED), "always escapable");
        assertEq(vault.claimable(buyer), PRICE, "buyer made whole");
    }

    /*//////////////////////////////////////////////////////////////
                             ROOT UNIQUENESS
    //////////////////////////////////////////////////////////////*/

    /// @notice However many offers chase a Root and in whatever order they resolve, it mints once.
    function testFuzz_OneRootMintsOnceAcrossAnyNumberOfCompetingOffers(uint8 countSeed, uint8 winnerSeed) public {
        uint256 count = bound(countSeed, 2, 6);
        uint256 winner = bound(winnerSeed, 0, count - 1);

        bytes32[] memory ids = new bytes32[](count);
        uint256 deposited;
        for (uint256 i = 0; i < count; i++) {
            uint256 price = (i + 1) * 0.5 ether;
            deposited += price;
            ids[i] = _createEvm(i % 2 == 0 ? buyer : otherBuyer, 0, price, recipient);
        }
        assertEq(escrow.lockedEscrowWei(), deposited, "all escrows held");

        _settleEvm(ids[winner], 0);
        assertEq(nft.nextTokenId(), 2, "exactly one HoodPup exists");

        for (uint256 i = 0; i < count; i++) {
            if (i == winner) continue;
            escrow.refundUnfillable(ids[i]);
        }

        assertEq(nft.nextTokenId(), 2, "still exactly one HoodPup");
        assertEq(escrow.lockedEscrowWei(), 0, "nothing left locked");
        assertEq(address(escrow).balance, 0, "escrow drained");
        assertEq(vault.totalLiability(), deposited, "every deposited wei is refunded or distributed");
    }

    /*//////////////////////////////////////////////////////////////
                              STRAY VALUE
    //////////////////////////////////////////////////////////////*/

    /// @notice Forced ETH of any size never becomes escrow and never blocks a settlement.
    function testFuzz_ForcedEthIsInertAtEverySize(uint128 forced) public {
        forced = uint128(bound(forced, 1, 10_000 ether));
        bytes32 offerId = _createEvm(0);
        vm.deal(address(escrow), address(escrow).balance + forced);

        assertEq(escrow.lockedEscrowWei(), PRICE, "not counted as escrow");
        _settleEvm(offerId, 0);

        assertEq(vault.totalLiability(), PRICE, "only the real escrow was distributed");
        assertEq(address(escrow).balance, forced, "the forced ETH is stranded and unclaimable");
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _reserveAt(bytes32 offerId, uint64 at) private {
        vm.prank(btcSettlement);
        escrow.markBtcReserved(offerId, solver, at);
    }
}
