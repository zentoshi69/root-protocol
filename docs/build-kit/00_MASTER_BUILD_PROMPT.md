# CODEX MASTER PROMPT — BUILD THE HOODPUPS ROOTED SETTLEMENT PROTOCOL

You are the lead protocol engineer and security owner for this repository. Build the complete HoodPups Rooted Settlement Protocol described below. Do not merely write a proposal. Inspect the repository, create a concrete implementation plan, edit the codebase, run tests, and leave the repository in a reproducible, audit-ready state.

## Operating rules

1. First inspect the existing repository, package manager, frameworks, contracts, deployment scripts, CI, and conventions. Preserve compatible existing work.
2. If the repository is empty, scaffold a monorepo with Foundry for Solidity, a typed off-chain service layer, a shared SDK, and a web application.
3. Do not deploy to mainnet, broadcast real transactions, use real private keys, move any real Bitcoin inscription, or send real BTC.
4. Use Robinhood Chain testnet for EVM integration and Bitcoin regtest for Bitcoin integration.
5. Before editing, create or update:
   - `docs/ARCHITECTURE.md`
   - `docs/THREAT_MODEL.md`
   - `docs/TRUST_ASSUMPTIONS.md`
   - `docs/STATE_MACHINES.md`
   - `docs/IMPLEMENTATION_PLAN.md`
6. Work in phases. After each phase, run formatting, compilation, unit tests, fuzz tests, and any integration tests available. Fix failures before moving on.
7. Never invent the Bitcoin Puppets inscription manifest. Production deployment must fail closed until a real, independently verified manifest is supplied.
8. Do not implement BIP-322 cryptography in Solidity. Verify Bitcoin facts off-chain, then attest them on Robinhood Chain through a three-of-five EIP-712 verifier quorum.
9. Use exact-pinned dependencies and lockfiles. Any BIP-322 library must be wrapped behind a narrow adapter and validated against official test vectors and project-owned golden vectors.
10. Prefer non-upgradeable core contracts. Use versioned redeployment rather than proxy upgrades for escrow, NFT uniqueness, fee percentages, and payout accounting.
11. Administrative changes must be designed for a multisig plus `TimelockController`. A separate guardian may pause new risk-taking actions, but pausing must never block refunds or withdrawals.
12. Use custom Solidity errors, NatSpec, explicit events, checks-effects-interactions, `ReentrancyGuard`, and least-privilege `AccessControl` roles.
13. Do not use `tx.origin`, `selfdestruct`, arbitrary `delegatecall`, hidden owner withdrawals, or an admin path that can seize user balances.
14. No token, no stock allocation, no market-maker allocation, and no royalty dependency in version one.

# Mission

Build a Robinhood Chain protocol where one canonical Bitcoin Puppet inscription can create at most one verified HoodPup.

The original Bitcoin Puppet:

- remains on Bitcoin;
- is never bridged, wrapped, deposited, staked, or placed in protocol custody;
- is proven through a BIP-322 signature over exact mint and payout terms;
- can authorize a paid mint to a Robinhood Chain buyer or a free self-cast;
- receives value either as ETH on Robinhood Chain or as exact native BTC through a bonded solver;
- controls future Root-linked benefits only while current ownership remains verified.

The HoodPup:

- is a transferable ERC-721 on Robinhood Chain;
- permanently references one Bitcoin inscription root;
- can never be minted twice for the same root;
- supports an ERC-4907 temporary user role for later tours;
- does not claim to be the original Bitcoin asset.

# Fixed economics

For every paid mint, calculate from the gross ETH escrow:

- 50% seller share;
- 25% Puppet ecosystem treasury;
- 25% protocol treasury.

Implement the split as immutable basis-point constants:

- `SELLER_BPS = 5000`
- `PUPPET_TREASURY_BPS = 2500`
- `PROTOCOL_BPS = 2500`
- `BPS_DENOMINATOR = 10000`

Calculate seller first, treasury second, and assign all rounding remainder to protocol:

```text
seller = gross * 5000 / 10000
treasury = gross * 2500 / 10000
protocol = gross - seller - treasury
```

Percentages must not be administratively changeable. Treasury destination addresses may change only through timelocked governance.

# Network assumptions

- Robinhood Chain mainnet chain ID: `4663`
- Robinhood Chain testnet chain ID: `46630`
- Native gas and settlement asset: ETH
- Bitcoin production network: mainnet
- Bitcoin development network: regtest

Deployment scripts must refuse unknown chain IDs unless an explicit local-development override is provided.

# High-level architecture

```text
Bob controls a Bitcoin Puppet UTXO
              │
              │ signs exact BIP-322 authorization
              ▼
Bitcoin Core + ord + BIP-322 verifier service
              │
              │ 3 of 5 independent EIP-712 attestations
              ▼
BitcoinOwnershipOracle on Robinhood Chain
              │
              ├──────── direct ETH payout flow
              │             │
Alice escrows ETH ──► HoodPupOfferEscrow ──► mint HoodPup
                                      │
                                      └──► FeeRouter ──► PayoutVault
                                                     ├── Bob 50%
                                                     ├── Puppet treasury 25%
                                                     └── Protocol 25%

              └──────── native BTC payout flow
                            │
                     offer becomes BTC_APPROVED
                            │
                     bonded solver reserves
                            │
                     solver sends exact sats to Bob
                            │
                     3 of 5 payment attestation
                            │
                     mint HoodPup + reimburse solver
```

This is not a trustless Bitcoin bridge. The verifier quorum cannot move Bob’s Bitcoin, but a dishonest quorum can falsely attest ownership or payment. Document this plainly in code comments, UI copy, and threat-model documentation.

# Required repository layout

Adapt this to existing conventions rather than duplicating frameworks:

```text
contracts/
  src/
    types/PuppetTypes.sol
    types/PuppetHashing.sol
    interfaces/
    PuppetCollectionRegistry.sol
    BitcoinAttestorRegistry.sol
    BitcoinOwnershipOracle.sol
    PayoutVault.sol
    RootOwnershipRegistry.sol
    FeeRouter.sol
    HoodPups.sol
    HoodPupOfferEscrow.sol
    BtcSolverSettlement.sol
    TourEngine.sol
  test/unit/
  test/fuzz/
  test/invariant/
  script/

services/
  bitcoin-verifier/
  attestor/
  relayer/
  btc-solver/

packages/
  protocol-sdk/
  canonical-message/
  generated-abis/

apps/
  web/

data/
  bitcoin-puppets-mainnet.example.json
  test-fixtures/

docs/
  ARCHITECTURE.md
  THREAT_MODEL.md
  TRUST_ASSUMPTIONS.md
  STATE_MACHINES.md
  RUNBOOK.md
  DEPLOYMENT.md
  INCIDENT_RESPONSE.md
```

# Canonical identity and hashing

Never store a human-readable Bitcoin address string as the security primitive on-chain.

Use:

```solidity
struct RootId {
    bytes32 inscriptionTxid;
    uint32 inscriptionIndex;
}
```

Define:

```text
collectionId = keccak256("BITCOIN_PUPPETS_MAINNET_V1")
rootKey = keccak256(abi.encode(collectionId, inscriptionTxid, inscriptionIndex))
outpointHash = keccak256(abi.encode(bitcoinTxid, vout))
scriptHash = keccak256(rawScriptPubKeyBytes)
paymentOutputKey = keccak256(abi.encode(bitcoinTxid, vout))
```

Use one canonical txid byte order everywhere and enforce it in shared tests. The SDK, Merkle builder, attestor, Solidity tests, and UI must all reproduce identical hashes from golden vectors.

# Offer state machine

Offer kinds:

- `PAID_EVM`
- `PAID_BTC`
- `SELF_CAST`

Offer statuses:

- `NONE`
- `OPEN`
- `BTC_APPROVED`
- `BTC_RESERVED`
- `SETTLED`
- `REFUNDED`

Allowed transitions:

```text
PAID_EVM: OPEN ──ownership quorum──► SETTLED
SELF_CAST: OPEN ──ownership quorum──► SETTLED
PAID_BTC: OPEN ──ownership quorum──► BTC_APPROVED
PAID_BTC: BTC_APPROVED ──solver bond──► BTC_RESERVED
PAID_BTC: BTC_RESERVED ──BTC payment quorum──► SETTLED
PAID_BTC: BTC_RESERVED ──reservation timeout──► BTC_APPROVED
OPEN/BTC_APPROVED ──offer expiry──► REFUNDED
any non-settled offer ──root already minted──► REFUNDED
```

Buyers may not cancel an offer early after publishing terms. This prevents bait-and-switch while a Bitcoin owner is signing. They may refund after expiry or immediately if another offer already minted that root.

# Paid EVM settlement

1. Alice creates a valid-root offer and deposits ETH.
2. The escrow stores gross, fixed split, root, buyer, recipient, kind, and expiry.
3. Bob chooses an EVM payout address and signs the exact canonical BIP-322 message.
4. Independent verifier instances confirm:
   - the root is in the canonical collection manifest;
   - `ord` reports the inscription in the claimed UTXO;
   - Bitcoin Core reports the UTXO unspent;
   - the UTXO is not being spent in the mempool;
   - the BIP-322 signature is valid for the UTXO script;
   - all signed offer and payout terms match;
   - the root has not already minted.
5. Three of five attestors sign the same EIP-712 `OwnershipAttestation`.
6. A relayer submits the attestation.
7. The oracle consumes it once.
8. The escrow marks the offer settled, mints the HoodPup, and sends the full gross amount to `FeeRouter`.
9. `FeeRouter` credits Bob, the Puppet treasury, and the protocol treasury inside `PayoutVault`.
10. Bob withdraws normally or signs a gasless withdrawal authorization for a relayer.

# Native BTC settlement

No price oracle is used.

The offer fixes two independent values:

- `sellerWei`: the ETH amount the solver receives on successful settlement;
- `sellerSats`: the exact satoshi amount Bob must receive.

Bob signs the exact satoshi amount and exact Bitcoin payout script hash. A solver decides whether that quote is economically attractive.

1. Alice creates `PAID_BTC` and escrows ETH.
2. Bob signs an ownership authorization containing his chosen Bitcoin payout script hash and the fixed `sellerSats`.
3. Three-of-five ownership attestation changes the offer to `BTC_APPROVED`; no NFT is minted yet.
4. A solver posts a bond and reserves the offer.
5. The solver sends exactly `sellerSats` to the exact payout script.
6. Verifiers wait for the configured confirmation policy and attest the precise `txid:vout`, script hash, sat amount, solver, and offer.
7. Three-of-five payment attestation is submitted.
8. The payment output is marked globally consumed.
9. The HoodPup is minted.
10. The solver receives `sellerWei`, the Puppet treasury receives 25%, the protocol receives 25%, and the solver bond is returned.
11. If the solver times out, the reservation expires, its bond is slashed according to constructor configuration, and another solver may reserve.

Feature-flag native BTC settlement off in production until operational and legal review is complete.

# Free self-cast

A self-cast is represented as a zero-value `SELF_CAST` offer:

- gross ETH: zero;
- seller amount: zero;
- buyer and recipient: the chosen Robinhood address;
- payout mode: none;
- exact root ownership still required;
- the original Puppet never moves;
- the relayer may sponsor gas.

The same root uniqueness rule applies.

# Required contracts

Implement and integrate:

1. `PuppetTypes.sol` and `PuppetHashing.sol`
2. `PuppetCollectionRegistry.sol`
3. `BitcoinAttestorRegistry.sol`
4. `BitcoinOwnershipOracle.sol`
5. `PayoutVault.sol`
6. `RootOwnershipRegistry.sol`
7. `FeeRouter.sol`
8. `HoodPups.sol`
9. `HoodPupOfferEscrow.sol`
10. `BtcSolverSettlement.sol`
11. `TourEngine.sol` as a phase-two module

Use OpenZeppelin 5.x primitives where appropriate, but do not inherit unnecessary enumerable or upgradeable extensions.

# Root ownership epochs

Mint settlement records the current verified Bitcoin owner’s chosen beneficiary in `RootOwnershipRegistry`.

When the original inscription UTXO is later spent:

- verifier nodes issue a `RootSpendAttestation`;
- the root becomes inactive;
- future Root-linked fees go into `PayoutVault` as `pendingByRoot[rootKey]`;
- a new owner can submit a fresh ownership proof and activate a new epoch;
- pending Root fees release to the newly verified beneficiary;
- already credited balances remain with the previous beneficiary.

The registry reflects attested state, not magical continuous Bitcoin consensus. Watchers must submit invalidations promptly, and this limitation must be documented.

# Temporary tours

After the settlement core is complete, implement a non-financial tour system using ERC-4907:

- owner retains ERC-721 ownership;
- temporary user receives use rights until expiry;
- recipient must check in during the active tour;
- transfer or user reset cancels reward eligibility;
- one valid check-in per recipient per season;
- no token, cash, or immediately farmable payout;
- valid finalized tours increment `miles` and emit permanent travel events;
- off-chain reputation may add Sybil analysis, but the contract must never claim proof of unique humanity.

# Off-chain services

Build four independently deployable services:

## Bitcoin verifier

- talks to the operator’s own Bitcoin Core node and `ord` indexer;
- parses canonical inscription IDs and outpoints;
- verifies collection membership;
- verifies BIP-322 simple/full/proof-of-funds formats only where safely supported;
- checks UTXO unspent state, mempool spend state, confirmations, and exact script;
- produces a deterministic verification result and audit log;
- never receives or stores a seed phrase or private key.

## Attestor

- one codebase, independently configured five times;
- each instance independently verifies the complete fact set;
- signs the exact EIP-712 digest with its own EVM attestor key;
- refuses stale chain state, unknown policy versions, mismatched canonical hashes, or incomplete proofs;
- exposes health and signed-attestation endpoints;
- does not trust another attestor’s result.

## Relayer

- gathers at least three matching signatures;
- sorts recovered signer addresses in strictly ascending order;
- submits the appropriate oracle/escrow transaction;
- retries idempotently;
- never changes terms;
- sponsors gas only through explicit policy.

## BTC solver

- watches approved BTC offers;
- evaluates the fixed sats/wei quote;
- reserves with a bond;
- builds and broadcasts a Bitcoin transaction paying the exact script and amount;
- waits for payment attestations;
- submits settlement and receives reimbursement;
- never controls Bob’s original Puppet UTXO.

# Frontend requirements

Build clear flows for:

- buyer creates EVM or BTC offer;
- holder sees exact offer and 50/25/25 split;
- holder chooses ETH or native BTC payout;
- holder signs canonical BIP-322 authorization;
- cold-wallet user can export/import or scan a signing request without exposing keys;
- offer status timeline;
- refunds;
- solver status;
- claimable PayoutVault balance and gasless withdrawal;
- current Root ownership epoch;
- tour start, check-in, and completion.

Every screen must distinguish:

- ETH on Robinhood Chain;
- native BTC on Bitcoin;
- the original Bitcoin Puppet;
- the derived HoodPup.

Never display “trustless bridge.”

# Security invariants

Implement unit, fuzz, and stateful invariant tests proving at least:

1. One `rootKey` can mint at most one HoodPup.
2. One offer can settle at most once.
3. One attestation digest can be consumed at most once.
4. One Bitcoin `txid:vout` can settle at most one BTC offer.
5. An EVM seller payout can only go to the address signed in the ownership authorization.
6. A BTC settlement can only reimburse the solver named in the payment attestation and active reservation.
7. A BTC-mode HoodPup cannot mint before a valid payment attestation.
8. `seller + Puppet treasury + protocol == gross` for every amount, including rounding edges.
9. PayoutVault liabilities never exceed its ETH balance.
10. User funds cannot be withdrawn by an administrator.
11. Pausing new risk-taking actions never blocks refunds or withdrawals.
12. Expired or stale-epoch attestations fail.
13. Duplicate, unsorted, unauthorized, or insufficient attestor signatures fail.
14. Wrong chain, wrong oracle, wrong escrow, wrong offer, wrong payout, wrong root, and wrong purpose signatures fail.
15. Root movement invalidation stops future direct recurring payouts to the old beneficiary.
16. Refund plus distributions can never exceed the amount originally escrowed.
17. Contracts retain no unaccounted ETH after successful routing.
18. A transfer of the NFT clears the ERC-4907 user role.

# Required developer tooling

Use Foundry for Solidity. Add:

- unit tests;
- fuzz tests;
- handler-based stateful invariant tests;
- gas snapshots;
- deployment simulations;
- ABI generation;
- NatSpec generation;
- static analysis configuration;
- CI commands for format, build, test, invariant, and static analysis.

Use Bitcoin regtest plus `ord` in Docker Compose for end-to-end tests. The test harness must create fixture inscriptions, move them, sign authorization messages, exercise ownership invalidation, and simulate native-BTC solver settlement without real funds.

# Deployment model

Create scripts for local, Robinhood testnet, and Robinhood mainnet, but only execute local/testnet.

Suggested order:

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
11. grant narrow roles;
12. transfer admin to timelock;
13. revoke deployer roles.

Write deployed addresses and constructor arguments to `deployments/<chainId>.json`. Add a script that verifies every expected role assignment and fails if the deployer retains privilege.

# Definition of done

Do not call the work complete until:

- all required contracts compile;
- all public/external functions have NatSpec;
- all state transitions are tested;
- all listed invariants pass;
- the Merkle builder matches Solidity golden vectors;
- BIP-322 verification passes official and wallet-specific vectors;
- a complete EVM-payout flow passes locally;
- a complete native-BTC solver flow passes on Bitcoin regtest;
- a complete Robinhood Chain testnet flow passes with test assets;
- docs clearly describe every trust assumption and failure mode;
- no production secret or real key exists in the repository;
- no mainnet transaction has been broadcast;
- the final response summarizes files changed, commands run, test results, unresolved risks, and exact next steps.

Begin by inspecting the repository and writing the implementation plan. Then execute the phases rather than stopping after the plan.
