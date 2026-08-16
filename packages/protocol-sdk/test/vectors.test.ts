/**
 * Cross-language hash parity.
 *
 * This is the most important test in the TypeScript half of the repository. Every expected value in
 * `data/test-fixtures/hashing-vectors.json` was produced by *running* the Foundry suite against
 * `PuppetHashing.sol`. If TypeScript cannot reproduce one of them, the SDK, the verifier and the
 * five attestor services would compute digests the contract does not recognise — and nothing would
 * ever settle.
 *
 * The test is written to walk the vector file rather than hard-code cases, so a vector added on the
 * Solidity side is automatically enforced here instead of being quietly ignored.
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import type { Hex } from 'viem';

import {
  BITCOIN_PAYMENT_ATTESTATION_TYPEHASH,
  buildProof,
  buildRoot,
  collectionLeaf,
  COLLECTION_ID,
  hashBitcoinPaymentStruct,
  hashOwnershipStruct,
  hashRootSpendStruct,
  hashWithdrawalStruct,
  OFFER_ID_DOMAIN,
  OFFER_TERMS_DOMAIN,
  offerId,
  offerTermsHash,
  OUTPOINT_DOMAIN,
  outpointHash,
  OWNERSHIP_ATTESTATION_TYPEHASH,
  PAYMENT_OUTPUT_DOMAIN,
  paymentOutputKey,
  ROOT_SPEND_ATTESTATION_TYPEHASH,
  rootKey,
  scriptHash,
  verifyProof,
  WITHDRAWAL_TYPEHASH,
} from '../src/index.js';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const vectorFile = JSON.parse(readFileSync(join(ROOT, 'data', 'test-fixtures', 'hashing-vectors.json'), 'utf8')) as {
  vectors: Array<{ name: string; fn: string; inputs?: Record<string, unknown>; expected: unknown }>;
};

const byName = new Map(vectorFile.vectors.map((v) => [v.name, v]));

/** Look a vector up by name and fail loudly if the Solidity side renamed or dropped it. */
function vector(name: string) {
  const v = byName.get(name);
  if (!v) {
    throw new Error(
      `golden vector "${name}" is missing from data/test-fixtures/hashing-vectors.json. ` +
        'If Solidity renamed it, update this test; do not delete the assertion.',
    );
  }
  return v;
}

const hex = (v: unknown): Hex => v as Hex;
const big = (v: unknown): bigint => BigInt(v as string | number);
const num = (v: unknown): number => Number(v);

describe('domain constants', () => {
  it('COLLECTION_ID', () => expect(COLLECTION_ID).toBe(vector('collectionId').expected));
  it('OUTPOINT_DOMAIN', () => expect(OUTPOINT_DOMAIN).toBe(vector('outpointDomain').expected));
  it('PAYMENT_OUTPUT_DOMAIN', () => expect(PAYMENT_OUTPUT_DOMAIN).toBe(vector('paymentOutputDomain').expected));
  it('OFFER_TERMS_DOMAIN', () => expect(OFFER_TERMS_DOMAIN).toBe(vector('offerTermsDomain').expected));
  it('OFFER_ID_DOMAIN', () => expect(OFFER_ID_DOMAIN).toBe(vector('offerIdDomain').expected));

  it('outpoint and payment-output domains are distinct', () => {
    // Both hash (txid, vout). Without distinct domain tags an inscription's outpoint and a consumed
    // BTC payment output would share a value, and consuming one could be presented as the other.
    expect(OUTPOINT_DOMAIN).not.toBe(PAYMENT_OUTPUT_DOMAIN);
  });
});

describe('rootKey', () => {
  for (const name of ['rootKey/inscriptionA', 'rootKey/inscriptionB-sameTxidDifferentIndex', 'rootKey/inscriptionC']) {
    it(name, () => {
      const v = vector(name);
      expect(
        rootKey({
          inscriptionTxid: hex(v.inputs!['inscriptionTxid']),
          inscriptionIndex: num(v.inputs!['inscriptionIndex']),
        }),
      ).toBe(v.expected);
    });
  }

  it('sibling inscriptions sharing a reveal txid do not collide', () => {
    const a = vector('rootKey/inscriptionA').expected;
    const b = vector('rootKey/inscriptionB-sameTxidDifferentIndex').expected;
    expect(a).not.toBe(b);
  });
});

describe('collectionLeaf', () => {
  for (const name of ['collectionLeaf/inscriptionA', 'collectionLeaf/inscriptionB', 'collectionLeaf/inscriptionC']) {
    it(name, () => {
      const v = vector(name);
      const input = v.inputs!;
      const key = input['rootKey']
        ? hex(input['rootKey'])
        : rootKey({ inscriptionTxid: hex(input['inscriptionTxid']), inscriptionIndex: num(input['inscriptionIndex']) });
      expect(collectionLeaf(key)).toBe(v.expected);
    });
  }
});

describe('outpoint and payment output keys', () => {
  it('outpointHash', () => {
    const v = vector('outpointHash/fixtureOutpoint');
    expect(outpointHash(hex(v.inputs!['bitcoinTxid']), num(v.inputs!['vout']))).toBe(v.expected);
  });

  it('paymentOutputKey over the same inputs differs from outpointHash', () => {
    const v = vector('paymentOutputKey/sameInputsAsOutpointHash');
    const got = paymentOutputKey(hex(v.inputs!['bitcoinTxid']), num(v.inputs!['vout']));
    expect(got).toBe(v.expected);
    expect(got).not.toBe(vector('outpointHash/fixtureOutpoint').expected);
  });

  it('paymentOutputKey', () => {
    const v = vector('paymentOutputKey/fixturePayment');
    expect(paymentOutputKey(hex(v.inputs!['bitcoinTxid']), num(v.inputs!['vout']))).toBe(v.expected);
  });
});

describe('scriptHash', () => {
  it('P2TR scriptPubKey', () => {
    const v = vector('scriptHash/p2tr');
    const raw = (v.inputs!['rawScriptPubKey'] ?? v.inputs!['hex'] ?? v.inputs!['script']) as Hex;
    expect(scriptHash(raw)).toBe(v.expected);
  });
});

describe('offer hashing', () => {
  it('offerId', () => {
    const v = vector('offerId/fixture');
    const i = v.inputs!;
    expect(offerId(big(i['chainId']), hex(i['escrow']), hex(i['buyer']), big(i['buyerNonce']))).toBe(v.expected);
  });

  it('offerTermsHash', () => {
    const v = vector('offerTermsHash/fixture');
    const i = v.inputs!;
    expect(
      offerTermsHash({
        chainId: big(i['chainId']),
        escrow: hex(i['escrow']),
        offerId: hex(i['id']),
        kind: num(i['kind']),
        rootKey: hex(i['key']),
        buyer: hex(i['buyer']),
        recipient: hex(i['recipient']),
        grossWei: big(i['grossWei']),
        sellerWei: big(i['sellerWei']),
        sellerSats: big(i['sellerSats']),
        expiry: big(i['expiry']),
      }),
    ).toBe(v.expected);
  });
});

describe('EIP-712 typehashes', () => {
  it('OwnershipAttestation', () =>
    expect(OWNERSHIP_ATTESTATION_TYPEHASH).toBe(vector('typehash/OwnershipAttestation').expected));
  it('BitcoinPaymentAttestation', () =>
    expect(BITCOIN_PAYMENT_ATTESTATION_TYPEHASH).toBe(vector('typehash/BitcoinPaymentAttestation').expected));
  it('RootSpendAttestation', () =>
    expect(ROOT_SPEND_ATTESTATION_TYPEHASH).toBe(vector('typehash/RootSpendAttestation').expected));
  it('Withdrawal', () => expect(WITHDRAWAL_TYPEHASH).toBe(vector('typehash/Withdrawal').expected));
});

describe('attestation struct hashing', () => {
  it('OwnershipAttestation — all 22 fields', () => {
    const v = vector('hashStruct/OwnershipAttestation');
    const i = v.inputs!;
    expect(
      hashOwnershipStruct({
        purpose: num(i['purpose']),
        rootTxid: hex(i['rootTxid']),
        rootIndex: num(i['rootIndex']),
        contextId: hex(i['contextId']),
        offerTermsHash: hex(i['offerTermsHash']),
        currentOutpointHash: hex(i['currentOutpointHash']),
        ownerScriptHash: hex(i['ownerScriptHash']),
        bip322ProofHash: hex(i['bip322ProofHash']),
        buyer: hex(i['buyer']),
        recipient: hex(i['recipient']),
        payoutMode: num(i['payoutMode']),
        evmPayout: hex(i['evmPayout']),
        btcPayoutScriptHash: hex(i['btcPayoutScriptHash']),
        sellerSats: big(i['sellerSats']),
        grossWei: big(i['grossWei']),
        sellerWei: big(i['sellerWei']),
        bitcoinBlockHash: hex(i['bitcoinBlockHash']),
        bitcoinHeight: big(i['bitcoinHeight']),
        authorizationId: hex(i['authorizationId']),
        deadline: big(i['deadline']),
        attestorEpoch: big(i['attestorEpoch']),
        policyVersion: num(i['policyVersion']),
      }),
    ).toBe(v.expected);
  });

  it('BitcoinPaymentAttestation', () => {
    const v = vector('hashStruct/BitcoinPaymentAttestation');
    const i = v.inputs!;
    expect(
      hashBitcoinPaymentStruct({
        contextId: hex(i['contextId']),
        ownershipDigest: hex(i['ownershipDigest']),
        solver: hex(i['solver']),
        bitcoinTxid: hex(i['bitcoinTxid']),
        outputIndex: num(i['outputIndex']),
        recipientScriptHash: hex(i['recipientScriptHash']),
        amountSats: big(i['amountSats']),
        bitcoinBlockHash: hex(i['bitcoinBlockHash']),
        bitcoinHeight: big(i['bitcoinHeight']),
        authorizationId: hex(i['authorizationId']),
        deadline: big(i['deadline']),
        attestorEpoch: big(i['attestorEpoch']),
        policyVersion: num(i['policyVersion']),
      }),
    ).toBe(v.expected);
  });

  it('RootSpendAttestation', () => {
    const v = vector('hashStruct/RootSpendAttestation');
    const i = v.inputs!;
    expect(
      hashRootSpendStruct({
        rootTxid: hex(i['rootTxid']),
        rootIndex: num(i['rootIndex']),
        previousOutpointHash: hex(i['previousOutpointHash']),
        spendingTxid: hex(i['spendingTxid']),
        bitcoinBlockHash: hex(i['bitcoinBlockHash']),
        bitcoinHeight: big(i['bitcoinHeight']),
        authorizationId: hex(i['authorizationId']),
        deadline: big(i['deadline']),
        attestorEpoch: big(i['attestorEpoch']),
        policyVersion: num(i['policyVersion']),
      }),
    ).toBe(v.expected);
  });

  it('Withdrawal', () => {
    const v = vector('hashWithdrawal/fixture');
    const i = v.inputs!;
    expect(
      hashWithdrawalStruct(
        hex(i['beneficiary']),
        hex(i['recipient']),
        big(i['amount']),
        big(i['nonce']),
        big(i['deadline']),
      ),
    ).toBe(v.expected);
  });
});

describe('Merkle tree parity with the Solidity fixture builder', () => {
  it('reproduces the fixture manifest root', () => {
    const v = vector('collectionMerkleRoot/threeInscriptionFixtureManifest');
    expect(buildRoot((v.inputs!['leaves'] as Hex[]).slice())).toBe(v.expected);
  });

  it('reproduces the proof for inscriptionA', () => {
    const v = vector('collectionMerkleProof/inscriptionA');
    const i = v.inputs!;
    const proof = buildProof((i['leaves'] as Hex[]).slice(), hex(i['leaf']));
    expect(proof).toEqual(v.expected);
    expect(verifyProof(proof, hex(i['root']), hex(i['leaf']))).toBe(true);
  });

  it('every leaf in the fixture tree has a verifying proof', () => {
    const leaves = vector('collectionMerkleRoot/threeInscriptionFixtureManifest').inputs!['leaves'] as Hex[];
    const root = buildRoot(leaves.slice());
    for (const leaf of leaves) {
      expect(verifyProof(buildProof(leaves.slice(), leaf), root, leaf)).toBe(true);
    }
  });

  it('a leaf outside the tree never verifies', () => {
    const leaves = vector('collectionMerkleRoot/threeInscriptionFixtureManifest').inputs!['leaves'] as Hex[];
    const root = buildRoot(leaves.slice());
    const outsider = `0x${'99'.repeat(32)}` as Hex;
    expect(verifyProof(buildProof(leaves.slice(), leaves[0]!), root, outsider)).toBe(false);
  });
});

describe('coverage of the vector file', () => {
  it('asserts every vector the Solidity side publishes', () => {
    // A vector added on the Solidity side that nothing here checks is a silent gap in the
    // cross-language guarantee. Listing the intentionally-unasserted names makes any new one fail.
    const asserted = new Set(
      vectorFile.vectors
        .map((v) => v.name)
        .filter(
          (n) =>
            n.startsWith('rootKey/') ||
            n.startsWith('collectionLeaf/') ||
            n.startsWith('outpointHash/') ||
            n.startsWith('paymentOutputKey/') ||
            n.startsWith('scriptHash/') ||
            n.startsWith('offerId/') ||
            n.startsWith('offerTermsHash/') ||
            n.startsWith('typehash/') ||
            n.startsWith('hashStruct/') ||
            n.startsWith('hashWithdrawal/') ||
            n.startsWith('collectionMerkle') ||
            ['collectionId', 'outpointDomain', 'paymentOutputDomain', 'offerTermsDomain', 'offerIdDomain'].includes(n),
        ),
    );
    const unasserted = vectorFile.vectors.map((v) => v.name).filter((n) => !asserted.has(n));
    expect(unasserted, `unasserted golden vectors: ${unasserted.join(', ')}`).toEqual([]);
  });
});
