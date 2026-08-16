// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IBitcoinAttestorRegistry} from "../../src/interfaces/IBitcoinAttestorRegistry.sol";

/// @title MockAttestorRegistry
/// @notice Freely mutable stand-in for `BitcoinAttestorRegistry`.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      HONESTY NOTE: this mock RELAXES governance, it does not relax verification. There are no
///      roles, no timelock and no epoch-bump-on-mutation coupling, so a suite can drive the set
///      into any shape it needs — in particular a STALE epoch or policy version, which is the
///      main reason this mock exists. It deliberately keeps the properties the oracle actually
///      depends on: membership is a set, `attestors()` is a faithful snapshot, and
///      `quorumContext()` returns exactly what the individual getters return.
///
///      Because it is mutable by anyone, never use it to argue that the real registry is safe.
contract MockAttestorRegistry is IBitcoinAttestorRegistry {
    address[] private _attestors;
    mapping(address => bool) private _isAttestor;

    uint8 private _threshold;
    uint64 private _epoch;
    uint32 private _policyVersion;

    /// @param initialAttestors Starting attestor set. Duplicates revert, mirroring the real registry.
    /// @param initialThreshold Starting quorum threshold.
    /// @param initialEpoch Starting attestor epoch.
    /// @param initialPolicyVersion Starting policy version.
    constructor(
        address[] memory initialAttestors,
        uint8 initialThreshold,
        uint64 initialEpoch,
        uint32 initialPolicyVersion
    ) {
        _setAttestors(initialAttestors);
        _threshold = initialThreshold;
        _epoch = initialEpoch;
        _policyVersion = initialPolicyVersion;
    }

    /*//////////////////////////////////////////////////////////////
                             TEST MUTATORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Replace the whole attestor set without touching the epoch.
    /// @dev Epoch is left alone on purpose: a suite testing "removed attestor still counts"
    ///      needs to be able to change membership WITHOUT the epoch invalidating in-flight
    ///      signatures. The real registry always bumps.
    /// @param next The new attestor set.
    function setAttestors(address[] memory next) external {
        _setAttestors(next);
    }

    /// @notice Add one attestor.
    /// @param account Address to add. Reverts if already present.
    function addAttestor(address account) external {
        if (account == address(0)) revert ZeroAddress();
        if (_isAttestor[account]) revert DuplicateAttestor(account);
        _isAttestor[account] = true;
        _attestors.push(account);
    }

    /// @notice Remove one attestor.
    /// @param account Address to remove. Reverts if absent.
    function removeAttestor(address account) external {
        if (!_isAttestor[account]) revert UnknownAttestor(account);
        _isAttestor[account] = false;
        uint256 n = _attestors.length;
        for (uint256 i = 0; i < n; i++) {
            if (_attestors[i] == account) {
                _attestors[i] = _attestors[n - 1];
                _attestors.pop();
                break;
            }
        }
    }

    /// @notice Set the quorum threshold. No range validation, so suites can test degenerate values.
    /// @param next New threshold.
    function setThreshold(uint8 next) external {
        uint8 previous = _threshold;
        _threshold = next;
        emit ThresholdUpdated(previous, next, _epoch, _epoch);
    }

    /// @notice Set the attestor epoch directly, including backwards, to build stale-epoch cases.
    /// @param next New epoch value.
    function setEpoch(uint64 next) external {
        _epoch = next;
    }

    /// @notice Increment the attestor epoch, simulating any real membership change.
    /// @return next The new epoch.
    function bumpEpoch() external returns (uint64 next) {
        next = _epoch + 1;
        _epoch = next;
    }

    /// @notice Set the policy version, including to zero, to build stale-policy cases.
    /// @param next New policy version.
    function setPolicyVersion(uint32 next) external {
        uint32 previous = _policyVersion;
        _policyVersion = next;
        emit PolicyVersionUpdated(previous, next, _epoch, _epoch);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBitcoinAttestorRegistry
    function isAttestor(address account) external view returns (bool) {
        return _isAttestor[account];
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    function attestorCount() external view returns (uint256) {
        return _attestors.length;
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    function attestorAt(uint256 index) external view returns (address) {
        return _attestors[index];
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    function attestors() external view returns (address[] memory) {
        return _attestors;
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    function threshold() external view returns (uint8) {
        return _threshold;
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    function attestorEpoch() external view returns (uint64) {
        return _epoch;
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    function policyVersion() external view returns (uint32) {
        return _policyVersion;
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    function quorumContext() external view returns (uint8 currentThreshold, uint64 epoch, uint32 policy) {
        return (_threshold, _epoch, _policyVersion);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _setAttestors(address[] memory next) private {
        uint256 n = _attestors.length;
        for (uint256 i = 0; i < n; i++) {
            _isAttestor[_attestors[i]] = false;
        }
        delete _attestors;

        for (uint256 i = 0; i < next.length; i++) {
            if (next[i] == address(0)) revert ZeroAddress();
            if (_isAttestor[next[i]]) revert DuplicateAttestor(next[i]);
            _isAttestor[next[i]] = true;
            _attestors.push(next[i]);
        }
    }
}
