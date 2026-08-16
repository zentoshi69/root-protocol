/**
 * The immutable 50 / 25 / 25 split, mirrored from `FeeRouter.sol`.
 *
 * These are compile-time constants on chain with no setter and no upgrade path. This module exists
 * so a UI can show a holder exactly what they will receive **before** they sign — the numbers here
 * must match the contract's to the wei, or the message a holder approves would not describe what
 * executes.
 */

export const SELLER_BPS = 5000n;
export const PUPPET_TREASURY_BPS = 2500n;
export const PROTOCOL_BPS = 2500n;
export const BPS_DENOMINATOR = 10000n;

export interface Split {
  gross: bigint;
  seller: bigint;
  puppetTreasury: bigint;
  protocol: bigint;
}

/**
 * Split a gross amount exactly as `FeeRouter.quote` does.
 *
 * Seller and treasury are floor-divided; the protocol absorbs whatever remains. That ordering is
 * what makes `seller + puppetTreasury + protocol === gross` hold for **every** input including 1, 2
 * and 3 wei — three separate floor divisions would silently strand dust in the router forever.
 */
export function quote(gross: bigint): Split {
  if (gross < 0n) throw new RangeError(`gross must be non-negative, got ${gross}`);
  const seller = (gross * SELLER_BPS) / BPS_DENOMINATOR;
  const puppetTreasury = (gross * PUPPET_TREASURY_BPS) / BPS_DENOMINATOR;
  const protocol = gross - seller - puppetTreasury;
  return { gross, seller, puppetTreasury, protocol };
}

/** Assert conservation. Cheap enough to call on every quote a UI displays. */
export function assertConservation(split: Split): void {
  const sum = split.seller + split.puppetTreasury + split.protocol;
  if (sum !== split.gross) {
    throw new Error(`split does not conserve: ${split.seller}+${split.puppetTreasury}+${split.protocol} != ${split.gross}`);
  }
}

/** Exact decimal ETH. Never rounds — a rounded payout figure must never be shown to a signer. */
export function formatEther(wei: bigint): string {
  const negative = wei < 0n;
  const abs = negative ? -wei : wei;
  const whole = abs / 10n ** 18n;
  const frac = (abs % 10n ** 18n).toString().padStart(18, '0').replace(/0+$/, '');
  return `${negative ? '-' : ''}${whole}${frac ? `.${frac}` : ''}`;
}

/** Exact BTC from satoshis, always eight decimal places. */
export function formatBtc(sats: bigint): string {
  const negative = sats < 0n;
  const abs = negative ? -sats : sats;
  return `${negative ? '-' : ''}${abs / 100_000_000n}.${(abs % 100_000_000n).toString().padStart(8, '0')}`;
}
