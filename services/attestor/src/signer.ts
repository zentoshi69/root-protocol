/**
 * Attestor signing key abstraction.
 *
 * ## The one rule
 *
 * An attestor signs a digest it **computed itself, from facts it verified itself**. It never signs
 * a digest handed to it by a requester. That would turn a 3-of-5 quorum into a 0-of-5, because the
 * requester would be choosing what is attested.
 *
 * The API in `attest.ts` enforces this structurally: there is no code path that accepts a
 * `bytes32` and returns a signature. This module only exposes `signDigest`, and the only caller is
 * the attestation pipeline after it has finished verifying.
 *
 * ## Key custody
 *
 * Production keys live in an HSM or KMS. {@link LocalDevSigner} exists for regtest and CI only and
 * refuses to run against a production chain id — a development key that quietly worked on mainnet
 * would be the worst kind of convenience.
 */

import { privateKeyToAccount } from 'viem/accounts';
import type { Hex } from 'viem';

export interface AttestorSigner {
  /** The EVM address that must be a member of `BitcoinAttestorRegistry`. */
  readonly address: Hex;
  readonly kind: 'local-dev' | 'kms' | 'hsm';
  /** Sign a 32-byte EIP-712 digest. Callers must have computed it themselves. */
  signDigest(digest: Hex): Promise<Hex>;
}

const PRODUCTION_CHAIN_IDS = new Set([4663]);

/**
 * In-memory key signer. Development and CI only.
 *
 * @throws if pointed at a production chain. There is no flag to override this.
 */
export class LocalDevSigner implements AttestorSigner {
  readonly kind = 'local-dev' as const;
  readonly address: Hex;
  readonly #account: ReturnType<typeof privateKeyToAccount>;

  constructor(privateKey: Hex, chainId: number) {
    if (PRODUCTION_CHAIN_IDS.has(chainId)) {
      throw new Error(
        `refusing to use an in-memory development key on production chain ${chainId}. ` +
          'Production attestor keys must live in an HSM or KMS. There is no override.',
      );
    }
    this.#account = privateKeyToAccount(privateKey);
    this.address = this.#account.address;
  }

  async signDigest(digest: Hex): Promise<Hex> {
    // `sign` over a precomputed hash: the digest is already the full EIP-712 hash, so it must not
    // be re-wrapped in the personal_sign prefix.
    return this.#account.sign({ hash: digest });
  }

  /** Never log or serialise the key. Guard against an accidental `JSON.stringify(signer)`. */
  toJSON() {
    return { kind: this.kind, address: this.address };
  }
}

/**
 * Interface a KMS/HSM signer must satisfy.
 *
 * Deliberately identical to {@link AttestorSigner}: moving from a development key to an HSM must be
 * a configuration change, not a code change, or it will not happen before launch.
 */
export interface KmsSignerConfig {
  keyId: string;
  region?: string;
  /** Address derived from the KMS public key, verified at startup against the registry. */
  address: Hex;
}
