# CODEX MASTER PROMPT — HOODPUPS FRONTEND AND PROTOCOL SDK

Build the user-facing application and typed SDK for the HoodPups Rooted Settlement Protocol. Inspect and preserve the existing design system and repository architecture.

## Product goal

Make the technical machine feel simple:

```text
Buyer makes offer → Bitcoin holder signs → holder gets paid → buyer receives HoodPup
```

The UI must never hide the actual trust and payment model.

## Shared SDK

Create a typed package that exports:

- contract addresses by chain ID;
- generated ABIs and typed clients;
- Root ID parser/formatter;
- root key, outpoint hash, script hash, payment output key;
- Merkle proof lookup;
- offer terms hash;
- EIP-712 attestation schemas/digests;
- canonical BIP-322 message generator/parser;
- amount split calculator;
- offer and solver state-machine helpers;
- event decoders;
- validation schemas;
- golden vectors shared with Solidity and verifier services.

No SDK function may silently normalize an invalid txid, address, or amount. Return explicit errors.

## Buyer flow

Build screens for:

1. select or enter a canonical Bitcoin Puppet root;
2. confirm it is in the protocol manifest;
3. choose recipient on Robinhood Chain;
4. choose payout mode:
   - holder receives ETH on Robinhood Chain;
   - holder receives exact native BTC through solver;
5. for BTC mode, display exact sats, exact seller reimbursement in ETH, expiry, and solver risk;
6. display fixed 50/25/25 split;
7. create offer;
8. show offer timeline and refund eligibility.

Never label the BTC mode as an atomic trustless swap.

## Bitcoin holder flow

Build a claim/approval page that:

1. loads the exact on-chain offer;
2. shows the original inscription, root ID, buyer, recipient, gross, seller amount, treasury amount, protocol amount, and expiry;
3. lets the holder choose:
   - EVM payout address, or
   - Bitcoin payout address/script for BTC mode;
4. generates the exact canonical signing message;
5. supports connected-wallet BIP-322 signing where available;
6. supports offline/cold-wallet export/import or QR flow;
7. never asks for a seed or private key;
8. submits only the signature/proof;
9. displays verifier/attestor progress;
10. shows final credit, BTC transaction output, or rejection reason.

For unsupported wallets, say the wallet cannot sign the required proof. Do not suggest importing the seed into the app.

## PayoutVault flow

Show claimable ETH and implement:

- normal withdraw;
- withdraw all;
- gas-sponsored withdrawal authorization;
- destination confirmation;
- clear distinction between claimable credit and wallet balance.

## Root ownership flow

Show:

- active/inactive verification state;
- current epoch;
- beneficiary;
- verified Bitcoin height/outpoint hash;
- pending Root fees;
- re-verification after the inscription moves.

Make clear that watcher/attestor updates can lag Bitcoin.

## HoodPup and tour flow

Show permanent Bitcoin root provenance, token owner, temporary user, tour expiry, miles, and travel events.

Implement:

- start tour;
- recipient check-in;
- finalize/clean up;
- no token or cash-reward language;
- warning that wallet uniqueness is not proof of unique humanity.

## Account abstraction

Integrate Robinhood Chain-supported account abstraction through the existing provider architecture when available. Use gas sponsorship only for allowlisted actions:

- self-cast settlement submission;
- proof submission relay;
- PayoutVault withdrawal authorization;
- tour check-in.

Add spend limits, rate limits, and server-side policy. Do not build a custom paymaster unless the existing stack requires it.

## Admin/operations console

Read-only by default. Show:

- verifier health and chain heights;
- attestor epoch/policy;
- offer states;
- solver reservations;
- stuck transactions;
- Root invalidations;
- contract pauses and roles;
- treasury and protocol credits.

Any privileged action must show timelock delay and target calldata. Do not add a secret direct-admin button.

## Testing

Add unit and end-to-end tests for:

- canonical message rendering;
- wrong field mutation;
- split calculation;
- offer creation;
- connected and offline proof flows;
- rejected proof;
- refund;
- gasless withdrawal;
- BTC solver timeline;
- root moved/inactive state;
- tour lifecycle;
- accessibility and destructive-action confirmations.

## Required copy

Prominently state:

- “Your Bitcoin Puppet never leaves Bitcoin.”
- “A 3-of-5 verifier quorum confirms ownership and BTC payments.”
- “ETH payout is on Robinhood Chain.”
- “BTC payout is native Bitcoin sent by a bonded solver.”
- “One verified HoodPup may be minted per protocol Root.”

Do not state or imply official Bitcoin Puppets or Robinhood endorsement unless separately authorized.

Run build, typecheck, tests, and end-to-end tests. Return screenshots or route descriptions, exact commands, and remaining UX risks.
