// SPDX-License-Identifier: MIT
pragma solidity =0.8.28 ^0.8.20;

// lib/openzeppelin-contracts/contracts/utils/Context.sol

// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// lib/openzeppelin-contracts/contracts/access/IAccessControl.sol

// OpenZeppelin Contracts (last updated v5.1.0) (access/IAccessControl.sol)

/**
 * @dev External interface of AccessControl declared to support ERC-165 detection.
 */
interface IAccessControl {
    /**
     * @dev The `account` is missing a role.
     */
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    /**
     * @dev The caller of a function is not the expected one.
     *
     * NOTE: Don't confuse with {AccessControlUnauthorizedAccount}.
     */
    error AccessControlBadConfirmation();

    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call. This account bears the admin role (for the granted role).
     * Expected in cases where the role was granted using the internal {AccessControl-_grantRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {AccessControl-_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `callerConfirmation`.
     */
    function renounceRole(bytes32 role, address callerConfirmation) external;
}

// lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/introspection/IERC165.sol)

/**
 * @dev Interface of the ERC-165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[ERC].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// src/interfaces/IPayoutVault.sol

/// @title IPayoutVault
/// @notice Pull-payment accounting for every ETH obligation the protocol creates.
/// @dev Settlement must never depend on an arbitrary recipient's fallback succeeding: a seller
///      whose payout address is a contract that reverts on receive would otherwise be able to
///      block a mint permanently. Credits are bookkeeping; ETH moves only on withdrawal.
///
///      Core invariant: `address(this).balance >= totalLiability()`.
interface IPayoutVault {
    error ZeroAddress();
    error ZeroRootKey();
    error ZeroAmount();
    error AmountMismatch(uint256 expected, uint256 provided);
    error ArrayLengthMismatch(uint256 a, uint256 b);
    error InsufficientClaimable(address beneficiary, uint256 requested, uint256 available);
    error InsufficientPendingRoot(bytes32 rootKey, uint256 requested, uint256 available);
    error WithdrawalFailed(address recipient, uint256 amount);
    error ExpiredAuthorization(uint64 deadline, uint256 nowTs);
    error InvalidAuthorizationSignature();
    error InvalidNonce(uint256 expected, uint256 provided);
    error NoExcess();
    error DirectDepositRejected();

    event Credited(address indexed beneficiary, uint256 amount, address indexed creditor);
    /// @notice Emitted alongside `Credited` when the credit is a refund, so indexers can tell a
    ///         buyer being made whole apart from a seller being paid.
    event RefundCredited(address indexed beneficiary, uint256 amount, address indexed creditor);
    event RootCredited(bytes32 indexed rootKey, uint256 amount, address indexed creditor);
    event RootCreditReleased(bytes32 indexed rootKey, address indexed beneficiary, uint256 amount);
    event Withdrawn(address indexed beneficiary, address indexed recipient, uint256 amount);
    event WithdrawnWithAuthorization(
        address indexed beneficiary, address indexed recipient, uint256 amount, uint256 nonce, address relayer
    );
    event ExcessSwept(address indexed recipient, uint256 amount);

    /// @notice ETH `beneficiary` may withdraw right now.
    function claimable(address beneficiary) external view returns (uint256);

    /// @notice ETH held for a Root whose Bitcoin owner is not currently verified.
    function pendingByRoot(bytes32 rootKey) external view returns (uint256);

    /// @notice Sum of every obligation the vault owes.
    function totalLiability() external view returns (uint256);

    /// @notice Next expected gasless-withdrawal nonce for `beneficiary`.
    function withdrawalNonce(address beneficiary) external view returns (uint256);

    /// @notice `address(this).balance - totalLiability()`; only force-sent ETH ends up here.
    function excessBalance() external view returns (uint256);

    /// @notice Credit `beneficiary` with `msg.value`. Requires `CREDITOR_ROLE`. Pausable.
    function credit(address beneficiary) external payable;

    /// @notice Credit a refund. Requires `CREDITOR_ROLE`. Deliberately NOT pausable.
    /// @dev A refund releases an obligation the beneficiary already holds rather than creating a
    ///      new one, so the credit pause must not reach it (protocol invariant I12).
    function creditRefund(address beneficiary) external payable;

    /// @notice Credit a Root's pending bucket with `msg.value`. Requires `CREDITOR_ROLE`.
    function creditRoot(bytes32 rootKey) external payable;

    /// @notice Credit several beneficiaries in one call. `sum(amounts)` must equal `msg.value`.
    function creditBatch(address[] calldata beneficiaries, uint256[] calldata amounts) external payable;

    /// @notice Move a Root's pending bucket to a newly verified beneficiary's claimable balance.
    /// @dev Pure bookkeeping: no ETH moves and `totalLiability` is unchanged.
    ///      Requires `ROOT_RELEASER_ROLE`.
    function releaseRootCredit(bytes32 rootKey, address beneficiary) external returns (uint256 amount);

    /// @notice Withdraw `amount` of your own claimable balance.
    function withdraw(uint256 amount) external;

    /// @notice Withdraw your entire claimable balance.
    function withdrawAll() external;

    /// @notice Withdraw `amount` of your own balance to another address.
    function withdrawTo(address payable recipient, uint256 amount) external;

    /// @notice Withdraw on a beneficiary's behalf against their EIP-712 signature.
    /// @dev Accepts EOA signatures and ERC-1271 smart-account signatures. This is what lets a
    ///      seller who holds zero ETH for gas still get paid.
    function withdrawWithAuthorization(
        address beneficiary,
        address payable recipient,
        uint256 amount,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) external;

    /// @notice Move only unaccounted (force-sent) ETH out. Can never touch a liability.
    function sweepExcess(address payable recipient) external returns (uint256 amount);
}

// src/types/PuppetTypes.sol

/// @title PuppetTypes
/// @notice Canonical shared type system for the HoodPups Rooted Settlement Protocol.
/// @dev Every contract, service and SDK in this repository MUST use these definitions verbatim.
///      Field order inside the attestation structs is security critical: it defines the EIP-712
///      `encodeType` string and therefore the digest that five independent attestors sign.
///      Changing the order of any field is a breaking protocol change and requires a new
///      deployment plus a new `policyVersion`, never an in-place edit.
///
///      TRUST BOUNDARY: nothing in this file, and nothing in this protocol, verifies Bitcoin
///      consensus on Robinhood Chain. Bitcoin facts are asserted by a 3-of-5 quorum of
///      independent verifier operators. This is an attested settlement system, not a
///      trustless bridge.
library PuppetTypes {
    /*//////////////////////////////////////////////////////////////
                              ENUMERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice What a buyer is asking for when they open an offer.
    /// @dev PAID_EVM  Seller is credited ETH inside PayoutVault on Robinhood Chain.
    ///      PAID_BTC  Seller is paid exact native BTC by a bonded solver, who is then
    ///                reimbursed in ETH from the buyer's escrow.
    ///      SELF_CAST The Bitcoin controller mints to themselves for free; no money moves.
    enum OfferKind {
        PAID_EVM,
        PAID_BTC,
        SELF_CAST
    }

    /// @notice Lifecycle position of an offer inside `HoodPupOfferEscrow`.
    /// @dev NONE          Offer id has never been created.
    ///      OPEN          Escrowed and awaiting a Bitcoin ownership quorum.
    ///      BTC_APPROVED  Ownership proven for a PAID_BTC offer; awaiting a solver.
    ///      BTC_RESERVED  A bonded solver has claimed the right to pay Bob in BTC.
    ///      SETTLED       HoodPup minted and funds routed. Terminal.
    ///      REFUNDED      Escrow returned to the buyer. Terminal.
    enum OfferStatus {
        NONE,
        OPEN,
        BTC_APPROVED,
        BTC_RESERVED,
        SETTLED,
        REFUNDED
    }

    /// @notice How the current Bitcoin controller elected to be paid.
    enum PayoutMode {
        NONE,
        EVM,
        BTC
    }

    /// @notice What a BIP-322 authorization signed by the Bitcoin controller permits.
    /// @dev The purpose is bound into the attestation digest so a signature collected for one
    ///      action can never be replayed into a different action.
    enum AuthorizationPurpose {
        PAID_EVM_MINT,
        PAID_BTC_MINT,
        SELF_CAST,
        ROOT_BIND,
        ROOT_INVALIDATE
    }

    /*//////////////////////////////////////////////////////////////
                            CANONICAL IDENTITY
    //////////////////////////////////////////////////////////////*/

    /// @notice The permanent identity of one Bitcoin Puppet inscription.
    /// @dev `inscriptionTxid` is the reveal transaction id in **big-endian / RPC display order**
    ///      (the order a block explorer shows), left-padded into `bytes32`. Byte order is a
    ///      security primitive here: the SDK, the Merkle builder, the verifier and Solidity must
    ///      all agree. See `docs/ARCHITECTURE.md#canonical-byte-order`.
    /// @param inscriptionTxid Reveal txid, display order.
    /// @param inscriptionIndex Inscription index within that reveal transaction (the `iN` suffix).
    struct RootId {
        bytes32 inscriptionTxid;
        uint32 inscriptionIndex;
    }

    /*//////////////////////////////////////////////////////////////
                              ATTESTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice A statement by one verifier operator that a Bitcoin controller authorized an action.
    /// @dev Flat by design: nested EIP-712 structs would force every off-chain implementation to
    ///      reproduce sub-hashing, which is a common source of cross-language divergence.
    ///
    ///      Replay protection is NOT provided by EIP-712 itself. It comes from
    ///      `authorizationId` + `deadline` + one-time digest consumption in `BitcoinOwnershipOracle`.
    ///
    /// @param purpose `AuthorizationPurpose` as uint8. Binds the signature to one action.
    /// @param rootTxid Inscription reveal txid, display order.
    /// @param rootIndex Inscription index.
    /// @param contextId Offer id for mint purposes; zero-or-root-scoped context for ROOT_BIND.
    /// @param offerTermsHash `PuppetHashing.offerTermsHash` over the immutable offer terms.
    /// @param currentOutpointHash Hash of the Bitcoin outpoint currently holding the inscription.
    /// @param ownerScriptHash keccak256 of the raw scriptPubKey bytes that own that outpoint.
    /// @param bip322ProofHash Commitment to the normalized BIP-322 proof bytes. Emitted, never
    ///        interpreted on chain.
    /// @param buyer Robinhood Chain address that escrowed the ETH.
    /// @param recipient Robinhood Chain address that receives the HoodPup.
    /// @param payoutMode `PayoutMode` as uint8.
    /// @param evmPayout Seller's Robinhood Chain payout address. Zero unless payoutMode == EVM.
    /// @param btcPayoutScriptHash keccak256 of the seller's Bitcoin payout scriptPubKey.
    ///        Zero unless payoutMode == BTC.
    /// @param sellerSats Exact satoshis the seller must receive. Zero unless payoutMode == BTC.
    /// @param grossWei Total wei escrowed by the buyer.
    /// @param sellerWei Seller share in wei (50% of gross).
    /// @param bitcoinBlockHash Bitcoin tip hash observed by the attestor.
    /// @param bitcoinHeight Bitcoin tip height observed by the attestor.
    /// @param authorizationId Unique per-authorization identifier chosen off chain.
    /// @param deadline Unix timestamp after which this attestation is worthless.
    /// @param attestorEpoch Attestor-set epoch this signature is valid for.
    /// @param policyVersion Verification policy version this signature is valid for.
    struct OwnershipAttestation {
        uint8 purpose;
        bytes32 rootTxid;
        uint32 rootIndex;
        bytes32 contextId;
        bytes32 offerTermsHash;
        bytes32 currentOutpointHash;
        bytes32 ownerScriptHash;
        bytes32 bip322ProofHash;
        address buyer;
        address recipient;
        uint8 payoutMode;
        address evmPayout;
        bytes32 btcPayoutScriptHash;
        uint64 sellerSats;
        uint256 grossWei;
        uint256 sellerWei;
        bytes32 bitcoinBlockHash;
        uint64 bitcoinHeight;
        bytes32 authorizationId;
        uint64 deadline;
        uint64 attestorEpoch;
        uint32 policyVersion;
    }

    /// @notice A statement by one verifier operator that a specific Bitcoin output paid the seller.
    /// @param contextId Offer id the payment settles.
    /// @param ownershipDigest Digest of the ownership attestation this payment discharges.
    /// @param solver Robinhood Chain address of the bonded solver that broadcast the payment.
    /// @param bitcoinTxid Payment txid, display order.
    /// @param outputIndex Output index (vout) inside that transaction.
    /// @param recipientScriptHash keccak256 of the raw scriptPubKey of that output.
    /// @param amountSats Exact value of that output in satoshis.
    /// @param bitcoinBlockHash Bitcoin block hash containing the payment, as observed.
    /// @param bitcoinHeight Height of that block.
    /// @param authorizationId Unique per-authorization identifier chosen off chain.
    /// @param deadline Unix timestamp after which this attestation is worthless.
    /// @param attestorEpoch Attestor-set epoch this signature is valid for.
    /// @param policyVersion Verification policy version this signature is valid for.
    struct BitcoinPaymentAttestation {
        bytes32 contextId;
        bytes32 ownershipDigest;
        address solver;
        bytes32 bitcoinTxid;
        uint32 outputIndex;
        bytes32 recipientScriptHash;
        uint64 amountSats;
        bytes32 bitcoinBlockHash;
        uint64 bitcoinHeight;
        bytes32 authorizationId;
        uint64 deadline;
        uint64 attestorEpoch;
        uint32 policyVersion;
    }

    /// @notice A statement by one verifier operator that a recorded inscription outpoint was spent.
    /// @dev Used to end a Root ownership epoch when the Bitcoin Puppet changes hands.
    /// @param rootTxid Inscription reveal txid, display order.
    /// @param rootIndex Inscription index.
    /// @param previousOutpointHash The outpoint hash that the registry currently records as live.
    /// @param spendingTxid Bitcoin txid that spent it, display order.
    /// @param bitcoinBlockHash Bitcoin block hash containing the spend.
    /// @param bitcoinHeight Height of that block.
    /// @param authorizationId Unique per-authorization identifier chosen off chain.
    /// @param deadline Unix timestamp after which this attestation is worthless.
    /// @param attestorEpoch Attestor-set epoch this signature is valid for.
    /// @param policyVersion Verification policy version this signature is valid for.
    struct RootSpendAttestation {
        bytes32 rootTxid;
        uint32 rootIndex;
        bytes32 previousOutpointHash;
        bytes32 spendingTxid;
        bytes32 bitcoinBlockHash;
        uint64 bitcoinHeight;
        bytes32 authorizationId;
        uint64 deadline;
        uint64 attestorEpoch;
        uint32 policyVersion;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Complete public view of one escrow offer.
    /// @dev `kind` is `OfferKind` and `status` is `OfferStatus`, both as uint8 so the struct
    ///      round-trips cleanly through ABI decoders in every language.
    struct Offer {
        address buyer;
        address recipient;
        bytes32 rootKey;
        bytes32 rootTxid;
        uint32 rootIndex;
        uint256 grossWei;
        uint256 sellerWei;
        uint256 treasuryWei;
        uint256 protocolWei;
        uint64 sellerSats;
        uint64 createdAt;
        uint64 expiry;
        uint8 kind;
        uint8 status;
        bytes32 termsHash;
        bytes32 ownershipDigest;
        bytes32 btcPayoutScriptHash;
        address reservedSolver;
        uint64 reservationExpiry;
    }

    /// @notice Snapshot of the currently verified Bitcoin controller for one Root.
    struct RootState {
        uint64 epoch;
        bool active;
        bytes32 currentOutpointHash;
        bytes32 ownerScriptHash;
        address beneficiary;
        bytes32 ownershipDigest;
        bytes32 bip322ProofHash;
        uint64 verifiedBitcoinHeight;
        bytes32 lastBitcoinBlockHash;
        bytes32 invalidatingSpendTxid;
    }

    /// @notice Historical record of one Root ownership epoch.
    struct RootEpochInfo {
        address beneficiary;
        bytes32 outpointHash;
        bytes32 ownerScriptHash;
        uint64 activatedAtBitcoinHeight;
        uint64 activatedAtBlockTimestamp;
        uint64 deactivatedAtBitcoinHeight;
        uint64 deactivatedAtBlockTimestamp;
        bytes32 ownershipDigest;
    }
}

// lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/ReentrancyGuard.sol)

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

// lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/introspection/ERC165.sol)

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC-165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

// src/interfaces/IBitcoinOwnershipOracle.sol

/// @title IBitcoinOwnershipOracle
/// @notice Turns a 3-of-5 quorum of EIP-712 attestations into one-time-consumable authorizations.
/// @dev This contract verifies SIGNATURES, not Bitcoin. It has no ability to check a BIP-322 proof,
///      an inscription location or a UTXO set. A dishonest quorum can assert a false Bitcoin fact.
///      It can never move the underlying inscription. See `docs/TRUST_ASSUMPTIONS.md`.
interface IBitcoinOwnershipOracle {
    error DeadlineExpired(uint64 deadline, uint256 nowTs);
    error StaleAttestorEpoch(uint64 provided, uint64 current);
    error StalePolicyVersion(uint32 provided, uint32 current);
    error DigestAlreadyConsumed(bytes32 digest);
    error PaymentOutputAlreadyConsumed(bytes32 paymentOutputKey);
    error InsufficientSignatures(uint256 provided, uint8 required);
    error SignerNotAttestor(address signer);
    error SignersNotStrictlyAscending(address previous, address next);
    error ZeroAuthorizationId();
    error UnsupportedPurpose(uint8 purpose);
    error InvalidPayoutShape();
    error ZeroSolver();
    error ZeroAmount();
    error ZeroScriptHash();
    error ZeroOwnershipDigest();
    error ZeroSpendReference();

    event OwnershipConsumed(
        bytes32 indexed digest,
        bytes32 indexed rootKey,
        bytes32 indexed contextId,
        uint8 purpose,
        address consumer,
        bytes32 bip322ProofHash
    );
    event BitcoinPaymentConsumed(
        bytes32 indexed digest,
        bytes32 indexed contextId,
        bytes32 indexed paymentOutputKey,
        address solver,
        uint64 amountSats,
        address consumer
    );
    event RootSpendConsumed(bytes32 indexed digest, bytes32 indexed rootKey, bytes32 spendingTxid, address consumer);

    /// @notice EIP-712 digest of an ownership attestation.
    function hashOwnershipAttestation(PuppetTypes.OwnershipAttestation calldata a) external view returns (bytes32);

    /// @notice EIP-712 digest of a Bitcoin payment attestation.
    function hashBitcoinPaymentAttestation(PuppetTypes.BitcoinPaymentAttestation calldata a)
        external
        view
        returns (bytes32);

    /// @notice EIP-712 digest of a root-spend attestation.
    function hashRootSpendAttestation(PuppetTypes.RootSpendAttestation calldata a) external view returns (bytes32);

    /// @notice Read-only validation. Reverts on any failure. Does not consume.
    function verifyOwnership(
        PuppetTypes.OwnershipAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external view returns (bytes32 digest, bytes32 rootKey);

    /// @notice Read-only validation. Reverts on any failure. Does not consume.
    function verifyBitcoinPayment(PuppetTypes.BitcoinPaymentAttestation calldata a, bytes[] calldata signatures)
        external
        view
        returns (bytes32 digest, bytes32 paymentOutputKey);

    /// @notice Read-only validation. Reverts on any failure. Does not consume.
    function verifyRootSpend(
        PuppetTypes.RootSpendAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external view returns (bytes32 digest, bytes32 rootKey);

    /// @notice Validate and permanently consume an ownership attestation.
    /// @dev Restricted to `OWNERSHIP_CONSUMER_ROLE` so an outsider cannot burn a valid
    ///      authorization out from under the escrow.
    function consumeOwnership(
        PuppetTypes.OwnershipAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (bytes32 digest, bytes32 rootKey);

    /// @notice Validate and permanently consume a payment attestation and its Bitcoin output.
    function consumeBitcoinPayment(PuppetTypes.BitcoinPaymentAttestation calldata a, bytes[] calldata signatures)
        external
        returns (bytes32 digest, bytes32 paymentOutputKey);

    /// @notice Validate and permanently consume a root-spend attestation.
    function consumeRootSpend(
        PuppetTypes.RootSpendAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (bytes32 digest, bytes32 rootKey);

    /// @notice True once a digest has been consumed. Consumption is permanent.
    function isDigestConsumed(bytes32 digest) external view returns (bool);

    /// @notice True once a Bitcoin output has been used to settle any offer.
    function isPaymentOutputConsumed(bytes32 bitcoinTxid, uint32 outputIndex) external view returns (bool);

    /// @notice True once a payment output key has been consumed.
    function isPaymentOutputKeyConsumed(bytes32 paymentOutputKey) external view returns (bool);
}

// src/interfaces/IBtcSolverSettlement.sol

/// @title IBtcSolverSettlement
/// @notice Bonded solvers convert an ETH seller share into an exact native-BTC payment.
/// @dev There is no BTC/ETH price oracle anywhere in this contract, by design. The buyer fixed
///      `sellerSats` and `sellerWei` when the offer was created and the Bitcoin holder signed
///      both. A solver either finds that quote attractive or ignores it; the spread is the
///      market. Removing the oracle removes oracle manipulation, price disputes and slippage
///      arguments from the settlement path entirely.
interface IBtcSolverSettlement {
    /// @notice Lifecycle of one solver reservation.
    enum ReservationStatus {
        NONE,
        ACTIVE,
        SETTLED,
        EXPIRED
    }

    /// @notice Terms snapshotted at reservation time so later governance cannot change them.
    struct Reservation {
        address solver;
        uint256 bondWei;
        uint64 reservedAt;
        uint64 reservationExpiry;
        uint16 buyerSlashBpsSnapshot;
        uint8 status;
    }

    error ZeroAddress();
    error InvalidConfiguration();
    error InsufficientBond(uint256 provided, uint256 required);
    error AlreadyReserved(bytes32 offerId, address solver);
    error NoActiveReservation(bytes32 offerId);
    error ReservationNotExpired(bytes32 offerId, uint64 expiry);
    error ReservationExpired(bytes32 offerId, uint64 expiry);
    error NotReservedSolver(address caller, address solver);
    error PaymentFieldMismatch(string field);
    error OfferNotBtcApproved(bytes32 offerId, uint8 status);
    error RootAlreadyMinted(bytes32 rootKey);

    event Reserved(
        bytes32 indexed offerId, address indexed solver, uint256 bondWei, uint64 reservationExpiry, uint16 buyerSlashBps
    );
    event Settled(
        bytes32 indexed offerId,
        address indexed solver,
        bytes32 indexed paymentDigest,
        bytes32 bitcoinTxid,
        uint32 outputIndex,
        uint64 amountSats,
        bytes32 recipientScriptHash,
        uint256 bondReturned
    );
    event ReservationExpiredAndSlashed(
        bytes32 indexed offerId,
        address indexed solver,
        uint256 bondWei,
        uint256 buyerCompensation,
        uint256 protocolAmount
    );

    /// @notice Minimum bond a solver must post.
    function minimumBondWei() external view returns (uint256);

    /// @notice How long a reservation lasts before anyone may expire it.
    function reservationDuration() external view returns (uint64);

    /// @notice Portion of a slashed bond that compensates the buyer, in basis points.
    function buyerSlashBps() external view returns (uint16);

    /// @notice Where the non-buyer portion of a slashed bond goes.
    function protocolSlashRecipient() external view returns (address);

    /// @notice Current reservation for an offer.
    function reservationOf(bytes32 offerId) external view returns (Reservation memory);

    /// @notice Post a bond and claim the exclusive right to pay this offer's seller in BTC.
    function reserve(bytes32 offerId) external payable;

    /// @notice Prove the exact BTC payment happened, mint the HoodPup and take reimbursement.
    function settle(
        bytes32 offerId,
        PuppetTypes.BitcoinPaymentAttestation calldata attestation,
        bytes[] calldata signatures
    ) external returns (uint256 tokenId);

    /// @notice Permissionless: release a stale reservation and slash its bond.
    function expireReservation(bytes32 offerId) external;
}

// src/interfaces/IHoodPupOfferEscrow.sol

/// @title IHoodPupOfferEscrow
/// @notice Holds buyer ETH and runs the offer lifecycle from creation to mint or refund.
/// @dev A buyer cannot cancel an open offer early. That is deliberate: a Bitcoin holder may be
///      partway through a cold-wallet signing ceremony that takes minutes or hours, and a
///      cancellable offer would let a buyer bait a signature and then withdraw. Buyers get their
///      ETH back at expiry, or immediately if another offer already minted the Root.
interface IHoodPupOfferEscrow {
    error ZeroAddress();
    error ZeroValue();
    error UnknownOffer(bytes32 offerId);
    error InvalidOfferStatus(bytes32 offerId, uint8 actual, uint8 expected);
    error OfferExpired(bytes32 offerId, uint64 expiry);
    error OfferNotExpired(bytes32 offerId, uint64 expiry);
    error InvalidExpiry(uint64 expiry, uint64 minAllowed, uint64 maxAllowed);
    error RootAlreadyMinted(bytes32 rootKey);
    error RootNotMinted(bytes32 rootKey);
    error SelfCastMustBeZeroValue();
    error SelfCastRecipientMismatch(address caller, address recipient);
    error PaidOfferRequiresValue();
    error BtcOfferRequiresSats();
    error AttestationFieldMismatch(string field);
    error UnexpectedPurpose(uint8 provided, uint8 expected);
    error NotReservedSolver(address provided, address active);
    error DurationBoundsInvalid(uint64 minimum, uint64 maximum);

    event OfferCreated(
        bytes32 indexed offerId,
        bytes32 indexed rootKey,
        address indexed buyer,
        address recipient,
        uint8 kind,
        uint256 grossWei,
        uint256 sellerWei,
        uint64 sellerSats,
        uint64 expiry,
        bytes32 termsHash
    );
    event OwnershipApproved(bytes32 indexed offerId, bytes32 indexed ownershipDigest, uint8 purpose, address evmPayout);
    event BtcOfferApproved(
        bytes32 indexed offerId, bytes32 indexed ownershipDigest, bytes32 btcPayoutScriptHash, uint64 sellerSats
    );
    event BtcReserved(bytes32 indexed offerId, address indexed solver, uint64 reservationExpiry);
    event BtcReservationCleared(bytes32 indexed offerId, address indexed solver);
    event OfferSettled(
        bytes32 indexed offerId,
        bytes32 indexed rootKey,
        uint256 indexed tokenId,
        address recipient,
        address paidTo,
        uint256 grossWei,
        uint8 kind
    );
    event OfferRefunded(bytes32 indexed offerId, address indexed buyer, uint256 amount, bool unfillable);

    /// @notice Full offer view.
    function getOffer(bytes32 offerId) external view returns (PuppetTypes.Offer memory);

    /// @notice Next offer id `buyer` will produce.
    function nextOfferId(address buyer) external view returns (bytes32);

    /// @notice Per-buyer offer counter.
    function buyerNonce(address buyer) external view returns (uint256);

    /// @notice Recompute an offer's terms hash from explicit fields. Mirrored in the SDK.
    function computeTermsHash(
        bytes32 offerId,
        uint8 kind,
        bytes32 rootKey,
        address buyer,
        address recipient,
        uint256 grossWei,
        uint256 sellerWei,
        uint64 sellerSats,
        uint64 expiry
    ) external view returns (bytes32);

    /// @notice Create a paid offer settled in ETH on Robinhood Chain.
    function createPaidEvmOffer(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 expiry,
        bytes32[] calldata collectionProof
    ) external payable returns (bytes32 offerId);

    /// @notice Create a paid offer settled in exact native BTC through a bonded solver.
    function createPaidBtcOffer(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 sellerSats,
        uint64 expiry,
        bytes32[] calldata collectionProof
    ) external payable returns (bytes32 offerId);

    /// @notice Create a free self-cast for the Bitcoin controller.
    function createSelfCastOffer(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 expiry,
        bytes32[] calldata collectionProof
    ) external returns (bytes32 offerId);

    /// @notice Settle an ETH-payout offer: mint and route funds atomically.
    function settlePaidEvm(
        bytes32 offerId,
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (uint256 tokenId);

    /// @notice Settle a free self-cast: mint only, no money moves.
    function settleSelfCast(
        bytes32 offerId,
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (uint256 tokenId);

    /// @notice Prove ownership for a BTC-payout offer. Does not mint; moves to `BTC_APPROVED`.
    function approvePaidBtc(
        bytes32 offerId,
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external;

    /// @notice Mark an approved BTC offer reserved. Requires `BTC_SETTLEMENT_ROLE`.
    function markBtcReserved(bytes32 offerId, address solver, uint64 reservationExpiry) external;

    /// @notice Return a reserved offer to `BTC_APPROVED`. Requires `BTC_SETTLEMENT_ROLE`.
    function clearBtcReservation(bytes32 offerId) external;

    /// @notice Mint and reimburse the solver. Requires `BTC_SETTLEMENT_ROLE`.
    function finalizeBtcSettlement(bytes32 offerId, address solver, bytes32 paymentDigest)
        external
        returns (uint256 tokenId);

    /// @notice Refund an expired, unsettled offer to the buyer via PayoutVault.
    function refundExpired(bytes32 offerId) external;

    /// @notice Refund immediately when the Root was already minted by a competing offer.
    function refundUnfillable(bytes32 offerId) external;
}

// lib/openzeppelin-contracts/contracts/utils/Pausable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Pausable.sol)

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    bool private _paused;

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// lib/openzeppelin-contracts/contracts/access/AccessControl.sol

// OpenZeppelin Contracts (last updated v5.0.0) (access/AccessControl.sol)

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms. This is a lightweight version that doesn't allow enumerating role
 * members except through off-chain means by accessing the contract event logs. Some
 * applications may benefit from on-chain enumerability, for those cases see
 * {AccessControlEnumerable}.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```solidity
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```solidity
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it. We recommend using {AccessControlDefaultAdminRules}
 * to enforce additional security measures for this role.
 */
abstract contract AccessControl is Context, IAccessControl, ERC165 {
    struct RoleData {
        mapping(address account => bool) hasRole;
        bytes32 adminRole;
    }

    mapping(bytes32 role => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with an {AccessControlUnauthorizedAccount} error including the required role.
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        return _roles[role].hasRole[account];
    }

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `_msgSender()`
     * is missing `role`. Overriding this function changes the behavior of the {onlyRole} modifier.
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `account`
     * is missing `role`.
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            revert AccessControlUnauthorizedAccount(account, role);
        }
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view virtual returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleGranted} event.
     */
    function grantRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleRevoked} event.
     */
    function revokeRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been revoked `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `callerConfirmation`.
     *
     * May emit a {RoleRevoked} event.
     */
    function renounceRole(bytes32 role, address callerConfirmation) public virtual {
        if (callerConfirmation != _msgSender()) {
            revert AccessControlBadConfirmation();
        }

        _revokeRole(role, callerConfirmation);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /**
     * @dev Attempts to grant `role` to `account` and returns a boolean indicating if `role` was granted.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleGranted} event.
     */
    function _grantRole(bytes32 role, address account) internal virtual returns (bool) {
        if (!hasRole(role, account)) {
            _roles[role].hasRole[account] = true;
            emit RoleGranted(role, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Attempts to revoke `role` to `account` and returns a boolean indicating if `role` was revoked.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleRevoked} event.
     */
    function _revokeRole(bytes32 role, address account) internal virtual returns (bool) {
        if (hasRole(role, account)) {
            _roles[role].hasRole[account] = false;
            emit RoleRevoked(role, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }
}

// src/BtcSolverSettlement.sol

/// @title BtcSolverSettlement
/// @notice Bonded solvers pay a Bitcoin seller in exact native BTC and are reimbursed in ETH out of
///         the buyer's escrow.
/// @dev ────────────────────────────────────────────────────────────────────────────────────────
///      TRUST BOUNDARY — READ THIS FIRST.
///      Nothing here verifies Bitcoin consensus. This contract cannot see the Bitcoin chain, cannot
///      parse a transaction and cannot count confirmations. Every Bitcoin fact it acts on is
///      ASSERTED by a 3-of-5 quorum of independent attestor operators through
///      `BitcoinOwnershipOracle`. This is an attested settlement system, not a trustless bridge.
///      The original Bitcoin Puppet inscription never moves, is never wrapped and is never held in
///      custody or escrow by anything in this repository.
///      ────────────────────────────────────────────────────────────────────────────────────────
///
///      NO PRICE ORACLE. EVER.
///      `sellerSats` (what the Bitcoin holder must receive in BTC) and `sellerWei` (what the solver
///      is reimbursed in ETH) were BOTH fixed when the buyer created the offer, and the Bitcoin
///      holder signed both inside the BIP-322 authorization that produced the ownership
///      attestation. This contract therefore never needs to know a BTC/ETH exchange rate, and it
///      must never be given one. The solver's spread — the difference between the sats it pays and
///      the wei it collects — IS the market mechanism, priced by competing solvers at the moment
///      they choose to bond. Introducing a price feed here would add oracle manipulation,
///      staleness disputes and slippage arguments to a settlement path that currently has none of
///      them, and would buy nothing: the two legs are already fixed numbers signed by the two
///      parties who care about them.
///
///      THE SOLVER STATE MACHINE (one instance per `offerId`):
///
///          NONE ──reserve()──▶ ACTIVE ──settle()───────────▶ SETTLED   (terminal)
///                                │
///                                └──expireReservation()───▶ EXPIRED
///                                                              │
///                                                              └──reserve()──▶ ACTIVE  (re-bond)
///
///      SETTLED is terminal and unreachable from anywhere else. EXPIRED is re-enterable, which is
///      what lets a second solver rescue an offer whose first solver went dark.
///
///      THE BOND ACCOUNTING EQUATION, enforced on every state transition by
///      `_assertBondBooksBalance` and asserted continuously by the stateful campaign:
///
///          totalBondsPosted == totalActiveBondWei + totalBondsReturned + totalBondsSlashed
///          address(this).balance >= totalActiveBondWei
///
///      Every wei a solver posts is at all times in exactly ONE of three places: held here as the
///      liability of an ACTIVE reservation, already credited back to the solver in `PayoutVault`
///      (SETTLED), or already credited to the buyer and the protocol in `PayoutVault` (EXPIRED).
///      Bond wei is never burned, never retained beyond an active reservation, and never routed
///      anywhere an admin can choose per reservation.
///
///      NON-UPGRADEABLE. No proxy, no initializer, no delegatecall, no selfdestruct, no
///      `tx.origin`, no owner EOA, and no admin path that can seize a bond or reduce a credited
///      balance. `DEFAULT_ADMIN_ROLE` is meant for a multisig behind a `TimelockController`.
contract BtcSolverSettlement is IBtcSolverSettlement, AccessControl, Pausable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice May change the four economic parameters. Held by the timelock.
    /// @dev Deliberately separate from `DEFAULT_ADMIN_ROLE` (least privilege, matching the
    ///      precedent set by `BitcoinAttestorRegistry` and `FeeRouter`): parameter tuning and role
    ///      administration are different duties and can be delegated to different timelocks. Both
    ///      are granted to `admin` at construction so a single-timelock deployment works as is.
    ///      Neither role can touch a bond: see `_assertBondBooksBalance` and the absence of any
    ///      per-reservation admin function anywhere in this file.
    bytes32 public constant CONFIG_ADMIN_ROLE = keccak256("CONFIG_ADMIN_ROLE");

    /// @notice May pause NEW reservations. Nothing else.
    /// @dev Asymmetric with unpausing on purpose: pausing is the safe direction and may live on a
    ///      hot monitoring key that reacts in seconds, while `unpause` requires
    ///      `DEFAULT_ADMIN_ROLE` so restarting risk-taking is a governed act.
    ///      `docs/PAUSE_AND_RECOVERY.md` states that asymmetry as protocol policy.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Basis-point denominator for the slash split.
    uint16 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Shortest reservation window governance may configure.
    /// @dev A Bitcoin payment needs to be broadcast, mined and then observed by five independent
    ///      attestors under their confirmation policy. A window shorter than this would guarantee
    ///      that honest solvers are slashed for the chain's latency rather than for misbehaviour,
    ///      which would turn the bond from a liveness incentive into a tax.
    uint64 public constant MIN_RESERVATION_DURATION = 1 hours;

    /// @notice Longest reservation window governance may configure.
    /// @dev This is the bound on how long a buyer's escrow can stay locked past the offer's own
    ///      expiry (see the settlement grace window note on `settle`). It is a hard ceiling in
    ///      bytecode rather than a policy note precisely because the party it protects — the buyer
    ///      — is not the party that sets it.
    uint64 public constant MAX_RESERVATION_DURATION = 30 days;

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLE WIRING
    //////////////////////////////////////////////////////////////*/

    /// @notice The escrow that owns the offer lifecycle. Fixed at construction.
    /// @dev Immutable rather than settable: a repointable escrow would let an admin substitute a
    ///      contract that reports any offer terms it likes, which is an admin path to redirect a
    ///      solver's reimbursement. Repointing requires a redeploy and a fresh role grant.
    IHoodPupOfferEscrow public immutable ESCROW;

    /// @notice The 3-of-5 attestation oracle. Fixed at construction.
    IBitcoinOwnershipOracle public immutable ORACLE;

    /// @notice Pull-payment vault every wei of bond flows out through. Fixed at construction.
    IPayoutVault public immutable PAYOUT_VAULT;

    /*//////////////////////////////////////////////////////////////
                            ADDITIVE ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Raised when ETH is sent to this contract outside `reserve`.
    /// @dev Bond wei must always be attributable to exactly one reservation. An anonymous deposit
    ///      would be unattributable and therefore unrecoverable by its sender.
    error DirectDepositRejected();

    /// @notice Raised when a solver tries to bond an offer that has already expired.
    /// @dev Same name and argument shape as `IHoodPupOfferEscrow.OfferExpired`, so the two share a
    ///      selector and a decoder written against either ABI reads this correctly.
    error OfferExpired(bytes32 offerId, uint64 expiry);

    /// @notice Raised when a BTC offer is missing a field settlement depends on.
    error IncompleteBtcOffer(bytes32 offerId);

    /// @notice Raised when a governance write would not change anything.
    /// @dev House rule across this protocol: a timelock proposal executed twice must not emit a
    ///      second event describing a change that did not occur.
    error ConfigUnchanged();

    /// @notice Raised when `sweepForcedEth` is called with nothing to sweep.
    error NoForcedEth();

    /// @notice Raised if the bond books ever stop balancing. Should be unreachable.
    error BondAccountingBroken(uint256 posted, uint256 active, uint256 returned, uint256 slashed);

    /*//////////////////////////////////////////////////////////////
                            ADDITIVE EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, with the full genesis configuration.
    event SettlementDeployed(
        address indexed admin,
        address escrow,
        address oracle,
        address payoutVault,
        uint256 minimumBondWei,
        uint64 reservationDuration,
        uint16 buyerSlashBps,
        address protocolSlashRecipient
    );

    /// @notice Emitted when the minimum bond changes. Never affects an active reservation.
    event MinimumBondUpdated(uint256 previousWei, uint256 newWei);

    /// @notice Emitted when the reservation window changes. Never affects an active reservation.
    event ReservationDurationUpdated(uint64 previousDuration, uint64 newDuration);

    /// @notice Emitted when the buyer slash share changes. Never affects an active reservation.
    event BuyerSlashBpsUpdated(uint16 previousBps, uint16 newBps);

    /// @notice Emitted when the protocol slash destination changes.
    event ProtocolSlashRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);

    /// @notice Emitted when force-sent ETH is credited to the protocol slash recipient.
    event ForcedEthSwept(address indexed recipient, uint256 amount, address indexed caller);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Governed economic parameters. Every one of these is SNAPSHOTTED into a `Reservation`
    ///      at `reserve` time, so a change here can only ever affect reservations made after it
    ///      lands. The single exception is `_protocolSlashRecipient`; see `expireReservation`.
    uint256 private _minimumBondWei;

    // These three pack into one slot: 64 + 16 + 160 = 240 bits.
    uint64 private _reservationDuration;
    uint16 private _buyerSlashBps;
    address private _protocolSlashRecipient;

    mapping(bytes32 offerId => Reservation) private _reservations;

    /// @dev Roots this contract has itself settled, keyed to the offer that did it. Used as a
    ///      cheap pre-bond guard; see the honesty note on `settledOfferForRoot`.
    mapping(bytes32 rootKey => bytes32 offerId) private _settledOfferForRoot;

    /// @dev The three ledgers behind the bond accounting equation. Cumulative counters never
    ///      decrease, which makes an off-chain reconciliation a subtraction rather than a replay.
    uint256 private _totalActiveBondWei;
    uint256 private _totalBondsPosted;
    uint256 private _totalBondsReturned;
    uint256 private _totalBondsSlashed;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the bonded-solver settlement contract.
    /// @dev Argument list matches `docs/DEPLOYMENT.md` step 9 exactly. `HoodPups` is deliberately
    ///      NOT a constituent: this contract never mints, it asks the escrow to. That keeps
    ///      `MINTER_ROLE` in exactly one place.
    ///
    ///      No role beyond `DEFAULT_ADMIN_ROLE`, `CONFIG_ADMIN_ROLE` and `PAUSER_ROLE` exists, and
    ///      all three go to `admin`. Solvers are not a role: anyone who can post a bond can
    ///      reserve, and no admin may nominate one. That is the whole point of a bond.
    /// @param admin Timelocked address granted admin, config and pauser roles.
    /// @param escrow The `HoodPupOfferEscrow` this contract settles against.
    /// @param oracle The `BitcoinOwnershipOracle` that consumes payment attestations.
    /// @param payoutVault The `PayoutVault` every bond flows out through.
    /// @param minimumBondWei_ Minimum bond a solver must post. Must be non-zero.
    /// @param reservationDuration_ Exclusive window a solver gets to prove payment.
    /// @param buyerSlashBps_ Share of a slashed bond that compensates the buyer, in bps.
    /// @param protocolSlashRecipient_ Destination for the non-buyer share of a slashed bond.
    constructor(
        address admin,
        IHoodPupOfferEscrow escrow,
        IBitcoinOwnershipOracle oracle,
        IPayoutVault payoutVault,
        uint256 minimumBondWei_,
        uint64 reservationDuration_,
        uint16 buyerSlashBps_,
        address protocolSlashRecipient_
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (address(escrow) == address(0)) revert ZeroAddress();
        if (address(oracle) == address(0)) revert ZeroAddress();
        if (address(payoutVault) == address(0)) revert ZeroAddress();
        if (protocolSlashRecipient_ == address(0)) revert ZeroAddress();

        // A zero minimum bond would make reservations free, and a free reservation is a free
        // denial-of-service on every BTC offer: grab them all, never pay, lose nothing.
        if (minimumBondWei_ == 0) revert InvalidConfiguration();
        if (reservationDuration_ < MIN_RESERVATION_DURATION || reservationDuration_ > MAX_RESERVATION_DURATION) {
            revert InvalidConfiguration();
        }
        if (buyerSlashBps_ > BPS_DENOMINATOR) revert InvalidConfiguration();

        ESCROW = escrow;
        ORACLE = oracle;
        PAYOUT_VAULT = payoutVault;

        _minimumBondWei = minimumBondWei_;
        _reservationDuration = reservationDuration_;
        _buyerSlashBps = buyerSlashBps_;
        _protocolSlashRecipient = protocolSlashRecipient_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIG_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        emit SettlementDeployed(
            admin,
            address(escrow),
            address(oracle),
            address(payoutVault),
            minimumBondWei_,
            reservationDuration_,
            buyerSlashBps_,
            protocolSlashRecipient_
        );
    }

    /*//////////////////////////////////////////////////////////////
                                RESERVE
    //////////////////////////////////////////////////////////////*/

    /// @notice Post a bond and claim the exclusive right to pay this offer's seller in BTC.
    /// @dev The caller IS the solver. There is no argument for it and no admin function that can
    ///      nominate one, because a solver that somebody else chose is not bonded against its own
    ///      failure — it is bonded against whoever chose it.
    ///
    ///      EVERY ECONOMIC TERM IS SNAPSHOTTED HERE. `bondWei`, `reservationExpiry` and
    ///      `buyerSlashBpsSnapshot` are written into the `Reservation` and are the only values the
    ///      settle and expiry paths ever read. A timelocked change to `minimumBondWei`,
    ///      `reservationDuration` or `buyerSlashBps` therefore cannot retroactively shorten a live
    ///      solver's window or raise the penalty it already accepted. Governance can change the
    ///      deal on offer; it cannot change a deal already struck.
    ///
    ///      OVERPAYMENT IS KEPT, NOT REFUNDED. A solver may bond more than the minimum, and the
    ///      whole `msg.value` becomes the bond. Refunding the excess would mean a value-moving
    ///      external call in the middle of a reservation; keeping it is simpler, is fully
    ///      conserved by the same three ledgers, and is returned in full on settlement.
    /// @param offerId The escrow offer to reserve.
    function reserve(bytes32 offerId) external payable override nonReentrant whenNotPaused {
        uint256 required = _minimumBondWei;
        if (msg.value < required) revert InsufficientBond(msg.value, required);

        Reservation storage r = _reservations[offerId];
        uint8 status = r.status;
        if (status == uint8(ReservationStatus.ACTIVE)) revert AlreadyReserved(offerId, r.solver);

        PuppetTypes.Offer memory offer = ESCROW.getOffer(offerId);

        // A reservation that already settled means this very offer minted the Root. Reporting that
        // as "already reserved" would be a lie in the trace; the Root is gone, permanently.
        if (status == uint8(ReservationStatus.SETTLED)) revert RootAlreadyMinted(offer.rootKey);

        // A DIFFERENT offer for the same Root already settled through this contract. See the
        // honesty note on `settledOfferForRoot` for what this check does NOT cover.
        if (_settledOfferForRoot[offer.rootKey] != bytes32(0)) revert RootAlreadyMinted(offer.rootKey);

        if (offer.status != uint8(PuppetTypes.OfferStatus.BTC_APPROVED)) {
            revert OfferNotBtcApproved(offerId, offer.status);
        }
        // Inclusive: an offer is live through the whole second named by `expiry`.
        if (block.timestamp > offer.expiry) revert OfferExpired(offerId, offer.expiry);

        // The three fields settlement will compare the payment attestation against. Checking them
        // now means a solver can never bond against an offer that is structurally unpayable, and
        // discovers it before it has spent real BTC rather than after.
        if (offer.ownershipDigest == bytes32(0) || offer.btcPayoutScriptHash == bytes32(0) || offer.sellerSats == 0) {
            revert IncompleteBtcOffer(offerId);
        }

        uint64 expiry = uint64(block.timestamp) + _reservationDuration;
        uint16 slashBps = _buyerSlashBps;

        r.solver = msg.sender;
        r.bondWei = msg.value;
        r.reservedAt = uint64(block.timestamp);
        r.reservationExpiry = expiry;
        r.buyerSlashBpsSnapshot = slashBps;
        r.status = uint8(ReservationStatus.ACTIVE);

        _totalBondsPosted += msg.value;
        _totalActiveBondWei += msg.value;
        _assertBondBooksBalance();

        emit Reserved(offerId, msg.sender, msg.value, expiry, slashBps);

        // Interaction last. The escrow's own guard is the authority on whether this offer may move
        // to BTC_RESERVED; if it disagrees with the status we just read, the whole call reverts and
        // no bond is recorded.
        ESCROW.markBtcReserved(offerId, msg.sender, expiry);
    }

    /*//////////////////////////////////////////////////////////////
                                 SETTLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Prove the exact BTC payment happened, mint the HoodPup and take reimbursement.
    /// @dev WHY THIS FUNCTION IS NOT PAUSABLE. By the time it is callable the solver has already
    ///      broadcast an irreversible Bitcoin transaction paying the seller. A pause here would
    ///      leave that payment stranded while the reservation clock kept running toward a slash —
    ///      i.e. it would be a lever that confiscates a solver's BTC *and* its bond. The incident
    ///      lever the specification asks for exists, and it lives where the incident would be:
    ///      `BitcoinOwnershipOracle.pause()` stops `consumeBitcoinPayment` for every consumer at
    ///      once. Pausing the risk source is right; pausing the victim's exit is not.
    ///
    ///      THE SETTLEMENT GRACE WINDOW. Settlement is allowed while the RESERVATION is live, even
    ///      if the OFFER's own expiry has passed. That window is `reservationExpiry - offer.expiry`
    ///      when positive, and is bounded by the `reservationDuration` snapshotted at `reserve`.
    ///      It exists because the alternative is strictly worse: a solver that paid BTC minutes
    ///      before the offer expired would otherwise lose the BTC, lose the bond and watch the
    ///      buyer refund, while the seller keeps the payment. The buyer is not exposed during the
    ///      window — the escrow holds the offer in BTC_RESERVED and refuses to refund it until
    ///      `expireReservation` clears the reservation here.
    ///
    ///      DELIBERATELY NOT DUPLICATED HERE: the attestation's deadline, attestor epoch, policy
    ///      version, signature count, signer membership and signer ordering, and whether this
    ///      Bitcoin output was already consumed. All of those are the oracle's authority. Copying
    ///      them into this contract would create a second source of truth that can silently drift
    ///      from the first. What IS checked here is everything the oracle cannot know: which offer,
    ///      which solver, which script, which amount.
    /// @param offerId The reserved offer being settled.
    /// @param attestation The 3-of-5 attested Bitcoin payment.
    /// @param signatures Attestor signatures, strictly ascending by recovered signer.
    /// @return tokenId The HoodPup minted by the escrow.
    function settle(
        bytes32 offerId,
        PuppetTypes.BitcoinPaymentAttestation calldata attestation,
        bytes[] calldata signatures
    ) external override nonReentrant returns (uint256 tokenId) {
        Reservation storage r = _reservations[offerId];
        if (r.status != uint8(ReservationStatus.ACTIVE)) revert NoActiveReservation(offerId);

        address solver = r.solver;
        // Two separate checks, both required. `msg.sender == solver` stops a permissionless relayer
        // from driving somebody else's settlement (the bond and the seller share would land on the
        // reserved solver, but the relayer would control WHEN and could grief the timing).
        // `attestation.solver == solver` stops a valid attestation naming a different solver from
        // being spent here at all — the oracle would happily consume it, and the reimbursement
        // would then be redirected to whoever the attestors named.
        if (msg.sender != solver) revert NotReservedSolver(msg.sender, solver);
        if (attestation.solver != solver) revert NotReservedSolver(attestation.solver, solver);

        // Inclusive: the reservation is live through the whole second named by its expiry, which
        // is the same boundary convention `expireReservation` uses on the other side.
        if (block.timestamp > r.reservationExpiry) revert ReservationExpired(offerId, r.reservationExpiry);

        bytes32 rootKey = _requirePaymentMatchesOffer(offerId, attestation);

        uint256 bond = r.bondWei;

        // EFFECTS FIRST. The reservation is closed before any external call, so no callback can
        // re-enter settle for this offer even if `nonReentrant` were somehow removed.
        r.status = uint8(ReservationStatus.SETTLED);
        _totalActiveBondWei -= bond;
        _totalBondsReturned += bond;
        _settledOfferForRoot[rootKey] = offerId;
        _assertBondBooksBalance();

        // INTERACTIONS, in the only order that is safe.
        //
        // 1. Consume the payment. This is the authorization: it verifies the quorum, the freshness
        //    context and the deadline, and permanently burns both the digest and the Bitcoin
        //    output key so one real BTC payment can settle at most one offer, ever.
        bytes32 paymentDigest;
        (paymentDigest,) = ORACLE.consumeBitcoinPayment(attestation, signatures);

        // 2. Mint and route. The escrow pays the SELLER share to the solver, because the seller was
        //    already paid in BTC off chain. If this reverts — Root minted by a competing offer, a
        //    recipient that rejects ERC-721, a paused router — the entire transaction rolls back,
        //    including the oracle consumption above. Nothing is half-settled.
        tokenId = ESCROW.finalizeBtcSettlement(offerId, solver, paymentDigest);

        // 3. ONLY NOW is the bond reimbursed. Steps 1 and 2 have both succeeded, so the solver has
        //    provably delivered. Credited rather than pushed: a solver whose fallback reverts must
        //    not be able to brick its own settlement, and a pull payment keeps the ETH exit out of
        //    this contract's reentrancy surface entirely.
        PAYOUT_VAULT.credit{value: bond}(solver);

        _emitSettled(offerId, solver, paymentDigest, attestation, bond);
    }

    /// @dev Every equality the oracle structurally cannot check, because it knows nothing about
    ///      escrow offers. Split out of `settle` so the offer struct's memory lifetime ends before
    ///      the interaction sequence begins; that keeps the stack inside the EVM's 16-slot limit
    ///      without turning on via-IR for the whole workspace.
    /// @return rootKey The offer's canonical Root key, used to record the settlement.
    function _requirePaymentMatchesOffer(bytes32 offerId, PuppetTypes.BitcoinPaymentAttestation calldata attestation)
        private
        view
        returns (bytes32 rootKey)
    {
        PuppetTypes.Offer memory offer = ESCROW.getOffer(offerId);
        if (offer.status != uint8(PuppetTypes.OfferStatus.BTC_RESERVED)) {
            revert OfferNotBtcApproved(offerId, offer.status);
        }

        if (attestation.contextId != offerId) revert PaymentFieldMismatch("contextId");
        // The digest ties this payment to the exact ownership fact the escrow approved, which is
        // what binds the payment to the seller's signed terms rather than to a bare script hash.
        if (attestation.ownershipDigest != offer.ownershipDigest) revert PaymentFieldMismatch("ownershipDigest");
        if (attestation.recipientScriptHash != offer.btcPayoutScriptHash) {
            revert PaymentFieldMismatch("recipientScriptHash");
        }
        // EXACT equality, never "at least". An overpayment is the solver's business; an
        // underpayment must not be settleable, and a range check would make "how much did Bob
        // actually get" unanswerable from on-chain data alone.
        if (attestation.amountSats != offer.sellerSats) revert PaymentFieldMismatch("amountSats");

        rootKey = offer.rootKey;
    }

    /// @dev Emitting through a helper keeps eight event arguments off `settle`'s stack.
    function _emitSettled(
        bytes32 offerId,
        address solver,
        bytes32 paymentDigest,
        PuppetTypes.BitcoinPaymentAttestation calldata attestation,
        uint256 bond
    ) private {
        emit Settled(
            offerId,
            solver,
            paymentDigest,
            attestation.bitcoinTxid,
            attestation.outputIndex,
            attestation.amountSats,
            attestation.recipientScriptHash,
            bond
        );
    }

    /*//////////////////////////////////////////////////////////////
                            EXPIRY AND SLASHING
    //////////////////////////////////////////////////////////////*/

    /// @notice Permissionless: release a stale reservation and slash its bond.
    /// @dev PERMISSIONLESS BY DESIGN. The buyer, a competing solver, a watcher bot or a passer-by
    ///      may all call this. Gating it would make the buyer's refund depend on a privileged
    ///      party's liveness, and there is nothing to gate: the amounts and destinations are fully
    ///      determined by the snapshot, so the caller has no discretion whatsoever.
    ///
    ///      NOT PAUSABLE, EVER. Pausing may block new risk-taking; it must never block a path that
    ///      returns money. This is that path: it is what lets the buyer's escrow become refundable
    ///      again and what pays the buyer its compensation.
    ///
    ///      NO DISCRETIONARY FORGIVENESS EXISTS. There is no admin function that can cancel,
    ///      shorten, extend or waive an individual slash. Such a function would be a rug lever
    ///      wearing a customer-service badge: whoever holds it could privately promise one solver
    ///      immunity and thereby hand it a free option on every BTC offer in the system. If the
    ///      slash policy is too harsh for real Bitcoin confirmation latency, the honest fix is a
    ///      longer `reservationDuration` or a lower `buyerSlashBps` — both public, both timelocked,
    ///      and both applying only to reservations made after they land.
    ///
    ///      CONSERVATION IS EXACT. `protocolAmount` is the REMAINDER, never an independently
    ///      computed percentage, so `buyerCompensation + protocolAmount == bondWei` holds for every
    ///      bond and every bps value including the rounding-dust cases. Zero-valued shares are
    ///      filtered out rather than sent, because `PayoutVault` correctly rejects a zero credit.
    /// @param offerId The offer whose reservation has run out.
    function expireReservation(bytes32 offerId) external override nonReentrant {
        Reservation storage r = _reservations[offerId];
        if (r.status != uint8(ReservationStatus.ACTIVE)) revert NoActiveReservation(offerId);

        uint64 reservationExpiry = r.reservationExpiry;
        if (block.timestamp <= reservationExpiry) revert ReservationNotExpired(offerId, reservationExpiry);

        address solver = r.solver;
        uint256 bond = r.bondWei;
        uint16 slashBps = r.buyerSlashBpsSnapshot;

        // EFFECTS FIRST.
        r.status = uint8(ReservationStatus.EXPIRED);
        _totalActiveBondWei -= bond;
        _totalBondsSlashed += bond;
        _assertBondBooksBalance();

        // The buyer is read from the escrow rather than snapshotted because an offer's buyer is
        // immutable there; snapshotting it would duplicate a fact that cannot change.
        PuppetTypes.Offer memory offer = ESCROW.getOffer(offerId);

        uint256 buyerCompensation = (bond * slashBps) / BPS_DENOMINATOR;
        uint256 protocolAmount = bond - buyerCompensation;

        // Return the offer to BTC_APPROVED so another solver can bond it, or so the buyer can
        // refund it if it has since expired. Called without try/catch: the escrow only reaches
        // BTC_RESERVED through this contract and only leaves it through this contract, so a revert
        // here means the two are already inconsistent, and quietly proceeding would bury that.
        ESCROW.clearBtcReservation(offerId);

        emit ReservationExpiredAndSlashed(offerId, solver, bond, buyerCompensation, protocolAmount);

        _creditSlash(offer.buyer, buyerCompensation, _protocolSlashRecipient, protocolAmount);
    }

    /// @dev Pays out a slashed bond in at most one `PayoutVault` call.
    ///      Filtering zero shares matters more than it looks: `buyerSlashBps == 0` or `== 10000`
    ///      are both legitimate governance choices, and small bonds round one share to zero. A
    ///      naive two-entry batch would revert `ZeroAmount` on exactly those inputs and would make
    ///      an expiry — a refund path — permanently uncallable.
    function _creditSlash(address buyer, uint256 buyerCompensation, address protocolRecipient, uint256 protocolAmount)
        private
    {
        if (buyerCompensation != 0 && protocolAmount != 0) {
            address[] memory beneficiaries = new address[](2);
            uint256[] memory amounts = new uint256[](2);
            beneficiaries[0] = buyer;
            amounts[0] = buyerCompensation;
            beneficiaries[1] = protocolRecipient;
            amounts[1] = protocolAmount;
            PAYOUT_VAULT.creditBatch{value: buyerCompensation + protocolAmount}(beneficiaries, amounts);
        } else if (buyerCompensation != 0) {
            PAYOUT_VAULT.credit{value: buyerCompensation}(buyer);
        } else if (protocolAmount != 0) {
            PAYOUT_VAULT.credit{value: protocolAmount}(protocolRecipient);
        }
        // A zero bond is impossible (`minimumBondWei` is non-zero and immutable in effect for the
        // life of a reservation), so at least one branch always runs. The final `else` is left
        // unwritten rather than reverting, because a revert there would be unreachable code
        // pretending to be a guard.
    }

    /*//////////////////////////////////////////////////////////////
                              FORCED ETH
    //////////////////////////////////////////////////////////////*/

    /// @notice Credit any ETH that is not backing an active reservation to the protocol recipient.
    /// @dev Anyone may call this and nobody chooses the destination: it is read from the governed
    ///      `protocolSlashRecipient` at execution time and the amount is computed as
    ///      `balance - totalActiveBondWei`, so it is structurally incapable of touching a bond.
    ///      That is what keeps it from being the "hidden owner withdrawal" the protocol rules
    ///      forbid — there is no privileged caller and no discretion for a timelock to delay.
    ///
    ///      ETH can only get here by `selfdestruct` or a block reward, neither of which carries an
    ///      identifiable sender, so returning it is impossible rather than merely inconvenient.
    /// @return amount Wei credited.
    function sweepForcedEth() external nonReentrant returns (uint256 amount) {
        amount = address(this).balance - _totalActiveBondWei;
        if (amount == 0) revert NoForcedEth();

        address recipient = _protocolSlashRecipient;
        emit ForcedEthSwept(recipient, amount, msg.sender);
        PAYOUT_VAULT.credit{value: amount}(recipient);
    }

    /// @dev No plain ETH transfer is ever legitimate here; bond wei must arrive through `reserve`
    ///      so it is attributable to exactly one reservation.
    receive() external payable {
        revert DirectDepositRejected();
    }

    /// @dev Same reasoning as `receive`, and it also turns a mistyped selector into a clear revert
    ///      instead of a silent donation.
    fallback() external payable {
        revert DirectDepositRejected();
    }

    /*//////////////////////////////////////////////////////////////
                             CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the minimum bond required of future reservations.
    /// @dev Cannot affect an active reservation: the bond in force is the one snapshotted at
    ///      `reserve`, and this value is never read again after that.
    /// @param newMinimumBondWei New minimum, in wei. Must be non-zero.
    function setMinimumBondWei(uint256 newMinimumBondWei) external onlyRole(CONFIG_ADMIN_ROLE) {
        if (newMinimumBondWei == 0) revert InvalidConfiguration();
        uint256 previous = _minimumBondWei;
        if (previous == newMinimumBondWei) revert ConfigUnchanged();

        _minimumBondWei = newMinimumBondWei;
        emit MinimumBondUpdated(previous, newMinimumBondWei);
    }

    /// @notice Set the window future solvers get to prove payment.
    /// @dev Bounded by `MIN_RESERVATION_DURATION` / `MAX_RESERVATION_DURATION` in bytecode. The
    ///      lower bound protects solvers from being slashed for Bitcoin's latency; the upper bound
    ///      protects buyers from having their escrow locked indefinitely past an offer's expiry.
    /// @param newDuration New reservation window in seconds.
    function setReservationDuration(uint64 newDuration) external onlyRole(CONFIG_ADMIN_ROLE) {
        if (newDuration < MIN_RESERVATION_DURATION || newDuration > MAX_RESERVATION_DURATION) {
            revert InvalidConfiguration();
        }
        uint64 previous = _reservationDuration;
        if (previous == newDuration) revert ConfigUnchanged();

        _reservationDuration = newDuration;
        emit ReservationDurationUpdated(previous, newDuration);
    }

    /// @notice Set the share of a future slashed bond that compensates the buyer.
    /// @dev Both extremes are permitted. 10000 sends the whole bond to the buyer; 0 sends it all to
    ///      the protocol. Neither is a safety problem — conservation holds either way — and
    ///      forbidding them would be an aesthetic rule, not a security one.
    /// @param newBps New buyer share in basis points. Must be at most 10000.
    function setBuyerSlashBps(uint16 newBps) external onlyRole(CONFIG_ADMIN_ROLE) {
        if (newBps > BPS_DENOMINATOR) revert InvalidConfiguration();
        uint16 previous = _buyerSlashBps;
        if (previous == newBps) revert ConfigUnchanged();

        _buyerSlashBps = newBps;
        emit BuyerSlashBpsUpdated(previous, newBps);
    }

    /// @notice Set where the non-buyer share of a slashed bond goes.
    /// @dev THE ONE PARAMETER THAT IS NOT SNAPSHOTTED, and deliberately so. It is a protocol
    ///      destination, not a term of the solver's bargain: changing it cannot alter how much the
    ///      solver loses or how much the buyer receives, only which protocol address receives a
    ///      share the solver had already forfeited. Snapshotting it would freeze a possibly
    ///      compromised address into every live reservation, which is strictly worse.
    /// @param newRecipient New protocol destination. Must be non-zero.
    function setProtocolSlashRecipient(address newRecipient) external onlyRole(CONFIG_ADMIN_ROLE) {
        if (newRecipient == address(0)) revert ZeroAddress();
        address previous = _protocolSlashRecipient;
        if (previous == newRecipient) revert ConfigUnchanged();

        _protocolSlashRecipient = newRecipient;
        emit ProtocolSlashRecipientUpdated(previous, newRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                                  PAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice Stop new reservations. Settlement, expiry and slash credits stay live.
    /// @dev The complete list of things this blocks is one function: `reserve`. It cannot block a
    ///      solver from settling a payment it has already made, cannot block an expiry, cannot
    ///      block a buyer's compensation and cannot block a withdrawal (which lives in
    ///      `PayoutVault` and is unpausable there).
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Allow new reservations again.
    /// @dev `DEFAULT_ADMIN_ROLE`, not `PAUSER_ROLE`: a hot guardian key may stop risk in seconds,
    ///      but restarting it is a governed decision.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBtcSolverSettlement
    /// @param offerId The offer to look up.
    /// @return The reservation record. A never-reserved offer returns an all-zero struct with
    ///         `status == ReservationStatus.NONE`; this view never reverts.
    function reservationOf(bytes32 offerId) external view override returns (Reservation memory) {
        return _reservations[offerId];
    }

    /// @inheritdoc IBtcSolverSettlement
    function minimumBondWei() external view override returns (uint256) {
        return _minimumBondWei;
    }

    /// @inheritdoc IBtcSolverSettlement
    function reservationDuration() external view override returns (uint64) {
        return _reservationDuration;
    }

    /// @inheritdoc IBtcSolverSettlement
    function buyerSlashBps() external view override returns (uint16) {
        return _buyerSlashBps;
    }

    /// @inheritdoc IBtcSolverSettlement
    function protocolSlashRecipient() external view override returns (address) {
        return _protocolSlashRecipient;
    }

    /// @notice Sum of the bonds of every currently ACTIVE reservation.
    /// @return The contract's total bond liability in wei.
    function totalActiveBondWei() external view returns (uint256) {
        return _totalActiveBondWei;
    }

    /// @notice Cumulative wei ever posted as bonds. Never decreases.
    function totalBondsPosted() external view returns (uint256) {
        return _totalBondsPosted;
    }

    /// @notice Cumulative wei ever credited back to solvers on settlement. Never decreases.
    function totalBondsReturned() external view returns (uint256) {
        return _totalBondsReturned;
    }

    /// @notice Cumulative wei ever slashed and split on expiry. Never decreases.
    function totalBondsSlashed() external view returns (uint256) {
        return _totalBondsSlashed;
    }

    /// @notice The offer that settled a Root through THIS contract, or zero.
    /// @dev HONESTY NOTE: this records only settlements this contract performed. A Root minted
    ///      through the ETH path (`HoodPupOfferEscrow.settlePaidEvm`) or by a self-cast is
    ///      invisible here, because the deployment-pinned constructor gives this contract no
    ///      `HoodPups` reference to ask. A solver MUST therefore check `HoodPups.rootMinted`
    ///      off chain before bonding; the guard in `reserve` catches the competing-BTC-offer case
    ///      only. The authoritative one-Root-one-HoodPup rule is enforced where the mint happens,
    ///      in `HoodPups.mintRooted`, and a settlement that races it reverts in full.
    /// @param rootKey Canonical Root key.
    /// @return offerId The settling offer id, or zero.
    function settledOfferForRoot(bytes32 rootKey) external view returns (bytes32 offerId) {
        return _settledOfferForRoot[rootKey];
    }

    /// @notice ETH held here that is not backing an active reservation.
    /// @dev Non-zero only when ETH has been forced in by `selfdestruct` or a block reward, since
    ///      `receive`/`fallback` reject every ordinary transfer.
    function forcedEthBalance() external view returns (uint256) {
        return address(this).balance - _totalActiveBondWei;
    }

    /// @notice True while the bond accounting equation holds. Should never be false.
    /// @dev Exposed so a monitoring service can assert the same equation the contract enforces
    ///      internally, without having to reconstruct it from four separate getters and risk
    ///      writing the equation down differently.
    function bondBooksBalance() external view returns (bool) {
        return _totalBondsPosted == _totalActiveBondWei + _totalBondsReturned + _totalBondsSlashed;
    }

    /// @inheritdoc IERC165
    /// @param interfaceId The ERC-165 identifier being queried.
    /// @return True if this contract implements `interfaceId`.
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return interfaceId == type(IBtcSolverSettlement).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Re-derives the bond accounting equation after every ledger write and reverts if it has
    ///      stopped holding. This is defence in depth, not a correctness requirement: the three
    ///      call sites are already written so that each bond moves between exactly two counters in
    ///      one statement pair. It is kept anyway, at the cost of four SLOADs on a value-moving
    ///      path, because "the books balanced when this transaction ended" is the single property
    ///      a solver's money depends on, and a future edit that adds a fourth ledger movement
    ///      should fail loudly rather than drift quietly. Clarity and safety over gas, explicitly.
    function _assertBondBooksBalance() private view {
        uint256 posted = _totalBondsPosted;
        uint256 active = _totalActiveBondWei;
        uint256 returned = _totalBondsReturned;
        uint256 slashed = _totalBondsSlashed;
        if (posted != active + returned + slashed) {
            revert BondAccountingBroken(posted, active, returned, slashed);
        }
    }
}
