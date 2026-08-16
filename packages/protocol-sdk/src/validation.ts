/**
 * Input validation for the SDK.
 *
 * The governing rule: **no SDK function silently normalises an invalid txid, address or amount.**
 * A helpful `.toLowerCase()` here is exactly how one component ends up hashing a different byte
 * string than another, and a hash mismatch between the SDK and Solidity means five attestors can
 * never reach quorum. Every rejection is explicit and names the field.
 */

import type { Hex } from 'viem';

export class SdkValidationError extends TypeError {
  constructor(
    readonly field: string,
    message: string,
  ) {
    super(message);
    this.name = 'SdkValidationError';
  }
}

const BYTES32_RE = /^0x[0-9a-f]{64}$/;
const ADDRESS_RE = /^0x[0-9a-f]{40}$/;
const BARE_TXID_RE = /^[0-9a-f]{64}$/;

/** 32 bytes, `0x`-prefixed, lowercase. Uppercase is rejected, not lowercased. */
export function assertBytes32(value: string, field: string): asserts value is Hex {
  if (!BYTES32_RE.test(value)) {
    throw new SdkValidationError(
      field,
      `${field} must be 0x followed by 64 lowercase hex characters, got ${JSON.stringify(value)}`,
    );
  }
}

/**
 * 20 bytes, `0x`-prefixed, lowercase.
 *
 * EIP-55 checksummed input is rejected rather than lowercased. A checksummed and a lowercase
 * address are different strings; accepting both would mean a UI could display one while the
 * canonical message hashed the other.
 */
export function assertEvmAddress(value: string, field: string): asserts value is Hex {
  if (!ADDRESS_RE.test(value)) {
    throw new SdkValidationError(
      field,
      `${field} must be 0x followed by 40 lowercase hex characters, got ${JSON.stringify(value)}. ` +
        'Checksummed input is rejected rather than normalised.',
    );
  }
}

/** Non-negative integer fitting in `bits`. */
export function assertUint(value: bigint | number, field: string, bits: number): bigint {
  const v = typeof value === 'bigint' ? value : BigInt(value);
  if (typeof value === 'number' && !Number.isInteger(value)) {
    throw new SdkValidationError(field, `${field} must be an integer, got ${value}`);
  }
  if (v < 0n) throw new SdkValidationError(field, `${field} must be non-negative, got ${v}`);
  const max = (1n << BigInt(bits)) - 1n;
  if (v > max) throw new SdkValidationError(field, `${field} does not fit in uint${bits}, got ${v}`);
  return v;
}

/*//////////////////////////////////////////////////////////////
                      BITCOIN TXID BYTE ORDER
//////////////////////////////////////////////////////////////*/

/**
 * Convert a bare Bitcoin txid (display order, no prefix) into the `bytes32` the contracts use.
 *
 * Byte order is a security primitive in this protocol. Bitcoin's wire format stores txids in the
 * reverse of the order block explorers display, and a component that quietly used the wrong one
 * would compute a different `rootKey` for the same inscription. The protocol uses **display order
 * everywhere**, and this function does no reversal — it only widens a validated string.
 *
 * @param txid 64 lowercase hex characters, display order, no `0x` prefix.
 */
export function txidToBytes32(txid: string): Hex {
  if (!BARE_TXID_RE.test(txid)) {
    throw new SdkValidationError(
      'txid',
      `txid must be 64 lowercase hex characters in display order with no 0x prefix, got ${JSON.stringify(txid)}`,
    );
  }
  return `0x${txid}` as Hex;
}

/** Inverse of {@link txidToBytes32}. Produces the bare, display-order form Bitcoin tooling expects. */
export function bytes32ToTxid(value: Hex): string {
  assertBytes32(value, 'txid');
  return value.slice(2);
}

/**
 * Reverse a txid's byte order.
 *
 * Provided ONLY for talking to APIs that insist on internal byte order. It is deliberately named so
 * that any call site is obvious in review — nothing in the hashing path may use it.
 */
export function reverseTxidByteOrder(txid: string): string {
  const bare = txid.startsWith('0x') ? txid.slice(2) : txid;
  if (!BARE_TXID_RE.test(bare)) {
    throw new SdkValidationError('txid', 'txid must be 64 lowercase hex characters');
  }
  return (bare.match(/../g) ?? []).reverse().join('');
}

/*//////////////////////////////////////////////////////////////
                          INSCRIPTION IDS
//////////////////////////////////////////////////////////////*/

/**
 * Parse an Ordinals inscription id of the form `<txid>i<index>`.
 *
 * Strict: rejects uppercase, a `0x` prefix, a missing `i`, a negative or non-integer index, and a
 * leading zero on the index. `abci0` and `abci00` must not both parse — they would produce the same
 * `RootId` from different strings, which is exactly the ambiguity this protocol cannot afford.
 */
export function parseInscriptionId(id: string): { inscriptionTxid: Hex; inscriptionIndex: number } {
  const match = /^([0-9a-f]{64})i(0|[1-9][0-9]*)$/.exec(id);
  if (!match) {
    throw new SdkValidationError(
      'inscriptionId',
      `inscription id must be <64 lowercase hex>i<index> with no leading zeros, got ${JSON.stringify(id)}`,
    );
  }
  const index = Number(match[2]);
  assertUint(index, 'inscriptionIndex', 32);
  return { inscriptionTxid: `0x${match[1]}` as Hex, inscriptionIndex: index };
}

/** Render a `RootId` back to its Ordinals `<txid>i<index>` form. */
export function formatInscriptionId(root: { inscriptionTxid: Hex; inscriptionIndex: number }): string {
  assertBytes32(root.inscriptionTxid, 'inscriptionTxid');
  assertUint(root.inscriptionIndex, 'inscriptionIndex', 32);
  return `${root.inscriptionTxid.slice(2)}i${root.inscriptionIndex}`;
}

/** Parse a Bitcoin outpoint of the form `<txid>:<vout>`. */
export function parseOutpoint(outpoint: string): { bitcoinTxid: Hex; vout: number } {
  const match = /^([0-9a-f]{64}):(0|[1-9][0-9]*)$/.exec(outpoint);
  if (!match) {
    throw new SdkValidationError(
      'outpoint',
      `outpoint must be <64 lowercase hex>:<vout> with no leading zeros, got ${JSON.stringify(outpoint)}`,
    );
  }
  const vout = Number(match[2]);
  assertUint(vout, 'vout', 32);
  return { bitcoinTxid: `0x${match[1]}` as Hex, vout };
}

/** Render an outpoint back to `<txid>:<vout>`. */
export function formatOutpoint(bitcoinTxid: Hex, vout: number): string {
  assertBytes32(bitcoinTxid, 'bitcoinTxid');
  assertUint(vout, 'vout', 32);
  return `${bitcoinTxid.slice(2)}:${vout}`;
}
