// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IBitcoinAttestorRegistry
/// @notice Membership, quorum threshold, epoch and policy version for the fixed five-member Bitcoin verifier set.
/// @dev Any membership or threshold change bumps `attestorEpoch`, which instantly invalidates
///      every in-flight attestation signature. That is intentional: a rotating set must never
///      leave a window in which a removed operator still counts toward quorum.
interface IBitcoinAttestorRegistry {
    error ZeroAddress();
    error DuplicateAttestor(address attestor);
    error UnknownAttestor(address attestor);
    error AttestorCountOutOfRange(uint256 count);
    error ThresholdOutOfRange(uint8 threshold, uint256 count);
    error ZeroPolicyVersion();

    event AttestorAdded(address indexed attestor, uint64 previousEpoch, uint64 newEpoch);
    event AttestorRemoved(address indexed attestor, uint64 previousEpoch, uint64 newEpoch);
    event AttestorReplaced(
        address indexed previous, address indexed replacement, uint64 previousEpoch, uint64 newEpoch
    );
    event ThresholdUpdated(uint8 previousThreshold, uint8 newThreshold, uint64 previousEpoch, uint64 newEpoch);
    event PolicyVersionUpdated(uint32 previousVersion, uint32 newVersion, uint64 previousEpoch, uint64 newEpoch);

    /// @notice True if `account` is currently an authorized attestor.
    function isAttestor(address account) external view returns (bool);

    /// @notice Current number of authorized attestors; always exactly five after construction.
    function attestorCount() external view returns (uint256);

    /// @notice Attestor at `index` in the enumerable set. Order is not stable across mutations.
    function attestorAt(uint256 index) external view returns (address);

    /// @notice Full attestor set snapshot.
    function attestors() external view returns (address[] memory);

    /// @notice Minimum number of distinct valid signatures required for quorum.
    function threshold() external view returns (uint8);

    /// @notice Monotonic epoch counter, incremented on every membership/threshold/policy change.
    function attestorEpoch() external view returns (uint64);

    /// @notice Verification policy version attestors must be running.
    function policyVersion() external view returns (uint32);

    /// @notice Convenience accessor used by the oracle's hot path.
    function quorumContext() external view returns (uint8 currentThreshold, uint64 epoch, uint32 policy);
}
