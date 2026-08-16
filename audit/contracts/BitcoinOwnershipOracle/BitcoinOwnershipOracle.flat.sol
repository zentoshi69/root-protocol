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

// lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/cryptography/ECDSA.sol)

/**
 * @dev Elliptic Curve Digital Signature Algorithm (ECDSA) operations.
 *
 * These functions can be used to verify that a message was signed by the holder
 * of the private keys of a given address.
 */
library ECDSA {
    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        InvalidSignatureS
    }

    /**
     * @dev The signature derives the `address(0)`.
     */
    error ECDSAInvalidSignature();

    /**
     * @dev The signature has an invalid length.
     */
    error ECDSAInvalidSignatureLength(uint256 length);

    /**
     * @dev The signature has an S value that is in the upper half order.
     */
    error ECDSAInvalidSignatureS(bytes32 s);

    /**
     * @dev Returns the address that signed a hashed message (`hash`) with `signature` or an error. This will not
     * return address(0) without also returning an error description. Errors are documented using an enum (error type)
     * and a bytes32 providing additional information about the error.
     *
     * If no error is returned, then the address can be used for verification purposes.
     *
     * The `ecrecover` EVM precompile allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {MessageHashUtils-toEthSignedMessageHash} on it.
     *
     * Documentation for signature generation:
     * - with https://web3js.readthedocs.io/en/v1.3.4/web3-eth-accounts.html#sign[Web3.js]
     * - with https://docs.ethers.io/v5/api/signer/#Signer-signMessage[ethers]
     */
    function tryRecover(
        bytes32 hash,
        bytes memory signature
    ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            // ecrecover takes the signature parameters, and the only way to get them
            // currently is to use assembly.
            assembly ("memory-safe") {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            return tryRecover(hash, v, r, s);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength, bytes32(signature.length));
        }
    }

    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * `signature`. This address can then be used for verification purposes.
     *
     * The `ecrecover` EVM precompile allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {MessageHashUtils-toEthSignedMessageHash} on it.
     */
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, signature);
        _throwError(error, errorArg);
        return recovered;
    }

    /**
     * @dev Overload of {ECDSA-tryRecover} that receives the `r` and `vs` short-signature fields separately.
     *
     * See https://eips.ethereum.org/EIPS/eip-2098[ERC-2098 short signatures]
     */
    function tryRecover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
        unchecked {
            bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            // We do not check for an overflow here since the shift operation results in 0 or 1.
            uint8 v = uint8((uint256(vs) >> 255) + 27);
            return tryRecover(hash, v, r, s);
        }
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `r and `vs` short-signature fields separately.
     */
    function recover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, r, vs);
        _throwError(error, errorArg);
        return recovered;
    }

    /**
     * @dev Overload of {ECDSA-tryRecover} that receives the `v`,
     * `r` and `s` signature fields separately.
     */
    function tryRecover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address recovered, RecoverError err, bytes32 errArg) {
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return (address(0), RecoverError.InvalidSignatureS, s);
        }

        // If the signature is valid (and not malleable), return the signer address
        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0)) {
            return (address(0), RecoverError.InvalidSignature, bytes32(0));
        }

        return (signer, RecoverError.NoError, bytes32(0));
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `v`,
     * `r` and `s` signature fields separately.
     */
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, v, r, s);
        _throwError(error, errorArg);
        return recovered;
    }

    /**
     * @dev Optionally reverts with the corresponding custom error according to the `error` argument provided.
     */
    function _throwError(RecoverError error, bytes32 errorArg) private pure {
        if (error == RecoverError.NoError) {
            return; // no error: do nothing
        } else if (error == RecoverError.InvalidSignature) {
            revert ECDSAInvalidSignature();
        } else if (error == RecoverError.InvalidSignatureLength) {
            revert ECDSAInvalidSignatureLength(uint256(errorArg));
        } else if (error == RecoverError.InvalidSignatureS) {
            revert ECDSAInvalidSignatureS(errorArg);
        }
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

// src/interfaces/IBitcoinAttestorRegistry.sol

/// @title IBitcoinAttestorRegistry
/// @notice Membership, quorum threshold, epoch and policy version for the Bitcoin verifier set.
/// @dev Any membership or threshold change bumps `attestorEpoch`, which instantly invalidates
///      every in-flight attestation signature. That is intentional: a rotating set must never
///      leave a window in which a removed operator still counts toward quorum.
interface IBitcoinAttestorRegistry {
    error ZeroAddress();
    error DuplicateAttestor(address attestor);
    error UnknownAttestor(address attestor);
    error AttestorCountOutOfRange(uint256 count);
    error ThresholdOutOfRange(uint8 threshold, uint256 count);
    error ZeroPolicyVersion();

    event AttestorAdded(address indexed attestor, uint64 previousEpoch, uint64 newEpoch);
    event AttestorRemoved(address indexed attestor, uint64 previousEpoch, uint64 newEpoch);
    event AttestorReplaced(
        address indexed previous, address indexed replacement, uint64 previousEpoch, uint64 newEpoch
    );
    event ThresholdUpdated(uint8 previousThreshold, uint8 newThreshold, uint64 previousEpoch, uint64 newEpoch);
    event PolicyVersionUpdated(uint32 previousVersion, uint32 newVersion, uint64 previousEpoch, uint64 newEpoch);

    /// @notice True if `account` is currently an authorized attestor.
    function isAttestor(address account) external view returns (bool);

    /// @notice Current number of authorized attestors.
    function attestorCount() external view returns (uint256);

    /// @notice Attestor at `index` in the enumerable set. Order is not stable across mutations.
    function attestorAt(uint256 index) external view returns (address);

    /// @notice Full attestor set snapshot.
    function attestors() external view returns (address[] memory);

    /// @notice Minimum number of distinct valid signatures required for quorum.
    function threshold() external view returns (uint8);

    /// @notice Monotonic epoch counter, incremented on every membership/threshold/policy change.
    function attestorEpoch() external view returns (uint64);

    /// @notice Verification policy version attestors must be running.
    function policyVersion() external view returns (uint32);

    /// @notice Convenience accessor used by the oracle's hot path.
    function quorumContext() external view returns (uint8 currentThreshold, uint64 epoch, uint32 policy);
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

// lib/openzeppelin-contracts/contracts/interfaces/IERC5267.sol

// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/IERC5267.sol)

interface IERC5267 {
    /**
     * @dev MAY be emitted to signal that the domain could have changed.
     */
    event EIP712DomainChanged();

    /**
     * @dev returns the fields and values that describe the domain separator used by this contract for EIP-712
     * signature.
     */
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
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

// lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC-1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     // Define the slot. Alternatively, use the SlotDerivation library to derive the slot.
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * TIP: Consider using this library along with {SlotDerivation}.
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct Int256Slot {
        int256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Int256Slot` with member `value` located at `slot`.
     */
    function getInt256Slot(bytes32 slot) internal pure returns (Int256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns a `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
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

// lib/openzeppelin-contracts/contracts/utils/ShortStrings.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/ShortStrings.sol)

// | string  | 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA   |
// | length  | 0x                                                              BB |
type ShortString is bytes32;

/**
 * @dev This library provides functions to convert short memory strings
 * into a `ShortString` type that can be used as an immutable variable.
 *
 * Strings of arbitrary length can be optimized using this library if
 * they are short enough (up to 31 bytes) by packing them with their
 * length (1 byte) in a single EVM word (32 bytes). Additionally, a
 * fallback mechanism can be used for every other case.
 *
 * Usage example:
 *
 * ```solidity
 * contract Named {
 *     using ShortStrings for *;
 *
 *     ShortString private immutable _name;
 *     string private _nameFallback;
 *
 *     constructor(string memory contractName) {
 *         _name = contractName.toShortStringWithFallback(_nameFallback);
 *     }
 *
 *     function name() external view returns (string memory) {
 *         return _name.toStringWithFallback(_nameFallback);
 *     }
 * }
 * ```
 */
library ShortStrings {
    // Used as an identifier for strings longer than 31 bytes.
    bytes32 private constant FALLBACK_SENTINEL = 0x00000000000000000000000000000000000000000000000000000000000000FF;

    error StringTooLong(string str);
    error InvalidShortString();

    /**
     * @dev Encode a string of at most 31 chars into a `ShortString`.
     *
     * This will trigger a `StringTooLong` error is the input string is too long.
     */
    function toShortString(string memory str) internal pure returns (ShortString) {
        bytes memory bstr = bytes(str);
        if (bstr.length > 31) {
            revert StringTooLong(str);
        }
        return ShortString.wrap(bytes32(uint256(bytes32(bstr)) | bstr.length));
    }

    /**
     * @dev Decode a `ShortString` back to a "normal" string.
     */
    function toString(ShortString sstr) internal pure returns (string memory) {
        uint256 len = byteLength(sstr);
        // using `new string(len)` would work locally but is not memory safe.
        string memory str = new string(32);
        assembly ("memory-safe") {
            mstore(str, len)
            mstore(add(str, 0x20), sstr)
        }
        return str;
    }

    /**
     * @dev Return the length of a `ShortString`.
     */
    function byteLength(ShortString sstr) internal pure returns (uint256) {
        uint256 result = uint256(ShortString.unwrap(sstr)) & 0xFF;
        if (result > 31) {
            revert InvalidShortString();
        }
        return result;
    }

    /**
     * @dev Encode a string into a `ShortString`, or write it to storage if it is too long.
     */
    function toShortStringWithFallback(string memory value, string storage store) internal returns (ShortString) {
        if (bytes(value).length < 32) {
            return toShortString(value);
        } else {
            StorageSlot.getStringSlot(store).value = value;
            return ShortString.wrap(FALLBACK_SENTINEL);
        }
    }

    /**
     * @dev Decode a string that was encoded to `ShortString` or written to storage using {setWithFallback}.
     */
    function toStringWithFallback(ShortString value, string storage store) internal pure returns (string memory) {
        if (ShortString.unwrap(value) != FALLBACK_SENTINEL) {
            return toString(value);
        } else {
            return store;
        }
    }

    /**
     * @dev Return the length of a string that was encoded to `ShortString` or written to storage using
     * {setWithFallback}.
     *
     * WARNING: This will return the "byte length" of the string. This may not reflect the actual length in terms of
     * actual characters as the UTF-8 encoding of a single character can span over multiple bytes.
     */
    function byteLengthWithFallback(ShortString value, string storage store) internal view returns (uint256) {
        if (ShortString.unwrap(value) != FALLBACK_SENTINEL) {
            return byteLength(value);
        } else {
            return bytes(store).length;
        }
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

// lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/cryptography/MessageHashUtils.sol)

/**
 * @dev Signature message hash utilities for producing digests to be consumed by {ECDSA} recovery or signing.
 *
 * The library provides methods for generating a hash of a message that conforms to the
 * https://eips.ethereum.org/EIPS/eip-191[ERC-191] and https://eips.ethereum.org/EIPS/eip-712[EIP 712]
 * specifications.
 */
library MessageHashUtils {
    /**
     * @dev Returns the keccak256 digest of an ERC-191 signed data with version
     * `0x45` (`personal_sign` messages).
     *
     * The digest is calculated by prefixing a bytes32 `messageHash` with
     * `"\x19Ethereum Signed Message:\n32"` and hashing the result. It corresponds with the
     * hash signed when using the https://eth.wiki/json-rpc/API#eth_sign[`eth_sign`] JSON-RPC method.
     *
     * NOTE: The `messageHash` parameter is intended to be the result of hashing a raw message with
     * keccak256, although any bytes32 value can be safely used because the final digest will
     * be re-hashed.
     *
     * See {ECDSA-recover}.
     */
    function toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32 digest) {
        assembly ("memory-safe") {
            mstore(0x00, "\x19Ethereum Signed Message:\n32") // 32 is the bytes-length of messageHash
            mstore(0x1c, messageHash) // 0x1c (28) is the length of the prefix
            digest := keccak256(0x00, 0x3c) // 0x3c is the length of the prefix (0x1c) + messageHash (0x20)
        }
    }

    /**
     * @dev Returns the keccak256 digest of an ERC-191 signed data with version
     * `0x45` (`personal_sign` messages).
     *
     * The digest is calculated by prefixing an arbitrary `message` with
     * `"\x19Ethereum Signed Message:\n" + len(message)` and hashing the result. It corresponds with the
     * hash signed when using the https://eth.wiki/json-rpc/API#eth_sign[`eth_sign`] JSON-RPC method.
     *
     * See {ECDSA-recover}.
     */
    function toEthSignedMessageHash(bytes memory message) internal pure returns (bytes32) {
        return
            keccak256(bytes.concat("\x19Ethereum Signed Message:\n", bytes(Strings.toString(message.length)), message));
    }

    /**
     * @dev Returns the keccak256 digest of an ERC-191 signed data with version
     * `0x00` (data with intended validator).
     *
     * The digest is calculated by prefixing an arbitrary `data` with `"\x19\x00"` and the intended
     * `validator` address. Then hashing the result.
     *
     * See {ECDSA-recover}.
     */
    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(hex"19_00", validator, data));
    }

    /**
     * @dev Returns the keccak256 digest of an EIP-712 typed data (ERC-191 version `0x01`).
     *
     * The digest is calculated from a `domainSeparator` and a `structHash`, by prefixing them with
     * `\x19\x01` and hashing the result. It corresponds to the hash signed by the
     * https://eips.ethereum.org/EIPS/eip-712[`eth_signTypedData`] JSON-RPC method as part of EIP-712.
     *
     * See {ECDSA-recover}.
     */
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 digest) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, hex"19_01")
            mstore(add(ptr, 0x02), domainSeparator)
            mstore(add(ptr, 0x22), structHash)
            digest := keccak256(ptr, 0x42)
        }
    }
}

// lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/cryptography/EIP712.sol)

/**
 * @dev https://eips.ethereum.org/EIPS/eip-712[EIP-712] is a standard for hashing and signing of typed structured data.
 *
 * The encoding scheme specified in the EIP requires a domain separator and a hash of the typed structured data, whose
 * encoding is very generic and therefore its implementation in Solidity is not feasible, thus this contract
 * does not implement the encoding itself. Protocols need to implement the type-specific encoding they need in order to
 * produce the hash of their typed data using a combination of `abi.encode` and `keccak256`.
 *
 * This contract implements the EIP-712 domain separator ({_domainSeparatorV4}) that is used as part of the encoding
 * scheme, and the final step of the encoding to obtain the message digest that is then signed via ECDSA
 * ({_hashTypedDataV4}).
 *
 * The implementation of the domain separator was designed to be as efficient as possible while still properly updating
 * the chain id to protect against replay attacks on an eventual fork of the chain.
 *
 * NOTE: This contract implements the version of the encoding known as "v4", as implemented by the JSON RPC method
 * https://docs.metamask.io/guide/signing-data.html[`eth_signTypedDataV4` in MetaMask].
 *
 * NOTE: In the upgradeable version of this contract, the cached values will correspond to the address, and the domain
 * separator of the implementation contract. This will cause the {_domainSeparatorV4} function to always rebuild the
 * separator from the immutable values, which is cheaper than accessing a cached version in cold storage.
 *
 * @custom:oz-upgrades-unsafe-allow state-variable-immutable
 */
abstract contract EIP712 is IERC5267 {
    using ShortStrings for *;

    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    bytes32 private immutable _cachedDomainSeparator;
    uint256 private immutable _cachedChainId;
    address private immutable _cachedThis;

    bytes32 private immutable _hashedName;
    bytes32 private immutable _hashedVersion;

    ShortString private immutable _name;
    ShortString private immutable _version;
    string private _nameFallback;
    string private _versionFallback;

    /**
     * @dev Initializes the domain separator and parameter caches.
     *
     * The meaning of `name` and `version` is specified in
     * https://eips.ethereum.org/EIPS/eip-712#definition-of-domainseparator[EIP-712]:
     *
     * - `name`: the user readable name of the signing domain, i.e. the name of the DApp or the protocol.
     * - `version`: the current major version of the signing domain.
     *
     * NOTE: These parameters cannot be changed except through a xref:learn::upgrading-smart-contracts.adoc[smart
     * contract upgrade].
     */
    constructor(string memory name, string memory version) {
        _name = name.toShortStringWithFallback(_nameFallback);
        _version = version.toShortStringWithFallback(_versionFallback);
        _hashedName = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));

        _cachedChainId = block.chainid;
        _cachedDomainSeparator = _buildDomainSeparator();
        _cachedThis = address(this);
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _cachedThis && block.chainid == _cachedChainId) {
            return _cachedDomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(this)));
    }

    /**
     * @dev Given an already https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct[hashed struct], this
     * function returns the hash of the fully encoded EIP712 message for this domain.
     *
     * This hash can be used together with {ECDSA-recover} to obtain the signer of a message. For example:
     *
     * ```solidity
     * bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
     *     keccak256("Mail(address to,string contents)"),
     *     mailTo,
     *     keccak256(bytes(mailContents))
     * )));
     * address signer = ECDSA.recover(digest, signature);
     * ```
     */
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
    }

    /**
     * @dev See {IERC-5267}.
     */
    function eip712Domain()
        public
        view
        virtual
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return (
            hex"0f", // 01111
            _EIP712Name(),
            _EIP712Version(),
            block.chainid,
            address(this),
            bytes32(0),
            new uint256[](0)
        );
    }

    /**
     * @dev The name parameter for the EIP712 domain.
     *
     * NOTE: By default this function reads _name which is an immutable value.
     * It only reads from storage if necessary (in case the value is too large to fit in a ShortString).
     */
    // solhint-disable-next-line func-name-mixedcase
    function _EIP712Name() internal view returns (string memory) {
        return _name.toStringWithFallback(_nameFallback);
    }

    /**
     * @dev The version parameter for the EIP712 domain.
     *
     * NOTE: By default this function reads _version which is an immutable value.
     * It only reads from storage if necessary (in case the value is too large to fit in a ShortString).
     */
    // solhint-disable-next-line func-name-mixedcase
    function _EIP712Version() internal view returns (string memory) {
        return _version.toStringWithFallback(_versionFallback);
    }
}

// src/BitcoinOwnershipOracle.sol

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
