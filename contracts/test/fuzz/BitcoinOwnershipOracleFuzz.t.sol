// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {BitcoinOwnershipOracle} from "../../src/BitcoinOwnershipOracle.sol";
import {PuppetCollectionRegistry} from "../../src/PuppetCollectionRegistry.sol";
import {IBitcoinOwnershipOracle} from "../../src/interfaces/IBitcoinOwnershipOracle.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";
import {AttestorSet} from "../helpers/AttestorSet.sol";
import {MerkleFixture} from "../helpers/MerkleFixture.sol";
import {ConsumerHarness} from "../mocks/ConsumerHarness.sol";
import {MockAttestorRegistry} from "../mocks/MockAttestorRegistry.sol";

/// @title BitcoinOwnershipOracleFuzz
/// @notice Property-based campaign over the oracle's signature handling and digest binding.
/// @dev WHAT THIS FILE IS FOR, AS DISTINCT FROM THE UNIT SUITE.
///      The unit suite pins named cases: three-of-five, one duplicate, one unsorted array. Those
///      cases were chosen by the same person who wrote the code, which is exactly the blind spot
///      fuzzing exists to cover. Here the campaign asks structural questions instead:
///
///        - is EVERY signer subset of size >= threshold accepted, and every smaller one rejected?
///        - is EVERY non-ascending permutation of a genuinely valid quorum rejected?
///        - is EVERY single-field mutation of an attestation bound into the digest, and does the
///          previously-collected quorum then fail?
///        - can random bytes ever be mistaken for a quorum?
///
///      A note on how failures are asserted. Several properties are "this must not succeed"
///      without a predictable revert reason — a signature over a digest nobody chose recovers to
///      an address chosen by the curve, so neither the error's arguments nor, sometimes, its
///      selector is knowable in advance. Those use `try/catch` with an explicit `fail()` in the
///      success branch rather than a bare `vm.expectRevert()`, so the assertion states "did not
///      succeed" rather than "reverted for some reason I did not look at". forge-std's `fail()`
///      takes no message in this version, so the success branch asserts `false` with the message.
///
///      TRUST BOUNDARY: nothing here verifies a Bitcoin fact. These are signature properties.
contract BitcoinOwnershipOracleFuzz is Test {
    uint64 internal constant EPOCH = 7;
    uint32 internal constant POLICY = 3;
    uint8 internal constant THRESHOLD = 3;
    uint256 internal constant ATTESTOR_COUNT = 5;

    AttestorSet internal attestors;
    MockAttestorRegistry internal registry;
    PuppetCollectionRegistry internal collection;
    BitcoinOwnershipOracle internal oracle;
    ConsumerHarness internal escrowConsumer;
    ConsumerHarness internal settlementConsumer;

    PuppetTypes.RootId[] internal fixtureRoots;

    function setUp() public {
        vm.warp(1_700_000_000);

        attestors = new AttestorSet(ATTESTOR_COUNT, keccak256("HOODPUPS_ORACLE_FUZZ_V1"));
        registry = new MockAttestorRegistry(attestors.addresses(), THRESHOLD, EPOCH, POLICY);

        fixtureRoots.push(PuppetTypes.RootId({inscriptionTxid: _fixtureTxid("fuzz-root-a"), inscriptionIndex: 0}));
        fixtureRoots.push(PuppetTypes.RootId({inscriptionTxid: _fixtureTxid("fuzz-root-b"), inscriptionIndex: 3}));
        fixtureRoots.push(PuppetTypes.RootId({inscriptionTxid: _fixtureTxid("fuzz-root-c"), inscriptionIndex: 11}));

        collection = new PuppetCollectionRegistry(
            MerkleFixture.build(MerkleFixture.leavesOf(_rootsMemory())),
            keccak256("HOODPUPS_ORACLE_FUZZ_MANIFEST"),
            "hoodpups-oracle-fuzz-v1",
            fixtureRoots.length
        );

        oracle = new BitcoinOwnershipOracle(address(this), collection, registry);

        escrowConsumer = new ConsumerHarness(IBitcoinOwnershipOracle(address(oracle)));
        settlementConsumer = new ConsumerHarness(IBitcoinOwnershipOracle(address(oracle)));

        uint8[] memory mintPurposes = new uint8[](3);
        mintPurposes[0] = uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT);
        mintPurposes[1] = uint8(PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT);
        mintPurposes[2] = uint8(PuppetTypes.AuthorizationPurpose.SELF_CAST);
        oracle.grantOwnershipConsumer(address(escrowConsumer), mintPurposes);
        oracle.grantRole(oracle.PAYMENT_CONSUMER_ROLE(), address(settlementConsumer));
    }

    /*//////////////////////////////////////////////////////////////
                        SIGNATURE COUNT AND SUBSET
    //////////////////////////////////////////////////////////////*/

    /// @dev Every subset of the attestor set is either accepted or rejected purely on its SIZE.
    ///      Which three of the five operators sign must never matter — if it did, some operators
    ///      would be more equal than others, which is not what "3-of-5" means.
    function testFuzz_AnySubsetOfSizeAtLeastThresholdVerifies(uint256 seed, uint8 size) public view {
        uint256 k = bound(size, THRESHOLD, ATTESTOR_COUNT);
        uint256[] memory subset = _randomSubset(seed, k);

        PuppetTypes.OwnershipAttestation memory a = _ownership();
        bytes32 digest = oracle.hashOwnershipAttestation(a);

        (bytes32 verified,) = oracle.verifyOwnership(a, attestors.signWith(digest, subset), _proof(0));
        assertEq(verified, digest, "any quorum of at least the threshold size must verify");
    }

    function testFuzz_AnySubsetBelowThresholdIsRejected(uint256 seed, uint8 size) public {
        uint256 k = bound(size, 0, THRESHOLD - 1);
        uint256[] memory subset = _randomSubset(seed, k);

        PuppetTypes.OwnershipAttestation memory a = _ownership();
        bytes[] memory signatures = attestors.signWith(oracle.hashOwnershipAttestation(a), subset);
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.InsufficientSignatures.selector, k, THRESHOLD));
        oracle.verifyOwnership(a, signatures, proof);
    }

    /// @dev A genuinely valid quorum, reordered. Only the strictly-ascending arrangement may be
    ///      accepted; every other permutation must be rejected. This is what makes the accepted
    ///      form of a quorum canonical.
    function testFuzz_OnlyTheAscendingPermutationIsAccepted(uint256 seed, uint8 size) public {
        uint256 k = bound(size, THRESHOLD, ATTESTOR_COUNT);
        uint256[] memory subset = _randomSubset(seed, k);

        PuppetTypes.OwnershipAttestation memory a = _ownership();
        bytes32 digest = oracle.hashOwnershipAttestation(a);

        // `signWith` returns the ascending arrangement; permute it and track the signer order.
        bytes[] memory signatures = attestors.signWith(digest, subset);
        address[] memory signers = _signersOf(subset);
        _permute(signatures, signers, seed);

        bool ascending = _isStrictlyAscending(signers);
        bytes32[] memory proof = _proof(0);

        if (ascending) {
            (bytes32 verified,) = oracle.verifyOwnership(a, signatures, proof);
            assertEq(verified, digest, "the ascending arrangement must verify");
        } else {
            vm.expectPartialRevert(IBitcoinOwnershipOracle.SignersNotStrictlyAscending.selector);
            oracle.verifyOwnership(a, signatures, proof);
        }
    }

    /// @dev Repeating any signer at any position must be rejected, no matter how many genuine
    ///      operators are also present. Quorum inflation is the attack this closes.
    function testFuzz_ADuplicatedSignerIsAlwaysRejected(uint256 seed, uint8 size, uint8 slot) public {
        uint256 k = bound(size, THRESHOLD, ATTESTOR_COUNT);
        uint256[] memory subset = _randomSubset(seed, k);
        uint256 position = bound(slot, 0, k - 1);

        PuppetTypes.OwnershipAttestation memory a = _ownership();
        bytes[] memory ascending = attestors.signWith(oracle.hashOwnershipAttestation(a), subset);

        // Insert a copy of the signature at `position` immediately after it: the array stays
        // non-decreasing, which is precisely the shape that a naive "is it sorted?" check misses.
        bytes[] memory inflated = new bytes[](k + 1);
        uint256 cursor = 0;
        for (uint256 i = 0; i < k; i++) {
            inflated[cursor++] = ascending[i];
            if (i == position) inflated[cursor++] = ascending[i];
        }
        bytes32[] memory proof = _proof(0);

        vm.expectPartialRevert(IBitcoinOwnershipOracle.SignersNotStrictlyAscending.selector);
        oracle.verifyOwnership(a, inflated, proof);
    }

    /// @dev Random bytes must never be mistaken for a quorum, whatever their length.
    function testFuzz_RandomSignatureBytesNeverVerify(bytes32 entropy, uint8 lengthSeed) public view {
        uint256 length = bound(lengthSeed, 0, 96);

        bytes[] memory garbage = new bytes[](THRESHOLD);
        for (uint256 i = 0; i < THRESHOLD; i++) {
            bytes memory blob = new bytes(length);
            for (uint256 j = 0; j < length; j++) {
                blob[j] = bytes1(uint8(uint256(keccak256(abi.encode(entropy, i, j)))));
            }
            garbage[i] = blob;
        }

        PuppetTypes.OwnershipAttestation memory a = _ownership();
        bytes32[] memory proof = _proof(0);

        try oracle.verifyOwnership(a, garbage, proof) returns (bytes32, bytes32) {
            assertTrue(false, "random bytes were accepted as a quorum");
        } catch {}
    }

    /// @dev A non-attestor's signature is worthless no matter which position it occupies.
    function testFuzz_AnOutsiderSignatureIsNeverCounted(uint256 seed) public {
        PuppetTypes.OwnershipAttestation memory a = _ownership();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory signatures = attestors.signWithOutsider(digest, bound(seed, THRESHOLD, ATTESTOR_COUNT - 1));
        bytes32[] memory proof = _proof(0);

        address outsider = attestors.outsider();
        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.SignerNotAttestor.selector, outsider));
        oracle.verifyOwnership(a, signatures, proof);
    }

    /*//////////////////////////////////////////////////////////////
                         FIELD-MUTATION BINDING
    //////////////////////////////////////////////////////////////*/

    /// @dev Mutate exactly one field of an ownership attestation to a fuzzed value. Two properties
    ///      must hold together: the digest MOVES (so the field is genuinely part of what was
    ///      signed), and the quorum collected for the original attestation no longer verifies the
    ///      mutated one. The second is the property that matters operationally — a relayer must not
    ///      be able to edit a signed fact in flight.
    function testFuzz_MutatingAnyOwnershipFieldBreaksTheQuorum(uint8 fieldSeed, uint256 valueSeed) public view {
        uint256 field = bound(fieldSeed, 0, 21);

        PuppetTypes.OwnershipAttestation memory original = _ownership();
        bytes32 originalDigest = oracle.hashOwnershipAttestation(original);
        bytes[] memory signatures = attestors.sign(originalDigest, THRESHOLD);
        bytes32[] memory proof = _proof(0);

        PuppetTypes.OwnershipAttestation memory mutated = _mutateOwnership(original, field, valueSeed);
        bytes32 mutatedDigest = oracle.hashOwnershipAttestation(mutated);
        // A fuzzed value can coincide with the original; that is not a mutation.
        vm.assume(mutatedDigest != originalDigest);

        try oracle.verifyOwnership(mutated, signatures, proof) returns (bytes32, bytes32) {
            assertTrue(false, "a quorum for one attestation verified a different one");
        } catch {}
    }

    function testFuzz_MutatingAnyPaymentFieldBreaksTheQuorum(uint8 fieldSeed, uint256 valueSeed) public view {
        uint256 field = bound(fieldSeed, 0, 12);

        PuppetTypes.BitcoinPaymentAttestation memory original = _payment();
        bytes32 originalDigest = oracle.hashBitcoinPaymentAttestation(original);
        bytes[] memory signatures = attestors.sign(originalDigest, THRESHOLD);

        PuppetTypes.BitcoinPaymentAttestation memory mutated = _mutatePayment(original, field, valueSeed);
        vm.assume(oracle.hashBitcoinPaymentAttestation(mutated) != originalDigest);

        try oracle.verifyBitcoinPayment(mutated, signatures) returns (bytes32, bytes32) {
            assertTrue(false, "a quorum for one payment verified a different one");
        } catch {}
    }

    function testFuzz_MutatingAnyRootSpendFieldBreaksTheQuorum(uint8 fieldSeed, uint256 valueSeed) public view {
        uint256 field = bound(fieldSeed, 0, 9);

        PuppetTypes.RootSpendAttestation memory original = _rootSpend();
        bytes32 originalDigest = oracle.hashRootSpendAttestation(original);
        bytes[] memory signatures = attestors.sign(originalDigest, THRESHOLD);
        bytes32[] memory proof = _proof(0);

        PuppetTypes.RootSpendAttestation memory mutated = _mutateRootSpend(original, field, valueSeed);
        vm.assume(oracle.hashRootSpendAttestation(mutated) != originalDigest);

        try oracle.verifyRootSpend(mutated, signatures, proof) returns (bytes32, bytes32) {
            assertTrue(false, "a quorum for one spend verified a different one");
        } catch {}
    }

    /*//////////////////////////////////////////////////////////////
                       FRESHNESS AND CONSUMPTION
    //////////////////////////////////////////////////////////////*/

    /// @dev Any epoch or policy other than the live pair must be rejected, in both directions.
    function testFuzz_OnlyTheLiveEpochAndPolicyAreAccepted(uint64 epoch, uint32 policy) public {
        PuppetTypes.OwnershipAttestation memory a = _ownership();
        a.attestorEpoch = epoch;
        a.policyVersion = policy;

        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        if (epoch != EPOCH) {
            vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.StaleAttestorEpoch.selector, epoch, EPOCH));
            oracle.verifyOwnership(a, signatures, proof);
        } else if (policy != POLICY) {
            vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.StalePolicyVersion.selector, policy, POLICY));
            oracle.verifyOwnership(a, signatures, proof);
        } else {
            (bytes32 verified,) = oracle.verifyOwnership(a, signatures, proof);
            assertEq(verified, oracle.hashOwnershipAttestation(a), "the live pair must verify");
        }
    }

    /// @dev The deadline boundary is inclusive at every timestamp, not just the one the unit suite
    ///      happens to warp to.
    function testFuzz_DeadlineBoundaryIsInclusive(uint64 deadline, uint64 nowTs) public {
        uint256 timestamp = bound(nowTs, 1, type(uint40).max);
        vm.warp(timestamp);

        PuppetTypes.OwnershipAttestation memory a = _ownership();
        a.deadline = deadline;
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        if (deadline < timestamp) {
            vm.expectRevert(
                abi.encodeWithSelector(IBitcoinOwnershipOracle.DeadlineExpired.selector, deadline, timestamp)
            );
            oracle.verifyOwnership(a, signatures, proof);
        } else {
            (bytes32 verified,) = oracle.verifyOwnership(a, signatures, proof);
            assertEq(verified, oracle.hashOwnershipAttestation(a), "a live deadline must verify");
        }
    }

    /// @dev Once consumed, no signature count, subset or ordering revives a digest.
    function testFuzz_AConsumedDigestNeverVerifiesAgain(uint256 seed, uint8 size) public {
        PuppetTypes.OwnershipAttestation memory a = _ownership();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes32[] memory proof = _proof(0);

        escrowConsumer.consumeOwnership(a, attestors.sign(digest, THRESHOLD), proof);

        uint256 k = bound(size, THRESHOLD, ATTESTOR_COUNT);
        bytes[] memory retry = attestors.signWith(digest, _randomSubset(seed, k));

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.DigestAlreadyConsumed.selector, digest));
        oracle.verifyOwnership(a, retry, proof);
    }

    /// @dev One Bitcoin output settles at most one offer, whatever else changes around it. The
    ///      fuzzed second attestation shares only `(bitcoinTxid, outputIndex)` with the first.
    function testFuzz_OneBitcoinOutputSettlesAtMostOneOffer(
        bytes32 contextId,
        bytes32 ownershipDigest,
        bytes32 authorizationId,
        address solver,
        uint64 amountSats
    ) public {
        vm.assume(solver != address(0));
        vm.assume(ownershipDigest != bytes32(0));
        vm.assume(authorizationId != bytes32(0));
        amountSats = uint64(bound(amountSats, 1, type(uint64).max));

        PuppetTypes.BitcoinPaymentAttestation memory first = _payment();
        settlementConsumer.consumeBitcoinPayment(
            first, attestors.sign(oracle.hashBitcoinPaymentAttestation(first), THRESHOLD)
        );

        PuppetTypes.BitcoinPaymentAttestation memory second = _payment();
        second.contextId = contextId;
        second.ownershipDigest = ownershipDigest;
        second.authorizationId = authorizationId;
        second.solver = solver;
        second.amountSats = amountSats;

        bytes[] memory signatures = attestors.sign(oracle.hashBitcoinPaymentAttestation(second), THRESHOLD);
        bytes32 key = PuppetHashing.paymentOutputKey(second.bitcoinTxid, second.outputIndex);

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.PaymentOutputAlreadyConsumed.selector, key));
        settlementConsumer.consumeBitcoinPayment(second, signatures);
    }

    /*//////////////////////////////////////////////////////////////
                          ACCESS AND ENCODINGS
    //////////////////////////////////////////////////////////////*/

    /// @dev No address outside the granted consumers may ever burn an authorization, however the
    ///      quorum is arranged.
    function testFuzz_NoUngrantedCallerCanConsume(address caller, uint256 seed, uint8 size) public {
        vm.assume(caller != address(escrowConsumer));
        vm.assume(caller != address(settlementConsumer));

        uint256 k = bound(size, THRESHOLD, ATTESTOR_COUNT);
        PuppetTypes.OwnershipAttestation memory a = _ownership();
        bytes[] memory signatures = attestors.signWith(oracle.hashOwnershipAttestation(a), _randomSubset(seed, k));
        bytes32[] memory proof = _proof(0);

        vm.prank(caller);
        try oracle.consumeOwnership(a, signatures, proof) returns (bytes32, bytes32) {
            assertTrue(false, "an ungranted caller consumed an authorization");
        } catch {}
    }

    /// @dev The two accepted encodings must be interchangeable for every digest: an attestor's
    ///      choice of encoding cannot change whether their signature counts.
    function testFuzz_CompactAndCanonicalEncodingsAreInterchangeable(bytes32 entropy, uint8 size) public view {
        uint256 k = bound(size, THRESHOLD, ATTESTOR_COUNT);

        PuppetTypes.OwnershipAttestation memory a = _ownership();
        a.authorizationId = entropy == bytes32(0) ? keccak256("fallback") : entropy;
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes32[] memory proof = _proof(0);

        uint256[] memory subset = _firstIndices(k);
        (bytes32 fromCanonical,) = oracle.verifyOwnership(a, attestors.signWith(digest, subset), proof);
        (bytes32 fromCompact,) = oracle.verifyOwnership(a, attestors.signCompactWith(digest, subset), proof);

        assertEq(fromCanonical, digest, "canonical encoding");
        assertEq(fromCompact, digest, "compact encoding");
    }

    /// @dev The purpose bitmask round-trips: whatever set an admin configures is exactly the set
    ///      `isPurposeAllowed` reports, and nothing else is allowed.
    function testFuzz_PurposeMaskRoundTrips(uint8 rawMask) public {
        uint8 wanted = uint8(bound(rawMask, 0, 31)); // five purposes, bits 0..4

        uint256 count;
        for (uint256 i = 0; i < 5; i++) {
            if ((wanted >> i) & 1 == 1) count++;
        }
        uint8[] memory purposes = new uint8[](count);
        uint256 cursor;
        for (uint256 i = 0; i < 5; i++) {
            // casting to 'uint8' is safe because the loop bounds i to 0..4.
            // forge-lint: disable-next-line(unsafe-typecast)
            if ((wanted >> i) & 1 == 1) purposes[cursor++] = uint8(i);
        }

        oracle.setConsumerPurposes(address(escrowConsumer), purposes);
        assertEq(oracle.consumerPurposeMask(address(escrowConsumer)), wanted, "mask round-trip");

        for (uint256 i = 0; i < 5; i++) {
            assertEq(
                // casting to 'uint8' is safe because the loop bounds i to 0..4.
                // forge-lint: disable-next-line(unsafe-typecast)
                oracle.isPurposeAllowed(address(escrowConsumer), uint8(i)),
                (wanted >> i) & 1 == 1,
                "isPurposeAllowed must agree with the stored mask"
            );
        }
    }

    /// @dev Distinct roots never collide into one key, so no inscription can be proven by another's
    ///      identity.
    function testFuzz_RootKeyIsInjective(bytes32 txidA, uint32 indexA, bytes32 txidB, uint32 indexB) public pure {
        vm.assume(txidA != txidB || indexA != indexB);
        assertTrue(PuppetHashing.rootKey(txidA, indexA) != PuppetHashing.rootKey(txidB, indexB));
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    // Truncating the keccak output to 16 bytes is the point: the first half of every fixture txid
    // is the literal marker "FIXTURE-NOT-REAL", so no value here can be mistaken for a real one.
    // forge-lint: disable-next-item(unsafe-typecast)
    function _fixtureTxid(string memory tag) internal pure returns (bytes32) {
        return bytes32(bytes.concat(bytes16("FIXTURE-NOT-REAL"), bytes16(keccak256(bytes(tag)))));
    }

    function _rootsMemory() internal view returns (PuppetTypes.RootId[] memory out) {
        out = new PuppetTypes.RootId[](fixtureRoots.length);
        for (uint256 i = 0; i < fixtureRoots.length; i++) {
            out[i] = fixtureRoots[i];
        }
    }

    function _proof(uint256 index) internal view returns (bytes32[] memory) {
        return MerkleFixture.proof(MerkleFixture.leavesOf(_rootsMemory()), index);
    }

    function _firstIndices(uint256 k) internal pure returns (uint256[] memory indices) {
        indices = new uint256[](k);
        for (uint256 i = 0; i < k; i++) {
            indices[i] = i;
        }
    }

    /// @dev A uniformly-drawn distinct subset of attestor creation indices, via a seeded partial
    ///      Fisher-Yates shuffle. Distinctness matters: a subset with a repeat would be testing the
    ///      duplicate rule, not the subset rule.
    function _randomSubset(uint256 seed, uint256 k) internal pure returns (uint256[] memory subset) {
        uint256[] memory pool = new uint256[](ATTESTOR_COUNT);
        for (uint256 i = 0; i < ATTESTOR_COUNT; i++) {
            pool[i] = i;
        }
        for (uint256 i = 0; i < k; i++) {
            uint256 j = i + (uint256(keccak256(abi.encode(seed, i))) % (ATTESTOR_COUNT - i));
            (pool[i], pool[j]) = (pool[j], pool[i]);
        }
        subset = new uint256[](k);
        for (uint256 i = 0; i < k; i++) {
            subset[i] = pool[i];
        }
    }

    /// @dev Attestor addresses for `subset`, sorted ascending — the order `AttestorSet.signWith`
    ///      produces, so position `i` of the returned array is the signer of signature `i`.
    function _signersOf(uint256[] memory subset) internal view returns (address[] memory signers) {
        signers = new address[](subset.length);
        for (uint256 i = 0; i < subset.length; i++) {
            signers[i] = attestors.addressAt(subset[i]);
        }
        for (uint256 i = 1; i < signers.length; i++) {
            address key = signers[i];
            uint256 j = i;
            while (j > 0 && signers[j - 1] > key) {
                signers[j] = signers[j - 1];
                j--;
            }
            signers[j] = key;
        }
    }

    /// @dev Shuffles the signature array and the parallel signer array together, so the caller can
    ///      still say exactly which signer sits at which position after the shuffle.
    function _permute(bytes[] memory signatures, address[] memory signers, uint256 seed) internal pure {
        uint256 n = signatures.length;
        for (uint256 i = n; i > 1; i--) {
            uint256 j = uint256(keccak256(abi.encode(seed, "permute", i))) % i;
            (signatures[i - 1], signatures[j]) = (signatures[j], signatures[i - 1]);
            (signers[i - 1], signers[j]) = (signers[j], signers[i - 1]);
        }
    }

    function _isStrictlyAscending(address[] memory values) internal pure returns (bool) {
        for (uint256 i = 1; i < values.length; i++) {
            if (values[i] <= values[i - 1]) return false;
        }
        return true;
    }

    function _ownership() internal view returns (PuppetTypes.OwnershipAttestation memory a) {
        a = PuppetTypes.OwnershipAttestation({
            purpose: uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT),
            rootTxid: fixtureRoots[0].inscriptionTxid,
            rootIndex: fixtureRoots[0].inscriptionIndex,
            contextId: keccak256("fuzz-offer"),
            offerTermsHash: keccak256("fuzz-terms"),
            currentOutpointHash: PuppetHashing.outpointHash(_fixtureTxid("fuzz-outpoint"), 0),
            ownerScriptHash: keccak256("fuzz-owner-script"),
            bip322ProofHash: keccak256("fuzz-bip322"),
            buyer: address(0x2222222222222222222222222222222222222222),
            recipient: address(0x3333333333333333333333333333333333333333),
            payoutMode: uint8(PuppetTypes.PayoutMode.EVM),
            evmPayout: address(0x4444444444444444444444444444444444444444),
            btcPayoutScriptHash: bytes32(0),
            sellerSats: 0,
            grossWei: 1 ether,
            sellerWei: 0.5 ether,
            bitcoinBlockHash: keccak256("fuzz-block"),
            bitcoinHeight: 880_000,
            authorizationId: keccak256("fuzz-authorization"),
            deadline: uint64(block.timestamp + 1 hours),
            attestorEpoch: EPOCH,
            policyVersion: POLICY
        });
    }

    function _payment() internal view returns (PuppetTypes.BitcoinPaymentAttestation memory a) {
        a = PuppetTypes.BitcoinPaymentAttestation({
            contextId: keccak256("fuzz-offer"),
            ownershipDigest: keccak256("fuzz-ownership-digest"),
            solver: address(0x5555555555555555555555555555555555555555),
            bitcoinTxid: _fixtureTxid("fuzz-payment-transaction"),
            outputIndex: 2,
            recipientScriptHash: keccak256("fuzz-seller-script"),
            amountSats: 250_000,
            bitcoinBlockHash: keccak256("fuzz-block"),
            bitcoinHeight: 880_001,
            authorizationId: keccak256("fuzz-payment-authorization"),
            deadline: uint64(block.timestamp + 1 hours),
            attestorEpoch: EPOCH,
            policyVersion: POLICY
        });
    }

    function _rootSpend() internal view returns (PuppetTypes.RootSpendAttestation memory a) {
        a = PuppetTypes.RootSpendAttestation({
            rootTxid: fixtureRoots[0].inscriptionTxid,
            rootIndex: fixtureRoots[0].inscriptionIndex,
            previousOutpointHash: PuppetHashing.outpointHash(_fixtureTxid("fuzz-outpoint"), 0),
            spendingTxid: _fixtureTxid("fuzz-spending-transaction"),
            bitcoinBlockHash: keccak256("fuzz-block"),
            bitcoinHeight: 880_002,
            authorizationId: keccak256("fuzz-spend-authorization"),
            deadline: uint64(block.timestamp + 1 hours),
            attestorEpoch: EPOCH,
            policyVersion: POLICY
        });
    }

    /// @dev Replaces exactly one field with a fuzz-derived value. Field indices follow the frozen
    ///      declaration order in `PuppetTypes.OwnershipAttestation`.
    // TRUNCATION IS THE POINT HERE. Each branch narrows one fuzzed `uint256` to the exact
    // width of the field being mutated, which is how a random value becomes a legal value of
    // that field. A checked cast would reject most of the fuzzer's input and shrink the
    // mutation space to almost nothing, which is the opposite of what this campaign needs.
    // forge-lint: disable-next-item(unsafe-typecast)
    function _mutateOwnership(PuppetTypes.OwnershipAttestation memory base, uint256 field, uint256 value)
        internal
        pure
        returns (PuppetTypes.OwnershipAttestation memory a)
    {
        a = base;
        if (field == 0) a.purpose = uint8(value);
        else if (field == 1) a.rootTxid = bytes32(value);
        else if (field == 2) a.rootIndex = uint32(value);
        else if (field == 3) a.contextId = bytes32(value);
        else if (field == 4) a.offerTermsHash = bytes32(value);
        else if (field == 5) a.currentOutpointHash = bytes32(value);
        else if (field == 6) a.ownerScriptHash = bytes32(value);
        else if (field == 7) a.bip322ProofHash = bytes32(value);
        else if (field == 8) a.buyer = address(uint160(value));
        else if (field == 9) a.recipient = address(uint160(value));
        else if (field == 10) a.payoutMode = uint8(value);
        else if (field == 11) a.evmPayout = address(uint160(value));
        else if (field == 12) a.btcPayoutScriptHash = bytes32(value);
        else if (field == 13) a.sellerSats = uint64(value);
        else if (field == 14) a.grossWei = value;
        else if (field == 15) a.sellerWei = value;
        else if (field == 16) a.bitcoinBlockHash = bytes32(value);
        else if (field == 17) a.bitcoinHeight = uint64(value);
        else if (field == 18) a.authorizationId = bytes32(value);
        else if (field == 19) a.deadline = uint64(value);
        else if (field == 20) a.attestorEpoch = uint64(value);
        else a.policyVersion = uint32(value);
    }

    // TRUNCATION IS THE POINT HERE. Each branch narrows one fuzzed `uint256` to the exact
    // width of the field being mutated, which is how a random value becomes a legal value of
    // that field. A checked cast would reject most of the fuzzer's input and shrink the
    // mutation space to almost nothing, which is the opposite of what this campaign needs.
    // forge-lint: disable-next-item(unsafe-typecast)
    function _mutatePayment(PuppetTypes.BitcoinPaymentAttestation memory base, uint256 field, uint256 value)
        internal
        pure
        returns (PuppetTypes.BitcoinPaymentAttestation memory a)
    {
        a = base;
        if (field == 0) a.contextId = bytes32(value);
        else if (field == 1) a.ownershipDigest = bytes32(value);
        else if (field == 2) a.solver = address(uint160(value));
        else if (field == 3) a.bitcoinTxid = bytes32(value);
        else if (field == 4) a.outputIndex = uint32(value);
        else if (field == 5) a.recipientScriptHash = bytes32(value);
        else if (field == 6) a.amountSats = uint64(value);
        else if (field == 7) a.bitcoinBlockHash = bytes32(value);
        else if (field == 8) a.bitcoinHeight = uint64(value);
        else if (field == 9) a.authorizationId = bytes32(value);
        else if (field == 10) a.deadline = uint64(value);
        else if (field == 11) a.attestorEpoch = uint64(value);
        else a.policyVersion = uint32(value);
    }

    // TRUNCATION IS THE POINT HERE. Each branch narrows one fuzzed `uint256` to the exact
    // width of the field being mutated, which is how a random value becomes a legal value of
    // that field. A checked cast would reject most of the fuzzer's input and shrink the
    // mutation space to almost nothing, which is the opposite of what this campaign needs.
    // forge-lint: disable-next-item(unsafe-typecast)
    function _mutateRootSpend(PuppetTypes.RootSpendAttestation memory base, uint256 field, uint256 value)
        internal
        pure
        returns (PuppetTypes.RootSpendAttestation memory a)
    {
        a = base;
        if (field == 0) a.rootTxid = bytes32(value);
        else if (field == 1) a.rootIndex = uint32(value);
        else if (field == 2) a.previousOutpointHash = bytes32(value);
        else if (field == 3) a.spendingTxid = bytes32(value);
        else if (field == 4) a.bitcoinBlockHash = bytes32(value);
        else if (field == 5) a.bitcoinHeight = uint64(value);
        else if (field == 6) a.authorizationId = bytes32(value);
        else if (field == 7) a.deadline = uint64(value);
        else if (field == 8) a.attestorEpoch = uint64(value);
        else a.policyVersion = uint32(value);
    }
}
