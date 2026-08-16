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

// lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC721/IERC721Receiver.sol)

/**
 * @title ERC-721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC-721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be
     * reverted.
     *
     * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

// lib/openzeppelin-contracts/contracts/utils/Panic.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/Panic.sol)

/**
 * @dev Helper library for emitting standardized panic codes.
 *
 * ```solidity
 * contract Example {
 *      using Panic for uint256;
 *
 *      // Use any of the declared internal constants
 *      function foo() { Panic.GENERIC.panic(); }
 *
 *      // Alternatively
 *      function foo() { Panic.panic(Panic.GENERIC); }
 * }
 * ```
 *
 * Follows the list from https://github.com/ethereum/solidity/blob/v0.8.24/libsolutil/ErrorCodes.h[libsolutil].
 *
 * _Available since v5.1._
 */
// slither-disable-next-line unused-state
library Panic {
    /// @dev generic / unspecified error
    uint256 internal constant GENERIC = 0x00;
    /// @dev used by the assert() builtin
    uint256 internal constant ASSERT = 0x01;
    /// @dev arithmetic underflow or overflow
    uint256 internal constant UNDER_OVERFLOW = 0x11;
    /// @dev division or modulo by zero
    uint256 internal constant DIVISION_BY_ZERO = 0x12;
    /// @dev enum conversion error
    uint256 internal constant ENUM_CONVERSION_ERROR = 0x21;
    /// @dev invalid encoding in storage
    uint256 internal constant STORAGE_ENCODING_ERROR = 0x22;
    /// @dev empty array pop
    uint256 internal constant EMPTY_ARRAY_POP = 0x31;
    /// @dev array out of bounds access
    uint256 internal constant ARRAY_OUT_OF_BOUNDS = 0x32;
    /// @dev resource error (too large allocation or too large array)
    uint256 internal constant RESOURCE_ERROR = 0x41;
    /// @dev calling invalid internal function
    uint256 internal constant INVALID_INTERNAL_FUNCTION = 0x51;

    /// @dev Reverts with a panic code. Recommended to use with
    /// the internal constants with predefined codes.
    function panic(uint256 code) internal pure {
        assembly ("memory-safe") {
            mstore(0x00, 0x4e487b71)
            mstore(0x20, code)
            revert(0x1c, 0x24)
        }
    }
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

// lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/math/SafeCast.sol)
// This file was procedurally generated from scripts/generate/templates/SafeCast.js.

/**
 * @dev Wrappers over Solidity's uintXX/intXX/bool casting operators with added overflow
 * checks.
 *
 * Downcasting from uint256/int256 in Solidity does not revert on overflow. This can
 * easily result in undesired exploitation or bugs, since developers usually
 * assume that overflows raise errors. `SafeCast` restores this intuition by
 * reverting the transaction when such an operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeCast {
    /**
     * @dev Value doesn't fit in an uint of `bits` size.
     */
    error SafeCastOverflowedUintDowncast(uint8 bits, uint256 value);

    /**
     * @dev An int value doesn't fit in an uint of `bits` size.
     */
    error SafeCastOverflowedIntToUint(int256 value);

    /**
     * @dev Value doesn't fit in an int of `bits` size.
     */
    error SafeCastOverflowedIntDowncast(uint8 bits, int256 value);

    /**
     * @dev An uint value doesn't fit in an int of `bits` size.
     */
    error SafeCastOverflowedUintToInt(uint256 value);

    /**
     * @dev Returns the downcasted uint248 from uint256, reverting on
     * overflow (when the input is greater than largest uint248).
     *
     * Counterpart to Solidity's `uint248` operator.
     *
     * Requirements:
     *
     * - input must fit into 248 bits
     */
    function toUint248(uint256 value) internal pure returns (uint248) {
        if (value > type(uint248).max) {
            revert SafeCastOverflowedUintDowncast(248, value);
        }
        return uint248(value);
    }

    /**
     * @dev Returns the downcasted uint240 from uint256, reverting on
     * overflow (when the input is greater than largest uint240).
     *
     * Counterpart to Solidity's `uint240` operator.
     *
     * Requirements:
     *
     * - input must fit into 240 bits
     */
    function toUint240(uint256 value) internal pure returns (uint240) {
        if (value > type(uint240).max) {
            revert SafeCastOverflowedUintDowncast(240, value);
        }
        return uint240(value);
    }

    /**
     * @dev Returns the downcasted uint232 from uint256, reverting on
     * overflow (when the input is greater than largest uint232).
     *
     * Counterpart to Solidity's `uint232` operator.
     *
     * Requirements:
     *
     * - input must fit into 232 bits
     */
    function toUint232(uint256 value) internal pure returns (uint232) {
        if (value > type(uint232).max) {
            revert SafeCastOverflowedUintDowncast(232, value);
        }
        return uint232(value);
    }

    /**
     * @dev Returns the downcasted uint224 from uint256, reverting on
     * overflow (when the input is greater than largest uint224).
     *
     * Counterpart to Solidity's `uint224` operator.
     *
     * Requirements:
     *
     * - input must fit into 224 bits
     */
    function toUint224(uint256 value) internal pure returns (uint224) {
        if (value > type(uint224).max) {
            revert SafeCastOverflowedUintDowncast(224, value);
        }
        return uint224(value);
    }

    /**
     * @dev Returns the downcasted uint216 from uint256, reverting on
     * overflow (when the input is greater than largest uint216).
     *
     * Counterpart to Solidity's `uint216` operator.
     *
     * Requirements:
     *
     * - input must fit into 216 bits
     */
    function toUint216(uint256 value) internal pure returns (uint216) {
        if (value > type(uint216).max) {
            revert SafeCastOverflowedUintDowncast(216, value);
        }
        return uint216(value);
    }

    /**
     * @dev Returns the downcasted uint208 from uint256, reverting on
     * overflow (when the input is greater than largest uint208).
     *
     * Counterpart to Solidity's `uint208` operator.
     *
     * Requirements:
     *
     * - input must fit into 208 bits
     */
    function toUint208(uint256 value) internal pure returns (uint208) {
        if (value > type(uint208).max) {
            revert SafeCastOverflowedUintDowncast(208, value);
        }
        return uint208(value);
    }

    /**
     * @dev Returns the downcasted uint200 from uint256, reverting on
     * overflow (when the input is greater than largest uint200).
     *
     * Counterpart to Solidity's `uint200` operator.
     *
     * Requirements:
     *
     * - input must fit into 200 bits
     */
    function toUint200(uint256 value) internal pure returns (uint200) {
        if (value > type(uint200).max) {
            revert SafeCastOverflowedUintDowncast(200, value);
        }
        return uint200(value);
    }

    /**
     * @dev Returns the downcasted uint192 from uint256, reverting on
     * overflow (when the input is greater than largest uint192).
     *
     * Counterpart to Solidity's `uint192` operator.
     *
     * Requirements:
     *
     * - input must fit into 192 bits
     */
    function toUint192(uint256 value) internal pure returns (uint192) {
        if (value > type(uint192).max) {
            revert SafeCastOverflowedUintDowncast(192, value);
        }
        return uint192(value);
    }

    /**
     * @dev Returns the downcasted uint184 from uint256, reverting on
     * overflow (when the input is greater than largest uint184).
     *
     * Counterpart to Solidity's `uint184` operator.
     *
     * Requirements:
     *
     * - input must fit into 184 bits
     */
    function toUint184(uint256 value) internal pure returns (uint184) {
        if (value > type(uint184).max) {
            revert SafeCastOverflowedUintDowncast(184, value);
        }
        return uint184(value);
    }

    /**
     * @dev Returns the downcasted uint176 from uint256, reverting on
     * overflow (when the input is greater than largest uint176).
     *
     * Counterpart to Solidity's `uint176` operator.
     *
     * Requirements:
     *
     * - input must fit into 176 bits
     */
    function toUint176(uint256 value) internal pure returns (uint176) {
        if (value > type(uint176).max) {
            revert SafeCastOverflowedUintDowncast(176, value);
        }
        return uint176(value);
    }

    /**
     * @dev Returns the downcasted uint168 from uint256, reverting on
     * overflow (when the input is greater than largest uint168).
     *
     * Counterpart to Solidity's `uint168` operator.
     *
     * Requirements:
     *
     * - input must fit into 168 bits
     */
    function toUint168(uint256 value) internal pure returns (uint168) {
        if (value > type(uint168).max) {
            revert SafeCastOverflowedUintDowncast(168, value);
        }
        return uint168(value);
    }

    /**
     * @dev Returns the downcasted uint160 from uint256, reverting on
     * overflow (when the input is greater than largest uint160).
     *
     * Counterpart to Solidity's `uint160` operator.
     *
     * Requirements:
     *
     * - input must fit into 160 bits
     */
    function toUint160(uint256 value) internal pure returns (uint160) {
        if (value > type(uint160).max) {
            revert SafeCastOverflowedUintDowncast(160, value);
        }
        return uint160(value);
    }

    /**
     * @dev Returns the downcasted uint152 from uint256, reverting on
     * overflow (when the input is greater than largest uint152).
     *
     * Counterpart to Solidity's `uint152` operator.
     *
     * Requirements:
     *
     * - input must fit into 152 bits
     */
    function toUint152(uint256 value) internal pure returns (uint152) {
        if (value > type(uint152).max) {
            revert SafeCastOverflowedUintDowncast(152, value);
        }
        return uint152(value);
    }

    /**
     * @dev Returns the downcasted uint144 from uint256, reverting on
     * overflow (when the input is greater than largest uint144).
     *
     * Counterpart to Solidity's `uint144` operator.
     *
     * Requirements:
     *
     * - input must fit into 144 bits
     */
    function toUint144(uint256 value) internal pure returns (uint144) {
        if (value > type(uint144).max) {
            revert SafeCastOverflowedUintDowncast(144, value);
        }
        return uint144(value);
    }

    /**
     * @dev Returns the downcasted uint136 from uint256, reverting on
     * overflow (when the input is greater than largest uint136).
     *
     * Counterpart to Solidity's `uint136` operator.
     *
     * Requirements:
     *
     * - input must fit into 136 bits
     */
    function toUint136(uint256 value) internal pure returns (uint136) {
        if (value > type(uint136).max) {
            revert SafeCastOverflowedUintDowncast(136, value);
        }
        return uint136(value);
    }

    /**
     * @dev Returns the downcasted uint128 from uint256, reverting on
     * overflow (when the input is greater than largest uint128).
     *
     * Counterpart to Solidity's `uint128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     */
    function toUint128(uint256 value) internal pure returns (uint128) {
        if (value > type(uint128).max) {
            revert SafeCastOverflowedUintDowncast(128, value);
        }
        return uint128(value);
    }

    /**
     * @dev Returns the downcasted uint120 from uint256, reverting on
     * overflow (when the input is greater than largest uint120).
     *
     * Counterpart to Solidity's `uint120` operator.
     *
     * Requirements:
     *
     * - input must fit into 120 bits
     */
    function toUint120(uint256 value) internal pure returns (uint120) {
        if (value > type(uint120).max) {
            revert SafeCastOverflowedUintDowncast(120, value);
        }
        return uint120(value);
    }

    /**
     * @dev Returns the downcasted uint112 from uint256, reverting on
     * overflow (when the input is greater than largest uint112).
     *
     * Counterpart to Solidity's `uint112` operator.
     *
     * Requirements:
     *
     * - input must fit into 112 bits
     */
    function toUint112(uint256 value) internal pure returns (uint112) {
        if (value > type(uint112).max) {
            revert SafeCastOverflowedUintDowncast(112, value);
        }
        return uint112(value);
    }

    /**
     * @dev Returns the downcasted uint104 from uint256, reverting on
     * overflow (when the input is greater than largest uint104).
     *
     * Counterpart to Solidity's `uint104` operator.
     *
     * Requirements:
     *
     * - input must fit into 104 bits
     */
    function toUint104(uint256 value) internal pure returns (uint104) {
        if (value > type(uint104).max) {
            revert SafeCastOverflowedUintDowncast(104, value);
        }
        return uint104(value);
    }

    /**
     * @dev Returns the downcasted uint96 from uint256, reverting on
     * overflow (when the input is greater than largest uint96).
     *
     * Counterpart to Solidity's `uint96` operator.
     *
     * Requirements:
     *
     * - input must fit into 96 bits
     */
    function toUint96(uint256 value) internal pure returns (uint96) {
        if (value > type(uint96).max) {
            revert SafeCastOverflowedUintDowncast(96, value);
        }
        return uint96(value);
    }

    /**
     * @dev Returns the downcasted uint88 from uint256, reverting on
     * overflow (when the input is greater than largest uint88).
     *
     * Counterpart to Solidity's `uint88` operator.
     *
     * Requirements:
     *
     * - input must fit into 88 bits
     */
    function toUint88(uint256 value) internal pure returns (uint88) {
        if (value > type(uint88).max) {
            revert SafeCastOverflowedUintDowncast(88, value);
        }
        return uint88(value);
    }

    /**
     * @dev Returns the downcasted uint80 from uint256, reverting on
     * overflow (when the input is greater than largest uint80).
     *
     * Counterpart to Solidity's `uint80` operator.
     *
     * Requirements:
     *
     * - input must fit into 80 bits
     */
    function toUint80(uint256 value) internal pure returns (uint80) {
        if (value > type(uint80).max) {
            revert SafeCastOverflowedUintDowncast(80, value);
        }
        return uint80(value);
    }

    /**
     * @dev Returns the downcasted uint72 from uint256, reverting on
     * overflow (when the input is greater than largest uint72).
     *
     * Counterpart to Solidity's `uint72` operator.
     *
     * Requirements:
     *
     * - input must fit into 72 bits
     */
    function toUint72(uint256 value) internal pure returns (uint72) {
        if (value > type(uint72).max) {
            revert SafeCastOverflowedUintDowncast(72, value);
        }
        return uint72(value);
    }

    /**
     * @dev Returns the downcasted uint64 from uint256, reverting on
     * overflow (when the input is greater than largest uint64).
     *
     * Counterpart to Solidity's `uint64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     */
    function toUint64(uint256 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert SafeCastOverflowedUintDowncast(64, value);
        }
        return uint64(value);
    }

    /**
     * @dev Returns the downcasted uint56 from uint256, reverting on
     * overflow (when the input is greater than largest uint56).
     *
     * Counterpart to Solidity's `uint56` operator.
     *
     * Requirements:
     *
     * - input must fit into 56 bits
     */
    function toUint56(uint256 value) internal pure returns (uint56) {
        if (value > type(uint56).max) {
            revert SafeCastOverflowedUintDowncast(56, value);
        }
        return uint56(value);
    }

    /**
     * @dev Returns the downcasted uint48 from uint256, reverting on
     * overflow (when the input is greater than largest uint48).
     *
     * Counterpart to Solidity's `uint48` operator.
     *
     * Requirements:
     *
     * - input must fit into 48 bits
     */
    function toUint48(uint256 value) internal pure returns (uint48) {
        if (value > type(uint48).max) {
            revert SafeCastOverflowedUintDowncast(48, value);
        }
        return uint48(value);
    }

    /**
     * @dev Returns the downcasted uint40 from uint256, reverting on
     * overflow (when the input is greater than largest uint40).
     *
     * Counterpart to Solidity's `uint40` operator.
     *
     * Requirements:
     *
     * - input must fit into 40 bits
     */
    function toUint40(uint256 value) internal pure returns (uint40) {
        if (value > type(uint40).max) {
            revert SafeCastOverflowedUintDowncast(40, value);
        }
        return uint40(value);
    }

    /**
     * @dev Returns the downcasted uint32 from uint256, reverting on
     * overflow (when the input is greater than largest uint32).
     *
     * Counterpart to Solidity's `uint32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     */
    function toUint32(uint256 value) internal pure returns (uint32) {
        if (value > type(uint32).max) {
            revert SafeCastOverflowedUintDowncast(32, value);
        }
        return uint32(value);
    }

    /**
     * @dev Returns the downcasted uint24 from uint256, reverting on
     * overflow (when the input is greater than largest uint24).
     *
     * Counterpart to Solidity's `uint24` operator.
     *
     * Requirements:
     *
     * - input must fit into 24 bits
     */
    function toUint24(uint256 value) internal pure returns (uint24) {
        if (value > type(uint24).max) {
            revert SafeCastOverflowedUintDowncast(24, value);
        }
        return uint24(value);
    }

    /**
     * @dev Returns the downcasted uint16 from uint256, reverting on
     * overflow (when the input is greater than largest uint16).
     *
     * Counterpart to Solidity's `uint16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     */
    function toUint16(uint256 value) internal pure returns (uint16) {
        if (value > type(uint16).max) {
            revert SafeCastOverflowedUintDowncast(16, value);
        }
        return uint16(value);
    }

    /**
     * @dev Returns the downcasted uint8 from uint256, reverting on
     * overflow (when the input is greater than largest uint8).
     *
     * Counterpart to Solidity's `uint8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits
     */
    function toUint8(uint256 value) internal pure returns (uint8) {
        if (value > type(uint8).max) {
            revert SafeCastOverflowedUintDowncast(8, value);
        }
        return uint8(value);
    }

    /**
     * @dev Converts a signed int256 into an unsigned uint256.
     *
     * Requirements:
     *
     * - input must be greater than or equal to 0.
     */
    function toUint256(int256 value) internal pure returns (uint256) {
        if (value < 0) {
            revert SafeCastOverflowedIntToUint(value);
        }
        return uint256(value);
    }

    /**
     * @dev Returns the downcasted int248 from int256, reverting on
     * overflow (when the input is less than smallest int248 or
     * greater than largest int248).
     *
     * Counterpart to Solidity's `int248` operator.
     *
     * Requirements:
     *
     * - input must fit into 248 bits
     */
    function toInt248(int256 value) internal pure returns (int248 downcasted) {
        downcasted = int248(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(248, value);
        }
    }

    /**
     * @dev Returns the downcasted int240 from int256, reverting on
     * overflow (when the input is less than smallest int240 or
     * greater than largest int240).
     *
     * Counterpart to Solidity's `int240` operator.
     *
     * Requirements:
     *
     * - input must fit into 240 bits
     */
    function toInt240(int256 value) internal pure returns (int240 downcasted) {
        downcasted = int240(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(240, value);
        }
    }

    /**
     * @dev Returns the downcasted int232 from int256, reverting on
     * overflow (when the input is less than smallest int232 or
     * greater than largest int232).
     *
     * Counterpart to Solidity's `int232` operator.
     *
     * Requirements:
     *
     * - input must fit into 232 bits
     */
    function toInt232(int256 value) internal pure returns (int232 downcasted) {
        downcasted = int232(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(232, value);
        }
    }

    /**
     * @dev Returns the downcasted int224 from int256, reverting on
     * overflow (when the input is less than smallest int224 or
     * greater than largest int224).
     *
     * Counterpart to Solidity's `int224` operator.
     *
     * Requirements:
     *
     * - input must fit into 224 bits
     */
    function toInt224(int256 value) internal pure returns (int224 downcasted) {
        downcasted = int224(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(224, value);
        }
    }

    /**
     * @dev Returns the downcasted int216 from int256, reverting on
     * overflow (when the input is less than smallest int216 or
     * greater than largest int216).
     *
     * Counterpart to Solidity's `int216` operator.
     *
     * Requirements:
     *
     * - input must fit into 216 bits
     */
    function toInt216(int256 value) internal pure returns (int216 downcasted) {
        downcasted = int216(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(216, value);
        }
    }

    /**
     * @dev Returns the downcasted int208 from int256, reverting on
     * overflow (when the input is less than smallest int208 or
     * greater than largest int208).
     *
     * Counterpart to Solidity's `int208` operator.
     *
     * Requirements:
     *
     * - input must fit into 208 bits
     */
    function toInt208(int256 value) internal pure returns (int208 downcasted) {
        downcasted = int208(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(208, value);
        }
    }

    /**
     * @dev Returns the downcasted int200 from int256, reverting on
     * overflow (when the input is less than smallest int200 or
     * greater than largest int200).
     *
     * Counterpart to Solidity's `int200` operator.
     *
     * Requirements:
     *
     * - input must fit into 200 bits
     */
    function toInt200(int256 value) internal pure returns (int200 downcasted) {
        downcasted = int200(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(200, value);
        }
    }

    /**
     * @dev Returns the downcasted int192 from int256, reverting on
     * overflow (when the input is less than smallest int192 or
     * greater than largest int192).
     *
     * Counterpart to Solidity's `int192` operator.
     *
     * Requirements:
     *
     * - input must fit into 192 bits
     */
    function toInt192(int256 value) internal pure returns (int192 downcasted) {
        downcasted = int192(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(192, value);
        }
    }

    /**
     * @dev Returns the downcasted int184 from int256, reverting on
     * overflow (when the input is less than smallest int184 or
     * greater than largest int184).
     *
     * Counterpart to Solidity's `int184` operator.
     *
     * Requirements:
     *
     * - input must fit into 184 bits
     */
    function toInt184(int256 value) internal pure returns (int184 downcasted) {
        downcasted = int184(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(184, value);
        }
    }

    /**
     * @dev Returns the downcasted int176 from int256, reverting on
     * overflow (when the input is less than smallest int176 or
     * greater than largest int176).
     *
     * Counterpart to Solidity's `int176` operator.
     *
     * Requirements:
     *
     * - input must fit into 176 bits
     */
    function toInt176(int256 value) internal pure returns (int176 downcasted) {
        downcasted = int176(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(176, value);
        }
    }

    /**
     * @dev Returns the downcasted int168 from int256, reverting on
     * overflow (when the input is less than smallest int168 or
     * greater than largest int168).
     *
     * Counterpart to Solidity's `int168` operator.
     *
     * Requirements:
     *
     * - input must fit into 168 bits
     */
    function toInt168(int256 value) internal pure returns (int168 downcasted) {
        downcasted = int168(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(168, value);
        }
    }

    /**
     * @dev Returns the downcasted int160 from int256, reverting on
     * overflow (when the input is less than smallest int160 or
     * greater than largest int160).
     *
     * Counterpart to Solidity's `int160` operator.
     *
     * Requirements:
     *
     * - input must fit into 160 bits
     */
    function toInt160(int256 value) internal pure returns (int160 downcasted) {
        downcasted = int160(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(160, value);
        }
    }

    /**
     * @dev Returns the downcasted int152 from int256, reverting on
     * overflow (when the input is less than smallest int152 or
     * greater than largest int152).
     *
     * Counterpart to Solidity's `int152` operator.
     *
     * Requirements:
     *
     * - input must fit into 152 bits
     */
    function toInt152(int256 value) internal pure returns (int152 downcasted) {
        downcasted = int152(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(152, value);
        }
    }

    /**
     * @dev Returns the downcasted int144 from int256, reverting on
     * overflow (when the input is less than smallest int144 or
     * greater than largest int144).
     *
     * Counterpart to Solidity's `int144` operator.
     *
     * Requirements:
     *
     * - input must fit into 144 bits
     */
    function toInt144(int256 value) internal pure returns (int144 downcasted) {
        downcasted = int144(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(144, value);
        }
    }

    /**
     * @dev Returns the downcasted int136 from int256, reverting on
     * overflow (when the input is less than smallest int136 or
     * greater than largest int136).
     *
     * Counterpart to Solidity's `int136` operator.
     *
     * Requirements:
     *
     * - input must fit into 136 bits
     */
    function toInt136(int256 value) internal pure returns (int136 downcasted) {
        downcasted = int136(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(136, value);
        }
    }

    /**
     * @dev Returns the downcasted int128 from int256, reverting on
     * overflow (when the input is less than smallest int128 or
     * greater than largest int128).
     *
     * Counterpart to Solidity's `int128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     */
    function toInt128(int256 value) internal pure returns (int128 downcasted) {
        downcasted = int128(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(128, value);
        }
    }

    /**
     * @dev Returns the downcasted int120 from int256, reverting on
     * overflow (when the input is less than smallest int120 or
     * greater than largest int120).
     *
     * Counterpart to Solidity's `int120` operator.
     *
     * Requirements:
     *
     * - input must fit into 120 bits
     */
    function toInt120(int256 value) internal pure returns (int120 downcasted) {
        downcasted = int120(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(120, value);
        }
    }

    /**
     * @dev Returns the downcasted int112 from int256, reverting on
     * overflow (when the input is less than smallest int112 or
     * greater than largest int112).
     *
     * Counterpart to Solidity's `int112` operator.
     *
     * Requirements:
     *
     * - input must fit into 112 bits
     */
    function toInt112(int256 value) internal pure returns (int112 downcasted) {
        downcasted = int112(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(112, value);
        }
    }

    /**
     * @dev Returns the downcasted int104 from int256, reverting on
     * overflow (when the input is less than smallest int104 or
     * greater than largest int104).
     *
     * Counterpart to Solidity's `int104` operator.
     *
     * Requirements:
     *
     * - input must fit into 104 bits
     */
    function toInt104(int256 value) internal pure returns (int104 downcasted) {
        downcasted = int104(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(104, value);
        }
    }

    /**
     * @dev Returns the downcasted int96 from int256, reverting on
     * overflow (when the input is less than smallest int96 or
     * greater than largest int96).
     *
     * Counterpart to Solidity's `int96` operator.
     *
     * Requirements:
     *
     * - input must fit into 96 bits
     */
    function toInt96(int256 value) internal pure returns (int96 downcasted) {
        downcasted = int96(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(96, value);
        }
    }

    /**
     * @dev Returns the downcasted int88 from int256, reverting on
     * overflow (when the input is less than smallest int88 or
     * greater than largest int88).
     *
     * Counterpart to Solidity's `int88` operator.
     *
     * Requirements:
     *
     * - input must fit into 88 bits
     */
    function toInt88(int256 value) internal pure returns (int88 downcasted) {
        downcasted = int88(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(88, value);
        }
    }

    /**
     * @dev Returns the downcasted int80 from int256, reverting on
     * overflow (when the input is less than smallest int80 or
     * greater than largest int80).
     *
     * Counterpart to Solidity's `int80` operator.
     *
     * Requirements:
     *
     * - input must fit into 80 bits
     */
    function toInt80(int256 value) internal pure returns (int80 downcasted) {
        downcasted = int80(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(80, value);
        }
    }

    /**
     * @dev Returns the downcasted int72 from int256, reverting on
     * overflow (when the input is less than smallest int72 or
     * greater than largest int72).
     *
     * Counterpart to Solidity's `int72` operator.
     *
     * Requirements:
     *
     * - input must fit into 72 bits
     */
    function toInt72(int256 value) internal pure returns (int72 downcasted) {
        downcasted = int72(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(72, value);
        }
    }

    /**
     * @dev Returns the downcasted int64 from int256, reverting on
     * overflow (when the input is less than smallest int64 or
     * greater than largest int64).
     *
     * Counterpart to Solidity's `int64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     */
    function toInt64(int256 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(64, value);
        }
    }

    /**
     * @dev Returns the downcasted int56 from int256, reverting on
     * overflow (when the input is less than smallest int56 or
     * greater than largest int56).
     *
     * Counterpart to Solidity's `int56` operator.
     *
     * Requirements:
     *
     * - input must fit into 56 bits
     */
    function toInt56(int256 value) internal pure returns (int56 downcasted) {
        downcasted = int56(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(56, value);
        }
    }

    /**
     * @dev Returns the downcasted int48 from int256, reverting on
     * overflow (when the input is less than smallest int48 or
     * greater than largest int48).
     *
     * Counterpart to Solidity's `int48` operator.
     *
     * Requirements:
     *
     * - input must fit into 48 bits
     */
    function toInt48(int256 value) internal pure returns (int48 downcasted) {
        downcasted = int48(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(48, value);
        }
    }

    /**
     * @dev Returns the downcasted int40 from int256, reverting on
     * overflow (when the input is less than smallest int40 or
     * greater than largest int40).
     *
     * Counterpart to Solidity's `int40` operator.
     *
     * Requirements:
     *
     * - input must fit into 40 bits
     */
    function toInt40(int256 value) internal pure returns (int40 downcasted) {
        downcasted = int40(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(40, value);
        }
    }

    /**
     * @dev Returns the downcasted int32 from int256, reverting on
     * overflow (when the input is less than smallest int32 or
     * greater than largest int32).
     *
     * Counterpart to Solidity's `int32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     */
    function toInt32(int256 value) internal pure returns (int32 downcasted) {
        downcasted = int32(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(32, value);
        }
    }

    /**
     * @dev Returns the downcasted int24 from int256, reverting on
     * overflow (when the input is less than smallest int24 or
     * greater than largest int24).
     *
     * Counterpart to Solidity's `int24` operator.
     *
     * Requirements:
     *
     * - input must fit into 24 bits
     */
    function toInt24(int256 value) internal pure returns (int24 downcasted) {
        downcasted = int24(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(24, value);
        }
    }

    /**
     * @dev Returns the downcasted int16 from int256, reverting on
     * overflow (when the input is less than smallest int16 or
     * greater than largest int16).
     *
     * Counterpart to Solidity's `int16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     */
    function toInt16(int256 value) internal pure returns (int16 downcasted) {
        downcasted = int16(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(16, value);
        }
    }

    /**
     * @dev Returns the downcasted int8 from int256, reverting on
     * overflow (when the input is less than smallest int8 or
     * greater than largest int8).
     *
     * Counterpart to Solidity's `int8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits
     */
    function toInt8(int256 value) internal pure returns (int8 downcasted) {
        downcasted = int8(value);
        if (downcasted != value) {
            revert SafeCastOverflowedIntDowncast(8, value);
        }
    }

    /**
     * @dev Converts an unsigned uint256 into a signed int256.
     *
     * Requirements:
     *
     * - input must be less than or equal to maxInt256.
     */
    function toInt256(uint256 value) internal pure returns (int256) {
        // Note: Unsafe cast below is okay because `type(int256).max` is guaranteed to be positive
        if (value > uint256(type(int256).max)) {
            revert SafeCastOverflowedUintToInt(value);
        }
        return int256(value);
    }

    /**
     * @dev Cast a boolean (false or true) to a uint256 (0 or 1) with no jump.
     */
    function toUint(bool b) internal pure returns (uint256 u) {
        assembly ("memory-safe") {
            u := iszero(iszero(b))
        }
    }
}

// lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol

// OpenZeppelin Contracts (last updated v5.1.0) (interfaces/draft-IERC6093.sol)

/**
 * @dev Standard ERC-20 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-20 tokens.
 */
interface IERC20Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC20InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC20InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `spender`’s `allowance`. Used in transfers.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     * @param allowance Amount of tokens a `spender` is allowed to operate with.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC20InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `spender` to be approved. Used in approvals.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC20InvalidSpender(address spender);
}

/**
 * @dev Standard ERC-721 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-721 tokens.
 */
interface IERC721Errors {
    /**
     * @dev Indicates that an address can't be an owner. For example, `address(0)` is a forbidden owner in ERC-20.
     * Used in balance queries.
     * @param owner Address of the current owner of a token.
     */
    error ERC721InvalidOwner(address owner);

    /**
     * @dev Indicates a `tokenId` whose `owner` is the zero address.
     * @param tokenId Identifier number of a token.
     */
    error ERC721NonexistentToken(uint256 tokenId);

    /**
     * @dev Indicates an error related to the ownership over a particular token. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param tokenId Identifier number of a token.
     * @param owner Address of the current owner of a token.
     */
    error ERC721IncorrectOwner(address sender, uint256 tokenId, address owner);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC721InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC721InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param tokenId Identifier number of a token.
     */
    error ERC721InsufficientApproval(address operator, uint256 tokenId);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC721InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC721InvalidOperator(address operator);
}

/**
 * @dev Standard ERC-1155 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-1155 tokens.
 */
interface IERC1155Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     * @param tokenId Identifier number of a token.
     */
    error ERC1155InsufficientBalance(address sender, uint256 balance, uint256 needed, uint256 tokenId);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC1155InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC1155InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param owner Address of the current owner of a token.
     */
    error ERC1155MissingApprovalForAll(address operator, address owner);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC1155InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC1155InvalidOperator(address operator);

    /**
     * @dev Indicates an array length mismatch between ids and values in a safeBatchTransferFrom operation.
     * Used in batch transfers.
     * @param idsLength Length of the array of token identifiers
     * @param valuesLength Length of the array of token amounts
     */
    error ERC1155InvalidArrayLength(uint256 idsLength, uint256 valuesLength);
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

// lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/math/SignedMath.sol)

/**
 * @dev Standard signed math utilities missing in the Solidity language.
 */
library SignedMath {
    /**
     * @dev Branchless ternary evaluation for `a ? b : c`. Gas costs are constant.
     *
     * IMPORTANT: This function may reduce bytecode size and consume less gas when used standalone.
     * However, the compiler may optimize Solidity ternary operations (i.e. `a ? b : c`) to only compute
     * one branch when needed, making this function more expensive.
     */
    function ternary(bool condition, int256 a, int256 b) internal pure returns (int256) {
        unchecked {
            // branchless ternary works because:
            // b ^ (a ^ b) == a
            // b ^ 0 == b
            return b ^ ((a ^ b) * int256(SafeCast.toUint(condition)));
        }
    }

    /**
     * @dev Returns the largest of two signed numbers.
     */
    function max(int256 a, int256 b) internal pure returns (int256) {
        return ternary(a > b, a, b);
    }

    /**
     * @dev Returns the smallest of two signed numbers.
     */
    function min(int256 a, int256 b) internal pure returns (int256) {
        return ternary(a < b, a, b);
    }

    /**
     * @dev Returns the average of two signed numbers without overflow.
     * The result is rounded towards zero.
     */
    function average(int256 a, int256 b) internal pure returns (int256) {
        // Formula from the book "Hacker's Delight"
        int256 x = (a & b) + ((a ^ b) >> 1);
        return x + (int256(uint256(x) >> 255) & (a ^ b));
    }

    /**
     * @dev Returns the absolute unsigned value of a signed value.
     */
    function abs(int256 n) internal pure returns (uint256) {
        unchecked {
            // Formula from the "Bit Twiddling Hacks" by Sean Eron Anderson.
            // Since `n` is a signed integer, the generated bytecode will use the SAR opcode to perform the right shift,
            // taking advantage of the most significant (or "sign" bit) in two's complement representation.
            // This opcode adds new most significant bits set to the value of the previous most significant bit. As a result,
            // the mask will either be `bytes32(0)` (if n is positive) or `~bytes32(0)` (if n is negative).
            int256 mask = n >> 255;

            // A `bytes32(0)` mask leaves the input unchanged, while a `~bytes32(0)` mask complements it.
            return uint256((n + mask) ^ mask);
        }
    }
}

// lib/openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Utils.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC721/utils/ERC721Utils.sol)

/**
 * @dev Library that provide common ERC-721 utility functions.
 *
 * See https://eips.ethereum.org/EIPS/eip-721[ERC-721].
 *
 * _Available since v5.1._
 */
library ERC721Utils {
    /**
     * @dev Performs an acceptance check for the provided `operator` by calling {IERC721-onERC721Received}
     * on the `to` address. The `operator` is generally the address that initiated the token transfer (i.e. `msg.sender`).
     *
     * The acceptance call is not executed and treated as a no-op if the target address doesn't contain code (i.e. an EOA).
     * Otherwise, the recipient must implement {IERC721Receiver-onERC721Received} and return the acceptance magic value to accept
     * the transfer.
     */
    function checkOnERC721Received(
        address operator,
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal {
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(operator, from, tokenId, data) returns (bytes4 retval) {
                if (retval != IERC721Receiver.onERC721Received.selector) {
                    // Token rejected
                    revert IERC721Errors.ERC721InvalidReceiver(to);
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    // non-IERC721Receiver implementer
                    revert IERC721Errors.ERC721InvalidReceiver(to);
                } else {
                    assembly ("memory-safe") {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }
}

// lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC721/extensions/IERC721Metadata.sol)

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata is IERC721 {
    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

// lib/openzeppelin-contracts/contracts/utils/math/Math.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/math/Math.sol)

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    enum Rounding {
        Floor, // Toward negative infinity
        Ceil, // Toward positive infinity
        Trunc, // Toward zero
        Expand // Away from zero
    }

    /**
     * @dev Returns the addition of two unsigned integers, with an success flag (no overflow).
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with an success flag (no overflow).
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an success flag (no overflow).
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a success flag (no division by zero).
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a success flag (no division by zero).
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool success, uint256 result) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Branchless ternary evaluation for `a ? b : c`. Gas costs are constant.
     *
     * IMPORTANT: This function may reduce bytecode size and consume less gas when used standalone.
     * However, the compiler may optimize Solidity ternary operations (i.e. `a ? b : c`) to only compute
     * one branch when needed, making this function more expensive.
     */
    function ternary(bool condition, uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            // branchless ternary works because:
            // b ^ (a ^ b) == a
            // b ^ 0 == b
            return b ^ ((a ^ b) * SafeCast.toUint(condition));
        }
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return ternary(a > b, a, b);
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return ternary(a < b, a, b);
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds towards infinity instead
     * of rounding towards zero.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            // Guarantee the same behavior as in a regular Solidity division.
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }

        // The following calculation ensures accurate ceiling division without overflow.
        // Since a is non-zero, (a - 1) / b will not overflow.
        // The largest possible result occurs when (a - 1) / b is type(uint256).max,
        // but the largest value we can obtain is type(uint256).max - 1, which happens
        // when a = type(uint256).max and b = 1.
        unchecked {
            return SafeCast.toUint(a > 0) * ((a - 1) / b + 1);
        }
    }

    /**
     * @dev Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or
     * denominator == 0.
     *
     * Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv) with further edits by
     * Uniswap Labs also under MIT license.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2²⁵⁶ and mod 2²⁵⁶ - 1, then use
            // the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2²⁵⁶ + prod0.
            uint256 prod0 = x * y; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2²⁵⁶. Also prevents denominator == 0.
            if (denominator <= prod1) {
                Panic.panic(ternary(denominator == 0, Panic.DIVISION_BY_ZERO, Panic.UNDER_OVERFLOW));
            }

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator.
            // Always >= 1. See https://cs.stackexchange.com/q/138556/92363.

            uint256 twos = denominator & (0 - denominator);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2²⁵⁶ / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2²⁵⁶. Now that denominator is an odd number, it has an inverse modulo 2²⁵⁶ such
            // that denominator * inv ≡ 1 mod 2²⁵⁶. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv ≡ 1 mod 2⁴.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also
            // works in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2⁸
            inverse *= 2 - denominator * inverse; // inverse mod 2¹⁶
            inverse *= 2 - denominator * inverse; // inverse mod 2³²
            inverse *= 2 - denominator * inverse; // inverse mod 2⁶⁴
            inverse *= 2 - denominator * inverse; // inverse mod 2¹²⁸
            inverse *= 2 - denominator * inverse; // inverse mod 2²⁵⁶

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2²⁵⁶. Since the preconditions guarantee that the outcome is
            // less than 2²⁵⁶, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }

    /**
     * @dev Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        return mulDiv(x, y, denominator) + SafeCast.toUint(unsignedRoundsUp(rounding) && mulmod(x, y, denominator) > 0);
    }

    /**
     * @dev Calculate the modular multiplicative inverse of a number in Z/nZ.
     *
     * If n is a prime, then Z/nZ is a field. In that case all elements are inversible, except 0.
     * If n is not a prime, then Z/nZ is not a field, and some elements might not be inversible.
     *
     * If the input value is not inversible, 0 is returned.
     *
     * NOTE: If you know for sure that n is (big) a prime, it may be cheaper to use Fermat's little theorem and get the
     * inverse using `Math.modExp(a, n - 2, n)`. See {invModPrime}.
     */
    function invMod(uint256 a, uint256 n) internal pure returns (uint256) {
        unchecked {
            if (n == 0) return 0;

            // The inverse modulo is calculated using the Extended Euclidean Algorithm (iterative version)
            // Used to compute integers x and y such that: ax + ny = gcd(a, n).
            // When the gcd is 1, then the inverse of a modulo n exists and it's x.
            // ax + ny = 1
            // ax = 1 + (-y)n
            // ax ≡ 1 (mod n) # x is the inverse of a modulo n

            // If the remainder is 0 the gcd is n right away.
            uint256 remainder = a % n;
            uint256 gcd = n;

            // Therefore the initial coefficients are:
            // ax + ny = gcd(a, n) = n
            // 0a + 1n = n
            int256 x = 0;
            int256 y = 1;

            while (remainder != 0) {
                uint256 quotient = gcd / remainder;

                (gcd, remainder) = (
                    // The old remainder is the next gcd to try.
                    remainder,
                    // Compute the next remainder.
                    // Can't overflow given that (a % gcd) * (gcd // (a % gcd)) <= gcd
                    // where gcd is at most n (capped to type(uint256).max)
                    gcd - remainder * quotient
                );

                (x, y) = (
                    // Increment the coefficient of a.
                    y,
                    // Decrement the coefficient of n.
                    // Can overflow, but the result is casted to uint256 so that the
                    // next value of y is "wrapped around" to a value between 0 and n - 1.
                    x - y * int256(quotient)
                );
            }

            if (gcd != 1) return 0; // No inverse exists.
            return ternary(x < 0, n - uint256(-x), uint256(x)); // Wrap the result if it's negative.
        }
    }

    /**
     * @dev Variant of {invMod}. More efficient, but only works if `p` is known to be a prime greater than `2`.
     *
     * From https://en.wikipedia.org/wiki/Fermat%27s_little_theorem[Fermat's little theorem], we know that if p is
     * prime, then `a**(p-1) ≡ 1 mod p`. As a consequence, we have `a * a**(p-2) ≡ 1 mod p`, which means that
     * `a**(p-2)` is the modular multiplicative inverse of a in Fp.
     *
     * NOTE: this function does NOT check that `p` is a prime greater than `2`.
     */
    function invModPrime(uint256 a, uint256 p) internal view returns (uint256) {
        unchecked {
            return Math.modExp(a, p - 2, p);
        }
    }

    /**
     * @dev Returns the modular exponentiation of the specified base, exponent and modulus (b ** e % m)
     *
     * Requirements:
     * - modulus can't be zero
     * - underlying staticcall to precompile must succeed
     *
     * IMPORTANT: The result is only valid if the underlying call succeeds. When using this function, make
     * sure the chain you're using it on supports the precompiled contract for modular exponentiation
     * at address 0x05 as specified in https://eips.ethereum.org/EIPS/eip-198[EIP-198]. Otherwise,
     * the underlying function will succeed given the lack of a revert, but the result may be incorrectly
     * interpreted as 0.
     */
    function modExp(uint256 b, uint256 e, uint256 m) internal view returns (uint256) {
        (bool success, uint256 result) = tryModExp(b, e, m);
        if (!success) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }
        return result;
    }

    /**
     * @dev Returns the modular exponentiation of the specified base, exponent and modulus (b ** e % m).
     * It includes a success flag indicating if the operation succeeded. Operation will be marked as failed if trying
     * to operate modulo 0 or if the underlying precompile reverted.
     *
     * IMPORTANT: The result is only valid if the success flag is true. When using this function, make sure the chain
     * you're using it on supports the precompiled contract for modular exponentiation at address 0x05 as specified in
     * https://eips.ethereum.org/EIPS/eip-198[EIP-198]. Otherwise, the underlying function will succeed given the lack
     * of a revert, but the result may be incorrectly interpreted as 0.
     */
    function tryModExp(uint256 b, uint256 e, uint256 m) internal view returns (bool success, uint256 result) {
        if (m == 0) return (false, 0);
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            // | Offset    | Content    | Content (Hex)                                                      |
            // |-----------|------------|--------------------------------------------------------------------|
            // | 0x00:0x1f | size of b  | 0x0000000000000000000000000000000000000000000000000000000000000020 |
            // | 0x20:0x3f | size of e  | 0x0000000000000000000000000000000000000000000000000000000000000020 |
            // | 0x40:0x5f | size of m  | 0x0000000000000000000000000000000000000000000000000000000000000020 |
            // | 0x60:0x7f | value of b | 0x<.............................................................b> |
            // | 0x80:0x9f | value of e | 0x<.............................................................e> |
            // | 0xa0:0xbf | value of m | 0x<.............................................................m> |
            mstore(ptr, 0x20)
            mstore(add(ptr, 0x20), 0x20)
            mstore(add(ptr, 0x40), 0x20)
            mstore(add(ptr, 0x60), b)
            mstore(add(ptr, 0x80), e)
            mstore(add(ptr, 0xa0), m)

            // Given the result < m, it's guaranteed to fit in 32 bytes,
            // so we can use the memory scratch space located at offset 0.
            success := staticcall(gas(), 0x05, ptr, 0xc0, 0x00, 0x20)
            result := mload(0x00)
        }
    }

    /**
     * @dev Variant of {modExp} that supports inputs of arbitrary length.
     */
    function modExp(bytes memory b, bytes memory e, bytes memory m) internal view returns (bytes memory) {
        (bool success, bytes memory result) = tryModExp(b, e, m);
        if (!success) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }
        return result;
    }

    /**
     * @dev Variant of {tryModExp} that supports inputs of arbitrary length.
     */
    function tryModExp(
        bytes memory b,
        bytes memory e,
        bytes memory m
    ) internal view returns (bool success, bytes memory result) {
        if (_zeroBytes(m)) return (false, new bytes(0));

        uint256 mLen = m.length;

        // Encode call args in result and move the free memory pointer
        result = abi.encodePacked(b.length, e.length, mLen, b, e, m);

        assembly ("memory-safe") {
            let dataPtr := add(result, 0x20)
            // Write result on top of args to avoid allocating extra memory.
            success := staticcall(gas(), 0x05, dataPtr, mload(result), dataPtr, mLen)
            // Overwrite the length.
            // result.length > returndatasize() is guaranteed because returndatasize() == m.length
            mstore(result, mLen)
            // Set the memory pointer after the returned data.
            mstore(0x40, add(dataPtr, mLen))
        }
    }

    /**
     * @dev Returns whether the provided byte array is zero.
     */
    function _zeroBytes(bytes memory byteArray) private pure returns (bool) {
        for (uint256 i = 0; i < byteArray.length; ++i) {
            if (byteArray[i] != 0) {
                return false;
            }
        }
        return true;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded
     * towards zero.
     *
     * This method is based on Newton's method for computing square roots; the algorithm is restricted to only
     * using integer operations.
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        unchecked {
            // Take care of easy edge cases when a == 0 or a == 1
            if (a <= 1) {
                return a;
            }

            // In this function, we use Newton's method to get a root of `f(x) := x² - a`. It involves building a
            // sequence x_n that converges toward sqrt(a). For each iteration x_n, we also define the error between
            // the current value as `ε_n = | x_n - sqrt(a) |`.
            //
            // For our first estimation, we consider `e` the smallest power of 2 which is bigger than the square root
            // of the target. (i.e. `2**(e-1) ≤ sqrt(a) < 2**e`). We know that `e ≤ 128` because `(2¹²⁸)² = 2²⁵⁶` is
            // bigger than any uint256.
            //
            // By noticing that
            // `2**(e-1) ≤ sqrt(a) < 2**e → (2**(e-1))² ≤ a < (2**e)² → 2**(2*e-2) ≤ a < 2**(2*e)`
            // we can deduce that `e - 1` is `log2(a) / 2`. We can thus compute `x_n = 2**(e-1)` using a method similar
            // to the msb function.
            uint256 aa = a;
            uint256 xn = 1;

            if (aa >= (1 << 128)) {
                aa >>= 128;
                xn <<= 64;
            }
            if (aa >= (1 << 64)) {
                aa >>= 64;
                xn <<= 32;
            }
            if (aa >= (1 << 32)) {
                aa >>= 32;
                xn <<= 16;
            }
            if (aa >= (1 << 16)) {
                aa >>= 16;
                xn <<= 8;
            }
            if (aa >= (1 << 8)) {
                aa >>= 8;
                xn <<= 4;
            }
            if (aa >= (1 << 4)) {
                aa >>= 4;
                xn <<= 2;
            }
            if (aa >= (1 << 2)) {
                xn <<= 1;
            }

            // We now have x_n such that `x_n = 2**(e-1) ≤ sqrt(a) < 2**e = 2 * x_n`. This implies ε_n ≤ 2**(e-1).
            //
            // We can refine our estimation by noticing that the middle of that interval minimizes the error.
            // If we move x_n to equal 2**(e-1) + 2**(e-2), then we reduce the error to ε_n ≤ 2**(e-2).
            // This is going to be our x_0 (and ε_0)
            xn = (3 * xn) >> 1; // ε_0 := | x_0 - sqrt(a) | ≤ 2**(e-2)

            // From here, Newton's method give us:
            // x_{n+1} = (x_n + a / x_n) / 2
            //
            // One should note that:
            // x_{n+1}² - a = ((x_n + a / x_n) / 2)² - a
            //              = ((x_n² + a) / (2 * x_n))² - a
            //              = (x_n⁴ + 2 * a * x_n² + a²) / (4 * x_n²) - a
            //              = (x_n⁴ + 2 * a * x_n² + a² - 4 * a * x_n²) / (4 * x_n²)
            //              = (x_n⁴ - 2 * a * x_n² + a²) / (4 * x_n²)
            //              = (x_n² - a)² / (2 * x_n)²
            //              = ((x_n² - a) / (2 * x_n))²
            //              ≥ 0
            // Which proves that for all n ≥ 1, sqrt(a) ≤ x_n
            //
            // This gives us the proof of quadratic convergence of the sequence:
            // ε_{n+1} = | x_{n+1} - sqrt(a) |
            //         = | (x_n + a / x_n) / 2 - sqrt(a) |
            //         = | (x_n² + a - 2*x_n*sqrt(a)) / (2 * x_n) |
            //         = | (x_n - sqrt(a))² / (2 * x_n) |
            //         = | ε_n² / (2 * x_n) |
            //         = ε_n² / | (2 * x_n) |
            //
            // For the first iteration, we have a special case where x_0 is known:
            // ε_1 = ε_0² / | (2 * x_0) |
            //     ≤ (2**(e-2))² / (2 * (2**(e-1) + 2**(e-2)))
            //     ≤ 2**(2*e-4) / (3 * 2**(e-1))
            //     ≤ 2**(e-3) / 3
            //     ≤ 2**(e-3-log2(3))
            //     ≤ 2**(e-4.5)
            //
            // For the following iterations, we use the fact that, 2**(e-1) ≤ sqrt(a) ≤ x_n:
            // ε_{n+1} = ε_n² / | (2 * x_n) |
            //         ≤ (2**(e-k))² / (2 * 2**(e-1))
            //         ≤ 2**(2*e-2*k) / 2**e
            //         ≤ 2**(e-2*k)
            xn = (xn + a / xn) >> 1; // ε_1 := | x_1 - sqrt(a) | ≤ 2**(e-4.5)  -- special case, see above
            xn = (xn + a / xn) >> 1; // ε_2 := | x_2 - sqrt(a) | ≤ 2**(e-9)    -- general case with k = 4.5
            xn = (xn + a / xn) >> 1; // ε_3 := | x_3 - sqrt(a) | ≤ 2**(e-18)   -- general case with k = 9
            xn = (xn + a / xn) >> 1; // ε_4 := | x_4 - sqrt(a) | ≤ 2**(e-36)   -- general case with k = 18
            xn = (xn + a / xn) >> 1; // ε_5 := | x_5 - sqrt(a) | ≤ 2**(e-72)   -- general case with k = 36
            xn = (xn + a / xn) >> 1; // ε_6 := | x_6 - sqrt(a) | ≤ 2**(e-144)  -- general case with k = 72

            // Because e ≤ 128 (as discussed during the first estimation phase), we know have reached a precision
            // ε_6 ≤ 2**(e-144) < 1. Given we're operating on integers, then we can ensure that xn is now either
            // sqrt(a) or sqrt(a) + 1.
            return xn - SafeCast.toUint(xn > a / xn);
        }
    }

    /**
     * @dev Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + SafeCast.toUint(unsignedRoundsUp(rounding) && result * result < a);
        }
    }

    /**
     * @dev Return the log in base 2 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        uint256 exp;
        unchecked {
            exp = 128 * SafeCast.toUint(value > (1 << 128) - 1);
            value >>= exp;
            result += exp;

            exp = 64 * SafeCast.toUint(value > (1 << 64) - 1);
            value >>= exp;
            result += exp;

            exp = 32 * SafeCast.toUint(value > (1 << 32) - 1);
            value >>= exp;
            result += exp;

            exp = 16 * SafeCast.toUint(value > (1 << 16) - 1);
            value >>= exp;
            result += exp;

            exp = 8 * SafeCast.toUint(value > (1 << 8) - 1);
            value >>= exp;
            result += exp;

            exp = 4 * SafeCast.toUint(value > (1 << 4) - 1);
            value >>= exp;
            result += exp;

            exp = 2 * SafeCast.toUint(value > (1 << 2) - 1);
            value >>= exp;
            result += exp;

            result += SafeCast.toUint(value > 1);
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + SafeCast.toUint(unsignedRoundsUp(rounding) && 1 << result < value);
        }
    }

    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + SafeCast.toUint(unsignedRoundsUp(rounding) && 10 ** result < value);
        }
    }

    /**
     * @dev Return the log in base 256 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        uint256 isGt;
        unchecked {
            isGt = SafeCast.toUint(value > (1 << 128) - 1);
            value >>= isGt * 128;
            result += isGt * 16;

            isGt = SafeCast.toUint(value > (1 << 64) - 1);
            value >>= isGt * 64;
            result += isGt * 8;

            isGt = SafeCast.toUint(value > (1 << 32) - 1);
            value >>= isGt * 32;
            result += isGt * 4;

            isGt = SafeCast.toUint(value > (1 << 16) - 1);
            value >>= isGt * 16;
            result += isGt * 2;

            result += SafeCast.toUint(value > (1 << 8) - 1);
        }
        return result;
    }

    /**
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + SafeCast.toUint(unsignedRoundsUp(rounding) && 1 << (result << 3) < value);
        }
    }

    /**
     * @dev Returns whether a provided rounding mode is considered rounding up for unsigned integers.
     */
    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
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

// lib/openzeppelin-contracts/contracts/utils/Strings.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/Strings.sol)

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    uint8 private constant ADDRESS_LENGTH = 20;

    /**
     * @dev The `value` string doesn't fit in the specified `length`.
     */
    error StringsInsufficientHexLength(uint256 value, uint256 length);

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            assembly ("memory-safe") {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                assembly ("memory-safe") {
                    mstore8(ptr, byte(mod(value, 10), HEX_DIGITS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    /**
     * @dev Converts a `int256` to its ASCII `string` decimal representation.
     */
    function toStringSigned(int256 value) internal pure returns (string memory) {
        return string.concat(value < 0 ? "-" : "", toString(SignedMath.abs(value)));
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, Math.log256(value) + 1);
        }
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        uint256 localValue = value;
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = HEX_DIGITS[localValue & 0xf];
            localValue >>= 4;
        }
        if (localValue != 0) {
            revert StringsInsufficientHexLength(value, length);
        }
        return string(buffer);
    }

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its not checksummed ASCII `string` hexadecimal
     * representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), ADDRESS_LENGTH);
    }

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its checksummed ASCII `string` hexadecimal
     * representation, according to EIP-55.
     */
    function toChecksumHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = bytes(toHexString(addr));

        // hash the hex part of buffer (skip length + 2 bytes, length 40)
        uint256 hashValue;
        assembly ("memory-safe") {
            hashValue := shr(96, keccak256(add(buffer, 0x22), 40))
        }

        for (uint256 i = 41; i > 1; --i) {
            // possible values for buffer[i] are 48 (0) to 57 (9) and 97 (a) to 102 (f)
            if (hashValue & 0xf > 7 && uint8(buffer[i]) > 96) {
                // case shift by xoring with 0x20
                buffer[i] ^= 0x20;
            }
            hashValue >>= 4;
        }
        return string(buffer);
    }

    /**
     * @dev Returns true if the two strings are equal.
     */
    function equal(string memory a, string memory b) internal pure returns (bool) {
        return bytes(a).length == bytes(b).length && keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

// lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC721/ERC721.sol)

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC-721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
abstract contract ERC721 is Context, ERC165, IERC721, IERC721Metadata, IERC721Errors {
    using Strings for uint256;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    mapping(uint256 tokenId => address) private _owners;

    mapping(address owner => uint256) private _balances;

    mapping(uint256 tokenId => address) private _tokenApprovals;

    mapping(address owner => mapping(address operator => bool)) private _operatorApprovals;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual returns (uint256) {
        if (owner == address(0)) {
            revert ERC721InvalidOwner(address(0));
        }
        return _balances[owner];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        return _requireOwned(tokenId);
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual returns (string memory) {
        _requireOwned(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string.concat(baseURI, tokenId.toString()) : "";
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual {
        _approve(to, tokenId, _msgSender());
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual returns (address) {
        _requireOwned(tokenId);

        return _getApproved(tokenId);
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        // Setting an "auth" arguments enables the `_isAuthorized` check which verifies that the token exists
        // (from != 0). Therefore, it is not needed to verify that the return value is not 0 here.
        address previousOwner = _update(to, tokenId, _msgSender());
        if (previousOwner != from) {
            revert ERC721IncorrectOwner(from, tokenId, previousOwner);
        }
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual {
        transferFrom(from, to, tokenId);
        ERC721Utils.checkOnERC721Received(_msgSender(), from, to, tokenId, data);
    }

    /**
     * @dev Returns the owner of the `tokenId`. Does NOT revert if token doesn't exist
     *
     * IMPORTANT: Any overrides to this function that add ownership of tokens not tracked by the
     * core ERC-721 logic MUST be matched with the use of {_increaseBalance} to keep balances
     * consistent with ownership. The invariant to preserve is that for any address `a` the value returned by
     * `balanceOf(a)` must be equal to the number of tokens such that `_ownerOf(tokenId)` is `a`.
     */
    function _ownerOf(uint256 tokenId) internal view virtual returns (address) {
        return _owners[tokenId];
    }

    /**
     * @dev Returns the approved address for `tokenId`. Returns 0 if `tokenId` is not minted.
     */
    function _getApproved(uint256 tokenId) internal view virtual returns (address) {
        return _tokenApprovals[tokenId];
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `owner`'s tokens, or `tokenId` in
     * particular (ignoring whether it is owned by `owner`).
     *
     * WARNING: This function assumes that `owner` is the actual owner of `tokenId` and does not verify this
     * assumption.
     */
    function _isAuthorized(address owner, address spender, uint256 tokenId) internal view virtual returns (bool) {
        return
            spender != address(0) &&
            (owner == spender || isApprovedForAll(owner, spender) || _getApproved(tokenId) == spender);
    }

    /**
     * @dev Checks if `spender` can operate on `tokenId`, assuming the provided `owner` is the actual owner.
     * Reverts if:
     * - `spender` does not have approval from `owner` for `tokenId`.
     * - `spender` does not have approval to manage all of `owner`'s assets.
     *
     * WARNING: This function assumes that `owner` is the actual owner of `tokenId` and does not verify this
     * assumption.
     */
    function _checkAuthorized(address owner, address spender, uint256 tokenId) internal view virtual {
        if (!_isAuthorized(owner, spender, tokenId)) {
            if (owner == address(0)) {
                revert ERC721NonexistentToken(tokenId);
            } else {
                revert ERC721InsufficientApproval(spender, tokenId);
            }
        }
    }

    /**
     * @dev Unsafe write access to the balances, used by extensions that "mint" tokens using an {ownerOf} override.
     *
     * NOTE: the value is limited to type(uint128).max. This protect against _balance overflow. It is unrealistic that
     * a uint256 would ever overflow from increments when these increments are bounded to uint128 values.
     *
     * WARNING: Increasing an account's balance using this function tends to be paired with an override of the
     * {_ownerOf} function to resolve the ownership of the corresponding tokens so that balances and ownership
     * remain consistent with one another.
     */
    function _increaseBalance(address account, uint128 value) internal virtual {
        unchecked {
            _balances[account] += value;
        }
    }

    /**
     * @dev Transfers `tokenId` from its current owner to `to`, or alternatively mints (or burns) if the current owner
     * (or `to`) is the zero address. Returns the owner of the `tokenId` before the update.
     *
     * The `auth` argument is optional. If the value passed is non 0, then this function will check that
     * `auth` is either the owner of the token, or approved to operate on the token (by the owner).
     *
     * Emits a {Transfer} event.
     *
     * NOTE: If overriding this function in a way that tracks balances, see also {_increaseBalance}.
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual returns (address) {
        address from = _ownerOf(tokenId);

        // Perform (optional) operator check
        if (auth != address(0)) {
            _checkAuthorized(from, auth, tokenId);
        }

        // Execute the update
        if (from != address(0)) {
            // Clear approval. No need to re-authorize or emit the Approval event
            _approve(address(0), tokenId, address(0), false);

            unchecked {
                _balances[from] -= 1;
            }
        }

        if (to != address(0)) {
            unchecked {
                _balances[to] += 1;
            }
        }

        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        return from;
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal {
        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        address previousOwner = _update(to, tokenId, address(0));
        if (previousOwner != address(0)) {
            revert ERC721InvalidSender(address(0));
        }
    }

    /**
     * @dev Mints `tokenId`, transfers it to `to` and checks for `to` acceptance.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 tokenId, bytes memory data) internal virtual {
        _mint(to, tokenId);
        ERC721Utils.checkOnERC721Received(_msgSender(), address(0), to, tokenId, data);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     * This is an internal function that does not check if the sender is authorized to operate on the token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal {
        address previousOwner = _update(address(0), tokenId, address(0));
        if (previousOwner == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId) internal {
        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        address previousOwner = _update(to, tokenId, address(0));
        if (previousOwner == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        } else if (previousOwner != from) {
            revert ERC721IncorrectOwner(from, tokenId, previousOwner);
        }
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking that contract recipients
     * are aware of the ERC-721 standard to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is like {safeTransferFrom} in the sense that it invokes
     * {IERC721Receiver-onERC721Received} on the receiver, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `tokenId` token must exist and be owned by `from`.
     * - `to` cannot be the zero address.
     * - `from` cannot be the zero address.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint256 tokenId) internal {
        _safeTransfer(from, to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeTransfer-address-address-uint256-}[`_safeTransfer`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal virtual {
        _transfer(from, to, tokenId);
        ERC721Utils.checkOnERC721Received(_msgSender(), from, to, tokenId, data);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * The `auth` argument is optional. If the value passed is non 0, then this function will check that `auth` is
     * either the owner of the token, or approved to operate on all tokens held by this owner.
     *
     * Emits an {Approval} event.
     *
     * Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument.
     */
    function _approve(address to, uint256 tokenId, address auth) internal {
        _approve(to, tokenId, auth, true);
    }

    /**
     * @dev Variant of `_approve` with an optional flag to enable or disable the {Approval} event. The event is not
     * emitted in the context of transfers.
     */
    function _approve(address to, uint256 tokenId, address auth, bool emitEvent) internal virtual {
        // Avoid reading the owner unless necessary
        if (emitEvent || auth != address(0)) {
            address owner = _requireOwned(tokenId);

            // We do not use _isAuthorized because single-token approvals should not be able to call approve
            if (auth != address(0) && owner != auth && !isApprovedForAll(owner, auth)) {
                revert ERC721InvalidApprover(auth);
            }

            if (emitEvent) {
                emit Approval(owner, to, tokenId);
            }
        }

        _tokenApprovals[tokenId] = to;
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Requirements:
     * - operator can't be the address zero.
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(address owner, address operator, bool approved) internal virtual {
        if (operator == address(0)) {
            revert ERC721InvalidOperator(operator);
        }
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    /**
     * @dev Reverts if the `tokenId` doesn't have a current owner (it hasn't been minted, or it has been burned).
     * Returns the owner.
     *
     * Overrides to ownership logic should be done to {_ownerOf}.
     */
    function _requireOwned(uint256 tokenId) internal view returns (address) {
        address owner = _ownerOf(tokenId);
        if (owner == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }
        return owner;
    }
}

// src/HoodPups.sol

/// @title HoodPups
/// @notice ERC-721 on Robinhood Chain where every token permanently references exactly one
///         canonical Bitcoin Puppet inscription.
/// @dev WHAT A HOODPUP IS, AND WHAT IT IS NOT — READ THIS BEFORE READING ANY OTHER LINE:
///      A HoodPup is a derived Robinhood Chain asset that *references* a Bitcoin inscription. It is
///      not the inscription, it does not custody, wrap, bridge or escrow it, and holding one confers
///      no rights over it. The original Bitcoin Puppet never leaves Bitcoin. This contract has no
///      payable function and no way to hold or move value of any kind.
///
///      TRUST BOUNDARY: nothing here verifies Bitcoin consensus. That a given inscription was
///      genuinely controlled by whoever authorized a mint is asserted upstream by a 3-of-5 quorum of
///      independent attestors, and this contract simply trusts `MINTER_ROLE` to have done that work.
///      It is an attested settlement system, not a trustless bridge.
///
///      THE CENTRAL PROMISE: one canonical inscription mints AT MOST ONE HoodPup, ever. That is
///      enforced by `_tokenOfRoot`, a mapping that is written exactly once per Root and for which no
///      clearing, remapping, burning or administrative override exists anywhere in this file. There
///      is deliberately no `burn`, no `setRootOf`, no rescue hook and no upgrade path: every one of
///      those would be a way to make one inscription produce a second token, which is precisely the
///      guarantee the whole protocol is built on. Auditors should verify this by searching the file
///      for writes to `_tokenOfRoot` — there is one, inside `mintRooted`, guarded by a check that
///      the slot is still empty.
///
///      TOKEN IDS START AT 1. Zero is reserved as the "no such token" sentinel so `tokenOfRoot`
///      can answer "not minted" without a second lookup, and so no caller can mistake a
///      default-initialised storage slot for a real token.
///
///      PAUSING IS NARROW BY DESIGN. `mintingPaused` blocks `mintRooted` and nothing else.
///      Transfers, approvals, ERC-4907 reads and every view keep working while paused, because a
///      holder's property must not depend on the protocol's operational state. There is no
///      `whenNotPaused` modifier anywhere near a transfer path, and the unit suite asserts that.
///
///      NON-UPGRADEABLE by construction: no proxy, no initializer, no `delegatecall`, no
///      `selfdestruct`, no `tx.origin`, and no admin path that can seize, move or destroy a token
///      that a user already holds.
contract HoodPups is IHoodPups, ERC721, AccessControl, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role permitted to mint a HoodPup for a Root.
    /// @dev Granted to `HoodPupOfferEscrow` only. It is NOT granted at construction: the escrow does
    ///      not exist yet when this contract is deployed, and pre-granting it to the deployer would
    ///      create exactly the EOA-holds-a-privileged-role state the deployment is meant to avoid.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role permitted to set the ERC-4907 user without holding or being approved for a token.
    /// @dev Granted to `TourEngine` only, which sets a user after validating tour rules. This is the
    ///      narrowest possible extra authority: it can change who may *use* a token temporarily, and
    ///      it can never transfer, mint, burn or approve one. A compromised TourEngine can grief
    ///      rental state; it can never take a token away from its owner.
    bytes32 public constant TOUR_ENGINE_ROLE = keccak256("TOUR_ENGINE_ROLE");

    /// @notice Role permitted to change or permanently freeze the metadata URIs.
    /// @dev Separate from `DEFAULT_ADMIN_ROLE` for least privilege: role administration and metadata
    ///      administration are different jobs with different blast radii, and separating them lets a
    ///      deployment move one without widening the other. In production this MUST be held by a
    ///      `TimelockController` under multisig control, which is what makes every metadata change a
    ///      publicly visible, delayed operation rather than a silent storage write.
    bytes32 public constant METADATA_ADMIN_ROLE = keccak256("METADATA_ADMIN_ROLE");

    /// @notice Role permitted to pause minting. Cannot unpause.
    /// @dev Held by the guardian multisig — smaller and faster than the timelock, because pausing
    ///      during an incident must be fast. Unpausing requires `DEFAULT_ADMIN_ROLE` (the timelock),
    ///      because resuming risk-taking must be deliberate. The asymmetry means a compromised
    ///      guardian can only ever cost liveness on the mint path; it can never resume a mint path
    ///      that governance has stopped, and it can never touch a token that already exists.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              EXTRA ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when `mintRooted` is handed a `RootId` whose reveal txid is zero.
    /// @dev A zero txid is not a Bitcoin transaction; it is the shape of a default-initialised
    ///      struct that reached the mint path through a caller bug. Rejecting it costs one comparison
    ///      and prevents that bug from permanently consuming a token id and a `_tokenOfRoot` slot
    ///      that can never be reclaimed, since nothing in this contract can undo a mint.
    error ZeroRootTxid();

    /// @notice Thrown when the mint pause is set to the value it already holds.
    /// @dev Reverting on a no-op is the house rule across this protocol. Here it also carries useful
    ///      operational information: a guardian re-sending `pauseMinting()` during an incident gets
    ///      an unambiguous "already paused" answer instead of a second, indistinguishable
    ///      `MintingPauseUpdated` event that would make the incident timeline ambiguous for indexers.
    /// @param currentlyPaused The pause state already stored.
    error MintPauseUnchanged(bool currentlyPaused);

    /*//////////////////////////////////////////////////////////////
                               EXTRA EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, recording the collection's genesis configuration.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE`, `METADATA_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param name The ERC-721 collection name.
    /// @param symbol The ERC-721 collection symbol.
    /// @param firstTokenId The id the first mint will assign, always 1.
    event HoodPupsInitialized(address indexed admin, string name, string symbol, uint256 firstTokenId);

    /*//////////////////////////////////////////////////////////////
                            ERC-4907 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Temporary use rights over one token.
    /// @dev Packed into a single slot: an address and a `uint64` fit in 32 bytes together, so a
    ///      `setUser` writes one slot and the `_update` clear on transfer wipes one slot.
    /// @param user Address currently entitled to use the token.
    /// @param expires Unix timestamp at which that entitlement lapses.
    struct UserInfo {
        address user;
        uint64 expires;
    }

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Next id `mintRooted` will assign. Starts at 1 and only ever increases; there is no code
    ///      path that decrements it, and no burn to make a gap reusable.
    uint256 private _nextTokenId;

    /// @dev Root key => token id. WRITE-ONCE PER KEY. This mapping is the one-mint-per-Root rule.
    mapping(bytes32 rootKey => uint256 tokenId) private _tokenOfRoot;

    /// @dev Token id => the Bitcoin inscription identity it permanently references. Written once, in
    ///      `mintRooted`, and never again by anything.
    mapping(uint256 tokenId => PuppetTypes.RootId root) private _rootOf;

    /// @dev Token id => ERC-4907 temporary user. The only entry here that is cleared automatically
    ///      is on a genuine change of owner; see `_update`.
    mapping(uint256 tokenId => UserInfo info) private _userInfo;

    /// @dev Prefix `tokenURI` builds on. Mutable until `_metadataFrozen` is set, then permanent.
    string private _baseTokenURI;

    /// @dev Collection-level metadata document URI. Mutable until frozen, then permanent.
    string private _collectionURI;

    /// @dev Once true, no URI in this contract can ever change again. There is no unfreeze.
    bool private _metadataFrozen;

    /// @dev Once true, `mintRooted` reverts. Affects nothing else, ever.
    bool private _mintingPaused;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the collection.
    /// @dev `admin` MUST be a `TimelockController` (itself governed by a multisig) in production.
    ///      Nothing in this contract can enforce that, so the deployment script grants the roles to
    ///      the timelock and revokes them from the deployer in the same transaction batch;
    ///      `test_TimelockHandoverFullyRevokesDeployer` proves the revocation path leaves the
    ///      deployer with zero authority.
    ///
    ///      `MINTER_ROLE` and `TOUR_ENGINE_ROLE` are intentionally left ungranted: the escrow and the
    ///      tour engine are deployed after this contract, and granting them later is a separate,
    ///      reviewable governance action.
    ///
    ///      Both URI events are emitted here with an empty `previous`, so an indexer that only
    ///      listens to `BaseURIUpdated` / `ContractURIUpdated` reconstructs the full history without
    ///      needing to special-case genesis.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE`, `METADATA_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param name_ ERC-721 collection name.
    /// @param symbol_ ERC-721 collection symbol.
    /// @param baseURI_ Initial `tokenURI` prefix. May be empty and set later.
    /// @param contractURI_ Initial collection metadata URI. May be empty and set later.
    constructor(
        address admin,
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        string memory contractURI_
    ) ERC721(name_, symbol_) {
        if (admin == address(0)) revert ZeroAddress();

        // Ids start at 1 so that zero is an unambiguous "not minted" answer everywhere.
        _nextTokenId = 1;

        _baseTokenURI = baseURI_;
        _collectionURI = contractURI_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(METADATA_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        emit BaseURIUpdated("", baseURI_);
        emit ContractURIUpdated("", contractURI_);
        emit HoodPupsInitialized(admin, name_, symbol_, 1);
    }

    /*//////////////////////////////////////////////////////////////
                                  MINT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPups
    /// @dev CHECKS-EFFECTS-INTERACTIONS. Every storage write and the protocol-level event happen
    ///      before `_safeMint`, whose `onERC721Received` callback is the only external call in this
    ///      contract. A recipient that reenters therefore observes a fully consistent state: its
    ///      Root is already marked as minted, so it cannot use the callback to mint the same Root
    ///      twice.
    ///
    ///      `nonReentrant` is applied anyway. No value moves here, so the guard is defence in depth
    ///      rather than a correctness requirement, and it costs a storage slot per mint. That trade
    ///      is taken deliberately: this is the function that enforces the protocol's central promise,
    ///      and a future edit that introduces a state write *after* `_safeMint` would silently become
    ///      exploitable without it. Clarity and durability beat the gas here.
    ///
    ///      `_safeMint` (not `_mint`) is used so a contract recipient that cannot handle ERC-721s
    ///      reverts the settlement rather than having its HoodPup permanently stranded at an address
    ///      that can never transfer it. Since a Root can only ever mint once, a stranded token would
    ///      be unrecoverable in the strongest sense: no burn, no remap, no second chance.
    /// @param recipient Address that receives the HoodPup. Must be nonzero and ERC-721 aware.
    /// @param root The Bitcoin inscription this token will permanently reference.
    /// @return tokenId The newly assigned token id.
    function mintRooted(address recipient, PuppetTypes.RootId calldata root)
        external
        onlyRole(MINTER_ROLE)
        nonReentrant
        returns (uint256 tokenId)
    {
        if (_mintingPaused) revert MintingPaused();
        return _mintRooted(recipient, root);
    }

    /// @inheritdoc IHoodPups
    /// @dev The only production holder of `MINTER_ROLE` is the immutable offer escrow, which calls
    ///      this entry point solely to finish a BTC reservation whose solver may already have paid
    ///      irreversible Bitcoin. Ordinary settlement continues through `mintRooted` and remains
    ///      blocked by the incident pause.
    function mintRootedTerminal(address recipient, PuppetTypes.RootId calldata root)
        external
        onlyRole(MINTER_ROLE)
        nonReentrant
        returns (uint256 tokenId)
    {
        return _mintRooted(recipient, root);
    }

    function _mintRooted(address recipient, PuppetTypes.RootId calldata root) private returns (uint256 tokenId) {
        if (recipient == address(0)) revert ZeroAddress();
        if (root.inscriptionTxid == bytes32(0)) revert ZeroRootTxid();

        bytes32 key = PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);

        uint256 existing = _tokenOfRoot[key];
        if (existing != 0) revert RootAlreadyMinted(key, existing);

        tokenId = _nextTokenId;
        // Cannot realistically overflow: one mint per inscription, and the manifest is finite.
        _nextTokenId = tokenId + 1;

        _tokenOfRoot[key] = tokenId;
        _rootOf[tokenId] = root;

        // Emitted before the receiver callback so the protocol-level record of the mint is written
        // ahead of the ERC-721 `Transfer`, and cannot be reordered by anything the recipient does.
        emit RootedMint(tokenId, key, recipient, root.inscriptionTxid, root.inscriptionIndex);

        _safeMint(recipient, tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                             ROOT IDENTITY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPups
    /// @dev Permanent. Nothing in this contract can make this return false once it has returned true.
    /// @param rootKey The canonical protocol key for an inscription.
    /// @return True if this Root has already produced its one HoodPup.
    function rootMinted(bytes32 rootKey) external view returns (bool) {
        return _tokenOfRoot[rootKey] != 0;
    }

    /// @inheritdoc IHoodPups
    /// @dev Returns zero for an unminted Root rather than reverting, because callers legitimately
    ///      ask this question about Roots that have never minted — that is the entire point of the
    ///      check. Ids start at 1, so zero can never be confused with a real token.
    /// @param rootKey The canonical protocol key for an inscription.
    /// @return The token id for that Root, or zero if it has never minted.
    function tokenOfRoot(bytes32 rootKey) external view returns (uint256) {
        return _tokenOfRoot[rootKey];
    }

    /// @inheritdoc IHoodPups
    /// @dev Reverts for an unknown token instead of returning a zeroed struct, because a zeroed
    ///      `RootId` is a syntactically valid identity and a caller that forgot to check would treat
    ///      it as a real inscription.
    /// @param tokenId The token to look up.
    /// @return The Bitcoin inscription identity this token permanently references.
    function rootOf(uint256 tokenId) external view returns (PuppetTypes.RootId memory) {
        _requireKnown(tokenId);
        return _rootOf[tokenId];
    }

    /// @inheritdoc IHoodPups
    /// @dev Derived from the stored `RootId` through `PuppetHashing` rather than cached in its own
    ///      mapping. One keccak on a view path buys the guarantee that the key returned here can
    ///      never drift from the identity stored in `_rootOf` — a cached copy could, if a future edit
    ///      updated one and not the other.
    /// @param tokenId The token to look up.
    /// @return The canonical root key this token references.
    function rootKeyOf(uint256 tokenId) external view returns (bytes32) {
        _requireKnown(tokenId);
        PuppetTypes.RootId memory root = _rootOf[tokenId];
        return PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);
    }

    /// @inheritdoc IHoodPups
    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    /*//////////////////////////////////////////////////////////////
                                ERC-4907
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC4907
    /// @dev AUTHORIZATION. The owner, an approved operator (`setApprovalForAll`) and the single
    ///      approved address for the token may all set the user, matching the ERC-4907 reference
    ///      implementation's "owner or approved" rule. `TOUR_ENGINE_ROLE` is additionally allowed so
    ///      `TourEngine` can place a token on tour after validating its own rules, without the owner
    ///      having to hand it a blanket ERC-721 approval — which would let it *transfer* the token.
    ///      Granting the narrow role instead of a transfer approval is the entire point.
    ///
    ///      CLEARING. Passing `address(0)` clears the entitlement, and the expiry is forced to zero
    ///      rather than being rejected, so a caller that clears with a stale nonzero `expires` gets
    ///      the obvious outcome instead of a confusing revert. Since `user` is zero the expiry can
    ///      have no effect, so silently normalising it cannot hide a mistake that matters.
    ///
    ///      EXPIRY MUST BE IN THE FUTURE. An expiry at or before `block.timestamp` would create an
    ///      entitlement that is already dead on arrival while still occupying the slot, so callers
    ///      would see `userOf == address(0)` immediately and have no way to tell it apart from a
    ///      failed call. Reverting makes the mistake loud.
    /// @param tokenId Token to grant temporary use of.
    /// @param user Address entitled to use it, or `address(0)` to clear.
    /// @param expires Unix timestamp at which the entitlement lapses. Must be in the future unless
    ///        clearing.
    function setUser(uint256 tokenId, address user, uint64 expires) external {
        _requireKnown(tokenId);

        address owner = ownerOf(tokenId);
        if (!_isAuthorized(owner, msg.sender, tokenId) && !hasRole(TOUR_ENGINE_ROLE, msg.sender)) {
            revert NotOwnerNorApproved(msg.sender, tokenId);
        }

        // The owner already holds every right the user role can confer, so naming them as user is
        // always a mistake — and one that would let a rental marketplace show a token as "rented"
        // to the person who owns it.
        if (user == owner) revert UserIsOwner();

        if (user == address(0)) {
            expires = 0;
        } else if (expires <= block.timestamp) {
            revert ExpiryInPast(expires, block.timestamp);
        }

        _userInfo[tokenId] = UserInfo({user: user, expires: expires});
        emit UpdateUser(tokenId, user, expires);
    }

    /// @inheritdoc IERC4907
    /// @dev Returns `address(0)` once the term has elapsed, and also for a token id that was never
    ///      minted. Deliberately non-reverting: this is the read every integrator puts on a hot path,
    ///      and a view that reverts on an unknown id invites callers to wrap it in a try/catch whose
    ///      failure branch is untested. Zero already means "nobody may use this token", which is the
    ///      correct, fail-closed answer in both cases.
    ///
    ///      The comparison is `>=`, matching the ERC-4907 reference implementation: an entitlement
    ///      expiring at exactly `block.timestamp` is still live for that block. `setUser` refuses to
    ///      create such an entitlement, so this branch only matters for integrators comparing this
    ///      implementation against the reference.
    /// @param tokenId Token to query.
    /// @return The current user, or the zero address.
    function userOf(uint256 tokenId) external view returns (address) {
        UserInfo memory info = _userInfo[tokenId];
        if (uint256(info.expires) >= block.timestamp) return info.user;
        return address(0);
    }

    /// @inheritdoc IERC4907
    /// @dev Returns the raw stored expiry, including one already in the past, so a UI can show
    ///      "expired at" rather than only "not rented". Zero means no entitlement was ever set, or
    ///      the last one was cleared. Non-reverting for the same reason as `userOf`.
    /// @param tokenId Token to query.
    /// @return The stored expiry timestamp, or zero.
    function userExpires(uint256 tokenId) external view returns (uint256) {
        return _userInfo[tokenId].expires;
    }

    /*//////////////////////////////////////////////////////////////
                                METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice The prefix `tokenURI` is built on.
    /// @return The current base URI.
    function baseTokenURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    /// @notice Collection-level metadata document, as consumed by marketplaces.
    /// @return The current contract URI.
    function contractURI() external view returns (string memory) {
        return _collectionURI;
    }

    /// @inheritdoc IHoodPups
    function metadataFrozen() external view returns (bool) {
        return _metadataFrozen;
    }

    /// @notice Replace the `tokenURI` prefix.
    /// @dev Timelocked: `METADATA_ADMIN_ROLE` is held by the `TimelockController` in production, so
    ///      every URI change is queued publicly for the full delay before it can execute. Permanently
    ///      reverts once metadata is frozen.
    ///
    ///      No-op writes are allowed here (unlike the pause flags) because a "change" that resolves
    ///      to the same string is a plausible outcome of a legitimate re-deploy of an off-chain
    ///      metadata service, and rejecting it would strand a timelock proposal for no security gain.
    /// @param next The new base URI.
    function setBaseURI(string calldata next) external onlyRole(METADATA_ADMIN_ROLE) {
        if (_metadataFrozen) revert MetadataFrozen();

        string memory previous = _baseTokenURI;
        _baseTokenURI = next;
        emit BaseURIUpdated(previous, next);
    }

    /// @notice Replace the collection metadata URI.
    /// @dev Same timelocked, freeze-respecting rules as `setBaseURI`.
    /// @param next The new contract URI.
    function setContractURI(string calldata next) external onlyRole(METADATA_ADMIN_ROLE) {
        if (_metadataFrozen) revert MetadataFrozen();

        string memory previous = _collectionURI;
        _collectionURI = next;
        emit ContractURIUpdated(previous, next);
    }

    /// @notice Permanently lock both metadata URIs.
    /// @dev IRREVERSIBLE. There is no unfreeze function, and adding one would defeat the only
    ///      guarantee this call provides: that holders can verify, on chain and forever, that nobody
    ///      — including governance — can repoint their token's metadata afterwards. Calling it twice
    ///      reverts, so a duplicated timelock execution cannot emit a second, misleading
    ///      `MetadataFrozenForever`.
    function freezeMetadata() external onlyRole(METADATA_ADMIN_ROLE) {
        if (_metadataFrozen) revert MetadataFrozen();

        _metadataFrozen = true;
        emit MetadataFrozenForever();
    }

    /// @notice Metadata document for one token.
    /// @dev Built as `baseTokenURI + tokenId` by the inherited ERC-721 implementation. Per-token URIs
    ///      are deliberately not stored: thousands of individually settable strings would be an
    ///      admin-controlled surface with no benefit, since the off-chain document is what actually
    ///      carries the provenance fields (inscription txid/index, root key, token id, tour state,
    ///      and the disclaimer that this contract neither owns nor custodies the Bitcoin
    ///      inscription).
    /// @param tokenId Token to describe.
    /// @return The metadata URI for `tokenId`.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return super.tokenURI(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              MINT PAUSING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPups
    function mintingPaused() external view returns (bool) {
        return _mintingPaused;
    }

    /// @notice Stop new mints. Affects nothing else.
    /// @dev Held by the guardian multisig so an incident response is fast. It cannot unpause, cannot
    ///      touch metadata, cannot move a token and cannot grant itself anything: `PAUSER_ROLE`'s
    ///      entire authority is this one boolean.
    function pauseMinting() external onlyRole(PAUSER_ROLE) {
        if (_mintingPaused) revert MintPauseUnchanged(true);

        _mintingPaused = true;
        emit MintingPauseUpdated(true);
    }

    /// @notice Allow mints again.
    /// @dev Gated on `DEFAULT_ADMIN_ROLE`, i.e. the timelock, not on `PAUSER_ROLE`. Pausing must be
    ///      fast; resuming risk-taking must be deliberate and publicly visible for the full timelock
    ///      delay. This asymmetry is why a compromised guardian can only cost liveness.
    function unpauseMinting() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_mintingPaused) revert MintPauseUnchanged(false);

        _mintingPaused = false;
        emit MintingPauseUpdated(false);
    }

    /*//////////////////////////////////////////////////////////////
                                 ERC-165
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC-165 interface detection.
    /// @dev Advertises ERC-721, ERC-721 Metadata, ERC-165, AccessControl and ERC-4907.
    ///      It deliberately does NOT advertise `ERC721Enumerable` (`0x780e9d63`), and the contract
    ///      does not inherit it: `totalSupply` / `tokenByIndex` add an O(n) write to every transfer
    ///      to serve data an indexer already has, and — worse — advertising an interface whose
    ///      functions do not exist would make a marketplace call into a revert. The unit suite
    ///      asserts both halves of that claim.
    /// @param interfaceId The ERC-165 identifier being queried.
    /// @return True if this contract implements `interfaceId`.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return interfaceId == type(IERC4907).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev OpenZeppelin 5.x routes every mint, transfer and burn through `_update`. The pre-v5
    ///      `_beforeTokenTransfer` hook does not exist in this version, so this is the only correct
    ///      place to clear ERC-4907 state.
    ///
    ///      The clear is conditioned on the owner ACTUALLY changing, for two reasons. A mint
    ///      (`previousOwner == address(0)`) must not emit a spurious `UpdateUser`, which would make
    ///      every mint look like a rental change to an indexer. And a self-transfer
    ///      (`previousOwner == to`) is not a change of custody, so silently cancelling a live rental
    ///      would be a surprising side effect the standard does not call for.
    ///
    ///      The second condition — that a user is actually recorded — keeps ordinary transfers of
    ///      never-rented tokens from emitting a no-op event. Note that an EXPIRED entitlement is
    ///      still cleared: leaving stale rental state attached to a token under new ownership would
    ///      be a trap for anyone reading `userExpires` directly.
    /// @param to Address receiving the token.
    /// @param tokenId Token being moved.
    /// @param auth Address whose authorization is being checked by the base implementation.
    /// @return previousOwner The owner before this update.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address previousOwner) {
        previousOwner = super._update(to, tokenId, auth);

        if (previousOwner != to && _userInfo[tokenId].user != address(0)) {
            delete _userInfo[tokenId];
            emit UpdateUser(tokenId, address(0), 0);
        }
    }

    /// @dev Prefix for `tokenURI`.
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @dev Existence check that does not depend on ownership.
    ///      Ids are assigned strictly sequentially from 1 and there is no burn, so "minted" is
    ///      exactly "1 <= tokenId < _nextTokenId". Deriving it arithmetically rather than reading
    ///      `_ownerOf` keeps the answer correct even for a token whose owner is momentarily being
    ///      rewritten inside `_update`.
    /// @param tokenId Token to check.
    function _requireKnown(uint256 tokenId) private view {
        if (tokenId == 0 || tokenId >= _nextTokenId) revert UnknownToken(tokenId);
    }
}
