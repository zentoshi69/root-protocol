# FeeRouter — audit brief

**Risk class:** MEDIUM — an arithmetic error here leaks value on every settlement.

| | |
|---|---|
| Source | `contracts/src/FeeRouter.sol` · 497 non-blank lines |
| Flattened | `FeeRouter.flat.sol` · 1356 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `c75417ad32a08e3fa7c5e8e42004a332a7643c65e3db3d339952d31c1b54de54` |
| Commit | `10e4ce8b0c222196c6e9a3d5572c74bcb61149fb` |
| Compiler | solc 0.8.28, evm shanghai, optimizer on (800 runs), via-IR off |

## What it does

The immutable 50 / 25 / 25 split. Holds no ETH after any call.

## Trust and authority

Percentages are compile-time constants with no setter and no upgrade path. Only the two treasury destinations are governable, via timelock, and only for future routing.

## Invariants it must hold

1. seller + puppetTreasury + protocol == gross, exactly, for every input
2. Router balance is zero after every successful route
3. Percentages cannot change by any path

## Where to look first

- Conservation at 1, 2 and 3 wei, where three independent floor divisions would strand dust permanently
- Confirm no setter, no upgrade and no delegatecall can reach the BPS constants
- The BTC route credits the SOLVER rather than the seller, because the seller was already paid in BTC — verify that is unambiguous and cannot be inverted

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
| `FeeRouter.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `FeeRouter.abi.json` | ABI. |
| `FeeRouter.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
