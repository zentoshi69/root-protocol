import { describe, expect, it } from 'vitest';
import { scriptHash } from '@hoodpups/protocol-sdk';
import type { Hex } from 'viem';
import {
  analyseProfit,
  buildPayment,
  decide,
  estimateConfirmationSeconds,
  isFeeBumpSafe,
  PaymentValidationError,
  realisedPnl,
  reconcileBonds,
  validatePaymentRequest,
  type OfferQuote,
  type SolverConfig,
} from '../src/index.js';

const SCRIPT = `5120${'a1'.repeat(32)}`;
const SCRIPT_HASH = scriptHash(`0x${SCRIPT}` as Hex);
const OFFER_ID = `0x${'ab'.repeat(32)}` as Hex;

// 1 sat = 10^10 wei is a round stand-in; the real number is the solver's own view, not an oracle.
const WEI_PER_SAT = 10_000_000_000n;

// Realistic scale matters here: an absurdly wide spread makes the margin check unreachable and
// the test would pass for the wrong reason. 50,000 sats cost 0.0005 ETH at the reference rate, the
// offer reimburses 0.00055 ETH, so the gross spread is ~10% before fees and gas.
const config = (over: Partial<SolverConfig> = {}): SolverConfig => ({
  minimumProfitWei: 10_000_000_000_000n, // 0.00001 ETH
  minimumMarginBps: 100n, // 1%
  weiPerSat: WEI_PER_SAT,
  expectedNetworkFeeSats: 500n,
  expectedGasWei: 1_000_000_000_000n, // 0.000001 ETH — L2 gas
  bondWei: 10_000_000_000_000_000n, // 0.01 ETH
  maxExposureSats: 1_000_000n,
  ...over,
});

const quote = (over: Partial<OfferQuote> = {}): OfferQuote => ({
  offerId: 'offer-1',
  sellerSats: 50_000n,
  sellerWei: 550_000_000_000_000n, // 0.00055 ETH against 0.0005 ETH of sats — an ~8% net margin
  expiry: 100_000n,
  reservationDuration: 3600n,
  minimumBondWei: 1_000_000_000_000_000n,
  ...over,
});

const context = { nowSeconds: 1000n, requiredConfirmations: 3n, secondsPerBlock: 600n };

describe('profit analysis uses the solver’s own rate, never an oracle', () => {
  it('accounts for sats cost, network fee and gas', () => {
    const a = analyseProfit(quote(), config());
    expect(a.satsCostWei).toBe(50_000n * WEI_PER_SAT);
    expect(a.networkFeeWei).toBe(500n * WEI_PER_SAT);
    expect(a.profitWei).toBe(550_000_000_000_000n - 50_000n * WEI_PER_SAT - 500n * WEI_PER_SAT - 1_000_000_000_000n);
    expect(a.marginBps).toBe(800n); // 8%
    expect(a.marginBps).toBeGreaterThan(0n);
  });

  it('reports a loss as a negative profit rather than clamping to zero', () => {
    const a = analyseProfit(quote({ sellerWei: 1n }), config());
    expect(a.profitWei).toBeLessThan(0n);
  });
});

describe('the reserve decision', () => {
  it('reserves a profitable offer with a safe window', () => {
    expect(decide(quote(), config(), context).reserve).toBe(true);
  });

  it('declines an unprofitable quote', () => {
    // Reimbursement barely covers the sats, leaving nothing for fee and gas.
    const d = decide(quote({ sellerWei: 505_000_000_000_000n }), config(), context);
    expect(d.reserve).toBe(false);
    expect(d.reason).toBe('UNPROFITABLE');
  });

  it('declines when the margin is too thin even if the absolute profit clears', () => {
    // 8% realised against a 9% floor: the absolute profit clears minimumProfitWei, the margin does not.
    const d = decide(quote(), config({ minimumMarginBps: 900n }), context);
    expect(d.reserve).toBe(false);
    expect(d.reason).toBe('MARGIN_TOO_THIN');
  });

  it('declines when exposure exceeds the cap', () => {
    const d = decide(quote({ sellerSats: 2_000_000n }), config(), context);
    expect(d.reserve).toBe(false);
    expect(d.reason).toBe('EXPOSURE_EXCEEDED');
  });

  it('declines when the configured bond is below the contract minimum', () => {
    const d = decide(quote({ minimumBondWei: 10n ** 18n }), config(), context);
    expect(d.reserve).toBe(false);
    expect(d.reason).toBe('BOND_BELOW_MINIMUM');
  });

  it('refuses a reservation window shorter than the confirmation policy', () => {
    // THE failure mode: reserve, pay real BTC, get expired before the payment confirms, lose both
    // the bond and the sats. No profit margin compensates for that, so it is a hard refusal.
    const d = decide(quote({ reservationDuration: 600n }), config(), context);
    expect(d.reserve).toBe(false);
    expect(d.reason).toBe('RESERVATION_WINDOW_TOO_SHORT');
  });

  it('refuses when the offer itself expires before the payment could confirm', () => {
    const d = decide(quote({ expiry: 2000n }), config(), context);
    expect(d.reserve).toBe(false);
    expect(d.reason).toBe('OFFER_EXPIRES_TOO_SOON');
  });

  it('checks window safety before profitability, so a bad config is never masked by a fat spread', () => {
    const d = decide(quote({ reservationDuration: 60n, sellerWei: 10n ** 18n }), config(), context);
    expect(d.reason).toBe('RESERVATION_WINDOW_TOO_SHORT');
  });
});

describe('payment construction refuses to be approximately right', () => {
  const request = {
    offerId: OFFER_ID,
    recipientScriptPubKeyHex: SCRIPT,
    amountSats: 50_000n,
    feeRateSatPerVb: 10,
  };

  it('builds a payment matching the approved script and amount', () => {
    const payment = buildPayment(request, SCRIPT_HASH, 50_000n);
    expect(payment.amountSats).toBe(50_000n);
    expect(payment.recipientScriptPubKeyHex).toBe(SCRIPT);
  });

  it('refuses a script the seller did not approve', () => {
    // Catching this before broadcast costs nothing; catching it after costs the whole payment,
    // because verifiers will not attest it and the sats are gone.
    expect(() => validatePaymentRequest(request, `0x${'ff'.repeat(32)}` as Hex, 50_000n)).toThrow(
      /not the one the seller approved/,
    );
  });

  it('refuses an amount that is off by one satoshi in either direction', () => {
    expect(() => validatePaymentRequest({ ...request, amountSats: 49_999n }, SCRIPT_HASH, 50_000n)).toThrow(
      PaymentValidationError,
    );
    expect(() => validatePaymentRequest({ ...request, amountSats: 50_001n }, SCRIPT_HASH, 50_000n)).toThrow(
      /exactly 50000 sats/,
    );
  });

  it('refuses a malformed script or a non-positive fee rate', () => {
    expect(() => validatePaymentRequest({ ...request, recipientScriptPubKeyHex: 'zz' }, SCRIPT_HASH, 50_000n)).toThrow(
      /lowercase hex/,
    );
    expect(() => validatePaymentRequest({ ...request, feeRateSatPerVb: 0 }, SCRIPT_HASH, 50_000n)).toThrow(/fee rate/);
  });

  it('accepts a 0x-prefixed script and normalises it consistently', () => {
    const payment = buildPayment({ ...request, recipientScriptPubKeyHex: `0x${SCRIPT}` }, SCRIPT_HASH, 50_000n);
    expect(payment.recipientScriptPubKeyHex).toBe(SCRIPT);
  });
});

describe('RBF safety', () => {
  const original = { recipientScriptPubKeyHex: SCRIPT, amountSats: 50_000n };

  it('allows a pure fee bump', () => {
    expect(isFeeBumpSafe(original, { ...original })).toBe(true);
  });

  it('rejects a replacement that changes the recipient', () => {
    // Verifiers check for conflicting spends; a replacement that moves the payment invalidates any
    // attestation already produced for the original.
    expect(isFeeBumpSafe(original, { recipientScriptPubKeyHex: `5120${'ee'.repeat(32)}`, amountSats: 50_000n })).toBe(
      false,
    );
  });

  it('rejects a replacement that changes the amount', () => {
    expect(isFeeBumpSafe(original, { ...original, amountSats: 49_000n })).toBe(false);
  });
});

describe('confirmation time estimation is deliberately pessimistic', () => {
  it('applies the safety factor', () => {
    expect(estimateConfirmationSeconds(3, 600)).toBe(3600);
    expect(estimateConfirmationSeconds(3, 600, 3)).toBe(5400);
  });
});

describe('bond reconciliation mirrors the on-chain invariant', () => {
  it('balances when every bond is returned, slashed or locked', () => {
    const result = reconcileBonds([
      { offerId: '1', bondPostedWei: 100n, bondReturnedWei: 100n, bondSlashedWei: 0n, satsPaid: 10n, bitcoinFeeSats: 1n, reimbursementWei: 200n, gasSpentWei: 5n, outcome: 'settled' },
      { offerId: '2', bondPostedWei: 100n, bondReturnedWei: 0n, bondSlashedWei: 100n, satsPaid: 0n, bitcoinFeeSats: 0n, reimbursementWei: 0n, gasSpentWei: 5n, outcome: 'expired' },
      { offerId: '3', bondPostedWei: 100n, bondReturnedWei: 0n, bondSlashedWei: 0n, satsPaid: 0n, bitcoinFeeSats: 0n, reimbursementWei: 0n, gasSpentWei: 0n, outcome: 'active' },
    ]);
    expect(result.posted).toBe(300n);
    expect(result.returned).toBe(100n);
    expect(result.slashed).toBe(100n);
    expect(result.locked).toBe(100n);
    expect(result.balanced).toBe(true);
  });

  it('flags books that do not balance', () => {
    const result = reconcileBonds([
      { offerId: '1', bondPostedWei: 100n, bondReturnedWei: 50n, bondSlashedWei: 0n, satsPaid: 0n, bitcoinFeeSats: 0n, reimbursementWei: 0n, gasSpentWei: 0n, outcome: 'settled' },
    ]);
    expect(result.balanced).toBe(false);
  });

  it('counts a timeout that already paid BTC as losing both the bond and the sats', () => {
    // The worst case, stated explicitly in the P&L rather than buried.
    const pnl = realisedPnl(
      [
        {
          offerId: '1',
          bondPostedWei: 1000n,
          bondReturnedWei: 0n,
          bondSlashedWei: 1000n,
          satsPaid: 50n,
          bitcoinFeeSats: 5n,
          reimbursementWei: 0n,
          gasSpentWei: 10n,
          outcome: 'expired',
        },
      ],
      2n,
    );
    expect(pnl).toBe(-(1000n + 10n + 55n * 2n));
  });

  it('computes realised profit on a settled offer', () => {
    const pnl = realisedPnl(
      [
        {
          offerId: '1',
          bondPostedWei: 1000n,
          bondReturnedWei: 1000n,
          bondSlashedWei: 0n,
          satsPaid: 50n,
          bitcoinFeeSats: 5n,
          reimbursementWei: 500n,
          gasSpentWei: 10n,
          outcome: 'settled',
        },
      ],
      2n,
    );
    expect(pnl).toBe(500n - 55n * 2n - 10n);
  });
});
