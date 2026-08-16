# HoodPups — audit brief

**Risk class:** HIGH — the one-token-per-Root guarantee is the collection's entire integrity claim.

| | |
|---|---|
| Source | `contracts/src/HoodPups.sol` · 493 non-blank lines |
| Flattened | `HoodPups.flat.sol` · 4090 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `21aaac654920a5c8902527e5f7695e3a59d4348e422d874dd1bb592131344eb7` |
| Commit | `5d853a42604f54d71ffb0ac740302e5aa7e4adef` |
| Compiler | solc 0.8.28, evm shanghai, optimizer on (800 runs), via-IR off |

## What it does

ERC-721 plus ERC-4907. Each token permanently references exactly one Bitcoin Puppet inscription.

## Trust and authority

Timelock admin for metadata only. No burn, no admin remap, no root reassignment.

## Invariants it must hold

1. rootToToken is injective — no two tokens share a Root, and no Root maps to two tokens
2. rootMinted is permanent and cannot be cleared by anyone, including the deployer
3. Token ids start at 1, so tokenOfRoot() == 0 unambiguously means not minted
4. ERC-4907 user state clears on a real owner change
5. mintingPaused never affects transfers or the role-gated terminal BTC mint

## Where to look first

- The OpenZeppelin 5.x _update hook — confirm user clearing fires on a transfer but not spuriously on a mint
- Whether any path can mint a second token for a Root
- supportsInterface: confirm ERC721Enumerable is NOT advertised, since it is deliberately not inherited
- TOUR_ENGINE_ROLE setUser: can it be abused to grief an owner?

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
| `HoodPups.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `HoodPups.abi.json` | ABI. |
| `HoodPups.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
