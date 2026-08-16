// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {BitcoinAttestorRegistry} from "../../src/BitcoinAttestorRegistry.sol";
import {BitcoinOwnershipOracle} from "../../src/BitcoinOwnershipOracle.sol";
import {PuppetCollectionRegistry} from "../../src/PuppetCollectionRegistry.sol";
import {IBitcoinAttestorRegistry} from "../../src/interfaces/IBitcoinAttestorRegistry.sol";
import {IBitcoinOwnershipOracle} from "../../src/interfaces/IBitcoinOwnershipOracle.sol";
import {IPuppetCollectionRegistry} from "../../src/interfaces/IPuppetCollectionRegistry.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";
import {AttestorSet} from "../helpers/AttestorSet.sol";
import {MerkleFixture} from "../helpers/MerkleFixture.sol";
import {ConsumerHarness} from "../mocks/ConsumerHarness.sol";
import {MockAttestorRegistry} from "../mocks/MockAttestorRegistry.sol";

/// @title BitcoinOwnershipOracleTest
/// @notice Exhaustive unit suite for the protocol's quorum oracle.
/// @dev THREE THINGS THIS SUITE IS CAREFUL ABOUT.
///
///      1. CHEAT-CODE ARGUMENT EVALUATION. `vm.expectRevert` and `vm.prank` apply to the NEXT
///         external call. An inline argument such as `oracle.PAUSER_ROLE()` is itself an external
///         call and silently consumes the cheat code, which makes the assertion vacuous. Every role
///         id, digest and signature array used inside an expectation is therefore hoisted into a
///         local or a cached field BEFORE the cheat code is armed.
///
///      2. THE REGISTRY MOCK RELAXES GOVERNANCE, NOT VERIFICATION. `MockAttestorRegistry` is used
///         where a suite needs a stale epoch, a stale policy or a membership change that does NOT
///         bump the epoch — states the real registry deliberately makes unreachable. The real
///         `BitcoinAttestorRegistry` is also deployed and driven directly, so at least one path
///         proves the oracle works against production governance and that a real mutation
///         invalidates in-flight signatures.
///
///      3. THE COLLECTION REGISTRY IS THE REAL ONE. Membership is a security property of this
///         contract's inputs, so `PuppetCollectionRegistry` is deployed with a real fixture tree
///         built by `MerkleFixture` rather than mocked with `allowAll`.
///
///      TRUST BOUNDARY REMINDER: none of these tests verifies a Bitcoin fact, and none can. They
///      verify that a threshold of designated EVM keys signed the same typed struct.
contract BitcoinOwnershipOracleTest is Test {
    /*//////////////////////////////////////////////////////////////
                                FIXTURES
    //////////////////////////////////////////////////////////////*/

    /// @dev Deliberately not 1: a hard-coded `1` in the oracle would pass with epoch 1 and fail here.
    uint64 internal constant EPOCH = 7;
    /// @dev Same reasoning as `EPOCH`.
    uint32 internal constant POLICY = 3;
    uint8 internal constant THRESHOLD = 3;
    uint256 internal constant ATTESTOR_COUNT = 5;

    /// @dev Order of the secp256k1 group, used to build a deliberately malleable upper-half `s`.
    uint256 internal constant SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    address internal constant BUYER = address(0x2222222222222222222222222222222222222222);
    address internal constant RECIPIENT = address(0x3333333333333333333333333333333333333333);
    address internal constant SELLER_EVM = address(0x4444444444444444444444444444444444444444);
    address internal constant SOLVER = address(0x5555555555555555555555555555555555555555);
    address internal constant OUTSIDER_EOA = address(0xBAD);

    AttestorSet internal attestors;
    MockAttestorRegistry internal registry;
    PuppetCollectionRegistry internal collection;
    BitcoinOwnershipOracle internal oracle;

    /// @dev Stands in for `HoodPupOfferEscrow`: may consume the three mint purposes.
    ConsumerHarness internal escrowConsumer;
    /// @dev Stands in for `RootOwnershipRegistry`: may consume ROOT_BIND / ROOT_INVALIDATE and
    ///      root-spend attestations.
    ConsumerHarness internal rootConsumer;
    /// @dev Stands in for `BtcSolverSettlement`: may consume Bitcoin payment attestations.
    ConsumerHarness internal settlementConsumer;

    /// @dev The fixture manifest. Four members plus one deliberate non-member.
    PuppetTypes.RootId[] internal fixtureRoots;
    PuppetTypes.RootId internal nonMemberRoot;

    /// @dev Hoisted role ids; see note 1 in the contract NatSpec.
    bytes32 internal ownershipConsumerRole;
    bytes32 internal paymentConsumerRole;
    bytes32 internal rootSpendConsumerRole;
    bytes32 internal pauserRole;
    bytes32 internal defaultAdminRole;

    function setUp() public {
        vm.warp(1_700_000_000);

        attestors = new AttestorSet(ATTESTOR_COUNT, keccak256("HOODPUPS_ORACLE_SUITE_V1"));
        registry = new MockAttestorRegistry(attestors.addresses(), THRESHOLD, EPOCH, POLICY);

        fixtureRoots.push(PuppetTypes.RootId({inscriptionTxid: _fixtureTxid("oracle-root-a"), inscriptionIndex: 0}));
        fixtureRoots.push(PuppetTypes.RootId({inscriptionTxid: _fixtureTxid("oracle-root-a"), inscriptionIndex: 1}));
        fixtureRoots.push(PuppetTypes.RootId({inscriptionTxid: _fixtureTxid("oracle-root-b"), inscriptionIndex: 0}));
        fixtureRoots.push(PuppetTypes.RootId({inscriptionTxid: _fixtureTxid("oracle-root-c"), inscriptionIndex: 4}));
        nonMemberRoot =
            PuppetTypes.RootId({inscriptionTxid: _fixtureTxid("oracle-not-in-manifest"), inscriptionIndex: 9});

        bytes32 merkleRoot = MerkleFixture.build(MerkleFixture.leavesOf(_rootsMemory()));
        collection = new PuppetCollectionRegistry(
            merkleRoot, keccak256("HOODPUPS_ORACLE_SUITE_MANIFEST"), "hoodpups-oracle-suite-v1", fixtureRoots.length
        );

        oracle = new BitcoinOwnershipOracle(address(this), collection, registry);

        ownershipConsumerRole = oracle.OWNERSHIP_CONSUMER_ROLE();
        paymentConsumerRole = oracle.PAYMENT_CONSUMER_ROLE();
        rootSpendConsumerRole = oracle.ROOT_SPEND_CONSUMER_ROLE();
        pauserRole = oracle.PAUSER_ROLE();
        defaultAdminRole = oracle.DEFAULT_ADMIN_ROLE();

        escrowConsumer = new ConsumerHarness(IBitcoinOwnershipOracle(address(oracle)));
        rootConsumer = new ConsumerHarness(IBitcoinOwnershipOracle(address(oracle)));
        settlementConsumer = new ConsumerHarness(IBitcoinOwnershipOracle(address(oracle)));

        oracle.grantOwnershipConsumer(address(escrowConsumer), _mintPurposes());
        oracle.grantOwnershipConsumer(address(rootConsumer), _rootPurposes());
        oracle.grantRole(rootSpendConsumerRole, address(rootConsumer));
        oracle.grantRole(paymentConsumerRole, address(settlementConsumer));
    }

    /*//////////////////////////////////////////////////////////////
                       DOMAIN AND TYPED-DATA HASHING
    //////////////////////////////////////////////////////////////*/

    /// @dev Rebuilds the EIP-712 domain separator from the specification text rather than from the
    ///      contract, so a wrong name, version, chain id or verifying contract fails here.
    function test_DomainSeparatorMatchesSpecification() public view {
        bytes32 expected = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("HoodPups Bitcoin Oracle")),
                keccak256(bytes("1")),
                block.chainid,
                address(oracle)
            )
        );
        assertEq(oracle.domainSeparator(), expected, "domain separator diverges from the specified domain");
    }

    function test_Eip712DomainReportsSpecifiedNameAndVersion() public view {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            oracle.eip712Domain();
        assertEq(name, "HoodPups Bitcoin Oracle", "domain name");
        assertEq(version, "1", "domain version");
        assertEq(chainId, block.chainid, "domain chain id");
        assertEq(verifyingContract, address(oracle), "domain verifying contract");
        assertEq(oracle.EIP712_NAME(), name, "exposed constant must match the live domain");
        assertEq(oracle.EIP712_VERSION(), version, "exposed constant must match the live domain");
    }

    /// @dev Composes the digest by hand from the shared library's `hashStruct` and the domain
    ///      separator. If the oracle ever re-derived the encoding locally, this would diverge.
    function test_OwnershipDigestIsDomainSeparatorPlusLibraryStructHash() public view {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 expected = keccak256(abi.encodePacked(hex"1901", oracle.domainSeparator(), PuppetHashing.hashStruct(a)));
        assertEq(oracle.hashOwnershipAttestation(a), expected, "ownership digest");
    }

    function test_PaymentDigestIsDomainSeparatorPlusLibraryStructHash() public view {
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment();
        bytes32 expected = keccak256(abi.encodePacked(hex"1901", oracle.domainSeparator(), PuppetHashing.hashStruct(a)));
        assertEq(oracle.hashBitcoinPaymentAttestation(a), expected, "payment digest");
    }

    function test_RootSpendDigestIsDomainSeparatorPlusLibraryStructHash() public view {
        PuppetTypes.RootSpendAttestation memory a = _rootSpend();
        bytes32 expected = keccak256(abi.encodePacked(hex"1901", oracle.domainSeparator(), PuppetHashing.hashStruct(a)));
        assertEq(oracle.hashRootSpendAttestation(a), expected, "root-spend digest");
    }

    /// @dev The three type strings are the cross-language contract. They are re-declared here as
    ///      literals so an edit to `PuppetHashing` cannot quietly change what attestors sign.
    function test_TypeStringsAreCanonicalAndFieldOrderIsFrozen() public pure {
        assertEq(
            PuppetHashing.OWNERSHIP_ATTESTATION_TYPEHASH,
            keccak256(
                bytes(
                    "OwnershipAttestation(uint8 purpose,bytes32 rootTxid,uint32 rootIndex,bytes32 contextId,bytes32 offerTermsHash,bytes32 currentOutpointHash,bytes32 ownerScriptHash,bytes32 bip322ProofHash,address buyer,address recipient,uint8 payoutMode,address evmPayout,bytes32 btcPayoutScriptHash,uint64 sellerSats,uint256 grossWei,uint256 sellerWei,bytes32 bitcoinBlockHash,uint64 bitcoinHeight,bytes32 authorizationId,uint64 deadline,uint64 attestorEpoch,uint32 policyVersion)"
                )
            ),
            "OwnershipAttestation type string"
        );
        assertEq(
            PuppetHashing.BITCOIN_PAYMENT_ATTESTATION_TYPEHASH,
            keccak256(
                bytes(
                    "BitcoinPaymentAttestation(bytes32 contextId,bytes32 ownershipDigest,address solver,bytes32 bitcoinTxid,uint32 outputIndex,bytes32 recipientScriptHash,uint64 amountSats,bytes32 bitcoinBlockHash,uint64 bitcoinHeight,bytes32 authorizationId,uint64 deadline,uint64 attestorEpoch,uint32 policyVersion)"
                )
            ),
            "BitcoinPaymentAttestation type string"
        );
        assertEq(
            PuppetHashing.ROOT_SPEND_ATTESTATION_TYPEHASH,
            keccak256(
                bytes(
                    "RootSpendAttestation(bytes32 rootTxid,uint32 rootIndex,bytes32 previousOutpointHash,bytes32 spendingTxid,bytes32 bitcoinBlockHash,uint64 bitcoinHeight,bytes32 authorizationId,uint64 deadline,uint64 attestorEpoch,uint32 policyVersion)"
                )
            ),
            "RootSpendAttestation type string"
        );
    }

    /// @dev Mutating any single field must move the digest. Field-order bugs and dropped fields
    ///      both show up as a digest that fails to move.
    function test_EveryOwnershipFieldIsBoundIntoTheDigest() public view {
        PuppetTypes.OwnershipAttestation memory base = _ownershipEvm();
        bytes32 baseDigest = oracle.hashOwnershipAttestation(base);

        for (uint256 field = 0; field < 22; field++) {
            PuppetTypes.OwnershipAttestation memory mutated = _mutateOwnershipField(base, field);
            assertTrue(
                oracle.hashOwnershipAttestation(mutated) != baseDigest,
                "a field mutation left the digest unchanged, so that field is not bound"
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                            QUORUM: HAPPY PATHS
    //////////////////////////////////////////////////////////////*/

    function test_ValidThreeOfFiveOwnershipConsumes() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory signatures = attestors.sign(digest, THRESHOLD);
        bytes32 expectedKey = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);

        vm.expectEmit(true, true, true, true, address(oracle));
        emit IBitcoinOwnershipOracle.OwnershipConsumed(
            digest, expectedKey, a.contextId, a.purpose, address(escrowConsumer), a.bip322ProofHash
        );
        (bytes32 returnedDigest, bytes32 returnedKey) = escrowConsumer.consumeOwnership(a, signatures, _proof(0));

        assertEq(returnedDigest, digest, "returned digest");
        assertEq(returnedKey, expectedKey, "returned root key");
        assertTrue(oracle.isDigestConsumed(digest), "digest must be consumed");
        assertEq(escrowConsumer.forwardCount(), 1, "the harness call must actually have reached the oracle");
    }

    function test_MoreThanThresholdSignaturesSucceeds() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory signatures = attestors.sign(digest, ATTESTOR_COUNT);

        (bytes32 returnedDigest,) = escrowConsumer.consumeOwnership(a, signatures, _proof(0));
        assertEq(returnedDigest, digest, "five-of-five must be accepted");
    }

    /// @dev Threshold is a floor, not an equality. Raising the registry threshold to 5 must make a
    ///      previously-sufficient 4-signature set insufficient, and a 5-signature set sufficient.
    function test_ThresholdIsAFloorAndTracksTheRegistry() public {
        registry.setThreshold(5);

        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory four = attestors.sign(digest, 4);
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.InsufficientSignatures.selector, 4, uint8(5)));
        oracle.verifyOwnership(a, four, proof);

        bytes[] memory five = attestors.sign(digest, 5);
        (bytes32 returnedDigest,) = oracle.verifyOwnership(a, five, proof);
        assertEq(returnedDigest, digest, "five signatures satisfy a threshold of five");
    }

    function test_CompactEip2098SignaturesAccepted() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory signatures = attestors.signCompact(digest, THRESHOLD);
        assertEq(signatures[0].length, 64, "compact signatures must be 64 bytes");

        (bytes32 returnedDigest,) = escrowConsumer.consumeOwnership(a, signatures, _proof(0));
        assertEq(returnedDigest, digest, "compact quorum must be accepted");
    }

    /// @dev A relayer may aggregate signatures from services using different encodings. Mixing the
    ///      two forms in one array must be accepted, because nothing in the protocol requires all
    ///      five operators to agree on an encoding.
    function test_MixedCompactAndCanonicalSignaturesAccepted() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory canonical = attestors.sign(digest, THRESHOLD);
        bytes[] memory compact = attestors.signCompact(digest, THRESHOLD);

        bytes[] memory mixed = new bytes[](THRESHOLD);
        mixed[0] = canonical[0];
        mixed[1] = compact[1];
        mixed[2] = canonical[2];

        (bytes32 returnedDigest,) = escrowConsumer.consumeOwnership(a, mixed, _proof(0));
        assertEq(returnedDigest, digest, "mixed encodings must be accepted");
    }

    /// @dev Every fixture member must be provable, including the pair that shares a reveal txid and
    ///      differs only by inscription index.
    function test_EveryFixtureMemberVerifies() public view {
        for (uint256 i = 0; i < fixtureRoots.length; i++) {
            PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
            a.rootTxid = fixtureRoots[i].inscriptionTxid;
            a.rootIndex = fixtureRoots[i].inscriptionIndex;
            a.authorizationId = keccak256(abi.encode("auth", i));

            bytes32 digest = oracle.hashOwnershipAttestation(a);
            (, bytes32 key) = oracle.verifyOwnership(a, attestors.sign(digest, THRESHOLD), _proof(i));
            assertEq(key, PuppetHashing.rootKey(fixtureRoots[i].inscriptionTxid, fixtureRoots[i].inscriptionIndex));
        }
    }

    /*//////////////////////////////////////////////////////////////
                          QUORUM: REJECTION PATHS
    //////////////////////////////////////////////////////////////*/

    function test_OneSignatureShortOfThresholdReverts() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD - 1);
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinOwnershipOracle.InsufficientSignatures.selector, uint256(2), THRESHOLD)
        );
        oracle.verifyOwnership(a, signatures, proof);
    }

    function test_ZeroSignaturesReverts() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory none = new bytes[](0);
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinOwnershipOracle.InsufficientSignatures.selector, uint256(0), THRESHOLD)
        );
        oracle.verifyOwnership(a, none, proof);
    }

    /// @dev The array is correctly ascending; the only defect is that one signer is not an
    ///      attestor. That keeps the assertion honest about which rule fired.
    function test_UnauthorizedSignerMixedIntoAnOtherwiseValidSetReverts() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory signatures = attestors.signWithOutsider(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);
        address outsider = attestors.outsider();

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.SignerNotAttestor.selector, outsider));
        oracle.verifyOwnership(a, signatures, proof);
    }

    /// @dev Quorum inflation: three signatures, two distinct operators. Rejected by strict ascent.
    function test_DuplicateSignerReverts() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory signatures = attestors.signWithDuplicate(oracle.hashOwnershipAttestation(a), THRESHOLD, 0);
        bytes32[] memory proof = _proof(0);

        // `signWithDuplicate(_, 3, 0)` repeats the address-lowest of the two distinct signers, so
        // the offending pair is exactly (x, x) — the shape a quorum-inflation attempt would take.
        address repeated = _sortedFirstAddress(2);

        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinOwnershipOracle.SignersNotStrictlyAscending.selector, repeated, repeated)
        );
        oracle.verifyOwnership(a, signatures, proof);
    }

    function test_UnsortedSignerListReverts() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory signatures = attestors.signUnsorted(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        // Descending order: the first signature is accepted, the second is the first violation.
        uint256[] memory sorted = _sortedFirstIndices(THRESHOLD);
        address highest = attestors.addressAt(sorted[THRESHOLD - 1]);
        address middle = attestors.addressAt(sorted[THRESHOLD - 2]);

        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinOwnershipOracle.SignersNotStrictlyAscending.selector, highest, middle)
        );
        oracle.verifyOwnership(a, signatures, proof);
    }

    /// @dev An upper-half `s` recovers to the SAME signer under the raw `ecrecover` precompile, so
    ///      without an explicit rejection this would be a second valid encoding of one signature —
    ///      i.e. a way to make one operator look like two. OpenZeppelin rejects it; this proves the
    ///      oracle surfaces that rejection as a named error at a known index rather than letting a
    ///      library revert escape.
    function test_MalleableUpperHalfSignatureRejected() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory signatures = attestors.sign(digest, THRESHOLD);

        uint256 lowestSigner = _sortedFirstIndices(THRESHOLD)[0];
        signatures[0] = _malleableSignature(attestors.keyAt(lowestSigner), digest);
        bytes32[] memory proof = _proof(0);

        // errorCode 3 == ECDSA.RecoverError.InvalidSignatureS.
        vm.expectRevert(
            abi.encodeWithSelector(BitcoinOwnershipOracle.MalformedSignature.selector, uint256(0), uint8(3))
        );
        oracle.verifyOwnership(a, signatures, proof);
    }

    /// @dev Sanity control for the test above: the malleable form really does recover to the same
    ///      attestor under raw `ecrecover`, so the rejection is doing work rather than rejecting
    ///      something that was never valid.
    function test_MalleableSignatureRecoversToTheSameSignerUnderRawEcrecover() public view {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        uint256 index = _sortedFirstIndices(THRESHOLD)[0];

        bytes memory malleable = _malleableSignature(attestors.keyAt(index), digest);
        (bytes32 r, bytes32 s, uint8 v) = _split(malleable);
        assertEq(ecrecover(digest, v, r, s), attestors.addressAt(index), "control: raw ecrecover accepts the mutation");
    }

    function test_WrongLengthSignatureRejected() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        signatures[1] = hex"deadbeef";
        bytes32[] memory proof = _proof(0);

        // errorCode 2 == ECDSA.RecoverError.InvalidSignatureLength.
        vm.expectRevert(
            abi.encodeWithSelector(BitcoinOwnershipOracle.MalformedSignature.selector, uint256(1), uint8(2))
        );
        oracle.verifyOwnership(a, signatures, proof);
    }

    function test_UnrecoverableSignatureRejected() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        // v == 1 is outside {27, 28}: ECDSA reports InvalidSignature (code 1).
        signatures[2] = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(1));
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(
            abi.encodeWithSelector(BitcoinOwnershipOracle.MalformedSignature.selector, uint256(2), uint8(1))
        );
        oracle.verifyOwnership(a, signatures, proof);
    }

    /// @dev Uses the mock's ability to change membership WITHOUT bumping the epoch, which the real
    ///      registry never allows. It isolates the membership check from the epoch check.
    function test_RemovedAttestorNoLongerCountsTowardQuorum() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory signatures = attestors.sign(digest, THRESHOLD);
        bytes32[] memory proof = _proof(0);

        address removed = _sortedFirstAddress(THRESHOLD);
        registry.removeAttestor(removed);

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.SignerNotAttestor.selector, removed));
        oracle.verifyOwnership(a, signatures, proof);
    }

    /// @dev Signatures over a different digest recover to unrelated addresses, so they fail
    ///      membership. This is the generic "signature does not match this attestation" path.
    function test_SignaturesOverADifferentAttestationFail() public {
        PuppetTypes.OwnershipAttestation memory signed = _ownershipEvm();
        PuppetTypes.OwnershipAttestation memory submitted = _ownershipEvm();
        submitted.grossWei = signed.grossWei + 1 wei;

        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(signed), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        // The recovered address is a function of the signature over a digest nobody chose, so only
        // the selector is predictable. `expectPartialRevert` matches on the selector alone.
        vm.expectPartialRevert(IBitcoinOwnershipOracle.SignerNotAttestor.selector);
        oracle.verifyOwnership(submitted, signatures, proof);
    }

    /*//////////////////////////////////////////////////////////////
                         FRESHNESS AND REPLAY
    //////////////////////////////////////////////////////////////*/

    function test_ExpiredDeadlineReverts() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        vm.warp(uint256(a.deadline) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinOwnershipOracle.DeadlineExpired.selector, a.deadline, block.timestamp)
        );
        oracle.verifyOwnership(a, signatures, proof);
    }

    /// @dev `deadline >= block.timestamp`: an attestation is still valid in the exact second it
    ///      expires. Pinning the boundary stops a later refactor from silently making deadlines
    ///      one second shorter than every issuer believes.
    function test_DeadlineEqualToNowIsStillValid() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory signatures = attestors.sign(digest, THRESHOLD);

        vm.warp(uint256(a.deadline));
        (bytes32 returnedDigest,) = oracle.verifyOwnership(a, signatures, _proof(0));
        assertEq(returnedDigest, digest, "the expiry second itself must remain valid");
    }

    function test_StaleAttestorEpochReverts() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        registry.bumpEpoch();

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.StaleAttestorEpoch.selector, EPOCH, EPOCH + 1));
        oracle.verifyOwnership(a, signatures, proof);
    }

    /// @dev A FUTURE epoch is just as invalid as a stale one — it was signed against a verifier set
    ///      this chain has not adopted. Equality, not "at least".
    function test_FutureAttestorEpochAlsoReverts() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        a.attestorEpoch = EPOCH + 5;
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.StaleAttestorEpoch.selector, EPOCH + 5, EPOCH));
        oracle.verifyOwnership(a, signatures, proof);
    }

    function test_StalePolicyVersionReverts() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        registry.setPolicyVersion(POLICY + 1);

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.StalePolicyVersion.selector, POLICY, POLICY + 1));
        oracle.verifyOwnership(a, signatures, proof);
    }

    /// @dev The same three checks against the REAL registry, whose every mutation bumps the epoch.
    ///      This is the production-governance counterpart to the mock-driven cases above.
    function test_RealRegistryMutationInvalidatesInFlightAttestations() public {
        BitcoinAttestorRegistry real = new BitcoinAttestorRegistry(address(this), attestors.addresses(), THRESHOLD, 1);
        BitcoinOwnershipOracle liveOracle = new BitcoinOwnershipOracle(address(this), collection, real);

        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        a.attestorEpoch = real.attestorEpoch();
        a.policyVersion = real.policyVersion();

        bytes32 digest = liveOracle.hashOwnershipAttestation(a);
        bytes[] memory signatures = attestors.sign(digest, THRESHOLD);
        bytes32[] memory proof = _proof(0);

        (bytes32 verified,) = liveOracle.verifyOwnership(a, signatures, proof);
        assertEq(verified, digest, "the quorum must verify against the real registry first");

        real.replaceAttestor(attestors.addresses()[0], address(0xA11CE));

        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinOwnershipOracle.StaleAttestorEpoch.selector, uint64(1), uint64(2))
        );
        liveOracle.verifyOwnership(a, signatures, proof);
    }

    function test_ReplayOfAConsumedDigestReverts() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory signatures = attestors.sign(digest, THRESHOLD);
        bytes32[] memory proof = _proof(0);

        escrowConsumer.consumeOwnership(a, signatures, proof);

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.DigestAlreadyConsumed.selector, digest));
        escrowConsumer.consumeOwnership(a, signatures, proof);

        // The read-only path must agree: a consumed authorization is no longer verifiable.
        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.DigestAlreadyConsumed.selector, digest));
        oracle.verifyOwnership(a, signatures, proof);
    }

    /// @dev Consumption is a one-way door: no admin, pauser or consumer path can clear it. Proven
    ///      by driving every privileged surface the contract exposes and re-reading the flag.
    function test_ConsumptionIsPermanentAndIrreversible() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        escrowConsumer.consumeOwnership(a, attestors.sign(digest, THRESHOLD), _proof(0));

        oracle.pause();
        oracle.unpause();
        oracle.setConsumerPurposes(address(escrowConsumer), new uint8[](0));
        oracle.revokeRole(ownershipConsumerRole, address(escrowConsumer));
        registry.bumpEpoch();
        vm.warp(block.timestamp + 3650 days);

        assertTrue(oracle.isDigestConsumed(digest), "a consumed digest must never become unconsumed");
    }

    /*//////////////////////////////////////////////////////////////
                            DOMAIN SEPARATION
    //////////////////////////////////////////////////////////////*/

    /// @dev Signatures gathered on one chain must not settle on another. `vm.chainId` moves the
    ///      domain out from under the already-collected quorum.
    function test_SignaturesFromAnotherChainIdAreRejected() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 homeDigest = oracle.hashOwnershipAttestation(a);
        bytes[] memory signatures = attestors.sign(homeDigest, THRESHOLD);
        bytes32[] memory proof = _proof(0);

        vm.chainId(block.chainid + 1);
        assertTrue(oracle.hashOwnershipAttestation(a) != homeDigest, "the digest must move with the chain id");

        vm.expectPartialRevert(IBitcoinOwnershipOracle.SignerNotAttestor.selector);
        oracle.verifyOwnership(a, signatures, proof);
    }

    /// @dev Two oracles sharing the same registries must still have disjoint domains, so a quorum
    ///      collected for one can never be replayed into the other.
    function test_SignaturesForAnotherVerifyingContractAreRejected() public {
        BitcoinOwnershipOracle secondOracle = new BitcoinOwnershipOracle(address(this), collection, registry);

        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 firstDigest = oracle.hashOwnershipAttestation(a);
        bytes32 secondDigest = secondOracle.hashOwnershipAttestation(a);
        assertTrue(firstDigest != secondDigest, "two deployments must not share a digest");
        assertTrue(oracle.domainSeparator() != secondOracle.domainSeparator(), "domain separators must differ");

        bytes[] memory signatures = attestors.sign(firstDigest, THRESHOLD);
        bytes32[] memory proof = _proof(0);

        vm.expectPartialRevert(IBitcoinOwnershipOracle.SignerNotAttestor.selector);
        secondOracle.verifyOwnership(a, signatures, proof);
    }

    /// @dev The three attestation families must never collide. Even with identical trailing
    ///      context, a payment digest can never be presented as an ownership digest, because the
    ///      typehash differs.
    function test_AttestationFamiliesProduceDisjointDigests() public view {
        bytes32 ownership = oracle.hashOwnershipAttestation(_ownershipEvm());
        bytes32 payment = oracle.hashBitcoinPaymentAttestation(_payment());
        bytes32 spend = oracle.hashRootSpendAttestation(_rootSpend());

        assertTrue(ownership != payment, "ownership vs payment");
        assertTrue(ownership != spend, "ownership vs root spend");
        assertTrue(payment != spend, "payment vs root spend");
    }

    /*//////////////////////////////////////////////////////////////
                       OWNERSHIP-SPECIFIC VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_ZeroAuthorizationIdReverts() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        a.authorizationId = bytes32(0);
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(IBitcoinOwnershipOracle.ZeroAuthorizationId.selector);
        oracle.verifyOwnership(a, signatures, proof);
    }

    function test_PurposeOutsideTheEnumReverts() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        a.purpose = 5; // one past ROOT_INVALIDATE
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.UnsupportedPurpose.selector, uint8(5)));
        oracle.verifyOwnership(a, signatures, proof);
    }

    function test_ValidBtcPayoutShapeAccepted() public view {
        PuppetTypes.OwnershipAttestation memory a = _ownershipBtc();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        (bytes32 returned,) = oracle.verifyOwnership(a, attestors.sign(digest, THRESHOLD), _proof(0));
        assertEq(returned, digest, "a well-formed BTC payout must be accepted");
    }

    function test_ValidSelfCastShapeAccepted() public view {
        PuppetTypes.OwnershipAttestation memory a = _ownershipSelfCast();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        (bytes32 returned,) = oracle.verifyOwnership(a, attestors.sign(digest, THRESHOLD), _proof(0));
        assertEq(returned, digest, "a well-formed self-cast must be accepted");
    }

    function test_ValidRootBindShapeAccepted() public view {
        PuppetTypes.OwnershipAttestation memory a = _ownershipSelfCast();
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.EVM);
        a.evmPayout = RECIPIENT;
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        (bytes32 returned,) = oracle.verifyOwnership(a, attestors.sign(digest, THRESHOLD), _proof(0));
        assertEq(returned, digest, "a well-formed ROOT_BIND must be accepted");
    }

    /// @dev Every malformed payout combination the specification names, plus the purpose/mode
    ///      mismatches. Each case mutates exactly one thing away from a valid attestation, so a
    ///      passing case cannot be passing for an unrelated reason.
    function test_MalformedPayoutCombinationsAllRevert() public {
        // EVM mode with a zero payout address: nobody to credit.
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        a.evmPayout = address(0);
        _expectInvalidPayoutShape(a);

        // EVM mode carrying a BTC script hash: two readings of one signed fact.
        a = _ownershipEvm();
        a.btcPayoutScriptHash = keccak256("btc-script");
        _expectInvalidPayoutShape(a);

        // EVM mode carrying sats.
        a = _ownershipEvm();
        a.sellerSats = 1;
        _expectInvalidPayoutShape(a);

        // EVM mode where the seller share exceeds the whole escrow.
        a = _ownershipEvm();
        a.sellerWei = a.grossWei + 1;
        _expectInvalidPayoutShape(a);

        // BTC mode with a zero script hash: nowhere on Bitcoin to pay.
        a = _ownershipBtc();
        a.btcPayoutScriptHash = bytes32(0);
        _expectInvalidPayoutShape(a);

        // BTC mode with zero sats: a payment of nothing.
        a = _ownershipBtc();
        a.sellerSats = 0;
        _expectInvalidPayoutShape(a);

        // BTC mode carrying an EVM payout address.
        a = _ownershipBtc();
        a.evmPayout = SELLER_EVM;
        _expectInvalidPayoutShape(a);

        // Self-cast carrying an EVM payout address.
        a = _ownershipSelfCast();
        a.evmPayout = SELLER_EVM;
        _expectInvalidPayoutShape(a);

        // Self-cast carrying a BTC script hash.
        a = _ownershipSelfCast();
        a.btcPayoutScriptHash = keccak256("btc-script");
        _expectInvalidPayoutShape(a);

        // Self-cast carrying sats.
        a = _ownershipSelfCast();
        a.sellerSats = 1;
        _expectInvalidPayoutShape(a);

        // Self-cast claiming a buyer escrowed value.
        a = _ownershipSelfCast();
        a.grossWei = 1 ether;
        _expectInvalidPayoutShape(a);

        // Self-cast claiming a seller share.
        a = _ownershipSelfCast();
        a.sellerWei = 1 wei;
        _expectInvalidPayoutShape(a);

        // ROOT_INVALIDATE must move no money either.
        a = _ownershipSelfCast();
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.ROOT_INVALIDATE);
        a.grossWei = 1 ether;
        _expectInvalidPayoutShape(a);
    }

    function test_PurposeAndPayoutModeMustAgree() public {
        // PAID_EVM_MINT declaring a BTC payout mode.
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        a.payoutMode = uint8(PuppetTypes.PayoutMode.BTC);
        _expectInvalidPayoutShape(a);

        // PAID_BTC_MINT declaring an EVM payout mode.
        a = _ownershipBtc();
        a.payoutMode = uint8(PuppetTypes.PayoutMode.EVM);
        _expectInvalidPayoutShape(a);

        // SELF_CAST declaring a paying mode.
        a = _ownershipSelfCast();
        a.payoutMode = uint8(PuppetTypes.PayoutMode.EVM);
        _expectInvalidPayoutShape(a);

        // ROOT_BIND declaring a paying mode.
        a = _ownershipSelfCast();
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.BTC);
        _expectInvalidPayoutShape(a);

        // A payout mode outside the enum is caught by the same rule.
        a = _ownershipEvm();
        a.payoutMode = 9;
        _expectInvalidPayoutShape(a);
    }

    function test_NonMemberRootIsRejected() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        a.rootTxid = nonMemberRoot.inscriptionTxid;
        a.rootIndex = nonMemberRoot.inscriptionIndex;

        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory borrowedProof = _proof(0);
        bytes32 key = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);

        vm.expectRevert(abi.encodeWithSelector(IPuppetCollectionRegistry.NotCollectionMember.selector, key));
        oracle.verifyOwnership(a, signatures, borrowedProof);
    }

    /// @dev A real member presented with another member's proof must fail. Reusing a valid proof is
    ///      the natural attempt once an attacker has one.
    function test_MemberWithAnotherMembersProofIsRejected() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        a.rootTxid = fixtureRoots[2].inscriptionTxid;
        a.rootIndex = fixtureRoots[2].inscriptionIndex;

        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory wrongProof = _proof(0);
        bytes32 key = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);

        vm.expectRevert(abi.encodeWithSelector(IPuppetCollectionRegistry.NotCollectionMember.selector, key));
        oracle.verifyOwnership(a, signatures, wrongProof);
    }

    function test_EmptyProofForAMemberIsRejected() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory empty = new bytes32[](0);
        bytes32 key = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);

        vm.expectRevert(abi.encodeWithSelector(IPuppetCollectionRegistry.NotCollectionMember.selector, key));
        oracle.verifyOwnership(a, signatures, empty);
    }

    /// @dev The inscription index is part of the identity. A sibling inscription from the same
    ///      reveal transaction must not be provable with its sibling's proof.
    function test_SiblingInscriptionIndexIsNotInterchangeable() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        a.rootIndex = 1; // fixtureRoots[1] shares fixtureRoots[0]'s txid

        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory siblingProof = _proof(0);
        bytes32 key = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);

        vm.expectRevert(abi.encodeWithSelector(IPuppetCollectionRegistry.NotCollectionMember.selector, key));
        oracle.verifyOwnership(a, signatures, siblingProof);
    }

    /// @dev `bip322ProofHash` is emitted verbatim and never interpreted. Any 32 bytes, including a
    ///      value the contract could not possibly understand, must pass through untouched.
    function test_Bip322ProofHashIsEmittedVerbatimAndNeverInterpreted() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        a.bip322ProofHash = bytes32(type(uint256).max);

        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes32 key = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);

        vm.expectEmit(true, true, true, true, address(oracle));
        emit IBitcoinOwnershipOracle.OwnershipConsumed(
            digest, key, a.contextId, a.purpose, address(escrowConsumer), bytes32(type(uint256).max)
        );
        escrowConsumer.consumeOwnership(a, attestors.sign(digest, THRESHOLD), _proof(0));
    }

    /*//////////////////////////////////////////////////////////////
                          PAYMENT-SPECIFIC RULES
    //////////////////////////////////////////////////////////////*/

    function test_ValidBitcoinPaymentConsumes() public {
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment();
        bytes32 digest = oracle.hashBitcoinPaymentAttestation(a);
        bytes32 expectedKey = PuppetHashing.paymentOutputKey(a.bitcoinTxid, a.outputIndex);

        vm.expectEmit(true, true, true, true, address(oracle));
        emit IBitcoinOwnershipOracle.BitcoinPaymentConsumed(
            digest, a.contextId, expectedKey, a.solver, a.amountSats, address(settlementConsumer)
        );
        (bytes32 returnedDigest, bytes32 returnedKey) =
            settlementConsumer.consumeBitcoinPayment(a, attestors.sign(digest, THRESHOLD));

        assertEq(returnedDigest, digest, "returned digest");
        assertEq(returnedKey, expectedKey, "returned payment output key");
        assertTrue(oracle.isDigestConsumed(digest), "digest consumed");
        assertTrue(oracle.isPaymentOutputConsumed(a.bitcoinTxid, a.outputIndex), "output consumed by (txid, vout)");
        assertTrue(oracle.isPaymentOutputKeyConsumed(expectedKey), "output consumed by key");
    }

    /// @dev THE WORST FAILURE MODE THIS CONTRACT COULD PERMIT. Two entirely different offers, two
    ///      different authorization ids, two different attestation digests — and one real Bitcoin
    ///      output. If this passed, a solver would be reimbursed twice for one payment. The
    ///      consumed-output set is global precisely so the second attempt cannot succeed no matter
    ///      how the surrounding attestation differs.
    function test_ReusingOneBitcoinOutputAcrossTwoOffersIsImpossible() public {
        PuppetTypes.BitcoinPaymentAttestation memory first = _payment();
        bytes32 firstDigest = oracle.hashBitcoinPaymentAttestation(first);
        settlementConsumer.consumeBitcoinPayment(first, attestors.sign(firstDigest, THRESHOLD));

        PuppetTypes.BitcoinPaymentAttestation memory second = _payment();
        second.contextId = keccak256("a-completely-different-offer");
        second.ownershipDigest = keccak256("a-completely-different-ownership-fact");
        second.authorizationId = keccak256("a-completely-different-authorization");
        second.solver = address(0x6666666666666666666666666666666666666666);
        second.amountSats = first.amountSats + 1;

        bytes32 secondDigest = oracle.hashBitcoinPaymentAttestation(second);
        assertTrue(secondDigest != firstDigest, "the two attestations must genuinely be different");

        bytes[] memory signatures = attestors.sign(secondDigest, THRESHOLD);
        bytes32 key = PuppetHashing.paymentOutputKey(second.bitcoinTxid, second.outputIndex);

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.PaymentOutputAlreadyConsumed.selector, key));
        settlementConsumer.consumeBitcoinPayment(second, signatures);

        assertFalse(oracle.isDigestConsumed(secondDigest), "a rejected payment must not consume its digest");
    }

    /// @dev The output key is (txid, vout), so two outputs of the SAME transaction are independent.
    ///      A per-txid check would wrongly reject this legitimate case.
    function test_DifferentVoutOfTheSameTransactionIsIndependent() public {
        PuppetTypes.BitcoinPaymentAttestation memory first = _payment();
        settlementConsumer.consumeBitcoinPayment(
            first, attestors.sign(oracle.hashBitcoinPaymentAttestation(first), THRESHOLD)
        );

        PuppetTypes.BitcoinPaymentAttestation memory second = _payment();
        second.outputIndex = first.outputIndex + 1;
        second.contextId = keccak256("second-offer");
        second.authorizationId = keccak256("second-authorization");

        bytes32 digest = oracle.hashBitcoinPaymentAttestation(second);
        (, bytes32 key) = settlementConsumer.consumeBitcoinPayment(second, attestors.sign(digest, THRESHOLD));

        assertEq(key, PuppetHashing.paymentOutputKey(second.bitcoinTxid, second.outputIndex), "second output key");
        assertTrue(oracle.isPaymentOutputConsumed(first.bitcoinTxid, first.outputIndex), "first output still consumed");
    }

    /// @dev Both marks land in the same transaction. Asserting them together is what makes
    ///      "atomically" a tested claim rather than a comment.
    function test_DigestAndPaymentOutputAreConsumedAtomically() public {
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment();
        bytes32 digest = oracle.hashBitcoinPaymentAttestation(a);
        bytes32 key = PuppetHashing.paymentOutputKey(a.bitcoinTxid, a.outputIndex);

        assertFalse(oracle.isDigestConsumed(digest), "precondition");
        assertFalse(oracle.isPaymentOutputKeyConsumed(key), "precondition");

        settlementConsumer.consumeBitcoinPayment(a, attestors.sign(digest, THRESHOLD));

        assertTrue(oracle.isDigestConsumed(digest), "digest must be marked");
        assertTrue(oracle.isPaymentOutputKeyConsumed(key), "output must be marked in the same call");
    }

    /// @dev A failed consumption must leave BOTH marks untouched, or a griefer could burn an output
    ///      key with an attestation that was never valid.
    function test_AFailedPaymentConsumesNeitherMark() public {
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment();
        bytes32 digest = oracle.hashBitcoinPaymentAttestation(a);
        bytes32 key = PuppetHashing.paymentOutputKey(a.bitcoinTxid, a.outputIndex);
        bytes[] memory tooFew = attestors.sign(digest, THRESHOLD - 1);

        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinOwnershipOracle.InsufficientSignatures.selector, uint256(2), THRESHOLD)
        );
        settlementConsumer.consumeBitcoinPayment(a, tooFew);

        assertFalse(oracle.isDigestConsumed(digest), "digest untouched");
        assertFalse(oracle.isPaymentOutputKeyConsumed(key), "output untouched");
    }

    function test_PaymentFieldValidation() public {
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment();
        a.authorizationId = bytes32(0);
        _expectPaymentRevert(a, IBitcoinOwnershipOracle.ZeroAuthorizationId.selector);

        a = _payment();
        a.solver = address(0);
        _expectPaymentRevert(a, IBitcoinOwnershipOracle.ZeroSolver.selector);

        a = _payment();
        a.amountSats = 0;
        _expectPaymentRevert(a, IBitcoinOwnershipOracle.ZeroAmount.selector);

        a = _payment();
        a.recipientScriptHash = bytes32(0);
        _expectPaymentRevert(a, IBitcoinOwnershipOracle.ZeroScriptHash.selector);

        a = _payment();
        a.ownershipDigest = bytes32(0);
        _expectPaymentRevert(a, IBitcoinOwnershipOracle.ZeroOwnershipDigest.selector);
    }

    function test_PaymentRespectsFreshnessAndQuorumRules() public {
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment();
        bytes[] memory signatures = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), THRESHOLD);

        registry.bumpEpoch();
        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.StaleAttestorEpoch.selector, EPOCH, EPOCH + 1));
        oracle.verifyBitcoinPayment(a, signatures);
    }

    /// @dev `isPaymentOutputConsumed(txid, vout)` and `isPaymentOutputKeyConsumed(key)` must agree,
    ///      so a consumer cannot query a differently-derived key than consumption writes.
    function test_PaymentOutputViewsAgreeWithTheLibraryDerivation() public {
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment();
        bytes32 key = PuppetHashing.paymentOutputKey(a.bitcoinTxid, a.outputIndex);

        assertEq(oracle.isPaymentOutputConsumed(a.bitcoinTxid, a.outputIndex), oracle.isPaymentOutputKeyConsumed(key));
        settlementConsumer.consumeBitcoinPayment(a, attestors.sign(oracle.hashBitcoinPaymentAttestation(a), THRESHOLD));
        assertEq(oracle.isPaymentOutputConsumed(a.bitcoinTxid, a.outputIndex), oracle.isPaymentOutputKeyConsumed(key));
        assertTrue(oracle.isPaymentOutputKeyConsumed(key), "and both must now be true");
    }

    /*//////////////////////////////////////////////////////////////
                            ROOT-SPEND RULES
    //////////////////////////////////////////////////////////////*/

    function test_ValidRootSpendConsumes() public {
        PuppetTypes.RootSpendAttestation memory a = _rootSpend();
        bytes32 digest = oracle.hashRootSpendAttestation(a);
        bytes32 expectedKey = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);

        vm.expectEmit(true, true, true, true, address(oracle));
        emit IBitcoinOwnershipOracle.RootSpendConsumed(digest, expectedKey, a.spendingTxid, address(rootConsumer));
        (bytes32 returnedDigest, bytes32 returnedKey) =
            rootConsumer.consumeRootSpend(a, attestors.sign(digest, THRESHOLD), _proof(0));

        assertEq(returnedDigest, digest, "returned digest");
        assertEq(returnedKey, expectedKey, "returned root key");
        assertTrue(oracle.isDigestConsumed(digest), "digest consumed");
    }

    function test_RootSpendRequiresBothSpendReferences() public {
        PuppetTypes.RootSpendAttestation memory a = _rootSpend();
        a.previousOutpointHash = bytes32(0);
        _expectRootSpendRevert(a, IBitcoinOwnershipOracle.ZeroSpendReference.selector);

        a = _rootSpend();
        a.spendingTxid = bytes32(0);
        _expectRootSpendRevert(a, IBitcoinOwnershipOracle.ZeroSpendReference.selector);

        a = _rootSpend();
        a.authorizationId = bytes32(0);
        _expectRootSpendRevert(a, IBitcoinOwnershipOracle.ZeroAuthorizationId.selector);
    }

    function test_RootSpendRequiresCollectionMembership() public {
        PuppetTypes.RootSpendAttestation memory a = _rootSpend();
        a.rootTxid = nonMemberRoot.inscriptionTxid;
        a.rootIndex = nonMemberRoot.inscriptionIndex;

        bytes[] memory signatures = attestors.sign(oracle.hashRootSpendAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);
        bytes32 key = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);

        vm.expectRevert(abi.encodeWithSelector(IPuppetCollectionRegistry.NotCollectionMember.selector, key));
        oracle.verifyRootSpend(a, signatures, proof);
    }

    function test_RootSpendConsumesOnlyOnce() public {
        PuppetTypes.RootSpendAttestation memory a = _rootSpend();
        bytes32 digest = oracle.hashRootSpendAttestation(a);
        bytes[] memory signatures = attestors.sign(digest, THRESHOLD);
        bytes32[] memory proof = _proof(0);

        rootConsumer.consumeRootSpend(a, signatures, proof);

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.DigestAlreadyConsumed.selector, digest));
        rootConsumer.consumeRootSpend(a, signatures, proof);
    }

    /*//////////////////////////////////////////////////////////////
                         ROLES AND PURPOSE POLICY
    //////////////////////////////////////////////////////////////*/

    function test_ConstructorGrantsOnlyGovernanceRoles() public view {
        assertTrue(oracle.hasRole(defaultAdminRole, address(this)), "admin holds DEFAULT_ADMIN_ROLE");
        assertTrue(oracle.hasRole(pauserRole, address(this)), "admin holds PAUSER_ROLE");
        assertFalse(oracle.hasRole(ownershipConsumerRole, address(this)), "no consumer role at construction");
        assertFalse(oracle.hasRole(paymentConsumerRole, address(this)), "no consumer role at construction");
        assertFalse(oracle.hasRole(rootSpendConsumerRole, address(this)), "no consumer role at construction");
        assertEq(oracle.consumerPurposeMask(address(this)), 0, "no purposes at construction");
    }

    function test_ConstructorRejectsZeroArguments() public {
        vm.expectRevert(BitcoinOwnershipOracle.ZeroAddress.selector);
        new BitcoinOwnershipOracle(address(0), collection, registry);

        vm.expectRevert(BitcoinOwnershipOracle.ZeroAddress.selector);
        new BitcoinOwnershipOracle(address(this), IPuppetCollectionRegistry(address(0)), registry);

        vm.expectRevert(BitcoinOwnershipOracle.ZeroAddress.selector);
        new BitcoinOwnershipOracle(address(this), collection, IBitcoinAttestorRegistry(address(0)));
    }

    function test_ConstructorBindsRegistriesImmutably() public view {
        assertEq(address(oracle.collectionRegistry()), address(collection), "collection registry");
        assertEq(address(oracle.attestorRegistry()), address(registry), "attestor registry");
    }

    /// @dev THE FRONT-RUNNING DEFENCE. An outsider who has watched a valid quorum land in the
    ///      mempool must not be able to burn it. If this failed, every settlement in the protocol
    ///      could be denied for the cost of gas.
    function test_PublicCallerCannotBurnAValidAuthorization() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory signatures = attestors.sign(digest, THRESHOLD);
        bytes32[] memory proof = _proof(0);

        // The outsider can READ the authorization freely...
        vm.prank(OUTSIDER_EOA);
        (bytes32 verified,) = oracle.verifyOwnership(a, signatures, proof);
        assertEq(verified, digest, "verification must stay public");

        // ...but cannot burn it.
        vm.prank(OUTSIDER_EOA);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, OUTSIDER_EOA, ownershipConsumerRole
            )
        );
        oracle.consumeOwnership(a, signatures, proof);

        // ...and the legitimate consumer still succeeds afterwards.
        (bytes32 consumed,) = escrowConsumer.consumeOwnership(a, signatures, proof);
        assertEq(consumed, digest, "the authorization survived the attempt");
    }

    function test_PaymentAndRootSpendConsumptionAreRoleGated() public {
        PuppetTypes.BitcoinPaymentAttestation memory p = _payment();
        bytes[] memory paymentSignatures = attestors.sign(oracle.hashBitcoinPaymentAttestation(p), THRESHOLD);

        vm.prank(OUTSIDER_EOA);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, OUTSIDER_EOA, paymentConsumerRole
            )
        );
        oracle.consumeBitcoinPayment(p, paymentSignatures);

        PuppetTypes.RootSpendAttestation memory s = _rootSpend();
        bytes[] memory spendSignatures = attestors.sign(oracle.hashRootSpendAttestation(s), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        vm.prank(OUTSIDER_EOA);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, OUTSIDER_EOA, rootSpendConsumerRole
            )
        );
        oracle.consumeRootSpend(s, spendSignatures, proof);
    }

    /// @dev The escrow and the root registry both hold `OWNERSHIP_CONSUMER_ROLE`. Without the
    ///      purpose allowlist, either could burn the other's authorizations.
    function test_EscrowCannotConsumeARootRegistryPurpose() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipSelfCast();
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.ROOT_INVALIDATE);

        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                BitcoinOwnershipOracle.PurposeNotPermittedForConsumer.selector,
                address(escrowConsumer),
                uint8(PuppetTypes.AuthorizationPurpose.ROOT_INVALIDATE)
            )
        );
        escrowConsumer.consumeOwnership(a, signatures, proof);

        // The registry consumer, which IS permitted, succeeds on the identical attestation.
        (bytes32 consumed,) = rootConsumer.consumeOwnership(a, signatures, proof);
        assertEq(consumed, oracle.hashOwnershipAttestation(a), "the permitted consumer must succeed");
    }

    function test_RootRegistryCannotConsumeAMintPurpose() public {
        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                BitcoinOwnershipOracle.PurposeNotPermittedForConsumer.selector,
                address(rootConsumer),
                uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT)
            )
        );
        rootConsumer.consumeOwnership(a, signatures, proof);
    }

    /// @dev Fail closed. A consumer that holds the role but was never configured can consume
    ///      nothing — a missing wiring step is a loud revert, not a silent widening.
    function test_RoleWithoutPurposeGrantCanConsumeNothing() public {
        ConsumerHarness unconfigured = new ConsumerHarness(IBitcoinOwnershipOracle(address(oracle)));
        oracle.grantRole(ownershipConsumerRole, address(unconfigured));
        assertEq(oracle.consumerPurposeMask(address(unconfigured)), 0, "mask must start empty");

        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                BitcoinOwnershipOracle.PurposeNotPermittedForConsumer.selector, address(unconfigured), uint8(0)
            )
        );
        unconfigured.consumeOwnership(a, signatures, proof);
    }

    function test_PurposeMaskEncodingAndQueries() public view {
        assertEq(oracle.consumerPurposeMask(address(escrowConsumer)), 0x07, "bits 0,1,2 for the mint purposes");
        assertEq(oracle.consumerPurposeMask(address(rootConsumer)), 0x18, "bits 3,4 for the root purposes");

        assertTrue(oracle.isPurposeAllowed(address(escrowConsumer), 0), "PAID_EVM_MINT");
        assertTrue(oracle.isPurposeAllowed(address(escrowConsumer), 2), "SELF_CAST");
        assertFalse(oracle.isPurposeAllowed(address(escrowConsumer), 3), "ROOT_BIND");
        assertFalse(oracle.isPurposeAllowed(address(escrowConsumer), 200), "out-of-range must be false, not revert");
    }

    function test_PurposeMaskRejectsValuesOutsideTheEnum() public {
        uint8[] memory bad = new uint8[](1);
        bad[0] = 5;

        vm.expectRevert(abi.encodeWithSelector(BitcoinOwnershipOracle.InvalidPurposeValue.selector, uint8(5)));
        oracle.purposeMask(bad);

        vm.expectRevert(abi.encodeWithSelector(BitcoinOwnershipOracle.InvalidPurposeValue.selector, uint8(5)));
        oracle.setConsumerPurposes(address(escrowConsumer), bad);
    }

    function test_SetConsumerPurposesReplacesTheWholeMaskAndEmits() public {
        uint8[] memory onlySelfCast = new uint8[](1);
        onlySelfCast[0] = uint8(PuppetTypes.AuthorizationPurpose.SELF_CAST);

        vm.expectEmit(true, true, true, true, address(oracle));
        emit BitcoinOwnershipOracle.ConsumerPurposesUpdated(address(escrowConsumer), 0x07, 0x04);
        oracle.setConsumerPurposes(address(escrowConsumer), onlySelfCast);

        assertEq(oracle.consumerPurposeMask(address(escrowConsumer)), 0x04, "mask is replaced, not merged");
        assertFalse(oracle.isPurposeAllowed(address(escrowConsumer), 0), "the previous purposes are gone");
    }

    function test_SetConsumerPurposesWithAnEmptyArrayRevokesEverything() public {
        oracle.setConsumerPurposes(address(escrowConsumer), new uint8[](0));
        assertEq(oracle.consumerPurposeMask(address(escrowConsumer)), 0, "empty array clears the mask");
    }

    function test_OnlyAdminMayChangePurposePolicy() public {
        uint8[] memory purposes = _mintPurposes();

        vm.prank(OUTSIDER_EOA);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, OUTSIDER_EOA, defaultAdminRole
            )
        );
        oracle.setConsumerPurposes(address(escrowConsumer), purposes);

        vm.prank(OUTSIDER_EOA);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, OUTSIDER_EOA, defaultAdminRole
            )
        );
        oracle.grantOwnershipConsumer(address(escrowConsumer), purposes);
    }

    function test_GrantOwnershipConsumerIsAtomic() public {
        ConsumerHarness fresh = new ConsumerHarness(IBitcoinOwnershipOracle(address(oracle)));
        assertFalse(oracle.hasRole(ownershipConsumerRole, address(fresh)), "precondition");

        oracle.grantOwnershipConsumer(address(fresh), _mintPurposes());

        assertTrue(oracle.hasRole(ownershipConsumerRole, address(fresh)), "role granted");
        assertEq(oracle.consumerPurposeMask(address(fresh)), 0x07, "mask set in the same call");
    }

    function test_PurposePolicyRejectsTheZeroAddress() public {
        uint8[] memory purposes = _mintPurposes();

        vm.expectRevert(BitcoinOwnershipOracle.ZeroAddress.selector);
        oracle.setConsumerPurposes(address(0), purposes);

        vm.expectRevert(BitcoinOwnershipOracle.ZeroAddress.selector);
        oracle.grantOwnershipConsumer(address(0), purposes);
    }

    /*//////////////////////////////////////////////////////////////
                                  PAUSE
    //////////////////////////////////////////////////////////////*/

    function test_PauseBlocksOwnershipAndSpendButLeavesTerminalPaymentLive() public {
        PuppetTypes.OwnershipAttestation memory o = _ownershipEvm();
        bytes[] memory oSignatures = attestors.sign(oracle.hashOwnershipAttestation(o), THRESHOLD);
        PuppetTypes.BitcoinPaymentAttestation memory p = _payment();
        bytes[] memory pSignatures = attestors.sign(oracle.hashBitcoinPaymentAttestation(p), THRESHOLD);
        PuppetTypes.RootSpendAttestation memory s = _rootSpend();
        bytes[] memory sSignatures = attestors.sign(oracle.hashRootSpendAttestation(s), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        oracle.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrowConsumer.consumeOwnership(o, oSignatures, proof);

        settlementConsumer.consumeBitcoinPayment(p, pSignatures);
        bytes32 paymentDigest = oracle.hashBitcoinPaymentAttestation(p);
        assertTrue(oracle.isDigestConsumed(paymentDigest), "terminal payment consumed while paused");

        vm.expectRevert(Pausable.EnforcedPause.selector);
        rootConsumer.consumeRootSpend(s, sSignatures, proof);
    }

    /// @dev Pausing must never blind the protocol. Hashing, verification and every consumption
    ///      view stay live so relayers, indexers and incident responders can keep reading.
    function test_PauseLeavesHashingAndVerificationLive() public {
        PuppetTypes.OwnershipAttestation memory o = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(o);
        bytes[] memory signatures = attestors.sign(digest, THRESHOLD);
        bytes32[] memory proof = _proof(0);

        oracle.pause();

        assertEq(oracle.hashOwnershipAttestation(o), digest, "hashing stays live");
        assertEq(oracle.hashBitcoinPaymentAttestation(_payment()), oracle.hashBitcoinPaymentAttestation(_payment()));
        assertEq(oracle.hashRootSpendAttestation(_rootSpend()), oracle.hashRootSpendAttestation(_rootSpend()));

        (bytes32 verified,) = oracle.verifyOwnership(o, signatures, proof);
        assertEq(verified, digest, "verification stays live");

        (bytes32 paymentDigest,) = oracle.verifyBitcoinPayment(_payment(), _paymentSignatures());
        assertTrue(paymentDigest != bytes32(0), "payment verification stays live");

        assertFalse(oracle.isDigestConsumed(digest), "consumption views stay live");
        assertFalse(oracle.isPaymentOutputConsumed(_payment().bitcoinTxid, _payment().outputIndex));
        assertEq(oracle.domainSeparator(), oracle.domainSeparator(), "domain view stays live");
    }

    function test_UnpausingRestoresConsumption() public {
        oracle.pause();
        oracle.unpause();

        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        (bytes32 consumed,) = escrowConsumer.consumeOwnership(a, attestors.sign(digest, THRESHOLD), _proof(0));
        assertEq(consumed, digest, "consumption resumes after unpause");
    }

    /// @dev The guardian asymmetry: fast to stop, deliberate to restart.
    function test_PauserCanPauseButOnlyAdminCanUnpause() public {
        address guardian = address(0x64A2D1A4);
        oracle.grantRole(pauserRole, guardian);

        vm.prank(guardian);
        oracle.pause();
        assertTrue(oracle.paused(), "guardian paused");

        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, guardian, defaultAdminRole)
        );
        oracle.unpause();

        oracle.unpause();
        assertFalse(oracle.paused(), "the timelock admin unpauses");
    }

    function test_OnlyPauserMayPause() public {
        vm.prank(OUTSIDER_EOA);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, OUTSIDER_EOA, pauserRole)
        );
        oracle.pause();
    }

    /*//////////////////////////////////////////////////////////////
                          SURFACE AND INTERFACES
    //////////////////////////////////////////////////////////////*/

    function test_SupportsInterface() public view {
        assertTrue(oracle.supportsInterface(type(IBitcoinOwnershipOracle).interfaceId), "oracle interface");
        assertTrue(oracle.supportsInterface(type(IAccessControl).interfaceId), "access control");
        assertTrue(oracle.supportsInterface(0x01ffc9a7), "erc165");
        assertFalse(oracle.supportsInterface(0xffffffff), "the ERC-165 invalid id");
    }

    /// @dev Scans the deployed RUNTIME BYTECODE for forbidden selectors instead of only checking
    ///      that calls revert: a call with malformed arguments reverts whether or not the function
    ///      exists, which would make a call-based version close to vacuous. A positive control is
    ///      included so the scan cannot pass by finding nothing at all.
    function test_NoUpgradeOwnerOrValueSurfaceExists() public view {
        bytes memory code = address(oracle).code;
        assertTrue(code.length > 0, "the oracle must have runtime code");

        string[10] memory forbidden = [
            "upgradeTo(address)",
            "upgradeToAndCall(address,bytes)",
            "initialize(address)",
            "transferOwnership(address)",
            "owner()",
            "setCollectionRegistry(address)",
            "setAttestorRegistry(address)",
            "clearDigest(bytes32)",
            "withdraw()",
            "implementation()"
        ];
        for (uint256 i = 0; i < forbidden.length; i++) {
            assertFalse(
                _containsSelector(code, bytes4(keccak256(bytes(forbidden[i])))),
                string.concat("forbidden selector present: ", forbidden[i])
            );
        }

        assertTrue(
            _containsSelector(code, bytes4(keccak256("isDigestConsumed(bytes32)"))),
            "positive control: the scanner must be able to find a selector that IS present"
        );
    }

    /// @dev No payable function anywhere, so the oracle cannot hold or move value and no admin path
    ///      can seize a balance through it.
    function test_OracleCannotReceiveValue() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(oracle).call{value: 1 ether}("");
        assertFalse(ok, "the oracle must reject plain ETH");
        assertEq(address(oracle).balance, 0, "the oracle must never hold value");
    }

    /*//////////////////////////////////////////////////////////////
                    GOLDEN EIP-712 VECTORS (CROSS-LANGUAGE)
    //////////////////////////////////////////////////////////////*/

    /// @dev The pinned deployment used by `data/test-fixtures/eip712-vectors.json`. The address is
    ///      deliberately a placeholder that no deployment will ever occupy; the vector pins the
    ///      DOMAIN, not a real contract.
    address internal constant PINNED_VERIFYING_CONTRACT = address(0x0000000000000000000000000000000000C0FFEE);
    uint256 internal constant PINNED_CHAIN_ID = 31_337;

    /// @dev WHY THESE ARE SOLIDITY CONSTANTS AND NOT PARSED FROM THE JSON FILE.
    ///      The Foundry project root is `contracts/`, and `foundry.toml` grants read access to
    ///      `./` only, so `vm.readFile("../data/...")` is denied. Rather than reach outside my
    ///      ownership boundary to widen `fs_permissions`, the authoritative values live here, are
    ///      re-derived by the real contract on every run, and are copied verbatim into
    ///      `data/test-fixtures/eip712-vectors.json`. The one-line change that would let CI diff
    ///      the file directly is named in that file under `_HOW_TO_MAKE_CI_DIFF_THIS_FILE`.
    ///
    ///      Every value below was OBSERVED by running this suite, never hand-derived.
    bytes32 internal constant PINNED_DOMAIN_SEPARATOR =
        0xb576263998b174b7c6045062e95c46b6b5e9506ac48adfc71d2d2ab1330173c0;
    bytes32 internal constant PINNED_OWNERSHIP_DIGEST =
        0x4b9ec9611a2dbcf6834ff97f8a9a8f509862877fc5a95669a873c3a1624ddc7d;
    bytes32 internal constant PINNED_OWNERSHIP_SELF_CAST_DIGEST =
        0x1fbedfa6877e82e605f8a64efca78b5aee879885280a1c3cebc8cbfd65d61238;
    bytes32 internal constant PINNED_PAYMENT_DIGEST =
        0xb9d6f38cc86314dc287a822ca2d66d8d6587aa0f4ad48ae75c70eb4a0cd81aa6;
    bytes32 internal constant PINNED_ROOT_SPEND_DIGEST =
        0xd6e9890cd2404b96d579501dcebf113f851cca391e73945d441e266b151851c3;
    bytes32 internal constant PINNED_OWNERSHIP_SELF_CAST_STRUCT_HASH =
        0x9cc04bf0738b648cea39fe05b4c0d2f4f919f49da94571b2e8043a8e0a3bc552;

    /// @dev Re-derives the pinned domain separator from the EIP-712 formula, then checks that the
    ///      REAL contract, running at the pinned address and chain id, produces exactly it. Two
    ///      independent derivations of one value: a wrong name, version, chain id or verifying
    ///      contract fails the first, and a wrong `EIP712` wiring fails the second.
    function test_PinnedDomainSeparatorMatchesTheContract() public {
        bytes32 formula = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("HoodPups Bitcoin Oracle")),
                keccak256(bytes("1")),
                PINNED_CHAIN_ID,
                PINNED_VERIFYING_CONTRACT
            )
        );
        assertEq(formula, PINNED_DOMAIN_SEPARATOR, "the pinned domain separator drifted from the formula");

        BitcoinOwnershipOracle pinned = _pinnedOracle();
        assertEq(pinned.domainSeparator(), PINNED_DOMAIN_SEPARATOR, "the contract must reproduce it");
    }

    /// @dev Every digest published in the fixture file, re-derived by the real contract at the
    ///      pinned domain. This is what the SDK and the five attestor services are validated
    ///      against; if any of them builds a different digest, its signatures are simply not
    ///      recognised — a silent liveness failure unless it is caught here.
    function test_PinnedDigestsMatchTheContract() public {
        BitcoinOwnershipOracle pinned = _pinnedOracle();

        assertEq(pinned.hashOwnershipAttestation(_vectorOwnership()), PINNED_OWNERSHIP_DIGEST, "ownership digest");
        assertEq(
            pinned.hashOwnershipAttestation(_vectorOwnershipSelfCast()),
            PINNED_OWNERSHIP_SELF_CAST_DIGEST,
            "self-cast ownership digest"
        );
        assertEq(pinned.hashBitcoinPaymentAttestation(_vectorPayment()), PINNED_PAYMENT_DIGEST, "payment digest");
        assertEq(pinned.hashRootSpendAttestation(_vectorRootSpend()), PINNED_ROOT_SPEND_DIGEST, "root-spend digest");
    }

    /// @dev The vectors COMPOSE with the struct hashes already pinned in
    ///      `data/test-fixtures/hashing-vectors.json`, which is why three of the four instances
    ///      reuse that file's field values byte for byte:
    ///      `digest == keccak256(0x1901 ‖ domainSeparator ‖ hashStruct)`.
    ///      A drift in either file therefore shows up in both suites rather than in neither.
    function test_PinnedDigestsComposeWithThePinnedStructHashes() public pure {
        // These three struct hashes are the `hashStruct/*` expectations in hashing-vectors.json.
        assertEq(
            PuppetHashing.hashStruct(_vectorOwnership()),
            0xb02af5de3a4d7b7536a5fbe847a692c8966ef3560d5c9cd9cb7646c4f219720b,
            "ownership struct hash must equal the value pinned in hashing-vectors.json"
        );
        assertEq(
            PuppetHashing.hashStruct(_vectorPayment()),
            0x8cdccdfbbf7f4dbeb03ae231279a7cceea59a2db60257f029728fd4c28824720,
            "payment struct hash must equal the value pinned in hashing-vectors.json"
        );
        assertEq(
            PuppetHashing.hashStruct(_vectorRootSpend()),
            0x7d3fff25a330d6aaf3de6ee172afaf703947ab560c25eb617943d8d9b2cfeb28,
            "root-spend struct hash must equal the value pinned in hashing-vectors.json"
        );
        assertEq(
            PuppetHashing.hashStruct(_vectorOwnershipSelfCast()),
            PINNED_OWNERSHIP_SELF_CAST_STRUCT_HASH,
            "self-cast struct hash"
        );

        assertEq(
            keccak256(
                abi.encodePacked(hex"1901", PINNED_DOMAIN_SEPARATOR, PuppetHashing.hashStruct(_vectorOwnership()))
            ),
            PINNED_OWNERSHIP_DIGEST,
            "ownership composition"
        );
        assertEq(
            keccak256(abi.encodePacked(hex"1901", PINNED_DOMAIN_SEPARATOR, PuppetHashing.hashStruct(_vectorPayment()))),
            PINNED_PAYMENT_DIGEST,
            "payment composition"
        );
        assertEq(
            keccak256(
                abi.encodePacked(hex"1901", PINNED_DOMAIN_SEPARATOR, PuppetHashing.hashStruct(_vectorRootSpend()))
            ),
            PINNED_ROOT_SPEND_DIGEST,
            "root-spend composition"
        );
    }

    /// @dev The self-cast vector is the semantically valid one, so it must survive the real
    ///      `verifyOwnership` shape checks and not merely hash correctly.
    function test_SelfCastVectorIsAStructurallyValidAttestation() public view {
        PuppetTypes.OwnershipAttestation memory a = _vectorOwnershipSelfCast();
        assertEq(a.payoutMode, uint8(PuppetTypes.PayoutMode.NONE), "self-cast carries no payout mode");
        assertEq(a.evmPayout, address(0), "no EVM payout");
        assertEq(a.btcPayoutScriptHash, bytes32(0), "no BTC payout");
        assertEq(a.sellerSats, 0, "no sats");
        assertEq(a.grossWei, 0, "no gross");
        assertEq(a.sellerWei, 0, "no seller share");
        assertTrue(oracle.isPurposeAllowed(address(escrowConsumer), a.purpose), "the escrow may consume it");
    }

    /*//////////////////////////////////////////////////////////////
                              LIGHT FUZZING
                (the dedicated campaign lives in test/fuzz)
    //////////////////////////////////////////////////////////////*/

    /// @dev No signature count below the threshold is ever accepted, and no count at or above it is
    ///      ever rejected for a count-related reason.
    function testFuzz_SignatureCountBoundary(uint8 count) public {
        count = uint8(bound(count, 0, ATTESTOR_COUNT));

        PuppetTypes.OwnershipAttestation memory a = _ownershipEvm();
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory signatures = attestors.sign(digest, count);
        bytes32[] memory proof = _proof(0);

        if (count < THRESHOLD) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IBitcoinOwnershipOracle.InsufficientSignatures.selector, uint256(count), THRESHOLD
                )
            );
            oracle.verifyOwnership(a, signatures, proof);
        } else {
            (bytes32 verified,) = oracle.verifyOwnership(a, signatures, proof);
            assertEq(verified, digest, "any count at or above threshold must verify");
        }
    }

    /// @dev A payment output key is injective over (txid, vout), so no pair of distinct outputs can
    ///      collide into one consumed slot and block a legitimate settlement.
    function testFuzz_PaymentOutputKeyIsInjective(bytes32 txidA, uint32 voutA, bytes32 txidB, uint32 voutB)
        public
        pure
    {
        vm.assume(txidA != txidB || voutA != voutB);
        assertTrue(
            PuppetHashing.paymentOutputKey(txidA, voutA) != PuppetHashing.paymentOutputKey(txidB, voutB),
            "distinct Bitcoin outputs must never share a consumption key"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Every fixture txid begins with the ASCII marker "FIXTURE-NOT-REAL" so none of these
    ///      identities can be mistaken for a real Bitcoin transaction or a real Bitcoin Puppets
    ///      inscription. No plausible-looking mainnet inscription id is invented anywhere.
    // Truncating the keccak output to 16 bytes is the point: the first half of every fixture txid
    // is the literal marker, so no value here can be mistaken for a real Bitcoin transaction.
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

    function _mintPurposes() internal pure returns (uint8[] memory purposes) {
        purposes = new uint8[](3);
        purposes[0] = uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT);
        purposes[1] = uint8(PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT);
        purposes[2] = uint8(PuppetTypes.AuthorizationPurpose.SELF_CAST);
    }

    function _rootPurposes() internal pure returns (uint8[] memory purposes) {
        purposes = new uint8[](2);
        purposes[0] = uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND);
        purposes[1] = uint8(PuppetTypes.AuthorizationPurpose.ROOT_INVALIDATE);
    }

    function _ownershipEvm() internal view returns (PuppetTypes.OwnershipAttestation memory a) {
        a = PuppetTypes.OwnershipAttestation({
            purpose: uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT),
            rootTxid: fixtureRoots[0].inscriptionTxid,
            rootIndex: fixtureRoots[0].inscriptionIndex,
            contextId: keccak256("offer-1"),
            offerTermsHash: keccak256("terms-1"),
            currentOutpointHash: PuppetHashing.outpointHash(_fixtureTxid("current-outpoint"), 1),
            ownerScriptHash: keccak256("owner-script"),
            bip322ProofHash: keccak256("bip322-proof"),
            buyer: BUYER,
            recipient: RECIPIENT,
            payoutMode: uint8(PuppetTypes.PayoutMode.EVM),
            evmPayout: SELLER_EVM,
            btcPayoutScriptHash: bytes32(0),
            sellerSats: 0,
            grossWei: 1 ether,
            sellerWei: 0.5 ether,
            bitcoinBlockHash: keccak256("bitcoin-block"),
            bitcoinHeight: 880_000,
            authorizationId: keccak256("authorization-1"),
            deadline: uint64(block.timestamp + 1 hours),
            attestorEpoch: EPOCH,
            policyVersion: POLICY
        });
    }

    function _ownershipBtc() internal view returns (PuppetTypes.OwnershipAttestation memory a) {
        a = _ownershipEvm();
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.BTC);
        a.evmPayout = address(0);
        a.btcPayoutScriptHash = keccak256("seller-btc-script");
        a.sellerSats = 250_000;
        a.authorizationId = keccak256("authorization-btc");
    }

    function _ownershipSelfCast() internal view returns (PuppetTypes.OwnershipAttestation memory a) {
        a = _ownershipEvm();
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.SELF_CAST);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.NONE);
        a.evmPayout = address(0);
        a.btcPayoutScriptHash = bytes32(0);
        a.sellerSats = 0;
        a.grossWei = 0;
        a.sellerWei = 0;
        a.buyer = address(0);
        a.authorizationId = keccak256("authorization-self-cast");
    }

    function _payment() internal view returns (PuppetTypes.BitcoinPaymentAttestation memory a) {
        a = PuppetTypes.BitcoinPaymentAttestation({
            contextId: keccak256("offer-1"),
            ownershipDigest: keccak256("ownership-digest-1"),
            solver: SOLVER,
            bitcoinTxid: _fixtureTxid("payment-transaction"),
            outputIndex: 1,
            recipientScriptHash: keccak256("seller-btc-script"),
            amountSats: 250_000,
            bitcoinBlockHash: keccak256("bitcoin-block"),
            bitcoinHeight: 880_001,
            authorizationId: keccak256("authorization-payment"),
            deadline: uint64(block.timestamp + 1 hours),
            attestorEpoch: EPOCH,
            policyVersion: POLICY
        });
    }

    function _paymentSignatures() internal view returns (bytes[] memory) {
        return attestors.sign(oracle.hashBitcoinPaymentAttestation(_payment()), THRESHOLD);
    }

    function _rootSpend() internal view returns (PuppetTypes.RootSpendAttestation memory a) {
        a = PuppetTypes.RootSpendAttestation({
            rootTxid: fixtureRoots[0].inscriptionTxid,
            rootIndex: fixtureRoots[0].inscriptionIndex,
            previousOutpointHash: PuppetHashing.outpointHash(_fixtureTxid("current-outpoint"), 1),
            spendingTxid: _fixtureTxid("spending-transaction"),
            bitcoinBlockHash: keccak256("bitcoin-block"),
            bitcoinHeight: 880_002,
            authorizationId: keccak256("authorization-spend"),
            deadline: uint64(block.timestamp + 1 hours),
            attestorEpoch: EPOCH,
            policyVersion: POLICY
        });
    }

    function _expectInvalidPayoutShape(PuppetTypes.OwnershipAttestation memory a) internal {
        bytes[] memory signatures = attestors.sign(oracle.hashOwnershipAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(IBitcoinOwnershipOracle.InvalidPayoutShape.selector);
        oracle.verifyOwnership(a, signatures, proof);
    }

    function _expectPaymentRevert(PuppetTypes.BitcoinPaymentAttestation memory a, bytes4 selector) internal {
        bytes[] memory signatures = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), THRESHOLD);

        vm.expectRevert(selector);
        oracle.verifyBitcoinPayment(a, signatures);
    }

    function _expectRootSpendRevert(PuppetTypes.RootSpendAttestation memory a, bytes4 selector) internal {
        bytes[] memory signatures = attestors.sign(oracle.hashRootSpendAttestation(a), THRESHOLD);
        bytes32[] memory proof = _proof(0);

        vm.expectRevert(selector);
        oracle.verifyRootSpend(a, signatures, proof);
    }

    /// @dev Creation indices `0..n-1` sorted by attestor address, mirroring what `AttestorSet.sign`
    ///      produces. Needed to know WHICH key sits at a given position in the signature array.
    function _sortedFirstIndices(uint256 n) internal view returns (uint256[] memory indices) {
        indices = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            indices[i] = i;
        }
        for (uint256 i = 1; i < n; i++) {
            uint256 key = indices[i];
            address keyAddr = attestors.addressAt(key);
            uint256 j = i;
            while (j > 0 && attestors.addressAt(indices[j - 1]) > keyAddr) {
                indices[j] = indices[j - 1];
                j--;
            }
            indices[j] = key;
        }
    }

    function _sortedFirstAddress(uint256 n) internal view returns (address) {
        return attestors.addressAt(_sortedFirstIndices(n)[0]);
    }

    /// @dev `(r, N - s, v ^ 1)` recovers to the same address under raw `ecrecover` but carries an
    ///      upper-half `s`, which EIP-2 and OpenZeppelin both reject.
    function _malleableSignature(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        bytes32 flippedS = bytes32(SECP256K1_N - uint256(s));
        uint8 flippedV = v == 27 ? 28 : 27;
        return abi.encodePacked(r, flippedS, flippedV);
    }

    function _split(bytes memory signature) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        assembly ("memory-safe") {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
    }

    /// @dev Naive 4-byte scan. It can only ever produce a FALSE FAILURE (a coincidental byte
    ///      sequence), never a false pass, which is the correct direction for a security assertion.
    function _containsSelector(bytes memory code, bytes4 selector) internal pure returns (bool) {
        if (code.length < 4) return false;
        for (uint256 i = 0; i + 4 <= code.length; i++) {
            if (
                code[i] == selector[0] && code[i + 1] == selector[1] && code[i + 2] == selector[2]
                    && code[i + 3] == selector[3]
            ) {
                return true;
            }
        }
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                        GOLDEN-VECTOR FIXTURE DATA
    //////////////////////////////////////////////////////////////*/

    /// @dev Copies the real oracle's runtime code to the pinned address and switches to the pinned
    ///      chain id. OpenZeppelin's `EIP712` caches its domain separator against the deploying
    ///      address and chain id and REBUILDS whenever either differs, so the copy at the pinned
    ///      address genuinely derives the pinned domain rather than replaying a cached one.
    function _pinnedOracle() internal returns (BitcoinOwnershipOracle) {
        vm.chainId(PINNED_CHAIN_ID);
        vm.etch(PINNED_VERIFYING_CONTRACT, address(oracle).code);
        return BitcoinOwnershipOracle(PINNED_VERIFYING_CONTRACT);
    }

    /// @dev Byte-for-byte the `hashStruct/OwnershipAttestation` instance already pinned in
    ///      `data/test-fixtures/hashing-vectors.json`. Reusing it means the two files COMPOSE: the
    ///      struct hash is pinned there, the domain and digest here, and a drift in either shows up
    ///      as a failure in both suites rather than in neither.
    ///
    ///      It is deliberately a HASHING vector, not a semantically valid attestation: every field
    ///      is non-zero, including ones a real PAID_EVM_MINT would leave zero, because zero fields
    ///      hide field-ordering bugs. `verifyOwnership` would reject it on payout shape, and
    ///      `_vectorOwnershipSelfCast` exists as the semantically valid counterpart.
    function _vectorOwnership() internal pure returns (PuppetTypes.OwnershipAttestation memory a) {
        a = PuppetTypes.OwnershipAttestation({
            purpose: 0,
            rootTxid: 0x1f9f8a6d2c4b7e0135a9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7,
            rootIndex: 0,
            contextId: 0x59b74fc7f15158d3fe2af015aa1cd19e16d6d44bc195d2590e45200ef7af39e4,
            offerTermsHash: 0x8d980d7bc135673fcf6b5f8de2b3029feac6fe51448352999f3d58cc680bdfb8,
            currentOutpointHash: 0x1e910b1b6b7ed6bc6e12a2b6549a3bbb6ceedae0aae41b546200403b7a872526,
            ownerScriptHash: 0xa8dff22a679ccee9973bbcce0bf96a43738f5034bfcf3d27a8f75ee450fe4c8d,
            bip322ProofHash: 0x05164637df72d81c3d23f034ced84407afdf70f899d7e5a5243bc2d68e554756,
            buyer: 0x2222222222222222222222222222222222222222,
            recipient: 0x3333333333333333333333333333333333333333,
            payoutMode: 1,
            evmPayout: 0x4444444444444444444444444444444444444444,
            btcPayoutScriptHash: 0xfe4da2fb7b6e4bd4d89d528e680844b60ffba5f41cbfbd2401e7d52c7a4ea16e,
            sellerSats: 250_000,
            grossWei: 1_000_000_000_000_000_000,
            sellerWei: 500_000_000_000_000_000,
            bitcoinBlockHash: 0x0000000000000000000159f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5,
            bitcoinHeight: 880_000,
            authorizationId: 0xee7620f74b8888194261a6d381ca219b11f9f3973776e0500e0030d3518288f1,
            deadline: 1_893_456_000,
            attestorEpoch: 7,
            policyVersion: 1
        });
    }

    /// @dev A semantically VALID attestation, so an attestor service has an example that both
    ///      hashes correctly and would actually pass `verifyOwnership`.
    function _vectorOwnershipSelfCast() internal pure returns (PuppetTypes.OwnershipAttestation memory a) {
        a = _vectorOwnership();
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.SELF_CAST);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.NONE);
        a.buyer = address(0);
        a.evmPayout = address(0);
        a.btcPayoutScriptHash = bytes32(0);
        a.sellerSats = 0;
        a.grossWei = 0;
        a.sellerWei = 0;
    }

    function _vectorPayment() internal pure returns (PuppetTypes.BitcoinPaymentAttestation memory a) {
        a = PuppetTypes.BitcoinPaymentAttestation({
            contextId: 0x59b74fc7f15158d3fe2af015aa1cd19e16d6d44bc195d2590e45200ef7af39e4,
            ownershipDigest: 0x840ab6e778db7e0e0bd0dfead427aedd32ee8ca505aef41caf4ed3fa8adc28cf,
            solver: 0x5555555555555555555555555555555555555555,
            bitcoinTxid: 0x3e5a7c9e0b2d4f6183a5c7e9012b3d5f7a9c1e3f5b7d90124a6c8e0b2d4f6183,
            outputIndex: 1,
            recipientScriptHash: 0xa8dff22a679ccee9973bbcce0bf96a43738f5034bfcf3d27a8f75ee450fe4c8d,
            amountSats: 250_000,
            bitcoinBlockHash: 0x0000000000000000000159f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5,
            bitcoinHeight: 880_001,
            authorizationId: 0xe542a5fd8cfa920156ec941384fbf34106e12827c0d6a84c204467640b5e3b75,
            deadline: 1_893_456_000,
            attestorEpoch: 7,
            policyVersion: 1
        });
    }

    function _vectorRootSpend() internal pure returns (PuppetTypes.RootSpendAttestation memory a) {
        a = PuppetTypes.RootSpendAttestation({
            rootTxid: 0x1f9f8a6d2c4b7e0135a9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7,
            rootIndex: 0,
            previousOutpointHash: 0x1e910b1b6b7ed6bc6e12a2b6549a3bbb6ceedae0aae41b546200403b7a872526,
            spendingTxid: 0xb4d6f8092a4c6e801b3d5f7991a3c5e7092b4d6f81a3c5e79b0d2f4a6c8e0193,
            bitcoinBlockHash: 0x0000000000000000000159f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5,
            bitcoinHeight: 880_002,
            authorizationId: 0x96c40ac3410eda9d552afb40f4dfb52e0c01de3fbeeafdfd639630634e50e7c7,
            deadline: 1_893_456_000,
            attestorEpoch: 7,
            policyVersion: 1
        });
    }

    /// @dev Mutates exactly one field of an ownership attestation. Used to prove every field is
    ///      bound into the digest.
    function _mutateOwnershipField(PuppetTypes.OwnershipAttestation memory base, uint256 field)
        internal
        pure
        returns (PuppetTypes.OwnershipAttestation memory a)
    {
        a = base;
        if (field == 0) a.purpose = base.purpose + 1;
        else if (field == 1) a.rootTxid = bytes32(uint256(base.rootTxid) ^ 1);
        else if (field == 2) a.rootIndex = base.rootIndex + 1;
        else if (field == 3) a.contextId = bytes32(uint256(base.contextId) ^ 1);
        else if (field == 4) a.offerTermsHash = bytes32(uint256(base.offerTermsHash) ^ 1);
        else if (field == 5) a.currentOutpointHash = bytes32(uint256(base.currentOutpointHash) ^ 1);
        else if (field == 6) a.ownerScriptHash = bytes32(uint256(base.ownerScriptHash) ^ 1);
        else if (field == 7) a.bip322ProofHash = bytes32(uint256(base.bip322ProofHash) ^ 1);
        else if (field == 8) a.buyer = address(uint160(base.buyer) ^ 1);
        else if (field == 9) a.recipient = address(uint160(base.recipient) ^ 1);
        else if (field == 10) a.payoutMode = base.payoutMode + 1;
        else if (field == 11) a.evmPayout = address(uint160(base.evmPayout) ^ 1);
        else if (field == 12) a.btcPayoutScriptHash = bytes32(uint256(base.btcPayoutScriptHash) ^ 1);
        else if (field == 13) a.sellerSats = base.sellerSats + 1;
        else if (field == 14) a.grossWei = base.grossWei + 1;
        else if (field == 15) a.sellerWei = base.sellerWei + 1;
        else if (field == 16) a.bitcoinBlockHash = bytes32(uint256(base.bitcoinBlockHash) ^ 1);
        else if (field == 17) a.bitcoinHeight = base.bitcoinHeight + 1;
        else if (field == 18) a.authorizationId = bytes32(uint256(base.authorizationId) ^ 1);
        else if (field == 19) a.deadline = base.deadline + 1;
        else if (field == 20) a.attestorEpoch = base.attestorEpoch + 1;
        else a.policyVersion = base.policyVersion + 1;
    }
}
