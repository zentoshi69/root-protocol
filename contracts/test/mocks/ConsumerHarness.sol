// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IBitcoinOwnershipOracle} from "../../src/interfaces/IBitcoinOwnershipOracle.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";

/// @title ConsumerHarness
/// @notice A contract that can hold `OWNERSHIP_CONSUMER_ROLE` and forward calls to the oracle.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      Role gating on `BitcoinOwnershipOracle.consume*` exists so an outsider cannot burn a valid
///      authorization out from under the escrow. Proving that requires calling from BOTH sides of
///      the boundary. `vm.prank` covers the EOA side, but in production the role holder is a
///      contract, and a contract caller exercises paths an EOA never does — `msg.sender` is not
///      `tx.origin`, and any `EXTCODESIZE`-style assumption shows up here. This harness is that
///      contract caller.
///
///      It records the last returned digest/key so a suite can assert the forwarded call actually
///      reached the oracle rather than silently no-oping.
contract ConsumerHarness {
    /// @notice Oracle this harness forwards to.
    IBitcoinOwnershipOracle public oracle;

    /// @notice Digest returned by the most recent successful forward.
    bytes32 public lastDigest;
    /// @notice Root key or payment output key returned by the most recent successful forward.
    bytes32 public lastKey;
    /// @notice Number of successful forwards.
    uint256 public forwardCount;

    /// @param initialOracle Oracle to forward to.
    constructor(IBitcoinOwnershipOracle initialOracle) {
        oracle = initialOracle;
    }

    /// @notice Point the harness at a different oracle.
    /// @param next Oracle to forward to.
    function setOracle(IBitcoinOwnershipOracle next) external {
        oracle = next;
    }

    /// @notice Forward an ownership consumption, preserving the revert of the underlying call.
    /// @param a The ownership attestation.
    /// @param signatures Attestor signatures, ascending by recovered signer.
    /// @param collectionProof Merkle proof of collection membership.
    /// @return digest The consumed digest.
    /// @return rootKey The canonical root key.
    function consumeOwnership(
        PuppetTypes.OwnershipAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (bytes32 digest, bytes32 rootKey) {
        (digest, rootKey) = oracle.consumeOwnership(a, signatures, collectionProof);
        lastDigest = digest;
        lastKey = rootKey;
        forwardCount++;
    }

    /// @notice Forward a Bitcoin payment consumption.
    /// @param a The payment attestation.
    /// @param signatures Attestor signatures, ascending by recovered signer.
    /// @return digest The consumed digest.
    /// @return paymentOutputKey The consumed Bitcoin output key.
    function consumeBitcoinPayment(PuppetTypes.BitcoinPaymentAttestation calldata a, bytes[] calldata signatures)
        external
        returns (bytes32 digest, bytes32 paymentOutputKey)
    {
        (digest, paymentOutputKey) = oracle.consumeBitcoinPayment(a, signatures);
        lastDigest = digest;
        lastKey = paymentOutputKey;
        forwardCount++;
    }

    /// @notice Forward a root-spend consumption.
    /// @param a The spend attestation.
    /// @param signatures Attestor signatures, ascending by recovered signer.
    /// @param collectionProof Merkle proof of collection membership.
    /// @return digest The consumed digest.
    /// @return rootKey The canonical root key.
    function consumeRootSpend(
        PuppetTypes.RootSpendAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (bytes32 digest, bytes32 rootKey) {
        (digest, rootKey) = oracle.consumeRootSpend(a, signatures, collectionProof);
        lastDigest = digest;
        lastKey = rootKey;
        forwardCount++;
    }

    /// @notice Generic forwarder, for role-gating any other contract from a non-EOA caller.
    /// @dev A plain `call`, never `delegatecall`: the harness must act as an independent caller
    ///      with its own identity, which is the whole point. Test-only; nothing in `src/` has an
    ///      arbitrary-call surface like this.
    /// @param target Contract to call.
    /// @param data Calldata to send.
    /// @return ok Whether the call succeeded.
    /// @return ret Return or revert data.
    function forward(address target, bytes calldata data) external payable returns (bool ok, bytes memory ret) {
        (ok, ret) = target.call{value: msg.value}(data);
    }

    receive() external payable {}
}
