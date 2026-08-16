// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IHoodPups} from "./interfaces/IHoodPups.sol";
import {ITourEngine} from "./interfaces/ITourEngine.sol";

/// @title TourEngine
/// @notice Temporary HoodPup "tours": an owner lends the ERC-4907 user role to another wallet for a
///         bounded window, and a completed tour stamps permanent provenance plus a `miles` counter.
/// @dev WHAT A TOUR IS, AND WHAT IT IS NOT — READ THIS BEFORE READING ANY OTHER LINE:
///      A tour moves the ERC-4907 *user* role and nothing else. No ERC-721 ownership ever transfers,
///      no token is minted, no cash is paid, and finishing a tour confers no claim on protocol
///      revenue of any kind. The reward is a number that goes up and an event an indexer can render
///      as a travel stamp. This contract is not payable and has no function that can move value.
///
///      THE ORIGINAL BITCOIN PUPPET IS NOT INVOLVED AT ALL. Tours act on a HoodPup, the derived
///      Robinhood Chain asset. The inscription never leaves Bitcoin, is never wrapped, bridged,
///      escrowed or custodied, and nothing here reads or asserts any Bitcoin fact.
///
///      THIS CONTRACT DOES NOT PROVE UNIQUE HUMANITY, AND MUST NEVER BE DESCRIBED AS IF IT DID.
///      What it enforces is narrow and purely mechanical: wallet-level uniqueness (one credited
///      recipient address per token per season), a minimum lending duration, and a delayed
///      confirmation from the recipient. A determined operator with many wallets can still satisfy
///      all three. Any stronger Sybil resistance belongs off chain and must be labelled heuristic
///      wherever it is published. The on-chain rules below raise the cost of a trivial farm loop;
///      they do not make one impossible, and the miles counter should be read in that light.
///
///      THE FOUR ANTI-FARM BOUNDARIES, AND WHERE EACH LIVES:
///        1. one credited recipient per token per season   -> `_recipientUsedInSeason`, checked in
///           `startTour` and re-checked in `finalizeTour`;
///        2. a minimum lending duration                    -> `_minimumDuration` in `startTour`;
///        3. a delayed check-in the recipient must send    -> `_checkInDelayOf` in `checkIn`;
///        4. no credit for anything that looks like a sale -> `finalizeTour` refuses when the owner
///           changed mid-tour, and `startTour` refuses when the recipient IS the owner.
///      A raw ERC-721 transfer scores nothing anywhere in this file, by construction: `miles` is only
///      ever written inside `finalizeTour`.
///
///      PAUSING IS NARROW BY DESIGN. `whenNotPaused` appears on `startTour` and nowhere else.
///      Starting a new tour is the only risk-taking action here; `checkIn`, `finalizeTour` and
///      `cancelInvalidTour` all complete or clean up an obligation that already exists, and a pause
///      that could strand an in-flight tour — denying a recipient the stamp they already earned, or
///      locking a token in `ACTIVE` so its owner can never tour it again — would be the tour
///      equivalent of a pause blocking a withdrawal. That is not negotiable in this protocol.
///
///      NON-UPGRADEABLE by construction: no proxy, no initializer, no `delegatecall`, no
///      `selfdestruct`, no `tx.origin`, and no admin path that can seize a token, reduce a balance
///      (there are none), or delete miles that have already been awarded.
contract TourEngine is ITourEngine, AccessControl, Pausable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role permitted to roll the season and to change the duration bounds.
    /// @dev Held by the `TimelockController` in production. Deliberately separate from
    ///      `DEFAULT_ADMIN_ROLE`: parameter administration and role administration are different
    ///      jobs, and this role's entire authority is four `uint64`s that gate FUTURE tours. It
    ///      cannot touch a tour already in flight (see `_checkInDelayOf`), cannot award or remove a
    ///      mile, and cannot mark a recipient used or unused.
    bytes32 public constant TOUR_ADMIN_ROLE = keccak256("TOUR_ADMIN_ROLE");

    /// @notice Role permitted to pause new tours. Cannot unpause.
    /// @dev Held by the guardian multisig, mirroring the asymmetry used across this protocol:
    ///      stopping must be fast, resuming must be deliberate and publicly visible for the full
    ///      timelock delay. A compromised guardian can therefore only ever cost liveness on
    ///      `startTour`; it can never strand a tour that is already running.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              EXTRA ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when `setSeason` is handed a season that does not strictly increase.
    /// @dev Seasons only ever move forward. Rewinding would not un-set any
    ///      `recipientUsedInSeason` flag — those are keyed by the season they were written in — but
    ///      it would let governance replay a season number, which makes the off-chain provenance
    ///      record ambiguous for anyone reconstructing tour history from events. Refusing is free.
    /// @param current The season already stored.
    /// @param proposed The season that was rejected.
    error SeasonMustIncrease(uint64 current, uint64 proposed);

    /// @notice Thrown when `checkIn` arrives after the tour's expiry.
    /// @dev Distinct from `CheckInTooEarly` so a UI can tell the two failure modes apart. The tour
    ///      is still `ACTIVE` in storage at this point — it simply can no longer be checked into,
    ///      and is now cancellable through `cancelInvalidTour`.
    /// @param nowTs Current block timestamp.
    /// @param expires The expiry that has already passed.
    error CheckInAfterExpiry(uint64 nowTs, uint64 expires);

    /*//////////////////////////////////////////////////////////////
                               EXTRA EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, recording the immutable wiring of this engine.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE`, `TOUR_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param hoodPups The collection whose ERC-4907 user role this engine lends.
    /// @param feeRouter Recorded fee router, or the zero address. Tours are free; see `FEE_ROUTER`.
    /// @param firstSeason The season the first tour will be recorded in, always 1.
    event TourEngineInitialized(
        address indexed admin, address indexed hoodPups, address indexed feeRouter, uint64 firstSeason
    );

    /// @notice Emitted when the best-effort clear of a lapsed ERC-4907 record did not go through.
    /// @dev Not a failure of the tour. See `_clearLapsedUserRecord` for why the clear must never be
    ///      allowed to revert a finalization, and why the miles are already safe by the time this
    ///      can be emitted.
    /// @param tokenId Token whose stale user record was left in place.
    event StaleUserRecordNotCleared(uint256 indexed tokenId);

    /*//////////////////////////////////////////////////////////////
                            CANCELLATION REASONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted in `TourCancelled.reason`. Kept as constants so indexers can match on exact
    ///      strings rather than on prose that a later edit might reword.
    string private constant REASON_OWNERSHIP_CHANGED = "OWNERSHIP_CHANGED";
    string private constant REASON_USER_ROLE_TAMPERED = "USER_ROLE_TAMPERED";
    string private constant REASON_NO_CHECK_IN = "NO_CHECK_IN";

    /*//////////////////////////////////////////////////////////////
                             IMMUTABLE WIRING
    //////////////////////////////////////////////////////////////*/

    /// @notice The HoodPups collection this engine lends the user role of.
    /// @dev `immutable`: a repointable collection would let governance aim `TOUR_ENGINE_ROLE` at a
    ///      different contract while the miles ledger below kept accruing against token ids that no
    ///      longer mean anything.
    IHoodPups public immutable HOOD_PUPS;

    /// @dev The same address as `HOOD_PUPS`, typed as ERC-721 for `ownerOf` / approval reads.
    ///      `IHoodPups` deliberately does not redeclare the ERC-721 surface, and that interface file
    ///      is frozen, so the cast is done once here rather than at a dozen call sites.
    IERC721 private immutable _COLLECTION;

    /// @notice Fee router recorded for off-chain discovery. May be the zero address.
    /// @dev TOURS ARE FREE AND NOTHING IN THIS FILE READS THIS ADDRESS. It is `immutable` and
    ///      write-once precisely so that claim is verifiable rather than promised: there is no
    ///      setter, no `payable` function, and no code path that could route a fee through it. It
    ///      exists only so a future *separate deployment* that introduces a paid tour action can be
    ///      wired to the same router that the mint path uses, and so an indexer can see which router
    ///      this engine was deployed alongside. Charging for a tour would require a new contract;
    ///      this one is non-upgradeable.
    address public immutable FEE_ROUTER;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Season tours started from now on are recorded in. Strictly increasing; see `setSeason`.
    uint64 private _currentSeason;

    /// @dev Shortest lendable window, in seconds. Always non-zero.
    uint64 private _minimumDuration;

    /// @dev Longest lendable window, in seconds. Always `>= _minimumDuration`.
    uint64 private _maximumDuration;

    /// @dev How long after a tour starts the recipient must wait before checking in. Always
    ///      strictly less than `_minimumDuration`, so every legal tour has a window in which a
    ///      check-in is actually possible.
    uint64 private _minimumCheckInDelay;

    /// @dev Token id => the one tour slot for that token. A token has at most one tour at a time;
    ///      finalizing or cancelling frees the slot for the next one.
    mapping(uint256 tokenId => Tour tour) private _tours;

    /// @dev Token id => check-in delay SNAPSHOTTED when the tour started.
    ///      WHY THIS EXISTS: the `Tour` struct is a frozen protocol type with nowhere to put it, and
    ///      reading the live `_minimumCheckInDelay` inside `checkIn` would let `TOUR_ADMIN_ROLE`
    ///      raise the delay mid-tour and retroactively void a tour that was legal when it started.
    ///      Governance must not be able to reach into a running tour, so the rule a tour is judged
    ///      by is fixed at its start.
    mapping(uint256 tokenId => uint64 delaySeconds) private _checkInDelayOf;

    /// @dev Token id => cumulative seconds spent on finalized tours. WRITTEN IN EXACTLY ONE PLACE,
    ///      `finalizeTour`, and only ever upwards. No decrement, no reset, no admin override.
    mapping(uint256 tokenId => uint256 milesEarned) private _miles;

    /// @dev Token id => number of finalized tours. Same single-writer rule as `_miles`.
    mapping(uint256 tokenId => uint256 count) private _completedTours;

    /// @dev token id => season => recipient => already credited. The wallet-level uniqueness rule.
    ///      Written only in `finalizeTour`, and never cleared: a season that has passed can never be
    ///      re-entered, because `setSeason` only moves forward.
    mapping(uint256 tokenId => mapping(uint64 season => mapping(address recipient => bool used))) private
        _recipientUsedInSeason;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the tour engine.
    /// @dev `admin` MUST be a `TimelockController` under multisig control in production. Nothing in
    ///      this contract can enforce that, so the deployment script grants the roles to the timelock
    ///      and revokes the deployer in the same batch.
    ///
    ///      `TOUR_ENGINE_ROLE` on `HoodPups` is NOT granted here — this contract cannot grant itself
    ///      a role on another contract, and that grant is a separate, reviewable governance action
    ///      taken after this address is known.
    ///
    ///      The first season is 1 rather than 0 so that "season 0" is an unambiguous "before any
    ///      tour existed" sentinel in the event stream, matching the token-ids-start-at-1 convention
    ///      the collection uses.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE`, `TOUR_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param hoodPups The HoodPups collection.
    /// @param feeRouter Fee router recorded for discovery only. May be zero. Tours are free.
    /// @param minimumDuration_ Shortest lendable window in seconds. Must be non-zero.
    /// @param maximumDuration_ Longest lendable window in seconds. Must be `>= minimumDuration_`.
    /// @param minimumCheckInDelay_ Wait before a check-in counts. Must be `< minimumDuration_`.
    constructor(
        address admin,
        IHoodPups hoodPups,
        address feeRouter,
        uint64 minimumDuration_,
        uint64 maximumDuration_,
        uint64 minimumCheckInDelay_
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (address(hoodPups) == address(0)) revert ZeroAddress();

        HOOD_PUPS = hoodPups;
        _COLLECTION = IERC721(address(hoodPups));
        FEE_ROUTER = feeRouter;

        _setBounds(minimumDuration_, maximumDuration_, minimumCheckInDelay_);

        _currentSeason = 1;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TOUR_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        // Emitted with `previous = 0` so an indexer that only follows `SeasonUpdated` reconstructs
        // the full season history without special-casing genesis.
        emit SeasonUpdated(0, 1);
        emit TourEngineInitialized(admin, address(hoodPups), feeRouter, 1);
    }

    /*//////////////////////////////////////////////////////////////
                                  TOURS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITourEngine
    /// @dev CHECKS-EFFECTS-INTERACTIONS. Every storage write and the `TourStarted` event happen
    ///      before the single external call, `HoodPups.setUser`. That call is to a fixed, immutable,
    ///      protocol-owned contract with no callback into anything, so reentrancy is not actually
    ///      reachable here; `nonReentrant` is applied anyway as defence in depth, because a future
    ///      edit that added a second interaction would otherwise become exploitable silently.
    ///
    ///      AUTHORIZATION mirrors ERC-721 exactly: owner, the single approved address, or an
    ///      operator approved for all. It deliberately does NOT accept `TOUR_ENGINE_ROLE`-style
    ///      protocol authority — nobody but the owner's own approval chain decides that their token
    ///      goes on tour.
    ///
    ///      WHY THE RECIPIENT MAY NOT BE THE OWNER: the owner already holds every right the user
    ///      role can confer, so a self-tour would be a pure farm loop that costs one transaction and
    ///      proves nothing. `HoodPups.setUser` rejects it too; checking here makes the failure legible
    ///      and keeps the rule visible in the file that owns the anti-farm boundaries.
    /// @param tokenId Token to send on tour.
    /// @param user Recipient wallet that receives the temporary user role. Nonzero, not the owner.
    /// @param expires Unix timestamp the tour ends at. Must sit inside the duration bounds.
    function startTour(uint256 tokenId, address user, uint64 expires) external whenNotPaused nonReentrant {
        if (user == address(0)) revert ZeroAddress();

        // Reverts for a token id that was never minted, which is the existence check for free.
        address owner = _COLLECTION.ownerOf(tokenId);
        if (
            msg.sender != owner && _COLLECTION.getApproved(tokenId) != msg.sender
                && !_COLLECTION.isApprovedForAll(owner, msg.sender)
        ) {
            revert NotTokenOwnerNorApproved(msg.sender, tokenId);
        }
        if (user == owner) revert UserCannotBeOwner();

        if (_tours[tokenId].status == uint8(TourStatus.ACTIVE)) revert TourAlreadyActive(tokenId);

        uint64 nowTs = uint64(block.timestamp);
        // Saturating rather than reverting on underflow so a past `expires` reports the real rule it
        // broke (`DurationOutOfBounds`) instead of an arithmetic panic a caller cannot interpret.
        uint64 duration = expires > nowTs ? expires - nowTs : 0;
        if (duration < _minimumDuration || duration > _maximumDuration) {
            revert DurationOutOfBounds(duration, _minimumDuration, _maximumDuration);
        }

        uint64 season = _currentSeason;
        if (_recipientUsedInSeason[tokenId][season][user]) {
            revert RecipientAlreadyCreditedThisSeason(tokenId, season, user);
        }

        _tours[tokenId] = Tour({
            ownerAtStart: owner,
            user: user,
            startedAt: nowTs,
            expires: expires,
            checkedInAt: 0,
            season: season,
            status: uint8(TourStatus.ACTIVE)
        });
        _checkInDelayOf[tokenId] = _minimumCheckInDelay;

        emit TourStarted(tokenId, user, owner, nowTs, expires, season);

        HOOD_PUPS.setUser(tokenId, user, expires);
    }

    /// @inheritdoc ITourEngine
    /// @dev THE CHECK-IN IS WHAT SEPARATES A TOUR FROM A PARKED APPROVAL. Without it, an owner could
    ///      point the user role at a wallet they also control, wait, and collect — with the recipient
    ///      never having to hold a key or pay for a transaction. Requiring the recipient to send this
    ///      themselves, from the address that currently holds the user role, after a delay, is the
    ///      cheapest on-chain evidence that a second live wallet was actually involved. It is
    ///      evidence about wallets, never about people.
    ///
    ///      Both the recorded recipient AND the live ERC-4907 user must be `msg.sender`. The second
    ///      check catches the case where the owner replaced the user role mid-tour: the replacement
    ///      wallet is not the recorded recipient and cannot check in, and the recorded recipient no
    ///      longer holds the role, so neither of them can credit the tour.
    ///
    ///      Not `whenNotPaused`: a pause must never strand a tour that is already running.
    /// @param tokenId Token whose tour is being confirmed.
    function checkIn(uint256 tokenId) external nonReentrant {
        Tour storage tour = _tours[tokenId];
        if (tour.status != uint8(TourStatus.ACTIVE)) revert NoActiveTour(tokenId);

        uint64 nowTs = uint64(block.timestamp);
        if (nowTs > tour.expires) revert CheckInAfterExpiry(nowTs, tour.expires);

        if (msg.sender != tour.user) revert NotTourUser(msg.sender, tour.user);

        address liveUser = HOOD_PUPS.userOf(tokenId);
        if (liveUser != msg.sender) revert UserRoleTampered(tour.user, liveUser);

        if (tour.checkedInAt != 0) revert AlreadyCheckedIn(tokenId);

        // Snapshotted at start, so a later governance change to the bounds cannot move this line.
        uint64 allowedAt = tour.startedAt + _checkInDelayOf[tokenId];
        if (nowTs < allowedAt) revert CheckInTooEarly(nowTs, allowedAt);

        tour.checkedInAt = nowTs;

        emit TourCheckIn(tokenId, msg.sender, nowTs, tour.season);
    }

    /// @inheritdoc ITourEngine
    /// @dev PERMISSIONLESS ON PURPOSE. Finalizing awards a fixed amount to a fixed token and a fixed
    ///      recipient that were both decided at `startTour`, so the caller gains nothing by being the
    ///      caller and cannot steer the outcome. Making anyone able to close a tour means a recipient
    ///      can always claim the stamp they earned, even if the owner has lost interest — the same
    ///      reason refunds elsewhere in this protocol are not gated on a counterparty.
    ///
    ///      WHY EXPIRY IS STRICT (`block.timestamp > expires`): `HoodPups.userOf` treats an
    ///      entitlement expiring at exactly `block.timestamp` as still live, matching the ERC-4907
    ///      reference. Finalizing in that same second would credit a tour the recipient is still on.
    ///
    ///      HOW TAMPERING IS DETECTED AFTER EXPIRY: once the term has elapsed `userOf` returns zero
    ///      for every token, so it can no longer distinguish "our record, now lapsed" from "cleared".
    ///      `userExpires` returns the RAW stored expiry, which survives expiry, so comparing it to
    ///      the tour's own expiry detects both a clear (a transfer wipes it to zero; so does an
    ///      explicit clear) and a replacement with any different term.
    ///
    ///      THE ONE RESIDUAL CASE, STATED HONESTLY: an owner who replaces the user role mid-tour with
    ///      a different wallet and the byte-identical expiry is not detectable here. It is also not
    ///      profitable — the credit still goes to the originally recorded recipient, that recipient
    ///      is still consumed for the season, and the replacement wallet cannot check in — so the
    ///      owner gains nothing they could not get by simply letting the tour run.
    /// @param tokenId Token whose tour is being credited.
    function finalizeTour(uint256 tokenId) external nonReentrant {
        Tour storage tour = _tours[tokenId];
        if (tour.status != uint8(TourStatus.ACTIVE)) revert NoActiveTour(tokenId);

        if (block.timestamp <= uint256(tour.expires)) revert TourNotExpired(tokenId, tour.expires);
        if (tour.checkedInAt == 0) revert NoCheckIn(tokenId);

        address currentOwner = _COLLECTION.ownerOf(tokenId);
        if (currentOwner != tour.ownerAtStart) revert OwnershipChangedDuringTour(tour.ownerAtStart, currentOwner);

        if (uint64(HOOD_PUPS.userExpires(tokenId)) != tour.expires) {
            revert UserRoleTampered(tour.user, HOOD_PUPS.userOf(tokenId));
        }

        address recipient = tour.user;
        uint64 season = tour.season;
        // Re-checked even though `startTour` already refused a used recipient: this mapping is the
        // one rule that stops a repeat loop, and it is cheap to assert it again at the only place
        // that writes it.
        if (_recipientUsedInSeason[tokenId][season][recipient]) {
            revert RecipientAlreadyCreditedThisSeason(tokenId, season, recipient);
        }

        // The SCHEDULED window, not the time until someone happened to call this. A lazy or hostile
        // finalizer must not be able to inflate the award by waiting.
        uint64 durationSeconds = tour.expires - tour.startedAt;

        tour.status = uint8(TourStatus.FINALIZED);
        _recipientUsedInSeason[tokenId][season][recipient] = true;

        // Cannot realistically overflow: each addition is bounded by `_maximumDuration`, and a token
        // would need more finalized tours than there are seconds in the universe to reach 2^256.
        uint256 newMiles = _miles[tokenId] + durationSeconds;
        uint256 completed = _completedTours[tokenId] + 1;
        _miles[tokenId] = newMiles;
        _completedTours[tokenId] = completed;

        // The permanent travel stamp. Emitted before the tidy-up interaction so the provenance
        // record is written even if the clear below cannot go through.
        emit TourFinalized(tokenId, recipient, season, durationSeconds, newMiles, completed);

        _clearLapsedUserRecord(tokenId);
    }

    /// @inheritdoc ITourEngine
    /// @dev PERMISSIONLESS, AND SAFE TO BE: this can only close a tour that is ALREADY impossible to
    ///      credit. If none of the three invalidating conditions holds, it reverts `TourStillValid`,
    ///      so it can never be used to cancel a tour out from under a recipient who is on track.
    ///
    ///      Cancelling awards nothing: no miles, no completed-tour count, and — importantly — no
    ///      entry in `_recipientUsedInSeason`. A tour that failed through no fault of the recipient
    ///      must not burn that recipient's one slot for the season.
    ///
    ///      WHY THE USER-ROLE CLEAR IS CONDITIONAL: when the live ERC-4907 record is no longer the
    ///      one this tour wrote, it belongs to whoever wrote it next — possibly a fresh, legitimate
    ///      rental the owner set up directly. Clearing it would let any passer-by cancel a stale tour
    ///      in order to destroy an unrelated live entitlement. The engine only ever clears a record
    ///      it can prove is its own.
    ///
    ///      Not `whenNotPaused`: cleanup is the path that un-sticks a token, and a pause that blocked
    ///      it would leave the token unable to ever tour again.
    /// @param tokenId Token whose tour is being closed without credit.
    function cancelInvalidTour(uint256 tokenId) external nonReentrant {
        Tour storage tour = _tours[tokenId];
        if (tour.status != uint8(TourStatus.ACTIVE)) revert NoActiveTour(tokenId);

        bool ownershipChanged = _COLLECTION.ownerOf(tokenId) != tour.ownerAtStart;
        bool roleTampered = uint64(HOOD_PUPS.userExpires(tokenId)) != tour.expires;
        bool expiredWithoutCheckIn = block.timestamp > uint256(tour.expires) && tour.checkedInAt == 0;

        if (!ownershipChanged && !roleTampered && !expiredWithoutCheckIn) revert TourStillValid(tokenId);

        tour.status = uint8(TourStatus.CANCELLED);

        // Ordered most-specific-cause first, so the emitted reason names the root cause rather than
        // a symptom: an ERC-721 transfer also wipes the user record, which would otherwise surface
        // as `USER_ROLE_TAMPERED` and mislead anyone reading the history.
        string memory reason = ownershipChanged
            ? REASON_OWNERSHIP_CHANGED
            : (roleTampered ? REASON_USER_ROLE_TAMPERED : REASON_NO_CHECK_IN);
        emit TourCancelled(tokenId, tour.user, reason);

        if (!roleTampered) _clearLapsedUserRecord(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Roll the season forward, which re-opens every recipient for every token.
    /// @dev Tours already in flight are unaffected: each one carries the season it started in and is
    ///      credited against that season, so a roll cannot retroactively move where a running tour
    ///      lands, nor make an already-credited recipient look uncredited.
    ///
    ///      Strictly increasing; see `SeasonMustIncrease`. Timelocked in production, which is what
    ///      makes a season roll a publicly visible scheduled event rather than a silent write that
    ///      resets the anti-farm boundary.
    /// @param newSeason The new season number. Must be greater than the current one.
    function setSeason(uint64 newSeason) external onlyRole(TOUR_ADMIN_ROLE) {
        uint64 previous = _currentSeason;
        if (newSeason <= previous) revert SeasonMustIncrease(previous, newSeason);

        _currentSeason = newSeason;
        emit SeasonUpdated(previous, newSeason);
    }

    /// @notice Replace the duration bounds and the check-in delay.
    /// @dev Applies to tours started AFTER this call only. Running tours keep the check-in delay
    ///      snapshotted at their start, and their duration was already validated when they began, so
    ///      this role can never invalidate a tour that is in flight. That is the whole reason
    ///      `_checkInDelayOf` exists.
    /// @param minimumDuration_ Shortest lendable window in seconds. Must be non-zero.
    /// @param maximumDuration_ Longest lendable window in seconds. Must be `>= minimumDuration_`.
    /// @param minimumCheckInDelay_ Wait before a check-in counts. Must be `< minimumDuration_`.
    function setDurationBounds(uint64 minimumDuration_, uint64 maximumDuration_, uint64 minimumCheckInDelay_)
        external
        onlyRole(TOUR_ADMIN_ROLE)
    {
        _setBounds(minimumDuration_, maximumDuration_, minimumCheckInDelay_);
    }

    /// @notice Stop new tours from starting. Affects nothing else.
    /// @dev Check-in, finalization and cancellation all keep working while paused, by design.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Allow new tours again.
    /// @dev Restricted to `DEFAULT_ADMIN_ROLE` (the timelock) rather than `PAUSER_ROLE`, so a
    ///      compromised fast-reaction key can stop new tours but cannot restart them.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITourEngine
    function currentSeason() external view returns (uint64) {
        return _currentSeason;
    }

    /// @inheritdoc ITourEngine
    function minimumDuration() external view returns (uint64) {
        return _minimumDuration;
    }

    /// @inheritdoc ITourEngine
    function maximumDuration() external view returns (uint64) {
        return _maximumDuration;
    }

    /// @inheritdoc ITourEngine
    function minimumCheckInDelay() external view returns (uint64) {
        return _minimumCheckInDelay;
    }

    /// @inheritdoc ITourEngine
    /// @dev Returns a zeroed struct (`status == NONE`) for a token that has never toured, rather
    ///      than reverting: "has this token ever toured" is a question callers legitimately ask about
    ///      tokens that have not, and `NONE` is an unambiguous answer.
    /// @param tokenId Token to look up.
    /// @return The tour slot, which is the last tour recorded for this token.
    function tourOf(uint256 tokenId) external view returns (Tour memory) {
        return _tours[tokenId];
    }

    /// @inheritdoc ITourEngine
    /// @dev Cumulative seconds this token has spent on finalized tours. Monotonically increasing.
    /// @param tokenId Token to look up.
    /// @return Miles earned so far.
    function miles(uint256 tokenId) external view returns (uint256) {
        return _miles[tokenId];
    }

    /// @inheritdoc ITourEngine
    /// @param tokenId Token to look up.
    /// @return Number of tours this token has finalized.
    function completedTours(uint256 tokenId) external view returns (uint256) {
        return _completedTours[tokenId];
    }

    /// @inheritdoc ITourEngine
    /// @dev True only after a FINALIZED tour. A cancelled tour never consumes a recipient's slot.
    /// @param tokenId Token to look up.
    /// @param season Season to look up.
    /// @param recipient Wallet to look up.
    /// @return True if that wallet has already been credited for that token in that season.
    function recipientUsedInSeason(uint256 tokenId, uint64 season, address recipient) external view returns (bool) {
        return _recipientUsedInSeason[tokenId][season][recipient];
    }

    /// @notice Earliest timestamp at which the current tour for `tokenId` can be checked into.
    /// @dev Uses the delay snapshotted when that tour started, so a UI shows the rule the tour will
    ///      actually be judged by. Returns zero when the token has never toured.
    /// @param tokenId Token to look up.
    /// @return The unlock timestamp for the recorded tour's check-in.
    function checkInUnlocksAt(uint256 tokenId) external view returns (uint64) {
        Tour memory tour = _tours[tokenId];
        if (tour.status == uint8(TourStatus.NONE)) return 0;
        return tour.startedAt + _checkInDelayOf[tokenId];
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Validates and stores the three timing parameters. Shared by the constructor and
    ///      `setDurationBounds` so a deployment can never be configured in a shape governance would
    ///      be refused later.
    ///
    ///      `minimumCheckInDelay_ < minimumDuration_` is STRICT. Were equality allowed, the shortest
    ///      legal tour would have exactly one block in which a check-in was possible, which turns a
    ///      full second of network latency into a lost tour.
    function _setBounds(uint64 minimumDuration_, uint64 maximumDuration_, uint64 minimumCheckInDelay_) private {
        if (minimumDuration_ == 0 || maximumDuration_ < minimumDuration_ || minimumCheckInDelay_ >= minimumDuration_) {
            revert InvalidBounds();
        }

        _minimumDuration = minimumDuration_;
        _maximumDuration = maximumDuration_;
        _minimumCheckInDelay = minimumCheckInDelay_;

        emit DurationBoundsUpdated(minimumDuration_, maximumDuration_, minimumCheckInDelay_);
    }

    /// @dev Clears an ERC-4907 record this engine wrote and has just finished with.
    ///      BEST EFFORT, NEVER FATAL. The call needs `TOUR_ENGINE_ROLE` on `HoodPups`, which is
    ///      governance-granted and therefore governance-revocable. If it were allowed to revert, a
    ///      revoked role would permanently block every finalization — recipients would lose stamps
    ///      they had already earned — and every cancellation, leaving tokens stuck `ACTIVE` and
    ///      untourable forever. Since the record being cleared has already lapsed (`userOf` returns
    ///      zero for it) the clear is cosmetic tidy-up, so trading a revert for an event is the right
    ///      call. It runs last, after every state change and every event, so nothing it could do —
    ///      including reverting — can affect what was already recorded.
    /// @param tokenId Token whose lapsed user record should be cleared.
    function _clearLapsedUserRecord(uint256 tokenId) private {
        try HOOD_PUPS.setUser(tokenId, address(0), 0) {}
        catch {
            emit StaleUserRecordNotCleared(tokenId);
        }
    }
}
