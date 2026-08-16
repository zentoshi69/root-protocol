import { describe, expect, it } from 'vitest';
import { allCopyStrings, BANNED_PHRASES, REQUIRED_STATEMENTS } from '../src/copy.js';

describe('product copy obeys the trust-assumption rules', () => {
  it('never uses a banned phrase', () => {
    // docs/TRUST_ASSUMPTIONS.md bans these outright. Keeping every string in one module makes the
    // rule enforceable rather than aspirational — a well-meaning edit fails here instead of shipping.
    for (const text of allCopyStrings()) {
      const lower = text.toLowerCase();
      for (const banned of BANNED_PHRASES) {
        expect(lower.includes(banned), `"${banned}" found in: ${text}`).toBe(false);
      }
    }
  });

  it('carries all five required statements verbatim', () => {
    expect(REQUIRED_STATEMENTS.puppetStays).toBe('Your Bitcoin Puppet never leaves Bitcoin.');
    expect(REQUIRED_STATEMENTS.quorum).toBe('A 3-of-5 verifier quorum confirms ownership and BTC payments.');
    expect(REQUIRED_STATEMENTS.ethPayout).toBe('ETH payout is on Robinhood Chain.');
    expect(REQUIRED_STATEMENTS.btcPayout).toBe('BTC payout is native Bitcoin sent by a bonded solver.');
    expect(REQUIRED_STATEMENTS.oneHoodPup).toBe('One verified HoodPup may be minted per protocol Root.');
  });

  it('never claims an endorsement by Bitcoin Puppets or Robinhood', () => {
    for (const text of allCopyStrings()) {
      const lower = text.toLowerCase();
      expect(lower).not.toMatch(/official|endorse|partnered with|in partnership/);
    }
  });

  it('never suggests importing a seed phrase', () => {
    const joined = allCopyStrings().join(' ').toLowerCase();
    expect(joined).toContain('never ask for your seed');
    expect(joined).not.toMatch(/import your (seed|wallet|private key)/);
  });
});
