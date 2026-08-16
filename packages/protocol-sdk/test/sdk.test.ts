import { describe, expect, it } from 'vitest';
import type { Hex } from 'viem';
import {
  assertConservation,
  assertSupportedChain,
  buildManifest,
  buildProof,
  buildRoot,
  bytes32ToTxid,
  canBuyerCancel,
  canExpireReservation,
  canRefundExpired,
  canRefundUnfillable,
  canSolverReserve,
  collectionLeaf,
  formatBtc,
  formatEther,
  formatInscriptionId,
  formatOutpoint,
  getDeployment,
  isTerminal,
  LOCAL_CHAIN_ID,
  ManifestError,
  OfferKind,
  OfferStatus,
  parseInscriptionId,
  parseOutpoint,
  purposeForKind,
  quote,
  relayerStatusFromCount,
  reverseTxidByteOrder,
  ROBINHOOD_MAINNET_CHAIN_ID,
  rootKey,
  scriptHash,
  SdkValidationError,
  txidToBytes32,
  UnsupportedChainError,
  verifyProof,
} from '../src/index.js';

const TXID = 'a'.repeat(64);
const TXID_HEX = `0x${TXID}` as Hex;

describe('validation refuses to normalise', () => {
  it('rejects an uppercase txid instead of lowercasing it', () => {
    expect(() => txidToBytes32(TXID.toUpperCase())).toThrow(SdkValidationError);
  });

  it('rejects a 0x-prefixed bare txid', () => {
    expect(() => txidToBytes32(`0x${TXID}`)).toThrow(SdkValidationError);
  });

  it('rejects a checksummed EVM address in rootKey inputs', () => {
    expect(() => rootKey({ inscriptionTxid: TXID_HEX.toUpperCase() as Hex, inscriptionIndex: 0 })).toThrow(
      SdkValidationError,
    );
  });

  it('rejects an inscription index that does not fit uint32', () => {
    expect(() => rootKey({ inscriptionTxid: TXID_HEX, inscriptionIndex: 2 ** 32 })).toThrow(/uint32/);
  });

  it('rejects an odd-length scriptPubKey', () => {
    expect(() => scriptHash('0x512' as Hex)).toThrow(/even length/);
  });

  it('round-trips txid <-> bytes32 without touching byte order', () => {
    expect(bytes32ToTxid(txidToBytes32(TXID))).toBe(TXID);
  });

  it('reverseTxidByteOrder is available but is its own explicit call', () => {
    // Byte order is a security primitive. Reversal exists only for APIs that demand internal order,
    // and must never appear in a hashing path — naming it loudly is the enforcement mechanism.
    const reversed = reverseTxidByteOrder('00'.repeat(31) + 'ff');
    expect(reversed).toBe('ff' + '00'.repeat(31));
    expect(reverseTxidByteOrder(reversed)).toBe('00'.repeat(31) + 'ff');
  });
});

describe('inscription id and outpoint parsing', () => {
  it('parses and re-renders an inscription id', () => {
    const root = parseInscriptionId(`${TXID}i7`);
    expect(root).toEqual({ inscriptionTxid: TXID_HEX, inscriptionIndex: 7 });
    expect(formatInscriptionId(root)).toBe(`${TXID}i7`);
  });

  it('rejects a leading zero on the index, so two strings cannot map to one RootId', () => {
    expect(() => parseInscriptionId(`${TXID}i00`)).toThrow(/leading zeros/);
    expect(() => parseInscriptionId(`${TXID}i07`)).toThrow(/leading zeros/);
  });

  it('rejects a missing separator, uppercase hex and a negative index', () => {
    expect(() => parseInscriptionId(TXID)).toThrow(SdkValidationError);
    expect(() => parseInscriptionId(`${TXID.toUpperCase()}i0`)).toThrow(SdkValidationError);
    expect(() => parseInscriptionId(`${TXID}i-1`)).toThrow(SdkValidationError);
  });

  it('parses and re-renders an outpoint', () => {
    const o = parseOutpoint(`${TXID}:3`);
    expect(o).toEqual({ bitcoinTxid: TXID_HEX, vout: 3 });
    expect(formatOutpoint(o.bitcoinTxid, o.vout)).toBe(`${TXID}:3`);
  });
});

describe('economics — the split conserves exactly', () => {
  it('splits 0.1 ETH into 50/25/25', () => {
    const s = quote(100_000_000_000_000_000n);
    expect(s.seller).toBe(50_000_000_000_000_000n);
    expect(s.puppetTreasury).toBe(25_000_000_000_000_000n);
    expect(s.protocol).toBe(25_000_000_000_000_000n);
    assertConservation(s);
  });

  it('conserves at every rounding edge', () => {
    // Three independent floor divisions would strand dust here. Protocol absorbs the remainder.
    for (const gross of [0n, 1n, 2n, 3n, 4n, 5n, 7n, 9999n, 10001n]) {
      const s = quote(gross);
      expect(s.seller + s.puppetTreasury + s.protocol).toBe(gross);
    }
  });

  it('gives the remainder to protocol, never to the seller', () => {
    const s = quote(3n);
    expect(s.seller).toBe(1n);
    expect(s.puppetTreasury).toBe(0n);
    expect(s.protocol).toBe(2n);
  });

  it('conserves over a wide sweep', () => {
    for (let i = 0n; i < 2000n; i++) {
      const gross = i * 7919n + i;
      expect(quote(gross).seller + quote(gross).puppetTreasury + quote(gross).protocol).toBe(gross);
    }
  });

  it('rejects a negative gross', () => {
    expect(() => quote(-1n)).toThrow(RangeError);
  });

  it('formats amounts exactly, without rounding', () => {
    expect(formatEther(100_000_000_000_000_000n)).toBe('0.1');
    expect(formatEther(1n)).toBe('0.000000000000000001');
    expect(formatEther(10n ** 18n)).toBe('1');
    expect(formatBtc(50_000n)).toBe('0.00050000');
    expect(formatBtc(100_000_000n)).toBe('1.00000000');
  });
});

describe('offer state machine', () => {
  const offer = (over: Partial<Parameters<typeof canRefundExpired>[0]> = {}) => ({
    kind: OfferKind.PAID_EVM,
    status: OfferStatus.OPEN,
    expiry: 1000n,
    grossWei: 10n,
    reservationExpiry: 0n,
    ...over,
  });

  it('a buyer can never cancel an open offer', () => {
    // Deliberate: a holder may be mid cold-wallet ceremony, and a cancellable offer would let a
    // buyer bait a signature and withdraw.
    expect(canBuyerCancel()).toBe(false);
  });

  it('refunds only after expiry', () => {
    expect(canRefundExpired(offer(), 999n)).toBe(false);
    expect(canRefundExpired(offer(), 1000n)).toBe(false);
    expect(canRefundExpired(offer(), 1001n)).toBe(true);
  });

  it('BTC_APPROVED is refundable at expiry but BTC_RESERVED is not', () => {
    expect(canRefundExpired(offer({ status: OfferStatus.BTC_APPROVED }), 1001n)).toBe(true);
    // A solver may already have broadcast the payment; refunding underneath them would leave them
    // having paid real BTC for nothing. The reservation must be expired first.
    expect(canRefundExpired(offer({ status: OfferStatus.BTC_RESERVED }), 1001n)).toBe(false);
  });

  it('terminal states never transition again', () => {
    for (const status of [OfferStatus.SETTLED, OfferStatus.REFUNDED]) {
      expect(isTerminal(status)).toBe(true);
      expect(canRefundExpired(offer({ status }), 99_999n)).toBe(false);
      expect(canRefundUnfillable(offer({ status }), true)).toBe(false);
    }
  });

  it('a losing competing offer is immediately refundable', () => {
    expect(canRefundUnfillable(offer(), true)).toBe(true);
    expect(canRefundUnfillable(offer(), false)).toBe(false);
  });

  it('solver reservation windows', () => {
    expect(canSolverReserve(offer({ status: OfferStatus.BTC_APPROVED }), 999n)).toBe(true);
    expect(canSolverReserve(offer({ status: OfferStatus.BTC_APPROVED }), 1001n)).toBe(false);
    expect(canSolverReserve(offer({ status: OfferStatus.OPEN }), 999n)).toBe(false);
    expect(canExpireReservation(offer({ status: OfferStatus.BTC_RESERVED, reservationExpiry: 500n }), 501n)).toBe(true);
    expect(canExpireReservation(offer({ status: OfferStatus.BTC_RESERVED, reservationExpiry: 500n }), 500n)).toBe(false);
  });

  it('maps each offer kind to its required authorization purpose', () => {
    expect(purposeForKind(OfferKind.PAID_EVM)).toBe(0);
    expect(purposeForKind(OfferKind.PAID_BTC)).toBe(1);
    expect(purposeForKind(OfferKind.SELF_CAST)).toBe(2);
    expect(() => purposeForKind(9)).toThrow(RangeError);
  });

  it('relayer progress counts matching facts, not signatures', () => {
    expect(relayerStatusFromCount(0)).toBe('VERIFYING');
    expect(relayerStatusFromCount(1)).toBe('ATTESTATIONS_1_OF_3');
    expect(relayerStatusFromCount(2)).toBe('ATTESTATIONS_2_OF_3');
    expect(relayerStatusFromCount(3)).toBe('READY_TO_SUBMIT');
    expect(relayerStatusFromCount(5)).toBe('READY_TO_SUBMIT');
  });
});

describe('merkle edge cases', () => {
  const leaf = (n: number) => collectionLeaf(rootKey({ inscriptionTxid: TXID_HEX, inscriptionIndex: n }));

  it('a single-leaf tree roots at the leaf with an empty proof', () => {
    const leaves = [leaf(0)];
    expect(buildRoot(leaves)).toBe(leaves[0]);
    expect(buildProof(leaves, leaves[0]!)).toEqual([]);
    expect(verifyProof([], leaves[0]!, leaves[0]!)).toBe(true);
  });

  it('every leaf verifies for odd and even tree sizes', () => {
    for (const size of [1, 2, 3, 4, 5, 8, 9, 17]) {
      const leaves = Array.from({ length: size }, (_, i) => leaf(i));
      const root = buildRoot(leaves);
      for (const l of leaves) {
        expect(verifyProof(buildProof(leaves, l), root, l), `size ${size}`).toBe(true);
      }
    }
  });

  it('leaf ordering does not change the root', () => {
    const leaves = [leaf(0), leaf(1), leaf(2), leaf(3), leaf(4)];
    expect(buildRoot([...leaves].reverse())).toBe(buildRoot(leaves));
  });

  it('rejects a duplicate leaf rather than collapsing it', () => {
    expect(() => buildRoot([leaf(0), leaf(0)])).toThrow(ManifestError);
  });

  it('rejects an empty tree', () => {
    expect(() => buildRoot([])).toThrow(ManifestError);
  });

  it('rejects a proof request for a leaf outside the tree', () => {
    expect(() => buildProof([leaf(0), leaf(1)], leaf(9))).toThrow(/not in the tree/);
  });
});

describe('manifest builder fails closed', () => {
  const goodManifest = {
    collection: 'Bitcoin Puppets',
    version: 'test-v1',
    network: 'mainnet',
    inscriptions: [{ id: `${TXID}i0` }, { id: `${TXID}i1` }, { id: `${'b'.repeat(64)}i0` }],
  };

  it('builds a root, a manifest hash and a verifying proof per entry', () => {
    const built = buildManifest(goodManifest, JSON.stringify(goodManifest));
    expect(built.leafCount).toBe(3);
    expect(built.merkleRoot).toMatch(/^0x[0-9a-f]{64}$/);
    expect(built.manifestHash).toMatch(/^0x[0-9a-f]{64}$/);
    for (const r of built.roots) {
      expect(verifyProof(built.proofs[r.rootKey]!, built.merkleRoot, r.leaf)).toBe(true);
    }
  });

  it('refuses the shipped example manifest', () => {
    // The Merkle root is immutable once deployed. Committing to fabricated inscription ids would be
    // permanent, so the example carries a marker and the builder refuses it outright.
    expect(() =>
      buildManifest({ ...goodManifest, EXAMPLE_ONLY_DO_NOT_DEPLOY: true }, '{}'),
    ).toThrow(/EXAMPLE/);
  });

  it('refuses an empty manifest', () => {
    expect(() => buildManifest({ ...goodManifest, inscriptions: [] }, '{}')).toThrow(/no inscriptions/);
  });

  it('refuses a duplicated inscription', () => {
    expect(() =>
      buildManifest({ ...goodManifest, inscriptions: [{ id: `${TXID}i0` }, { id: `${TXID}i0` }] }, '{}'),
    ).toThrow(/duplicate/);
  });

  it('refuses a malformed inscription id', () => {
    expect(() => buildManifest({ ...goodManifest, inscriptions: [{ id: 'not-an-id' }] }, '{}')).toThrow(
      SdkValidationError,
    );
  });

  it('the manifest hash tracks the file bytes, not just the leaf set', () => {
    const a = buildManifest(goodManifest, JSON.stringify(goodManifest));
    const b = buildManifest(goodManifest, `${JSON.stringify(goodManifest)}\n`);
    expect(a.merkleRoot).toBe(b.merkleRoot);
    expect(a.manifestHash).not.toBe(b.manifestHash);
  });
});

describe('chain guards fail closed', () => {
  it('accepts the two Robinhood chains', () => {
    expect(assertSupportedChain(ROBINHOOD_MAINNET_CHAIN_ID).isProduction).toBe(true);
    expect(assertSupportedChain(46630).isProduction).toBe(false);
  });

  it('rejects an unknown chain id rather than defaulting', () => {
    expect(() => assertSupportedChain(1)).toThrow(UnsupportedChainError);
    expect(() => assertSupportedChain(8453)).toThrow(UnsupportedChainError);
  });

  it('requires an explicit override for the local chain', () => {
    expect(() => assertSupportedChain(LOCAL_CHAIN_ID)).toThrow(UnsupportedChainError);
    expect(assertSupportedChain(LOCAL_CHAIN_ID, true).bitcoinNetwork).toBe('regtest');
  });

  it('refuses to invent an address when no deployment is registered', () => {
    expect(() => getDeployment(ROBINHOOD_MAINNET_CHAIN_ID)).toThrow(/no HoodPups deployment/);
  });
});
