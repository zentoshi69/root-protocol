// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";

/// @title MerkleFixture
/// @notice Pure-Solidity builder for the canonical Bitcoin Puppets manifest Merkle tree.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      THE ALGORITHM, SPELLED OUT SO THE TYPESCRIPT BUILDER CAN BE WRITTEN AGAINST IT:
///
///      1. Leaf: `leaf = keccak256(bytes.concat(rootKey))` — i.e. `PuppetHashing.collectionLeaf`.
///         The rootKey is itself a keccak output, so leaves are DOUBLE hashed. That is what makes
///         an internal node's preimage structurally unusable as a leaf preimage, which is the
///         standard second-preimage defence (OpenZeppelin `StandardMerkleTree` convention).
///      2. Sort the leaf array ascending, comparing the 32 raw bytes as an unsigned big-endian
///         integer. Sorting makes the tree a pure function of the SET of members, so two
///         independent implementations that disagree about manifest ordering still agree about
///         the root. Duplicate leaves are rejected: a duplicate makes `proof()` ambiguous and
///         would silently mean the manifest committed the same inscription twice.
///      3. If exactly one leaf remains, the root IS that leaf and every proof is empty.
///      4. Otherwise fold level by level. For level `L` of length `n`, level `L+1` has length
///         `ceil(n / 2)` and `L+1[i] = hashPair(L[2i], L[2i+1])`. When `n` is odd the final node
///         has no sibling and is PROMOTED UNCHANGED to the next level (it is not hashed with
///         itself, and it is not paired with a zero node).
///      5. `hashPair(a, b) = keccak256(abi.encodePacked(min(a,b), max(a,b)))`. Sorted-pair
///         hashing is what makes proofs verify under OpenZeppelin `MerkleProof.verify` without
///         carrying left/right direction bits.
///      6. A proof for the leaf at sorted position `p` is, for each level, the sibling
///         `L[p ^ 1]` when that index exists (omitted for a promoted odd node), after which
///         `p = p / 2`.
///
///      Promotion (step 4) is worth calling out: promoting rather than duplicating the odd node
///      avoids the classic "duplicate last leaf" ambiguity, where a tree of n leaves and a tree of
///      n+1 leaves whose last leaf repeats can produce the same root.
library MerkleFixture {
    /// @notice Thrown when the leaf array is empty; an empty tree has no meaningful root.
    error EmptyLeaves();
    /// @notice Thrown when two identical leaves are supplied, which makes proofs ambiguous.
    error DuplicateLeaf(bytes32 leaf);
    /// @notice Thrown when the requested proof index is outside the supplied array.
    error IndexOutOfRange(uint256 index, uint256 length);

    /*//////////////////////////////////////////////////////////////
                              LEAF HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Convert canonical inscription identities into collection leaves.
    /// @param roots The inscriptions the manifest commits to.
    /// @return leaves One `PuppetHashing.collectionLeaf` per root, in the caller's order.
    function leavesOf(PuppetTypes.RootId[] memory roots) internal pure returns (bytes32[] memory leaves) {
        leaves = new bytes32[](roots.length);
        for (uint256 i = 0; i < roots.length; i++) {
            leaves[i] = PuppetHashing.collectionLeaf(roots[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                BUILDING
    //////////////////////////////////////////////////////////////*/

    /// @notice Build the Merkle root over `leaves`.
    /// @dev The input array is copied before sorting so the caller's array keeps its own order and
    ///      can still be indexed for `proof()`.
    /// @param leaves Collection leaves, in any order.
    /// @return root The sorted-pair Merkle root.
    function build(bytes32[] memory leaves) internal pure returns (bytes32 root) {
        bytes32[] memory level = _sortedCopy(leaves);
        while (level.length > 1) {
            level = _foldLevel(level);
        }
        return level[0];
    }

    /// @notice Build the Merkle root over a set of inscriptions.
    /// @param roots The inscriptions the manifest commits to.
    /// @return root The sorted-pair Merkle root.
    function buildFromRoots(PuppetTypes.RootId[] memory roots) internal pure returns (bytes32 root) {
        return build(leavesOf(roots));
    }

    /*//////////////////////////////////////////////////////////////
                                 PROOFS
    //////////////////////////////////////////////////////////////*/

    /// @notice Merkle proof for the leaf at `index` of the CALLER'S array.
    /// @dev `index` addresses the caller's unsorted array; the function locates that leaf inside
    ///      the sorted layout itself. Indexing the sorted layout instead would be a silent
    ///      foot-gun, because sorting reorders the manifest.
    /// @param leaves Collection leaves, in any order.
    /// @param index Position in `leaves` of the member being proven.
    /// @return proof Sibling hashes, leaf level first, verifiable with `MerkleProof.verify`.
    function proof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        if (index >= leaves.length) revert IndexOutOfRange(index, leaves.length);
        return proofForLeaf(leaves, leaves[index]);
    }

    /// @notice Merkle proof for an explicit leaf value.
    /// @param leaves Collection leaves, in any order.
    /// @param leaf The leaf to prove. Must be present in `leaves`.
    /// @return result Sibling hashes, leaf level first.
    function proofForLeaf(bytes32[] memory leaves, bytes32 leaf) internal pure returns (bytes32[] memory result) {
        bytes32[] memory level = _sortedCopy(leaves);

        uint256 position = type(uint256).max;
        for (uint256 i = 0; i < level.length; i++) {
            if (level[i] == leaf) {
                position = i;
                break;
            }
        }
        if (position == type(uint256).max) revert IndexOutOfRange(type(uint256).max, level.length);

        // Depth is bounded by ceil(log2(n)); over-allocating then trimming keeps the loop simple.
        bytes32[] memory scratch = new bytes32[](_depthBound(level.length));
        uint256 written = 0;

        while (level.length > 1) {
            uint256 sibling = position ^ 1;
            if (sibling < level.length) {
                scratch[written++] = level[sibling];
            }
            position /= 2;
            level = _foldLevel(level);
        }

        result = new bytes32[](written);
        for (uint256 i = 0; i < written; i++) {
            result[i] = scratch[i];
        }
    }

    /// @notice Merkle proof for the inscription at `index` of `roots`.
    /// @param roots The inscriptions the manifest commits to.
    /// @param index Position in `roots` of the member being proven.
    /// @return proofNodes Sibling hashes, leaf level first.
    function proofFromRoots(PuppetTypes.RootId[] memory roots, uint256 index)
        internal
        pure
        returns (bytes32[] memory proofNodes)
    {
        return proof(leavesOf(roots), index);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Matches OpenZeppelin `MerkleProof._hashPair` exactly. Diverging here would produce a
    ///      tree that only this test helper can verify, which is worse than no helper at all.
    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /// @dev One folding step. Odd tail node is promoted unchanged (never self-paired).
    function _foldLevel(bytes32[] memory level) private pure returns (bytes32[] memory next) {
        uint256 n = level.length;
        next = new bytes32[]((n + 1) / 2);
        for (uint256 i = 0; i < next.length; i++) {
            uint256 left = 2 * i;
            uint256 right = left + 1;
            next[i] = right < n ? _hashPair(level[left], level[right]) : level[left];
        }
    }

    function _sortedCopy(bytes32[] memory leaves) private pure returns (bytes32[] memory out) {
        if (leaves.length == 0) revert EmptyLeaves();
        out = new bytes32[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            out[i] = leaves[i];
        }

        // Insertion sort by raw big-endian value. Fixture trees are small; clarity wins.
        for (uint256 i = 1; i < out.length; i++) {
            bytes32 key = out[i];
            uint256 j = i;
            while (j > 0 && out[j - 1] > key) {
                out[j] = out[j - 1];
                j--;
            }
            out[j] = key;
        }

        for (uint256 i = 1; i < out.length; i++) {
            if (out[i] == out[i - 1]) revert DuplicateLeaf(out[i]);
        }
    }

    /// @dev Upper bound on tree depth, used only to size a scratch buffer.
    function _depthBound(uint256 n) private pure returns (uint256 depth) {
        while (n > 1) {
            n = (n + 1) / 2;
            depth++;
        }
    }
}
