// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CommonBase} from "forge-std/Base.sol";

/// @title AttestorSet
/// @notice Deterministic 3-of-5 style attestor quorum helper shared by every Foundry suite.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      WHERE `vm` COMES FROM: this contract inherits forge-std `CommonBase`, which exposes the
///      hevm cheat-code address as `vm`. Inheriting is preferred over re-declaring the raw
///      address so there is exactly one definition of the cheat address in the tree.
///
///      WHY ORDERING IS BY *RECOVERED ADDRESS*, NOT BY SIGNATURE BYTES:
///      `BitcoinOwnershipOracle` walks the signature array and requires each recovered signer to
///      be strictly greater than the previous one. That single check does three jobs at once:
///      it fixes a canonical ordering, it makes duplicate signatures free to reject (a repeat is
///      not strictly greater than itself), and it removes the need for an O(n^2) seen-set. The
///      consequence for this helper is that the signer SET must be sorted by address *before*
///      signing; sorting the produced signature bytes afterwards would order them by ECDSA
///      output, which has no relationship to the recovered address and would fail the check.
///
///      Every private key is derived from `(seed, index)` so a suite that constructs the same
///      seed always gets the same attestor addresses, which keeps golden vectors reproducible.
contract AttestorSet is CommonBase {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a helper is asked for more signers than the set contains.
    error NotEnoughAttestors(uint256 requested, uint256 available);
    /// @notice Thrown when an attestor index is out of range.
    error IndexOutOfRange(uint256 index, uint256 length);
    /// @notice Thrown when the set would be constructed with zero members.
    error EmptySet();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Order of the secp256k1 group. Derived keys are folded into `[1, N-1]` so `vm.sign`
    ///      never sees an out-of-range key, which would revert with an opaque cheat-code error.
    uint256 internal constant SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    /// @dev Domain tag for attestor key derivation, so a suite seed cannot accidentally collide
    ///      with the outsider key derived from the same seed.
    bytes32 internal constant ATTESTOR_KEY_DOMAIN = keccak256("HOODPUPS_TEST_ATTESTOR_KEY_V1");

    /// @dev Domain tag for the non-attestor ("outsider") key.
    bytes32 internal constant OUTSIDER_KEY_DOMAIN = keccak256("HOODPUPS_TEST_OUTSIDER_KEY_V1");

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256[] private _keys;
    address[] private _addrs;

    uint256 private _outsiderKey;
    address private _outsider;

    /// @notice Build `count` deterministic attestor keypairs plus one non-attestor keypair.
    /// @param attestorCount Number of attestors. Pass 5 for the canonical production shape.
    /// @param seed Suite-specific seed; identical seeds produce identical addresses.
    constructor(uint256 attestorCount, bytes32 seed) {
        if (attestorCount == 0) revert EmptySet();
        for (uint256 i = 0; i < attestorCount; i++) {
            uint256 key = _deriveKey(ATTESTOR_KEY_DOMAIN, seed, i);
            _keys.push(key);
            _addrs.push(vm.addr(key));
        }
        _outsiderKey = _deriveKey(OUTSIDER_KEY_DOMAIN, seed, 0);
        _outsider = vm.addr(_outsiderKey);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Number of attestors in the set.
    function count() external view returns (uint256) {
        return _addrs.length;
    }

    /// @notice Attestor addresses in creation order (index 0 is attestor 0).
    function addresses() external view returns (address[] memory) {
        return _addrs;
    }

    /// @notice Attestor addresses sorted ascending, which is the order the oracle demands.
    function sortedAddresses() external view returns (address[] memory sorted) {
        sorted = _copyAddresses();
        _sortAddresses(sorted);
    }

    /// @notice Address of the attestor at creation index `index`.
    function addressAt(uint256 index) external view returns (address) {
        if (index >= _addrs.length) revert IndexOutOfRange(index, _addrs.length);
        return _addrs[index];
    }

    /// @notice Private key of the attestor at creation index `index`.
    /// @dev Exposed so suites can sign non-attestation payloads (e.g. an ERC-1271 owner key).
    function keyAt(uint256 index) external view returns (uint256) {
        if (index >= _keys.length) revert IndexOutOfRange(index, _keys.length);
        return _keys[index];
    }

    /// @notice Address of the deterministic key that is deliberately NOT in the attestor set.
    function outsider() external view returns (address) {
        return _outsider;
    }

    /// @notice Private key of the non-attestor.
    function outsiderKey() external view returns (uint256) {
        return _outsiderKey;
    }

    /*//////////////////////////////////////////////////////////////
                            POSITIVE SIGNING
    //////////////////////////////////////////////////////////////*/

    /// @notice Sign `digest` with the first `signerCount` attestors, ordered by recovered address.
    /// @dev The signer subset is attestor indices `0 .. signerCount-1`, so a suite can reason about
    ///      exactly who signed. The returned array is then sorted by address, which is what the
    ///      oracle's strictly-ascending check consumes.
    /// @param digest The EIP-712 digest the attestors are attesting to.
    /// @param signerCount How many attestors sign. Must not exceed the set size.
    /// @return signatures 65-byte `(r, s, v)` signatures in strictly ascending signer order.
    function sign(bytes32 digest, uint256 signerCount) external view returns (bytes[] memory signatures) {
        return _signSorted(digest, _firstIndices(signerCount), false);
    }

    /// @notice Sign `digest` with a hand-picked attestor subset, ordered by recovered address.
    /// @param digest The EIP-712 digest.
    /// @param indices Creation indices of the attestors that should sign.
    /// @return signatures 65-byte signatures in strictly ascending signer order.
    function signWith(bytes32 digest, uint256[] memory indices) external view returns (bytes[] memory signatures) {
        return _signSorted(digest, _validated(indices), false);
    }

    /// @notice Sign `digest` with the first `signerCount` attestors as EIP-2098 compact signatures.
    /// @dev 64 bytes: `r` then `vs`, where the top bit of `s` carries `v == 28`. Used by the
    ///      oracle's compact-signature acceptance tests.
    /// @param digest The EIP-712 digest.
    /// @param signerCount How many attestors sign.
    /// @return signatures 64-byte compact signatures in strictly ascending signer order.
    function signCompact(bytes32 digest, uint256 signerCount) external view returns (bytes[] memory signatures) {
        return _signSorted(digest, _firstIndices(signerCount), true);
    }

    /// @notice Compact-signature variant of `signWith`.
    /// @param digest The EIP-712 digest.
    /// @param indices Creation indices of the attestors that should sign.
    /// @return signatures 64-byte compact signatures in strictly ascending signer order.
    function signCompactWith(bytes32 digest, uint256[] memory indices)
        external
        view
        returns (bytes[] memory signatures)
    {
        return _signSorted(digest, _validated(indices), true);
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE SIGNING
    //////////////////////////////////////////////////////////////*/

    /// @notice Sign with the first `signerCount` attestors in DESCENDING address order.
    /// @dev Every signature is individually valid; only the ordering is wrong. This isolates the
    ///      `SignersNotStrictlyAscending` path from any signature-validity failure.
    /// @param digest The EIP-712 digest.
    /// @param signerCount How many attestors sign. Must be at least 2 for the order to be wrong.
    /// @return signatures 65-byte signatures in strictly descending signer order.
    function signUnsorted(bytes32 digest, uint256 signerCount) external view returns (bytes[] memory signatures) {
        uint256[] memory indices = _firstIndices(signerCount);
        _sortIndicesByAddress(indices);
        _reverse(indices);
        return _signInGivenOrder(digest, indices, false);
    }

    /// @notice Sign in exactly the order given, performing no sorting at all.
    /// @dev Escape hatch for bespoke ordering cases the named helpers do not cover.
    /// @param digest The EIP-712 digest.
    /// @param indices Creation indices, signed in this exact order.
    /// @return signatures 65-byte signatures in the caller's order.
    function signRaw(bytes32 digest, uint256[] memory indices) external view returns (bytes[] memory signatures) {
        return _signInGivenOrder(digest, _validated(indices), false);
    }

    /// @notice Produce `signerCount` signatures in which one attestor signs twice, adjacently.
    /// @dev The array is non-decreasing but not STRICTLY ascending, which is precisely the shape a
    ///      quorum-inflation attack would take: three signatures, two real signers.
    /// @param digest The EIP-712 digest.
    /// @param signerCount Total number of signatures returned. Must be at least 2.
    /// @param duplicateSlot Position within the address-sorted distinct signers to repeat.
    /// @return signatures 65-byte signatures containing one adjacent duplicate signer.
    function signWithDuplicate(bytes32 digest, uint256 signerCount, uint256 duplicateSlot)
        external
        view
        returns (bytes[] memory signatures)
    {
        if (signerCount < 2) revert NotEnoughAttestors(2, signerCount);
        uint256 distinct = signerCount - 1;
        uint256[] memory base = _firstIndices(distinct);
        _sortIndicesByAddress(base);
        if (duplicateSlot >= distinct) revert IndexOutOfRange(duplicateSlot, distinct);

        uint256[] memory withDup = new uint256[](signerCount);
        uint256 cursor = 0;
        for (uint256 i = 0; i < distinct; i++) {
            withDup[cursor++] = base[i];
            if (i == duplicateSlot) withDup[cursor++] = base[i];
        }
        return _signInGivenOrder(digest, withDup, false);
    }

    /// @notice One signature from the deterministic non-attestor key.
    /// @param digest The EIP-712 digest.
    /// @return signature A 65-byte signature that recovers to an address outside the set.
    function signAsOutsider(bytes32 digest) external view returns (bytes memory signature) {
        return _sign(_outsiderKey, digest, false);
    }

    /// @notice A correctly ascending signature array in which one signer is NOT an attestor.
    /// @dev Ordering is valid, so the only reason verification may fail is membership. That keeps
    ///      the `SignerNotAttestor` test honest.
    /// @param digest The EIP-712 digest.
    /// @param attestorCount How many genuine attestors join the outsider.
    /// @return signatures 65-byte signatures in strictly ascending signer order.
    function signWithOutsider(bytes32 digest, uint256 attestorCount) external view returns (bytes[] memory signatures) {
        uint256[] memory indices = _firstIndices(attestorCount);

        // Build a parallel (address, key) list including the outsider, then sort it as one unit.
        uint256 n = attestorCount + 1;
        address[] memory signers = new address[](n);
        uint256[] memory keys = new uint256[](n);
        for (uint256 i = 0; i < attestorCount; i++) {
            signers[i] = _addrs[indices[i]];
            keys[i] = _keys[indices[i]];
        }
        signers[n - 1] = _outsider;
        keys[n - 1] = _outsiderKey;
        _sortPairs(signers, keys);

        signatures = new bytes[](n);
        for (uint256 i = 0; i < n; i++) {
            signatures[i] = _sign(keys[i], digest, false);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Fold a keccak output into a valid secp256k1 private key.
    function _deriveKey(bytes32 domain, bytes32 seed, uint256 index) private pure returns (uint256) {
        uint256 raw = uint256(keccak256(abi.encode(domain, seed, index)));
        return (raw % (SECP256K1_N - 1)) + 1;
    }

    function _firstIndices(uint256 n) private view returns (uint256[] memory indices) {
        if (n > _addrs.length) revert NotEnoughAttestors(n, _addrs.length);
        indices = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            indices[i] = i;
        }
    }

    function _validated(uint256[] memory indices) private view returns (uint256[] memory) {
        for (uint256 i = 0; i < indices.length; i++) {
            if (indices[i] >= _addrs.length) revert IndexOutOfRange(indices[i], _addrs.length);
        }
        return indices;
    }

    /// @dev Sort the signer subset by address FIRST, then sign. See the contract-level note on why
    ///      sorting signature bytes after the fact would be wrong.
    function _signSorted(bytes32 digest, uint256[] memory indices, bool compact)
        private
        view
        returns (bytes[] memory signatures)
    {
        _sortIndicesByAddress(indices);
        return _signInGivenOrder(digest, indices, compact);
    }

    function _signInGivenOrder(bytes32 digest, uint256[] memory indices, bool compact)
        private
        view
        returns (bytes[] memory signatures)
    {
        signatures = new bytes[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            signatures[i] = _sign(_keys[indices[i]], digest, compact);
        }
    }

    function _sign(uint256 key, bytes32 digest, bool compact) private pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        if (!compact) return abi.encodePacked(r, s, v);
        // EIP-2098: `yParity` is folded into the unused top bit of `s`.
        bytes32 vs = v == 28 ? bytes32(uint256(s) | (uint256(1) << 255)) : s;
        return abi.encodePacked(r, vs);
    }

    function _copyAddresses() private view returns (address[] memory out) {
        out = new address[](_addrs.length);
        for (uint256 i = 0; i < _addrs.length; i++) {
            out[i] = _addrs[i];
        }
    }

    /// @dev Insertion sort. The set is five members in practice; clarity beats asymptotics here.
    function _sortAddresses(address[] memory arr) private pure {
        for (uint256 i = 1; i < arr.length; i++) {
            address key = arr[i];
            uint256 j = i;
            while (j > 0 && arr[j - 1] > key) {
                arr[j] = arr[j - 1];
                j--;
            }
            arr[j] = key;
        }
    }

    function _sortIndicesByAddress(uint256[] memory indices) private view {
        for (uint256 i = 1; i < indices.length; i++) {
            uint256 key = indices[i];
            address keyAddr = _addrs[key];
            uint256 j = i;
            while (j > 0 && _addrs[indices[j - 1]] > keyAddr) {
                indices[j] = indices[j - 1];
                j--;
            }
            indices[j] = key;
        }
    }

    function _sortPairs(address[] memory signers, uint256[] memory keys) private pure {
        for (uint256 i = 1; i < signers.length; i++) {
            address a = signers[i];
            uint256 k = keys[i];
            uint256 j = i;
            while (j > 0 && signers[j - 1] > a) {
                signers[j] = signers[j - 1];
                keys[j] = keys[j - 1];
                j--;
            }
            signers[j] = a;
            keys[j] = k;
        }
    }

    function _reverse(uint256[] memory arr) private pure {
        uint256 n = arr.length;
        for (uint256 i = 0; i < n / 2; i++) {
            (arr[i], arr[n - 1 - i]) = (arr[n - 1 - i], arr[i]);
        }
    }
}
