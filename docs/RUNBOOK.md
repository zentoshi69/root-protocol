# Operations Runbook

Day-to-day operation of the HoodPups Rooted Settlement Protocol. For emergencies see
[`INCIDENT_RESPONSE.md`](./INCIDENT_RESPONSE.md); for pausing see
[`PAUSE_AND_RECOVERY.md`](./PAUSE_AND_RECOVERY.md).

## System inventory

| Component | Count | Who runs it | Failure mode |
|---|---|---|---|
| Robinhood Chain contracts | 10 | nobody — immutable | none; they cannot be changed |
| `bitcoin-verifier` + `ord` + `bitcoind` | 5 | five independent operators | attestation stalls |
| `attestor` | 5 | same five, one key each | quorum drops below 3 |
| `relayer` | ≥1 | anyone | settlement delayed, never wrong |
| `btc-solver` | 0..n | independent market participants | BTC offers go unfilled |

The only components whose failure can lose money are the attestors, and only by collusion. Every
other failure costs time.

## Daily checks

```bash
# 1. Quorum health — all five attestors up, agreeing, on the current epoch and policy
curl -s https://attestor-{1..5}.example/health | jq '{ok, epoch, policyVersion, btcHeight, rhBlock}'

# 2. Epoch and policy on chain must match what every attestor reports
cast call $ATTESTOR_REGISTRY "attestorEpoch()(uint64)"  --rpc-url $RH_RPC
cast call $ATTESTOR_REGISTRY "policyVersion()(uint32)"  --rpc-url $RH_RPC
cast call $ATTESTOR_REGISTRY "threshold()(uint8)"       --rpc-url $RH_RPC

# 3. Vault solvency — MUST be >= 0, always
cast call $PAYOUT_VAULT "totalLiability()(uint256)" --rpc-url $RH_RPC
cast balance $PAYOUT_VAULT --rpc-url $RH_RPC

# 4. Nobody holds admin except the timelock
node scripts/verify-roles.mjs --chain $CHAIN_ID
```

### Alert thresholds

| Signal | Warn | Page |
|---|---|---|
| Attestors reporting healthy | < 5 | < 4 (one more failure loses quorum) |
| Attestor Bitcoin height spread | > 2 blocks | > 6 blocks |
| Attestor `ord` index lag behind `bitcoind` | > 1 block | > 6 blocks |
| `balance - totalLiability` on `PayoutVault` | — | **< 0, ever** |
| Offers stuck in `READY_TO_SUBMIT` | > 10 min | > 60 min |
| BTC offers in `BTC_RESERVED` past expiry | any | > 3 |
| Attestors disagreeing on the same request | any | ≥ 2 in an hour |

`balance < totalLiability` on `PayoutVault` is the one signal that means "stop everything". It
should be structurally impossible; if it fires, treat it as a live exploit and go straight to
[`INCIDENT_RESPONSE.md`](./INCIDENT_RESPONSE.md).

## Weekly

- Reconcile solver books: BTC spent vs ETH reimbursed vs bonds returned vs network fees.
- Diff each attestor's audit log against the others for the same authorization ids. Silent
  divergence in *inputs* is an early warning even when the outputs happened to agree.
- Confirm the `ord` index on each verifier still reproduces known-good inscription locations from
  `data/test-fixtures/`.
- Re-run the cross-language vector suite against deployed contract addresses.

## Routine procedures

### Verifying a stuck offer

```bash
cast call $ESCROW "getOffer(bytes32)" $OFFER_ID --rpc-url $RH_RPC
```

Read `status`:

- `OPEN` past expiry → anyone may call `refundExpired`. Tell the buyer; it is permissionless.
- `OPEN` and the holder signed → check relayer status. Likely fewer than 3 attestations.
- `BTC_APPROVED` with no solver → the quote is unattractive. Nothing is broken; the buyer can let
  it expire and re-offer with more sats.
- `BTC_RESERVED` past `reservationExpiry` → anyone may call `expireReservation`. The bond is
  slashed and the offer returns to `BTC_APPROVED`.
- `SETTLED` / `REFUNDED` → terminal. Nothing to do.

### Attestors disagree

Disagreement is a **feature firing**, not a fault. Do not "fix" it by overriding.

1. Pull each attestor's structured rejection code for that authorization id.
2. Identify the divergent input: usually `ord` index lag, a mempool spend one node saw and others
   did not, or a chain-tip difference.
3. If it is lag, wait. If it is a genuine fact conflict, treat it as an incident.
4. Never ask an operator to sign a fact its own verification rejected. That is the exact behaviour
   the 3-of-5 design exists to prevent.

### Rotating an attestor

Timelocked and atomic through `replaceAttestor`. The set cannot grow or shrink from exactly five.
Every rotation bumps `attestorEpoch`, which invalidates every in-flight signature — announce a
quiet window first.

### Rotating a treasury address

Timelocked `FeeRouter` admin call. Affects only *future* routing; already-credited balances are
untouchable. Percentages cannot be changed by anyone, including this procedure.

## What operators must never do

- Never ask a user for a seed phrase or private key. There is no support scenario that requires it.
- Never sign an attestation for a fact the operator's own node did not independently verify.
- Never point more than one attestor at the same Bitcoin node or Ordinals API. Five instances
  sharing one source is 1-of-1 wearing a five-person costume.
- Never "help" a user by moving their inscription.
- Never modify an offer's terms. It is not possible on chain, and attempting it off chain just
  produces attestations that fail.
- Never deploy to mainnet outside the launch-gate checklist.

## Escalation

| Situation | First action |
|---|---|
| Vault liability exceeds balance | Page everyone. [`INCIDENT_RESPONSE.md`](./INCIDENT_RESPONSE.md). |
| Attestor key suspected compromised | [`KEY_ROTATION.md`](./KEY_ROTATION.md), emergency path. |
| Bitcoin reorg past confirmation depth | [`BITCOIN_REORG_RESPONSE.md`](./BITCOIN_REORG_RESPONSE.md). |
| Solver claims it paid but was not reimbursed | [`SOLVER_OPERATIONS.md`](./SOLVER_OPERATIONS.md). |
| Manifest believed wrong | Stop new offers. The Merkle root is immutable — a wrong manifest means redeploying the registry and every contract downstream of it. |
