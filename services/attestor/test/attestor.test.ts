import { describe, expect, it } from 'vitest';
import { buildMessage, type AuthorizationMessageFields } from '@hoodpups/canonical-message';
import { offerTermsHash, ownershipDigest, rootKey, parseInscriptionId, scriptHash } from '@hoodpups/protocol-sdk';
import { classifyScriptPubKey, RejectionCode, VerificationRejection } from '@hoodpups/bitcoin-verifier';
import { recoverAddress } from 'viem';
import type { Hex } from 'viem';
import { attestOwnership, assertNoSecrets, LocalDevSigner, MemoryAuditLog } from '../src/index.js';
import type { AttestorContext, OnChainOffer } from '../src/index.js';

const CHAIN_ID = 31337;
const ESCROW = '0x1111111111111111111111111111111111111111' as Hex;
const ORACLE = '0x2222222222222222222222222222222222222222' as Hex;
const BUYER = '0x3333333333333333333333333333333333333333' as Hex;
const RECIPIENT = '0x4444444444444444444444444444444444444444' as Hex;
const EVM_PAYOUT = '0x5555555555555555555555555555555555555555' as Hex;
const ATTESTOR_KEY = `0x${'11'.repeat(32)}` as Hex;

const INSCRIPTION_TXID = '1f9f8a6d2c4b7e0135a9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7';
const OUTPOINT_TXID = '7c1d3f5a9b2e46081a3c5e7092b4d6f80e2a4c6e8103957bd5f7192b3d4f6a8c';
const OUTPOINT = `${OUTPOINT_TXID}:2`;
const P2TR_SCRIPT = `5120${'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2'}`;
const OFFER_ID = `0x${'ab'.repeat(32)}` as Hex;

const ROOT_KEY = rootKey(parseInscriptionId(`${INSCRIPTION_TXID}i0`));
const EXPIRY = 4_102_444_800n; // 2100-01-01, comfortably in the future

function makeOffer(over: Partial<OnChainOffer> = {}): OnChainOffer {
  return {
    buyer: BUYER,
    recipient: RECIPIENT,
    rootKey: ROOT_KEY,
    rootTxid: `0x${INSCRIPTION_TXID}` as Hex,
    rootIndex: 0,
    grossWei: 100_000_000_000_000_000n,
    sellerWei: 50_000_000_000_000_000n,
    treasuryWei: 25_000_000_000_000_000n,
    protocolWei: 25_000_000_000_000_000n,
    sellerSats: 0n,
    createdAt: 1n,
    expiry: EXPIRY,
    kind: 0,
    status: 1,
    termsHash: `0x${'00'.repeat(32)}` as Hex,
    ownershipDigest: `0x${'00'.repeat(32)}` as Hex,
    btcPayoutScriptHash: `0x${'00'.repeat(32)}` as Hex,
    reservedSolver: `0x${'00'.repeat(20)}` as Hex,
    reservationExpiry: 0n,
    ...over,
  };
}

function makeFields(over: Partial<AuthorizationMessageFields> = {}): AuthorizationMessageFields {
  const offer = makeOffer();
  return {
    purpose: 'PAID_EVM_MINT',
    bitcoinNetwork: 'regtest',
    rootTxid: INSCRIPTION_TXID,
    rootIndex: 0,
    currentOutpointTxid: OUTPOINT_TXID,
    currentOutpointVout: 2,
    rhChainId: CHAIN_ID,
    verifyingContract: ESCROW,
    contextId: OFFER_ID,
    offerTermsHash: offerTermsHash({
      chainId: CHAIN_ID,
      escrow: ESCROW,
      offerId: OFFER_ID,
      kind: 0,
      rootKey: ROOT_KEY,
      buyer: BUYER,
      recipient: RECIPIENT,
      grossWei: offer.grossWei,
      sellerWei: offer.sellerWei,
      sellerSats: 0n,
      expiry: EXPIRY,
    }),
    buyer: BUYER,
    recipient: RECIPIENT,
    payoutMode: 'EVM',
    evmPayout: EVM_PAYOUT,
    btcPayoutScriptHash: `0x${'00'.repeat(32)}`,
    sellerSats: 0n,
    grossWei: offer.grossWei,
    sellerWei: offer.sellerWei,
    authorizationId: `0x${'77'.repeat(32)}`,
    expiresAt: Number(EXPIRY),
    ...over,
  };
}

function makeContext(over: { offer?: OnChainOffer | null; rootMinted?: boolean; policyVersion?: number } = {}) {
  const audit = new MemoryAuditLog();
  const ctx: AttestorContext = {
    verifier: {
      bitcoin: {
        getBlockchainInfo: async () => ({ chain: 'regtest', blocks: 200, bestblockhash: '00'.repeat(32) }),
        getTxOut: async () => ({
          confirmations: 6,
          value: 0.0001,
          scriptPubKey: { hex: P2TR_SCRIPT, type: 'witness_v1_taproot' },
        }),
        findMempoolSpend: async () => null,
        getRawTransaction: async () => null,
        getRawMempool: async () => [],
        getMempoolEntry: async () => null,
        getConfirmations: async () => 6,
      } as never,
      ord: {
        assertFresh: async () => 200,
        outputOfInscription: async () => OUTPOINT,
        output: async () => ({ script_pubkey: P2TR_SCRIPT, value: 10_000, inscriptions: [`${INSCRIPTION_TXID}i0`] }),
        status: async () => ({ height: 200 }),
        inscription: async () => null,
      } as never,
      bip322: {
        name: 'stub',
        version: '0',
        supportedScriptTypes: ['p2tr', 'p2wpkh', 'p2sh-p2wpkh'],
        verify: () => true,
        scriptPubKeyForAddress: () => P2TR_SCRIPT,
        classifyScript: (s: string) => classifyScriptPubKey(s),
      },
      policy: { ownership: 1, payment: 1, rootSpend: 1, maxOrdLag: 2 },
      policyVersion: over.policyVersion ?? 1,
      network: 'regtest',
      isCollectionMember: () => true,
    },
    chain: {
      quorumContext: async () => ({ threshold: 3, epoch: 7n, policyVersion: 1 }),
      getOffer: async () => (over.offer === undefined ? makeOffer() : over.offer),
      isRootMinted: async () => over.rootMinted ?? false,
      isPaymentOutputConsumed: async () => false,
      rootState: async () => ({
        epoch: 0n,
        active: false,
        currentOutpointHash: `0x${'00'.repeat(32)}` as Hex,
        ownerScriptHash: `0x${'00'.repeat(32)}` as Hex,
        beneficiary: `0x${'00'.repeat(20)}` as Hex,
      }),
      blockNumber: async () => 1n,
    },
    signer: new LocalDevSigner(ATTESTOR_KEY, CHAIN_ID),
    audit,
    chainId: CHAIN_ID,
    oracleAddress: ORACLE,
    escrowAddress: ESCROW,
  };
  return { ctx, audit };
}

const request = (message: string) => ({
  canonicalMessage: message,
  signature: 'AAAAAAAA',
  variant: 'simple' as const,
  signingAddress: 'bcrt1pexample',
  claimedOutpoint: OUTPOINT,
  ttlSeconds: 900,
  correlationId: 'test-1',
});

async function expectRejection(promise: Promise<unknown>, code: string) {
  await expect(promise).rejects.toBeInstanceOf(VerificationRejection);
  await promise.catch((e: VerificationRejection) => expect(e.code).toBe(code));
}

describe('the signer never blind-signs', () => {
  it('exposes no exported function that turns a caller-supplied digest into a signature', async () => {
    // The structural guarantee. If someone later adds `signDigest(req.digest)` behind an HTTP
    // handler, this test is the tripwire — the module surface must stay free of any entry point
    // whose input is a digest.
    const module = await import('../src/index.js');
    const exported = Object.keys(module);
    expect(exported).not.toContain('signDigest');
    expect(exported).not.toContain('signArbitrary');
    for (const name of exported) {
      expect(name.toLowerCase()).not.toMatch(/^sign(digest|hash|raw)/);
    }
  });

  it('refuses an in-memory development key on a production chain', () => {
    // 4663 is Robinhood mainnet. There is deliberately no override flag.
    expect(() => new LocalDevSigner(ATTESTOR_KEY, 4663)).toThrow(/HSM or KMS/);
  });

  it('never serialises its key, even through JSON.stringify', () => {
    const signer = new LocalDevSigner(ATTESTOR_KEY, CHAIN_ID);
    const json = JSON.stringify(signer);
    expect(json).not.toContain('11111111');
    expect(JSON.parse(json)).toEqual({ kind: 'local-dev', address: signer.address });
  });
});

describe('ownership attestation', () => {
  it('signs a digest that recovers to the attestor address', async () => {
    const { ctx, audit } = makeContext();
    const result = await attestOwnership(ctx, request(buildMessage(makeFields())));

    // The digest must be the one the contract will compute, and the signature must recover to a
    // key the registry knows. Anything else never reaches quorum.
    expect(result.digest).toBe(ownershipDigest(CHAIN_ID, ORACLE, result.attestation));
    const recovered = await recoverAddress({ hash: result.digest, signature: result.signature });
    expect(recovered.toLowerCase()).toBe(ctx.signer.address.toLowerCase());

    expect(result.attestation.evmPayout).toBe(EVM_PAYOUT);
    expect(result.attestation.attestorEpoch).toBe(7n);
    expect(result.attestation.ownerScriptHash).toBe(scriptHash(`0x${P2TR_SCRIPT}` as Hex));
    expect(audit.entries).toHaveLength(1);
    expect(audit.entries[0]!.decision).toBe('signed');
  });

  it('clamps the attestation deadline to the holder’s own expiry', async () => {
    // A 900-second TTL must not extend an authorization past what the holder actually signed.
    const soon = Math.floor(Date.now() / 1000) + 60;
    const { ctx } = makeContext({ offer: makeOffer({ expiry: BigInt(soon) }) });
    const fields = makeFields({
      expiresAt: soon,
      offerTermsHash: offerTermsHash({
        chainId: CHAIN_ID,
        escrow: ESCROW,
        offerId: OFFER_ID,
        kind: 0,
        rootKey: ROOT_KEY,
        buyer: BUYER,
        recipient: RECIPIENT,
        grossWei: 100_000_000_000_000_000n,
        sellerWei: 50_000_000_000_000_000n,
        sellerSats: 0n,
        expiry: BigInt(soon),
      }),
    });
    const result = await attestOwnership(ctx, request(buildMessage(fields)));
    expect(result.attestation.deadline).toBeLessThanOrEqual(BigInt(soon));
  });

  it('rejects a message naming a different chain', async () => {
    const { ctx } = makeContext();
    await expectRejection(
      attestOwnership(ctx, request(buildMessage(makeFields({ rhChainId: 4663 })))),
      RejectionCode.OFFER_TERMS_MISMATCH,
    );
  });

  it('rejects a message naming a different escrow contract', async () => {
    const { ctx } = makeContext();
    await expectRejection(
      attestOwnership(ctx, request(buildMessage(makeFields({ verifyingContract: `0x${'9'.repeat(40)}` })))),
      RejectionCode.OFFER_TERMS_MISMATCH,
    );
  });

  it('rejects a non-canonical message rather than repairing it', async () => {
    const { ctx } = makeContext();
    await expectRejection(
      attestOwnership(ctx, request(buildMessage(makeFields()).replace(/\n/g, '\r\n'))),
      RejectionCode.MESSAGE_NOT_CANONICAL,
    );
  });

  it('rejects an unknown offer', async () => {
    const { ctx } = makeContext({ offer: null });
    await expectRejection(attestOwnership(ctx, request(buildMessage(makeFields()))), RejectionCode.OFFER_NOT_FOUND);
  });

  it('rejects an offer that is not open', async () => {
    const { ctx } = makeContext({ offer: makeOffer({ status: 4 }) });
    await expectRejection(attestOwnership(ctx, request(buildMessage(makeFields()))), RejectionCode.OFFER_WRONG_STATUS);
  });

  it('rejects an expired offer', async () => {
    const { ctx } = makeContext({ offer: makeOffer({ expiry: 1n }) });
    await expectRejection(attestOwnership(ctx, request(buildMessage(makeFields()))), RejectionCode.OFFER_EXPIRED);
  });

  it('rejects a Root that already minted', async () => {
    const { ctx } = makeContext({ rootMinted: true });
    await expectRejection(attestOwnership(ctx, request(buildMessage(makeFields()))), RejectionCode.ROOT_ALREADY_MINTED);
  });

  it('rejects a message whose buyer disagrees with the chain', async () => {
    // The requester's copy of the terms is never trusted; every field is re-read and compared.
    const { ctx } = makeContext();
    await expectRejection(
      attestOwnership(ctx, request(buildMessage(makeFields({ buyer: `0x${'8'.repeat(40)}` })))),
      RejectionCode.OFFER_TERMS_MISMATCH,
    );
  });

  it('rejects a message whose amounts disagree with the chain', async () => {
    const { ctx } = makeContext();
    await expectRejection(
      attestOwnership(ctx, request(buildMessage(makeFields({ sellerWei: 1n })))),
      RejectionCode.OFFER_TERMS_MISMATCH,
    );
  });

  it('rejects a tampered terms hash even when every visible field matches', async () => {
    // The individual field comparison is not sufficient — the hash is what the contract checks.
    const { ctx } = makeContext();
    await expectRejection(
      attestOwnership(ctx, request(buildMessage(makeFields({ offerTermsHash: `0x${'de'.repeat(32)}` })))),
      RejectionCode.OFFER_TERMS_MISMATCH,
    );
  });

  it('rejects a message claiming an outpoint the inscription is not at', async () => {
    const { ctx } = makeContext();
    const fields = makeFields({ currentOutpointTxid: 'e'.repeat(64), currentOutpointVout: 0 });
    await expectRejection(
      attestOwnership(ctx, {
        ...request(buildMessage(fields)),
        claimedOutpoint: `${'e'.repeat(64)}:0`,
      }),
      RejectionCode.INSCRIPTION_NOT_AT_CLAIMED_OUTPOINT,
    );
  });

  it('rejects when the attestor runs a different policy version than the chain', async () => {
    const { ctx } = makeContext({ policyVersion: 2 });
    await expectRejection(
      attestOwnership(ctx, request(buildMessage(makeFields()))),
      RejectionCode.STALE_POLICY_VERSION,
    );
  });

  it('rejects a forged payout mode before comparing it with the offer', async () => {
    // The canonical-message package and on-chain oracle now enforce the same purpose/mode shape.
    // Simulate a requester editing the already-built bytes: the attestor must classify them as
    // non-canonical and never reach the signer.
    const { ctx } = makeContext();
    const forged = buildMessage(makeFields())
      .replace('payout_mode=EVM', 'payout_mode=BTC')
      .replace(`evm_payout=${EVM_PAYOUT}`, 'evm_payout=0x0000000000000000000000000000000000000000')
      .replace(`btc_payout_script_hash=0x${'00'.repeat(32)}`, `btc_payout_script_hash=0x${'cc'.repeat(32)}`)
      .replace('seller_sats=0', 'seller_sats=50000');
    await expectRejection(attestOwnership(ctx, request(forged)), RejectionCode.MESSAGE_NOT_CANONICAL);
  });

  it('two attestors over identical facts produce the same digest', async () => {
    // This is what quorum means. Different keys, one digest.
    const a = makeContext();
    const b = makeContext();
    b.ctx.signer = new LocalDevSigner(`0x${'22'.repeat(32)}` as Hex, CHAIN_ID);
    const message = buildMessage(makeFields());
    const ra = await attestOwnership(a.ctx, request(message));
    const rb = await attestOwnership(b.ctx, request(message));

    expect(ra.digest).toBe(rb.digest);
    expect(ra.signature).not.toBe(rb.signature);
    expect(ra.attestor).not.toBe(rb.attestor);
  });
});

describe('audit log', () => {
  it('refuses to write anything key-shaped', () => {
    // The attestor never receives a key, so this firing means a bug — and it should fail loudly at
    // the moment it happens rather than leaving key material on disk.
    expect(() => assertNoSecrets('{"privateKey": "0xdead"}')).toThrow(/key material/);
    expect(() => assertNoSecrets('-----BEGIN EC PRIVATE KEY-----')).toThrow(/key material/);
    expect(() => assertNoSecrets(`{"seed":"${'x'.repeat(10)}"}`)).toThrow(/key material/);
    expect(() => assertNoSecrets('{"digest":"0xabc","decision":"signed"}')).not.toThrow();
  });

  it('records both node heights so a reorg audit is possible after the fact', async () => {
    const { ctx, audit } = makeContext();
    await attestOwnership(ctx, request(buildMessage(makeFields())));
    const entry = audit.entries[0]!;
    expect(entry.bitcoinHeight).toBe(200);
    expect(entry.ordIndexHeight).toBe(200);
    expect(entry.bitcoinTipHash).toBeTruthy();
    expect(entry.epoch).toBe(7);
    expect(entry.correlationId).toBe('test-1');
  });
});
