/**
 * Append-only attestor audit log.
 *
 * This log is what makes a false-attestation post-mortem possible. An operator that cannot produce
 * it cannot be exonerated — so it records every input, both node heights, every recomputed hash,
 * and the decision, whether the outcome was a signature or a rejection.
 *
 * Retention: at least two years (`docs/ATTESTOR_POLICY.md`).
 *
 * ## What must never appear here
 *
 * Private keys, seed phrases, or anything derived from them. The attestor never receives one, so
 * the only way one could reach this log is a serious bug — {@link assertNoSecrets} exists so that
 * bug fails a test rather than shipping.
 */

import { appendFile, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

export interface AuditRecord {
  correlationId: string;
  kind: 'ownership' | 'payment' | 'rootSpend';
  startedAt: string;
  finishedAt: string;
  attestor: string;
  authorizationId: string;
  bitcoinHeight: number;
  bitcoinTipHash: string;
  ordIndexHeight: number;
  threshold: number;
  epoch: number;
  policyVersion: number;
  decision: 'signed' | 'rejected';
  /** Present when signed. */
  digest?: string;
  /** Present when rejected — the structured code, so operators can diff disagreements. */
  rejectionCode?: string;
  rejectionMessage?: string;
  /** The full verified fact set, or the rejection detail. */
  facts?: unknown;
}

export interface AuditLog {
  record(entry: AuditRecord): Promise<void>;
}

/** Patterns that must never reach an audit log. */
const SECRET_PATTERNS = [
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  /\bxprv[0-9a-zA-Z]{50,}/,
  /\btprv[0-9a-zA-Z]{50,}/,
  // A bare 32-byte hex value is how a raw private key would look. Digests and hashes are the same
  // shape, so this only fires on a key-shaped value under a suspicious key name.
  /"(privateKey|seed|mnemonic|secret|passphrase)"\s*:/i,
];

/**
 * Throw if a serialised record contains anything key-shaped.
 *
 * Called on every write. The cost is a regex scan per attestation; the benefit is that a bug that
 * would otherwise write a key to disk fails loudly at the moment it happens.
 */
export function assertNoSecrets(serialised: string): void {
  for (const pattern of SECRET_PATTERNS) {
    if (pattern.test(serialised)) {
      throw new Error(
        'refusing to write an audit record that appears to contain key material. ' +
          'This is a bug: the attestor never receives a private key or seed phrase.',
      );
    }
  }
}

/** JSON Lines audit log. One record per line, append-only, never rewritten. */
export class FileAuditLog implements AuditLog {
  constructor(private readonly path: string) {}

  async record(entry: AuditRecord): Promise<void> {
    const line = JSON.stringify(entry, (_key, value) =>
      typeof value === 'bigint' ? value.toString() : value,
    );
    assertNoSecrets(line);
    await mkdir(dirname(this.path), { recursive: true });
    await appendFile(this.path, `${line}\n`, 'utf8');
  }
}

/** In-memory log for tests. */
export class MemoryAuditLog implements AuditLog {
  readonly entries: AuditRecord[] = [];

  async record(entry: AuditRecord): Promise<void> {
    assertNoSecrets(JSON.stringify(entry, (_k, v) => (typeof v === 'bigint' ? v.toString() : v)));
    this.entries.push(entry);
  }
}
