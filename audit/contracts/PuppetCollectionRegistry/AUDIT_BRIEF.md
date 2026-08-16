# PuppetCollectionRegistry — audit brief

**Risk class:** LOW — no state can change after deployment. The exposure is entirely in whether the committed manifest was correct, which is a process gate rather than a code property.

| | |
|---|---|
| Source | `contracts/src/PuppetCollectionRegistry.sol` · 197 non-blank lines |
| Flattened | `PuppetCollectionRegistry.flat.sol` · 1214 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `05b825b225202f06bef1834bb3272c2066d76a6c98ec4c78133d80ab35504c21` |
| Commit | `dde0ec7c8ed5f2f1dbadb9c099a08a8d702d912b` |
| Compiler | solc 0.8.28, evm shanghai, optimizer on (800 runs), via-IR off |

## What it does

Immutable Merkle membership for the canonical Bitcoin Puppets manifest. It answers exactly one question — is this inscription in the set this deployment committed to? — and knows nothing about who currently owns it.

## Trust and authority

No admin, no owner, no upgrade path. The Merkle root is fixed at construction and can never change.

## Invariants it must hold

1. Membership cannot be added or removed after deployment, by anyone
2. leaf = keccak256(rootKey) — double-hashed, so a 64-byte internal node preimage can never be presented as a 32-byte leaf
3. Sibling inscriptions sharing a reveal txid produce distinct rootKeys

## Where to look first

- Merkle verification against OpenZeppelin's sorted-pair convention
- Whether the double-hashed leaf genuinely defeats second-preimage attacks
- Constructor validation — a zero root would make every proof fail permanently, with no recovery

## Context worth having before you start

- This is **not** a trustless Bitcoin bridge. Bitcoin facts are asserted by a 3-of-5 quorum of
  independent verifier operators. `docs/TRUST_ASSUMPTIONS.md` states what that quorum can and
  cannot do. A report that "a colluding quorum can lie" describes the design, not a finding —
  the useful question is whether the blast radius is genuinely bounded as claimed.
- Core contracts are **non-upgradeable**. No proxy, no initializer, no delegatecall. There is no
  upgrade key to compromise, and equally no way to patch a finding in place.
- The findings from the prior whole-protocol review and their regression coverage are mapped in
  `docs/AUDIT_REMEDIATION.md`. Cross-contract seams remain the first place to challenge.

## Files in this bundle

| File | Purpose |
|---|---|
| `PuppetCollectionRegistry.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `PuppetCollectionRegistry.abi.json` | ABI. |
| `PuppetCollectionRegistry.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
