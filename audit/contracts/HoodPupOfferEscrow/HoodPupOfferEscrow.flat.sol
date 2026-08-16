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

// src/interfaces/IFeeRouter.sol

/// @title IFeeRouter
/// @notice The immutable 50 / 25 / 25 economic split.
/// @dev Percentages are compile-time constants with no setter and no upgrade path. Only the two
///      treasury destination addresses are governable, and only through the timelock.
interface IFeeRouter {
    error ZeroAddress();
    error ValueMismatch(uint256 expected, uint256 provided);
    error RoutingResidue(uint256 residue);
    error DirectDepositRejected();

    event MintRouted(
        bytes32 indexed rootKey,
        address indexed sellerOrSolver,
        uint8 route,
        uint256 gross,
        uint256 sellerAmount,
        uint256 puppetTreasuryAmount,
        uint256 protocolAmount
    );
    event RecurringRouted(
        bytes32 indexed rootKey,
        address indexed beneficiary,
        bool beneficiaryActive,
        uint256 gross,
        uint256 rootAmount,
        uint256 puppetTreasuryAmount,
        uint256 protocolAmount
    );
    event TreasuryUpdated(address indexed previous, address indexed next, bool isProtocol);

    /// @notice 5000.
    function SELLER_BPS() external view returns (uint256);
    /// @notice 2500.
    function PUPPET_TREASURY_BPS() external view returns (uint256);
    /// @notice 2500.
    function PROTOCOL_BPS() external view returns (uint256);
    /// @notice 10000.
    function BPS_DENOMINATOR() external view returns (uint256);

    /// @notice Current Bitcoin Puppets ecosystem treasury address.
    function puppetTreasury() external view returns (address);
    /// @notice Current protocol treasury address.
    function protocolTreasury() external view returns (address);

    /// @notice Split `gross` into its three parts.
    /// @dev Seller and treasury are floor-divided; protocol absorbs the rounding remainder, so
    ///      `seller + puppetTreasuryAmount + protocolAmount == gross` holds for every input.
    function quote(uint256 gross)
        external
        pure
        returns (uint256 sellerAmount, uint256 puppetTreasuryAmount, uint256 protocolAmount);

    /// @notice Route a completed EVM-payout mint. Requires `ROUTER_CALLER_ROLE`.
    function routeMintEvm(bytes32 rootKey, address seller, uint256 gross) external payable;

    /// @notice Route a completed native-BTC mint; the seller share reimburses the solver.
    /// @dev Bob was already paid in BTC off chain, so the 50% share belongs to the solver that
    ///      fronted it. Requires `ROUTER_CALLER_ROLE`.
    function routeMintBtc(bytes32 rootKey, address solver, uint256 gross) external payable;

    /// @notice Route recurring Root-linked value. Requires `ROUTER_CALLER_ROLE`.
    /// @dev Root share goes to the active beneficiary, or to the Root's pending bucket when no
    ///      owner is currently verified.
    function routeRecurring(bytes32 rootKey, uint256 gross) external payable;
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

// src/interfaces/IHoodPups.sol

/// @notice EIP-4907 rental / temporary-user standard.
interface IERC4907 {
    /// @notice Emitted when the user of an NFT or its expiry changes.
    event UpdateUser(uint256 indexed tokenId, address indexed user, uint64 expires);

    /// @notice Grant temporary use rights without transferring ownership.
    function setUser(uint256 tokenId, address user, uint64 expires) external;

    /// @notice Current user, or the zero address once the term has elapsed.
    function userOf(uint256 tokenId) external view returns (address);

    /// @notice Timestamp at which the current user's rights lapse.
    function userExpires(uint256 tokenId) external view returns (uint256);
}

/// @title IHoodPups
/// @notice ERC-721 where each token permanently references exactly one Bitcoin Puppet inscription.
/// @dev A HoodPup is a derived Robinhood Chain asset. It is NOT the Bitcoin inscription, it does
///      not custody it, and holding one confers no rights over it.
interface IHoodPups is IERC4907 {
    error ZeroAddress();
    error RootAlreadyMinted(bytes32 rootKey, uint256 tokenId);
    error UnknownToken(uint256 tokenId);
    error MintingPaused();
    error MetadataFrozen();
    error NotOwnerNorApproved(address caller, uint256 tokenId);
    error UserIsOwner();
    error ExpiryInPast(uint64 expires, uint256 nowTs);

    event RootedMint(
        uint256 indexed tokenId, bytes32 indexed rootKey, address indexed recipient, bytes32 rootTxid, uint32 rootIndex
    );
    event BaseURIUpdated(string previous, string next);
    event ContractURIUpdated(string previous, string next);
    event MetadataFrozenForever();
    event MintingPauseUpdated(bool paused);

    /// @notice Mint the single HoodPup for `root`. Requires `MINTER_ROLE`.
    function mintRooted(address recipient, PuppetTypes.RootId calldata root) external returns (uint256 tokenId);

    /// @notice True once a Root has produced its HoodPup. Permanent.
    function rootMinted(bytes32 rootKey) external view returns (bool);

    /// @notice Token id for a Root, or zero. Ids start at 1 so zero is unambiguous.
    function tokenOfRoot(bytes32 rootKey) external view returns (uint256);

    /// @notice The Bitcoin inscription a token references.
    function rootOf(uint256 tokenId) external view returns (PuppetTypes.RootId memory);

    /// @notice Canonical root key a token references.
    function rootKeyOf(uint256 tokenId) external view returns (bytes32);

    /// @notice Next id that will be assigned.
    function nextTokenId() external view returns (uint256);

    /// @notice True while `mintRooted` is disabled. Transfers are never affected.
    function mintingPaused() external view returns (bool);

    /// @notice True once metadata URIs are permanently locked.
    function metadataFrozen() external view returns (bool);
}

// src/interfaces/IPuppetCollectionRegistry.sol

/// @title IPuppetCollectionRegistry
/// @notice Immutable membership oracle for the canonical Bitcoin Puppets manifest.
/// @dev Answers exactly one question: "is this inscription in the manifest this deployment
///      committed to?" It knows nothing about who currently owns it.
interface IPuppetCollectionRegistry {
    /// @notice Thrown when a constructor argument that must be non-zero is zero.
    error ZeroValue();
    /// @notice Thrown when `requireMember` is given a proof that does not verify.
    error NotCollectionMember(bytes32 rootKey);

    /// @notice Protocol-wide collection domain separator.
    function collectionId() external view returns (bytes32);

    /// @notice Immutable Merkle root over the canonical manifest.
    function merkleRoot() external view returns (bytes32);

    /// @notice Immutable content hash of the manifest file that produced `merkleRoot`.
    function manifestHash() external view returns (bytes32);

    /// @notice Human-readable manifest version, e.g. "bitcoin-puppets-mainnet-2026-01".
    function manifestVersion() external view returns (string memory);

    /// @notice Number of leaves in the committed manifest, for reproducibility checks.
    function manifestLeafCount() external view returns (uint256);

    /// @notice Canonical protocol key for an inscription.
    function rootKey(PuppetTypes.RootId calldata root) external pure returns (bytes32);

    /// @notice Merkle leaf for an inscription.
    function leafOf(PuppetTypes.RootId calldata root) external pure returns (bytes32);

    /// @notice Non-reverting membership check.
    function isMember(PuppetTypes.RootId calldata root, bytes32[] calldata proof) external view returns (bool);

    /// @notice Reverting membership check used by settlement paths.
    /// @return key The canonical root key, returned so callers avoid recomputing it.
    function requireMember(PuppetTypes.RootId calldata root, bytes32[] calldata proof)
        external
        view
        returns (bytes32 key);
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

// src/HoodPupOfferEscrow.sol

/// @title HoodPupOfferEscrow
/// @notice Holds buyer ETH and runs the whole offer lifecycle: creation, Bitcoin ownership
///         approval, mint, fund routing and refund.
/// @dev TRUST BOUNDARY — READ THIS FIRST. Nothing in this contract verifies Bitcoin consensus.
///      Every Bitcoin fact it acts on is asserted by a 3-of-5 quorum of independent attestor
///      operators and is delivered through `BitcoinOwnershipOracle`. This is an attested
///      settlement system, not a trustless bridge. The original Bitcoin Puppet inscription never
///      leaves Bitcoin: it is never bridged, wrapped, custodied or escrowed, and nothing in this
///      file can move it. A HoodPup is a derived Robinhood Chain asset that references one
///      inscription; holding one confers no rights over the inscription itself.
///
///      WHY A BUYER CANNOT CANCEL AN OPEN OFFER. There is deliberately no `cancelOffer`. A Bitcoin
///      holder answering an offer may be partway through a cold-wallet BIP-322 signing ceremony
///      that takes minutes or hours — hardware in a safe, a second location, a co-signer. If the
///      buyer could withdraw at will, they could bait that signature out of the holder and then
///      pull the escrow the instant before it lands, turning every offer into a free option
///      written by the seller. The buyer's protection is bounded instead of instant: the offer
///      expires (`refundExpired`), or becomes immediately refundable the moment the Root is minted
///      by a competing offer (`refundUnfillable`). Both are permissionless and neither can be
///      blocked by governance.
///
///      THE PAYOUT ADDRESS IS WHATEVER THE BITCOIN HOLDER SIGNED, AND NOTHING ELSE. On the paid
///      EVM path the seller share is routed to `attestation.evmPayout` — a field inside the digest
///      the quorum signed, which itself commits to `offerTermsHash`. There is no stored seller
///      address, no admin override, and no setter. That binding is the entire point of the BIP-322
///      message: "I control this inscription, I accept these exact terms, pay me at this address."
///
///      THE ROOT BENEFICIARY IS ONLY EVER RECORDED FROM AN ATTESTATION THAT CARRIES A SIGNED EVM
///      ADDRESS. `settlePaidEvm` records the Root's first ownership epoch, because a
///      `PAID_EVM_MINT` attestation contains a holder-signed `evmPayout`. `settleSelfCast` and
///      `finalizeBtcSettlement` deliberately do NOT: a `SELF_CAST` attestation carries
///      `PayoutMode.NONE` and a `PAID_BTC_MINT` attestation carries `PayoutMode.BTC`, so in both
///      cases `evmPayout` is structurally zero and there is no EVM address the holder signed.
///      Inventing one — using `recipient`, or the caller, or the buyer — would break the invariant
///      above at exactly the point where it matters most, so those two paths require a separate,
///      permissionless `RootOwnershipRegistry.bindRootOwner` afterwards. Nothing is lost by
///      waiting: recurring Root value accrues into `PayoutVault.pendingByRoot` and is released to
///      whoever next proves Bitcoin control. See `docs/TRUST_ASSUMPTIONS.md`.
///
///      MONEY NEVER MOVES BY PUSH. Buyer refunds and seller payouts are both credited inside
///      `PayoutVault`. A seller (or buyer) whose address is a contract that reverts on receive can
///      therefore never block a settlement, a refund or anybody else's mint.
///
///      PAUSING. `whenNotPaused` guards the paths that take on NEW risk: the three creation
///      functions, the three attestation-consuming settlement/approval functions, and the two
///      authorized BTC hooks that start or complete a solver flow. It appears on NO refund path.
///      `refundExpired`, `refundUnfillable`, `clearBtcReservation` and `expireBtcReservation` stay
///      live while paused, so a pause can never trap a buyer's escrow inside this contract.
///
///      NON-UPGRADEABLE by construction: no proxy, no initializer, no `delegatecall`, no
///      `selfdestruct`, no `tx.origin`, no owner EOA, and no admin path that can seize, redirect or
///      reduce a user's escrow. `DEFAULT_ADMIN_ROLE` is intended for a `TimelockController` under
///      multisig control.
contract HoodPupOfferEscrow is IHoodPupOfferEscrow, AccessControl, Pausable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Narrow role held by `BtcSolverSettlement` and nothing else.
    /// @dev It can move an offer between `BTC_APPROVED` and `BTC_RESERVED`, and it can finalize a
    ///      reserved offer. It CANNOT create offers, settle the EVM or self-cast paths, refund,
    ///      pause, choose a mint recipient, or name a payout address other than the solver it
    ///      passes — and even that address must equal the solver already recorded on the offer.
    ///      Deliberately NOT granted at construction: `BtcSolverSettlement` does not exist yet at
    ///      the escrow's deployment step, and pre-granting it to the deployer would create exactly
    ///      the EOA-holds-privilege state the timelock handover is meant to eliminate.
    bytes32 public constant BTC_SETTLEMENT_ROLE = keccak256("BTC_SETTLEMENT_ROLE");

    /// @notice Role permitted to halt new offers and new settlements.
    /// @dev Asymmetric, matching the rest of the protocol: `PAUSER_ROLE` may pause (the safe
    ///      direction, so it can be a hot guardian key that reacts in seconds) but only
    ///      `DEFAULT_ADMIN_ROLE` may unpause, because resuming settlement re-enables risk.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Longest solver reservation this escrow will ever accept, in seconds.
    /// @dev A reservation freezes a buyer's escrow: while `BTC_RESERVED`, refunds are blocked so
    ///      that a solver who is mid-way through broadcasting a real Bitcoin payment cannot have
    ///      the offer pulled out from under them. That protection has to be bounded, or a buggy or
    ///      hostile `BtcSolverSettlement` could reserve with `reservationExpiry = type(uint64).max`
    ///      and freeze the escrow permanently. 24 hours is far beyond the ~1 hour six Bitcoin
    ///      confirmations need, and is the ceiling past which "the solver is still working" stops
    ///      being a credible claim.
    uint64 public constant MAX_RESERVATION_WINDOW = 24 hours;

    /*//////////////////////////////////////////////////////////////
                          ERRORS BEYOND THE INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a settlement entry point is used on an offer of a different kind.
    /// @dev `settlePaidEvm`, `settleSelfCast` and `approvePaidBtc` each serve exactly one
    ///      `OfferKind`. Several of the field checks would incidentally catch a mismatch, but
    ///      relying on that would make the revert reason depend on which incidental check happened
    ///      to fire first. An explicit error keeps the trace honest.
    /// @param offerId The offer being acted on.
    /// @param actual The offer's `PuppetTypes.OfferKind`.
    /// @param expected The kind the entry point serves.
    error UnexpectedOfferKind(bytes32 offerId, uint8 actual, uint8 expected);

    /// @notice Thrown when the oracle's derived root key disagrees with the offer's stored key.
    /// @dev Unreachable while the oracle derives keys with `PuppetHashing.rootKey`, which is what
    ///      this contract uses at creation. It exists so that a future oracle whose hashing has
    ///      drifted aborts the settlement instead of minting against the wrong inscription.
    /// @param expected The key stored on the offer at creation.
    /// @param provided The key the oracle returned.
    error RootMismatch(bytes32 expected, bytes32 provided);

    /// @notice Thrown when a reservation window is zero-length, in the past, or too long.
    /// @param requested The expiry the solver contract asked for.
    /// @param earliestAllowed Exclusive lower bound: `block.timestamp`.
    /// @param latestAllowed Inclusive upper bound: `min(offer.expiry, now + MAX_RESERVATION_WINDOW)`.
    error ReservationWindowInvalid(uint64 requested, uint64 earliestAllowed, uint64 latestAllowed);

    /// @notice Thrown when finalizing a reservation whose window has already closed.
    /// @param offerId The offer being finalized.
    /// @param reservationExpiry The moment the exclusive window ended.
    error ReservationLapsed(bytes32 offerId, uint64 reservationExpiry);

    /// @notice Thrown when trying to force-expire a reservation that is still live.
    /// @param offerId The offer being released.
    /// @param reservationExpiry The moment the exclusive window ends.
    error ReservationNotLapsed(bytes32 offerId, uint64 reservationExpiry);

    /// @notice Thrown when an inscription identity carries a zero reveal txid.
    /// @dev The shape of a default-initialised `RootId` reaching offer creation. Rejected because a
    ///      zero identity would still produce a well-formed `rootKey` and could be escrowed
    ///      against forever without ever being settleable.
    error ZeroRootTxid();

    /// @notice Thrown on any plain ETH transfer into this contract.
    /// @dev Escrow arrives only as `msg.value` on a creation function, where it is immediately
    ///      attributed to an offer. Accepting a bare transfer would create ETH that belongs to
    ///      nobody and that no code path can ever pay out.
    error DirectDepositRejected();

    /*//////////////////////////////////////////////////////////////
                         EVENTS BEYOND THE INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, recording the immutable wiring of this escrow.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param collectionRegistry Immutable manifest membership registry.
    /// @param ownershipOracle Immutable 3-of-5 attestation oracle.
    /// @param hoodPups Immutable HoodPups ERC-721 collection.
    /// @param feeRouter Immutable 50/25/25 router.
    /// @param payoutVault Immutable pull-payment vault.
    /// @param rootOwnershipRegistry Immutable Root ownership epoch registry.
    /// @param minimumOfferDuration Shortest life an offer may be created with.
    /// @param maximumOfferDuration Longest life an offer may be created with.
    event EscrowInitialized(
        address indexed admin,
        address collectionRegistry,
        address ownershipOracle,
        address hoodPups,
        address feeRouter,
        address payoutVault,
        address rootOwnershipRegistry,
        uint64 minimumOfferDuration,
        uint64 maximumOfferDuration
    );

    /// @notice Emitted when a solver's BTC payment discharges an offer.
    /// @dev Carries the payment digest as an opaque reference so an indexer can join this
    ///      settlement to the `BitcoinPaymentAttestation` the oracle consumed. No raw BIP-322 or
    ///      Bitcoin proof bytes are ever emitted by this contract.
    /// @param offerId The offer that settled.
    /// @param solver The bonded solver reimbursed in ETH.
    /// @param paymentDigest Digest of the consumed Bitcoin payment attestation.
    event BtcSettlementFinalized(bytes32 indexed offerId, address indexed solver, bytes32 indexed paymentDigest);

    /*//////////////////////////////////////////////////////////////
                             IMMUTABLE WIRING
    //////////////////////////////////////////////////////////////*/

    /// @dev Every protocol dependency is `immutable`. A swappable oracle pointer would be an admin
    ///      path to redefine what counts as proof of Bitcoin control; a swappable router would be
    ///      an admin path to redirect the 50/25/25 split; a swappable vault would be an admin path
    ///      to redirect refunds. None of those may exist, so none of these have setters.
    IPuppetCollectionRegistry private immutable _COLLECTION_REGISTRY;
    IBitcoinOwnershipOracle private immutable _OWNERSHIP_ORACLE;
    IHoodPups private immutable _HOOD_PUPS;
    IFeeRouter private immutable _FEE_ROUTER;
    IPayoutVault private immutable _PAYOUT_VAULT;
    IRootOwnershipRegistry private immutable _ROOT_OWNERSHIP_REGISTRY;

    uint64 private immutable _MINIMUM_OFFER_DURATION;
    uint64 private immutable _MAXIMUM_OFFER_DURATION;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(bytes32 => PuppetTypes.Offer) private _offers;
    mapping(address => uint256) private _buyerNonce;

    /// @dev Sum of `grossWei` over every offer that is currently OPEN, BTC_APPROVED or
    ///      BTC_RESERVED. Incremented once at creation and decremented once when the offer reaches
    ///      a terminal state, so it is exactly the ETH this contract still owes to somebody.
    uint256 private _lockedEscrowWei;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the escrow with its permanent protocol wiring.
    /// @dev `BTC_SETTLEMENT_ROLE` is intentionally left unassigned; see its NatSpec.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`. Must be a
    ///        `TimelockController` under multisig control in production.
    /// @param collectionRegistry_ Immutable manifest membership registry.
    /// @param ownershipOracle_ Immutable 3-of-5 attestation oracle.
    /// @param hoodPups_ Immutable HoodPups ERC-721 collection.
    /// @param feeRouter_ Immutable 50/25/25 router.
    /// @param payoutVault_ Immutable pull-payment vault.
    /// @param rootOwnershipRegistry_ Immutable Root ownership epoch registry.
    /// @param minimumOfferDuration_ Shortest life an offer may be created with, in seconds. Must be
    ///        non-zero: a zero-duration offer would be expired in the block that created it, which
    ///        no Bitcoin holder could ever answer.
    /// @param maximumOfferDuration_ Longest life an offer may be created with, in seconds.
    constructor(
        address admin,
        address collectionRegistry_,
        address ownershipOracle_,
        address hoodPups_,
        address feeRouter_,
        address payoutVault_,
        address rootOwnershipRegistry_,
        uint64 minimumOfferDuration_,
        uint64 maximumOfferDuration_
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (collectionRegistry_ == address(0)) revert ZeroAddress();
        if (ownershipOracle_ == address(0)) revert ZeroAddress();
        if (hoodPups_ == address(0)) revert ZeroAddress();
        if (feeRouter_ == address(0)) revert ZeroAddress();
        if (payoutVault_ == address(0)) revert ZeroAddress();
        if (rootOwnershipRegistry_ == address(0)) revert ZeroAddress();
        if (minimumOfferDuration_ == 0 || minimumOfferDuration_ > maximumOfferDuration_) {
            revert DurationBoundsInvalid(minimumOfferDuration_, maximumOfferDuration_);
        }

        _COLLECTION_REGISTRY = IPuppetCollectionRegistry(collectionRegistry_);
        _OWNERSHIP_ORACLE = IBitcoinOwnershipOracle(ownershipOracle_);
        _HOOD_PUPS = IHoodPups(hoodPups_);
        _FEE_ROUTER = IFeeRouter(feeRouter_);
        _PAYOUT_VAULT = IPayoutVault(payoutVault_);
        _ROOT_OWNERSHIP_REGISTRY = IRootOwnershipRegistry(rootOwnershipRegistry_);
        _MINIMUM_OFFER_DURATION = minimumOfferDuration_;
        _MAXIMUM_OFFER_DURATION = maximumOfferDuration_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        emit EscrowInitialized(
            admin,
            collectionRegistry_,
            ownershipOracle_,
            hoodPups_,
            feeRouter_,
            payoutVault_,
            rootOwnershipRegistry_,
            minimumOfferDuration_,
            maximumOfferDuration_
        );
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice The immutable manifest membership registry this escrow proves inclusion against.
    function collectionRegistry() external view returns (IPuppetCollectionRegistry) {
        return _COLLECTION_REGISTRY;
    }

    /// @notice The immutable oracle that turns a 3-of-5 quorum into a one-time authorization.
    function ownershipOracle() external view returns (IBitcoinOwnershipOracle) {
        return _OWNERSHIP_ORACLE;
    }

    /// @notice The immutable HoodPups collection this escrow mints from.
    function hoodPups() external view returns (IHoodPups) {
        return _HOOD_PUPS;
    }

    /// @notice The immutable router that applies the 50/25/25 split.
    function feeRouter() external view returns (IFeeRouter) {
        return _FEE_ROUTER;
    }

    /// @notice The immutable vault every refund and payout is credited into.
    function payoutVault() external view returns (IPayoutVault) {
        return _PAYOUT_VAULT;
    }

    /// @notice The immutable registry that records Root ownership epochs.
    function rootOwnershipRegistry() external view returns (IRootOwnershipRegistry) {
        return _ROOT_OWNERSHIP_REGISTRY;
    }

    /// @notice Shortest life an offer may be created with, in seconds.
    function minimumOfferDuration() external view returns (uint64) {
        return _MINIMUM_OFFER_DURATION;
    }

    /// @notice Longest life an offer may be created with, in seconds.
    function maximumOfferDuration() external view returns (uint64) {
        return _MAXIMUM_OFFER_DURATION;
    }

    /// @notice ETH this contract still owes: the sum of `grossWei` over all non-terminal offers.
    /// @dev `address(this).balance >= lockedEscrowWei()` is the escrow's solvency invariant. The
    ///      two can differ only by ETH forced in with `selfdestruct` or a block reward, which no
    ///      code path here can create and none can spend.
    function lockedEscrowWei() external view returns (uint256) {
        return _lockedEscrowWei;
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev Non-reverting for an unknown id: the zero struct carries `status == OfferStatus.NONE`,
    ///      which is unambiguous, and integrators should not need a try/catch to probe an id.
    function getOffer(bytes32 offerId) external view returns (PuppetTypes.Offer memory) {
        return _offers[offerId];
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function nextOfferId(address buyer) external view returns (bytes32) {
        return PuppetHashing.offerId(block.chainid, address(this), buyer, _buyerNonce[buyer]);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function buyerNonce(address buyer) external view returns (uint256) {
        return _buyerNonce[buyer];
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev `view` rather than `pure` because the hash binds `block.chainid` and this escrow's own
    ///      address, so one deployment's terms can never be replayed against another. The SDK and
    ///      the five attestor services must reproduce this exactly: they all check that the holder
    ///      signed the SAME terms the escrow stored, and a divergence here silently breaks that.
    /// @param offerId Deterministic offer identifier.
    /// @param kind `PuppetTypes.OfferKind` as uint8.
    /// @param rootKey Canonical protocol key of the inscription.
    /// @param buyer Address that escrowed the ETH.
    /// @param recipient Address that receives the HoodPup.
    /// @param grossWei Total wei escrowed.
    /// @param sellerWei Seller share in wei.
    /// @param sellerSats Exact satoshis the seller must receive on a BTC offer.
    /// @param expiry Unix timestamp after which the offer is refundable.
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
    ) public view returns (bytes32) {
        return PuppetHashing.offerTermsHash(
            block.chainid,
            address(this),
            offerId,
            kind,
            rootKey,
            buyer,
            recipient,
            grossWei,
            sellerWei,
            sellerSats,
            expiry
        );
    }

    /// @notice ERC-165 support, extended with this escrow's own interface id.
    /// @param interfaceId The interface identifier being queried.
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return interfaceId == type(IHoodPupOfferEscrow).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                             OFFER CREATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev Multiple competing offers may exist for one Root at the same time, on purpose: the
    ///      Bitcoin holder should be able to pick the best one. Exactly one can ever settle,
    ///      because the Root mints at most once; every loser becomes immediately refundable
    ///      through `refundUnfillable`.
    /// @param root Canonical inscription identity.
    /// @param recipient Address that will receive the HoodPup.
    /// @param expiry Unix timestamp after which the buyer may reclaim the escrow.
    /// @param collectionProof Merkle proof of manifest membership.
    /// @return offerId The created offer's deterministic identifier.
    function createPaidEvmOffer(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 expiry,
        bytes32[] calldata collectionProof
    ) external payable whenNotPaused nonReentrant returns (bytes32 offerId) {
        if (msg.value == 0) revert PaidOfferRequiresValue();
        return _create(root, recipient, expiry, collectionProof, PuppetTypes.OfferKind.PAID_EVM, 0);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev The buyer fixes BOTH sides of the trade here: `msg.value` in ETH and `sellerSats` in
    ///      satoshis. There is no price oracle anywhere in this flow, so there is no oracle to
    ///      manipulate and no slippage to argue about — a bonded solver either finds the implied
    ///      rate attractive or ignores the offer, and the spread is the market.
    /// @param root Canonical inscription identity.
    /// @param recipient Address that will receive the HoodPup.
    /// @param sellerSats Exact satoshis the Bitcoin holder must be paid.
    /// @param expiry Unix timestamp after which the buyer may reclaim the escrow.
    /// @param collectionProof Merkle proof of manifest membership.
    /// @return offerId The created offer's deterministic identifier.
    function createPaidBtcOffer(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 sellerSats,
        uint64 expiry,
        bytes32[] calldata collectionProof
    ) external payable whenNotPaused nonReentrant returns (bytes32 offerId) {
        if (msg.value == 0) revert PaidOfferRequiresValue();
        if (sellerSats == 0) revert BtcOfferRequiresSats();
        return _create(root, recipient, expiry, collectionProof, PuppetTypes.OfferKind.PAID_BTC, sellerSats);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev Free mint for the Bitcoin controller themselves. The caller must equal the recipient:
    ///      a self-cast escrows nothing, so without that rule anyone could open unlimited free
    ///      offers naming an arbitrary recipient and spam the Root's offer book at no cost.
    ///
    ///      `SelfCastMustBeZeroValue` is declared on the interface but can never be emitted by
    ///      this implementation, because this function is not `payable` — the ABI rejects value
    ///      before any of this contract's code runs, which is a stronger guarantee than a check.
    /// @param root Canonical inscription identity.
    /// @param recipient Address that will receive the HoodPup. Must equal `msg.sender`.
    /// @param expiry Unix timestamp after which the offer may be closed out for clean state.
    /// @param collectionProof Merkle proof of manifest membership.
    /// @return offerId The created offer's deterministic identifier.
    function createSelfCastOffer(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 expiry,
        bytes32[] calldata collectionProof
    ) external whenNotPaused nonReentrant returns (bytes32 offerId) {
        if (msg.sender != recipient) {
            revert SelfCastRecipientMismatch(msg.sender, recipient);
        }
        return _create(root, recipient, expiry, collectionProof, PuppetTypes.OfferKind.SELF_CAST, 0);
    }

    /*//////////////////////////////////////////////////////////////
                             EVM SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev PERMISSIONLESS ON PURPOSE. Anybody may submit a quorum they have collected — a relayer,
    ///      the buyer, the seller's own tooling. Submitting it decides nothing: the recipient, the
    ///      payout address and every amount come from the signed attestation and the stored offer,
    ///      never from the caller.
    ///
    ///      ORDERING, AND WHY IT DEVIATES FROM TEXTBOOK CHECKS-EFFECTS-INTERACTIONS. Local checks
    ///      run first so a doomed call cannot burn a quorum's work. The oracle consumption then
    ///      precedes the state writes because it IS the authorization — there is nothing to record
    ///      until it succeeds — and the oracle is an immutable, trusted protocol contract fixed at
    ///      construction. Only then are the effects written, and only then does the contract talk
    ///      to anyone else.
    ///
    ///      THE MINT IS DELIBERATELY THE LAST EXTERNAL CALL. `mintRooted` uses `_safeMint`, so it
    ///      hands control to `recipient.onERC721Received`, which is the only untrusted code this
    ///      function can reach. By the time it runs, the offer is already SETTLED, the escrow
    ///      accounting is already decremented, the Root epoch is already recorded and the funds
    ///      are already routed — so even without `nonReentrant` there would be no half-finished
    ///      state to observe. The guard is kept anyway, as defence in depth.
    /// @param offerId The offer to settle.
    /// @param attestation The 3-of-5 attested ownership statement authorizing this exact offer.
    /// @param signatures Attestor signatures, forwarded verbatim to the oracle.
    /// @param collectionProof Merkle proof of manifest membership, forwarded verbatim.
    /// @return tokenId The minted HoodPup's token id.
    function settlePaidEvm(
        bytes32 offerId,
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external whenNotPaused nonReentrant returns (uint256 tokenId) {
        PuppetTypes.Offer storage o = _settleableOffer(offerId, PuppetTypes.OfferKind.PAID_EVM);
        _requireTermsMatch(offerId, o, attestation, PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT);

        // The seller share follows the address the Bitcoin holder signed, so that address must
        // exist and the BTC-side payout fields must be empty. A `PAID_EVM_MINT` that also carried a
        // BTC script hash would be one signed fact two contracts could read two different ways.
        if (attestation.payoutMode != uint8(PuppetTypes.PayoutMode.EVM)) {
            revert AttestationFieldMismatch("payoutMode");
        }
        if (attestation.evmPayout == address(0)) revert AttestationFieldMismatch("evmPayout");
        if (attestation.btcPayoutScriptHash != bytes32(0)) revert AttestationFieldMismatch("btcPayoutScriptHash");

        bytes32 digest = _consume(o.rootKey, attestation, signatures, collectionProof);

        // EFFECTS.
        o.status = uint8(PuppetTypes.OfferStatus.SETTLED);
        o.ownershipDigest = digest;
        _lockedEscrowWei -= o.grossWei;

        emit OwnershipApproved(offerId, digest, attestation.purpose, attestation.evmPayout);

        // INTERACTIONS, trusted protocol contracts first and the untrusted mint callback last.
        _recordFirstOwnershipEpoch(o.rootKey, digest, attestation);
        _FEE_ROUTER.routeMintEvm{value: o.grossWei}(o.rootKey, attestation.evmPayout, o.grossWei);
        tokenId = _mint(o);

        emit OfferSettled(offerId, o.rootKey, tokenId, o.recipient, attestation.evmPayout, o.grossWei, o.kind);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev No money exists on this path, so there is no `FeeRouter` call and no vault credit.
    ///
    ///      IT DELIBERATELY DOES NOT RECORD A ROOT BENEFICIARY. A `SELF_CAST` attestation carries
    ///      `PayoutMode.NONE` and a structurally zero `evmPayout`: the holder signed no EVM payout
    ///      address, so there is none to record. The alternatives — using `recipient`, or the
    ///      caller — would mean the protocol invented a beneficiary the Bitcoin controller never
    ///      signed, which is precisely the invariant this file exists to protect. The controller
    ///      binds their Root afterwards with a separate, permissionless
    ///      `RootOwnershipRegistry.bindRootOwner` carrying a `ROOT_BIND` attestation, which does
    ///      contain a signed EVM address. Nothing is lost in the meantime: recurring Root value
    ///      accrues into `PayoutVault.pendingByRoot` and is released to whoever next proves control.
    /// @param offerId The offer to settle.
    /// @param attestation The 3-of-5 attested ownership statement authorizing this exact offer.
    /// @param signatures Attestor signatures, forwarded verbatim to the oracle.
    /// @param collectionProof Merkle proof of manifest membership, forwarded verbatim.
    /// @return tokenId The minted HoodPup's token id.
    function settleSelfCast(
        bytes32 offerId,
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external whenNotPaused nonReentrant returns (uint256 tokenId) {
        PuppetTypes.Offer storage o = _settleableOffer(offerId, PuppetTypes.OfferKind.SELF_CAST);
        _requireTermsMatch(offerId, o, attestation, PuppetTypes.AuthorizationPurpose.SELF_CAST);

        if (attestation.payoutMode != uint8(PuppetTypes.PayoutMode.NONE)) {
            revert AttestationFieldMismatch("payoutMode");
        }
        if (attestation.evmPayout != address(0)) revert AttestationFieldMismatch("evmPayout");
        if (attestation.btcPayoutScriptHash != bytes32(0)) revert AttestationFieldMismatch("btcPayoutScriptHash");

        bytes32 digest = _consume(o.rootKey, attestation, signatures, collectionProof);

        // EFFECTS. `grossWei` is zero here, so `_lockedEscrowWei` is untouched by construction.
        o.status = uint8(PuppetTypes.OfferStatus.SETTLED);
        o.ownershipDigest = digest;

        emit OwnershipApproved(offerId, digest, attestation.purpose, address(0));

        tokenId = _mint(o);

        emit OfferSettled(offerId, o.rootKey, tokenId, o.recipient, address(0), 0, o.kind);
    }

    /*//////////////////////////////////////////////////////////////
                          BTC OWNERSHIP APPROVAL
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev Proves that the Bitcoin holder accepted these exact terms and named a Bitcoin payout
    ///      script, and nothing more. No HoodPup is minted and no ETH moves: the buyer's escrow is
    ///      still fully refundable at expiry, because at this point nobody has yet paid Bob
    ///      anything on the Bitcoin side.
    ///
    ///      Like `settleSelfCast`, this records no Root beneficiary — a `PAID_BTC_MINT`
    ///      attestation carries `PayoutMode.BTC` and a structurally zero `evmPayout`.
    /// @param offerId The offer to approve.
    /// @param attestation The 3-of-5 attested ownership statement authorizing this exact offer.
    /// @param signatures Attestor signatures, forwarded verbatim to the oracle.
    /// @param collectionProof Merkle proof of manifest membership, forwarded verbatim.
    function approvePaidBtc(
        bytes32 offerId,
        PuppetTypes.OwnershipAttestation calldata attestation,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) external whenNotPaused nonReentrant {
        PuppetTypes.Offer storage o = _settleableOffer(offerId, PuppetTypes.OfferKind.PAID_BTC);
        _requireTermsMatch(offerId, o, attestation, PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT);

        if (attestation.payoutMode != uint8(PuppetTypes.PayoutMode.BTC)) {
            revert AttestationFieldMismatch("payoutMode");
        }
        if (attestation.btcPayoutScriptHash == bytes32(0)) revert AttestationFieldMismatch("btcPayoutScriptHash");
        if (attestation.evmPayout != address(0)) revert AttestationFieldMismatch("evmPayout");

        bytes32 digest = _consume(o.rootKey, attestation, signatures, collectionProof);

        // EFFECTS. The escrow stays locked: this transition creates an obligation to a solver who
        // has not acted yet, not a payment.
        o.status = uint8(PuppetTypes.OfferStatus.BTC_APPROVED);
        o.ownershipDigest = digest;
        o.btcPayoutScriptHash = attestation.btcPayoutScriptHash;

        emit OwnershipApproved(offerId, digest, attestation.purpose, address(0));
        emit BtcOfferApproved(offerId, digest, attestation.btcPayoutScriptHash, attestation.sellerSats);
    }

    /*//////////////////////////////////////////////////////////////
                        AUTHORIZED BTC SOLVER HOOKS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev Grants one solver the exclusive right to pay Bob in BTC and be reimbursed here. While
    ///      reserved, the buyer's refund paths are closed, which is the whole point: a solver about
    ///      to broadcast an irreversible Bitcoin payment must not have the offer pulled from under
    ///      them mid-flight.
    ///
    ///      THAT FREEZE IS BOUNDED THREE WAYS, because an unbounded one would be a way to trap a
    ///      buyer's ETH forever. The window must end in the future, within `MAX_RESERVATION_WINDOW`
    ///      of now, and never later than the offer's own expiry. The last bound is what makes the
    ///      refund story airtight: a live reservation therefore implies an unexpired offer, and an
    ///      expired offer therefore implies a lapsed reservation that ANYONE may clear with
    ///      `expireBtcReservation`. There is no ordering of events in which the buyer's escrow is
    ///      both unrefundable and unsettleable.
    /// @param offerId The approved offer being reserved.
    /// @param solver The bonded solver claiming the reservation.
    /// @param reservationExpiry Unix timestamp at which the exclusive window closes.
    function markBtcReserved(bytes32 offerId, address solver, uint64 reservationExpiry)
        external
        whenNotPaused
        onlyRole(BTC_SETTLEMENT_ROLE)
    {
        PuppetTypes.Offer storage o = _offerWithStatus(offerId, PuppetTypes.OfferStatus.BTC_APPROVED);
        if (solver == address(0)) revert ZeroAddress();
        if (block.timestamp > o.expiry) revert OfferExpired(offerId, o.expiry);

        uint64 ceiling = o.expiry;
        uint64 windowCap = uint64(block.timestamp) + MAX_RESERVATION_WINDOW;
        if (windowCap < ceiling) ceiling = windowCap;
        if (reservationExpiry <= block.timestamp || reservationExpiry > ceiling) {
            revert ReservationWindowInvalid(reservationExpiry, uint64(block.timestamp), ceiling);
        }

        o.status = uint8(PuppetTypes.OfferStatus.BTC_RESERVED);
        o.reservedSolver = solver;
        o.reservationExpiry = reservationExpiry;

        emit BtcReserved(offerId, solver, reservationExpiry);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev NOT pausable. This only ever moves an offer back towards refundability, so blocking it
    ///      during an incident could only ever hurt the buyer.
    /// @param offerId The reserved offer to release.
    function clearBtcReservation(bytes32 offerId) external onlyRole(BTC_SETTLEMENT_ROLE) {
        PuppetTypes.Offer storage o = _offerWithStatus(offerId, PuppetTypes.OfferStatus.BTC_RESERVED);
        _releaseReservation(offerId, o);
    }

    /// @notice Permissionlessly release a reservation whose exclusive window has closed.
    /// @dev ADDITIVE, not part of `IHoodPupOfferEscrow`, and the reason a buyer's escrow can never
    ///      be trapped. `clearBtcReservation` requires `BTC_SETTLEMENT_ROLE`, so if
    ///      `BtcSolverSettlement` were paused, broken or had its role revoked, a reserved offer
    ///      would otherwise be frozen forever with the buyer's ETH inside it. This function needs
    ///      no role and no governance action: once the window the solver themselves asked for has
    ///      elapsed, anybody may return the offer to `BTC_APPROVED`, after which the ordinary
    ///      refund paths apply. It is not pausable, for the same reason.
    ///
    ///      It cannot harm an honest solver: the window is chosen by `BtcSolverSettlement` at
    ///      reservation time and `finalizeBtcSettlement` refuses a lapsed reservation anyway, so
    ///      this function can only release a reservation that was already unusable.
    /// @param offerId The reserved offer whose window has closed.
    function expireBtcReservation(bytes32 offerId) external {
        PuppetTypes.Offer storage o = _offerWithStatus(offerId, PuppetTypes.OfferStatus.BTC_RESERVED);
        if (block.timestamp <= o.reservationExpiry) revert ReservationNotLapsed(offerId, o.reservationExpiry);
        _releaseReservation(offerId, o);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev BOB IS NEVER PAID IN ETH HERE. He was already paid the exact `sellerSats` in native
    ///      Bitcoin by the bonded solver, off this chain, and `BtcSolverSettlement` proved that
    ///      with a consumed `BitcoinPaymentAttestation` before calling. The 50% seller share
    ///      therefore reimburses the SOLVER that fronted it; routing it to a seller address as
    ///      well would pay for the same Puppet twice. The two treasury shares are unaffected.
    ///
    ///      The reservation must still be live. A lapsed window means anybody could already have
    ///      released the offer and refunded the buyer, so honouring it here would let two
    ///      irreconcilable outcomes race. The consequence for solvers is real and is stated in the
    ///      integration notes: do not broadcast a Bitcoin payment you cannot finalize inside your
    ///      own reservation window.
    /// @param offerId The reserved offer to finalize.
    /// @param solver The solver being reimbursed. Must equal the recorded reservation holder.
    /// @param paymentDigest Digest of the Bitcoin payment attestation the caller consumed.
    /// @return tokenId The minted HoodPup's token id.
    function finalizeBtcSettlement(bytes32 offerId, address solver, bytes32 paymentDigest)
        external
        whenNotPaused
        nonReentrant
        onlyRole(BTC_SETTLEMENT_ROLE)
        returns (uint256 tokenId)
    {
        PuppetTypes.Offer storage o = _offerWithStatus(offerId, PuppetTypes.OfferStatus.BTC_RESERVED);
        if (solver != o.reservedSolver) revert NotReservedSolver(solver, o.reservedSolver);
        if (block.timestamp > o.reservationExpiry) revert ReservationLapsed(offerId, o.reservationExpiry);
        if (paymentDigest == bytes32(0)) revert ZeroValue();
        if (_HOOD_PUPS.rootMinted(o.rootKey)) revert RootAlreadyMinted(o.rootKey);

        // EFFECTS. `reservedSolver` and `reservationExpiry` are deliberately preserved: SETTLED is
        // terminal, so they cannot be reused, and they are the on-chain record of who was paid.
        o.status = uint8(PuppetTypes.OfferStatus.SETTLED);
        _lockedEscrowWei -= o.grossWei;

        emit BtcSettlementFinalized(offerId, solver, paymentDigest);

        _FEE_ROUTER.routeMintBtc{value: o.grossWei}(o.rootKey, solver, o.grossWei);
        tokenId = _mint(o);

        emit OfferSettled(offerId, o.rootKey, tokenId, o.recipient, solver, o.grossWei, o.kind);
    }

    /*//////////////////////////////////////////////////////////////
                                 REFUNDS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev PERMISSIONLESS AND NEVER PAUSABLE. Only the buyer is ever credited, so there is nothing
    ///      for a caller to gain by triggering it — which is exactly why anybody may, including a
    ///      keeper acting for a buyer who has no gas. No role, no pause and no governance action
    ///      can stop, delay or redirect it.
    ///
    ///      `BTC_RESERVED` is rejected here rather than silently allowed: a solver may be
    ///      mid-broadcast. The offer must first return to `BTC_APPROVED`, either through
    ///      `BtcSolverSettlement` or, if that contract is unavailable, through the permissionless
    ///      `expireBtcReservation`. Because a reservation can never outlive the offer, an expired
    ///      offer always has a lapsed reservation, so that route is always open.
    /// @param offerId The expired offer to refund.
    function refundExpired(bytes32 offerId) external nonReentrant {
        PuppetTypes.Offer storage o = _refundableOffer(offerId);
        if (block.timestamp <= o.expiry) revert OfferNotExpired(offerId, o.expiry);
        _refund(offerId, o, false);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    /// @dev Competing offers are allowed, so exactly one of them wins the Root and every other one
    ///      becomes permanently unfillable the instant the mint lands. Making those refundable
    ///      immediately, rather than at expiry, is what keeps a competitive offer book cheap for
    ///      buyers.
    ///
    ///      Unlike `refundExpired`, this DOES accept a `BTC_RESERVED` offer. Once the Root is
    ///      minted, `finalizeBtcSettlement` is structurally impossible — the mint would revert —
    ///      so the reservation protects nobody and holding the buyer's ETH for the rest of the
    ///      window would be pure cost. Such a reservation is explicitly RELEASED first, emitting
    ///      `BtcReservationCleared`, so a refunded offer never carries a solver and a window that
    ///      no longer mean anything. A stale reservation left on a terminal offer would be a lie in
    ///      the indexed history, and `BtcSolverSettlement` reads these fields.
    /// @param offerId The unfillable offer to refund.
    function refundUnfillable(bytes32 offerId) external nonReentrant {
        PuppetTypes.Offer storage o = _offers[offerId];
        uint8 status = o.status;
        if (status == uint8(PuppetTypes.OfferStatus.NONE)) revert UnknownOffer(offerId);
        if (
            status != uint8(PuppetTypes.OfferStatus.OPEN) && status != uint8(PuppetTypes.OfferStatus.BTC_APPROVED)
                && status != uint8(PuppetTypes.OfferStatus.BTC_RESERVED)
        ) {
            revert InvalidOfferStatus(offerId, status, uint8(PuppetTypes.OfferStatus.OPEN));
        }
        if (!_HOOD_PUPS.rootMinted(o.rootKey)) revert RootNotMinted(o.rootKey);
        if (status == uint8(PuppetTypes.OfferStatus.BTC_RESERVED)) _releaseReservation(offerId, o);
        _refund(offerId, o, true);
    }

    /*//////////////////////////////////////////////////////////////
                                 PAUSING
    //////////////////////////////////////////////////////////////*/

    /// @notice Halt new offers and new settlements. Refunds are unaffected.
    /// @dev Guardian-facing: fast to reach, and it cannot touch anybody's money.
    function pauseSettlement() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Resume offers and settlements.
    /// @dev `DEFAULT_ADMIN_ROLE`, not `PAUSER_ROLE`: re-enabling risk is the direction that should
    ///      require the timelock. A guardian that could unpause could also un-do its own incident
    ///      response under duress.
    function unpauseSettlement() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL — CREATION
    //////////////////////////////////////////////////////////////*/

    /// @dev The terms of a new offer, carried as ONE memory pointer.
    ///      Solidity without via-IR can only reach 16 stack slots, and offer creation legitimately
    ///      handles more distinct values than that. Bundling them keeps the whole creation path
    ///      readable rather than splitting the security-critical checks across artificial helpers.
    struct NewOffer {
        address recipient;
        bytes32 rootTxid;
        uint32 rootIndex;
        uint64 sellerSats;
        uint64 expiry;
        uint8 kind;
    }

    /// @dev Shared body of the three creation entry points.
    function _create(
        PuppetTypes.RootId calldata root,
        address recipient,
        uint64 expiry,
        bytes32[] calldata collectionProof,
        PuppetTypes.OfferKind kind,
        uint64 sellerSats
    ) private returns (bytes32 offerId) {
        if (recipient == address(0)) revert ZeroAddress();
        if (root.inscriptionTxid == bytes32(0)) revert ZeroRootTxid();
        _requireExpiryInWindow(expiry);

        // Membership is proven against the immutable manifest commitment, not asserted by anyone.
        bytes32 rootKey = _COLLECTION_REGISTRY.requireMember(root, collectionProof);
        if (_HOOD_PUPS.rootMinted(rootKey)) revert RootAlreadyMinted(rootKey);

        offerId = PuppetHashing.offerId(block.chainid, address(this), msg.sender, _buyerNonce[msg.sender]);
        unchecked {
            // One increment per offer; overflowing a uint256 nonce is not a reachable state.
            _buyerNonce[msg.sender] += 1;
        }

        _store(
            offerId,
            rootKey,
            NewOffer({
                recipient: recipient,
                rootTxid: root.inscriptionTxid,
                rootIndex: root.inscriptionIndex,
                sellerSats: sellerSats,
                expiry: expiry,
                kind: uint8(kind)
            })
        );
    }

    /// @dev Assert the requested expiry sits inside the configured window.
    ///      The window is measured from NOW, not from a stored anchor, so it bounds how long the
    ///      buyer's ETH can be locked before the refund path opens.
    function _requireExpiryInWindow(uint64 expiry) private view {
        uint64 minAllowed = uint64(block.timestamp) + _MINIMUM_OFFER_DURATION;
        uint64 maxAllowed = uint64(block.timestamp) + _MAXIMUM_OFFER_DURATION;
        if (expiry < minAllowed || expiry > maxAllowed) revert InvalidExpiry(expiry, minAllowed, maxAllowed);
    }

    /// @dev Snapshot the immutable terms, the exact 50/25/25 split and the terms commitment.
    ///      Everything written here is written once and never mutated again: only `status`,
    ///      `ownershipDigest`, `btcPayoutScriptHash` and the two reservation fields ever change.
    function _store(bytes32 offerId, bytes32 rootKey, NewOffer memory n) private {
        // The split is read from FeeRouter rather than recomputed here, so the 50/25/25 rule has
        // exactly one on-chain definition and the stored amounts can never drift from the amounts
        // that will actually be routed at settlement.
        (uint256 sellerWei, uint256 treasuryWei, uint256 protocolWei) = _FEE_ROUTER.quote(msg.value);

        bytes32 termsHash = computeTermsHash(
            offerId, n.kind, rootKey, msg.sender, n.recipient, msg.value, sellerWei, n.sellerSats, n.expiry
        );

        PuppetTypes.Offer storage o = _offers[offerId];
        o.buyer = msg.sender;
        o.recipient = n.recipient;
        o.rootKey = rootKey;
        o.rootTxid = n.rootTxid;
        o.rootIndex = n.rootIndex;
        o.grossWei = msg.value;
        o.sellerWei = sellerWei;
        o.treasuryWei = treasuryWei;
        o.protocolWei = protocolWei;
        o.sellerSats = n.sellerSats;
        o.createdAt = uint64(block.timestamp);
        o.expiry = n.expiry;
        o.kind = n.kind;
        o.status = uint8(PuppetTypes.OfferStatus.OPEN);
        o.termsHash = termsHash;

        _lockedEscrowWei += msg.value;

        emit OfferCreated(
            offerId, rootKey, msg.sender, n.recipient, n.kind, msg.value, sellerWei, n.sellerSats, n.expiry, termsHash
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL — LOOKUP AND GUARDS
    //////////////////////////////////////////////////////////////*/

    /// @dev Load an offer and assert its exact status.
    function _offerWithStatus(bytes32 offerId, PuppetTypes.OfferStatus expected)
        private
        view
        returns (PuppetTypes.Offer storage o)
    {
        o = _offers[offerId];
        uint8 status = o.status;
        if (status == uint8(PuppetTypes.OfferStatus.NONE)) revert UnknownOffer(offerId);
        if (status != uint8(expected)) revert InvalidOfferStatus(offerId, status, uint8(expected));
    }

    /// @dev Load an OPEN offer of `kind` that is unexpired and whose Root is still unminted.
    ///      Every attestation-consuming entry point starts here, so the four preconditions that
    ///      make an attestation worth verifying at all are checked in exactly one place.
    function _settleableOffer(bytes32 offerId, PuppetTypes.OfferKind kind)
        private
        view
        returns (PuppetTypes.Offer storage o)
    {
        o = _offerWithStatus(offerId, PuppetTypes.OfferStatus.OPEN);
        if (o.kind != uint8(kind)) revert UnexpectedOfferKind(offerId, o.kind, uint8(kind));
        // Inclusive: an offer is live through the whole second named as its expiry, and refundable
        // only strictly after it. The two conditions therefore partition time with no overlap and
        // no gap, so an offer can never be simultaneously settleable and refundable.
        if (block.timestamp > o.expiry) revert OfferExpired(offerId, o.expiry);
        if (_HOOD_PUPS.rootMinted(o.rootKey)) revert RootAlreadyMinted(o.rootKey);
    }

    /// @dev Load an offer that a refund path may act on. `BTC_RESERVED` is excluded on purpose.
    function _refundableOffer(bytes32 offerId) private view returns (PuppetTypes.Offer storage o) {
        o = _offers[offerId];
        uint8 status = o.status;
        if (status == uint8(PuppetTypes.OfferStatus.NONE)) revert UnknownOffer(offerId);
        if (status != uint8(PuppetTypes.OfferStatus.OPEN) && status != uint8(PuppetTypes.OfferStatus.BTC_APPROVED)) {
            revert InvalidOfferStatus(offerId, status, uint8(PuppetTypes.OfferStatus.OPEN));
        }
    }

    /// @dev Assert that every term the Bitcoin holder signed equals the term this escrow stored.
    ///      Each field gets its own named error so a failed settlement tells the relayer exactly
    ///      which value diverged, rather than a single opaque "mismatch".
    ///
    ///      `offerTermsHash` alone would cover most of these, since it commits to the offer id,
    ///      kind, root key, buyer, recipient, both amounts, the sats and the expiry. The individual
    ///      checks are kept anyway: they are what makes a divergence diagnosable, and they mean a
    ///      future change to `PuppetHashing.offerTermsHash` that dropped a field would be caught
    ///      here instead of silently widening what a signature authorizes.
    function _requireTermsMatch(
        bytes32 offerId,
        PuppetTypes.Offer storage o,
        PuppetTypes.OwnershipAttestation calldata a,
        PuppetTypes.AuthorizationPurpose purpose
    ) private view {
        if (a.purpose != uint8(purpose)) {
            revert UnexpectedPurpose(a.purpose, uint8(purpose));
        }
        if (a.contextId != offerId) revert AttestationFieldMismatch("contextId");
        if (a.offerTermsHash != o.termsHash) revert AttestationFieldMismatch("offerTermsHash");
        if (a.rootTxid != o.rootTxid) revert AttestationFieldMismatch("rootTxid");
        if (a.rootIndex != o.rootIndex) revert AttestationFieldMismatch("rootIndex");
        if (a.buyer != o.buyer) revert AttestationFieldMismatch("buyer");
        if (a.recipient != o.recipient) revert AttestationFieldMismatch("recipient");
        if (a.grossWei != o.grossWei) revert AttestationFieldMismatch("grossWei");
        if (a.sellerWei != o.sellerWei) revert AttestationFieldMismatch("sellerWei");
        if (a.sellerSats != o.sellerSats) revert AttestationFieldMismatch("sellerSats");
        // The two Bitcoin facts that `RootOwnershipRegistry` will be handed. A zero here would be
        // recorded as a real outpoint and would make a later spend attestation unmatchable.
        if (a.currentOutpointHash == bytes32(0)) revert AttestationFieldMismatch("currentOutpointHash");
        if (a.ownerScriptHash == bytes32(0)) revert AttestationFieldMismatch("ownerScriptHash");
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL — EFFECTS AND CALLS
    //////////////////////////////////////////////////////////////*/

    /// @dev Consume the attestation through the oracle and cross-check the identity it derived.
    function _consume(
        bytes32 expectedRootKey,
        PuppetTypes.OwnershipAttestation calldata a,
        bytes[] calldata signatures,
        bytes32[] calldata collectionProof
    ) private returns (bytes32 digest) {
        bytes32 derivedRootKey;
        (digest, derivedRootKey) = _OWNERSHIP_ORACLE.consumeOwnership(a, signatures, collectionProof);
        if (derivedRootKey != expectedRootKey) revert RootMismatch(expectedRootKey, derivedRootKey);
    }

    /// @dev Open the Root's first ownership epoch from the facts the quorum just signed.
    ///      Extracted into its own function purely to keep `settlePaidEvm` under the EVM's 16-slot
    ///      stack limit without enabling via-IR; it has exactly one call site.
    function _recordFirstOwnershipEpoch(bytes32 rootKey, bytes32 digest, PuppetTypes.OwnershipAttestation calldata a)
        private
    {
        _ROOT_OWNERSHIP_REGISTRY.recordMintOwnership(
            rootKey,
            a.evmPayout,
            a.currentOutpointHash,
            a.ownerScriptHash,
            digest,
            a.bip322ProofHash,
            a.bitcoinBlockHash,
            a.bitcoinHeight
        );
    }

    /// @dev Mint the single HoodPup for an offer's Root. Always the last external call on a
    ///      settlement path, because `_safeMint` hands control to the recipient.
    function _mint(PuppetTypes.Offer storage o) private returns (uint256 tokenId) {
        return _HOOD_PUPS.mintRooted(
            o.recipient, PuppetTypes.RootId({inscriptionTxid: o.rootTxid, inscriptionIndex: o.rootIndex})
        );
    }

    /// @dev Return a reserved offer to `BTC_APPROVED` and clear the reservation fields.
    function _releaseReservation(bytes32 offerId, PuppetTypes.Offer storage o) private {
        address solver = o.reservedSolver;
        o.status = uint8(PuppetTypes.OfferStatus.BTC_APPROVED);
        o.reservedSolver = address(0);
        o.reservationExpiry = 0;

        emit BtcReservationCleared(offerId, solver);
    }

    /// @dev Credit the buyer's escrow back inside `PayoutVault` and close the offer.
    ///      Checks-effects-interactions: the status is terminal and the escrow accounting is
    ///      decremented before the vault is touched, so a re-entrant refund finds nothing to refund.
    ///
    ///      A self-cast escrows nothing, so there is no credit to make. It still moves to REFUNDED
    ///      so that a Bitcoin holder who opened one and never signed does not leave a permanently
    ///      OPEN row in the offer book.
    function _refund(bytes32 offerId, PuppetTypes.Offer storage o, bool unfillable) private {
        uint256 amount = o.grossWei;
        address buyer = o.buyer;

        o.status = uint8(PuppetTypes.OfferStatus.REFUNDED);
        if (amount != 0) {
            _lockedEscrowWei -= amount;
        }

        emit OfferRefunded(offerId, buyer, amount, unfillable);

        if (amount != 0) {
            // Pull payment, never a push: a buyer whose address reverts on receive must not be able
            // to make their own refund — and therefore this offer — permanently unclosable.
            _PAYOUT_VAULT.creditRefund{value: amount}(buyer);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            NO STRAY ETH IN
    //////////////////////////////////////////////////////////////*/

    /// @dev ETH may only enter as `msg.value` on a creation function, where it is immediately
    ///      attributed to exactly one offer. There is no sweep for force-sent ETH, and that is
    ///      deliberate: a sweep needs a destination, a destination needs an authority to choose it,
    ///      and an authority that can move ETH out of an escrow is precisely the admin path this
    ///      protocol forbids. Dust forced in with `selfdestruct` is stranded and harmless — it is
    ///      never counted as anyone's escrow and can never be paid out to anyone.
    receive() external payable {
        revert DirectDepositRejected();
    }

    fallback() external payable {
        revert DirectDepositRejected();
    }
}
