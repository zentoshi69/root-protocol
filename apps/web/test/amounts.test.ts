import { describe, expect, it } from 'vitest';
import { parseEtherStrict } from '../src/flows/BuyerOffer.js';

describe('parseEtherStrict never goes through a float', () => {
  it('parses exactly', () => {
    expect(parseEtherStrict('0.1')).toBe(100_000_000_000_000_000n);
    expect(parseEtherStrict('1')).toBe(10n ** 18n);
    expect(parseEtherStrict('0.000000000000000001')).toBe(1n);
    expect(parseEtherStrict('123.456')).toBe(123_456_000_000_000_000_000n);
  });

  it('handles values a float cannot represent', () => {
    // Number('0.1') * 1e18 is 100000000000000000 only by luck; 0.3 is not so lucky. An amount that
    // differs from what the buyer typed would also differ from what the holder is asked to sign.
    expect(parseEtherStrict('0.1')! + parseEtherStrict('0.2')!).toBe(parseEtherStrict('0.3'));
    expect(parseEtherStrict('0.07')).toBe(70_000_000_000_000_000n);
  });

  it('rejects rather than rounding', () => {
    expect(parseEtherStrict('0.0000000000000000001')).toBeNull(); // 19 decimals
    expect(parseEtherStrict('1e18')).toBeNull();
    expect(parseEtherStrict('-1')).toBeNull();
    expect(parseEtherStrict('abc')).toBeNull();
    expect(parseEtherStrict('')).toBeNull();
    expect(parseEtherStrict('1,000')).toBeNull();
  });
});
