/**
 * Read-only Robinhood Chain access.
 *
 * The attestor reads the chain **itself**. Every offer term the requester claims is re-fetched from
 * the escrow contract and compared, so a lying requester produces a mismatch rather than a
 * signature.
 *
 * Deliberately read-only. An attestor has no business sending transactions; the relayer submits,
 * and it cannot alter what the attestors signed.
 */

import { createPublicClient, http, type Hex, type PublicClient } from 'viem';
import { reject, RejectionCode } from '@hoodpups/bitcoin-verifier';

/** Mirrors `PuppetTypes.Offer`. Field order matches the struct the escrow returns. */
export interface OnChainOffer {
  buyer: Hex;
  recipient: Hex;
  rootKey: Hex;
  rootTxid: Hex;
  rootIndex: number;
  grossWei: bigint;
  sellerWei: bigint;
  treasuryWei: bigint;
  protocolWei: bigint;
  sellerSats: bigint;
  createdAt: bigint;
  expiry: bigint;
  kind: number;
  status: number;
  termsHash: Hex;
  ownershipDigest: Hex;
  btcPayoutScriptHash: Hex;
  reservedSolver: Hex;
  reservationExpiry: bigint;
}

export interface RootStateView {
  epoch: bigint;
  active: boolean;
  currentOutpointHash: Hex;
  ownerScriptHash: Hex;
  beneficiary: Hex;
}

export interface ChainReader {
  quorumContext(): Promise<{ threshold: number; epoch: bigint; policyVersion: number }>;
  getOffer(offerId: Hex): Promise<OnChainOffer | null>;
  isRootMinted(rootKey: Hex): Promise<boolean>;
  isPaymentOutputConsumed(bitcoinTxid: string, outputIndex: number): Promise<boolean>;
  rootState(rootKey: Hex): Promise<RootStateView>;
  blockNumber(): Promise<bigint>;
}

const OFFER_TUPLE = {
  type: 'tuple',
  components: [
    { name: 'buyer', type: 'address' },
    { name: 'recipient', type: 'address' },
    { name: 'rootKey', type: 'bytes32' },
    { name: 'rootTxid', type: 'bytes32' },
    { name: 'rootIndex', type: 'uint32' },
    { name: 'grossWei', type: 'uint256' },
    { name: 'sellerWei', type: 'uint256' },
    { name: 'treasuryWei', type: 'uint256' },
    { name: 'protocolWei', type: 'uint256' },
    { name: 'sellerSats', type: 'uint64' },
    { name: 'createdAt', type: 'uint64' },
    { name: 'expiry', type: 'uint64' },
    { name: 'kind', type: 'uint8' },
    { name: 'status', type: 'uint8' },
    { name: 'termsHash', type: 'bytes32' },
    { name: 'ownershipDigest', type: 'bytes32' },
    { name: 'btcPayoutScriptHash', type: 'bytes32' },
    { name: 'reservedSolver', type: 'address' },
    { name: 'reservationExpiry', type: 'uint64' },
  ],
} as const;

const ESCROW_ABI = [
  { type: 'function', name: 'getOffer', stateMutability: 'view', inputs: [{ name: 'offerId', type: 'bytes32' }], outputs: [OFFER_TUPLE] },
] as const;

const ATTESTOR_REGISTRY_ABI = [
  {
    type: 'function',
    name: 'quorumContext',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'currentThreshold', type: 'uint8' },
      { name: 'epoch', type: 'uint64' },
      { name: 'policy', type: 'uint32' },
    ],
  },
] as const;

const HOODPUPS_ABI = [
  { type: 'function', name: 'rootMinted', stateMutability: 'view', inputs: [{ name: 'rootKey', type: 'bytes32' }], outputs: [{ type: 'bool' }] },
] as const;

const ORACLE_ABI = [
  {
    type: 'function',
    name: 'isPaymentOutputConsumed',
    stateMutability: 'view',
    inputs: [
      { name: 'bitcoinTxid', type: 'bytes32' },
      { name: 'outputIndex', type: 'uint32' },
    ],
    outputs: [{ type: 'bool' }],
  },
] as const;

const ROOT_REGISTRY_ABI = [
  {
    type: 'function',
    name: 'currentState',
    stateMutability: 'view',
    inputs: [{ name: 'rootKey', type: 'bytes32' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'epoch', type: 'uint64' },
          { name: 'active', type: 'bool' },
          { name: 'currentOutpointHash', type: 'bytes32' },
          { name: 'ownerScriptHash', type: 'bytes32' },
          { name: 'beneficiary', type: 'address' },
          { name: 'ownershipDigest', type: 'bytes32' },
          { name: 'bip322ProofHash', type: 'bytes32' },
          { name: 'verifiedBitcoinHeight', type: 'uint64' },
          { name: 'lastBitcoinBlockHash', type: 'bytes32' },
          { name: 'invalidatingSpendTxid', type: 'bytes32' },
        ],
      },
    ],
  },
] as const;

export interface ChainReaderConfig {
  rpcUrl: string;
  escrow: Hex;
  attestorRegistry: Hex;
  hoodPups: Hex;
  oracle: Hex;
  rootRegistry: Hex;
}

export class ViemChainReader implements ChainReader {
  readonly #client: PublicClient;

  constructor(private readonly config: ChainReaderConfig) {
    this.#client = createPublicClient({ transport: http(config.rpcUrl) }) as PublicClient;
  }

  /** Wrap RPC failures as an abstention. An attestor that cannot read the chain must not guess. */
  async #read<T>(fn: () => Promise<T>, what: string): Promise<T> {
    try {
      return await fn();
    } catch (error) {
      reject(RejectionCode.CHAIN_RPC_UNAVAILABLE, `could not read ${what} from Robinhood Chain`, {
        what,
        cause: error instanceof Error ? error.message : String(error),
      });
    }
  }

  async quorumContext() {
    const [threshold, epoch, policy] = await this.#read(
      () =>
        this.#client.readContract({
          address: this.config.attestorRegistry,
          abi: ATTESTOR_REGISTRY_ABI,
          functionName: 'quorumContext',
        }) as Promise<readonly [number, bigint, number]>,
      'attestor quorum context',
    );
    return { threshold, epoch, policyVersion: policy };
  }

  async getOffer(offerId: Hex): Promise<OnChainOffer | null> {
    const offer = (await this.#read(
      () =>
        this.#client.readContract({
          address: this.config.escrow,
          abi: ESCROW_ABI,
          functionName: 'getOffer',
          args: [offerId],
        }),
      `offer ${offerId}`,
    )) as OnChainOffer;
    // Status NONE means the id was never created. Returning null keeps "unknown offer" distinct
    // from "offer in a bad state", which are different rejections.
    return offer.status === 0 ? null : offer;
  }

  isRootMinted(rootKey: Hex): Promise<boolean> {
    return this.#read(
      () =>
        this.#client.readContract({
          address: this.config.hoodPups,
          abi: HOODPUPS_ABI,
          functionName: 'rootMinted',
          args: [rootKey],
        }) as Promise<boolean>,
      `mint status for ${rootKey}`,
    );
  }

  isPaymentOutputConsumed(bitcoinTxid: string, outputIndex: number): Promise<boolean> {
    const txid = (bitcoinTxid.startsWith('0x') ? bitcoinTxid : `0x${bitcoinTxid}`) as Hex;
    return this.#read(
      () =>
        this.#client.readContract({
          address: this.config.oracle,
          abi: ORACLE_ABI,
          functionName: 'isPaymentOutputConsumed',
          args: [txid, outputIndex],
        }) as Promise<boolean>,
      `payment output ${bitcoinTxid}:${outputIndex}`,
    );
  }

  async rootState(rootKey: Hex): Promise<RootStateView> {
    const state = (await this.#read(
      () =>
        this.#client.readContract({
          address: this.config.rootRegistry,
          abi: ROOT_REGISTRY_ABI,
          functionName: 'currentState',
          args: [rootKey],
        }),
      `root state for ${rootKey}`,
    )) as RootStateView;
    return state;
  }

  blockNumber(): Promise<bigint> {
    return this.#read(() => this.#client.getBlockNumber(), 'block number');
  }
}
