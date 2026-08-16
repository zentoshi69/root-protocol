# CODEX MASTER PROMPT — INTEGRATION, INVARIANTS, SECURITY, AND DEPLOYMENT

Treat the existing HoodPups implementation as pre-audit production code. Perform a full integration and security-hardening pass. Do not deploy mainnet.

## First actions

1. Inspect every contract, role, constructor, external call, state transition, and off-chain signature schema.
2. Reconcile actual code against `docs/ARCHITECTURE.md` and `docs/STATE_MACHINES.md`.
3. Produce `docs/SECURITY_REVIEW.md` with severity-ranked findings before changing code.
4. Fix critical/high issues, add regression tests, then rerun the review.

## Required Foundry coverage

Create handler-based invariant suites spanning all core contracts.

Mandatory invariants:

```text
I1  One rootKey mints at most one HoodPup.
I2  One offer settles at most once.
I3  One attestation digest is consumed at most once.
I4  One Bitcoin txid:vout settles at most one BTC offer.
I5  seller + Puppet treasury + protocol equals gross exactly.
I6  PayoutVault balance is never below total liabilities.
I7  Escrow refunds plus distributions never exceed deposits.
I8  No admin can seize user claimable balances.
I9  No BTC HoodPup mints before a valid payment attestation.
I10 Solver reimbursement only reaches the active attested solver.
I11 EVM seller credit only reaches the address signed by the Bitcoin owner.
I12 Pausing does not block refunds or withdrawals.
I13 Expired, stale-epoch, stale-policy, wrong-domain, duplicate, unsorted, and insufficient signatures never consume.
I14 Root invalidation stops future direct recurring credits to the old beneficiary.
I15 HoodPups transfer clears ERC-4907 user state.
I16 Tour miles increments only after one valid finalized check-in tuple.
I17 No core routing contract retains unaccounted ETH after a successful operation.
```

Use large stateful run counts in CI nightly and smaller deterministic counts in pull requests.

## Static and differential analysis

Configure and run available tools such as:

- Slither;
- Foundry lint/format/build;
- mutation testing where practical;
- gas snapshots;
- ABI/storage-layout diffing;
- dependency vulnerability audit;
- secret scanning.

Do not suppress findings without a written reason.

## Signature and hashing audit

Create a cross-language vector corpus proving identical results across:

- Solidity;
- protocol SDK;
- Bitcoin verifier;
- attestor;
- relayer.

Vectors must cover:

- root key;
- outpoint hash;
- script hash;
- offer terms hash;
- all EIP-712 digests;
- canonical BIP-322 message bytes;
- proof hash;
- payment output key.

Add CI that fails on any divergence.

## Bitcoin regtest E2E

Automate:

1. start bitcoind and ord;
2. mine funds;
3. create a fixture inscription;
4. create a HoodPup offer;
5. sign and verify BIP-322 ownership;
6. collect three-of-five attestations;
7. settle EVM payout;
8. repeat with BTC solver payout;
9. move the inscription;
10. attest invalidation;
11. bind new owner epoch;
12. route pending Root fees;
13. confirm all accounting.

## Robinhood Chain testnet E2E

Deploy to chain ID 46630 with test keys only. Verify:

- addresses and bytecode;
- all roles;
- timelock configuration;
- attestor epoch/policy;
- offer lifecycle;
- PayoutVault withdrawal;
- account-abstraction sponsored action if configured;
- event indexing;
- block explorer verification.

## Deployment scripts

Create deterministic, idempotent Foundry scripts for local, testnet, and mainnet configuration. Mainnet script may be generated but not executed.

Deployment must:

1. validate chain ID;
2. validate nonzero real manifest root/hash;
3. deploy contracts in dependency order;
4. grant only required roles;
5. configure three-of-five attestors;
6. configure timelock and guardian;
7. revoke deployer roles;
8. write `deployments/<chainId>.json`;
9. run a post-deploy role/invariant smoke test;
10. fail if any unexpected admin remains.

## Operational runbooks

Create:

- `docs/RUNBOOK.md`
- `docs/INCIDENT_RESPONSE.md`
- `docs/KEY_ROTATION.md`
- `docs/ATTESTOR_POLICY.md`
- `docs/SOLVER_OPERATIONS.md`
- `docs/BITCOIN_REORG_RESPONSE.md`
- `docs/PAUSE_AND_RECOVERY.md`

Cover verifier disagreement, stale ord index, Bitcoin reorg, compromised attestor, compromised relayer, solver timeout, stuck RH transaction, wrong manifest, and payout accounting mismatch.

## Launch gates

Write an executable checklist that blocks production release unless:

- real manifest independently reproduced;
- external audit complete;
- all high findings fixed;
- five independent operators live;
- multisig and timelock live;
- testnet burn-in complete;
- native BTC solver separately approved and enabled;
- monitoring and alerting live;
- bug bounty and disclosure contact published;
- no deployer privilege remains.

## Final output

Return:

- findings and fixes;
- commands run;
- test and invariant counts;
- gas snapshot summary;
- deployment addresses on testnet only;
- unresolved risks;
- explicit `GO`, `NO-GO`, or `GO WITH CONDITIONS` recommendation.

Never call the protocol trustless. Never execute a mainnet deployment.
