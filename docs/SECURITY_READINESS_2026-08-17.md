# Security readiness forensic audit — 2026-08-17

**Repository:** `zentoshi69/deriv.wtf`
**Reviewed branch:** `codex/security-readiness-final`
**Scope:** Solidity contracts, deployment and governance handover, TypeScript services, Bitcoin RPC
boundary, dependency graph, CI/CD, secret controls, regtest specification and security operations
documentation.

## Decision

| Decision surface | Verdict |
|---|---|
| Security-remediation work defined for this pass | **10/10 controls addressed** |
| Candidate source and automated repository gates | **GO for external re-review and testnet** |
| Public or mainnet use with real funds | **NO-GO** |

The first line is not a public-launch score. It means every source-controlled weakness identified in
this pass was either fixed and regression-tested or converted into an explicit fail-closed gate.
No honest forensic review can label the protocol 10/10 for public use while the executable Bitcoin
regtest harness, deployable off-chain processes, production KMS/HSM signer, independent external
re-review, real manifest, live independent attestors, production multisigs/timelock, testnet
burn-in, monitoring and incident rehearsal do not exist as verified evidence.

## Scope and method

The review combined:

- line-by-line reconciliation of the supplied whole-protocol audit with
  [`AUDIT_REMEDIATION.md`](./AUDIT_REMEDIATION.md);
- privileged-role and value-flow review across all nine `AccessControl` contracts;
- deployment execution against a local chain, including adversarial controller configuration;
- unit, fuzz, integration and stateful invariant campaigns;
- Solidity coverage, deployed-bytecode size, gas-snapshot and Slither gates;
- cross-language hash-vector parity across Solidity and TypeScript;
- production dependency advisory review and lockfile analysis;
- Bitcoin Core RPC amplification and fail-closed behavior review;
- GitHub Actions supply-chain, permissions, secret-scanning and fail-open control review;
- verification of claims in top-level documentation against artifacts actually present in the
  repository.

This remains an internal forensic pass. It is not an independent external audit, formal
verification, economic review, legal opinion or production-operations certification.

## Findings closed in this pass

| ID | Severity | Finding | Resolution and evidence |
|---|---:|---|---|
| R-01 | High | Deployment moved `DEFAULT_ADMIN_ROLE` but left the deployer holding independently usable attestor, treasury, metadata, solver-config, excess-sweep and pause roles. | Every constructor-granted operational role is transferred or renounced before admin renunciation. Zero, colliding and EOA controllers are rejected. The full integration suite checks the complete matrix. |
| R-02 | High | The post-deploy checker proved selected grants only. It could not establish exact holder sets, detect unknown role hashes or prove complete history, while its success message overstated what it checked. | Deployment records now include chain, start block, source commit, controllers and all ten contracts. The checker replays every `RoleGranted`/`RoleRevoked` log in bounded chunks, rejects unknown or extra holders, confirms every result with `hasRole` at one fixed block, verifies code at contracts/controllers and fails on chain mismatch. A local deployment proved both fail-closed and success paths, with 35 exact intended holder entries. |
| R-03 | High | The production graph contained vulnerable `ws` versions affected by remotely triggerable memory-exhaustion and memory-disclosure advisories. | A workspace override pins `ws` 8.21.3. The live audit now reports zero critical, high or moderate advisories. |
| R-04 | Medium | One Bitcoin ownership check scanned the entire mempool and fetched transactions sequentially, producing attacker-influenced O(mempool) RPC work. | Replaced with one bounded Bitcoin Core `gettxspendingprevout` request. Tests prove one RPC, no-spender behavior and fail-closed rejection of a mismatched response. |
| R-05 | Medium | Slither, contract-size and gas-snapshot checks could not fail the build because of `|| true`/warning-only behavior; coverage generated a report without enforcing a floor. | All four are blocking. Slither is exact-pinned with `--fail-high`; size preserves the build exit code; the committed gas snapshot is checked; aggregate and per-file coverage floors are enforced. |
| R-06 | Medium | Third-party GitHub Actions used floating tags, workflow token rights depended on repository defaults and checkout credentials remained available to subsequent build steps. | Actions are immutable-SHA pinned, the workflow token is explicitly read-only, and every checkout uses `persist-credentials: false`. Foundry is version-pinned. |
| R-07 | Medium | Documentation claimed an executable Bitcoin regtest harness existed. Nightly CI would fail later with an opaque missing-package error, and the Compose file referenced a nonexistent ord image plus end-of-life Bitcoin Core 24. | Documentation now states “specification only,” nightly fails immediately when the harness package is absent, the workspace anticipates the package, Bitcoin Core/Foundry images are digest-pinned, and ord 0.27.1 is built from its official release artifact with its published SHA-256 verified. The missing executable harness remains a deliberate red launch gate. |
| R-08 | Low | The equal-height Root ownership fuzz path could synthesize a new block hash and exercise the newly forbidden conflicting-block case instead of a valid same-block transition. | Equal-height transitions reuse the accepted block hash. The exact historical seed and the full suite pass. |
| R-09 | Low | The Slither configuration contained a non-schema `_comment` field, making behavior version-dependent. | Removed; Slither 0.11.6 completed with no high-severity result. |
| R-10 | Informational | The active release record mixed historic counts and current claims, obscuring which evidence actually applied to the candidate. | Historic review is labeled as such; this dated record is the canonical candidate verdict and separates source remediation from public-launch authorization. |
| R-11 | High | The off-chain folders were described as independently deployable services, but they contain domain libraries only. The attestor advertised a `start` script targeting a nonexistent `src/server.ts`, the web app had no build entry, and the production KMS/HSM signer is an interface without an implementation. | Removed the dead start command, made the architecture/runbook status explicit, added a fail-closed pre-release web entry and made its production bundle a CI gate. Deployable, authenticated, rate-limited and observable attestor/relayer/solver processes plus production key custody remain hard launch gates requiring operator/provider choices. |
| R-12 | Medium | The public GitHub repository had no default-branch protection or ruleset, vulnerability alerts and automatic security updates were disabled, and no CodeQL workflow or dependency-update schedule existed. | Enabled vulnerability alerts, automated security fixes and private vulnerability reporting; retained secret scanning and push protection; added immutable-pinned CodeQL and weekly npm/Actions/Docker update schedules. The default branch now requires a pull request with eight strict up-to-date CI/security checks, stale-review dismissal, conversation resolution and linear history; force-pushes and deletion are blocked. Administrator bypass remains an explicit solo-repository recovery path if the workflow configuration itself breaks. |
| R-13 | Medium | An `ord` index height ahead of its own Bitcoin Core node—an impossible/inconsistent state—passed the freshness check because only positive lag was rejected. Runtime-invalid height types could also be coerced. | Added the stable `ORD_INDEX_INCONSISTENT` infrastructure code; malformed, negative or ahead-of-node heights now force abstention. Five regression tests cover valid lag, ahead-of-node, malformed/negative ord heights and an invalid node height. |
| R-14 | High | The verifier accepted `getblockchaininfo` without proving that Bitcoin Core served the configured network, and the attestor did not bind the signed message's Bitcoin network to its verifier configuration. A mainnet-configured operator could therefore attest state read from a regtest/testnet node if its deployment was misconfigured. | Every ownership, payment and root-spend path now verifies Core's chain identity plus runtime-valid tip fields before trusting state. The attestor independently requires the canonical message network to equal its verifier network. Mismatch and malformed-height regression tests force an infrastructure abstention. |
| R-15 | Medium | The test-only Compose stack published Bitcoin RPC/ZMQ, ord and Anvil on every host interface despite using deliberately public regtest credentials and deterministic accounts. A machine on an untrusted LAN could expose its local test state to remote manipulation. The fresh ord volume was also mounted at a root-owned path after the container dropped privileges, preventing first-run initialization. | Every published test-stack port is now bound explicitly to `127.0.0.1`; services remain reachable to one another on the private Compose network. The ord image pre-creates `/data` for its unprivileged user, so a fresh named volume remains writable without running ord as root. The localhost deployment record is ignored, while real environment records remain commit-eligible. CI validates the composition and builds/runs the checksum-verified ord image. |

The supplied smart-contract audit's six findings and two hardening recommendations remain resolved
as mapped in [`AUDIT_REMEDIATION.md`](./AUDIT_REMEDIATION.md): Root-wide reservation mutual
exclusion, one lifecycle owner, terminal paths surviving pause, compatible `ROOT_BIND`, bounded
reservation duration, exact five-member attestor set, same-height block-hash consistency and exact
fee conservation.

## Reproducible verification evidence

| Gate | Candidate result |
|---|---|
| Solidity default suite | **848 passed, 0 failed, 0 skipped** |
| Deep stateful suite | **62/62 executable invariant properties passed at 2,000 runs × depth 256 (512,000 calls per property); 67/67 suite tests passed, 0 failed** |
| Solidity coverage (unit/fuzz, invariant files excluded from line accounting) | **Lines 98.95% (1323/1337), functions 99.61% (258/259), branches 91.24% (302/331)** |
| Solidity coverage policy | Aggregate minimum 95/95/85; per-source-file minimum 90/90/70 — **passed** |
| TypeScript tests | **263 passed** across canonical messages, SDK, verifier, solver, relayer, web and attestor |
| Type checking | **7 projects passed** |
| TypeScript production build | **7 projects passed; Vite production bundle built (30 modules)** |
| Cross-language vectors | **32 passed** |
| Contract build/size | **passed**; largest runtime `HoodPupOfferEscrow` 16,035 bytes, 8,541 bytes below EIP-170 |
| Gas snapshot | **848-test snapshot generated and `forge snapshot --check` passed** |
| Slither 0.11.6 | **54 contracts, 100 detectors, 52 lower-severity results, 0 high, exit 0** |
| Production dependency threshold | **0 critical, 0 high, 0 moderate; 1 accepted low** |
| Local key-material/mainnet-broadcast scan | **clean** |
| Post-deploy verifier | **adversarial EOA-controller deployment rejected; contract-controller deployment matched all 35 intended entries with no deployer privilege** |
| Workflow and Compose syntax | **passed** |
| Executable Bitcoin regtest E2E | **not implemented — hard red launch gate** |
| Deployable attestor/relayer/solver processes and KMS/HSM signer | **not implemented — hard red launch gate** |
| Robinhood testnet burn-in | **not executed — hard red launch gate** |

The deep profile is configured for 2,000 invariant runs at depth 256 and 20,000 fuzz runs. There
are 62 executable `invariant_*` properties representing the documented I1–I17 protocol invariants.

## Static-analysis disposition

Slither returned no high-severity finding. The 52 reported lower-severity results were reviewed by
detector category:

| Category | Disposition |
|---|---|
| `incorrect-equality` | Exact zero, sentinel and lifecycle-status equality is intentional and regression-tested. |
| `reentrancy-no-eth` / benign reentrancy | External oracle wiring is immutable and protocol-controlled; mutating entry points are `nonReentrant` or checks-effects-interactions constrained. Views and the role-gated mint recorder do not create attacker-controlled mutation paths. |
| `uninitialized-local` | Solidity-defined zero initialization is used for bounded accumulators and indices. |
| `unused-return` | Secondary values, error payloads or epochs are intentionally discarded where the primary value is independently validated. |
| `missing-zero-check` | `TourEngine`'s FeeRouter discovery address is explicitly optional and may be zero. |
| `calls-loop` | Calls are bounded by the immutable exact-five attestor set and fixed quorum validation. |
| `timestamp` | Timestamps define intended offer, reservation and tour lifecycle boundaries. |
| `cyclomatic-complexity` | Centralized field-shape validation is explicit and covered by high branch coverage. |
| `dead-code` | The inherited ERC-721 `_baseURI` report is a virtual-dispatch false positive. |
| `low-level-calls` | ETH delivery requires low-level calls; liabilities are updated first, entry points are non-reentrant, and failed delivery reverts. |

Any change that invalidates one of these facts requires fresh triage; this table is not a permanent
suppression list.

## Accepted dependency residual

The only live production advisory is `elliptic` 6.6.1 / CVE-2025-14505 / GHSA-848j-6mx2-7j84,
pulled transitively by exact-pinned `bip322-js` 3.0.0. The advisory affects ECDSA **signature
generation** and has no patched `elliptic` release. In this repository that dependency is reachable
only through the BIP-322 verification/address adapter; it receives public messages, signatures and
scripts and is not given private-key material. Attestor EVM signing is outside `bip322-js`: the
local test signer uses viem, while a production KMS/HSM implementation is still a launch blocker.

This containment lowers the current exploitability but does not erase supply-chain risk. Keep the
advisory visible, replace the adapter when a maintained compatible verifier is validated, and never
extend `bip322-js` usage to signing or key handling.

## Trust boundaries that code does not remove

- Three of the exact five attestors can collude and assert a false Bitcoin fact. They cannot spend
  an inscription, but they can authorize a false mint or payout.
- A stale indexer, a deeper-than-policy Bitcoin reorganization or a shared upstream-provider
  failure can cause incorrect or unavailable attestations.
- Controller addresses having bytecode is necessary but not sufficient. Production review must
  prove the timelock delay/proposer/executor configuration and guardian multisig owners/threshold.
- Non-upgradeability removes an upgrade-key attack surface but makes defects expensive to migrate.
- Native BTC settlement exposes real solver capital and stays feature-flagged off until separately
  reviewed and exercised.

## Mandatory public-launch blockers

Public/mainnet use remains prohibited until evidence for every item below is attached to a release:

1. Independent external re-review of the final commit and closure of every high/critical finding.
2. Implementation and successful execution of the real `@hoodpups/regtest-harness`, including all
   positive and negative Bitcoin/EVM seam cases in `infra/regtest/README.md`.
3. Robinhood testnet deployment, role-history verification and sustained burn-in.
4. Canonical Bitcoin Puppets manifest independently sourced and its Merkle root reproduced by at
   least two independent implementations.
5. Deployable attestor, relayer and solver processes with authenticated/rate-limited ingress,
   durable audit storage, production KMS/HSM signing, health checks and operator deployment
   artifacts.
6. Five genuinely independent attestor operators using independent nodes, indexers, infrastructure
   and keys.
7. Real multisig guardian and `TimelockController` deployed; owners, threshold, delay, proposers,
   executors and exact role history independently verified.
8. Official and wallet-specific BIP-322 vector coverage for every allowed script/variant.
9. Production monitoring, alerting, backups and log retention operating—not merely documented.
10. Incident-response and key-rotation rehearsals completed, with evidence and named responders.
11. Bug bounty/disclosure channel live, operational/legal review complete and native BTC settlement
    still disabled until separately approved.

## Final recommendation

**Approve this candidate for independent external re-review and controlled testnet deployment. Do
not approve it for unrestricted public/mainnet use or real funds.**

The repository now fails closed where evidence is absent: mainnet deployment is refused by code,
the missing regtest harness fails nightly, dependency advisories at moderate or above fail CI,
unexpected roles fail the deployment audit, and security gates no longer turn failures into
warnings. A public readiness label of 10/10 becomes defensible only after the eleven external and
operational blockers above are evidenced against the exact release commit.
