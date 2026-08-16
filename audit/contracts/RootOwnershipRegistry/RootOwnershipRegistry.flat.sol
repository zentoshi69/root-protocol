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
    /// @notice Emitted alongside `Credited` when an existing cross-chain obligation is finalized.
    /// @dev Terminal credits deliberately remain executable while ordinary liability creation is
    ///      paused. Authorized callers may use them only after the protocol has already incurred
    ///      an irreversible obligation, such as a solver payment or a bond resolution.
    event TerminalCredited(address indexed beneficiary, uint256 amount, address indexed creditor);
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

    /// @notice Credit an obligation that existed before the current transaction.
    /// @dev Requires `CREDITOR_ROLE`. Deliberately NOT pausable so incident response cannot strand
    ///      a solver after an irreversible Bitcoin payment or block terminal bond accounting.
    function creditTerminal(address beneficiary) external payable;

    /// @notice Credit a Root's pending bucket with `msg.value`. Requires `CREDITOR_ROLE`.
    function creditRoot(bytes32 rootKey) external payable;

    /// @notice Credit several beneficiaries in one call. `sum(amounts)` must equal `msg.value`.
    function creditBatch(address[] calldata beneficiaries, uint256[] calldata amounts) external payable;

    /// @notice Batch form of `creditTerminal`; `sum(amounts)` must equal `msg.value`.
    /// @dev Requires `CREDITOR_ROLE` and deliberately remains live while paused.
    function creditTerminalBatch(address[] calldata beneficiaries, uint256[] calldata amounts) external payable;

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
    /// @notice Protocol-wide ceiling for a bonded solver reservation.
    /// @dev Both the escrow and solver coordinator reference this value so their acceptance
    ///      windows cannot drift into a configuration where every reservation reverts.
    uint64 internal constant MAX_BTC_RESERVATION_DURATION = 30 days;

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

// src/interfaces/IRootOwnershipRegistry.sol

/// @title IRootOwnershipRegistry
/// @notice Tracks which Bitcoin controller is currently verified for each Root, as ownership epochs.
/// @dev This registry records ATTESTED state, not live Bitcoin state. When Bob sells his Puppet
///      on Bitcoin, the registry keeps naming Bob until a watcher submits a spend attestation.
///      That lag is an unavoidable property of the design and is documented in
///      `docs/TRUST_ASSUMPTIONS.md`. Recurring value accrued during the lag is recoverable
///      because it lands in the Root's pending bucket once the epoch closes.
interface IRootOwnershipRegistry {
    error ZeroAddress();
    error ZeroRootKey();
    error RootAlreadyActive(bytes32 rootKey, uint64 epoch);
    error RootNotActive(bytes32 rootKey);
    error RootMismatch(bytes32 expected, bytes32 provided);
    error OutpointMismatch(bytes32 expected, bytes32 provided);
    error StaleBitcoinHeight(uint64 provided, uint64 current);
    error ConflictingBitcoinBlockAtHeight(uint64 height, bytes32 recordedBlockHash, bytes32 providedBlockHash);
    error UnchangedOutpoint(bytes32 outpointHash);
    error InvalidBeneficiary();
    error UnsupportedPurpose(uint8 purpose);

    event RootEpochActivated(
        bytes32 indexed rootKey,
        uint64 indexed epoch,
        address indexed beneficiary,
        bytes32 outpointHash,
        bytes32 ownerScriptHash,
        uint64 bitcoinHeight,
        bytes32 ownershipDigest
    );
    event RootEpochInvalidated(
        bytes32 indexed rootKey,
        uint64 indexed epoch,
        address indexed previousBeneficiary,
        bytes32 spendingTxid,
        uint64 bitcoinHeight
    );
    event RootPendingReleased(bytes32 indexed rootKey, address indexed beneficiary, uint256 amount);

    /// @notice Full current state for a Root.
    function currentState(bytes32 rootKey) external view returns (PuppetTypes.RootState memory);

    /// @notice The address that should receive Root-linked value right now.
    /// @return beneficiary Zero if no epoch was ever activated.
    /// @return active False when the inscription is known to have moved.
    /// @return epoch Current epoch number; zero if never activated.
    function currentBeneficiary(bytes32 rootKey) external view returns (address beneficiary, bool active, uint64 epoch);

    /// @notice True when the recorded owner is currently believed valid.
    function isActive(bytes32 rootKey) external view returns (bool);

    /// @notice Current epoch number for a Root; zero if never activated.
    function epochOf(bytes32 rootKey) external view returns (uint64);

    /// @notice Historical record of one epoch.
    function epochInfo(bytes32 rootKey, uint64 epoch) external view returns (PuppetTypes.RootEpochInfo memory);

    /// @notice Record the first ownership epoch as part of a mint settlement.
    /// @dev Requires `MINT_RECORDER_ROLE`. The caller must already have consumed the attestation
    ///      through the oracle; this function trusts its authorized caller for that, and binds the
    ///      exact facts it is handed.
    function recordMintOwnership(
        bytes32 rootKey,
        address beneficiary,
        bytes32 outpointHash,
        bytes32 ownerScriptHash,
        bytes32 ownershipDigest,
        bytes32 bip322ProofHash,
        bytes32 bitcoinBlockHash,
        uint64 bitcoinHeight
    ) external returns (uint64 epoch);

    /// @notice Permissionless: prove current Bitcoin control and start a new ownership epoch.
    /// @dev Purpose must be `ROOT_BIND`. Releases any pending Root balance to the new beneficiary.
    function bindRootOwner(
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external returns (uint64 epoch, uint256 releasedPending);

    /// @notice Permissionless: prove the recorded inscription outpoint was spent and close the epoch.
    function invalidateRoot(
        PuppetTypes.RootSpendAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external;
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

// src/types/PuppetHashing.sol

/// @title PuppetHashing
/// @notice The single source of truth for every security-relevant hash in the protocol.
/// @dev Rules enforced across this library, and mirrored byte-for-byte in
///      `packages/protocol-sdk` and the attestor services:
///
///      1. NEVER `abi.encodePacked` a multi-field identifier. Packed encoding of two dynamic or
///         two variable-width fields is ambiguous and creates collisions. Everything here uses
///         `abi.encode`, which is 32-byte-word aligned and unambiguous.
///      2. Every hash is domain separated by a constant string so a preimage for one hash family
///         can never be reinterpreted as another.
///      3. Attestation `encodeData` is built with `bytes.concat` of two `abi.encode` chunks.
///         The concatenation is bit-identical to a single `abi.encode` of all fields (every field
///         is a value type, so each occupies exactly one 32-byte word). Chunking exists purely to
///         stay under the EVM's 16-slot stack limit without enabling via-IR.
///
///      Golden vectors covering every function live in `test/unit/PuppetHashing.t.sol` and
///      `data/test-fixtures/hashing-vectors.json`, and CI fails if Solidity and TypeScript diverge.
library PuppetHashing {
    /*//////////////////////////////////////////////////////////////
                             DOMAIN CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Identifies this protocol deployment's canonical Bitcoin Puppets manifest.
    /// @dev "Canonical" means canonical *to this deployment*. It is not, and must never be
    ///      presented as, an endorsement by the Bitcoin Puppets project.
    bytes32 internal constant COLLECTION_ID = keccak256("BITCOIN_PUPPETS_MAINNET_V1");

    /// @dev Domain tag for `outpointHash`, keeping outpoint preimages disjoint from root preimages.
    bytes32 internal constant OUTPOINT_DOMAIN = keccak256("HOODPUPS_BITCOIN_OUTPOINT_V1");

    /// @dev Domain tag for `paymentOutputKey`. Deliberately distinct from `OUTPOINT_DOMAIN` so an
    ///      inscription outpoint can never be mistaken for a consumed BTC payment output.
    bytes32 internal constant PAYMENT_OUTPUT_DOMAIN = keccak256("HOODPUPS_BITCOIN_PAYMENT_OUTPUT_V1");

    /// @dev Domain tag for the immutable offer terms commitment.
    bytes32 internal constant OFFER_TERMS_DOMAIN = keccak256("HOODPUPS_OFFER_TERMS_V1");

    /// @dev Domain tag for deterministic offer identifiers.
    bytes32 internal constant OFFER_ID_DOMAIN = keccak256("HOODPUPS_OFFER_ID_V1");

    /*//////////////////////////////////////////////////////////////
                           EIP-712 TYPE STRINGS
    //////////////////////////////////////////////////////////////*/

    /// @dev Field order MUST match `PuppetTypes.OwnershipAttestation` exactly.
    string internal constant OWNERSHIP_ATTESTATION_TYPE = "OwnershipAttestation(" "uint8 purpose," "bytes32 rootTxid,"
        "uint32 rootIndex," "bytes32 contextId," "bytes32 offerTermsHash," "bytes32 currentOutpointHash,"
        "bytes32 ownerScriptHash," "bytes32 bip322ProofHash," "address buyer," "address recipient," "uint8 payoutMode,"
        "address evmPayout," "bytes32 btcPayoutScriptHash," "uint64 sellerSats," "uint256 grossWei,"
        "uint256 sellerWei," "bytes32 bitcoinBlockHash," "uint64 bitcoinHeight," "bytes32 authorizationId,"
        "uint64 deadline," "uint64 attestorEpoch," "uint32 policyVersion" ")";

    /// @dev Field order MUST match `PuppetTypes.BitcoinPaymentAttestation` exactly.
    string internal constant BITCOIN_PAYMENT_ATTESTATION_TYPE = "BitcoinPaymentAttestation(" "bytes32 contextId,"
        "bytes32 ownershipDigest," "address solver," "bytes32 bitcoinTxid," "uint32 outputIndex,"
        "bytes32 recipientScriptHash," "uint64 amountSats," "bytes32 bitcoinBlockHash," "uint64 bitcoinHeight,"
        "bytes32 authorizationId," "uint64 deadline," "uint64 attestorEpoch," "uint32 policyVersion" ")";

    /// @dev Field order MUST match `PuppetTypes.RootSpendAttestation` exactly.
    string internal constant ROOT_SPEND_ATTESTATION_TYPE = "RootSpendAttestation(" "bytes32 rootTxid,"
        "uint32 rootIndex," "bytes32 previousOutpointHash," "bytes32 spendingTxid," "bytes32 bitcoinBlockHash,"
        "uint64 bitcoinHeight," "bytes32 authorizationId," "uint64 deadline," "uint64 attestorEpoch,"
        "uint32 policyVersion" ")";

    /// @dev EIP-712 type used by `PayoutVault.withdrawWithAuthorization`.
    string internal constant WITHDRAWAL_TYPE = "Withdrawal(" "address beneficiary," "address recipient,"
        "uint256 amount," "uint256 nonce," "uint64 deadline" ")";

    /*//////////////////////////////////////////////////////////////
                            EIP-712 TYPE HASHES
    //////////////////////////////////////////////////////////////*/

    bytes32 internal constant OWNERSHIP_ATTESTATION_TYPEHASH = keccak256(bytes(OWNERSHIP_ATTESTATION_TYPE));
    bytes32 internal constant BITCOIN_PAYMENT_ATTESTATION_TYPEHASH = keccak256(bytes(BITCOIN_PAYMENT_ATTESTATION_TYPE));
    bytes32 internal constant ROOT_SPEND_ATTESTATION_TYPEHASH = keccak256(bytes(ROOT_SPEND_ATTESTATION_TYPE));
    bytes32 internal constant WITHDRAWAL_TYPEHASH = keccak256(bytes(WITHDRAWAL_TYPE));

    /*//////////////////////////////////////////////////////////////
                            IDENTITY HASHING
    //////////////////////////////////////////////////////////////*/

    /// @notice Canonical protocol key for one Bitcoin Puppet inscription.
    /// @dev `keccak256(abi.encode(COLLECTION_ID, inscriptionTxid, inscriptionIndex))`.
    ///      Two inscriptions sharing a reveal txid but differing by index produce different keys,
    ///      because `inscriptionIndex` occupies its own 32-byte word.
    function rootKey(bytes32 inscriptionTxid, uint32 inscriptionIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(COLLECTION_ID, inscriptionTxid, inscriptionIndex));
    }

    /// @notice Canonical protocol key for a `RootId` struct.
    function rootKey(PuppetTypes.RootId memory root) internal pure returns (bytes32) {
        return rootKey(root.inscriptionTxid, root.inscriptionIndex);
    }

    /// @notice Merkle leaf for the canonical collection tree.
    /// @dev Double hashed (`keccak256` of the 32-byte `rootKey`) following the OpenZeppelin
    ///      `StandardMerkleTree` convention. The second hash makes an internal node preimage
    ///      structurally impossible to present as a leaf, which defeats second-preimage attacks.
    ///      The off-chain builder in `packages/protocol-sdk` reproduces this exactly.
    function collectionLeaf(bytes32 key) internal pure returns (bytes32) {
        return keccak256(bytes.concat(key));
    }

    /// @notice Merkle leaf for a `RootId`.
    function collectionLeaf(PuppetTypes.RootId memory root) internal pure returns (bytes32) {
        return collectionLeaf(rootKey(root));
    }

    /// @notice Hash of a Bitcoin outpoint (`txid:vout`) holding an inscription.
    /// @param bitcoinTxid Txid in display order.
    /// @param vout Output index.
    function outpointHash(bytes32 bitcoinTxid, uint32 vout) internal pure returns (bytes32) {
        return keccak256(abi.encode(OUTPOINT_DOMAIN, bitcoinTxid, vout));
    }

    /// @notice Global uniqueness key for a Bitcoin output used to pay a seller.
    /// @dev Consuming this key in `BitcoinOwnershipOracle` is what stops one BTC payment from
    ///      settling more than one offer.
    function paymentOutputKey(bytes32 bitcoinTxid, uint32 vout) internal pure returns (bytes32) {
        return keccak256(abi.encode(PAYMENT_OUTPUT_DOMAIN, bitcoinTxid, vout));
    }

    /// @notice Hash of a raw Bitcoin `scriptPubKey`.
    /// @dev Takes the raw script bytes, never a bech32/base58 address string. Address strings are
    ///      network- and encoding-dependent and are therefore unsafe as a security primitive.
    function scriptHash(bytes memory rawScriptPubKey) internal pure returns (bytes32) {
        return keccak256(rawScriptPubKey);
    }

    /*//////////////////////////////////////////////////////////////
                              OFFER HASHING
    //////////////////////////////////////////////////////////////*/

    /// @notice Deterministic offer identifier.
    /// @dev Bound to chain, escrow and buyer so ids cannot collide across deployments.
    function offerId(uint256 chainId, address escrow, address buyer, uint256 buyerNonce)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(OFFER_ID_DOMAIN, chainId, escrow, buyer, buyerNonce));
    }

    /// @notice Immutable commitment to every fixed term of an offer.
    /// @dev The Bitcoin controller signs this hash inside the canonical BIP-322 message, so it is
    ///      what makes "the terms I saw are the terms that execute" enforceable. Any change to a
    ///      bound field invalidates every signature collected for the offer.
    function offerTermsHash(
        uint256 chainId,
        address escrow,
        bytes32 id,
        uint8 kind,
        bytes32 key,
        address buyer,
        address recipient,
        uint256 grossWei,
        uint256 sellerWei,
        uint64 sellerSats,
        uint64 expiry
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OFFER_TERMS_DOMAIN,
                chainId,
                escrow,
                id,
                kind,
                key,
                buyer,
                recipient,
                grossWei,
                sellerWei,
                sellerSats,
                expiry
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                          ATTESTATION STRUCT HASHING
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP-712 `hashStruct` of an `OwnershipAttestation`.
    /// @dev Two-chunk `bytes.concat` is byte-identical to encoding all 23 words at once.
    function hashStruct(PuppetTypes.OwnershipAttestation memory a) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    OWNERSHIP_ATTESTATION_TYPEHASH,
                    a.purpose,
                    a.rootTxid,
                    a.rootIndex,
                    a.contextId,
                    a.offerTermsHash,
                    a.currentOutpointHash,
                    a.ownerScriptHash,
                    a.bip322ProofHash,
                    a.buyer,
                    a.recipient,
                    a.payoutMode
                ),
                abi.encode(
                    a.evmPayout,
                    a.btcPayoutScriptHash,
                    a.sellerSats,
                    a.grossWei,
                    a.sellerWei,
                    a.bitcoinBlockHash,
                    a.bitcoinHeight,
                    a.authorizationId,
                    a.deadline,
                    a.attestorEpoch,
                    a.policyVersion
                )
            )
        );
    }

    /// @notice EIP-712 `hashStruct` of a `BitcoinPaymentAttestation`.
    function hashStruct(PuppetTypes.BitcoinPaymentAttestation memory a) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    BITCOIN_PAYMENT_ATTESTATION_TYPEHASH,
                    a.contextId,
                    a.ownershipDigest,
                    a.solver,
                    a.bitcoinTxid,
                    a.outputIndex,
                    a.recipientScriptHash,
                    a.amountSats
                ),
                abi.encode(
                    a.bitcoinBlockHash, a.bitcoinHeight, a.authorizationId, a.deadline, a.attestorEpoch, a.policyVersion
                )
            )
        );
    }

    /// @notice EIP-712 `hashStruct` of a `RootSpendAttestation`.
    function hashStruct(PuppetTypes.RootSpendAttestation memory a) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ROOT_SPEND_ATTESTATION_TYPEHASH,
                a.rootTxid,
                a.rootIndex,
                a.previousOutpointHash,
                a.spendingTxid,
                a.bitcoinBlockHash,
                a.bitcoinHeight,
                a.authorizationId,
                a.deadline,
                a.attestorEpoch,
                a.policyVersion
            )
        );
    }

    /// @notice EIP-712 `hashStruct` of a gasless `Withdrawal` authorization.
    function hashWithdrawal(address beneficiary, address recipient, uint256 amount, uint256 nonce, uint64 deadline)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(WITHDRAWAL_TYPEHASH, beneficiary, recipient, amount, nonce, deadline));
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

// src/RootOwnershipRegistry.sol

/// @title RootOwnershipRegistry
/// @notice Records which Bitcoin controller is currently *attested* to own each Root, as a chain of
///         monotonic ownership epochs, and routes Root-linked value to that controller.
/// @dev WHAT THIS CONTRACT IS FOR. Recurring Root-linked value (tour revenue, protocol fee shares)
///      has to be paid to somebody. "Somebody" is whoever currently controls the Bitcoin Puppet
///      inscription. This contract is the only place in the protocol that answers that question,
///      and every answer it gives comes from exactly two sources:
///
///        1. a 3-of-5 quorum attestation consumed through `BitcoinOwnershipOracle`, or
///        2. the authorized escrow's `MINT_RECORDER_ROLE` call, made immediately after the escrow
///           itself consumed a mint ownership attestation through the same oracle.
///
///      There is no third source. No admin function assigns, reassigns or clears a beneficiary,
///      and there is no path by which governance can point a Root at an address of its choosing.
///
///      TRUST BOUNDARY — READ THIS BEFORE TRUSTING ANY VALUE THIS CONTRACT RETURNS. Nothing here
///      verifies Bitcoin consensus. Bitcoin facts are asserted by a 3-of-5 quorum of independent
///      attestor operators. This is an attested settlement system, not a trustless bridge. The
///      original Bitcoin Puppet never leaves Bitcoin: it is never bridged, wrapped, custodied or
///      escrowed, and nothing in this contract can move it.
///
///      THE STALE-WATCHER WINDOW — THE MOST IMPORTANT CAVEAT IN THIS FILE.
///      This registry records attested state, not live state. When Bob sells his Puppet on Bitcoin,
///      this contract keeps naming Bob until somebody submits a `RootSpendAttestation` proving the
///      recorded outpoint was spent. Between the Bitcoin spend and that submission, recurring
///      Root-linked value routed through `FeeRouter` is credited to Bob, and Charlie cannot recover
///      it. That window is unavoidable in an attested design; it can be made short, never zero.
///
///      Four properties bound the damage, and each one is enforced somewhere in this file or its
///      immediate neighbours:
///        * Only RECURRING value is exposed. A new mint needs a fresh ownership proof, which a
///          seller who no longer controls the inscription cannot produce.
///        * Once the epoch closes, future value accrues to `PayoutVault.pendingByRoot(rootKey)`
///          and is released to whoever next proves control — not to the stale beneficiary.
///        * `invalidateRoot` is PERMISSIONLESS. Charlie, who has the strongest possible incentive,
///          does not need anyone's permission to close Bob's epoch, and neither does a watcher bot.
///        * `bindRootOwner` is PERMISSIONLESS too, so Charlie's own bind can supersede an active
///          stale epoch directly (new outpoint, non-decreasing Bitcoin height) without waiting for
///          a separate invalidation.
///      The window is real. Front-end copy must say so; see `docs/TRUST_ASSUMPTIONS.md`.
///
///      MONEY ALREADY EARNED IS NEVER CLAWED BACK. Closing an epoch touches this contract's
///      bookkeeping only. Balances already credited inside `PayoutVault` belong to the address they
///      were credited to, permanently, and neither an invalidation nor a rebind can reduce them.
///      That is why the invalidation path writes no vault call at all.
///
///      PAUSING. `whenNotPaused` appears on `bindRootOwner` and `invalidateRoot` — the two
///      permissionless paths that consume attestations and take on new state — and NOWHERE else.
///      A pause cannot alter recorded state, cannot block any view, cannot block a `PayoutVault`
///      withdrawal, and cannot block `releasePendingRootCredit`, which only forwards value the
///      protocol already owes to an already-recorded owner. `recordMintOwnership` is deliberately
///      not pausable either: pausing this registry must never brick the escrow's settlement path,
///      which has its own pause and its own role gate.
///
///      NON-UPGRADEABLE by construction: no proxy, no initializer, no `delegatecall`, no
///      `selfdestruct`, no `tx.origin`, and no owner EOA — `DEFAULT_ADMIN_ROLE` is intended for a
///      `TimelockController` under multisig control.
contract RootOwnershipRegistry is IRootOwnershipRegistry, AccessControl, Pausable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role permitted to record the FIRST ownership epoch as part of a mint settlement.
    /// @dev Held by `HoodPupOfferEscrow` and nothing else. This role is trusted for one narrow
    ///      claim: "I have just consumed, through the oracle, an ownership attestation carrying
    ///      exactly these facts." It cannot rebind an existing Root, cannot invalidate one, and
    ///      cannot touch any epoch after the first — those checks live in `recordMintOwnership`
    ///      and are not waivable by any role.
    ///
    ///      Deliberately NOT granted at construction: the escrow does not exist yet at deployment
    ///      step 5, and pre-granting it to the deployer would create exactly the EOA-holds-
    ///      privilege state the timelock handover is meant to eliminate.
    bytes32 public constant MINT_RECORDER_ROLE = keccak256("MINT_RECORDER_ROLE");

    /// @notice Role permitted to halt new activations and invalidations.
    /// @dev Asymmetric on purpose, matching the rest of the protocol: `PAUSER_ROLE` may pause (the
    ///      safe direction, so it can be a hot guardian key that reacts in seconds) but only
    ///      `DEFAULT_ADMIN_ROLE` may unpause, because resuming attestation consumption is the
    ///      direction that re-enables risk.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              EXTRA ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when `recordMintOwnership` runs against a Root that already has an epoch.
    /// @dev Distinct from `RootAlreadyActive`, which covers a Root that is currently ACTIVE. A Root
    ///      whose epoch has been closed is not "already active", and reverting with that error
    ///      would be a lie in the trace. One canonical inscription mints at most one HoodPup ever,
    ///      so the mint recorder is single-use per Root either way.
    /// @param rootKey Canonical protocol key of the inscription.
    /// @param epoch The epoch that already exists.
    error RootEpochAlreadyExists(bytes32 rootKey, uint64 epoch);

    /// @notice Thrown when a `ROOT_BIND` attestation does not elect the EVM payout mode.
    /// @dev A `ROOT_BIND` binds an EVM address to a Root. Every other payout mode is incompatible
    ///      with the canonical binding shape and is rejected rather than inventing a beneficiary.
    /// @param payoutMode The `PuppetTypes.PayoutMode` value that was supplied.
    error UnsupportedPayoutMode(uint8 payoutMode);

    /// @notice Thrown when an activation supplies a zero inscription reveal txid.
    /// @dev The shape of a default-initialised struct reaching an activation path.
    error ZeroRootTxid();

    /// @notice Thrown when an activation supplies a zero Bitcoin outpoint hash.
    /// @dev A zero outpoint would make the `UnchangedOutpoint` guard and the invalidation
    ///      `previousOutpointHash` match meaningless, so it is rejected at both entry points.
    error ZeroOutpointHash();

    /// @notice Thrown when an activation supplies a zero owner script hash.
    error ZeroScriptHash();

    /// @notice Thrown when the mint recorder supplies a zero ownership digest.
    /// @dev The digest is the audit link from this epoch back to the attestation the escrow
    ///      consumed. Recording an epoch with no such link would make the history unverifiable.
    error ZeroOwnershipDigest();

    /// @notice Thrown when an attestation carries a zero authorization id.
    /// @dev Belt and braces: the real `BitcoinOwnershipOracle` rejects this too. It is repeated
    ///      here because it is cheap and because a mock oracle used in another suite may not.
    error ZeroAuthorizationId();

    /// @notice Thrown when a spend attestation carries a zero spending txid.
    error ZeroSpendingTxid();

    /// @notice Thrown when a `ROOT_BIND` attestation's `contextId` is neither zero nor the rootKey.
    /// @dev `PuppetTypes` defines `contextId` for `ROOT_BIND` as "zero-or-root-scoped". Enforcing
    ///      that keeps a `ROOT_BIND` signature raised inside some other subsystem's context from
    ///      being replayed here, and costs one comparison.
    /// @param contextId The context that was supplied.
    error InvalidBindContext(bytes32 contextId);

    /// @notice Thrown when the vault releases a different amount than it reported as pending.
    /// @dev Defensive: it can only fire if the vault's `pendingByRoot` view and its
    ///      `releaseRootCredit` accounting disagree, which would be a vault bug. Failing loudly
    ///      beats writing an activation event whose `releasedPending` figure is fiction.
    /// @param expected Amount `pendingByRoot` reported immediately before the release.
    /// @param released Amount `releaseRootCredit` actually moved.
    error PendingReleaseMismatch(uint256 expected, uint256 released);

    /// @notice Thrown when `releasePendingRootCredit` finds nothing to forward.
    /// @param rootKey Canonical protocol key of the inscription.
    error NoPendingRootBalance(bytes32 rootKey);

    /*//////////////////////////////////////////////////////////////
                              EXTRA EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, recording the immutable wiring of this registry.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param oracle The `BitcoinOwnershipOracle` every attestation is consumed through.
    /// @param payoutVault The `PayoutVault` pending Root balances are released from.
    event RegistryInitialized(address indexed admin, address indexed oracle, address indexed payoutVault);

    /// @notice Emitted when a fresh bind closes a still-active epoch without a spend attestation.
    /// @dev Distinct from `RootEpochInvalidated` on purpose. No spend was ever attested here, so
    ///      emitting the invalidation event with a zero `spendingTxid` would tell an indexer that
    ///      a Bitcoin spend happened when none was proven. This event says what actually occurred:
    ///      a newer, non-decreasing-height ownership proof for a DIFFERENT outpoint arrived while
    ///      the old epoch was still open.
    /// @param rootKey Canonical protocol key of the inscription.
    /// @param epoch The epoch being closed.
    /// @param previousBeneficiary Beneficiary that epoch named. Their credited balance is untouched.
    /// @param newEpoch The epoch that supersedes it.
    /// @param bitcoinHeight Bitcoin height of the superseding attestation.
    event RootEpochSuperseded(
        bytes32 indexed rootKey,
        uint64 indexed epoch,
        address indexed previousBeneficiary,
        uint64 newEpoch,
        uint64 bitcoinHeight
    );

    /*//////////////////////////////////////////////////////////////
                             INTERNAL TYPES
    //////////////////////////////////////////////////////////////*/

    /// @dev The seven Bitcoin-side facts an activation binds, carried as one memory struct.
    ///      Grouping them is not cosmetic: passing them individually pushes `_activate` past the
    ///      EVM's 16-slot stack limit with `via_ir` disabled, and enabling `via_ir` for one
    ///      function would change codegen for the whole protocol.
    struct ActivationFacts {
        address beneficiary;
        bytes32 outpointHash;
        bytes32 ownerScriptHash;
        bytes32 ownershipDigest;
        bytes32 bip322ProofHash;
        bytes32 bitcoinBlockHash;
        uint64 bitcoinHeight;
    }

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The oracle every attestation consumed by this registry passes through.
    /// @dev Immutable: a swappable oracle pointer would be an admin path to redefine what counts as
    ///      proof of Bitcoin control, which is the same thing as an admin path to assign ownership.
    ///      Replacing the oracle requires redeploying this registry and repointing its consumers.
    IBitcoinOwnershipOracle public immutable ORACLE;

    /// @notice The vault whose pending Root balances this registry releases.
    /// @dev Immutable for the same reason: the release target must not be governable.
    IPayoutVault public immutable PAYOUT_VAULT;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Current attested state per Root. Written only by `_activate` and `invalidateRoot`.
    mapping(bytes32 => PuppetTypes.RootState) private _rootState;

    /// @dev Per-epoch history. A record's activation fields are written exactly once, when the
    ///      epoch opens, and are never rewritten; only the two deactivation fields are filled in
    ///      later, exactly once, when it closes. That makes the full ownership history of a Root
    ///      reconstructible on chain, not only from events.
    mapping(bytes32 => mapping(uint64 => PuppetTypes.RootEpochInfo)) private _rootEpochInfo;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the registry against a fixed oracle and vault.
    /// @dev `MINT_RECORDER_ROLE` is intentionally left unassigned; see the role's own NatSpec.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`. Must be a
    ///        `TimelockController` in production — never an EOA.
    /// @param oracle Address of the deployed `BitcoinOwnershipOracle`.
    /// @param payoutVault Address of the deployed `PayoutVault`.
    constructor(address admin, address oracle, address payoutVault) {
        if (admin == address(0) || oracle == address(0) || payoutVault == address(0)) revert ZeroAddress();

        ORACLE = IBitcoinOwnershipOracle(oracle);
        PAYOUT_VAULT = IPayoutVault(payoutVault);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        emit RegistryInitialized(admin, oracle, payoutVault);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev Returns a zeroed struct for a Root that has never been activated. `beneficiary` and
    ///      `currentOutpointHash` survive an invalidation on purpose: they are the audit trail of
    ///      who was named and which outpoint was spent. `active` is the single field that decides
    ///      whether value may be paid, and consumers MUST read it rather than assuming a non-zero
    ///      beneficiary means "pay this address".
    /// @param rootKey Canonical protocol key of the inscription.
    function currentState(bytes32 rootKey) external view returns (PuppetTypes.RootState memory) {
        return _rootState[rootKey];
    }

    /// @inheritdoc IRootOwnershipRegistry
    /// @param rootKey Canonical protocol key of the inscription.
    function currentBeneficiary(bytes32 rootKey)
        external
        view
        returns (address beneficiary, bool active, uint64 epoch)
    {
        PuppetTypes.RootState storage s = _rootState[rootKey];
        return (s.beneficiary, s.active, s.epoch);
    }

    /// @inheritdoc IRootOwnershipRegistry
    /// @param rootKey Canonical protocol key of the inscription.
    function isActive(bytes32 rootKey) external view returns (bool) {
        return _rootState[rootKey].active;
    }

    /// @inheritdoc IRootOwnershipRegistry
    /// @param rootKey Canonical protocol key of the inscription.
    function epochOf(bytes32 rootKey) external view returns (uint64) {
        return _rootState[rootKey].epoch;
    }

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev Non-reverting for unknown roots and unknown epochs so integrators need no `try/catch`;
    ///      an unwritten record is all zeroes, and `beneficiary == address(0)` distinguishes it.
    /// @param rootKey Canonical protocol key of the inscription.
    /// @param epoch Epoch number to look up. Epoch numbering starts at 1.
    function epochInfo(bytes32 rootKey, uint64 epoch) external view returns (PuppetTypes.RootEpochInfo memory) {
        return _rootEpochInfo[rootKey][epoch];
    }

    /// @notice ERC-165 support, extended with this registry's own interface id.
    /// @param interfaceId The interface identifier being queried.
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return interfaceId == type(IRootOwnershipRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                          ACTIVATION FROM A MINT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev CALLER TRUST, STATED PRECISELY. This function does not re-verify a quorum; it binds the
    ///      facts it is handed. That is safe only because `MINT_RECORDER_ROLE` is held by the
    ///      escrow, which consumed the very same attestation through the oracle moments earlier in
    ///      the same transaction. The role is therefore trusted for the *provenance* of these
    ///      arguments and nothing else — every structural rule below still applies to it.
    ///
    ///      IT MAKES NO EXTERNAL CALLS, ON PURPOSE. A mint settlement must not be able to fail
    ///      because of the vault's state, its pause flag or a missing role grant, so this path
    ///      never touches `PayoutVault`. If a Root somehow already holds a pending balance when it
    ///      is first minted, that balance is not lost: the same owner can claim it later through
    ///      `bindRootOwner`, or anyone can forward it with `releasePendingRootCredit`.
    ///
    ///      IT IS NOT PAUSABLE, ON PURPOSE. Pausing this registry must never brick the escrow's
    ///      settlement path; the escrow has its own pause and its own role gate for that.
    /// @param rootKey Canonical protocol key of the inscription.
    /// @param beneficiary EVM address that should receive Root-linked value.
    /// @param outpointHash Bitcoin outpoint currently holding the inscription.
    /// @param ownerScriptHash keccak256 of the owning `scriptPubKey`.
    /// @param ownershipDigest Digest of the attestation the escrow consumed.
    /// @param bip322ProofHash Commitment to the normalized BIP-322 proof bytes.
    /// @param bitcoinBlockHash Bitcoin tip hash the attestors observed.
    /// @param bitcoinHeight Bitcoin tip height the attestors observed.
    /// @return epoch Always 1: this path only ever opens a Root's first epoch.
    function recordMintOwnership(
        bytes32 rootKey,
        address beneficiary,
        bytes32 outpointHash,
        bytes32 ownerScriptHash,
        bytes32 ownershipDigest,
        bytes32 bip322ProofHash,
        bytes32 bitcoinBlockHash,
        uint64 bitcoinHeight
    ) external onlyRole(MINT_RECORDER_ROLE) returns (uint64 epoch) {
        if (rootKey == bytes32(0)) revert ZeroRootKey();
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (outpointHash == bytes32(0)) revert ZeroOutpointHash();
        if (ownerScriptHash == bytes32(0)) revert ZeroScriptHash();
        if (ownershipDigest == bytes32(0)) revert ZeroOwnershipDigest();

        PuppetTypes.RootState storage s = _rootState[rootKey];

        // Two separate guards rather than one `epoch != 0`, so the revert reason distinguishes
        // "someone else currently owns this" from "this Root's history has already begun".
        // Neither is waivable, by any role, ever: this is the "do not silently overwrite a
        // different active owner" rule.
        if (s.active) revert RootAlreadyActive(rootKey, s.epoch);
        if (s.epoch != 0) revert RootEpochAlreadyExists(rootKey, s.epoch);

        epoch = _activate(
            rootKey,
            ActivationFacts({
                beneficiary: beneficiary,
                outpointHash: outpointHash,
                ownerScriptHash: ownerScriptHash,
                ownershipDigest: ownershipDigest,
                bip322ProofHash: bip322ProofHash,
                bitcoinBlockHash: bitcoinBlockHash,
                bitcoinHeight: bitcoinHeight
            })
        );
    }

    /*//////////////////////////////////////////////////////////////
                         PERMISSIONLESS REBINDING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev ORDERING. Cheap local checks run first so a doomed call cannot waste a quorum's work;
    ///      then the attestation is consumed through the oracle; then state is written; then the
    ///      vault is asked to release the Root's pending bucket. The oracle call precedes the state
    ///      writes because it IS the authorization — there is nothing to write until it succeeds —
    ///      and it is an immutable, trusted protocol contract. `nonReentrant` covers the residual
    ///      risk of any external call re-entering this function, so the deviation from textbook
    ///      checks-effects-interactions cannot be exploited.
    ///
    ///      A FAILED RELEASE FAILS THE WHOLE BIND, deliberately. The alternative — swallowing the
    ///      vault error and advancing the epoch anyway — would strand the Root's pending balance
    ///      with no path to release it, because releases are only ever driven from an epoch change.
    ///      An activation is all-or-nothing, including its money routing.
    /// @param attestation The ownership attestation. `purpose` must be `ROOT_BIND` and `payoutMode`
    ///        must be `EVM`; `evmPayout` becomes the new beneficiary.
    /// @param signatures Attestor signatures, forwarded verbatim to the oracle.
    /// @param collectionProof Merkle proof of collection membership, forwarded verbatim.
    /// @return epoch The newly opened epoch number.
    /// @return releasedPending Wei moved out of the Root's pending bucket into the new
    ///         beneficiary's claimable balance. Zero when the bucket was empty.
    function bindRootOwner(
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external nonReentrant whenNotPaused returns (uint64 epoch, uint256 releasedPending) {
        bytes32 rootKey = _validateBind(attestation);

        (bytes32 digest, bytes32 oracleRootKey) = ORACLE.consumeOwnership(attestation, signatures, collectionProof);
        // The oracle derives the rootKey from the same signed fields, so a disagreement means the
        // two contracts do not share a hashing definition. Refuse to record anything in that case.
        if (oracleRootKey != rootKey) revert RootMismatch(rootKey, oracleRootKey);

        epoch = _activate(
            rootKey,
            ActivationFacts({
                beneficiary: attestation.evmPayout,
                outpointHash: attestation.currentOutpointHash,
                ownerScriptHash: attestation.ownerScriptHash,
                ownershipDigest: digest,
                bip322ProofHash: attestation.bip322ProofHash,
                bitcoinBlockHash: attestation.bitcoinBlockHash,
                bitcoinHeight: attestation.bitcoinHeight
            })
        );

        releasedPending = _releasePending(rootKey, attestation.evmPayout);
    }

    /*//////////////////////////////////////////////////////////////
                        PERMISSIONLESS INVALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRootOwnershipRegistry
    /// @dev THIS IS THE WATCHER'S FUNCTION AND IT IS OPEN TO EVERYONE, which is what keeps the
    ///      stale-watcher window short. It closes the current epoch and nothing else: no vault call,
    ///      no balance change, no beneficiary rewrite. Bob keeps every wei already credited to him;
    ///      only value that arrives AFTER this call is diverted, and it is diverted by `FeeRouter`
    ///      reading `active == false` and crediting `PayoutVault.pendingByRoot` instead.
    ///
    ///      `verifiedBitcoinHeight` is advanced to the spend height because the spend is the most
    ///      recent attested Bitcoin fact about this Root. That keeps the field monotonically
    ///      non-decreasing, which is what makes the "not older than" guard on the next bind mean
    ///      something: nobody can rebind using a proof of control from before the spend.
    /// @param attestation The spend attestation. Its `previousOutpointHash` must equal the recorded
    ///        `currentOutpointHash`, so an attestation about some other outpoint cannot close this
    ///        epoch.
    /// @param signatures Attestor signatures, forwarded verbatim to the oracle.
    /// @param collectionProof Merkle proof of collection membership, forwarded verbatim.
    function invalidateRoot(
        PuppetTypes.RootSpendAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external nonReentrant whenNotPaused {
        bytes32 rootKey = _validateSpend(attestation);

        (, bytes32 oracleRootKey) = ORACLE.consumeRootSpend(attestation, signatures, collectionProof);
        if (oracleRootKey != rootKey) revert RootMismatch(rootKey, oracleRootKey);

        PuppetTypes.RootState storage s = _rootState[rootKey];
        uint64 closingEpoch = s.epoch;
        address previousBeneficiary = s.beneficiary;

        s.active = false;
        s.invalidatingSpendTxid = attestation.spendingTxid;
        s.verifiedBitcoinHeight = attestation.bitcoinHeight;
        s.lastBitcoinBlockHash = attestation.bitcoinBlockHash;

        PuppetTypes.RootEpochInfo storage info = _rootEpochInfo[rootKey][closingEpoch];
        info.deactivatedAtBitcoinHeight = attestation.bitcoinHeight;
        info.deactivatedAtBlockTimestamp = uint64(block.timestamp);

        emit RootEpochInvalidated(
            rootKey, closingEpoch, previousBeneficiary, attestation.spendingTxid, attestation.bitcoinHeight
        );
    }

    /*//////////////////////////////////////////////////////////////
                       PENDING BALANCE FORWARDING
    //////////////////////////////////////////////////////////////*/

    /// @notice Forward a Root's pending vault balance to the beneficiary already recorded for it.
    /// @dev NOT IN THE FROZEN INTERFACE — an addition, and a deliberately powerless one. It cannot
    ///      choose a destination: it pays the address this registry already records, and only while
    ///      that record is active. It exists because a pending balance can otherwise sit until the
    ///      next epoch change, and a balance that is already owed to an identified address should
    ///      not need an ownership event to move.
    ///
    ///      WHY THIS OPENS NO NEW TRUST WINDOW: a pending bucket is only ever filled while a Root
    ///      is inactive, and an activation drains it atomically. So any pending balance on an
    ///      ACTIVE Root accrued after that Root's current epoch opened, and belongs to exactly the
    ///      beneficiary this function pays. It is not pausable, for the same reason a withdrawal is
    ///      not pausable: it moves value the protocol already owes.
    /// @param rootKey Canonical protocol key of the inscription.
    /// @return amount Wei moved into the beneficiary's claimable balance.
    function releasePendingRootCredit(bytes32 rootKey) external nonReentrant returns (uint256 amount) {
        PuppetTypes.RootState storage s = _rootState[rootKey];
        if (!s.active) revert RootNotActive(rootKey);

        address beneficiary = s.beneficiary;
        if (beneficiary == address(0)) revert InvalidBeneficiary();

        if (PAYOUT_VAULT.pendingByRoot(rootKey) == 0) revert NoPendingRootBalance(rootKey);

        amount = _releasePending(rootKey, beneficiary);
    }

    /*//////////////////////////////////////////////////////////////
                             PAUSE CONTROLS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stop consuming new ownership and spend attestations.
    /// @dev Incident response only. It freezes nothing that already exists: every view keeps
    ///      answering, every recorded epoch stays exactly as it was, `PayoutVault` withdrawals are
    ///      unaffected, and `releasePendingRootCredit` keeps working. The cost of pausing is that
    ///      the stale-watcher window cannot be closed while it lasts, so it must be short.
    function pauseActivations() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resume consuming attestations.
    /// @dev `DEFAULT_ADMIN_ROLE`, not `PAUSER_ROLE`: a hot guardian key may stop the protocol but
    ///      must not be able to restart it on its own.
    function unpauseActivations() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Every structural rule a `ROOT_BIND` must satisfy, in one place, before any external
    ///      call happens. Returns the canonical rootKey derived from the signed identity fields.
    function _validateBind(PuppetTypes.OwnershipAttestation calldata a) private view returns (bytes32 rootKey) {
        if (a.purpose != uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND)) revert UnsupportedPurpose(a.purpose);
        if (a.payoutMode != uint8(PuppetTypes.PayoutMode.EVM)) revert UnsupportedPayoutMode(a.payoutMode);
        if (a.evmPayout == address(0)) revert InvalidBeneficiary();
        if (a.rootTxid == bytes32(0)) revert ZeroRootTxid();
        if (a.currentOutpointHash == bytes32(0)) revert ZeroOutpointHash();
        if (a.ownerScriptHash == bytes32(0)) revert ZeroScriptHash();
        if (a.authorizationId == bytes32(0)) revert ZeroAuthorizationId();

        rootKey = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);
        if (a.contextId != bytes32(0) && a.contextId != rootKey) revert InvalidBindContext(a.contextId);

        PuppetTypes.RootState storage s = _rootState[rootKey];
        if (s.epoch != 0) {
            // Never accept a proof of control older than the newest Bitcoin fact already recorded
            // for this Root. Without this, a stale-but-valid attestation collected before a sale
            // could be replayed after it to reinstate the previous owner.
            if (a.bitcoinHeight < s.verifiedBitcoinHeight) {
                revert StaleBitcoinHeight(a.bitcoinHeight, s.verifiedBitcoinHeight);
            }
            _requireConsistentChainPoint(
                a.bitcoinHeight, a.bitcoinBlockHash, s.verifiedBitcoinHeight, s.lastBitcoinBlockHash
            );
            // While a Root is active, only a MOVE of the inscription justifies a new epoch. Binding
            // the same outpoint again would let anyone holding a second valid attestation for the
            // current owner churn epochs (and re-point the beneficiary) without anything having
            // changed on Bitcoin. Once the Root is inactive this restriction lifts, because the
            // recorded outpoint is then known to be spent.
            if (s.active && a.currentOutpointHash == s.currentOutpointHash) {
                revert UnchangedOutpoint(a.currentOutpointHash);
            }
        }
    }

    /// @dev Every structural rule a `RootSpendAttestation` must satisfy, before any external call.
    function _validateSpend(PuppetTypes.RootSpendAttestation calldata a) private view returns (bytes32 rootKey) {
        if (a.rootTxid == bytes32(0)) revert ZeroRootTxid();
        if (a.previousOutpointHash == bytes32(0)) revert ZeroOutpointHash();
        if (a.spendingTxid == bytes32(0)) revert ZeroSpendingTxid();
        if (a.authorizationId == bytes32(0)) revert ZeroAuthorizationId();

        rootKey = PuppetHashing.rootKey(a.rootTxid, a.rootIndex);

        PuppetTypes.RootState storage s = _rootState[rootKey];
        if (!s.active) revert RootNotActive(rootKey);
        if (a.previousOutpointHash != s.currentOutpointHash) {
            revert OutpointMismatch(s.currentOutpointHash, a.previousOutpointHash);
        }
        if (a.bitcoinHeight < s.verifiedBitcoinHeight) {
            revert StaleBitcoinHeight(a.bitcoinHeight, s.verifiedBitcoinHeight);
        }
        _requireConsistentChainPoint(
            a.bitcoinHeight, a.bitcoinBlockHash, s.verifiedBitcoinHeight, s.lastBitcoinBlockHash
        );
    }

    /// @dev At one Bitcoin height there is exactly one block in the chain view this registry has
    ///      accepted. A distinct block hash at the same height is a conflicting fork assertion,
    ///      not monotonic progress. A canonical-chain recovery remains possible by attesting from
    ///      a later height after the off-chain confirmation policy has resolved the reorg.
    function _requireConsistentChainPoint(
        uint64 providedHeight,
        bytes32 providedBlockHash,
        uint64 recordedHeight,
        bytes32 recordedBlockHash
    ) private pure {
        if (providedHeight == recordedHeight && providedBlockHash != recordedBlockHash) {
            revert ConflictingBitcoinBlockAtHeight(providedHeight, recordedBlockHash, providedBlockHash);
        }
    }

    /// @dev The single writer that opens an epoch. Both activation paths route through it so the
    ///      epoch counter, the history record and the event can never diverge between them.
    ///      Arithmetic is left checked: `epoch` is a security-relevant counter and clarity beats
    ///      the handful of gas an `unchecked` block would save.
    function _activate(bytes32 rootKey, ActivationFacts memory facts) private returns (uint64 epoch) {
        PuppetTypes.RootState storage s = _rootState[rootKey];

        if (s.active) {
            // A newer proof for a different outpoint arrived while the old epoch was still open —
            // the watcher never showed up, or the new owner simply got there first. Close the old
            // epoch's history record so no two records for one Root are ever open at once.
            PuppetTypes.RootEpochInfo storage outgoing = _rootEpochInfo[rootKey][s.epoch];
            outgoing.deactivatedAtBitcoinHeight = facts.bitcoinHeight;
            outgoing.deactivatedAtBlockTimestamp = uint64(block.timestamp);

            emit RootEpochSuperseded(rootKey, s.epoch, s.beneficiary, s.epoch + 1, facts.bitcoinHeight);
        }

        epoch = s.epoch + 1;

        s.epoch = epoch;
        s.active = true;
        s.currentOutpointHash = facts.outpointHash;
        s.ownerScriptHash = facts.ownerScriptHash;
        s.beneficiary = facts.beneficiary;
        s.ownershipDigest = facts.ownershipDigest;
        s.bip322ProofHash = facts.bip322ProofHash;
        s.verifiedBitcoinHeight = facts.bitcoinHeight;
        s.lastBitcoinBlockHash = facts.bitcoinBlockHash;
        // A live epoch must not carry the txid that killed the previous one, or a consumer reading
        // `invalidatingSpendTxid` would believe the current owner has already been dispossessed.
        s.invalidatingSpendTxid = bytes32(0);

        _rootEpochInfo[rootKey][epoch] = PuppetTypes.RootEpochInfo({
            beneficiary: facts.beneficiary,
            outpointHash: facts.outpointHash,
            ownerScriptHash: facts.ownerScriptHash,
            activatedAtBitcoinHeight: facts.bitcoinHeight,
            activatedAtBlockTimestamp: uint64(block.timestamp),
            deactivatedAtBitcoinHeight: 0,
            deactivatedAtBlockTimestamp: 0,
            ownershipDigest: facts.ownershipDigest
        });

        emit RootEpochActivated(
            rootKey,
            epoch,
            facts.beneficiary,
            facts.outpointHash,
            facts.ownerScriptHash,
            facts.bitcoinHeight,
            facts.ownershipDigest
        );
    }

    /// @dev Move the Root's pending bucket to `beneficiary`, if there is one. The bucket is read
    ///      first because `PayoutVault.releaseRootCredit` reverts on an empty bucket, and an empty
    ///      bucket is the normal case for a first activation — it must not fail the bind.
    function _releasePending(bytes32 rootKey, address beneficiary) private returns (uint256 amount) {
        amount = PAYOUT_VAULT.pendingByRoot(rootKey);
        if (amount == 0) return 0;

        uint256 released = PAYOUT_VAULT.releaseRootCredit(rootKey, beneficiary);
        if (released != amount) revert PendingReleaseMismatch(amount, released);

        emit RootPendingReleased(rootKey, beneficiary, released);
    }
}
