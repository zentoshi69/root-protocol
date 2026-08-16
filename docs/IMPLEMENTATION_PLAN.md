# Implementation Plan

Status legend: ✅ done · 🚧 in progress · ⬜ not started · 🔒 blocked on an external precondition

## Phase 0 — Foundation ✅

| Item | Status |
|---|---|
| Foundry workspace, solc 0.8.28, `evm_version = shanghai` | ✅ |
| forge-std 1.9.7 + OpenZeppelin 5.1.0 vendored and pinned | ✅ |
| `lite` / `default` / `deep` fuzz + invariant profiles | ✅ |
| `PuppetTypes.sol` — canonical structs, enums, frozen EIP-712 field order | ✅ |
| `PuppetHashing.sol` — every protocol hash and type string, single source of truth | ✅ |
| Eleven interfaces freezing the external API | ✅ |
| `ARCHITECTURE.md`, `THREAT_MODEL.md`, `TRUST_ASSUMPTIONS.md`, `STATE_MACHINES.md` | ✅ |

**Why freeze the interfaces before writing implementations:** ten contracts, four services, an SDK
and a frontend all have to agree on the same field ordering and the same hashes. Freezing the
surface first lets the rest be built in parallel against a stable target, and makes any proposed
change to it a visible, reviewed event rather than a silent drift.

## Phase 1 — Shared test infrastructure 🚧

| Item | Notes |
|---|---|
| `AttestorSet.sol` | Deterministic 5-key attestor set; signs quorums with recovered signers strictly ascending; also produces the negative cases (unsorted, duplicate, non-attestor, compact, high-`s`) |
| `MerkleFixture.sol` | Sorted-pair Merkle builder matching `PuppetHashing.collectionLeaf` |
| Mocks | Registry / oracle / root-registry / HoodPups / receivers / ERC-1271 wallet / consumer harness |
| `PuppetHashing.t.sol` + `hashing-vectors.json` | The cross-language golden vectors every other language is validated against |

## Phase 2 — Leaf contracts 🚧

Built in parallel; each depends only on the frozen types and interfaces.

| Contract | Core guarantee |
|---|---|
| `PuppetCollectionRegistry` | Immutable Merkle root; no admin can change membership after deployment |
| `BitcoinAttestorRegistry` | Exactly 5 attestors, threshold ≥ 3, atomic rotation, epoch bumps on every mutation |
| `PayoutVault` | `balance >= totalLiability`; withdrawals never pausable; no admin can reduce a balance |
| `HoodPups` | One token per Root forever; ERC-4907 user clears on transfer |

## Phase 3 — Oracle, epochs, economics ⬜

| Contract | Core guarantee |
|---|---|
| `BitcoinOwnershipOracle` | 3-of-5 EIP-712, one-time digest consumption, global payment-output uniqueness |
| `RootOwnershipRegistry` | Monotonic ownership epochs; already-credited balances survive an epoch change |
| `FeeRouter` | `seller + treasury + protocol == gross` exactly; zero retained ETH |

## Phase 4 — Settlement core ⬜

| Contract | Core guarantee |
|---|---|
| `HoodPupOfferEscrow` | Atomic mint + payout; buyer cannot cancel early; refunds survive pause |
| `BtcSolverSettlement` | No price oracle; bond fully conserved across settle/slash |

## Phase 5 — Tours ⬜

`TourEngine` — ERC-4907 temporary use, miles, seasons, anti-farm bounds, no token or cash reward.

## Phase 6 — Off-chain services ⬜

| Service | Notes |
|---|---|
| `packages/canonical-message` | The versioned BIP-322 message generator/parser. ASCII keys, lowercase hex, decimal ints, LF endings, fixed field order, zero values rendered not omitted |
| `packages/protocol-sdk` | Typed clients, hashes, EIP-712 digests, Merkle builder, split calculator, state-machine helpers — validated against the Solidity golden vectors |
| `services/bitcoin-verifier` | Own bitcoind + `ord`; inscription location, unspent state, mempool spend, exact script, BIP-322 adapter |
| `services/attestor` | One codebase, five independent deployments; recomputes everything; never blind-signs a digest |
| `services/relayer` | Threshold of *byte-identical* facts; ascending signer sort; simulate then submit idempotently |
| `services/btc-solver` | Watches `BTC_APPROVED`, bonds, pays exact sats from a separate operational wallet, settles |

## Phase 7 — Frontend ⬜

Buyer flow · holder claim/approval flow (connected wallet **and** cold-wallet export/QR) ·
PayoutVault claim with gasless withdrawal · Root ownership state · tours · read-only ops console.

Every screen must distinguish ETH-on-Robinhood-Chain from native BTC, and the original Bitcoin
Puppet from the derived HoodPup. The strings "trustless bridge" and "atomic swap" are banned.

## Phase 8 — Integration, invariants, deployment ⬜

| Item | Notes |
|---|---|
| Cross-language vector corpus + CI divergence gate | Solidity ↔ SDK ↔ verifier ↔ attestor |
| The 17 protocol invariants (I1–I17) under handler-based stateful fuzzing | `build-kit/14_*.md` |
| Slither, gas snapshots, storage-layout diffing, secret scanning | |
| Bitcoin regtest E2E (bitcoind + `ord` in Docker) | 🔒 needs container images reachable from the build environment |
| Robinhood Chain testnet E2E (chain ID 46630) | 🔒 needs an RPC endpoint and funded test keys |
| Deployment scripts for local / testnet / mainnet | Mainnet script generated, **never executed** |
| Runbooks: incident response, key rotation, attestor policy, solver ops, reorg response, pause/recovery | |

## Ordering constraints that actually bind

```
types+interfaces ──► test infra ──► leaf contracts ──► oracle/epochs/fees ──► settlement ──► tours
        │                  │                                                        │
        └──────────────────┴──► canonical-message ──► SDK ──► services ──► frontend ─┘
                                                              │
                                                              └──► regtest E2E ──► testnet E2E
```

`canonical-message` and the SDK's hashing module depend only on the frozen types and the golden
vectors, so they can be built alongside the contracts rather than after them.

## Deployment order (scripted, local/testnet only)

1. `PuppetCollectionRegistry`
2. `BitcoinAttestorRegistry`
3. `BitcoinOwnershipOracle`
4. `PayoutVault`
5. `RootOwnershipRegistry`
6. `FeeRouter`
7. `HoodPups`
8. `HoodPupOfferEscrow`
9. `BtcSolverSettlement`
10. `TourEngine`
11. Grant narrow roles
12. Transfer admin to the `TimelockController`
13. Revoke every deployer role, then **verify** none remains

Addresses and constructor arguments are written to `deployments/<chainId>.json`. A post-deploy
script asserts every expected role assignment and fails if the deployer retains any privilege.

## Hard stop

**No mainnet deployment.** Not in this repository, not in this session, not until every launch gate
in `build-kit/README.md` is green — including an external audit, five genuinely independent
operators, an independently reproduced manifest, and a live multisig plus timelock.
