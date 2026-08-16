#!/usr/bin/env python3
"""
Write the README that ships inside the single-file audit zip.

Generated rather than hand-written so the contract list, line numbers, and hashes in it are the ones
actually in the bundle. A README that drifts from its artifact is worse than no README.

Usage: single_file_readme.py <out_dir> <bundle_name> <commit>
"""

import json
import sys
from pathlib import Path

TEMPLATE = """# HoodPups Rooted Settlement Protocol — single-file audit bundle

Everything the protocol deploys, in one compilation unit.

| | |
|---|---|
| Commit | `{commit}` |
| Bundle | `{bundle}` |
| SHA-256 | `{sha}` |
| Lines | {lines:,} ({nonblank:,} non-blank) |
| Contracts | {n_protocol} protocol, {n_iface} interfaces, {n_types} type/hash libraries, {n_dep} vendored dependencies |
| Compiler | solc {solc}, evm `{evm}`, optimizer on at {runs} runs, no viaIR |

## Compile it

No remappings, no `lib/`, no submodules. The bundle is self-contained.

```bash
solc --optimize --optimize-runs {runs} --evm-version {evm} {bundle}
```

Or with Foundry:

```bash
mkdir -p audit-check/src && cd audit-check
cp ../{bundle} src/
printf '[profile.default]\\nsrc = "src"\\nlibs = []\\nsolc = "{solc}"\\nevm_version = "{evm}"\\noptimizer = true\\noptimizer_runs = {runs}\\n' > foundry.toml
forge build
```

The export script refuses to emit this file unless that build succeeds and all {n_protocol} protocol
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
| 1 | `BitcoinOwnershipOracle` | {line_oracle:,} | Quorum verification, replay protection, one-time digest consumption. Everything else trusts this. |
| 2 | `HoodPupOfferEscrow` | {line_escrow:,} | The money path — offers, settlement, refunds, and the state machine between them. |
| 3 | `PayoutVault` | {line_vault:,} | Pull-payment accounting. Refunds must survive a pause; a stuck refund is a lost user. |
| 4 | `RootOwnershipRegistry` | {line_registry:,} | The one-root-one-pup invariant and ownership epochs. |

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
the vendored dependencies. The {n_protocol} protocol contracts are:

{contract_table}

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
"""


def main() -> int:
    out_dir, bundle, commit = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    m = json.loads((out_dir / "MANIFEST.json").read_text())
    lines_by_name = {c["name"]: c["line"] for c in m["protocolContracts"]}

    table = "\n".join(
        f"{i}. `{c['name']}` — line {c['line']:,}"
        for i, c in enumerate(m["protocolContracts"], start=1)
    )

    (out_dir / "README.md").write_text(
        TEMPLATE.format(
            commit=commit,
            bundle=bundle,
            sha=m["bundle"]["sha256"],
            lines=m["bundle"]["lines"],
            nonblank=m["bundle"]["nonBlankLines"],
            n_protocol=m["declarationCounts"]["protocol"],
            n_iface=m["declarationCounts"]["interface"],
            n_types=m["declarationCounts"]["types"],
            n_dep=m["declarationCounts"]["dependency"],
            solc=m["compiler"]["solc"],
            evm=m["compiler"]["evmVersion"],
            runs=m["compiler"]["optimizerRuns"],
            line_oracle=lines_by_name["BitcoinOwnershipOracle"],
            line_escrow=lines_by_name["HoodPupOfferEscrow"],
            line_vault=lines_by_name["PayoutVault"],
            line_registry=lines_by_name["RootOwnershipRegistry"],
            contract_table=table,
        )
    )
    print(f"    README.md written ({len(m['protocolContracts'])} contracts indexed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
