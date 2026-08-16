# CODEX CONTRACT PROMPT 01 — SHARED TYPES, HASHING, AND INTERFACES

Act as a senior Solidity protocol engineer. Inspect the repository and implement the canonical shared type system for the HoodPups Rooted Settlement Protocol. Do not implement business contracts yet unless required to compile interfaces. Reuse existing conventions where safe.

## Files

Create or adapt:

```text
contracts/src/types/PuppetTypes.sol
contracts/src/types/PuppetHashing.sol
contracts/src/interfaces/IPuppetCollectionRegistry.sol
contracts/src/interfaces/IBitcoinAttestorRegistry.sol
contracts/src/interfaces/IBitcoinOwnershipOracle.sol
contracts/src/interfaces/IPayoutVault.sol
contracts/src/interfaces/IRootOwnershipRegistry.sol
contracts/src/interfaces/IFeeRouter.sol
contracts/src/interfaces/IHoodPups.sol
contracts/src/interfaces/IHoodPupOfferEscrow.sol
contracts/src/interfaces/IBtcSolverSettlement.sol
contracts/src/interfaces/ITourEngine.sol
```

## Canonical types

Define:

```solidity
struct RootId {
    bytes32 inscriptionTxid;
    uint32 inscriptionIndex;
}
```

Enums:

```text
OfferKind: PAID_EVM, PAID_BTC, SELF_CAST
OfferStatus: NONE, OPEN, BTC_APPROVED, BTC_RESERVED, SETTLED, REFUNDED
PayoutMode: NONE, EVM, BTC
AuthorizationPurpose: PAID_EVM_MINT, PAID_BTC_MINT, SELF_CAST, ROOT_BIND, ROOT_INVALIDATE
```

Define a flat `OwnershipAttestation` with fields in exactly this semantic order:

```text
uint8 purpose
bytes32 rootTxid
uint32 rootIndex
bytes32 contextId
bytes32 offerTermsHash
bytes32 currentOutpointHash
bytes32 ownerScriptHash
bytes32 bip322ProofHash
address buyer
address recipient
uint8 payoutMode
address evmPayout
bytes32 btcPayoutScriptHash
uint64 sellerSats
uint256 grossWei
uint256 sellerWei
bytes32 bitcoinBlockHash
uint64 bitcoinHeight
bytes32 authorizationId
uint64 deadline
uint64 attestorEpoch
uint32 policyVersion
```

Define a flat `BitcoinPaymentAttestation`:

```text
bytes32 contextId
bytes32 ownershipDigest
address solver
bytes32 bitcoinTxid
uint32 outputIndex
bytes32 recipientScriptHash
uint64 amountSats
bytes32 bitcoinBlockHash
uint64 bitcoinHeight
bytes32 authorizationId
uint64 deadline
uint64 attestorEpoch
uint32 policyVersion
```

Define a flat `RootSpendAttestation`:

```text
bytes32 rootTxid
uint32 rootIndex
bytes32 previousOutpointHash
bytes32 spendingTxid
bytes32 bitcoinBlockHash
uint64 bitcoinHeight
bytes32 authorizationId
uint64 deadline
uint64 attestorEpoch
uint32 policyVersion
```

Define an `Offer` view struct containing at least:

```text
address buyer
address recipient
bytes32 rootKey
bytes32 rootTxid
uint32 rootIndex
uint256 grossWei
uint256 sellerWei
uint256 treasuryWei
uint256 protocolWei
uint64 sellerSats
uint64 createdAt
uint64 expiry
uint8 kind
uint8 status
bytes32 termsHash
bytes32 ownershipDigest
bytes32 btcPayoutScriptHash
address reservedSolver
uint64 reservationExpiry
```

Use smaller integer widths only where they are safe and do not create opaque packing tricks.

## Canonical hashing

In `PuppetHashing.sol`, define:

```text
COLLECTION_ID = keccak256("BITCOIN_PUPPETS_MAINNET_V1")
rootKey = keccak256(abi.encode(COLLECTION_ID, inscriptionTxid, inscriptionIndex))
outpointHash = keccak256(abi.encode(bitcoinTxid, vout))
scriptHash = keccak256(rawScriptPubKeyBytes)
paymentOutputKey = keccak256(abi.encode(bitcoinTxid, vout))
```

Do not use `abi.encodePacked` for multi-field security identifiers.

Add pure functions for every hash and make the same formulas available in the TypeScript/Rust shared SDK later.

Define and expose exact EIP-712 type strings and type hashes for all three attestations. Do not allow each contract to silently invent a different field order.

## Interface requirements

Interfaces must expose only stable external behavior, not internal implementation details. Include:

- collection membership verification and root-key calculation;
- attestor membership, threshold, epoch, and policy version;
- oracle digest hashing, view verification, and one-time consumption;
- PayoutVault address/root crediting and withdrawal functions;
- root beneficiary lookup and epoch status;
- FeeRouter quote and routing functions;
- HoodPups mint and root uniqueness queries;
- escrow offer views and BTC lifecycle hooks;
- solver reservation/settlement views;
- tour start/check-in/finalization views.

## Tests

Create tests proving:

- Solidity root/outpoint/payment hashes match hard-coded golden vectors;
- no collision occurs between roots with the same txid and different indices;
- all EIP-712 type hashes are stable;
- ABI encoding matches equivalent TypeScript test vectors if a shared package already exists;
- all interfaces compile against mock implementations.

## Output requirements

Run format, build, and tests. Report exact files changed and any interface decision that differs from this prompt. Do not proceed to unrelated contracts.
