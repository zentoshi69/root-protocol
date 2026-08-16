/**
 * `bip322-js` adapter.
 *
 * The ONLY place this repository touches a BIP-322 library. The dependency is exact-pinned at
 * 3.0.0 in `package.json`; bumping it is a reviewed change that must re-run the vector corpus.
 *
 * ## Honest capability statement
 *
 * bip322-js 3.0.0 verifies BIP-322 for **P2WPKH, P2SH-P2WPKH and single-key-spend P2TR**. It does
 * not verify P2WSH, and its P2PKH path is legacy BIP-137 rather than BIP-322 proper.
 *
 * `supportedScriptTypes` therefore lists only the three it can actually do. Bitcoin Puppets live on
 * P2TR, which is the case that matters — but a P2WSH holder gets an honest
 * `SCRIPT_TYPE_UNSUPPORTED` rather than a code path nobody tested. A user told "this wallet cannot
 * produce the required proof yet" is inconvenienced; a user whose Puppet is minted out from under
 * them by an untested code path is robbed.
 *
 * Script-key-path P2TR is also worth calling out: a Taproot output spendable only through a script
 * path cannot produce a single-key BIP-322 signature, and will be rejected by the library. That is
 * the correct outcome.
 */

import { Address, Verifier } from 'bip322-js';
import type { Bip322Adapter, Bip322VerifyRequest, SupportedScriptType } from '../bip322.js';
import { classifyScriptPubKey } from '../bip322.js';

export class Bip322JsAdapter implements Bip322Adapter {
  readonly name = 'bip322-js';
  readonly version = '3.0.0';

  /** Only what the library has passing vectors for. Deliberately shorter than `KNOWN_SCRIPT_TYPES`. */
  readonly supportedScriptTypes: readonly SupportedScriptType[] = ['p2tr', 'p2wpkh', 'p2sh-p2wpkh'];

  /**
   * Verify a BIP-322 signature.
   *
   * The message is passed as an explicit UTF-8 `Buffer` rather than a string. The canonical message
   * is pure ASCII so the two are equivalent today, but being explicit means a future non-ASCII
   * field cannot change the signed bytes through an encoding default nobody reviewed.
   *
   * Returns `false` rather than throwing on a malformed signature: an adapter that throws turns
   * "invalid signature" into "service error", which an attacker could use to force an honest
   * verifier to abstain and push the quorum toward whoever remains.
   */
  verify(request: Bip322VerifyRequest): boolean {
    try {
      return Verifier.verifySignature(
        request.address,
        Buffer.from(request.message, 'utf8'),
        request.signature,
        // Strict verification enforces the BIP-137 address flag. Enabled deliberately: a lenient
        // flag check accepts a signature whose recovery flag disagrees with the claimed address,
        // widening the set of addresses one signature appears valid for.
        true,
      );
    } catch {
      return false;
    }
  }

  /** Derive the scriptPubKey an address encodes, for the independent binding check. */
  scriptPubKeyForAddress(address: string, network: Bip322VerifyRequest['network']): string {
    if (!Address.isValidBitcoinAddress(address)) {
      throw new Error(`not a valid Bitcoin address: ${address}`);
    }

    // An address encodes its network in its prefix. A mainnet address supplied for a regtest
    // verification is a configuration error serious enough to fail loudly — silently accepting it
    // would let a testnet deployment verify mainnet claims, or worse, the reverse.
    const detected = Address.getNetworkFromAddess(address);
    const expectedBech32 = { mainnet: 'bc', testnet: 'tb', signet: 'tb', regtest: 'bcrt' }[network];
    if (detected.bech32 !== expectedBech32) {
      throw new Error(
        `address ${address} belongs to the ${detected.bech32} network but this verifier is configured for ${network} (${expectedBech32})`,
      );
    }

    return Address.convertAdressToScriptPubkey(address).toString('hex');
  }

  classifyScript(scriptPubKeyHex: string): SupportedScriptType | null {
    return classifyScriptPubKey(scriptPubKeyHex);
  }
}
