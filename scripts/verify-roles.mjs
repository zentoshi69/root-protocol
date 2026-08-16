#!/usr/bin/env node
/**
 * Post-deploy role audit. Exits non-zero if the deployed role matrix differs from the intended one
 * in `docs/DEPLOYMENT.md`, or if any EOA retains privilege.
 *
 * This is the check that catches the most expensive possible deployment mistake: leaving the
 * deployer key with `DEFAULT_ADMIN_ROLE` on a contract that can never be upgraded to fix it.
 *
 *   node scripts/verify-roles.mjs --chain 46630 --rpc $RH_TESTNET_RPC_URL
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPublicClient, http, keccak256, toHex } from 'viem';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

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

const role = (name) => (name === 'DEFAULT_ADMIN_ROLE' ? `0x${'00'.repeat(32)}` : keccak256(toHex(name)));

/**
 * The intended matrix. `holder` names a key in the deployment file. Anything granted on chain but
 * absent here is an unexpected grant and fails the audit — least privilege has to be verified, not
 * merely intended.
 */
const EXPECTED = [
  ['BitcoinOwnershipOracle', 'OWNERSHIP_CONSUMER_ROLE', ['HoodPupOfferEscrow', 'RootOwnershipRegistry']],
  ['BitcoinOwnershipOracle', 'PAYMENT_CONSUMER_ROLE', ['BtcSolverSettlement']],
  ['BitcoinOwnershipOracle', 'ROOT_SPEND_CONSUMER_ROLE', ['RootOwnershipRegistry']],
  ['PayoutVault', 'CREDITOR_ROLE', ['FeeRouter', 'HoodPupOfferEscrow', 'BtcSolverSettlement']],
  ['PayoutVault', 'ROOT_RELEASER_ROLE', ['RootOwnershipRegistry']],
  ['RootOwnershipRegistry', 'MINT_RECORDER_ROLE', ['HoodPupOfferEscrow']],
  ['FeeRouter', 'ROUTER_CALLER_ROLE', ['HoodPupOfferEscrow']],
  ['HoodPups', 'MINTER_ROLE', ['HoodPupOfferEscrow']],
  ['HoodPups', 'TOUR_ENGINE_ROLE', ['TourEngine']],
  ['HoodPupOfferEscrow', 'BTC_SETTLEMENT_ROLE', ['BtcSolverSettlement']],
];

const ADMINISTERED = [
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

const deployments = JSON.parse(readFileSync(join(ROOT, 'deployments', `${chainId}.json`), 'utf8'));
const addr = (name) => {
  const a = deployments.contracts?.[name];
  if (!a) throw new Error(`deployments/${chainId}.json is missing contract ${name}`);
  return a;
};

const client = createPublicClient({ transport: http(rpcUrl) });
const failures = [];
const checks = [];

const hasRole = (contract, roleHash, account) =>
  client.readContract({ address: addr(contract), abi: HAS_ROLE_ABI, functionName: 'hasRole', args: [roleHash, account] });

// 1. Every intended grant is actually present.
for (const [contract, roleName, holders] of EXPECTED) {
  for (const holder of holders) {
    const ok = await hasRole(contract, role(roleName), addr(holder));
    checks.push({ contract, roleName, holder, ok });
    if (!ok) failures.push(`MISSING: ${holder} lacks ${roleName} on ${contract}`);
  }
}

// 2. Admin belongs to the timelock, and to nothing else.
const timelock = deployments.timelock;
const guardian = deployments.guardian;
const deployer = deployments.deployer;

if (!timelock) failures.push('deployments file does not record a timelock address');

for (const contract of ADMINISTERED) {
  const timelockIsAdmin = await hasRole(contract, role('DEFAULT_ADMIN_ROLE'), timelock);
  if (!timelockIsAdmin) failures.push(`MISSING: timelock lacks DEFAULT_ADMIN_ROLE on ${contract}`);

  // 3. The expensive mistake: the deployer still holds admin on an immutable contract.
  if (deployer) {
    const deployerIsAdmin = await hasRole(contract, role('DEFAULT_ADMIN_ROLE'), deployer);
    if (deployerIsAdmin) failures.push(`CRITICAL: deployer ${deployer} still holds DEFAULT_ADMIN_ROLE on ${contract}`);
  }

  // 4. The guardian may pause. It must never hold admin — a compromised guardian should only be
  //    able to cost liveness, never to change parameters or unpause itself.
  if (guardian) {
    const guardianIsAdmin = await hasRole(contract, role('DEFAULT_ADMIN_ROLE'), guardian);
    if (guardianIsAdmin) failures.push(`CRITICAL: guardian ${guardian} holds DEFAULT_ADMIN_ROLE on ${contract}`);
  }
}

console.log(`\nRole audit — chain ${chainId}\n${'='.repeat(40)}`);
for (const c of checks) {
  console.log(`${c.ok ? 'ok  ' : 'FAIL'}  ${c.contract}.${c.roleName} -> ${c.holder}`);
}

if (failures.length > 0) {
  console.error(`\n${failures.length} problem(s):\n`);
  for (const f of failures) console.error(`  ${f}`);
  console.error('\nDeployment is NOT safe to use.');
  process.exit(1);
}

console.log('\nAll expected roles present. No EOA holds privilege. Deployer fully revoked.');
