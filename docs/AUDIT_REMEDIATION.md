# Smart-contract audit remediation

**Prepared:** 2026-08-16

**Scope:** the ten Solidity protocol contracts, deployment wiring, shared interfaces, canonical
authorization messages, tests, operational documentation, and generated audit artifacts.

**Source:** external whole-protocol audit handoff supplied by the repository owner.

**Status:** all six reported Solidity findings and both recommended hardening items are addressed in
the source tree and regression suites. This document is an implementation record, **not** an
independent re-audit or a statement that the protocol is ready for mainnet.

## Remediation map

| ID | Severity | Resolution | Primary regression evidence |
|---|---|---|---|
| F-01 | Critical | `HoodPupOfferEscrow` now owns a Root-wide BTC reservation mutex. Every competing EVM, self-cast, and BTC reservation/mint path consults it. Reservation acquisition also refuses a Root that was already minted. The mutex and offer state change atomically. | `FullFlow::test_OnlyOneBtcOfferForARootCanBeReserved`; `HoodPupOfferEscrow::test_ActiveBtcReservationBlocksCompetingMintUntilFinalization`; `EscrowInvariant::invariant_AtMostOneActiveReservationPerRootAndConverseHolds` |
| F-02 | High | The escrow no longer exposes an independent public reservation-expiry transition. Only the canonical `BtcSolverSettlement` coordinator can clear the escrow row while resolving the corresponding bond. Public refund paths reject `BTC_RESERVED`, including when another offer minted the Root. | `FullFlow::test_BtcExpirySynchronizesBothStateMachinesWhilePaused`; `HoodPupOfferEscrow::test_EscrowHasNoIndependentReservationExpiryStateMachine`; `test_RefundExpiredRejectsAReservedOffer`; `test_RefundUnfillableRejectsReservedOfferAndPreservesMutex` |
| F-03 | High | `ROOT_BIND` has one compatible encoding end to end: `PayoutMode.EVM`, a nonzero EVM beneficiary, and zero BTC and monetary fields. The Solidity oracle and canonical-message builder enforce the same shape. | `BitcoinOwnershipOracle::test_ValidRootBindShapeAccepted`; `HoodPupOfferEscrow::test_RootBindWorksAgainstTheRealOracleAndReleasesPendingValue`; canonical-message `ROOT_BIND` shape tests |
| F-04 | High | Terminal operations for an already-active BTC reservation remain callable during incident pauses: payment-attestation consumption, escrow finalization, NFT mint, fee routing, solver reimbursement, bond return/slashing, and expiry cleanup. Operations that create new exposure remain pausable. | `FullFlow::test_BtcSettlementCompletesWhileEveryIncidentPauseIsActive`; `test_BtcExpirySynchronizesBothStateMachinesWhilePaused`; terminal-path unit tests in Oracle, Vault, FeeRouter, HoodPups, Escrow, and Solver |
| F-05 | Medium | Escrow and solver share a single 30-day maximum reservation duration. A live reservation may extend beyond the buyer offer's expiry; expiry closes offer acceptance, while the accepted solver receives its complete bounded execution window. | `BtcSolverSettlement::test_SettleSucceedsAfterOfferExpiryWhileTheReservationIsLive`; `HoodPupOfferEscrow::test_MarkBtcReservedRejectsUnboundedAndBackwardsWindows`; constructor-boundary tests |
| F-06 | Medium | The attestor set is fixed at exactly five. Membership can change only through atomic replacement; add/remove entry points are ABI-retained but unreachable at the fixed bound. The threshold may remain 3 or be strengthened to 4/5 or 5/5, but membership cannot expand into a diluted 3-of-N set. | `BitcoinAttestorRegistry::test_AddAttestorCannotDiluteTheFixedFiveMemberSet`; `test_RemoveAttestorCannotShrinkTheFixedFiveMemberSet`; `test_ReplaceAttestorIsAtomicAtMinimumSetSize` |
| H-01 | Hardening | `RootOwnershipRegistry` rejects two different Bitcoin block hashes presented at the same height, for both bind and spend transitions. Equal height with the same block hash remains valid for facts from one block. | `test_BindRootOwnerRejectsConflictingBlockAtEqualBitcoinHeight`; `test_InvalidateRootRejectsConflictingBlockAtEqualBitcoinHeight` |
| H-02 | Hardening | Fee allocation is documented and tested as exact conservation: seller and Puppet-treasury shares use integer floors and the protocol receives the remainder. No claim is made that every indivisible wei always has a literal 50/25/25 decomposition. | tiny-value FeeRouter fuzz/unit coverage; exact-liability vault invariants |

## Lifecycle ownership introduced by the fix

There is exactly one owner of the BTC reservation/bond state machine. The first
`BTC_SETTLEMENT_ROLE` grant permanently records the deployed `BtcSolverSettlement` coordinator in
the escrow. Later grants, revocation, and renunciation are rejected, because changing the
coordinator while a solver is at risk could leave the escrow and bond state machines permanently
out of sync. A coordinator migration therefore requires a fresh escrow/solver deployment after the
old deployment has no active reservations. Deployment verification checks both the role and the
recorded coordinator address.

## Pause model after remediation

The pause boundary distinguishes *new risk* from *existing obligations*:

- Creating, approving, or reserving a new offer remains blocked by the relevant pause.
- Ownership binds and Root invalidations remain blocked while the Oracle/Registry is paused.
- An active BTC reservation can still settle or expire, including its mint, payout, reimbursement,
  bond return or slash, and mutex release.
- Refunds and user withdrawals remain available.

This is a deliberate safety tradeoff. If the attestor quorum is suspected of compromise, guardians
must pause before new reservations are accepted. Once a solver has paid BTC, preventing the terminal
path would guarantee a loss for an honest solver and strand buyer escrow. Because contracts cannot
distinguish an honest terminal attestation from a quorum-signed false one, active reservations retain
their bounded terminal path while paused.

## Verification

The final verification run must include:

```bash
FOUNDRY_PROFILE=lite forge fmt --check
FOUNDRY_PROFILE=lite forge build --offline
FOUNDRY_PROFILE=lite forge test --offline --summary
pnpm typecheck
pnpm test
pnpm vectors
```

Generated ABIs and both external-audit packages must be regenerated only after those checks pass.
The exact final counts and artifact hashes belong in the release/PR record rather than being frozen
in this living document.

## Residual risks and launch decision

- A colluding quorum at the configured threshold can still attest a false Bitcoin fact. That is the
  protocol's disclosed trust boundary, not something Solidity can eliminate.
- Bitcoin reorganizations, stale indexers, BIP-322 implementation defects, and operator
  independence remain operational risks.
- The terminal-while-paused behavior above is necessary for solvency but increases the importance
  of stopping new reservations quickly when quorum integrity is in doubt.
- The coordinator's immutability deliberately trades operational rotation for a single lifecycle
  owner. Migration requires a new deployment.
- Tests establish behavior for the exercised model; they do not replace adversarial external
  review, formal verification, live testnet burn-in, or Bitcoin/Robinhood end-to-end execution.

**Recommendation:** send the remediated source and regenerated artifacts for independent re-review.
Mainnet remains **NO-GO** until every gate in [`DEPLOYMENT.md`](./DEPLOYMENT.md), including that
re-review, is complete.
