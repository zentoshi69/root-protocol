/**
 * @hoodpups/protocol-sdk
 *
 * Typed access to the HoodPups Rooted Settlement Protocol: canonical hashing, EIP-712 digests,
 * Merkle tooling, the fixed economics, and the offer/solver/relayer state machines.
 *
 * Two rules govern everything exported here:
 *
 * 1. **Nothing is silently normalised.** An invalid txid, address or amount is an explicit error.
 *    A helpful `.toLowerCase()` is how one component ends up hashing a different byte string than
 *    another, and that divergence means five independent attestors never reach quorum.
 * 2. **Every hash matches Solidity byte for byte**, verified in CI against golden vectors produced
 *    by running the Foundry suite.
 */

export * from './hashing.js';
export * from './validation.js';
export * from './eip712.js';
export * from './merkle.js';
export * from './economics.js';
export * from './stateMachines.js';
export * from './chains.js';

// The canonical BIP-322 message lives in its own package so the verifier and attestor services can
// depend on it without pulling in EVM client code.
export {
  buildMessage,
  parseMessage,
  messageBytes,
  renderHumanSummary,
  computeBip322ProofHash,
  normalizeProofBytes,
  MESSAGE_HEADER,
  MESSAGE_VERSION,
  FIELD_ORDER,
  type AuthorizationMessageFields,
  type Bip322Variant,
} from '@hoodpups/canonical-message';
