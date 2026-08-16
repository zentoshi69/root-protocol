/**
 * The canonical HoodPups BIP-322 authorization message.
 *
 * This file defines the exact bytes a Bitcoin Puppet controller signs. Every verifier, every
 * attestor, the SDK and the frontend must produce byte-identical output from the same fields, and
 * must reject anything that differs by even one space.
 *
 * ## Format rules (all security relevant)
 *
 * - ASCII only. Line 1 is the version header; every subsequent line is `key=value`.
 * - Fields appear in ONE fixed order. A parser that accepted reordering would let an attacker
 *   present a differently-ordered message to a wallet than the one the verifier re-derives.
 * - LF (`\n`) line endings, never CRLF. A CR would change the signed bytes invisibly.
 * - No leading or trailing whitespace on any line, and no whitespace around `=`.
 * - Exactly one trailing LF at the end of the message.
 * - Integers are decimal with no separators, no sign and no leading zeros (except literal `0`).
 * - EVM values are `0x`-prefixed lowercase hex. Bitcoin txids are bare lowercase hex with NO `0x`
 *   prefix, in display (block-explorer) order.
 *
 * That prefix asymmetry is deliberate. On a hardware wallet screen it lets a human tell at a glance
 * which values belong to Bitcoin and which belong to Robinhood Chain — the single most valuable
 * thing a reviewer can check when confirming "am I authorising the right chain's payout?".
 *
 * - Fields that do not apply to the current purpose are rendered with their canonical ZERO value,
 *   never omitted. Every message has the same shape, so a missing line is always an error rather
 *   than an ambiguity.
 */

import {
  type AuthorizationMessageFields,
  AuthorizationPurpose,
  type AuthorizationPurposeName,
  type BitcoinNetwork,
  CanonicalMessageError,
  type EvmAddress,
  type Hex32,
  type ParsedAuthorizationMessage,
  PayoutMode,
  type PayoutModeName,
} from './types.js';

/** The exact first line. Bump this — and the version — for any format change, never edit in place. */
export const MESSAGE_HEADER = 'HOODPUPS AUTHORIZATION V1';
export const MESSAGE_VERSION = 1;

/**
 * The one fixed field order. Do not reorder. Do not append without bumping the header version:
 * an old parser reading a new message must fail loudly, not silently ignore a trailing field.
 */
export const FIELD_ORDER = [
  'purpose',
  'bitcoin_network',
  'root_txid',
  'root_index',
  'current_outpoint_txid',
  'current_outpoint_vout',
  'rh_chain_id',
  'verifying_contract',
  'context_id',
  'offer_terms_hash',
  'buyer',
  'recipient',
  'payout_mode',
  'evm_payout',
  'btc_payout_script_hash',
  'seller_sats',
  'gross_wei',
  'seller_wei',
  'authorization_id',
  'expires_at',
] as const;

export type FieldKey = (typeof FIELD_ORDER)[number];

export const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000' as const;
export const ZERO_HASH = '0x0000000000000000000000000000000000000000000000000000000000000000' as const;

const BITCOIN_NETWORKS: readonly BitcoinNetwork[] = ['mainnet', 'testnet', 'signet', 'regtest'];
const TXID_RE = /^[0-9a-f]{64}$/;
const HEX32_RE = /^0x[0-9a-f]{64}$/;
const ADDRESS_RE = /^0x[0-9a-f]{40}$/;
const UINT_RE = /^(0|[1-9][0-9]*)$/;

function fail(code: CanonicalMessageError['code'], message: string): never {
  throw new CanonicalMessageError(code, message);
}

/*//////////////////////////////////////////////////////////////
                            VALIDATION
//////////////////////////////////////////////////////////////*/

/**
 * Validate a Bitcoin txid.
 *
 * Rejects uppercase and rejects a `0x` prefix rather than normalising either away. Silent
 * normalisation is how one component ends up hashing a different string than another — the SDK
 * contract is that an invalid input is an explicit error, never a quietly repaired value.
 */
export function assertTxid(value: string, field: string): asserts value is string {
  if (!TXID_RE.test(value)) {
    fail(
      'BAD_TXID',
      `${field} must be 64 lowercase hex characters in display order with no 0x prefix, got ${JSON.stringify(value)}`,
    );
  }
}

export function assertHex32(value: string, field: string): asserts value is Hex32 {
  if (!HEX32_RE.test(value)) {
    fail('BAD_HEX32', `${field} must be 0x followed by 64 lowercase hex characters, got ${JSON.stringify(value)}`);
  }
}

export function assertAddress(value: string, field: string): asserts value is EvmAddress {
  if (!ADDRESS_RE.test(value)) {
    fail(
      'BAD_ADDRESS',
      `${field} must be 0x followed by 40 lowercase hex characters, got ${JSON.stringify(value)}. ` +
        'Checksummed input is rejected rather than lowercased, so callers cannot accidentally sign a ' +
        'different byte string than they display.',
    );
  }
}

function assertUint(value: bigint | number, field: string, max?: bigint): bigint {
  const asBigInt = typeof value === 'bigint' ? value : BigInt(value);
  if (typeof value === 'number' && !Number.isInteger(value)) {
    fail('BAD_UINT', `${field} must be an integer, got ${value}`);
  }
  if (asBigInt < 0n) fail('BAD_UINT', `${field} must be non-negative, got ${asBigInt}`);
  if (max !== undefined && asBigInt > max) fail('BAD_UINT', `${field} exceeds its ${max} maximum, got ${asBigInt}`);
  return asBigInt;
}

const MAX_UINT32 = 2n ** 32n - 1n;
const MAX_UINT64 = 2n ** 64n - 1n;
const MAX_UINT256 = 2n ** 256n - 1n;

/**
 * Enforce that the payout fields match the payout mode.
 *
 * This is the same shape check `BitcoinOwnershipOracle` applies on chain. Doing it here too means a
 * malformed authorization is rejected before a human is ever asked to sign it, rather than after
 * five verifiers have burned work on it.
 */
export function assertPayoutShape(fields: AuthorizationMessageFields): void {
  const { payoutMode, evmPayout, btcPayoutScriptHash, sellerSats, purpose } = fields;

  if (payoutMode === 'EVM') {
    if (evmPayout === ZERO_ADDRESS) fail('PAYOUT_SHAPE', 'EVM payout mode requires a non-zero evm_payout');
    if (btcPayoutScriptHash !== ZERO_HASH) {
      fail('PAYOUT_SHAPE', 'EVM payout mode requires a zero btc_payout_script_hash');
    }
    if (sellerSats !== 0n) fail('PAYOUT_SHAPE', 'EVM payout mode requires seller_sats to be 0');
  } else if (payoutMode === 'BTC') {
    if (evmPayout !== ZERO_ADDRESS) fail('PAYOUT_SHAPE', 'BTC payout mode requires a zero evm_payout');
    if (btcPayoutScriptHash === ZERO_HASH) {
      fail('PAYOUT_SHAPE', 'BTC payout mode requires a non-zero btc_payout_script_hash');
    }
    if (sellerSats <= 0n) fail('PAYOUT_SHAPE', 'BTC payout mode requires seller_sats > 0');
  } else {
    if (evmPayout !== ZERO_ADDRESS || btcPayoutScriptHash !== ZERO_HASH || sellerSats !== 0n) {
      fail('PAYOUT_SHAPE', 'NONE payout mode requires all payout fields to be zero');
    }
  }

  // A self-cast moves no money at all. Allowing a non-zero amount here would create a message a
  // human reads as "free" while the contract reads as a paid mint.
  if (purpose === 'SELF_CAST') {
    if (fields.grossWei !== 0n || fields.sellerWei !== 0n || sellerSats !== 0n || payoutMode !== 'NONE') {
      fail('PAYOUT_SHAPE', 'SELF_CAST requires payout mode NONE and zero gross_wei, seller_wei and seller_sats');
    }
  }
}

/** Full structural validation. Called by both `buildMessage` and `parseMessage`. */
export function assertValidFields(fields: AuthorizationMessageFields): void {
  if (!(fields.purpose in AuthorizationPurpose)) {
    fail('BAD_ENUM', `unknown purpose ${JSON.stringify(fields.purpose)}`);
  }
  if (!(fields.payoutMode in PayoutMode)) {
    fail('BAD_ENUM', `unknown payout_mode ${JSON.stringify(fields.payoutMode)}`);
  }
  if (!BITCOIN_NETWORKS.includes(fields.bitcoinNetwork)) {
    fail('BAD_ENUM', `unknown bitcoin_network ${JSON.stringify(fields.bitcoinNetwork)}`);
  }

  assertTxid(fields.rootTxid, 'root_txid');
  assertTxid(fields.currentOutpointTxid, 'current_outpoint_txid');
  assertHex32(fields.contextId, 'context_id');
  assertHex32(fields.offerTermsHash, 'offer_terms_hash');
  assertHex32(fields.btcPayoutScriptHash, 'btc_payout_script_hash');
  assertHex32(fields.authorizationId, 'authorization_id');
  assertAddress(fields.verifyingContract, 'verifying_contract');
  assertAddress(fields.buyer, 'buyer');
  assertAddress(fields.recipient, 'recipient');
  assertAddress(fields.evmPayout, 'evm_payout');

  assertUint(fields.rootIndex, 'root_index', MAX_UINT32);
  assertUint(fields.currentOutpointVout, 'current_outpoint_vout', MAX_UINT32);
  assertUint(fields.rhChainId, 'rh_chain_id', MAX_UINT256);
  assertUint(fields.sellerSats, 'seller_sats', MAX_UINT64);
  assertUint(fields.grossWei, 'gross_wei', MAX_UINT256);
  assertUint(fields.sellerWei, 'seller_wei', MAX_UINT256);
  assertUint(fields.expiresAt, 'expires_at', MAX_UINT64);

  // A zero authorization id would make two otherwise-identical authorizations collide, defeating
  // the replay protection the oracle relies on.
  if (fields.authorizationId === ZERO_HASH) {
    fail('ZERO_AUTHORIZATION_ID', 'authorization_id must be non-zero');
  }

  assertPayoutShape(fields);
}

/*//////////////////////////////////////////////////////////////
                             BUILD
//////////////////////////////////////////////////////////////*/

/**
 * Render the exact bytes to be signed.
 *
 * @throws {CanonicalMessageError} on any invalid field. Never repairs input.
 */
export function buildMessage(fields: AuthorizationMessageFields): string {
  assertValidFields(fields);

  const values: Record<FieldKey, string> = {
    purpose: fields.purpose,
    bitcoin_network: fields.bitcoinNetwork,
    root_txid: fields.rootTxid,
    root_index: String(fields.rootIndex),
    current_outpoint_txid: fields.currentOutpointTxid,
    current_outpoint_vout: String(fields.currentOutpointVout),
    rh_chain_id: String(fields.rhChainId),
    verifying_contract: fields.verifyingContract,
    context_id: fields.contextId,
    offer_terms_hash: fields.offerTermsHash,
    buyer: fields.buyer,
    recipient: fields.recipient,
    payout_mode: fields.payoutMode,
    evm_payout: fields.evmPayout,
    btc_payout_script_hash: fields.btcPayoutScriptHash,
    seller_sats: fields.sellerSats.toString(10),
    gross_wei: fields.grossWei.toString(10),
    seller_wei: fields.sellerWei.toString(10),
    authorization_id: fields.authorizationId,
    expires_at: String(fields.expiresAt),
  };

  const lines = [MESSAGE_HEADER, ...FIELD_ORDER.map((key) => `${key}=${values[key]}`)];
  return `${lines.join('\n')}\n`;
}

/** UTF-8 (here, ASCII) bytes of the canonical message — what actually gets signed. */
export function messageBytes(fields: AuthorizationMessageFields): Uint8Array {
  return new TextEncoder().encode(buildMessage(fields));
}

/*//////////////////////////////////////////////////////////////
                             PARSE
//////////////////////////////////////////////////////////////*/

/**
 * Parse a canonical message back into typed fields.
 *
 * Strict by design: a message that would not have been produced by `buildMessage` is rejected, even
 * if its meaning is obvious. Being liberal in what we accept here would mean a wallet and a
 * verifier could agree on the *meaning* of two different byte strings while signing only one.
 */
export function parseMessage(raw: string): ParsedAuthorizationMessage {
  if (raw.includes('\r')) {
    fail('BAD_LINE_ENDING', 'message must use LF line endings; a CR was found');
  }
  if (!raw.endsWith('\n')) {
    fail('MISSING_FINAL_NEWLINE', 'message must end with exactly one LF');
  }
  if (raw.endsWith('\n\n')) {
    fail('MISSING_FINAL_NEWLINE', 'message must end with exactly one LF, found a blank final line');
  }

  const lines = raw.slice(0, -1).split('\n');
  const header = lines.shift();
  if (header !== MESSAGE_HEADER) {
    fail('BAD_HEADER', `expected header ${JSON.stringify(MESSAGE_HEADER)}, got ${JSON.stringify(header)}`);
  }

  if (lines.length !== FIELD_ORDER.length) {
    fail('MISSING_FIELD', `expected ${FIELD_ORDER.length} field lines, got ${lines.length}`);
  }

  const seen = new Set<string>();
  const kv = new Map<string, string>();

  lines.forEach((line, i) => {
    if (line !== line.trim()) {
      fail('TRAILING_WHITESPACE', `line ${i + 2} has leading or trailing whitespace`);
    }
    const eq = line.indexOf('=');
    if (eq <= 0) fail('MISSING_FIELD', `line ${i + 2} is not a key=value pair: ${JSON.stringify(line)}`);

    const key = line.slice(0, eq);
    const value = line.slice(eq + 1);

    if (seen.has(key)) fail('DUPLICATE_FIELD', `field ${key} appears more than once`);
    seen.add(key);

    const expected = FIELD_ORDER[i];
    if (key !== expected) {
      // Distinguish "unknown key" from "known key in the wrong place" — the two mean very
      // different things when triaging a wallet integration.
      if (!(FIELD_ORDER as readonly string[]).includes(key)) {
        fail('UNKNOWN_FIELD', `unknown field ${JSON.stringify(key)} at line ${i + 2}`);
      }
      fail('FIELD_ORDER', `expected field ${expected} at line ${i + 2}, got ${key}`);
    }
    kv.set(key, value);
  });

  const get = (key: FieldKey): string => {
    const v = kv.get(key);
    if (v === undefined) fail('MISSING_FIELD', `missing field ${key}`);
    return v;
  };

  const uint = (key: FieldKey): bigint => {
    const v = get(key);
    if (!UINT_RE.test(v)) {
      fail('BAD_UINT', `${key} must be a decimal integer with no leading zeros or separators, got ${JSON.stringify(v)}`);
    }
    return BigInt(v);
  };

  const purpose = get('purpose');
  if (!(purpose in AuthorizationPurpose)) fail('BAD_ENUM', `unknown purpose ${JSON.stringify(purpose)}`);
  const payoutMode = get('payout_mode');
  if (!(payoutMode in PayoutMode)) fail('BAD_ENUM', `unknown payout_mode ${JSON.stringify(payoutMode)}`);
  const bitcoinNetwork = get('bitcoin_network');
  if (!BITCOIN_NETWORKS.includes(bitcoinNetwork as BitcoinNetwork)) {
    fail('BAD_ENUM', `unknown bitcoin_network ${JSON.stringify(bitcoinNetwork)}`);
  }

  const fields: AuthorizationMessageFields = {
    purpose: purpose as AuthorizationPurposeName,
    bitcoinNetwork: bitcoinNetwork as BitcoinNetwork,
    rootTxid: get('root_txid'),
    rootIndex: Number(uint('root_index')),
    currentOutpointTxid: get('current_outpoint_txid'),
    currentOutpointVout: Number(uint('current_outpoint_vout')),
    rhChainId: Number(uint('rh_chain_id')),
    verifyingContract: get('verifying_contract') as EvmAddress,
    contextId: get('context_id') as Hex32,
    offerTermsHash: get('offer_terms_hash') as Hex32,
    buyer: get('buyer') as EvmAddress,
    recipient: get('recipient') as EvmAddress,
    payoutMode: payoutMode as PayoutModeName,
    evmPayout: get('evm_payout') as EvmAddress,
    btcPayoutScriptHash: get('btc_payout_script_hash') as Hex32,
    sellerSats: uint('seller_sats'),
    grossWei: uint('gross_wei'),
    sellerWei: uint('seller_wei'),
    authorizationId: get('authorization_id') as Hex32,
    expiresAt: Number(uint('expires_at')),
  };

  assertValidFields(fields);

  // Belt and braces: a round-trip that does not reproduce the input byte-for-byte means the parser
  // and the builder disagree, which is exactly the class of bug this whole package exists to stop.
  const rebuilt = buildMessage(fields);
  if (rebuilt !== raw) {
    fail('FIELD_ORDER', 'message did not survive a parse/build round trip; it is not in canonical form');
  }

  return { fields, raw, version: MESSAGE_VERSION };
}

/*//////////////////////////////////////////////////////////////
                        HUMAN PRESENTATION
//////////////////////////////////////////////////////////////*/

/** Format wei as ETH with full precision and no rounding — a rounded amount must never be shown. */
function formatEth(wei: bigint): string {
  const negative = wei < 0n;
  const abs = negative ? -wei : wei;
  const whole = abs / 10n ** 18n;
  const frac = (abs % 10n ** 18n).toString().padStart(18, '0').replace(/0+$/, '');
  return `${negative ? '-' : ''}${whole}${frac ? `.${frac}` : ''} ETH`;
}

/** Format satoshis with a BTC equivalent, both exact. */
function formatSats(sats: bigint): string {
  const btc = `${sats / 100_000_000n}.${(sats % 100_000_000n).toString().padStart(8, '0')}`;
  return `${sats.toLocaleString('en-US')} sats (${btc} BTC)`;
}

/**
 * A plain-language summary to show a human BEFORE they sign.
 *
 * The canonical message is what gets signed, but it is not what a person should be asked to reason
 * about. This renders the same facts as sentences. The UI must show both: the summary to decide,
 * the raw message to verify.
 */
export function renderHumanSummary(fields: AuthorizationMessageFields): string {
  const lines: string[] = [];
  const inscription = `${fields.rootTxid}i${fields.rootIndex}`;

  switch (fields.purpose) {
    case 'PAID_EVM_MINT':
      lines.push('You are authorising a paid HoodPup mint from your Bitcoin Puppet.');
      break;
    case 'PAID_BTC_MINT':
      lines.push('You are authorising a paid HoodPup mint, paid to you in native Bitcoin.');
      break;
    case 'SELF_CAST':
      lines.push('You are casting a free HoodPup from your own Bitcoin Puppet.');
      break;
    case 'ROOT_BIND':
      lines.push('You are proving current control of this Bitcoin Puppet and naming a payout address.');
      break;
    case 'ROOT_INVALIDATE':
      lines.push('You are recording that this Bitcoin Puppet has moved.');
      break;
  }

  lines.push('');
  lines.push(`Bitcoin Puppet:   ${inscription}`);
  lines.push(`Currently at:     ${fields.currentOutpointTxid}:${fields.currentOutpointVout}`);
  lines.push(`Bitcoin network:  ${fields.bitcoinNetwork}`);
  lines.push('');
  lines.push('Your Puppet will NOT move. This signature does not spend it, transfer it, or');
  lines.push('give anyone else the ability to.');
  lines.push('');

  if (fields.purpose === 'PAID_EVM_MINT' || fields.purpose === 'PAID_BTC_MINT') {
    lines.push(`Buyer pays:       ${formatEth(fields.grossWei)} on Robinhood Chain`);
    if (fields.payoutMode === 'EVM') {
      lines.push(`You receive:      ${formatEth(fields.sellerWei)} on Robinhood Chain`);
      lines.push(`Paid to:          ${fields.evmPayout}`);
    } else {
      lines.push(`You receive:      ${formatSats(fields.sellerSats)} on Bitcoin`);
      lines.push(`Paid to script:   ${fields.btcPayoutScriptHash}`);
      lines.push('                  (sent by a bonded solver, then reimbursed in ETH)');
    }
    const treasury = (fields.grossWei * 2500n) / 10000n;
    const protocolShare = fields.grossWei - fields.sellerWei - treasury;
    lines.push(`Puppet treasury:  ${formatEth(treasury)}`);
    lines.push(`Protocol:         ${formatEth(protocolShare)}`);
    lines.push('');
  }

  lines.push(`HoodPup goes to:  ${fields.recipient}`);
  lines.push(`Robinhood chain:  ${fields.rhChainId}`);
  lines.push(`Contract:         ${fields.verifyingContract}`);
  lines.push(`Expires:          ${new Date(fields.expiresAt * 1000).toISOString()}`);
  lines.push('');
  lines.push('This authorisation is single use and cannot be replayed on another offer,');
  lines.push('another chain, or another contract.');

  return lines.join('\n');
}
