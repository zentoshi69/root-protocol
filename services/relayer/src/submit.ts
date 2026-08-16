/**
 * Submission: simulate, then send, then track. Idempotently.
 *
 * The relayer never modifies a term. Its inputs are an attestation and a set of signatures over
 * that exact attestation; changing any field invalidates the quorum, so the only failure modes
 * available to a hostile relayer are delay and wasted gas.
 */

import type { Hex } from 'viem';
import type { QuorumGroup } from './quorum.js';

export const RelayerStatus = [
  'PROOF_RECEIVED',
  'VERIFYING',
  'ATTESTATIONS_1_OF_3',
  'ATTESTATIONS_2_OF_3',
  'READY_TO_SUBMIT',
  'SUBMITTED',
  'CONFIRMED',
  'REJECTED',
  'EXPIRED',
] as const;

export type RelayerStatusValue = (typeof RelayerStatus)[number];

export interface SubmissionRecord {
  /** Deduplication key. The attestation digest is the natural one: it is unique per authorization
   *  and already consumed exactly once on chain. */
  idempotencyKey: Hex;
  status: RelayerStatusValue;
  txHash?: Hex;
  submittedAt?: string;
  confirmedAt?: string;
  error?: string;
  attempts: number;
}

export interface SubmissionStore {
  get(key: Hex): Promise<SubmissionRecord | undefined>;
  put(record: SubmissionRecord): Promise<void>;
}

export class MemorySubmissionStore implements SubmissionStore {
  readonly records = new Map<Hex, SubmissionRecord>();
  async get(key: Hex) {
    return this.records.get(key);
  }
  async put(record: SubmissionRecord) {
    this.records.set(record.idempotencyKey, record);
  }
}

export interface Submitter {
  /** Dry-run the call. Must throw with the revert reason if it would fail. */
  simulate(group: QuorumGroup<unknown>): Promise<void>;
  /** Broadcast and return the transaction hash. */
  send(group: QuorumGroup<unknown>): Promise<Hex>;
  /** Wait for inclusion. Resolves true on success, false on revert. */
  waitForReceipt(txHash: Hex): Promise<boolean>;
}

export interface SubmitOptions {
  maxAttempts?: number;
  /** Delay between attempts, in milliseconds. Injected so tests do not sleep. */
  backoffMs?: (attempt: number) => number;
  sleep?: (ms: number) => Promise<void>;
}

/**
 * Submit a quorum, at most once per digest.
 *
 * Simulation runs first, always. A settlement that would revert — because the offer expired, the
 * epoch rotated, or someone else already settled the Root — costs nothing to discover in a
 * simulation and real gas to discover on chain.
 *
 * Idempotency is keyed on the attestation digest. If a record already exists in a terminal or
 * in-flight state, this returns it rather than broadcasting again: on-chain digest consumption
 * would make the second transaction revert anyway, but a duplicate broadcast still burns gas and
 * muddies the operator's view of what happened.
 */
export async function submitQuorum(
  group: QuorumGroup<unknown>,
  submitter: Submitter,
  store: SubmissionStore,
  options: SubmitOptions = {},
): Promise<SubmissionRecord> {
  const key = group.digest;
  const existing = await store.get(key);
  if (existing && (existing.status === 'SUBMITTED' || existing.status === 'CONFIRMED')) {
    return existing;
  }

  const maxAttempts = options.maxAttempts ?? 3;
  const backoffMs = options.backoffMs ?? ((attempt: number) => 2 ** attempt * 1000);
  const sleep = options.sleep ?? ((ms: number) => new Promise((r) => setTimeout(r, ms)));

  const record: SubmissionRecord = existing ?? { idempotencyKey: key, status: 'READY_TO_SUBMIT', attempts: 0 };

  let lastError = '';
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    record.attempts = attempt + 1;
    try {
      await submitter.simulate(group);
    } catch (error) {
      // A simulation failure is usually terminal — an expired offer or a rotated epoch will not fix
      // itself — so it is recorded as REJECTED rather than retried into the ground.
      record.status = 'REJECTED';
      record.error = error instanceof Error ? error.message : String(error);
      await store.put(record);
      return record;
    }

    try {
      const txHash = await submitter.send(group);
      record.txHash = txHash;
      record.status = 'SUBMITTED';
      record.submittedAt = new Date().toISOString();
      await store.put(record);

      const ok = await submitter.waitForReceipt(txHash);
      record.status = ok ? 'CONFIRMED' : 'REJECTED';
      if (ok) record.confirmedAt = new Date().toISOString();
      else record.error = 'transaction reverted on chain';
      await store.put(record);
      return record;
    } catch (error) {
      // Broadcast/RPC failures ARE worth retrying: the transaction may not have been accepted at
      // all, and the digest is still unconsumed.
      lastError = error instanceof Error ? error.message : String(error);
      record.error = lastError;
      await store.put(record);
      if (attempt < maxAttempts - 1) await sleep(backoffMs(attempt));
    }
  }

  record.status = 'REJECTED';
  record.error = `failed after ${maxAttempts} attempts: ${lastError}`;
  await store.put(record);
  return record;
}

/** Map an agreeing-attestation count to the status the UI shows. */
export function statusFromMatching(matching: number, threshold = 3): RelayerStatusValue {
  if (matching <= 0) return 'VERIFYING';
  if (matching >= threshold) return 'READY_TO_SUBMIT';
  return matching === 1 ? 'ATTESTATIONS_1_OF_3' : 'ATTESTATIONS_2_OF_3';
}
