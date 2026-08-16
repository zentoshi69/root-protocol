# Historical internal security review

> This document is the pre-audit snapshot from commit `8a52832`. It is retained as review history;
> its test counts and finding set are not the current release record. The later external
> whole-protocol findings and their source/test mapping are tracked in
> [`AUDIT_REMEDIATION.md`](./AUDIT_REMEDIATION.md).

**Scope:** the ten Robinhood Chain contracts, the deployment path, the canonical message format, the
protocol SDK, and the four off-chain services, at commit `8a52832`.

**Status at the time:** internal pre-audit review. This was **not** a substitute for an external
audit, which remains a launch gate in [`DEPLOYMENT.md`](./DEPLOYMENT.md).

**Method:** interface-first construction with the type and hashing layer frozen before any
implementation; per-contract unit, fuzz and handler-based stateful invariant suites; a
no-mocks integration suite that deploys all ten contracts together; cross-language hash parity
enforced in CI; Slither; secret scanning.

**Result at review time:** 836 Solidity tests and 250 TypeScript tests passing. Two genuine defects
found and fixed, both by the integration suite. Details below.

---

## Findings

### H-1 — Pausing `PayoutVault` blocked refunds (invariant I12 violation) · **FIXED**

**Severity:** High — user funds temporarily unreachable during exactly the incident that would make
a user want them back.

`HoodPupOfferEscrow.refundExpired` credited the buyer through `PayoutVault.credit`, which carries
`whenNotPaused`. A guardian pausing vault credits therefore blocked every refund.

This contradicted three separate commitments: the build specification ("refunds and withdrawals must
remain available during an emergency pause"), protocol invariant **I12**, and
[`INCIDENT_RESPONSE.md`](./INCIDENT_RESPONSE.md), which tells users in as many words that they can
still get their money out while the protocol is paused.

**Why 823 existing tests missed it.** Every individual contract behaved correctly in isolation:

- `PayoutVault` correctly makes `credit` pausable and `withdraw` not.
- `HoodPupOfferEscrow` correctly keeps `refundExpired` working through an **escrow** pause.

The violation lives only in the composition. No single-contract suite could express "refund while
the *vault* is paused", because that requires both contracts wired together with a real vault.

**Fix.** `PayoutVault.creditRefund` — `CREDITOR_ROLE`-gated, deliberately **not** pausable. The
reasoning matters more than the code: a refund *releases* an obligation the buyer already holds,
against ETH the escrow is already carrying on their behalf. It is not a new obligation. Blocking it
protects nobody and strands the buyer's own money for the duration of the incident.

An existing escrow test asserted the previous behaviour ("deferred, never lost"). That is a
defensible design — the money was never at risk of loss — but it is not the guarantee the protocol
publishes, so the test was replaced rather than the documentation weakened. A companion test asserts
the pause still blocks non-refund credits, so that making refunds non-pausable did not quietly make
everything non-pausable.

**Regression cover:** `FullFlow.t.sol::test_ExpiredOfferRefundsAndRefundsSurvivePause`,
`HoodPupOfferEscrow.t.sol::test_APausedVaultStillLetsARefundThrough`,
`HoodPupOfferEscrow.t.sol::test_APausedVaultStillBlocksNonRefundCredits`.

---

### H-2 — Deployment granted consumer roles without purpose allowlists · **FIXED**

**Severity:** High — a deployment that passes a role audit and then cannot settle anything.

`BitcoinOwnershipOracle` maintains a per-consumer *purpose* bitmask that **fails closed**: an address
holding `OWNERSHIP_CONSUMER_ROLE` with an empty mask can consume nothing. That separation is a
genuine security improvement — it stops the escrow consuming a `ROOT_INVALIDATE` (which would burn a
Root's ownership epoch) and stops the root registry consuming a `PAID_EVM_MINT` (which would burn a
buyer's settlement).

`DeployLib.grantRoles` granted the roles and never the masks. A deployment would have looked correct
to any role-matrix audit and reverted on its first real settlement with
`PurposeNotPermittedForConsumer`.

**Fix.** Use `grantOwnershipConsumer`, which sets role and mask atomically so the two cannot drift.
`verifyRoles` now asserts the masks *and* the negative separations that make them worth having.

**Regression cover:** the entire `FullFlow.t.sol` suite exercises `DeployLib` directly, so any future
divergence between the deployment path and the contracts fails there rather than on a testnet.

---

### I-1 — `MockOwnershipOracle` uses its own EIP-712 domain · **accepted, documented**

**Severity:** Informational.

The shared mock computes digests under its own domain separator, which does not match the real
oracle's. A suite that obtained a digest from one and verified against the other would silently
fail to reach quorum.

Accepted because the mock exposes its own `hashOwnershipAttestation` and every current consumer uses
it consistently. Documented in the mock's NatSpec. The integration suite uses the **real** oracle
throughout, so the production digest path is covered by something that cannot drift.

---

### I-2 — `MockOwnershipOracle.setNextCallReverts` is sticky, not one-shot · **accepted, documented**

**Severity:** Informational.

A self-clearing flag is impossible: the revert that delivers the failure also rolls back the storage
write that would clear it. Callers must reset it explicitly. Documented in the mock's NatSpec.

---

### I-3 — Golden vectors use synthetic txids and chain 31337 · **by design, gated**

The cross-language corpus deliberately uses structurally valid but fabricated Bitcoin txids. This is
correct — inventing plausible real Bitcoin Puppets inscription ids would be worse than useless — but
it means the vectors prove *consistency*, not *correctness of the manifest*.

The launch gate is unchanged and non-negotiable: the real manifest must be independently sourced and
its Merkle root reproduced by at least two implementations before mainnet.

---

## Controls verified

| Control | Evidence |
|---|---|
| One Root mints at most one HoodPup | Stateful invariant on `rootToToken` injectivity; integration test across competing offers |
| One offer settles at most once | Escrow invariant suite; terminal-status transitions |
| One attestation digest consumed at most once | Oracle unit tests; `FullFlow::test_AnAttestationCannotBeReplayed` |
| One Bitcoin `txid:vout` settles at most one offer | `paymentOutputKey` consumed atomically with the digest |
| Seller payout only reaches the signed address | `FullFlow::test_PayoutAddressIsBoundToTheSignature` — mutating `evmPayout` changes the digest, invalidating the quorum |
| Split conserves exactly | FeeRouter fuzz at 1, 2, 3 wei where three floor divisions would strand dust |
| Vault balance never below liability | Handler-based stateful invariant with ghost sums |
| No admin can seize a user balance | No such code path; asserted by enumerating admin functions |
| Pausing never blocks refunds or withdrawals | **H-1 above** — enforced at this review snapshot; active BTC terminal paths were hardened later |
| Quorum rules | `FullFlow::test_QuorumIsEnforcedEndToEnd` — too few, unsorted, and outsider-contaminated sets all rejected |
| Deployer privilege fully revoked | `DeployLib.assertDeployerRevoked`, asserted in the integration suite |
| Cross-language hash parity | 32 golden vectors, CI-gated, fails the build on drift |
| No key material in the repository | gitleaks + GitGuardian + a bespoke private-key grep in CI |

## Design choices that reduce attack surface

- **Non-upgradeable core.** No proxy, no initializer, no `delegatecall`. There is no upgrade key to
  steal — the most valuable target in most protocols simply does not exist here.
- **Immutable economics.** 50/25/25 floor shares plus exact-conservation remainder compiled in with no setter.
- **Pull payments.** A hostile payout address cannot block a mint.
- **Fail-closed everywhere.** Unknown chain ids, missing manifests, unsupported script types, stale
  epochs, empty purpose masks and unvalidated BIP-322 adapters all reject rather than degrade.
- **Strictly ascending recovered signers.** Makes duplicate signers structurally impossible rather
  than merely checked.
- **Attestors cannot blind-sign.** Enforced by module surface, with a test that fails if an entry
  point taking a digest ever appears.

## Residual risks — accepted for v1, disclosed

1. A colluding 3-of-5 quorum can assert a false Bitcoin fact. *This is the design*, stated
   throughout [`TRUST_ASSUMPTIONS.md`](./TRUST_ASSUMPTIONS.md).
2. The stale-watcher window between a real Bitcoin sale and its attestation.
3. Bitcoin reorg deeper than the configured confirmation policy.
4. BIP-322 library defects for script types outside the tested set.
5. Operator independence is a social and operational property that code cannot enforce.
6. Bitcoin regtest and Robinhood testnet end-to-end flows are **authored but not executed** in this
   environment — no Docker daemon, no RPC endpoint, no funded keys. Both are launch gates.

## Recommendation

**NO-GO for mainnet**, unconditionally, and not because of anything found here.

The blocking items are structural and known: no external audit, no independently reproduced
manifest, no five live independent operators, no multisig or timelock deployed, and two end-to-end
flows that this environment could not run. Every one of those is already a launch gate in
[`DEPLOYMENT.md`](./DEPLOYMENT.md).

**GO for testnet deployment and burn-in**, once an RPC endpoint and funded test keys exist.

The most valuable next step is not more contract review. It is executing the two E2E flows that
were authored but never run — because the two defects this review found were both invisible to 823
passing unit tests and both surfaced the moment components were exercised together. That pattern is
unlikely to have exhausted itself at the Solidity boundary; the Bitcoin seam is where it will show
up next.
