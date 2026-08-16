// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";

import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";

contract PuppetHashingProbe is Test {
    bytes32 internal constant TXID_A = 0x1f9f8a6d2c4b7e0135a9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7;
    bytes32 internal constant TXID_C = 0xa3c5e7091b2d4f6880a1c3e5d7f9b0a2c4e6f8091a3b5c7d9e0f1a2b3c4d5e6f;
    bytes32 internal constant OUTPOINT_TXID = 0x7c1d3f5a9b2e46081a3c5e7092b4d6f80e2a4c6e8103957bd5f7192b3d4f6a8c;
    bytes32 internal constant PAYMENT_TXID = 0x3e5a7c9e0b2d4f6183a5c7e9012b3d5f7a9c1e3f5b7d90124a6c8e0b2d4f6183;
    bytes32 internal constant SPEND_TXID = 0xb4d6f8092a4c6e801b3d5f7991a3c5e7092b4d6f81a3c5e79b0d2f4a6c8e0193;
    bytes32 internal constant BLOCK_HASH = 0x0000000000000000000159f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5;

    bytes internal constant P2TR = hex"5120a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2";

    uint256 internal constant CHAIN_ID = 31337;
    address internal constant ESCROW = 0x1111111111111111111111111111111111111111;
    address internal constant BUYER = 0x2222222222222222222222222222222222222222;
    address internal constant RECIPIENT = 0x3333333333333333333333333333333333333333;
    address internal constant EVM_PAYOUT = 0x4444444444444444444444444444444444444444;
    address internal constant SOLVER = 0x5555555555555555555555555555555555555555;
    address internal constant VAULT_BENEFICIARY = 0x6666666666666666666666666666666666666666;

    function test_Probe() public pure {
        console2.log("COLLECTION_ID");
        console2.logBytes32(PuppetHashing.COLLECTION_ID);
        console2.log("OUTPOINT_DOMAIN");
        console2.logBytes32(PuppetHashing.OUTPOINT_DOMAIN);
        console2.log("PAYMENT_OUTPUT_DOMAIN");
        console2.logBytes32(PuppetHashing.PAYMENT_OUTPUT_DOMAIN);
        console2.log("OFFER_TERMS_DOMAIN");
        console2.logBytes32(PuppetHashing.OFFER_TERMS_DOMAIN);
        console2.log("OFFER_ID_DOMAIN");
        console2.logBytes32(PuppetHashing.OFFER_ID_DOMAIN);

        console2.log("OWNERSHIP_TYPEHASH");
        console2.logBytes32(PuppetHashing.OWNERSHIP_ATTESTATION_TYPEHASH);
        console2.log("PAYMENT_TYPEHASH");
        console2.logBytes32(PuppetHashing.BITCOIN_PAYMENT_ATTESTATION_TYPEHASH);
        console2.log("SPEND_TYPEHASH");
        console2.logBytes32(PuppetHashing.ROOT_SPEND_ATTESTATION_TYPEHASH);
        console2.log("WITHDRAWAL_TYPEHASH");
        console2.logBytes32(PuppetHashing.WITHDRAWAL_TYPEHASH);

        console2.log("TYPE_OWNERSHIP");
        console2.log(PuppetHashing.OWNERSHIP_ATTESTATION_TYPE);
        console2.log("TYPE_PAYMENT");
        console2.log(PuppetHashing.BITCOIN_PAYMENT_ATTESTATION_TYPE);
        console2.log("TYPE_SPEND");
        console2.log(PuppetHashing.ROOT_SPEND_ATTESTATION_TYPE);
        console2.log("TYPE_WITHDRAWAL");
        console2.log(PuppetHashing.WITHDRAWAL_TYPE);

        bytes32 keyA = PuppetHashing.rootKey(TXID_A, 0);
        bytes32 keyB = PuppetHashing.rootKey(TXID_A, 1);
        bytes32 keyC = PuppetHashing.rootKey(TXID_C, 7);
        console2.log("ROOT_KEY_A");
        console2.logBytes32(keyA);
        console2.log("ROOT_KEY_B");
        console2.logBytes32(keyB);
        console2.log("ROOT_KEY_C");
        console2.logBytes32(keyC);

        console2.log("LEAF_A");
        console2.logBytes32(PuppetHashing.collectionLeaf(keyA));
        console2.log("LEAF_B");
        console2.logBytes32(PuppetHashing.collectionLeaf(keyB));
        console2.log("LEAF_C");
        console2.logBytes32(PuppetHashing.collectionLeaf(keyC));

        console2.log("OUTPOINT_HASH");
        console2.logBytes32(PuppetHashing.outpointHash(OUTPOINT_TXID, 2));
        console2.log("PAYMENT_OUTPUT_KEY_SAME_INPUTS");
        console2.logBytes32(PuppetHashing.paymentOutputKey(OUTPOINT_TXID, 2));
        console2.log("PAYMENT_OUTPUT_KEY");
        console2.logBytes32(PuppetHashing.paymentOutputKey(PAYMENT_TXID, 1));
        console2.log("SCRIPT_HASH");
        console2.logBytes32(PuppetHashing.scriptHash(P2TR));

        bytes32 id = PuppetHashing.offerId(CHAIN_ID, ESCROW, BUYER, 3);
        console2.log("OFFER_ID");
        console2.logBytes32(id);

        bytes32 terms = PuppetHashing.offerTermsHash(
            CHAIN_ID, ESCROW, id, 0, keyA, BUYER, RECIPIENT, 1 ether, 0.5 ether, 250_000, 1_893_456_000
        );
        console2.log("OFFER_TERMS_HASH");
        console2.logBytes32(terms);

        console2.log("OWNERSHIP_HASH_STRUCT");
        console2.logBytes32(PuppetHashing.hashStruct(_ownership(id, terms)));
        console2.log("PAYMENT_HASH_STRUCT");
        console2.logBytes32(PuppetHashing.hashStruct(_payment(id)));
        console2.log("SPEND_HASH_STRUCT");
        console2.logBytes32(PuppetHashing.hashStruct(_spend()));

        console2.log("WITHDRAWAL_HASH");
        console2.logBytes32(
            PuppetHashing.hashWithdrawal(VAULT_BENEFICIARY, RECIPIENT, 0.25 ether, 4, 1_893_456_000)
        );
    }

    function _ownership(bytes32 id, bytes32 terms)
        internal
        pure
        returns (PuppetTypes.OwnershipAttestation memory a)
    {
        a = PuppetTypes.OwnershipAttestation({
            purpose: uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT),
            rootTxid: TXID_A,
            rootIndex: 0,
            contextId: id,
            offerTermsHash: terms,
            currentOutpointHash: PuppetHashing.outpointHash(OUTPOINT_TXID, 2),
            ownerScriptHash: PuppetHashing.scriptHash(P2TR),
            bip322ProofHash: keccak256("HOODPUPS_FIXTURE_BIP322_PROOF"),
            buyer: BUYER,
            recipient: RECIPIENT,
            payoutMode: uint8(PuppetTypes.PayoutMode.EVM),
            evmPayout: EVM_PAYOUT,
            btcPayoutScriptHash: keccak256("HOODPUPS_FIXTURE_BTC_PAYOUT_SCRIPT"),
            sellerSats: 250_000,
            grossWei: 1 ether,
            sellerWei: 0.5 ether,
            bitcoinBlockHash: BLOCK_HASH,
            bitcoinHeight: 880_000,
            authorizationId: keccak256("HOODPUPS_FIXTURE_AUTHORIZATION_1"),
            deadline: 1_893_456_000,
            attestorEpoch: 7,
            policyVersion: 1
        });
    }

    function _payment(bytes32 id) internal pure returns (PuppetTypes.BitcoinPaymentAttestation memory a) {
        a = PuppetTypes.BitcoinPaymentAttestation({
            contextId: id,
            ownershipDigest: keccak256("HOODPUPS_FIXTURE_OWNERSHIP_DIGEST"),
            solver: SOLVER,
            bitcoinTxid: PAYMENT_TXID,
            outputIndex: 1,
            recipientScriptHash: PuppetHashing.scriptHash(P2TR),
            amountSats: 250_000,
            bitcoinBlockHash: BLOCK_HASH,
            bitcoinHeight: 880_001,
            authorizationId: keccak256("HOODPUPS_FIXTURE_AUTHORIZATION_2"),
            deadline: 1_893_456_000,
            attestorEpoch: 7,
            policyVersion: 1
        });
    }

    function _spend() internal pure returns (PuppetTypes.RootSpendAttestation memory a) {
        a = PuppetTypes.RootSpendAttestation({
            rootTxid: TXID_A,
            rootIndex: 0,
            previousOutpointHash: PuppetHashing.outpointHash(OUTPOINT_TXID, 2),
            spendingTxid: SPEND_TXID,
            bitcoinBlockHash: BLOCK_HASH,
            bitcoinHeight: 880_002,
            authorizationId: keccak256("HOODPUPS_FIXTURE_AUTHORIZATION_3"),
            deadline: 1_893_456_000,
            attestorEpoch: 7,
            policyVersion: 1
        });
    }

    function test_ProbeFixtureHashes() public pure {
        console2.log("BIP322_PROOF_HASH");
        console2.logBytes32(keccak256("HOODPUPS_FIXTURE_BIP322_PROOF"));
        console2.log("BTC_PAYOUT_SCRIPT_HASH");
        console2.logBytes32(keccak256("HOODPUPS_FIXTURE_BTC_PAYOUT_SCRIPT"));
        console2.log("FIXTURE_OWNERSHIP_DIGEST");
        console2.logBytes32(keccak256("HOODPUPS_FIXTURE_OWNERSHIP_DIGEST"));
        console2.log("AUTH_1");
        console2.logBytes32(keccak256("HOODPUPS_FIXTURE_AUTHORIZATION_1"));
        console2.log("AUTH_2");
        console2.logBytes32(keccak256("HOODPUPS_FIXTURE_AUTHORIZATION_2"));
        console2.log("AUTH_3");
        console2.logBytes32(keccak256("HOODPUPS_FIXTURE_AUTHORIZATION_3"));
    }
}
