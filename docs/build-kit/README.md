# HoodPups Rooted Settlement Protocol — Codex Build Kit

This kit turns the full HoodPups idea into an executable Codex workflow.

## What this builds

A Robinhood Chain protocol where:

- one canonical Bitcoin Puppet inscription can create at most one verified HoodPup;
- the original Bitcoin inscription never moves, bridges, stakes, or enters custody;
- its current controller authorizes the mint with a BIP-322 ownership proof;
- a buyer escrows ETH on Robinhood Chain;
- the seller can receive either ETH on Robinhood Chain or exact native BTC through a bonded solver;
- mint economics are fixed at 50% to the current Bitcoin Puppet controller, 25% to the Puppet ecosystem treasury, and 25% to the protocol;
- self-casting is free;
- later recurring fees follow the currently verified Bitcoin owner;
- HoodPups can be sent on temporary ERC-4907 tours without transferring ownership.

This is an attested cross-chain settlement system, not a trustless Bitcoin bridge. In version one, three of five independent verifier operators attest to Bitcoin ownership and BTC payment facts. They cannot move the original Puppet, but a dishonest quorum could falsely attest ownership or payment. That trust boundary must remain explicit everywhere.

## Recommended execution order

1. Paste `00_MASTER_BUILD_PROMPT.md` into Codex first.
2. Run the contract prompts in numerical order from `01` through `10`.
3. Run `11_TourEngine.md` only after the settlement core passes all invariants.
4. Run `12_OFFCHAIN_SERVICES.md` to build Bitcoin verification, attestors, relayer, and solver.
5. Run `13_FRONTEND_AND_SDK.md` for the product surface.
6. Run `14_INTEGRATION_SECURITY_AND_DEPLOYMENT.md` last.

Each contract prompt is standalone enough to be run in a fresh Codex session, but Codex should always inspect the repository and reuse the shared types and interfaces already created.

## Hard launch gates

Do not deploy mainnet until all of these are true:

- the real Bitcoin Puppets inscription manifest has been independently verified and its Merkle root reproduced by at least two implementations;
- BIP-322 verification passes official vectors and wallet-specific compatibility tests;
- five genuinely independent verifier keys/operators exist;
- the three-of-five attestation path, replay protection, payout accounting, refund paths, solver bond, and BTC-output uniqueness have been audited;
- every core invariant passes under Foundry stateful fuzzing;
- Robinhood Chain testnet end-to-end tests pass;
- Bitcoin regtest end-to-end tests pass;
- the native-BTC solver remains feature-flagged off until legal and operational review is complete;
- admin roles are transferred to a multisig plus timelock and deployer privileges are revoked.

## Core file map

- `00_MASTER_BUILD_PROMPT.md` — orchestrates the full protocol build.
- `01_PUPPET_TYPES_AND_INTERFACES.md` — canonical structs, enums, hashing, and interfaces.
- `02_PUPPET_COLLECTION_REGISTRY.md` — immutable Merkle membership for canonical roots.
- `03_BITCOIN_ATTESTOR_REGISTRY.md` — verifier set, threshold, and epochs.
- `04_BITCOIN_OWNERSHIP_ORACLE.md` — EIP-712 quorum verification and replay protection.
- `05_PAYOUT_VAULT.md` — safe pull-payment accounting and gasless withdrawal authorization.
- `06_ROOT_OWNERSHIP_REGISTRY.md` — current Bitcoin owner epochs and recurring beneficiaries.
- `07_FEE_ROUTER.md` — immutable 50/25/25 economics.
- `08_HOODPUPS_NFT.md` — one ERC-721 per Bitcoin root, plus ERC-4907 user role.
- `09_HOODPUP_OFFER_ESCROW.md` — offers, self-casts, ETH settlement, refunds, and BTC approval.
- `10_BTC_SOLVER_SETTLEMENT.md` — bonded native-BTC payout and solver reimbursement.
- `11_TOUR_ENGINE.md` — temporary sending, check-ins, miles, and non-financial progression.
- `12_OFFCHAIN_SERVICES.md` — Bitcoin Core, ord, BIP-322, attestors, relayer, and solver.
- `13_FRONTEND_AND_SDK.md` — buyer, holder, payout, cold-wallet, and admin UX.
- `14_INTEGRATION_SECURITY_AND_DEPLOYMENT.md` — CI, invariants, regtest, testnet, deployment, and runbooks.

## Important product rule

No token, no stock basket, no market maker, no “utility later” switchblade hidden inside the stroller. The protocol must work and return value to Bitcoin Puppet owners before any extra financial object is considered.
