/**
 * `ord` indexer HTTP client.
 *
 * The operator runs its own `ord`, synced against its own `bitcoind`. A public Ordinals API may be
 * used as a cross-check that raises an alarm on disagreement — it must never be the input to a
 * signature. See `docs/ATTESTOR_POLICY.md`.
 */

import { reject, RejectionCode } from './errors.js';

export interface OrdConfig {
  baseUrl: string;
  timeoutMs?: number;
}

export interface OrdStatus {
  /** Height ord has indexed to. Compared against the node's tip to detect lag. */
  height: number;
  initial_sync_time?: unknown;
}

export interface OrdInscription {
  id: string;
  /** `<txid>:<vout>:<offset>` — the sat this inscription currently sits on. */
  satpoint: string;
  address?: string;
  /** Present on newer ord versions; the `<txid>:<vout>` containing the inscription. */
  output?: string;
  genesis_height?: number;
}

export interface OrdOutput {
  /** Raw scriptPubKey hex — the security primitive. Never the address string. */
  script_pubkey: string;
  value: number;
  address?: string;
  /** Inscription ids currently residing in this output. */
  inscriptions: string[];
  spent?: boolean;
}

export class OrdClient {
  private readonly timeoutMs: number;

  constructor(private readonly config: OrdConfig) {
    this.timeoutMs = config.timeoutMs ?? 10_000;
  }

  private async get<T>(path: string): Promise<T | null> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await fetch(`${this.config.baseUrl}${path}`, {
        signal: controller.signal,
        headers: { accept: 'application/json' },
      });
      if (response.status === 404) return null;
      if (!response.ok) {
        reject(RejectionCode.ORD_UNAVAILABLE, `ord returned HTTP ${response.status} for ${path}`, { path });
      }
      return (await response.json()) as T;
    } catch (error) {
      if (error instanceof Error && error.name === 'VerificationRejection') throw error;
      reject(RejectionCode.ORD_UNAVAILABLE, `ord unreachable at ${path}`, {
        path,
        cause: error instanceof Error ? error.message : String(error),
      });
    } finally {
      clearTimeout(timer);
    }
  }

  async status(): Promise<OrdStatus> {
    const status = await this.get<OrdStatus>('/status');
    if (!status) reject(RejectionCode.ORD_UNAVAILABLE, 'ord /status returned nothing');
    return status;
  }

  inscription(id: string): Promise<OrdInscription | null> {
    return this.get<OrdInscription>(`/inscription/${id}`);
  }

  output(outpoint: string): Promise<OrdOutput | null> {
    return this.get<OrdOutput>(`/output/${outpoint}`);
  }

  /**
   * The `<txid>:<vout>` currently holding an inscription.
   *
   * Prefers ord's explicit `output` field and falls back to trimming the offset off the satpoint.
   * A satpoint is `<txid>:<vout>:<offset>`; only the first two components identify the output.
   */
  async outputOfInscription(id: string): Promise<string | null> {
    const inscription = await this.inscription(id);
    if (!inscription) return null;
    if (inscription.output) return inscription.output;
    const parts = inscription.satpoint?.split(':');
    if (!parts || parts.length < 2) return null;
    return `${parts[0]}:${parts[1]}`;
  }

  /**
   * Assert ord is not lagging the node by more than `maxLag` blocks.
   *
   * A lagging index is the single most common cause of two honest operators disagreeing, and it
   * must produce an abstention rather than a stale answer presented as fact.
   */
  async assertFresh(nodeHeight: number, maxLag = 2): Promise<number> {
    const { height } = await this.status();
    if (!Number.isSafeInteger(nodeHeight) || nodeHeight < 0 || !Number.isSafeInteger(maxLag) || maxLag < 0) {
      reject(RejectionCode.ORD_INDEX_INCONSISTENT, 'invalid Bitcoin node height or ord lag policy; abstaining', {
        nodeHeight,
        maxLag,
      });
    }
    if (!Number.isSafeInteger(height) || height < 0) {
      reject(RejectionCode.ORD_INDEX_INCONSISTENT, 'ord returned an invalid index height; abstaining', {
        ordHeight: height,
        nodeHeight,
      });
    }
    if (height > nodeHeight) {
      reject(
        RejectionCode.ORD_INDEX_INCONSISTENT,
        'ord is ahead of its Bitcoin Core node; the two data sources are inconsistent',
        { ordHeight: height, nodeHeight },
      );
    }
    if (nodeHeight - height > maxLag) {
      reject(
        RejectionCode.ORD_INDEX_LAGGING,
        `ord is ${nodeHeight - height} blocks behind the node (max ${maxLag}); abstaining rather than attesting stale state`,
        { ordHeight: height, nodeHeight, maxLag },
      );
    }
    return height;
  }
}
