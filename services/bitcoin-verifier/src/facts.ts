/**
 * Every hash and parser the verifier uses, re-exported from the shared packages.
 *
 * The verifier deliberately owns **no** hashing code of its own. Five independent operators plus
 * the SDK plus Solidity must agree byte-for-byte, and the only way to guarantee that is for there
 * to be exactly one implementation. A convenience helper defined here "just for the verifier" is
 * how that guarantee gets quietly broken.
 */

export type { Hex } from 'viem';

export {
  collectionLeaf,
  formatInscriptionId,
  formatOutpoint,
  outpointHash,
  parseInscriptionId,
  parseOutpoint,
  paymentOutputKey,
  rootKey,
  scriptHash,
  txidToBytes32,
  bytes32ToTxid,
  type RootId,
} from '@hoodpups/protocol-sdk';

export {
  buildMessage,
  computeBip322ProofHash,
  parseMessage,
  type AuthorizationMessageFields,
} from '@hoodpups/canonical-message';
