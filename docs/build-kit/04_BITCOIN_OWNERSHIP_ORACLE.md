# CODEX CONTRACT PROMPT 04 — BITCOIN OWNERSHIP ORACLE

Implement the EIP-712 quorum oracle that translates independently verified Bitcoin facts into one-time consumable Robinhood Chain authorizations.

This contract does not verify Bitcoin scripts or BIP-322 itself. It verifies that a threshold of authorized attestors signed exactly the same typed fact set.

## Contract

Create:

```text
contracts/src/BitcoinOwnershipOracle.sol
```

Dependencies:

- `PuppetCollectionRegistry`
- `BitcoinAttestorRegistry`
- shared `PuppetTypes` and `PuppetHashing`
- OpenZeppelin `EIP712`, `ECDSA`, `AccessControl`, and `Pausable`

Do not make it upgradeable.

## EIP-712 domain

Use:

```text
name: HoodPups Bitcoin Oracle
version: 1
chainId: runtime chain ID
verifyingContract: this contract
```

Expose public pure/view digest functions so off-chain code can compare exact hashes before signing.

## Attestation types

Implement exact hashing for:

1. `OwnershipAttestation`
2. `BitcoinPaymentAttestation`
3. `RootSpendAttestation`

Use the canonical field order from `PuppetTypes.sol`. Do not use packed encoding.

## Verification rules common to all attestations

- `deadline >= block.timestamp`;
- `attestorEpoch == registry.attestorEpoch()`;
- `policyVersion == registry.policyVersion()`;
- digest not previously consumed;
- signature count at least current threshold;
- every signature recovers to a current attestor;
- recovered signer addresses are strictly ascending, which simultaneously rejects duplicates and makes behavior deterministic;
- support canonical 65-byte and EIP-2098 compact ECDSA signatures through OpenZeppelin;
- wrong chain or wrong verifying contract fails through EIP-712 domain separation.

## Ownership-specific rules

- calculate `rootKey` from root txid/index;
- require valid collection Merkle proof;
- `authorizationId` nonzero;
- purpose must be one of the ownership purposes supported by the caller;
- payout fields must be structurally valid:
  - EVM payout requires nonzero `evmPayout`, zero BTC script hash, zero sats;
  - BTC payout requires zero EVM payout, nonzero BTC script hash, positive sats;
  - self-cast requires zero payout fields and zero monetary fields;
- include and emit `bip322ProofHash`, but do not interpret it on-chain.

## Payment-specific rules

- nonzero solver;
- positive sats;
- nonzero recipient script hash;
- nonzero ownership digest;
- derive `paymentOutputKey = keccak256(abi.encode(bitcoinTxid, outputIndex))`;
- globally prevent reuse of a Bitcoin payment output;
- mark both digest and payment output consumed atomically.

## Root-spend rules

- require valid collection membership proof;
- previous outpoint hash and spending txid nonzero;
- consume once.

## Consumer roles

Create narrow roles:

```text
OWNERSHIP_CONSUMER_ROLE
PAYMENT_CONSUMER_ROLE
ROOT_SPEND_CONSUMER_ROLE
PAUSER_ROLE
```

Only authorized protocol contracts may consume attestations. Public callers may use view verification/hash functions but must not be able to front-run and burn a valid authorization.

Pause consumption functions only. Hashing and view verification remain available.

## Required functions

At minimum:

```text
hashOwnershipAttestation(attestation)
hashBitcoinPaymentAttestation(attestation)
hashRootSpendAttestation(attestation)
verifyOwnership(attestation, signatures, merkleProof)
verifyBitcoinPayment(attestation, signatures)
verifyRootSpend(attestation, signatures, merkleProof)
consumeOwnership(...)
consumeBitcoinPayment(...)
consumeRootSpend(...)
isDigestConsumed(bytes32)
isPaymentOutputConsumed(bytes32 txid, uint32 vout)
```

Return the consumed digest from consume functions.

## Tests

Build exhaustive tests for:

- valid three-of-five quorum;
- insufficient signatures;
- unauthorized signer;
- duplicate signer;
- unsorted signer list;
- signature malleability handling;
- compact signatures;
- stale epoch;
- stale policy;
- expired deadline;
- replay;
- wrong chain/domain;
- wrong field ordering;
- wrong purpose;
- invalid Merkle proof;
- malformed payout combinations;
- reused Bitcoin payment output;
- caller without consumer role;
- pause behavior;
- fuzzing signature array order and size.

Add golden EIP-712 vectors consumed by Solidity and the off-chain SDK.

Run format, build, unit tests, fuzz tests, and static analysis. Report the exact EIP-712 type strings in the final summary.
