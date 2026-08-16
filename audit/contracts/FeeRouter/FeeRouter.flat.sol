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

// src/FeeRouter.sol

/// @title FeeRouter
/// @notice The immutable 50 / 25 / 25 HoodPups economic split, and the only contract allowed to
///         turn settlement value into `PayoutVault` liabilities.
/// @dev WHY THIS CONTRACT EXISTS AS A SEPARATE CONTRACT. The split is the single economic promise
///      the protocol makes to Bitcoin Puppet holders. Burying it inside the escrow would mean the
///      escrow's whole (large) attack surface stands between a reader and the arithmetic they came
///      to check. Here the entire economic policy is four constants and nine lines of arithmetic in
///      one file, with no setter, no proxy, no initializer and no `delegatecall`, so verifying
///      "50 / 25 / 25, forever" is a matter of reading a screen of code rather than auditing a
///      state machine.
///
///      THE SPLIT, stated once:
///
///          sellerAmount         = gross * 5000 / 10000     (floor)
///          puppetTreasuryAmount = gross * 2500 / 10000     (floor)
///          protocolAmount       = gross - seller - puppetTreasury
///
///      Both percentage terms floor, so up to 3 wei of rounding dust would otherwise vanish. The
///      protocol share is defined as the REMAINDER rather than as its own percentage, which makes
///      `seller + puppetTreasury + protocol == gross` an identity for every input — including 0, 1,
///      2 and 3 wei, where the percentage terms are zero. The protocol absorbing the dust (rather
///      than the seller or the ecosystem treasury) is the deliberate choice: dust must land
///      somewhere, and it should land on the party that wrote the rounding rule.
///
///      PERCENTAGES CANNOT CHANGE. They are `constant`, so they live in the deployed bytecode and
///      not in storage; there is no function on this contract that writes them and no upgrade path
///      that could replace the code. Only the two treasury DESTINATION addresses are governable,
///      and only by `TREASURY_ADMIN_ROLE`, which is meant to be a `TimelockController`.
///
///      THE ROUTER NEVER HOLDS VALUE. Every route forwards its entire `msg.value` into the vault in
///      the same transaction and then asserts that its own balance is unchanged from what it was
///      before the call. There is no owner withdrawal, no rescue function with a caller-chosen
///      destination, and no path by which a privileged account can redirect value that is already
///      in flight or already credited.
///
///      TRUST BOUNDARY. This contract knows nothing about Bitcoin. It is handed a `rootKey`, a
///      beneficiary and an amount by a holder of `ROUTER_CALLER_ROLE` (the offer escrow and the
///      solver settlement contract), which derive those facts from a 3-of-5 quorum of independent
///      attestors. That is an attested settlement system, not a trustless bridge. The original
///      Bitcoin Puppet never leaves Bitcoin and is never wrapped, escrowed or custodied anywhere in
///      this protocol; this contract moves ETH and nothing else.
contract FeeRouter is IFeeRouter, AccessControl, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE ECONOMICS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFeeRouter
    /// @dev The current Bitcoin controller's share. `constant`, in bytecode, with no setter.
    uint256 public constant SELLER_BPS = 5000;

    /// @inheritdoc IFeeRouter
    /// @dev The Bitcoin Puppets ecosystem treasury's share.
    uint256 public constant PUPPET_TREASURY_BPS = 2500;

    /// @inheritdoc IFeeRouter
    /// @dev The protocol treasury's nominal share. The amount actually credited is computed as the
    ///      remainder, so this constant is the floor of what the protocol receives, never a cap
    ///      applied after the fact — see `quote`.
    uint256 public constant PROTOCOL_BPS = 2500;

    /// @inheritdoc IFeeRouter
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                              ROUTE TAGS
    //////////////////////////////////////////////////////////////*/

    /// @notice `route` value emitted by `MintRouted` for an EVM-payout mint.
    /// @dev Deliberately equal to `uint8(PuppetTypes.OfferKind.PAID_EVM)` so one number means the
    ///      same thing in the escrow's offer records and in this contract's events. A unit test
    ///      pins the equality so a future reordering of that enum cannot silently desynchronise the
    ///      two without failing CI.
    uint8 public constant ROUTE_MINT_EVM = 0;

    /// @notice `route` value emitted by `MintRouted` for a native-BTC mint.
    /// @dev Equal to `uint8(PuppetTypes.OfferKind.PAID_BTC)`. See `ROUTE_MINT_EVM`.
    uint8 public constant ROUTE_MINT_BTC = 1;

    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role permitted to route settlement or activity value through the split.
    /// @dev Held by `HoodPupOfferEscrow` and `BtcSolverSettlement`. Deliberately NOT granted at
    ///      construction: those contracts do not exist yet at this point in the deployment, and
    ///      pre-granting it to the deployer would create exactly the privileged EOA the handover is
    ///      meant to eliminate. The role cannot move value that is already in the vault — it can
    ///      only ask this contract to split ETH the caller itself supplied in the same call.
    bytes32 public constant ROUTER_CALLER_ROLE = keccak256("ROUTER_CALLER_ROLE");

    /// @notice Role permitted to repoint the two treasury destination addresses.
    /// @dev Separated from `DEFAULT_ADMIN_ROLE` for least privilege: role administration and
    ///      treasury custody are different duties and may legitimately sit behind different
    ///      timelocks. Both are granted to `admin` at construction so a single-timelock deployment
    ///      works out of the box.
    ///
    ///      WHY THERE IS NO SECOND, IN-CONTRACT TIMELOCK ON THESE SETTERS. A treasury change only
    ///      affects value routed AFTER it lands. Value already credited sits in `PayoutVault` under
    ///      the OLD address and stays withdrawable by that address alone — this contract cannot
    ///      reach into the vault and move it. The blast radius of a bad update is therefore bounded
    ///      by "future revenue until the update is reverted", which is precisely the class of risk
    ///      an external `TimelockController` plus its public proposal queue is designed to cover.
    ///      Adding a second delay here would duplicate that control without shrinking the radius.
    bytes32 public constant TREASURY_ADMIN_ROLE = keccak256("TREASURY_ADMIN_ROLE");

    /*//////////////////////////////////////////////////////////////
                              EXTRA ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a route is handed the zero Root key.
    /// @dev Every route emits an event indexed on `rootKey`, and the recurring route uses it as the
    ///      vault's pending-bucket key. A zero key would produce an un-attributable payout record
    ///      and, on the recurring path, would be rejected by the vault anyway — failing here gives
    ///      the caller the accurate reason.
    error ZeroRootKey();

    /// @notice Thrown when a route is handed a gross of zero.
    /// @dev A free mint (`SELF_CAST`) must not call the router at all. Accepting a zero route would
    ///      emit a payout event describing a payment that never happened, which is worse than a
    ///      revert: indexers and accounting tools would faithfully record it.
    error ZeroGross();

    /// @notice Thrown when `sweepForcedEth` runs with no force-sent ETH present.
    error NoForcedEth();

    /// @notice Thrown when a treasury setter is asked to write the value already stored.
    /// @dev A governance proposal executed twice would otherwise emit a second `TreasuryUpdated`
    ///      event describing a change that did not occur, muddying the on-chain audit trail of who
    ///      controlled protocol revenue at which block.
    /// @param treasury The unchanged address.
    error TreasuryUnchanged(address treasury);

    /*//////////////////////////////////////////////////////////////
                              EXTRA EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, recording the immutable wiring.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `TREASURY_ADMIN_ROLE`.
    /// @param vault Vault every route credits.
    /// @param registry Registry consulted for recurring-route beneficiaries.
    /// @param puppetTreasury Genesis Bitcoin Puppets ecosystem treasury.
    /// @param protocolTreasury Genesis protocol treasury.
    event RouterInitialized(
        address indexed admin,
        address indexed vault,
        address indexed registry,
        address puppetTreasury,
        address protocolTreasury
    );

    /// @notice Emitted when force-sent ETH is pushed into the vault for the protocol treasury.
    /// @param protocolTreasury Destination, read from storage at execution time.
    /// @param amount Wei swept.
    /// @param caller Whoever called the permissionless sweep.
    event ForcedEthSwept(address indexed protocolTreasury, uint256 amount, address indexed caller);

    /*//////////////////////////////////////////////////////////////
                             IMMUTABLE WIRING
    //////////////////////////////////////////////////////////////*/

    /// @notice Vault that receives every wei this router splits.
    /// @dev `immutable`, so no governance action can repoint the router at a different vault and
    ///      strand or divert settlement funds. Repointing requires a redeployment plus regranting
    ///      `ROUTER_CALLER_ROLE`, which is a visible, reviewable operation.
    IPayoutVault public immutable PAYOUT_VAULT;

    /// @notice Registry consulted to find a Root's currently verified beneficiary.
    /// @dev `immutable` for the same reason as `PAYOUT_VAULT`. Read-only from this contract's point
    ///      of view: the router never writes Bitcoin state, it only asks who is currently attested.
    IRootOwnershipRegistry public immutable ROOT_REGISTRY;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Bitcoin Puppets ecosystem treasury. One of only two mutable words in this contract.
    address private _puppetTreasury;

    /// @dev Protocol treasury. The other one.
    address private _protocolTreasury;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the router and bind it permanently to a vault and a Root registry.
    /// @dev `admin` MUST be a `TimelockController` under multisig control in production. Nothing
    ///      here can enforce that, so the deployment script is responsible for granting to the
    ///      timelock and revoking the deployer in the same batch. `ROUTER_CALLER_ROLE` is left
    ///      unassigned on purpose.
    ///
    ///      Every address argument is rejected when zero. A zero vault would make every route
    ///      revert (funds stay safely in the escrow, but the protocol is bricked); a zero treasury
    ///      would make the vault reject the batch for the same reason. Both are unrecoverable
    ///      without redeployment, which is why they are checked rather than left to fail later.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `TREASURY_ADMIN_ROLE`.
    /// @param payoutVault_ Vault every route credits.
    /// @param rootRegistry_ Registry consulted on the recurring route.
    /// @param puppetTreasury_ Genesis Bitcoin Puppets ecosystem treasury address.
    /// @param protocolTreasury_ Genesis protocol treasury address.
    constructor(
        address admin,
        IPayoutVault payoutVault_,
        IRootOwnershipRegistry rootRegistry_,
        address puppetTreasury_,
        address protocolTreasury_
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (address(payoutVault_) == address(0)) revert ZeroAddress();
        if (address(rootRegistry_) == address(0)) revert ZeroAddress();
        if (puppetTreasury_ == address(0)) revert ZeroAddress();
        if (protocolTreasury_ == address(0)) revert ZeroAddress();

        PAYOUT_VAULT = payoutVault_;
        ROOT_REGISTRY = rootRegistry_;
        _puppetTreasury = puppetTreasury_;
        _protocolTreasury = protocolTreasury_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TREASURY_ADMIN_ROLE, admin);

        emit RouterInitialized(admin, address(payoutVault_), address(rootRegistry_), puppetTreasury_, protocolTreasury_);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFeeRouter
    /// @return Current Bitcoin Puppets ecosystem treasury address.
    function puppetTreasury() external view returns (address) {
        return _puppetTreasury;
    }

    /// @inheritdoc IFeeRouter
    /// @return Current protocol treasury address.
    function protocolTreasury() external view returns (address) {
        return _protocolTreasury;
    }

    /// @inheritdoc IFeeRouter
    /// @dev `public` rather than `external` so the three routes split with the exact same code path
    ///      a caller can quote off chain — there is deliberately no second, internal copy of this
    ///      arithmetic that could drift from the published one.
    ///
    ///      OVERFLOW BOUND, stated honestly: `gross * 5000` reverts with a checked-arithmetic panic
    ///      above `type(uint256).max / 5000`, which is roughly 2.3e73 wei — about 1e47 times every
    ///      wei that will ever exist. It is unreachable by any real value and by `msg.value`, which
    ///      is bounded by the chain's actual supply. The multiply-then-divide form is kept anyway
    ///      because it is the form the SDK, the indexer and the spec all state, and three
    ///      implementations agreeing character for character is worth more than removing a branch
    ///      that cannot be taken.
    /// @param gross Total wei to split.
    /// @return sellerAmount 50% of `gross`, floored.
    /// @return puppetTreasuryAmount 25% of `gross`, floored.
    /// @return protocolAmount Everything left over, so the three always sum to `gross` exactly.
    function quote(uint256 gross)
        public
        pure
        returns (uint256 sellerAmount, uint256 puppetTreasuryAmount, uint256 protocolAmount)
    {
        sellerAmount = (gross * SELLER_BPS) / BPS_DENOMINATOR;
        puppetTreasuryAmount = (gross * PUPPET_TREASURY_BPS) / BPS_DENOMINATOR;
        // The remainder, never an independent percentage. This is what makes conservation exact.
        protocolAmount = gross - sellerAmount - puppetTreasuryAmount;
    }

    /*//////////////////////////////////////////////////////////////
                                 ROUTING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFeeRouter
    /// @dev The seller is credited inside the vault rather than paid directly, because a seller
    ///      whose payout address is a contract that reverts on receive would otherwise be able to
    ///      block their own mint — and therefore every buyer's mint of that Puppet — at zero cost.
    ///      All three shares go in through ONE `creditBatch`, so the vault sees a single atomic
    ///      accounting event per settlement and a partially-applied split is impossible.
    /// @param rootKey Canonical `PuppetHashing.rootKey` of the inscription being minted against.
    /// @param seller Bitcoin controller's Robinhood Chain payout address.
    /// @param gross Total wei escrowed by the buyer; must equal `msg.value`.
    function routeMintEvm(bytes32 rootKey, address seller, uint256 gross)
        external
        payable
        onlyRole(ROUTER_CALLER_ROLE)
        nonReentrant
    {
        if (seller == address(0)) revert ZeroAddress();
        _checkRouteInputs(rootKey, gross);

        uint256 preExistingBalance = address(this).balance - msg.value;
        (uint256 sellerAmount, uint256 puppetAmount, uint256 protocolAmount) = quote(gross);

        // EFFECTS-equivalent: the payout record is emitted before any external call, so an event
        // log can never describe a split that a later revert undid halfway.
        emit MintRouted(rootKey, seller, ROUTE_MINT_EVM, gross, sellerAmount, puppetAmount, protocolAmount);

        _creditSplit(seller, sellerAmount, puppetAmount, protocolAmount, false);
        _assertNothingRetained(preExistingBalance);
    }

    /// @inheritdoc IFeeRouter
    /// @dev IDENTICAL SPLIT, DIFFERENT RECIPIENT FOR THE 50%. The Bitcoin controller has already
    ///      been paid in native BTC by a bonded solver, off this chain. The seller share therefore
    ///      reimburses the solver that fronted that BTC; paying the seller again here would pay for
    ///      the same Puppet twice. Which address counts as "the solver" is decided by
    ///      `BtcSolverSettlement` against an attested payment fact — this contract trusts its
    ///      authorized caller for that and binds exactly the address it is handed.
    /// @param rootKey Canonical `PuppetHashing.rootKey` of the inscription being minted against.
    /// @param solver Address of the bonded solver that already paid the seller in BTC.
    /// @param gross Total wei escrowed by the buyer; must equal `msg.value`.
    function routeMintBtc(bytes32 rootKey, address solver, uint256 gross)
        external
        payable
        onlyRole(ROUTER_CALLER_ROLE)
        nonReentrant
    {
        if (solver == address(0)) revert ZeroAddress();
        _checkRouteInputs(rootKey, gross);

        uint256 preExistingBalance = address(this).balance - msg.value;
        (uint256 solverAmount, uint256 puppetAmount, uint256 protocolAmount) = quote(gross);

        emit MintRouted(rootKey, solver, ROUTE_MINT_BTC, gross, solverAmount, puppetAmount, protocolAmount);

        // The solver may already have paid irreversible BTC. Route through the vault's terminal
        // accounting path so an ordinary credit pause cannot strand that cross-chain obligation.
        _creditSplit(solver, solverAmount, puppetAmount, protocolAmount, true);
        _assertNothingRetained(preExistingBalance);
    }

    /// @inheritdoc IFeeRouter
    /// @dev THE LAG PROBLEM, AND WHY THE PENDING BUCKET EXISTS. The registry records ATTESTED
    ///      Bitcoin ownership, not live Bitcoin ownership. Between the moment a Puppet changes
    ///      hands on Bitcoin and the moment a watcher submits the spend attestation, the registry
    ///      still names the previous owner and is marked inactive as soon as that spend is seen. If
    ///      the Root share were paid to a named address in that window it could reach the wrong
    ///      person irreversibly. Instead it goes to `PayoutVault.creditRoot(rootKey)`, where it is
    ///      already a liability of the vault but belongs to no address yet, and is released to
    ///      whoever next proves Bitcoin control. Nobody loses the money; it simply waits.
    ///
    ///      The two treasuries are paid in both branches. Their entitlement does not depend on who
    ///      controls the inscription, so withholding it would be an unnecessary second failure mode.
    ///
    ///      A registry that reports `active == true` with a zero beneficiary is treated as
    ///      inactive. That combination should be unreachable in the real registry, but the router
    ///      is the contract holding the money at that instant, and routing to the pending bucket is
    ///      recoverable whereas reverting the whole settlement is not.
    /// @param rootKey Canonical `PuppetHashing.rootKey` the recurring value is attached to.
    /// @param gross Total wei to split; must equal `msg.value`.
    function routeRecurring(bytes32 rootKey, uint256 gross) external payable onlyRole(ROUTER_CALLER_ROLE) nonReentrant {
        _checkRouteInputs(rootKey, gross);

        uint256 preExistingBalance = address(this).balance - msg.value;
        (uint256 rootAmount, uint256 puppetAmount, uint256 protocolAmount) = quote(gross);

        (address beneficiary, bool active,) = ROOT_REGISTRY.currentBeneficiary(rootKey);
        bool payBeneficiaryDirectly = active && beneficiary != address(0);

        emit RecurringRouted(
            rootKey,
            payBeneficiaryDirectly ? beneficiary : address(0),
            payBeneficiaryDirectly,
            gross,
            rootAmount,
            puppetAmount,
            protocolAmount
        );

        if (payBeneficiaryDirectly) {
            _creditSplit(beneficiary, rootAmount, puppetAmount, protocolAmount, false);
        } else {
            // `rootAmount` is zero only for a sub-2-wei gross; the vault rejects zero-value credits,
            // so the call is skipped rather than allowed to revert the whole settlement over dust.
            if (rootAmount > 0) {
                PAYOUT_VAULT.creditRoot{value: rootAmount}(rootKey);
            }
            _creditSplit(address(0), 0, puppetAmount, protocolAmount, false);
        }

        _assertNothingRetained(preExistingBalance);
    }

    /*//////////////////////////////////////////////////////////////
                            TREASURY GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Repoint the Bitcoin Puppets ecosystem treasury.
    /// @dev Affects future routes only. Value already credited under the previous address remains
    ///      that address's to withdraw from the vault; this contract has no ability to move it.
    /// @param next New ecosystem treasury address.
    function setPuppetTreasury(address next) external onlyRole(TREASURY_ADMIN_ROLE) {
        address previous = _puppetTreasury;
        if (next == address(0)) revert ZeroAddress();
        if (next == previous) revert TreasuryUnchanged(previous);

        _puppetTreasury = next;

        emit TreasuryUpdated(previous, next, false);
    }

    /// @notice Repoint the protocol treasury.
    /// @dev Same bounded blast radius as `setPuppetTreasury`. This address is also the fixed
    ///      destination of `sweepForcedEth`, which is why that function needs no destination
    ///      argument and therefore cannot be aimed by its caller.
    /// @param next New protocol treasury address.
    function setProtocolTreasury(address next) external onlyRole(TREASURY_ADMIN_ROLE) {
        address previous = _protocolTreasury;
        if (next == address(0)) revert ZeroAddress();
        if (next == previous) revert TreasuryUnchanged(previous);

        _protocolTreasury = next;

        emit TreasuryUpdated(previous, next, true);
    }

    /*//////////////////////////////////////////////////////////////
                               FORCED ETH
    //////////////////////////////////////////////////////////////*/

    /// @notice Push any force-sent ETH into the vault, credited to the protocol treasury.
    /// @dev WHY THIS IS PERMISSIONLESS AND HAS NO DESTINATION ARGUMENT. `receive` and `fallback`
    ///      both revert, but `selfdestruct` beneficiary payments and consensus-layer withdrawal
    ///      credits cannot be refused by any contract. That ETH is not in-flight settlement value —
    ///      routing forwards its whole `msg.value` and asserts a zero delta within the same
    ///      transaction, so between transactions the only ETH here is forced ETH.
    ///
    ///      The destination is read from storage at execution and is the governed protocol
    ///      treasury; the caller chooses nothing and receives nothing. That is what keeps this from
    ///      being the "generic owner withdrawal" the protocol rules forbid: there is no privileged
    ///      account, no discretion over where the money goes, and therefore nothing for a timelock
    ///      to delay. Forced ETH carries no identifiable sender, so returning it is not possible;
    ///      surfacing it through the normal accounting with a public event is the honest handling.
    ///
    ///      It cannot touch in-flight value: `nonReentrant` shares its slot with the three routes,
    ///      so this cannot execute inside a route, and outside a route there is no in-flight value.
    /// @return amount Wei swept into the vault.
    function sweepForcedEth() external nonReentrant returns (uint256 amount) {
        amount = address(this).balance;
        if (amount == 0) revert NoForcedEth();

        address treasury = _protocolTreasury;

        emit ForcedEthSwept(treasury, amount, msg.sender);

        PAYOUT_VAULT.credit{value: amount}(treasury);

        // The router is a conduit; it must be empty again the moment the call returns.
        _assertNothingRetained(0);
    }

    /*//////////////////////////////////////////////////////////////
                               ERC-165
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC-165 support, extended with `IFeeRouter`.
    /// @param interfaceId Interface identifier being queried.
    /// @return True when the interface is supported.
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeeRouter).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Input rules shared by all three routes. `msg.value == gross` is the one that matters:
    ///      the router splits what it was actually paid, and a caller that names a larger `gross`
    ///      than it sends would otherwise get a payout event and a `creditBatch` for money that is
    ///      not there (the batch would revert, but with the vault's error rather than the router's).
    /// @param rootKey Root key supplied by the caller.
    /// @param gross Gross supplied by the caller.
    function _checkRouteInputs(bytes32 rootKey, uint256 gross) private view {
        if (rootKey == bytes32(0)) revert ZeroRootKey();
        if (gross == 0) revert ZeroGross();
        if (msg.value != gross) revert ValueMismatch(gross, msg.value);
    }

    /// @dev Credits up to three beneficiaries in ONE `creditBatch`, skipping zero-valued entries.
    ///
    ///      WHY ZERO ENTRIES ARE SKIPPED RATHER THAN SENT. `PayoutVault.creditBatch` rejects a zero
    ///      amount, correctly: for the vault, a zero entry is always a bug in the caller's
    ///      arithmetic. For this router it is not a bug, it is the arithmetic working — a 1 wei
    ///      gross legitimately produces `(0, 0, 1)`. Filtering here is what lets tiny values route
    ///      successfully instead of reverting on dust, and it is safe because the value forwarded
    ///      is the sum of exactly the entries that were kept.
    ///
    ///      At least one entry always survives for a non-zero gross: the protocol share is at least
    ///      `ceil(gross / 4)`, hence at least 1 wei.
    /// @param primary Seller, solver or Root beneficiary. Ignored when `primaryAmount` is zero.
    /// @param primaryAmount The 50% share.
    /// @param puppetAmount The Puppet ecosystem treasury share.
    /// @param protocolAmount The protocol treasury share.
    function _creditSplit(
        address primary,
        uint256 primaryAmount,
        uint256 puppetAmount,
        uint256 protocolAmount,
        bool terminal
    ) private {
        // Defensive: the callers already reject a zero seller/solver/beneficiary, and the recurring
        // pending branch only ever passes a zero primary with a zero amount. Kept because this is a
        // value-moving path and a silent credit to address(0) would be an unrecoverable burn.
        if (primaryAmount > 0 && primary == address(0)) revert ZeroAddress();

        uint256 count;
        if (primaryAmount > 0) count++;
        if (puppetAmount > 0) count++;
        if (protocolAmount > 0) count++;
        if (count == 0) return;

        address[] memory beneficiaries = new address[](count);
        uint256[] memory amounts = new uint256[](count);

        uint256 i;
        if (primaryAmount > 0) {
            beneficiaries[i] = primary;
            amounts[i] = primaryAmount;
            i++;
        }
        if (puppetAmount > 0) {
            beneficiaries[i] = _puppetTreasury;
            amounts[i] = puppetAmount;
            i++;
        }
        if (protocolAmount > 0) {
            beneficiaries[i] = _protocolTreasury;
            amounts[i] = protocolAmount;
        }

        // The vault independently re-checks that the sum of `amounts` equals the value sent, so the
        // conservation property is enforced on both sides of this call rather than trusted once.
        uint256 total = primaryAmount + puppetAmount + protocolAmount;
        if (terminal) {
            PAYOUT_VAULT.creditTerminalBatch{value: total}(beneficiaries, amounts);
        } else {
            PAYOUT_VAULT.creditBatch{value: total}(beneficiaries, amounts);
        }
    }

    /// @dev Asserts the router forwarded every wei it was paid.
    ///
    ///      The comparison is DIFFERENTIAL — against the balance that existed before the call — not
    ///      against zero. An absolute `balance == 0` check would hand anyone a permanent denial of
    ///      service: one wei force-sent via `selfdestruct` would make every future route revert, and
    ///      because this contract is non-upgradeable and holds no sweep-to-arbitrary-address
    ///      function, the protocol would have to be redeployed. The differential form keeps the
    ///      real guarantee ("nothing that arrived with this call stayed here") while making the
    ///      griefing attempt inert. `test_ForcedEthDoesNotBrickRouting` pins that.
    /// @param preExistingBalance Balance the router held before `msg.value` arrived.
    function _assertNothingRetained(uint256 preExistingBalance) private view {
        uint256 retained = address(this).balance;
        // Reports the full remaining balance rather than the delta: in the unreachable case where
        // this fires, the auditor wants to know how much ETH is sitting in a contract that is
        // supposed to be empty.
        if (retained != preExistingBalance) revert RoutingResidue(retained);
    }

    /*//////////////////////////////////////////////////////////////
                          DIRECT DEPOSIT REJECTION
    //////////////////////////////////////////////////////////////*/

    /// @dev ETH arriving without a route is always a mistake — most often an integrator that meant
    ///      to call `routeMintEvm` and sent a bare transfer instead. Accepting it would leave value
    ///      in a contract that has no owner-withdrawal path, so the sender would be worse off than
    ///      if the transfer had simply failed.
    receive() external payable {
        revert DirectDepositRejected();
    }

    /// @dev Also catches calls to selectors this contract does not implement, which usually means
    ///      an integrator pointed at the wrong ABI or the wrong address.
    fallback() external payable {
        revert DirectDepositRejected();
    }
}
