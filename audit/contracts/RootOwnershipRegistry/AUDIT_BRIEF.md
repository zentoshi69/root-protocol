# RootOwnershipRegistry — audit brief

**Risk class:** HIGH — controls where recurring Root-linked value flows.

| | |
|---|---|
| Source | `contracts/src/RootOwnershipRegistry.sol` · 565 non-blank lines |
| Flattened | `RootOwnershipRegistry.flat.sol` · 1795 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `7d3e1a96b7bcebdbfe4e207f2eecea691d44594e3a70be99c457ce97cd90ad7a` |
| Commit | `10e4ce8b0c222196c6e9a3d5572c74bcb61149fb` |
| Compiler | solc 0.8.28, evm shanghai, optimizer on (800 runs), via-IR off |

## What it does

Bitcoin ownership epochs. Determines who receives recurring value, and handles what happens when a Puppet is sold on Bitcoin.

## Trust and authority

No admin can assign ownership. The only two sources are a consumed oracle attestation or the authorized escrow mint recorder.

## Invariants it must hold

1. At most one active beneficiary per Root
2. epoch is strictly monotonic
3. An inactive Root has no active beneficiary
4. Already-credited balances survive an epoch change untouched — money the previous owner earned stays theirs
5. Historical RootEpochInfo is never rewritten

## Where to look first

- The stale-watcher window: value accruing between a real Bitcoin sale and its attestation. This is disclosed, not hidden — assess whether the bound is as tight as claimed
- Whether invalidateRoot can be triggered against an outpoint other than the recorded live one
- Height-ordering checks — can an older attestation overwrite a newer epoch?
- The interaction with PayoutVault.releaseRootCredit on rebind

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
| `RootOwnershipRegistry.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `RootOwnershipRegistry.abi.json` | ABI. |
| `RootOwnershipRegistry.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
