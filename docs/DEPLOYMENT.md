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
| `DEFAULT_ADMIN_ROLE` | all | **TimelockController** | everything else |

Note what is absent: no EOA holds anything, and the guardian can pause but never unpause.

## Handover — the step that actually matters

```
1. Grant DEFAULT_ADMIN_ROLE to the TimelockController on every contract
2. Grant PAUSER_ROLE to the guardian multisig
3. Revoke DEFAULT_ADMIN_ROLE from the deployer on every contract
4. Verify — and fail the deploy if anything remains
```

Order is load-bearing. Revoking before granting bricks administration permanently, because there is
no recovery path. That absence is the point: a recovery path is a backdoor.

```bash
node scripts/verify-roles.mjs --chain $CHAIN_ID
# exits non-zero if any EOA holds any role, or the deployer retains privilege
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

Output lands in `deployments/<chainId>.json` with addresses, constructor arguments, the deployment
block, and the exact commit hash — everything needed to reproduce and verify the bytecode.

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
[ ] All 17 protocol invariants passing under deep stateful fuzzing
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
