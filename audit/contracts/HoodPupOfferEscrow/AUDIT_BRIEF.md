# HoodPupOfferEscrow — audit brief

**Risk class:** CRITICAL — the largest attack surface, and it holds buyer funds.

| | |
|---|---|
| Source | `contracts/src/HoodPupOfferEscrow.sol` · 989 non-blank lines |
| Flattened | `HoodPupOfferEscrow.flat.sol` · 2510 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `c43cae74b4760064840f803f4f4545d596dc9bda5e3f1478e6d6e53718a015bc` |
| Commit | `82277b00b808d9fd324a129ccc80284e22609d4b` |
| Compiler | solc 0.8.28, evm shanghai, optimizer on (800 runs), via-IR off |

## What it does

The offer lifecycle: create, approve, settle, refund.

## Trust and authority

Timelock admin, guardian pause. Buyers deliberately cannot cancel an open offer.

## Invariants it must hold

1. Total deposited == refunds credited + distributions routed + still locked
2. No offer settles twice; no settled offer refunds
3. No BTC offer mints before finalizeBtcSettlement
4. One Root mints once, across competing offers
5. At most one active BTC reservation exists per Root, and every mint path consults that mutex
6. Refunds remain available while paused
7. The seller is paid the address inside the signed attestation and no other

## Where to look first

- Every attestation field is compared against stored terms — verify none is missed
- The terms-hash comparison, not merely field-by-field equality
- Reentrancy via ERC-721 onERC721Received during settlement
- Atomicity: mint, epoch record and fee routing must all succeed or all revert
- Why buyers cannot cancel: a holder may be minutes or hours into a cold-wallet signing ceremony, and a cancellable offer would let a buyer bait a valid signature then withdraw. Confirm no path reintroduces cancellation.

## Context worth having before you start

- This is **not** a trustless Bitcoin bridge. Bitcoin facts are asserted by a 3-of-5 quorum of
  independent verifier operators. `docs/TRUST_ASSUMPTIONS.md` states what that quorum can and
  cannot do. A report that "a colluding quorum can lie" describes the design, not a finding —
  the useful question is whether the blast radius is genuinely bounded as claimed.
- Core contracts are **non-upgradeable**. No proxy, no initializer, no delegatecall. There is no
  upgrade key to compromise, and equally no way to patch a finding in place.
- The findings from the prior whole-protocol review and their regression coverage are mapped in
  `docs/AUDIT_REMEDIATION.md`. Cross-contract seams remain the first place to challenge.

## Files in this bundle

| File | Purpose |
|---|---|
| `HoodPupOfferEscrow.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `HoodPupOfferEscrow.abi.json` | ABI. |
| `HoodPupOfferEscrow.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
