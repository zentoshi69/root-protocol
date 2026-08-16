import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { buildMessage, type AuthorizationMessageFields } from '@hoodpups/canonical-message';
import { HolderClaim } from '../src/flows/HolderClaim.js';

afterEach(cleanup);

const EVM_PAYOUT = '0x6666666666666666666666666666666666666666';

const fields = (over: Partial<AuthorizationMessageFields> = {}): AuthorizationMessageFields => ({
  purpose: 'PAID_EVM_MINT',
  bitcoinNetwork: 'mainnet',
  rootTxid: 'a'.repeat(64),
  rootIndex: 0,
  currentOutpointTxid: 'b'.repeat(64),
  currentOutpointVout: 1,
  rhChainId: 4663,
  verifyingContract: '0x1111111111111111111111111111111111111111',
  contextId: `0x${'22'.repeat(32)}`,
  offerTermsHash: `0x${'33'.repeat(32)}`,
  buyer: '0x4444444444444444444444444444444444444444',
  recipient: '0x5555555555555555555555555555555555555555',
  payoutMode: 'EVM',
  evmPayout: EVM_PAYOUT,
  btcPayoutScriptHash: `0x${'00'.repeat(32)}`,
  sellerSats: 0n,
  grossWei: 100_000_000_000_000_000n,
  sellerWei: 50_000_000_000_000_000n,
  authorizationId: `0x${'77'.repeat(32)}`,
  expiresAt: 1_786_870_800,
  ...over,
});

describe('the holder signing surface', () => {
  it('shows the raw canonical message verbatim, not just a summary', () => {
    // The raw message is what gets signed. A summary is a courtesy; presenting only the summary
    // would make it authoritative in the reader's mind, which it is not.
    render(<HolderClaim fields={fields()} walletCanSign onSubmitProof={() => {}} />);
    const raw = screen.getByText((_, el) => el?.className === 'canonical-message mono');
    expect(raw.textContent).toBe(buildMessage(fields()));
  });

  it('renders the payout address in full, never truncated', () => {
    // Truncation is exactly what an address-swap attack hides behind: 0x6666…6666 looks identical
    // whether or not the middle was changed.
    render(<HolderClaim fields={fields()} walletCanSign onSubmitProof={() => {}} />);
    const address = screen.getByText(EVM_PAYOUT);
    expect(address.textContent).toBe(EVM_PAYOUT);
    expect(address.textContent).not.toContain('…');
    expect(address.textContent).not.toContain('...');
  });

  it('states that the Puppet does not move, and that we never ask for a seed', () => {
    render(<HolderClaim fields={fields()} walletCanSign onSubmitProof={() => {}} />);
    expect(screen.getByText(/never leaves Bitcoin/i)).toBeTruthy();
    expect(screen.getByText(/never ask for your seed phrase/i)).toBeTruthy();
  });

  it('shows the exact 50/25/25 split of the buyer’s escrow', () => {
    render(<HolderClaim fields={fields()} walletCanSign onSubmitProof={() => {}} />);
    // The seller amount appears twice by design — once as the headline "what you receive", once in
    // the split table. Both are wanted; a holder should not have to hunt for it.
    expect(screen.getAllByText('0.05 ETH').length).toBeGreaterThanOrEqual(1);
    expect(screen.getAllByText('0.025 ETH')).toHaveLength(2); // treasury + protocol
  });

  it('offers the cold-wallet path even when a wallet can sign', () => {
    // Cold storage is the normal case for a valuable Puppet, so it is a first-class option rather
    // than a fallback surfaced only on failure.
    render(<HolderClaim fields={fields()} walletCanSign onSubmitProof={() => {}} />);
    expect(screen.getByLabelText(/Cold wallet/i)).toBeTruthy();
  });

  it('tells an incompatible wallet plainly instead of suggesting a seed import', () => {
    render(<HolderClaim fields={fields()} walletCanSign={false} onSubmitProof={() => {}} />);
    const notice = screen.getByText(/cannot produce the proof/i);
    expect(notice).toBeTruthy();
    expect(notice.textContent?.toLowerCase()).not.toContain('import');
    // And the cold-wallet path is preselected, since it is the only one that can work.
    expect((screen.getByLabelText(/Cold wallet/i) as HTMLInputElement).checked).toBe(true);
  });

  it('renders sats and the paying script for a BTC-mode offer', () => {
    const btc = fields({
      purpose: 'PAID_BTC_MINT',
      payoutMode: 'BTC',
      evmPayout: '0x0000000000000000000000000000000000000000',
      btcPayoutScriptHash: `0x${'88'.repeat(32)}`,
      sellerSats: 50_000n,
    });
    render(<HolderClaim fields={btc} walletCanSign onSubmitProof={() => {}} />);
    // Appears in the headline and again inside the human-readable summary block.
    expect(screen.getAllByText(/50,000 sats/).length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText(/native Bitcoin sent by a bonded solver/i)).toBeTruthy();
    expect(screen.getAllByText(`0x${'88'.repeat(32)}`).length).toBeGreaterThanOrEqual(1);
  });

  it('handles a free self-cast without inventing a payment', () => {
    const selfCast = fields({
      purpose: 'SELF_CAST',
      payoutMode: 'NONE',
      evmPayout: '0x0000000000000000000000000000000000000000',
      sellerSats: 0n,
      grossWei: 0n,
      sellerWei: 0n,
    });
    render(<HolderClaim fields={selfCast} walletCanSign onSubmitProof={() => {}} />);
    expect(screen.getByText(/Free self-cast/i)).toBeTruthy();
    expect(screen.queryByText(/How the buyer/i)).toBeNull();
  });

  it('exports a signing request whose bytes are exactly the message', async () => {
    // The trailing LF is load-bearing. A download path that URI-encoded the message would produce a
    // signature over subtly different bytes than the verifier checks.
    const captured: BlobPart[] = [];
    const OriginalBlob = globalThis.Blob;
    vi.stubGlobal(
      'Blob',
      class extends OriginalBlob {
        constructor(parts: BlobPart[], options?: BlobPropertyBag) {
          super(parts, options);
          captured.push(...parts);
        }
      },
    );
    vi.stubGlobal('URL', { ...URL, createObjectURL: () => 'blob:x', revokeObjectURL: () => {} });
    const clickSpy = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});

    const { downloadSigningRequest } = await import('../src/flows/HolderClaim.js');
    downloadSigningRequest(buildMessage(fields()), 'abc123i0');

    expect(captured[0]).toBe(buildMessage(fields()));
    expect(String(captured[0]).endsWith('\n')).toBe(true);

    clickSpy.mockRestore();
    vi.unstubAllGlobals();
  });
});
