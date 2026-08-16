// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PuppetTypes} from "../types/PuppetTypes.sol";

/// @title IBitcoinOwnershipOracle
/// @notice Turns a 3-of-5 quorum of EIP-712 attestations into one-time-consumable authorizations.
/// @dev This contract verifies SIGNATURES, not Bitcoin. It has no ability to check a BIP-322 proof,
///      an inscription location or a UTXO set. A dishonest quorum can assert a false Bitcoin fact.
///      It can never move the underlying inscription. See `docs/TRUST_ASSUMPTIONS.md`.
interface IBitcoinOwnershipOracle {
    error DeadlineExpired(uint64 deadline, uint256 nowTs);
    error StaleAttestorEpoch(uint64 provided, uint64 current);
    error StalePolicyVersion(uint32 provided, uint32 current);
    error DigestAlreadyConsumed(bytes32 digest);
    error PaymentOutputAlreadyConsumed(bytes32 paymentOutputKey);
    error InsufficientSignatures(uint256 provided, uint8 required);
    error SignerNotAttestor(address signer);
    error SignersNotStrictlyAscending(address previous, address next);
    error ZeroAuthorizationId();
    error UnsupportedPurpose(uint8 purpose);
    error InvalidPayoutShape();
    error ZeroSolver();
    error ZeroAmount();
    error ZeroScriptHash();
    error ZeroOwnershipDigest();
    error ZeroSpendReference();

    event OwnershipConsumed(
        bytes32 indexed digest,
        bytes32 indexed rootKey,
        bytes32 indexed contextId,
        uint8 purpose,
        address consumer,
        bytes32 bip322ProofHash
    );
    event BitcoinPaymentConsumed(
        bytes32 indexed digest,
        bytes32 indexed contextId,
        bytes32 indexed paymentOutputKey,
        address solver,
        uint64 amountSats,
        address consumer
    );
    event RootSpendConsumed(
        bytes32 indexed digest, bytes32 indexed rootKey, bytes32 spendingTxid, address consumer
    );

    /// @notice EIP-712 digest of an ownership attestation.
    function hashOwnershipAttestation(PuppetTypes.OwnershipAttestation calldata a) external view returns (bytes32);

    /// @notice EIP-712 digest of a Bitcoin payment attestation.
    function hashBitcoinPaymentAttestation(PuppetTypes.BitcoinPaymentAttestation calldata a)
        external
        view
        returns (bytes32);

    /// @notice EIP-712 digest of a root-spend attestation.
    function hashRootSpendAttestation(PuppetTypes.RootSpendAttestation calldata a) external view returns (bytes32);

    /// @notice Read-only validation. Reverts on any failure. Does not consume.
    function verifyOwnership(
        PuppetTypes.OwnershipAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external view returns (bytes32 digest, bytes32 rootKey);

    /// @notice Read-only validation. Reverts on any failure. Does not consume.
    function verifyBitcoinPayment(PuppetTypes.BitcoinPaymentAttestation calldata a, bytes[] calldata signatures)
        external
        view
        returns (bytes32 digest, bytes32 paymentOutputKey);

    /// @notice Read-only validation. Reverts on any failure. Does not consume.
    function verifyRootSpend(
        PuppetTypes.RootSpendAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external view returns (bytes32 digest, bytes32 rootKey);

    /// @notice Validate and permanently consume an ownership attestation.
    /// @dev Restricted to `OWNERSHIP_CONSUMER_ROLE` so an outsider cannot burn a valid
    ///      authorization out from under the escrow.
    function consumeOwnership(
        PuppetTypes.OwnershipAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (bytes32 digest, bytes32 rootKey);

    /// @notice Validate and permanently consume a payment attestation and its Bitcoin output.
    function consumeBitcoinPayment(PuppetTypes.BitcoinPaymentAttestation calldata a, bytes[] calldata signatures)
        external
        returns (bytes32 digest, bytes32 paymentOutputKey);

    /// @notice Validate and permanently consume a root-spend attestation.
    function consumeRootSpend(
        PuppetTypes.RootSpendAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (bytes32 digest, bytes32 rootKey);

    /// @notice True once a digest has been consumed. Consumption is permanent.
    function isDigestConsumed(bytes32 digest) external view returns (bool);

    /// @notice True once a Bitcoin output has been used to settle any offer.
    function isPaymentOutputConsumed(bytes32 bitcoinTxid, uint32 outputIndex) external view returns (bool);

    /// @notice True once a payment output key has been consumed.
    function isPaymentOutputKeyConsumed(bytes32 paymentOutputKey) external view returns (bool);
}
