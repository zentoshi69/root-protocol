import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  assertAdapterValidated,
  Bip322JsAdapter,
  BitcoinCoreClient,
  btcToSats,
  classifyScriptPubKey,
  isInfrastructureFailure,
  KNOWN_SCRIPT_TYPES,
  OrdClient,
  RejectionCode,
  validateAdapter,
  VerificationRejection,
  verifyBitcoinPayment,
  verifyOwnershipAuthorization,
  verifyRootSpend,
  type Bip322Vector,
  type VerifierContext,
} from '../src/index.js';
import { REGTEST_POLICY } from '../src/verify.js';
import { rootKey, parseInscriptionId, scriptHash } from '@hoodpups/protocol-sdk';
import type { Hex } from 'viem';

/*//////////////////////////////////////////////////////////////
                       SCRIPT CLASSIFICATION
//////////////////////////////////////////////////////////////*/

describe('scriptPubKey classification', () => {
  const key32 = 'a'.repeat(64);
  const hash20 = 'b'.repeat(40);

  it('recognises the shapes it claims to', () => {
    expect(classifyScriptPubKey(`5120${key32}`)).toBe('p2tr');
    expect(classifyScriptPubKey(`0014${hash20}`)).toBe('p2wpkh');
    expect(classifyScriptPubKey(`0020${key32}`)).toBe('p2wsh');
    expect(classifyScriptPubKey(`76a914${hash20}88ac`)).toBe('p2pkh');
    expect(classifyScriptPubKey(`a914${hash20}87`)).toBe('p2sh-p2wpkh');
  });

  it('accepts a 0x prefix and is case insensitive on input', () => {
    expect(classifyScriptPubKey(`0x5120${key32}`)).toBe('p2tr');
    expect(classifyScriptPubKey(`5120${key32}`.toUpperCase())).toBe('p2tr');
  });

  it('returns null for anything it cannot classify, rather than guessing', () => {
    // A wrong guess here means verifying a signature against a script type nobody tested.
    expect(classifyScriptPubKey('')).toBeNull();
    expect(classifyScriptPubKey('51')).toBeNull();
    expect(classifyScriptPubKey(`5120${key32}00`)).toBeNull(); // right prefix, wrong length
    expect(classifyScriptPubKey(`5121${key32}`)).toBeNull(); // OP_2, not OP_1
    expect(classifyScriptPubKey(`6a${key32}`)).toBeNull(); // OP_RETURN
    expect(classifyScriptPubKey('zzzz')).toBeNull();
    expect(classifyScriptPubKey(`512${key32}`)).toBeNull(); // odd length
  });

  it('does not classify a bare multisig or a timelocked script', () => {
    expect(classifyScriptPubKey(`5221${'02'.repeat(33)}21${'03'.repeat(33)}52ae`)).toBeNull();
    expect(classifyScriptPubKey(`04${'11'.repeat(4)}b175${'76a914'}${hash20}88ac`)).toBeNull();
  });
});

/*//////////////////////////////////////////////////////////////
                        THE BIP-322 ADAPTER
//////////////////////////////////////////////////////////////*/

describe('bip322-js adapter', () => {
  const adapter = new Bip322JsAdapter();

  it('declares only the script types the library actually supports', () => {
    // bip322-js 3.0.0 does P2WPKH, P2SH-P2WPKH and single-key P2TR. It does NOT do P2WSH, and its
    // P2PKH path is legacy BIP-137. Claiming more than the library delivers is how an untested
    // code path ends up authorising a mint.
    expect([...adapter.supportedScriptTypes].sort()).toEqual(['p2sh-p2wpkh', 'p2tr', 'p2wpkh']);
    for (const t of adapter.supportedScriptTypes) expect(KNOWN_SCRIPT_TYPES).toContain(t);
    expect(adapter.supportedScriptTypes).not.toContain('p2wsh');
  });

  it('returns false rather than throwing on a malformed signature', () => {
    // An adapter that throws turns "invalid signature" into "service error", which an attacker
    // could use to force honest verifiers to abstain.
    expect(
      adapter.verify({
        address: 'bc1q9vza2e8x573nczrlzms0wvx3gsqjx7vavgkx0l',
        message: 'anything\n',
        signature: 'not-a-signature',
        variant: 'simple',
        expectedScriptPubKeyHex: '00142b05d564e6a7a33c087f16e0f730d1440123799d',
        network: 'mainnet',
      }),
    ).toBe(false);
  });

  it('derives a scriptPubKey from a valid mainnet address', () => {
    const script = adapter.scriptPubKeyForAddress('bc1q9vza2e8x573nczrlzms0wvx3gsqjx7vavgkx0l', 'mainnet');
    expect(script).toBe('00142b05d564e6a7a33c087f16e0f730d1440123799d');
    expect(classifyScriptPubKey(script)).toBe('p2wpkh');
  });

  it('refuses an address from the wrong network', () => {
    // A testnet deployment that accepted mainnet addresses could verify mainnet claims; the
    // reverse is worse. Fail loudly rather than deriving a script for the wrong chain.
    expect(() => adapter.scriptPubKeyForAddress('bc1q9vza2e8x573nczrlzms0wvx3gsqjx7vavgkx0l', 'regtest')).toThrow(
      /network/,
    );
  });

  it('refuses a malformed address', () => {
    expect(() => adapter.scriptPubKeyForAddress('definitely-not-an-address', 'mainnet')).toThrow(/valid Bitcoin address/);
  });
});

describe('adapter validation gate', () => {
  const adapter = new Bip322JsAdapter();

  const failingVector: Bip322Vector = {
    name: 'garbage-signature-must-not-verify',
    address: 'bc1q9vza2e8x573nczrlzms0wvx3gsqjx7vavgkx0l',
    message: 'hello\n',
    signature: 'AAAA',
    variant: 'simple',
    network: 'mainnet',
    expectedScriptPubKeyHex: '00142b05d564e6a7a33c087f16e0f730d1440123799d',
    shouldVerify: false,
    source: 'project',
  };

  it('passes when the adapter behaves as the vectors expect', () => {
    const result = validateAdapter(adapter, [failingVector]);
    expect(result.passed).toBe(1);
    expect(result.failed).toEqual([]);
    expect(() => assertAdapterValidated(adapter, [failingVector])).not.toThrow();
  });

  it('refuses to start with no vectors at all', () => {
    // An unvalidated adapter must never touch a real proof.
    expect(() => assertAdapterValidated(adapter, [])).toThrow(/no BIP-322 vectors/);
  });

  it('refuses to start when a vector fails', () => {
    const wrongExpectation = { ...failingVector, shouldVerify: true, name: 'deliberately-wrong' };
    expect(() => assertAdapterValidated(adapter, [wrongExpectation])).toThrow(/failed 1 of 1 vectors/);
  });
});

/*//////////////////////////////////////////////////////////////
                          SATOSHI ARITHMETIC
//////////////////////////////////////////////////////////////*/

describe('btcToSats never goes through a float', () => {
  it('converts exactly', () => {
    expect(btcToSats('0.00050000')).toBe(50_000n);
    expect(btcToSats('1')).toBe(100_000_000n);
    expect(btcToSats('0.00000001')).toBe(1n);
    expect(btcToSats('21000000')).toBe(2_100_000_000_000_000n);
    expect(btcToSats('-0.5')).toBe(-50_000_000n);
  });

  it('handles the classic float trap', () => {
    // 0.1 + 0.2 !== 0.3 is not an acceptable failure mode when the number decides whether a seller
    // was paid the exact amount they signed for.
    expect(btcToSats('0.1') + btcToSats('0.2')).toBe(btcToSats('0.3'));
  });

  it('rejects nonsense rather than coercing it', () => {
    expect(() => btcToSats('abc')).toThrow();
    expect(() => btcToSats('0.000000001')).toThrow(); // more precision than a satoshi
  });
});

describe('Bitcoin Core mempool-spend lookup', () => {
  afterEach(() => vi.restoreAllMocks());

  function client() {
    return new BitcoinCoreClient({ url: 'http://127.0.0.1:18443', username: 'u', password: 'p' });
  }

  it('uses one bounded gettxspendingprevout RPC and returns the spender', async () => {
    const txid = 'a'.repeat(64);
    const spendingtxid = 'b'.repeat(64);
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(
        JSON.stringify({ result: [{ txid, vout: 2, spendingtxid }], error: null }),
        { status: 200, headers: { 'content-type': 'application/json' } },
      ),
    );

    await expect(client().findMempoolSpend(txid, 2)).resolves.toBe(spendingtxid);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const request = JSON.parse(String(fetchMock.mock.calls[0]![1]?.body));
    expect(request).toMatchObject({ method: 'gettxspendingprevout', params: [[{ txid, vout: 2 }]] });
  });

  it('returns null when Core reports the outpoint has no mempool spender', async () => {
    const txid = 'c'.repeat(64);
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ result: [{ txid, vout: 0 }], error: null }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    );

    await expect(client().findMempoolSpend(txid, 0)).resolves.toBeNull();
  });

  it('fails closed if Core answers for a different outpoint', async () => {
    const txid = 'd'.repeat(64);
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ result: [{ txid: 'e'.repeat(64), vout: 1 }], error: null }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    );

    await expectRejection(client().findMempoolSpend(txid, 1), RejectionCode.NODE_UNAVAILABLE);
  });
});

describe('ord freshness boundary', () => {
  afterEach(() => vi.restoreAllMocks());

  function withHeight(height: unknown) {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ height }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    );
    return new OrdClient({ baseUrl: 'http://127.0.0.1:8080' });
  }

  it('accepts an index at or slightly behind the node tip', async () => {
    await expect(withHeight(199).assertFresh(200, 2)).resolves.toBe(199);
  });

  it('abstains if ord claims to be ahead of its own Bitcoin node', async () => {
    await expectRejection(withHeight(201).assertFresh(200, 2), RejectionCode.ORD_INDEX_INCONSISTENT);
  });

  it('abstains on a malformed index height instead of coercing it', async () => {
    await expectRejection(withHeight('200').assertFresh(200, 2), RejectionCode.ORD_INDEX_INCONSISTENT);
  });

  it('abstains on a negative index height', async () => {
    await expectRejection(withHeight(-1).assertFresh(200, 2), RejectionCode.ORD_INDEX_INCONSISTENT);
  });

  it('abstains when the Bitcoin node height is malformed', async () => {
    await expectRejection(withHeight(200).assertFresh(Number.NaN, 2), RejectionCode.ORD_INDEX_INCONSISTENT);
  });
});

/*//////////////////////////////////////////////////////////////
                      THE VERIFICATION PIPELINE
//////////////////////////////////////////////////////////////*/

const INSCRIPTION_TXID = '1f9f8a6d2c4b7e0135a9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7';
const INSCRIPTION_ID = `${INSCRIPTION_TXID}i0`;
const OUTPOINT_TXID = '7c1d3f5a9b2e46081a3c5e7092b4d6f80e2a4c6e8103957bd5f7192b3d4f6a8c';
const OUTPOINT = `${OUTPOINT_TXID}:2`;
const P2TR_SCRIPT = `5120${'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2'}`;

/** A context whose node and ord are stubs, so the pipeline's ordering can be tested precisely. */
function makeContext(over: Partial<Record<string, unknown>> = {}): VerifierContext {
  const state = {
    chainInfo: { chain: 'regtest', blocks: 200, bestblockhash: '00'.repeat(32) },
    ordHeight: 200,
    inscriptionOutput: OUTPOINT as string | null,
    outputInscriptions: [INSCRIPTION_ID],
    outputScript: P2TR_SCRIPT,
    txOut: { confirmations: 6, value: 0.0001, scriptPubKey: { hex: P2TR_SCRIPT, type: 'witness_v1_taproot' } } as
      | { confirmations: number; value: number; scriptPubKey: { hex: string; type: string } }
      | null,
    mempoolSpend: null as string | null,
    signatureValid: true,
    ...over,
  };

  return {
    bitcoin: {
      getBlockchainInfo: async () => state.chainInfo,
      getTxOut: async () => state.txOut,
      findMempoolSpend: async () => state.mempoolSpend,
      getRawTransaction: async () => null,
      getRawMempool: async () => [],
      getMempoolEntry: async () => null,
      getConfirmations: async () => 6,
    } as never,
    ord: {
      assertFresh: async () => state.ordHeight,
      outputOfInscription: async () => state.inscriptionOutput,
      output: async () =>
        state.outputInscriptions === null
          ? null
          : { script_pubkey: state.outputScript, value: 10_000, inscriptions: state.outputInscriptions },
      status: async () => ({ height: state.ordHeight }),
      inscription: async () => null,
    } as never,
    bip322: {
      name: 'stub',
      version: '0',
      supportedScriptTypes: ['p2tr', 'p2wpkh', 'p2sh-p2wpkh'],
      verify: () => state.signatureValid,
      scriptPubKeyForAddress: () => state.outputScript,
      classifyScript: (s: string) => classifyScriptPubKey(s),
    },
    policy: REGTEST_POLICY,
    policyVersion: 1,
    network: 'regtest',
    isCollectionMember: () => true,
  };
}

const ownershipInput = {
  inscriptionId: INSCRIPTION_ID,
  claimedOutpoint: OUTPOINT,
  canonicalMessage: 'HOODPUPS AUTHORIZATION V1\npurpose=PAID_EVM_MINT\n',
  signingAddress: 'bcrt1pexample',
  signature: 'AAAA',
  variant: 'simple' as const,
};

async function expectRejection(promise: Promise<unknown>, code: string) {
  await expect(promise).rejects.toBeInstanceOf(VerificationRejection);
  await promise.catch((e: VerificationRejection) => expect(e.code).toBe(code));
}

describe('ownership verification', () => {
  it('produces a complete fact set on the happy path', async () => {
    const fact = await verifyOwnershipAuthorization(makeContext(), ownershipInput);
    expect(fact.kind).toBe('ownership');
    expect(fact.rootKey).toBe(rootKey(parseInscriptionId(INSCRIPTION_ID)));
    expect(fact.currentOutpoint).toBe(OUTPOINT);
    expect(fact.ownerScriptHash).toBe(scriptHash(`0x${P2TR_SCRIPT}` as Hex));
    expect(fact.scriptType).toBe('p2tr');
    expect(fact.bip322ProofHash).toMatch(/^0x[0-9a-f]{64}$/);
    expect(fact.policyVersion).toBe(1);
  });

  it('rejects an inscription outside the manifest', async () => {
    const ctx = { ...makeContext(), isCollectionMember: () => false };
    await expectRejection(verifyOwnershipAuthorization(ctx, ownershipInput), RejectionCode.ROOT_NOT_IN_MANIFEST);
  });

  it('abstains when Bitcoin Core serves a different network than configured', async () => {
    const ctx = { ...makeContext(), network: 'mainnet' as const };
    await expectRejection(
      verifyOwnershipAuthorization(ctx, ownershipInput),
      RejectionCode.BITCOIN_NETWORK_MISMATCH,
    );
  });

  it('rejects when the inscription has moved since the claim was made', async () => {
    const ctx = makeContext({ inscriptionOutput: `${'9'.repeat(64)}:0` });
    await expectRejection(
      verifyOwnershipAuthorization(ctx, ownershipInput),
      RejectionCode.INSCRIPTION_NOT_AT_CLAIMED_OUTPOINT,
    );
  });

  it('rejects when ord does not know the inscription', async () => {
    const ctx = makeContext({ inscriptionOutput: null });
    await expectRejection(verifyOwnershipAuthorization(ctx, ownershipInput), RejectionCode.INSCRIPTION_NOT_FOUND);
  });

  it('rejects when the output does not actually contain the inscription', async () => {
    // Asking ord from both directions catches an internally inconsistent index that a single
    // lookup would happily accept.
    const ctx = makeContext({ outputInscriptions: [`${'c'.repeat(64)}i0`] });
    await expectRejection(
      verifyOwnershipAuthorization(ctx, ownershipInput),
      RejectionCode.INSCRIPTION_NOT_AT_CLAIMED_OUTPOINT,
    );
  });

  it('rejects a spent outpoint', async () => {
    const ctx = makeContext({ txOut: null });
    await expectRejection(verifyOwnershipAuthorization(ctx, ownershipInput), RejectionCode.OUTPOINT_SPENT);
  });

  it('rejects an outpoint being spent in the mempool', async () => {
    // "Unspent" and "not being spent" are different questions; only the second is safe to attest.
    const ctx = makeContext({ mempoolSpend: 'd'.repeat(64) });
    await expectRejection(verifyOwnershipAuthorization(ctx, ownershipInput), RejectionCode.MEMPOOL_SPEND_DETECTED);
  });

  it('rejects an under-confirmed output', async () => {
    const ctx = makeContext({
      txOut: { confirmations: 0, value: 0.0001, scriptPubKey: { hex: P2TR_SCRIPT, type: 'witness_v1_taproot' } },
    });
    await expectRejection(verifyOwnershipAuthorization(ctx, ownershipInput), RejectionCode.INSUFFICIENT_CONFIRMATIONS);
  });

  it('rejects when ord and the node disagree about the script', async () => {
    const ctx = makeContext({ outputScript: `0014${'f'.repeat(40)}` });
    await expectRejection(verifyOwnershipAuthorization(ctx, ownershipInput), RejectionCode.SCRIPT_BINDING_MISMATCH);
  });

  it('rejects an invalid signature', async () => {
    const ctx = makeContext({ signatureValid: false });
    await expectRejection(verifyOwnershipAuthorization(ctx, ownershipInput), RejectionCode.BIP322_INVALID);
  });

  it('rejects a script type the adapter has no vectors for', async () => {
    const p2wsh = `0020${'e'.repeat(64)}`;
    const ctx = makeContext({
      outputScript: p2wsh,
      txOut: { confirmations: 6, value: 0.0001, scriptPubKey: { hex: p2wsh, type: 'witness_v0_scripthash' } },
    });
    await expectRejection(verifyOwnershipAuthorization(ctx, ownershipInput), RejectionCode.SCRIPT_TYPE_UNSUPPORTED);
  });

  it('rejects an unsupported BIP-322 variant', async () => {
    await expectRejection(
      verifyOwnershipAuthorization(makeContext(), { ...ownershipInput, variant: 'proof_of_funds' }),
      RejectionCode.BIP322_VARIANT_UNSUPPORTED,
    );
  });

  it('rejects a message missing its trailing newline', async () => {
    await expectRejection(
      verifyOwnershipAuthorization(makeContext(), { ...ownershipInput, canonicalMessage: 'no trailing lf' }),
      RejectionCode.MESSAGE_NOT_CANONICAL,
    );
  });
});

describe('payment verification demands exactness', () => {
  const PAYMENT_SCRIPT = `5120${'1'.repeat(64)}`;
  const expectedScriptHash = scriptHash(`0x${PAYMENT_SCRIPT}` as Hex);

  function paymentContext(vout: Array<{ n: number; value: number; hex: string }>, confirmations = 3): VerifierContext {
    const ctx = makeContext();
    return {
      ...ctx,
      bitcoin: {
        ...ctx.bitcoin,
        getBlockchainInfo: async () => ({ chain: 'regtest', blocks: 200, bestblockhash: '00'.repeat(32) }),
        getRawTransaction: async () => ({
          txid: OUTPOINT_TXID,
          hash: OUTPOINT_TXID,
          confirmations,
          blockhash: '11'.repeat(32),
          vin: [],
          vout: vout.map((o) => ({ n: o.n, value: o.value, scriptPubKey: { hex: o.hex, type: 'witness_v1_taproot' } })),
        }),
      } as never,
    };
  }

  const input = { bitcoinTxid: OUTPOINT_TXID, outputIndex: 1, expectedScriptHash, expectedAmountSats: 50_000n };

  it('accepts an exact payment', async () => {
    const fact = await verifyBitcoinPayment(
      paymentContext([
        { n: 0, value: 0.001, hex: `5120${'9'.repeat(64)}` },
        { n: 1, value: 0.0005, hex: PAYMENT_SCRIPT },
      ]),
      input,
    );
    expect(fact.amountSats).toBe(50_000n);
    expect(fact.recipientScriptHash).toBe(expectedScriptHash);
    expect(fact.paymentOutputKey).toMatch(/^0x[0-9a-f]{64}$/);
  });

  it('rejects a payment one satoshi short', async () => {
    await expectRejection(
      verifyBitcoinPayment(paymentContext([{ n: 1, value: 0.00049999, hex: PAYMENT_SCRIPT }]), input),
      RejectionCode.PAYMENT_AMOUNT_MISMATCH,
    );
  });

  it('rejects a payment one satoshi over — exact means exact', async () => {
    // A tolerated range would let a solver probe for the smallest amount that passes.
    await expectRejection(
      verifyBitcoinPayment(paymentContext([{ n: 1, value: 0.00050001, hex: PAYMENT_SCRIPT }]), input),
      RejectionCode.PAYMENT_AMOUNT_MISMATCH,
    );
  });

  it('rejects the right amount to the wrong script', async () => {
    await expectRejection(
      verifyBitcoinPayment(paymentContext([{ n: 1, value: 0.0005, hex: `5120${'7'.repeat(64)}` }]), input),
      RejectionCode.PAYMENT_SCRIPT_MISMATCH,
    );
  });

  it('resolves the correct output among several with identical values', async () => {
    // Multiple similar outputs is a real attack shape: pay the right amount to your own script and
    // hope the verifier matches on value rather than index.
    const fact = await verifyBitcoinPayment(
      paymentContext([
        { n: 0, value: 0.0005, hex: `5120${'7'.repeat(64)}` },
        { n: 1, value: 0.0005, hex: PAYMENT_SCRIPT },
        { n: 2, value: 0.0005, hex: `5120${'8'.repeat(64)}` },
      ]),
      input,
    );
    expect(fact.outputIndex).toBe(1);
    expect(fact.recipientScriptHash).toBe(expectedScriptHash);
  });

  it('rejects the right payment at the wrong output index', async () => {
    await expectRejection(
      verifyBitcoinPayment(paymentContext([{ n: 0, value: 0.0005, hex: PAYMENT_SCRIPT }]), input),
      RejectionCode.PAYMENT_OUTPUT_NOT_FOUND,
    );
  });

  it('rejects an under-confirmed payment', async () => {
    // Burial depth, never mempool presence — otherwise a solver could broadcast, be attested, then
    // RBF-replace with a transaction paying itself.
    await expectRejection(
      verifyBitcoinPayment(paymentContext([{ n: 1, value: 0.0005, hex: PAYMENT_SCRIPT }], 0), input),
      RejectionCode.INSUFFICIENT_CONFIRMATIONS,
    );
  });
});

describe('root spend verification', () => {
  function spendContext(vin: Array<{ txid: string; vout: number }>, unspent: boolean, confirmations = 3) {
    const ctx = makeContext();
    return {
      ...ctx,
      bitcoin: {
        ...ctx.bitcoin,
        getBlockchainInfo: async () => ({ chain: 'regtest', blocks: 200, bestblockhash: '00'.repeat(32) }),
        getRawTransaction: async () => ({
          txid: 'f'.repeat(64),
          hash: 'f'.repeat(64),
          confirmations,
          blockhash: '22'.repeat(32),
          vin,
          vout: [],
        }),
        getTxOut: async () =>
          unspent ? { confirmations: 6, value: 0.0001, scriptPubKey: { hex: P2TR_SCRIPT, type: 't' } } : null,
      } as never,
    } as VerifierContext;
  }

  const input = { inscriptionId: INSCRIPTION_ID, previousOutpoint: OUTPOINT, spendingTxid: 'f'.repeat(64) };

  it('accepts a confirmed spend of the recorded outpoint', async () => {
    const fact = await verifyRootSpend(spendContext([{ txid: OUTPOINT_TXID, vout: 2 }], false), input);
    expect(fact.kind).toBe('rootSpend');
    expect(fact.previousOutpoint).toBe(OUTPOINT);
  });

  it('rejects a transaction that does not spend the recorded outpoint', async () => {
    // Without this, any confirmed transaction could be presented to deactivate any root.
    await expectRejection(
      verifyRootSpend(spendContext([{ txid: 'a'.repeat(64), vout: 0 }], false), input),
      RejectionCode.PREVIOUS_OUTPOINT_MISMATCH,
    );
  });

  it('rejects when the outpoint is still unspent in this node’s UTXO set', async () => {
    await expectRejection(
      verifyRootSpend(spendContext([{ txid: OUTPOINT_TXID, vout: 2 }], true), input),
      RejectionCode.PREVIOUS_OUTPOINT_MISMATCH,
    );
  });

  it('rejects an under-confirmed spend', async () => {
    // A reorged spend would wrongly strip a live owner's epoch.
    await expectRejection(
      verifyRootSpend(spendContext([{ txid: OUTPOINT_TXID, vout: 2 }], false, 0), input),
      RejectionCode.INSUFFICIENT_CONFIRMATIONS,
    );
  });
});

describe('rejection taxonomy', () => {
  it('separates "I could not check" from "this claim is false"', () => {
    // An operator that cannot verify must abstain, never defer to the others. A quorum of four
    // honest operators plus one that guesses is worse than four.
    expect(isInfrastructureFailure(RejectionCode.NODE_UNAVAILABLE)).toBe(true);
    expect(isInfrastructureFailure(RejectionCode.BITCOIN_NETWORK_MISMATCH)).toBe(true);
    expect(isInfrastructureFailure(RejectionCode.ORD_INDEX_LAGGING)).toBe(true);
    expect(isInfrastructureFailure(RejectionCode.ORD_INDEX_INCONSISTENT)).toBe(true);
    expect(isInfrastructureFailure(RejectionCode.BIP322_INVALID)).toBe(false);
    expect(isInfrastructureFailure(RejectionCode.PAYMENT_AMOUNT_MISMATCH)).toBe(false);
  });

  it('serialises with a stable shape for the audit log', () => {
    const rejection = new VerificationRejection(RejectionCode.OUTPOINT_SPENT, 'gone', { outpoint: OUTPOINT });
    expect(rejection.toJSON()).toEqual({
      code: 'OUTPOINT_SPENT',
      message: 'gone',
      detail: { outpoint: OUTPOINT },
    });
  });
});
