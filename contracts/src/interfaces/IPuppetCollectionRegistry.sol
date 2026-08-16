// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PuppetTypes} from "../types/PuppetTypes.sol";

/// @title IPuppetCollectionRegistry
/// @notice Immutable membership oracle for the canonical Bitcoin Puppets manifest.
/// @dev Answers exactly one question: "is this inscription in the manifest this deployment
///      committed to?" It knows nothing about who currently owns it.
interface IPuppetCollectionRegistry {
    /// @notice Thrown when a constructor argument that must be non-zero is zero.
    error ZeroValue();
    /// @notice Thrown when `requireMember` is given a proof that does not verify.
    error NotCollectionMember(bytes32 rootKey);

    /// @notice Protocol-wide collection domain separator.
    function collectionId() external view returns (bytes32);

    /// @notice Immutable Merkle root over the canonical manifest.
    function merkleRoot() external view returns (bytes32);

    /// @notice Immutable content hash of the manifest file that produced `merkleRoot`.
    function manifestHash() external view returns (bytes32);

    /// @notice Human-readable manifest version, e.g. "bitcoin-puppets-mainnet-2026-01".
    function manifestVersion() external view returns (string memory);

    /// @notice Number of leaves in the committed manifest, for reproducibility checks.
    function manifestLeafCount() external view returns (uint256);

    /// @notice Canonical protocol key for an inscription.
    function rootKey(PuppetTypes.RootId calldata root) external pure returns (bytes32);

    /// @notice Merkle leaf for an inscription.
    function leafOf(PuppetTypes.RootId calldata root) external pure returns (bytes32);

    /// @notice Non-reverting membership check.
    function isMember(PuppetTypes.RootId calldata root, bytes32[] calldata proof) external view returns (bool);

    /// @notice Reverting membership check used by settlement paths.
    /// @return key The canonical root key, returned so callers avoid recomputing it.
    function requireMember(PuppetTypes.RootId calldata root, bytes32[] calldata proof)
        external
        view
        returns (bytes32 key);
}
