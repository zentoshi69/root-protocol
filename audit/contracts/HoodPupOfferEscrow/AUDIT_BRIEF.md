# HoodPupOfferEscrow — audit brief

**Risk class:** CRITICAL — the largest attack surface, and it holds buyer funds.

| | |
|---|---|
| Source | `contracts/src/HoodPupOfferEscrow.sol` · 959 non-blank lines |
| Flattened | `HoodPupOfferEscrow.flat.sol` · 2453 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `99ac3216143a89b40cc1cdc427739008f6c570f1c1bc598ea8d98ad0497c36c2` |
| Commit | `10e4ce8b0c222196c6e9a3d5572c74bcb61149fb` |
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
5. Refunds remain available while paused
6. The seller is paid the address inside the signed attestation and no other

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
- Two High-severity defects were already found and fixed internally, both by the integration
  suite rather than by unit tests. Both are written up in `docs/SECURITY_REVIEW.md`; the more
  instructive one is H-1, where every contract was individually correct and the violation existed
  only in the composition.

## Files in this bundle

| File | Purpose |
|---|---|
| `HoodPupOfferEscrow.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `HoodPupOfferEscrow.abi.json` | ABI. |
| `HoodPupOfferEscrow.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
