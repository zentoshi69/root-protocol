/**
 * The buyer's offer-creation screen.
 *
 * Two things this screen must not soften:
 *  - the offer cannot be cancelled, and the reason why;
 *  - in BTC mode the buyer is fixing a quote with no price feed behind it, so a stale quote simply
 *    goes unfilled.
 *
 * Both are stated before the button, not in a footnote after it.
 */

import { useMemo, useState } from 'react';
import { formatBtc, formatEther, parseInscriptionId, quote, SdkValidationError } from '@hoodpups/protocol-sdk';
import { BUYER, REQUIRED_STATEMENTS } from '../copy.js';

export type PayoutChoice = 'EVM' | 'BTC';

export interface BuyerOfferProps {
  onCreate: (offer: {
    inscriptionId: string;
    recipient: string;
    grossWei: bigint;
    sellerSats: bigint;
    payout: PayoutChoice;
    expirySeconds: number;
  }) => void;
  /** Membership lookup against the manifest. Returns null while loading. */
  isInManifest: (inscriptionId: string) => boolean | null;
}

export function BuyerOffer({ onCreate, isInManifest }: BuyerOfferProps) {
  const [inscriptionId, setInscriptionId] = useState('');
  const [recipient, setRecipient] = useState('');
  const [ethAmount, setEthAmount] = useState('0.1');
  const [sats, setSats] = useState('50000');
  const [payout, setPayout] = useState<PayoutChoice>('EVM');
  const [days, setDays] = useState(7);

  // Parse rather than sanitise. An invalid id is surfaced as an error, never quietly corrected —
  // the SDK's whole contract is that nothing is silently normalised.
  const rootError = useMemo(() => {
    if (inscriptionId.trim() === '') return null;
    try {
      parseInscriptionId(inscriptionId.trim());
      return null;
    } catch (error) {
      return error instanceof SdkValidationError ? error.message : String(error);
    }
  }, [inscriptionId]);

  const membership = rootError === null && inscriptionId.trim() !== '' ? isInManifest(inscriptionId.trim()) : null;

  const grossWei = useMemo(() => parseEtherStrict(ethAmount), [ethAmount]);
  const split = useMemo(() => (grossWei === null ? null : quote(grossWei)), [grossWei]);
  const satsValue = useMemo(() => {
    if (!/^\d+$/.test(sats)) return null;
    return BigInt(sats);
  }, [sats]);

  const canSubmit =
    rootError === null &&
    membership === true &&
    recipient.trim() !== '' &&
    grossWei !== null &&
    grossWei > 0n &&
    (payout === 'EVM' || (satsValue !== null && satsValue > 0n));

  return (
    <main className="buyer-offer">
      <h1>{BUYER.heading}</h1>

      <section aria-label="Choose a Bitcoin Puppet">
        <label htmlFor="inscription">Bitcoin Puppet inscription id</label>
        <input
          id="inscription"
          value={inscriptionId}
          onChange={(e) => setInscriptionId(e.target.value)}
          placeholder="<64 hex>i0"
          aria-invalid={rootError !== null}
          aria-describedby={rootError ? 'inscription-error' : undefined}
        />
        {rootError && (
          <p id="inscription-error" role="alert" className="error">
            {rootError}
          </p>
        )}
        {membership === false && (
          <p role="alert" className="error">
            This inscription is not in the protocol manifest, so no HoodPup can be minted from it.
          </p>
        )}
        {membership === true && <p className="ok">In the protocol manifest.</p>}
      </section>

      <section aria-label="Recipient">
        <label htmlFor="recipient">Who receives the HoodPup (Robinhood Chain address)</label>
        <input id="recipient" value={recipient} onChange={(e) => setRecipient(e.target.value)} placeholder="0x…" />
      </section>

      <section aria-label="How the holder is paid">
        <h2>How should the Bitcoin holder be paid?</h2>
        <fieldset>
          <legend>Payout</legend>
          <label>
            <input type="radio" checked={payout === 'EVM'} onChange={() => setPayout('EVM')} />
            ETH on Robinhood Chain
          </label>
          <label>
            <input type="radio" checked={payout === 'BTC'} onChange={() => setPayout('BTC')} />
            Native BTC on Bitcoin
          </label>
        </fieldset>
        <p>{payout === 'EVM' ? REQUIRED_STATEMENTS.ethPayout : REQUIRED_STATEMENTS.btcPayout}</p>
      </section>

      <section aria-label="Amount">
        <label htmlFor="eth">You escrow (ETH)</label>
        <input id="eth" value={ethAmount} onChange={(e) => setEthAmount(e.target.value)} inputMode="decimal" />
        {grossWei === null && (
          <p role="alert" className="error">
            Enter a decimal ETH amount with at most 18 decimal places.
          </p>
        )}

        {payout === 'BTC' && (
          <>
            <label htmlFor="sats">The holder receives (satoshis, exact)</label>
            <input id="sats" value={sats} onChange={(e) => setSats(e.target.value)} inputMode="numeric" />
            {satsValue !== null && <p className="hint">{formatBtc(satsValue)} BTC</p>}
            <p className="notice">{BUYER.noOracle}</p>
            <p className="notice">{BUYER.btcModeRisk}</p>
          </>
        )}
      </section>

      {split && (
        <section aria-label="Split">
          <h2>How your ETH is split</h2>
          <p>{BUYER.splitExplainer}</p>
          <table className="split">
            <tbody>
              <tr>
                <th scope="row">{payout === 'BTC' ? 'Solver reimbursement' : 'Bitcoin Puppet holder'}</th>
                <td>{formatEther(split.seller)} ETH</td>
              </tr>
              <tr>
                <th scope="row">Bitcoin Puppets treasury</th>
                <td>{formatEther(split.puppetTreasury)} ETH</td>
              </tr>
              <tr>
                <th scope="row">Protocol</th>
                <td>{formatEther(split.protocol)} ETH</td>
              </tr>
            </tbody>
          </table>
        </section>
      )}

      <section aria-label="Expiry">
        <label htmlFor="expiry">Offer expires after</label>
        <select id="expiry" value={days} onChange={(e) => setDays(Number(e.target.value))}>
          <option value={1}>1 day</option>
          <option value={7}>7 days</option>
          <option value={30}>30 days</option>
        </select>
      </section>

      <section aria-label="Before you commit" className="notice notice--important">
        <h2>Before you commit</h2>
        <p>{BUYER.noCancel}</p>
        <p>{REQUIRED_STATEMENTS.oneHoodPup}</p>
        <p>{REQUIRED_STATEMENTS.puppetStays}</p>
      </section>

      <button
        type="button"
        disabled={!canSubmit}
        onClick={() =>
          onCreate({
            inscriptionId: inscriptionId.trim(),
            recipient: recipient.trim(),
            grossWei: grossWei!,
            sellerSats: payout === 'BTC' ? satsValue! : 0n,
            payout,
            expirySeconds: days * 24 * 60 * 60,
          })
        }
      >
        Escrow {grossWei !== null ? formatEther(grossWei) : '—'} ETH and open the offer
      </button>
    </main>
  );
}

/**
 * Parse a decimal ETH string into wei, exactly.
 *
 * Deliberately not `Number(x) * 1e18` — floating point cannot represent most decimal ETH values,
 * and a rounding error here would put an amount on chain that differs from what the buyer typed and
 * from what the holder is later asked to sign.
 *
 * @returns null for anything that is not a clean decimal with at most 18 places.
 */
export function parseEtherStrict(value: string): bigint | null {
  const match = /^(\d+)(?:\.(\d{1,18}))?$/.exec(value.trim());
  if (!match) return null;
  const [, whole, frac = ''] = match;
  return BigInt(whole!) * 10n ** 18n + BigInt(frac.padEnd(18, '0'));
}
