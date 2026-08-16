# Threat Model

Scope: the ten Robinhood Chain contracts, the four off-chain services, the canonical message
format, and the operational surface around them. Read alongside
[`TRUST_ASSUMPTIONS.md`](./TRUST_ASSUMPTIONS.md), which states what the system openly concedes.

Severity uses the usual scale: **Critical** = direct loss of user funds or a stolen Bitcoin asset;
**High** = loss of protocol funds, permanent unavailability, or a broken core invariant;
**Medium** = recoverable loss, griefing with a cost; **Low** = nuisance.

## Assets worth attacking

| Asset | Where it lives | Worst outcome |
|---|---|---|
| Alice's escrowed ETH | `HoodPupOfferEscrow` | stolen or permanently locked |
| Bob's credited ETH | `PayoutVault` | stolen or unwithdrawable |
| Solver bonds | `BtcSolverSettlement` | stolen or wrongly slashed |
| Bob's Bitcoin Puppet | **Bitcoin, Bob's cold wallet** | *out of reach by construction* |
| The one-mint-per-Root guarantee | `HoodPups.rootMinted` | collection integrity destroyed |
| Attestor signing keys | five independent operators | false attestations |

Note the third row. The protocol never holds a Bitcoin key, never receives a seed, and never
requires the inscription to move. No compromise of any protocol component can move Bob's Puppet.

## Adversaries

- **A1 — Opportunistic on-chain attacker.** Reads calldata, front-runs, reenters, replays.
- **A2 — Malicious buyer.** Wants a HoodPup without paying, or wants to bait a signature.
- **A3 — Malicious seller.** Wants payment without genuinely controlling the inscription, or wants
  to sell the same Root twice.
- **A4 — Malicious solver.** Wants ETH reimbursement without paying BTC.
- **A5 — Compromised attestor (1 of 5).** Signs anything asked of it.
- **A6 — Colluding quorum (3 of 5).** The conceded trust boundary.
- **A7 — Compromised relayer.** Controls submission ordering and timing.
- **A8 — Malicious/compromised admin key.** Holds the timelock admin.
- **A9 — Bitcoin-layer attacker.** Reorgs, mempool manipulation, RBF, exotic scripts.

## Attack surface, by adversary

### A1 — On-chain attacker

| # | Attack | Severity | Mitigation |
|---|---|---|---|
| 1.1 | Reenter `PayoutVault.withdraw` via a malicious recipient | Critical | `ReentrancyGuard` + checks-effects-interactions: balance and `totalLiability` decrease *before* the external call. Tested with a re-entering receiver. |
| 1.2 | Reenter escrow settlement through an ERC-721 `onERC721Received` hook | Critical | `nonReentrant` on all settlement entry points; status flipped to `SETTLED` before the mint. |
| 1.3 | Front-run `consumeOwnership` to burn a valid authorization | High | Consumption is role-gated to protocol contracts. Public callers get `verify*` views only. |
| 1.4 | Replay a consumed attestation | Critical | Digest consumption is permanent and checked before any effect. |
| 1.5 | Reuse one Bitcoin payment output across offers | Critical | `paymentOutputKey` is consumed globally and permanently, in the same transaction as the digest. |
| 1.6 | Signature malleability — resubmit a high-`s` variant to dodge duplicate detection | High | `ECDSA.tryRecover` rejects high-`s`; duplicates are already impossible because recovered signers must be strictly ascending. |
| 1.7 | Grief by force-sending ETH to break an accounting equality | Medium | Every invariant is `balance >= liability`, never `==`. `sweepExcess` can move only the surplus. |
| 1.8 | Cross-deployment signature replay | Critical | EIP-712 domain binds `chainId` and `verifyingContract`; the offer terms hash binds chain and escrow address independently. Tested by deploying a second oracle and cross-submitting. |

### A2 — Malicious buyer

| # | Attack | Severity | Mitigation |
|---|---|---|---|
| 2.1 | Bait a BIP-322 signature, then cancel the offer and reuse the signature elsewhere | High | Buyers **cannot** cancel early. The signature is bound to `offerId` + `termsHash` + escrow + chain, so it is worthless anywhere else. |
| 2.2 | Create an offer, get it approved, then mutate terms | Critical | Terms are stored immutably at creation and re-checked field-by-field against the attestation at settlement. |
| 2.3 | Underfund an offer and still settle | High | `grossWei` is `msg.value` at creation; settlement asserts attestation `grossWei` equals stored gross. |
| 2.4 | Spam offers to lock a Root | Low | Competing offers are explicitly allowed; the first valid quorum wins and the rest become immediately refundable. Spam costs gas and locks only the spammer's own ETH. |
| 2.5 | Set an absurd expiry to trap funds or rush a signer | Medium | Expiry must fall inside a configured `[minimumOfferDuration, maximumOfferDuration]` window. |

### A3 — Malicious seller

| # | Attack | Severity | Mitigation |
|---|---|---|---|
| 3.1 | Claim an inscription they do not control | Critical | Verifiers check `ord` inscription location, Bitcoin Core unspent state, *and* a BIP-322 signature valid for that exact output script. All three, independently, five times. |
| 3.2 | Mint two HoodPups from one Puppet | Critical | `rootMinted[rootKey]` is permanent and uncleanable. Checked at creation *and* at settlement. Covered by a stateful invariant. |
| 3.3 | Sell the Puppet on Bitcoin, then settle an old offer | High | Verifiers check the UTXO is currently unspent and not being spent in the mempool at attestation time. |
| 3.4 | Keep receiving Root fees after selling | Medium | Ownership epochs. A spend attestation deactivates the Root and diverts future value to `pendingByRoot`. The residual stale-watcher window is disclosed. |
| 3.5 | Redirect an approved payout to a different address after signing | Critical | The payout address is inside the signed message and inside the attestation. The escrow pays that address and no other. |

### A4 — Malicious solver

| # | Attack | Severity | Mitigation |
|---|---|---|---|
| 4.1 | Reserve, never pay, keep the offer hostage | Medium | Anyone may `expireReservation` after the timeout; the bond is slashed to buyer compensation + protocol, and another solver may reserve. |
| 4.2 | Get reimbursed without paying BTC | Critical | Reimbursement requires a 3-of-5 payment attestation naming the exact `txid:vout`, script hash, sat amount and solver. |
| 4.3 | Pay a slightly wrong amount or a similar-looking output | High | The attestation binds the exact sat amount and the exact recipient script hash; the escrow re-checks both against the offer. Verifier tests explicitly cover "multiple outputs with similar amounts". |
| 4.4 | Have a relayer redirect its reimbursement | High | `settle` requires `msg.sender` to be the reserved solver *and* the attestation's named solver. |
| 4.5 | Front-run another solver's payment attestation | Medium | Only the actively reserved solver can settle; the payment output is single-use globally. |

### A5 — One compromised attestor

| # | Attack | Severity | Mitigation |
|---|---|---|---|
| 5.1 | Sign a false fact alone | — | Below threshold. Nothing happens. |
| 5.2 | Sign twice to fake quorum | Critical if unmitigated | Strictly-ascending recovered signers makes duplicates structurally impossible. |
| 5.3 | Sign a digest handed to it by a requester | High | Attestors must recompute the digest from independently verified facts. Blind digest signing is prohibited by design and by API shape. |
| 5.4 | Leak its key | High | Key rotation via `replaceAttestor` bumps the epoch, instantly invalidating every in-flight signature from the old set. See `KEY_ROTATION.md`. |

### A6 — Colluding 3-of-5 quorum

Conceded. See [`TRUST_ASSUMPTIONS.md`](./TRUST_ASSUMPTIONS.md). Damage is bounded to false mints
and false payment reimbursements; it can never reach Bob's Bitcoin, already-credited balances, the
fee split, or the one-mint-per-Root rule.

Reduction levers, in order of value: genuinely independent operators; published operator identities
and infrastructure attestations; a higher threshold as the set grows; a future Bitcoin light client
or ZK proof of the `ord` index.

### A7 — Compromised relayer

| # | Attack | Severity | Mitigation |
|---|---|---|---|
| 7.1 | Alter payout, recipient or amount | Critical if unmitigated | Every field is covered by the attestor signatures. Any mutation invalidates the quorum. |
| 7.2 | Censor a settlement until expiry | Medium | Relaying is permissionless; users or anyone else can submit. Escrow is refundable at expiry. |
| 7.3 | Submit duplicate transactions | Low | Idempotent submission plus one-time digest consumption. The second tx reverts. |

### A8 — Compromised admin

| # | Attack | Severity | Mitigation |
|---|---|---|---|
| 8.1 | Upgrade the contracts to steal funds | — | Non-upgradeable. No proxy, no `delegatecall`, no initializer. |
| 8.2 | Change the fee split | — | Compile-time constants, no setter. |
| 8.3 | Withdraw user balances | — | No such code path exists. `sweepExcess` is bounded to `balance - totalLiability`. |
| 8.4 | Point a treasury at an attacker address | Medium | Timelocked, publicly visible, and affects only *future* routing — already-credited balances are untouchable. |
| 8.5 | Pause to freeze user or solver funds | Medium | Refunds, withdrawals, active BTC finalization and terminal bond accounting remain live. Asserted by invariants and full-deployment tests. |
| 8.6 | Dilute 3-of-5 into 3-of-N | High | The set is fixed at exactly five; governance can only rotate one member atomically, and every rotation bumps the epoch. |

### A9 — Bitcoin-layer attacker

| # | Attack | Severity | Mitigation |
|---|---|---|---|
| 9.1 | Reorg away a payment that was already attested | High | Confirmation policy before attestation; `BITCOIN_REORG_RESPONSE.md` runbook; verifiers record the observed block hash and height in every attestation, so a reorg is detectable after the fact. |
| 9.2 | RBF-replace the solver's payment after attestation | High | Confirmation policy requires burial depth, not mempool presence. Verifiers explicitly check the mempool for conflicting spends. |
| 9.3 | Spend the inscription UTXO between verification and settlement | Medium | Mempool spend check plus a short attestation deadline. Residual risk is disclosed. |
| 9.4 | Exotic or timelocked script that a BIP-322 library mishandles | High | Only script types proven by tests are supported; everything else is rejected rather than guessed at. |
| 9.5 | Txid byte-order confusion between components | Critical | One canonical display order everywhere, enforced by cross-language golden vectors that fail CI on divergence. |

## Cross-cutting engineering mitigations

- **Custom errors everywhere**, so a failed settlement says *which* field mismatched.
- **Checks-effects-interactions** on every path that moves value.
- **Pull payments** rather than push, so a hostile payout address cannot block a mint.
- **Fail closed**: unknown chain IDs, missing manifests, unsupported script types and stale epochs
  all reject rather than degrade.
- **No `tx.origin`, no `selfdestruct`, no arbitrary `delegatecall`.**
- **Handler-based stateful invariant tests** for the seventeen protocol invariants listed in
  `build-kit/14_INTEGRATION_SECURITY_AND_DEPLOYMENT.md`.

## Known residual risks — accepted for v1, disclosed

1. The 3-of-5 quorum can lie about Bitcoin. *This is the design.*
2. The stale-watcher window between a real Bitcoin sale and its attestation.
3. Bitcoin reorg deeper than the configured confirmation policy.
4. BIP-322 library defects for script types outside the tested set.
5. Operator-independence is a social/operational property that code cannot enforce.
6. A HoodPup's link to its inscription is protocol-canonical, not an endorsement by the Bitcoin
   Puppets project.

Each of these must appear in user-facing copy in plain language, not buried in a footnote.
