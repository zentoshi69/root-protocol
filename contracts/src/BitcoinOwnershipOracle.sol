// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {IBitcoinAttestorRegistry} from "./interfaces/IBitcoinAttestorRegistry.sol";
import {IBitcoinOwnershipOracle} from "./interfaces/IBitcoinOwnershipOracle.sol";
import {IPuppetCollectionRegistry} from "./interfaces/IPuppetCollectionRegistry.sol";
import {PuppetHashing} from "./types/PuppetHashing.sol";
import {PuppetTypes} from "./types/PuppetTypes.sol";

/// @title BitcoinOwnershipOracle
/// @notice Turns a quorum of EIP-712 attestations into one-time-consumable Robinhood Chain
///         authorizations.
/// @dev TRUST BOUNDARY — READ THIS BEFORE READING ANY OTHER LINE IN THIS FILE.
///      This contract verifies SIGNATURES. It does not verify Bitcoin. It cannot read the Bitcoin
///      UTXO set, cannot evaluate a Bitcoin script, and cannot check a BIP-322 proof. Every Bitcoin
///      fact it acts on is an ASSERTION by a 3-of-5 quorum of independent attestor operators
///      designated in `BitcoinAttestorRegistry`. A dishonest quorum can assert a false Bitcoin fact
///      and this contract will believe it. What no quorum can ever do is move the underlying
///      inscription: the original Bitcoin Puppet stays on Bitcoin, unbridged, unwrapped and
///      uncustodied, and nothing here has any authority over it. See `docs/TRUST_ASSUMPTIONS.md`.
///
///      WHAT "CONSUMPTION" MEANS. A digest is a single-use ticket. Once consumed it is dead
///      forever: the mapping is write-once with no clearing function, not even for an admin. That
///      one-way door is the protocol's replay defence, and it is why consumption is role gated —
///      see the note on front-running below.
///
///      WHY CONSUMPTION IS ROLE GATED BUT VERIFICATION IS NOT.
///      `verify*` are `view` and open to everyone: reading whether a quorum signed something can
///      never harm anyone, and relayers, indexers and the five attestor services all need it.
///      `consume*` BURNS the authorization. If it were permissionless, anyone watching the mempool
///      could front-run the escrow's settlement transaction, consume the digest first, and leave
///      the escrow's own call reverting with `DigestAlreadyConsumed` — a free, repeatable denial of
///      service against every settlement in the protocol. Restricting the burn to the specific
///      protocol contracts that need it removes that class of attack entirely.
///
///      WHY SIGNERS MUST BE STRICTLY ASCENDING BY RECOVERED ADDRESS.
///      One rule does three jobs. (1) It rejects duplicates: a repeated signer is not strictly
///      greater than itself, so three signatures from two operators can never be inflated into a
///      3-of-5 quorum. (2) It removes the need for an O(n^2) seen-set or a temporary storage
///      bitmap, so the check is a single comparison per signature. (3) It makes the accepted form
///      of a quorum canonical: for a given signer set there is exactly one valid array order, so
///      two honest relayers submitting the same quorum submit byte-identical calldata and nothing
///      depends on collection order. Note it is the RECOVERED ADDRESS that must ascend, not the
///      signature bytes — sorting signature bytes would order by ECDSA output, which has no
///      relationship to the signer.
///
///      NON-UPGRADEABLE by construction: no proxy, no initializer, no `delegatecall`, no
///      `selfdestruct`, no `tx.origin`. This contract holds no value, has no payable function, and
///      has no admin path that can move, seize or reduce anyone's balance — the only thing an admin
///      can do is decide WHO may consume, and pause consumption.
///
///      NO `ReentrancyGuard`, DELIBERATELY. No value moves here and every external call this
///      contract makes is a `view` into one of two immutable, protocol-owned registries fixed at
///      construction. There is no untrusted callee and no callback surface to re-enter through. The
///      write-once consumption mapping is itself checked before and written before anything else
///      could observe it, so even a hypothetical re-entrant caller cannot double-consume.
contract BitcoinOwnershipOracle is IBitcoinOwnershipOracle, AccessControl, Pausable, EIP712 {
    /*//////////////////////////////////////////////////////////////
                              EIP-712 DOMAIN
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP-712 domain name. Part of the digest every attestor signs.
    /// @dev Exposed as a constant so the SDK and the five attestor services can assert they build
    ///      the same domain rather than hard-coding a string that silently drifts.
    string public constant EIP712_NAME = "HoodPups Bitcoin Oracle";

    /// @notice EIP-712 domain version.
    string public constant EIP712_VERSION = "1";

    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice May consume ownership attestations. Held by `HoodPupOfferEscrow` and
    ///         `RootOwnershipRegistry`.
    bytes32 public constant OWNERSHIP_CONSUMER_ROLE = keccak256("OWNERSHIP_CONSUMER_ROLE");

    /// @notice May consume Bitcoin payment attestations. Held by `BtcSolverSettlement`.
    bytes32 public constant PAYMENT_CONSUMER_ROLE = keccak256("PAYMENT_CONSUMER_ROLE");

    /// @notice May consume root-spend attestations. Held by `RootOwnershipRegistry`.
    bytes32 public constant ROOT_SPEND_CONSUMER_ROLE = keccak256("ROOT_SPEND_CONSUMER_ROLE");

    /// @notice May pause consumption. Held by the guardian multisig.
    /// @dev Asymmetric by design: the guardian pauses, `DEFAULT_ADMIN_ROLE` (the timelock)
    ///      unpauses. A compromised guardian can therefore only cost liveness, never authority.
    ///      This mirrors `docs/PAUSE_AND_RECOVERY.md`, which states the asymmetry as policy; this
    ///      is where it becomes code.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              EXTRA ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a constructor address argument that must be non-zero is zero.
    error ZeroAddress();

    /// @notice Thrown when one signature cannot be recovered at all.
    /// @dev The spec requires that a malformed signature — wrong length, `v` outside {27,28}, or a
    ///      malleable upper-half `s` — surfaces as a named oracle failure rather than as an opaque
    ///      revert from deep inside a library. `index` is the position in the submitted array so a
    ///      relayer can identify which attestor's payload is broken. `errorCode` is the numeric
    ///      value of OpenZeppelin's `ECDSA.RecoverError`: 1 invalid signature, 2 invalid length,
    ///      3 upper-half (malleable) `s`.
    /// @param index Position of the offending signature in the submitted array.
    /// @param errorCode Numeric `ECDSA.RecoverError`.
    error MalformedSignature(uint256 index, uint8 errorCode);

    /// @notice Thrown when a consumer holds `OWNERSHIP_CONSUMER_ROLE` but not for this purpose.
    /// @dev Distinct from `UnsupportedPurpose`, which means "not a valid `AuthorizationPurpose` at
    ///      all". Keeping them apart matters operationally: one is a malformed attestation, the
    ///      other is a missing governance grant, and they have completely different remedies.
    /// @param consumer The calling contract.
    /// @param purpose The `AuthorizationPurpose` it attempted to consume.
    error PurposeNotPermittedForConsumer(address consumer, uint8 purpose);

    /// @notice Thrown when a purpose allowlist update names a value outside `AuthorizationPurpose`.
    /// @param purpose The invalid value.
    error InvalidPurposeValue(uint8 purpose);

    /*//////////////////////////////////////////////////////////////
                              EXTRA EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, at construction, binding this oracle to its two registries.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param collectionRegistry Immutable collection membership registry.
    /// @param attestorRegistry Immutable attestor/quorum registry.
    /// @param domainSeparator The EIP-712 domain separator at construction time.
    event OracleDeployed(
        address indexed admin,
        address indexed collectionRegistry,
        address indexed attestorRegistry,
        bytes32 domainSeparator
    );

    /// @notice Emitted when an ownership consumer's permitted purpose set changes.
    /// @dev Emitted as a bitmask (bit `n` set means `AuthorizationPurpose(n)` is permitted) so an
    ///      indexer can reconstruct the full permission state from a single log.
    /// @param consumer The contract whose allowlist changed.
    /// @param previousMask Bitmask before the change.
    /// @param newMask Bitmask after the change.
    event ConsumerPurposesUpdated(address indexed consumer, uint256 previousMask, uint256 newMask);

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE WIRING
    //////////////////////////////////////////////////////////////*/

    /// @dev Immutable so no admin can ever repoint the oracle at a different manifest. Swapping the
    ///      collection registry would be equivalent to editing the canonical Puppets list, which is
    ///      exactly what `PuppetCollectionRegistry`'s immutability exists to prevent; letting the
    ///      oracle point somewhere else would reintroduce that power one level up.
    IPuppetCollectionRegistry private immutable _COLLECTION_REGISTRY;

    /// @dev Immutable for the same reason: a repointable attestor registry would let an admin
    ///      substitute a verifier set of their choosing and mint arbitrary Bitcoin facts. Rotating
    ///      operators is the real registry's job, under its own timelocked roles.
    IBitcoinAttestorRegistry private immutable _ATTESTOR_REGISTRY;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Write-once. There is no function anywhere in this contract that clears an entry.
    mapping(bytes32 digest => bool consumed) private _consumedDigests;

    /// @dev Write-once, keyed by `PuppetHashing.paymentOutputKey`. This is the single mapping that
    ///      makes "one Bitcoin output settles at most one offer" true globally rather than
    ///      per-offer. A per-offer check would be satisfiable by pointing two different offers at
    ///      the same real Bitcoin payment.
    mapping(bytes32 paymentOutputKey => bool consumed) private _consumedPaymentOutputs;

    /// @dev Bit `n` set means the consumer may consume `AuthorizationPurpose(n)`.
    ///      FAIL CLOSED: an unconfigured consumer has mask 0 and can consume nothing, even while
    ///      holding `OWNERSHIP_CONSUMER_ROLE`. See `setConsumerPurposes` for why.
    mapping(address consumer => uint256 purposeMask) private _consumerPurposeMask;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the oracle and bind it permanently to its two registries.
    /// @dev `admin` MUST be a `TimelockController` under multisig control in production. Nothing
    ///      here can enforce that, so the deployment script is responsible for granting roles to
    ///      the timelock and the guardian and revoking everything from the deployer in one batch.
    ///
    ///      The consumer roles are deliberately NOT granted at construction. The escrow, the
    ///      settlement contract and the root registry do not exist yet at deployment step 3
    ///      (`docs/DEPLOYMENT.md`), and pre-granting to the deployer would create exactly the
    ///      EOA-holds-privilege state the handover is meant to eliminate.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param collectionRegistry_ Immutable `PuppetCollectionRegistry` for membership proofs.
    /// @param attestorRegistry_ Immutable `BitcoinAttestorRegistry` for quorum context.
    constructor(
        address admin,
        IPuppetCollectionRegistry collectionRegistry_,
        IBitcoinAttestorRegistry attestorRegistry_
    ) EIP712(EIP712_NAME, EIP712_VERSION) {
        if (admin == address(0)) revert ZeroAddress();
        if (address(collectionRegistry_) == address(0)) revert ZeroAddress();
        if (address(attestorRegistry_) == address(0)) revert ZeroAddress();

        _COLLECTION_REGISTRY = collectionRegistry_;
        _ATTESTOR_REGISTRY = attestorRegistry_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        emit OracleDeployed(admin, address(collectionRegistry_), address(attestorRegistry_), _domainSeparatorV4());
    }

    /*//////////////////////////////////////////////////////////////
                                 WIRING VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice The immutable collection membership registry this oracle proves inclusion against.
    /// @return The `PuppetCollectionRegistry` address fixed at construction.
    function collectionRegistry() external view returns (IPuppetCollectionRegistry) {
        return _COLLECTION_REGISTRY;
    }

    /// @notice The immutable attestor registry this oracle reads quorum context from.
    /// @return The `BitcoinAttestorRegistry` address fixed at construction.
    function attestorRegistry() external view returns (IBitcoinAttestorRegistry) {
        return _ATTESTOR_REGISTRY;
    }

    /// @notice The EIP-712 domain separator currently in force.
    /// @dev Exposed so off-chain signers can compare against their own derivation before signing,
    ///      instead of discovering a domain mismatch as an unexplained `SignerNotAttestor`.
    /// @return The domain separator for this chain id and this contract address.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /*//////////////////////////////////////////////////////////////
                          CONSUMER PURPOSE POLICY
    //////////////////////////////////////////////////////////////*/

    /// @notice Replace the set of `AuthorizationPurpose` values a consumer may consume.
    /// @dev WHY THIS EXISTS. `OWNERSHIP_CONSUMER_ROLE` is held by two different contracts with two
    ///      completely different jobs: the escrow mints (`PAID_EVM_MINT`, `PAID_BTC_MINT`,
    ///      `SELF_CAST`) and the root registry binds and invalidates Bitcoin ownership
    ///      (`ROOT_BIND`, `ROOT_INVALIDATE`). Without this allowlist, a bug or compromise in either
    ///      one would let it consume the other's authorizations — an escrow that could consume a
    ///      `ROOT_INVALIDATE` could burn a Root's ownership epoch, and a root registry that could
    ///      consume a `PAID_EVM_MINT` could burn a buyer's settlement. The role says "you may
    ///      consume"; this says "you may consume THESE".
    ///
    ///      FAIL CLOSED. An address that has never been configured has an empty mask and can
    ///      consume nothing. That is deliberate: a permissive default would make the allowlist
    ///      decorative, and a missing grant fails loudly at deploy-verification time with
    ///      `PurposeNotPermittedForConsumer` rather than silently widening authority. The
    ///      deployment script MUST call this (or `grantOwnershipConsumer`) for every ownership
    ///      consumer.
    ///
    ///      This function grants no ability to move value and cannot reduce anyone's balance; the
    ///      worst an admin can do with it is deny a consumer, which is a liveness action equivalent
    ///      to revoking the role.
    /// @param consumer The contract whose allowlist is being replaced.
    /// @param purposes The complete new set of permitted purposes. Pass an empty array to revoke
    ///        every purpose. Duplicates are harmless; out-of-range values revert.
    function setConsumerPurposes(address consumer, uint8[] calldata purposes) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (consumer == address(0)) revert ZeroAddress();

        uint256 newMask = purposeMask(purposes);
        uint256 previousMask = _consumerPurposeMask[consumer];
        _consumerPurposeMask[consumer] = newMask;

        emit ConsumerPurposesUpdated(consumer, previousMask, newMask);
    }

    /// @notice Grant `OWNERSHIP_CONSUMER_ROLE` and set the purpose allowlist in one call.
    /// @dev Convenience that exists purely to make the two-step wiring impossible to half-do. A
    ///      deployment that grants the role and forgets the allowlist produces a consumer that
    ///      reverts on every consumption; a deployment that sets the allowlist and forgets the role
    ///      does the same. One call, one atomic outcome.
    /// @param consumer The contract to authorize.
    /// @param purposes The purposes it may consume. Must be non-empty to be useful, but an empty
    ///        array is accepted and simply grants the role with no purposes.
    function grantOwnershipConsumer(address consumer, uint8[] calldata purposes) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (consumer == address(0)) revert ZeroAddress();

        uint256 newMask = purposeMask(purposes);
        uint256 previousMask = _consumerPurposeMask[consumer];
        _consumerPurposeMask[consumer] = newMask;

        emit ConsumerPurposesUpdated(consumer, previousMask, newMask);
        _grantRole(OWNERSHIP_CONSUMER_ROLE, consumer);
    }

    /// @notice Convert a list of purposes into the bitmask this contract stores.
    /// @dev `public pure` so the deployment script and the SDK can compute the expected mask and
    ///      assert it against `consumerPurposeMask` after wiring, rather than trusting the grant.
    /// @param purposes Purpose values, each a valid `PuppetTypes.AuthorizationPurpose`.
    /// @return mask Bit `n` set for each `AuthorizationPurpose(n)` present in `purposes`.
    function purposeMask(uint8[] calldata purposes) public pure returns (uint256 mask) {
        for (uint256 i = 0; i < purposes.length; i++) {
            uint8 purpose = purposes[i];
            if (purpose > uint8(type(PuppetTypes.AuthorizationPurpose).max)) revert InvalidPurposeValue(purpose);
            mask |= (uint256(1) << purpose);
        }
    }

    /// @notice The purpose bitmask currently configured for `consumer`.
    /// @param consumer The address to query.
    /// @return Bit `n` set means `AuthorizationPurpose(n)` may be consumed by `consumer`.
    function consumerPurposeMask(address consumer) external view returns (uint256) {
        return _consumerPurposeMask[consumer];
    }

    /// @notice Whether `consumer` may consume ownership attestations carrying `purpose`.
    /// @dev Deliberately does NOT check `OWNERSHIP_CONSUMER_ROLE`; it answers only the purpose
    ///      question, so a caller pre-flighting a settlement can tell a missing role apart from a
    ///      missing purpose grant. Both are required for a consumption to succeed.
    /// @param consumer The address to query.
    /// @param purpose The `AuthorizationPurpose` as uint8.
    /// @return True if the purpose bit is set for `consumer`.
    function isPurposeAllowed(address consumer, uint8 purpose) public view returns (bool) {
        if (purpose > uint8(type(PuppetTypes.AuthorizationPurpose).max)) return false;
        return (_consumerPurposeMask[consumer] >> purpose) & 1 == 1;
    }

    /*//////////////////////////////////////////////////////////////
                                 HASHING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @dev The struct hash comes from `PuppetHashing`, never from an encoding written here. One
    ///      library is the single source of truth for the field order five independent operators
    ///      and two languages must reproduce; a local re-derivation would be a second source that
    ///      could drift silently.
    /// @param a The ownership attestation.
    /// @return The EIP-712 digest attestors sign.
    function hashOwnershipAttestation(PuppetTypes.OwnershipAttestation calldata a) public view returns (bytes32) {
        return _hashTypedDataV4(PuppetHashing.hashStruct(a));
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @param a The Bitcoin payment attestation.
    /// @return The EIP-712 digest attestors sign.
    function hashBitcoinPaymentAttestation(PuppetTypes.BitcoinPaymentAttestation calldata a)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(PuppetHashing.hashStruct(a));
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @param a The root-spend attestation.
    /// @return The EIP-712 digest attestors sign.
    function hashRootSpendAttestation(PuppetTypes.RootSpendAttestation calldata a) public view returns (bytes32) {
        return _hashTypedDataV4(PuppetHashing.hashStruct(a));
    }

    /*//////////////////////////////////////////////////////////////
                            READ-ONLY VERIFICATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @dev Caller-agnostic on purpose. This checks that the attestation is well formed, in the
    ///      collection, fresh, unconsumed and backed by a real quorum — everything that is a
    ///      property of the ATTESTATION. It deliberately does not consult the caller's purpose
    ///      allowlist, because a `view` whose answer depends on `msg.sender` is a trap for the
    ///      relayers and indexers this function exists to serve. Use `isPurposeAllowed` for the
    ///      caller-specific half.
    /// @param a The ownership attestation.
    /// @param signatures Attestor signatures, strictly ascending by recovered signer.
    /// @param collectionProof Merkle proof of the Root's membership in the canonical manifest.
    /// @return digest The EIP-712 digest.
    /// @return rootKey The canonical protocol key for the Root.
    function verifyOwnership(
        PuppetTypes.OwnershipAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external view returns (bytes32 digest, bytes32 rootKey) {
        return _checkOwnership(a, signatures, collectionProof);
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @param a The Bitcoin payment attestation.
    /// @param signatures Attestor signatures, strictly ascending by recovered signer.
    /// @return digest The EIP-712 digest.
    /// @return paymentOutputKey The global uniqueness key for the Bitcoin output.
    function verifyBitcoinPayment(PuppetTypes.BitcoinPaymentAttestation calldata a, bytes[] calldata signatures)
        external
        view
        returns (bytes32 digest, bytes32 paymentOutputKey)
    {
        return _checkBitcoinPayment(a, signatures);
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @param a The root-spend attestation.
    /// @param signatures Attestor signatures, strictly ascending by recovered signer.
    /// @param collectionProof Merkle proof of the Root's membership in the canonical manifest.
    /// @return digest The EIP-712 digest.
    /// @return rootKey The canonical protocol key for the Root.
    function verifyRootSpend(
        PuppetTypes.RootSpendAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external view returns (bytes32 digest, bytes32 rootKey) {
        return _checkRootSpend(a, signatures, collectionProof);
    }

    /*//////////////////////////////////////////////////////////////
                               CONSUMPTION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @dev Two independent gates: the role says this contract may consume ownership attestations
    ///      at all, the purpose allowlist says it may consume THIS KIND. Both are checked before
    ///      any state is written.
    ///
    ///      `bip322ProofHash` is emitted verbatim and never interpreted. It is a commitment to the
    ///      normalized BIP-322 proof bytes the attestors examined off chain; publishing it lets a
    ///      third party fetch those bytes and check the operators' work, which is the only form of
    ///      accountability an attested system can offer. Nothing on chain can validate it.
    /// @param a The ownership attestation.
    /// @param signatures Attestor signatures, strictly ascending by recovered signer.
    /// @param collectionProof Merkle proof of the Root's membership in the canonical manifest.
    /// @return digest The digest that was consumed.
    /// @return rootKey The canonical protocol key for the Root.
    function consumeOwnership(
        PuppetTypes.OwnershipAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external whenNotPaused onlyRole(OWNERSHIP_CONSUMER_ROLE) returns (bytes32 digest, bytes32 rootKey) {
        if (!isPurposeAllowed(msg.sender, a.purpose)) {
            revert PurposeNotPermittedForConsumer(msg.sender, a.purpose);
        }

        (digest, rootKey) = _checkOwnership(a, signatures, collectionProof);

        // Effects before the event; there are no interactions after this point at all.
        _consumedDigests[digest] = true;

        emit OwnershipConsumed(digest, rootKey, a.contextId, a.purpose, msg.sender, a.bip322ProofHash);
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @dev Consumes TWO things in one atomic write: the digest and the Bitcoin output key. Both
    ///      are set before the event and there is no path between them, so a payment can never be
    ///      half-consumed. Reusing one real Bitcoin output across two offers is the single worst
    ///      failure this contract could permit — a solver would be reimbursed twice for one
    ///      payment — and `_consumedPaymentOutputs` is global rather than per-offer precisely so
    ///      that the second attempt fails no matter which offer, solver or attestation set
    ///      presents it.
    /// @param a The Bitcoin payment attestation.
    /// @param signatures Attestor signatures, strictly ascending by recovered signer.
    /// @return digest The digest that was consumed.
    /// @return paymentOutputKey The Bitcoin output key that was consumed.
    function consumeBitcoinPayment(PuppetTypes.BitcoinPaymentAttestation calldata a, bytes[] calldata signatures)
        external
        whenNotPaused
        onlyRole(PAYMENT_CONSUMER_ROLE)
        returns (bytes32 digest, bytes32 paymentOutputKey)
    {
        (digest, paymentOutputKey) = _checkBitcoinPayment(a, signatures);

        _consumedDigests[digest] = true;
        _consumedPaymentOutputs[paymentOutputKey] = true;

        emit BitcoinPaymentConsumed(digest, a.contextId, paymentOutputKey, a.solver, a.amountSats, msg.sender);
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @param a The root-spend attestation.
    /// @param signatures Attestor signatures, strictly ascending by recovered signer.
    /// @param collectionProof Merkle proof of the Root's membership in the canonical manifest.
    /// @return digest The digest that was consumed.
    /// @return rootKey The canonical protocol key for the Root.
    function consumeRootSpend(
        PuppetTypes.RootSpendAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external whenNotPaused onlyRole(ROOT_SPEND_CONSUMER_ROLE) returns (bytes32 digest, bytes32 rootKey) {
        (digest, rootKey) = _checkRootSpend(a, signatures, collectionProof);

        _consumedDigests[digest] = true;

        emit RootSpendConsumed(digest, rootKey, a.spendingTxid, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSUMPTION VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @param digest The EIP-712 digest to query.
    /// @return True once the digest has been consumed. Never returns to false.
    function isDigestConsumed(bytes32 digest) external view returns (bool) {
        return _consumedDigests[digest];
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @dev Convenience wrapper that derives the key, so a caller cannot accidentally query a
    ///      differently-derived key than the one consumption writes.
    /// @param bitcoinTxid Payment txid in display order.
    /// @param outputIndex Output index (vout).
    /// @return True once that output has settled any offer.
    function isPaymentOutputConsumed(bytes32 bitcoinTxid, uint32 outputIndex) external view returns (bool) {
        return _consumedPaymentOutputs[PuppetHashing.paymentOutputKey(bitcoinTxid, outputIndex)];
    }

    /// @inheritdoc IBitcoinOwnershipOracle
    /// @param paymentOutputKey_ A `PuppetHashing.paymentOutputKey` value.
    /// @return True once that key has been consumed.
    function isPaymentOutputKeyConsumed(bytes32 paymentOutputKey_) external view returns (bool) {
        return _consumedPaymentOutputs[paymentOutputKey_];
    }

    /*//////////////////////////////////////////////////////////////
                                  PAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice Halt all three consumption paths.
    /// @dev Hashing, verification and every consumption-state view remain live. Pausing this
    ///      contract cannot block a refund or a withdrawal: it holds no value and no user balance
    ///      is reachable through it. The correct use is a suspected false attestation or an
    ///      in-progress Bitcoin reorg (`docs/PAUSE_AND_RECOVERY.md`).
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resume consumption.
    /// @dev `DEFAULT_ADMIN_ROLE`, not `PAUSER_ROLE`. Pausing must be fast; unpausing must be
    ///      deliberate and go through the timelock.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                 ERC-165
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC-165 support, extended with this oracle's own interface id.
    /// @param interfaceId The interface identifier being queried.
    /// @return True if the interface is supported.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IBitcoinOwnershipOracle).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                          VERIFICATION INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Full ownership check. Ordering is deliberate: the cheapest and most commonly-wrong
    ///      conditions (freshness, then structural shape) are checked before the Merkle proof and
    ///      the signature walk, so an expired or stale submission costs a caller as little as
    ///      possible and reports the real reason rather than the first expensive failure.
    function _checkOwnership(
        PuppetTypes.OwnershipAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) private view returns (bytes32 digest, bytes32 rootKey) {
        uint8 required = _requireFreshContext(a.deadline, a.attestorEpoch, a.policyVersion);

        if (a.authorizationId == bytes32(0)) revert ZeroAuthorizationId();
        _requireValidPayoutShape(a);

        // The registry returns the key it actually proved, so this contract cannot key its events
        // off a different derivation than the one that was verified.
        rootKey = _COLLECTION_REGISTRY.requireMember(
            PuppetTypes.RootId({inscriptionTxid: a.rootTxid, inscriptionIndex: a.rootIndex}), collectionProof
        );

        digest = hashOwnershipAttestation(a);
        _requireUnconsumedDigest(digest);
        _requireQuorum(digest, signatures, required);
    }

    /// @dev Full Bitcoin payment check.
    function _checkBitcoinPayment(PuppetTypes.BitcoinPaymentAttestation calldata a, bytes[] calldata signatures)
        private
        view
        returns (bytes32 digest, bytes32 paymentOutputKey)
    {
        uint8 required = _requireFreshContext(a.deadline, a.attestorEpoch, a.policyVersion);

        if (a.authorizationId == bytes32(0)) revert ZeroAuthorizationId();
        if (a.solver == address(0)) revert ZeroSolver();
        if (a.amountSats == 0) revert ZeroAmount();
        if (a.recipientScriptHash == bytes32(0)) revert ZeroScriptHash();
        // A payment must discharge a specific ownership fact. A zero digest would let a payment
        // float free of any offer, which is the shape a double-reimbursement attempt would take.
        if (a.ownershipDigest == bytes32(0)) revert ZeroOwnershipDigest();

        paymentOutputKey = PuppetHashing.paymentOutputKey(a.bitcoinTxid, a.outputIndex);
        if (_consumedPaymentOutputs[paymentOutputKey]) revert PaymentOutputAlreadyConsumed(paymentOutputKey);

        digest = hashBitcoinPaymentAttestation(a);
        _requireUnconsumedDigest(digest);
        _requireQuorum(digest, signatures, required);
    }

    /// @dev Full root-spend check.
    function _checkRootSpend(
        PuppetTypes.RootSpendAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) private view returns (bytes32 digest, bytes32 rootKey) {
        uint8 required = _requireFreshContext(a.deadline, a.attestorEpoch, a.policyVersion);

        if (a.authorizationId == bytes32(0)) revert ZeroAuthorizationId();
        // Both references are required: `previousOutpointHash` is what the registry currently
        // records as live, and `spendingTxid` is the Bitcoin transaction that ended it. A spend
        // attestation missing either half cannot be reconciled against Bitcoin by a reviewer.
        if (a.previousOutpointHash == bytes32(0) || a.spendingTxid == bytes32(0)) revert ZeroSpendReference();

        rootKey = _COLLECTION_REGISTRY.requireMember(
            PuppetTypes.RootId({inscriptionTxid: a.rootTxid, inscriptionIndex: a.rootIndex}), collectionProof
        );

        digest = hashRootSpendAttestation(a);
        _requireUnconsumedDigest(digest);
        _requireQuorum(digest, signatures, required);
    }

    /// @dev Deadline, epoch and policy version, plus the threshold the quorum must reach.
    ///      All three quorum values come from ONE `quorumContext()` call, which the registry serves
    ///      from a single storage slot; reading them separately could observe a torn combination
    ///      across a governance transaction in the same block.
    ///
    ///      `deadline >= block.timestamp` means an attestation is still valid in the exact second
    ///      it expires. That boundary is chosen (rather than a strict `>`) so an attestation is
    ///      valid for the full duration its issuer intended, and it is pinned by a unit test.
    function _requireFreshContext(uint64 deadline, uint64 attestorEpoch, uint32 policyVersion)
        private
        view
        returns (uint8 required)
    {
        if (deadline < block.timestamp) revert DeadlineExpired(deadline, block.timestamp);

        (uint8 currentThreshold, uint64 currentEpoch, uint32 currentPolicy) = _ATTESTOR_REGISTRY.quorumContext();

        // Equality, not "at least". A signature carrying a FUTURE epoch is just as invalid as a
        // stale one: it was produced against a set this chain has not adopted.
        if (attestorEpoch != currentEpoch) revert StaleAttestorEpoch(attestorEpoch, currentEpoch);
        if (policyVersion != currentPolicy) revert StalePolicyVersion(policyVersion, currentPolicy);

        return currentThreshold;
    }

    /// @dev Separate helper so all three paths reject a replay identically.
    function _requireUnconsumedDigest(bytes32 digest) private view {
        if (_consumedDigests[digest]) revert DigestAlreadyConsumed(digest);
    }

    /// @dev The quorum walk. See the contract header for why strict ascent by recovered address is
    ///      the only ordering rule needed.
    ///
    ///      There is no artificial cap on `signatures.length`. A cap would add a failure mode
    ///      without adding safety: every accepted signature must recover to a distinct, strictly
    ///      increasing, currently-authorized attestor, so the number of signatures that can ever be
    ///      ACCEPTED is already bounded by the registry's `MAX_ATTESTORS`. A caller who submits ten
    ///      thousand junk signatures only burns their own gas, and `consume*` is role gated anyway.
    function _requireQuorum(bytes32 digest, bytes[] calldata signatures, uint8 required) private view {
        if (signatures.length < required) revert InsufficientSignatures(signatures.length, required);

        address previous = address(0);
        for (uint256 i = 0; i < signatures.length; i++) {
            (address signer, ECDSA.RecoverError err) = _tryRecover(digest, signatures[i]);
            if (err != ECDSA.RecoverError.NoError) revert MalformedSignature(i, uint8(err));

            // `previous` starts at the zero address and `tryRecover` never returns zero without an
            // error, so the first iteration's comparison is meaningful rather than a special case.
            if (signer <= previous) revert SignersNotStrictlyAscending(previous, signer);
            if (!_ATTESTOR_REGISTRY.isAttestor(signer)) revert SignerNotAttestor(signer);

            previous = signer;
        }
    }

    /// @dev Recover one signature in either accepted encoding, never reverting from inside the
    ///      library.
    ///
    ///      65 bytes is the canonical `(r, s, v)` form. 64 bytes is EIP-2098 "compact", where the
    ///      recovery bit is folded into the unused top bit of `s`; it exists because it saves a
    ///      whole calldata word per attestor, which is 32 bytes times the threshold on every
    ///      settlement. Both are supported through OpenZeppelin's `ECDSA`, which rejects an
    ///      upper-half (malleable) `s` in the 65-byte form. Note the compact form cannot express a
    ///      malleable `s` at all: the top bit is spoken for by the recovery id, so an upper-half
    ///      value is not representable.
    ///
    ///      Returning the error instead of reverting is what lets `_requireQuorum` report
    ///      `MalformedSignature(index, code)` — the caller learns WHICH signature is broken and
    ///      why, instead of an opaque library revert with no position information.
    function _tryRecover(bytes32 digest, bytes calldata signature)
        private
        pure
        returns (address signer, ECDSA.RecoverError err)
    {
        if (signature.length == 65) {
            (signer, err,) = ECDSA.tryRecover(digest, signature);
        } else if (signature.length == 64) {
            bytes32 r = bytes32(signature[0:32]);
            bytes32 vs = bytes32(signature[32:64]);
            (signer, err,) = ECDSA.tryRecover(digest, r, vs);
        } else {
            return (address(0), ECDSA.RecoverError.InvalidSignatureLength);
        }
    }

    /// @dev Structural validity of an ownership attestation's purpose and payout fields.
    ///
    ///      TWO RULES, NOT ONE. First, `purpose` and `payoutMode` must agree: a `PAID_EVM_MINT`
    ///      carries `PayoutMode.EVM`, a `PAID_BTC_MINT` carries `PayoutMode.BTC`, and every
    ///      non-paying purpose (`SELF_CAST`, `ROOT_BIND`, `ROOT_INVALIDATE`) carries
    ///      `PayoutMode.NONE`. Second, the payout fields must match that mode exactly. Checking
    ///      only the second rule would accept a `PAID_EVM_MINT` that declares a BTC payout — an
    ///      attestation that would read as "mint for EVM settlement" to one consumer and "pay in
    ///      Bitcoin" to another. Two consumers reading one signed fact differently is precisely the
    ///      confusion this contract exists to prevent.
    ///
    ///      WHY THE ZERO REQUIREMENTS ARE ENFORCED, NOT MERELY IGNORED. An unused field that is
    ///      allowed to be non-zero is a field an attacker can populate. `btcPayoutScriptHash` set
    ///      on an EVM-mode attestation would be signed, on chain and available for a downstream
    ///      contract to misread. Requiring the unused half to be zero means there is exactly one
    ///      canonical encoding of each payout intention.
    ///
    ///      `sellerWei <= grossWei` is a structural sanity bound, not the fee split. The 50/25/25
    ///      split is `FeeRouter`'s authority and is deliberately NOT duplicated here: two sources
    ///      of truth for a percentage is how percentages drift. What is checked is the one thing
    ///      that can never be true under ANY split — the seller's share exceeding the total escrow.
    function _requireValidPayoutShape(PuppetTypes.OwnershipAttestation calldata a) private pure {
        if (a.purpose > uint8(type(PuppetTypes.AuthorizationPurpose).max)) revert UnsupportedPurpose(a.purpose);

        PuppetTypes.AuthorizationPurpose purpose = PuppetTypes.AuthorizationPurpose(a.purpose);

        PuppetTypes.PayoutMode expectedMode;
        if (purpose == PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT) {
            expectedMode = PuppetTypes.PayoutMode.EVM;
        } else if (purpose == PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT) {
            expectedMode = PuppetTypes.PayoutMode.BTC;
        } else {
            expectedMode = PuppetTypes.PayoutMode.NONE;
        }

        if (a.payoutMode != uint8(expectedMode)) revert InvalidPayoutShape();

        if (expectedMode == PuppetTypes.PayoutMode.EVM) {
            if (a.evmPayout == address(0)) revert InvalidPayoutShape();
            if (a.btcPayoutScriptHash != bytes32(0)) revert InvalidPayoutShape();
            if (a.sellerSats != 0) revert InvalidPayoutShape();
            if (a.sellerWei > a.grossWei) revert InvalidPayoutShape();
        } else if (expectedMode == PuppetTypes.PayoutMode.BTC) {
            if (a.evmPayout != address(0)) revert InvalidPayoutShape();
            if (a.btcPayoutScriptHash == bytes32(0)) revert InvalidPayoutShape();
            if (a.sellerSats == 0) revert InvalidPayoutShape();
            if (a.sellerWei > a.grossWei) revert InvalidPayoutShape();
        } else {
            // No money moves for SELF_CAST, ROOT_BIND or ROOT_INVALIDATE, so every payout AND
            // every monetary field must be zero. A non-zero `grossWei` on a free mint would be a
            // signed claim that a buyer escrowed value, which no consumer should ever see here.
            if (a.evmPayout != address(0)) revert InvalidPayoutShape();
            if (a.btcPayoutScriptHash != bytes32(0)) revert InvalidPayoutShape();
            if (a.sellerSats != 0) revert InvalidPayoutShape();
            if (a.grossWei != 0) revert InvalidPayoutShape();
            if (a.sellerWei != 0) revert InvalidPayoutShape();
        }
    }
}
