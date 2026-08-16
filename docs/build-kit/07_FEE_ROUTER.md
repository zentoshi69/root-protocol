# CODEX CONTRACT PROMPT 07 — FEE ROUTER

Implement the immutable HoodPups economic split and route all ETH into `PayoutVault` without retaining funds.

## Contract

Create:

```text
contracts/src/FeeRouter.sol
```

Dependencies:

- `PayoutVault`
- `RootOwnershipRegistry`
- shared interfaces/types
- OpenZeppelin `AccessControl`

Non-upgradeable.

## Immutable percentages

Hardcode:

```text
SELLER_BPS = 5000
PUPPET_TREASURY_BPS = 2500
PROTOCOL_BPS = 2500
BPS_DENOMINATOR = 10000
```

Do not add a setter.

Quote logic:

```text
seller = gross * 5000 / 10000
treasury = gross * 2500 / 10000
protocol = gross - seller - treasury
```

This ensures exact conservation despite rounding.

## Destinations

Constructor:

```text
address admin
IPayoutVault payoutVault
IRootOwnershipRegistry rootRegistry
address puppetTreasury
address protocolTreasury
```

Reject zeros.

Treasury addresses may be updated only through timelocked admin functions. Percentages cannot change.

## Roles

Use `ROUTER_CALLER_ROLE` for protocol contracts allowed to route settlement or activity fees.

## Functions

Implement:

```text
quote(uint256 gross) -> seller, puppetTreasuryAmount, protocolAmount
routeMintEvm(bytes32 rootKey, address seller, uint256 gross) payable
routeMintBtc(bytes32 rootKey, address solver, uint256 gross) payable
routeRecurring(bytes32 rootKey, uint256 gross) payable
```

All functions require `msg.value == gross` and an authorized caller.

### EVM mint

Credit seller, Puppet treasury, and protocol treasury through one `PayoutVault.creditBatch` call.

### BTC mint

Credit the seller share to the active solver, because Bob has already received native BTC. Credit treasury and protocol normally.

### Recurring Root fee

Use the same 50/25/25 split unless a separate activity schedule is explicitly added later. For the 50% Root share:

- if `RootOwnershipRegistry` reports an active beneficiary, credit it;
- otherwise credit `pendingByRoot[rootKey]`.

Treasury and protocol always receive their shares.

## ETH handling

- Router should end every successful call with zero retained ETH.
- Reject raw `receive()` calls.
- Do not add generic owner withdrawal.
- If forced ETH is possible, provide a narrowly scoped timelocked excess sweep that cannot touch in-flight call value, or document why no sweep is needed.

## Events

Emit gross and all three split amounts, root key, route type, and actual beneficiary/solver.

## Tests and invariants

Cover:

- exact split for zero, one wei, tiny values, odd values, and large fuzzed values;
- conservation `seller + treasury + protocol == gross`;
- EVM mint route;
- BTC solver route;
- recurring active beneficiary;
- recurring inactive Root pending credit;
- wrong `msg.value`;
- unauthorized caller;
- zero recipient updates;
- timelocked recipient update simulation;
- router balance zero after successful routing;
- percentages cannot change.

Run format, build, tests, fuzzing, and static analysis. Return a table of split examples in the final summary.
