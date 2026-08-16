// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {IPuppetCollectionRegistry} from "../../src/interfaces/IPuppetCollectionRegistry.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";

/// @title MockCollectionRegistry
/// @notice Stand-in for `PuppetCollectionRegistry` with a mutable root and an `allowAll` escape.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      HONESTY NOTE: the real registry's Merkle root is IMMUTABLE — that immutability is the
///      whole point of the contract, because it is what stops governance from quietly adding an
///      inscription to the canonical manifest. This mock makes it settable so a suite can build
///      several fixture trees in one test. That relaxation exists only here.
///
///      `allowAll` short-circuits membership entirely, for suites (escrow, fee routing) whose
///      subject is not membership. It is off by default so nobody enables it by accident, and
///      `isMember`/`requireMember` still run the real `MerkleProof.verify` when it is off.
contract MockCollectionRegistry is IPuppetCollectionRegistry {
    bytes32 private _merkleRoot;
    bytes32 private _manifestHash;
    string private _manifestVersion;
    uint256 private _manifestLeafCount;
    bool private _allowAll;

    /// @param initialRoot Merkle root over the fixture manifest.
    /// @param initialAllowAll When true, every root is considered a member regardless of proof.
    constructor(bytes32 initialRoot, bool initialAllowAll) {
        _merkleRoot = initialRoot;
        _allowAll = initialAllowAll;
        _manifestHash = keccak256("MOCK_MANIFEST");
        _manifestVersion = "mock-manifest";
        _manifestLeafCount = 0;
    }

    /*//////////////////////////////////////////////////////////////
                             TEST MUTATORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Point the mock at a different fixture tree.
    /// @param next The new Merkle root.
    function setMerkleRoot(bytes32 next) external {
        _merkleRoot = next;
    }

    /// @notice Toggle unconditional membership.
    /// @param next True to accept every root without checking a proof.
    function setAllowAll(bool next) external {
        _allowAll = next;
    }

    /// @notice Set the reproducibility metadata a suite may assert on.
    /// @param manifestHash_ Content hash of the fixture manifest.
    /// @param manifestVersion_ Human-readable version string.
    /// @param leafCount Number of leaves in the fixture manifest.
    function setManifest(bytes32 manifestHash_, string calldata manifestVersion_, uint256 leafCount) external {
        _manifestHash = manifestHash_;
        _manifestVersion = manifestVersion_;
        _manifestLeafCount = leafCount;
    }

    /// @notice True when membership checks are being short-circuited.
    function allowAll() external view returns (bool) {
        return _allowAll;
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPuppetCollectionRegistry
    function collectionId() external pure returns (bytes32) {
        return PuppetHashing.COLLECTION_ID;
    }

    /// @inheritdoc IPuppetCollectionRegistry
    function merkleRoot() external view returns (bytes32) {
        return _merkleRoot;
    }

    /// @inheritdoc IPuppetCollectionRegistry
    function manifestHash() external view returns (bytes32) {
        return _manifestHash;
    }

    /// @inheritdoc IPuppetCollectionRegistry
    function manifestVersion() external view returns (string memory) {
        return _manifestVersion;
    }

    /// @inheritdoc IPuppetCollectionRegistry
    function manifestLeafCount() external view returns (uint256) {
        return _manifestLeafCount;
    }

    /// @inheritdoc IPuppetCollectionRegistry
    function rootKey(PuppetTypes.RootId calldata root) external pure returns (bytes32) {
        return PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);
    }

    /// @inheritdoc IPuppetCollectionRegistry
    function leafOf(PuppetTypes.RootId calldata root) external pure returns (bytes32) {
        return PuppetHashing.collectionLeaf(PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex));
    }

    /// @inheritdoc IPuppetCollectionRegistry
    function isMember(PuppetTypes.RootId calldata root, bytes32[] calldata proof) external view returns (bool) {
        if (_allowAll) return true;
        bytes32 leaf = PuppetHashing.collectionLeaf(PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex));
        return MerkleProof.verify(proof, _merkleRoot, leaf);
    }

    /// @inheritdoc IPuppetCollectionRegistry
    function requireMember(PuppetTypes.RootId calldata root, bytes32[] calldata proof)
        external
        view
        returns (bytes32 key)
    {
        key = PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);
        if (_allowAll) return key;
        if (!MerkleProof.verify(proof, _merkleRoot, PuppetHashing.collectionLeaf(key))) {
            revert NotCollectionMember(key);
        }
    }
}
