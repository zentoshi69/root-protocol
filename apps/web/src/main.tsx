import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

function PreReleaseApp() {
  return (
    <main className="status-card">
      <p className="eyebrow">deriv.wtf</p>
      <h1>Pre-release security build</h1>
      <p>
        No production contracts or off-chain services are configured. Do not send funds, sign an
        authorization, or treat this build as a live protocol.
      </p>
      <p>
        The reviewed buyer and holder flows are packaged as components while external audit,
        Bitcoin regtest end-to-end testing, testnet burn-in, production operators and key custody
        remain required launch gates.
      </p>
    </main>
  );
}

const container = document.getElementById('root');
if (container === null) throw new Error('missing application root');

createRoot(container).render(
  <StrictMode>
    <PreReleaseApp />
  </StrictMode>,
);
