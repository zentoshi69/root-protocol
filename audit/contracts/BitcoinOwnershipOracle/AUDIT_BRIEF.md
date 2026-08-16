# BitcoinOwnershipOracle — audit brief

**Risk class:** CRITICAL — this contract gates every mint and every payout in the protocol.

| | |
|---|---|
| Source | `contracts/src/BitcoinOwnershipOracle.sol` · 684 non-blank lines |
| Flattened | `BitcoinOwnershipOracle.flat.sol` · 4310 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `2d814fbd2f5d32405dbe6e972ef625d7f1d5c31179e35c417de5ae8241fc6339` |
| Commit | `5d853a42604f54d71ffb0ac740302e5aa7e4adef` |
| Compiler | solc 0.8.28, evm shanghai, optimizer on (800 runs), via-IR off |

## What it does

Converts a 3-of-5 quorum of EIP-712 attestations into one-time-consumable authorizations. It verifies SIGNATURES, never Bitcoin — it cannot check a BIP-322 proof, an inscription location or a UTXO set, and does not pretend to.

## Trust and authority

A colluding 3-of-5 quorum can assert a false Bitcoin fact. It can never move a Bitcoin asset. This is the protocol's conceded trust boundary, documented in docs/TRUST_ASSUMPTIONS.md.

## Invariants it must hold

1. A digest can be consumed at most once, ever
2. A Bitcoin txid:vout can be consumed at most once, globally across all offers
3. Recovered signer addresses must be strictly ascending
4. Consumption requires BOTH the consumer role AND the per-consumer purpose bit
5. Pause blocks ownership and Root-spend consumption; terminal BTC payment consumption stays live

## Where to look first

- REVIEW THIS CONTRACT FIRST AND HARDEST. It is the highest-value target in the package.
- Signature malleability, and whether the ECDSA.tryRecover error path can be made to accept
- Whether the strictly-ascending rule genuinely makes duplicate signers impossible in every path
- Whether digest consumption and paymentOutputKey consumption are truly atomic — a path consuming one without the other would let a single BTC payment settle two offers
- EIP-712 domain separation across chainId and verifyingContract, including a second deployment on the same chain
- The per-consumer purpose mask: can any consumer reach a purpose it was not granted? Note the mask fails closed and is set at deploy time via grantOwnershipConsumer

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
| `BitcoinOwnershipOracle.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `BitcoinOwnershipOracle.abi.json` | ABI. |
| `BitcoinOwnershipOracle.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
