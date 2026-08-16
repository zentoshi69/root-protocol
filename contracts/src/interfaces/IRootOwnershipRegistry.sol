// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PuppetTypes} from "../types/PuppetTypes.sol";

/// @title IRootOwnershipRegistry
/// @notice Tracks which Bitcoin controller is currently verified for each Root, as ownership epochs.
/// @dev This registry records ATTESTED state, not live Bitcoin state. When Bob sells his Puppet
///      on Bitcoin, the registry keeps naming Bob until a watcher submits a spend attestation.
///      That lag is an unavoidable property of the design and is documented in
///      `docs/TRUST_ASSUMPTIONS.md`. Recurring value accrued during the lag is recoverable
///      because it lands in the Root's pending bucket once the epoch closes.
interface IRootOwnershipRegistry {
    error ZeroAddress();
    error ZeroRootKey();
    error RootAlreadyActive(bytes32 rootKey, uint64 epoch);
    error RootNotActive(bytes32 rootKey);
    error RootMismatch(bytes32 expected, bytes32 provided);
    error OutpointMismatch(bytes32 expected, bytes32 provided);
    error StaleBitcoinHeight(uint64 provided, uint64 current);
    error UnchangedOutpoint(bytes32 outpointHash);
    error InvalidBeneficiary();
    error UnsupportedPurpose(uint8 purpose);

    event RootEpochActivated(
        bytes32 indexed rootKey,
        uint64 indexed epoch,
        address indexed beneficiary,
        bytes32 outpointHash,
        bytes32 ownerScriptHash,
        uint64 bitcoinHeight,
        bytes32 ownershipDigest
    );
    event RootEpochInvalidated(
        bytes32 indexed rootKey,
        uint64 indexed epoch,
        address indexed previousBeneficiary,
        bytes32 spendingTxid,
        uint64 bitcoinHeight
    );
    event RootPendingReleased(bytes32 indexed rootKey, address indexed beneficiary, uint256 amount);

    /// @notice Full current state for a Root.
    function currentState(bytes32 rootKey) external view returns (PuppetTypes.RootState memory);

    /// @notice The address that should receive Root-linked value right now.
    /// @return beneficiary Zero if no epoch was ever activated.
    /// @return active False when the inscription is known to have moved.
    /// @return epoch Current epoch number; zero if never activated.
    function currentBeneficiary(bytes32 rootKey) external view returns (address beneficiary, bool active, uint64 epoch);

    /// @notice True when the recorded owner is currently believed valid.
    function isActive(bytes32 rootKey) external view returns (bool);

    /// @notice Current epoch number for a Root; zero if never activated.
    function epochOf(bytes32 rootKey) external view returns (uint64);

    /// @notice Historical record of one epoch.
    function epochInfo(bytes32 rootKey, uint64 epoch) external view returns (PuppetTypes.RootEpochInfo memory);

    /// @notice Record the first ownership epoch as part of a mint settlement.
    /// @dev Requires `MINT_RECORDER_ROLE`. The caller must already have consumed the attestation
    ///      through the oracle; this function trusts its authorized caller for that, and binds the
    ///      exact facts it is handed.
    function recordMintOwnership(
        bytes32 rootKey,
        address beneficiary,
        bytes32 outpointHash,
        bytes32 ownerScriptHash,
        bytes32 ownershipDigest,
        bytes32 bip322ProofHash,
        bytes32 bitcoinBlockHash,
        uint64 bitcoinHeight
    ) external returns (uint64 epoch);

    /// @notice Permissionless: prove current Bitcoin control and start a new ownership epoch.
    /// @dev Purpose must be `ROOT_BIND`. Releases any pending Root balance to the new beneficiary.
    function bindRootOwner(
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (uint64 epoch, uint256 releasedPending);

    /// @notice Permissionless: prove the recorded inscription outpoint was spent and close the epoch.
    function invalidateRoot(
        PuppetTypes.RootSpendAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external;
}
