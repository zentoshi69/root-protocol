/**
 * BIP-322 verification, behind a narrow project-owned adapter.
 *
 * ## Why an adapter rather than calling a library directly
 *
 * BIP-322 support across libraries and hardware wallets is uneven, and the failure mode is silent:
 * a library that returns `true` for a signature it did not actually bind to the claimed script
 * would let an attacker mint from someone else's Puppet. So:
 *
 * - the dependency is exact-pinned and reachable only through {@link Bip322Adapter};
 * - the adapter is validated against official BIP-322 vectors **and** project golden vectors before
 *   any proof is accepted — {@link assertAdapterValidated} enforces this at startup;
 * - only script types with passing tests are supported. Anything else is REJECTED, never guessed;
 * - a `true` from the library is not sufficient on its own. `verifyOwnershipSignature` independently
 *   re-derives the script the signature was checked against and compares it to the script the
 *   verifier read from `ord`/Bitcoin Core.
 *
 * That last point is the defence-in-depth the spec calls for. A library "verified the signature"
 * and "verified the signature *for this exact output's script*" are different claims, and only the
 * second one is what the protocol needs.
 */

import { reject, RejectionCode } from './errors.js';

/**
 * Every script type this codebase can *classify*.
 *
 * Classifying a script is not the same as being able to verify a signature against it. Which of
 * these an adapter will actually accept is declared per adapter in
 * {@link Bip322Adapter.supportedScriptTypes}, because that set is a property of the underlying
 * library, not an aspiration of this file.
 */
export const KNOWN_SCRIPT_TYPES = ['p2tr', 'p2wpkh', 'p2wsh', 'p2pkh', 'p2sh-p2wpkh'] as const;
export type SupportedScriptType = (typeof KNOWN_SCRIPT_TYPES)[number];

export type Bip322Variant = 'simple' | 'full' | 'proof_of_funds';

/** Variants accepted today. `proof_of_funds` binds a specific UTXO but has poor wallet support. */
export const SUPPORTED_VARIANTS: readonly Bip322Variant[] = ['simple', 'full'];

export interface Bip322VerifyRequest {
  /** Bech32/base58 address the wallet signed with. */
  address: string;
  /** Exact canonical message bytes, trailing LF included. */
  message: string;
  /** Signature as the wallet returned it (base64 or hex). */
  signature: string;
  variant: Bip322Variant;
  /** Raw scriptPubKey the verifier independently read for the inscription's output. */
  expectedScriptPubKeyHex: string;
  network: 'mainnet' | 'testnet' | 'signet' | 'regtest';
}

export interface Bip322Adapter {
  readonly name: string;
  readonly version: string;
  /**
   * Script types this adapter has passing vectors for.
   *
   * Declared by the adapter rather than assumed globally: a library that handles single-key P2TR
   * and P2WPKH but not P2WSH must say so, and the verifier must reject P2WSH rather than hand it to
   * a code path that was never tested.
   */
  readonly supportedScriptTypes: readonly SupportedScriptType[];
  /** Verify a signature. MUST NOT throw for an invalid signature — return false. */
  verify(request: Bip322VerifyRequest): boolean;
  /** Derive the scriptPubKey an address encodes, for independent binding checks. */
  scriptPubKeyForAddress(address: string, network: Bip322VerifyRequest['network']): string;
  /** Classify a raw scriptPubKey. Returns null for anything unrecognised. */
  classifyScript(scriptPubKeyHex: string): SupportedScriptType | null;
}

/*//////////////////////////////////////////////////////////////
                        SCRIPT CLASSIFICATION
//////////////////////////////////////////////////////////////*/

/**
 * Classify a raw scriptPubKey from its bytes.
 *
 * Implemented here rather than delegated, so classification does not depend on the same library
 * whose output we are cross-checking. Shapes:
 *
 *   p2tr        OP_1 (0x51) PUSH32 (0x20) <32 bytes>              — 34 bytes
 *   p2wpkh      OP_0 (0x00) PUSH20 (0x14) <20 bytes>              — 22 bytes
 *   p2wsh       OP_0 (0x00) PUSH32 (0x20) <32 bytes>              — 34 bytes
 *   p2pkh       OP_DUP OP_HASH160 PUSH20 <20> OP_EQUALVERIFY OP_CHECKSIG — 25 bytes
 *   p2sh        OP_HASH160 PUSH20 <20> OP_EQUAL                   — 23 bytes
 */
export function classifyScriptPubKey(scriptPubKeyHex: string): SupportedScriptType | null {
  const hex = scriptPubKeyHex.startsWith('0x') ? scriptPubKeyHex.slice(2) : scriptPubKeyHex;
  const lower = hex.toLowerCase();
  if (!/^([0-9a-f]{2})+$/.test(lower)) return null;

  if (lower.length === 68 && lower.startsWith('5120')) return 'p2tr';
  if (lower.length === 44 && lower.startsWith('0014')) return 'p2wpkh';
  if (lower.length === 68 && lower.startsWith('0020')) return 'p2wsh';
  if (lower.length === 50 && lower.startsWith('76a914') && lower.endsWith('88ac')) return 'p2pkh';
  // A bare P2SH could wrap anything. Only the P2SH-P2WPKH pattern is claimed here, and the caller
  // must still confirm the redeem script — which is why an unwrapped P2SH stays unsupported.
  if (lower.length === 46 && lower.startsWith('a914') && lower.endsWith('87')) return 'p2sh-p2wpkh';
  return null;
}

/*//////////////////////////////////////////////////////////////
                             VALIDATION
//////////////////////////////////////////////////////////////*/

export interface Bip322Vector {
  name: string;
  address: string;
  message: string;
  signature: string;
  variant: Bip322Variant;
  network: Bip322VerifyRequest['network'];
  expectedScriptPubKeyHex: string;
  shouldVerify: boolean;
  source: 'official' | 'project' | 'wallet';
}

export interface AdapterValidationResult {
  adapter: string;
  version: string;
  passed: number;
  failed: Array<{ name: string; expected: boolean; got: boolean | string }>;
}

/**
 * Run an adapter against a vector corpus.
 *
 * A failure here is a launch blocker, not a warning: an adapter that mis-verifies even one official
 * vector cannot be trusted with any of them.
 */
export function validateAdapter(adapter: Bip322Adapter, vectors: Bip322Vector[]): AdapterValidationResult {
  const failed: AdapterValidationResult['failed'] = [];
  let passed = 0;

  for (const v of vectors) {
    let got: boolean | string;
    try {
      got = adapter.verify({
        address: v.address,
        message: v.message,
        signature: v.signature,
        variant: v.variant,
        expectedScriptPubKeyHex: v.expectedScriptPubKeyHex,
        network: v.network,
      });
    } catch (error) {
      // An adapter that throws on a malformed signature instead of returning false is a bug: it
      // turns "invalid signature" into "service error", which an attacker can use to force a
      // verifier to abstain.
      got = `threw: ${error instanceof Error ? error.message : String(error)}`;
    }
    if (got === v.shouldVerify) passed++;
    else failed.push({ name: v.name, expected: v.shouldVerify, got });
  }

  return { adapter: adapter.name, version: adapter.version, passed, failed };
}

/** Throw unless every vector passes. Call this at service startup, before serving any request. */
export function assertAdapterValidated(adapter: Bip322Adapter, vectors: Bip322Vector[]): void {
  if (vectors.length === 0) {
    throw new Error(
      'refusing to start: no BIP-322 vectors supplied. An unvalidated adapter must never verify a ' +
        'real proof — a library that returns true for a signature it did not bind to the claimed ' +
        'script would let an attacker mint from someone else’s Puppet.',
    );
  }
  const result = validateAdapter(adapter, vectors);
  if (result.failed.length > 0) {
    throw new Error(
      `refusing to start: BIP-322 adapter ${result.adapter}@${result.version} failed ` +
        `${result.failed.length} of ${vectors.length} vectors: ` +
        result.failed.map((f) => `${f.name} (expected ${f.expected}, got ${f.got})`).join('; '),
    );
  }
}

/*//////////////////////////////////////////////////////////////
                        VERIFICATION ENTRY POINT
//////////////////////////////////////////////////////////////*/

/**
 * Verify an ownership signature with full binding checks.
 *
 * Order matters. The cheap structural rejections run first so a malformed request never reaches the
 * cryptography, and the script-binding check runs *around* the library rather than trusting it.
 */
export function verifyOwnershipSignature(adapter: Bip322Adapter, request: Bip322VerifyRequest): void {
  if (!SUPPORTED_VARIANTS.includes(request.variant)) {
    reject(
      RejectionCode.BIP322_VARIANT_UNSUPPORTED,
      `BIP-322 variant ${request.variant} is not supported by this verifier`,
      { variant: request.variant, supported: SUPPORTED_VARIANTS },
    );
  }

  const scriptType = classifyScriptPubKey(request.expectedScriptPubKeyHex);
  if (!scriptType) {
    // Rejecting an unrecognised script is a support ticket. Guessing at one is a stolen mint.
    reject(
      RejectionCode.SCRIPT_TYPE_UNSUPPORTED,
      'the output holding this inscription uses a script type this verifier cannot classify; ' +
        'unsupported and exotic scripts are rejected rather than guessed at',
      { scriptPubKey: request.expectedScriptPubKeyHex },
    );
  }
  if (!adapter.supportedScriptTypes.includes(scriptType)) {
    reject(
      RejectionCode.SCRIPT_TYPE_UNSUPPORTED,
      `this verifier's BIP-322 adapter has no passing vectors for ${scriptType}, so it will not ` +
        'verify signatures against it. The claim is not rejected as false — it cannot be checked.',
      { scriptType, supported: adapter.supportedScriptTypes, adapter: adapter.name },
    );
  }

  if (!request.message.endsWith('\n')) {
    reject(RejectionCode.MESSAGE_NOT_CANONICAL, 'message is not in canonical form: missing the trailing LF');
  }

  // Defence in depth #1: the address the wallet signed with must encode the exact script the
  // verifier independently read from the chain. Without this, a valid signature over a *different*
  // address the attacker controls would pass.
  let derived: string;
  try {
    derived = adapter.scriptPubKeyForAddress(request.address, request.network);
  } catch (error) {
    reject(RejectionCode.SCRIPT_BINDING_MISMATCH, 'could not derive a scriptPubKey from the signing address', {
      address: request.address,
      cause: error instanceof Error ? error.message : String(error),
    });
  }

  const normalize = (s: string) => (s.startsWith('0x') ? s.slice(2) : s).toLowerCase();
  if (normalize(derived) !== normalize(request.expectedScriptPubKeyHex)) {
    reject(
      RejectionCode.SCRIPT_BINDING_MISMATCH,
      'the signing address does not control the output holding this inscription',
      { derived: normalize(derived), expected: normalize(request.expectedScriptPubKeyHex) },
    );
  }

  // Defence in depth #2: only now consult the library.
  let valid: boolean;
  try {
    valid = adapter.verify(request);
  } catch (error) {
    reject(RejectionCode.BIP322_INVALID, 'BIP-322 verification raised an error', {
      cause: error instanceof Error ? error.message : String(error),
    });
  }

  if (!valid) {
    reject(RejectionCode.BIP322_INVALID, 'BIP-322 signature is not valid for this message and script', {
      scriptType,
      variant: request.variant,
    });
  }
}
