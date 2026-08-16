// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PuppetTypes} from "../types/PuppetTypes.sol";

/// @title IHoodPupOfferEscrow
/// @notice Holds buyer ETH and runs the offer lifecycle from creation to mint or refund.
/// @dev A buyer cannot cancel an open offer early. That is deliberate: a Bitcoin holder may be
///      partway through a cold-wallet signing ceremony that takes minutes or hours, and a
///      cancellable offer would let a buyer bait a signature and then withdraw. Buyers get their
///      ETH back at expiry, or immediately if another offer already minted the Root.
interface IHoodPupOfferEscrow {
    error ZeroAddress();
    error ZeroValue();
    error UnknownOffer(bytes32 offerId);
    error InvalidOfferStatus(bytes32 offerId, uint8 actual, uint8 expected);
    error OfferExpired(bytes32 offerId, uint64 expiry);
    error OfferNotExpired(bytes32 offerId, uint64 expiry);
    error InvalidExpiry(uint64 expiry, uint64 minAllowed, uint64 maxAllowed);
    error RootAlreadyMinted(bytes32 rootKey);
    error RootReservationActive(bytes32 rootKey, bytes32 activeOfferId);
    error RootNotMinted(bytes32 rootKey);
    error SelfCastMustBeZeroValue();
    error SelfCastRecipientMismatch(address caller, address recipient);
    error PaidOfferRequiresValue();
    error BtcOfferRequiresSats();
    error AttestationFieldMismatch(string field);
    error UnexpectedPurpose(uint8 provided, uint8 expected);
    error NotReservedSolver(address provided, address active);
    error DurationBoundsInvalid(uint64 minimum, uint64 maximum);

    event OfferCreated(
        bytes32 indexed offerId,
        bytes32 indexed rootKey,
        address indexed buyer,
        address recipient,
        uint8 kind,
        uint256 grossWei,
        uint256 sellerWei,
        uint64 sellerSats,
        uint64 expiry,
        bytes32 termsHash
    );
    event OwnershipApproved(bytes32 indexed offerId, bytes32 indexed ownershipDigest, uint8 purpose, address evmPayout);
    event BtcOfferApproved(
        bytes32 indexed offerId, bytes32 indexed ownershipDigest, bytes32 btcPayoutScriptHash, uint64 sellerSats
    );
    event BtcReserved(bytes32 indexed offerId, address indexed solver, uint64 reservationExpiry);
    event BtcReservationCleared(bytes32 indexed offerId, address indexed solver);
    event OfferSettled(
        bytes32 indexed offerId,
        bytes32 indexed rootKey,
        uint256 indexed tokenId,
        address recipient,
        address paidTo,
        uint256 grossWei,
        uint8 kind
    );
    event OfferRefunded(bytes32 indexed offerId, address indexed buyer, uint256 amount, bool unfillable);

    /// @notice Full offer view.
    function getOffer(bytes32 offerId) external view returns (PuppetTypes.Offer memory);

    /// @notice Offer holding the Root-wide BTC reservation mutex, or zero when unlocked.
    function activeBtcOfferForRoot(bytes32 rootKey) external view returns (bytes32 offerId);

    /// @notice Sole, permanently bound coordinator for the BTC reservation and bond lifecycle.
    function btcSettlementCoordinator() external view returns (address);

    /// @notice Next offer id `buyer` will produce.
    function nextOfferId(address buyer) external view returns (bytes32);

    /// @notice Per-buyer offer counter.
    function buyerNonce(address buyer) external view returns (uint256);

    /// @notice Recompute an offer's terms hash from explicit fields. Mirrored in the SDK.
    function computeTermsHash(
        bytes32 offerId,
        uint8 kind,
        bytes32 rootKey,
        address buyer,
        address recipient,
        uint256 grossWei,
        uint256 sellerWei,
        uint64 sellerSats,
        uint64 expiry
    ) external view returns (bytes32);

    /// @notice Create a paid offer settled in ETH on Robinhood Chain.
    function createPaidEvmOffer(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 expiry,
        bytes32[] calldata collectionProof
    ) external payable returns (bytes32 offerId);

    /// @notice Create a paid offer settled in exact native BTC through a bonded solver.
    function createPaidBtcOffer(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 sellerSats,
        uint64 expiry,
        bytes32[] calldata collectionProof
    ) external payable returns (bytes32 offerId);

    /// @notice Create a free self-cast for the Bitcoin controller.
    function createSelfCastOffer(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 expiry,
        bytes32[] calldata collectionProof
    ) external returns (bytes32 offerId);

    /// @notice Settle an ETH-payout offer: mint and route funds atomically.
    function settlePaidEvm(
        bytes32 offerId,
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (uint256 tokenId);

    /// @notice Settle a free self-cast: mint only, no money moves.
    function settleSelfCast(
        bytes32 offerId,
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (uint256 tokenId);

    /// @notice Prove ownership for a BTC-payout offer. Does not mint; moves to `BTC_APPROVED`.
    function approvePaidBtc(
        bytes32 offerId,
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external;

    /// @notice Mark an approved BTC offer reserved. Requires `BTC_SETTLEMENT_ROLE`.
    function markBtcReserved(bytes32 offerId, address solver, uint64 reservationExpiry) external;

    /// @notice Return a reserved offer to `BTC_APPROVED`. Requires `BTC_SETTLEMENT_ROLE`.
    function clearBtcReservation(bytes32 offerId) external;

    /// @notice Mint and reimburse the solver. Requires `BTC_SETTLEMENT_ROLE`.
    function finalizeBtcSettlement(bytes32 offerId, address solver, bytes32 paymentDigest)
        external
        returns (uint256 tokenId);

    /// @notice Refund an expired, unsettled offer to the buyer via PayoutVault.
    function refundExpired(bytes32 offerId) external;

    /// @notice Refund immediately when the Root was already minted by a competing offer.
    function refundUnfillable(bytes32 offerId) external;
}
