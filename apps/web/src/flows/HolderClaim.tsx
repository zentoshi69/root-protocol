/**
 * The Bitcoin holder's claim/approval screen.
 *
 * The most security-sensitive surface in the product. Everything here exists to make one question
 * answerable before a signature happens: *exactly what am I authorising, and who gets paid?*
 *
 * Design rules this screen follows:
 *  - The raw canonical message is always shown, never hidden behind a "details" toggle. It is what
 *    gets signed; a summary is a courtesy, not a substitute.
 *  - The payout destination is displayed in full, never truncated. A truncated address is exactly
 *    what an address-swap attack hides behind.
 *  - The cold-wallet path is first-class, not a fallback. The whole point of the protocol is that
 *    the Puppet never moves, and most valuable Puppets live in cold storage.
 *  - An unsupported wallet is told so plainly. We never suggest importing a seed.
 */

import { useMemo, useState } from 'react';
import {
  buildMessage,
  renderHumanSummary,
  type AuthorizationMessageFields,
} from '@hoodpups/canonical-message';
import { formatEther, quote } from '@hoodpups/protocol-sdk';
import { HOLDER, REQUIRED_STATEMENTS, TRUST_MODEL } from '../copy.js';

export type SigningMethod = 'connected-wallet' | 'cold-wallet';

export interface HolderClaimProps {
  fields: AuthorizationMessageFields;
  /** True when the connected wallet can produce the required BIP-322 proof. */
  walletCanSign: boolean;
  /** Called with the proof the holder produced. */
  onSubmitProof: (proof: { signature: string; variant: 'simple' | 'full' }) => void;
  /** Relayer/attestor progress, if a proof is already in flight. */
  progress?: { matching: number; threshold: number; label: string } | undefined;
}

export function HolderClaim({ fields, walletCanSign, onSubmitProof, progress }: HolderClaimProps) {
  const [method, setMethod] = useState<SigningMethod>(walletCanSign ? 'connected-wallet' : 'cold-wallet');
  const [pastedSignature, setPastedSignature] = useState('');

  // Built once from the fields, and shown verbatim. If this render ever disagreed with what the
  // wallet signs, the whole "the terms I saw are the terms that execute" guarantee would be a lie.
  const message = useMemo(() => buildMessage(fields), [fields]);
  const summary = useMemo(() => renderHumanSummary(fields), [fields]);
  const split = useMemo(() => quote(fields.grossWei), [fields.grossWei]);

  const inscriptionId = `${fields.rootTxid}i${fields.rootIndex}`;

  return (
    <main className="holder-claim">
      <h1>{HOLDER.heading}</h1>

      <section className="assurance" aria-label="What this signature does">
        <p className="assurance__headline">{REQUIRED_STATEMENTS.puppetStays}</p>
        <p>{HOLDER.signingIntro}</p>
        <p className="assurance__warning">{HOLDER.neverSeed}</p>
      </section>

      <section aria-label="The Bitcoin Puppet">
        <h2>Your Bitcoin Puppet</h2>
        <dl>
          <dt>Inscription</dt>
          {/* Full value, never truncated — this is an identity the holder must be able to check. */}
          <dd className="mono">{inscriptionId}</dd>
          <dt>Currently held at</dt>
          <dd className="mono">
            {fields.currentOutpointTxid}:{fields.currentOutpointVout}
          </dd>
          <dt>Bitcoin network</dt>
          <dd>{fields.bitcoinNetwork}</dd>
        </dl>
      </section>

      <section aria-label="Payment terms">
        <h2>What you receive</h2>
        {fields.payoutMode === 'BTC' ? (
          <>
            <p className="amount">
              {fields.sellerSats.toLocaleString('en-US')} sats — native Bitcoin
            </p>
            <p>{REQUIRED_STATEMENTS.btcPayout}</p>
            <dl>
              <dt>Paid to script</dt>
              <dd className="mono">{fields.btcPayoutScriptHash}</dd>
            </dl>
          </>
        ) : fields.payoutMode === 'EVM' ? (
          <>
            <p className="amount">{formatEther(fields.sellerWei)} ETH</p>
            <p>{REQUIRED_STATEMENTS.ethPayout}</p>
            <dl>
              <dt>Paid to</dt>
              {/* Full address. Truncation is what an address-swap attack hides behind. */}
              <dd className="mono payout-address">{fields.evmPayout}</dd>
            </dl>
          </>
        ) : (
          <p className="amount">Free self-cast — no payment</p>
        )}

        {fields.grossWei > 0n && (
          <table className="split">
            <caption>How the buyer&apos;s {formatEther(fields.grossWei)} ETH is split</caption>
            <tbody>
              <tr>
                <th scope="row">You</th>
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
        )}
      </section>

      <section aria-label="Trust model">
        <h2>{TRUST_MODEL.heading}</h2>
        <p>{TRUST_MODEL.body}</p>
        <p>{TRUST_MODEL.notABridge}</p>
        <p>{REQUIRED_STATEMENTS.quorum}</p>
        <p>{REQUIRED_STATEMENTS.oneHoodPup}</p>
      </section>

      <section aria-label="Review before signing">
        <h2>Exactly what you are signing</h2>
        <p>{HOLDER.reviewBeforeSigning}</p>
        <pre className="summary">{summary}</pre>
        <details open>
          {/* Open by default: the raw message is the thing being signed, so hiding it would make the
              summary authoritative in the reader's mind, which it is not. */}
          <summary>Raw message ({message.length} bytes)</summary>
          <pre className="canonical-message mono">{message}</pre>
        </details>
      </section>

      {!walletCanSign && (
        <section aria-label="Wallet compatibility" className="warning">
          <h2>This wallet cannot sign</h2>
          <p>{HOLDER.unsupportedWallet}</p>
        </section>
      )}

      <section aria-label="Sign">
        <h2>Sign</h2>
        <fieldset>
          <legend>Signing method</legend>
          <label>
            <input
              type="radio"
              name="method"
              value="connected-wallet"
              checked={method === 'connected-wallet'}
              disabled={!walletCanSign}
              onChange={() => setMethod('connected-wallet')}
            />
            Connected wallet
          </label>
          <label>
            <input
              type="radio"
              name="method"
              value="cold-wallet"
              checked={method === 'cold-wallet'}
              onChange={() => setMethod('cold-wallet')}
            />
            Cold wallet / offline
          </label>
        </fieldset>

        {method === 'cold-wallet' ? (
          <div className="cold-wallet">
            <p>{HOLDER.coldWallet}</p>
            <button
              type="button"
              onClick={() => downloadSigningRequest(message, inscriptionId)}
            >
              Download signing request
            </button>
            <label htmlFor="signature">Paste the signature your device produced</label>
            <textarea
              id="signature"
              value={pastedSignature}
              onChange={(e) => setPastedSignature(e.target.value)}
              placeholder="base64 signature"
            />
            <button
              type="button"
              disabled={pastedSignature.trim().length === 0}
              onClick={() => onSubmitProof({ signature: pastedSignature.trim(), variant: 'simple' })}
            >
              Submit proof
            </button>
          </div>
        ) : (
          <button type="button" disabled={!walletCanSign} onClick={() => onSubmitProof({ signature: '', variant: 'simple' })}>
            Sign with connected wallet
          </button>
        )}
      </section>

      {progress && (
        <section aria-label="Verification progress">
          <h2>Verification</h2>
          <progress value={progress.matching} max={progress.threshold} />
          <p>{progress.label}</p>
        </section>
      )}
    </main>
  );
}

/**
 * Hand the holder the exact bytes to sign offline.
 *
 * Uses a Blob rather than embedding the message in a data URI so the file content is byte-identical
 * to what the verifier will check — URI encoding a message whose trailing LF is load-bearing is a
 * good way to produce a signature over subtly different bytes.
 */
export function downloadSigningRequest(message: string, inscriptionId: string): void {
  const blob = new Blob([message], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `hoodpups-signing-request-${inscriptionId.slice(0, 12)}.txt`;
  anchor.click();
  URL.revokeObjectURL(url);
}
