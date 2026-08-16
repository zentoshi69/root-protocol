/**
 * The TypeScript half of the protocol's hash contract.
 *
 * Every function here MUST produce byte-identical output to the Solidity function of the same name
 * in `contracts/src/types/PuppetHashing.sol`. `test/vectors.test.ts` asserts that against
 * `data/test-fixtures/hashing-vectors.json`, whose expected values were produced by running the
 * Foundry suite — not by hand-deriving them here and hoping.
 *
 * If a value in this file and the Solidity library ever disagree, five "independent" attestors
 * would compute five digests that the contract does not recognise, and nothing would ever settle.
 * CI fails the build on any divergence.
 */

import { encodeAbiParameters, keccak256, stringToBytes, type Hex } from 'viem';
import { assertBytes32, assertEvmAddress, assertUint } from './validation.js';

/*//////////////////////////////////////////////////////////////
                         DOMAIN CONSTANTS
//////////////////////////////////////////////////////////////*/

/**
 * Identifies this protocol deployment's canonical Bitcoin Puppets manifest.
 *
 * "Canonical" means canonical *to this deployment*. It is not an endorsement claim by the Bitcoin
 * Puppets project, and no UI copy may present it as one.
 */
export const COLLECTION_ID = keccak256(stringToBytes('BITCOIN_PUPPETS_MAINNET_V1'));

/** Keeps inscription-outpoint preimages disjoint from every other hash family. */
export const OUTPOINT_DOMAIN = keccak256(stringToBytes('HOODPUPS_BITCOIN_OUTPOINT_V1'));

/**
 * Deliberately distinct from `OUTPOINT_DOMAIN` even though both hash `(txid, vout)`.
 *
 * Without the separation, an inscription's outpoint hash and a consumed BTC payment output key
 * would be the same value, and consuming one could be made to look like consuming the other.
 */
export const PAYMENT_OUTPUT_DOMAIN = keccak256(stringToBytes('HOODPUPS_BITCOIN_PAYMENT_OUTPUT_V1'));

export const OFFER_TERMS_DOMAIN = keccak256(stringToBytes('HOODPUPS_OFFER_TERMS_V1'));
export const OFFER_ID_DOMAIN = keccak256(stringToBytes('HOODPUPS_OFFER_ID_V1'));

/*//////////////////////////////////////////////////////////////
                          IDENTITY HASHING
//////////////////////////////////////////////////////////////*/

/** A Bitcoin Puppet inscription's permanent identity. `inscriptionTxid` is in display order. */
export interface RootId {
  inscriptionTxid: Hex;
  inscriptionIndex: number;
}

/**
 * Canonical protocol key for one inscription.
 *
 * `inscriptionIndex` occupies its own 32-byte word, so two inscriptions sharing a reveal txid but
 * differing by index can never collide — a property the golden vectors assert explicitly.
 */
export function rootKey(root: RootId): Hex {
  assertBytes32(root.inscriptionTxid, 'inscriptionTxid');
  assertUint(root.inscriptionIndex, 'inscriptionIndex', 32);
  return keccak256(
    encodeAbiParameters(
      [{ type: 'bytes32' }, { type: 'bytes32' }, { type: 'uint32' }],
      [COLLECTION_ID, root.inscriptionTxid, root.inscriptionIndex],
    ),
  );
}

/**
 * Merkle leaf for the canonical collection tree — the `rootKey` hashed a second time.
 *
 * Double hashing follows the OpenZeppelin `StandardMerkleTree` convention: an internal node
 * preimage is 64 bytes, so it can never be presented as a 32-byte leaf. That is the second-preimage
 * defence, and skipping it would let an attacker prove membership of an internal node.
 */
export function collectionLeaf(rootKeyOrRoot: Hex | RootId): Hex {
  const key = typeof rootKeyOrRoot === 'string' ? rootKeyOrRoot : rootKey(rootKeyOrRoot);
  assertBytes32(key, 'rootKey');
  return keccak256(key);
}

/** Hash of the Bitcoin outpoint currently holding an inscription. */
export function outpointHash(bitcoinTxid: Hex, vout: number): Hex {
  assertBytes32(bitcoinTxid, 'bitcoinTxid');
  assertUint(vout, 'vout', 32);
  return keccak256(
    encodeAbiParameters(
      [{ type: 'bytes32' }, { type: 'bytes32' }, { type: 'uint32' }],
      [OUTPOINT_DOMAIN, bitcoinTxid, vout],
    ),
  );
}

/**
 * Global uniqueness key for a Bitcoin output used to pay a seller.
 *
 * Consuming this on chain is what stops one BTC payment from settling more than one offer.
 */
export function paymentOutputKey(bitcoinTxid: Hex, vout: number): Hex {
  assertBytes32(bitcoinTxid, 'bitcoinTxid');
  assertUint(vout, 'vout', 32);
  return keccak256(
    encodeAbiParameters(
      [{ type: 'bytes32' }, { type: 'bytes32' }, { type: 'uint32' }],
      [PAYMENT_OUTPUT_DOMAIN, bitcoinTxid, vout],
    ),
  );
}

/**
 * Hash of a raw Bitcoin `scriptPubKey`.
 *
 * Takes raw script bytes, never a bech32 or base58 address string. Address encodings are network-
 * and format-dependent; the script bytes are the actual thing that controls the coins.
 */
export function scriptHash(rawScriptPubKey: Hex | Uint8Array): Hex {
  if (rawScriptPubKey instanceof Uint8Array) return keccak256(rawScriptPubKey);
  if (!/^0x([0-9a-f]{2})+$/.test(rawScriptPubKey)) {
    throw new TypeError(
      `rawScriptPubKey must be 0x-prefixed lowercase hex with an even length, got ${rawScriptPubKey}`,
    );
  }
  return keccak256(rawScriptPubKey);
}

/*//////////////////////////////////////////////////////////////
                           OFFER HASHING
//////////////////////////////////////////////////////////////*/

/** Deterministic offer identifier, bound to chain + escrow + buyer so ids cannot collide. */
export function offerId(chainId: bigint | number, escrow: Hex, buyer: Hex, buyerNonce: bigint | number): Hex {
  assertEvmAddress(escrow, 'escrow');
  assertEvmAddress(buyer, 'buyer');
  return keccak256(
    encodeAbiParameters(
      [{ type: 'bytes32' }, { type: 'uint256' }, { type: 'address' }, { type: 'address' }, { type: 'uint256' }],
      [OFFER_ID_DOMAIN, BigInt(chainId), escrow, buyer, BigInt(buyerNonce)],
    ),
  );
}

export interface OfferTerms {
  chainId: bigint | number;
  escrow: Hex;
  offerId: Hex;
  /** `OfferKind` ordinal: 0 PAID_EVM, 1 PAID_BTC, 2 SELF_CAST. */
  kind: number;
  rootKey: Hex;
  buyer: Hex;
  recipient: Hex;
  grossWei: bigint;
  sellerWei: bigint;
  sellerSats: bigint;
  expiry: bigint | number;
}

/**
 * Immutable commitment to every fixed term of an offer.
 *
 * The Bitcoin controller signs this hash inside the canonical BIP-322 message. It is what makes
 * "the terms I was shown are the terms that execute" enforceable — change any bound field and every
 * signature already collected for that offer becomes worthless.
 */
export function offerTermsHash(t: OfferTerms): Hex {
  assertEvmAddress(t.escrow, 'escrow');
  assertEvmAddress(t.buyer, 'buyer');
  assertEvmAddress(t.recipient, 'recipient');
  assertBytes32(t.offerId, 'offerId');
  assertBytes32(t.rootKey, 'rootKey');
  assertUint(t.kind, 'kind', 8);

  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'uint256' },
        { type: 'address' },
        { type: 'bytes32' },
        { type: 'uint8' },
        { type: 'bytes32' },
        { type: 'address' },
        { type: 'address' },
        { type: 'uint256' },
        { type: 'uint256' },
        { type: 'uint64' },
        { type: 'uint64' },
      ],
      [
        OFFER_TERMS_DOMAIN,
        BigInt(t.chainId),
        t.escrow,
        t.offerId,
        t.kind,
        t.rootKey,
        t.buyer,
        t.recipient,
        t.grossWei,
        t.sellerWei,
        t.sellerSats,
        BigInt(t.expiry),
      ],
    ),
  );
}
