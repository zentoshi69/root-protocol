# HoodPups Rooted Settlement Protocol — Architecture

> **This is not a trustless Bitcoin bridge.** A 3-of-5 quorum of independent verifier operators
> asserts Bitcoin facts to a Robinhood Chain contract. That quorum can never move, spend or
> encumber anyone's Bitcoin Puppet — but a dishonest quorum can assert a false ownership or
> payment fact. Everything below is written on that assumption. See
> [`TRUST_ASSUMPTIONS.md`](./TRUST_ASSUMPTIONS.md).

## 1. The problem

Alice, on Robinhood Chain, wants a HoodPup derived from Bitcoin Puppet #123. Bob owns that Puppet
on Bitcoin, in a cold wallet, and has no intention of moving it, bridging it, or trusting a
custodian with it.

A Robinhood Chain contract cannot read Bitcoin. It cannot parse an Ordinals index, check a UTXO
set, or verify a BIP-322 signature over a Taproot script. So the protocol does not ask it to.
Instead it splits the problem into three machines:

```
Bob's Bitcoin wallet
        │  signs one exact message (BIP-322) — the Puppet never moves
        ▼
Bitcoin verifier network  (5 independent operators, each with their own bitcoind + ord)
        │  3 matching EIP-712 attestations
        ▼
Robinhood Chain settlement contracts
        ├── mint HoodPup to Alice
        ├── pay Bob (ETH credit, or native BTC via a bonded solver)
        ├── pay the Bitcoin Puppets ecosystem treasury
        └── pay the protocol
```

The value proposition, stated honestly: **the protocol does not move Puppets across chains. It
moves Robinhood Chain money back to Bitcoin owners.**

## 2. Network assumptions

| | Value |
|---|---|
| Robinhood Chain mainnet | chain ID `4663`, native asset ETH |
| Robinhood Chain testnet | chain ID `46630`, native asset ETH |
| Bitcoin production | mainnet |
| Bitcoin development | regtest |
| Solidity | `0.8.28`, `evm_version = shanghai` |
| Libraries | OpenZeppelin 5.1.0, forge-std 1.9.7, both vendored and pinned |

Robinhood Chain is an EVM-equivalent Arbitrum L2, so ordinary Solidity works and ETH is the native
gas and settlement asset. Deployment scripts refuse unknown chain IDs unless an explicit
local-development override is supplied.

`shanghai` is chosen deliberately over `cancun`: it guarantees `PUSH0` support while avoiding any
dependence on transient storage (`TSTORE`), whose availability varies across Orbit chain ArbOS
versions. Nothing in the protocol needs it.

## 3. Contract topology

```
                      ┌──────────────────────────────┐
                      │  PuppetCollectionRegistry     │  immutable Merkle root over the
                      │  "is this inscription ours?"  │  canonical Puppets manifest
                      └───────────────┬───────────────┘
                                      │
    ┌──────────────────────────┐      │      ┌──────────────────────────────┐
    │ BitcoinAttestorRegistry   │      │      │  5 independent attestors      │
    │ set / threshold / epoch   │◄─────┼──────┤  (off chain, own bitcoind)    │
    └───────────────┬───────────┘      │      └──────────────────────────────┘
                    │                  │
                    ▼                  ▼
            ┌─────────────────────────────────────┐
            │      BitcoinOwnershipOracle          │  verifies SIGNATURES, not Bitcoin.
            │  EIP-712 · 3-of-5 · consume once     │  one digest → one consumption, forever
            └───────┬──────────────────┬───────────┘
                    │                  │
        ownership   │                  │  payment / root-spend
                    ▼                  ▼
    ┌───────────────────────┐   ┌──────────────────────┐   ┌────────────────────────┐
    │ HoodPupOfferEscrow    │◄─▶│ BtcSolverSettlement  │   │ RootOwnershipRegistry  │
    │ offers · mint · refund│   │ bonded native-BTC    │   │ ownership epochs       │
    └───┬───────────┬───────┘   └──────────┬───────────┘   └───────────┬────────────┘
        │           │                      │                           │
        ▼           ▼                      ▼                           │
  ┌──────────┐  ┌───────────┐        ┌──────────┐                      │
  │ HoodPups │  │ FeeRouter │───────▶│PayoutVault│◄─────────────────────┘
  │ ERC-721  │  │ 50/25/25  │        │ pull-pay  │
  │ + 4907   │  │ immutable │        │ + gasless │
  └────┬─────┘  └───────────┘        └──────────┘
       │
       ▼
  ┌────────────┐
  │ TourEngine │  phase two: temporary ERC-4907 use, no ownership transfer
  └────────────┘
```

### What each contract is for

| Contract | Single responsibility |
|---|---|
| `PuppetCollectionRegistry` | Immutable Merkle membership. Answers *"is this inscription in the manifest this deployment committed to?"* and nothing else. |
| `BitcoinAttestorRegistry` | Who the verifiers are, how many must agree, and which epoch/policy version is current. |
| `BitcoinOwnershipOracle` | Turns a 3-of-5 quorum of EIP-712 signatures into a one-time-consumable authorization. Verifies signatures, never Bitcoin. |
| `PayoutVault` | Every ETH obligation the protocol creates, as a pull payment. Includes gasless (ERC-1271-aware) withdrawal. |
| `RootOwnershipRegistry` | Which Bitcoin controller is currently verified for each Root, as monotonic epochs. |
| `FeeRouter` | The immutable 50/25/25 split. Holds no ETH after any call. |
| `HoodPups` | ERC-721 + ERC-4907. One token per Root, forever. |
| `HoodPupOfferEscrow` | The offer lifecycle: create, approve, settle, refund. |
| `BtcSolverSettlement` | Bonded solvers who front native BTC and get reimbursed in ETH. |
| `TourEngine` | Temporary use rights and a miles counter. No token, no cash. |

All ten are **non-upgradeable**. There are no proxies, no initializers, and no `delegatecall`.
Fixing a bug means deploying a new version and migrating, which is a deliberate trade: it removes
the single most valuable target in most protocols — the upgrade key.

## 4. Canonical identity and hashing

Never store a human-readable Bitcoin address string as a security primitive. Address encodings are
network- and format-dependent; raw script bytes are not.

```solidity
struct RootId {
    bytes32 inscriptionTxid;   // reveal txid, BIG-ENDIAN / RPC display order
    uint32  inscriptionIndex;  // the `iN` suffix
}
```

<a name="canonical-byte-order"></a>
### Byte order is a security primitive

Bitcoin displays txids in reverse byte order from how they appear in the wire format. Every
component in this repository uses **display order** (what a block explorer shows), left-padded into
`bytes32`. A component that silently used internal order would compute a different `rootKey` for
the same inscription and either fail closed (best case) or admit a different inscription (worst
case). Cross-language golden vectors in `data/test-fixtures/hashing-vectors.json` exist to make
that divergence impossible to ship.

### The hash family

Defined once in `contracts/src/types/PuppetHashing.sol` and mirrored in
`packages/protocol-sdk` and every attestor:

```
COLLECTION_ID    = keccak256("BITCOIN_PUPPETS_MAINNET_V1")

rootKey          = keccak256(abi.encode(COLLECTION_ID, inscriptionTxid, inscriptionIndex))
collectionLeaf   = keccak256(bytes.concat(rootKey))              // double-hashed leaf
outpointHash     = keccak256(abi.encode(OUTPOINT_DOMAIN,        bitcoinTxid, vout))
paymentOutputKey = keccak256(abi.encode(PAYMENT_OUTPUT_DOMAIN,  bitcoinTxid, vout))
scriptHash       = keccak256(rawScriptPubKeyBytes)
offerId          = keccak256(abi.encode(OFFER_ID_DOMAIN, chainId, escrow, buyer, buyerNonce))
offerTermsHash   = keccak256(abi.encode(OFFER_TERMS_DOMAIN, chainId, escrow, offerId, kind,
                                        rootKey, buyer, recipient, grossWei, sellerWei,
                                        sellerSats, expiry))
```

Three rules, each load-bearing:

1. **`abi.encode`, never `abi.encodePacked`,** for any multi-field identifier. Packed encoding of
   adjacent variable-width fields is ambiguous and collides.
2. **Every family is domain separated.** `outpointHash` and `paymentOutputKey` take the same
   arguments but different domain tags, so an inscription's outpoint can never be replayed as a
   consumed BTC payment output.
3. **Leaves are double-hashed.** `collectionLeaf` hashes the 32-byte `rootKey` again, following
   the OpenZeppelin `StandardMerkleTree` convention. An internal node preimage is 64 bytes and can
   therefore never be presented as a leaf — that is the second-preimage defence.

### Why the attestation structs are flat

Nested EIP-712 structs force every off-chain implementation to reproduce sub-struct hashing, which
is a reliable source of cross-language divergence. All three attestations are flat, value-type-only
structs. Their `encodeData` is built as two concatenated `abi.encode` chunks purely to stay under
the EVM's 16-slot stack limit without enabling via-IR; because every field is a value type
occupying exactly one 32-byte word, the concatenation is byte-identical to a single encode. A test
asserts that equivalence rather than leaving it as a comment.

## 5. The two settlement paths

### 5a. Paid EVM settlement — Bob takes ETH

1. Alice calls `createPaidEvmOffer` with a `RootId`, a recipient, an expiry and a Merkle proof,
   and sends ETH. The escrow stores gross, the exact 50/25/25 split computed at creation, the
   root, buyer, recipient, kind, expiry, and an immutable `termsHash`.
2. Bob picks an EVM payout address and signs **one exact canonical message** with the Bitcoin
   wallet controlling the Puppet, using BIP-322. The message binds the Puppet, the offer, the
   buyer, the payout address, the amount, the Robinhood chain ID, the escrow address, a nonce and
   an expiry — so nobody can lift the signature and redirect the payment.
3. Five verifier instances independently check: collection membership; `ord` reports the
   inscription in the claimed UTXO; Bitcoin Core reports that UTXO unspent; no mempool spend; the
   BIP-322 signature is valid for that output's script; every signed offer term matches the chain;
   the Root has not already minted.
4. Three of five sign the same EIP-712 `OwnershipAttestation`.
5. A relayer submits it and pays the gas. Neither Alice nor Bob needs to send the final tx.
6. The oracle consumes the digest exactly once.
7. Atomically: mark settled → mint the HoodPup to Alice → record the ownership epoch → route the
   full gross through `FeeRouter`.
8. `FeeRouter` credits Bob, the Puppet treasury and the protocol treasury inside `PayoutVault`.
9. Bob withdraws, or signs a gasless withdrawal authorization so a relayer can do it for him —
   which matters, because Bob may hold zero ETH.

### 5b. Native BTC settlement — Bob takes actual Bitcoin

This is the version a Bitcoin holder immediately understands: *Robinhood user pays ETH, Bitcoin
Puppet holder receives BTC.*

**There is no price oracle anywhere in this path.** The offer fixes two independent numbers:
`sellerSats` (exactly what Bob receives) and `sellerWei` (exactly what the solver is reimbursed).
Bob signs the sats figure; a solver either finds the spread attractive or ignores the offer. That
single design choice deletes oracle manipulation, BTC/ETH price disputes, slippage arguments and
"the chart moved while I was signing" from the settlement path.

1. Alice creates a `PAID_BTC` offer and escrows ETH.
2. Bob signs an authorization naming his Bitcoin payout **script hash** and the fixed `sellerSats`.
3. A 3-of-5 ownership attestation moves the offer to `BTC_APPROVED`. **Nothing is minted yet.**
4. A solver posts a bond and reserves the offer, snapshotting the bond and slash terms so later
   governance changes cannot retroactively alter an active reservation.
5. The solver sends exactly `sellerSats` to exactly that script, from its own operational wallet.
6. Verifiers wait for the confirmation policy, then attest the precise `txid:vout`, script hash,
   sat amount, solver and offer.
7. The payment output is marked **globally consumed** — this is what stops one Bitcoin payment
   settling seventeen HoodPups.
8. Atomically: mint → reimburse the solver `sellerWei` → pay both treasuries → return the bond.
9. If the solver times out, anyone may expire the reservation. The snapshotted bond is split
   between buyer compensation and the protocol, and another solver may reserve.

Native BTC settlement is **feature-flagged off in production** until operational and legal review
is complete.

### 5c. Free self-cast

A self-cast is a zero-value `SELF_CAST` offer: zero gross, zero seller amount, buyer and recipient
both the Bitcoin controller's chosen Robinhood address, no payout mode. Exact Root ownership is
still required and the same one-HoodPup-per-Root rule applies. The relayer may sponsor the gas.

## 6. Ownership epochs — what happens when Bob sells

Paying a previous holder forever after they sold the original would be a bug, not a feature.

```
Puppet #123
  Epoch 1 — Bob verified, Bob receives Root-linked value
  Bob sells to Charlie on Bitcoin
  Watcher observes the inscription UTXO being spent → submits a RootSpendAttestation
  Root becomes INACTIVE — future Root value accrues to pendingByRoot[rootKey]
  Charlie signs a fresh ownership proof and names his payout address
  Epoch 2 — Charlie verified, pending balance releases to Charlie
```

Money Bob already earned stays Bob's; only *future* value follows the new owner. The registry
records **attested** state, not live Bitcoin state, so there is a window between the real sale and
the watcher's attestation. Value accrued in that window is recoverable, because it lands in the
Root's pending bucket the moment the epoch closes rather than being paid out to the stale
beneficiary. That window is a real limitation and is documented in
[`TRUST_ASSUMPTIONS.md`](./TRUST_ASSUMPTIONS.md), not hidden.

## 7. Economics

For every paid mint, computed from the gross ETH escrow:

```
seller   = gross * 5000 / 10000     // 50%  — the current Bitcoin Puppet controller
treasury = gross * 2500 / 10000     // 25%  — the Bitcoin Puppets ecosystem treasury
protocol = gross - seller - treasury // 25% — absorbs the rounding remainder
```

Seller first, treasury second, protocol takes the remainder — so
`seller + treasury + protocol == gross` holds exactly for every input, including 1, 2 and 3 wei.
The basis points are compile-time constants with **no setter and no upgrade path**. Only the two
treasury destination addresses are governable, and only through the timelock.

## 8. Why payouts are pull, not push

Naively pushing ETH to Bob is a liveness bug. If Bob's payout address is a contract that reverts on
receive — or just burns more than the forwarded gas — the whole mint transaction fails, and the
Root is permanently unmintable through that offer.

Every obligation is therefore credited inside `PayoutVault`, and ETH moves only when someone
withdraws. The vault's core invariant is `address(this).balance >= totalLiability()`. Pausing may
block new credits; it can never block a withdrawal. No admin function can reduce a user's claimable
balance — there is no such code path, and a test asserts it.

## 9. Off-chain services

Four independently deployable services, described fully in
[`build-kit/12_OFFCHAIN_SERVICES.md`](./build-kit/12_OFFCHAIN_SERVICES.md):

- **`bitcoin-verifier`** — talks to the operator's *own* Bitcoin Core and `ord`. Parses canonical
  ids, checks collection membership, inscription location, unspent state, mempool spends,
  confirmations and the exact script, and verifies BIP-322 only for script types proven by tests.
  Never receives or stores a seed or private key.
- **`attestor`** — one codebase, five independent deployments with separate nodes, databases, keys,
  endpoints and operators. Each instance re-runs the *entire* verification itself and signs only
  the digest it independently computed. A requester can never hand it a digest for blind signing.
  One central API returning a boolean to all five is **not** independence.
- **`relayer`** — collects attestations, requires at least the threshold of *byte-identical* facts,
  rejects mixed facts even when each signature is individually valid, sorts recovered signer
  addresses strictly ascending, simulates, then submits idempotently. It never modifies terms.
- **`btc-solver`** — watches `BTC_APPROVED` offers, applies its own spread policy, bonds, pays
  exact sats from a separate operational wallet, and settles. It never touches Bob's inscription
  wallet.

## 10. Cold wallets

Bob's Puppet never leaves the cold wallet:

```
site builds signing request → Bob scans / downloads it → hardware wallet signs BIP-322
  → Bob returns only the signature → verifiers check it
```

Non-negotiables: never ask for a seed; never ask Bob to import a cold wallet into the app; never
treat a screenshot as proof; never require moving the Puppet. Wallets whose firmware cannot produce
the required proof simply cannot complete a trust-minimised claim until an adapter exists. Saying
so plainly is better than building the protocol on duct tape and Telegram honesty.

## 11. Repository layout

```
contracts/          Foundry workspace — src/, test/{unit,fuzz,invariant,mocks,helpers}/, script/
services/           bitcoin-verifier/ · attestor/ · relayer/ · btc-solver/
packages/           protocol-sdk/ · canonical-message/ · generated-abis/
apps/web/           buyer, holder, payout, root and tour flows
data/               manifest example + test fixtures + cross-language golden vectors
infra/regtest/      bitcoind + ord docker compose and E2E harness
docs/               this file and its siblings
deployments/        <chainId>.json, written by the deploy scripts
```

## 12. What version one deliberately does not have

No token. No stock basket. No market maker. No royalty dependency. No upgrade proxy. No BTC/ETH
oracle. No claim of trustlessness. The protocol has to work and return value to Bitcoin Puppet
owners before any additional financial object is worth discussing.
