# Bitcoin Reorg Response

A Bitcoin reorganisation can invalidate a fact that five verifiers already attested and a
Robinhood Chain contract already consumed. Consumption is permanent. This is the sharpest edge in
the protocol and it cannot be designed away — only bounded, detected, and handled honestly.

## Why attestations record block hash and height

Every attestation carries `bitcoinBlockHash` and `bitcoinHeight`. Neither is checked on chain — the
contract cannot validate them. They exist so that **after** a reorg, anyone can determine exactly
which attestations referenced an orphaned block.

Without them, a reorg would be undetectable after the fact. With them, the affected set is a
database query.

## Detection

Every verifier watches for its own tip being reorganised:

```
alert when:  a block previously reported at height H no longer exists at height H
             AND any attestation referenced that block hash
```

Verifiers must additionally alert on:

- reorg depth exceeding the payment confirmation policy (3 on mainnet) — **SEV-1**
- an inscription UTXO becoming spent after being attested unspent
- a payment transaction disappearing from the chain after being attested confirmed
- persistent disagreement between operators about the tip

## Blast radius by fact type

### Ownership attestation

**Impact: low.** An ownership attestation asserts an inscription sits in an unspent UTXO. A reorg
that undoes that transaction also undoes the ownership claim itself — the counterfactual is that
the mint should not have happened, but no money moved to a party who did not deserve it *because
of the reorg*. Bob still controlled the inscription in every history where the reveal exists.

The dangerous case is narrow: a reorg that lets a *competing* spend of the inscription UTXO
confirm, meaning Bob had already sold and the sale was briefly orphaned. The mint stands and the
seller share went to Bob.

**Response:** record it, disclose it, do not attempt to reverse the mint. `HoodPups` has no burn
function, by design.

### Payment attestation

**Impact: high.** This is the one that costs real money. If a solver's BTC payment is reorged away
after the solver was reimbursed in ETH, the seller was never paid and the buyer's escrow is gone.

**Response:**

1. Pause `BtcSolverSettlement` reservations and oracle consumption immediately.
2. Query every payment attestation referencing an orphaned block.
3. For each, check whether the payment transaction was re-mined in the new chain. Most are — the
   same transaction is usually valid in both histories and gets re-included within a few blocks.
4. Only payments that are genuinely absent are losses. Quantify exactly and publish.
5. Compensation is a social process. There is deliberately no admin reversal path, because a
   contract that can un-mint and claw back is a contract with a rug lever.
6. Raise the confirmation policy and bump `policyVersion`.

### Root spend attestation

**Impact: medium.** A reorged spend would wrongly deactivate a live owner's epoch. Recoverable: the
owner submits a fresh `ROOT_BIND` and starts a new epoch, and any value that accrued to
`pendingByRoot` in the meantime releases to them. Nothing is lost, only delayed.

## Response by depth

| Depth | Severity | Action |
|---|---|---|
| 1–2 blocks | routine | Normal. Ownership policy already tolerates it. Log only. |
| 3–5 blocks | SEV-2 | Pause solver settlement. Audit payment attestations in range. Resume when clean. |
| 6+ blocks | SEV-1 | Pause oracle consumption entirely. Full audit. Public notice. Do not resume until the chain is stable and every affected attestation is accounted for. |
| Sustained chain split | SEV-1 | Halt all attestation. Verifiers must not sign while operators disagree about which chain is Bitcoin. Wait for convergence. |

## The RBF case

A solver's payment replaced by fee bumping before it confirms is **not** a reorg, and it is why the
payment policy requires burial depth rather than mempool presence.

If a verifier ever attested a payment on mempool presence alone, a solver could broadcast, get
attested, then RBF-replace with a transaction paying itself. The confirmation requirement closes
this. Verifiers must additionally check for conflicting spends in the mempool at attestation time —
"confirmed" and "not being replaced" are different questions.

## Recovery checklist

```
[ ] Reorg depth and orphaned block hashes recorded
[ ] Every attestation referencing an orphaned block identified (query by bitcoinBlockHash)
[ ] Each classified: ownership / payment / root-spend
[ ] Payment transactions checked for re-inclusion in the new chain
[ ] Genuine losses quantified in sats and wei, with txids
[ ] Public disclosure published, including the exact affected list
[ ] Confirmation policy reviewed; policyVersion bumped if changed
[ ] Reservation duration re-checked against the new confirmation policy
[ ] Verifiers resynced and agreeing on the tip
[ ] Pause lifted through the timelock
[ ] Post-mortem published
```

That second-to-last configuration check matters: raising the payment confirmation requirement
without also lengthening `reservationDuration` means solvers start timing out while their payments
are still confirming, converting a reorg incident into a wave of wrongly slashed bonds.

## What users need to be told

- Their Bitcoin Puppet is unaffected. A reorg cannot move it, and neither can this protocol.
- HoodPups already minted stay minted. There is no burn.
- `PayoutVault` balances already credited stay credited and withdrawable.
- If a BTC payment was genuinely lost, say exactly which one and what happens next.

## Prevention

- Payment confirmation depth ≥ 3 on mainnet, tunable via `policyVersion`.
- Reservation duration comfortably longer than the confirmation policy.
- Mempool conflict checks at attestation time.
- Short attestation deadlines, so a stale fact expires rather than lingering.
- Every attestation records the tip it was made against.
- Verifiers alert on tip divergence between operators before it becomes an incident.
