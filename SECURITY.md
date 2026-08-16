# Security Policy

## Reporting a vulnerability

**Do not open a public issue.** Email the disclosure contact published in the project's release
notes, or use GitHub's private vulnerability reporting on this repository.

Please include: the affected component, the impact, a reproduction (a Foundry test is ideal), and
whether you believe it is being actively exploited.

We aim to acknowledge within 48 hours and to give an initial severity assessment within five
business days.

## Scope

**In scope**

- The ten Robinhood Chain contracts under `contracts/src/`
- The canonical message format and `bip322ProofHash` derivation
- The protocol SDK's hashing and EIP-712 derivations
- The verifier, attestor, relayer and solver services
- Any divergence between Solidity and an off-chain implementation of the same hash

**Out of scope**

- The 3-of-5 trust assumption itself. It is documented, deliberate, and stated everywhere. A report
  that "a colluding quorum can lie" is describing the design, not a vulnerability.
- Third-party wallet, node or indexer bugs, unless we mishandle their output.
- Anything requiring a user to disclose a seed phrase. We never ask for one and neither should
  anyone else.
- Testnet or regtest keys and fixtures, which are deliberately public.

## What we consider critical

- Any path that moves, spends or encumbers a user's Bitcoin inscription. *This should be
  structurally impossible — the protocol holds no Bitcoin key.*
- Minting two HoodPups for one Root.
- Reusing one Bitcoin payment output across two settlements.
- Replaying a consumed attestation digest.
- Redirecting a seller's payout away from the address they signed.
- Draining or locking `PayoutVault`, or any path where its liability exceeds its balance.
- Any admin path that reduces a user's claimable balance.
- Reaching quorum with fewer than `threshold` distinct authorized signers.

## Bug bounty

A bounty program and its terms will be published before mainnet launch. It is one of the launch
gates in [`docs/DEPLOYMENT.md`](./docs/DEPLOYMENT.md).

## Our commitments

- We will not take legal action against good-faith research within this scope.
- We will credit you, unless you prefer otherwise.
- We will publish a post-mortem for any exploited vulnerability, including what our existing
  controls failed to catch.

## Secrets

This repository contains **no production keys**. If you find key material committed here, that is
itself a critical report — please tell us immediately.
