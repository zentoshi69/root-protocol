/**
 * Quorum assembly.
 *
 * The relayer's only real job, and the two rules that define it:
 *
 * 1. **Count byte-identical facts, not signatures.** Three individually valid signatures over three
 *    *different* fact sets is a rejection, not a quorum. Grouping by digest makes that structural.
 * 2. **Sort by recovered signer address, strictly ascending.** `BitcoinOwnershipOracle` requires
 *    it, and that single rule does three jobs at once: it rejects duplicate signers for free, it
 *    makes the submission deterministic regardless of collection order, and it removes the need for
 *    an O(n²) duplicate scan on chain.
 *
 * The relayer is **not trusted for correctness**. It cannot alter a term — every field is covered
 * by the attestor signatures, and any mutation invalidates the quorum. It is trusted only for
 * liveness, and relaying is permissionless, so a censoring relayer is a delay rather than a loss.
 */

import { recoverAddress, type Hex } from 'viem';

export interface CollectedAttestation<T> {
  /** Which operator returned this. Informational — the recovered address is what counts. */
  operator: string;
  attestation: T;
  digest: Hex;
  signature: Hex;
  /** Address the operator claims signed. Verified by recovery, never trusted. */
  attestor: Hex;
}

export interface QuorumGroup<T> {
  digest: Hex;
  attestation: T;
  /** Sorted strictly ascending by recovered signer address. */
  signatures: Hex[];
  signers: Hex[];
  operators: string[];
}

export class QuorumError extends Error {
  constructor(
    readonly code: 'NO_QUORUM' | 'MIXED_FACTS' | 'DUPLICATE_SIGNER' | 'BAD_SIGNATURE' | 'UNAUTHORIZED_SIGNER',
    message: string,
    readonly detail: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = 'QuorumError';
  }
}

/**
 * Group collected attestations by digest, verifying each signature by recovery.
 *
 * A signature whose recovered address differs from the address the operator claimed is discarded
 * rather than trusted, so a compromised or buggy operator cannot inflate a group by lying about who
 * signed.
 */
export async function groupByDigest<T>(collected: CollectedAttestation<T>[]): Promise<Map<Hex, QuorumGroup<T>>> {
  const groups = new Map<Hex, QuorumGroup<T>>();

  for (const item of collected) {
    let recovered: Hex;
    try {
      recovered = await recoverAddress({ hash: item.digest, signature: item.signature });
    } catch {
      // A malformed signature is dropped, not fatal. One broken operator must not stop a quorum
      // that the other four can still form.
      continue;
    }
    if (recovered.toLowerCase() !== item.attestor.toLowerCase()) continue;

    const existing = groups.get(item.digest);
    if (!existing) {
      groups.set(item.digest, {
        digest: item.digest,
        attestation: item.attestation,
        signatures: [item.signature],
        signers: [recovered],
        operators: [item.operator],
      });
      continue;
    }

    // Same operator answering twice contributes once. Two entries from one signer would be
    // rejected on chain by the ascending-order rule anyway; dropping it here gives a clearer error.
    if (existing.signers.some((s) => s.toLowerCase() === recovered.toLowerCase())) continue;

    existing.signatures.push(item.signature);
    existing.signers.push(recovered);
    existing.operators.push(item.operator);
  }

  return groups;
}

/**
 * Sort a group's signatures by recovered signer address, strictly ascending.
 *
 * The signatures must be reordered *together with* their signers — sorting the signature bytes
 * themselves would produce an order that has nothing to do with the recovered addresses, and the
 * oracle would reject it.
 */
export function sortGroupAscending<T>(group: QuorumGroup<T>): QuorumGroup<T> {
  const paired = group.signers.map((signer, i) => ({
    signer,
    signature: group.signatures[i]!,
    operator: group.operators[i]!,
  }));

  paired.sort((a, b) => {
    const x = a.signer.toLowerCase();
    const y = b.signer.toLowerCase();
    return x < y ? -1 : x > y ? 1 : 0;
  });

  for (let i = 1; i < paired.length; i++) {
    if (paired[i]!.signer.toLowerCase() === paired[i - 1]!.signer.toLowerCase()) {
      throw new QuorumError('DUPLICATE_SIGNER', `signer ${paired[i]!.signer} appears twice`, {
        signer: paired[i]!.signer,
      });
    }
  }

  return {
    digest: group.digest,
    attestation: group.attestation,
    signatures: paired.map((p) => p.signature),
    signers: paired.map((p) => p.signer),
    operators: paired.map((p) => p.operator),
  };
}

export interface AssembleOptions {
  threshold: number;
  /** Current attestor set. A signature from outside it can never reach quorum on chain. */
  authorizedAttestors: readonly Hex[];
}

/**
 * Assemble a submittable quorum, or explain precisely why there isn't one.
 *
 * Distinguishes "not enough answers yet" from "the operators disagree" — the two mean completely
 * different things operationally, and collapsing them into one error is how a real fact conflict
 * gets mistaken for slow infrastructure.
 */
export async function assembleQuorum<T>(
  collected: CollectedAttestation<T>[],
  options: AssembleOptions,
): Promise<QuorumGroup<T>> {
  const authorized = new Set(options.authorizedAttestors.map((a) => a.toLowerCase()));

  const eligible = collected.filter((c) => authorized.has(c.attestor.toLowerCase()));
  const groups = await groupByDigest(eligible);

  const best = [...groups.values()].sort((a, b) => b.signers.length - a.signers.length)[0];

  if (!best) {
    throw new QuorumError('NO_QUORUM', 'no valid attestations were collected', {
      collected: collected.length,
      eligible: eligible.length,
    });
  }

  if (best.signers.length < options.threshold) {
    // More than one distinct digest means the operators genuinely disagree about the facts. That is
    // the 3-of-5 design working, and it must never be "resolved" by submitting the largest group
    // regardless of size, or by asking an operator to sign something it rejected.
    if (groups.size > 1) {
      throw new QuorumError(
        'MIXED_FACTS',
        `operators disagree: ${groups.size} distinct fact sets, largest has ${best.signers.length} of ${options.threshold} required`,
        {
          digests: [...groups.keys()],
          sizes: [...groups.values()].map((g) => ({ digest: g.digest, signers: g.signers.length, operators: g.operators })),
        },
      );
    }
    throw new QuorumError('NO_QUORUM', `only ${best.signers.length} of ${options.threshold} attestations collected`, {
      have: best.signers.length,
      need: options.threshold,
      operators: best.operators,
    });
  }

  return sortGroupAscending(best);
}

/**
 * Progress for the UI, from a set of collected attestations.
 *
 * Reports the size of the largest *agreeing* group, not the raw count, so a user watching three
 * operators disagree does not see "3 of 3" and then a failure.
 */
export async function quorumProgress<T>(
  collected: CollectedAttestation<T>[],
  threshold: number,
): Promise<{ matching: number; distinctFactSets: number }> {
  const groups = await groupByDigest(collected);
  const sizes = [...groups.values()].map((g) => g.signers.length);
  return {
    matching: Math.min(sizes.length > 0 ? Math.max(...sizes) : 0, threshold),
    distinctFactSets: groups.size,
  };
}
