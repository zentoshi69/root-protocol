# Pause and Recovery

## The rule that governs every pause

> **Pausing may block new risk-taking. Pausing must never block a refund, withdrawal, or terminal
> resolution of risk the protocol already accepted.**

This is enforced in code, not policy. Refunds, withdrawals, BTC reservation expiry, payment
consumption for an active reservation, terminal minting, and terminal vault credits carry no pause
guard. Full-deployment regressions raise every incident pause after reservation and prove both
settlement and expiry still complete.

## What each pause actually does

| Contract | Pauser blocks | Stays available |
|---|---|---|
| `HoodPupOfferEscrow` | `createPaid*`, `createSelfCast`, `settlePaidEvm`, `settleSelfCast`, `approvePaidBtc`, new BTC reservations | `finalizeBtcSettlement`, `clearBtcReservation`, `refundExpired`, `refundUnfillable`, all views |
| `PayoutVault` | `credit`, `creditRoot`, `creditBatch` | `creditRefund`, `creditTerminal`, `creditTerminalBatch`, every withdrawal, `releaseRootCredit` |
| `BitcoinOwnershipOracle` | `consumeOwnership`, `consumeRootSpend` | `consumeBitcoinPayment` for active BTC resolution, `hash*`, `verify*`, all consumption state views |
| `BtcSolverSettlement` | `reserve` | `expireReservation`, bond credits already earned |
| `RootOwnershipRegistry` | `bindRootOwner`, `invalidateRoot` | all views, existing epoch state |
| `HoodPups` | ordinary `mintRooted` | `mintRootedTerminal` from the escrow, **all transfers**, approvals, ERC-4907 reads |

Note the last row. Pausing minting never freezes the NFT. A paused protocol still leaves every
HoodPup fully transferable, because a token holder's property should not depend on the protocol's
operational state.

## Who can pause

The **guardian** — a separate role from the timelock admin, held by a smaller and faster multisig.

The guardian can *pause*. It cannot unpause, change parameters, move funds, or alter membership.
This asymmetry is the point: pausing during an incident must be fast, and unpausing must be
deliberate.

**Unpausing goes through the timelock.** A compromised guardian can only cost liveness.

## Choosing what to pause

Match the pause to the mechanism that is misbehaving. A broad pause has a real cost — it strands
holders mid-signature and buyers mid-offer.

| Symptom | Pause | Leave running |
|---|---|---|
| False ownership/spend attestation suspected | oracle ownership + Root-spend consumption; pause new solver reservations too | terminal resolution of already-active BTC reservations, refunds, withdrawals |
| Vault accounting broken | vault credits + escrow settlement | withdrawals (mandatory) |
| Solver settlement exploited | `BtcSolverSettlement` reservations | EVM settlement, refunds |
| Manifest wrong | escrow creation | settlement of already-approved offers, refunds |
| Relayer down | **nothing** | relaying is permissionless; this is not a pause-shaped problem |
| Bitcoin reorg in progress | ownership/Root-spend consumption and new solver reservations | active BTC terminal resolution, refunds, withdrawals |

The last two matter. Pausing because something is *slow* converts a liveness problem into a bigger
liveness problem.

## Pausing

```bash
# Guardian multisig executes:
cast send $ORACLE   "pause()" --rpc-url $RH_RPC   # oracle consumption
cast send $ESCROW   "pauseSettlement()" --rpc-url $RH_RPC   # new offers + ordinary settlement
cast send $VAULT    "pause()" --rpc-url $RH_RPC   # new credits only
cast send $SOLVER   "pause()" --rpc-url $RH_RPC   # new reservations
cast send $HOODPUPS "pauseMinting()" --rpc-url $RH_RPC
```

Then, immediately:

1. Post a status notice. State what is paused, what still works, and that withdrawals and refunds
   are unaffected.
2. Snapshot the block number so the investigation has a clean boundary.
3. Tell relayers to stop ordinary ownership/spend submissions and solvers to stop reserving. A
   solver with an active reservation should continue settlement or allow canonical expiry.

## While paused

Users can still:

- withdraw everything in `PayoutVault`,
- refund expired offers,
- settle or expire an already-active BTC reservation,
- transfer, approve and read HoodPups,
- read every view on every contract.

Users cannot create offers, settle through the ordinary EVM/self-cast paths, approve new BTC
offers, reserve, or bind/invalidate a Root owner.

**Offers keep expiring while paused.** An offer that expires during a pause becomes refundable —
which is correct, and is why refunds cannot be pausable. If a pause runs long, expect a wave of
refunds when it lifts, and say so in advance rather than letting it look like a bank run.

## Unpausing

1. Root cause identified and documented.
2. Fix deployed if the fix required a redeployment.
3. Regression test added that reproduces the original failure.
4. Timelock proposal queued to `unpause()`, publicly visible for the full delay.
5. Announce the unpause time.
6. Execute, then verify:

```bash
cast call $ORACLE "paused()(bool)"  --rpc-url $RH_RPC   # false
cast call $ESCROW "paused()(bool)"  --rpc-url $RH_RPC   # false
node scripts/verify-roles.mjs --chain $CHAIN_ID          # no unexpected admin
```

7. Watch the first settlements closely. Do not walk away from an unpause.

## Recovery when a contract cannot be fixed

Core contracts are immutable. If a defect is in the logic itself, the only path is redeploy and
migrate.

1. Pause the affected surface permanently and say so.
2. Deploy corrected versions. Contracts that are unaffected and hold no defective state can be
   reused — `PuppetCollectionRegistry` in particular, since its Merkle root is immutable and
   correct.
3. `PayoutVault` balances stay withdrawable from the **old** vault forever. Never migrate user
   balances by fiat; there is no code path to do it and adding one would have been the larger risk.
4. `HoodPups` tokens minted by the old deployment remain valid and remain the canonical HoodPup for
   their Root. A new `HoodPups` contract must respect that — otherwise one Root produces two
   tokens, breaking the protocol's central promise.
5. Publish the migration plan before executing it.

## Testing

`test/invariant/` covers refunds and withdrawals under pause (protocol invariant **I12**), and
`test/integration/FullFlow.t.sol` pauses every BTC dependency after reservation and proves both
settlement and expiry complete. Neither layer is optional.
