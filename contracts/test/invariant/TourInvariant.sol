// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {HoodPups} from "../../src/HoodPups.sol";
import {TourEngine} from "../../src/TourEngine.sol";
import {IHoodPups} from "../../src/interfaces/IHoodPups.sol";
import {ITourEngine} from "../../src/interfaces/ITourEngine.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";
import {TourHandler} from "./handlers/TourHandler.sol";

/// @title TourInvariantTest
/// @notice Stateful campaign over the HoodPup tour engine.
/// @dev THE PROPERTY THIS FILE EXISTS FOR: `miles` moves only through a finalized tour that was
///      really checked into, and the same (token, season, recipient) tuple is never credited twice.
///      Everything else asserted here supports that claim or protects a token owner while the
///      protocol is under stress.
///
///      HOW THE CREDIT LEDGER IS PROVEN WITHOUT TRUSTING THE ENGINE: the handler recomputes every
///      award from the tour it read immediately BEFORE each successful finalization, and accumulates
///      it into ghost state. The invariants below compare the engine's counters against that
///      independent ledger, so an engine that awarded the wrong amount, awarded twice, or awarded
///      through `cancelInvalidTour` diverges from the ghost rather than agreeing with itself.
///
///      A RAW ERC-721 TRANSFER SCORES NOTHING. The handler transfers tokens between actors
///      constantly, including mid-tour, and no transfer ever appends to the ghost ledger — so if a
///      transfer ever moved `miles`, the comparison breaks.
///
///      HONESTY NOTE: this proves properties of a state machine over wallet addresses. It proves
///      nothing about Bitcoin and nothing about unique humanity. Four distinct actors are four
///      distinct addresses, which is exactly the guarantee the engine claims and no more.
contract TourInvariantTest is StdInvariant, Test {
    HoodPups internal nft;
    TourEngine internal engine;
    TourHandler internal handler;

    /// @dev Stands in for the `TimelockController`. The only party that can unpause or roll seasons.
    address internal admin = makeAddr("timelockAdmin");

    uint64 internal constant MIN_DURATION = 1 days;
    uint64 internal constant MAX_DURATION = 3 days;
    uint64 internal constant CHECK_IN_DELAY = 1 hours;

    function setUp() public {
        vm.warp(1_700_000_000);

        nft = new HoodPups(
            admin, "HoodPups", "HPUP", "https://meta.hoodpups.example/token/", "https://meta.hoodpups.example/c.json"
        );
        engine = new TourEngine(admin, IHoodPups(address(nft)), address(0), MIN_DURATION, MAX_DURATION, CHECK_IN_DELAY);
        handler = new TourHandler(nft, engine, admin);

        bytes32 minterRole = nft.MINTER_ROLE();
        bytes32 tourEngineRole = nft.TOUR_ENGINE_ROLE();
        bytes32 pauserRole = engine.PAUSER_ROLE();
        bytes32 tourAdminRole = engine.TOUR_ADMIN_ROLE();

        vm.startPrank(admin);
        nft.grantRole(minterRole, address(this));
        // The narrow grant under test: the engine may move the user role and nothing else.
        nft.grantRole(tourEngineRole, address(engine));
        // The handler stands in for the guardian. It deliberately does NOT get `DEFAULT_ADMIN_ROLE`
        // or `TOUR_ADMIN_ROLE`, so unpausing and season rolls stay pranked as the timelock and the
        // campaign explores the same authority split production has.
        engine.grantRole(pauserRole, address(handler));
        vm.stopPrank();
        // Silences an unused-variable warning while documenting that the handler never holds it.
        assertFalse(engine.hasRole(tourAdminRole, address(handler)), "handler must not administer parameters");

        for (uint256 i = 0; i < handler.TOKEN_COUNT(); i++) {
            nft.mintRooted(
                handler.actors(i % 4),
                PuppetTypes.RootId({
                    inscriptionTxid: keccak256(abi.encode("invariant-root", i)), inscriptionIndex: uint32(i)
                })
            );
        }

        // Only the handler is fuzzed; letting the campaign call the engine directly would spend the
        // whole budget failing authorization checks instead of exploring the state machine.
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = TourHandler.startTour.selector;
        selectors[1] = TourHandler.checkIn.selector;
        selectors[2] = TourHandler.finalizeTour.selector;
        selectors[3] = TourHandler.cancelInvalidTour.selector;
        selectors[4] = TourHandler.transfer.selector;
        selectors[5] = TourHandler.tamperUser.selector;
        selectors[6] = TourHandler.rollSeason.selector;
        selectors[7] = TourHandler.togglePause.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /*//////////////////////////////////////////////////////////////
                               INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Miles and completed tours match an independently accumulated ledger, exactly.
    /// @dev This is the headline property. Any award that did not come from a finalization the
    ///      handler observed — a transfer, a cancellation, a double credit, a wrong amount — shows
    ///      up here as a mismatch.
    function invariant_MilesComeOnlyFromObservedFinalizations() public view {
        for (uint256 tokenId = 1; tokenId <= handler.TOKEN_COUNT(); tokenId++) {
            assertEq(engine.miles(tokenId), handler.ghostMiles(tokenId), "miles diverged from the ghost ledger");
            assertEq(
                engine.completedTours(tokenId),
                handler.ghostCompletedTours(tokenId),
                "completed tours diverged from the ghost ledger"
            );
            // Miles are the sum of scheduled windows, each at least `MIN_DURATION`, so the two
            // counters can never disagree about whether anything happened at all.
            assertEq(engine.miles(tokenId) > 0, engine.completedTours(tokenId) > 0, "counters disagree");
        }
    }

    /// @notice No (token, season, recipient) tuple is ever credited more than once.
    function invariant_NoTupleIsCreditedTwice() public view {
        assertFalse(handler.tupleCreditedTwice(), "a tuple was credited twice");
    }

    /// @notice Every tuple the campaign saw credited is recorded on chain as used.
    /// @dev The mirror of the flag above: it catches the opposite failure, where a credit was paid
    ///      out but the anti-farm flag was never written, leaving the tuple free to be farmed again.
    function invariant_CreditedTuplesAreRecordedOnChain() public view {
        uint256 count = handler.creditedTupleCount();

        for (uint256 i = 0; i < count; i++) {
            (uint256 tokenId, uint64 season, address recipient) = handler.creditedTupleAt(i);
            assertTrue(
                engine.recipientUsedInSeason(tokenId, season, recipient), "credited tuple was not marked as used"
            );
        }
    }

    /// @notice A tour is never credited without a check-in.
    function invariant_NoCreditWithoutACheckIn() public view {
        assertFalse(handler.creditedWithoutCheckIn(), "a tour with no check-in was credited");
    }

    /// @notice Cancellation never moves a counter.
    function invariant_CancellationNeverAwards() public view {
        assertFalse(handler.cancelAwardedMiles(), "a cancellation moved the miles or tour counter");
    }

    /// @notice A running tour's recipient is not yet marked as used for that tour's season.
    /// @dev The flag is written only by the finalization that consumes it, so a tour that is still
    ///      `ACTIVE` against an already-used tuple would mean `startTour` let a repeat through.
    function invariant_ActiveTourNeverTargetsAUsedRecipient() public view {
        for (uint256 tokenId = 1; tokenId <= handler.TOKEN_COUNT(); tokenId++) {
            ITourEngine.Tour memory tour = engine.tourOf(tokenId);
            if (tour.status != uint8(ITourEngine.TourStatus.ACTIVE)) continue;

            assertFalse(
                engine.recipientUsedInSeason(tokenId, tour.season, tour.user),
                "an active tour targets a recipient already credited this season"
            );
            assertTrue(tour.user != tour.ownerAtStart, "an active tour lent the role to its own owner");
            assertTrue(tour.expires - tour.startedAt >= MIN_DURATION, "an active tour is shorter than the minimum");
            assertTrue(tour.expires - tour.startedAt <= MAX_DURATION, "an active tour is longer than the maximum");
        }
    }

    /// @notice The engine never acquires a token, and every token keeps a real owner.
    /// @dev `TOUR_ENGINE_ROLE` confers the right to move the ERC-4907 user role and NOTHING else. A
    ///      compromised engine must never be able to take a token away from its owner, and this is
    ///      the campaign-wide statement of that.
    function invariant_EngineNeverTakesCustodyOfAToken() public view {
        assertFalse(handler.engineTookOwnership(), "the engine ended up owning a token");

        for (uint256 tokenId = 1; tokenId <= handler.TOKEN_COUNT(); tokenId++) {
            address owner = nft.ownerOf(tokenId);
            assertTrue(owner != address(0), "token with no owner");
            assertTrue(owner != address(engine), "engine holds a token");
        }
    }

    /// @notice Pausing never blocks a check-in, a finalization or a cleanup.
    /// @dev Pausing may stop new tours. It must never strand one that is already running, for the
    ///      same reason a pause elsewhere in this protocol may never block a refund.
    function invariant_PauseNeverBlocksCompletionPaths() public view {
        assertFalse(handler.pauseBlockedCompletion(), "a pause blocked a completion path");
    }

    /// @notice Seasons only ever move forward.
    /// @dev A rewind would re-open a season that has already been played, which is the one way
    ///      governance could hand an already-credited recipient a second slot without touching the
    ///      credit mapping itself.
    function invariant_SeasonNeverRewinds() public view {
        assertFalse(handler.seasonRewound(), "the season went backwards");
        assertGe(engine.currentSeason(), handler.highestSeasonSeen(), "season fell below the observed maximum");
        assertGe(engine.currentSeason(), 1, "season fell below genesis");
    }

    /*//////////////////////////////////////////////////////////////
                            CAMPAIGN SELF-CHECK
    //////////////////////////////////////////////////////////////*/

    /// @notice Drives one full tour deterministically, so the invariants above can never be green
    ///         merely because the handler was silently doing nothing.
    /// @dev A stateful campaign is only as good as its handler. This is the guard against the
    ///      classic failure mode where every fuzzed action reverts and every invariant holds
    ///      vacuously.
    function test_HandlerCanActuallyCompleteATour() public {
        // Actor 0 owns token 1 from `setUp`; recipient seed 1 selects a different actor.
        handler.startTour(0, 0, 1, uint256(MIN_DURATION));
        assertEq(handler.successfulStarts(), 1, "the probe tour did not start");

        handler.checkIn(20 hours, 0);
        assertEq(handler.successfulCheckIns(), 1, "the probe check-in did not land");

        handler.finalizeTour(20 hours, 0);
        assertEq(handler.successfulFinalizations(), 1, "the probe finalization did not land");

        assertEq(engine.miles(1), handler.ghostMiles(1), "probe ledger mismatch");
        assertGt(engine.miles(1), 0, "the probe tour awarded nothing");
        assertFalse(handler.tupleCreditedTwice(), "probe double credit");
        assertFalse(handler.creditedWithoutCheckIn(), "probe credited without a check-in");
    }

    /// @notice Prints the action mix so a campaign that explored nothing is visible rather than green.
    function invariant_CallSummary() public view {
        console.log("startTour        ", handler.callsStart(), "ok:", handler.successfulStarts());
        console.log("checkIn          ", handler.callsCheckIn(), "ok:", handler.successfulCheckIns());
        console.log("finalizeTour     ", handler.callsFinalize(), "ok:", handler.successfulFinalizations());
        console.log("cancelInvalidTour", handler.callsCancel(), "ok:", handler.successfulCancellations());
        console.log("transfer         ", handler.callsTransfer());
        console.log("tamperUser       ", handler.callsTamperUser());
        console.log("rollSeason       ", handler.callsRollSeason());
        console.log("togglePause      ", handler.callsPauseToggle());
        console.log("time advances    ", handler.timeAdvances());
        console.log("credited tuples  ", handler.creditedTupleCount());
        console.log("current season   ", engine.currentSeason());
    }
}
