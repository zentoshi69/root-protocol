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

// src/interfaces/ITourEngine.sol

/// @title ITourEngine
/// @notice Temporary HoodPup "tours" using the ERC-4907 user role. No ownership ever transfers.
/// @dev Tours produce provenance and a `miles` counter. They produce no token, no cash and no
///      claim on protocol revenue. On-chain rules enforce wallet-level uniqueness only; this
///      contract makes no claim to prove unique humanity, and any stronger Sybil score belongs
///      off chain and must be labelled heuristic.
interface ITourEngine {
    enum TourStatus {
        NONE,
        ACTIVE,
        FINALIZED,
        CANCELLED
    }

    struct Tour {
        address ownerAtStart;
        address user;
        uint64 startedAt;
        uint64 expires;
        uint64 checkedInAt;
        uint64 season;
        uint8 status;
    }

    error ZeroAddress();
    error TourAlreadyActive(uint256 tokenId);
    error NoActiveTour(uint256 tokenId);
    error NotTokenOwnerNorApproved(address caller, uint256 tokenId);
    error UserCannotBeOwner();
    error RecipientAlreadyCreditedThisSeason(uint256 tokenId, uint64 season, address recipient);
    error DurationOutOfBounds(uint64 duration, uint64 minimum, uint64 maximum);
    error NotTourUser(address caller, address user);
    error CheckInTooEarly(uint64 nowTs, uint64 allowedAt);
    error AlreadyCheckedIn(uint256 tokenId);
    error TourNotExpired(uint256 tokenId, uint64 expires);
    error TourStillValid(uint256 tokenId);
    error NoCheckIn(uint256 tokenId);
    error OwnershipChangedDuringTour(address ownerAtStart, address currentOwner);
    error UserRoleTampered(address expected, address actual);
    error InvalidBounds();

    event TourStarted(
        uint256 indexed tokenId,
        address indexed user,
        address indexed ownerAtStart,
        uint64 startedAt,
        uint64 expires,
        uint64 season
    );
    event TourCheckIn(uint256 indexed tokenId, address indexed user, uint64 checkedInAt, uint64 season);
    event TourFinalized(
        uint256 indexed tokenId,
        address indexed user,
        uint64 season,
        uint64 durationSeconds,
        uint256 newMiles,
        uint256 completedTours
    );
    event TourCancelled(uint256 indexed tokenId, address indexed user, string reason);
    event SeasonUpdated(uint64 previous, uint64 next);
    event DurationBoundsUpdated(uint64 minimumDuration, uint64 maximumDuration, uint64 minimumCheckInDelay);

    function currentSeason() external view returns (uint64);
    function minimumDuration() external view returns (uint64);
    function maximumDuration() external view returns (uint64);
    function minimumCheckInDelay() external view returns (uint64);
    function tourOf(uint256 tokenId) external view returns (Tour memory);
    function miles(uint256 tokenId) external view returns (uint256);
    function completedTours(uint256 tokenId) external view returns (uint256);
    function recipientUsedInSeason(uint256 tokenId, uint64 season, address recipient) external view returns (bool);

    /// @notice Lend a HoodPup's user role until `expires`. Owner or approved operator only.
    function startTour(uint256 tokenId, address user, uint64 expires) external;

    /// @notice The current user confirms they hold the role. Required for the tour to count.
    function checkIn(uint256 tokenId) external;

    /// @notice After expiry, credit a valid tour: increment miles and stamp provenance.
    function finalizeTour(uint256 tokenId) external;

    /// @notice Clean up a tour that can no longer be credited, without incrementing miles.
    function cancelInvalidTour(uint256 tokenId) external;
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

// lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC721/IERC721.sol)

/**
 * @dev Required interface of an ERC-721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC-721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or
     *   {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC-721
     * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
     * understand this adds an external call which potentially creates a reentrancy vulnerability.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the address zero.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
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

    /// @notice Mint for an already-active BTC solver reservation even while ordinary minting is paused.
    /// @dev Requires `MINTER_ROLE`. The authorized escrow exposes this only after consuming the
    ///      matching Bitcoin-payment attestation, so this resolves existing risk rather than
    ///      accepting a new mint obligation.
    function mintRootedTerminal(address recipient, PuppetTypes.RootId calldata root) external returns (uint256 tokenId);

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

// src/TourEngine.sol

/// @title TourEngine
/// @notice Temporary HoodPup "tours": an owner lends the ERC-4907 user role to another wallet for a
///         bounded window, and a completed tour stamps permanent provenance plus a `miles` counter.
/// @dev WHAT A TOUR IS, AND WHAT IT IS NOT — READ THIS BEFORE READING ANY OTHER LINE:
///      A tour moves the ERC-4907 *user* role and nothing else. No ERC-721 ownership ever transfers,
///      no token is minted, no cash is paid, and finishing a tour confers no claim on protocol
///      revenue of any kind. The reward is a number that goes up and an event an indexer can render
///      as a travel stamp. This contract is not payable and has no function that can move value.
///
///      THE ORIGINAL BITCOIN PUPPET IS NOT INVOLVED AT ALL. Tours act on a HoodPup, the derived
///      Robinhood Chain asset. The inscription never leaves Bitcoin, is never wrapped, bridged,
///      escrowed or custodied, and nothing here reads or asserts any Bitcoin fact.
///
///      THIS CONTRACT DOES NOT PROVE UNIQUE HUMANITY, AND MUST NEVER BE DESCRIBED AS IF IT DID.
///      What it enforces is narrow and purely mechanical: wallet-level uniqueness (one credited
///      recipient address per token per season), a minimum lending duration, and a delayed
///      confirmation from the recipient. A determined operator with many wallets can still satisfy
///      all three. Any stronger Sybil resistance belongs off chain and must be labelled heuristic
///      wherever it is published. The on-chain rules below raise the cost of a trivial farm loop;
///      they do not make one impossible, and the miles counter should be read in that light.
///
///      THE FOUR ANTI-FARM BOUNDARIES, AND WHERE EACH LIVES:
///        1. one credited recipient per token per season   -> `_recipientUsedInSeason`, checked in
///           `startTour` and re-checked in `finalizeTour`;
///        2. a minimum lending duration                    -> `_minimumDuration` in `startTour`;
///        3. a delayed check-in the recipient must send    -> `_checkInDelayOf` in `checkIn`;
///        4. no credit for anything that looks like a sale -> `finalizeTour` refuses when the owner
///           changed mid-tour, and `startTour` refuses when the recipient IS the owner.
///      A raw ERC-721 transfer scores nothing anywhere in this file, by construction: `miles` is only
///      ever written inside `finalizeTour`.
///
///      PAUSING IS NARROW BY DESIGN. `whenNotPaused` appears on `startTour` and nowhere else.
///      Starting a new tour is the only risk-taking action here; `checkIn`, `finalizeTour` and
///      `cancelInvalidTour` all complete or clean up an obligation that already exists, and a pause
///      that could strand an in-flight tour — denying a recipient the stamp they already earned, or
///      locking a token in `ACTIVE` so its owner can never tour it again — would be the tour
///      equivalent of a pause blocking a withdrawal. That is not negotiable in this protocol.
///
///      NON-UPGRADEABLE by construction: no proxy, no initializer, no `delegatecall`, no
///      `selfdestruct`, no `tx.origin`, and no admin path that can seize a token, reduce a balance
///      (there are none), or delete miles that have already been awarded.
contract TourEngine is ITourEngine, AccessControl, Pausable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role permitted to roll the season and to change the duration bounds.
    /// @dev Held by the `TimelockController` in production. Deliberately separate from
    ///      `DEFAULT_ADMIN_ROLE`: parameter administration and role administration are different
    ///      jobs, and this role's entire authority is four `uint64`s that gate FUTURE tours. It
    ///      cannot touch a tour already in flight (see `_checkInDelayOf`), cannot award or remove a
    ///      mile, and cannot mark a recipient used or unused.
    bytes32 public constant TOUR_ADMIN_ROLE = keccak256("TOUR_ADMIN_ROLE");

    /// @notice Role permitted to pause new tours. Cannot unpause.
    /// @dev Held by the guardian multisig, mirroring the asymmetry used across this protocol:
    ///      stopping must be fast, resuming must be deliberate and publicly visible for the full
    ///      timelock delay. A compromised guardian can therefore only ever cost liveness on
    ///      `startTour`; it can never strand a tour that is already running.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              EXTRA ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when `setSeason` is handed a season that does not strictly increase.
    /// @dev Seasons only ever move forward. Rewinding would not un-set any
    ///      `recipientUsedInSeason` flag — those are keyed by the season they were written in — but
    ///      it would let governance replay a season number, which makes the off-chain provenance
    ///      record ambiguous for anyone reconstructing tour history from events. Refusing is free.
    /// @param current The season already stored.
    /// @param proposed The season that was rejected.
    error SeasonMustIncrease(uint64 current, uint64 proposed);

    /// @notice Thrown when `checkIn` arrives after the tour's expiry.
    /// @dev Distinct from `CheckInTooEarly` so a UI can tell the two failure modes apart. The tour
    ///      is still `ACTIVE` in storage at this point — it simply can no longer be checked into,
    ///      and is now cancellable through `cancelInvalidTour`.
    /// @param nowTs Current block timestamp.
    /// @param expires The expiry that has already passed.
    error CheckInAfterExpiry(uint64 nowTs, uint64 expires);

    /*//////////////////////////////////////////////////////////////
                               EXTRA EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, recording the immutable wiring of this engine.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE`, `TOUR_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param hoodPups The collection whose ERC-4907 user role this engine lends.
    /// @param feeRouter Recorded fee router, or the zero address. Tours are free; see `FEE_ROUTER`.
    /// @param firstSeason The season the first tour will be recorded in, always 1.
    event TourEngineInitialized(
        address indexed admin, address indexed hoodPups, address indexed feeRouter, uint64 firstSeason
    );

    /// @notice Emitted when the best-effort clear of a lapsed ERC-4907 record did not go through.
    /// @dev Not a failure of the tour. See `_clearLapsedUserRecord` for why the clear must never be
    ///      allowed to revert a finalization, and why the miles are already safe by the time this
    ///      can be emitted.
    /// @param tokenId Token whose stale user record was left in place.
    event StaleUserRecordNotCleared(uint256 indexed tokenId);

    /*//////////////////////////////////////////////////////////////
                            CANCELLATION REASONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted in `TourCancelled.reason`. Kept as constants so indexers can match on exact
    ///      strings rather than on prose that a later edit might reword.
    string private constant REASON_OWNERSHIP_CHANGED = "OWNERSHIP_CHANGED";
    string private constant REASON_USER_ROLE_TAMPERED = "USER_ROLE_TAMPERED";
    string private constant REASON_NO_CHECK_IN = "NO_CHECK_IN";

    /*//////////////////////////////////////////////////////////////
                             IMMUTABLE WIRING
    //////////////////////////////////////////////////////////////*/

    /// @notice The HoodPups collection this engine lends the user role of.
    /// @dev `immutable`: a repointable collection would let governance aim `TOUR_ENGINE_ROLE` at a
    ///      different contract while the miles ledger below kept accruing against token ids that no
    ///      longer mean anything.
    IHoodPups public immutable HOOD_PUPS;

    /// @dev The same address as `HOOD_PUPS`, typed as ERC-721 for `ownerOf` / approval reads.
    ///      `IHoodPups` deliberately does not redeclare the ERC-721 surface, and that interface file
    ///      is frozen, so the cast is done once here rather than at a dozen call sites.
    IERC721 private immutable _COLLECTION;

    /// @notice Fee router recorded for off-chain discovery. May be the zero address.
    /// @dev TOURS ARE FREE AND NOTHING IN THIS FILE READS THIS ADDRESS. It is `immutable` and
    ///      write-once precisely so that claim is verifiable rather than promised: there is no
    ///      setter, no `payable` function, and no code path that could route a fee through it. It
    ///      exists only so a future *separate deployment* that introduces a paid tour action can be
    ///      wired to the same router that the mint path uses, and so an indexer can see which router
    ///      this engine was deployed alongside. Charging for a tour would require a new contract;
    ///      this one is non-upgradeable.
    address public immutable FEE_ROUTER;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Season tours started from now on are recorded in. Strictly increasing; see `setSeason`.
    uint64 private _currentSeason;

    /// @dev Shortest lendable window, in seconds. Always non-zero.
    uint64 private _minimumDuration;

    /// @dev Longest lendable window, in seconds. Always `>= _minimumDuration`.
    uint64 private _maximumDuration;

    /// @dev How long after a tour starts the recipient must wait before checking in. Always
    ///      strictly less than `_minimumDuration`, so every legal tour has a window in which a
    ///      check-in is actually possible.
    uint64 private _minimumCheckInDelay;

    /// @dev Token id => the one tour slot for that token. A token has at most one tour at a time;
    ///      finalizing or cancelling frees the slot for the next one.
    mapping(uint256 tokenId => Tour tour) private _tours;

    /// @dev Token id => check-in delay SNAPSHOTTED when the tour started.
    ///      WHY THIS EXISTS: the `Tour` struct is a frozen protocol type with nowhere to put it, and
    ///      reading the live `_minimumCheckInDelay` inside `checkIn` would let `TOUR_ADMIN_ROLE`
    ///      raise the delay mid-tour and retroactively void a tour that was legal when it started.
    ///      Governance must not be able to reach into a running tour, so the rule a tour is judged
    ///      by is fixed at its start.
    mapping(uint256 tokenId => uint64 delaySeconds) private _checkInDelayOf;

    /// @dev Token id => cumulative seconds spent on finalized tours. WRITTEN IN EXACTLY ONE PLACE,
    ///      `finalizeTour`, and only ever upwards. No decrement, no reset, no admin override.
    mapping(uint256 tokenId => uint256 milesEarned) private _miles;

    /// @dev Token id => number of finalized tours. Same single-writer rule as `_miles`.
    mapping(uint256 tokenId => uint256 count) private _completedTours;

    /// @dev token id => season => recipient => already credited. The wallet-level uniqueness rule.
    ///      Written only in `finalizeTour`, and never cleared: a season that has passed can never be
    ///      re-entered, because `setSeason` only moves forward.
    mapping(uint256 tokenId => mapping(uint64 season => mapping(address recipient => bool used))) private
        _recipientUsedInSeason;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the tour engine.
    /// @dev `admin` MUST be a `TimelockController` under multisig control in production. Nothing in
    ///      this contract can enforce that, so the deployment script grants the roles to the timelock
    ///      and revokes the deployer in the same batch.
    ///
    ///      `TOUR_ENGINE_ROLE` on `HoodPups` is NOT granted here — this contract cannot grant itself
    ///      a role on another contract, and that grant is a separate, reviewable governance action
    ///      taken after this address is known.
    ///
    ///      The first season is 1 rather than 0 so that "season 0" is an unambiguous "before any
    ///      tour existed" sentinel in the event stream, matching the token-ids-start-at-1 convention
    ///      the collection uses.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE`, `TOUR_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param hoodPups The HoodPups collection.
    /// @param feeRouter Fee router recorded for discovery only. May be zero. Tours are free.
    /// @param minimumDuration_ Shortest lendable window in seconds. Must be non-zero.
    /// @param maximumDuration_ Longest lendable window in seconds. Must be `>= minimumDuration_`.
    /// @param minimumCheckInDelay_ Wait before a check-in counts. Must be `< minimumDuration_`.
    constructor(
        address admin,
        IHoodPups hoodPups,
        address feeRouter,
        uint64 minimumDuration_,
        uint64 maximumDuration_,
        uint64 minimumCheckInDelay_
    ) {
        if (admin == address(0)) revert ZeroAddress();
        if (address(hoodPups) == address(0)) revert ZeroAddress();

        HOOD_PUPS = hoodPups;
        _COLLECTION = IERC721(address(hoodPups));
        FEE_ROUTER = feeRouter;

        _setBounds(minimumDuration_, maximumDuration_, minimumCheckInDelay_);

        _currentSeason = 1;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TOUR_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        // Emitted with `previous = 0` so an indexer that only follows `SeasonUpdated` reconstructs
        // the full season history without special-casing genesis.
        emit SeasonUpdated(0, 1);
        emit TourEngineInitialized(admin, address(hoodPups), feeRouter, 1);
    }

    /*//////////////////////////////////////////////////////////////
                                  TOURS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITourEngine
    /// @dev CHECKS-EFFECTS-INTERACTIONS. Every storage write and the `TourStarted` event happen
    ///      before the single external call, `HoodPups.setUser`. That call is to a fixed, immutable,
    ///      protocol-owned contract with no callback into anything, so reentrancy is not actually
    ///      reachable here; `nonReentrant` is applied anyway as defence in depth, because a future
    ///      edit that added a second interaction would otherwise become exploitable silently.
    ///
    ///      AUTHORIZATION mirrors ERC-721 exactly: owner, the single approved address, or an
    ///      operator approved for all. It deliberately does NOT accept `TOUR_ENGINE_ROLE`-style
    ///      protocol authority — nobody but the owner's own approval chain decides that their token
    ///      goes on tour.
    ///
    ///      WHY THE RECIPIENT MAY NOT BE THE OWNER: the owner already holds every right the user
    ///      role can confer, so a self-tour would be a pure farm loop that costs one transaction and
    ///      proves nothing. `HoodPups.setUser` rejects it too; checking here makes the failure legible
    ///      and keeps the rule visible in the file that owns the anti-farm boundaries.
    /// @param tokenId Token to send on tour.
    /// @param user Recipient wallet that receives the temporary user role. Nonzero, not the owner.
    /// @param expires Unix timestamp the tour ends at. Must sit inside the duration bounds.
    function startTour(uint256 tokenId, address user, uint64 expires) external whenNotPaused nonReentrant {
        if (user == address(0)) revert ZeroAddress();

        // Reverts for a token id that was never minted, which is the existence check for free.
        address owner = _COLLECTION.ownerOf(tokenId);
        if (
            msg.sender != owner && _COLLECTION.getApproved(tokenId) != msg.sender
                && !_COLLECTION.isApprovedForAll(owner, msg.sender)
        ) {
            revert NotTokenOwnerNorApproved(msg.sender, tokenId);
        }
        if (user == owner) revert UserCannotBeOwner();

        if (_tours[tokenId].status == uint8(TourStatus.ACTIVE)) revert TourAlreadyActive(tokenId);

        uint64 nowTs = uint64(block.timestamp);
        // Saturating rather than reverting on underflow so a past `expires` reports the real rule it
        // broke (`DurationOutOfBounds`) instead of an arithmetic panic a caller cannot interpret.
        uint64 duration = expires > nowTs ? expires - nowTs : 0;
        if (duration < _minimumDuration || duration > _maximumDuration) {
            revert DurationOutOfBounds(duration, _minimumDuration, _maximumDuration);
        }

        uint64 season = _currentSeason;
        if (_recipientUsedInSeason[tokenId][season][user]) {
            revert RecipientAlreadyCreditedThisSeason(tokenId, season, user);
        }

        _tours[tokenId] = Tour({
            ownerAtStart: owner,
            user: user,
            startedAt: nowTs,
            expires: expires,
            checkedInAt: 0,
            season: season,
            status: uint8(TourStatus.ACTIVE)
        });
        _checkInDelayOf[tokenId] = _minimumCheckInDelay;

        emit TourStarted(tokenId, user, owner, nowTs, expires, season);

        HOOD_PUPS.setUser(tokenId, user, expires);
    }

    /// @inheritdoc ITourEngine
    /// @dev THE CHECK-IN IS WHAT SEPARATES A TOUR FROM A PARKED APPROVAL. Without it, an owner could
    ///      point the user role at a wallet they also control, wait, and collect — with the recipient
    ///      never having to hold a key or pay for a transaction. Requiring the recipient to send this
    ///      themselves, from the address that currently holds the user role, after a delay, is the
    ///      cheapest on-chain evidence that a second live wallet was actually involved. It is
    ///      evidence about wallets, never about people.
    ///
    ///      Both the recorded recipient AND the live ERC-4907 user must be `msg.sender`. The second
    ///      check catches the case where the owner replaced the user role mid-tour: the replacement
    ///      wallet is not the recorded recipient and cannot check in, and the recorded recipient no
    ///      longer holds the role, so neither of them can credit the tour.
    ///
    ///      Not `whenNotPaused`: a pause must never strand a tour that is already running.
    /// @param tokenId Token whose tour is being confirmed.
    function checkIn(uint256 tokenId) external nonReentrant {
        Tour storage tour = _tours[tokenId];
        if (tour.status != uint8(TourStatus.ACTIVE)) revert NoActiveTour(tokenId);

        uint64 nowTs = uint64(block.timestamp);
        if (nowTs > tour.expires) revert CheckInAfterExpiry(nowTs, tour.expires);

        if (msg.sender != tour.user) revert NotTourUser(msg.sender, tour.user);

        address liveUser = HOOD_PUPS.userOf(tokenId);
        if (liveUser != msg.sender) revert UserRoleTampered(tour.user, liveUser);

        if (tour.checkedInAt != 0) revert AlreadyCheckedIn(tokenId);

        // Snapshotted at start, so a later governance change to the bounds cannot move this line.
        uint64 allowedAt = tour.startedAt + _checkInDelayOf[tokenId];
        if (nowTs < allowedAt) revert CheckInTooEarly(nowTs, allowedAt);

        tour.checkedInAt = nowTs;

        emit TourCheckIn(tokenId, msg.sender, nowTs, tour.season);
    }

    /// @inheritdoc ITourEngine
    /// @dev PERMISSIONLESS ON PURPOSE. Finalizing awards a fixed amount to a fixed token and a fixed
    ///      recipient that were both decided at `startTour`, so the caller gains nothing by being the
    ///      caller and cannot steer the outcome. Making anyone able to close a tour means a recipient
    ///      can always claim the stamp they earned, even if the owner has lost interest — the same
    ///      reason refunds elsewhere in this protocol are not gated on a counterparty.
    ///
    ///      WHY EXPIRY IS STRICT (`block.timestamp > expires`): `HoodPups.userOf` treats an
    ///      entitlement expiring at exactly `block.timestamp` as still live, matching the ERC-4907
    ///      reference. Finalizing in that same second would credit a tour the recipient is still on.
    ///
    ///      HOW TAMPERING IS DETECTED AFTER EXPIRY: once the term has elapsed `userOf` returns zero
    ///      for every token, so it can no longer distinguish "our record, now lapsed" from "cleared".
    ///      `userExpires` returns the RAW stored expiry, which survives expiry, so comparing it to
    ///      the tour's own expiry detects both a clear (a transfer wipes it to zero; so does an
    ///      explicit clear) and a replacement with any different term.
    ///
    ///      THE ONE RESIDUAL CASE, STATED HONESTLY: an owner who replaces the user role mid-tour with
    ///      a different wallet and the byte-identical expiry is not detectable here. It is also not
    ///      profitable — the credit still goes to the originally recorded recipient, that recipient
    ///      is still consumed for the season, and the replacement wallet cannot check in — so the
    ///      owner gains nothing they could not get by simply letting the tour run.
    /// @param tokenId Token whose tour is being credited.
    function finalizeTour(uint256 tokenId) external nonReentrant {
        Tour storage tour = _tours[tokenId];
        if (tour.status != uint8(TourStatus.ACTIVE)) revert NoActiveTour(tokenId);

        if (block.timestamp <= uint256(tour.expires)) revert TourNotExpired(tokenId, tour.expires);
        if (tour.checkedInAt == 0) revert NoCheckIn(tokenId);

        address currentOwner = _COLLECTION.ownerOf(tokenId);
        if (currentOwner != tour.ownerAtStart) revert OwnershipChangedDuringTour(tour.ownerAtStart, currentOwner);

        if (uint64(HOOD_PUPS.userExpires(tokenId)) != tour.expires) {
            revert UserRoleTampered(tour.user, HOOD_PUPS.userOf(tokenId));
        }

        address recipient = tour.user;
        uint64 season = tour.season;
        // Re-checked even though `startTour` already refused a used recipient: this mapping is the
        // one rule that stops a repeat loop, and it is cheap to assert it again at the only place
        // that writes it.
        if (_recipientUsedInSeason[tokenId][season][recipient]) {
            revert RecipientAlreadyCreditedThisSeason(tokenId, season, recipient);
        }

        // The SCHEDULED window, not the time until someone happened to call this. A lazy or hostile
        // finalizer must not be able to inflate the award by waiting.
        uint64 durationSeconds = tour.expires - tour.startedAt;

        tour.status = uint8(TourStatus.FINALIZED);
        _recipientUsedInSeason[tokenId][season][recipient] = true;

        // Cannot realistically overflow: each addition is bounded by `_maximumDuration`, and a token
        // would need more finalized tours than there are seconds in the universe to reach 2^256.
        uint256 newMiles = _miles[tokenId] + durationSeconds;
        uint256 completed = _completedTours[tokenId] + 1;
        _miles[tokenId] = newMiles;
        _completedTours[tokenId] = completed;

        // The permanent travel stamp. Emitted before the tidy-up interaction so the provenance
        // record is written even if the clear below cannot go through.
        emit TourFinalized(tokenId, recipient, season, durationSeconds, newMiles, completed);

        _clearLapsedUserRecord(tokenId);
    }

    /// @inheritdoc ITourEngine
    /// @dev PERMISSIONLESS, AND SAFE TO BE: this can only close a tour that is ALREADY impossible to
    ///      credit. If none of the three invalidating conditions holds, it reverts `TourStillValid`,
    ///      so it can never be used to cancel a tour out from under a recipient who is on track.
    ///
    ///      Cancelling awards nothing: no miles, no completed-tour count, and — importantly — no
    ///      entry in `_recipientUsedInSeason`. A tour that failed through no fault of the recipient
    ///      must not burn that recipient's one slot for the season.
    ///
    ///      WHY THE USER-ROLE CLEAR IS CONDITIONAL: when the live ERC-4907 record is no longer the
    ///      one this tour wrote, it belongs to whoever wrote it next — possibly a fresh, legitimate
    ///      rental the owner set up directly. Clearing it would let any passer-by cancel a stale tour
    ///      in order to destroy an unrelated live entitlement. The engine only ever clears a record
    ///      it can prove is its own.
    ///
    ///      Not `whenNotPaused`: cleanup is the path that un-sticks a token, and a pause that blocked
    ///      it would leave the token unable to ever tour again.
    /// @param tokenId Token whose tour is being closed without credit.
    function cancelInvalidTour(uint256 tokenId) external nonReentrant {
        Tour storage tour = _tours[tokenId];
        if (tour.status != uint8(TourStatus.ACTIVE)) revert NoActiveTour(tokenId);

        bool ownershipChanged = _COLLECTION.ownerOf(tokenId) != tour.ownerAtStart;
        bool roleTampered = uint64(HOOD_PUPS.userExpires(tokenId)) != tour.expires;
        bool expiredWithoutCheckIn = block.timestamp > uint256(tour.expires) && tour.checkedInAt == 0;

        if (!ownershipChanged && !roleTampered && !expiredWithoutCheckIn) revert TourStillValid(tokenId);

        tour.status = uint8(TourStatus.CANCELLED);

        // Ordered most-specific-cause first, so the emitted reason names the root cause rather than
        // a symptom: an ERC-721 transfer also wipes the user record, which would otherwise surface
        // as `USER_ROLE_TAMPERED` and mislead anyone reading the history.
        string memory reason = ownershipChanged
            ? REASON_OWNERSHIP_CHANGED
            : (roleTampered ? REASON_USER_ROLE_TAMPERED : REASON_NO_CHECK_IN);
        emit TourCancelled(tokenId, tour.user, reason);

        if (!roleTampered) _clearLapsedUserRecord(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Roll the season forward, which re-opens every recipient for every token.
    /// @dev Tours already in flight are unaffected: each one carries the season it started in and is
    ///      credited against that season, so a roll cannot retroactively move where a running tour
    ///      lands, nor make an already-credited recipient look uncredited.
    ///
    ///      Strictly increasing; see `SeasonMustIncrease`. Timelocked in production, which is what
    ///      makes a season roll a publicly visible scheduled event rather than a silent write that
    ///      resets the anti-farm boundary.
    /// @param newSeason The new season number. Must be greater than the current one.
    function setSeason(uint64 newSeason) external onlyRole(TOUR_ADMIN_ROLE) {
        uint64 previous = _currentSeason;
        if (newSeason <= previous) revert SeasonMustIncrease(previous, newSeason);

        _currentSeason = newSeason;
        emit SeasonUpdated(previous, newSeason);
    }

    /// @notice Replace the duration bounds and the check-in delay.
    /// @dev Applies to tours started AFTER this call only. Running tours keep the check-in delay
    ///      snapshotted at their start, and their duration was already validated when they began, so
    ///      this role can never invalidate a tour that is in flight. That is the whole reason
    ///      `_checkInDelayOf` exists.
    /// @param minimumDuration_ Shortest lendable window in seconds. Must be non-zero.
    /// @param maximumDuration_ Longest lendable window in seconds. Must be `>= minimumDuration_`.
    /// @param minimumCheckInDelay_ Wait before a check-in counts. Must be `< minimumDuration_`.
    function setDurationBounds(uint64 minimumDuration_, uint64 maximumDuration_, uint64 minimumCheckInDelay_)
        external
        onlyRole(TOUR_ADMIN_ROLE)
    {
        _setBounds(minimumDuration_, maximumDuration_, minimumCheckInDelay_);
    }

    /// @notice Stop new tours from starting. Affects nothing else.
    /// @dev Check-in, finalization and cancellation all keep working while paused, by design.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Allow new tours again.
    /// @dev Restricted to `DEFAULT_ADMIN_ROLE` (the timelock) rather than `PAUSER_ROLE`, so a
    ///      compromised fast-reaction key can stop new tours but cannot restart them.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITourEngine
    function currentSeason() external view returns (uint64) {
        return _currentSeason;
    }

    /// @inheritdoc ITourEngine
    function minimumDuration() external view returns (uint64) {
        return _minimumDuration;
    }

    /// @inheritdoc ITourEngine
    function maximumDuration() external view returns (uint64) {
        return _maximumDuration;
    }

    /// @inheritdoc ITourEngine
    function minimumCheckInDelay() external view returns (uint64) {
        return _minimumCheckInDelay;
    }

    /// @inheritdoc ITourEngine
    /// @dev Returns a zeroed struct (`status == NONE`) for a token that has never toured, rather
    ///      than reverting: "has this token ever toured" is a question callers legitimately ask about
    ///      tokens that have not, and `NONE` is an unambiguous answer.
    /// @param tokenId Token to look up.
    /// @return The tour slot, which is the last tour recorded for this token.
    function tourOf(uint256 tokenId) external view returns (Tour memory) {
        return _tours[tokenId];
    }

    /// @inheritdoc ITourEngine
    /// @dev Cumulative seconds this token has spent on finalized tours. Monotonically increasing.
    /// @param tokenId Token to look up.
    /// @return Miles earned so far.
    function miles(uint256 tokenId) external view returns (uint256) {
        return _miles[tokenId];
    }

    /// @inheritdoc ITourEngine
    /// @param tokenId Token to look up.
    /// @return Number of tours this token has finalized.
    function completedTours(uint256 tokenId) external view returns (uint256) {
        return _completedTours[tokenId];
    }

    /// @inheritdoc ITourEngine
    /// @dev True only after a FINALIZED tour. A cancelled tour never consumes a recipient's slot.
    /// @param tokenId Token to look up.
    /// @param season Season to look up.
    /// @param recipient Wallet to look up.
    /// @return True if that wallet has already been credited for that token in that season.
    function recipientUsedInSeason(uint256 tokenId, uint64 season, address recipient) external view returns (bool) {
        return _recipientUsedInSeason[tokenId][season][recipient];
    }

    /// @notice Earliest timestamp at which the current tour for `tokenId` can be checked into.
    /// @dev Uses the delay snapshotted when that tour started, so a UI shows the rule the tour will
    ///      actually be judged by. Returns zero when the token has never toured.
    /// @param tokenId Token to look up.
    /// @return The unlock timestamp for the recorded tour's check-in.
    function checkInUnlocksAt(uint256 tokenId) external view returns (uint64) {
        Tour memory tour = _tours[tokenId];
        if (tour.status == uint8(TourStatus.NONE)) return 0;
        return tour.startedAt + _checkInDelayOf[tokenId];
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Validates and stores the three timing parameters. Shared by the constructor and
    ///      `setDurationBounds` so a deployment can never be configured in a shape governance would
    ///      be refused later.
    ///
    ///      `minimumCheckInDelay_ < minimumDuration_` is STRICT. Were equality allowed, the shortest
    ///      legal tour would have exactly one block in which a check-in was possible, which turns a
    ///      full second of network latency into a lost tour.
    function _setBounds(uint64 minimumDuration_, uint64 maximumDuration_, uint64 minimumCheckInDelay_) private {
        if (minimumDuration_ == 0 || maximumDuration_ < minimumDuration_ || minimumCheckInDelay_ >= minimumDuration_) {
            revert InvalidBounds();
        }

        _minimumDuration = minimumDuration_;
        _maximumDuration = maximumDuration_;
        _minimumCheckInDelay = minimumCheckInDelay_;

        emit DurationBoundsUpdated(minimumDuration_, maximumDuration_, minimumCheckInDelay_);
    }

    /// @dev Clears an ERC-4907 record this engine wrote and has just finished with.
    ///      BEST EFFORT, NEVER FATAL. The call needs `TOUR_ENGINE_ROLE` on `HoodPups`, which is
    ///      governance-granted and therefore governance-revocable. If it were allowed to revert, a
    ///      revoked role would permanently block every finalization — recipients would lose stamps
    ///      they had already earned — and every cancellation, leaving tokens stuck `ACTIVE` and
    ///      untourable forever. Since the record being cleared has already lapsed (`userOf` returns
    ///      zero for it) the clear is cosmetic tidy-up, so trading a revert for an event is the right
    ///      call. It runs last, after every state change and every event, so nothing it could do —
    ///      including reverting — can affect what was already recorded.
    /// @param tokenId Token whose lapsed user record should be cleared.
    function _clearLapsedUserRecord(uint256 tokenId) private {
        try HOOD_PUPS.setUser(tokenId, address(0), 0) {}
        catch {
            emit StaleUserRecordNotCleared(tokenId);
        }
    }
}
