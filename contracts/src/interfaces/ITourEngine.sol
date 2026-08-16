// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ITourEngine
/// @notice Temporary HoodPup "tours" using the ERC-4907 user role. No ownership ever transfers.
/// @dev Tours produce provenance and a `miles` counter. They produce no token, no cash and no
///      claim on protocol revenue. On-chain rules enforce wallet-level uniqueness only; this
///      contract makes no claim to prove unique humanity, and any stronger Sybil score belongs
///      off chain and must be labelled heuristic.
interface ITourEngine {
    enum TourStatus {
        NONE,
        ACTIVE,
        FINALIZED,
        CANCELLED
    }

    struct Tour {
        address ownerAtStart;
        address user;
        uint64 startedAt;
        uint64 expires;
        uint64 checkedInAt;
        uint64 season;
        uint8 status;
    }

    error ZeroAddress();
    error TourAlreadyActive(uint256 tokenId);
    error NoActiveTour(uint256 tokenId);
    error NotTokenOwnerNorApproved(address caller, uint256 tokenId);
    error UserCannotBeOwner();
    error RecipientAlreadyCreditedThisSeason(uint256 tokenId, uint64 season, address recipient);
    error DurationOutOfBounds(uint64 duration, uint64 minimum, uint64 maximum);
    error NotTourUser(address caller, address user);
    error CheckInTooEarly(uint64 nowTs, uint64 allowedAt);
    error AlreadyCheckedIn(uint256 tokenId);
    error TourNotExpired(uint256 tokenId, uint64 expires);
    error TourStillValid(uint256 tokenId);
    error NoCheckIn(uint256 tokenId);
    error OwnershipChangedDuringTour(address ownerAtStart, address currentOwner);
    error UserRoleTampered(address expected, address actual);
    error InvalidBounds();

    event TourStarted(
        uint256 indexed tokenId,
        address indexed user,
        address indexed ownerAtStart,
        uint64 startedAt,
        uint64 expires,
        uint64 season
    );
    event TourCheckIn(uint256 indexed tokenId, address indexed user, uint64 checkedInAt, uint64 season);
    event TourFinalized(
        uint256 indexed tokenId,
        address indexed user,
        uint64 season,
        uint64 durationSeconds,
        uint256 newMiles,
        uint256 completedTours
    );
    event TourCancelled(uint256 indexed tokenId, address indexed user, string reason);
    event SeasonUpdated(uint64 previous, uint64 next);
    event DurationBoundsUpdated(uint64 minimumDuration, uint64 maximumDuration, uint64 minimumCheckInDelay);

    function currentSeason() external view returns (uint64);
    function minimumDuration() external view returns (uint64);
    function maximumDuration() external view returns (uint64);
    function minimumCheckInDelay() external view returns (uint64);
    function tourOf(uint256 tokenId) external view returns (Tour memory);
    function miles(uint256 tokenId) external view returns (uint256);
    function completedTours(uint256 tokenId) external view returns (uint256);
    function recipientUsedInSeason(uint256 tokenId, uint64 season, address recipient) external view returns (bool);

    /// @notice Lend a HoodPup's user role until `expires`. Owner or approved operator only.
    function startTour(uint256 tokenId, address user, uint64 expires) external;

    /// @notice The current user confirms they hold the role. Required for the tour to count.
    function checkIn(uint256 tokenId) external;

    /// @notice After expiry, credit a valid tour: increment miles and stamp provenance.
    function finalizeTour(uint256 tokenId) external;

    /// @notice Clean up a tour that can no longer be credited, without incrementing miles.
    function cancelInvalidTour(uint256 tokenId) external;
}
