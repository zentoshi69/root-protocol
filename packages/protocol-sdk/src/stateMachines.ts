/**
 * Offer, solver and relayer state-machine helpers.
 *
 * Mirrors `docs/STATE_MACHINES.md` and the enums in `PuppetTypes.sol`. A UI that computes "can I
 * refund yet?" by hand will eventually disagree with the contract and show a button that reverts;
 * these helpers keep that logic in one place, next to the reasoning.
 */

export const OfferKind = { PAID_EVM: 0, PAID_BTC: 1, SELF_CAST: 2 } as const;
export const OfferStatus = {
  NONE: 0,
  OPEN: 1,
  BTC_APPROVED: 2,
  BTC_RESERVED: 3,
  SETTLED: 4,
  REFUNDED: 5,
} as const;
export const PayoutMode = { NONE: 0, EVM: 1, BTC: 2 } as const;
export const AuthorizationPurpose = {
  PAID_EVM_MINT: 0,
  PAID_BTC_MINT: 1,
  SELF_CAST: 2,
  ROOT_BIND: 3,
  ROOT_INVALIDATE: 4,
} as const;
export const ReservationStatus = { NONE: 0, ACTIVE: 1, SETTLED: 2, EXPIRED: 3 } as const;

export type OfferStatusValue = (typeof OfferStatus)[keyof typeof OfferStatus];
export type OfferKindValue = (typeof OfferKind)[keyof typeof OfferKind];

export const OFFER_STATUS_LABEL: Record<number, string> = {
  0: 'Not created',
  1: 'Open — waiting for the Bitcoin holder',
  2: 'Approved — waiting for a solver to pay BTC',
  3: 'Reserved — a solver is paying BTC now',
  4: 'Settled',
  5: 'Refunded',
};

/** Terminal states can never transition again. */
export function isTerminal(status: number): boolean {
  return status === OfferStatus.SETTLED || status === OfferStatus.REFUNDED;
}

export interface OfferView {
  kind: number;
  status: number;
  expiry: bigint;
  grossWei: bigint;
  reservationExpiry: bigint;
}

/**
 * Refundable at expiry.
 *
 * `BTC_RESERVED` is deliberately excluded: a solver may already have broadcast the Bitcoin payment,
 * and refunding the buyer underneath them would leave the solver having paid real BTC for nothing.
 * The reservation must be expired first, which slashes the bond and returns the offer to
 * `BTC_APPROVED`.
 */
export function canRefundExpired(offer: OfferView, nowSeconds: bigint): boolean {
  if (isTerminal(offer.status)) return false;
  if (offer.status !== OfferStatus.OPEN && offer.status !== OfferStatus.BTC_APPROVED) return false;
  return nowSeconds > offer.expiry;
}

/** Refundable immediately when a competing offer already minted the Root. */
export function canRefundUnfillable(offer: OfferView, rootAlreadyMinted: boolean): boolean {
  if (isTerminal(offer.status)) return false;
  return rootAlreadyMinted;
}

/**
 * Whether a buyer may cancel. Always false, deliberately.
 *
 * A Bitcoin holder may be minutes or hours into a cold-wallet signing ceremony. A cancellable offer
 * would let a buyer bait a valid signature and then withdraw, obtaining an authorization for free.
 * The buyer's protection is the expiry, plus immediate refundability if someone else wins the Root.
 */
export function canBuyerCancel(): false {
  return false;
}

/** A solver may reserve only an approved, unexpired, unreserved offer. */
export function canSolverReserve(offer: OfferView, nowSeconds: bigint): boolean {
  return offer.status === OfferStatus.BTC_APPROVED && nowSeconds <= offer.expiry;
}

/** Anyone may expire a stale reservation; the bond is then slashed and split. */
export function canExpireReservation(offer: OfferView, nowSeconds: bigint): boolean {
  return offer.status === OfferStatus.BTC_RESERVED && nowSeconds > offer.reservationExpiry;
}

/** Which authorization purpose an offer kind requires. */
export function purposeForKind(kind: number): number {
  switch (kind) {
    case OfferKind.PAID_EVM:
      return AuthorizationPurpose.PAID_EVM_MINT;
    case OfferKind.PAID_BTC:
      return AuthorizationPurpose.PAID_BTC_MINT;
    case OfferKind.SELF_CAST:
      return AuthorizationPurpose.SELF_CAST;
    default:
      throw new RangeError(`unknown offer kind ${kind}`);
  }
}

/*//////////////////////////////////////////////////////////////
                        RELAYER STATUS MODEL
//////////////////////////////////////////////////////////////*/

export const RelayerStatus = [
  'PROOF_RECEIVED',
  'VERIFYING',
  'ATTESTATIONS_1_OF_3',
  'ATTESTATIONS_2_OF_3',
  'READY_TO_SUBMIT',
  'SUBMITTED',
  'CONFIRMED',
  'REJECTED',
  'EXPIRED',
] as const;

export type RelayerStatusValue = (typeof RelayerStatus)[number];

export const RELAYER_STATUS_LABEL: Record<RelayerStatusValue, string> = {
  PROOF_RECEIVED: 'Proof received',
  VERIFYING: 'Verifiers checking Bitcoin',
  ATTESTATIONS_1_OF_3: '1 of 3 verifiers agreed',
  ATTESTATIONS_2_OF_3: '2 of 3 verifiers agreed',
  READY_TO_SUBMIT: '3 of 3 agreed — submitting',
  SUBMITTED: 'Submitted to Robinhood Chain',
  CONFIRMED: 'Confirmed',
  REJECTED: 'Rejected by verifiers',
  EXPIRED: 'Expired before settlement',
};

/**
 * Progress from an attestation count.
 *
 * The relayer requires the threshold of **byte-identical** fact sets. Three individually valid
 * signatures over three *different* fact sets is a rejection, not a quorum — count matching facts,
 * never signatures.
 */
export function relayerStatusFromCount(matching: number, threshold = 3): RelayerStatusValue {
  if (matching <= 0) return 'VERIFYING';
  if (matching >= threshold) return 'READY_TO_SUBMIT';
  return matching === 1 ? 'ATTESTATIONS_1_OF_3' : 'ATTESTATIONS_2_OF_3';
}
