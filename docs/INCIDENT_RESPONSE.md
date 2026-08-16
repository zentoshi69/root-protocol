# Incident Response

## First principles

1. **Refunds and withdrawals must keep working.** Pausing is designed so it cannot block them. If
   you find yourself considering an action that would trap user funds, that is the wrong action.
2. **You cannot upgrade your way out.** Core contracts are immutable. The levers are: pause new
   risk-taking, rotate attestors, change the treasury destinations, or deploy a new version and
   migrate. That is the whole list.
3. **Communicate the trust boundary honestly.** If the quorum was compromised, say so. The
   protocol was always documented as 3-of-5 attested, never trustless.

## Severity

| | Definition | Response |
|---|---|---|
| **SEV-1** | User funds at risk or already lost | Page all operators. Pause immediately. Public notice within 1 hour. |
| **SEV-2** | Invariant violated, no loss yet | Page on-call. Pause the affected surface. Notice within 4 hours. |
| **SEV-3** | Degraded liveness | Ticket. Fix in hours. Status-page note. |
| **SEV-4** | Cosmetic or single-user | Normal queue. |

## The pause decision

Pausing costs liveness and buys time. Pause when a mechanism is producing wrong outcomes; do not
pause because a mechanism is *slow*.

| Contract | Pausing blocks | Pausing NEVER blocks |
|---|---|---|
| `HoodPupOfferEscrow` | new offers, settlements | `refundExpired`, `refundUnfillable` |
| `PayoutVault` | new credits | every withdrawal path |
| `BitcoinOwnershipOracle` | attestation consumption | `hash*` and `verify*` views |
| `BtcSolverSettlement` | new reservations | `expireReservation`, earned bond credits |
| `RootOwnershipRegistry` | new activations/invalidations | existing state, vault withdrawals |

Full mechanics in [`PAUSE_AND_RECOVERY.md`](./PAUSE_AND_RECOVERY.md).

## Playbooks

### PayoutVault liability exceeds balance — SEV-1

This should be structurally impossible. If it is true, assume a live exploit.

1. Pause credits on `PayoutVault` and settlements on the escrow. **Do not pause withdrawals** —
   you cannot, and you would not want to.
2. Snapshot: block number, `totalLiability()`, `address(this).balance`, and the full credit/
   withdraw event log since deployment.
3. Reconstruct expected liability from events. Find the first block where the sums diverge.
4. Identify the transaction that broke it. Publish it.
5. Users can still withdraw against real balances first-come-first-served. Say so plainly rather
   than letting people discover it.
6. Remediate by deploying a corrected version and funding a claims process. There is no admin
   path to reassign balances, and adding one would have been a bigger risk than this incident.

### Compromised attestor key — SEV-1 or SEV-2

SEV-2 with one key, SEV-1 with two, because at three the quorum is gone.

1. Immediately propose `replaceAttestor(compromised, fresh)` through the timelock. The epoch bump
   invalidates every in-flight signature from the old set, including any the attacker holds.
2. While the timelock runs, pause oracle consumption if you believe the attacker can reach three
   keys. One or two compromised keys cannot produce quorum on their own — do not pause for that.
3. Audit every digest consumed since the suspected compromise. Cross-reference the compromised
   attestor's audit log against the other four.
4. Full detail in [`KEY_ROTATION.md`](./KEY_ROTATION.md).

### False attestation suspected — SEV-1

A HoodPup minted for an inscription its claimed controller did not control.

1. Pause oracle consumption. This is exactly the case pausing exists for.
2. Determine whether three keys actually signed the same false fact, or whether one operator's
   *inputs* were poisoned (a fed `ord` index, a hijacked RPC) while the operator itself was honest.
   The remediation is completely different.
3. Publish the digest, its signers, and the fact set. The attestation is on chain and permanent —
   there is no version of this where quiet is an option.
4. The mint cannot be reversed. `HoodPups` has no burn function and no admin remap. Remediation is
   social and economic: disclose, compensate, and if necessary redeploy with a new manifest.
5. Root cause the operator independence failure. If three operators shared infrastructure, that is
   the finding, not the signatures.

### Solver paid BTC but was not reimbursed — SEV-2

1. Confirm the Bitcoin payment: exact `txid:vout`, script hash, sat amount, confirmations.
2. Check `isPaymentOutputConsumed(txid, vout)`. If already consumed, another settlement used it —
   investigate as a double-spend attempt against the solver.
3. Check the reservation: expired reservations cannot settle. If it expired while the payment was
   confirming, the reservation duration is too short for the confirmation policy. That is a
   configuration bug and the solver is owed compensation — fix the config, do not add an admin
   override.
4. There is deliberately no discretionary admin reimbursement. Adding one would be a rug lever.

### Bitcoin reorg past confirmation depth — SEV-1

See [`BITCOIN_REORG_RESPONSE.md`](./BITCOIN_REORG_RESPONSE.md).

### Relayer censoring or stuck — SEV-3

Relaying is permissionless and the relayer cannot alter terms. Run another one, or let users
submit directly. Escrow remains refundable at expiry throughout.

### Wrong manifest discovered — SEV-1

The Merkle root is immutable by design, which is a feature until the manifest is wrong.

1. Stop new offers (pause the escrow).
2. Determine the delta: inscriptions wrongly included, wrongly excluded, or both.
3. Wrongly *excluded* is recoverable by redeploying the registry and the contracts downstream of it.
4. Wrongly *included* means HoodPups may already exist for inscriptions that should not have
   qualified. Those tokens are permanent. Disclose the exact list.
5. Root cause the verification failure. The launch gate requires two independent implementations to
   reproduce the root precisely so this cannot happen.

## Communication template

```
[SEV-n] <one-line description>
Detected: <UTC timestamp> · Status: investigating | mitigated | resolved

What happened:
What is affected:
What is NOT affected:   ← always include. Users' Bitcoin Puppets are never affected.
What we did:
What you should do:
Next update:
```

Always state explicitly: **no incident in this protocol can move anyone's Bitcoin Puppet.** The
protocol never holds a Bitcoin key. That is true in every scenario above and is the single most
useful thing a user can be told.

## After

Within five business days publish a post-mortem covering timeline, root cause, why existing
controls did not catch it, what changed, and what remains at risk. Update
[`THREAT_MODEL.md`](./THREAT_MODEL.md) if a new attack class was found — a threat model that never
changes after a real incident was not being used.
