// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {IPuppetCollectionRegistry} from "./interfaces/IPuppetCollectionRegistry.sol";
import {PuppetHashing} from "./types/PuppetHashing.sol";
import {PuppetTypes} from "./types/PuppetTypes.sol";

/// @title PuppetCollectionRegistry
/// @notice Immutable Merkle membership registry for this deployment's canonical Bitcoin Puppets manifest.
/// @dev SCOPE. This contract answers exactly one question:
///
///          "Is this exact Bitcoin inscription included in the manifest this deployment committed to?"
///
///      It does NOT know, and must never be read as knowing, who currently controls an inscription.
///      Current Bitcoin ownership is asserted elsewhere, by a 3-of-5 quorum of independent attestors.
///      Membership is a static set commitment; ownership is a live, attested fact. Conflating the two
///      would let a stale membership proof stand in for a fresh ownership quorum.
///
///      TRUST BOUNDARY. Nothing here verifies Bitcoin consensus. The manifest is a list that the
///      deployer sourced and verified off chain, and the only thing this contract enforces is that
///      the list can never change afterwards.
///
///      "CANONICAL" MEANS CANONICAL TO THIS PROTOCOL DEPLOYMENT. It is not an endorsement,
///      affiliation or approval claim by the Bitcoin Puppets project, and must never be presented
///      as one. A different deployment may legitimately commit to a different manifest.
///
///      IMMUTABILITY IS THE SECURITY PROPERTY. There is no admin, no owner, no role, no pause and no
///      upgrade path. The Merkle root is fixed at construction, so no party — including whoever
///      deployed it — can later add an inscription to the collection, remove one, or swap the whole
///      set. A wrong manifest is not repairable in place: it is repaired by deploying a new registry
///      and migrating the protocol to it, which is a visible, reviewable event rather than a silent
///      storage write.
///
///      The original Bitcoin Puppet never leaves Bitcoin. This contract holds no value, has no
///      payable function, and has no way to receive or move funds or tokens.
contract PuppetCollectionRegistry is IPuppetCollectionRegistry {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, at construction, recording the manifest this deployment is bound to.
    /// @dev This is the only event the contract will ever emit, because it is the only state
    ///      transition it will ever have. Indexers and the reproducibility report key off it.
    /// @param merkleRoot The immutable sorted-pair Merkle root over the manifest leaves.
    /// @param manifestHash The immutable content commitment of the manifest that produced that root.
    /// @param manifestVersion Human-readable manifest version.
    /// @param manifestLeafCount Number of leaves committed, so a verifier knows how many entries to expect.
    event CollectionCommitted(
        bytes32 indexed merkleRoot, bytes32 indexed manifestHash, string manifestVersion, uint256 manifestLeafCount
    );

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Sorted-pair Merkle root over `PuppetHashing.collectionLeaf` of every manifest entry.
    bytes32 private immutable _MERKLE_ROOT;

    /// @dev Content commitment of the manifest file that produced `_MERKLE_ROOT`. Never used in a
    ///      membership check; it exists so an auditor can prove which list this root came from.
    bytes32 private immutable _MANIFEST_HASH;

    /// @dev Number of leaves in the committed manifest, for reproducibility checks.
    uint256 private immutable _MANIFEST_LEAF_COUNT;

    /// @dev Solidity cannot mark a `string` as `immutable` (immutables must be value types of at
    ///      most one word). This is therefore a plain private storage string that is written exactly
    ///      once, in the constructor, and has no setter anywhere in the contract. It is immutable in
    ///      effect, and the absence of any writing function is what enforces that — the `immutable`
    ///      keyword is unavailable, not omitted.
    string private _manifestVersion;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Permanently bind this registry to one manifest.
    /// @dev Every argument is validated as non-empty because each zero value has a specific failure
    ///      mode that would otherwise be discovered only in production:
    ///
    ///        - a zero `merkleRoot` is what an uninitialised or fail-open builder emits, and it would
    ///          make `isMember` return false for everything, bricking every settlement path;
    ///        - a zero `manifestHash` destroys the audit trail linking this root to a reviewable list;
    ///        - a zero `manifestLeafCount` means the builder committed an empty set;
    ///        - an empty `manifestVersion` defeats the reproducibility report, whose whole job is to
    ///          let a third party re-derive this root from a named list.
    ///
    ///      All four revert with the interface's `ZeroValue`, which covers "a value that must carry
    ///      information is empty", not merely "the integer is 0".
    ///
    ///      This constructor deliberately does NOT attempt to sanity-check the root against the leaf
    ///      count (for example by requiring a plausible tree depth). A Merkle root is opaque by
    ///      construction; any such check would be theatre, and theatre in a security-critical
    ///      constructor is worse than nothing because it invites trust it cannot earn.
    /// @param merkleRoot_ Sorted-pair Merkle root over the manifest's collection leaves.
    /// @param manifestHash_ Content commitment of the manifest file that produced `merkleRoot_`.
    /// @param manifestVersion_ Human-readable version, e.g. "bitcoin-puppets-mainnet-2026-01".
    /// @param manifestLeafCount_ Number of leaves committed by `merkleRoot_`.
    constructor(
        bytes32 merkleRoot_,
        bytes32 manifestHash_,
        string memory manifestVersion_,
        uint256 manifestLeafCount_
    ) {
        if (merkleRoot_ == bytes32(0)) revert ZeroValue();
        if (manifestHash_ == bytes32(0)) revert ZeroValue();
        if (manifestLeafCount_ == 0) revert ZeroValue();
        if (bytes(manifestVersion_).length == 0) revert ZeroValue();

        _MERKLE_ROOT = merkleRoot_;
        _MANIFEST_HASH = manifestHash_;
        _MANIFEST_LEAF_COUNT = manifestLeafCount_;
        _manifestVersion = manifestVersion_;

        emit CollectionCommitted(merkleRoot_, manifestHash_, manifestVersion_, manifestLeafCount_);
    }

    /*//////////////////////////////////////////////////////////////
                               COMMITMENTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPuppetCollectionRegistry
    /// @dev Read from `PuppetHashing` rather than re-declared here, so a single edit to the shared
    ///      library can never leave this contract keying leaves off a stale domain separator.
    function collectionId() external pure returns (bytes32) {
        return PuppetHashing.COLLECTION_ID;
    }

    /// @inheritdoc IPuppetCollectionRegistry
    function merkleRoot() external view returns (bytes32) {
        return _MERKLE_ROOT;
    }

    /// @inheritdoc IPuppetCollectionRegistry
    function manifestHash() external view returns (bytes32) {
        return _MANIFEST_HASH;
    }

    /// @inheritdoc IPuppetCollectionRegistry
    /// @dev Backed by a write-once private string; see `_manifestVersion` for why it is not
    ///      `immutable`.
    function manifestVersion() external view returns (string memory) {
        return _manifestVersion;
    }

    /// @inheritdoc IPuppetCollectionRegistry
    function manifestLeafCount() external view returns (uint256) {
        return _MANIFEST_LEAF_COUNT;
    }

    /*//////////////////////////////////////////////////////////////
                             IDENTITY HASHING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPuppetCollectionRegistry
    /// @dev `pure`, and identical for every deployment: the root key is a property of the
    ///      inscription and the protocol-wide collection domain, not of this contract instance.
    ///      Two inscriptions revealed by the same Bitcoin transaction differ only in
    ///      `inscriptionIndex`, and that field occupies its own 32-byte word in the preimage, so
    ///      they can never collide.
    /// @param root The inscription identity.
    /// @return The canonical protocol key for `root`.
    function rootKey(PuppetTypes.RootId calldata root) external pure returns (bytes32) {
        return PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);
    }

    /// @inheritdoc IPuppetCollectionRegistry
    /// @dev The leaf is `keccak256` of the root key, i.e. the inscription identity is hashed twice.
    ///      Double hashing is the standard second-preimage defence: an internal node preimage is 64
    ///      bytes, a leaf preimage is 32, so no internal node can be replayed as a leaf.
    /// @param root The inscription identity.
    /// @return The Merkle leaf for `root`.
    function leafOf(PuppetTypes.RootId calldata root) external pure returns (bytes32) {
        return PuppetHashing.collectionLeaf(PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex));
    }

    /*//////////////////////////////////////////////////////////////
                              MEMBERSHIP
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPuppetCollectionRegistry
    /// @dev Non-reverting form, for UIs and off-chain quoting. Settlement paths should call
    ///      `requireMember` instead: a boolean that a caller forgets to check fails open, whereas a
    ///      revert cannot be ignored.
    ///
    ///      Verification uses OpenZeppelin `MerkleProof.verify`, which hashes each pair in sorted
    ///      order. Sorted-pair hashing removes the need for direction bits in the proof, and the
    ///      off-chain builder reproduces exactly the same rule (see
    ///      `contracts/test/helpers/MerkleFixture.sol` for the algorithm written out in full).
    /// @param root The inscription identity being checked.
    /// @param proof Sibling hashes from the leaf level upwards.
    /// @return True if `root` is committed by `merkleRoot()`.
    function isMember(PuppetTypes.RootId calldata root, bytes32[] calldata proof) external view returns (bool) {
        bytes32 leaf = PuppetHashing.collectionLeaf(PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex));
        return MerkleProof.verify(proof, _MERKLE_ROOT, leaf);
    }

    /// @inheritdoc IPuppetCollectionRegistry
    /// @dev Returns the root key on success so callers do not recompute a keccak they already paid
    ///      for, and — more importantly — so they cannot key their own storage off a DIFFERENT
    ///      derivation than the one that was just proven. Handing back the exact proven key removes
    ///      that whole class of caller bug.
    ///
    ///      This is a `view`: it can never be blocked by a pause, and there is no pause to block it.
    ///      Membership is a fact about a fixed list, so refusing to answer it could only ever break
    ///      honest callers.
    /// @param root The inscription identity being checked.
    /// @param proof Sibling hashes from the leaf level upwards.
    /// @return key The canonical root key for `root`.
    function requireMember(PuppetTypes.RootId calldata root, bytes32[] calldata proof)
        external
        view
        returns (bytes32 key)
    {
        key = PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);
        if (!MerkleProof.verify(proof, _MERKLE_ROOT, PuppetHashing.collectionLeaf(key))) {
            revert NotCollectionMember(key);
        }
    }
}
