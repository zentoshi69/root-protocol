/**
 * Solver economics and the go/no-go decision.
 *
 * ## There is no price oracle, anywhere
 *
 * The offer fixed `sellerSats` (what the seller receives on Bitcoin) and `sellerWei` (what the
 * solver is reimbursed on Robinhood Chain) at creation, and the Bitcoin holder signed both. The
 * solver either finds that spread attractive or ignores the offer.
 *
 * That single choice removes oracle manipulation, BTC/ETH price disputes, slippage arguments and
 * "the chart moved while I was signing" from the settlement path. The cost is that a quote can go
 * stale, and that cost lands on the buyer — whose offer simply expires and refunds — never on the
 * protocol.
 *
 * A solver is a market maker taking a position, not a service provider. Nothing here is insured.
 */

export interface SolverConfig {
  /** Minimum profit, in wei, required to reserve. */
  minimumProfitWei: bigint;
  /** Minimum profit as a fraction of the reimbursement, in basis points. Both must be met. */
  minimumMarginBps: bigint;
  /** The solver's own BTC→ETH reference rate, in wei per satoshi. Its view, not an oracle. */
  weiPerSat: bigint;
  /** Expected Bitcoin network fee for the payment, in satoshis. */
  expectedNetworkFeeSats: bigint;
  /** Expected Robinhood Chain gas for reserve + settle, in wei. */
  expectedGasWei: bigint;
  /** Bond the solver is willing to post, in wei. Must be at least the contract's minimum. */
  bondWei: bigint;
  /** Maximum sats to expose on a single offer. */
  maxExposureSats: bigint;
}

export interface OfferQuote {
  offerId: string;
  sellerSats: bigint;
  sellerWei: bigint;
  /** Offer expiry, unix seconds. */
  expiry: bigint;
  /** How long a reservation lasts once taken, in seconds. */
  reservationDuration: bigint;
  /** Contract minimum bond, in wei. */
  minimumBondWei: bigint;
}

export interface ProfitAnalysis {
  /** What the solver receives. */
  reimbursementWei: bigint;
  /** What the sats cost at the solver's own reference rate. */
  satsCostWei: bigint;
  networkFeeWei: bigint;
  gasWei: bigint;
  profitWei: bigint;
  marginBps: bigint;
}

export function analyseProfit(quote: OfferQuote, config: SolverConfig): ProfitAnalysis {
  const satsCostWei = quote.sellerSats * config.weiPerSat;
  const networkFeeWei = config.expectedNetworkFeeSats * config.weiPerSat;
  const profitWei = quote.sellerWei - satsCostWei - networkFeeWei - config.expectedGasWei;
  return {
    reimbursementWei: quote.sellerWei,
    satsCostWei,
    networkFeeWei,
    gasWei: config.expectedGasWei,
    profitWei,
    marginBps: quote.sellerWei === 0n ? 0n : (profitWei * 10_000n) / quote.sellerWei,
  };
}

export type DeclineReason =
  | 'UNPROFITABLE'
  | 'MARGIN_TOO_THIN'
  | 'EXPOSURE_EXCEEDED'
  | 'BOND_BELOW_MINIMUM'
  | 'RESERVATION_WINDOW_TOO_SHORT'
  | 'OFFER_EXPIRES_TOO_SOON';

export interface Decision {
  reserve: boolean;
  reason?: DeclineReason;
  analysis: ProfitAnalysis;
}

/**
 * Decide whether to reserve.
 *
 * Two of these checks are not about profit at all, and they are the ones that actually protect a
 * solver from ruin:
 *
 * - `RESERVATION_WINDOW_TOO_SHORT` — if the reservation can expire before the payment reaches the
 *   verifier's confirmation depth, the solver loses **both the bond and the BTC**. That is the
 *   single worst outcome available in this protocol, and it is a configuration bug rather than a
 *   market risk. Refuse to reserve and report it.
 * - `OFFER_EXPIRES_TOO_SOON` — a reservation that outlives its offer cannot settle.
 */
export function decide(
  quote: OfferQuote,
  config: SolverConfig,
  context: {
    nowSeconds: bigint;
    /** Confirmations the verifiers require before they will attest the payment. */
    requiredConfirmations: bigint;
    /** Realistic seconds per block for the target network. */
    secondsPerBlock: bigint;
    /** Safety multiplier over the naive confirmation time. */
    safetyFactor?: bigint;
  },
): Decision {
  const analysis = analyseProfit(quote, config);

  if (config.bondWei < quote.minimumBondWei) {
    return { reserve: false, reason: 'BOND_BELOW_MINIMUM', analysis };
  }
  if (quote.sellerSats > config.maxExposureSats) {
    return { reserve: false, reason: 'EXPOSURE_EXCEEDED', analysis };
  }

  const safety = context.safetyFactor ?? 2n;
  const confirmationSeconds = context.requiredConfirmations * context.secondsPerBlock * safety;
  if (quote.reservationDuration < confirmationSeconds) {
    return { reserve: false, reason: 'RESERVATION_WINDOW_TOO_SHORT', analysis };
  }
  if (quote.expiry - context.nowSeconds < confirmationSeconds) {
    return { reserve: false, reason: 'OFFER_EXPIRES_TOO_SOON', analysis };
  }

  if (analysis.profitWei < config.minimumProfitWei) {
    return { reserve: false, reason: 'UNPROFITABLE', analysis };
  }
  if (analysis.marginBps < config.minimumMarginBps) {
    return { reserve: false, reason: 'MARGIN_TOO_THIN', analysis };
  }

  return { reserve: true, analysis };
}

/*//////////////////////////////////////////////////////////////
                           RECONCILIATION
//////////////////////////////////////////////////////////////*/

export interface SettlementRecord {
  offerId: string;
  bondPostedWei: bigint;
  bondReturnedWei: bigint;
  bondSlashedWei: bigint;
  satsPaid: bigint;
  bitcoinFeeSats: bigint;
  reimbursementWei: bigint;
  gasSpentWei: bigint;
  outcome: 'settled' | 'expired' | 'active';
}

/**
 * Assert the solver's own books balance, mirroring the on-chain bond invariant.
 *
 * A mismatch means either the books are wrong or the contract is. Check the contract's own
 * invariant test before assuming it is the books.
 */
export function reconcileBonds(records: SettlementRecord[]): {
  posted: bigint;
  returned: bigint;
  slashed: bigint;
  locked: bigint;
  balanced: boolean;
} {
  let posted = 0n;
  let returned = 0n;
  let slashed = 0n;
  let locked = 0n;

  for (const r of records) {
    posted += r.bondPostedWei;
    returned += r.bondReturnedWei;
    slashed += r.bondSlashedWei;
    if (r.outcome === 'active') locked += r.bondPostedWei;
  }

  return { posted, returned, slashed, locked, balanced: posted === returned + slashed + locked };
}

/** Realised profit and loss across settled offers, in wei at the solver's reference rate. */
export function realisedPnl(records: SettlementRecord[], weiPerSat: bigint): bigint {
  let pnl = 0n;
  for (const r of records) {
    if (r.outcome === 'settled') {
      pnl += r.reimbursementWei - (r.satsPaid + r.bitcoinFeeSats) * weiPerSat - r.gasSpentWei;
    } else if (r.outcome === 'expired') {
      // The worst case made explicit: an expired reservation loses the slashed bond AND, if the
      // payment was already broadcast, the sats. Both belong in the P&L.
      pnl -= r.bondSlashedWei + r.gasSpentWei + (r.satsPaid + r.bitcoinFeeSats) * weiPerSat;
    }
  }
  return pnl;
}
