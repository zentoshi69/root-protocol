# CODEX CONTRACT PROMPT 02 — PUPPET COLLECTION REGISTRY

Implement an immutable Merkle membership registry for the canonical Bitcoin Puppets root set.

## Purpose

The contract answers only one security question:

> Is this exact Bitcoin inscription ID included in the protocol’s canonical Bitcoin Puppets manifest?

It does not track current Bitcoin ownership. Ownership is handled by the verifier/oracle layer.

## Contract

Create:

```text
contracts/src/PuppetCollectionRegistry.sol
```

Use the shared `RootId` and `PuppetHashing` library.

Constructor inputs:

```text
bytes32 merkleRoot
bytes32 manifestHash
string manifestVersion
```

Store all three immutably where Solidity permits. Reject a zero Merkle root or zero manifest hash.

Expose:

```text
collectionId() -> bytes32
merkleRoot() -> bytes32
manifestHash() -> bytes32
manifestVersion() -> string
rootKey(RootId) -> bytes32
isMember(RootId, bytes32[] proof) -> bool
requireMember(RootId, bytes32[] proof)
```

Use OpenZeppelin `MerkleProof` with sorted-pair hashing. The off-chain builder must use the same algorithm.

## Manifest tooling

Create a deterministic tool under `scripts/` or `packages/protocol-sdk/` that:

1. Reads `data/bitcoin-puppets-mainnet.json`.
2. Validates every entry is a unique lowercase 64-hex txid plus a non-negative inscription index fitting `uint32`.
3. Computes `rootKey = keccak256(abi.encode(collectionId, txid, index))` exactly as Solidity does.
4. Sorts leaves by raw bytes.
5. Builds the OpenZeppelin-compatible sorted-pair Merkle tree.
6. Outputs:
   - Merkle root;
   - SHA-256 or Keccak manifest content hash, clearly named;
   - per-root proofs;
   - a reproducibility report.
7. Fails if the production manifest file is missing. Do not create fake production inscription IDs.

Provide a small fixture manifest for tests only.

## Security rules

- No admin can change the Merkle root after deployment.
- No upgradeability.
- No ownership concept.
- No arbitrary collection insertion.
- No mutable URI or metadata dependency.
- Clearly document that “canonical” means canonical to this protocol deployment, not an official endorsement claim.

## Tests

Cover:

- valid member;
- invalid member;
- modified txid;
- modified inscription index;
- empty proof for a single-leaf fixture;
- duplicate manifest entry rejection in the builder;
- deterministic root reproduction;
- cross-language golden vectors;
- constructor zero-value reverts.

Run format, build, and tests. Report the computed fixture Merkle root and the command used to reproduce it.
