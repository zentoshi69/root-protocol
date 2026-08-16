// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {HoodPups} from "../../../src/HoodPups.sol";
import {TourEngine} from "../../../src/TourEngine.sol";
import {ITourEngine} from "../../../src/interfaces/ITourEngine.sol";

/// @title TourHandler
/// @notice Bounded action surface driving `TourEngine` for the stateful invariant campaign.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      WHY A HANDLER RATHER THAN FUZZING THE ENGINE DIRECTLY: an unguided campaign would spend
///      almost every call bouncing off `NotTokenOwnerNorApproved` or `NotTourUser` and would
///      essentially never produce the one sequence that matters — start, wait, check in, wait,
///      finalize — let alone the adversarial variants of it. Every action here therefore pranks the
///      address that is actually entitled to make the call, and draws tokens and wallets from a
///      deliberately TINY space so the same (token, season, recipient) tuple recurs constantly
///      rather than astronomically rarely. Repeat-credit attempts are the property under test, so
///      they must be frequent.
///
///      EVERY ACTION ADVANCES TIME (see `advancesTime`), rather than time being a separate action.
///      A tour spans days, and the campaign depth is 64 calls; with a dedicated `warp` action the
///      whole budget went on waiting and a run completed at most one tour, which makes "the same
///      tuple is never credited twice" vacuous — you cannot credit twice if you never credit twice
///      in the same run. Folding a bounded jump into every call was measured to raise a run from one
///      completed tour to several, which is what gives the repeat-credit invariants something to
///      bite on.
///
///      GHOST STATE LIVES HERE, NOT IN THE INVARIANT CONTRACT. Forge restores the whole EVM state
///      between invariant runs and the handler's storage is part of that state; a counter kept in
///      the test contract would leak values from one run into the next and produce failures no call
///      sequence can reproduce.
///
///      REVERTS ARE EXPECTED AND FINE (`fail_on_revert = false`). What is NOT fine is a call that
///      should have reverted and did not, so every rule that must never bend is recorded as an
///      explicit boolean flag: a tuple credited twice, miles awarded without a check-in, miles
///      awarded by a cancellation, a pause blocking a completion path, and the engine ever ending up
///      in custody of a token.
///
///      HONESTY NOTE: this campaign proves properties of a state machine over wallet addresses. It
///      proves nothing about people. Distinct actors here are distinct addresses and nothing more,
///      which is exactly the guarantee the engine itself claims.
contract TourHandler is CommonBase, StdUtils {
    /*//////////////////////////////////////////////////////////////
                                 TARGETS
    //////////////////////////////////////////////////////////////*/

    HoodPups public immutable NFT;
    TourEngine public immutable ENGINE;

    /// @dev Holds `DEFAULT_ADMIN_ROLE` and `TOUR_ADMIN_ROLE` on the engine: only it can unpause or
    ///      roll the season, so the campaign explores the same authority split production has.
    address public immutable ADMIN;

    /// @dev Token ids 1..TOKEN_COUNT, minted in the campaign's `setUp`. Deliberately tiny so the
    ///      same (token, season, recipient) tuple is proposed again and again.
    uint256 public constant TOKEN_COUNT = 2;

    /// @dev Owners and tour recipients. Plain addresses with no code, so `_safeMint` never reaches a
    ///      receiver hook — receiver behaviour belongs to the collection's own suite.
    address[4] public actors =
        [address(uint160(0xA11CE)), address(uint160(0xB0B)), address(uint160(0xCA401)), address(uint160(0xDA5E))];

    /*//////////////////////////////////////////////////////////////
                               GHOST STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Miles the campaign believes each token has earned, accumulated independently of the
    ///         engine from the tour it read immediately before each successful finalization.
    mapping(uint256 tokenId => uint256 milesEarned) public ghostMiles;

    /// @notice Finalizations the campaign has observed per token.
    mapping(uint256 tokenId => uint256 count) public ghostCompletedTours;

    /// @notice (token, season, recipient) => number of times the campaign saw that tuple credited.
    mapping(bytes32 tuple => uint256 credits) public ghostTupleCredits;

    /// @dev Every distinct tuple the campaign saw credited, so the invariant can re-read each one
    ///      from the engine rather than trusting the ghost alone.
    bytes32[] private _creditedTupleKeys;
    mapping(bytes32 tuple => CreditedTuple record) private _creditedTuples;

    struct CreditedTuple {
        uint256 tokenId;
        uint64 season;
        address recipient;
    }

    /// @notice Set if the same (token, season, recipient) tuple was ever credited twice.
    bool public tupleCreditedTwice;

    /// @notice Set if a finalization succeeded for a tour with no check-in recorded.
    bool public creditedWithoutCheckIn;

    /// @notice Set if a cancellation ever moved the miles or completed-tour counter.
    bool public cancelAwardedMiles;

    /// @notice Set if a check-in, finalization or cancellation was refused because of the pause.
    bool public pauseBlockedCompletion;

    /// @notice Set if the engine ever ended up owning a token, which it must never be able to do.
    bool public engineTookOwnership;

    /// @notice Highest season the campaign has ever observed.
    uint64 public highestSeasonSeen;

    /// @notice Set if the season ever went backwards, which would let a consumed recipient be
    ///         proposed again inside a season that has already been played.
    bool public seasonRewound;

    /// @notice Per-action call counts, for the campaign summary.
    uint256 public callsStart;
    uint256 public callsCheckIn;
    uint256 public callsFinalize;
    uint256 public callsCancel;
    uint256 public callsTransfer;
    uint256 public callsTamperUser;
    uint256 public callsRollSeason;
    uint256 public callsPauseToggle;

    /// @notice Number of time jumps performed, one per action.
    uint256 public timeAdvances;

    /// @notice Successful outcomes, so a vacuous campaign is visible rather than green.
    uint256 public successfulStarts;
    uint256 public successfulCheckIns;
    uint256 public successfulFinalizations;
    uint256 public successfulCancellations;

    /// @param nft The collection under test.
    /// @param engine The tour engine under test.
    /// @param admin The address holding `DEFAULT_ADMIN_ROLE` and `TOUR_ADMIN_ROLE` on `engine`.
    constructor(HoodPups nft, TourEngine engine, address admin) {
        NFT = nft;
        ENGINE = engine;
        ADMIN = admin;
    }

    /// @dev Advances the clock before every action by a fuzzer-chosen amount. The upper bound is
    ///      shorter than the shortest legal tour, so no single jump can skip a whole tour lifecycle
    ///      and the campaign still has to sequence start, check-in and finalization correctly.
    /// @param seed Fuzzer-supplied jump length.
    modifier advancesTime(uint256 seed) {
        timeAdvances++;
        vm.warp(block.timestamp + bound(seed, 30 minutes, 20 hours));
        _;

        // Sampled after every action, so a rewind is caught in the call that caused it.
        uint64 season = ENGINE.currentSeason();
        if (season < highestSeasonSeen) seasonRewound = true;
        else highestSeasonSeen = season;
    }

    /*//////////////////////////////////////////////////////////////
                                 ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Start a tour, pranked as the token's real owner.
    /// @dev The recipient is drawn from the same tiny actor set the owners come from, so the
    ///      campaign regularly proposes the owner themselves (must revert), a wallet already
    ///      credited this season (must revert), and a fresh wallet (must succeed).
    /// @param timeSeed Time jump taken before the call.
    /// @param tokenSeed Selects the token.
    /// @param userSeed Selects the recipient.
    /// @param durationSeed Selects the requested duration, spanning both sides of both bounds.
    function startTour(uint256 timeSeed, uint256 tokenSeed, uint256 userSeed, uint256 durationSeed)
        external
        advancesTime(timeSeed)
    {
        callsStart++;

        uint256 tokenId = _tokenBiased(tokenSeed, false);
        address owner = NFT.ownerOf(tokenId);
        address user = _actor(userSeed);

        // Deliberately spans illegal values on both sides so the bounds are exercised, not assumed.
        uint64 duration = uint64(bound(durationSeed, 0, uint256(ENGINE.maximumDuration()) + 1 days));
        uint64 expires = uint64(block.timestamp) + duration;

        vm.prank(owner);
        try ENGINE.startTour(tokenId, user, expires) {
            successfulStarts++;
        } catch {
            // Expected for a self-tour, an out-of-bounds duration, an already-active tour, a
            // recipient already credited this season, or a pause.
        }

        _checkEngineNeverOwns(tokenId);
    }

    /// @notice Check in as the tour's recorded recipient.
    /// @param timeSeed Time jump taken before the call.
    /// @param tokenSeed Selects the token.
    function checkIn(uint256 timeSeed, uint256 tokenSeed) external advancesTime(timeSeed) {
        callsCheckIn++;

        uint256 tokenId = _tokenBiased(tokenSeed, true);
        ITourEngine.Tour memory tour = ENGINE.tourOf(tokenId);
        address caller = tour.user == address(0) ? actors[0] : tour.user;

        vm.prank(caller);
        try ENGINE.checkIn(tokenId) {
            successfulCheckIns++;
        } catch (bytes memory err) {
            _recordPauseBlock(err);
        }
    }

    /// @notice Finalize a tour, permissionlessly, and mirror the credit into ghost state.
    /// @dev The tour is READ BEFORE the call so the expected award is computed from the engine's
    ///      pre-state rather than from whatever the engine wrote — otherwise the ghost would simply
    ///      agree with any bug.
    /// @param timeSeed Time jump taken before the call.
    /// @param tokenSeed Selects the token.
    function finalizeTour(uint256 timeSeed, uint256 tokenSeed) external advancesTime(timeSeed) {
        callsFinalize++;

        uint256 tokenId = _tokenBiased(tokenSeed, true);
        ITourEngine.Tour memory tour = ENGINE.tourOf(tokenId);

        try ENGINE.finalizeTour(tokenId) {
            successfulFinalizations++;

            if (tour.checkedInAt == 0) creditedWithoutCheckIn = true;

            ghostMiles[tokenId] += uint256(tour.expires - tour.startedAt);
            ghostCompletedTours[tokenId] += 1;

            bytes32 key = keccak256(abi.encode(tokenId, tour.season, tour.user));
            ghostTupleCredits[key] += 1;
            if (ghostTupleCredits[key] > 1) tupleCreditedTwice = true;
            if (ghostTupleCredits[key] == 1) {
                _creditedTupleKeys.push(key);
                _creditedTuples[key] = CreditedTuple({tokenId: tokenId, season: tour.season, recipient: tour.user});
            }
        } catch (bytes memory err) {
            _recordPauseBlock(err);
        }

        _checkEngineNeverOwns(tokenId);
    }

    /// @notice Cancel a tour that can no longer be credited.
    /// @dev Brackets the call with a counter read: a cancellation that ever awarded anything would be
    ///      the single worst bug in this contract, so it is caught in the call that caused it rather
    ///      than left to the aggregate ghost comparison.
    /// @param timeSeed Time jump taken before the call.
    /// @param tokenSeed Selects the token.
    function cancelInvalidTour(uint256 timeSeed, uint256 tokenSeed) external advancesTime(timeSeed) {
        callsCancel++;

        uint256 tokenId = _tokenBiased(tokenSeed, true);
        uint256 milesBefore = ENGINE.miles(tokenId);
        uint256 completedBefore = ENGINE.completedTours(tokenId);

        try ENGINE.cancelInvalidTour(tokenId) {
            successfulCancellations++;
            if (ENGINE.miles(tokenId) != milesBefore) cancelAwardedMiles = true;
            if (ENGINE.completedTours(tokenId) != completedBefore) cancelAwardedMiles = true;
        } catch (bytes memory err) {
            _recordPauseBlock(err);
        }
    }

    /// @notice Move a token between actors mid-campaign.
    /// @dev The "no score for a raw ERC-721 transfer" boundary only gets tested if transfers really
    ///      happen while tours are running, so this is a first-class action rather than a rarity.
    /// @param timeSeed Time jump taken before the call.
    /// @param tokenSeed Selects the token.
    /// @param toSeed Selects the new owner.
    function transfer(uint256 timeSeed, uint256 tokenSeed, uint256 toSeed) external advancesTime(timeSeed) {
        callsTransfer++;

        uint256 tokenId = _token(tokenSeed);
        address owner = NFT.ownerOf(tokenId);
        address to = _actor(toSeed);

        vm.prank(owner);
        try NFT.transferFrom(owner, to, tokenId) {} catch {}

        _checkEngineNeverOwns(tokenId);
    }

    /// @notice Have the owner rewrite the ERC-4907 record directly, behind the engine's back.
    /// @param timeSeed Time jump taken before the call.
    /// @param tokenSeed Selects the token.
    /// @param userSeed Selects the replacement user.
    /// @param clear Whether to clear the record rather than replace it.
    function tamperUser(uint256 timeSeed, uint256 tokenSeed, uint256 userSeed, bool clear)
        external
        advancesTime(timeSeed)
    {
        callsTamperUser++;

        uint256 tokenId = _token(tokenSeed);
        address owner = NFT.ownerOf(tokenId);
        address user = clear ? address(0) : _actor(userSeed);
        uint64 expires = clear ? 0 : uint64(block.timestamp) + 3 days;

        vm.prank(owner);
        try NFT.setUser(tokenId, user, expires) {} catch {}
    }

    /// @notice Roll the season forward.
    /// @param timeSeed Time jump taken before the call.
    /// @param steps How many seasons to skip, bounded to keep the numbers legible.
    function rollSeason(uint256 timeSeed, uint256 steps) external advancesTime(timeSeed) {
        callsRollSeason++;

        uint64 next = ENGINE.currentSeason() + uint64(bound(steps, 1, 3));
        address admin = ADMIN;

        vm.prank(admin);
        try ENGINE.setSeason(next) {} catch {}
    }

    /// @notice Pause or unpause the engine.
    /// @dev The handler holds `PAUSER_ROLE` and can only stop; resuming is pranked as `ADMIN`,
    ///      preserving production's asymmetry inside the campaign.
    ///
    ///      DELIBERATELY BIASED TOWARDS UNPAUSED (one pause per four calls). An even split leaves the
    ///      engine paused half the campaign, which starves the lifecycle of the starts it needs to
    ///      reach a finalization at all. A quarter is still far more pause churn than any real
    ///      deployment would ever see.
    /// @param timeSeed Time jump taken before the call.
    /// @param seed Selects pause versus unpause.
    function togglePause(uint256 timeSeed, uint256 seed) external advancesTime(timeSeed) {
        callsPauseToggle++;

        if (seed % 4 == 0) {
            try ENGINE.pause() {} catch {}
        } else {
            address admin = ADMIN;
            vm.prank(admin);
            try ENGINE.unpause() {} catch {}
        }
    }

    /*//////////////////////////////////////////////////////////////
                             GHOST ACCESSORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Number of distinct (token, season, recipient) tuples the campaign saw credited.
    function creditedTupleCount() external view returns (uint256) {
        return _creditedTupleKeys.length;
    }

    /// @notice One credited tuple, for the invariant to re-read from the engine.
    /// @param index Position in the credited-tuple list.
    /// @return tokenId The token that was credited.
    /// @return season The season it was credited in.
    /// @return recipient The wallet that was credited.
    function creditedTupleAt(uint256 index) external view returns (uint256 tokenId, uint64 season, address recipient) {
        CreditedTuple memory record = _creditedTuples[_creditedTupleKeys[index]];
        return (record.tokenId, record.season, record.recipient);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Records a violation if a completion path was refused specifically because of the pause.
    ///      Every other revert reason is legitimate here and ignored.
    /// @param err Raw revert data from the failed call.
    function _recordPauseBlock(bytes memory err) private {
        if (err.length >= 4 && bytes4(err) == Pausable.EnforcedPause.selector) pauseBlockedCompletion = true;
    }

    /// @dev The engine holds `TOUR_ENGINE_ROLE`, which confers no transfer authority whatsoever.
    ///      Checking inside the actions catches a violation in the call that caused it.
    /// @param tokenId Token to check.
    function _checkEngineNeverOwns(uint256 tokenId) private {
        if (NFT.ownerOf(tokenId) == address(ENGINE)) engineTookOwnership = true;
    }

    function _token(uint256 seed) private pure returns (uint256) {
        return bound(seed, 1, TOKEN_COUNT);
    }

    /// @dev Token selection biased towards one whose tour is in the state the action needs.
    ///      WHY THIS BIAS IS LEGITIMATE: the fuzzer still chooses when each action fires, which token
    ///      it starts looking from, and every other argument — the handler only slides the starting
    ///      point to a token where the call is not dead on arrival. Without it most check-ins and
    ///      finalizations land on a token with no active tour, and the campaign ends up measuring the
    ///      `NoActiveTour` guard over and over instead of the tour lifecycle.
    /// @param seed The fuzzer's starting point.
    /// @param wantActive True to prefer a token with an ACTIVE tour, false to prefer a free one.
    function _tokenBiased(uint256 seed, bool wantActive) private view returns (uint256) {
        uint256 start = _token(seed);

        for (uint256 i = 0; i < TOKEN_COUNT; i++) {
            uint256 candidate = ((start - 1 + i) % TOKEN_COUNT) + 1;
            bool active = ENGINE.tourOf(candidate).status == uint8(ITourEngine.TourStatus.ACTIVE);
            if (active == wantActive) return candidate;
        }

        return start;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }
}
