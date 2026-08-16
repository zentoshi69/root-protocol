# CODEX CONTRACT PROMPT 08 — HOODPUPS ERC-721

Implement the HoodPups NFT as a rooted ERC-721 where each token permanently references exactly one canonical Bitcoin Puppet inscription.

## Contract

Create:

```text
contracts/src/HoodPups.sol
```

Use OpenZeppelin 5.x `ERC721`, `AccessControl`, and ERC-165. Implement the ERC-4907 user interface directly or through a small local extension. Do not use `ERC721Enumerable` or an upgradeable base.

## Core rules

- one root can mint at most one token;
- token IDs are sequential starting at 1;
- a token’s root identity is immutable;
- only `MINTER_ROLE` may mint;
- no public paid mint function exists here;
- no burn function in version one;
- no admin can remap or replace a root;
- normal transfers remain available even if minting is paused;
- ERC-4907 user state clears on transfer.

## State

Store:

```text
nextTokenId
rootKey -> tokenId
tokenId -> RootId
baseTokenURI
contractURI
metadataFrozen
mintingPaused
```

Use `0` as “not minted” because token IDs start at 1.

## Functions

Implement:

```text
mintRooted(address recipient, RootId root) -> uint256 tokenId
rootMinted(bytes32 rootKey) -> bool
tokenOfRoot(bytes32 rootKey) -> uint256
rootOf(uint256 tokenId) -> RootId
rootKeyOf(uint256 tokenId) -> bytes32
setBaseURI(string)
setContractURI(string)
freezeMetadata()
pauseMinting()
unpauseMinting()
```

Metadata setters and freeze must be timelocked admin operations. Once frozen, URI changes permanently revert.

## ERC-4907

Implement:

```text
setUser(uint256 tokenId, address user, uint64 expires)
userOf(uint256 tokenId)
userExpires(uint256 tokenId)
```

Owner or approved operator may set the user. Also support a narrow `TOUR_ENGINE_ROLE` so the protocol TourEngine can set users after validating tour rules.

When a token transfers between different owners, clear user and expiry and emit the ERC-4907 update event. Use the correct OpenZeppelin 5.x transfer hook/`_update` pattern rather than obsolete pre-v5 hooks.

## Metadata

Do not store every token URI individually. Build from base URI and token ID or root key. Include provenance fields in the off-chain metadata schema:

- Bitcoin inscription txid/index;
- root key;
- HoodPup token ID;
- verification disclaimer;
- current tour state from chain indexer.

The contract does not claim ownership of or custody over the Bitcoin inscription.

## Tests

Cover:

- authorized mint;
- unauthorized mint;
- one root only once;
- different inscription index produces different root;
- token ID sequencing;
- root lookup;
- safe mint to receiver;
- transferability;
- mint pause does not pause transfers;
- ERC-4907 set/user/expiry;
- transfer clears user;
- TourEngine role;
- metadata freeze irreversible;
- no enumerable interface advertised;
- supportsInterface values.

Add a stateful invariant that `rootToToken` is injective and no two token IDs map to the same root.

Run format, build, tests, invariants, and static analysis.
