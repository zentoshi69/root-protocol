# CODEX CONTRACT PROMPT 11 — HOODPUP TOUR ENGINE

Build this only after the full settlement core passes all tests and invariants.

Implement temporary HoodPup sending without transferring ERC-721 ownership. Use the ERC-4907 user role already supported by `HoodPups`.

## Contract

Create:

```text
contracts/src/TourEngine.sol
```

Dependencies:

- `HoodPups`
- optional `FeeRouter` for future paid actions, disabled by default
- OpenZeppelin `AccessControl`, `Pausable`, and `ReentrancyGuard`

Non-upgradeable.

## Product rule

Tours generate progression and provenance, not a token or immediate cash reward. The contract must not claim proof of unique humanity. It only enforces wallet-level uniqueness and time/action rules.

## State

Track:

```text
currentSeason
minimumDuration
maximumDuration
minimumCheckInDelay
Tour by tokenId
recipientUsedInSeason[tokenId][season][recipient]
miles[tokenId]
completedTours[tokenId]
```

A Tour should contain:

```text
ownerAtStart
user
startedAt
expires
checkedInAt
season
status
```

## Functions

Implement:

```text
startTour(uint256 tokenId, address user, uint64 expires)
checkIn(uint256 tokenId)
finalizeTour(uint256 tokenId)
cancelInvalidTour(uint256 tokenId)
setSeason(uint64 newSeason)
setDurationBounds(...)
```

## Rules

### Start

- caller is owner or approved operator;
- user nonzero and not owner;
- no active tour;
- duration inside min/max bounds;
- recipient has not already produced a valid tour for this token in the season;
- record `ownerAtStart`;
- call HoodPups `setUser` through `TOUR_ENGINE_ROLE`;
- emit full start event.

### Check-in

- caller is current ERC-4907 user;
- tour active;
- wait at least `minimumCheckInDelay` after start;
- check in once;
- emit event.

### Finalize

- tour expired;
- valid check-in exists;
- current token owner still equals `ownerAtStart`;
- HoodPups user state was not prematurely reset or replaced;
- recipient unused for this token/season;
- mark recipient used;
- increment miles and completed tours;
- clear user if still present;
- emit a permanent event suitable for indexing as a travel stamp.

### Invalid/cancelled tour

If token ownership changed, user was reset, or no valid check-in occurred, allow cleanup without incrementing miles.

## Anti-farm boundaries

On-chain rules can stop simple repeat loops but not prove unique humans. Add:

- one credited recipient per token per season;
- minimum duration and delayed check-in;
- no cash reward;
- no score for raw ERC-721 transfer;
- no score when owner changes during tour;
- no score when recipient equals owner.

Any stronger Sybil score belongs off-chain and must be labeled heuristic.

## Tests

Cover all start/check-in/finalize/cancel paths, transfer during tour, user reset, repeat recipient, season change, duration boundaries, unauthorized caller, pause behavior, and reentrancy.

Invariant: miles increments only after one valid checked-in finalized tour and never more than once for the same token/season/recipient tuple.

Run format, build, tests, fuzzing, and invariants.
