# CODEX CONTRACT PROMPT 06 — ROOT OWNERSHIP REGISTRY

Implement attested Bitcoin ownership epochs and the current beneficiary for recurring Root-linked value.

The registry must never claim continuous trustless knowledge of Bitcoin. It records facts accepted from the three-of-five oracle and can be temporarily stale until watcher attestations are submitted.

## Contract

Create:

```text
contracts/src/RootOwnershipRegistry.sol
```

Dependencies:

- `BitcoinOwnershipOracle`
- `PayoutVault`
- shared types/hashing
- OpenZeppelin `AccessControl` and `Pausable`

Non-upgradeable.

## State

For each `rootKey`, store:

```text
uint64 epoch
bool active
bytes32 currentOutpointHash
bytes32 ownerScriptHash
address beneficiary
bytes32 ownershipDigest
bytes32 bip322ProofHash
uint64 verifiedBitcoinHeight
bytes32 lastBitcoinBlockHash
bytes32 invalidatingSpendTxid
```

Maintain historical epoch metadata or emit sufficient events for complete off-chain reconstruction. Prefer a mapping by root and epoch for beneficiary, activation height, and deactivation height if gas is acceptable.

## Activation paths

### Initial activation from mint

The escrow may call a narrow function after consuming a mint ownership attestation:

```text
recordMintOwnership(...)
```

Only `MINT_RECORDER_ROLE` may call. It must bind exactly the root, outpoint, owner script, beneficiary, digest, proof hash, and Bitcoin height already accepted by the oracle.

If no epoch exists, create epoch 1. Do not overwrite a different active owner silently.

### Owner re-verification

Anyone may submit a fresh `OwnershipAttestation` with purpose `ROOT_BIND`, valid signatures, and a collection proof. The registry consumes it through the oracle and starts a new epoch.

Require:

- nonzero beneficiary;
- EVM payout mode for the beneficiary binding;
- root matches;
- new outpoint or previously inactive state;
- fresh authorization ID;
- current root is not being overwritten with an older Bitcoin height.

On successful activation, call `PayoutVault.releaseRootCredit(rootKey, beneficiary)`.

## Invalidation

Anyone may submit a valid `RootSpendAttestation` proving the previously recorded outpoint was spent.

Require:

- attested previous outpoint equals current outpoint;
- root is active;
- spend Bitcoin height is not older than activation height.

Set active false and clear only fields that should not remain live. Preserve historical beneficiary and already credited balances. Future Root-linked fees must route to `pendingByRoot` until a new owner activates.

## Views

Expose:

```text
currentState(rootKey)
currentBeneficiary(rootKey) -> (address beneficiary, bool active, uint64 epoch)
isActive(rootKey)
epochOf(rootKey)
epochInfo(rootKey, epoch)
```

## Security and governance

- No admin function may arbitrarily assign ownership.
- Admin may pause new activations/invalidation consumption only for incident response.
- Pausing must not alter prior state or block PayoutVault withdrawals.
- The only ownership sources are a consumed oracle attestation or the authorized escrow mint recorder.

## Tests

Cover:

- initial mint activation;
- duplicate initial activation rejection;
- fresh owner rebind;
- epoch increment;
- stale Bitcoin height rejection;
- invalidation;
- wrong previous outpoint;
- invalidation replay;
- pending Root credit release to new owner;
- previous owner keeps already credited balance;
- unauthorized mint recorder;
- paused behavior;
- fuzzed epoch transitions;
- invariant that at most one active beneficiary exists per root.

Run format, build, tests, invariants, and static analysis. Document the unavoidable stale-watcher trust window in the final summary.
