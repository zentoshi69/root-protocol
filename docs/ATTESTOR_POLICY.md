# Attestor Policy

Binding rules for anyone operating one of the five verifier instances. Breaking a rule here breaks
the protocol's only real security assumption.

## The independence requirement

Three of five signatures authorize a Bitcoin fact. That threshold is meaningful **only** if the
five are genuinely independent. Each operator must run its own:

- Bitcoin Core node (fully validating, not a pruned SPV shortcut, not someone else's RPC)
- `ord` indexer, synced against *that* node
- database and audit log
- EVM signing key, in its own HSM/KMS
- network endpoint
- organisation, on infrastructure it controls

If all five query the same public Ordinals API, the system's real security is 1-of-1 wearing a
five-person costume. **Deployment is gated on five genuinely independent operators being live.**

Operators must publish enough about their infrastructure (cloud region, node version, `ord`
version) that a third party can audit for correlated failure domains. Two operators in the same
region on the same provider is a finding worth disclosing, not hiding.

## What an attestor must verify, itself, every time

No step may be skipped, delegated, or cached from another operator's answer.

### Ownership

1. Parse the root id and outpoint with the project's single canonical byte-order implementation.
   Display order everywhere. Never hand-roll this.
2. Confirm the root is in the canonical manifest and reproduce its Merkle proof.
3. `ord /inscription/<id>` — read the current satpoint and containing output.
4. `ord /output/<outpoint>` — confirm the output actually contains that exact inscription.
5. Query Bitcoin Core for the same transaction and output. Confirm it is **unspent**.
6. Confirm chain tip and that the containing transaction meets the confirmation policy.
7. Check the mempool for any transaction spending the claimed UTXO. A pending spend is a rejection.
8. Extract the exact raw `scriptPubKey` bytes — bytes, never a decoded address string.
9. Verify the BIP-322 signature against the exact canonical message and that exact script.
10. Fetch the offer from Robinhood Chain **directly** and compare every signed term against it.
11. Recompute `rootKey`, `offerTermsHash`, `outpointHash`, `scriptHash`, `bip322ProofHash`.
12. Emit a typed fact set, or a structured rejection code. Never a bare boolean.

### Payment

1. Confirm the transaction exists and meets the confirmation policy — burial depth, not mempool
   presence.
2. Confirm the exact output index pays the exact `recipientScriptHash`.
3. Confirm the exact satoshi value. Not "at least". Exactly.
4. Confirm no conflicting spend or RBF replacement is in flight.
5. Confirm the payment output has not already been consumed on chain.
6. Bind the solver address from the offer's active reservation, read from chain.

### Root spend

1. Confirm the previously recorded outpoint was in fact spent.
2. Confirm the spending transaction meets the confirmation policy.
3. Record the spending txid and the block that contains it.

## Hard prohibitions

- **Never sign a digest supplied by a requester.** The attestor computes the digest itself, from
  facts it verified itself. Blind signing turns a 3-of-5 quorum into a 0-of-5.
- **Never accept a public Ordinals API as the source of truth.** It may be used as a cross-check
  that raises an alarm on disagreement — never as the input to a signature.
- **Never request, receive, log, transmit or store a seed phrase or private key.** The user signs
  locally, in their own wallet or hardware device. There is no support scenario that needs more.
- **Never call a signature valid because a wallet library returned `true`.** Bind it to the exact
  script and the exact outpoint independently.
- **Never guess at an unsupported script type.** Reject it. A rejected claim is a support ticket; a
  wrongly accepted one is a stolen mint.
- **Never sign a fact another operator asserted.** If you did not verify it, you do not sign it.
- **Never infer a field.** Every field in an attestation must be explicitly bound to something the
  operator observed. If a field was inferred, do not sign.

## Confirmation policy

Version-controlled and bound into every attestation as `policyVersion`, so a signature produced
under one policy can never be counted under another.

| Fact | Minimum confirmations | Reasoning |
|---|---|---|
| Inscription location (ownership) | 1 | The UTXO must simply exist and be unspent; a reorg that undoes it also undoes the ownership claim, and the short attestation deadline bounds exposure. |
| BTC payment to seller | 3 (mainnet) | Real money is being reimbursed. Depth beats speed. |
| Root spend (invalidation) | 3 | Deactivating an epoch on a reorged spend would wrongly strip a live owner. |
| regtest / testnet | 1 | Test networks. |

Raising the payment threshold reduces reorg risk and increases the reservation duration a solver
needs. Change both together, or solvers will time out while their payments are still confirming.

## Supported script types

Support only what the test suite proves.

| Type | Status |
|---|---|
| P2TR (`OP_1 <32-byte>`) | supported — the Bitcoin Puppets case |
| P2WPKH | supported |
| P2WSH | supported only with passing vectors for the specific script |
| P2PKH / P2SH-P2WPKH | supported where BIP-322 vectors pass |
| Bare multisig, timelocked, exotic | **rejected** |

Adding a type requires: passing official BIP-322 vectors, project golden vectors, a wallet
compatibility matrix, and a `policyVersion` bump.

## Audit log

Immutable, append-only, per request:

- correlation id, authorization id, timestamp
- every raw input (message, proof, declared variant, claimed outpoint)
- Bitcoin node height and tip hash at verification time
- `ord` index height at verification time
- every intermediate hash recomputed
- the decision, and on rejection the structured code
- the EIP-712 digest and the signature, if signed

Retain for at least two years. This log is what makes a false-attestation post-mortem possible; an
operator that cannot produce it cannot be exonerated.

## Health endpoint

`GET /health` must expose, unauthenticated:

```json
{
  "ok": true,
  "attestorAddress": "0x...",
  "epoch": 1,
  "policyVersion": 1,
  "bitcoinHeight": 900000,
  "bitcoinTipHash": "0000...",
  "ordIndexHeight": 900000,
  "rhBlock": 123456,
  "lastAttestationAt": "2026-01-01T00:00:00Z"
}
```

Divergence between operators is the earliest signal that something is wrong. Making it public makes
it everyone's early warning, not just the operator's.

## Rejection codes

Structured and stable, so a user can be told *why*:

```
ROOT_NOT_IN_MANIFEST        INSCRIPTION_NOT_AT_CLAIMED_OUTPOINT
OUTPOINT_SPENT              MEMPOOL_SPEND_DETECTED
INSUFFICIENT_CONFIRMATIONS  BIP322_INVALID
BIP322_VARIANT_UNSUPPORTED  SCRIPT_TYPE_UNSUPPORTED
OFFER_TERMS_MISMATCH        OFFER_EXPIRED
ROOT_ALREADY_MINTED         PAYOUT_SHAPE_INVALID
STALE_ATTESTOR_EPOCH        STALE_POLICY_VERSION
PAYMENT_OUTPUT_CONSUMED     PAYMENT_AMOUNT_MISMATCH
PAYMENT_SCRIPT_MISMATCH     NODE_UNAVAILABLE
ORD_INDEX_LAGGING           INTERNAL_ERROR
```

`NODE_UNAVAILABLE` and `ORD_INDEX_LAGGING` are honest "I don't know" answers. An operator that
cannot verify must say so rather than defer to the others — a quorum of four honest operators and
one that guesses is worse than a quorum of four.
