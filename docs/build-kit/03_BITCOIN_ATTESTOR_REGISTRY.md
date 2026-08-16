# CODEX CONTRACT PROMPT 03 — BITCOIN ATTESTOR REGISTRY

Implement the verifier membership and quorum registry used by the HoodPups Bitcoin attestation oracle.

## Contract

Create:

```text
contracts/src/BitcoinAttestorRegistry.sol
```

Use OpenZeppelin 5.x `AccessControl` and `EnumerableSet` where appropriate. Do not make this contract upgradeable.

## Required state

- active attestor address set;
- `uint64 attestorEpoch`, starting at 1;
- `uint8 threshold`;
- `uint32 policyVersion`, starting at 1;
- maximum attestor count of 32;
- minimum production threshold of 3;
- minimum production attestor count of 5.

For tests, use a dedicated mock rather than weakening production constraints.

## Constructor

Accept:

```text
address admin
address[] initialAttestors
uint8 initialThreshold
uint32 initialPolicyVersion
```

Validate:

- nonzero admin;
- no zero attestor;
- no duplicate attestor;
- count between 5 and 32;
- threshold at least 3 and at most count;
- nonzero policy version.

## Administrative behavior

Expose timelock-admin functions:

- `addAttestor(address)`;
- `removeAttestor(address)`;
- `replaceAttestor(address old, address replacement)` atomically;
- `setThreshold(uint8)`;
- `setPolicyVersion(uint32)`.

Every membership or threshold change increments `attestorEpoch` exactly once. A policy-version-only change may either increment epoch or use its own event, but choose one model and document it; prefer incrementing epoch so all stale signatures fail immediately.

Never allow a mutation that leaves threshold greater than count or count below five.

Expose views:

```text
isAttestor(address)
attestorCount()
attestorAt(uint256)
attestors()
threshold()
attestorEpoch()
policyVersion()
```

## Events and errors

Use explicit custom errors and events for every mutation, including old/new epoch, old/new threshold, and old/new policy version.

## Governance

The deployment script must assign `DEFAULT_ADMIN_ROLE` to a TimelockController and revoke it from the deployer. Do not bake a single EOA owner into production scripts.

## Tests

Cover:

- constructor validation;
- duplicate rejection;
- add/remove/replace;
- epoch increments exactly once;
- stale epoch behavior via a mock oracle integration;
- threshold safety;
- unauthorized mutations;
- maximum count;
- deployer role revocation simulation.

Run format, build, and tests. Return a concise role matrix and mutation table.
