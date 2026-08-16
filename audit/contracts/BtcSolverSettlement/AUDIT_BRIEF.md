# BtcSolverSettlement — audit brief

**Risk class:** HIGH — feature-flagged off at launch, but holds solver bonds when enabled.

| | |
|---|---|
| Source | `contracts/src/BtcSolverSettlement.sol` · 696 non-blank lines |
| Flattened | `BtcSolverSettlement.flat.sol` · 1812 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `118cd02a5056545b6e1d91d71c9184d61777b6e879568fbbd9dbd623097fd104` |
| Commit | `10e4ce8b0c222196c6e9a3d5572c74bcb61149fb` |
| Compiler | solc 0.8.28, evm shanghai, optimizer on (800 runs), via-IR off |

## What it does

Bonded solvers front exact native BTC to a seller and are reimbursed in ETH after a 3-of-5 payment attestation.

## Trust and authority

No price oracle anywhere, by design. No admin can choose a solver or forgive an individual reservation — either would be a rug lever.

## Invariants it must hold

1. Every wei of every bond is at all times in exactly one of: active reservation, returned credit, slash credit
2. buyerCompensation + protocolAmount == bond, exactly, with no dust
3. Reimbursement requires msg.sender to be the reserved solver AND the attested solver
4. Terms are snapshotted at reservation, so later config changes cannot alter an in-flight reservation

## Where to look first

- Bond conservation across both the settle and slash paths
- Whether a permissionless relayer can redirect a solver's reimbursement
- Whether reservationDuration can be configured shorter than the verifiers' confirmation policy — that combination loses a solver both its bond and its BTC, the worst outcome available in the protocol
- Ordering: reimbursement must not precede oracle consumption and mint finalization

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
| `BtcSolverSettlement.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `BtcSolverSettlement.abi.json` | ABI. |
| `BtcSolverSettlement.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
