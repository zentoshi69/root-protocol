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

// lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/structs/EnumerableSet.sol)
// This file was procedurally generated from scripts/generate/templates/EnumerableSet.js.

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```solidity
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 *
 * [WARNING]
 * ====
 * Trying to delete such a structure from storage will likely result in data corruption, rendering the structure
 * unusable.
 * See https://github.com/ethereum/solidity/pull/11843[ethereum/solidity#11843] for more info.
 *
 * In order to clean an EnumerableSet, you can either remove all elements one by one or create a fresh instance using an
 * array of EnumerableSet.
 * ====
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;
        // Position is the index of the value in the `values` array plus 1.
        // Position 0 is used to mean a value is not in the set.
        mapping(bytes32 value => uint256) _positions;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._positions[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We cache the value's position to prevent multiple reads from the same storage slot
        uint256 position = set._positions[value];

        if (position != 0) {
            // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 valueIndex = position - 1;
            uint256 lastIndex = set._values.length - 1;

            if (valueIndex != lastIndex) {
                bytes32 lastValue = set._values[lastIndex];

                // Move the lastValue to the index where the value to delete is
                set._values[valueIndex] = lastValue;
                // Update the tracked position of the lastValue (that was just moved)
                set._positions[lastValue] = position;
            }

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the tracked position for the deleted slot
            delete set._positions[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._positions[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        return set._values[index];
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function _values(Set storage set) private view returns (bytes32[] memory) {
        return set._values;
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(Bytes32Set storage set) internal view returns (bytes32[] memory) {
        bytes32[] memory store = _values(set._inner);
        bytes32[] memory result;

        assembly ("memory-safe") {
            result := store
        }

        return result;
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(AddressSet storage set) internal view returns (address[] memory) {
        bytes32[] memory store = _values(set._inner);
        address[] memory result;

        assembly ("memory-safe") {
            result := store
        }

        return result;
    }

    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(UintSet storage set) internal view returns (uint256[] memory) {
        bytes32[] memory store = _values(set._inner);
        uint256[] memory result;

        assembly ("memory-safe") {
            result := store
        }

        return result;
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
/// @notice Membership, quorum threshold, epoch and policy version for the fixed five-member Bitcoin verifier set.
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

    /// @notice Current number of authorized attestors; always exactly five after construction.
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

// src/BitcoinAttestorRegistry.sol

/// @title BitcoinAttestorRegistry
/// @notice Membership, quorum threshold, epoch and policy version for the protocol's Bitcoin
///         verifier set.
/// @dev TRUST BOUNDARY — READ THIS BEFORE READING ANY OTHER LINE IN THIS FILE:
///      This contract does not verify anything about Bitcoin. It records WHICH EVM keys the
///      protocol's governance has designated as independent verifier operators, and HOW MANY of
///      them must agree before `BitcoinOwnershipOracle` will treat a Bitcoin fact as settled.
///      Every Bitcoin fact in this system is an assertion by a 3-of-5 quorum of those operators.
///      This is an attested settlement system, not a trustless bridge, and no amount of care in
///      this file changes that.
///
///      DESIGN: EPOCH IS THE KILL SWITCH.
///      `attestorEpoch` is folded into every attestation digest (see
///      `PuppetTypes.OwnershipAttestation.attestorEpoch`). Bumping it therefore invalidates every
///      signature that is in flight at that instant, atomically and without any per-signature
///      bookkeeping. That is the whole reason the counter exists: a set rotation must never leave
///      a window in which a just-removed operator still counts toward quorum, and a threshold
///      raise must never be satisfiable by signatures gathered under the lower threshold.
///
///      DESIGN DECISION — POLICY VERSION ALSO BUMPS THE EPOCH.
///      The specification allowed either "bump the epoch" or "emit a separate event only". This
///      contract bumps. `policyVersion` says which verification rules (confirmation depth, ord
///      index semantics, reorg handling) an operator must have been running when it signed. If a
///      policy change did not move the epoch, signatures produced under the OLD policy would stay
///      live for as long as their deadlines allowed — which is exactly the window a policy change
///      is normally made to close. Bumping costs one storage word per change and removes the
///      window entirely. The cost is that a policy change also invalidates in-flight ownership
///      proofs; that is deliberate, and callers simply re-request attestations.
///
///      DESIGN DECISION — NO-OP MUTATIONS REVERT.
///      `setThreshold` and `setPolicyVersion` reject a write of the value already stored. A
///      timelock proposal that is accidentally executed twice would otherwise silently bump the
///      epoch a second time and kill every in-flight attestation for no governance reason: a
///      liveness weapon disguised as an idempotent setter. Governance that genuinely wants to
///      invalidate in-flight signatures must express that as a real change to the set.
///
///      NON-UPGRADEABLE by construction: no proxy, no initializer, no delegatecall, no
///      `selfdestruct`, and no admin path that can move or seize user value — this contract holds
///      no value at all.
contract BitcoinAttestorRegistry is IBitcoinAttestorRegistry, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role permitted to mutate membership, threshold and policy version.
    /// @dev Least privilege: `DEFAULT_ADMIN_ROLE` is deliberately NOT a mutator here. It only
    ///      grants and revokes roles, so the deployment can hand `DEFAULT_ADMIN_ROLE` to a
    ///      `TimelockController` under multisig control and, later, hand day-to-day rotation to a
    ///      different (still timelocked) governance address without ever widening role
    ///      administration. Both roles are granted to `admin` at construction so a single
    ///      timelock deployment works out of the box.
    bytes32 public constant ATTESTOR_ADMIN_ROLE = keccak256("ATTESTOR_ADMIN_ROLE");

    /*//////////////////////////////////////////////////////////////
                          PRODUCTION CONSTRAINTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Smallest attestor set the protocol will ever operate with.
    /// @dev Five is the "3-of-5" shape the protocol is specified around: it tolerates two
    ///      simultaneously unavailable operators without losing liveness, and it means no two
    ///      operators can settle a Bitcoin fact on their own. Never lower this for a test — use
    ///      `test/mocks/MockAttestorRegistry.sol`, which exists precisely so production
    ///      constraints never have to be weakened.
    uint256 public constant MIN_ATTESTORS = 5;

    /// @notice Largest attestor set.
    /// @dev Equal to `MIN_ATTESTORS` on purpose: the protocol's claimed trust shape is exactly
    ///      five independent operators. Governance rotates members atomically with
    ///      `replaceAttestor`; it cannot dilute a three-signature quorum into 3-of-N.
    uint256 public constant MAX_ATTESTORS = 5;

    /// @notice Smallest quorum threshold the protocol will ever operate with.
    /// @dev Three signatures means a single compromised operator, and any pair of them, is
    ///      insufficient to assert a Bitcoin fact.
    uint8 public constant MIN_THRESHOLD = 3;

    /*//////////////////////////////////////////////////////////////
                              EXTRA ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when `attestorAt` is called with an index past the end of the set.
    /// @param index The requested index.
    /// @param count The current attestor count.
    error AttestorIndexOutOfRange(uint256 index, uint256 count);

    /// @notice Thrown when `setThreshold` is asked to write the value already stored.
    /// @param currentThreshold The stored threshold.
    error ThresholdUnchanged(uint8 currentThreshold);

    /// @notice Thrown when `setPolicyVersion` is asked to write the value already stored.
    /// @param currentVersion The stored policy version.
    error PolicyVersionUnchanged(uint32 currentVersion);

    /*//////////////////////////////////////////////////////////////
                              EXTRA EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, with the registry's genesis configuration.
    /// @dev Indexers reconstruct membership purely from `AttestorAdded` / `AttestorRemoved` /
    ///      `AttestorReplaced`, so the constructor also emits one `AttestorAdded` per initial
    ///      member with `previousEpoch == 0`. Epoch 0 is the "no set existed" sentinel and is
    ///      never observable through `attestorEpoch()`, which starts at 1.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `ATTESTOR_ADMIN_ROLE`.
    /// @param attestorCount Size of the genesis attestor set.
    /// @param threshold Genesis quorum threshold.
    /// @param attestorEpoch Genesis epoch, always 1.
    /// @param policyVersion Genesis verification policy version.
    event RegistryInitialized(
        address indexed admin, uint256 attestorCount, uint8 threshold, uint64 attestorEpoch, uint32 policyVersion
    );

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev The authoritative membership set. `EnumerableSet` gives O(1) membership and
    ///      duplicate rejection for free, which is what makes the duplicate checks below cheap
    ///      enough to be unconditional.
    EnumerableSet.AddressSet private _attestorSet;

    /// @dev Packed into a single slot with `_threshold` and `_policyVersion`; `quorumContext()`
    ///      is on the oracle's hot path and reads all three in one `SLOAD`.
    uint64 private _attestorEpoch;

    uint8 private _threshold;

    uint32 private _policyVersion;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the registry with its genesis verifier set.
    /// @dev `admin` MUST be a `TimelockController` (itself governed by a multisig) in production.
    ///      Nothing in this contract can enforce that, so the deployment script is responsible for
    ///      granting the roles to the timelock and revoking them from the deployer in the same
    ///      transaction batch; `test_TimelockHandoverFullyRevokesDeployer` in the unit suite
    ///      proves the revocation path leaves the deployer with zero authority.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE` and `ATTESTOR_ADMIN_ROLE`.
    /// @param initialAttestors Exactly five distinct nonzero genesis attestor addresses.
    /// @param initialThreshold Genesis quorum threshold; must be 3..`initialAttestors.length`.
    /// @param initialPolicyVersion Genesis verification policy version; must be nonzero.
    constructor(address admin, address[] memory initialAttestors, uint8 initialThreshold, uint32 initialPolicyVersion) {
        if (admin == address(0)) revert ZeroAddress();
        if (initialPolicyVersion == 0) revert ZeroPolicyVersion();

        uint256 count = initialAttestors.length;
        if (count < MIN_ATTESTORS || count > MAX_ATTESTORS) revert AttestorCountOutOfRange(count);
        if (initialThreshold < MIN_THRESHOLD || uint256(initialThreshold) > count) {
            revert ThresholdOutOfRange(initialThreshold, count);
        }

        // Epoch is set before the member events are emitted so every event in this transaction
        // reports the same, final, genesis epoch of 1.
        _attestorEpoch = 1;
        _threshold = initialThreshold;
        _policyVersion = initialPolicyVersion;

        for (uint256 i = 0; i < count; i++) {
            address attestor = initialAttestors[i];
            if (attestor == address(0)) revert ZeroAddress();
            // `add` returns false for an address already in the set, which is the duplicate check.
            if (!_attestorSet.add(attestor)) revert DuplicateAttestor(attestor);
            emit AttestorAdded(attestor, 0, 1);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ATTESTOR_ADMIN_ROLE, admin);

        emit RegistryInitialized(admin, count, initialThreshold, 1, initialPolicyVersion);
    }

    /*//////////////////////////////////////////////////////////////
                            MEMBERSHIP CHANGES
    //////////////////////////////////////////////////////////////*/

    /// @notice Retained for ABI clarity but unreachable under the fixed five-operator trust model.
    /// @dev `MAX_ATTESTORS == 5`, so this always reverts for a correctly initialized registry.
    ///      Membership changes must use `replaceAttestor`, which preserves the 3-of-5 shape.
    /// @param attestor Address to authorize. Must be nonzero and not already a member.
    function addAttestor(address attestor) external onlyRole(ATTESTOR_ADMIN_ROLE) {
        if (attestor == address(0)) revert ZeroAddress();
        if (_attestorSet.contains(attestor)) revert DuplicateAttestor(attestor);

        uint256 nextCount = _attestorSet.length() + 1;
        if (nextCount > MAX_ATTESTORS) revert AttestorCountOutOfRange(nextCount);

        _attestorSet.add(attestor);

        (uint64 previousEpoch, uint64 newEpoch) = _bumpEpoch();
        emit AttestorAdded(attestor, previousEpoch, newEpoch);
    }

    /// @notice Retained for ABI clarity but unreachable under the fixed five-operator trust model.
    /// @dev `MIN_ATTESTORS == 5`, so this always reverts and rolls back. Use `replaceAttestor`.
    /// @param attestor Address to deauthorize. Must currently be a member.
    function removeAttestor(address attestor) external onlyRole(ATTESTOR_ADMIN_ROLE) {
        // `remove` returns false for an address that was not in the set.
        if (!_attestorSet.remove(attestor)) revert UnknownAttestor(attestor);

        uint256 newCount = _attestorSet.length();
        if (newCount < MIN_ATTESTORS) revert AttestorCountOutOfRange(newCount);
        if (uint256(_threshold) > newCount) revert ThresholdOutOfRange(_threshold, newCount);

        (uint64 previousEpoch, uint64 newEpoch) = _bumpEpoch();
        emit AttestorRemoved(attestor, previousEpoch, newEpoch);
    }

    /// @notice Atomically swap one attestor for another, bumping the epoch exactly once.
    /// @dev This exists so a compromised-key rotation never has to be expressed as
    ///      remove-then-add. Two separate calls would bump the epoch twice (invalidating in-flight
    ///      signatures for longer than necessary) and, at a 5-member set, the intermediate state
    ///      would violate `MIN_ATTESTORS` and revert outright. Here the count is unchanged
    ///      throughout, so `MIN_ATTESTORS`, `MAX_ATTESTORS` and `threshold <= count` all hold
    ///      before, during and after with no re-check needed.
    /// @param previous Current member to deauthorize.
    /// @param replacement New member to authorize. Must be nonzero and not already a member.
    function replaceAttestor(address previous, address replacement) external onlyRole(ATTESTOR_ADMIN_ROLE) {
        if (replacement == address(0)) revert ZeroAddress();
        if (!_attestorSet.contains(previous)) revert UnknownAttestor(previous);
        // Also catches `previous == replacement`, which would otherwise be a no-op epoch bump.
        if (_attestorSet.contains(replacement)) revert DuplicateAttestor(replacement);

        _attestorSet.remove(previous);
        _attestorSet.add(replacement);

        (uint64 previousEpoch, uint64 newEpoch) = _bumpEpoch();
        emit AttestorReplaced(previous, replacement, previousEpoch, newEpoch);
    }

    /*//////////////////////////////////////////////////////////////
                            POLICY CHANGES
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the number of distinct attestor signatures required for quorum.
    /// @dev Bounded below by `MIN_THRESHOLD` so governance can never quietly weaken the security
    ///      model to 1-of-n, and above by the current count so quorum always stays reachable.
    ///      Raising the threshold must invalidate signatures already gathered under the old,
    ///      lower one — hence the epoch bump.
    /// @param newThreshold The new quorum threshold; must be 3..`attestorCount()` and different
    ///        from the current value.
    function setThreshold(uint8 newThreshold) external onlyRole(ATTESTOR_ADMIN_ROLE) {
        uint256 count = _attestorSet.length();
        if (newThreshold < MIN_THRESHOLD || uint256(newThreshold) > count) {
            revert ThresholdOutOfRange(newThreshold, count);
        }

        uint8 previousThreshold = _threshold;
        if (newThreshold == previousThreshold) revert ThresholdUnchanged(previousThreshold);

        _threshold = newThreshold;

        (uint64 previousEpoch, uint64 newEpoch) = _bumpEpoch();
        emit ThresholdUpdated(previousThreshold, newThreshold, previousEpoch, newEpoch);
    }

    /// @notice Set the verification policy version attestors must be running.
    /// @dev The value is NOT required to increase. A bad policy rollout must be revertible, and
    ///      rolling back is replay-safe here precisely because the epoch bumps on every change:
    ///      an attestation signed under the earlier instance of version N carries the earlier
    ///      epoch and can never be replayed against the restored version N.
    /// @param newVersion The new policy version; must be nonzero and different from the current
    ///        value.
    function setPolicyVersion(uint32 newVersion) external onlyRole(ATTESTOR_ADMIN_ROLE) {
        if (newVersion == 0) revert ZeroPolicyVersion();

        uint32 previousVersion = _policyVersion;
        if (newVersion == previousVersion) revert PolicyVersionUnchanged(previousVersion);

        _policyVersion = newVersion;

        (uint64 previousEpoch, uint64 newEpoch) = _bumpEpoch();
        emit PolicyVersionUpdated(previousVersion, newVersion, previousEpoch, newEpoch);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBitcoinAttestorRegistry
    function isAttestor(address account) external view returns (bool) {
        return _attestorSet.contains(account);
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    function attestorCount() external view returns (uint256) {
        return _attestorSet.length();
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    /// @dev Reverts with a named error rather than an `EnumerableSet` array panic, so an
    ///      off-by-one in a consumer surfaces as a readable failure.
    function attestorAt(uint256 index) external view returns (address) {
        uint256 count = _attestorSet.length();
        if (index >= count) revert AttestorIndexOutOfRange(index, count);
        return _attestorSet.at(index);
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    /// @dev Unbounded-looking but bounded by `MAX_ATTESTORS == 5`, so this is safe to call
    ///      on-chain as well as from `eth_call`.
    function attestors() external view returns (address[] memory) {
        return _attestorSet.values();
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    function threshold() external view returns (uint8) {
        return _threshold;
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    function attestorEpoch() external view returns (uint64) {
        return _attestorEpoch;
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    function policyVersion() external view returns (uint32) {
        return _policyVersion;
    }

    /// @inheritdoc IBitcoinAttestorRegistry
    /// @dev All three values live in one storage slot, so the oracle reads its entire quorum
    ///      context in a single `SLOAD` and can never observe a torn combination of them.
    function quorumContext() external view returns (uint8 currentThreshold, uint64 epoch, uint32 policy) {
        return (_threshold, _attestorEpoch, _policyVersion);
    }

    /// @notice ERC-165 support, extended with this registry's own interface id.
    /// @param interfaceId The interface identifier being queried.
    /// @return True if the interface is supported.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IBitcoinAttestorRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Single place the epoch is ever written, so "exactly one bump per mutation" is a
    ///      property of the call graph rather than of five separate correct implementations.
    ///      Left checked rather than `unchecked`: at one mutation per block, `uint64` overflow is
    ///      ~5.8e11 years away, and clarity in a security-critical counter beats ~20 gas.
    function _bumpEpoch() private returns (uint64 previousEpoch, uint64 newEpoch) {
        previousEpoch = _attestorEpoch;
        newEpoch = previousEpoch + 1;
        _attestorEpoch = newEpoch;
    }
}
