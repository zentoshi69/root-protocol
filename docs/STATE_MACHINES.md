# State Machines

Every transition in this document is enforced by a `require`/custom-error check and covered by a
test. Anything not drawn here is an illegal transition.

## 1. Offer lifecycle (`HoodPupOfferEscrow`)

### Kinds

| Kind | Gross | Seller receives | Mints on |
|---|---|---|---|
| `PAID_EVM` | > 0 | ETH credit in `PayoutVault` | ownership quorum |
| `PAID_BTC` | > 0 | exact native BTC from a solver | BTC payment quorum |
| `SELF_CAST` | 0 | nothing | ownership quorum |

### Statuses

`NONE` → `OPEN` → { `BTC_APPROVED` → `BTC_RESERVED` } → `SETTLED` | `REFUNDED`

```
                       createPaid*/createSelfCast
              NONE ──────────────────────────────► OPEN
                                                    │
        ┌───────────────────────────────────────────┤
        │ PAID_EVM / SELF_CAST                      │ PAID_BTC
        │ ownership quorum                          │ ownership quorum
        ▼                                           ▼
     SETTLED  ◄─────────────────────────────  BTC_APPROVED
        ▲                                        │      ▲
        │ BTC payment quorum                     │      │ reservation timeout
        │                              solver bond│      │ (bond slashed)
        │                                        ▼      │
        └─────────────────────────────────  BTC_RESERVED
                                                 │
   OPEN ──────── expiry ──────────► REFUNDED     │
   BTC_APPROVED ─ expiry ─────────► REFUNDED     │
   any non-settled ─ root minted elsewhere ─► REFUNDED
   BTC_RESERVED ── must clear reservation first ─┘
```

### Transition table

| From | Trigger | Guard | To |
|---|---|---|---|
| `NONE` | `createPaidEvmOffer` | member root, recipient ≠ 0, expiry in window, root unminted, `msg.value` > 0 | `OPEN` |
| `NONE` | `createPaidBtcOffer` | as above **and** `sellerSats` > 0 | `OPEN` |
| `NONE` | `createSelfCastOffer` | as above, `msg.value` == 0, `caller == recipient` | `OPEN` |
| `OPEN` | `settlePaidEvm` | purpose `PAID_EVM_MINT`, all terms match exactly, payout mode EVM, unexpired, root unminted | `SETTLED` |
| `OPEN` | `settleSelfCast` | purpose `SELF_CAST`, zero monetary fields, unexpired, root unminted | `SETTLED` |
| `OPEN` | `approvePaidBtc` | purpose `PAID_BTC_MINT`, terms match, payout mode BTC, sats match, unexpired | `BTC_APPROVED` |
| `BTC_APPROVED` | `markBtcReserved` | `BTC_SETTLEMENT_ROLE`, bond posted | `BTC_RESERVED` |
| `BTC_RESERVED` | `finalizeBtcSettlement` | `BTC_SETTLEMENT_ROLE`, exact active solver, payment quorum consumed | `SETTLED` |
| `BTC_RESERVED` | `clearBtcReservation` | `BTC_SETTLEMENT_ROLE`, reservation expired | `BTC_APPROVED` |
| `OPEN` / `BTC_APPROVED` | `refundExpired` | `block.timestamp > expiry` | `REFUNDED` |
| any non-terminal | `refundUnfillable` | root already minted by another offer | `REFUNDED` |
| `SETTLED` | — | terminal | — |
| `REFUNDED` | — | terminal | — |

### Why a buyer cannot cancel early

A Bitcoin holder may be halfway through a cold-wallet signing ceremony that takes minutes or hours.
If a buyer could withdraw at will, they could bait a signature and then pull the offer — obtaining
a valid authorization while paying nothing. The buyer's protection is the expiry, plus immediate
refundability if a competing offer mints the Root first.

### Pause behaviour

`Pausable` blocks `create*` and `settle*`/`approve*`. It **never** blocks `refundExpired`,
`refundUnfillable`, or any `PayoutVault` withdrawal.

## 2. Solver reservation (`BtcSolverSettlement`)

```
   NONE ──── reserve(bond ≥ minimum) ────► ACTIVE
                                            │  │
      settle(payment quorum) ───────────────┘  └──── expireReservation (after expiry)
              ▼                                              ▼
           SETTLED                                        EXPIRED
        bond returned                              bond slashed and split
       via PayoutVault                         buyer / protocol, then re-reservable
```

| From | Trigger | Guard | To |
|---|---|---|---|
| `NONE` | `reserve` | not paused, `msg.value ≥ minimumBondWei`, offer `BTC_APPROVED`, unexpired, unminted, unreserved | `ACTIVE` |
| `ACTIVE` | `settle` | `msg.sender` is the reserved solver, attestation matches offer exactly, reservation unexpired, payment output unconsumed | `SETTLED` |
| `ACTIVE` | `expireReservation` | `block.timestamp > reservationExpiry` | `EXPIRED` |
| `EXPIRED` | `reserve` (a different solver) | offer still `BTC_APPROVED` and unexpired | `ACTIVE` |

**Snapshotting.** `bondWei`, `reservationExpiry` and `buyerSlashBps` are copied into the
`Reservation` at reserve time. Later timelocked config changes therefore cannot retroactively alter
the terms of a reservation already in flight.

**Bond accounting.** At every instant, every wei of every bond is in exactly one of three places:

```
totalBonds == activeReservationLiability + returnedCredits + slashCredits
```

with a slash splitting as `buyerCompensation = bond * buyerSlashBpsSnapshot / 10000` and
`protocolAmount = bond - buyerCompensation`. No dust is left behind, and there is no discretionary
admin forgiveness for individual reservations — that would be a rug lever.

## 3. Root ownership epochs (`RootOwnershipRegistry`)

```
   (no epoch)
        │ recordMintOwnership (escrow, MINT_RECORDER_ROLE)
        │ or bindRootOwner (permissionless, purpose ROOT_BIND)
        ▼
   epoch N, active = true, beneficiary = B
        │
        │ invalidateRoot (permissionless, RootSpendAttestation)
        ▼
   epoch N, active = false
        │  future Root value → pendingByRoot[rootKey]
        │  B keeps everything already credited
        │
        │ bindRootOwner by the new controller C
        ▼
   epoch N+1, active = true, beneficiary = C
        │  pendingByRoot released to C
```

| Transition | Caller | Key guards |
|---|---|---|
| → epoch 1 | escrow (`MINT_RECORDER_ROLE`) | no existing active epoch; facts bound exactly as the oracle accepted them |
| → epoch N+1 | anyone | purpose `ROOT_BIND`, EVM payout mode, beneficiary ≠ 0, root matches, new outpoint **or** currently inactive, Bitcoin height not older than current |
| active → inactive | anyone | attested `previousOutpointHash` == recorded `currentOutpointHash`, root active, spend height ≥ activation height |

Invariants: at most one active beneficiary per root; `epoch` is strictly monotonic; an inactive
root has no active beneficiary; historical `RootEpochInfo` is never rewritten.

## 4. Attestation consumption (`BitcoinOwnershipOracle`)

```
   digest computed off chain by 5 independent attestors
        │
        │ ≥ threshold signatures, recovered signers strictly ascending
        ▼
   verify* (view, permissionless)  ──── no state change, safe to call
        │
        │ consume* (role-gated: OWNERSHIP / PAYMENT / ROOT_SPEND consumer)
        ▼
   digest consumed  ── permanent, irreversible
   (payment path also consumes paymentOutputKey — permanent, global)
```

Every consumption path checks, in order:

1. `deadline >= block.timestamp`
2. `attestorEpoch == registry.attestorEpoch()`
3. `policyVersion == registry.policyVersion()`
4. digest not already consumed
5. `signatures.length >= registry.threshold()`
6. every signature recovers to a current attestor
7. recovered signer addresses **strictly ascending**

Rule 7 does three jobs at once: it rejects duplicate signers for free, it makes the result
deterministic regardless of submission order, and it removes the need for an O(n²) duplicate scan.

Consumption is role-gated specifically so a public caller cannot front-run the escrow and burn a
valid authorization, which would be a cheap griefing attack. The `verify*` and `hash*` views stay
permissionless so anyone — including Bob's wallet before he signs — can check exactly what will
happen.

## 5. Tour lifecycle (`TourEngine`)

```
   NONE ── startTour(owner/approved) ──► ACTIVE ── checkIn(user, after delay) ──► ACTIVE(checked in)
                                           │                                        │
                                           │                            finalizeTour (after expiry)
                                           │                                        ▼
                                           │                                    FINALIZED
                                           │                              miles++, permanent stamp
                                           │
                                           └── cancelInvalidTour ──────────► CANCELLED  (no miles)
                                               owner changed · user role reset · no check-in
```

| Transition | Guards |
|---|---|
| `NONE` → `ACTIVE` | caller owns or is approved; `user` ≠ 0 and ≠ owner; no active tour; duration in `[min, max]`; recipient not already credited this token+season |
| check-in | caller is the current ERC-4907 user; tour active; `≥ minimumCheckInDelay` after start; once only |
| `ACTIVE` → `FINALIZED` | expired; a check-in exists; current owner still == `ownerAtStart`; user role untampered; recipient still unused this season |
| `ACTIVE` → `CANCELLED` | any of the above fails — cleanup with **no** miles |

Anti-farm boundaries: one credited recipient per token per season; a minimum duration; a delayed
check-in; no credit for a raw ERC-721 transfer; no credit when the owner changes mid-tour; no
credit when the recipient is the owner. These stop simple repeat loops. They do **not** prove
unique humanity, and the contract makes no such claim — any stronger Sybil score belongs off chain
and must be labelled heuristic.

## 6. Relayer status model (off chain, surfaced in the UI)

```
PROOF_RECEIVED → VERIFYING → ATTESTATIONS_1_OF_3 → ATTESTATIONS_2_OF_3
   → READY_TO_SUBMIT → SUBMITTED → CONFIRMED
                    ↘ REJECTED   (a verifier returned a structured rejection code)
                    ↘ EXPIRED    (offer or attestation deadline passed)
```

The relayer requires the threshold of **byte-identical** facts. Three individually valid signatures
over three *different* fact sets is a rejection, not a quorum.
