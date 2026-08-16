/**
 * Canonical types for the HoodPups BIP-322 authorization message.
 *
 * These mirror `contracts/src/types/PuppetTypes.sol` exactly. The numeric values are the on-chain
 * enum ordinals and must never be reordered — they are bound into the EIP-712 digest that five
 * independent attestors sign.
 */

/** Mirrors `PuppetTypes.AuthorizationPurpose`. Ordinals are load-bearing. */
export const AuthorizationPurpose = {
  PAID_EVM_MINT: 0,
  PAID_BTC_MINT: 1,
  SELF_CAST: 2,
  ROOT_BIND: 3,
  ROOT_INVALIDATE: 4,
} as const;

export type AuthorizationPurposeName = keyof typeof AuthorizationPurpose;
export type AuthorizationPurposeValue = (typeof AuthorizationPurpose)[AuthorizationPurposeName];

/** Mirrors `PuppetTypes.PayoutMode`. Ordinals are load-bearing. */
export const PayoutMode = {
  NONE: 0,
  EVM: 1,
  BTC: 2,
} as const;

export type PayoutModeName = keyof typeof PayoutMode;
export type PayoutModeValue = (typeof PayoutMode)[PayoutModeName];

/** Bitcoin networks this protocol will render a message for. */
export type BitcoinNetwork = 'mainnet' | 'testnet' | 'signet' | 'regtest';

/**
 * Which BIP-322 construction produced a proof.
 *
 * `simple` is the widely implemented variant. `full` and `proof_of_funds` give stronger binding to
 * specific UTXOs but have patchy hardware-wallet support. A variant is only accepted once the
 * verifier has passing tests for it against that script type — unsupported combinations are
 * rejected rather than guessed at.
 */
export type Bip322Variant = 'simple' | 'full' | 'proof_of_funds';

/** A 32-byte value as lowercase `0x`-prefixed hex. */
export type Hex32 = `0x${string}`;
/** A 20-byte EVM address as lowercase `0x`-prefixed hex. */
export type EvmAddress = `0x${string}`;
/** A Bitcoin txid as 64 lowercase hex chars, display order, NO `0x` prefix. */
export type BitcoinTxid = string;

/**
 * Every field a Bitcoin Puppet controller commits to when they sign.
 *
 * Nothing here is optional. A field that does not apply to the current purpose is rendered with its
 * canonical zero value rather than omitted, so the message shape is identical for every purpose and
 * a parser can never be confused by a missing line.
 */
export interface AuthorizationMessageFields {
  /** What this signature permits. Binds the signature to exactly one action. */
  purpose: AuthorizationPurposeName;
  /** Which Bitcoin network the inscription lives on. */
  bitcoinNetwork: BitcoinNetwork;

  /** Inscription reveal txid, display order, 64 lowercase hex, no prefix. */
  rootTxid: BitcoinTxid;
  /** Inscription index — the `iN` suffix. */
  rootIndex: number;

  /** Txid of the outpoint currently holding the inscription, display order. */
  currentOutpointTxid: BitcoinTxid;
  /** Output index of that outpoint. */
  currentOutpointVout: number;

  /** Robinhood Chain id: 4663 mainnet, 46630 testnet. */
  rhChainId: number;
  /** The escrow (or registry) contract that will consume this authorization. */
  verifyingContract: EvmAddress;

  /** Offer id for mint purposes; the root key for a `ROOT_BIND`. */
  contextId: Hex32;
  /** Commitment to every immutable term of the offer. */
  offerTermsHash: Hex32;

  /** Robinhood Chain address that escrowed the ETH. */
  buyer: EvmAddress;
  /** Robinhood Chain address that receives the HoodPup. */
  recipient: EvmAddress;

  /** How the controller elected to be paid. */
  payoutMode: PayoutModeName;
  /** Seller's Robinhood Chain payout address; zero address unless `payoutMode` is `EVM`. */
  evmPayout: EvmAddress;
  /** keccak256 of the seller's Bitcoin payout scriptPubKey; zero unless `payoutMode` is `BTC`. */
  btcPayoutScriptHash: Hex32;

  /** Exact satoshis the seller must receive; zero unless `payoutMode` is `BTC`. */
  sellerSats: bigint;
  /** Total wei escrowed by the buyer. */
  grossWei: bigint;
  /** Seller share in wei. */
  sellerWei: bigint;

  /** Unique per-authorization identifier. Non-zero, and never reused. */
  authorizationId: Hex32;
  /** Unix seconds after which this authorization is worthless. */
  expiresAt: number;
}

/** A parsed message plus the exact bytes it came from, so callers never re-render to compare. */
export interface ParsedAuthorizationMessage {
  fields: AuthorizationMessageFields;
  /** The exact string that was parsed, byte-for-byte. */
  raw: string;
  /** Message format version, currently always 1. */
  version: number;
}

/** Thrown for every rejection. Carries a stable machine-readable code. */
export class CanonicalMessageError extends Error {
  constructor(
    readonly code: CanonicalMessageErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'CanonicalMessageError';
  }
}

export type CanonicalMessageErrorCode =
  | 'BAD_HEADER'
  | 'BAD_LINE_ENDING'
  | 'TRAILING_WHITESPACE'
  | 'MISSING_FINAL_NEWLINE'
  | 'MISSING_FIELD'
  | 'UNKNOWN_FIELD'
  | 'DUPLICATE_FIELD'
  | 'FIELD_ORDER'
  | 'BAD_TXID'
  | 'BAD_HEX32'
  | 'BAD_ADDRESS'
  | 'BAD_UINT'
  | 'BAD_ENUM'
  | 'PAYOUT_SHAPE'
  | 'ZERO_AUTHORIZATION_ID';
