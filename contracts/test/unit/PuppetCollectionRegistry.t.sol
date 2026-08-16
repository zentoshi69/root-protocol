// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {PuppetCollectionRegistry} from "../../src/PuppetCollectionRegistry.sol";
import {IPuppetCollectionRegistry} from "../../src/interfaces/IPuppetCollectionRegistry.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";
import {MerkleFixture} from "../helpers/MerkleFixture.sol";

/// @title PuppetCollectionRegistryTest
/// @notice Membership, immutability and reproducibility tests for `PuppetCollectionRegistry`.
/// @dev THE FIXTURE IS NOT REAL DATA. Every inscription txid used here has the ASCII string
///      "FIXTURE-NOT-REAL" as its first 16 bytes, so none of these identities can exist on Bitcoin.
///      No plausible-looking Bitcoin Puppets inscription id appears anywhere in this repository;
///      the production manifest must be independently sourced and verified before deployment.
///      The same fixture, with every derived hash and proof, is pinned in
///      `data/test-fixtures/puppets-fixture-manifest.json` so the TypeScript builder can be
///      validated against exactly these vectors.
///
///      Every pinned constant below was OBSERVED by running the toolchain (`cast keccak` /
///      `cast abi-encode`, foundry 1.5.1-stable) and then written down. Nothing is hand-derived.
///      `test_DeterministicRootReproduction` re-derives them from the raw inscription identities on
///      every run, so a divergence between the pinned vectors and the live library is a test
///      failure rather than a silent drift.
contract PuppetCollectionRegistryTest is Test {
    /*//////////////////////////////////////////////////////////////
                             FIXTURE CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev keccak256("BITCOIN_PUPPETS_MAINNET_V1"), pinned so a change to the shared domain
    ///      separator surfaces here and not in production.
    bytes32 internal constant EXPECTED_COLLECTION_ID =
        0x3343dd53bae221cbae39fcca5d3c2c62e89e268149b83a35ba197aefd15463e6;

    /// @dev First 16 bytes are ASCII "FIXTURE-NOT-REAL"; the low 16 bytes carry a counter.
    bytes32 internal constant FIXTURE_TXID_PREFIX = 0x464958545552452d4e4f542d5245414c00000000000000000000000000000000;

    string internal constant FIXTURE_VERSION = "hoodpups-fixture-manifest-v1";
    string internal constant SINGLE_LEAF_VERSION = "hoodpups-fixture-single-leaf-v1";

    /// @dev Golden root over the 11-entry fixture manifest.
    bytes32 internal constant FIXTURE_ROOT = 0xeb007e33528c7a949ec5241836ea3366a7841facef47a4006361ace8bc7770bd;

    /// @dev Golden manifest content commitment:
    ///      keccak256(abi.encode(COLLECTION_ID, keccak256(bytes(version)), sortedLeaves)).
    bytes32 internal constant FIXTURE_MANIFEST_HASH =
        0xe1269b472f9f1bf139c5ca6539283c406dad1f123aaae12430d37666435e80ff;

    /// @dev Golden values for entry 0.
    bytes32 internal constant ENTRY0_ROOT_KEY = 0x87c3f70920e8882ba0697efd43a9015b28829c60962df15f8f57d33177f920e2;
    bytes32 internal constant ENTRY0_LEAF = 0x43a71c33183e4d0c6f41817c693318dab458d67692f74e5833dbd845f81b81f3;

    /// @dev Golden values for the two entries that SHARE a reveal txid and differ only by index.
    bytes32 internal constant ENTRY2_ROOT_KEY = 0xfa9cf70ac1b386015a3d792a3e2230564d48dd389f34b1035cfa70bb540c5652;
    bytes32 internal constant ENTRY3_ROOT_KEY = 0x3a8bbe9a71ba22bf57df5180090b50618fd524c50a982fa8c9e8e5f185f7df42;

    /// @dev Single-leaf fixture: the root IS the leaf and the only valid proof is empty.
    bytes32 internal constant SINGLE_LEAF_ROOT = 0xf74668e885623a91d74aa71cf1a6b6291e1bf154de8ee8ff54248b971751009b;
    bytes32 internal constant SINGLE_LEAF_ROOT_KEY = 0xa7e7067aa2fc99d64cd987d3daa80de22ac8d05c2c575b2c01ff65adb442b070;
    bytes32 internal constant SINGLE_LEAF_MANIFEST_HASH =
        0x5104377bbc0e3c0b6fa1e92ad2f24819daf13c6ef62d11f16785b26e52e8a6ad;

    /// @dev An identity deliberately absent from the manifest.
    bytes32 internal constant NON_MEMBER_ROOT_KEY = 0x65ec102372bc07e48472c09c9aff7964ea1bd7ac85d36713cd35df34ca060c8f;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    PuppetCollectionRegistry internal registry;
    PuppetCollectionRegistry internal singleLeafRegistry;

    /// @dev The fixture manifest, in file order (NOT leaf-sorted order).
    PuppetTypes.RootId[] internal roots;
    PuppetTypes.RootId internal singleRoot;
    PuppetTypes.RootId internal nonMemberRoot;

    /// @dev Mirrors the `CollectionCommitted` event so `vm.expectEmit` has a definition to match.
    event CollectionCommitted(
        bytes32 indexed merkleRoot, bytes32 indexed manifestHash, string manifestVersion, uint256 manifestLeafCount
    );

    /*//////////////////////////////////////////////////////////////
                                 SET UP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // 11 entries: comfortably more than 8, an ODD count, and containing levels with an odd
        // node so the "promote the unpaired tail node" branch is genuinely exercised rather than
        // assumed. Entries 2 and 3 share a reveal txid and differ only in inscription index.
        _add(0x01, 0);
        _add(0x02, 0);
        _add(0x03, 0);
        _add(0x03, 1);
        _add(0x04, 0);
        _add(0x05, 2);
        _add(0x06, 0);
        _add(0x07, 0);
        _add(0x08, 3);
        _add(0x09, 0);
        _add(0x0A, 0);

        singleRoot = PuppetTypes.RootId({inscriptionTxid: _fixtureTxid(0xE1), inscriptionIndex: 0});
        nonMemberRoot = PuppetTypes.RootId({inscriptionTxid: _fixtureTxid(0xFF), inscriptionIndex: 0});

        registry = new PuppetCollectionRegistry(FIXTURE_ROOT, FIXTURE_MANIFEST_HASH, FIXTURE_VERSION, roots.length);
        singleLeafRegistry =
            new PuppetCollectionRegistry(SINGLE_LEAF_ROOT, SINGLE_LEAF_MANIFEST_HASH, SINGLE_LEAF_VERSION, 1);
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Every commitment supplied at construction is readable and unchanged.
    function test_ConstructorStoresCommitments() public view {
        assertEq(registry.merkleRoot(), FIXTURE_ROOT, "root");
        assertEq(registry.manifestHash(), FIXTURE_MANIFEST_HASH, "manifest hash");
        assertEq(registry.manifestVersion(), FIXTURE_VERSION, "version");
        assertEq(registry.manifestLeafCount(), roots.length, "leaf count");
        assertEq(registry.collectionId(), EXPECTED_COLLECTION_ID, "collection id");
        assertEq(registry.collectionId(), PuppetHashing.COLLECTION_ID, "collection id matches library");
    }

    /// @notice A zero Merkle root is rejected: it is what a fail-open builder emits, and it would
    ///         make every membership check fail forever with no way to repair it.
    function test_RevertWhen_ConstructorMerkleRootIsZero() public {
        vm.expectRevert(IPuppetCollectionRegistry.ZeroValue.selector);
        new PuppetCollectionRegistry(bytes32(0), FIXTURE_MANIFEST_HASH, FIXTURE_VERSION, 11);
    }

    /// @notice A zero manifest hash is rejected: it destroys the link between this root and a
    ///         reviewable list, which is the only audit trail the contract has.
    function test_RevertWhen_ConstructorManifestHashIsZero() public {
        vm.expectRevert(IPuppetCollectionRegistry.ZeroValue.selector);
        new PuppetCollectionRegistry(FIXTURE_ROOT, bytes32(0), FIXTURE_VERSION, 11);
    }

    /// @notice A zero leaf count is rejected: it claims the manifest committed an empty set.
    function test_RevertWhen_ConstructorLeafCountIsZero() public {
        vm.expectRevert(IPuppetCollectionRegistry.ZeroValue.selector);
        new PuppetCollectionRegistry(FIXTURE_ROOT, FIXTURE_MANIFEST_HASH, FIXTURE_VERSION, 0);
    }

    /// @notice An empty version string is rejected. Not in the original prompt, but an unnamed
    ///         manifest cannot be reproduced by a third party, which defeats the reproducibility
    ///         report the whole design depends on.
    function test_RevertWhen_ConstructorManifestVersionIsEmpty() public {
        vm.expectRevert(IPuppetCollectionRegistry.ZeroValue.selector);
        new PuppetCollectionRegistry(FIXTURE_ROOT, FIXTURE_MANIFEST_HASH, "", 11);
    }

    /// @notice Construction emits the one and only event this contract will ever emit.
    function test_ConstructorEmitsCollectionCommitted() public {
        vm.expectEmit(true, true, false, true);
        emit CollectionCommitted(FIXTURE_ROOT, FIXTURE_MANIFEST_HASH, FIXTURE_VERSION, 11);
        new PuppetCollectionRegistry(FIXTURE_ROOT, FIXTURE_MANIFEST_HASH, FIXTURE_VERSION, 11);
    }

    /*//////////////////////////////////////////////////////////////
                            IDENTITY HASHING
    //////////////////////////////////////////////////////////////*/

    /// @notice `rootKey` and `leafOf` match the pinned cross-language golden vectors.
    function test_RootKeyAndLeafMatchGoldenVectors() public view {
        assertEq(registry.rootKey(roots[0]), ENTRY0_ROOT_KEY, "entry0 root key");
        assertEq(registry.leafOf(roots[0]), ENTRY0_LEAF, "entry0 leaf");
        assertEq(registry.rootKey(nonMemberRoot), NON_MEMBER_ROOT_KEY, "non-member root key");
        assertEq(registry.rootKey(singleRoot), SINGLE_LEAF_ROOT_KEY, "single-leaf root key");
        assertEq(registry.leafOf(singleRoot), SINGLE_LEAF_ROOT, "single-leaf leaf equals its root");
    }

    /// @notice Two inscriptions revealed by the SAME Bitcoin transaction are different protocol
    ///         identities. If `inscriptionIndex` were ever dropped from the preimage, sibling
    ///         inscriptions would collide and one proof would unlock both.
    function test_SharedTxidDifferentIndexAreDistinctIdentities() public view {
        assertEq(roots[2].inscriptionTxid, roots[3].inscriptionTxid, "fixture must share a txid");
        assertTrue(roots[2].inscriptionIndex != roots[3].inscriptionIndex, "fixture must differ by index");

        assertEq(registry.rootKey(roots[2]), ENTRY2_ROOT_KEY, "entry2 root key");
        assertEq(registry.rootKey(roots[3]), ENTRY3_ROOT_KEY, "entry3 root key");
        assertTrue(registry.rootKey(roots[2]) != registry.rootKey(roots[3]), "keys must differ");
        assertTrue(registry.leafOf(roots[2]) != registry.leafOf(roots[3]), "leaves must differ");
    }

    /// @notice The leaf is genuinely a SECOND hash of the root key, not the key itself. That extra
    ///         hash is what makes a 64-byte internal-node preimage unusable as a 32-byte leaf
    ///         preimage.
    function test_LeafIsDoubleHashedRootKey() public view {
        bytes32 key = registry.rootKey(roots[5]);
        assertTrue(registry.leafOf(roots[5]) != key, "leaf must not equal the root key");
        assertEq(registry.leafOf(roots[5]), keccak256(bytes.concat(key)), "leaf is keccak of the key");
    }

    /*//////////////////////////////////////////////////////////////
                            POSITIVE MEMBERSHIP
    //////////////////////////////////////////////////////////////*/

    /// @notice A member with its own proof verifies, through both entry points.
    function test_ValidMember() public view {
        bytes32[] memory proof = MerkleFixture.proofFromRoots(roots, 0);
        assertTrue(registry.isMember(roots[0], proof), "isMember");
        assertEq(registry.requireMember(roots[0], proof), ENTRY0_ROOT_KEY, "requireMember returns the proven key");
    }

    /// @notice Every one of the 11 leaves verifies against the single committed root, including the
    ///         entries whose proofs are SHORTER because an odd tail node was promoted rather than
    ///         paired. A tree helper that only works for power-of-two sizes passes a "valid member"
    ///         test and still ships a broken manifest, so this walks the whole set.
    function test_ProofForEveryLeafInLargeFixture() public view {
        assertGt(roots.length, 8, "fixture must exceed 8 leaves");

        uint256 shortProofs;
        for (uint256 i = 0; i < roots.length; i++) {
            bytes32[] memory proof = MerkleFixture.proofFromRoots(roots, i);
            assertTrue(registry.isMember(roots[i], proof), "member must verify");
            assertEq(registry.requireMember(roots[i], proof), registry.rootKey(roots[i]), "key round-trip");
            if (proof.length < 4) shortProofs++;
        }

        // 11 leaves means at least one level has an odd length, so at least one proof must be
        // shorter than the full depth. Asserting this stops the fixture from silently degenerating
        // into a balanced tree if someone edits the entry list.
        assertGt(shortProofs, 0, "odd-node promotion must be exercised");
    }

    /// @notice A single-entry manifest: the root IS the leaf and the EMPTY proof is the valid one.
    /// @dev This degenerate shape is easy to get wrong in an off-chain builder (a common bug is to
    ///      self-pair the lone leaf), and it is exactly the shape a first deployment or a hotfix
    ///      manifest would take.
    function test_SingleLeafTreeVerifiesWithEmptyProof() public view {
        bytes32[] memory empty = new bytes32[](0);
        assertEq(singleLeafRegistry.merkleRoot(), singleLeafRegistry.leafOf(singleRoot), "root equals leaf");
        assertTrue(singleLeafRegistry.isMember(singleRoot, empty), "empty proof must verify");
        assertEq(singleLeafRegistry.requireMember(singleRoot, empty), SINGLE_LEAF_ROOT_KEY, "key");
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE MEMBERSHIP
    //////////////////////////////////////////////////////////////*/

    /// @notice An inscription that is simply not in the manifest fails against every proof in it.
    function test_NonMemberIsRejected() public {
        bytes32[] memory empty = new bytes32[](0);
        assertFalse(registry.isMember(nonMemberRoot, empty), "empty proof");

        for (uint256 i = 0; i < roots.length; i++) {
            bytes32[] memory proof = MerkleFixture.proofFromRoots(roots, i);
            assertFalse(registry.isMember(nonMemberRoot, proof), "borrowed proof must not work");
        }

        vm.expectRevert(
            abi.encodeWithSelector(IPuppetCollectionRegistry.NotCollectionMember.selector, NON_MEMBER_ROOT_KEY)
        );
        registry.requireMember(nonMemberRoot, empty);
    }

    /// @notice Flipping a single byte of the txid produces a different identity, and the member's
    ///         proof does not carry over to it.
    function test_MutatedTxidIsRejected() public {
        PuppetTypes.RootId memory mutated =
            PuppetTypes.RootId({inscriptionTxid: _fixtureTxid(0x11), inscriptionIndex: roots[0].inscriptionIndex});
        bytes32[] memory proof = MerkleFixture.proofFromRoots(roots, 0);

        assertTrue(registry.isMember(roots[0], proof), "control: the unmutated entry is a member");
        assertFalse(registry.isMember(mutated, proof), "mutated txid must fail");

        vm.expectRevert(
            abi.encodeWithSelector(IPuppetCollectionRegistry.NotCollectionMember.selector, registry.rootKey(mutated))
        );
        registry.requireMember(mutated, proof);
    }

    /// @notice Same reveal txid, different inscription index: still a different inscription, still
    ///         rejected. This is the mutation a txid-only registry would wrongly accept, which is
    ///         why the index is part of the preimage.
    function test_MutatedIndexSameTxidIsRejected() public {
        PuppetTypes.RootId memory mutated =
            PuppetTypes.RootId({inscriptionTxid: roots[0].inscriptionTxid, inscriptionIndex: 1});
        bytes32[] memory proof = MerkleFixture.proofFromRoots(roots, 0);

        assertEq(mutated.inscriptionTxid, roots[0].inscriptionTxid, "txid unchanged by construction");
        assertFalse(registry.isMember(mutated, proof), "index 1 of that txid is not in the manifest");

        vm.expectRevert(
            abi.encodeWithSelector(IPuppetCollectionRegistry.NotCollectionMember.selector, registry.rootKey(mutated))
        );
        registry.requireMember(mutated, proof);
    }

    /// @notice A proof is bound to ONE leaf. Entry 3 is a genuine member, but entry 2's proof does
    ///         not authorise it — even though the two share a reveal transaction.
    function test_MemberWithAnotherMembersProofIsRejected() public view {
        bytes32[] memory proofOf2 = MerkleFixture.proofFromRoots(roots, 2);
        assertTrue(registry.isMember(roots[2], proofOf2), "control");
        assertFalse(registry.isMember(roots[3], proofOf2), "proof must not transfer between members");
    }

    /// @notice A valid proof against the WRONG committed root fails. This is what protects a
    ///         deployment from being handed proofs built over a different manifest version.
    function test_WrongRootRejectsValidProof() public {
        bytes32[] memory proof = MerkleFixture.proofFromRoots(roots, 0);

        // Same manifest, one bit different in the committed root.
        PuppetCollectionRegistry wrong = new PuppetCollectionRegistry(
            bytes32(uint256(FIXTURE_ROOT) ^ 1), FIXTURE_MANIFEST_HASH, FIXTURE_VERSION, roots.length
        );
        assertFalse(wrong.isMember(roots[0], proof), "proof must not verify under a mutated root");

        // A completely unrelated root: the single-leaf registry.
        assertFalse(singleLeafRegistry.isMember(roots[0], proof), "proof must not verify under another manifest");

        vm.expectRevert(abi.encodeWithSelector(IPuppetCollectionRegistry.NotCollectionMember.selector, ENTRY0_ROOT_KEY));
        wrong.requireMember(roots[0], proof);
    }

    /// @notice A truncated or padded proof fails. Proof length is part of the claim, not a hint.
    function test_MalformedProofLengthsAreRejected() public view {
        bytes32[] memory proof = MerkleFixture.proofFromRoots(roots, 0);
        assertGt(proof.length, 1, "fixture proof must be long enough to truncate");

        bytes32[] memory truncated = new bytes32[](proof.length - 1);
        for (uint256 i = 0; i < truncated.length; i++) {
            truncated[i] = proof[i];
        }
        assertFalse(registry.isMember(roots[0], truncated), "truncated proof");

        bytes32[] memory extended = new bytes32[](proof.length + 1);
        for (uint256 i = 0; i < proof.length; i++) {
            extended[i] = proof[i];
        }
        extended[proof.length] = FIXTURE_ROOT;
        assertFalse(registry.isMember(roots[0], extended), "extended proof");

        assertFalse(registry.isMember(roots[0], new bytes32[](0)), "empty proof against a multi-leaf tree");
    }

    /// @notice On a multi-leaf tree, the root itself is not a valid leaf. Presenting an internal
    ///         node where a leaf belongs is the second-preimage attack the double hash defeats.
    function test_RootIsNotAcceptedAsALeaf() public view {
        // There is no RootId whose leaf equals the root, because the leaf is a double hash of a
        // domain-separated key; assert the structural fact that makes that true.
        for (uint256 i = 0; i < roots.length; i++) {
            assertTrue(registry.leafOf(roots[i]) != FIXTURE_ROOT, "no leaf may equal the root");
        }
    }

    /*//////////////////////////////////////////////////////////////
                            REPRODUCIBILITY
    //////////////////////////////////////////////////////////////*/

    /// @notice The pinned root is reproduced from the raw inscription identities, and is a function
    ///         of the SET, not of the file order. Two independent builders that disagree about
    ///         manifest ordering must still agree about the root, otherwise the reproducibility
    ///         report is worthless.
    function test_DeterministicRootReproduction() public view {
        assertEq(MerkleFixture.buildFromRoots(roots), FIXTURE_ROOT, "rebuild must match the pinned root");

        PuppetTypes.RootId[] memory reversed = new PuppetTypes.RootId[](roots.length);
        for (uint256 i = 0; i < roots.length; i++) {
            reversed[i] = roots[roots.length - 1 - i];
        }
        assertEq(MerkleFixture.buildFromRoots(reversed), FIXTURE_ROOT, "reversed order must give the same root");

        // Rotating by one is a different permutation again, and catches an accidental dependence on
        // the first or last element specifically.
        PuppetTypes.RootId[] memory rotated = new PuppetTypes.RootId[](roots.length);
        for (uint256 i = 0; i < roots.length; i++) {
            rotated[i] = roots[(i + 1) % roots.length];
        }
        assertEq(MerkleFixture.buildFromRoots(rotated), FIXTURE_ROOT, "rotated order must give the same root");
    }

    /// @notice The pinned manifest hash is reproduced from the same inputs the JSON fixture
    ///         documents: `keccak256(abi.encode(collectionId, keccak256(bytes(version)), sortedLeaves))`.
    /// @dev Hashing the canonical leaf SET rather than the raw file bytes keeps the commitment
    ///      invariant to JSON whitespace and key order, so an independent implementation can
    ///      reproduce it without agreeing byte-for-byte on formatting.
    function test_ManifestHashReproduction() public view {
        bytes32[] memory sorted = _sortedLeaves();
        bytes32 computed = keccak256(abi.encode(PuppetHashing.COLLECTION_ID, keccak256(bytes(FIXTURE_VERSION)), sorted));
        assertEq(computed, FIXTURE_MANIFEST_HASH, "manifest hash");
        assertEq(registry.manifestHash(), computed, "registry commitment matches");

        bytes32[] memory singleSorted = new bytes32[](1);
        singleSorted[0] = SINGLE_LEAF_ROOT;
        assertEq(
            keccak256(abi.encode(PuppetHashing.COLLECTION_ID, keccak256(bytes(SINGLE_LEAF_VERSION)), singleSorted)),
            SINGLE_LEAF_MANIFEST_HASH,
            "single-leaf manifest hash"
        );
    }

    /// @notice The proof arrays written into `data/test-fixtures/puppets-fixture-manifest.json` are
    ///         byte-for-byte the proofs this build produces.
    /// @dev The JSON is what the TypeScript builder and the cross-language CI check are validated
    ///      against, so a stale or hand-edited proof array there must fail here. Entry 4 is included
    ///      specifically because its proof is SHORT: it sits under a promoted odd node, which is the
    ///      case an off-chain builder is most likely to get wrong.
    function test_PinnedJsonProofsMatchComputedProofs() public view {
        bytes32[] memory entry0 = new bytes32[](4);
        entry0[0] = 0x58259c751decde1860b97d4de5903c7ae90a8ec978d85c6be1a765788c335f80;
        entry0[1] = 0xa301c9abd41b5735608b959529021a90438951bc2680a0512661967fa3c12e0e;
        entry0[2] = 0x34abe7adbb8128144e292a4123e6b91d1bce7d6935c57ef039074d551c45ee24;
        entry0[3] = 0xae86ddf4c794d70881780e69176c9a91b883992d7dc49facbe47e98f11cc70b0;
        _assertProofEquals(MerkleFixture.proofFromRoots(roots, 0), entry0, "entry 0");
        assertTrue(registry.isMember(roots[0], entry0), "pinned entry 0 proof must verify");

        bytes32[] memory entry4 = new bytes32[](2);
        entry4[0] = 0xbcf006ad3fceda05ef61136e1049074d9fa15a8022d64474475ca64841b30e17;
        entry4[1] = 0x8d72c576224aaf46d62a1c1d3dfb407ee396440336fd0e295f8bec3f3aef69df;
        _assertProofEquals(MerkleFixture.proofFromRoots(roots, 4), entry4, "entry 4");
        assertTrue(registry.isMember(roots[4], entry4), "pinned entry 4 proof must verify");
    }

    /// @notice The builder refuses a manifest that lists the same inscription twice.
    /// @dev A duplicate is never benign: it means the source list is wrong, and it makes proof
    ///      generation ambiguous because two positions claim the same leaf. Rejecting beats
    ///      silently de-duplicating, which would hide the upstream error.
    function test_RevertWhen_ManifestContainsADuplicateEntry() public {
        PuppetTypes.RootId[] memory withDuplicate = new PuppetTypes.RootId[](roots.length + 1);
        for (uint256 i = 0; i < roots.length; i++) {
            withDuplicate[i] = roots[i];
        }
        withDuplicate[roots.length] = roots[4];

        vm.expectRevert(
            abi.encodeWithSelector(MerkleFixture.DuplicateLeaf.selector, PuppetHashing.collectionLeaf(roots[4]))
        );
        this.buildExternal(withDuplicate);
    }

    /// @notice External wrapper so `vm.expectRevert` can target a library call.
    /// @param input Candidate manifest entries.
    /// @return The Merkle root over `input`.
    function buildExternal(PuppetTypes.RootId[] calldata input) external pure returns (bytes32) {
        PuppetTypes.RootId[] memory copied = new PuppetTypes.RootId[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            copied[i] = input[i];
        }
        return MerkleFixture.buildFromRoots(copied);
    }

    /*//////////////////////////////////////////////////////////////
                         IMMUTABILITY / NO ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice There is no admin surface at all: no setter, no owner, no upgrade hook, no fallback.
    /// @dev Asserting a NEGATIVE about an ABI needs more than "the call reverted" — a call with
    ///      malformed arguments reverts whether or not the function exists. So this scans the
    ///      deployed runtime bytecode for each forbidden 4-byte selector. Solidity's dispatcher
    ///      embeds the selector of every external function as a literal, so a present function is
    ///      guaranteed to show up; the only failure mode is a coincidental 4-byte sequence, which
    ///      would make this test fail loudly rather than pass wrongly.
    function test_NoAdminOrUpgradeSurfaceExists() public {
        bytes4[8] memory forbidden = [
            bytes4(keccak256("setMerkleRoot(bytes32)")),
            bytes4(keccak256("setManifest(bytes32,string,uint256)")),
            bytes4(keccak256("transferOwnership(address)")),
            bytes4(keccak256("owner()")),
            bytes4(keccak256("upgradeTo(address)")),
            bytes4(keccak256("upgradeToAndCall(address,bytes)")),
            bytes4(keccak256("pause()")),
            bytes4(keccak256("initialize(bytes32,bytes32,string,uint256)"))
        ];

        bytes memory runtime = address(registry).code;
        assertGt(runtime.length, 0, "registry must be deployed");

        for (uint256 i = 0; i < forbidden.length; i++) {
            assertFalse(_codeContainsSelector(runtime, forbidden[i]), "no admin selector may exist");
            (bool ok,) = address(registry).call(abi.encodePacked(forbidden[i], bytes32(0)));
            assertFalse(ok, "no admin entry point may be callable");
        }

        // Control: a selector that DOES exist is found, proving the scan is not vacuously passing.
        assertTrue(
            _codeContainsSelector(runtime, IPuppetCollectionRegistry.merkleRoot.selector), "scan must find merkleRoot"
        );

        // No payable fallback either: this contract must never be able to hold value.
        vm.deal(address(this), 1 ether);
        (bool sent,) = address(registry).call{value: 1 ether}("");
        assertFalse(sent, "registry must reject ether");
        assertEq(address(registry).balance, 0, "registry must hold no value");
    }

    /// @notice The commitments are stable across calls and across callers. Immutability is the
    ///         contract's entire security property, so it gets an explicit assertion rather than
    ///         being taken on faith from the `immutable` keyword.
    function test_CommitmentsAreStable() public {
        bytes32 rootBefore = registry.merkleRoot();
        bytes32 hashBefore = registry.manifestHash();

        vm.prank(address(0xBEEF));
        registry.isMember(roots[0], MerkleFixture.proofFromRoots(roots, 0));
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 100_000);

        assertEq(registry.merkleRoot(), rootBefore, "root");
        assertEq(registry.manifestHash(), hashBefore, "manifest hash");
        assertEq(registry.manifestVersion(), FIXTURE_VERSION, "version");
    }

    /*//////////////////////////////////////////////////////////////
                                  FUZZ
    //////////////////////////////////////////////////////////////*/

    /// @notice A random inscription that is not in the manifest never verifies, against any of the
    ///         manifest's real proofs or against an empty proof.
    /// @param txid Fuzzed reveal txid.
    /// @param index Fuzzed inscription index.
    function testFuzz_RandomNonMemberNeverVerifies(bytes32 txid, uint32 index) public view {
        PuppetTypes.RootId memory candidate = PuppetTypes.RootId({inscriptionTxid: txid, inscriptionIndex: index});
        bytes32 leaf = PuppetHashing.collectionLeaf(candidate);

        // Discard the (cryptographically negligible) case where the fuzzer lands on a real member.
        for (uint256 i = 0; i < roots.length; i++) {
            vm.assume(leaf != PuppetHashing.collectionLeaf(roots[i]));
        }

        assertFalse(registry.isMember(candidate, new bytes32[](0)), "empty proof");
        for (uint256 i = 0; i < roots.length; i++) {
            assertFalse(registry.isMember(candidate, MerkleFixture.proofFromRoots(roots, i)), "borrowed proof");
        }
    }

    /// @notice A fuzzed proof never lets a non-member in, and never lets a member in either unless
    ///         it happens to be that member's real proof.
    /// @param txid Fuzzed reveal txid.
    /// @param index Fuzzed inscription index.
    /// @param fuzzedProof Fuzzed sibling hashes.
    function testFuzz_ForgedProofNeverVerifies(bytes32 txid, uint32 index, bytes32[] calldata fuzzedProof) public view {
        // Bound the proof length: beyond the tree depth the outcome is uninteresting and the run
        // just burns gas.
        vm.assume(fuzzedProof.length <= 8);

        PuppetTypes.RootId memory candidate = PuppetTypes.RootId({inscriptionTxid: txid, inscriptionIndex: index});
        bytes32 leaf = PuppetHashing.collectionLeaf(candidate);
        for (uint256 i = 0; i < roots.length; i++) {
            vm.assume(leaf != PuppetHashing.collectionLeaf(roots[i]));
        }

        assertFalse(registry.isMember(candidate, fuzzedProof), "forged proof must not verify");
    }

    /// @notice `isMember` and `requireMember` can never disagree. A caller that switches between
    ///         them must not change the security outcome.
    /// @param index Fuzzed selector over the fixture entries and the non-member.
    /// @param proofIndex Fuzzed selector over which entry's proof is presented.
    function testFuzz_IsMemberAndRequireMemberAgree(uint256 index, uint256 proofIndex) public {
        index = bound(index, 0, roots.length); // roots.length selects the non-member
        proofIndex = bound(proofIndex, 0, roots.length - 1);

        PuppetTypes.RootId memory candidate = index == roots.length ? nonMemberRoot : roots[index];
        bytes32[] memory proof = MerkleFixture.proofFromRoots(roots, proofIndex);

        bool ok = registry.isMember(candidate, proof);
        assertEq(ok, index == proofIndex, "membership holds exactly when the proof matches the entry");

        if (!ok) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IPuppetCollectionRegistry.NotCollectionMember.selector, registry.rootKey(candidate)
                )
            );
        }
        registry.requireMember(candidate, proof);
    }

    /// @notice `rootKey` is injective over `(txid, index)`: two distinct inscriptions can never
    ///         share a protocol key, which is what stops one membership proof covering two Puppets.
    /// @param txidA First reveal txid.
    /// @param indexA First inscription index.
    /// @param txidB Second reveal txid.
    /// @param indexB Second inscription index.
    function testFuzz_RootKeyIsInjective(bytes32 txidA, uint32 indexA, bytes32 txidB, uint32 indexB) public view {
        vm.assume(txidA != txidB || indexA != indexB);
        PuppetTypes.RootId memory a = PuppetTypes.RootId({inscriptionTxid: txidA, inscriptionIndex: indexA});
        PuppetTypes.RootId memory b = PuppetTypes.RootId({inscriptionTxid: txidB, inscriptionIndex: indexB});
        assertTrue(registry.rootKey(a) != registry.rootKey(b), "root keys must not collide");
        assertTrue(registry.leafOf(a) != registry.leafOf(b), "leaves must not collide");
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Element-wise proof comparison, so a mismatch names the position rather than just
    ///      reporting "arrays differ".
    function _assertProofEquals(bytes32[] memory actual, bytes32[] memory expected, string memory label) internal pure {
        assertEq(actual.length, expected.length, string.concat(label, ": proof length"));
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(actual[i], expected[i], string.concat(label, ": proof element"));
        }
    }

    /// @dev True if `runtime` contains `selector` as a contiguous 4-byte sequence.
    function _codeContainsSelector(bytes memory runtime, bytes4 selector) internal pure returns (bool) {
        if (runtime.length < 4) return false;
        for (uint256 i = 0; i + 4 <= runtime.length; i++) {
            if (
                runtime[i] == selector[0] && runtime[i + 1] == selector[1] && runtime[i + 2] == selector[2]
                    && runtime[i + 3] == selector[3]
            ) {
                return true;
            }
        }
        return false;
    }

    /// @dev Build a self-identifying fixture txid: ASCII "FIXTURE-NOT-REAL" then a counter.
    function _fixtureTxid(uint256 tag) internal pure returns (bytes32) {
        return bytes32(uint256(FIXTURE_TXID_PREFIX) | tag);
    }

    function _add(uint256 tag, uint32 index) internal {
        roots.push(PuppetTypes.RootId({inscriptionTxid: _fixtureTxid(tag), inscriptionIndex: index}));
    }

    /// @dev Fixture leaves sorted ascending as unsigned big-endian integers, mirroring the ordering
    ///      rule the Merkle builder and the JSON fixture both document. Insertion sort: the fixture
    ///      is tiny and clarity beats cleverness in a file that defines golden vectors.
    function _sortedLeaves() internal view returns (bytes32[] memory out) {
        out = new bytes32[](roots.length);
        for (uint256 i = 0; i < roots.length; i++) {
            out[i] = PuppetHashing.collectionLeaf(roots[i]);
        }
        for (uint256 i = 1; i < out.length; i++) {
            bytes32 key = out[i];
            uint256 j = i;
            while (j > 0 && out[j - 1] > key) {
                out[j] = out[j - 1];
                j--;
            }
            out[j] = key;
        }
    }
}
