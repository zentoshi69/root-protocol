// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PuppetTypes} from "../types/PuppetTypes.sol";

/// @title IBtcSolverSettlement
/// @notice Bonded solvers convert an ETH seller share into an exact native-BTC payment.
/// @dev There is no BTC/ETH price oracle anywhere in this contract, by design. The buyer fixed
///      `sellerSats` and `sellerWei` when the offer was created and the Bitcoin holder signed
///      both. A solver either finds that quote attractive or ignores it; the spread is the
///      market. Removing the oracle removes oracle manipulation, price disputes and slippage
///      arguments from the settlement path entirely.
interface IBtcSolverSettlement {
    /// @notice Lifecycle of one solver reservation.
    enum ReservationStatus {
        NONE,
        ACTIVE,
        SETTLED,
        EXPIRED
    }

    /// @notice Terms snapshotted at reservation time so later governance cannot change them.
    struct Reservation {
        address solver;
        uint256 bondWei;
        uint64 reservedAt;
        uint64 reservationExpiry;
        uint16 buyerSlashBpsSnapshot;
        uint8 status;
    }

    error ZeroAddress();
    error InvalidConfiguration();
    error InsufficientBond(uint256 provided, uint256 required);
    error AlreadyReserved(bytes32 offerId, address solver);
    error NoActiveReservation(bytes32 offerId);
    error ReservationNotExpired(bytes32 offerId, uint64 expiry);
    error ReservationExpired(bytes32 offerId, uint64 expiry);
    error NotReservedSolver(address caller, address solver);
    error PaymentFieldMismatch(string field);
    error OfferNotBtcApproved(bytes32 offerId, uint8 status);
    error RootAlreadyMinted(bytes32 rootKey);

    event Reserved(
        bytes32 indexed offerId, address indexed solver, uint256 bondWei, uint64 reservationExpiry, uint16 buyerSlashBps
    );
    event Settled(
        bytes32 indexed offerId,
        address indexed solver,
        bytes32 indexed paymentDigest,
        bytes32 bitcoinTxid,
        uint32 outputIndex,
        uint64 amountSats,
        bytes32 recipientScriptHash,
        uint256 bondReturned
    );
    event ReservationExpiredAndSlashed(
        bytes32 indexed offerId,
        address indexed solver,
        uint256 bondWei,
        uint256 buyerCompensation,
        uint256 protocolAmount
    );

    /// @notice Minimum bond a solver must post.
    function minimumBondWei() external view returns (uint256);

    /// @notice How long a reservation lasts before anyone may expire it.
    function reservationDuration() external view returns (uint64);

    /// @notice Portion of a slashed bond that compensates the buyer, in basis points.
    function buyerSlashBps() external view returns (uint16);

    /// @notice Where the non-buyer portion of a slashed bond goes.
    function protocolSlashRecipient() external view returns (address);

    /// @notice Current reservation for an offer.
    function reservationOf(bytes32 offerId) external view returns (Reservation memory);

    /// @notice Post a bond and claim the exclusive right to pay this offer's seller in BTC.
    function reserve(bytes32 offerId) external payable;

    /// @notice Prove the exact BTC payment happened, mint the HoodPup and take reimbursement.
    function settle(
        bytes32 offerId,
        PuppetTypes.BitcoinPaymentAttestation calldata attestation,
        bytes[] calldata signatures
    ) external returns (uint256 tokenId);

    /// @notice Permissionless: release a stale reservation and slash its bond.
    function expireReservation(bytes32 offerId) external;
}
