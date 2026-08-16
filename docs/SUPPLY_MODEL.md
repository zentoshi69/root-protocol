# Supply model — what determines how many HoodPups exist

This document exists because the question "what if the derivative collection is smaller than the
original?" had no answer anywhere in the codebase, and the answer is not obvious from reading the
contracts.

## The short answer

**HoodPups supply is emergent, not fixed.** Nothing anywhere caps it. There is no `maxSupply`, no
`MAX_MINT`, no counter compared against a limit. `HoodPups._nextTokenId` increments forever
(`contracts/src/HoodPups.sol:262`), and the only bound the code acknowledges is the comment on that
line: *"one mint per inscription, and the manifest is finite."*

Supply is therefore defined by exactly two things:

```
maximum possible supply  =  the number of leaves in the committed Merkle manifest
actual supply at time T  =  how many of those holders have chosen to claim by time T
```

The derivative is **almost always** smaller than the original collection, and that is the normal,
intended, permanent steady state — not a failure mode. Every Puppet whose holder has not claimed is
simply an unminted HoodPup. There is no deadline, no forfeiture, and no expiry on the right to
claim. A Puppet holder who claims three years from now gets their HoodPup on the same terms as one
who claimed on day one.

This is why there is no "unsold inventory" problem: **nothing is ever pre-minted.** A HoodPup comes
into existence only when a specific Puppet's owner proves ownership and settles. There is no
treasury holding unclaimed stock, no burn mechanic for leftovers, and no supply number that has to
be hit.

## Where the eligible set is fixed

`PuppetCollectionRegistry` commits one immutable Merkle root at construction, over the manifest of
eligible inscriptions. It has no admin, no owner, no role, no pause, and no upgrade path — the root
cannot be changed after deployment by anyone, including the deployer.

Membership is checked at the door. `HoodPupOfferEscrow._create` calls
`_COLLECTION_REGISTRY.requireMember(root, collectionProof)` **before** taking any money
(`contracts/src/HoodPupOfferEscrow.sol:860`), and that call reverts with `NotCollectionMember` for
anything outside the manifest (`contracts/src/PuppetCollectionRegistry.sol:212`).

That ordering is the important part: **an ineligible Puppet cannot lock funds.** The transaction
reverts before escrow is created, so there is never a case where someone pays and then discovers
they were not eligible.

## Three scenarios, and what actually happens

### 1. Fewer HoodPups than Puppets because holders haven't claimed

The default. Nothing special happens — this is the design. Supply grows monotonically as holders
claim, asymptotically approaching the manifest size and realistically never reaching it (lost keys,
dormant wallets, disinterested holders).

Anything that reports supply — marketplaces, the frontend, dashboards — must treat total supply as a
**moving number that only ever goes up**, never as a fixed denominator. Rarity calculations and
"N of M" displays that assume a fixed M will be wrong on day one and get more wrong over time.

Note that `HoodPups` deliberately does not implement `ERC721Enumerable`, so there is no on-chain
`totalSupply()` at all (`contracts/src/HoodPups.sol:515`). Consumers read supply from an indexer via
the `RootedMint` event. This is a deliberate gas trade, documented at that line, not an oversight.

### 2. Fewer HoodPups than Puppets because the manifest committed a subset

Supported today, with no code change. `manifestLeafCount` is a plain constructor argument
(`contracts/src/PuppetCollectionRegistry.sol:105`) and nothing on chain forces it to equal the true
size of Bitcoin Puppets. Committing a Merkle root over a subset produces a strictly smaller eligible
set, permanently.

Two consequences worth being deliberate about before choosing this:

- **The exclusion is permanent and not repairable in place.** There is no "add an inscription"
  function. Correcting a wrong manifest means deploying a new registry and migrating the protocol to
  it — a visible, reviewable event, by design.
- **The error message is unhelpful to the excluded.** A holder outside the subset gets
  `NotCollectionMember`, which is the same revert they would get from passing a malformed proof or
  from the frontend using a stale manifest. The chain cannot distinguish "you are deliberately not
  eligible" from "something is broken." That distinction has to be made in the frontend, by checking
  the published manifest before building the transaction and explaining the outcome in words.

### 3. A hard cap — "10,000 Puppets, only 3,333 HoodPups, first come first served"

**Not supported. This cannot be done with the contracts as they stand.**

`mintRooted` has no counter and no limit check. Every manifest member can mint, once, forever. The
only lever an operator has is `_mintingPaused` (`contracts/src/HoodPups.sol:233`), and using it to
simulate a cap is a trap.

It is a trap twice over, because **the pause is not even a complete stop.** The audit remediation
added `mintRootedTerminal` (`contracts/src/HoodPups.sol:242`), which carries no `_mintingPaused`
check by design: it exists so a BTC solver reservation whose solver may already have paid
irreversible Bitcoin can be finalized rather than stranded. The escrow reaches it through
`_mintTerminal` (`contracts/src/HoodPupOfferEscrow.sol:1055`). That is correct for its purpose — an
incident pause must not trap risk the protocol already accepted — but it means an operator pausing
at a supply target would still see mints land afterwards, in a quantity set by however many BTC
reservations happened to be live. A cap enforced this way is not a cap; it is a soft target with an
unbounded overshoot.

Beyond that, here is what pausing at the cap actually does, traced through the code:

1. Offers created before the pause still hold buyer ETH in escrow.
2. Settlement calls `mintRooted`, which reverts `MintingPaused`. The settlement fails.
3. The buyer's ETH is **not lost** — `refundExpired` is permissionless and carries no
   `whenNotPaused` modifier (`contracts/src/HoodPupOfferEscrow.sol:783`), and the vault's
   `creditRefund` is deliberately non-pausable — but it is **frozen until the offer's expiry**.
4. Who gets the last slot is decided by transaction ordering in the block where the pause lands.
   That is a validator-orderable race, not a fair queue.

So a pause-based cap does not steal anyone's money, but it does freeze an arbitrary set of buyers
for up to their full offer duration and awards the final mints by MEV. It is not an acceptable
mechanism for a launch.

## If you want a real hard cap

This needs a contract change, and it is a one-way door: `HoodPups` is non-upgradeable, so the cap
would have to be right at deployment. The design below is the one to use, and the reason is a
sequencing decision rather than an arithmetic one.

**Enforce the cap at offer creation, not at mint.**

The naive implementation checks a counter inside `mintRooted`. That puts the cap check *after* the
buyer's money is already escrowed, which recreates exactly the failure in scenario 3: pay, wait,
fail, wait for expiry, refund. It converts a supply limit into a fund-freezing mechanism.

Reserving a slot when the offer is created inverts this. The invariant becomes:

```
reservedSlots + mintedSupply  <=  MAX_SUPPLY
```

with a slot taken in `_create` and released on every refund path (`refundExpired`,
`refundUnfillable`, and the BTC reservation expiry paths). A buyer who successfully creates an offer
then holds a guaranteed claim on a slot for the life of that offer. The race moves to offer
creation, where losing costs a reverted transaction and a gas fee — instead of to settlement, where
losing costs a locked deposit and a wait.

Sketch, with the parts that are easy to get wrong called out:

```solidity
// In HoodPups: the cap itself, immutable, checked in the one mint path.
uint256 public immutable MAX_SUPPLY;

function mintRooted(...) external onlyRole(MINTER_ROLE) nonReentrant returns (uint256 tokenId) {
    // _nextTokenId starts at 1, so minted count is _nextTokenId - 1.
    if (_nextTokenId - 1 >= MAX_SUPPLY) revert SupplyExhausted(MAX_SUPPLY);
    ...
}

// In HoodPupOfferEscrow: slot accounting, so the cap is felt before money moves.
uint256 private _reservedSlots;

// in _create, after requireMember and before taking value:
if (_reservedSlots + _HOOD_PUPS.totalMinted() >= _HOOD_PUPS.MAX_SUPPLY()) revert SupplyExhausted();
unchecked { _reservedSlots += 1; }

// in _refund and in the settle path, exactly once each:
unchecked { _reservedSlots -= 1; }
```

Getting this right requires, at minimum:

- **A `totalMinted()` view on `HoodPups`.** The contract does not implement `ERC721Enumerable` and
  should not start; expose `_nextTokenId - 1` directly instead of inheriting an O(n) enumeration.
- **A decision about `mintRootedTerminal`, made explicitly.** There are now two mint entry points,
  and the sketch above only guards one of them. Putting the check in the shared `_mintRooted` helper
  covers both — but that would let a supply cap strand a BTC solver who has already paid irreversible
  Bitcoin, which is precisely the failure `mintRootedTerminal` was added to prevent. The honest
  resolution is that the terminal path must stay exempt and the *reservation* must consume its slot
  when it is created, so the cap is respected without the mint itself ever being the thing that
  refuses. Whichever way this goes, it has to be a deliberate choice: a cap that guards only
  `mintRooted` silently overshoots, and one that guards both silently strands solvers.
- **Releasing the slot on every exit path, exactly once.** Every terminal transition out of an open
  offer must decrement, and settlement must decrement too (the slot becomes a real mint). A missed
  decrement permanently shrinks usable supply; a double decrement underflows or oversells. This is
  the kind of accounting the existing handler-based stateful invariant suite is built to check —
  add `reservedSlots + totalMinted <= MAX_SUPPLY` as an invariant and let the fuzzer hunt it.
- **A dedicated `refundCapExhausted` path** if the cap can ever be hit while offers are live, so
  affected buyers are refunded immediately rather than waiting out their expiry.
- **A decision about self-casts.** Self-casting is free and is the holder exercising a right the
  protocol promised them. Should a free self-cast consume a capped slot, or should the cap apply
  only to paid mints? These are different products. Answer it explicitly rather than letting the
  implementation decide by accident.
- **Deciding what the cap means for the excluded.** A cap plus a full manifest means some holders
  who were told they were eligible will find they are not, after the fact. That is a materially
  worse outcome than a subset manifest, where exclusion is knowable up front. If the goal is a
  smaller collection, **scenario 2 is almost always the better instrument than scenario 3.**

## Recommendation

Prefer emergent supply (scenario 1) or a subset manifest (scenario 2). Both are supported today, and
both make eligibility knowable before anyone spends gas.

A hard cap (scenario 3) buys enforced scarcity at the cost of telling some manifest members, after
they already believed they qualified, that they no longer do. If scarcity is the goal, a smaller
manifest achieves it without ever putting two eligible holders in a race — and without adding
slot-accounting to the contract that holds everyone's money.
