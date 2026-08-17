# Deployment

> **No mainnet deployment happens from this repository until every launch gate below is green.**
> The mainnet script exists so it can be reviewed, simulated and audited. It is not executed.

## Networks

| Environment | Chain ID | RPC | Bitcoin |
|---|---|---|---|
| Local | 31337 (Anvil) | `http://127.0.0.1:8545` | regtest |
| Robinhood testnet | `46630` | `$RH_TESTNET_RPC_URL` | testnet/signet |
| Robinhood mainnet | `4663` | `$RH_MAINNET_RPC_URL` | mainnet |

Deployment scripts **refuse unknown chain IDs** unless `ALLOW_LOCAL_OVERRIDE=1` is set. A deploy
that silently succeeded against the wrong chain would be the most expensive possible typo.

## Preconditions

```
[ ] contracts/lib pinned to the vendored commits; no floating dependency
[ ] forge fmt --check, forge build, forge test all green
[ ] FOUNDRY_PROFILE=deep forge test green (long stateful campaigns)
[ ] Cross-language vector suite green (Solidity ↔ SDK ↔ verifier ↔ attestor)
[ ] Slither run, every finding triaged with a written reason
[ ] Gas snapshot committed
[ ] Real manifest present and its Merkle root independently reproduced (mainnet only)
[ ] TimelockController deployed, multisig proposers configured
[ ] Guardian multisig deployed
[ ] Five attestor addresses collected from five independent operators
[ ] Treasury addresses confirmed in writing by their owners
```

## Order

Dependency order — each contract's constructor needs the ones above it.

| # | Contract | Constructor inputs |
|---|---|---|
| 1 | `PuppetCollectionRegistry` | merkleRoot, manifestHash, manifestVersion, leafCount |
| 2 | `BitcoinAttestorRegistry` | admin, 5 attestors, threshold 3, policyVersion 1 |
| 3 | `BitcoinOwnershipOracle` | admin, collectionRegistry, attestorRegistry |
| 4 | `PayoutVault` | admin |
| 5 | `RootOwnershipRegistry` | admin, oracle, payoutVault |
| 6 | `FeeRouter` | admin, payoutVault, rootRegistry, puppetTreasury, protocolTreasury |
| 7 | `HoodPups` | admin, name, symbol, baseURI, contractURI |
| 8 | `HoodPupOfferEscrow` | admin, collectionRegistry, oracle, hoodPups, feeRouter, payoutVault, rootRegistry, min/max offer duration |
| 9 | `BtcSolverSettlement` | admin, escrow, oracle, payoutVault, minimumBondWei, reservationDuration, buyerSlashBps, protocolSlashRecipient |
| 10 | `TourEngine` | admin, hoodPups, season, duration bounds |

## Role grants

Least privilege. Every grant below is necessary; nothing beyond this list should exist.

| Role | On | Granted to | Why |
|---|---|---|---|
| `OWNERSHIP_CONSUMER_ROLE` | Oracle | Escrow, RootOwnershipRegistry | consume ownership attestations |
| `PAYMENT_CONSUMER_ROLE` | Oracle | BtcSolverSettlement | consume payment attestations |
| `ROOT_SPEND_CONSUMER_ROLE` | Oracle | RootOwnershipRegistry | consume spend attestations |
| `CREDITOR_ROLE` | PayoutVault | FeeRouter, Escrow, BtcSolverSettlement | credit payouts, refunds, bonds |
| `ROOT_RELEASER_ROLE` | PayoutVault | RootOwnershipRegistry | release pending Root balances |
| `MINT_RECORDER_ROLE` | RootOwnershipRegistry | Escrow | record the first ownership epoch on mint |
| `ROUTER_CALLER_ROLE` | FeeRouter | Escrow | route settlement value |
| `MINTER_ROLE` | HoodPups | Escrow | mint on settlement |
| `TOUR_ENGINE_ROLE` | HoodPups | TourEngine | set the ERC-4907 user |
| `BTC_SETTLEMENT_ROLE` | Escrow | BtcSolverSettlement | reserve / clear / finalize BTC offers |
| `PAUSER_ROLE` | all pausable | Guardian multisig | emergency pause only |
| `ATTESTOR_ADMIN_ROLE` | BitcoinAttestorRegistry | **TimelockController** | rotate the fixed five-member set and policy |
| `EXCESS_SWEEPER_ROLE` | PayoutVault | **TimelockController** | schedule/cancel excess-only recovery |
| `TREASURY_ADMIN_ROLE` | FeeRouter | **TimelockController** | update future treasury destinations |
| `METADATA_ADMIN_ROLE` | HoodPups | **TimelockController** | update/freeze metadata |
| `CONFIG_ADMIN_ROLE` | BtcSolverSettlement | **TimelockController** | update future solver economics |
| `TOUR_ADMIN_ROLE` | TourEngine | **TimelockController** | update future seasons and duration bounds |
| `DEFAULT_ADMIN_ROLE` | all nine AccessControl contracts | **TimelockController** | grant/revoke roles and unpause |

Note what is absent: no EOA holds anything, and the guardian can pause but never unpause.

`BTC_SETTLEMENT_ROLE` is a one-time binding, not a rotatable operator key. The first grant records
the deployed `BtcSolverSettlement` as the escrow's sole coordinator; the escrow rejects later
grants, revocation and renunciation so no active reservation can be stranded between two lifecycle
owners. Replacing that coordinator requires deploying a new escrow/solver pair after the old pair
has no active offers. `DeployLib.verifyRoles` checks both the role and the recorded coordinator.

## Handover — the step that actually matters

```
1. Reject zero, colliding, or EOA controller addresses
2. Grant DEFAULT_ADMIN_ROLE on all nine AccessControl contracts to TimelockController
3. Grant all six configuration/value-recovery roles to TimelockController
4. Grant PAUSER_ROLE on all seven pausable contracts to the guardian multisig
5. Renounce every constructor-granted deployer operational role
6. Renounce deployer DEFAULT_ADMIN_ROLE last
7. Replay RoleGranted/RoleRevoked events and compare exact holder sets with this matrix
```

Order is load-bearing. Revoking before granting bricks administration permanently, because there is
no recovery path. That absence is the point: a recovery path is a backdoor.

```bash
node scripts/verify-roles.mjs --chain "$CHAIN_ID" --rpc "$RPC_URL"
# exits non-zero for a chain mismatch, missing controller/contract code, a missing intended grant,
# an unexpected known-role holder, an unknown role hash, or any replay/hasRole disagreement
```

## Running it

```bash
# Local
anvil &
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

# Testnet — test keys only, never a key that holds real value
forge script script/Deploy.s.sol --rpc-url $RH_TESTNET_RPC_URL --broadcast --verify

# Mainnet — simulation only. Never --broadcast.
forge script script/Deploy.s.sol --rpc-url $RH_MAINNET_RPC_URL
```

Set `DEPLOY_COMMIT=$(git rev-parse HEAD)` before deployment. Output lands in
`deployments/<chainId>.json` with the contract/controller addresses, the replay start block, chain
id and exact commit. Foundry's broadcast receipt retains the transactions and constructor inputs.
The role verifier refuses a record without `deploymentBlock`; checking only current `hasRole`
values would not prove that the RPC returned a complete grant history.

## Post-deploy verification

```
[ ] Every address in deployments/<chainId>.json has code
[ ] Bytecode matches a local build at the recorded commit
[ ] Role matrix exactly matches the table above — no more, no less
[ ] Deployer holds nothing
[ ] attestorEpoch == 1, policyVersion == 1, threshold == 3, attestorCount == 5
[ ] merkleRoot matches the independently reproduced manifest root
[ ] FeeRouter treasuries are the confirmed addresses
[ ] SELLER_BPS/PUPPET_TREASURY_BPS/PROTOCOL_BPS read back 5000/2500/2500
[ ] Smoke test: create → attest → settle → withdraw, end to end
[ ] BtcSolverSettlement feature flag OFF
[ ] Block explorer verification submitted
```

## Launch gates — all must be green for mainnet

```
[ ] Real Bitcoin Puppets manifest independently sourced, and its Merkle root reproduced by at
    least two implementations
[ ] External security audit complete
[ ] Every high and critical finding fixed, with regression tests
[ ] Five genuinely independent verifier operators live, on independent infrastructure
[ ] Multisig and timelock live; deployer privilege revoked and verified
[ ] All I1–I17 protocol invariants (currently 62 executable `invariant_*` properties) passing
    under deep stateful fuzzing
[ ] BIP-322 verification passing official and wallet-specific vectors
[ ] Bitcoin regtest end-to-end flow passing
[ ] Robinhood testnet burn-in complete
[ ] Native BTC solver separately approved, and enabled only after that approval
[ ] Monitoring and alerting live per RUNBOOK.md
[ ] Bug bounty and a published disclosure contact
[ ] Incident response rehearsed, not just written
```

## Redeployment

Core contracts are immutable, so "upgrade" means "deploy v2 and migrate". Reuse what is still
correct — `PuppetCollectionRegistry` in particular, since its Merkle root cannot drift.

`PayoutVault` balances stay withdrawable from the **old** vault forever. There is no code path to
migrate them and there should not be. HoodPups minted by the old deployment remain the canonical
HoodPup for their Root, and a v2 `HoodPups` must respect that — otherwise one Root produces two
tokens and the protocol's central promise is broken by its own maintainers.
