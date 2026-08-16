# HoodPups Rooted Settlement Protocol — single-file audit bundle

Everything the protocol deploys, in one compilation unit.

| | |
|---|---|
| Commit | `64fe0d1ba8588d8d5f04f577b846c6d44f96b2e1` |
| Bundle | `HoodPupsProtocol.flat.sol` |
| SHA-256 | `34312f5298862bb29d7c999d12cbb8cab874a76d02465543b607120185cfb9b1` |
| Lines | 12,822 (11,327 non-blank) |
| Contracts | 10 protocol, 10 interfaces, 2 type/hash libraries, 32 vendored dependencies |
| Compiler | solc 0.8.28, evm `shanghai`, optimizer on at 800 runs, no viaIR |

## Compile it

No remappings, no `lib/`, no submodules. The bundle is self-contained.

```bash
solc --optimize --optimize-runs 800 --evm-version shanghai HoodPupsProtocol.flat.sol
```

Or with Foundry:

```bash
mkdir -p audit-check/src && cd audit-check
cp ../HoodPupsProtocol.flat.sol src/
printf '[profile.default]\nsrc = "src"\nlibs = []\nsolc = "0.8.28"\nevm_version = "shanghai"\noptimizer = true\noptimizer_runs = 800\n' > foundry.toml
forge build
```

The export script refuses to emit this file unless that build succeeds and all 10 protocol
contracts produce artifacts, so a failure here means the bundle was altered after export — check the
SHA-256 above before spending time on it.

## What this protocol is

One Bitcoin Puppet inscription may create at most one HoodPup. The inscription never leaves Bitcoin.
Ownership is proven by a BIP-322 signature over a canonical message, and every Bitcoin fact that
reaches these contracts arrives as an EIP-712 attestation carrying at least 3 signatures from a
5-member verifier quorum.

**This is an attested settlement system, not a trustless bridge.** The quorum is a trust assumption,
not a cryptographic guarantee — a colluding majority of verifiers can assert a Bitcoin fact that is
not true. That assumption is the single most important thing in this review. It is stated plainly
because an auditor who discovers it on page 40 has already wasted the first 39.

## Where to look first

| Order | Contract | Line | Why |
|---|---|---|---|
| 1 | `BitcoinOwnershipOracle` | 11,495 | Quorum verification, replay protection, one-time digest consumption. Everything else trusts this. |
| 2 | `HoodPupOfferEscrow` | 9,895 | The money path — offers, settlement, refunds, and the state machine between them. |
| 3 | `PayoutVault` | 12,249 | Pull-payment accounting. Refunds must survive a pause; a stuck refund is a lost user. |
| 4 | `RootOwnershipRegistry` | 8,814 | The one-root-one-pup invariant and ownership epochs. |

## Invariants the protocol claims

Each of these should be falsifiable by reading the code. If one is not enforced where you would
expect it to be, that is the finding.

1. One canonical root inscription binds to at most one HoodPup token, ever.
2. No Bitcoin fact is accepted below the quorum threshold, and no attestation digest is ever
   consumed twice.
3. Paid settlement splits exactly 50/25/25 — seller, Puppet treasury, protocol — with no rounding
   dust stranded or double-counted.
4. Refunds and withdrawals remain available while the protocol is paused. Pausing stops the protocol
   taking on **new** obligations; it must never trap funds a user is already owed.
5. The core contracts are non-upgradeable. No proxy, no delegatecall to mutable code, no admin path
   that rewrites settled state.

Invariant 4 is worth dwelling on: it was violated once during development in a way that all
single-contract tests passed. `PayoutVault.credit` is pausable and `withdraw` is not, which is
correct in isolation — but refunds routed through `credit`, so pausing the vault silently blocked
them. The fix was a separate non-pausable `creditRefund` entry point. Seams between contracts are
where the remaining bugs will be.

## Full contract index

The bundle's own header carries a line-numbered table of contents for all declarations, including
the vendored dependencies. The 10 protocol contracts are:

1. `PuppetCollectionRegistry` — line 6,088
2. `BitcoinAttestorRegistry` — line 6,315
3. `BitcoinOwnershipOracle` — line 11,495
4. `PayoutVault` — line 12,249
5. `RootOwnershipRegistry` — line 8,814
6. `FeeRouter` — line 6,828
7. `HoodPups` — line 10,939
8. `HoodPupOfferEscrow` — line 9,895
9. `BtcSolverSettlement` — line 8,011
10. `TourEngine` — line 7,395

## What is NOT in this bundle

- **Tests.** 836 Solidity tests (unit, fuzz, and handler-based stateful invariant) and 250
  TypeScript tests live in the repository, not here.
- **Off-chain services.** The Bitcoin verifier, attestor, relayer, and BTC solver are TypeScript and
  are out of scope for a Solidity review — but note that the quorum's honesty is enforced there, so
  a complete assessment of the trust model has to read them too.
- **Deployment scripts and role wiring.** `contracts/script/Deploy.s.sol` grants the roles that make
  these contracts safe together. A role-matrix mistake there is invisible in this file.
- **Vendored dependency review.** OpenZeppelin sources are included unmodified so the bundle
  compiles; they are not part of the intended review scope.

## Per-contract bundles

If reviewers are splitting work by contract, `./scripts/export-audit-package.sh` in the repository
produces ten separate bundles, each with its own flattened source, ABI, storage layout, and a brief
covering risk class, trust assumptions, and invariants.
