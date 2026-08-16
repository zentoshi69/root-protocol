#!/usr/bin/env python3
"""Generate one audit brief per contract.

A flattened .sol file on its own is a dump, not a package. An auditor arriving cold needs to know
what the contract is *for*, what authority it holds, which invariants are load-bearing, and where the
sharp edges are — otherwise the first two days go into reconstructing context the team already had.

Every brief also carries the disclosure that two High-severity defects were already found and fixed
internally, and that a colluding 3-of-5 quorum lying is the conceded design, not a finding. Stating
both up front costs nothing and stops an auditor spending a day writing up a known trade-off.
"""

import json
import pathlib
import sys

BRIEFS = {
    "PuppetCollectionRegistry": dict(
        risk="LOW — no state can change after deployment. The exposure is entirely in whether the committed manifest was correct, which is a process gate rather than a code property.",
        purpose="Immutable Merkle membership for the canonical Bitcoin Puppets manifest. It answers exactly one question — is this inscription in the set this deployment committed to? — and knows nothing about who currently owns it.",
        trust="No admin, no owner, no upgrade path. The Merkle root is fixed at construction and can never change.",
        invariants=[
            "Membership cannot be added or removed after deployment, by anyone",
            "leaf = keccak256(rootKey) — double-hashed, so a 64-byte internal node preimage can never be presented as a 32-byte leaf",
            "Sibling inscriptions sharing a reveal txid produce distinct rootKeys",
        ],
        focus=[
            "Merkle verification against OpenZeppelin's sorted-pair convention",
            "Whether the double-hashed leaf genuinely defeats second-preimage attacks",
            "Constructor validation — a zero root would make every proof fail permanently, with no recovery",
        ],
    ),
    "BitcoinAttestorRegistry": dict(
        risk="MEDIUM — a governance error here weakens quorum. It cannot directly move funds.",
        purpose="Membership, threshold, epoch and policy version for the five-operator verifier set.",
        trust="Timelock admin. Every mutation bumps attestorEpoch, which instantly invalidates all in-flight attestation signatures.",
        invariants=[
            "5 <= attestorCount <= 32 at all times",
            "3 <= threshold <= attestorCount at all times",
            "Every membership, threshold or policy change increments attestorEpoch exactly once",
            "replaceAttestor is atomic and never transiently drops below the minimum",
        ],
        focus=[
            "Whether any mutation path can leave threshold > count",
            "Whether the epoch can fail to bump on a state-changing path — that would leave a window in which a removed operator still counts toward quorum, which is precisely what an attacker would aim for",
            "EnumerableSet removal semantics, particularly swap-and-pop during iteration",
        ],
    ),
    "BitcoinOwnershipOracle": dict(
        risk="CRITICAL — this contract gates every mint and every payout in the protocol.",
        purpose="Converts a 3-of-5 quorum of EIP-712 attestations into one-time-consumable authorizations. It verifies SIGNATURES, never Bitcoin — it cannot check a BIP-322 proof, an inscription location or a UTXO set, and does not pretend to.",
        trust="A colluding 3-of-5 quorum can assert a false Bitcoin fact. It can never move a Bitcoin asset. This is the protocol's conceded trust boundary, documented in docs/TRUST_ASSUMPTIONS.md.",
        invariants=[
            "A digest can be consumed at most once, ever",
            "A Bitcoin txid:vout can be consumed at most once, globally across all offers",
            "Recovered signer addresses must be strictly ascending",
            "Consumption requires BOTH the consumer role AND the per-consumer purpose bit",
            "Pause blocks consumption only; hashing and view verification stay live",
        ],
        focus=[
            "REVIEW THIS CONTRACT FIRST AND HARDEST. It is the highest-value target in the package.",
            "Signature malleability, and whether the ECDSA.tryRecover error path can be made to accept",
            "Whether the strictly-ascending rule genuinely makes duplicate signers impossible in every path",
            "Whether digest consumption and paymentOutputKey consumption are truly atomic — a path consuming one without the other would let a single BTC payment settle two offers",
            "EIP-712 domain separation across chainId and verifyingContract, including a second deployment on the same chain",
            "The per-consumer purpose mask: can any consumer reach a purpose it was not granted? Note the mask fails closed and is set at deploy time via grantOwnershipConsumer",
        ],
    ),
    "PayoutVault": dict(
        risk="CRITICAL — this contract holds all protocol ETH.",
        purpose="Pull-payment accounting for every ETH obligation the protocol creates, including ERC-1271-aware gasless withdrawal so a seller holding zero ETH can still be paid.",
        trust="Timelock admin, but no admin path can reduce a user balance — there is no such function. sweepExcess is bounded to balance minus totalLiability, which by construction is only force-sent ETH.",
        invariants=[
            "address(this).balance >= totalLiability() at all times",
            "totalLiability == sum(claimable) + sum(pendingByRoot)",
            "No withdrawal path is pausable",
            "creditRefund is deliberately NOT pausable — see finding H-1 in docs/SECURITY_REVIEW.md",
            "releaseRootCredit moves pendingByRoot to claimable without changing totalLiability or moving ETH",
        ],
        focus=[
            "Reentrancy on every withdrawal path, particularly withdrawWithAuthorization",
            "Whether the nonce increments strictly before the external call",
            "SignatureChecker / ERC-1271 handling for smart-account beneficiaries",
            "sweepExcess arithmetic — can it ever reach a liability under any ordering?",
            "creditRefund specifically: confirm it can only release obligations, never create new ones, since it bypasses the pause",
        ],
    ),
    "RootOwnershipRegistry": dict(
        risk="HIGH — controls where recurring Root-linked value flows.",
        purpose="Bitcoin ownership epochs. Determines who receives recurring value, and handles what happens when a Puppet is sold on Bitcoin.",
        trust="No admin can assign ownership. The only two sources are a consumed oracle attestation or the authorized escrow mint recorder.",
        invariants=[
            "At most one active beneficiary per Root",
            "epoch is strictly monotonic",
            "An inactive Root has no active beneficiary",
            "Already-credited balances survive an epoch change untouched — money the previous owner earned stays theirs",
            "Historical RootEpochInfo is never rewritten",
        ],
        focus=[
            "The stale-watcher window: value accruing between a real Bitcoin sale and its attestation. This is disclosed, not hidden — assess whether the bound is as tight as claimed",
            "Whether invalidateRoot can be triggered against an outpoint other than the recorded live one",
            "Height-ordering checks — can an older attestation overwrite a newer epoch?",
            "The interaction with PayoutVault.releaseRootCredit on rebind",
        ],
    ),
    "FeeRouter": dict(
        risk="MEDIUM — an arithmetic error here leaks value on every settlement.",
        purpose="The immutable 50 / 25 / 25 split. Holds no ETH after any call.",
        trust="Percentages are compile-time constants with no setter and no upgrade path. Only the two treasury destinations are governable, via timelock, and only for future routing.",
        invariants=[
            "seller + puppetTreasury + protocol == gross, exactly, for every input",
            "Router balance is zero after every successful route",
            "Percentages cannot change by any path",
        ],
        focus=[
            "Conservation at 1, 2 and 3 wei, where three independent floor divisions would strand dust permanently",
            "Confirm no setter, no upgrade and no delegatecall can reach the BPS constants",
            "The BTC route credits the SOLVER rather than the seller, because the seller was already paid in BTC — verify that is unambiguous and cannot be inverted",
        ],
    ),
    "HoodPups": dict(
        risk="HIGH — the one-token-per-Root guarantee is the collection's entire integrity claim.",
        purpose="ERC-721 plus ERC-4907. Each token permanently references exactly one Bitcoin Puppet inscription.",
        trust="Timelock admin for metadata only. No burn, no admin remap, no root reassignment.",
        invariants=[
            "rootToToken is injective — no two tokens share a Root, and no Root maps to two tokens",
            "rootMinted is permanent and cannot be cleared by anyone, including the deployer",
            "Token ids start at 1, so tokenOfRoot() == 0 unambiguously means not minted",
            "ERC-4907 user state clears on a real owner change",
            "mintingPaused never affects transfers",
        ],
        focus=[
            "The OpenZeppelin 5.x _update hook — confirm user clearing fires on a transfer but not spuriously on a mint",
            "Whether any path can mint a second token for a Root",
            "supportsInterface: confirm ERC721Enumerable is NOT advertised, since it is deliberately not inherited",
            "TOUR_ENGINE_ROLE setUser: can it be abused to grief an owner?",
        ],
    ),
    "HoodPupOfferEscrow": dict(
        risk="CRITICAL — the largest attack surface, and it holds buyer funds.",
        purpose="The offer lifecycle: create, approve, settle, refund.",
        trust="Timelock admin, guardian pause. Buyers deliberately cannot cancel an open offer.",
        invariants=[
            "Total deposited == refunds credited + distributions routed + still locked",
            "No offer settles twice; no settled offer refunds",
            "No BTC offer mints before finalizeBtcSettlement",
            "One Root mints once, across competing offers",
            "Refunds remain available while paused",
            "The seller is paid the address inside the signed attestation and no other",
        ],
        focus=[
            "Every attestation field is compared against stored terms — verify none is missed",
            "The terms-hash comparison, not merely field-by-field equality",
            "Reentrancy via ERC-721 onERC721Received during settlement",
            "Atomicity: mint, epoch record and fee routing must all succeed or all revert",
            "Why buyers cannot cancel: a holder may be minutes or hours into a cold-wallet signing ceremony, and a cancellable offer would let a buyer bait a valid signature then withdraw. Confirm no path reintroduces cancellation.",
        ],
    ),
    "BtcSolverSettlement": dict(
        risk="HIGH — feature-flagged off at launch, but holds solver bonds when enabled.",
        purpose="Bonded solvers front exact native BTC to a seller and are reimbursed in ETH after a 3-of-5 payment attestation.",
        trust="No price oracle anywhere, by design. No admin can choose a solver or forgive an individual reservation — either would be a rug lever.",
        invariants=[
            "Every wei of every bond is at all times in exactly one of: active reservation, returned credit, slash credit",
            "buyerCompensation + protocolAmount == bond, exactly, with no dust",
            "Reimbursement requires msg.sender to be the reserved solver AND the attested solver",
            "Terms are snapshotted at reservation, so later config changes cannot alter an in-flight reservation",
        ],
        focus=[
            "Bond conservation across both the settle and slash paths",
            "Whether a permissionless relayer can redirect a solver's reimbursement",
            "Whether reservationDuration can be configured shorter than the verifiers' confirmation policy — that combination loses a solver both its bond and its BTC, the worst outcome available in the protocol",
            "Ordering: reimbursement must not precede oracle consumption and mint finalization",
        ],
    ),
    "TourEngine": dict(
        risk="LOW — non-financial. Worst case is a farmed miles counter.",
        purpose="Temporary ERC-4907 lending. Produces provenance and a miles counter — no token, no cash, no claim on revenue.",
        trust="Timelock admin for season and duration bounds. Cannot move or transfer any NFT.",
        invariants=[
            "miles increments only via a finalized, checked-in tour",
            "Never more than once for the same (token, season, recipient) tuple",
            "No credit when the owner changes mid-tour or the user role is tampered with",
        ],
        focus=[
            "Anti-farm boundaries stop naive repeat loops, not Sybils — confirm the contract nowhere claims to prove unique humanity, because it cannot",
            "Whether cancelInvalidTour can be used to grief a legitimate tour",
            "The interaction with HoodPups.setUser under TOUR_ENGINE_ROLE",
        ],
    ),
}

SHARED_CONTEXT = [
    "- This is **not** a trustless Bitcoin bridge. Bitcoin facts are asserted by a 3-of-5 quorum of",
    "  independent verifier operators. `docs/TRUST_ASSUMPTIONS.md` states what that quorum can and",
    '  cannot do. A report that "a colluding quorum can lie" describes the design, not a finding —',
    "  the useful question is whether the blast radius is genuinely bounded as claimed.",
    "- Core contracts are **non-upgradeable**. No proxy, no initializer, no delegatecall. There is no",
    "  upgrade key to compromise, and equally no way to patch a finding in place.",
    "- Two High-severity defects were already found and fixed internally, both by the integration",
    "  suite rather than by unit tests. Both are written up in `docs/SECURITY_REVIEW.md`; the more",
    "  instructive one is H-1, where every contract was individually correct and the violation existed",
    "  only in the composition.",
]


def main(out_dir: str) -> int:
    out = pathlib.Path(out_dir)
    manifest = json.loads((out / "MANIFEST.json").read_text())
    by_name = {c["contract"]: c for c in manifest["contracts"]}

    missing = set(by_name) - set(BRIEFS)
    if missing:
        sys.exit(f"no audit brief defined for: {', '.join(sorted(missing))}")

    for name, brief in BRIEFS.items():
        meta = by_name[name]
        flat, src, comp = meta["flattened"], meta["source"], meta["compiler"]

        lines = [
            f"# {name} — audit brief",
            "",
            f"**Risk class:** {brief['risk']}",
            "",
            "| | |",
            "|---|---|",
            f"| Source | `{src['path']}` · {src['nonBlankLines']} non-blank lines |",
            f"| Flattened | `{name}.flat.sol` · {flat['nonBlankLines']} non-blank lines |",
            f"| Standalone compile | **{flat['standaloneCompile']}** |",
            f"| sha256 (flattened) | `{flat['sha256']}` |",
            f"| Commit | `{meta['commit']}` |",
            f"| Compiler | solc {comp['solc']}, evm {comp['evmVersion']}, optimizer on ({comp['optimizerRuns']} runs), via-IR off |",
            "",
            "## What it does",
            "",
            brief["purpose"],
            "",
            "## Trust and authority",
            "",
            brief["trust"],
            "",
            "## Invariants it must hold",
            "",
        ]
        lines += [f"{i}. {inv}" for i, inv in enumerate(brief["invariants"], 1)]
        lines += ["", "## Where to look first", ""]
        lines += [f"- {f}" for f in brief["focus"]]
        lines += ["", "## Context worth having before you start", ""] + SHARED_CONTEXT
        lines += [
            "",
            "## Files in this bundle",
            "",
            "| File | Purpose |",
            "|---|---|",
            f"| `{name}.flat.sol` | Self-contained source. Compiles with no dependencies and no remappings. |",
            f"| `{name}.abi.json` | ABI. |",
            f"| `{name}.storage.json` | Storage layout, for slot-packing and collision analysis. |",
            "| `metadata.json` | Commit, compiler settings, source hashes. |",
            "",
        ]
        (out / "contracts" / name / "AUDIT_BRIEF.md").write_text("\n".join(lines))

    print(f"==> {len(BRIEFS)} audit briefs written")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "audit"))
