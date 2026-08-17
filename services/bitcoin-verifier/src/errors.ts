/**
 * Structured rejection codes.
 *
 * A verifier never returns a bare boolean. "False" is useless to a user waiting on a claim and
 * useless to an operator triaging a disagreement — the whole value of five independent verifiers is
 * being able to compare *why* they differed.
 *
 * These codes are stable API. Renaming one breaks operator dashboards and user-facing copy, so
 * treat the list as append-only.
 */

export const RejectionCode = {
  // Collection membership
  ROOT_NOT_IN_MANIFEST: 'ROOT_NOT_IN_MANIFEST',

  // Inscription location
  INSCRIPTION_NOT_FOUND: 'INSCRIPTION_NOT_FOUND',
  INSCRIPTION_NOT_AT_CLAIMED_OUTPOINT: 'INSCRIPTION_NOT_AT_CLAIMED_OUTPOINT',
  OUTPUT_NOT_FOUND: 'OUTPUT_NOT_FOUND',
  OUTPOINT_SPENT: 'OUTPOINT_SPENT',
  MEMPOOL_SPEND_DETECTED: 'MEMPOOL_SPEND_DETECTED',
  INSUFFICIENT_CONFIRMATIONS: 'INSUFFICIENT_CONFIRMATIONS',

  // Signature
  BIP322_INVALID: 'BIP322_INVALID',
  BIP322_VARIANT_UNSUPPORTED: 'BIP322_VARIANT_UNSUPPORTED',
  SCRIPT_TYPE_UNSUPPORTED: 'SCRIPT_TYPE_UNSUPPORTED',
  SCRIPT_BINDING_MISMATCH: 'SCRIPT_BINDING_MISMATCH',
  MESSAGE_NOT_CANONICAL: 'MESSAGE_NOT_CANONICAL',

  // Offer agreement
  OFFER_NOT_FOUND: 'OFFER_NOT_FOUND',
  OFFER_TERMS_MISMATCH: 'OFFER_TERMS_MISMATCH',
  OFFER_EXPIRED: 'OFFER_EXPIRED',
  OFFER_WRONG_STATUS: 'OFFER_WRONG_STATUS',
  ROOT_ALREADY_MINTED: 'ROOT_ALREADY_MINTED',
  PAYOUT_SHAPE_INVALID: 'PAYOUT_SHAPE_INVALID',

  // Policy
  STALE_ATTESTOR_EPOCH: 'STALE_ATTESTOR_EPOCH',
  STALE_POLICY_VERSION: 'STALE_POLICY_VERSION',
  AUTHORIZATION_EXPIRED: 'AUTHORIZATION_EXPIRED',

  // Payment
  PAYMENT_TX_NOT_FOUND: 'PAYMENT_TX_NOT_FOUND',
  PAYMENT_OUTPUT_NOT_FOUND: 'PAYMENT_OUTPUT_NOT_FOUND',
  PAYMENT_AMOUNT_MISMATCH: 'PAYMENT_AMOUNT_MISMATCH',
  PAYMENT_SCRIPT_MISMATCH: 'PAYMENT_SCRIPT_MISMATCH',
  PAYMENT_OUTPUT_CONSUMED: 'PAYMENT_OUTPUT_CONSUMED',
  PAYMENT_CONFLICTING_SPEND: 'PAYMENT_CONFLICTING_SPEND',

  // Root spend
  PREVIOUS_OUTPOINT_MISMATCH: 'PREVIOUS_OUTPOINT_MISMATCH',
  SPEND_NOT_FOUND: 'SPEND_NOT_FOUND',

  // Infrastructure — honest "I don't know" answers
  NODE_UNAVAILABLE: 'NODE_UNAVAILABLE',
  BITCOIN_NETWORK_MISMATCH: 'BITCOIN_NETWORK_MISMATCH',
  ORD_UNAVAILABLE: 'ORD_UNAVAILABLE',
  ORD_INDEX_LAGGING: 'ORD_INDEX_LAGGING',
  ORD_INDEX_INCONSISTENT: 'ORD_INDEX_INCONSISTENT',
  CHAIN_RPC_UNAVAILABLE: 'CHAIN_RPC_UNAVAILABLE',
  INTERNAL_ERROR: 'INTERNAL_ERROR',
} as const;

export type RejectionCodeValue = (typeof RejectionCode)[keyof typeof RejectionCode];

/**
 * Codes that mean "this operator could not determine the answer", as opposed to "the claim is
 * false".
 *
 * The distinction matters operationally: an operator that cannot verify must abstain, never defer
 * to the others. A quorum of four honest operators plus one that guesses is worse than four.
 */
export const INFRASTRUCTURE_CODES: readonly RejectionCodeValue[] = [
  RejectionCode.NODE_UNAVAILABLE,
  RejectionCode.BITCOIN_NETWORK_MISMATCH,
  RejectionCode.ORD_UNAVAILABLE,
  RejectionCode.ORD_INDEX_LAGGING,
  RejectionCode.ORD_INDEX_INCONSISTENT,
  RejectionCode.CHAIN_RPC_UNAVAILABLE,
  RejectionCode.INTERNAL_ERROR,
];

export function isInfrastructureFailure(code: RejectionCodeValue): boolean {
  return INFRASTRUCTURE_CODES.includes(code);
}

/** A verification rejection. Carries the code, a human explanation, and safe-to-log detail. */
export class VerificationRejection extends Error {
  constructor(
    readonly code: RejectionCodeValue,
    message: string,
    readonly detail: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = 'VerificationRejection';
  }

  toJSON() {
    return { code: this.code, message: this.message, detail: this.detail };
  }
}

export function reject(
  code: RejectionCodeValue,
  message: string,
  detail: Record<string, unknown> = {},
): never {
  throw new VerificationRejection(code, message, detail);
}
