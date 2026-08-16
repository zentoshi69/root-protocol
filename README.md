# deriv.wtf — HoodPups Rooted Settlement Protocol

**One canonical Bitcoin Puppet inscription can create at most one verified HoodPup on Robinhood
Chain. The original Puppet never leaves Bitcoin.**

```
Bob's Bitcoin wallet
        │  signs one exact message (BIP-322) — the Puppet never moves
        ▼
Bitcoin verifier network  (5 independent operators, each with their own bitcoind + ord)
        │  3 matching EIP-712 attestations
        ▼
Robinhood Chain settlement contracts
        ├── mint HoodPup to Alice
        ├── pay Bob — ETH on Robinhood Chain, or native BTC via a bonded solver
        ├── pay the Bitcoin Puppets ecosystem treasury
        └── pay the protocol
```

## What this is, stated honestly

This is **not** a trustless Bitcoin bridge, and no part of this repository will ever claim it is.

A Robinhood Chain contract cannot read Bitcoin — it cannot parse an Ordinals index, check a UTXO
set, or verify a BIP-322 signature over a Taproot script. So the protocol doesn't pretend it can.
Five independent verifier operators check those facts, and three of five must agree before anything
settles.

That quorum **can** assert a false ownership or payment fact. It can **never** move, spend or
encumber anyone's Bitcoin Puppet — the protocol holds no Bitcoin key and requires no inscription to
move. The worst case is a bad mint, not a stolen asset.

The value proposition is not moving Puppets across chains. It's **moving Robinhood Chain money back
to Bitcoin owners.**

Read [`docs/TRUST_ASSUMPTIONS.md`](./docs/TRUST_ASSUMPTIONS.md) before anything else.

## How it works

Alice escrows ETH for a HoodPup derived from Bitcoin Puppet #123. Bob, who holds that Puppet in a
cold wallet, signs one exact message binding the Puppet, the offer, the buyer, his payout address,
the amount, the chain id and an expiry. Five verifiers independently confirm the inscription is
where he says it is, that the UTXO is unspent and unspent-in-mempool, and that the signature is
valid for that exact output script. Three sign an attestation. A relayer submits it and pays the
gas.

Then, in one atomic transaction: the HoodPup mints to Alice, and the escrow applies its immutable
**50% Bob · 25% Bitcoin Puppets ecosystem treasury · 25% protocol** policy. Integer shares round
down and the protocol receives the remainder, so every wei is conserved even for tiny amounts.

Bob can take that as ETH on Robinhood Chain, or as **exact native BTC** — a bonded solver pays him
in sats first and is reimbursed from Alice's escrow only after three verifiers attest the precise
`txid:vout`. There is no BTC/ETH price oracle anywhere in that path: the offer fixes both numbers up
front and the solver's spread is the market.

## Contracts

| Contract | Responsibility |
|---|---|
| `PuppetCollectionRegistry` | Immutable Merkle membership for the canonical manifest |
| `BitcoinAttestorRegistry` | Verifier set, threshold, epoch, policy version |
| `BitcoinOwnershipOracle` | 3-of-5 EIP-712 quorum, one-time digest consumption |
| `PayoutVault` | Pull payments, gasless (ERC-1271-aware) withdrawal |
| `RootOwnershipRegistry` | Bitcoin ownership epochs — what happens when Bob sells |
| `FeeRouter` | The immutable 50/25/25 split |
| `HoodPups` | ERC-721 + ERC-4907, one token per Root forever |
| `HoodPupOfferEscrow` | Offers, settlement, refunds |
| `BtcSolverSettlement` | Bonded native-BTC payouts |
| `TourEngine` | Temporary ERC-4907 use. No token, no cash |

All ten are **non-upgradeable**. No proxies, no initializers, no `delegatecall`. Fixing a bug means
deploying a new version and migrating — a deliberate trade that removes the most valuable target in
most protocols.

## Quick start

```bash
# Solidity
cd contracts
forge build
forge test                                    # unit + fuzz + invariants
FOUNDRY_PROFILE=lite forge test               # fast local loop
FOUNDRY_PROFILE=deep forge test               # long stateful campaigns

# TypeScript
pnpm install
pnpm typecheck && pnpm test
pnpm vectors                                  # TS must reproduce every Solidity hash

# Everything CI runs
pnpm ci
```

## Layout

```
contracts/        Foundry workspace — src/, test/{unit,fuzz,invariant,mocks,helpers}/, script/
services/         bitcoin-verifier/ · attestor/ · relayer/ · btc-solver/
packages/         protocol-sdk/ · canonical-message/ · generated-abis/
apps/web/         buyer, holder, payout, root and tour flows
data/             manifest example, test fixtures, cross-language golden vectors
infra/regtest/    bitcoind + ord compose and the end-to-end harness
docs/             architecture, trust assumptions, threat model, runbooks
```

## Documentation

| | |
|---|---|
| [`ARCHITECTURE.md`](./docs/ARCHITECTURE.md) | How the three machines fit together |
| [`TRUST_ASSUMPTIONS.md`](./docs/TRUST_ASSUMPTIONS.md) | **Read first.** What the quorum can and cannot do |
| [`THREAT_MODEL.md`](./docs/THREAT_MODEL.md) | Nine adversary classes, per-attack mitigations |
| [`STATE_MACHINES.md`](./docs/STATE_MACHINES.md) | Every legal transition, and why |
| [`DEPLOYMENT.md`](./docs/DEPLOYMENT.md) | Deploy order, role matrix, launch gates |
| [`RUNBOOK.md`](./docs/RUNBOOK.md) | Daily operation and alert thresholds |
| [`INCIDENT_RESPONSE.md`](./docs/INCIDENT_RESPONSE.md) | Severity ladder and playbooks |
| [`ATTESTOR_POLICY.md`](./docs/ATTESTOR_POLICY.md) | Binding rules for verifier operators |
| [`SOLVER_OPERATIONS.md`](./docs/SOLVER_OPERATIONS.md) | Running a bonded BTC solver |
| [`BITCOIN_REORG_RESPONSE.md`](./docs/BITCOIN_REORG_RESPONSE.md) | The sharpest edge in the design |
| [`KEY_ROTATION.md`](./docs/KEY_ROTATION.md) | Attestor, relayer, solver and admin keys |
| [`PAUSE_AND_RECOVERY.md`](./docs/PAUSE_AND_RECOVERY.md) | Pausing never blocks a refund |
| [`AUDIT_REMEDIATION.md`](./docs/AUDIT_REMEDIATION.md) | Finding-by-finding remediation map and residual risks |

## Security posture

- Core contracts immutable; no upgrade key exists to steal.
- The 50/25/25 policy and exact-conservation remainder rule are compiled in with no setter.
- Pausing may block new risk-taking. It can **never** block a refund, withdrawal, or terminal
  resolution of an active BTC reservation — enforced by invariant and full-deployment tests.
- No admin path can reduce a user's claimable balance. No such code exists.
- No `tx.origin`, no `selfdestruct`, no arbitrary `delegatecall`, no owner withdrawal.
- Admin is a multisig plus `TimelockController`; deployment fails if the deployer retains privilege.
- One canonical byte order for Bitcoin txids everywhere, enforced by cross-language golden vectors
  that fail CI on divergence.

Found something? See `SECURITY.md` for the disclosure contact. Please don't open a public issue for
a vulnerability.

## Status

Pre-audit. **No mainnet deployment**, and none until every launch gate in
[`DEPLOYMENT.md`](./docs/DEPLOYMENT.md) is green — including an external audit, five genuinely
independent operators, and an independently reproduced manifest.

Native BTC settlement is feature-flagged **off** pending operational and legal review.

## What v1 deliberately does not have

No token. No stock basket. No market maker. No royalty dependency. No upgrade proxy. No price
oracle. No claim of trustlessness. The protocol has to work and return value to Bitcoin Puppet
owners before any additional financial object is worth discussing.

## Naming

"Canonical" here means *canonical to this protocol deployment*. Nothing in this repository is an
endorsement by, or an affiliation with, the Bitcoin Puppets project or Robinhood.
