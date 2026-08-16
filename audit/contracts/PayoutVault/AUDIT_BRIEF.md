# PayoutVault — audit brief

**Risk class:** CRITICAL — this contract holds all protocol ETH.

| | |
|---|---|
| Source | `contracts/src/PayoutVault.sol` · 551 non-blank lines |
| Flattened | `PayoutVault.flat.sol` · 4239 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `8427a0dc5e54a2efd073bea283c9dd0f664af397104dbd48cf87003738bf3b63` |
| Commit | `dde0ec7c8ed5f2f1dbadb9c099a08a8d702d912b` |
| Compiler | solc 0.8.28, evm shanghai, optimizer on (800 runs), via-IR off |

## What it does

Pull-payment accounting for every ETH obligation the protocol creates, including ERC-1271-aware gasless withdrawal so a seller holding zero ETH can still be paid.

## Trust and authority

Timelock admin, but no admin path can reduce a user balance — there is no such function. sweepExcess is bounded to balance minus totalLiability, which by construction is only force-sent ETH.

## Invariants it must hold

1. address(this).balance >= totalLiability() at all times
2. totalLiability == sum(claimable) + sum(pendingByRoot)
3. No withdrawal path is pausable
4. creditRefund and terminal credits are deliberately NOT pausable
5. releaseRootCredit moves pendingByRoot to claimable without changing totalLiability or moving ETH

## Where to look first

- Reentrancy on every withdrawal path, particularly withdrawWithAuthorization
- Whether the nonce increments strictly before the external call
- SignatureChecker / ERC-1271 handling for smart-account beneficiaries
- sweepExcess arithmetic — can it ever reach a liability under any ordering?
- creditRefund specifically: confirm it can only release obligations, never create new ones, since it bypasses the pause

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
| `PayoutVault.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `PayoutVault.abi.json` | ABI. |
| `PayoutVault.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
