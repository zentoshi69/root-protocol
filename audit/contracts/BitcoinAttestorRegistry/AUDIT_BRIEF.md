# BitcoinAttestorRegistry — audit brief

**Risk class:** MEDIUM — a governance error here weakens quorum. It cannot directly move funds.

| | |
|---|---|
| Source | `contracts/src/BitcoinAttestorRegistry.sol` · 301 non-blank lines |
| Flattened | `BitcoinAttestorRegistry.flat.sol` · 1004 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `0bff02c1f066e03898eb4a89434d81621ec0072d467e33127ce8e28db3399a32` |
| Commit | `10e4ce8b0c222196c6e9a3d5572c74bcb61149fb` |
| Compiler | solc 0.8.28, evm shanghai, optimizer on (800 runs), via-IR off |

## What it does

Membership, threshold, epoch and policy version for the five-operator verifier set.

## Trust and authority

Timelock admin. Every mutation bumps attestorEpoch, which instantly invalidates all in-flight attestation signatures.

## Invariants it must hold

1. 5 <= attestorCount <= 32 at all times
2. 3 <= threshold <= attestorCount at all times
3. Every membership, threshold or policy change increments attestorEpoch exactly once
4. replaceAttestor is atomic and never transiently drops below the minimum

## Where to look first

- Whether any mutation path can leave threshold > count
- Whether the epoch can fail to bump on a state-changing path — that would leave a window in which a removed operator still counts toward quorum, which is precisely what an attacker would aim for
- EnumerableSet removal semantics, particularly swap-and-pop during iteration

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
| `BitcoinAttestorRegistry.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `BitcoinAttestorRegistry.abi.json` | ABI. |
| `BitcoinAttestorRegistry.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
