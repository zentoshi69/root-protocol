// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IBitcoinAttestorRegistry} from "./interfaces/IBitcoinAttestorRegistry.sol";

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

    /// @notice Largest attestor set, bounding the cost of the oracle's O(n) signature walk.
    uint256 public constant MAX_ATTESTORS = 32;

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
    /// @param initialAttestors Genesis attestor addresses; must be 5..32 distinct nonzero addresses.
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

    /// @notice Add one attestor to the verifier set and bump the epoch.
    /// @dev Growing the set never endangers the threshold invariant (`threshold <= count` can only
    ///      become slacker), so only the upper bound is checked. The epoch still bumps: a new
    ///      operator must not be able to contribute to a quorum that was already partly gathered
    ///      under the previous membership.
    /// @param attestor Address to authorize. Must be nonzero and not already a member.
    function addAttestor(address attestor) external onlyRole(ATTESTOR_ADMIN_ROLE) {
        if (attestor == address(0)) revert ZeroAddress();

        uint256 nextCount = _attestorSet.length() + 1;
        if (nextCount > MAX_ATTESTORS) revert AttestorCountOutOfRange(nextCount);

        if (!_attestorSet.add(attestor)) revert DuplicateAttestor(attestor);

        (uint64 previousEpoch, uint64 newEpoch) = _bumpEpoch();
        emit AttestorAdded(attestor, previousEpoch, newEpoch);
    }

    /// @notice Remove one attestor from the verifier set and bump the epoch.
    /// @dev Two invariants are enforced on the POST-removal count, not the pre-removal one:
    ///      the set may not fall below `MIN_ATTESTORS`, and the standing threshold may not exceed
    ///      the remaining count. The second check is the important one — leaving
    ///      `threshold > count` would make quorum unreachable and permanently freeze every
    ///      settlement path in the protocol. Lower the threshold first, then remove.
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
    /// @dev Unbounded-looking but bounded by `MAX_ATTESTORS == 32`, so this is safe to call
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
