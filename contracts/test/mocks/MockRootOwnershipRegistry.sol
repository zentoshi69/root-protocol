// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRootOwnershipRegistry} from "../../src/interfaces/IRootOwnershipRegistry.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";

/// @title MockRootOwnershipRegistry
/// @notice Stand-in for `RootOwnershipRegistry` whose beneficiary and active flag are settable.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      HONESTY NOTE: this mock lets any caller declare any beneficiary for any Root. The real
///      registry only ever moves a Root's beneficiary on the back of a consumed 3-of-5 ownership
///      attestation, and only ever deactivates it on a consumed spend attestation. This mock
///      exists so FeeRouter and TourEngine suites can put a Root into "active with beneficiary B"
///      or "inactive, value must go to the pending bucket" in one line — it proves nothing about
///      how a Root legitimately reaches those states.
contract MockRootOwnershipRegistry is IRootOwnershipRegistry {
    mapping(bytes32 => PuppetTypes.RootState) private _state;
    mapping(bytes32 => mapping(uint64 => PuppetTypes.RootEpochInfo)) private _epochInfo;

    /// @notice Number of times `recordMintOwnership` was called, for call-count assertions.
    uint256 public recordMintCallCount;

    /// @notice Root key of the most recent `recordMintOwnership` call.
    bytes32 public lastRecordedRootKey;

    /// @notice Caller of the most recent `recordMintOwnership` call.
    address public lastRecorder;

    /*//////////////////////////////////////////////////////////////
                             TEST MUTATORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Put a Root directly into an active or inactive ownership state.
    /// @param rootKey Canonical protocol key for the inscription.
    /// @param beneficiary Address that should receive Root-linked value.
    /// @param active Whether the recorded owner is currently believed valid.
    /// @param epoch Ownership epoch number to report.
    function setRoot(bytes32 rootKey, address beneficiary, bool active, uint64 epoch) external {
        PuppetTypes.RootState storage s = _state[rootKey];
        s.beneficiary = beneficiary;
        s.active = active;
        s.epoch = epoch;
    }

    /// @notice Flip only the active flag, simulating an observed Bitcoin spend.
    /// @param rootKey Canonical protocol key for the inscription.
    /// @param active New active flag.
    function setActive(bytes32 rootKey, bool active) external {
        _state[rootKey].active = active;
    }

    /// @notice Set the Bitcoin-side facts a suite may assert on.
    /// @param rootKey Canonical protocol key for the inscription.
    /// @param outpointHash Outpoint currently recorded as holding the inscription.
    /// @param ownerScriptHash keccak256 of the owning scriptPubKey.
    /// @param bitcoinHeight Height at which the state was verified.
    function setBitcoinFacts(bytes32 rootKey, bytes32 outpointHash, bytes32 ownerScriptHash, uint64 bitcoinHeight)
        external
    {
        PuppetTypes.RootState storage s = _state[rootKey];
        s.currentOutpointHash = outpointHash;
        s.ownerScriptHash = ownerScriptHash;
        s.verifiedBitcoinHeight = bitcoinHeight;
    }

    /// @notice Write a historical epoch record directly.
    /// @param rootKey Canonical protocol key for the inscription.
    /// @param epoch Epoch number the record belongs to.
    /// @param info The record.
    function setEpochInfo(bytes32 rootKey, uint64 epoch, PuppetTypes.RootEpochInfo calldata info) external {
        _epochInfo[rootKey][epoch] = info;
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRootOwnershipRegistry
    function currentState(bytes32 rootKey) external view returns (PuppetTypes.RootState memory) {
        return _state[rootKey];
    }

    /// @inheritdoc IRootOwnershipRegistry
    function currentBeneficiary(bytes32 rootKey)
        external
        view
        returns (address beneficiary, bool active, uint64 epoch)
    {
        PuppetTypes.RootState storage s = _state[rootKey];
        return (s.beneficiary, s.active, s.epoch);
    }

    /// @inheritdoc IRootOwnershipRegistry
    function isActive(bytes32 rootKey) external view returns (bool) {
        return _state[rootKey].active;
    }

    /// @inheritdoc IRootOwnershipRegistry
    function epochOf(bytes32 rootKey) external view returns (uint64) {
        return _state[rootKey].epoch;
    }

    /// @inheritdoc IRootOwnershipRegistry
    function epochInfo(bytes32 rootKey, uint64 epoch) external view returns (PuppetTypes.RootEpochInfo memory) {
        return _epochInfo[rootKey][epoch];
    }

    /*//////////////////////////////////////////////////////////////
                              MUTATING PATHS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev NOT role gated in the mock; the real registry requires `MINT_RECORDER_ROLE`.
    function recordMintOwnership(
        bytes32 rootKey,
        address beneficiary,
        bytes32 outpointHash,
        bytes32 ownerScriptHash,
        bytes32 ownershipDigest,
        bytes32 bip322ProofHash,
        bytes32 bitcoinBlockHash,
        uint64 bitcoinHeight
    ) external returns (uint64 epoch) {
        if (rootKey == bytes32(0)) revert ZeroRootKey();
        if (beneficiary == address(0)) revert ZeroAddress();

        PuppetTypes.RootState storage s = _state[rootKey];
        if (s.active) revert RootAlreadyActive(rootKey, s.epoch);

        epoch = s.epoch + 1;
        s.epoch = epoch;
        s.active = true;
        s.beneficiary = beneficiary;
        s.currentOutpointHash = outpointHash;
        s.ownerScriptHash = ownerScriptHash;
        s.ownershipDigest = ownershipDigest;
        s.bip322ProofHash = bip322ProofHash;
        s.lastBitcoinBlockHash = bitcoinBlockHash;
        s.verifiedBitcoinHeight = bitcoinHeight;

        _epochInfo[rootKey][epoch] = PuppetTypes.RootEpochInfo({
            beneficiary: beneficiary,
            outpointHash: outpointHash,
            ownerScriptHash: ownerScriptHash,
            activatedAtBitcoinHeight: bitcoinHeight,
            activatedAtBlockTimestamp: uint64(block.timestamp),
            deactivatedAtBitcoinHeight: 0,
            deactivatedAtBlockTimestamp: 0,
            ownershipDigest: ownershipDigest
        });

        recordMintCallCount++;
        lastRecordedRootKey = rootKey;
        lastRecorder = msg.sender;

        emit RootEpochActivated(
            rootKey, epoch, beneficiary, outpointHash, ownerScriptHash, bitcoinHeight, ownershipDigest
        );
    }

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev The mock does NOT verify the quorum or release any pending balance; it simply applies
    ///      the attestation's claims. `releasedPending` is always zero.
    function bindRootOwner(
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata,
        bytes32[] calldata
    ) external returns (uint64 epoch, uint256 releasedPending) {
        bytes32 rootKey = PuppetHashing.rootKey(attestation.rootTxid, attestation.rootIndex);
        PuppetTypes.RootState storage s = _state[rootKey];

        epoch = s.epoch + 1;
        s.epoch = epoch;
        s.active = true;
        s.beneficiary = attestation.evmPayout;
        s.currentOutpointHash = attestation.currentOutpointHash;
        s.ownerScriptHash = attestation.ownerScriptHash;
        s.bip322ProofHash = attestation.bip322ProofHash;
        s.lastBitcoinBlockHash = attestation.bitcoinBlockHash;
        s.verifiedBitcoinHeight = attestation.bitcoinHeight;

        emit RootEpochActivated(
            rootKey,
            epoch,
            attestation.evmPayout,
            attestation.currentOutpointHash,
            attestation.ownerScriptHash,
            attestation.bitcoinHeight,
            bytes32(0)
        );
        return (epoch, 0);
    }

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev The mock does NOT verify the quorum; it deactivates the Root unconditionally.
    function invalidateRoot(
        PuppetTypes.RootSpendAttestation calldata attestation,
        bytes[] calldata,
        bytes32[] calldata
    ) external {
        bytes32 rootKey = PuppetHashing.rootKey(attestation.rootTxid, attestation.rootIndex);
        PuppetTypes.RootState storage s = _state[rootKey];
        if (!s.active) revert RootNotActive(rootKey);

        address previous = s.beneficiary;
        s.active = false;
        s.invalidatingSpendTxid = attestation.spendingTxid;

        emit RootEpochInvalidated(rootKey, s.epoch, previous, attestation.spendingTxid, attestation.bitcoinHeight);
    }
}
