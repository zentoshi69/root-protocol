# Trust Assumptions

The single most important document in this repository. If a claim here conflicts with marketing
copy anywhere else, this document wins and the copy is wrong.

## The one-sentence version

**The Robinhood Chain settlement contracts are trustless once they receive an attestation, but the
cross-chain ownership verification trusts three of five Bitcoin verifier operators.**

## What the verifier quorum CAN do if it turns dishonest

A colluding majority (3 of 5) can:

1. **Assert a false ownership fact.** Claim that an inscription sits in a UTXO controlled by an
   attacker, causing a HoodPup to mint to the wrong recipient and the seller share to be credited
   to the wrong address.
2. **Assert a false BTC payment fact.** Claim a solver paid Bob when it did not, causing the solver
   to be reimbursed from Alice's escrow for a payment Bob never received.
3. **Assert a false root spend.** Claim Bob's inscription moved when it did not, deactivating his
   Root epoch and diverting *future* Root-linked value into the pending bucket until someone binds
   a new owner.
4. **Censor.** Refuse to attest anything, freezing new mints. Escrowed funds are still refundable
   at expiry, so censorship costs users time, not principal.

## What the verifier quorum CANNOT do, ever

1. **Move, spend, or encumber anyone's Bitcoin Puppet.** The protocol never holds a key, never
   receives a seed, and never requires the inscription to move. This is structural, not policy.
2. **Take money already credited in `PayoutVault`.** Credits are per-address balances with no admin
   path to reduce them.
3. **Mint a second HoodPup for a Root.** `rootMinted` is permanent and cannot be cleared by anyone,
   including the deployer.
4. **Reuse a Bitcoin payment output.** `paymentOutputKey` consumption is permanent and global.
5. **Replay a consumed attestation digest.** Consumption is permanent.
6. **Change the 50/25/25 split.** It is compiled into the bytecode with no setter.
7. **Redirect a seller's ETH payout.** The escrow pays the address inside the signed attestation
   and nothing else.

That asymmetry is the whole point of the design: the worst case is a bad mint and a bad payment,
not a stolen Bitcoin asset.

## The stale-watcher window

`RootOwnershipRegistry` records **attested** Bitcoin state, not live Bitcoin state.

When Bob sells his Puppet on Bitcoin, the registry keeps naming Bob until a watcher submits a
`RootSpendAttestation`. During that window, Root-linked value routed through `FeeRouter` goes to
Bob's `claimable` balance, not Charlie's.

Three things bound the damage:

- Only *recurring* Root-linked value is exposed. A new mint requires a fresh ownership proof, which
  a seller who no longer controls the inscription cannot produce.
- Once the epoch closes, future value accrues to `pendingByRoot[rootKey]` and releases to whoever
  next proves control — not to the stale beneficiary.
- Watchers are permissionless. Anyone, including Charlie, can submit the spend attestation. Charlie
  has the strongest possible incentive to do so promptly.

It is still a real window, it is unavoidable in an attested design, and the UI must say so.

## Trust in the manifest

`PuppetCollectionRegistry` commits to a Merkle root at deployment and can never change it. That
makes the manifest tamper-proof *after* deployment — it says nothing about whether the manifest was
correct *before*.

Therefore:

- The repository ships `data/bitcoin-puppets-mainnet.example.json`, an obviously fake example.
- **Production deployment fails closed** without a real manifest file.
- The launch gate requires the real manifest to be independently sourced and its Merkle root
  reproduced by at least two implementations before any mainnet deployment.
- "Canonical" in this codebase means *canonical to this protocol deployment*. It is not a claim of
  endorsement by the Bitcoin Puppets project, and no UI copy may imply otherwise.

## Trust in BIP-322 verification

The oracle does not verify BIP-322 — Solidity cannot. The verifier services do, off chain, and a
bug there is a bug in the quorum's inputs.

Mitigations that are required, not optional:

- BIP-322 dependencies are exact-pinned and wrapped behind a project-owned adapter, so swapping the
  library is a reviewed change rather than a lockfile drift.
- Verification must pass the official BIP-322 vectors *and* project-owned golden vectors before a
  proof is accepted.
- Only script types proven by tests are supported. Unsupported timelock or exotic scripts are
  **rejected**, not guessed at.
- A signature is never accepted merely because a wallet library returned `true`; defence-in-depth
  checks bind the signature to the exact script and outpoint.

## Trust in operator independence

The 3-of-5 threshold is only meaningful if the five operators are genuinely independent. Each
instance must have its **own** Bitcoin Core node, `ord` indexer, database, EVM signing key, network
endpoint and operator.

If all five read from one shared Ordinals API, the effective security is 1-of-1 wearing a
five-person costume. Deployment is gated on five genuinely independent operators being live.

## Trust in the relayer

The relayer is **not** trusted for correctness. It cannot modify terms; every field it submits is
covered by the attestor signatures, and any mutation invalidates the quorum. It is trusted only for
*liveness*: a censoring relayer delays settlement, and anyone can run another one.

## Trust in solvers

A solver is trusted for nothing. It posts a bond, pays Bob first, and is reimbursed only after
three verifiers attest the exact `txid:vout`. A solver that reserves and never pays loses its bond
to buyer compensation and the protocol. A solver can never receive reimbursement for a payment it
did not make unless the quorum lies about the payment.

## Administrative trust

- Core contracts are non-upgradeable. There is no key that can rewrite settlement logic.
- Administrative changes are designed for a multisig plus `TimelockController`, and the deployment
  script fails if the deployer retains privilege.
- A guardian may pause new risk-taking actions. Pausing can **never** block refunds, withdrawals,
  or terminal resolution of a BTC reservation whose solver may already have paid Bitcoin.
- There is no owner withdrawal function anywhere in the protocol. `sweepExcess` on `PayoutVault`
  can move only `balance - totalLiability`, which by construction is only force-sent ETH.

## What a fully trustless version would require

A Bitcoin light client on Robinhood Chain, plus proofs of an inscription's current Ordinals
location — realistically a zero-knowledge proof of the `ord` index. That is a genuine research
project and is the right long-term direction. It is also grotesquely overengineered for the first
777 green creatures, and shipping a slower, honest v1 beats shipping a v2 that does not exist.

## Language rules

Never write, and never let UI copy write:

- "trustless bridge" — it is neither
- "atomic swap" — the BTC leg is not atomic with the EVM leg
- "your Bitcoin is secured by the protocol" — the protocol never touches it
- "verified by Bitcoin" — it is verified by five operators *about* Bitcoin

Do write:

- "Your Bitcoin Puppet never leaves Bitcoin."
- "A 3-of-5 verifier quorum confirms ownership and BTC payments."
- "ETH payout is on Robinhood Chain. BTC payout is native Bitcoin sent by a bonded solver."
- "One verified HoodPup may be minted per protocol Root."
