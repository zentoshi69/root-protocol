# CODEX CONTRACT PROMPT 10 — NATIVE BTC SOLVER SETTLEMENT

Implement the bonded solver contract that converts a Robinhood Chain ETH seller share into an exact native-BTC payout without a price oracle.

## Contract

Create:

```text
contracts/src/BtcSolverSettlement.sol
```

Dependencies:

- `HoodPupOfferEscrow`
- `BitcoinOwnershipOracle`
- `PayoutVault`
- shared types/interfaces
- OpenZeppelin `AccessControl`, `Pausable`, and `ReentrancyGuard`

Non-upgradeable.

## Trust model

The contract cannot verify Bitcoin consensus directly. It trusts a three-of-five payment attestation that certifies a precise Bitcoin transaction output. The attestors must independently confirm the output exists, pays the exact script and sats, and satisfies the configured confirmation policy.

## Constructor configuration

Accept:

```text
admin
escrow
oracle
payoutVault
minimumBondWei
reservationDuration
buyerSlashBps
protocolSlashRecipient
```

Validate sensible nonzero bounds. `buyerSlashBps` must be at most 10000. Keep values timelock-changeable only if changes cannot affect an already active reservation; snapshot all applicable values into each reservation.

## Reservation state

For each offer, store:

```text
solver
bondWei
reservedAt
reservationExpiry
buyerSlashBpsSnapshot
status
```

A solver may reserve only an escrow offer in `BTC_APPROVED` state.

Implement:

```text
reserve(bytes32 offerId) payable
expireReservation(bytes32 offerId)
settle(
    bytes32 offerId,
    BitcoinPaymentAttestation attestation,
    bytes[] signatures
)
reservationOf(bytes32 offerId)
```

## Reserve

Requirements:

- feature not paused;
- `msg.value >= minimumBondWei`;
- offer is BTC-approved, unexpired, unminted, and not already reserved;
- solver nonzero by definition of caller;
- snapshot bond/slash terms;
- call escrow `markBtcReserved`;
- emit reservation.

Do not let an admin choose a solver.

## Settle

Validate the payment attestation exactly matches:

- context ID equals offer ID;
- ownership digest equals escrow’s stored digest;
- solver equals active reserved solver and `msg.sender` is that solver or a permissionless relayer cannot redirect reimbursement;
- recipient script hash equals Bob’s approved script hash;
- amount sats equals offer’s exact seller sats;
- attestation deadline valid;
- reservation not expired;
- the snapshotted Root-wide reservation is still live; it may extend beyond offer expiry up to the shared 30-day cap;
- exact payment output has not been consumed.

Consume the payment attestation through the oracle. Then atomically:

1. call escrow `finalizeBtcSettlement`, which mints and routes seller share to the solver;
2. mark reservation settled;
3. credit the solver bond back through PayoutVault;
4. emit txid, vout, sats, script hash, and payment digest.

Never reimburse a solver before successful oracle consumption and HoodPup finalization.

## Expiry and slashing

Anyone may expire a reservation after `reservationExpiry` if not settled.

Atomically:

1. mark reservation expired;
2. call escrow `clearBtcReservation`, returning offer to `BTC_APPROVED` if still valid;
3. calculate slash from snapshotted bond;
4. credit buyer compensation according to snapshot;
5. credit any configured remainder to solver or protocol according to explicit constructor policy;
6. preserve exact conservation.

Prefer a simple policy:

```text
buyer compensation = bond * buyerSlashBps / 10000
protocol amount = bond - buyer compensation
```

If that policy is too punitive for delayed Bitcoin confirmations, configure a long reservation duration and document it. Do not add discretionary admin forgiveness for individual reservations.

## No oracle pricing

The contract must never read a BTC/ETH oracle. `sellerSats` and `sellerWei` were fixed in the offer and accepted by Bob and the solver. The solver’s spread is the market mechanism.

## Pause behavior

Pause new reservations. Never block settlement of a reserved offer whose solver may already have
paid BTC, reservation expiry, or terminal bond credits. Ordinary ownership consumption, ordinary
minting and new vault credits may pause independently; the terminal BTC path must remain live
through those pauses.

## Tests and invariants

Cover:

- reserve success;
- insufficient bond;
- duplicate reservation;
- wrong offer status;
- wrong solver;
- wrong ownership digest;
- wrong script hash;
- wrong sats;
- reused payment output;
- stale attestor epoch/policy;
- settlement before/after expiry;
- bond return;
- timeout slashing conservation;
- re-reservation after timeout;
- root minted by another path;
- pause behavior;
- atomic rollback if escrow finalization fails;
- stateful invariant that every bond is exactly in active reservation liability, returned credit, or slash credit;
- no BTC-mode mint without one consumed unique payment output.

Run format, build, unit tests, fuzz tests, invariant tests, and static analysis. Return the exact solver state machine and bond accounting equation.
