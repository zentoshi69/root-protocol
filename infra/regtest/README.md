# Bitcoin regtest harness

> **Status: specification only — the executable `@hoodpups/regtest-harness` package is not yet
> implemented.** The nightly workflow fails explicitly until that package exists. This is a hard
> public-launch gate, not a passing test.

This document specifies end-to-end testing of the full protocol against a real `bitcoind` and a
real `ord` index, with no real value anywhere in the loop.

## Why a real ord index rather than a mock

The most dangerous bugs in this protocol are not in the Solidity. They are in the seam between
Bitcoin and the EVM: txid byte order, satpoint resolution, `scriptPubKey` extraction, BIP-322
binding to the right script. A mocked `ord` reproduces the *assumptions* of whoever wrote the mock,
which is exactly the thing under test.

The completed harness must inscribe for real, move inscriptions for real, and make the verifier
resolve them through a real index.

## Prerequisites

Docker with Compose v2, and Foundry on the host. The published ord Linux release is x86_64-only;
Apple Silicon and other ARM hosts therefore need Docker's `linux/amd64` emulation for this test
stack. The Compose file declares that platform explicitly.

## Running after the harness is implemented

```bash
docker compose -f infra/regtest/docker-compose.yml up -d --wait
pnpm --filter @hoodpups/regtest-harness run e2e
docker compose -f infra/regtest/docker-compose.yml down -v      # -v wipes chain state
```

| Service | Endpoint | Notes |
|---|---|---|
| `bitcoind` | `http://127.0.0.1:18443` | regtest, `txindex=1`, ZMQ on 28332/28333 |
| `ord` | `http://127.0.0.1:8080` | `--index-sats --index-addresses` |
| `anvil` | `http://127.0.0.1:8545` | chain id 31337, 15 funded accounts |

## What the E2E flow covers

1. Mine 101 blocks so the coinbase matures and the wallet is funded.
2. Create a fixture inscription and record its id, satpoint and owning `scriptPubKey`.
3. Deploy all ten contracts to Anvil with a fixture manifest whose Merkle root contains that
   inscription.
4. **EVM path** — buyer creates a `PAID_EVM` offer; the holder signs the canonical BIP-322 message;
   five attestors independently verify against `bitcoind` + `ord`; three sign; a relayer submits;
   assert the mint, the 50/25/25 split, and that the seller can withdraw.
5. **BTC path** — buyer creates a `PAID_BTC` offer; holder approves with a Bitcoin payout script;
   a solver bonds, pays exact sats on regtest, waits for the confirmation policy, collects payment
   attestations and settles; assert the mint, the solver reimbursement and the bond return.
6. **Solver timeout** — a solver reserves and does not pay; assert the bond is slashed and split
   exactly, and that another solver can then reserve.
7. **Ownership change** — move the inscription to a new UTXO on regtest; a watcher submits the
   spend attestation; assert the epoch closes, recurring value routes to `pendingByRoot`, the new
   controller binds a fresh epoch, the pending balance releases to them, and the previous owner's
   already-credited balance is untouched.
8. **Refunds** — an offer nobody fills expires and refunds; a competing offer that loses the race
   becomes immediately refundable.
9. Reconcile: every wei deposited equals refunds plus distributions plus what is still locked.

## Negative cases the harness must also prove

These matter more than the happy path, because the happy path is what everyone tests anyway.

- Signature over a mutated message field is rejected.
- Payout address changed after signing is rejected.
- Inscription moved between signing and verification is rejected.
- A spend of the claimed UTXO sitting in the mempool is rejected.
- A payment one satoshi off the quote is rejected.
- The wrong output index in an otherwise-correct payment transaction is rejected.
- A transaction with several outputs of similar value resolves to the right one, and only that one.
- A txid supplied in the wrong byte order is rejected rather than silently resolving.
- Attestors that disagree never reach quorum.
- A duplicate relayer submission reverts instead of double-settling.
- A payment output reused across two offers is rejected on the second.

## Fixtures

`data/test-fixtures/` holds the fixture manifest and the golden hashing vectors. Everything there
is synthetic and labelled as such.

**Nothing in this directory ever touches mainnet.** The RPC credentials in the compose file are
committed on purpose: they secure a throwaway chain whose coins are worth nothing, and dressing them
up as secrets would encourage someone to reuse a real-looking credential where it matters.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `ord` stuck at height 0 | `bitcoind` needs `-txindex=1`; wipe volumes and restart |
| Inscription not found | `ord` index lags the node. Wait, or check `/status` |
| Wallet has no funds | Mine 101 blocks — coinbase outputs need 100 confirmations |
| BIP-322 verification fails on a script that should work | Check byte order first; it is nearly always byte order |
| Anvil rejects the deploy | Chain id 31337 requires `ALLOW_LOCAL_OVERRIDE=1` |
