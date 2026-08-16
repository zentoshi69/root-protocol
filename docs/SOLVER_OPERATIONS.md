# Solver Operations

A solver fronts native BTC to a Bitcoin Puppet holder and is reimbursed in ETH from the buyer's
escrow. Solvers are independent market participants; the protocol grants them no privileges and
owes them nothing beyond what the contract enforces.

> Native BTC settlement is **feature-flagged off in production** until operational and legal review
> is complete. These procedures apply to regtest and testnet today.

## The economics

An offer fixes two independent numbers at creation:

- `sellerSats` — exactly what Bob receives on Bitcoin
- `sellerWei` — exactly what the solver is reimbursed on Robinhood Chain

**There is no price oracle.** The solver's profit is:

```
profit = sellerWei (in whatever unit you value it)
       - cost of acquiring sellerSats
       - Bitcoin network fee
       - Robinhood Chain gas
       - the opportunity cost of the bond for the reservation window
```

If that is negative, do not reserve. Nobody is obliged to fill an offer, and an unattractive quote
simply expires and is refunded. Removing the oracle removes oracle manipulation, price disputes,
slippage arguments and "the chart moved while I was signing" from the settlement path — the price
of that is that quotes can go stale, and that cost lands on the buyer, not the protocol.

## Lifecycle

```
watch BTC_APPROVED offers
   → evaluate quote against your own spread policy
   → reserve(offerId) with a bond
   → build and broadcast a Bitcoin tx paying exactly sellerSats to exactly the approved script
   → wait for the confirmation policy
   → request payment attestations from the five operators
   → settle(offerId, attestation, signatures)
   → receive sellerWei + bond back, both as PayoutVault credits
```

## Reserving

```bash
cast send $SOLVER "reserve(bytes32)" $OFFER_ID --value $BOND_WEI --rpc-url $RH_RPC
```

Before reserving, verify **yourself**:

- offer status is `BTC_APPROVED`
- the offer's own expiry leaves room for the full confirmation policy
- `sellerSats` and the approved `btcPayoutScriptHash` are what you intend to pay
- the Root is not already minted
- your bond meets `minimumBondWei`

The reservation snapshots `bondWei`, `reservationExpiry` and `buyerSlashBps`. Later timelocked
config changes cannot retroactively alter a reservation already in flight — check the snapshot, not
the current config, when reasoning about your exposure.

## Paying

Non-negotiable rules:

1. **Exactly** `sellerSats`. Not one sat more, not one less. The attestation binds the exact value
   and the escrow re-checks it.
2. **Exactly** the approved script. Verifiers compare the raw `scriptPubKey` hash, not an address
   string.
3. From a **separate operational wallet**. Never an inscription wallet, never a user's wallet.
4. Fee-bump conservatively. An RBF replacement that changes the output invalidates the payment;
   verifiers check for conflicting spends.
5. Record `txid:vout` immediately — it is the primary key for everything that follows.

Production signing should be PSBT-based with hardware or HSM keys. Never hardcode a seed in an
environment file.

## Settling

```bash
cast send $SOLVER "settle(bytes32,(...),bytes[])" $OFFER_ID $ATTESTATION $SIGNATURES --rpc-url $RH_RPC
```

`msg.sender` **must** be the reserved solver. This is what stops a permissionless relayer from
redirecting your reimbursement — but it also means you cannot delegate the final call. Keep the
reserving key available for the whole reservation window.

On success, in one atomic transaction: the HoodPup mints, `sellerWei` credits to you, both
treasuries are credited, and your bond returns — all as `PayoutVault` credits. Withdraw separately.

## Timeouts and slashing

After `reservationExpiry`, **anyone** may call `expireReservation`. Your snapshotted bond splits:

```
buyerCompensation = bond * buyerSlashBpsSnapshot / 10000
protocolAmount    = bond - buyerCompensation
```

There is no discretionary admin forgiveness for individual reservations. Adding one would be a rug
lever, and a protocol whose operators can selectively forgive is a protocol whose operators can
selectively punish.

**The failure mode to avoid:** paying BTC, then being expired before your payment confirms. You
lose the bond *and* the BTC. Prevent it:

- Confirm `reservationDuration` comfortably exceeds the payment confirmation policy before
  reserving. If it does not, do not reserve, and report the misconfiguration.
- Fee your transaction to confirm well inside the window.
- Do not reserve when the mempool is congested enough to threaten the window.
- Monitor your own reservations and settle the moment the attestation is available.

If you are expired despite a confirmed on-time payment, that is a protocol configuration bug. Open
an incident with the txid, the confirmation height and the reservation snapshot.

## Reconciliation

Per settled offer, record: offer id · BTC txid:vout · sats paid · Bitcoin fee · `sellerWei`
received · bond posted and returned · RH gas · realised spread.

Weekly, assert:

```
sum(bonds posted) == sum(bonds returned) + sum(bonds slashed) + sum(bonds locked in active reservations)
```

That mirrors the on-chain bond invariant. A mismatch means either your books are wrong or the
contract is — check the contract's own invariant test before assuming it is you.

## Risks you carry

| Risk | Mitigation |
|---|---|
| BTC price moves against you between reserve and settle | Short reservations; price the spread for volatility |
| Payment reorged after settlement | You keep the ETH; the seller lost the BTC. See [`BITCOIN_REORG_RESPONSE.md`](./BITCOIN_REORG_RESPONSE.md) |
| Expired before confirmation | Check `reservationDuration` vs confirmation policy **before** reserving |
| Attestors unavailable | You paid BTC and cannot settle. Escalate; the reservation window is your deadline |
| Offer expires mid-reservation | Verify the offer's own expiry leaves room before you reserve |
| Bond opportunity cost | Priced into your spread |

The protocol deliberately does not insure any of these. A solver is a market maker taking a
position, not a service provider with a support contract.

## What a solver can never do

- Touch the seller's inscription or inscription wallet
- Alter offer terms
- Be chosen by an admin — reservation is first-come, permissionless
- Be reimbursed without a 3-of-5 payment attestation naming the exact `txid:vout`
- Reuse one Bitcoin payment across two offers; `paymentOutputKey` is consumed globally and
  permanently
- Have its reimbursement redirected — `settle` requires `msg.sender` to be the reserved solver
