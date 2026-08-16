/**
 * Robinhood Chain network definitions and per-chain deployed addresses.
 *
 * `assertSupportedChain` fails closed on an unknown chain id rather than defaulting to something.
 * A deploy or a settlement that silently succeeded against the wrong chain would be the most
 * expensive possible typo, and the type system will not catch it — a runtime guard has to.
 */

import type { Hex } from 'viem';

export const ROBINHOOD_MAINNET_CHAIN_ID = 4663;
export const ROBINHOOD_TESTNET_CHAIN_ID = 46630;
/** Anvil. Accepted only with an explicit local-development override. */
export const LOCAL_CHAIN_ID = 31337;

export interface ChainConfig {
  chainId: number;
  name: string;
  /** Native gas and settlement asset. Robinhood Chain uses ETH, not a bespoke token. */
  nativeCurrency: { name: string; symbol: string; decimals: number };
  bitcoinNetwork: 'mainnet' | 'testnet' | 'signet' | 'regtest';
  isProduction: boolean;
}

export const CHAINS: Record<number, ChainConfig> = {
  [ROBINHOOD_MAINNET_CHAIN_ID]: {
    chainId: ROBINHOOD_MAINNET_CHAIN_ID,
    name: 'Robinhood Chain',
    nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
    bitcoinNetwork: 'mainnet',
    isProduction: true,
  },
  [ROBINHOOD_TESTNET_CHAIN_ID]: {
    chainId: ROBINHOOD_TESTNET_CHAIN_ID,
    name: 'Robinhood Chain Testnet',
    nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
    bitcoinNetwork: 'testnet',
    isProduction: false,
  },
  [LOCAL_CHAIN_ID]: {
    chainId: LOCAL_CHAIN_ID,
    name: 'Local (Anvil)',
    nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
    bitcoinNetwork: 'regtest',
    isProduction: false,
  },
};

export class UnsupportedChainError extends Error {
  constructor(chainId: number) {
    super(
      `chain ${chainId} is not a HoodPups deployment target. ` +
        `Expected ${ROBINHOOD_MAINNET_CHAIN_ID} (mainnet), ${ROBINHOOD_TESTNET_CHAIN_ID} (testnet), ` +
        `or ${LOCAL_CHAIN_ID} with an explicit local override.`,
    );
    this.name = 'UnsupportedChainError';
  }
}

export function assertSupportedChain(chainId: number, allowLocal = false): ChainConfig {
  const config = CHAINS[chainId];
  if (!config) throw new UnsupportedChainError(chainId);
  if (chainId === LOCAL_CHAIN_ID && !allowLocal) throw new UnsupportedChainError(chainId);
  return config;
}

/** Addresses of the ten protocol contracts on one chain. */
export interface Deployment {
  chainId: number;
  puppetCollectionRegistry: Hex;
  bitcoinAttestorRegistry: Hex;
  bitcoinOwnershipOracle: Hex;
  payoutVault: Hex;
  rootOwnershipRegistry: Hex;
  feeRouter: Hex;
  hoodPups: Hex;
  hoodPupOfferEscrow: Hex;
  btcSolverSettlement: Hex;
  tourEngine: Hex;
  timelock: Hex;
  guardian: Hex;
  deployedAtBlock: bigint;
  commit: string;
}

/**
 * Populated from `deployments/<chainId>.json` at build time.
 *
 * Deliberately empty until a deployment exists. An SDK that shipped placeholder addresses would let
 * a caller send real value to an address nobody controls.
 */
export const DEPLOYMENTS: Partial<Record<number, Deployment>> = {};

export function getDeployment(chainId: number): Deployment {
  const d = DEPLOYMENTS[chainId];
  if (!d) {
    throw new Error(
      `no HoodPups deployment recorded for chain ${chainId}. ` +
        'Load deployments/<chainId>.json and register it before using the SDK against this chain.',
    );
  }
  return d;
}
