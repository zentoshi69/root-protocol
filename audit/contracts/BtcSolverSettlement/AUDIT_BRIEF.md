# BtcSolverSettlement — audit brief

**Risk class:** HIGH — feature-flagged off at launch, but holds solver bonds when enabled.

| | |
|---|---|
| Source | `contracts/src/BtcSolverSettlement.sol` · 694 non-blank lines |
| Flattened | `BtcSolverSettlement.flat.sol` · 1831 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `d51167292602284ef39de8915d9d9721d16c1489f2cda2c3a573ad8c3f8ce443` |
| Commit | `5d853a42604f54d71ffb0ac740302e5aa7e4adef` |
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
5. ACTIVE reservation, escrow BTC_RESERVED state and the Root mutex always agree
6. Settlement and expiry remain executable through downstream incident pauses

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
- The findings from the prior whole-protocol review and their regression coverage are mapped in
  `docs/AUDIT_REMEDIATION.md`. Cross-contract seams remain the first place to challenge.

## Files in this bundle

| File | Purpose |
|---|---|
| `BtcSolverSettlement.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `BtcSolverSettlement.abi.json` | ABI. |
| `BtcSolverSettlement.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
