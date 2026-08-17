import { describe, expect, it } from 'vitest';
import {
  buildMessage,
  computeBip322ProofHash,
  FIELD_ORDER,
  MESSAGE_HEADER,
  messageBytes,
  normalizeProofBytes,
  parseMessage,
  renderHumanSummary,
  ZERO_ADDRESS,
  ZERO_HASH,
  type AuthorizationMessageFields,
} from '../src/index.js';

const TXID_A = 'a'.repeat(64);
const TXID_B = 'b'.repeat(64);

/** A complete, valid PAID_EVM authorization used as the base for mutation tests. */
const evmFields = (): AuthorizationMessageFields => ({
  purpose: 'PAID_EVM_MINT',
  bitcoinNetwork: 'mainnet',
  rootTxid: TXID_A,
  rootIndex: 0,
  currentOutpointTxid: TXID_B,
  currentOutpointVout: 1,
  rhChainId: 4663,
  verifyingContract: '0x1111111111111111111111111111111111111111',
  contextId: `0x${'22'.repeat(32)}`,
  offerTermsHash: `0x${'33'.repeat(32)}`,
  buyer: '0x4444444444444444444444444444444444444444',
  recipient: '0x5555555555555555555555555555555555555555',
  payoutMode: 'EVM',
  evmPayout: '0x6666666666666666666666666666666666666666',
  btcPayoutScriptHash: ZERO_HASH,
  sellerSats: 0n,
  grossWei: 100_000_000_000_000_000n, // 0.1 ETH
  sellerWei: 50_000_000_000_000_000n, // 0.05 ETH
  authorizationId: `0x${'77'.repeat(32)}`,
  expiresAt: 1_786_870_800,
});

const btcFields = (): AuthorizationMessageFields => ({
  ...evmFields(),
  purpose: 'PAID_BTC_MINT',
  payoutMode: 'BTC',
  evmPayout: ZERO_ADDRESS,
  btcPayoutScriptHash: `0x${'88'.repeat(32)}`,
  sellerSats: 50_000n,
});

const selfCastFields = (): AuthorizationMessageFields => ({
  ...evmFields(),
  purpose: 'SELF_CAST',
  payoutMode: 'NONE',
  evmPayout: ZERO_ADDRESS,
  btcPayoutScriptHash: ZERO_HASH,
  sellerSats: 0n,
  grossWei: 0n,
  sellerWei: 0n,
});

const rootBindFields = (): AuthorizationMessageFields => ({
  ...selfCastFields(),
  purpose: 'ROOT_BIND',
  payoutMode: 'EVM',
  evmPayout: '0x6666666666666666666666666666666666666666',
});

const rootInvalidateFields = (): AuthorizationMessageFields => ({
  ...selfCastFields(),
  purpose: 'ROOT_INVALIDATE',
});

describe('canonical message format', () => {
  it('renders the exact expected bytes for a PAID_EVM authorization', () => {
    // This literal IS the specification. If it changes, the message version must change with it,
    // because every previously collected signature becomes invalid.
    expect(buildMessage(evmFields())).toBe(
      'HOODPUPS AUTHORIZATION V1\n' +
        'purpose=PAID_EVM_MINT\n' +
        'bitcoin_network=mainnet\n' +
        `root_txid=${TXID_A}\n` +
        'root_index=0\n' +
        `current_outpoint_txid=${TXID_B}\n` +
        'current_outpoint_vout=1\n' +
        'rh_chain_id=4663\n' +
        'verifying_contract=0x1111111111111111111111111111111111111111\n' +
        `context_id=0x${'22'.repeat(32)}\n` +
        `offer_terms_hash=0x${'33'.repeat(32)}\n` +
        'buyer=0x4444444444444444444444444444444444444444\n' +
        'recipient=0x5555555555555555555555555555555555555555\n' +
        'payout_mode=EVM\n' +
        'evm_payout=0x6666666666666666666666666666666666666666\n' +
        `btc_payout_script_hash=${ZERO_HASH}\n` +
        'seller_sats=0\n' +
        'gross_wei=100000000000000000\n' +
        'seller_wei=50000000000000000\n' +
        `authorization_id=0x${'77'.repeat(32)}\n` +
        'expires_at=1786870800\n',
    );
  });

  it('is pure ASCII, LF only, and ends with exactly one newline', () => {
    for (const fields of [evmFields(), btcFields(), selfCastFields(), rootBindFields(), rootInvalidateFields()]) {
      const msg = buildMessage(fields);
      expect(msg).not.toContain('\r');
      expect(msg.endsWith('\n')).toBe(true);
      expect(msg.endsWith('\n\n')).toBe(false);
      expect(/^[\x20-\x7e\n]*$/.test(msg)).toBe(true);
      // No line carries leading or trailing whitespace.
      for (const line of msg.slice(0, -1).split('\n')) {
        expect(line).toBe(line.trim());
      }
    }
  });

  it('emits every field in the frozen order, none omitted', () => {
    const lines = buildMessage(selfCastFields()).slice(0, -1).split('\n');
    expect(lines[0]).toBe(MESSAGE_HEADER);
    expect(lines.slice(1).map((l) => l.split('=')[0])).toEqual([...FIELD_ORDER]);
  });

  it('renders zero values rather than omitting inapplicable fields', () => {
    const msg = buildMessage(selfCastFields());
    expect(msg).toContain(`evm_payout=${ZERO_ADDRESS}\n`);
    expect(msg).toContain(`btc_payout_script_hash=${ZERO_HASH}\n`);
    expect(msg).toContain('seller_sats=0\n');
    expect(msg).toContain('gross_wei=0\n');
  });

  it('round-trips build -> parse -> build for every purpose', () => {
    for (const fields of [evmFields(), btcFields(), selfCastFields(), rootBindFields(), rootInvalidateFields()]) {
      const raw = buildMessage(fields);
      const parsed = parseMessage(raw);
      expect(parsed.fields).toEqual(fields);
      expect(buildMessage(parsed.fields)).toBe(raw);
      expect(parsed.raw).toBe(raw);
    }
  });

  it('produces UTF-8 bytes matching the string length for pure ASCII', () => {
    const msg = buildMessage(evmFields());
    expect(messageBytes(evmFields())).toEqual(new TextEncoder().encode(msg));
    expect(messageBytes(evmFields()).length).toBe(msg.length);
  });
});

describe('parser strictness', () => {
  const valid = () => buildMessage(evmFields());

  it('rejects CRLF line endings', () => {
    expect(() => parseMessage(valid().replace(/\n/g, '\r\n'))).toThrow(/LF line endings/);
  });

  it('rejects a missing trailing newline', () => {
    expect(() => parseMessage(valid().slice(0, -1))).toThrow(/exactly one LF/);
  });

  it('rejects a doubled trailing newline', () => {
    expect(() => parseMessage(`${valid()}\n`)).toThrow(/exactly one LF/);
  });

  it('rejects a wrong or missing header', () => {
    expect(() => parseMessage(valid().replace(MESSAGE_HEADER, 'HOODPUPS AUTHORIZATION V2'))).toThrow(/header/);
  });

  it('rejects reordered fields even though the content is identical', () => {
    const lines = valid().slice(0, -1).split('\n');
    [lines[1], lines[2]] = [lines[2]!, lines[1]!];
    expect(() => parseMessage(`${lines.join('\n')}\n`)).toThrow(/expected field/);
  });

  it('rejects an extra unknown field', () => {
    expect(() => parseMessage(valid().replace('purpose=', 'purpouse='))).toThrow(/unknown field/);
  });

  it('rejects a duplicated field', () => {
    // Two independent guards catch this. Inserting a duplicate changes the line count, which the
    // arity check rejects first.
    const lines = valid().slice(0, -1).split('\n');
    lines.splice(2, 0, lines[1]!);
    expect(() => parseMessage(`${lines.join('\n')}\n`)).toThrow(/expected 20 field lines/);

    // Overwriting a line with a copy of its neighbour keeps the arity, so the explicit duplicate
    // check is what fires — and it reports the duplicated key, which is the more useful error.
    const overwritten = valid().slice(0, -1).split('\n');
    overwritten[2] = overwritten[1]!;
    expect(() => parseMessage(`${overwritten.join('\n')}\n`)).toThrow(/field purpose appears more than once/);
  });

  it('rejects trailing whitespace on a field line', () => {
    expect(() => parseMessage(valid().replace('root_index=0\n', 'root_index=0 \n'))).toThrow(/whitespace/);
  });

  it('rejects uppercase hex in a txid', () => {
    expect(() => parseMessage(valid().replace(TXID_A, TXID_A.toUpperCase()))).toThrow(/root_txid/);
  });

  it('rejects a 0x prefix on a Bitcoin txid', () => {
    expect(() => parseMessage(valid().replace(`root_txid=${TXID_A}`, `root_txid=0x${TXID_A}`))).toThrow(/root_txid/);
  });

  it('rejects a mixed-case EVM address rather than silently lowercasing it', () => {
    // EIP-55 checksummed input is a *different byte string* than the lowercase form. Accepting it
    // would let a wallet display one encoding while the verifier hashes another.
    const checksummed = '0xAbCdEf1234567890aBcDeF1234567890AbCdEf12';
    expect(() =>
      parseMessage(valid().replace('buyer=0x4444444444444444444444444444444444444444', `buyer=${checksummed}`)),
    ).toThrow(/buyer/);
  });

  it('rejects integers with leading zeros or separators', () => {
    expect(() => parseMessage(valid().replace('root_index=0\n', 'root_index=00\n'))).toThrow(/decimal integer/);
    expect(() => parseMessage(valid().replace('rh_chain_id=4663', 'rh_chain_id=4_663'))).toThrow(/decimal integer/);
  });

  it('rejects a zero authorization_id', () => {
    expect(() => parseMessage(valid().replace(`0x${'77'.repeat(32)}`, ZERO_HASH))).toThrow(/authorization_id/);
  });
});

describe('payout shape enforcement', () => {
  it('rejects EVM mode with a zero payout address', () => {
    expect(() => buildMessage({ ...evmFields(), evmPayout: ZERO_ADDRESS })).toThrow(/non-zero evm_payout/);
  });

  it('rejects EVM mode carrying BTC fields', () => {
    expect(() => buildMessage({ ...evmFields(), sellerSats: 1n })).toThrow(/seller_sats to be 0/);
    expect(() => buildMessage({ ...evmFields(), btcPayoutScriptHash: `0x${'99'.repeat(32)}` })).toThrow(
      /zero btc_payout_script_hash/,
    );
  });

  it('rejects BTC mode carrying an EVM payout address', () => {
    expect(() => buildMessage({ ...btcFields(), evmPayout: '0x6666666666666666666666666666666666666666' })).toThrow(
      /zero evm_payout/,
    );
  });

  it('rejects BTC mode with zero sats', () => {
    expect(() => buildMessage({ ...btcFields(), sellerSats: 0n })).toThrow(/seller_sats > 0/);
  });

  it('rejects a self-cast that carries money', () => {
    expect(() => buildMessage({ ...selfCastFields(), grossWei: 1n })).toThrow(/SELF_CAST/);
    expect(() => buildMessage({ ...selfCastFields(), payoutMode: 'EVM' })).toThrow(/SELF_CAST|non-zero evm_payout/);
  });

  it('uses the on-chain ROOT_BIND shape: EVM beneficiary with no money', () => {
    expect(buildMessage(rootBindFields())).toContain('purpose=ROOT_BIND\n');
    expect(() => buildMessage({ ...rootBindFields(), payoutMode: 'NONE' })).toThrow(/ROOT_BIND/);
    expect(() => buildMessage({ ...rootBindFields(), evmPayout: ZERO_ADDRESS })).toThrow(/ROOT_BIND/);
    expect(() => buildMessage({ ...rootBindFields(), grossWei: 1n })).toThrow(/ROOT_BIND/);
    expect(() => buildMessage({ ...rootBindFields(), sellerWei: 1n })).toThrow(/ROOT_BIND/);
    expect(() => buildMessage({ ...rootBindFields(), sellerSats: 1n })).toThrow(/ROOT_BIND/);
    expect(() => buildMessage({ ...rootBindFields(), btcPayoutScriptHash: `0x${'99'.repeat(32)}` })).toThrow(
      /ROOT_BIND/,
    );
  });

  it('requires every ROOT_INVALIDATE payout and monetary field to be zero', () => {
    expect(buildMessage(rootInvalidateFields())).toContain('purpose=ROOT_INVALIDATE\n');
    expect(() => buildMessage({ ...rootInvalidateFields(), payoutMode: 'EVM' })).toThrow(/ROOT_INVALIDATE/);
    expect(() => buildMessage({ ...rootInvalidateFields(), grossWei: 1n })).toThrow(/ROOT_INVALIDATE/);
  });

  it('rejects a seller share larger than the escrowed total', () => {
    expect(() => buildMessage({ ...evmFields(), sellerWei: evmFields().grossWei + 1n })).toThrow(
      /cannot exceed gross_wei/,
    );
    expect(() => buildMessage({ ...btcFields(), sellerWei: btcFields().grossWei + 1n })).toThrow(
      /cannot exceed gross_wei/,
    );
  });
});

describe('field mutation changes the signed bytes', () => {
  // Every field must be load-bearing. If mutating one produced identical bytes, an attacker could
  // swap it after the holder signed.
  const base = buildMessage(evmFields());

  const mutations: Array<[string, Partial<AuthorizationMessageFields>]> = [
    ['rootTxid', { rootTxid: 'c'.repeat(64) }],
    ['rootIndex', { rootIndex: 1 }],
    ['currentOutpointTxid', { currentOutpointTxid: 'd'.repeat(64) }],
    ['currentOutpointVout', { currentOutpointVout: 2 }],
    ['rhChainId', { rhChainId: 46630 }],
    ['verifyingContract', { verifyingContract: '0x9999999999999999999999999999999999999999' }],
    ['contextId', { contextId: `0x${'ab'.repeat(32)}` }],
    ['offerTermsHash', { offerTermsHash: `0x${'cd'.repeat(32)}` }],
    ['buyer', { buyer: '0x9999999999999999999999999999999999999999' }],
    ['recipient', { recipient: '0x9999999999999999999999999999999999999999' }],
    ['evmPayout', { evmPayout: '0x9999999999999999999999999999999999999999' }],
    ['grossWei', { grossWei: 100_000_000_000_000_001n }],
    ['sellerWei', { sellerWei: 50_000_000_000_000_001n }],
    ['authorizationId', { authorizationId: `0x${'ef'.repeat(32)}` }],
    ['expiresAt', { expiresAt: 1_786_870_801 }],
    ['bitcoinNetwork', { bitcoinNetwork: 'testnet' }],
  ];

  for (const [name, patch] of mutations) {
    it(`changing ${name} changes the message`, () => {
      expect(buildMessage({ ...evmFields(), ...patch })).not.toBe(base);
    });
  }

  it('the redirect attack is impossible: a different payout address is a different message', () => {
    const honest = buildMessage(evmFields());
    const attacker = buildMessage({ ...evmFields(), evmPayout: '0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef' });
    expect(attacker).not.toBe(honest);
  });
});

describe('bip322ProofHash', () => {
  const msg = buildMessage(evmFields());

  it('is deterministic', () => {
    expect(computeBip322ProofHash('simple', '0xdeadbeef', msg)).toBe(computeBip322ProofHash('simple', '0xdeadbeef', msg));
  });

  it('binds the variant', () => {
    expect(computeBip322ProofHash('simple', '0xdeadbeef', msg)).not.toBe(
      computeBip322ProofHash('full', '0xdeadbeef', msg),
    );
  });

  it('binds the message, so a proof cannot be lifted onto another authorization', () => {
    const other = buildMessage({ ...evmFields(), authorizationId: `0x${'ee'.repeat(32)}` });
    expect(computeBip322ProofHash('simple', '0xdeadbeef', msg)).not.toBe(
      computeBip322ProofHash('simple', '0xdeadbeef', other),
    );
  });

  it('binds the proof bytes', () => {
    expect(computeBip322ProofHash('simple', '0xdeadbeef', msg)).not.toBe(
      computeBip322ProofHash('simple', '0xdeadbeee', msg),
    );
  });

  it('is encoding neutral across hex, 0x-hex and raw bytes', () => {
    const bytes = new Uint8Array([0xde, 0xad, 0xbe, 0xef]);
    const a = computeBip322ProofHash('simple', bytes, msg);
    const b = computeBip322ProofHash('simple', '0xdeadbeef', msg);
    expect(a).toBe(b);
  });

  it('decodes base64 to the same bytes as hex', () => {
    // 0xdeadbeef === base64 "3q2+7w=="
    expect(normalizeProofBytes('3q2+7w==')).toEqual(normalizeProofBytes('0xdeadbeef'));
  });

  it('refuses input that is ambiguously hex or base64 instead of guessing', () => {
    // "abcd" parses as both 2 hex bytes and 3 base64 bytes.
    expect(() => normalizeProofBytes('abcd')).toThrow(/ambiguous/);
  });

  it('rejects a message without its trailing newline', () => {
    expect(() => computeBip322ProofHash('simple', '0xdeadbeef', msg.slice(0, -1))).toThrow(/trailing LF/);
  });

  it('rejects an unknown variant', () => {
    // @ts-expect-error deliberately invalid variant
    expect(() => computeBip322ProofHash('handwave', '0xdeadbeef', msg)).toThrow(/variant/);
  });
});

describe('human summary', () => {
  it('states plainly that the Puppet does not move', () => {
    expect(renderHumanSummary(evmFields())).toContain('Your Puppet will NOT move');
  });

  it('shows exact ETH amounts without rounding', () => {
    const summary = renderHumanSummary(evmFields());
    expect(summary).toContain('0.1 ETH');
    expect(summary).toContain('0.05 ETH');
    expect(summary).toContain('0.025 ETH'); // treasury and protocol shares
  });

  it('shows native BTC in sats and BTC for a BTC-mode offer', () => {
    const summary = renderHumanSummary(btcFields());
    expect(summary).toContain('50,000 sats');
    expect(summary).toContain('0.00050000 BTC');
    expect(summary).toContain('bonded solver');
  });

  it('never claims to be a bridge or an atomic swap', () => {
    for (const fields of [evmFields(), btcFields(), selfCastFields()]) {
      const summary = renderHumanSummary(fields).toLowerCase();
      expect(summary).not.toContain('bridge');
      expect(summary).not.toContain('atomic swap');
      expect(summary).not.toContain('trustless');
    }
  });
});
