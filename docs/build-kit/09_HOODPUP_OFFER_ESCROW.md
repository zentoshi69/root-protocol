# CODEX CONTRACT PROMPT 09 — HOODPUP OFFER ESCROW

Implement the primary HoodPups offer, escrow, ownership-approval, mint, and refund state machine.

## Contract

Create:

```text
contracts/src/HoodPupOfferEscrow.sol
```

Dependencies:

- `PuppetCollectionRegistry`
- `BitcoinOwnershipOracle`
- `HoodPups`
- `FeeRouter`
- `PayoutVault`
- `RootOwnershipRegistry`
- shared types/hashing/interfaces
- OpenZeppelin `AccessControl`, `Pausable`, and `ReentrancyGuard`

Non-upgradeable.

## Constructor configuration

Accept and validate:

```text
admin
collectionRegistry
ownershipOracle
hoodPups
feeRouter
payoutVault
rootOwnershipRegistry
minimumOfferDuration
maximumOfferDuration
```

Use a per-buyer nonce to derive unique offer IDs:

```text
offerId = keccak256(abi.encode(block.chainid, address(this), buyer, buyerNonce))
```

## Offer creation

Implement:

```text
createPaidEvmOffer(RootId root, address recipient, uint64 expiry, bytes32[] proof) payable
createPaidBtcOffer(RootId root, address recipient, uint64 sellerSats, uint64 expiry, bytes32[] proof) payable
createSelfCastOffer(RootId root, address recipient, uint64 expiry, bytes32[] proof)
```

Rules:

- root must be in collection registry;
- recipient nonzero;
- expiry inside configured min/max window;
- root not already minted at creation time;
- paid offers require positive `msg.value`;
- BTC offer requires positive `sellerSats`;
- self-cast requires zero value and caller equals recipient unless a separately signed EVM meta-authorization is implemented;
- calculate and store exact 50/25/25 amounts at creation;
- compute and store immutable `termsHash` over every fixed term;
- multiple competing offers for one root are allowed;
- buyer cannot cancel early.

The terms hash must bind at least:

```text
offerId
kind
rootKey
buyer
recipient
grossWei
sellerWei
sellerSats
expiry
chainId
escrow address
```

Expose a pure/view helper and mirror it in the SDK.

## EVM settlement

Implement:

```text
settlePaidEvm(
    bytes32 offerId,
    OwnershipAttestation attestation,
    bytes[] signatures,
    bytes32[] collectionProof
)
```

Validate exact equality between stored terms and attested fields:

- purpose is `PAID_EVM_MINT`;
- context is offer ID;
- root, buyer, recipient, gross, seller amount, and terms hash match;
- payout mode EVM;
- nonzero signed EVM payout;
- offer open and unexpired;
- root not minted.

Consume attestation through oracle. Then, using checks-effects-interactions and `nonReentrant`:

1. mark offer settled;
2. mint HoodPup to recipient;
3. record Root ownership/beneficiary from the accepted attestation;
4. route the entire gross amount through FeeRouter to the signed EVM payout, Puppet treasury, and protocol.

All steps must be atomic.

## Self-cast settlement

Implement the same path with purpose `SELF_CAST`, zero monetary fields, no payout, and no FeeRouter call. Record the chosen Root beneficiary only if the self-cast attestation explicitly contains a nonzero EVM beneficiary under a clearly defined field model; otherwise require a separate Root bind after mint. Choose one safe model and document it.

## BTC ownership approval

Implement:

```text
approvePaidBtc(
    bytes32 offerId,
    OwnershipAttestation attestation,
    bytes[] signatures,
    bytes32[] collectionProof
)
```

Validate:

- purpose `PAID_BTC_MINT`;
- all stored offer terms match;
- payout mode BTC;
- exact seller sats match offer;
- exact BTC payout script hash is nonzero;
- EVM payout is zero;
- offer open and unexpired;
- root not minted.

Consume attestation, store ownership digest and BTC payout script hash, record the current root ownership beneficiary only if an EVM beneficiary is explicitly and safely represented elsewhere, then transition to `BTC_APPROVED`.

Do not mint or distribute ETH yet.

## Authorized BTC hooks

Create a narrow `BTC_SETTLEMENT_ROLE` used only by `BtcSolverSettlement`:

```text
markBtcReserved(offerId, solver, reservationExpiry)
clearBtcReservation(offerId)
finalizeBtcSettlement(offerId, solver, paymentDigest)
```

`finalizeBtcSettlement` must:

- require status `BTC_RESERVED`;
- require exact active solver;
- mark settled;
- mint HoodPup;
- route seller share to solver and other shares to treasuries;
- never pay Bob in ETH, because Bob was paid BTC off-chain;
- be atomic.

## Refunds

Implement:

```text
refundExpired(bytes32 offerId)
refundUnfillable(bytes32 offerId)
```

Rules:

- only buyer receives refund credit;
- refund through `PayoutVault`, not arbitrary push;
- expired `OPEN` or `BTC_APPROVED` offers are refundable;
- `BTC_RESERVED` must first have its reservation expired/cleared by the solver contract;
- any non-settled paid offer is refundable immediately if the root was minted by another offer;
- self-cast has no money to refund but may move to `REFUNDED` for clean state;
- settled/refunded offers cannot transition again.

## Pause behavior

Pause new offer creation and new settlements. Refunds must remain available. Do not pause HoodPup transfers or PayoutVault withdrawals.

## Events

Emit complete lifecycle events without leaking unnecessary raw BIP proof data:

- OfferCreated
- OwnershipApproved
- BtcOfferApproved
- BtcReserved
- BtcReservationCleared
- OfferSettled
- OfferRefunded

## Tests and invariants

Cover every state transition, illegal transition, expiry boundary, competing offer, exact attestation field match, payout address binding, root uniqueness, atomic failure, pause/refund behavior, and reentrancy.

Stateful invariants:

- total refundable escrow plus settled distribution never exceeds deposits;
- no offer settles twice;
- no settled offer refunds;
- no BTC offer mints before payment finalization;
- one root mints once across competing offers;
- escrow has no unaccounted ETH after settlement/refund crediting.

Run format, build, unit tests, fuzz tests, invariant tests, and static analysis. Return the implemented state-transition table.
