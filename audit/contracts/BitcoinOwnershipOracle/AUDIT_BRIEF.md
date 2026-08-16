# BitcoinOwnershipOracle — audit brief

**Risk class:** CRITICAL — this contract gates every mint and every payout in the protocol.

| | |
|---|---|
| Source | `contracts/src/BitcoinOwnershipOracle.sol` · 670 non-blank lines |
| Flattened | `BitcoinOwnershipOracle.flat.sol` · 4292 non-blank lines |
| Standalone compile | **verified** |
| sha256 (flattened) | `b834914b4824150f7bd7439f7a0539c2ee633b6a204694ae11ec5ea90265292f` |
| Commit | `10e4ce8b0c222196c6e9a3d5572c74bcb61149fb` |
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
5. Pause blocks consumption only; hashing and view verification stay live

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
- Two High-severity defects were already found and fixed internally, both by the integration
  suite rather than by unit tests. Both are written up in `docs/SECURITY_REVIEW.md`; the more
  instructive one is H-1, where every contract was individually correct and the violation existed
  only in the composition.

## Files in this bundle

| File | Purpose |
|---|---|
| `BitcoinOwnershipOracle.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |
| `BitcoinOwnershipOracle.abi.json` | ABI. |
| `BitcoinOwnershipOracle.storage.json` | Storage layout, for slot-packing and collision analysis. |
| `metadata.json` | Commit, compiler settings, source hashes. |
