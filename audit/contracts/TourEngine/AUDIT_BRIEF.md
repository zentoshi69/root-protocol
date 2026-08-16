# TourEngine — audit brief

**Risk class:** LOW — non-financial. Worst case is a farmed miles counter.

| | |
|---|---|
| Source | `contracts/src/TourEngine.sol` · 526 non-blank lines |
| Flattened | `TourEngine.flat.sol` · 1526 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `1de71258d9f48bd43e938c61b8eddca9a9de311978e8acc97ae259ce31878a56` |
| Commit | `5d853a42604f54d71ffb0ac740302e5aa7e4adef` |
| Compiler | solc 0.8.28, evm shanghai, optimizer on (800 runs), via-IR off |

## What it does

Temporary ERC-4907 lending. Produces provenance and a miles counter — no token, no cash, no claim on revenue.

## Trust and authority

Timelock admin for season and duration bounds. Cannot move or transfer any NFT.

## Invariants it must hold

1. miles increments only via a finalized, checked-in tour
2. Never more than once for the same (token, season, recipient) tuple
3. No credit when the owner changes mid-tour or the user role is tampered with

## Where to look first

- Anti-farm boundaries stop naive repeat loops, not Sybils — confirm the contract nowhere claims to prove unique humanity, because it cannot
- Whether cancelInvalidTour can be used to grief a legitimate tour
- The interaction with HoodPups.setUser under TOUR_ENGINE_ROLE

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
| `TourEngine.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `TourEngine.abi.json` | ABI. |
| `TourEngine.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
