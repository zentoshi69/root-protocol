# HoodPups — audit brief

**Risk class:** HIGH — the one-token-per-Root guarantee is the collection's entire integrity claim.

| | |
|---|---|
| Source | `contracts/src/HoodPups.sol` · 477 non-blank lines |
| Flattened | `HoodPups.flat.sol` · 4065 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `bbfae65d823d4b703f4d9e90e8dd9a4104ae42fefb754538f200d71650fbd334` |
| Commit | `10e4ce8b0c222196c6e9a3d5572c74bcb61149fb` |
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
5. mintingPaused never affects transfers

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
- Two High-severity defects were already found and fixed internally, both by the integration
  suite rather than by unit tests. Both are written up in `docs/SECURITY_REVIEW.md`; the more
  instructive one is H-1, where every contract was individually correct and the violation existed
  only in the composition.

## Files in this bundle

| File | Purpose |
|---|---|
| `HoodPups.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `HoodPups.abi.json` | ABI. |
| `HoodPups.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
