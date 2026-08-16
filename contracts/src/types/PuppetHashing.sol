// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PuppetTypes} from "./PuppetTypes.sol";

/// @title PuppetHashing
/// @notice The single source of truth for every security-relevant hash in the protocol.
/// @dev Rules enforced across this library, and mirrored byte-for-byte in
///      `packages/protocol-sdk` and the attestor services:
///
///      1. NEVER `abi.encodePacked` a multi-field identifier. Packed encoding of two dynamic or
///         two variable-width fields is ambiguous and creates collisions. Everything here uses
///         `abi.encode`, which is 32-byte-word aligned and unambiguous.
///      2. Every hash is domain separated by a constant string so a preimage for one hash family
///         can never be reinterpreted as another.
///      3. Attestation `encodeData` is built with `bytes.concat` of two `abi.encode` chunks.
///         The concatenation is bit-identical to a single `abi.encode` of all fields (every field
///         is a value type, so each occupies exactly one 32-byte word). Chunking exists purely to
///         stay under the EVM's 16-slot stack limit without enabling via-IR.
///
///      Golden vectors covering every function live in `test/unit/PuppetHashing.t.sol` and
///      `data/test-fixtures/hashing-vectors.json`, and CI fails if Solidity and TypeScript diverge.
library PuppetHashing {
    /*//////////////////////////////////////////////////////////////
                             DOMAIN CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Identifies this protocol deployment's canonical Bitcoin Puppets manifest.
    /// @dev "Canonical" means canonical *to this deployment*. It is not, and must never be
    ///      presented as, an endorsement by the Bitcoin Puppets project.
    bytes32 internal constant COLLECTION_ID = keccak256("BITCOIN_PUPPETS_MAINNET_V1");

    /// @dev Domain tag for `outpointHash`, keeping outpoint preimages disjoint from root preimages.
    bytes32 internal constant OUTPOINT_DOMAIN = keccak256("HOODPUPS_BITCOIN_OUTPOINT_V1");

    /// @dev Domain tag for `paymentOutputKey`. Deliberately distinct from `OUTPOINT_DOMAIN` so an
    ///      inscription outpoint can never be mistaken for a consumed BTC payment output.
    bytes32 internal constant PAYMENT_OUTPUT_DOMAIN = keccak256("HOODPUPS_BITCOIN_PAYMENT_OUTPUT_V1");

    /// @dev Domain tag for the immutable offer terms commitment.
    bytes32 internal constant OFFER_TERMS_DOMAIN = keccak256("HOODPUPS_OFFER_TERMS_V1");

    /// @dev Domain tag for deterministic offer identifiers.
    bytes32 internal constant OFFER_ID_DOMAIN = keccak256("HOODPUPS_OFFER_ID_V1");

    /*//////////////////////////////////////////////////////////////
                           EIP-712 TYPE STRINGS
    //////////////////////////////////////////////////////////////*/

    /// @dev Field order MUST match `PuppetTypes.OwnershipAttestation` exactly.
    string internal constant OWNERSHIP_ATTESTATION_TYPE = "OwnershipAttestation("
        "uint8 purpose," "bytes32 rootTxid," "uint32 rootIndex," "bytes32 contextId," "bytes32 offerTermsHash,"
        "bytes32 currentOutpointHash," "bytes32 ownerScriptHash," "bytes32 bip322ProofHash," "address buyer,"
        "address recipient," "uint8 payoutMode," "address evmPayout," "bytes32 btcPayoutScriptHash,"
        "uint64 sellerSats," "uint256 grossWei," "uint256 sellerWei," "bytes32 bitcoinBlockHash,"
        "uint64 bitcoinHeight," "bytes32 authorizationId," "uint64 deadline," "uint64 attestorEpoch,"
        "uint32 policyVersion" ")";

    /// @dev Field order MUST match `PuppetTypes.BitcoinPaymentAttestation` exactly.
    string internal constant BITCOIN_PAYMENT_ATTESTATION_TYPE = "BitcoinPaymentAttestation("
        "bytes32 contextId," "bytes32 ownershipDigest," "address solver," "bytes32 bitcoinTxid,"
        "uint32 outputIndex," "bytes32 recipientScriptHash," "uint64 amountSats," "bytes32 bitcoinBlockHash,"
        "uint64 bitcoinHeight," "bytes32 authorizationId," "uint64 deadline," "uint64 attestorEpoch,"
        "uint32 policyVersion" ")";

    /// @dev Field order MUST match `PuppetTypes.RootSpendAttestation` exactly.
    string internal constant ROOT_SPEND_ATTESTATION_TYPE = "RootSpendAttestation("
        "bytes32 rootTxid," "uint32 rootIndex," "bytes32 previousOutpointHash," "bytes32 spendingTxid,"
        "bytes32 bitcoinBlockHash," "uint64 bitcoinHeight," "bytes32 authorizationId," "uint64 deadline,"
        "uint64 attestorEpoch," "uint32 policyVersion" ")";

    /// @dev EIP-712 type used by `PayoutVault.withdrawWithAuthorization`.
    string internal constant WITHDRAWAL_TYPE =
        "Withdrawal(" "address beneficiary," "address recipient," "uint256 amount," "uint256 nonce," "uint64 deadline" ")";

    /*//////////////////////////////////////////////////////////////
                            EIP-712 TYPE HASHES
    //////////////////////////////////////////////////////////////*/

    bytes32 internal constant OWNERSHIP_ATTESTATION_TYPEHASH = keccak256(bytes(OWNERSHIP_ATTESTATION_TYPE));
    bytes32 internal constant BITCOIN_PAYMENT_ATTESTATION_TYPEHASH =
        keccak256(bytes(BITCOIN_PAYMENT_ATTESTATION_TYPE));
    bytes32 internal constant ROOT_SPEND_ATTESTATION_TYPEHASH = keccak256(bytes(ROOT_SPEND_ATTESTATION_TYPE));
    bytes32 internal constant WITHDRAWAL_TYPEHASH = keccak256(bytes(WITHDRAWAL_TYPE));

    /*//////////////////////////////////////////////////////////////
                            IDENTITY HASHING
    //////////////////////////////////////////////////////////////*/

    /// @notice Canonical protocol key for one Bitcoin Puppet inscription.
    /// @dev `keccak256(abi.encode(COLLECTION_ID, inscriptionTxid, inscriptionIndex))`.
    ///      Two inscriptions sharing a reveal txid but differing by index produce different keys,
    ///      because `inscriptionIndex` occupies its own 32-byte word.
    function rootKey(bytes32 inscriptionTxid, uint32 inscriptionIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(COLLECTION_ID, inscriptionTxid, inscriptionIndex));
    }

    /// @notice Canonical protocol key for a `RootId` struct.
    function rootKey(PuppetTypes.RootId memory root) internal pure returns (bytes32) {
        return rootKey(root.inscriptionTxid, root.inscriptionIndex);
    }

    /// @notice Merkle leaf for the canonical collection tree.
    /// @dev Double hashed (`keccak256` of the 32-byte `rootKey`) following the OpenZeppelin
    ///      `StandardMerkleTree` convention. The second hash makes an internal node preimage
    ///      structurally impossible to present as a leaf, which defeats second-preimage attacks.
    ///      The off-chain builder in `packages/protocol-sdk` reproduces this exactly.
    function collectionLeaf(bytes32 key) internal pure returns (bytes32) {
        return keccak256(bytes.concat(key));
    }

    /// @notice Merkle leaf for a `RootId`.
    function collectionLeaf(PuppetTypes.RootId memory root) internal pure returns (bytes32) {
        return collectionLeaf(rootKey(root));
    }

    /// @notice Hash of a Bitcoin outpoint (`txid:vout`) holding an inscription.
    /// @param bitcoinTxid Txid in display order.
    /// @param vout Output index.
    function outpointHash(bytes32 bitcoinTxid, uint32 vout) internal pure returns (bytes32) {
        return keccak256(abi.encode(OUTPOINT_DOMAIN, bitcoinTxid, vout));
    }

    /// @notice Global uniqueness key for a Bitcoin output used to pay a seller.
    /// @dev Consuming this key in `BitcoinOwnershipOracle` is what stops one BTC payment from
    ///      settling more than one offer.
    function paymentOutputKey(bytes32 bitcoinTxid, uint32 vout) internal pure returns (bytes32) {
        return keccak256(abi.encode(PAYMENT_OUTPUT_DOMAIN, bitcoinTxid, vout));
    }

    /// @notice Hash of a raw Bitcoin `scriptPubKey`.
    /// @dev Takes the raw script bytes, never a bech32/base58 address string. Address strings are
    ///      network- and encoding-dependent and are therefore unsafe as a security primitive.
    function scriptHash(bytes memory rawScriptPubKey) internal pure returns (bytes32) {
        return keccak256(rawScriptPubKey);
    }

    /*//////////////////////////////////////////////////////////////
                              OFFER HASHING
    //////////////////////////////////////////////////////////////*/

    /// @notice Deterministic offer identifier.
    /// @dev Bound to chain, escrow and buyer so ids cannot collide across deployments.
    function offerId(uint256 chainId, address escrow, address buyer, uint256 buyerNonce)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(OFFER_ID_DOMAIN, chainId, escrow, buyer, buyerNonce));
    }

    /// @notice Immutable commitment to every fixed term of an offer.
    /// @dev The Bitcoin controller signs this hash inside the canonical BIP-322 message, so it is
    ///      what makes "the terms I saw are the terms that execute" enforceable. Any change to a
    ///      bound field invalidates every signature collected for the offer.
    function offerTermsHash(
        uint256 chainId,
        address escrow,
        bytes32 id,
        uint8 kind,
        bytes32 key,
        address buyer,
        address recipient,
        uint256 grossWei,
        uint256 sellerWei,
        uint64 sellerSats,
        uint64 expiry
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OFFER_TERMS_DOMAIN,
                chainId,
                escrow,
                id,
                kind,
                key,
                buyer,
                recipient,
                grossWei,
                sellerWei,
                sellerSats,
                expiry
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                          ATTESTATION STRUCT HASHING
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP-712 `hashStruct` of an `OwnershipAttestation`.
    /// @dev Two-chunk `bytes.concat` is byte-identical to encoding all 23 words at once.
    function hashStruct(PuppetTypes.OwnershipAttestation memory a) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    OWNERSHIP_ATTESTATION_TYPEHASH,
                    a.purpose,
                    a.rootTxid,
                    a.rootIndex,
                    a.contextId,
                    a.offerTermsHash,
                    a.currentOutpointHash,
                    a.ownerScriptHash,
                    a.bip322ProofHash,
                    a.buyer,
                    a.recipient,
                    a.payoutMode
                ),
                abi.encode(
                    a.evmPayout,
                    a.btcPayoutScriptHash,
                    a.sellerSats,
                    a.grossWei,
                    a.sellerWei,
                    a.bitcoinBlockHash,
                    a.bitcoinHeight,
                    a.authorizationId,
                    a.deadline,
                    a.attestorEpoch,
                    a.policyVersion
                )
            )
        );
    }

    /// @notice EIP-712 `hashStruct` of a `BitcoinPaymentAttestation`.
    function hashStruct(PuppetTypes.BitcoinPaymentAttestation memory a) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    BITCOIN_PAYMENT_ATTESTATION_TYPEHASH,
                    a.contextId,
                    a.ownershipDigest,
                    a.solver,
                    a.bitcoinTxid,
                    a.outputIndex,
                    a.recipientScriptHash,
                    a.amountSats
                ),
                abi.encode(
                    a.bitcoinBlockHash, a.bitcoinHeight, a.authorizationId, a.deadline, a.attestorEpoch, a.policyVersion
                )
            )
        );
    }

    /// @notice EIP-712 `hashStruct` of a `RootSpendAttestation`.
    function hashStruct(PuppetTypes.RootSpendAttestation memory a) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ROOT_SPEND_ATTESTATION_TYPEHASH,
                a.rootTxid,
                a.rootIndex,
                a.previousOutpointHash,
                a.spendingTxid,
                a.bitcoinBlockHash,
                a.bitcoinHeight,
                a.authorizationId,
                a.deadline,
                a.attestorEpoch,
                a.policyVersion
            )
        );
    }

    /// @notice EIP-712 `hashStruct` of a gasless `Withdrawal` authorization.
    function hashWithdrawal(address beneficiary, address recipient, uint256 amount, uint256 nonce, uint64 deadline)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(WITHDRAWAL_TYPEHASH, beneficiary, recipient, amount, nonce, deadline));
    }
}
