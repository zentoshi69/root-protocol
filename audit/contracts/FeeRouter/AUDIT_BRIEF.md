# FeeRouter — audit brief

**Risk class:** MEDIUM — an arithmetic error here leaks value on every settlement.

| | |
|---|---|
| Source | `contracts/src/FeeRouter.sol` · 508 non-blank lines |
| Flattened | `FeeRouter.flat.sol` · 1384 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `a78472a6a478524a839f8c570d1248023bd6d9891c65cf99299277b62f888fa0` |
| Commit | `5d853a42604f54d71ffb0ac740302e5aa7e4adef` |
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
- The findings from the prior whole-protocol review and their regression coverage are mapped in
  `docs/AUDIT_REMEDIATION.md`. Cross-contract seams remain the first place to challenge.

## Files in this bundle

| File | Purpose |
|---|---|
| `FeeRouter.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `FeeRouter.abi.json` | ABI. |
| `FeeRouter.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
