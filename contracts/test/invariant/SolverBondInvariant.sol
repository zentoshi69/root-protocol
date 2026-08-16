// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {BitcoinAttestorRegistry} from "../../src/BitcoinAttestorRegistry.sol";
import {BitcoinOwnershipOracle} from "../../src/BitcoinOwnershipOracle.sol";
import {BtcSolverSettlement} from "../../src/BtcSolverSettlement.sol";
import {PayoutVault} from "../../src/PayoutVault.sol";
import {PuppetCollectionRegistry} from "../../src/PuppetCollectionRegistry.sol";
import {IBitcoinAttestorRegistry} from "../../src/interfaces/IBitcoinAttestorRegistry.sol";
import {IBitcoinOwnershipOracle} from "../../src/interfaces/IBitcoinOwnershipOracle.sol";
import {IBtcSolverSettlement} from "../../src/interfaces/IBtcSolverSettlement.sol";
import {IHoodPupOfferEscrow} from "../../src/interfaces/IHoodPupOfferEscrow.sol";
import {IPayoutVault} from "../../src/interfaces/IPayoutVault.sol";
import {IPuppetCollectionRegistry} from "../../src/interfaces/IPuppetCollectionRegistry.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";
import {AttestorSet} from "../helpers/AttestorSet.sol";
import {MockHoodPups} from "../mocks/MockHoodPups.sol";
import {MockOfferEscrow} from "../unit/BtcSolverSettlement.t.sol";
import {SolverBondHandler} from "./handlers/SolverBondHandler.sol";

/// @title SolverBondInvariantTest
/// @notice Stateful campaign over arbitrary interleavings of bonding, settling, expiring, pausing,
///         time travel and forced ETH.
/// @dev THE CLAIMS, in the order they matter:
///
///        1. EVERY WEI OF EVERY BOND IS IN EXACTLY ONE PLACE. At all times, and for every ordering,
///           a posted bond is either the liability of an ACTIVE reservation, or already credited
///           back to its solver, or already credited to the buyer and the protocol as a slash.
///           Never two of those, never none of them, never partly.
///        2. THE CONTRACT IS ALWAYS SOLVENT FOR ITS BONDS. `address(this).balance` covers
///           `totalActiveBondWei` exactly, up to force-sent ETH the campaign injected on purpose.
///        3. NO BTC-MODE MINT WITHOUT EXACTLY ONE CONSUMED UNIQUE PAYMENT OUTPUT. The number of
///           HoodPups minted through this path equals the number of settlements equals the number
///           of distinct consumed Bitcoin output keys, and every one of those keys is still burned
///           in the real oracle.
///        4. A SETTLED RESERVATION IS TERMINAL. Nothing — not a pause, not a re-reservation
///           attempt, not an expiry, not time — ever moves it again.
///        5. THE TWO STATE MACHINES NEVER DISAGREE. The reservation status here and the offer
///           status in the escrow are always the matching pair.
///        6. NO ORDERING EVER REDUCES A CREDITED BALANCE. The campaign has no withdrawal action,
///           so any decrease at all is a bug rather than something to reconcile.
///
///      HONESTY NOTE. The escrow is `MockOfferEscrow`, so nothing here is evidence about
///      `HoodPupOfferEscrow`'s own correctness. The oracle, the attestor registry and the payout
///      vault ARE the production contracts and the signatures ARE real secp256k1 quorums, so claim
///      3 is a genuine statement about the real consumption path. Campaign offers carry
///      `sellerWei == 0` so vault balances move only for bond reasons; see the handler header.
contract SolverBondInvariantTest is StdInvariant, Test {
    BtcSolverSettlement internal settlement;
    MockOfferEscrow internal escrow;
    MockHoodPups internal hoodPups;
    BitcoinOwnershipOracle internal oracle;
    BitcoinAttestorRegistry internal attestorRegistry;
    PuppetCollectionRegistry internal collectionRegistry;
    PayoutVault internal vault;
    AttestorSet internal attestors;
    SolverBondHandler internal handler;

    address internal admin = address(0xAD0111);
    address internal campaignBuyer = address(0xB0FFEE);
    address internal protocolRecipient = address(0x9207);

    uint256 internal constant MIN_BOND = 0.25 ether;
    uint64 internal constant RESERVATION_DURATION = 6 hours;
    uint16 internal constant BUYER_SLASH_BPS = 6500;

    function setUp() public {
        vm.warp(1_760_000_000);

        attestors = new AttestorSet(5, keccak256("HOODPUPS_SOLVER_CAMPAIGN_SEED"));

        collectionRegistry = new PuppetCollectionRegistry(
            keccak256("campaign-merkle-root"), keccak256("campaign-manifest"), "campaign-v1", 8
        );
        attestorRegistry = new BitcoinAttestorRegistry(admin, attestors.sortedAddresses(), 3, 1);
        oracle = new BitcoinOwnershipOracle(
            admin,
            IPuppetCollectionRegistry(address(collectionRegistry)),
            IBitcoinAttestorRegistry(address(attestorRegistry))
        );
        vault = new PayoutVault(admin);
        hoodPups = new MockHoodPups();
        escrow = new MockOfferEscrow(hoodPups, IPayoutVault(address(vault)));

        settlement = new BtcSolverSettlement(
            admin,
            IHoodPupOfferEscrow(address(escrow)),
            IBitcoinOwnershipOracle(address(oracle)),
            IPayoutVault(address(vault)),
            MIN_BOND,
            RESERVATION_DURATION,
            BUYER_SLASH_BPS,
            protocolRecipient
        );
        escrow.setBtcSettlement(address(settlement));

        handler = new SolverBondHandler(
            settlement, escrow, oracle, attestorRegistry, attestors, campaignBuyer, protocolRecipient
        );

        vm.startPrank(admin);
        oracle.grantRole(oracle.PAYMENT_CONSUMER_ROLE(), address(settlement));
        vault.grantRole(vault.CREDITOR_ROLE(), address(settlement));
        vault.grantRole(vault.CREDITOR_ROLE(), address(escrow));
        // The handler is deliberately maximally privileged; see its header for why.
        settlement.grantRole(settlement.PAUSER_ROLE(), address(handler));
        settlement.grantRole(settlement.DEFAULT_ADMIN_ROLE(), address(handler));
        settlement.grantRole(settlement.CONFIG_ADMIN_ROLE(), address(handler));
        vm.stopPrank();

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = SolverBondHandler.createOffer.selector;
        selectors[1] = SolverBondHandler.reserve.selector;
        selectors[2] = SolverBondHandler.settle.selector;
        selectors[3] = SolverBondHandler.expire.selector;
        selectors[4] = SolverBondHandler.warp.selector;
        selectors[5] = SolverBondHandler.togglePause.selector;
        selectors[6] = SolverBondHandler.forceEth.selector;
        selectors[7] = SolverBondHandler.sweepForcedEth.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        // A fuzz call originating FROM one of these would model nothing real.
        excludeSender(address(settlement));
        excludeSender(address(escrow));
        excludeSender(address(vault));
        excludeSender(address(oracle));
        excludeSender(address(hoodPups));
    }

    /*//////////////////////////////////////////////////////////////
                               INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice CLAIM 1. The bond accounting equation the contract enforces internally still holds.
    function invariant_BondBooksBalance() public view {
        assertTrue(settlement.bondBooksBalance(), "bond accounting equation broken");
        assertEq(
            settlement.totalBondsPosted(),
            settlement.totalActiveBondWei() + settlement.totalBondsReturned() + settlement.totalBondsSlashed(),
            "posted != active + returned + slashed"
        );
    }

    /// @notice CLAIM 1. Independently re-derived from the handler's own ghost sums, so a bug that
    ///         corrupted the contract's counters symmetrically would still be caught.
    function invariant_GhostLedgersAgreeWithTheContract() public view {
        assertEq(settlement.totalBondsPosted(), handler.ghostPosted(), "posted ledger drifted");
        assertEq(settlement.totalBondsReturned(), handler.ghostReturned(), "returned ledger drifted");
        assertEq(settlement.totalBondsSlashed(), handler.ghostSlashed(), "slashed ledger drifted");
        assertEq(
            settlement.totalActiveBondWei(),
            handler.ghostPosted() - handler.ghostReturned() - handler.ghostSlashed(),
            "active liability drifted"
        );
    }

    /// @notice CLAIM 1. Every ACTIVE reservation's bond, summed, is exactly the reported liability.
    ///         This is the "exactly one bucket" claim read off the reservations themselves rather
    ///         than off a counter.
    function invariant_ActiveReservationsSumToTheLiability() public view {
        bytes32[] memory ids = handler.offerIds();
        uint256 sum;
        for (uint256 i = 0; i < ids.length; i++) {
            IBtcSolverSettlement.Reservation memory r = settlement.reservationOf(ids[i]);
            if (r.status == uint8(IBtcSolverSettlement.ReservationStatus.ACTIVE)) sum += r.bondWei;
        }
        assertEq(sum, settlement.totalActiveBondWei(), "active reservations do not sum to the liability");
    }

    /// @notice CLAIM 1 and 6. Returned bonds land on solvers; slashed bonds land on the buyer and
    ///         the protocol. Neither bucket ever borrows from the other.
    function invariant_CreditsMatchTheReturnedAndSlashedLedgers() public view {
        address[] memory who = handler.solvers();
        uint256 solverCredits;
        for (uint256 i = 0; i < who.length; i++) {
            solverCredits += vault.claimable(who[i]);
        }
        assertEq(solverCredits, settlement.totalBondsReturned(), "solver credits != returned bonds");

        uint256 slashCredits = vault.claimable(campaignBuyer) + vault.claimable(protocolRecipient);
        assertEq(
            slashCredits,
            settlement.totalBondsSlashed() + handler.ghostForcedSwept(),
            "buyer + protocol credits != slashed bonds plus swept forced eth"
        );
    }

    /// @notice CLAIM 2. The contract always holds at least its bond liability, and the excess is
    ///         exactly the forced ETH the campaign injected minus what it swept back out.
    function invariant_SolventForEveryActiveBond() public view {
        assertGe(address(settlement).balance, settlement.totalActiveBondWei(), "settlement is insolvent for bonds");
        assertEq(
            address(settlement).balance,
            settlement.totalActiveBondWei() + handler.ghostForcedIn() - handler.ghostForcedSwept(),
            "unattributable wei appeared or vanished"
        );
    }

    /// @notice CLAIM 2. The vault the bonds flow into stays solvent for everything it owes.
    function invariant_VaultStaysSolvent() public view {
        assertGe(address(vault).balance, vault.totalLiability(), "vault is insolvent");
    }

    /// @notice CLAIM 3. Every mint through this path is backed by exactly one settlement, and every
    ///         settlement burned exactly one distinct Bitcoin output that is still burned now.
    function invariant_NoMintWithoutOneConsumedUniquePaymentOutput() public view {
        bytes32[] memory keys = handler.consumedOutputKeys();
        assertEq(hoodPups.mintCount(), handler.settleCount(), "mint count != settlement count");
        assertEq(keys.length, handler.settleCount(), "consumed output count != settlement count");

        for (uint256 i = 0; i < keys.length; i++) {
            assertTrue(oracle.isPaymentOutputKeyConsumed(keys[i]), "a settled payment output is not consumed");
            for (uint256 j = i + 1; j < keys.length; j++) {
                assertTrue(keys[i] != keys[j], "one Bitcoin output settled two offers");
            }
        }
    }

    /// @notice CLAIM 4 and 5. A settled reservation is terminal, and the two state machines agree.
    function invariant_ReservationAndOfferStatusesNeverDisagree() public view {
        bytes32[] memory ids = handler.offerIds();
        for (uint256 i = 0; i < ids.length; i++) {
            uint8 rStatus = settlement.reservationOf(ids[i]).status;
            uint8 oStatus = escrow.getOffer(ids[i]).status;

            if (rStatus == uint8(IBtcSolverSettlement.ReservationStatus.ACTIVE)) {
                assertEq(oStatus, uint8(PuppetTypes.OfferStatus.BTC_RESERVED), "active reservation, unreserved offer");
            } else if (rStatus == uint8(IBtcSolverSettlement.ReservationStatus.SETTLED)) {
                assertEq(oStatus, uint8(PuppetTypes.OfferStatus.SETTLED), "settled reservation, unsettled offer");
                assertTrue(handler.ghostEverSettled(ids[i]), "an offer settled without the handler seeing it");
            } else {
                assertEq(oStatus, uint8(PuppetTypes.OfferStatus.BTC_APPROVED), "idle reservation, non-approved offer");
                assertFalse(handler.ghostEverSettled(ids[i]), "a settled reservation left the SETTLED state");
            }
        }
    }

    /// @notice COVERAGE, asserted deterministically rather than as an invariant.
    /// @dev A coverage claim is legitimately false on a shrunk single-call sequence, so making it
    ///      an invariant would produce failures that say nothing about the contract. This drives a
    ///      fixed script instead and proves the handler can reach every interesting state at all:
    ///      reserve, expire, re-reserve after a timeout, and settle.
    function test_HandlerReachesEveryReservationState() public {
        handler.reserve(0, 0, 0);
        assertEq(handler.reserveCount(), 1, "handler cannot reserve");

        handler.warp(type(uint256).max); // bounded to 9 hours, longer than the 6 hour window
        handler.expire(0, 1);
        assertEq(handler.expireCount(), 1, "handler cannot expire");

        handler.reserve(0, 1, 7);
        assertEq(handler.reReserveCount(), 1, "handler cannot re-reserve after a timeout");

        handler.settle(0);
        assertEq(handler.settleCount(), 1, "handler cannot settle");
        assertEq(hoodPups.mintCount(), 1, "handler settlement did not mint");

        assertTrue(settlement.bondBooksBalance(), "books after the scripted run");
    }
}
