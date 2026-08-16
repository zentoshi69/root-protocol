#!/usr/bin/env python3
"""
Prepend an auditor's header — banner plus a line-numbered table of contents — to the single-file
flattened bundle, and emit the manifest describing it.

A 12k-line file with no map is hostile to review. The table of contents is generated from the file
itself rather than hand-maintained, so it cannot drift: every entry is a real declaration at a real
line, and the line numbers account for the header's own length.

Usage: single_file_header.py <flat.sol> <out.sol> <manifest.json> <commit> <dirty:0|1>
"""

import hashlib
import json
import re
import sys
from pathlib import Path

# The ten protocol contracts, in deployment-dependency order rather than alphabetical: an auditor
# reading top to bottom meets each contract after the things it depends on.
PROTOCOL_CONTRACTS = [
    "PuppetCollectionRegistry",
    "BitcoinAttestorRegistry",
    "BitcoinOwnershipOracle",
    "PayoutVault",
    "RootOwnershipRegistry",
    "FeeRouter",
    "HoodPups",
    "HoodPupOfferEscrow",
    "BtcSolverSettlement",
    "TourEngine",
]

COMPILER = {
    "solc": "0.8.28",
    "evmVersion": "shanghai",
    "optimizer": True,
    "optimizerRuns": 800,
    "viaIR": False,
}

DECL_RE = re.compile(r"^(?:abstract\s+)?(contract|library|interface)\s+(\w+)")

# Every declaration that is ours rather than a vendored dependency. Anything not matching is
# classified as a third-party dependency, so a newly added protocol file shows up in the
# dependency bucket and is noticed, rather than being silently absorbed into the protocol bucket.
PROTOCOL_PREFIXES = ("Puppet", "Bitcoin", "HoodPup", "BtcSolver", "Tour", "Fee", "Payout", "Root")


def classify(kind: str, name: str) -> str:
    if name in PROTOCOL_CONTRACTS:
        return "protocol"
    stripped = name[1:] if name.startswith("I") and len(name) > 1 and name[1].isupper() else name
    if stripped.startswith(PROTOCOL_PREFIXES) or name in ("PuppetTypes", "PuppetHashing"):
        return "interface" if kind == "interface" else "types"
    return "dependency"


def main() -> int:
    flat_path, out_path, manifest_path, commit, dirty = sys.argv[1:6]
    source = Path(flat_path).read_text()
    lines = source.splitlines()

    decls = []
    for i, line in enumerate(lines, start=1):
        m = DECL_RE.match(line)
        if m:
            kind, name = m.group(1), m.group(2)
            decls.append({"kind": kind, "name": name, "line": i, "group": classify(kind, name)})

    found = {d["name"] for d in decls}
    missing = [c for c in PROTOCOL_CONTRACTS if c not in found]
    if missing:
        sys.exit(f"single-file bundle is missing protocol contracts: {', '.join(missing)}")

    groups = {
        "protocol": "THE TEN PROTOCOL CONTRACTS",
        "interface": "PROTOCOL INTERFACES",
        "types": "PROTOCOL TYPES AND HASHING",
        "dependency": "THIRD-PARTY DEPENDENCIES (OpenZeppelin, unmodified)",
    }

    # Two passes. The table of contents cites line numbers in the FINAL file, but those depend on
    # how many lines the header itself occupies. So build it once to measure, then rebuild with the
    # offset applied. Rendering is deterministic, so the second pass is the same shape as the first
    # and the measurement holds.
    def render(offset: int) -> str:
        out = []
        w = out.append
        w("// HoodPups Rooted Settlement Protocol — complete protocol source, single file.")
        w("//")
        w("// License: MIT")
        w(f"// Commit:  {commit}")
        if dirty == "1":
            w("// WARNING: exported from a DIRTY working tree — this does not match the commit above.")
        w(
            f"// Compile: solc {COMPILER['solc']}, evm {COMPILER['evmVersion']}, "
            f"optimizer on, {COMPILER['optimizerRuns']} runs, no viaIR"
        )
        w("//")
        w("// This is every contract the protocol deploys, plus its dependencies, flattened and")
        w("// deduplicated into one compilation unit. It compiles standalone with no remappings and")
        w("// no lib/ directory; the export script refuses to emit this file unless it does.")
        w("//")
        w("// WHAT THIS PROTOCOL IS, IN ONE PARAGRAPH")
        w("//")
        w("// One Bitcoin Puppet inscription may create at most one HoodPup. The inscription never")
        w("// leaves Bitcoin. Ownership is proven by a BIP-322 signature over a canonical message,")
        w("// and every Bitcoin fact reaching these contracts is an EIP-712 attestation carrying at")
        w("// least 3 signatures from a 5-member verifier quorum. This is an ATTESTED settlement")
        w("// system, not a trustless bridge — the quorum is a trust assumption, and it is the")
        w("// single most important thing to review. See BitcoinOwnershipOracle first.")
        w("//")
        w("// WHERE TO LOOK FIRST")
        w("//")
        w("//   1. BitcoinOwnershipOracle  — quorum verification, replay protection, digest consumption")
        w("//   2. HoodPupOfferEscrow      — the money path: offers, settlement, refunds")
        w("//   3. PayoutVault             — pull-payment accounting; refunds must survive a pause")
        w("//   4. RootOwnershipRegistry   — the one-root-one-pup invariant and ownership epochs")
        w("//")
        w("// INVARIANTS THE PROTOCOL CLAIMS (each should be falsifiable by reading the code)")
        w("//")
        w("//   * One canonical root inscription binds to at most one HoodPup token, ever.")
        w("//   * No Bitcoin fact is accepted below the quorum threshold, and no attestation digest")
        w("//     is ever consumed twice.")
        w("//   * Paid settlement splits exactly 50/25/25 — seller, Puppet treasury, protocol — with")
        w("//     no rounding dust stranded or double-counted.")
        w("//   * Refunds and withdrawals remain available while the protocol is paused. Pausing")
        w("//     stops NEW obligations; it must never trap funds a user is already owed.")
        w("//   * The core contracts are non-upgradeable. There is no proxy, no delegatecall to")
        w("//     mutable code, and no admin path that rewrites settled state.")
        w("//")
        w("// TABLE OF CONTENTS")
        w("//")
        for key, title in groups.items():
            members = [d for d in decls if d["group"] == key]
            if not members:
                continue
            if key == "protocol":
                members = sorted(members, key=lambda d: PROTOCOL_CONTRACTS.index(d["name"]))
            w(f"//   {title}")
            for d in members:
                w(f"//     line {d['line'] + offset:>6}  {d['kind']:<9} {d['name']}")
            w("//")
        w("// Generated by scripts/export-single-file.sh — do not edit this file by hand.")
        w("")
        return "\n".join(out) + "\n"

    header_lines = render(0).count("\n")
    header = render(header_lines)
    if header.count("\n") != header_lines:
        sys.exit("header length changed between passes — table of contents line numbers unreliable")

    bundle = header + source
    Path(out_path).write_text(bundle)

    digest = hashlib.sha256(bundle.encode()).hexdigest()
    Path(manifest_path).write_text(
        json.dumps(
            {
                "package": "hoodpups-single-file-audit-bundle",
                "commit": commit,
                "dirtyWorkingTree": dirty == "1",
                "compiler": COMPILER,
                "bundle": {
                    "path": Path(out_path).name,
                    "sha256": digest,
                    "lines": bundle.count("\n"),
                    "nonBlankLines": sum(1 for line in bundle.splitlines() if line.strip()),
                    "standaloneCompile": "verified",
                },
                "protocolContracts": [
                    {"name": d["name"], "line": d["line"] + header_lines}
                    for d in sorted(
                        (d for d in decls if d["group"] == "protocol"),
                        key=lambda d: PROTOCOL_CONTRACTS.index(d["name"]),
                    )
                ],
                "declarationCounts": {
                    g: sum(1 for d in decls if d["group"] == g) for g in groups
                },
            },
            indent=2,
        )
        + "\n"
    )

    print(f"    header: {header_lines} lines, sha256 {digest[:16]}")
    for g, title in groups.items():
        print(f"    {title}: {sum(1 for d in decls if d['group'] == g)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
