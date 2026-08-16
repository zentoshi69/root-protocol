/**
 * Sorted-pair Merkle tree over the canonical Bitcoin Puppets manifest.
 *
 * Must produce trees that verify against OpenZeppelin's `MerkleProof.verify` as used by
 * `PuppetCollectionRegistry`. The algorithm is fixed and small enough to state completely:
 *
 * 1. Leaf = `collectionLeaf(rootKey)` = `keccak256(rootKey)` — double hashed, so an internal node
 *    preimage (64 bytes) can never be presented as a leaf (32 bytes). Second-preimage defence.
 * 2. Sort leaves ascending by raw bytes, then deduplicate. A manifest with a duplicate entry is an
 *    error, not something to quietly collapse.
 * 3. Combine pairs as `keccak256(min(a,b) ++ max(a,b))` — sorted-pair hashing, which is what makes
 *    a proof position-independent.
 * 4. An odd node at the end of a level is promoted to the next level unchanged.
 *
 * Golden vectors in `data/test-fixtures/hashing-vectors.json` pin the root and one full proof for
 * a three-inscription fixture, so this implementation and the Solidity fixture builder cannot drift.
 */

import { concatHex, keccak256, type Hex } from 'viem';
import { collectionLeaf, rootKey, type RootId } from './hashing.js';
import { assertBytes32, parseInscriptionId } from './validation.js';

export class ManifestError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ManifestError';
  }
}

/** `keccak256(min(a,b) ++ max(a,b))`. */
export function hashPair(a: Hex, b: Hex): Hex {
  return a.toLowerCase() <= b.toLowerCase() ? keccak256(concatHex([a, b])) : keccak256(concatHex([b, a]));
}

/** Sort ascending by raw bytes and reject duplicates. */
export function sortLeaves(leaves: Hex[]): Hex[] {
  for (const l of leaves) assertBytes32(l, 'leaf');
  const sorted = [...leaves].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i] === sorted[i - 1]) {
      throw new ManifestError(`duplicate leaf ${sorted[i]} — the manifest contains the same inscription twice`);
    }
  }
  return sorted;
}

/** Build every level of the tree, bottom up. `levels[0]` is the sorted leaves. */
export function buildLevels(leaves: Hex[]): Hex[][] {
  if (leaves.length === 0) throw new ManifestError('cannot build a Merkle tree from zero leaves');
  const levels: Hex[][] = [sortLeaves(leaves)];

  while (levels[levels.length - 1]!.length > 1) {
    const current = levels[levels.length - 1]!;
    const next: Hex[] = [];
    for (let i = 0; i < current.length; i += 2) {
      // An odd tail node is promoted unchanged rather than paired with itself. Pairing a node with
      // itself would make its proof ambiguous.
      next.push(i + 1 < current.length ? hashPair(current[i]!, current[i + 1]!) : current[i]!);
    }
    levels.push(next);
  }
  return levels;
}

/** Merkle root over a set of leaves. A single-leaf tree's root IS that leaf. */
export function buildRoot(leaves: Hex[]): Hex {
  const levels = buildLevels(leaves);
  return levels[levels.length - 1]![0]!;
}

/** Proof for one leaf. A single-leaf tree yields an empty proof, which `MerkleProof` accepts. */
export function buildProof(leaves: Hex[], leaf: Hex): Hex[] {
  assertBytes32(leaf, 'leaf');
  const levels = buildLevels(leaves);
  let index = levels[0]!.indexOf(leaf);
  if (index < 0) throw new ManifestError(`leaf ${leaf} is not in the tree`);

  const proof: Hex[] = [];
  for (let level = 0; level < levels.length - 1; level++) {
    const nodes = levels[level]!;
    const siblingIndex = index % 2 === 0 ? index + 1 : index - 1;
    // No sibling means this was the promoted odd tail; it contributes nothing to the proof.
    if (siblingIndex < nodes.length) proof.push(nodes[siblingIndex]!);
    index = Math.floor(index / 2);
  }
  return proof;
}

/** Verify a proof exactly as `MerkleProof.verify` does. Useful for self-checking a built tree. */
export function verifyProof(proof: Hex[], root: Hex, leaf: Hex): boolean {
  let computed = leaf;
  for (const node of proof) computed = hashPair(computed, node);
  return computed.toLowerCase() === root.toLowerCase();
}

/*//////////////////////////////////////////////////////////////
                          MANIFEST TOOLING
//////////////////////////////////////////////////////////////*/

export interface ManifestEntry {
  /** Ordinals inscription id, `<64 lowercase hex>i<index>`. */
  id: string;
}

export interface ManifestFile {
  collection: string;
  version: string;
  network: string;
  inscriptions: ManifestEntry[];
  /** Present on the shipped example only. Its presence makes the build fail closed. */
  EXAMPLE_ONLY_DO_NOT_DEPLOY?: unknown;
}

export interface BuiltManifest {
  merkleRoot: Hex;
  manifestHash: Hex;
  leafCount: number;
  version: string;
  /** `rootKey` -> proof, for serving to clients. */
  proofs: Record<string, Hex[]>;
  roots: Array<{ id: string; root: RootId; rootKey: Hex; leaf: Hex }>;
}

/**
 * Build the committed Merkle root and every per-root proof from a manifest file.
 *
 * Fails closed on anything questionable:
 * - a manifest carrying the example marker,
 * - an empty inscription list,
 * - a malformed or uppercase inscription id,
 * - an index that does not fit `uint32`,
 * - the same inscription listed twice.
 *
 * The Merkle root is immutable once deployed, so a mistake here is permanent. The launch gate
 * requires this root to be independently reproduced by a second implementation before mainnet.
 */
export function buildManifest(manifest: ManifestFile, manifestFileBytes: Uint8Array | string): BuiltManifest {
  if (manifest.EXAMPLE_ONLY_DO_NOT_DEPLOY !== undefined) {
    throw new ManifestError(
      'this manifest is the shipped EXAMPLE. Supply a real, independently verified Bitcoin Puppets ' +
        'manifest. Deployment fails closed rather than committing to fabricated inscription ids.',
    );
  }
  if (!Array.isArray(manifest.inscriptions) || manifest.inscriptions.length === 0) {
    throw new ManifestError('manifest contains no inscriptions');
  }

  const seen = new Set<string>();
  const roots = manifest.inscriptions.map((entry) => {
    const root = parseInscriptionId(entry.id);
    const key = rootKey(root);
    if (seen.has(key)) throw new ManifestError(`duplicate inscription in manifest: ${entry.id}`);
    seen.add(key);
    return { id: entry.id, root, rootKey: key, leaf: collectionLeaf(key) };
  });

  const leaves = roots.map((r) => r.leaf);
  const merkleRoot = buildRoot(leaves);

  const proofs: Record<string, Hex[]> = {};
  for (const r of roots) {
    const proof = buildProof(leaves, r.leaf);
    // Self-check every proof at build time. A tree that cannot prove its own leaves would ship a
    // registry against which no legitimate root could ever be verified.
    if (!verifyProof(proof, merkleRoot, r.leaf)) {
      throw new ManifestError(`internal error: generated proof for ${r.id} does not verify`);
    }
    proofs[r.rootKey] = proof;
  }

  const bytes = typeof manifestFileBytes === 'string' ? new TextEncoder().encode(manifestFileBytes) : manifestFileBytes;

  return {
    merkleRoot,
    // Hash of the manifest file's exact bytes, so the deployed commitment identifies the source
    // document and not merely the set of leaves derived from it.
    manifestHash: keccak256(bytes),
    leafCount: roots.length,
    version: manifest.version,
    proofs,
    roots,
  };
}
