/**
 * Minimal Bitcoin Core JSON-RPC client.
 *
 * Deliberately small: only the calls the verifier genuinely needs. Every method that touches
 * consensus state goes through the operator's **own** fully validating node — never a public API,
 * never someone else's RPC, never a pruned SPV shortcut. If all five operators read from one
 * source, the 3-of-5 threshold means nothing.
 */

import { reject, RejectionCode } from './errors.js';

export interface BitcoinCoreConfig {
  url: string;
  username: string;
  password: string;
  /** Milliseconds. A slow node must abstain, not stall a quorum. */
  timeoutMs?: number;
}

export interface ChainInfo {
  chain: string;
  blocks: number;
  bestblockhash: string;
}

export interface TxOut {
  /** Confirmations of the containing transaction; 0 means it is unconfirmed in the mempool. */
  confirmations: number;
  /** Value in BTC, as Bitcoin Core reports it. Convert with `btcToSats`, never with floats. */
  value: number;
  scriptPubKey: { hex: string; type: string; address?: string };
}

export interface RawTransaction {
  txid: string;
  hash: string;
  confirmations?: number;
  blockhash?: string;
  vout: Array<{ n: number; value: number; scriptPubKey: { hex: string; type: string } }>;
  vin: Array<{ txid?: string; vout?: number }>;
}

export interface TxSpendingPrevout {
  txid: string;
  vout: number;
  spendingtxid?: string;
}

/**
 * Convert Bitcoin Core's BTC-denominated `value` into satoshis without going through a float.
 *
 * `0.1 + 0.2 !== 0.3` is not an acceptable failure mode when the number decides whether a seller
 * was paid the exact amount they signed for. The decimal string is parsed textually.
 */
export function btcToSats(value: number | string): bigint {
  const s = typeof value === 'string' ? value : value.toFixed(8);
  const match = /^(-?)(\d+)(?:\.(\d{1,8}))?$/.exec(s);
  if (!match) throw new TypeError(`cannot convert ${JSON.stringify(s)} to satoshis`);
  const [, sign, whole, frac = ''] = match;
  const sats = BigInt(whole!) * 100_000_000n + BigInt(frac.padEnd(8, '0'));
  return sign === '-' ? -sats : sats;
}

export class BitcoinCoreClient {
  private readonly timeoutMs: number;

  constructor(private readonly config: BitcoinCoreConfig) {
    this.timeoutMs = config.timeoutMs ?? 10_000;
  }

  private async rpc<T>(method: string, params: unknown[] = []): Promise<T> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await fetch(this.config.url, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'content-type': 'application/json',
          authorization: `Basic ${Buffer.from(`${this.config.username}:${this.config.password}`).toString('base64')}`,
        },
        body: JSON.stringify({ jsonrpc: '1.0', id: 'hoodpups-verifier', method, params }),
      });

      if (!response.ok && response.status !== 500) {
        reject(RejectionCode.NODE_UNAVAILABLE, `Bitcoin Core returned HTTP ${response.status} for ${method}`);
      }

      const body = (await response.json()) as { result: T; error: { code: number; message: string } | null };
      if (body.error) {
        // -5 is "not found" for gettxout/getrawtransaction — a real answer, not an outage. Callers
        // interpret null; anything else is an infrastructure problem the operator must abstain on.
        if (body.error.code === -5) return null as T;
        reject(RejectionCode.NODE_UNAVAILABLE, `Bitcoin Core error on ${method}: ${body.error.message}`, {
          method,
          code: body.error.code,
        });
      }
      return body.result;
    } catch (error) {
      if (error instanceof Error && error.name === 'VerificationRejection') throw error;
      reject(RejectionCode.NODE_UNAVAILABLE, `Bitcoin Core unreachable calling ${method}`, {
        method,
        cause: error instanceof Error ? error.message : String(error),
      });
    } finally {
      clearTimeout(timer);
    }
  }

  getBlockchainInfo(): Promise<ChainInfo> {
    return this.rpc<ChainInfo>('getblockchaininfo');
  }

  /**
   * Look up an unspent output.
   *
   * `includeMempool = true` is the important default: it makes a UTXO already being spent by an
   * unconfirmed transaction return `null`, which is exactly the "someone is moving this Puppet
   * right now" case that must not be attested.
   */
  getTxOut(txid: string, vout: number, includeMempool = true): Promise<TxOut | null> {
    return this.rpc<TxOut | null>('gettxout', [txid, vout, includeMempool]);
  }

  getRawTransaction(txid: string): Promise<RawTransaction | null> {
    return this.rpc<RawTransaction | null>('getrawtransaction', [txid, true]);
  }

  /**
   * Detect an unconfirmed transaction spending `txid:vout`.
   *
   * Bitcoin Core 24 exposes `gettxspendingprevout`, which performs this lookup inside the node.
   * Do not rebuild it by fetching every mempool transaction: a hostile or simply busy mempool
   * would turn one ownership check into thousands of sequential RPC calls and make honest
   * attestors easy to exhaust precisely when the network is under load.
   */
  async findMempoolSpend(txid: string, vout: number): Promise<string | null> {
    const result = await this.rpc<TxSpendingPrevout[]>('gettxspendingprevout', [[{ txid, vout }]]);
    const checked = result[0];
    if (!checked || checked.txid !== txid || checked.vout !== vout) {
      reject(RejectionCode.NODE_UNAVAILABLE, 'Bitcoin Core returned a mismatched gettxspendingprevout result', {
        requested: { txid, vout },
        received: checked ?? null,
      });
    }
    return checked.spendingtxid ?? null;
  }

  /** Confirmations for a transaction, or 0 if unconfirmed, or null if unknown to this node. */
  async getConfirmations(txid: string): Promise<number | null> {
    const tx = await this.getRawTransaction(txid);
    if (!tx) return null;
    return tx.confirmations ?? 0;
  }
}
