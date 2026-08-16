/**
 * Building the Bitcoin payment.
 *
 * ## Key custody
 *
 * The solver's Bitcoin wallet is **operational only**. It must never be an inscription wallet, and
 * it is never the user's. Conflating them is how a solver ends up spending a customer's Puppet to
 * pay a customer.
 *
 * Production signing is PSBT-based with a hardware or HSM key. This module deliberately builds an
 * unsigned request and hands it to a {@link PaymentSigner}; there is no code path here that touches
 * a private key, so a seed can never be read from an environment file by this package.
 *
 * ## Exactness
 *
 * The output must pay `exactly sellerSats` to `exactly` the approved script. Verifiers compare the
 * raw scriptPubKey hash and the exact satoshi value. One satoshi off in either direction is a
 * rejection — so the change output must absorb the fee, never the payment.
 */

import { scriptHash } from '@hoodpups/protocol-sdk';
import type { Hex } from 'viem';

export interface PaymentRequest {
  offerId: Hex;
  /** Raw scriptPubKey the seller signed for. Not an address string. */
  recipientScriptPubKeyHex: string;
  /** Exact satoshis. Not a minimum. */
  amountSats: bigint;
  /** Fee rate in sat/vB the solver intends to pay. */
  feeRateSatPerVb: number;
}

export interface UnsignedPayment {
  offerId: Hex;
  recipientScriptPubKeyHex: string;
  amountSats: bigint;
  feeRateSatPerVb: number;
  /** Set by the signer once broadcast. */
  txid?: string;
  outputIndex?: number;
}

export interface PaymentSigner {
  readonly kind: 'psbt-hardware' | 'psbt-hsm' | 'regtest-wallet';
  /** Sign and broadcast. Returns the txid and the index of the payment output. */
  signAndBroadcast(payment: UnsignedPayment): Promise<{ txid: string; outputIndex: number }>;
}

export class PaymentValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PaymentValidationError';
  }
}

/**
 * Validate a payment request before any key is touched.
 *
 * Catching a wrong script or a wrong amount here costs nothing. Catching it after broadcast costs
 * the entire payment, because the verifiers will refuse to attest it and the sats are gone.
 */
export function validatePaymentRequest(request: PaymentRequest, approvedScriptHash: Hex, approvedSats: bigint): void {
  const scriptHex = request.recipientScriptPubKeyHex.replace(/^0x/, '').toLowerCase();
  if (!/^([0-9a-f]{2})+$/.test(scriptHex)) {
    throw new PaymentValidationError('recipient scriptPubKey must be even-length lowercase hex');
  }

  const computed = scriptHash(`0x${scriptHex}` as Hex);
  if (computed.toLowerCase() !== approvedScriptHash.toLowerCase()) {
    throw new PaymentValidationError(
      `refusing to pay: this script is not the one the seller approved (approved ${approvedScriptHash}, got ${computed})`,
    );
  }

  if (request.amountSats !== approvedSats) {
    throw new PaymentValidationError(
      `refusing to pay: amount must be exactly ${approvedSats} sats, got ${request.amountSats}. ` +
        'Verifiers compare the exact value; one satoshi in either direction is a rejection.',
    );
  }

  if (request.amountSats <= 0n) {
    throw new PaymentValidationError('amount must be positive');
  }

  if (request.feeRateSatPerVb <= 0) {
    throw new PaymentValidationError('fee rate must be positive');
  }
}

/**
 * Build the unsigned payment.
 *
 * @throws {PaymentValidationError} if anything disagrees with what the seller approved.
 */
export function buildPayment(request: PaymentRequest, approvedScriptHash: Hex, approvedSats: bigint): UnsignedPayment {
  validatePaymentRequest(request, approvedScriptHash, approvedSats);
  return {
    offerId: request.offerId,
    recipientScriptPubKeyHex: request.recipientScriptPubKeyHex.replace(/^0x/, '').toLowerCase(),
    amountSats: request.amountSats,
    feeRateSatPerVb: request.feeRateSatPerVb,
  };
}

/*//////////////////////////////////////////////////////////////
                         RBF SAFETY
//////////////////////////////////////////////////////////////*/

/**
 * Whether a fee bump is safe to make.
 *
 * Fee bumping is fine as long as the payment output is untouched. A replacement that changes the
 * recipient script or the amount invalidates the payment: verifiers check for conflicting spends,
 * and the original attestation — if one was already produced — describes a transaction that no
 * longer exists.
 */
export function isFeeBumpSafe(
  original: { recipientScriptPubKeyHex: string; amountSats: bigint },
  replacement: { recipientScriptPubKeyHex: string; amountSats: bigint },
): boolean {
  return (
    original.recipientScriptPubKeyHex.toLowerCase() === replacement.recipientScriptPubKeyHex.toLowerCase() &&
    original.amountSats === replacement.amountSats
  );
}

/**
 * Seconds a solver should allow for the payment to reach the verifiers' confirmation depth.
 *
 * Deliberately pessimistic. Underestimating this is how a solver loses both the bond and the BTC —
 * the single worst outcome in the protocol, and one that no amount of profit margin compensates for.
 */
export function estimateConfirmationSeconds(
  requiredConfirmations: number,
  secondsPerBlock: number,
  safetyFactor = 2,
): number {
  return requiredConfirmations * secondsPerBlock * safetyFactor;
}
