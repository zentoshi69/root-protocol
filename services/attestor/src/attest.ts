/**
 * The attestation pipeline.
 *
 * Each of the five instances runs this independently, against its own node, its own `ord`, its own
 * copy of the manifest and its own key. Nothing here consults another attestor's result.
 *
 * ## Structural guarantee: no blind signing
 *
 * The exported functions accept a *request to attest facts* — an inscription id, a claimed
 * outpoint, a signature. They never accept a digest. There is deliberately no exported function
 * with the shape `(digest: Hex) => Promise<Hex>`; the digest is computed at the end of verification
 * from values this process derived, and the signer is called exactly once, there.
 */

import {
  bitcoinPaymentDigest,
  offerTermsHash,
  ownershipDigest,
  rootSpendDigest,
  type BitcoinPaymentAttestation,
  type OwnershipAttestation,
  type RootSpendAttestation,
} from '@hoodpups/protocol-sdk';
import {
  parseMessage,
  type AuthorizationMessageFields,
  type AuthorizationPurposeName,
  type PayoutModeName,
} from '@hoodpups/canonical-message';
import {
  reject,
  RejectionCode,
  verifyBitcoinPayment,
  verifyOwnershipAuthorization,
  verifyRootSpend,
  type VerifierContext,
} from '@hoodpups/bitcoin-verifier';
import type { Hex } from 'viem';
import type { AttestorSigner } from './signer.js';
import type { ChainReader, OnChainOffer } from './chain.js';
import type { AuditLog } from './audit.js';

export interface AttestorContext {
  verifier: VerifierContext;
  chain: ChainReader;
  signer: AttestorSigner;
  audit: AuditLog;
  chainId: number;
  oracleAddress: Hex;
  escrowAddress: Hex;
}

export interface SignedAttestation<T> {
  attestation: T;
  digest: Hex;
  signature: Hex;
  attestor: Hex;
}

/*//////////////////////////////////////////////////////////////
                             OWNERSHIP
//////////////////////////////////////////////////////////////*/

export interface OwnershipAttestationRequest {
  /** The exact canonical message the holder signed, trailing LF included. */
  canonicalMessage: string;
  /** The BIP-322 proof, as the wallet returned it. */
  signature: string;
  variant: 'simple' | 'full';
  /** Address the wallet signed with. */
  signingAddress: string;
  /** `<txid>:<vout>` the claimant says holds the inscription. */
  claimedOutpoint: string;
  /** How long the attestation should remain usable, in seconds. */
  ttlSeconds: number;
  correlationId: string;
}

/**
 * Verify everything and sign an `OwnershipAttestation`.
 *
 * The order is: parse the message the holder actually signed → fetch the offer from chain
 * ourselves → check every signed term against it → verify Bitcoin → build the attestation from
 * *verified* values → compute the digest → sign.
 *
 * Note step two. The requester tells us which offer they claim this is for, but every term is
 * re-read from the chain and compared. A requester that lies about the payout address produces a
 * mismatch, not a signature.
 */
export async function attestOwnership(
  ctx: AttestorContext,
  request: OwnershipAttestationRequest,
): Promise<SignedAttestation<OwnershipAttestation>> {
  const startedAt = new Date().toISOString();

  // 1. Parse the canonical message. Strict: a message that would not have been produced by the
  //    builder is rejected even if its meaning is obvious.
  let fields: AuthorizationMessageFields;
  try {
    fields = parseMessage(request.canonicalMessage).fields;
  } catch (error) {
    reject(RejectionCode.MESSAGE_NOT_CANONICAL, 'the signed message is not in canonical form', {
      cause: error instanceof Error ? error.message : String(error),
    });
  }

  // 2. The message must be addressed to THIS deployment. A message naming another chain or another
  //    escrow is not ours to attest, and signing it would let one deployment authorise another.
  if (fields.rhChainId !== ctx.chainId) {
    reject(RejectionCode.OFFER_TERMS_MISMATCH, 'the message names a different Robinhood chain', {
      messageChainId: fields.rhChainId,
      ourChainId: ctx.chainId,
    });
  }
  if (fields.bitcoinNetwork !== ctx.verifier.network) {
    reject(RejectionCode.OFFER_TERMS_MISMATCH, 'the message names a different Bitcoin network', {
      messageNetwork: fields.bitcoinNetwork,
      ourNetwork: ctx.verifier.network,
    });
  }
  if (fields.verifyingContract.toLowerCase() !== ctx.escrowAddress.toLowerCase()) {
    reject(RejectionCode.OFFER_TERMS_MISMATCH, 'the message names a different escrow contract', {
      messageContract: fields.verifyingContract,
      ourEscrow: ctx.escrowAddress,
    });
  }

  // 3. Registry epoch and policy version, read from chain now. A signature produced under a stale
  //    epoch is worthless, so producing one wastes everyone's time.
  const { threshold, epoch, policyVersion } = await ctx.chain.quorumContext();
  if (policyVersion !== ctx.verifier.policyVersion) {
    reject(RejectionCode.STALE_POLICY_VERSION, 'this attestor is running a different policy version than the chain', {
      chain: policyVersion,
      local: ctx.verifier.policyVersion,
    });
  }

  // 4. Fetch the offer OURSELVES. Never trust the requester's copy of the terms.
  const isSelfCast = fields.purpose === 'SELF_CAST';
  const offer: OnChainOffer | null = await ctx.chain.getOffer(fields.contextId);
  if (!offer) {
    reject(RejectionCode.OFFER_NOT_FOUND, 'no such offer on chain', { offerId: fields.contextId });
  }
  if (offer.status !== 1 /* OPEN */) {
    reject(RejectionCode.OFFER_WRONG_STATUS, 'the offer is not open', { offerId: fields.contextId, status: offer.status });
  }
  if (offer.expiry <= BigInt(Math.floor(Date.now() / 1000))) {
    reject(RejectionCode.OFFER_EXPIRED, 'the offer has expired', { offerId: fields.contextId, expiry: offer.expiry });
  }
  if (await ctx.chain.isRootMinted(offer.rootKey)) {
    reject(RejectionCode.ROOT_ALREADY_MINTED, 'a HoodPup already exists for this Root', { rootKey: offer.rootKey });
  }

  // 5. Every signed term must equal the chain's. This is what makes "the terms I saw are the terms
  //    that execute" true rather than aspirational.
  const mismatches: string[] = [];
  if (fields.buyer.toLowerCase() !== offer.buyer.toLowerCase()) mismatches.push('buyer');
  if (fields.recipient.toLowerCase() !== offer.recipient.toLowerCase()) mismatches.push('recipient');
  if (fields.grossWei !== offer.grossWei) mismatches.push('grossWei');
  if (fields.sellerWei !== offer.sellerWei) mismatches.push('sellerWei');
  if (fields.sellerSats !== offer.sellerSats) mismatches.push('sellerSats');
  if (mismatches.length > 0) {
    reject(RejectionCode.OFFER_TERMS_MISMATCH, `signed terms disagree with the chain: ${mismatches.join(', ')}`, {
      mismatches,
    });
  }

  // 6. Recompute the terms hash and compare it to the one inside the signed message. Comparing the
  //    fields individually is not enough — the hash is what the contract checks at settlement.
  const expectedTermsHash = offerTermsHash({
    chainId: ctx.chainId,
    escrow: ctx.escrowAddress,
    offerId: fields.contextId,
    kind: offer.kind,
    rootKey: offer.rootKey,
    buyer: offer.buyer,
    recipient: offer.recipient,
    grossWei: offer.grossWei,
    sellerWei: offer.sellerWei,
    sellerSats: offer.sellerSats,
    expiry: offer.expiry,
  });
  if (expectedTermsHash.toLowerCase() !== fields.offerTermsHash.toLowerCase()) {
    reject(RejectionCode.OFFER_TERMS_MISMATCH, 'the offer terms hash in the signed message does not match the chain', {
      signed: fields.offerTermsHash,
      recomputed: expectedTermsHash,
    });
  }

  // 7. Payout shape must match the offer kind. The message package already checked internal
  //    consistency; this checks it against what the buyer actually escrowed.
  const expectedPayoutMode = offer.kind === 1 ? 'BTC' : isSelfCast ? 'NONE' : 'EVM';
  if (fields.payoutMode !== expectedPayoutMode) {
    reject(RejectionCode.PAYOUT_SHAPE_INVALID, 'the payout mode does not match the offer kind', {
      offerKind: offer.kind,
      payoutMode: fields.payoutMode,
      expected: expectedPayoutMode,
    });
  }

  // 8. Now, and only now, the expensive part: verify Bitcoin.
  const fact = await verifyOwnershipAuthorization(ctx.verifier, {
    inscriptionId: `${fields.rootTxid}i${fields.rootIndex}`,
    claimedOutpoint: request.claimedOutpoint,
    canonicalMessage: request.canonicalMessage,
    signingAddress: request.signingAddress,
    signature: request.signature,
    variant: request.variant,
  });

  // 9. The message's own outpoint claim must match what the chain actually shows. The holder signed
  //    a specific outpoint; attesting a different one would attest something nobody signed.
  const messageOutpoint = `${fields.currentOutpointTxid}:${fields.currentOutpointVout}`;
  if (messageOutpoint.toLowerCase() !== fact.currentOutpoint.toLowerCase()) {
    reject(RejectionCode.OFFER_TERMS_MISMATCH, 'the outpoint in the signed message is not where the inscription is', {
      signed: messageOutpoint,
      actual: fact.currentOutpoint,
    });
  }
  if (fact.rootKey.toLowerCase() !== offer.rootKey.toLowerCase()) {
    reject(RejectionCode.OFFER_TERMS_MISMATCH, 'the signed inscription is not the offer’s Root', {
      signed: fact.rootKey,
      offer: offer.rootKey,
    });
  }

  // 10. Build the attestation exclusively from verified values.
  const deadline = BigInt(Math.floor(Date.now() / 1000) + request.ttlSeconds);
  const attestation: OwnershipAttestation = {
    purpose: PURPOSE_ORDINAL[fields.purpose],
    rootTxid: fact.rootTxid,
    rootIndex: fact.rootIndex,
    contextId: fields.contextId,
    offerTermsHash: expectedTermsHash,
    currentOutpointHash: fact.currentOutpointHash,
    ownerScriptHash: fact.ownerScriptHash,
    bip322ProofHash: fact.bip322ProofHash,
    buyer: offer.buyer,
    recipient: offer.recipient,
    payoutMode: PAYOUT_MODE_ORDINAL[fields.payoutMode],
    evmPayout: fields.evmPayout,
    btcPayoutScriptHash: fields.btcPayoutScriptHash,
    sellerSats: fields.sellerSats,
    grossWei: offer.grossWei,
    sellerWei: offer.sellerWei,
    bitcoinBlockHash: `0x${fact.bitcoinBlockHash.replace(/^0x/, '')}` as Hex,
    bitcoinHeight: BigInt(fact.bitcoinHeight),
    authorizationId: fields.authorizationId,
    deadline: deadline < BigInt(fields.expiresAt) ? deadline : BigInt(fields.expiresAt),
    attestorEpoch: epoch,
    policyVersion,
  };

  // 11. Compute the digest ourselves and sign it. This is the only signature call in the pipeline.
  const digest = ownershipDigest(ctx.chainId, ctx.oracleAddress, attestation);
  const signature = await ctx.signer.signDigest(digest);

  await ctx.audit.record({
    correlationId: request.correlationId,
    kind: 'ownership',
    startedAt,
    finishedAt: new Date().toISOString(),
    attestor: ctx.signer.address,
    authorizationId: fields.authorizationId,
    bitcoinHeight: fact.bitcoinHeight,
    bitcoinTipHash: fact.bitcoinBlockHash,
    ordIndexHeight: fact.ordIndexHeight,
    threshold,
    epoch: Number(epoch),
    policyVersion,
    decision: 'signed',
    digest,
    facts: fact,
  });

  return { attestation, digest, signature, attestor: ctx.signer.address };
}

/**
 * Enum name -> on-chain ordinal.
 *
 * Typed as a total map over the canonical union rather than `Record<string, number>`, so adding a
 * purpose to the message format without mapping it here is a compile error instead of an
 * `undefined` silently encoded as a zero — which would be `PAID_EVM_MINT`.
 */
const PURPOSE_ORDINAL: Record<AuthorizationPurposeName, number> = {
  PAID_EVM_MINT: 0,
  PAID_BTC_MINT: 1,
  SELF_CAST: 2,
  ROOT_BIND: 3,
  ROOT_INVALIDATE: 4,
};

const PAYOUT_MODE_ORDINAL: Record<PayoutModeName, number> = { NONE: 0, EVM: 1, BTC: 2 };

/*//////////////////////////////////////////////////////////////
                              PAYMENT
//////////////////////////////////////////////////////////////*/

export interface PaymentAttestationRequest {
  offerId: Hex;
  bitcoinTxid: string;
  outputIndex: number;
  /** Solver claiming the reimbursement. Verified against the on-chain reservation. */
  solver: Hex;
  authorizationId: Hex;
  ttlSeconds: number;
  correlationId: string;
}

/**
 * Verify a BTC payment and sign a `BitcoinPaymentAttestation`.
 *
 * The solver claim is checked against the on-chain reservation, not taken at face value. A solver
 * that names itself for someone else's payment gets a mismatch.
 */
export async function attestPayment(
  ctx: AttestorContext,
  request: PaymentAttestationRequest,
): Promise<SignedAttestation<BitcoinPaymentAttestation>> {
  const startedAt = new Date().toISOString();
  const { epoch, policyVersion } = await ctx.chain.quorumContext();

  const offer = await ctx.chain.getOffer(request.offerId);
  if (!offer) reject(RejectionCode.OFFER_NOT_FOUND, 'no such offer on chain', { offerId: request.offerId });
  if (offer.status !== 3 /* BTC_RESERVED */) {
    reject(RejectionCode.OFFER_WRONG_STATUS, 'the offer is not reserved by a solver', { status: offer.status });
  }
  if (offer.reservedSolver.toLowerCase() !== request.solver.toLowerCase()) {
    reject(RejectionCode.OFFER_TERMS_MISMATCH, 'the claiming solver is not the offer’s active reserved solver', {
      claimed: request.solver,
      reserved: offer.reservedSolver,
    });
  }
  if (offer.ownershipDigest === `0x${'00'.repeat(32)}`) {
    reject(RejectionCode.OFFER_WRONG_STATUS, 'the offer has no recorded ownership digest', { offerId: request.offerId });
  }

  // Refuse before doing the work if the output is already spent on another offer.
  if (await ctx.chain.isPaymentOutputConsumed(request.bitcoinTxid, request.outputIndex)) {
    reject(RejectionCode.PAYMENT_OUTPUT_CONSUMED, 'this Bitcoin output has already settled an offer', {
      txid: request.bitcoinTxid,
      vout: request.outputIndex,
    });
  }

  const fact = await verifyBitcoinPayment(ctx.verifier, {
    bitcoinTxid: request.bitcoinTxid,
    outputIndex: request.outputIndex,
    expectedScriptHash: offer.btcPayoutScriptHash,
    expectedAmountSats: offer.sellerSats,
  });

  const attestation: BitcoinPaymentAttestation = {
    contextId: request.offerId,
    ownershipDigest: offer.ownershipDigest,
    solver: offer.reservedSolver,
    bitcoinTxid: fact.bitcoinTxid,
    outputIndex: fact.outputIndex,
    recipientScriptHash: fact.recipientScriptHash,
    amountSats: fact.amountSats,
    bitcoinBlockHash: `0x${fact.bitcoinBlockHash.replace(/^0x/, '')}` as Hex,
    bitcoinHeight: BigInt(fact.bitcoinHeight),
    authorizationId: request.authorizationId,
    deadline: BigInt(Math.floor(Date.now() / 1000) + request.ttlSeconds),
    attestorEpoch: epoch,
    policyVersion,
  };

  const digest = bitcoinPaymentDigest(ctx.chainId, ctx.oracleAddress, attestation);
  const signature = await ctx.signer.signDigest(digest);

  await ctx.audit.record({
    correlationId: request.correlationId,
    kind: 'payment',
    startedAt,
    finishedAt: new Date().toISOString(),
    attestor: ctx.signer.address,
    authorizationId: request.authorizationId,
    bitcoinHeight: fact.bitcoinHeight,
    bitcoinTipHash: fact.bitcoinBlockHash,
    ordIndexHeight: 0,
    threshold: 0,
    epoch: Number(epoch),
    policyVersion,
    decision: 'signed',
    digest,
    facts: fact,
  });

  return { attestation, digest, signature, attestor: ctx.signer.address };
}

/*//////////////////////////////////////////////////////////////
                            ROOT SPEND
//////////////////////////////////////////////////////////////*/

export interface RootSpendAttestationRequest {
  inscriptionId: string;
  previousOutpoint: string;
  spendingTxid: string;
  authorizationId: Hex;
  ttlSeconds: number;
  correlationId: string;
}

/** Verify that a recorded inscription outpoint was spent, and sign a `RootSpendAttestation`. */
export async function attestRootSpend(
  ctx: AttestorContext,
  request: RootSpendAttestationRequest,
): Promise<SignedAttestation<RootSpendAttestation>> {
  const startedAt = new Date().toISOString();
  const { epoch, policyVersion } = await ctx.chain.quorumContext();

  const fact = await verifyRootSpend(ctx.verifier, {
    inscriptionId: request.inscriptionId,
    previousOutpoint: request.previousOutpoint,
    spendingTxid: request.spendingTxid,
  });

  // The registry must actually record this outpoint as live. Attesting a spend of an outpoint the
  // registry never recorded would deactivate nothing, or worse, the wrong thing.
  const state = await ctx.chain.rootState(fact.rootKey);
  if (!state.active) {
    reject(RejectionCode.OFFER_WRONG_STATUS, 'this Root has no active epoch to invalidate', { rootKey: fact.rootKey });
  }
  if (state.currentOutpointHash.toLowerCase() !== fact.previousOutpointHash.toLowerCase()) {
    reject(RejectionCode.PREVIOUS_OUTPOINT_MISMATCH, 'the registry records a different live outpoint for this Root', {
      registry: state.currentOutpointHash,
      claimed: fact.previousOutpointHash,
    });
  }

  const attestation: RootSpendAttestation = {
    rootTxid: fact.rootTxid,
    rootIndex: fact.rootIndex,
    previousOutpointHash: fact.previousOutpointHash,
    spendingTxid: fact.spendingTxid,
    bitcoinBlockHash: `0x${fact.bitcoinBlockHash.replace(/^0x/, '')}` as Hex,
    bitcoinHeight: BigInt(fact.bitcoinHeight),
    authorizationId: request.authorizationId,
    deadline: BigInt(Math.floor(Date.now() / 1000) + request.ttlSeconds),
    attestorEpoch: epoch,
    policyVersion,
  };

  const digest = rootSpendDigest(ctx.chainId, ctx.oracleAddress, attestation);
  const signature = await ctx.signer.signDigest(digest);

  await ctx.audit.record({
    correlationId: request.correlationId,
    kind: 'rootSpend',
    startedAt,
    finishedAt: new Date().toISOString(),
    attestor: ctx.signer.address,
    authorizationId: request.authorizationId,
    bitcoinHeight: fact.bitcoinHeight,
    bitcoinTipHash: fact.bitcoinBlockHash,
    ordIndexHeight: 0,
    threshold: 0,
    epoch: Number(epoch),
    policyVersion,
    decision: 'signed',
    digest,
    facts: fact,
  });

  return { attestation, digest, signature, attestor: ctx.signer.address };
}
