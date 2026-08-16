# CODEX MASTER PROMPT — OFF-CHAIN BITCOIN VERIFIER, ATTESTORS, RELAYER, AND SOLVER

Build the complete off-chain system required by the HoodPups contracts. Inspect the repository first and integrate with existing language/tooling. Prefer a small number of well-defined services over one giant backend.

## Non-negotiable security rules

- Never request, receive, log, transmit, or store a Bitcoin seed phrase or private key.
- The user signs locally in their wallet or hardware device.
- Do not trust a public Ordinals API as the sole source of truth.
- Production verifier instances use their own Bitcoin Core and `ord` nodes.
- Five attestors must independently recompute the result; one central API returning a boolean to all five is not independence.
- Pin BIP-322 dependencies exactly and wrap them behind a project-owned adapter.
- Pass official BIP-322 vectors and project golden vectors before accepting a proof.
- Treat txid byte order, script serialization, and canonical message line endings as security-critical.
- Never sign an attestation if any field was inferred rather than explicitly bound.

# Service A — Bitcoin verifier

Create a service or library with functions conceptually equivalent to:

```text
verifyOwnershipAuthorization(input) -> VerifiedOwnershipFact
verifyBitcoinPayment(input) -> VerifiedPaymentFact
verifyRootSpend(input) -> VerifiedRootSpendFact
```

## Inputs for ownership

- canonical Root ID;
- current claimed outpoint;
- exact canonical authorization message;
- BIP-322 signature and declared variant;
- expected offer terms from Robinhood Chain RPC;
- expected collection membership;
- policy version.

## Ownership verification steps

1. Parse txids/indexes with one canonical byte-order implementation.
2. Read the inscription from `ord /inscription/<id>`.
3. Read its current satpoint and containing output.
4. Read the output from `ord /output/<outpoint>`.
5. Confirm the output contains the exact inscription.
6. Query Bitcoin Core for the same transaction/output and unspent status.
7. Confirm current chain tip and minimum confirmation policy.
8. Check mempool for a spend of the claimed UTXO.
9. Extract exact raw scriptPubKey bytes.
10. Verify the BIP-322 signature against the exact canonical message and script/address.
11. Verify every offer field against the Robinhood Chain contract.
12. Recompute root key, terms hash, outpoint hash, script hash, and proof hash.
13. Return a deterministic typed fact set or a structured rejection code.

Do not call a signature valid merely because a wallet library returns true. Add defense-in-depth checks around script/address binding and test all supported script types.

Support only script types proven by tests. Start with the script types actually used by Bitcoin Puppets. Reject unsupported timelock or exotic scripts rather than guessing.

# Canonical BIP-322 message

Implement one shared generator/parser package. Use ASCII keys, lowercase hex, decimal integers, LF line endings, no trailing spaces, and a final LF. The message format must be versioned.

Required semantic fields:

```text
HOODPUPS AUTHORIZATION V1
purpose
bitcoin_network
root_txid
root_index
current_outpoint_txid
current_outpoint_vout
rh_chain_id
verifying_contract
context_id
offer_terms_hash
buyer
recipient
payout_mode
evm_payout
btc_payout_script_hash
seller_sats
gross_wei
seller_wei
authorization_id
expires_at
```

Use an exact fixed order. Zero values must be rendered canonically rather than omitted. Show the full human-readable terms before the wallet signs.

The attestation field `bip322ProofHash` must commit deterministically to the normalized signature/proof bytes. Define the normalization and include golden tests.

# Service B — independent attestor

One codebase runs as five independent deployments with separate:

- Bitcoin Core node or independently trusted node boundary;
- `ord` indexer;
- database/audit log;
- EVM attestor private key;
- network endpoint;
- operator.

Each instance:

1. fetches the on-chain offer itself;
2. reruns the full Bitcoin verification;
3. checks current attestor epoch and policy version;
4. computes the exact EIP-712 digest using generated contract types;
5. signs only the digest it independently verified;
6. records inputs, node heights, result, digest, signature, and rejection code;
7. exposes read-only health and attestation retrieval APIs.

Never let the requester send an arbitrary digest for blind signing.

Use a signer abstraction that can later move keys into HSM/KMS. Local development may use encrypted test keys only.

# Service C — relayer/aggregator

The relayer:

- watches offers and user proof submissions;
- requests attestations from all configured operators;
- requires at least the on-chain threshold of byte-identical facts;
- rejects mixed facts even if each has a valid signature;
- sorts recovered EVM signer addresses strictly ascending;
- simulates the target transaction before broadcast;
- submits idempotently;
- stores transaction hash and final status;
- retries safely after RPC failures;
- does not modify payout or recipient fields.

Expose a status model the frontend can display:

```text
PROOF_RECEIVED
VERIFYING
ATTESTATIONS_1_OF_3
ATTESTATIONS_2_OF_3
READY_TO_SUBMIT
SUBMITTED
CONFIRMED
REJECTED
EXPIRED
```

# Service D — BTC solver

Feature-flag off by default outside regtest/testnet.

The solver:

1. watches `BTC_APPROVED` offers;
2. reads fixed `sellerSats` and `sellerWei`;
3. applies its own spread/risk policy;
4. reserves with the required bond;
5. constructs a Bitcoin transaction paying the exact approved script and sats;
6. uses a separate operational BTC wallet, never the user’s inscription wallet;
7. broadcasts and tracks the transaction;
8. requests independent payment attestations after the configured confirmation policy;
9. submits settlement;
10. reconciles BTC spent, ETH reimbursement, bond return, network fee, and profit/loss.

Use PSBT and hardware/HSM-compatible signing architecture for production. Never hardcode a seed in environment files.

# Data storage

Use a relational schema with idempotency keys and immutable audit rows for:

- roots;
- offers;
- proof submissions;
- verifier runs;
- attestor facts/signatures;
- relayer submissions;
- solver reservations;
- Bitcoin transactions/outputs;
- EVM transactions;
- policy versions;
- incident flags.

Do not store more personal data than necessary.

# APIs

Design versioned endpoints such as:

```text
POST /v1/ownership/challenge
POST /v1/ownership/proof
GET  /v1/ownership/:authorizationId
GET  /v1/offers/:offerId/status
GET  /v1/attestations/:digest
GET  /health
```

The solver may use a private authenticated API. Add rate limits, request size limits, schema validation, structured errors, and correlation IDs.

# Regtest integration

Provide Docker Compose and scripts that:

1. start Bitcoin Core regtest;
2. start `ord` with indexes required by the verifier;
3. mine funds;
4. create test inscriptions;
5. move an inscription to a new UTXO;
6. create canonical BIP-322 proofs;
7. run five attestor instances;
8. run a relayer;
9. run a solver;
10. execute EVM and native-BTC settlement against Anvil or Robinhood Chain testnet.

# Tests

Include:

- official BIP-322 vectors;
- project vectors for P2TR and any other supported script;
- invalid key/script binding;
- mutated message field;
- changed payout address;
- stale outpoint;
- mempool spend;
- chain reorg simulation where practical;
- wrong txid byte order;
- wrong sat amount;
- wrong BTC output index;
- multiple outputs with similar amounts;
- attestors disagreeing;
- relayer duplicate submission;
- solver timeout and replacement;
- no secret leakage in logs.

# Definition of done

Run all tests, document exact supported wallet/script formats, generate API documentation, and provide a local command that performs a complete regtest flow from offer creation to HoodPup mint and payout reconciliation.
