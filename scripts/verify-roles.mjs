#!/usr/bin/env node
/**
 * Post-deploy role audit. Replays every AccessControl grant/revocation from the recorded deployment
 * block, compares the resulting holder sets with the intended least-privilege matrix, and confirms
 * the same state with `hasRole` reads at the audit block.
 *
 *   node scripts/verify-roles.mjs --chain 46630 --rpc "$RH_TESTNET_RPC_URL"
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createPublicClient,
  getAddress,
  http,
  isAddressEqual,
  keccak256,
  parseAbiItem,
  toHex,
} from 'viem';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const ZERO_ADDRESS = `0x${'00'.repeat(20)}`;
const DEFAULT_ADMIN_ROLE = `0x${'00'.repeat(32)}`;
const LOG_CHUNK_SIZE = 10_000n;

const args = process.argv.slice(2);
const arg = (flag, fallback) => {
  const i = args.indexOf(flag);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};

const chainId = Number(arg('--chain', process.env.CHAIN_ID));
const rpcUrl = arg('--rpc', process.env.RPC_URL);

if (!chainId || !rpcUrl) {
  console.error('usage: verify-roles.mjs --chain <id> --rpc <url>');
  process.exit(2);
}

const role = (name) => (name === 'DEFAULT_ADMIN_ROLE' ? DEFAULT_ADMIN_ROLE : keccak256(toHex(name)));
const roleGranted = parseAbiItem(
  'event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender)',
);
const roleRevoked = parseAbiItem(
  'event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender)',
);

const deployments = JSON.parse(readFileSync(join(ROOT, 'deployments', `${chainId}.json`), 'utf8'));
const PROTOCOL_CONTRACTS = [
  'PuppetCollectionRegistry',
  'BitcoinAttestorRegistry',
  'BitcoinOwnershipOracle',
  'PayoutVault',
  'RootOwnershipRegistry',
  'FeeRouter',
  'HoodPups',
  'HoodPupOfferEscrow',
  'BtcSolverSettlement',
  'TourEngine',
];
const contractAddress = (name) => {
  const value = deployments.contracts?.[name];
  if (!value) throw new Error(`deployments/${chainId}.json is missing contract ${name}`);
  return getAddress(value);
};
const controllerAddress = (name) => {
  const value = deployments[name];
  if (!value) throw new Error(`deployments/${chainId}.json is missing ${name}`);
  return getAddress(value);
};
const holderAddress = (name) =>
  name === 'timelock' || name === 'guardian' || name === 'deployer'
    ? controllerAddress(name)
    : contractAddress(name);

/**
 * Every AccessControl role recognized by each protocol contract and its complete intended holder
 * set. Replaying events makes unexpected historical grants visible; the final `hasRole` reads
 * protect against a truncated/misconfigured RPC log response.
 */
const EXPECTED = {
  BitcoinAttestorRegistry: {
    DEFAULT_ADMIN_ROLE: ['timelock'],
    ATTESTOR_ADMIN_ROLE: ['timelock'],
  },
  BitcoinOwnershipOracle: {
    DEFAULT_ADMIN_ROLE: ['timelock'],
    OWNERSHIP_CONSUMER_ROLE: ['HoodPupOfferEscrow', 'RootOwnershipRegistry'],
    PAYMENT_CONSUMER_ROLE: ['BtcSolverSettlement'],
    ROOT_SPEND_CONSUMER_ROLE: ['RootOwnershipRegistry'],
    PAUSER_ROLE: ['guardian'],
  },
  PayoutVault: {
    DEFAULT_ADMIN_ROLE: ['timelock'],
    CREDITOR_ROLE: ['FeeRouter', 'HoodPupOfferEscrow', 'BtcSolverSettlement'],
    ROOT_RELEASER_ROLE: ['RootOwnershipRegistry'],
    EXCESS_SWEEPER_ROLE: ['timelock'],
    PAUSER_ROLE: ['guardian'],
  },
  RootOwnershipRegistry: {
    DEFAULT_ADMIN_ROLE: ['timelock'],
    MINT_RECORDER_ROLE: ['HoodPupOfferEscrow'],
    PAUSER_ROLE: ['guardian'],
  },
  FeeRouter: {
    DEFAULT_ADMIN_ROLE: ['timelock'],
    ROUTER_CALLER_ROLE: ['HoodPupOfferEscrow'],
    TREASURY_ADMIN_ROLE: ['timelock'],
  },
  HoodPups: {
    DEFAULT_ADMIN_ROLE: ['timelock'],
    MINTER_ROLE: ['HoodPupOfferEscrow'],
    TOUR_ENGINE_ROLE: ['TourEngine'],
    METADATA_ADMIN_ROLE: ['timelock'],
    PAUSER_ROLE: ['guardian'],
  },
  HoodPupOfferEscrow: {
    DEFAULT_ADMIN_ROLE: ['timelock'],
    BTC_SETTLEMENT_ROLE: ['BtcSolverSettlement'],
    PAUSER_ROLE: ['guardian'],
  },
  BtcSolverSettlement: {
    DEFAULT_ADMIN_ROLE: ['timelock'],
    CONFIG_ADMIN_ROLE: ['timelock'],
    PAUSER_ROLE: ['guardian'],
  },
  TourEngine: {
    DEFAULT_ADMIN_ROLE: ['timelock'],
    TOUR_ADMIN_ROLE: ['timelock'],
    PAUSER_ROLE: ['guardian'],
  },
};

const HAS_ROLE_ABI = [
  {
    type: 'function',
    name: 'hasRole',
    stateMutability: 'view',
    inputs: [
      { name: 'role', type: 'bytes32' },
      { name: 'account', type: 'address' },
    ],
    outputs: [{ type: 'bool' }],
  },
];

const client = createPublicClient({ transport: http(rpcUrl) });
const failures = [];
const checks = [];

const rpcChainId = await client.getChainId();
if (rpcChainId !== chainId) {
  failures.push(`CRITICAL: RPC reports chain ${rpcChainId}, expected ${chainId}`);
}
if (Number(deployments.chainId) !== chainId) {
  failures.push(`CRITICAL: deployment record reports chain ${deployments.chainId}, expected ${chainId}`);
}
if (typeof deployments.commit !== 'string' || !/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/iu.test(deployments.commit)) {
  failures.push('deployment record commit must be a full 40- or 64-character hexadecimal object ID');
}

const deploymentBlockRaw = deployments.deploymentBlock;
if (deploymentBlockRaw === undefined || deploymentBlockRaw === null) {
  failures.push('deployment record is missing deploymentBlock; exact grant replay is impossible');
}
const deploymentBlock = BigInt(deploymentBlockRaw ?? 0);
const auditBlock = await client.getBlockNumber();
if (deploymentBlock > auditBlock) {
  failures.push(`deploymentBlock ${deploymentBlock} is ahead of current block ${auditBlock}`);
}

const timelock = controllerAddress('timelock');
const guardian = controllerAddress('guardian');
const deployer = controllerAddress('deployer');
if (
  [timelock, guardian, deployer].some((address) => isAddressEqual(address, ZERO_ADDRESS)) ||
  isAddressEqual(timelock, guardian) ||
  isAddressEqual(timelock, deployer) ||
  isAddressEqual(guardian, deployer)
) {
  failures.push('CRITICAL: timelock, guardian and deployer must be distinct non-zero addresses');
}

for (const name of PROTOCOL_CONTRACTS) {
  if ((await client.getCode({ address: contractAddress(name), blockNumber: auditBlock })) === undefined) {
    failures.push(`CRITICAL: no code at ${name} (${contractAddress(name)})`);
  }
}
for (const [name, address] of [
  ['timelock', timelock],
  ['guardian', guardian],
]) {
  if ((await client.getCode({ address, blockNumber: auditBlock })) === undefined) {
    failures.push(`CRITICAL: ${name} ${address} is not a contract`);
  }
}

const hasRole = (contract, roleHash, account) =>
  client.readContract({
    address: contractAddress(contract),
    abi: HAS_ROLE_ABI,
    functionName: 'hasRole',
    args: [roleHash, account],
    blockNumber: auditBlock,
  });

const holderKey = (roleHash, account) => `${roleHash.toLowerCase()}:${account.toLowerCase()}`;

for (const [contract, expectedRoles] of Object.entries(EXPECTED)) {
  const knownRoleNames = new Map(Object.keys(expectedRoles).map((name) => [role(name).toLowerCase(), name]));
  const active = new Map();
  const logs = [];

  if (deploymentBlock <= auditBlock) {
    for (let fromBlock = deploymentBlock; fromBlock <= auditBlock; fromBlock += LOG_CHUNK_SIZE) {
      const toBlock = fromBlock + LOG_CHUNK_SIZE - 1n > auditBlock
        ? auditBlock
        : fromBlock + LOG_CHUNK_SIZE - 1n;
      logs.push(
        ...(await client.getLogs({
          address: contractAddress(contract),
          events: [roleGranted, roleRevoked],
          fromBlock,
          toBlock,
          strict: true,
        })),
      );
    }
  }

  logs.sort((a, b) => {
    const byBlock = Number((a.blockNumber ?? 0n) - (b.blockNumber ?? 0n));
    return byBlock !== 0 ? byBlock : Number((a.logIndex ?? 0) - (b.logIndex ?? 0));
  });

  for (const log of logs) {
    const roleHash = log.args.role.toLowerCase();
    const account = getAddress(log.args.account);
    const roleName = knownRoleNames.get(roleHash);
    if (!roleName) {
      failures.push(`UNEXPECTED: unknown role ${roleHash} appeared on ${contract} for ${account}`);
      continue;
    }
    const key = holderKey(roleHash, account);
    if (log.eventName === 'RoleGranted') active.set(key, { roleHash, roleName, account });
    else active.delete(key);
  }

  const expectedKeys = new Set();
  for (const [roleName, holderNames] of Object.entries(expectedRoles)) {
    const roleHash = role(roleName);
    for (const holderName of holderNames) {
      const account = holderAddress(holderName);
      const key = holderKey(roleHash, account);
      expectedKeys.add(key);

      const onChain = await hasRole(contract, roleHash, account);
      const inReplay = active.has(key);
      checks.push({ contract, roleName, holder: holderName, account, onChain, inReplay });
      if (!onChain) failures.push(`MISSING: ${holderName} lacks ${roleName} on ${contract}`);
      if (!inReplay) failures.push(`LOG MISMATCH: ${roleName} -> ${account} missing from ${contract} replay`);
    }
  }

  for (const [key, grant] of active) {
    if (!expectedKeys.has(key)) {
      failures.push(`UNEXPECTED: ${grant.account} holds ${grant.roleName} on ${contract}`);
    }
    if (!(await hasRole(contract, grant.roleHash, grant.account))) {
      failures.push(`LOG MISMATCH: replay says ${grant.account} holds ${grant.roleName} on ${contract}`);
    }
  }
}

console.log(`\nRole audit — chain ${chainId}, block ${auditBlock}\n${'='.repeat(56)}`);
for (const check of checks) {
  const ok = check.onChain && check.inReplay;
  console.log(
    `${ok ? 'ok  ' : 'FAIL'}  ${check.contract}.${check.roleName} -> ${check.holder} (${check.account})`,
  );
}

if (failures.length > 0) {
  console.error(`\n${failures.length} problem(s):\n`);
  for (const failure of failures) console.error(`  ${failure}`);
  console.error('\nDeployment is NOT safe to use.');
  process.exit(1);
}

console.log(
  '\nExact known-role holder sets match the documented matrix; deployer privileges are revoked.',
);
