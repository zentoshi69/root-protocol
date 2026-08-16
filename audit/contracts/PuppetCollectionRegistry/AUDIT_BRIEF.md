# PuppetCollectionRegistry — audit brief

**Risk class:** LOW — no state can change after deployment. The exposure is entirely in whether the committed manifest was correct, which is a process gate rather than a code property.

| | |
|---|---|
| Source | `contracts/src/PuppetCollectionRegistry.sol` · 197 non-blank lines |
| Flattened | `PuppetCollectionRegistry.flat.sol` · 1210 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `3998c3453761edda8adfd8563e94bcd2b20a9d84954a70fae7eaf08a6d0b7215` |
| Commit | `10e4ce8b0c222196c6e9a3d5572c74bcb61149fb` |
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
- Two High-severity defects were already found and fixed internally, both by the integration
  suite rather than by unit tests. Both are written up in `docs/SECURITY_REVIEW.md`; the more
  instructive one is H-1, where every contract was individually correct and the violation existed
  only in the composition.

## Files in this bundle

| File | Purpose |
|---|---|
| `PuppetCollectionRegistry.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `PuppetCollectionRegistry.abi.json` | ABI. |
| `PuppetCollectionRegistry.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
