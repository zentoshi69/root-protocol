// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IBitcoinOwnershipOracle} from "../../src/interfaces/IBitcoinOwnershipOracle.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";

/// @title MockOwnershipOracle
/// @notice Stand-in for `BitcoinOwnershipOracle` that lets escrow / registry suites run without a
///         real 3-of-5 quorum.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      HONESTY NOTE — READ BEFORE TRUSTING A GREEN TEST THAT USES THIS:
///      this mock performs NO signature recovery, NO quorum counting, NO attestor-membership
///      check, NO epoch or policy freshness check, NO deadline check, NO collection-membership
///      check and NO role gating. The `signatures` and `collectionProof` arguments are recorded
///      and otherwise ignored. A suite that only ever talks to this mock has proven nothing about
///      quorum security; those properties belong to `BitcoinOwnershipOracle`'s own suite.
///
///      What it DOES keep honest, because downstream contracts genuinely depend on it:
///        * digests are the real `PuppetHashing` struct hashes under a real EIP-712 wrapper;
///        * one-time consumption is enforced — re-consuming a digest reverts `DigestAlreadyConsumed`;
///        * a Bitcoin payment output can settle at most one offer, enforced by
///          `paymentOutputKey` consumption.
///      Those three are the invariants escrow logic is built on, so relaxing them would let a
///      broken escrow look correct.
contract MockOwnershipOracle is IBitcoinOwnershipOracle {
    /// @notice Raised when a suite has armed the forced-failure switch.
    error MockOracleForcedRevert();

    /*//////////////////////////////////////////////////////////////
                            CONSUMPTION RECORDS
    //////////////////////////////////////////////////////////////*/

    /// @notice What the mock saw on the most recent `consumeOwnership` call.
    struct OwnershipRecord {
        bytes32 digest;
        bytes32 rootKey;
        bytes32 contextId;
        uint8 purpose;
        address consumer;
        uint256 signatureCount;
        uint256 proofLength;
    }

    /// @notice What the mock saw on the most recent `consumeBitcoinPayment` call.
    struct PaymentRecord {
        bytes32 digest;
        bytes32 contextId;
        bytes32 paymentOutputKey;
        address solver;
        uint64 amountSats;
        address consumer;
        uint256 signatureCount;
    }

    /// @notice What the mock saw on the most recent `consumeRootSpend` call.
    struct SpendRecord {
        bytes32 digest;
        bytes32 rootKey;
        bytes32 spendingTxid;
        address consumer;
        uint256 signatureCount;
    }

    OwnershipRecord private _lastOwnership;
    PaymentRecord private _lastPayment;
    SpendRecord private _lastSpend;

    uint256 public ownershipConsumeCount;
    uint256 public paymentConsumeCount;
    uint256 public rootSpendConsumeCount;

    mapping(bytes32 => bool) private _consumedDigest;
    mapping(bytes32 => bool) private _consumedPaymentOutput;

    bytes32 private _domainSeparator;
    bool private _nextCallReverts;

    constructor() {
        _domainSeparator = _defaultDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                             TEST MUTATORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Make oracle calls fail, so callers' failure handling can be exercised.
    /// @dev STICKY, not one-shot. A self-clearing flag is impossible here: the revert that
    ///      delivers the failure also rolls back the storage write that would clear it. Suites
    ///      must therefore call `setNextCallReverts(false)` to re-arm the happy path.
    /// @param on True to make every verify/consume call revert `MockOracleForcedRevert`.
    function setNextCallReverts(bool on) external {
        _nextCallReverts = on;
    }

    /// @notice True while the forced-failure switch is armed.
    function nextCallReverts() external view returns (bool) {
        return _nextCallReverts;
    }

    /// @notice Override the EIP-712 domain separator used for digests.
    /// @param next The separator to use.
    function setDomainSeparator(bytes32 next) external {
        _domainSeparator = next;
    }

    /// @notice Mark a digest consumed without going through a consume path.
    /// @param digest The digest to burn.
    function forceConsumeDigest(bytes32 digest) external {
        _consumedDigest[digest] = true;
    }

    /// @notice The EIP-712 domain separator currently in use.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparator;
    }

    /// @notice Most recent ownership consumption record.
    function lastOwnership() external view returns (OwnershipRecord memory) {
        return _lastOwnership;
    }

    /// @notice Most recent Bitcoin payment consumption record.
    function lastPayment() external view returns (PaymentRecord memory) {
        return _lastPayment;
    }

    /// @notice Most recent root-spend consumption record.
    function lastSpend() external view returns (SpendRecord memory) {
        return _lastSpend;
    }

    /*//////////////////////////////////////////////////////////////
                                DIGESTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBitcoinOwnershipOracle
    function hashOwnershipAttestation(PuppetTypes.OwnershipAttestation calldata a) external view returns (bytes32) {
        return _digest(PuppetHashing.hashStruct(a));
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    function hashBitcoinPaymentAttestation(PuppetTypes.BitcoinPaymentAttestation calldata a)
        external
        view
        returns (bytes32)
    {
        return _digest(PuppetHashing.hashStruct(a));
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    function hashRootSpendAttestation(PuppetTypes.RootSpendAttestation calldata a) external view returns (bytes32) {
        return _digest(PuppetHashing.hashStruct(a));
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW VERIFY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @dev Signatures and proof are ignored; see the contract-level honesty note.
    function verifyOwnership(
        PuppetTypes.OwnershipAttestation calldata a,
        bytes[] calldata,
        bytes32[] calldata
    ) external view returns (bytes32 digest, bytes32 rootKey) {
        _guard();
        digest = _digest(PuppetHashing.hashStruct(a));
        if (_consumedDigest[digest]) revert DigestAlreadyConsumed(digest);
        rootKey = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    function verifyBitcoinPayment(PuppetTypes.BitcoinPaymentAttestation calldata a, bytes[] calldata)
        external
        view
        returns (bytes32 digest, bytes32 paymentOutputKey)
    {
        _guard();
        digest = _digest(PuppetHashing.hashStruct(a));
        if (_consumedDigest[digest]) revert DigestAlreadyConsumed(digest);
        paymentOutputKey = PuppetHashing.paymentOutputKey(a.bitcoinTxid, a.outputIndex);
        if (_consumedPaymentOutput[paymentOutputKey]) revert PaymentOutputAlreadyConsumed(paymentOutputKey);
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    function verifyRootSpend(
        PuppetTypes.RootSpendAttestation calldata a,
        bytes[] calldata,
        bytes32[] calldata
    ) external view returns (bytes32 digest, bytes32 rootKey) {
        _guard();
        digest = _digest(PuppetHashing.hashStruct(a));
        if (_consumedDigest[digest]) revert DigestAlreadyConsumed(digest);
        rootKey = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);
    }

    /*//////////////////////////////////////////////////////////////
                               CONSUME
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @dev NOT role gated in the mock. Role gating is a property of the real oracle.
    function consumeOwnership(
        PuppetTypes.OwnershipAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (bytes32 digest, bytes32 rootKey) {
        _guard();
        digest = _digest(PuppetHashing.hashStruct(a));
        if (_consumedDigest[digest]) revert DigestAlreadyConsumed(digest);
        _consumedDigest[digest] = true;

        rootKey = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);
        _lastOwnership = OwnershipRecord({
            digest: digest,
            rootKey: rootKey,
            contextId: a.contextId,
            purpose: a.purpose,
            consumer: msg.sender,
            signatureCount: signatures.length,
            proofLength: collectionProof.length
        });
        ownershipConsumeCount++;

        emit OwnershipConsumed(digest, rootKey, a.contextId, a.purpose, msg.sender, a.bip322ProofHash);
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    function consumeBitcoinPayment(PuppetTypes.BitcoinPaymentAttestation calldata a, bytes[] calldata signatures)
        external
        returns (bytes32 digest, bytes32 paymentOutputKey)
    {
        _guard();
        digest = _digest(PuppetHashing.hashStruct(a));
        if (_consumedDigest[digest]) revert DigestAlreadyConsumed(digest);

        paymentOutputKey = PuppetHashing.paymentOutputKey(a.bitcoinTxid, a.outputIndex);
        if (_consumedPaymentOutput[paymentOutputKey]) revert PaymentOutputAlreadyConsumed(paymentOutputKey);

        _consumedDigest[digest] = true;
        _consumedPaymentOutput[paymentOutputKey] = true;

        _lastPayment = PaymentRecord({
            digest: digest,
            contextId: a.contextId,
            paymentOutputKey: paymentOutputKey,
            solver: a.solver,
            amountSats: a.amountSats,
            consumer: msg.sender,
            signatureCount: signatures.length
        });
        paymentConsumeCount++;

        emit BitcoinPaymentConsumed(digest, a.contextId, paymentOutputKey, a.solver, a.amountSats, msg.sender);
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    function consumeRootSpend(
        PuppetTypes.RootSpendAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata
    ) external returns (bytes32 digest, bytes32 rootKey) {
        _guard();
        digest = _digest(PuppetHashing.hashStruct(a));
        if (_consumedDigest[digest]) revert DigestAlreadyConsumed(digest);
        _consumedDigest[digest] = true;

        rootKey = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);
        _lastSpend = SpendRecord({
            digest: digest,
            rootKey: rootKey,
            spendingTxid: a.spendingTxid,
            consumer: msg.sender,
            signatureCount: signatures.length
        });
        rootSpendConsumeCount++;

        emit RootSpendConsumed(digest, rootKey, a.spendingTxid, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSUMPTION VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBitcoinOwnershipOracle
    function isDigestConsumed(bytes32 digest) external view returns (bool) {
        return _consumedDigest[digest];
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    function isPaymentOutputConsumed(bytes32 bitcoinTxid, uint32 outputIndex) external view returns (bool) {
        return _consumedPaymentOutput[PuppetHashing.paymentOutputKey(bitcoinTxid, outputIndex)];
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    function isPaymentOutputKeyConsumed(bytes32 paymentOutputKey) external view returns (bool) {
        return _consumedPaymentOutput[paymentOutputKey];
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _digest(bytes32 structHash) private view returns (bytes32) {
        return keccak256(abi.encodePacked(hex"1901", _domainSeparator, structHash));
    }

    function _defaultDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("HoodPupsOwnershipOracle"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    function _guard() private view {
        if (_nextCallReverts) revert MockOracleForcedRevert();
    }
}
