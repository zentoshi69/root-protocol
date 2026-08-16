/**
 * `bip322ProofHash` — the deterministic commitment to a BIP-322 proof.
 *
 * The attestation carries this hash so the proof a verifier checked is permanently bound to the
 * authorization it approved. The chain never interprets it; it is emitted for auditability, so that
 * after the fact anyone can ask "which exact proof bytes did the quorum claim to have validated?"
 * and get a single answer.
 *
 * ## Normalisation, defined once
 *
 * ```
 * bip322ProofHash = keccak256(abi.encode(
 *     keccak256("HOODPUPS_BIP322_PROOF_V1"),
 *     keccak256(utf8(variant)),           // "simple" | "full" | "proof_of_funds"
 *     keccak256(proofBytes),              // raw proof bytes, base64-decoded if it arrived encoded
 *     keccak256(utf8(canonicalMessage))   // the exact signed message, including its trailing LF
 * ))
 * ```
 *
 * Three properties this buys:
 *
 * 1. **Variant binding.** A `simple` proof and a `full` proof over identical bytes hash
 *    differently, so a verifier cannot be tricked into checking one variant's rules against
 *    another's bytes.
 * 2. **Message binding.** The proof hash commits to the message. A proof lifted from one
 *    authorization cannot be presented against another.
 * 3. **Encoding neutrality.** Wallets return proofs as base64, hex, or raw bytes. All three
 *    normalise to the same value, so the hash describes the proof rather than its transport.
 *
 * Normalisation deliberately stops there. It does NOT re-serialise the witness stack, strip
 * padding, or canonicalise the signature's `s` value — any of which would let two materially
 * different proofs collide onto one hash.
 */

import { encodeAbiParameters, keccak256, stringToBytes, type Hex } from 'viem';
import { CanonicalMessageError, type Bip322Variant } from './types.js';

/** Domain tag. Must match the value used by every verifier and attestor. */
export const BIP322_PROOF_DOMAIN = keccak256(stringToBytes('HOODPUPS_BIP322_PROOF_V1'));

const VALID_VARIANTS: readonly Bip322Variant[] = ['simple', 'full', 'proof_of_funds'];

const BASE64_RE = /^[A-Za-z0-9+/]+={0,2}$/;
const HEX_RE = /^(0x)?[0-9a-fA-F]+$/;

/**
 * Decode a wallet-supplied proof into raw bytes.
 *
 * Accepts raw bytes, `0x`-prefixed hex, bare hex, or base64 — the four things wallets actually
 * return. Ambiguous input is an error, not a guess: a string that is valid in two encodings would
 * otherwise hash differently depending on which branch happened to run first.
 */
export function normalizeProofBytes(proof: Uint8Array | string): Uint8Array {
  if (proof instanceof Uint8Array) return proof;
  if (proof.length === 0) {
    throw new CanonicalMessageError('BAD_HEX32', 'proof bytes must not be empty');
  }

  // A 0x prefix is unambiguous, so honour it first.
  if (proof.startsWith('0x') || proof.startsWith('0X')) {
    const body = proof.slice(2);
    if (body.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(body)) {
      throw new CanonicalMessageError('BAD_HEX32', 'proof looked like hex but did not decode');
    }
    return hexToBytes(body);
  }

  const looksHex = HEX_RE.test(proof) && proof.length % 2 === 0;
  const looksBase64 = BASE64_RE.test(proof) && proof.length % 4 === 0;

  if (looksHex && looksBase64) {
    throw new CanonicalMessageError(
      'BAD_HEX32',
      'proof string is valid as BOTH hex and base64; supply a 0x prefix or raw bytes so the encoding is unambiguous',
    );
  }
  if (looksHex) return hexToBytes(proof);
  if (looksBase64) return base64ToBytes(proof);

  throw new CanonicalMessageError('BAD_HEX32', 'proof must be raw bytes, 0x-prefixed hex, bare hex, or base64');
}

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function base64ToBytes(b64: string): Uint8Array {
  return Uint8Array.from(Buffer.from(b64, 'base64'));
}

/**
 * Compute the `bip322ProofHash` bound into an `OwnershipAttestation`.
 *
 * @param variant Which BIP-322 construction produced the proof.
 * @param proof   The proof bytes as the wallet returned them.
 * @param canonicalMessage The exact message string that was signed, trailing LF included.
 */
export function computeBip322ProofHash(
  variant: Bip322Variant,
  proof: Uint8Array | string,
  canonicalMessage: string,
): Hex {
  if (!VALID_VARIANTS.includes(variant)) {
    throw new CanonicalMessageError('BAD_ENUM', `unknown BIP-322 variant ${JSON.stringify(variant)}`);
  }
  if (!canonicalMessage.endsWith('\n')) {
    throw new CanonicalMessageError(
      'MISSING_FINAL_NEWLINE',
      'canonicalMessage must be the exact signed bytes, including the trailing LF',
    );
  }

  const proofBytes = normalizeProofBytes(proof);

  return keccak256(
    encodeAbiParameters(
      [{ type: 'bytes32' }, { type: 'bytes32' }, { type: 'bytes32' }, { type: 'bytes32' }],
      [
        BIP322_PROOF_DOMAIN,
        keccak256(stringToBytes(variant)),
        keccak256(proofBytes),
        keccak256(stringToBytes(canonicalMessage)),
      ],
    ),
  );
}
