#!/usr/bin/env bash
#
# Build a per-contract external audit package.
#
# For each of the ten protocol contracts this produces a self-contained bundle an auditor can review
# and compile WITHOUT this repository: flattened source, ABI, storage layout, and a source hash.
#
# Why flattened source rather than "here is the repo": an audit firm needs to compile exactly what
# was reviewed, pin exactly what was reviewed, and hand back findings against stable line numbers.
# A flattened file does all three. It is also what block-explorer verification consumes, so the same
# artifact serves both purposes.
#
# Every flattened file is RE-COMPILED STANDALONE before it is accepted. Flattening can silently
# produce a file that does not build — duplicate pragmas, dropped imports, cyclic ordering — and
# shipping one of those to an auditor wastes a day of someone else's time.
#
#   ./scripts/export-audit-package.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS="$ROOT/contracts"
OUT="$ROOT/audit"

export PATH="/root/.foundry/bin:$PATH"

CONTRACT_NAMES=(
  PuppetCollectionRegistry
  BitcoinAttestorRegistry
  BitcoinOwnershipOracle
  PayoutVault
  RootOwnershipRegistry
  FeeRouter
  HoodPups
  HoodPupOfferEscrow
  BtcSolverSettlement
  TourEngine
)

SOLC_VERSION="0.8.28"
EVM_VERSION="shanghai"
OPTIMIZER_RUNS="800"

# storageLayout is not in the default artifact output, and adding the flag to an already-cached
# build is a no-op — forge sees nothing to recompile and reuses artifacts that lack it. Building
# into a DEDICATED out dir forces a fresh compile so the extra output actually lands, and leaves the
# everyday build and the CI artifacts untouched.
AUDIT_OUT="out-audit"
echo "==> Building the workspace with storage layouts (dedicated out dir)"
(cd "$CONTRACTS" && forge build --silent --extra-output storageLayout --out "$AUDIT_OUT" --cache-path cache-audit)

rm -rf "$OUT/contracts"
mkdir -p "$OUT/contracts"

COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
DIRTY=""
if ! git -C "$ROOT" diff --quiet HEAD -- contracts/src; then DIRTY=" (WORKING TREE DIRTY)"; fi

echo "==> Exporting ${#CONTRACT_NAMES[@]} contracts at ${COMMIT:0:12}${DIRTY}"

for NAME in "${CONTRACT_NAMES[@]}"; do
  DIR="$OUT/contracts/$NAME"
  mkdir -p "$DIR"

  # 1. Flattened, self-contained source.
  forge flatten "$CONTRACTS/src/$NAME.sol" --root "$CONTRACTS" --output "$DIR/$NAME.flat.sol" >/dev/null 2>&1

  # 2. Prove it compiles on its own, in a scratch project with no remappings and no lib/.
  #    This is the step that makes the package trustworthy rather than merely present.
  SCRATCH="$(mktemp -d)"
  mkdir -p "$SCRATCH/src"
  cp "$DIR/$NAME.flat.sol" "$SCRATCH/src/"
  cat > "$SCRATCH/foundry.toml" <<TOML
[profile.default]
src = "src"
out = "out"
libs = []
solc = "$SOLC_VERSION"
evm_version = "$EVM_VERSION"
optimizer = true
optimizer_runs = $OPTIMIZER_RUNS
TOML
  if (cd "$SCRATCH" && forge build --silent 2>/dev/null); then
    STANDALONE="verified"
  else
    STANDALONE="FAILED"
    echo "    !! $NAME: flattened source does NOT compile standalone" >&2
  fi
  rm -rf "$SCRATCH"

  # 3. ABI and storage layout, read directly from the freshly built artifact. A missing layout is
  #    a hard failure rather than a warning: it is what an auditor needs to reason about slot
  #    packing and collisions, and a silently absent file would be discovered by them, not us.
  ARTIFACT="$CONTRACTS/$AUDIT_OUT/$NAME.sol/$NAME.json"
  python3 - "$ARTIFACT" "$DIR" "$NAME" <<'PYEOF'
import json, sys, pathlib
artifact_path, out_dir, name = sys.argv[1], sys.argv[2], sys.argv[3]
a = json.load(open(artifact_path))
pathlib.Path(out_dir, f"{name}.abi.json").write_text(json.dumps(a["abi"], indent=2) + "\n")
layout = a.get("storageLayout")
if layout is None:
    sys.exit(f"{name}: storageLayout missing from {artifact_path}")
pathlib.Path(out_dir, f"{name}.storage.json").write_text(json.dumps(layout, indent=2) + "\n")
PYEOF

  # 4. Per-contract metadata, including the hash of the exact bytes shipped.
  FLAT_SHA="$(sha256sum "$DIR/$NAME.flat.sol" | cut -d' ' -f1)"
  SRC_SHA="$(sha256sum "$CONTRACTS/src/$NAME.sol" | cut -d' ' -f1)"
  LOC="$(grep -cve '^\s*$' "$CONTRACTS/src/$NAME.sol")"
  FLAT_LOC="$(grep -cve '^\s*$' "$DIR/$NAME.flat.sol")"

  cat > "$DIR/metadata.json" <<JSON
{
  "contract": "$NAME",
  "commit": "$COMMIT",
  "compiler": {
    "solc": "$SOLC_VERSION",
    "evmVersion": "$EVM_VERSION",
    "optimizer": true,
    "optimizerRuns": $OPTIMIZER_RUNS,
    "viaIR": false
  },
  "source": {
    "path": "contracts/src/$NAME.sol",
    "sha256": "$SRC_SHA",
    "nonBlankLines": $LOC
  },
  "flattened": {
    "path": "audit/contracts/$NAME/$NAME.flat.sol",
    "sha256": "$FLAT_SHA",
    "nonBlankLines": $FLAT_LOC,
    "standaloneCompile": "$STANDALONE"
  }
}
JSON

  printf '    %-26s %5s src / %5s flat lines   standalone: %s\n' "$NAME" "$LOC" "$FLAT_LOC" "$STANDALONE"
done

# Top-level manifest so an auditor can verify they received the complete set.
python3 - "$OUT" "$COMMIT" <<'PY'
import json, pathlib, sys, hashlib
out, commit = pathlib.Path(sys.argv[1]), sys.argv[2]
entries = []
for d in sorted((out / "contracts").iterdir()):
    entries.append(json.loads((d / "metadata.json").read_text()))
digest = hashlib.sha256(
    "".join(e["flattened"]["sha256"] for e in entries).encode()
).hexdigest()
(out / "MANIFEST.json").write_text(json.dumps({
    "package": "hoodpups-audit-package",
    "commit": commit,
    "contractCount": len(entries),
    "packageDigest": digest,
    "contracts": entries,
}, indent=2) + "\n")
print(f"==> MANIFEST.json written — {len(entries)} contracts, package digest {digest[:16]}")
failed = [e['contract'] for e in entries if e['flattened']['standaloneCompile'] != 'verified']
if failed:
    print(f"!!  standalone compile FAILED for: {', '.join(failed)}")
    sys.exit(1)
print("==> every flattened contract compiles standalone")
PY

# Per-contract audit briefs. Generated last so a re-export never leaves a bundle without one.
python3 "$ROOT/scripts/lib/audit_briefs.py" "$OUT"
