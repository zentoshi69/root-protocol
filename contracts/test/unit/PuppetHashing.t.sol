// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Test} from "forge-std/Test.sol";

import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";
import {AttestorSet} from "../helpers/AttestorSet.sol";
import {MerkleFixture} from "../helpers/MerkleFixture.sol";

/// @title PuppetHashingFixtures
/// @notice Shared fixture inputs for the golden-vector suite.
/// @dev Every value below is mirrored field-for-field in `data/test-fixtures/hashing-vectors.json`,
///      which is what the TypeScript SDK is validated against. If a constant changes here it MUST
///      change there in the same commit, or Solidity and TypeScript have silently forked.
///
///      THE TXIDS ARE SYNTHETIC. They are structurally valid 32-byte values chosen for
///      reproducibility; none of them is a real Bitcoin transaction and none of them identifies a
///      real Bitcoin Puppets inscription. The real manifest is committed separately and verified
///      independently before mainnet.
abstract contract PuppetHashingFixtures is Test {
    /// @dev Fixture inscription A. Shares its reveal txid with B, differing only by index — the
    ///      collision case `rootKey` must separate.
    bytes32 internal constant TXID_A = 0x1f9f8a6d2c4b7e0135a9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7;
    uint32 internal constant INDEX_A = 0;
    uint32 internal constant INDEX_B = 1;

    /// @dev Fixture inscription C: unrelated reveal txid, non-zero index.
    bytes32 internal constant TXID_C = 0xa3c5e7091b2d4f6880a1c3e5d7f9b0a2c4e6f8091a3b5c7d9e0f1a2b3c4d5e6f;
    uint32 internal constant INDEX_C = 7;

    bytes32 internal constant OUTPOINT_TXID = 0x7c1d3f5a9b2e46081a3c5e7092b4d6f80e2a4c6e8103957bd5f7192b3d4f6a8c;
    uint32 internal constant OUTPOINT_VOUT = 2;

    bytes32 internal constant PAYMENT_TXID = 0x3e5a7c9e0b2d4f6183a5c7e9012b3d5f7a9c1e3f5b7d90124a6c8e0b2d4f6183;
    uint32 internal constant PAYMENT_VOUT = 1;

    bytes32 internal constant SPEND_TXID = 0xb4d6f8092a4c6e801b3d5f7991a3c5e7092b4d6f81a3c5e79b0d2f4a6c8e0193;
    bytes32 internal constant BLOCK_HASH = 0x0000000000000000000159f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5;

    /// @dev A real-shaped P2TR scriptPubKey: OP_1 (0x51), PUSH32 (0x20), then the 32-byte tweaked
    ///      output key. 34 bytes total. Bitcoin Puppets are taproot inscriptions, so this is the
    ///      script shape `ownerScriptHash` will actually cover in production.
    bytes internal constant P2TR_SCRIPT_PUBKEY =
        hex"5120a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2";

    uint256 internal constant CHAIN_ID = 31_337;
    address internal constant ESCROW = 0x1111111111111111111111111111111111111111;
    address internal constant BUYER = 0x2222222222222222222222222222222222222222;
    address internal constant RECIPIENT = 0x3333333333333333333333333333333333333333;
    address internal constant EVM_PAYOUT = 0x4444444444444444444444444444444444444444;
    address internal constant SOLVER = 0x5555555555555555555555555555555555555555;
    address internal constant VAULT_BENEFICIARY = 0x6666666666666666666666666666666666666666;

    uint256 internal constant BUYER_NONCE = 3;
    uint256 internal constant GROSS_WEI = 1 ether;
    uint256 internal constant SELLER_WEI = 0.5 ether;
    uint64 internal constant SELLER_SATS = 250_000;
    uint64 internal constant EXPIRY = 1_893_456_000;
    uint64 internal constant DEADLINE = 1_893_456_000;
    uint64 internal constant ATTESTOR_EPOCH = 7;
    uint32 internal constant POLICY_VERSION = 1;

    bytes32 internal constant BIP322_PROOF_HASH = keccak256("HOODPUPS_FIXTURE_BIP322_PROOF");
    bytes32 internal constant BTC_PAYOUT_SCRIPT_HASH = keccak256("HOODPUPS_FIXTURE_BTC_PAYOUT_SCRIPT");
    bytes32 internal constant FIXTURE_OWNERSHIP_DIGEST = keccak256("HOODPUPS_FIXTURE_OWNERSHIP_DIGEST");
    bytes32 internal constant AUTH_ID_1 = keccak256("HOODPUPS_FIXTURE_AUTHORIZATION_1");
    bytes32 internal constant AUTH_ID_2 = keccak256("HOODPUPS_FIXTURE_AUTHORIZATION_2");
    bytes32 internal constant AUTH_ID_3 = keccak256("HOODPUPS_FIXTURE_AUTHORIZATION_3");

    /*//////////////////////////////////////////////////////////////
                          FULLY POPULATED STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Every field is deliberately non-zero, INCLUDING fields a real PAID_EVM attestation
    ///      would leave zero (`btcPayoutScriptHash`, `sellerSats`). This is a hashing vector, not
    ///      a semantically valid attestation: a zero field would hide a field-ordering bug,
    ///      because swapping two zero words changes nothing. Payout-shape validation belongs to
    ///      `BitcoinOwnershipOracle`, and it would reject this exact struct.
    function ownershipFixture() internal pure returns (PuppetTypes.OwnershipAttestation memory a) {
        bytes32 id = PuppetHashing.offerId(CHAIN_ID, ESCROW, BUYER, BUYER_NONCE);
        a = PuppetTypes.OwnershipAttestation({
            purpose: uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT),
            rootTxid: TXID_A,
            rootIndex: INDEX_A,
            contextId: id,
            offerTermsHash: offerTermsFixture(),
            currentOutpointHash: PuppetHashing.outpointHash(OUTPOINT_TXID, OUTPOINT_VOUT),
            ownerScriptHash: PuppetHashing.scriptHash(P2TR_SCRIPT_PUBKEY),
            bip322ProofHash: BIP322_PROOF_HASH,
            buyer: BUYER,
            recipient: RECIPIENT,
            payoutMode: uint8(PuppetTypes.PayoutMode.EVM),
            evmPayout: EVM_PAYOUT,
            btcPayoutScriptHash: BTC_PAYOUT_SCRIPT_HASH,
            sellerSats: SELLER_SATS,
            grossWei: GROSS_WEI,
            sellerWei: SELLER_WEI,
            bitcoinBlockHash: BLOCK_HASH,
            bitcoinHeight: 880_000,
            authorizationId: AUTH_ID_1,
            deadline: DEADLINE,
            attestorEpoch: ATTESTOR_EPOCH,
            policyVersion: POLICY_VERSION
        });
    }

    /// @dev Fully populated Bitcoin payment attestation fixture.
    function paymentFixture() internal pure returns (PuppetTypes.BitcoinPaymentAttestation memory a) {
        a = PuppetTypes.BitcoinPaymentAttestation({
            contextId: PuppetHashing.offerId(CHAIN_ID, ESCROW, BUYER, BUYER_NONCE),
            ownershipDigest: FIXTURE_OWNERSHIP_DIGEST,
            solver: SOLVER,
            bitcoinTxid: PAYMENT_TXID,
            outputIndex: PAYMENT_VOUT,
            recipientScriptHash: PuppetHashing.scriptHash(P2TR_SCRIPT_PUBKEY),
            amountSats: SELLER_SATS,
            bitcoinBlockHash: BLOCK_HASH,
            bitcoinHeight: 880_001,
            authorizationId: AUTH_ID_2,
            deadline: DEADLINE,
            attestorEpoch: ATTESTOR_EPOCH,
            policyVersion: POLICY_VERSION
        });
    }

    /// @dev Fully populated root-spend attestation fixture.
    function spendFixture() internal pure returns (PuppetTypes.RootSpendAttestation memory a) {
        a = PuppetTypes.RootSpendAttestation({
            rootTxid: TXID_A,
            rootIndex: INDEX_A,
            previousOutpointHash: PuppetHashing.outpointHash(OUTPOINT_TXID, OUTPOINT_VOUT),
            spendingTxid: SPEND_TXID,
            bitcoinBlockHash: BLOCK_HASH,
            bitcoinHeight: 880_002,
            authorizationId: AUTH_ID_3,
            deadline: DEADLINE,
            attestorEpoch: ATTESTOR_EPOCH,
            policyVersion: POLICY_VERSION
        });
    }

    /// @dev The offer-terms commitment the ownership fixture is bound to.
    function offerTermsFixture() internal pure returns (bytes32) {
        return PuppetHashing.offerTermsHash(
            CHAIN_ID,
            ESCROW,
            PuppetHashing.offerId(CHAIN_ID, ESCROW, BUYER, BUYER_NONCE),
            uint8(PuppetTypes.OfferKind.PAID_EVM),
            PuppetHashing.rootKey(TXID_A, INDEX_A),
            BUYER,
            RECIPIENT,
            GROSS_WEI,
            SELLER_WEI,
            SELLER_SATS,
            EXPIRY
        );
    }
}

/// @title PuppetHashingTest
/// @notice Golden vectors for every protocol hash. THIS IS THE CROSS-LANGUAGE CONTRACT.
/// @dev These constants are not decoration. Five independent attestor operators, a TypeScript SDK
///      and a Rust verifier each recompute these hashes; if any of them drifts by one byte the
///      quorum silently stops reaching consensus and every mint fails — or worse, two
///      implementations agree on a digest the third never authorized. Pinning the expected outputs
///      here, rather than recomputing them with the same library under test, is what makes the
///      test capable of catching a change to `PuppetHashing` itself.
///
///      Every expected value below was produced by RUNNING this suite against `PuppetHashing.sol`
///      and reading the observed output. None was hand-derived.
contract PuppetHashingTest is PuppetHashingFixtures {
    /*//////////////////////////////////////////////////////////////
                          EXPECTED GOLDEN VALUES
    //////////////////////////////////////////////////////////////*/

    bytes32 internal constant EXPECT_COLLECTION_ID = 0x3343dd53bae221cbae39fcca5d3c2c62e89e268149b83a35ba197aefd15463e6;
    bytes32 internal constant EXPECT_OUTPOINT_DOMAIN =
        0xf9d27b03fada0c27860ad28c17e301e7f24a1a1e7e9ccb365fb0e40507b42802;
    bytes32 internal constant EXPECT_PAYMENT_OUTPUT_DOMAIN =
        0x68f3bafcc5a23fe65e4b87bc48bc818d78c7623c3afc0b0ed71b07da2dc638be;
    bytes32 internal constant EXPECT_OFFER_TERMS_DOMAIN =
        0xe45cdc297b8d19010e945d1d89426abb1cffc7cdb145f86559774fca480bbbe0;
    bytes32 internal constant EXPECT_OFFER_ID_DOMAIN =
        0x7822b9b863d6a3abbd6eb9a017ed366ed7adb6eec91c16347206a404fdf6849d;

    bytes32 internal constant EXPECT_OWNERSHIP_TYPEHASH =
        0x037dba76c7e82198c99e9916727cd68ba1e6db8e050f5ea9bef8f91586905f9e;
    bytes32 internal constant EXPECT_PAYMENT_TYPEHASH =
        0x8c5c41a9463a7a99719b7b4dfd4b32ca57bafc2358fe8e9a21f18812be37e5d3;
    bytes32 internal constant EXPECT_SPEND_TYPEHASH =
        0xc34007d672b0d728da6a12c630547c9fd1d8af74fb088f4f3a09b519adf12ca5;
    bytes32 internal constant EXPECT_WITHDRAWAL_TYPEHASH =
        0xc8149bc94f0d9ff0c92cc14deac10174f0276f102b672671a56453fd3f998206;

    bytes32 internal constant EXPECT_ROOT_KEY_A = 0xf142d51a92dacd70c4f79867a7652330c57ed62c9f9c98f38777b008bc6e5601;
    bytes32 internal constant EXPECT_ROOT_KEY_B = 0xea21950842034b79a2ca50dd0d73ba727c2e7f89273728ee05fca7c383092d14;
    bytes32 internal constant EXPECT_ROOT_KEY_C = 0x4beae8af638a93a555c906e6a78af425f1b321a5b97d7e59bb6809e5d787436e;

    bytes32 internal constant EXPECT_LEAF_A = 0x7696d13db16d1964bb761601f789333f08c6c6ce4ef2ec5a1719ea73cbc2c3ec;
    bytes32 internal constant EXPECT_LEAF_B = 0x8d14a4b109fc5a82fd98d70fdf5717850e4e8e12278cc519f674317504a5312a;
    bytes32 internal constant EXPECT_LEAF_C = 0xa008072512b4342ec11a353fa10b126c469f70162c4d92220a384f00cc19a015;

    bytes32 internal constant EXPECT_OUTPOINT_HASH = 0x1e910b1b6b7ed6bc6e12a2b6549a3bbb6ceedae0aae41b546200403b7a872526;
    /// @dev `paymentOutputKey` over the SAME (txid, vout) as `EXPECT_OUTPOINT_HASH`. The two must
    ///      differ; see `test_OutpointHashAndPaymentOutputKeyAreDomainSeparated`.
    bytes32 internal constant EXPECT_PAYMENT_KEY_SAME_INPUTS =
        0x04a0bdde41a92402f0c89f98c361a7a7e9c5a308ddfc4e86dcfbde44e4d25c32;
    bytes32 internal constant EXPECT_PAYMENT_OUTPUT_KEY =
        0x63ce9de79ab386e0e5f8b1ee79460f7a2c059b4d1ef0c8cc6b5e10266ccc08cc;

    bytes32 internal constant EXPECT_SCRIPT_HASH = 0xa8dff22a679ccee9973bbcce0bf96a43738f5034bfcf3d27a8f75ee450fe4c8d;

    bytes32 internal constant EXPECT_OFFER_ID = 0x59b74fc7f15158d3fe2af015aa1cd19e16d6d44bc195d2590e45200ef7af39e4;
    bytes32 internal constant EXPECT_OFFER_TERMS_HASH =
        0x8d980d7bc135673fcf6b5f8de2b3029feac6fe51448352999f3d58cc680bdfb8;

    bytes32 internal constant EXPECT_OWNERSHIP_HASH_STRUCT =
        0xb02af5de3a4d7b7536a5fbe847a692c8966ef3560d5c9cd9cb7646c4f219720b;
    bytes32 internal constant EXPECT_PAYMENT_HASH_STRUCT =
        0x8cdccdfbbf7f4dbeb03ae231279a7cceea59a2db60257f029728fd4c28824720;
    bytes32 internal constant EXPECT_SPEND_HASH_STRUCT =
        0x7d3fff25a330d6aaf3de6ee172afaf703947ab560c25eb617943d8d9b2cfeb28;
    bytes32 internal constant EXPECT_WITHDRAWAL_HASH =
        0x8754d512f001b23ba38ec58cd4243c0970f77a1969b279b8065d510b515db1b9;

    uint256 internal constant WITHDRAWAL_AMOUNT = 0.25 ether;
    uint256 internal constant WITHDRAWAL_NONCE = 4;

    /*//////////////////////////////////////////////////////////////
                            DOMAIN CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice `COLLECTION_ID` is the deployment's collection domain separator and must never move.
    function test_CollectionIdGoldenVector() public pure {
        assertEq(PuppetHashing.COLLECTION_ID, EXPECT_COLLECTION_ID, "COLLECTION_ID");
        assertEq(PuppetHashing.COLLECTION_ID, keccak256("BITCOIN_PUPPETS_MAINNET_V1"), "COLLECTION_ID preimage");
    }

    /// @notice Every domain tag is pinned, and all five are mutually distinct.
    /// @dev Distinctness is the property that makes a preimage for one hash family unusable as a
    ///      preimage for another. A copy-paste that duplicated a tag would still produce
    ///      plausible-looking hashes, so it has to be asserted explicitly.
    function test_DomainTagsArePinnedAndDistinct() public pure {
        assertEq(PuppetHashing.OUTPOINT_DOMAIN, EXPECT_OUTPOINT_DOMAIN, "OUTPOINT_DOMAIN");
        assertEq(PuppetHashing.PAYMENT_OUTPUT_DOMAIN, EXPECT_PAYMENT_OUTPUT_DOMAIN, "PAYMENT_OUTPUT_DOMAIN");
        assertEq(PuppetHashing.OFFER_TERMS_DOMAIN, EXPECT_OFFER_TERMS_DOMAIN, "OFFER_TERMS_DOMAIN");
        assertEq(PuppetHashing.OFFER_ID_DOMAIN, EXPECT_OFFER_ID_DOMAIN, "OFFER_ID_DOMAIN");

        bytes32[5] memory tags = [
            PuppetHashing.COLLECTION_ID,
            PuppetHashing.OUTPOINT_DOMAIN,
            PuppetHashing.PAYMENT_OUTPUT_DOMAIN,
            PuppetHashing.OFFER_TERMS_DOMAIN,
            PuppetHashing.OFFER_ID_DOMAIN
        ];
        for (uint256 i = 0; i < tags.length; i++) {
            for (uint256 j = i + 1; j < tags.length; j++) {
                assertTrue(tags[i] != tags[j], "domain tags must be mutually distinct");
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                ROOT KEY
    //////////////////////////////////////////////////////////////*/

    /// @notice Golden `rootKey` values for three fixture inscriptions.
    function test_RootKeyGoldenVectors() public pure {
        assertEq(PuppetHashing.rootKey(TXID_A, INDEX_A), EXPECT_ROOT_KEY_A, "rootKey A");
        assertEq(PuppetHashing.rootKey(TXID_A, INDEX_B), EXPECT_ROOT_KEY_B, "rootKey B");
        assertEq(PuppetHashing.rootKey(TXID_C, INDEX_C), EXPECT_ROOT_KEY_C, "rootKey C");
    }

    /// @notice Two inscriptions revealed by the SAME transaction get different keys.
    /// @dev This is the single most important property of `rootKey`. Bitcoin Puppets reveals can
    ///      carry several inscriptions in one transaction, so a scheme that collapsed
    ///      `(txid, 0)` and `(txid, 1)` into one key would let the first minter of a batch consume
    ///      every sibling inscription's mint. `abi.encode` giving the index its own 32-byte word
    ///      is what prevents it; `abi.encodePacked` would not.
    function test_RootKeyNoCollisionAcrossIndicesOfOneTxid() public pure {
        assertTrue(
            PuppetHashing.rootKey(TXID_A, INDEX_A) != PuppetHashing.rootKey(TXID_A, INDEX_B),
            "same txid, different index must not collide"
        );
    }

    /// @notice The `RootId` overload agrees with the explicit-argument form.
    function test_RootKeyStructOverloadMatches() public pure {
        PuppetTypes.RootId memory root = PuppetTypes.RootId({inscriptionTxid: TXID_C, inscriptionIndex: INDEX_C});
        assertEq(PuppetHashing.rootKey(root), EXPECT_ROOT_KEY_C, "RootId overload");
    }

    /*//////////////////////////////////////////////////////////////
                             COLLECTION LEAF
    //////////////////////////////////////////////////////////////*/

    /// @notice Golden `collectionLeaf` values, and proof the leaf is genuinely double hashed.
    /// @dev A leaf equal to its own rootKey would mean a single hash, which would reopen the
    ///      second-preimage hole the double hash exists to close.
    function test_CollectionLeafGoldenVectors() public pure {
        bytes32 keyA = PuppetHashing.rootKey(TXID_A, INDEX_A);
        assertEq(PuppetHashing.collectionLeaf(keyA), EXPECT_LEAF_A, "leaf A");
        assertEq(PuppetHashing.collectionLeaf(PuppetHashing.rootKey(TXID_A, INDEX_B)), EXPECT_LEAF_B, "leaf B");
        assertEq(PuppetHashing.collectionLeaf(PuppetHashing.rootKey(TXID_C, INDEX_C)), EXPECT_LEAF_C, "leaf C");

        assertTrue(PuppetHashing.collectionLeaf(keyA) != keyA, "leaf must be a second hash of the key");
        assertEq(PuppetHashing.collectionLeaf(keyA), keccak256(abi.encodePacked(keyA)), "leaf preimage is 32 bytes");
    }

    /// @notice The `RootId` leaf overload agrees with the key-based form.
    function test_CollectionLeafStructOverloadMatches() public pure {
        PuppetTypes.RootId memory root = PuppetTypes.RootId({inscriptionTxid: TXID_A, inscriptionIndex: INDEX_A});
        assertEq(PuppetHashing.collectionLeaf(root), EXPECT_LEAF_A, "RootId leaf overload");
    }

    /*//////////////////////////////////////////////////////////////
                        OUTPOINT / PAYMENT OUTPUT
    //////////////////////////////////////////////////////////////*/

    /// @notice Golden `outpointHash` and `paymentOutputKey` values.
    function test_OutpointAndPaymentGoldenVectors() public pure {
        assertEq(PuppetHashing.outpointHash(OUTPOINT_TXID, OUTPOINT_VOUT), EXPECT_OUTPOINT_HASH, "outpointHash");
        assertEq(
            PuppetHashing.paymentOutputKey(PAYMENT_TXID, PAYMENT_VOUT), EXPECT_PAYMENT_OUTPUT_KEY, "paymentOutputKey"
        );
    }

    /// @notice The same `(txid, vout)` hashes to two different values under the two functions.
    /// @dev The separation matters operationally: `outpointHash` labels the UTXO that currently
    ///      holds an inscription, while `paymentOutputKey` is a one-time consumption key for an
    ///      output that paid a seller. If they collided, consuming a seller payment could burn the
    ///      inscription's own outpoint record (or vice versa), and a solver could be reimbursed for
    ///      an output that was never a payment.
    function test_OutpointHashAndPaymentOutputKeyAreDomainSeparated() public pure {
        bytes32 outpoint = PuppetHashing.outpointHash(OUTPOINT_TXID, OUTPOINT_VOUT);
        bytes32 payment = PuppetHashing.paymentOutputKey(OUTPOINT_TXID, OUTPOINT_VOUT);

        assertEq(outpoint, EXPECT_OUTPOINT_HASH, "outpointHash(x,y)");
        assertEq(payment, EXPECT_PAYMENT_KEY_SAME_INPUTS, "paymentOutputKey(x,y)");
        assertTrue(outpoint != payment, "outpointHash(x,y) must never equal paymentOutputKey(x,y)");
    }

    /// @notice Distinct vouts on one txid produce distinct keys in both families.
    function test_VoutIsBoundIntoBothKeys() public pure {
        assertTrue(
            PuppetHashing.outpointHash(OUTPOINT_TXID, 0) != PuppetHashing.outpointHash(OUTPOINT_TXID, 1),
            "outpoint vout binding"
        );
        assertTrue(
            PuppetHashing.paymentOutputKey(PAYMENT_TXID, 0) != PuppetHashing.paymentOutputKey(PAYMENT_TXID, 1),
            "payment vout binding"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              SCRIPT HASH
    //////////////////////////////////////////////////////////////*/

    /// @notice Golden `scriptHash` over a real-shaped P2TR scriptPubKey.
    /// @dev Asserts the fixture's shape too. A vector built over a malformed script would still
    ///      produce a stable hash, and would then teach the SDK the wrong script encoding.
    function test_ScriptHashP2TRGoldenVector() public pure {
        assertEq(P2TR_SCRIPT_PUBKEY.length, 34, "P2TR scriptPubKey is 34 bytes");
        assertEq(uint8(P2TR_SCRIPT_PUBKEY[0]), 0x51, "OP_1 witness version");
        assertEq(uint8(P2TR_SCRIPT_PUBKEY[1]), 0x20, "PUSH32");
        assertEq(PuppetHashing.scriptHash(P2TR_SCRIPT_PUBKEY), EXPECT_SCRIPT_HASH, "scriptHash");
        assertEq(PuppetHashing.scriptHash(P2TR_SCRIPT_PUBKEY), keccak256(P2TR_SCRIPT_PUBKEY), "raw keccak of script");
    }

    /*//////////////////////////////////////////////////////////////
                                 OFFERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Golden `offerId`, plus proof that every bound field actually changes the id.
    /// @dev Ids are bound to chain, escrow and buyer so a replay across deployments — or across a
    ///      testnet and mainnet escrow — cannot reuse an id.
    function test_OfferIdGoldenVectorAndBinding() public pure {
        assertEq(PuppetHashing.offerId(CHAIN_ID, ESCROW, BUYER, BUYER_NONCE), EXPECT_OFFER_ID, "offerId");

        bytes32 base = EXPECT_OFFER_ID;
        assertTrue(PuppetHashing.offerId(CHAIN_ID + 1, ESCROW, BUYER, BUYER_NONCE) != base, "chainId bound");
        assertTrue(PuppetHashing.offerId(CHAIN_ID, RECIPIENT, BUYER, BUYER_NONCE) != base, "escrow bound");
        assertTrue(PuppetHashing.offerId(CHAIN_ID, ESCROW, RECIPIENT, BUYER_NONCE) != base, "buyer bound");
        assertTrue(PuppetHashing.offerId(CHAIN_ID, ESCROW, BUYER, BUYER_NONCE + 1) != base, "nonce bound");
    }

    /// @notice Golden `offerTermsHash`, plus proof a price change invalidates the commitment.
    /// @dev The Bitcoin controller signs this hash inside the BIP-322 message. If `grossWei` could
    ///      move without changing the hash, a buyer could get a signature for one price and settle
    ///      at another.
    function test_OfferTermsHashGoldenVectorAndBinding() public pure {
        assertEq(offerTermsFixture(), EXPECT_OFFER_TERMS_HASH, "offerTermsHash");

        bytes32 repriced = PuppetHashing.offerTermsHash(
            CHAIN_ID,
            ESCROW,
            EXPECT_OFFER_ID,
            uint8(PuppetTypes.OfferKind.PAID_EVM),
            EXPECT_ROOT_KEY_A,
            BUYER,
            RECIPIENT,
            GROSS_WEI + 1,
            SELLER_WEI,
            SELLER_SATS,
            EXPIRY
        );
        assertTrue(repriced != EXPECT_OFFER_TERMS_HASH, "grossWei must be bound into the terms hash");
    }

    /*//////////////////////////////////////////////////////////////
                        EIP-712 TYPES AND TYPEHASHES
    //////////////////////////////////////////////////////////////*/

    /// @notice The exact EIP-712 type strings, character for character.
    /// @dev Pinned as literals rather than reconstructed, because a reconstruction would share any
    ///      mistake with the library. These strings are what the SDK must emit verbatim.
    function test_TypeStringsAreExact() public pure {
        assertEq(
            PuppetHashing.OWNERSHIP_ATTESTATION_TYPE,
            "OwnershipAttestation(uint8 purpose,bytes32 rootTxid,uint32 rootIndex,bytes32 contextId,"
            "bytes32 offerTermsHash,bytes32 currentOutpointHash,bytes32 ownerScriptHash,bytes32 bip322ProofHash,"
            "address buyer,address recipient,uint8 payoutMode,address evmPayout,bytes32 btcPayoutScriptHash,"
            "uint64 sellerSats,uint256 grossWei,uint256 sellerWei,bytes32 bitcoinBlockHash,uint64 bitcoinHeight,"
            "bytes32 authorizationId,uint64 deadline,uint64 attestorEpoch,uint32 policyVersion)",
            "OwnershipAttestation type string"
        );
        assertEq(
            PuppetHashing.BITCOIN_PAYMENT_ATTESTATION_TYPE,
            "BitcoinPaymentAttestation(bytes32 contextId,bytes32 ownershipDigest,address solver,bytes32 bitcoinTxid,"
            "uint32 outputIndex,bytes32 recipientScriptHash,uint64 amountSats,bytes32 bitcoinBlockHash,"
            "uint64 bitcoinHeight,bytes32 authorizationId,uint64 deadline,uint64 attestorEpoch,uint32 policyVersion)",
            "BitcoinPaymentAttestation type string"
        );
        assertEq(
            PuppetHashing.ROOT_SPEND_ATTESTATION_TYPE,
            "RootSpendAttestation(bytes32 rootTxid,uint32 rootIndex,bytes32 previousOutpointHash,bytes32 spendingTxid,"
            "bytes32 bitcoinBlockHash,uint64 bitcoinHeight,bytes32 authorizationId,uint64 deadline,"
            "uint64 attestorEpoch,uint32 policyVersion)",
            "RootSpendAttestation type string"
        );
        assertEq(
            PuppetHashing.WITHDRAWAL_TYPE,
            "Withdrawal(address beneficiary,address recipient,uint256 amount,uint256 nonce,uint64 deadline)",
            "Withdrawal type string"
        );
    }

    /// @notice All four typehashes are pinned and mutually distinct.
    function test_TypeHashesAreStable() public pure {
        assertEq(PuppetHashing.OWNERSHIP_ATTESTATION_TYPEHASH, EXPECT_OWNERSHIP_TYPEHASH, "ownership typehash");
        assertEq(PuppetHashing.BITCOIN_PAYMENT_ATTESTATION_TYPEHASH, EXPECT_PAYMENT_TYPEHASH, "payment typehash");
        assertEq(PuppetHashing.ROOT_SPEND_ATTESTATION_TYPEHASH, EXPECT_SPEND_TYPEHASH, "spend typehash");
        assertEq(PuppetHashing.WITHDRAWAL_TYPEHASH, EXPECT_WITHDRAWAL_TYPEHASH, "withdrawal typehash");

        assertTrue(EXPECT_OWNERSHIP_TYPEHASH != EXPECT_PAYMENT_TYPEHASH, "ownership vs payment");
        assertTrue(EXPECT_OWNERSHIP_TYPEHASH != EXPECT_SPEND_TYPEHASH, "ownership vs spend");
        assertTrue(EXPECT_OWNERSHIP_TYPEHASH != EXPECT_WITHDRAWAL_TYPEHASH, "ownership vs withdrawal");
        assertTrue(EXPECT_PAYMENT_TYPEHASH != EXPECT_SPEND_TYPEHASH, "payment vs spend");
        assertTrue(EXPECT_PAYMENT_TYPEHASH != EXPECT_WITHDRAWAL_TYPEHASH, "payment vs withdrawal");
        assertTrue(EXPECT_SPEND_TYPEHASH != EXPECT_WITHDRAWAL_TYPEHASH, "spend vs withdrawal");
    }

    /// @notice Each typehash really is keccak256 of its own type string.
    function test_TypeHashesMatchTheirTypeStrings() public pure {
        assertEq(
            PuppetHashing.OWNERSHIP_ATTESTATION_TYPEHASH,
            keccak256(bytes(PuppetHashing.OWNERSHIP_ATTESTATION_TYPE)),
            "ownership"
        );
        assertEq(
            PuppetHashing.BITCOIN_PAYMENT_ATTESTATION_TYPEHASH,
            keccak256(bytes(PuppetHashing.BITCOIN_PAYMENT_ATTESTATION_TYPE)),
            "payment"
        );
        assertEq(
            PuppetHashing.ROOT_SPEND_ATTESTATION_TYPEHASH,
            keccak256(bytes(PuppetHashing.ROOT_SPEND_ATTESTATION_TYPE)),
            "spend"
        );
        assertEq(PuppetHashing.WITHDRAWAL_TYPEHASH, keccak256(bytes(PuppetHashing.WITHDRAWAL_TYPE)), "withdrawal");
    }

    /*//////////////////////////////////////////////////////////////
                            STRUCT HASHING
    //////////////////////////////////////////////////////////////*/

    /// @notice Golden `hashStruct` for one fully-populated instance of each attestation.
    function test_HashStructGoldenVectors() public pure {
        assertEq(PuppetHashing.hashStruct(ownershipFixture()), EXPECT_OWNERSHIP_HASH_STRUCT, "ownership hashStruct");
        assertEq(PuppetHashing.hashStruct(paymentFixture()), EXPECT_PAYMENT_HASH_STRUCT, "payment hashStruct");
        assertEq(PuppetHashing.hashStruct(spendFixture()), EXPECT_SPEND_HASH_STRUCT, "spend hashStruct");
    }

    /// @notice Golden `hashWithdrawal` for the gasless PayoutVault authorization.
    function test_HashWithdrawalGoldenVector() public pure {
        assertEq(
            PuppetHashing.hashWithdrawal(VAULT_BENEFICIARY, RECIPIENT, WITHDRAWAL_AMOUNT, WITHDRAWAL_NONCE, DEADLINE),
            EXPECT_WITHDRAWAL_HASH,
            "hashWithdrawal"
        );
    }

    /// @notice The two-chunk `bytes.concat` encoding is byte-identical to one `abi.encode`.
    /// @dev This is the claim `PuppetHashing`'s header makes, and the SDK relies on it: TypeScript
    ///      encodes all 23 words in a single pass and must land on the same digest.
    ///
    ///      The single-pass reference is `abi.encode(TYPEHASH, attestation)`. Every field of the
    ///      attestation structs is a value type, so each struct is an ABI *static* tuple and is
    ///      encoded inline, one 32-byte word per field, with no head/tail offset. That makes it
    ///      exactly the flat field-by-field encoding — and it sidesteps the stack-too-deep error
    ///      that listing 23 arguments would hit, which is the very reason the library chunks.
    function test_ChunkedEncodingEqualsSingleAbiEncode() public pure {
        PuppetTypes.OwnershipAttestation memory o = ownershipFixture();
        bytes memory flatOwnership = abi.encode(PuppetHashing.OWNERSHIP_ATTESTATION_TYPEHASH, o);
        assertEq(flatOwnership.length, 32 * 23, "ownership encodeData is 23 words");
        assertEq(keccak256(flatOwnership), PuppetHashing.hashStruct(o), "ownership chunking is transparent");

        PuppetTypes.BitcoinPaymentAttestation memory p = paymentFixture();
        bytes memory flatPayment = abi.encode(PuppetHashing.BITCOIN_PAYMENT_ATTESTATION_TYPEHASH, p);
        assertEq(flatPayment.length, 32 * 14, "payment encodeData is 14 words");
        assertEq(keccak256(flatPayment), PuppetHashing.hashStruct(p), "payment chunking is transparent");

        PuppetTypes.RootSpendAttestation memory s = spendFixture();
        bytes memory flatSpend = abi.encode(PuppetHashing.ROOT_SPEND_ATTESTATION_TYPEHASH, s);
        assertEq(flatSpend.length, 32 * 11, "spend encodeData is 11 words");
        assertEq(keccak256(flatSpend), PuppetHashing.hashStruct(s), "spend encoding is flat");
    }

    /// @notice Reordering two fields of equal ABI width changes the digest.
    /// @dev Field order defines the EIP-712 type string, so a silent reorder would produce
    ///      signatures that verify against a different meaning. `buyer` and `recipient` are the
    ///      dangerous pair: swapping them redirects the minted HoodPup.
    function test_FieldOrderIsLoadBearing() public pure {
        PuppetTypes.OwnershipAttestation memory a = ownershipFixture();
        // A fresh fixture, not `= a`: assigning one memory struct to another copies the reference,
        // so mutating the "copy" would mutate the original and the assertion would be vacuous.
        PuppetTypes.OwnershipAttestation memory swapped = ownershipFixture();
        swapped.buyer = a.recipient;
        swapped.recipient = a.buyer;
        assertTrue(
            PuppetHashing.hashStruct(swapped) != PuppetHashing.hashStruct(a), "buyer/recipient swap must change digest"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 FUZZ
    //////////////////////////////////////////////////////////////*/

    /// @notice `rootKey` is injective over `(txid, index)`.
    /// @dev Injectivity is the assumption every downstream uniqueness check inherits: "one Root
    ///      mints at most one HoodPup" is enforced on the key, not on the inscription, so two
    ///      distinct inscriptions sharing a key would break the protocol's central rule.
    /// @param txidA First reveal txid.
    /// @param indexA First inscription index.
    /// @param txidB Second reveal txid.
    /// @param indexB Second inscription index.
    function testFuzz_RootKeyIsInjective(bytes32 txidA, uint32 indexA, bytes32 txidB, uint32 indexB) public pure {
        vm.assume(txidA != txidB || indexA != indexB);
        assertTrue(PuppetHashing.rootKey(txidA, indexA) != PuppetHashing.rootKey(txidB, indexB), "rootKey collision");
    }

    /// @notice `rootKey` is deterministic and matches the `RootId` overload for any input.
    /// @param txid Reveal txid.
    /// @param index Inscription index.
    function testFuzz_RootKeyOverloadsAgree(bytes32 txid, uint32 index) public pure {
        PuppetTypes.RootId memory root = PuppetTypes.RootId({inscriptionTxid: txid, inscriptionIndex: index});
        assertEq(PuppetHashing.rootKey(root), PuppetHashing.rootKey(txid, index), "overload disagreement");
    }

    /// @notice The outpoint and payment-output families never collide, for any input.
    /// @param txid Bitcoin txid.
    /// @param vout Output index.
    function testFuzz_OutpointNeverCollidesWithPaymentOutput(bytes32 txid, uint32 vout) public pure {
        assertTrue(
            PuppetHashing.outpointHash(txid, vout) != PuppetHashing.paymentOutputKey(txid, vout), "domain collision"
        );
    }

    /// @notice `collectionLeaf` is injective over root keys.
    /// @param keyA First root key.
    /// @param keyB Second root key.
    function testFuzz_CollectionLeafIsInjective(bytes32 keyA, bytes32 keyB) public pure {
        vm.assume(keyA != keyB);
        assertTrue(PuppetHashing.collectionLeaf(keyA) != PuppetHashing.collectionLeaf(keyB), "leaf collision");
    }
}

/// @title MerkleFixtureTest
/// @notice Self-check for the shared sorted-pair Merkle builder.
/// @dev Lives in this file because the parallel build assigns file ownership, and this suite owns
///      `test/unit/PuppetHashing.t.sol`. Nine other suites import `MerkleFixture`, so shipping it
///      unverified would push a silent failure into all of them.
contract MerkleFixtureTest is PuppetHashingFixtures {
    bytes32 internal constant EXPECT_FIXTURE_MANIFEST_ROOT =
        0x1e282e09423b7326356d49b1f17876a6e35711b1a753877d6d2dac4007848281;
    bytes32 internal constant EXPECT_LEAF_B_NODE = 0x8d14a4b109fc5a82fd98d70fdf5717850e4e8e12278cc519f674317504a5312a;
    bytes32 internal constant EXPECT_LEAF_C_NODE = 0xa008072512b4342ec11a353fa10b126c469f70162c4d92220a384f00cc19a015;

    /// @notice A one-leaf tree has the leaf as its root and an empty proof.
    function test_SingleLeafTree() public pure {
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = PuppetHashing.collectionLeaf(PuppetHashing.rootKey(TXID_A, INDEX_A));

        assertEq(MerkleFixture.build(leaves), leaves[0], "single-leaf root is the leaf");
        assertEq(MerkleFixture.proof(leaves, 0).length, 0, "single-leaf proof is empty");
        assertTrue(MerkleProof.verify(MerkleFixture.proof(leaves, 0), leaves[0], leaves[0]), "verifies");
    }

    /// @notice Every member of an odd-sized tree verifies, exercising the promotion branch.
    /// @dev Five leaves gives levels of 5 -> 3 -> 2 -> 1, so promotion happens twice at different
    ///      depths. That is where a naive "duplicate the last node" builder diverges from
    ///      OpenZeppelin's verifier.
    function test_OddSizedTreeAllMembersVerify() public pure {
        bytes32[] memory leaves = _leaves(5);
        bytes32 root = MerkleFixture.build(leaves);
        for (uint256 i = 0; i < leaves.length; i++) {
            assertTrue(MerkleProof.verify(MerkleFixture.proof(leaves, i), root, leaves[i]), "member verifies");
        }
    }

    /// @notice Every member of an even-sized tree verifies.
    function test_EvenSizedTreeAllMembersVerify() public pure {
        bytes32[] memory leaves = _leaves(8);
        bytes32 root = MerkleFixture.build(leaves);
        for (uint256 i = 0; i < leaves.length; i++) {
            assertTrue(MerkleProof.verify(MerkleFixture.proof(leaves, i), root, leaves[i]), "member verifies");
        }
    }

    /// @notice A non-member cannot be proven with any member's proof.
    function test_NonMemberDoesNotVerify() public pure {
        bytes32[] memory leaves = _leaves(6);
        bytes32 root = MerkleFixture.build(leaves);
        bytes32 outsider = PuppetHashing.collectionLeaf(PuppetHashing.rootKey(TXID_C, 999));
        assertFalse(MerkleProof.verify(MerkleFixture.proof(leaves, 0), root, outsider), "non-member must not verify");
    }

    /// @notice The root depends only on the SET of leaves, not on the caller's ordering.
    /// @dev This is what lets the Solidity fixture, the TypeScript builder and the manifest file
    ///      disagree about ordering and still commit to the same root.
    function test_RootIsOrderIndependent() public pure {
        bytes32[] memory ascending = _leaves(7);
        bytes32[] memory reversed = new bytes32[](ascending.length);
        for (uint256 i = 0; i < ascending.length; i++) {
            reversed[i] = ascending[ascending.length - 1 - i];
        }
        assertEq(MerkleFixture.build(ascending), MerkleFixture.build(reversed), "root must be order independent");
    }

    /// @notice Duplicate leaves are rejected rather than silently producing an ambiguous proof.
    function test_DuplicateLeafReverts() public {
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = PuppetHashing.collectionLeaf(PuppetHashing.rootKey(TXID_A, INDEX_A));
        leaves[1] = leaves[0];
        vm.expectRevert(abi.encodeWithSelector(MerkleFixture.DuplicateLeaf.selector, leaves[0]));
        this.buildExternal(leaves);
    }

    /// @notice An empty leaf set is rejected; an empty tree has no meaningful root.
    function test_EmptyLeavesReverts() public {
        bytes32[] memory leaves = new bytes32[](0);
        vm.expectRevert(MerkleFixture.EmptyLeaves.selector);
        this.buildExternal(leaves);
    }

    /// @notice The `RootId` convenience builder agrees with the raw-leaf builder.
    function test_RootIdBuilderMatchesLeafBuilder() public pure {
        PuppetTypes.RootId[] memory roots = new PuppetTypes.RootId[](3);
        roots[0] = PuppetTypes.RootId({inscriptionTxid: TXID_A, inscriptionIndex: INDEX_A});
        roots[1] = PuppetTypes.RootId({inscriptionTxid: TXID_A, inscriptionIndex: INDEX_B});
        roots[2] = PuppetTypes.RootId({inscriptionTxid: TXID_C, inscriptionIndex: INDEX_C});

        bytes32 root = MerkleFixture.buildFromRoots(roots);
        for (uint256 i = 0; i < roots.length; i++) {
            bytes32 leaf = PuppetHashing.collectionLeaf(roots[i]);
            assertTrue(MerkleProof.verify(MerkleFixture.proofFromRoots(roots, i), root, leaf), "root member verifies");
        }
    }

    /// @notice Fuzzed trees of any size in `[1, 16]` verify every member.
    /// @param size Number of leaves, bounded into a practical fixture range.
    /// @param salt Varies the leaf values so the shape of the tree is not fixed.
    function testFuzz_AllMembersVerify(uint8 size, bytes32 salt) public pure {
        uint256 n = uint256(size) % 16 + 1;
        bytes32[] memory leaves = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            leaves[i] = PuppetHashing.collectionLeaf(keccak256(abi.encode(salt, i)));
        }
        bytes32 root = MerkleFixture.build(leaves);
        for (uint256 i = 0; i < n; i++) {
            assertTrue(MerkleProof.verify(MerkleFixture.proof(leaves, i), root, leaves[i]), "member verifies");
        }
    }

    /// @notice Golden root and proof for the three-inscription fixture manifest.
    /// @dev Pinned so the TypeScript builder in `packages/protocol-sdk` can be validated against
    ///      an independently observed value rather than against its own output. Three leaves also
    ///      exercises promotion: the level is [A, B, C], folds to [hashPair(A,B), C], and C rides
    ///      up unchanged.
    function test_FixtureManifestGoldenRootAndProof() public pure {
        PuppetTypes.RootId[] memory roots = new PuppetTypes.RootId[](3);
        roots[0] = PuppetTypes.RootId({inscriptionTxid: TXID_A, inscriptionIndex: INDEX_A});
        roots[1] = PuppetTypes.RootId({inscriptionTxid: TXID_A, inscriptionIndex: INDEX_B});
        roots[2] = PuppetTypes.RootId({inscriptionTxid: TXID_C, inscriptionIndex: INDEX_C});

        assertEq(MerkleFixture.buildFromRoots(roots), EXPECT_FIXTURE_MANIFEST_ROOT, "fixture manifest root");

        bytes32[] memory proof = MerkleFixture.proofFromRoots(roots, 0);
        assertEq(proof.length, 2, "proof length");
        assertEq(proof[0], EXPECT_LEAF_B_NODE, "sibling at leaf level");
        assertEq(proof[1], EXPECT_LEAF_C_NODE, "promoted sibling at level one");
        assertTrue(
            MerkleProof.verify(proof, EXPECT_FIXTURE_MANIFEST_ROOT, PuppetHashing.collectionLeaf(roots[0])),
            "golden proof verifies under OpenZeppelin"
        );
    }

    /// @notice External wrapper so `vm.expectRevert` can target a library call.
    /// @param leaves Leaves to build over.
    /// @return root The Merkle root.
    function buildExternal(bytes32[] memory leaves) external pure returns (bytes32 root) {
        return MerkleFixture.build(leaves);
    }

    function _leaves(uint256 n) private pure returns (bytes32[] memory leaves) {
        leaves = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            leaves[i] = PuppetHashing.collectionLeaf(PuppetHashing.rootKey(TXID_C, uint32(i + 1)));
        }
    }
}

/// @title AttestorSetTest
/// @notice Self-check for the shared quorum-signing helper.
/// @dev Also lives here for file-ownership reasons. If `AttestorSet` emitted signatures in the
///      wrong order, every oracle suite would fail for a reason that has nothing to do with the
///      oracle, so its ordering guarantee is verified independently here.
contract AttestorSetTest is Test {
    AttestorSet internal attestors;

    bytes32 internal constant DIGEST = keccak256("HOODPUPS_ATTESTOR_SET_SELFTEST_DIGEST");

    function setUp() public {
        attestors = new AttestorSet(5, keccak256("HOODPUPS_ATTESTOR_SET_SELFTEST_SEED"));
    }

    /// @notice The set is the expected size and holds five distinct, non-zero addresses.
    function test_SetShape() public view {
        address[] memory addrs = attestors.addresses();
        assertEq(addrs.length, 5, "five attestors");
        for (uint256 i = 0; i < addrs.length; i++) {
            assertTrue(addrs[i] != address(0), "non-zero");
            for (uint256 j = i + 1; j < addrs.length; j++) {
                assertTrue(addrs[i] != addrs[j], "distinct");
            }
        }
        assertTrue(attestors.outsider() != address(0), "outsider exists");
    }

    /// @notice `sortedAddresses` is strictly ascending and preserves the membership set.
    function test_SortedAddressesAreStrictlyAscending() public view {
        address[] memory sorted = attestors.sortedAddresses();
        assertEq(sorted.length, 5, "same size");
        for (uint256 i = 1; i < sorted.length; i++) {
            assertTrue(sorted[i] > sorted[i - 1], "strictly ascending");
        }
    }

    /// @notice `sign(digest, n)` recovers to strictly ascending signers.
    /// @dev The recovered addresses are what the oracle compares, so this test recovers rather than
    ///      inspecting the signature bytes.
    function test_SignProducesAscendingRecoveredSigners() public view {
        bytes[] memory sigs = attestors.sign(DIGEST, 3);
        assertEq(sigs.length, 3, "three signatures");
        address previous = address(0);
        for (uint256 i = 0; i < sigs.length; i++) {
            address signer = _recover(DIGEST, sigs[i]);
            assertTrue(signer > previous, "strictly ascending recovered signers");
            previous = signer;
        }
    }

    /// @notice Compact EIP-2098 signatures recover to the same ascending signers.
    function test_SignCompactRecoversIdentically() public view {
        bytes[] memory full = attestors.sign(DIGEST, 3);
        bytes[] memory compact = attestors.signCompact(DIGEST, 3);
        assertEq(compact.length, 3, "three signatures");
        for (uint256 i = 0; i < compact.length; i++) {
            assertEq(compact[i].length, 64, "compact signatures are 64 bytes");
            assertEq(_recoverCompact(DIGEST, compact[i]), _recover(DIGEST, full[i]), "same signer");
        }
    }

    /// @notice `signWith` honours a hand-picked subset and still sorts it.
    function test_SignWithSubsetIsSorted() public view {
        uint256[] memory indices = new uint256[](3);
        indices[0] = 4;
        indices[1] = 0;
        indices[2] = 2;
        bytes[] memory sigs = attestors.signWith(DIGEST, indices);

        address previous = address(0);
        for (uint256 i = 0; i < sigs.length; i++) {
            address signer = _recover(DIGEST, sigs[i]);
            assertTrue(signer > previous, "strictly ascending");
            previous = signer;
        }
    }

    /// @notice `signUnsorted` really is descending, so the negative case is genuinely negative.
    function test_SignUnsortedIsDescending() public view {
        bytes[] memory sigs = attestors.signUnsorted(DIGEST, 3);
        for (uint256 i = 1; i < sigs.length; i++) {
            assertTrue(_recover(DIGEST, sigs[i]) < _recover(DIGEST, sigs[i - 1]), "descending");
        }
    }

    /// @notice `signWithDuplicate` yields an adjacent equal pair, not a merely unsorted array.
    function test_SignWithDuplicateHasAdjacentEqualSigners() public view {
        bytes[] memory sigs = attestors.signWithDuplicate(DIGEST, 3, 1);
        assertEq(sigs.length, 3, "three signatures");

        address[] memory signers = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            signers[i] = _recover(DIGEST, sigs[i]);
        }
        assertTrue(signers[0] <= signers[1] && signers[1] <= signers[2], "non-decreasing");
        assertTrue(signers[1] == signers[2], "duplicate is adjacent");
    }

    /// @notice The outsider signature recovers to an address outside the set.
    function test_OutsiderIsNotAnAttestor() public view {
        address recovered = _recover(DIGEST, attestors.signAsOutsider(DIGEST));
        assertEq(recovered, attestors.outsider(), "recovers to the outsider");

        address[] memory addrs = attestors.addresses();
        for (uint256 i = 0; i < addrs.length; i++) {
            assertTrue(addrs[i] != recovered, "outsider is not in the set");
        }
    }

    /// @notice `signWithOutsider` stays correctly ordered while smuggling in a non-attestor.
    function test_SignWithOutsiderIsOrderedButContainsANonMember() public view {
        bytes[] memory sigs = attestors.signWithOutsider(DIGEST, 2);
        assertEq(sigs.length, 3, "two attestors plus the outsider");

        address previous = address(0);
        bool sawOutsider = false;
        for (uint256 i = 0; i < sigs.length; i++) {
            address signer = _recover(DIGEST, sigs[i]);
            assertTrue(signer > previous, "strictly ascending");
            previous = signer;
            if (signer == attestors.outsider()) sawOutsider = true;
        }
        assertTrue(sawOutsider, "the outsider must actually be present");
    }

    /// @notice The same seed reproduces the same addresses, which keeps fixtures deterministic.
    function test_DerivationIsDeterministic() public {
        AttestorSet twin = new AttestorSet(5, keccak256("HOODPUPS_ATTESTOR_SET_SELFTEST_SEED"));
        address[] memory a = attestors.addresses();
        address[] memory b = twin.addresses();
        for (uint256 i = 0; i < a.length; i++) {
            assertEq(a[i], b[i], "deterministic derivation");
        }
    }

    function _recover(bytes32 digest, bytes memory signature) private pure returns (address) {
        require(signature.length == 65, "bad length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly ("memory-safe") {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        return ecrecover(digest, v, r, s);
    }

    function _recoverCompact(bytes32 digest, bytes memory signature) private pure returns (address) {
        require(signature.length == 64, "bad length");
        bytes32 r;
        bytes32 vs;
        assembly ("memory-safe") {
            r := mload(add(signature, 0x20))
            vs := mload(add(signature, 0x40))
        }
        bytes32 s = vs & bytes32(uint256(type(uint256).max >> 1));
        uint8 v = uint8((uint256(vs) >> 255) + 27);
        return ecrecover(digest, v, r, s);
    }
}
