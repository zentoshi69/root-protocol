/**
 * EIP-712 attestation types, struct hashes and digests.
 *
 * Field order in every `TYPES` entry below MUST match `PuppetTypes.sol` exactly. It defines the
 * `encodeType` string, which defines the typehash, which defines what five independent attestors
 * sign. Reordering one field silently invalidates every signature in flight.
 *
 * ## What EIP-712 does and does not give you
 *
 * The domain binds `chainId` and `verifyingContract`, so a signature collected for one deployment
 * cannot be replayed against another. It provides **no replay protection within a deployment** —
 * that comes from `authorizationId`, `deadline`, and one-time digest consumption in
 * `BitcoinOwnershipOracle`. Conflating the two is a common and expensive mistake.
 */

import { encodeAbiParameters, hashTypedData, keccak256, type Hex, type TypedDataDomain } from 'viem';

/*//////////////////////////////////////////////////////////////
                              DOMAINS
//////////////////////////////////////////////////////////////*/

export const ORACLE_DOMAIN_NAME = 'HoodPups Bitcoin Oracle';
export const VAULT_DOMAIN_NAME = 'HoodPups PayoutVault';
export const DOMAIN_VERSION = '1';

export function oracleDomain(chainId: number, verifyingContract: Hex): TypedDataDomain {
  return { name: ORACLE_DOMAIN_NAME, version: DOMAIN_VERSION, chainId, verifyingContract };
}

export function payoutVaultDomain(chainId: number, verifyingContract: Hex): TypedDataDomain {
  return { name: VAULT_DOMAIN_NAME, version: DOMAIN_VERSION, chainId, verifyingContract };
}

/*//////////////////////////////////////////////////////////////
                            TYPE STRINGS
//////////////////////////////////////////////////////////////*/

export const OWNERSHIP_ATTESTATION_TYPE =
  'OwnershipAttestation(' +
  'uint8 purpose,bytes32 rootTxid,uint32 rootIndex,bytes32 contextId,bytes32 offerTermsHash,' +
  'bytes32 currentOutpointHash,bytes32 ownerScriptHash,bytes32 bip322ProofHash,address buyer,' +
  'address recipient,uint8 payoutMode,address evmPayout,bytes32 btcPayoutScriptHash,' +
  'uint64 sellerSats,uint256 grossWei,uint256 sellerWei,bytes32 bitcoinBlockHash,' +
  'uint64 bitcoinHeight,bytes32 authorizationId,uint64 deadline,uint64 attestorEpoch,' +
  'uint32 policyVersion)';

export const BITCOIN_PAYMENT_ATTESTATION_TYPE =
  'BitcoinPaymentAttestation(' +
  'bytes32 contextId,bytes32 ownershipDigest,address solver,bytes32 bitcoinTxid,' +
  'uint32 outputIndex,bytes32 recipientScriptHash,uint64 amountSats,bytes32 bitcoinBlockHash,' +
  'uint64 bitcoinHeight,bytes32 authorizationId,uint64 deadline,uint64 attestorEpoch,' +
  'uint32 policyVersion)';

export const ROOT_SPEND_ATTESTATION_TYPE =
  'RootSpendAttestation(' +
  'bytes32 rootTxid,uint32 rootIndex,bytes32 previousOutpointHash,bytes32 spendingTxid,' +
  'bytes32 bitcoinBlockHash,uint64 bitcoinHeight,bytes32 authorizationId,uint64 deadline,' +
  'uint64 attestorEpoch,uint32 policyVersion)';

export const WITHDRAWAL_TYPE =
  'Withdrawal(address beneficiary,address recipient,uint256 amount,uint256 nonce,uint64 deadline)';

export const OWNERSHIP_ATTESTATION_TYPEHASH = keccak256(new TextEncoder().encode(OWNERSHIP_ATTESTATION_TYPE));
export const BITCOIN_PAYMENT_ATTESTATION_TYPEHASH = keccak256(
  new TextEncoder().encode(BITCOIN_PAYMENT_ATTESTATION_TYPE),
);
export const ROOT_SPEND_ATTESTATION_TYPEHASH = keccak256(new TextEncoder().encode(ROOT_SPEND_ATTESTATION_TYPE));
export const WITHDRAWAL_TYPEHASH = keccak256(new TextEncoder().encode(WITHDRAWAL_TYPE));

/*//////////////////////////////////////////////////////////////
                          TYPED DATA SHAPES
//////////////////////////////////////////////////////////////*/

export const OWNERSHIP_ATTESTATION_TYPES = {
  OwnershipAttestation: [
    { name: 'purpose', type: 'uint8' },
    { name: 'rootTxid', type: 'bytes32' },
    { name: 'rootIndex', type: 'uint32' },
    { name: 'contextId', type: 'bytes32' },
    { name: 'offerTermsHash', type: 'bytes32' },
    { name: 'currentOutpointHash', type: 'bytes32' },
    { name: 'ownerScriptHash', type: 'bytes32' },
    { name: 'bip322ProofHash', type: 'bytes32' },
    { name: 'buyer', type: 'address' },
    { name: 'recipient', type: 'address' },
    { name: 'payoutMode', type: 'uint8' },
    { name: 'evmPayout', type: 'address' },
    { name: 'btcPayoutScriptHash', type: 'bytes32' },
    { name: 'sellerSats', type: 'uint64' },
    { name: 'grossWei', type: 'uint256' },
    { name: 'sellerWei', type: 'uint256' },
    { name: 'bitcoinBlockHash', type: 'bytes32' },
    { name: 'bitcoinHeight', type: 'uint64' },
    { name: 'authorizationId', type: 'bytes32' },
    { name: 'deadline', type: 'uint64' },
    { name: 'attestorEpoch', type: 'uint64' },
    { name: 'policyVersion', type: 'uint32' },
  ],
} as const;

export const BITCOIN_PAYMENT_ATTESTATION_TYPES = {
  BitcoinPaymentAttestation: [
    { name: 'contextId', type: 'bytes32' },
    { name: 'ownershipDigest', type: 'bytes32' },
    { name: 'solver', type: 'address' },
    { name: 'bitcoinTxid', type: 'bytes32' },
    { name: 'outputIndex', type: 'uint32' },
    { name: 'recipientScriptHash', type: 'bytes32' },
    { name: 'amountSats', type: 'uint64' },
    { name: 'bitcoinBlockHash', type: 'bytes32' },
    { name: 'bitcoinHeight', type: 'uint64' },
    { name: 'authorizationId', type: 'bytes32' },
    { name: 'deadline', type: 'uint64' },
    { name: 'attestorEpoch', type: 'uint64' },
    { name: 'policyVersion', type: 'uint32' },
  ],
} as const;

export const ROOT_SPEND_ATTESTATION_TYPES = {
  RootSpendAttestation: [
    { name: 'rootTxid', type: 'bytes32' },
    { name: 'rootIndex', type: 'uint32' },
    { name: 'previousOutpointHash', type: 'bytes32' },
    { name: 'spendingTxid', type: 'bytes32' },
    { name: 'bitcoinBlockHash', type: 'bytes32' },
    { name: 'bitcoinHeight', type: 'uint64' },
    { name: 'authorizationId', type: 'bytes32' },
    { name: 'deadline', type: 'uint64' },
    { name: 'attestorEpoch', type: 'uint64' },
    { name: 'policyVersion', type: 'uint32' },
  ],
} as const;

export const WITHDRAWAL_TYPES = {
  Withdrawal: [
    { name: 'beneficiary', type: 'address' },
    { name: 'recipient', type: 'address' },
    { name: 'amount', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint64' },
  ],
} as const;

/*//////////////////////////////////////////////////////////////
                             MESSAGES
//////////////////////////////////////////////////////////////*/

export interface OwnershipAttestation {
  purpose: number;
  rootTxid: Hex;
  rootIndex: number;
  contextId: Hex;
  offerTermsHash: Hex;
  currentOutpointHash: Hex;
  ownerScriptHash: Hex;
  bip322ProofHash: Hex;
  buyer: Hex;
  recipient: Hex;
  payoutMode: number;
  evmPayout: Hex;
  btcPayoutScriptHash: Hex;
  sellerSats: bigint;
  grossWei: bigint;
  sellerWei: bigint;
  bitcoinBlockHash: Hex;
  bitcoinHeight: bigint;
  authorizationId: Hex;
  deadline: bigint;
  attestorEpoch: bigint;
  policyVersion: number;
}

export interface BitcoinPaymentAttestation {
  contextId: Hex;
  ownershipDigest: Hex;
  solver: Hex;
  bitcoinTxid: Hex;
  outputIndex: number;
  recipientScriptHash: Hex;
  amountSats: bigint;
  bitcoinBlockHash: Hex;
  bitcoinHeight: bigint;
  authorizationId: Hex;
  deadline: bigint;
  attestorEpoch: bigint;
  policyVersion: number;
}

export interface RootSpendAttestation {
  rootTxid: Hex;
  rootIndex: number;
  previousOutpointHash: Hex;
  spendingTxid: Hex;
  bitcoinBlockHash: Hex;
  bitcoinHeight: bigint;
  authorizationId: Hex;
  deadline: bigint;
  attestorEpoch: bigint;
  policyVersion: number;
}

/*//////////////////////////////////////////////////////////////
                           STRUCT HASHING
//////////////////////////////////////////////////////////////*/

/**
 * EIP-712 `hashStruct` of an `OwnershipAttestation`.
 *
 * Solidity builds this as two concatenated `abi.encode` chunks to stay under the 16-slot stack
 * limit. Every field is a value type occupying exactly one word, so a single encode here is
 * byte-identical — asserted by the golden vectors rather than assumed.
 */
export function hashOwnershipStruct(a: OwnershipAttestation): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'uint8' },
        { type: 'bytes32' },
        { type: 'uint32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'address' },
        { type: 'address' },
        { type: 'uint8' },
        { type: 'address' },
        { type: 'bytes32' },
        { type: 'uint64' },
        { type: 'uint256' },
        { type: 'uint256' },
        { type: 'bytes32' },
        { type: 'uint64' },
        { type: 'bytes32' },
        { type: 'uint64' },
        { type: 'uint64' },
        { type: 'uint32' },
      ],
      [
        OWNERSHIP_ATTESTATION_TYPEHASH,
        a.purpose,
        a.rootTxid,
        a.rootIndex,
        a.contextId,
        a.offerTermsHash,
        a.currentOutpointHash,
        a.ownerScriptHash,
        a.bip322ProofHash,
        a.buyer,
        a.recipient,
        a.payoutMode,
        a.evmPayout,
        a.btcPayoutScriptHash,
        a.sellerSats,
        a.grossWei,
        a.sellerWei,
        a.bitcoinBlockHash,
        a.bitcoinHeight,
        a.authorizationId,
        a.deadline,
        a.attestorEpoch,
        a.policyVersion,
      ],
    ),
  );
}

export function hashBitcoinPaymentStruct(a: BitcoinPaymentAttestation): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'address' },
        { type: 'bytes32' },
        { type: 'uint32' },
        { type: 'bytes32' },
        { type: 'uint64' },
        { type: 'bytes32' },
        { type: 'uint64' },
        { type: 'bytes32' },
        { type: 'uint64' },
        { type: 'uint64' },
        { type: 'uint32' },
      ],
      [
        BITCOIN_PAYMENT_ATTESTATION_TYPEHASH,
        a.contextId,
        a.ownershipDigest,
        a.solver,
        a.bitcoinTxid,
        a.outputIndex,
        a.recipientScriptHash,
        a.amountSats,
        a.bitcoinBlockHash,
        a.bitcoinHeight,
        a.authorizationId,
        a.deadline,
        a.attestorEpoch,
        a.policyVersion,
      ],
    ),
  );
}

export function hashRootSpendStruct(a: RootSpendAttestation): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'uint32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'uint64' },
        { type: 'bytes32' },
        { type: 'uint64' },
        { type: 'uint64' },
        { type: 'uint32' },
      ],
      [
        ROOT_SPEND_ATTESTATION_TYPEHASH,
        a.rootTxid,
        a.rootIndex,
        a.previousOutpointHash,
        a.spendingTxid,
        a.bitcoinBlockHash,
        a.bitcoinHeight,
        a.authorizationId,
        a.deadline,
        a.attestorEpoch,
        a.policyVersion,
      ],
    ),
  );
}

export function hashWithdrawalStruct(
  beneficiary: Hex,
  recipient: Hex,
  amount: bigint,
  nonce: bigint,
  deadline: bigint,
): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'address' },
        { type: 'address' },
        { type: 'uint256' },
        { type: 'uint256' },
        { type: 'uint64' },
      ],
      [WITHDRAWAL_TYPEHASH, beneficiary, recipient, amount, nonce, deadline],
    ),
  );
}

/*//////////////////////////////////////////////////////////////
                              DIGESTS
//////////////////////////////////////////////////////////////*/

/**
 * Full EIP-712 digest an attestor signs.
 *
 * An attestor must compute this **itself**, from facts it verified itself. Signing a digest handed
 * over by a requester turns a 3-of-5 quorum into a 0-of-5, because the requester chooses what is
 * being attested. See `docs/ATTESTOR_POLICY.md`.
 */
export function ownershipDigest(chainId: number, oracle: Hex, a: OwnershipAttestation): Hex {
  return hashTypedData({
    domain: oracleDomain(chainId, oracle),
    types: OWNERSHIP_ATTESTATION_TYPES,
    primaryType: 'OwnershipAttestation',
    message: a,
  });
}

export function bitcoinPaymentDigest(chainId: number, oracle: Hex, a: BitcoinPaymentAttestation): Hex {
  return hashTypedData({
    domain: oracleDomain(chainId, oracle),
    types: BITCOIN_PAYMENT_ATTESTATION_TYPES,
    primaryType: 'BitcoinPaymentAttestation',
    message: a,
  });
}

export function rootSpendDigest(chainId: number, oracle: Hex, a: RootSpendAttestation): Hex {
  return hashTypedData({
    domain: oracleDomain(chainId, oracle),
    types: ROOT_SPEND_ATTESTATION_TYPES,
    primaryType: 'RootSpendAttestation',
    message: a,
  });
}

export function withdrawalDigest(
  chainId: number,
  vault: Hex,
  message: { beneficiary: Hex; recipient: Hex; amount: bigint; nonce: bigint; deadline: bigint },
): Hex {
  return hashTypedData({
    domain: payoutVaultDomain(chainId, vault),
    types: WITHDRAWAL_TYPES,
    primaryType: 'Withdrawal',
    message,
  });
}
