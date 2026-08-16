/**
 * The verification pipeline.
 *
 * Implements the steps `docs/ATTESTOR_POLICY.md` makes binding. Every one runs against the
 * operator's own node and index; none may be skipped, delegated, or copied from another operator's
 * answer.
 *
 * The output is a typed fact set or a structured rejection — never a bare boolean. Five operators
 * that disagree need to be able to say *why*, and a boolean makes that impossible.
 */

import {
  collectionLeaf,
  computeBip322ProofHash,
  formatOutpoint,
  outpointHash,
  parseInscriptionId,
  parseOutpoint,
  paymentOutputKey,
  rootKey,
  scriptHash,
  txidToBytes32,
  type Hex,
} from './facts.js';
import { verifyOwnershipSignature, type Bip322Adapter, type Bip322Variant } from './bip322.js';
import { BitcoinCoreClient, btcToSats } from './bitcoinCore.js';
import { OrdClient } from './ord.js';
import { reject, RejectionCode } from './errors.js';

export interface ConfirmationPolicy {
  /** Confirmations required for the output holding an inscription. */
  ownership: number;
  /** Confirmations required for a BTC payment to a seller. Real money — depth beats speed. */
  payment: number;
  /** Confirmations required for a spend that closes an ownership epoch. */
  rootSpend: number;
  /** Maximum blocks `ord` may lag the node before the verifier abstains. */
  maxOrdLag: number;
}

export const MAINNET_POLICY: ConfirmationPolicy = { ownership: 1, payment: 3, rootSpend: 3, maxOrdLag: 2 };
export const REGTEST_POLICY: ConfirmationPolicy = { ownership: 1, payment: 1, rootSpend: 1, maxOrdLag: 2 };

export interface VerifierContext {
  bitcoin: BitcoinCoreClient;
  ord: OrdClient;
  bip322: Bip322Adapter;
  policy: ConfirmationPolicy;
  policyVersion: number;
  network: 'mainnet' | 'testnet' | 'signet' | 'regtest';
  /** Membership oracle, backed by the operator's own copy of the manifest. */
  isCollectionMember(rootKey: Hex): boolean;
}

/** Everything an attestor needs, and nothing it should infer. */
export interface VerifiedOwnershipFact {
  kind: 'ownership';
  inscriptionId: string;
  rootTxid: Hex;
  rootIndex: number;
  rootKey: Hex;
  collectionLeaf: Hex;
  currentOutpoint: string;
  currentOutpointHash: Hex;
  ownerScriptPubKeyHex: string;
  ownerScriptHash: Hex;
  scriptType: string;
  bip322Variant: Bip322Variant;
  bip322ProofHash: Hex;
  confirmations: number;
  bitcoinHeight: number;
  bitcoinBlockHash: string;
  ordIndexHeight: number;
  policyVersion: number;
  observedAt: string;
}

export interface VerifiedPaymentFact {
  kind: 'payment';
  bitcoinTxid: Hex;
  outputIndex: number;
  paymentOutputKey: Hex;
  recipientScriptPubKeyHex: string;
  recipientScriptHash: Hex;
  amountSats: bigint;
  confirmations: number;
  bitcoinHeight: number;
  bitcoinBlockHash: string;
  policyVersion: number;
  observedAt: string;
}

export interface VerifiedRootSpendFact {
  kind: 'rootSpend';
  rootTxid: Hex;
  rootIndex: number;
  rootKey: Hex;
  previousOutpoint: string;
  previousOutpointHash: Hex;
  spendingTxid: Hex;
  confirmations: number;
  bitcoinHeight: number;
  bitcoinBlockHash: string;
  policyVersion: number;
  observedAt: string;
}

/*//////////////////////////////////////////////////////////////
                             OWNERSHIP
//////////////////////////////////////////////////////////////*/

export interface OwnershipVerificationInput {
  /** Ordinals inscription id, `<txid>i<index>`. */
  inscriptionId: string;
  /** The outpoint the claimant says currently holds it, `<txid>:<vout>`. */
  claimedOutpoint: string;
  /** The exact canonical message that was signed, trailing LF included. */
  canonicalMessage: string;
  /** Address the wallet signed with. */
  signingAddress: string;
  signature: string;
  variant: Bip322Variant;
}

/**
 * Verify that a Bitcoin controller authorized an action.
 *
 * Ordering is deliberate: cheap structural checks first, then chain state, then cryptography. A
 * malformed request should never reach the signature path, and a claim about an inscription that
 * has already moved should never cost a signature verification.
 */
export async function verifyOwnershipAuthorization(
  ctx: VerifierContext,
  input: OwnershipVerificationInput,
): Promise<VerifiedOwnershipFact> {
  // 1. Parse with one canonical byte-order implementation. Display order everywhere.
  const root = parseInscriptionId(input.inscriptionId);
  const claimed = parseOutpoint(input.claimedOutpoint);
  const key = rootKey(root);

  // 2. Collection membership, against the operator's own manifest copy.
  if (!ctx.isCollectionMember(key)) {
    reject(RejectionCode.ROOT_NOT_IN_MANIFEST, 'this inscription is not in the protocol manifest', {
      inscriptionId: input.inscriptionId,
      rootKey: key,
    });
  }

  // 3. Chain tip, and ord freshness. A lagging index abstains rather than answering from stale data.
  const chainInfo = await ctx.bitcoin.getBlockchainInfo();
  const ordIndexHeight = await ctx.ord.assertFresh(chainInfo.blocks, ctx.policy.maxOrdLag);

  // 4. Where does ord say the inscription actually is?
  const actualOutpoint = await ctx.ord.outputOfInscription(input.inscriptionId);
  if (!actualOutpoint) {
    reject(RejectionCode.INSCRIPTION_NOT_FOUND, 'ord does not know this inscription', {
      inscriptionId: input.inscriptionId,
    });
  }
  const expectedOutpoint = formatOutpoint(claimed.bitcoinTxid, claimed.vout);
  if (actualOutpoint.toLowerCase() !== expectedOutpoint.toLowerCase()) {
    reject(
      RejectionCode.INSCRIPTION_NOT_AT_CLAIMED_OUTPOINT,
      'the inscription is not in the output the claim names; it has moved',
      { claimed: expectedOutpoint, actual: actualOutpoint },
    );
  }

  // 5. And does that output really contain this inscription? Asking from both directions catches
  //    an index that is internally inconsistent, which a single lookup would not.
  const ordOutput = await ctx.ord.output(expectedOutpoint);
  if (!ordOutput) {
    reject(RejectionCode.OUTPUT_NOT_FOUND, 'ord has no record of this output', { outpoint: expectedOutpoint });
  }
  if (!ordOutput.inscriptions?.some((id) => id.toLowerCase() === input.inscriptionId.toLowerCase())) {
    reject(
      RejectionCode.INSCRIPTION_NOT_AT_CLAIMED_OUTPOINT,
      'ord reports this output does not contain the claimed inscription',
      { outpoint: expectedOutpoint, contains: ordOutput.inscriptions },
    );
  }

  // 6. Independently confirm with Bitcoin Core that the output is UNSPENT. `includeMempool` makes
  //    an in-flight spend return null, which is exactly the "someone is moving this right now" case.
  const txOut = await ctx.bitcoin.getTxOut(claimed.bitcoinTxid.slice(2), claimed.vout, true);
  if (!txOut) {
    reject(
      RejectionCode.OUTPOINT_SPENT,
      'Bitcoin Core reports this output is spent or being spent; it cannot authorize anything',
      { outpoint: expectedOutpoint },
    );
  }

  // 7. Confirmation policy.
  if (txOut.confirmations < ctx.policy.ownership) {
    reject(RejectionCode.INSUFFICIENT_CONFIRMATIONS, 'the output holding this inscription is not buried deeply enough', {
      confirmations: txOut.confirmations,
      required: ctx.policy.ownership,
    });
  }

  // 8. Explicit mempool conflict scan. `gettxout` already covers the common case; the attestor
  //    policy requires this as defence in depth, because "unspent" and "not being spent" are
  //    different questions and only the second one is safe to attest.
  const mempoolSpend = await ctx.bitcoin.findMempoolSpend(claimed.bitcoinTxid.slice(2), claimed.vout);
  if (mempoolSpend) {
    reject(RejectionCode.MEMPOOL_SPEND_DETECTED, 'an unconfirmed transaction is already spending this output', {
      outpoint: expectedOutpoint,
      spendingTxid: mempoolSpend,
    });
  }

  // 9. Take the raw script bytes. Never the decoded address string — encodings are network- and
  //    format-dependent, the bytes are what actually control the coins.
  const scriptPubKeyHex = (ordOutput.script_pubkey ?? txOut.scriptPubKey.hex).replace(/^0x/, '').toLowerCase();
  const nodeScriptHex = txOut.scriptPubKey.hex.toLowerCase();
  if (scriptPubKeyHex !== nodeScriptHex) {
    // ord and the node disagreeing about an output's script means one of them is wrong. Abstain.
    reject(RejectionCode.SCRIPT_BINDING_MISMATCH, 'ord and Bitcoin Core disagree about this output’s scriptPubKey', {
      ord: scriptPubKeyHex,
      node: nodeScriptHex,
    });
  }

  // 10. Verify BIP-322 against the exact canonical message and that exact script, with the
  //     independent address→script binding check inside.
  verifyOwnershipSignature(ctx.bip322, {
    address: input.signingAddress,
    message: input.canonicalMessage,
    signature: input.signature,
    variant: input.variant,
    expectedScriptPubKeyHex: scriptPubKeyHex,
    network: ctx.network,
  });

  // 11. Recompute every hash the attestation will carry. Nothing is taken from the requester.
  const scriptType = ctx.bip322.classifyScript(scriptPubKeyHex);
  return {
    kind: 'ownership',
    inscriptionId: input.inscriptionId,
    rootTxid: root.inscriptionTxid,
    rootIndex: root.inscriptionIndex,
    rootKey: key,
    collectionLeaf: collectionLeaf(key),
    currentOutpoint: expectedOutpoint,
    currentOutpointHash: outpointHash(claimed.bitcoinTxid, claimed.vout),
    ownerScriptPubKeyHex: scriptPubKeyHex,
    ownerScriptHash: scriptHash(`0x${scriptPubKeyHex}` as Hex),
    scriptType: scriptType ?? 'unknown',
    bip322Variant: input.variant,
    // Declared base64: BIP-322 wallets return signatures base64-encoded. Declaring it means the
    // proof hash never depends on encoding-sniffing heuristics.
    bip322ProofHash: computeBip322ProofHash(input.variant, input.signature, input.canonicalMessage, 'base64'),
    confirmations: txOut.confirmations,
    bitcoinHeight: chainInfo.blocks,
    bitcoinBlockHash: chainInfo.bestblockhash,
    ordIndexHeight,
    policyVersion: ctx.policyVersion,
    observedAt: new Date().toISOString(),
  };
}

/*//////////////////////////////////////////////////////////////
                              PAYMENT
//////////////////////////////////////////////////////////////*/

export interface PaymentVerificationInput {
  bitcoinTxid: string;
  outputIndex: number;
  /** The exact script the seller signed for. */
  expectedScriptHash: Hex;
  /** The exact sat amount the offer fixed. Not a minimum. */
  expectedAmountSats: bigint;
}

/**
 * Verify that a specific Bitcoin output paid a seller exactly what the offer promised.
 *
 * "Exactly" is load-bearing throughout. A payment of `expectedAmountSats + 1` is a rejection, not a
 * generous solver — accepting a range would let a solver probe for the smallest amount the verifier
 * tolerates.
 */
export async function verifyBitcoinPayment(
  ctx: VerifierContext,
  input: PaymentVerificationInput,
): Promise<VerifiedPaymentFact> {
  const txid = input.bitcoinTxid.replace(/^0x/, '').toLowerCase();
  const chainInfo = await ctx.bitcoin.getBlockchainInfo();

  const tx = await ctx.bitcoin.getRawTransaction(txid);
  if (!tx) {
    reject(RejectionCode.PAYMENT_TX_NOT_FOUND, 'this node has no record of the payment transaction', { txid });
  }

  const confirmations = tx.confirmations ?? 0;
  // Burial depth, never mempool presence. A solver that could be attested on an unconfirmed
  // transaction could broadcast, get attested, then RBF-replace it with one paying itself.
  if (confirmations < ctx.policy.payment) {
    reject(RejectionCode.INSUFFICIENT_CONFIRMATIONS, 'the payment is not buried deeply enough to attest', {
      txid,
      confirmations,
      required: ctx.policy.payment,
    });
  }

  const output = tx.vout.find((o) => o.n === input.outputIndex);
  if (!output) {
    reject(RejectionCode.PAYMENT_OUTPUT_NOT_FOUND, 'the transaction has no output at that index', {
      txid,
      outputIndex: input.outputIndex,
      outputCount: tx.vout.length,
    });
  }

  const outputScriptHex = output.scriptPubKey.hex.replace(/^0x/, '').toLowerCase();
  const observedScriptHash = scriptHash(`0x${outputScriptHex}` as Hex);
  if (observedScriptHash.toLowerCase() !== input.expectedScriptHash.toLowerCase()) {
    reject(RejectionCode.PAYMENT_SCRIPT_MISMATCH, 'this output does not pay the script the seller signed for', {
      txid,
      outputIndex: input.outputIndex,
      expected: input.expectedScriptHash,
      observed: observedScriptHash,
    });
  }

  // Parsed textually from the decimal string, never through a float. `0.1 + 0.2 !== 0.3` is not an
  // acceptable failure mode when the number decides whether a seller was paid.
  const observedSats = btcToSats(output.value);
  if (observedSats !== input.expectedAmountSats) {
    reject(RejectionCode.PAYMENT_AMOUNT_MISMATCH, 'the output value is not exactly the amount the offer fixed', {
      txid,
      outputIndex: input.outputIndex,
      expected: input.expectedAmountSats.toString(),
      observed: observedSats.toString(),
    });
  }

  return {
    kind: 'payment',
    bitcoinTxid: txidToBytes32(txid),
    outputIndex: input.outputIndex,
    paymentOutputKey: paymentOutputKey(txidToBytes32(txid), input.outputIndex),
    recipientScriptPubKeyHex: outputScriptHex,
    recipientScriptHash: observedScriptHash,
    amountSats: observedSats,
    confirmations,
    bitcoinHeight: chainInfo.blocks,
    bitcoinBlockHash: tx.blockhash ?? chainInfo.bestblockhash,
    policyVersion: ctx.policyVersion,
    observedAt: new Date().toISOString(),
  };
}

/*//////////////////////////////////////////////////////////////
                            ROOT SPEND
//////////////////////////////////////////////////////////////*/

export interface RootSpendVerificationInput {
  inscriptionId: string;
  /** The outpoint the registry currently records as live. */
  previousOutpoint: string;
  /** The transaction claimed to have spent it. */
  spendingTxid: string;
}

/**
 * Verify that a recorded inscription outpoint was genuinely spent.
 *
 * Getting this wrong in the false-positive direction wrongly strips a live owner's epoch, so the
 * spend must be confirmed to the policy depth and must actually reference the recorded outpoint —
 * "the output is gone" is not sufficient evidence on its own.
 */
export async function verifyRootSpend(
  ctx: VerifierContext,
  input: RootSpendVerificationInput,
): Promise<VerifiedRootSpendFact> {
  const root = parseInscriptionId(input.inscriptionId);
  const previous = parseOutpoint(input.previousOutpoint);
  const key = rootKey(root);

  if (!ctx.isCollectionMember(key)) {
    reject(RejectionCode.ROOT_NOT_IN_MANIFEST, 'this inscription is not in the protocol manifest', { rootKey: key });
  }

  const chainInfo = await ctx.bitcoin.getBlockchainInfo();
  const spendTxid = input.spendingTxid.replace(/^0x/, '').toLowerCase();
  const spendTx = await ctx.bitcoin.getRawTransaction(spendTxid);
  if (!spendTx) {
    reject(RejectionCode.SPEND_NOT_FOUND, 'this node has no record of the spending transaction', { spendTxid });
  }

  const confirmations = spendTx.confirmations ?? 0;
  if (confirmations < ctx.policy.rootSpend) {
    reject(RejectionCode.INSUFFICIENT_CONFIRMATIONS, 'the spend is not buried deeply enough to close an epoch', {
      confirmations,
      required: ctx.policy.rootSpend,
    });
  }

  // The spending transaction must actually consume the recorded outpoint. Without this, any
  // confirmed transaction could be presented to deactivate any root.
  const spendsIt = spendTx.vin.some(
    (vin) => vin.txid?.toLowerCase() === previous.bitcoinTxid.slice(2).toLowerCase() && vin.vout === previous.vout,
  );
  if (!spendsIt) {
    reject(
      RejectionCode.PREVIOUS_OUTPOINT_MISMATCH,
      'the named transaction does not spend the outpoint the registry records',
      { spendTxid, previousOutpoint: input.previousOutpoint },
    );
  }

  // And the outpoint must genuinely be gone from the UTXO set.
  const stillUnspent = await ctx.bitcoin.getTxOut(previous.bitcoinTxid.slice(2), previous.vout, false);
  if (stillUnspent) {
    reject(RejectionCode.PREVIOUS_OUTPOINT_MISMATCH, 'the outpoint is still unspent in this node’s UTXO set', {
      previousOutpoint: input.previousOutpoint,
    });
  }

  return {
    kind: 'rootSpend',
    rootTxid: root.inscriptionTxid,
    rootIndex: root.inscriptionIndex,
    rootKey: key,
    previousOutpoint: input.previousOutpoint,
    previousOutpointHash: outpointHash(previous.bitcoinTxid, previous.vout),
    spendingTxid: txidToBytes32(spendTxid),
    confirmations,
    bitcoinHeight: chainInfo.blocks,
    bitcoinBlockHash: spendTx.blockhash ?? chainInfo.bestblockhash,
    policyVersion: ctx.policyVersion,
    observedAt: new Date().toISOString(),
  };
}
