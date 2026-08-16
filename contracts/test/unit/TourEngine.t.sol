// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {HoodPups} from "../../src/HoodPups.sol";
import {TourEngine} from "../../src/TourEngine.sol";
import {IHoodPups} from "../../src/interfaces/IHoodPups.sol";
import {ITourEngine} from "../../src/interfaces/ITourEngine.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";

/// @notice A collection stand-in whose `setUser` reenters the engine.
/// @dev TEST-ONLY. This exists because the production wiring has NO reentrancy surface at all:
///      `HoodPups.setUser` is the engine's only external call and it cannot call anything back. To
///      prove the guard actually holds rather than merely being present, the engine is deployed
///      against this hostile collection instead, which is the only way the reentrant path is
///      reachable. It implements just the four functions the engine calls plus the three ERC-721
///      reads it performs; it is not an ERC-721 and must never be treated as one.
contract ReentrantCollection {
    /// @notice Fixed owner of every token id in this stand-in.
    address public immutable TOKEN_OWNER;

    TourEngine public engine;

    /// @dev 0 = behave; 1 = reenter `startTour`; 2 = reenter `finalizeTour`.
    uint8 public mode;

    /// @notice Number of `setUser` calls received, including the clearing one.
    uint256 public setUserCalls;

    address private _user;
    uint64 private _expires;

    constructor(address tokenOwner) {
        TOKEN_OWNER = tokenOwner;
    }

    function wire(TourEngine engine_) external {
        engine = engine_;
    }

    function setMode(uint8 mode_) external {
        mode = mode_;
    }

    function ownerOf(uint256) external view returns (address) {
        return TOKEN_OWNER;
    }

    function getApproved(uint256) external pure returns (address) {
        return address(0);
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    function userOf(uint256) external view returns (address) {
        return uint256(_expires) >= block.timestamp ? _user : address(0);
    }

    function userExpires(uint256) external view returns (uint256) {
        return _expires;
    }

    function setUser(uint256 tokenId, address user, uint64 expires) external {
        setUserCalls++;
        _user = user;
        _expires = expires;

        if (mode == 1) engine.startTour(tokenId, address(uint160(0xBEEF)), uint64(block.timestamp + 2 days));
        if (mode == 2) engine.finalizeTour(tokenId);
    }
}

/// @title TourEngineTest
/// @notice Unit suite for the HoodPup tour engine.
/// @dev WHAT THIS SUITE PROVES, AND WHAT IT CANNOT: it proves the engine's state machine and its
///      four anti-farm boundaries — one credited recipient per token per season, a minimum lending
///      duration, a delayed recipient check-in, and no credit whenever the token changed hands or the
///      recipient was the owner. It does NOT prove, and no test could prove, that distinct recipient
///      addresses belong to distinct people. The engine enforces wallet-level uniqueness only.
///
///      The REAL `HoodPups` is used rather than `MockHoodPups`, because half the properties here are
///      about ERC-721 behaviour the mock does not model: transfers during a tour, approvals and
///      operators as tour starters, and the automatic ERC-4907 wipe that a transfer performs.
contract TourEngineTest is Test {
    /*//////////////////////////////////////////////////////////////
                                FIXTURES
    //////////////////////////////////////////////////////////////*/

    HoodPups internal nft;
    TourEngine internal engine;

    /// @dev Stands in for the `TimelockController` that holds governance in production.
    address internal admin = makeAddr("timelockAdmin");
    /// @dev Stands in for the guardian multisig.
    address internal guardian = makeAddr("guardian");
    /// @dev Stands in for `HoodPupOfferEscrow`, the only holder of `MINTER_ROLE`.
    address internal minter = makeAddr("escrowMinter");
    /// @dev Recorded on the engine for discovery only; tours are free and never touch it.
    address internal feeRouter = makeAddr("feeRouter");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal stranger = makeAddr("stranger");

    uint64 internal constant MIN_DURATION = 1 days;
    uint64 internal constant MAX_DURATION = 30 days;
    uint64 internal constant CHECK_IN_DELAY = 6 hours;

    /// @dev Token minted to `alice` in `setUp`, used by most cases.
    uint256 internal tokenId;

    /// @dev Role ids hoisted out of every `vm.expectRevert`: arguments are evaluated AFTER the
    ///      expectation is armed, so a live `engine.TOUR_ADMIN_ROLE()` inside one would aim the
    ///      expectation at that getter instead of at the call under test.
    bytes32 internal DEFAULT_ADMIN;
    bytes32 internal TOUR_ADMIN;
    bytes32 internal PAUSER;

    function setUp() public {
        // A realistic wall-clock timestamp, so no expiry arithmetic runs against genesis.
        vm.warp(1_700_000_000);

        nft = new HoodPups(
            admin, "HoodPups", "HPUP", "https://meta.hoodpups.example/token/", "https://meta.hoodpups.example/c.json"
        );
        engine = new TourEngine(admin, IHoodPups(address(nft)), feeRouter, MIN_DURATION, MAX_DURATION, CHECK_IN_DELAY);

        DEFAULT_ADMIN = engine.DEFAULT_ADMIN_ROLE();
        TOUR_ADMIN = engine.TOUR_ADMIN_ROLE();
        PAUSER = engine.PAUSER_ROLE();

        vm.startPrank(admin);
        nft.grantRole(nft.MINTER_ROLE(), minter);
        // The narrow grant that lets the engine move the user role without any transfer authority.
        nft.grantRole(nft.TOUR_ENGINE_ROLE(), address(engine));
        engine.grantRole(PAUSER, guardian);
        vm.stopPrank();

        tokenId = _mint(alice, 1);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 salt) internal returns (uint256 id) {
        vm.prank(minter);
        id = nft.mintRooted(
            to,
            PuppetTypes.RootId({
                inscriptionTxid: keccak256(abi.encode("inscription-reveal-txid", salt)), inscriptionIndex: uint32(salt)
            })
        );
    }

    /// @dev Start a tour of `duration` seconds and return its expiry.
    function _start(address starter, uint256 id, address user, uint64 duration) internal returns (uint64 expires) {
        expires = uint64(block.timestamp) + duration;
        vm.prank(starter);
        engine.startTour(id, user, expires);
    }

    /// @dev Full happy path: start, wait out the delay, check in, then jump past expiry.
    function _runTourToExpiry(address owner_, uint256 id, address user, uint64 duration)
        internal
        returns (uint64 expires)
    {
        expires = _start(owner_, id, user, duration);
        vm.warp(block.timestamp + CHECK_IN_DELAY);
        vm.prank(user);
        engine.checkIn(id);
        vm.warp(uint256(expires) + 1);
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    function test_ConstructorWiresImmutablesAndGenesisState() public view {
        assertEq(address(engine.HOOD_PUPS()), address(nft), "collection");
        assertEq(engine.FEE_ROUTER(), feeRouter, "fee router recorded");
        assertEq(engine.currentSeason(), 1, "first season is 1");
        assertEq(engine.minimumDuration(), MIN_DURATION, "min duration");
        assertEq(engine.maximumDuration(), MAX_DURATION, "max duration");
        assertEq(engine.minimumCheckInDelay(), CHECK_IN_DELAY, "check-in delay");

        assertTrue(engine.hasRole(DEFAULT_ADMIN, admin), "admin role");
        assertTrue(engine.hasRole(TOUR_ADMIN, admin), "tour admin role");
        assertTrue(engine.hasRole(PAUSER, admin), "pauser role");
        assertFalse(engine.paused(), "starts unpaused");
    }

    /// @dev Tours are free. Nothing in the engine may be payable, so no fee path can exist.
    function test_EngineRejectsEther() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool ok,) = address(engine).call{value: 1 ether}("");
        assertFalse(ok, "engine must not accept value");
    }

    function test_ConstructorRevertsOnZeroAdmin() public {
        vm.expectRevert(ITourEngine.ZeroAddress.selector);
        new TourEngine(address(0), IHoodPups(address(nft)), feeRouter, MIN_DURATION, MAX_DURATION, CHECK_IN_DELAY);
    }

    function test_ConstructorRevertsOnZeroCollection() public {
        vm.expectRevert(ITourEngine.ZeroAddress.selector);
        new TourEngine(admin, IHoodPups(address(0)), feeRouter, MIN_DURATION, MAX_DURATION, CHECK_IN_DELAY);
    }

    function test_ConstructorRevertsOnInvalidBounds() public {
        vm.expectRevert(ITourEngine.InvalidBounds.selector);
        new TourEngine(admin, IHoodPups(address(nft)), feeRouter, 0, MAX_DURATION, CHECK_IN_DELAY);

        vm.expectRevert(ITourEngine.InvalidBounds.selector);
        new TourEngine(admin, IHoodPups(address(nft)), feeRouter, MAX_DURATION, MIN_DURATION, CHECK_IN_DELAY);

        // Delay equal to the minimum duration would leave exactly one legal check-in instant.
        vm.expectRevert(ITourEngine.InvalidBounds.selector);
        new TourEngine(admin, IHoodPups(address(nft)), feeRouter, MIN_DURATION, MAX_DURATION, MIN_DURATION);
    }

    /*//////////////////////////////////////////////////////////////
                                  START
    //////////////////////////////////////////////////////////////*/

    function test_StartTourRecordsTourAndLendsUserRole() public {
        uint64 expires = uint64(block.timestamp) + 5 days;

        vm.expectEmit(true, true, true, true, address(engine));
        emit ITourEngine.TourStarted(tokenId, bob, alice, uint64(block.timestamp), expires, 1);

        vm.prank(alice);
        engine.startTour(tokenId, bob, expires);

        ITourEngine.Tour memory tour = engine.tourOf(tokenId);
        assertEq(tour.ownerAtStart, alice, "owner snapshot");
        assertEq(tour.user, bob, "recipient");
        assertEq(tour.startedAt, uint64(block.timestamp), "startedAt");
        assertEq(tour.expires, expires, "expires");
        assertEq(tour.checkedInAt, 0, "not checked in yet");
        assertEq(tour.season, 1, "season");
        assertEq(tour.status, uint8(ITourEngine.TourStatus.ACTIVE), "active");

        assertEq(nft.userOf(tokenId), bob, "ERC-4907 user set");
        assertEq(nft.userExpires(tokenId), expires, "ERC-4907 expiry set");
        // The whole point of `TOUR_ENGINE_ROLE`: use rights move, ownership does not.
        assertEq(nft.ownerOf(tokenId), alice, "ownership untouched");
        assertEq(engine.checkInUnlocksAt(tokenId), uint64(block.timestamp) + CHECK_IN_DELAY, "check-in unlock");
    }

    function test_StartTourByApprovedAddress() public {
        vm.prank(alice);
        nft.approve(carol, tokenId);

        _start(carol, tokenId, bob, 2 days);
        assertEq(engine.tourOf(tokenId).ownerAtStart, alice, "owner snapshot is the owner, not the starter");
    }

    function test_StartTourByOperator() public {
        vm.prank(alice);
        nft.setApprovalForAll(carol, true);

        _start(carol, tokenId, bob, 2 days);
        assertEq(nft.userOf(tokenId), bob, "operator may start");
    }

    function test_StartTourRevertsForUnauthorizedCaller() public {
        uint64 expires = uint64(block.timestamp) + 2 days;
        vm.expectRevert(abi.encodeWithSelector(ITourEngine.NotTokenOwnerNorApproved.selector, stranger, tokenId));
        vm.prank(stranger);
        engine.startTour(tokenId, bob, expires);
    }

    function test_StartTourRevertsForZeroRecipient() public {
        uint64 expires = uint64(block.timestamp) + 2 days;
        vm.expectRevert(ITourEngine.ZeroAddress.selector);
        vm.prank(alice);
        engine.startTour(tokenId, address(0), expires);
    }

    /// @dev A self-tour would be a one-transaction farm loop that proves nothing.
    function test_StartTourRevertsWhenRecipientIsOwner() public {
        uint64 expires = uint64(block.timestamp) + 2 days;
        vm.expectRevert(ITourEngine.UserCannotBeOwner.selector);
        vm.prank(alice);
        engine.startTour(tokenId, alice, expires);
    }

    function test_StartTourRevertsWhenTourAlreadyActive() public {
        _start(alice, tokenId, bob, 2 days);

        uint64 expires = uint64(block.timestamp) + 2 days;
        vm.expectRevert(abi.encodeWithSelector(ITourEngine.TourAlreadyActive.selector, tokenId));
        vm.prank(alice);
        engine.startTour(tokenId, carol, expires);
    }

    function test_StartTourRevertsForUnknownToken() public {
        uint64 expires = uint64(block.timestamp) + 2 days;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999)));
        vm.prank(alice);
        engine.startTour(999, bob, expires);
    }

    function test_StartTourRevertsBelowMinimumDuration() public {
        uint64 duration = MIN_DURATION - 1;
        uint64 expires = uint64(block.timestamp) + duration;
        vm.expectRevert(
            abi.encodeWithSelector(ITourEngine.DurationOutOfBounds.selector, duration, MIN_DURATION, MAX_DURATION)
        );
        vm.prank(alice);
        engine.startTour(tokenId, bob, expires);
    }

    function test_StartTourRevertsAboveMaximumDuration() public {
        uint64 duration = MAX_DURATION + 1;
        uint64 expires = uint64(block.timestamp) + duration;
        vm.expectRevert(
            abi.encodeWithSelector(ITourEngine.DurationOutOfBounds.selector, duration, MIN_DURATION, MAX_DURATION)
        );
        vm.prank(alice);
        engine.startTour(tokenId, bob, expires);
    }

    /// @dev A past expiry reports the rule it broke, not an arithmetic panic.
    function test_StartTourRevertsForPastExpiry() public {
        uint64 expires = uint64(block.timestamp) - 1;
        vm.expectRevert(
            abi.encodeWithSelector(ITourEngine.DurationOutOfBounds.selector, uint64(0), MIN_DURATION, MAX_DURATION)
        );
        vm.prank(alice);
        engine.startTour(tokenId, bob, expires);
    }

    function test_StartTourAcceptsExactMinimumBoundary() public {
        _start(alice, tokenId, bob, MIN_DURATION);
        assertEq(engine.tourOf(tokenId).expires, uint64(block.timestamp) + MIN_DURATION, "exact minimum accepted");
    }

    function test_StartTourAcceptsExactMaximumBoundary() public {
        _start(alice, tokenId, bob, MAX_DURATION);
        assertEq(engine.tourOf(tokenId).expires, uint64(block.timestamp) + MAX_DURATION, "exact maximum accepted");
    }

    /*//////////////////////////////////////////////////////////////
                                CHECK-IN
    //////////////////////////////////////////////////////////////*/

    function test_CheckInRecordsTimestamp() public {
        _start(alice, tokenId, bob, 5 days);
        vm.warp(block.timestamp + CHECK_IN_DELAY);

        vm.expectEmit(true, true, true, true, address(engine));
        emit ITourEngine.TourCheckIn(tokenId, bob, uint64(block.timestamp), 1);

        vm.prank(bob);
        engine.checkIn(tokenId);

        assertEq(engine.tourOf(tokenId).checkedInAt, uint64(block.timestamp), "checked in");
    }

    /// @dev The delay boundary is inclusive: `startedAt + delay` is the first legal instant.
    function test_CheckInAtExactUnlockInstantSucceeds() public {
        _start(alice, tokenId, bob, 5 days);
        vm.warp(engine.checkInUnlocksAt(tokenId));

        vm.prank(bob);
        engine.checkIn(tokenId);
        assertGt(engine.tourOf(tokenId).checkedInAt, 0, "check-in accepted at the exact unlock");
    }

    function test_CheckInRevertsOneSecondEarly() public {
        _start(alice, tokenId, bob, 5 days);
        uint64 unlock = engine.checkInUnlocksAt(tokenId);
        vm.warp(uint256(unlock) - 1);

        vm.expectRevert(abi.encodeWithSelector(ITourEngine.CheckInTooEarly.selector, uint64(block.timestamp), unlock));
        vm.prank(bob);
        engine.checkIn(tokenId);
    }

    function test_CheckInRevertsForNonUserCaller() public {
        _start(alice, tokenId, bob, 5 days);
        vm.warp(block.timestamp + CHECK_IN_DELAY);

        vm.expectRevert(abi.encodeWithSelector(ITourEngine.NotTourUser.selector, stranger, bob));
        vm.prank(stranger);
        engine.checkIn(tokenId);

        // Not even the owner may check in on the recipient's behalf: that would erase the only
        // evidence that a second live wallet was involved at all.
        vm.expectRevert(abi.encodeWithSelector(ITourEngine.NotTourUser.selector, alice, bob));
        vm.prank(alice);
        engine.checkIn(tokenId);
    }

    function test_CheckInRevertsTwice() public {
        _start(alice, tokenId, bob, 5 days);
        vm.warp(block.timestamp + CHECK_IN_DELAY);
        vm.prank(bob);
        engine.checkIn(tokenId);

        vm.warp(block.timestamp + 1 hours);
        vm.expectRevert(abi.encodeWithSelector(ITourEngine.AlreadyCheckedIn.selector, tokenId));
        vm.prank(bob);
        engine.checkIn(tokenId);
    }

    function test_CheckInRevertsAfterExpiry() public {
        uint64 expires = _start(alice, tokenId, bob, 2 days);
        vm.warp(uint256(expires) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(TourEngine.CheckInAfterExpiry.selector, uint64(block.timestamp), expires)
        );
        vm.prank(bob);
        engine.checkIn(tokenId);
    }

    function test_CheckInRevertsWithoutActiveTour() public {
        vm.expectRevert(abi.encodeWithSelector(ITourEngine.NoActiveTour.selector, tokenId));
        vm.prank(bob);
        engine.checkIn(tokenId);
    }

    /// @dev The owner swapping the user role mid-tour locks BOTH wallets out of the check-in.
    function test_CheckInRevertsWhenUserRoleReplaced() public {
        uint64 expires = _start(alice, tokenId, bob, 5 days);
        vm.warp(block.timestamp + CHECK_IN_DELAY);

        vm.prank(alice);
        nft.setUser(tokenId, carol, expires);

        vm.expectRevert(abi.encodeWithSelector(ITourEngine.UserRoleTampered.selector, bob, carol));
        vm.prank(bob);
        engine.checkIn(tokenId);

        vm.expectRevert(abi.encodeWithSelector(ITourEngine.NotTourUser.selector, carol, bob));
        vm.prank(carol);
        engine.checkIn(tokenId);
    }

    function test_CheckInRevertsWhenUserRoleCleared() public {
        _start(alice, tokenId, bob, 5 days);
        vm.warp(block.timestamp + CHECK_IN_DELAY);

        vm.prank(alice);
        nft.setUser(tokenId, address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(ITourEngine.UserRoleTampered.selector, bob, address(0)));
        vm.prank(bob);
        engine.checkIn(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                                FINALIZE
    //////////////////////////////////////////////////////////////*/

    function test_FinalizeCreditsMilesAndStampsProvenance() public {
        uint64 duration = 5 days;
        _runTourToExpiry(alice, tokenId, bob, duration);

        vm.expectEmit(true, true, true, true, address(engine));
        emit ITourEngine.TourFinalized(tokenId, bob, 1, duration, duration, 1);

        // Permissionless: a passer-by can close the tour, and gains nothing by doing so.
        vm.prank(stranger);
        engine.finalizeTour(tokenId);

        assertEq(engine.miles(tokenId), duration, "miles credited");
        assertEq(engine.completedTours(tokenId), 1, "completed tours");
        assertTrue(engine.recipientUsedInSeason(tokenId, 1, bob), "recipient consumed for the season");
        assertEq(engine.tourOf(tokenId).status, uint8(ITourEngine.TourStatus.FINALIZED), "finalized");
        assertEq(nft.userExpires(tokenId), 0, "lapsed user record cleared");
        assertEq(nft.ownerOf(tokenId), alice, "ownership never moved");
    }

    /// @dev The award is the SCHEDULED window; a late finalizer cannot inflate it.
    function test_FinalizeAwardIsScheduledDurationNotElapsedTime() public {
        uint64 duration = 3 days;
        _runTourToExpiry(alice, tokenId, bob, duration);
        vm.warp(block.timestamp + 400 days);

        vm.prank(stranger);
        engine.finalizeTour(tokenId);
        assertEq(engine.miles(tokenId), duration, "miles bounded by the scheduled window");
    }

    function test_FinalizeRevertsBeforeExpiry() public {
        uint64 expires = _start(alice, tokenId, bob, 2 days);
        vm.warp(block.timestamp + CHECK_IN_DELAY);
        vm.prank(bob);
        engine.checkIn(tokenId);

        // Exactly at `expires` the ERC-4907 term is still live, so the tour is not over.
        vm.warp(expires);
        vm.expectRevert(abi.encodeWithSelector(ITourEngine.TourNotExpired.selector, tokenId, expires));
        engine.finalizeTour(tokenId);

        vm.warp(uint256(expires) + 1);
        engine.finalizeTour(tokenId);
        assertEq(engine.completedTours(tokenId), 1, "creditable one second later");
    }

    function test_FinalizeRevertsWithoutCheckIn() public {
        uint64 expires = _start(alice, tokenId, bob, 2 days);
        vm.warp(uint256(expires) + 1);

        vm.expectRevert(abi.encodeWithSelector(ITourEngine.NoCheckIn.selector, tokenId));
        engine.finalizeTour(tokenId);
        assertEq(engine.miles(tokenId), 0, "no miles without a check-in");
    }

    /// @dev A raw ERC-721 transfer must never score, and must void the tour it interrupted.
    function test_FinalizeRevertsWhenOwnershipChangedDuringTour() public {
        uint64 expires = _start(alice, tokenId, bob, 5 days);
        vm.warp(block.timestamp + CHECK_IN_DELAY);
        vm.prank(bob);
        engine.checkIn(tokenId);

        vm.prank(alice);
        nft.transferFrom(alice, dave, tokenId);

        vm.warp(uint256(expires) + 1);
        vm.expectRevert(abi.encodeWithSelector(ITourEngine.OwnershipChangedDuringTour.selector, alice, dave));
        engine.finalizeTour(tokenId);
        assertEq(engine.miles(tokenId), 0, "transfer scores nothing");
    }

    /// @dev Even a round trip back to the original owner leaves the ERC-4907 record wiped, which is
    ///      itself disqualifying — the recipient did not hold the role for the whole window.
    function test_FinalizeRevertsAfterRoundTripTransfer() public {
        uint64 expires = _start(alice, tokenId, bob, 5 days);
        vm.warp(block.timestamp + CHECK_IN_DELAY);
        vm.prank(bob);
        engine.checkIn(tokenId);

        vm.prank(alice);
        nft.transferFrom(alice, dave, tokenId);
        vm.prank(dave);
        nft.transferFrom(dave, alice, tokenId);

        vm.warp(uint256(expires) + 1);
        vm.expectRevert(abi.encodeWithSelector(ITourEngine.UserRoleTampered.selector, bob, address(0)));
        engine.finalizeTour(tokenId);
    }

    function test_FinalizeRevertsWhenUserRoleClearedMidTour() public {
        uint64 expires = _start(alice, tokenId, bob, 5 days);
        vm.warp(block.timestamp + CHECK_IN_DELAY);
        vm.prank(bob);
        engine.checkIn(tokenId);

        vm.prank(alice);
        nft.setUser(tokenId, address(0), 0);

        vm.warp(uint256(expires) + 1);
        vm.expectRevert(abi.encodeWithSelector(ITourEngine.UserRoleTampered.selector, bob, address(0)));
        engine.finalizeTour(tokenId);
        assertEq(engine.miles(tokenId), 0, "no miles after a reset");
    }

    function test_FinalizeRevertsWhenUserRoleReplacedMidTour() public {
        uint64 expires = _start(alice, tokenId, bob, 5 days);
        vm.warp(block.timestamp + CHECK_IN_DELAY);
        vm.prank(bob);
        engine.checkIn(tokenId);

        // A different term, which is what makes the swap detectable after expiry.
        vm.prank(alice);
        nft.setUser(tokenId, carol, expires + 1 days);

        vm.warp(uint256(expires) + 2 days);
        vm.expectRevert(abi.encodeWithSelector(ITourEngine.UserRoleTampered.selector, bob, address(0)));
        engine.finalizeTour(tokenId);
    }

    function test_FinalizeRevertsTwice() public {
        _runTourToExpiry(alice, tokenId, bob, 2 days);
        engine.finalizeTour(tokenId);

        vm.expectRevert(abi.encodeWithSelector(ITourEngine.NoActiveTour.selector, tokenId));
        engine.finalizeTour(tokenId);
        assertEq(engine.completedTours(tokenId), 1, "credited exactly once");
    }

    /// @dev A revoked `TOUR_ENGINE_ROLE` must not cost a recipient the stamp they already earned.
    function test_FinalizeStillCreditsWhenTourEngineRoleWasRevoked() public {
        uint64 duration = 2 days;
        _runTourToExpiry(alice, tokenId, bob, duration);

        // Hoisted: arguments are evaluated after `vm.prank` is armed, so an inline getter call
        // would consume the prank and leave the revoke unpranked.
        bytes32 tourEngineRole = nft.TOUR_ENGINE_ROLE();
        vm.prank(admin);
        nft.revokeRole(tourEngineRole, address(engine));

        vm.expectEmit(true, true, true, true, address(engine));
        emit TourEngine.StaleUserRecordNotCleared(tokenId);

        engine.finalizeTour(tokenId);

        assertEq(engine.miles(tokenId), duration, "miles credited regardless");
        assertGt(nft.userExpires(tokenId), 0, "stale record left in place, honestly reported");
    }

    /*//////////////////////////////////////////////////////////////
                        SEASONS AND REPEAT RECIPIENTS
    //////////////////////////////////////////////////////////////*/

    function test_RepeatRecipientInSameSeasonIsRejected() public {
        _runTourToExpiry(alice, tokenId, bob, 2 days);
        engine.finalizeTour(tokenId);

        uint64 expires = uint64(block.timestamp) + 2 days;
        vm.expectRevert(
            abi.encodeWithSelector(ITourEngine.RecipientAlreadyCreditedThisSeason.selector, tokenId, uint64(1), bob)
        );
        vm.prank(alice);
        engine.startTour(tokenId, bob, expires);
    }

    function test_DifferentRecipientInSameSeasonIsAllowed() public {
        uint64 first = 2 days;
        _runTourToExpiry(alice, tokenId, bob, first);
        engine.finalizeTour(tokenId);

        uint64 second = 3 days;
        _runTourToExpiry(alice, tokenId, carol, second);
        engine.finalizeTour(tokenId);

        assertEq(engine.miles(tokenId), uint256(first) + second, "miles accumulate across recipients");
        assertEq(engine.completedTours(tokenId), 2, "two completed tours");
    }

    function test_SeasonRolloverReopensTheSameRecipient() public {
        _runTourToExpiry(alice, tokenId, bob, 2 days);
        engine.finalizeTour(tokenId);

        vm.expectEmit(true, true, true, true, address(engine));
        emit ITourEngine.SeasonUpdated(1, 2);
        vm.prank(admin);
        engine.setSeason(2);

        _runTourToExpiry(alice, tokenId, bob, 2 days);
        engine.finalizeTour(tokenId);

        assertTrue(engine.recipientUsedInSeason(tokenId, 1, bob), "season 1 record kept");
        assertTrue(engine.recipientUsedInSeason(tokenId, 2, bob), "season 2 record written");
        assertEq(engine.completedTours(tokenId), 2, "one tour per season");
    }

    /// @dev A tour is credited against the season it STARTED in, so a mid-tour roll cannot move it.
    function test_TourIsCreditedToTheSeasonItStartedIn() public {
        _runTourToExpiry(alice, tokenId, bob, 2 days);

        vm.prank(admin);
        engine.setSeason(7);

        engine.finalizeTour(tokenId);
        assertTrue(engine.recipientUsedInSeason(tokenId, 1, bob), "credited to the starting season");
        assertFalse(engine.recipientUsedInSeason(tokenId, 7, bob), "not credited to the new season");
    }

    /// @dev The uniqueness rule is per token: the same wallet may tour a different token.
    function test_SameRecipientMayTourADifferentTokenInTheSameSeason() public {
        _runTourToExpiry(alice, tokenId, bob, 2 days);
        engine.finalizeTour(tokenId);

        uint256 second = _mint(carol, 2);
        _runTourToExpiry(carol, second, bob, 2 days);
        engine.finalizeTour(second);

        assertEq(engine.completedTours(second), 1, "per-token bookkeeping");
    }

    /*//////////////////////////////////////////////////////////////
                               CANCELLATION
    //////////////////////////////////////////////////////////////*/

    function test_CancelAfterOwnershipChange() public {
        _start(alice, tokenId, bob, 5 days);
        vm.prank(alice);
        nft.transferFrom(alice, dave, tokenId);

        vm.expectEmit(true, true, true, true, address(engine));
        emit ITourEngine.TourCancelled(tokenId, bob, "OWNERSHIP_CHANGED");

        vm.prank(stranger);
        engine.cancelInvalidTour(tokenId);

        assertEq(engine.tourOf(tokenId).status, uint8(ITourEngine.TourStatus.CANCELLED), "cancelled");
        assertEq(engine.miles(tokenId), 0, "no miles");
        assertEq(engine.completedTours(tokenId), 0, "no completed tour");
        assertFalse(engine.recipientUsedInSeason(tokenId, 1, bob), "recipient slot not burned");
    }

    function test_CancelAfterUserRoleResetLeavesAReplacementRentalIntact() public {
        uint64 expires = _start(alice, tokenId, bob, 5 days);

        // The owner reassigns the role directly. That is their right; it just voids the tour.
        vm.prank(alice);
        nft.setUser(tokenId, carol, expires + 3 days);

        vm.expectEmit(true, true, true, true, address(engine));
        emit ITourEngine.TourCancelled(tokenId, bob, "USER_ROLE_TAMPERED");
        engine.cancelInvalidTour(tokenId);

        // The engine only ever clears a record it can prove is its own, so a passer-by cannot use
        // cancellation to destroy an unrelated live entitlement.
        assertEq(nft.userOf(tokenId), carol, "replacement rental survives cancellation");
    }

    function test_CancelAfterExpiryWithoutCheckIn() public {
        uint64 expires = _start(alice, tokenId, bob, 2 days);
        vm.warp(uint256(expires) + 1);

        vm.expectEmit(true, true, true, true, address(engine));
        emit ITourEngine.TourCancelled(tokenId, bob, "NO_CHECK_IN");
        engine.cancelInvalidTour(tokenId);

        assertEq(nft.userExpires(tokenId), 0, "lapsed record cleared");
        assertEq(engine.miles(tokenId), 0, "no miles");
    }

    function test_CancelRevertsWhileTourIsStillValid() public {
        _start(alice, tokenId, bob, 5 days);

        vm.expectRevert(abi.encodeWithSelector(ITourEngine.TourStillValid.selector, tokenId));
        engine.cancelInvalidTour(tokenId);

        // Checked in and still inside the window: also not cancellable.
        vm.warp(block.timestamp + CHECK_IN_DELAY);
        vm.prank(bob);
        engine.checkIn(tokenId);

        vm.expectRevert(abi.encodeWithSelector(ITourEngine.TourStillValid.selector, tokenId));
        engine.cancelInvalidTour(tokenId);
    }

    /// @dev An expired, checked-in tour is finalizable, not cancellable: nobody may deny a
    ///      recipient the stamp they earned.
    function test_CancelRevertsForACreditableExpiredTour() public {
        _runTourToExpiry(alice, tokenId, bob, 2 days);

        vm.expectRevert(abi.encodeWithSelector(ITourEngine.TourStillValid.selector, tokenId));
        engine.cancelInvalidTour(tokenId);
    }

    function test_CancelRevertsWithoutActiveTour() public {
        vm.expectRevert(abi.encodeWithSelector(ITourEngine.NoActiveTour.selector, tokenId));
        engine.cancelInvalidTour(tokenId);
    }

    function test_CancelledTourFreesTheSlotAndTheRecipient() public {
        uint64 expires = _start(alice, tokenId, bob, 2 days);
        vm.warp(uint256(expires) + 1);
        engine.cancelInvalidTour(tokenId);

        // Same recipient, same season: a failed tour must not cost them their one slot.
        _runTourToExpiry(alice, tokenId, bob, 2 days);
        engine.finalizeTour(tokenId);
        assertEq(engine.completedTours(tokenId), 1, "retry credited");
    }

    /*//////////////////////////////////////////////////////////////
                              ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    function test_SetSeasonRequiresRoleAndMustIncrease() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, TOUR_ADMIN)
        );
        vm.prank(stranger);
        engine.setSeason(2);

        vm.expectRevert(abi.encodeWithSelector(TourEngine.SeasonMustIncrease.selector, uint64(1), uint64(1)));
        vm.prank(admin);
        engine.setSeason(1);

        vm.prank(admin);
        engine.setSeason(9);
        assertEq(engine.currentSeason(), 9, "season rolled");

        vm.expectRevert(abi.encodeWithSelector(TourEngine.SeasonMustIncrease.selector, uint64(9), uint64(8)));
        vm.prank(admin);
        engine.setSeason(8);
    }

    function test_SetDurationBoundsRequiresRoleAndValidShape() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, TOUR_ADMIN)
        );
        vm.prank(stranger);
        engine.setDurationBounds(1 hours, 2 days, 30 minutes);

        vm.expectRevert(ITourEngine.InvalidBounds.selector);
        vm.prank(admin);
        engine.setDurationBounds(0, 2 days, 0);

        vm.expectRevert(ITourEngine.InvalidBounds.selector);
        vm.prank(admin);
        engine.setDurationBounds(2 days, 1 days, 1 hours);

        vm.expectRevert(ITourEngine.InvalidBounds.selector);
        vm.prank(admin);
        engine.setDurationBounds(2 days, 4 days, 2 days);

        vm.expectEmit(true, true, true, true, address(engine));
        emit ITourEngine.DurationBoundsUpdated(2 hours, 4 days, 1 hours);
        vm.prank(admin);
        engine.setDurationBounds(2 hours, 4 days, 1 hours);

        assertEq(engine.minimumDuration(), 2 hours, "min");
        assertEq(engine.maximumDuration(), 4 days, "max");
        assertEq(engine.minimumCheckInDelay(), 1 hours, "delay");

        // The new floor is live for the next tour.
        _start(alice, tokenId, bob, 3 hours);
        assertEq(engine.tourOf(tokenId).status, uint8(ITourEngine.TourStatus.ACTIVE), "shorter tour now legal");
    }

    /// @dev Governance must not be able to reach into a tour that is already running.
    function test_RaisingTheCheckInDelayCannotVoidARunningTour() public {
        _start(alice, tokenId, bob, 5 days);
        uint64 unlock = engine.checkInUnlocksAt(tokenId);

        vm.prank(admin);
        engine.setDurationBounds(10 days, 30 days, 9 days);

        assertEq(engine.checkInUnlocksAt(tokenId), unlock, "snapshotted delay is unchanged");

        vm.warp(unlock);
        vm.prank(bob);
        engine.checkIn(tokenId);
        assertGt(engine.tourOf(tokenId).checkedInAt, 0, "running tour still checkable under its own rule");
    }

    /*//////////////////////////////////////////////////////////////
                                 PAUSING
    //////////////////////////////////////////////////////////////*/

    function test_PauseBlocksNewToursOnly() public {
        uint64 expires = _start(alice, tokenId, bob, 5 days);

        vm.prank(guardian);
        engine.pause();

        uint256 second = _mint(carol, 2);
        uint64 newExpires = uint64(block.timestamp) + 2 days;
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(carol);
        engine.startTour(second, bob, newExpires);

        // Everything that completes an in-flight tour keeps working while paused.
        vm.warp(block.timestamp + CHECK_IN_DELAY);
        vm.prank(bob);
        engine.checkIn(tokenId);

        vm.warp(uint256(expires) + 1);
        engine.finalizeTour(tokenId);
        assertEq(engine.completedTours(tokenId), 1, "finalize works while paused");
    }

    function test_PauseNeverBlocksCancellation() public {
        uint64 expires = _start(alice, tokenId, bob, 2 days);

        vm.prank(guardian);
        engine.pause();

        vm.warp(uint256(expires) + 1);
        engine.cancelInvalidTour(tokenId);
        assertEq(engine.tourOf(tokenId).status, uint8(ITourEngine.TourStatus.CANCELLED), "cleanup works while paused");
    }

    function test_PauserCannotUnpause() public {
        vm.prank(guardian);
        engine.pause();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, guardian, DEFAULT_ADMIN)
        );
        vm.prank(guardian);
        engine.unpause();

        vm.prank(admin);
        engine.unpause();
        assertFalse(engine.paused(), "timelock may resume");
    }

    function test_PauseRequiresPauserRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, PAUSER)
        );
        vm.prank(stranger);
        engine.pause();
    }

    /*//////////////////////////////////////////////////////////////
                                REENTRANCY
    //////////////////////////////////////////////////////////////*/

    /// @dev Proves the guard, not merely its presence: the engine is deployed against a hostile
    ///      collection whose `setUser` calls straight back into `startTour`.
    function test_ReentrantStartTourIsBlocked() public {
        ReentrantCollection hostile = new ReentrantCollection(alice);
        TourEngine hostileEngine =
            new TourEngine(admin, IHoodPups(address(hostile)), feeRouter, MIN_DURATION, MAX_DURATION, CHECK_IN_DELAY);
        hostile.wire(hostileEngine);
        hostile.setMode(1);

        uint64 expires = uint64(block.timestamp) + 2 days;
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(alice);
        hostileEngine.startTour(1, bob, expires);
    }

    /// @dev The clearing call at the end of `finalizeTour` is the last thing that runs and is
    ///      best-effort, so a reentrant collection cannot double-credit and cannot undo the credit.
    function test_ReentrantFinalizeCannotDoubleCredit() public {
        ReentrantCollection hostile = new ReentrantCollection(alice);
        TourEngine hostileEngine =
            new TourEngine(admin, IHoodPups(address(hostile)), feeRouter, MIN_DURATION, MAX_DURATION, CHECK_IN_DELAY);
        hostile.wire(hostileEngine);

        uint64 duration = 2 days;
        uint64 expires = uint64(block.timestamp) + duration;
        vm.prank(alice);
        hostileEngine.startTour(1, bob, expires);

        vm.warp(block.timestamp + CHECK_IN_DELAY);
        vm.prank(bob);
        hostileEngine.checkIn(1);

        vm.warp(uint256(expires) + 1);
        hostile.setMode(2);

        vm.expectEmit(true, true, true, true, address(hostileEngine));
        emit TourEngine.StaleUserRecordNotCleared(1);
        hostileEngine.finalizeTour(1);

        assertEq(hostileEngine.miles(1), duration, "credited exactly once");
        assertEq(hostileEngine.completedTours(1), 1, "one completed tour");
    }

    /*//////////////////////////////////////////////////////////////
                                  FUZZ
    //////////////////////////////////////////////////////////////*/

    /// @notice Only durations inside the bounds may start a tour, at every point in the range.
    function testFuzz_DurationBoundsAreEnforced(uint64 duration) public {
        duration = uint64(bound(duration, 0, uint256(MAX_DURATION) * 2));
        uint64 expires = uint64(block.timestamp) + duration;

        bool legal = duration >= MIN_DURATION && duration <= MAX_DURATION;
        if (!legal) {
            vm.expectRevert(
                abi.encodeWithSelector(ITourEngine.DurationOutOfBounds.selector, duration, MIN_DURATION, MAX_DURATION)
            );
        }
        vm.prank(alice);
        engine.startTour(tokenId, bob, expires);

        assertEq(
            engine.tourOf(tokenId).status,
            legal ? uint8(ITourEngine.TourStatus.ACTIVE) : uint8(ITourEngine.TourStatus.NONE),
            "tour exists exactly when the duration was legal"
        );
    }

    /// @notice A check-in is impossible before the snapshotted delay and possible from it onwards.
    function testFuzz_CheckInDelayIsEnforced(uint64 offset) public {
        uint64 duration = 10 days;
        _start(alice, tokenId, bob, duration);

        uint64 startedAt = uint64(block.timestamp);
        offset = uint64(bound(offset, 0, duration));
        vm.warp(uint256(startedAt) + offset);

        bool early = offset < CHECK_IN_DELAY;
        if (early) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITourEngine.CheckInTooEarly.selector, uint64(block.timestamp), startedAt + CHECK_IN_DELAY
                )
            );
        }
        vm.prank(bob);
        engine.checkIn(tokenId);

        assertEq(engine.tourOf(tokenId).checkedInAt != 0, !early, "check-in accepted exactly after the delay");
    }

    /// @notice Miles always equal the scheduled window, whoever finalizes and however late.
    function testFuzz_MilesEqualScheduledDuration(uint64 duration, uint64 lateness, address finalizer) public {
        duration = uint64(bound(duration, MIN_DURATION, MAX_DURATION));
        lateness = uint64(bound(lateness, 1, 365 days));
        vm.assume(finalizer != address(0));

        uint64 expires = _start(alice, tokenId, bob, duration);
        vm.warp(block.timestamp + CHECK_IN_DELAY);
        vm.prank(bob);
        engine.checkIn(tokenId);

        vm.warp(uint256(expires) + lateness);
        vm.prank(finalizer);
        engine.finalizeTour(tokenId);

        assertEq(engine.miles(tokenId), duration, "miles are the scheduled duration");
        assertEq(engine.completedTours(tokenId), 1, "one credit");
    }

    /// @notice Whatever the recipient address, it is consumed for exactly one tour per season.
    function testFuzz_RecipientIsSingleUsePerSeason(address recipient) public {
        vm.assume(recipient != address(0) && recipient != alice);
        vm.assume(recipient.code.length == 0);

        _runTourToExpiry(alice, tokenId, recipient, MIN_DURATION);
        engine.finalizeTour(tokenId);
        assertTrue(engine.recipientUsedInSeason(tokenId, 1, recipient), "consumed");

        uint64 expires = uint64(block.timestamp) + MIN_DURATION;
        vm.expectRevert(
            abi.encodeWithSelector(
                ITourEngine.RecipientAlreadyCreditedThisSeason.selector, tokenId, uint64(1), recipient
            )
        );
        vm.prank(alice);
        engine.startTour(tokenId, recipient, expires);

        vm.prank(admin);
        engine.setSeason(2);

        // The next season reopens them, and only them: the season-1 record stays written forever.
        _runTourToExpiry(alice, tokenId, recipient, MIN_DURATION);
        engine.finalizeTour(tokenId);
        assertEq(engine.completedTours(tokenId), 2, "one credit per season");
    }
}
