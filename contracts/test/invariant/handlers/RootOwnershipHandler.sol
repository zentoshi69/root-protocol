// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {PayoutVault} from "../../../src/PayoutVault.sol";
import {RootOwnershipRegistry} from "../../../src/RootOwnershipRegistry.sol";
import {PuppetHashing} from "../../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../../src/types/PuppetTypes.sol";

/// @title RootOwnershipHandler
/// @notice Bounded random driver for `RootOwnershipRegistry`'s stateful invariant campaign.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      WHY A HANDLER. Pointing the fuzzer straight at the registry would spend nearly every call
///      bouncing off `AccessControl` and off malformed-attestation guards, and the campaign would
///      prove only that the modifiers exist. This handler holds the privileged roles and keeps its
///      inputs inside the shapes the registry can actually accept, so most calls mutate state —
///      which is where the interesting orderings live.
///
///      IT HOLDS THE PRIVILEGED ROLES ON PURPOSE. `MINT_RECORDER_ROLE`, `PAUSER_ROLE` and
///      `DEFAULT_ADMIN_ROLE` on the registry, plus `CREDITOR_ROLE` on the vault. The invariants are
///      therefore asserted against a maximally-privileged adversary: "no admin path reassigns a
///      beneficiary" and "no admin path reduces a balance" are uninteresting claims if the fuzzer
///      never held the keys.
///
///      HONESTY NOTE. The oracle behind this campaign is `MockOwnershipOracle`, which performs no
///      signature recovery, no quorum counting and no membership checks. Nothing here is evidence
///      about quorum security. What the campaign does exercise is the registry's own state
///      machine: epoch ordering, activation and invalidation guards, height monotonicity, history
///      closure, and the fact that credited balances only ever grow.
///
///      NO WITHDRAWAL ACTION EXISTS, deliberately. With nothing in the campaign able to spend a
///      balance, "no actor's claimable ever decreased" becomes a flat, unconditional assertion
///      rather than one hedged by bookkeeping about who spent what.
contract RootOwnershipHandler is CommonBase, StdUtils {
    /*//////////////////////////////////////////////////////////////
                                FIXTURES
    //////////////////////////////////////////////////////////////*/

    RootOwnershipRegistry public immutable REGISTRY;
    PayoutVault public immutable VAULT;

    uint256 private constant ACTOR_COUNT = 4;
    uint256 private constant ROOT_COUNT = 3;

    address[] private _actors;
    bytes32[] private _rootKeys;
    bytes32[] private _rootTxids;
    uint32[] private _rootIndices;

    /// @dev Bumped on every call so no two attestations can collide on their digest.
    uint256 private _nonce;

    /*//////////////////////////////////////////////////////////////
                             GHOST ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Highest epoch ever observed per Root.
    mapping(bytes32 => uint64) public ghostEpoch;

    /// @notice Highest `verifiedBitcoinHeight` ever observed per Root.
    mapping(bytes32 => uint64) public ghostHeight;

    /// @notice Highest `claimable` ever observed per actor.
    mapping(address => uint256) public ghostClaimable;

    /// @notice Number of accepted `recordMintOwnership` calls per Root. Must never exceed one.
    mapping(bytes32 => uint256) public ghostMintRecordings;

    /// @notice Set if any Root's epoch was ever observed to go backwards.
    bool public sawEpochRegression;

    /// @notice Set if any Root's recorded Bitcoin height was ever observed to go backwards.
    bool public sawHeightRegression;

    /// @notice Set if any actor's claimable balance was ever observed to fall.
    /// @dev The campaign has no withdrawal action, so this can only trip on a bug.
    bool public sawClaimableDecrease;

    /// @notice Set if an active Root was ever observed with a zero beneficiary.
    bool public sawActiveWithoutBeneficiary;

    /// @notice Per-action counters, so coverage can be asserted rather than assumed.
    mapping(bytes32 => uint256) public calls;

    constructor(RootOwnershipRegistry registry_, PayoutVault vault_) {
        REGISTRY = registry_;
        VAULT = vault_;

        for (uint256 i = 0; i < ACTOR_COUNT; i++) {
            _actors.push(address(uint160(uint256(keccak256(abi.encode("root-owner-actor", i))))));
        }
        for (uint256 i = 0; i < ROOT_COUNT; i++) {
            bytes32 txid = keccak256(abi.encode("FIXTURE-NOT-REAL-inscription", i));
            // casting to `uint32` is safe because `i < ROOT_COUNT`, which is 3.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint32 index = uint32(i);
            _rootTxids.push(txid);
            _rootIndices.push(index);
            _rootKeys.push(PuppetHashing.rootKey(txid, index));
        }

        vm.deal(address(this), 10_000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice The actor set the invariants iterate over.
    function actors() external view returns (address[] memory) {
        return _actors;
    }

    /// @notice The Root keys the invariants iterate over.
    function rootKeys() external view returns (bytes32[] memory) {
        return _rootKeys;
    }

    /*//////////////////////////////////////////////////////////////
                                ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Record a first ownership epoch as the escrow would.
    /// @param rootSeed Selects the Root.
    /// @param actorSeed Selects the beneficiary.
    /// @param heightDelta Drives the Bitcoin height, sometimes backwards to exercise the guard.
    function recordMint(uint256 rootSeed, uint256 actorSeed, uint64 heightDelta) external {
        _nonce++;
        uint256 r = _rootIndex(rootSeed);
        bytes32 key = _rootKeys[r];
        address beneficiary = _actor(actorSeed);
        uint64 height = _height(key, heightDelta);

        try REGISTRY.recordMintOwnership(
            key,
            beneficiary,
            _freshOutpoint(key),
            keccak256(abi.encode("FIXTURE-script", beneficiary)),
            keccak256(abi.encode("FIXTURE-mint-digest", _nonce)),
            keccak256(abi.encode("FIXTURE-bip322", _nonce)),
            keccak256(abi.encode("FIXTURE-block", height)),
            height
        ) {
            calls["recordMint.ok"]++;
            ghostMintRecordings[key]++;
        } catch {
            calls["recordMint.revert"]++;
        }

        _sync(key);
    }

    /// @notice Permissionlessly bind a new owner with a fresh (or occasionally repeated) outpoint.
    /// @param rootSeed Selects the Root.
    /// @param actorSeed Selects the beneficiary.
    /// @param heightDelta Drives the Bitcoin height.
    /// @param reuseOutpoint When true, replays the currently recorded outpoint so the
    ///        `UnchangedOutpoint` guard is exercised as often as the happy path.
    function bind(uint256 rootSeed, uint256 actorSeed, uint64 heightDelta, bool reuseOutpoint) external {
        _nonce++;
        uint256 r = _rootIndex(rootSeed);
        bytes32 key = _rootKeys[r];
        address beneficiary = _actor(actorSeed);
        uint64 height = _height(key, heightDelta);

        bytes32 outpoint = reuseOutpoint ? REGISTRY.currentState(key).currentOutpointHash : _freshOutpoint(key);

        PuppetTypes.OwnershipAttestation memory a;
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND);
        a.rootTxid = _rootTxids[r];
        a.rootIndex = _rootIndices[r];
        a.contextId = key;
        a.currentOutpointHash = outpoint;
        a.ownerScriptHash = keccak256(abi.encode("FIXTURE-script", beneficiary));
        a.bip322ProofHash = keccak256(abi.encode("FIXTURE-bip322", _nonce));
        a.payoutMode = uint8(PuppetTypes.PayoutMode.EVM);
        a.evmPayout = beneficiary;
        a.bitcoinBlockHash = keccak256(abi.encode("FIXTURE-block", height));
        a.bitcoinHeight = height;
        a.authorizationId = keccak256(abi.encode("FIXTURE-auth", _nonce));
        a.deadline = uint64(block.timestamp + 1 days);
        a.attestorEpoch = 1;
        a.policyVersion = 1;

        try REGISTRY.bindRootOwner(a, new bytes[](3), new bytes32[](0)) {
            calls["bind.ok"]++;
        } catch {
            calls["bind.revert"]++;
        }

        _sync(key);
    }

    /// @notice Permissionlessly close an epoch with a spend attestation.
    /// @param rootSeed Selects the Root.
    /// @param heightDelta Drives the Bitcoin height.
    /// @param wrongOutpoint When true, attests a spend of an outpoint the registry does not record.
    function invalidate(uint256 rootSeed, uint64 heightDelta, bool wrongOutpoint) external {
        _nonce++;
        uint256 r = _rootIndex(rootSeed);
        bytes32 key = _rootKeys[r];
        uint64 height = _height(key, heightDelta);

        bytes32 previous = wrongOutpoint
            ? keccak256(abi.encode("FIXTURE-unrelated-outpoint", _nonce))
            : REGISTRY.currentState(key).currentOutpointHash;

        PuppetTypes.RootSpendAttestation memory a;
        a.rootTxid = _rootTxids[r];
        a.rootIndex = _rootIndices[r];
        a.previousOutpointHash = previous;
        a.spendingTxid = keccak256(abi.encode("FIXTURE-spend", _nonce));
        a.bitcoinBlockHash = keccak256(abi.encode("FIXTURE-block", height));
        a.bitcoinHeight = height;
        a.authorizationId = keccak256(abi.encode("FIXTURE-auth", _nonce));
        a.deadline = uint64(block.timestamp + 1 days);
        a.attestorEpoch = 1;
        a.policyVersion = 1;

        try REGISTRY.invalidateRoot(a, new bytes[](3), new bytes32[](0)) {
            calls["invalidate.ok"]++;
        } catch {
            calls["invalidate.revert"]++;
        }

        _sync(key);
    }

    /// @notice Park recurring value in a Root's pending bucket, as `FeeRouter` would.
    /// @param rootSeed Selects the Root.
    /// @param amount Wei to park, bounded to a sane range.
    function creditRootPending(uint256 rootSeed, uint256 amount) external {
        _nonce++;
        bytes32 key = _rootKeys[_rootIndex(rootSeed)];
        amount = bound(amount, 1 wei, 10 ether);
        if (address(this).balance < amount) return;

        try VAULT.creditRoot{value: amount}(key) {
            calls["creditRootPending.ok"]++;
        } catch {
            calls["creditRootPending.revert"]++;
        }

        _sync(key);
    }

    /// @notice Credit an actor directly, as `FeeRouter` would for an active Root.
    /// @param actorSeed Selects the beneficiary.
    /// @param amount Wei to credit, bounded to a sane range.
    function creditActor(uint256 actorSeed, uint256 amount) external {
        _nonce++;
        address beneficiary = _actor(actorSeed);
        amount = bound(amount, 1 wei, 10 ether);
        if (address(this).balance < amount) return;

        try VAULT.credit{value: amount}(beneficiary) {
            calls["creditActor.ok"]++;
        } catch {
            calls["creditActor.revert"]++;
        }

        _syncClaimable();
    }

    /// @notice Forward a Root's pending bucket to its recorded, active beneficiary.
    /// @param rootSeed Selects the Root.
    function releasePending(uint256 rootSeed) external {
        _nonce++;
        bytes32 key = _rootKeys[_rootIndex(rootSeed)];

        try REGISTRY.releasePendingRootCredit(key) {
            calls["releasePending.ok"]++;
        } catch {
            calls["releasePending.revert"]++;
        }

        _sync(key);
    }

    /// @notice Pause or unpause the registry, so every other action runs on both sides of a pause.
    function togglePause() external {
        _nonce++;
        if (REGISTRY.paused()) {
            REGISTRY.unpauseActivations();
            calls["unpause"]++;
        } else {
            REGISTRY.pauseActivations();
            calls["pause"]++;
        }
        _syncClaimable();
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _rootIndex(uint256 seed) private pure returns (uint256) {
        return seed % ROOT_COUNT;
    }

    function _actor(uint256 seed) private view returns (address) {
        return _actors[seed % ACTOR_COUNT];
    }

    /// @dev Heights walk forward most of the time and occasionally step backwards, so both the
    ///      accepted and the `StaleBitcoinHeight`-rejected branches get real traffic.
    function _height(bytes32 key, uint64 delta) private view returns (uint64) {
        uint64 current = ghostHeight[key];
        if (delta % 7 == 0 && current > 32) return current - 16;
        return current + uint64(bound(uint256(delta), 0, 500)) + 1;
    }

    function _freshOutpoint(bytes32 key) private view returns (bytes32) {
        // casting to `uint32` is safe because the operand is `_nonce % 8`, i.e. 0..7.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 vout = uint32(_nonce % 8);
        return PuppetHashing.outpointHash(keccak256(abi.encode("FIXTURE-outpoint", key, _nonce)), vout);
    }

    /// @dev Re-reads the registry after every action and trips a ghost flag on any regression.
    ///      Checking after EVERY call, rather than once at the end of a run, is what makes the
    ///      monotonicity claims meaningful.
    function _sync(bytes32 key) private {
        PuppetTypes.RootState memory s = REGISTRY.currentState(key);

        if (s.epoch < ghostEpoch[key]) sawEpochRegression = true;
        ghostEpoch[key] = s.epoch;

        if (s.verifiedBitcoinHeight < ghostHeight[key]) sawHeightRegression = true;
        ghostHeight[key] = s.verifiedBitcoinHeight;

        if (s.active && s.beneficiary == address(0)) sawActiveWithoutBeneficiary = true;

        _syncClaimable();
    }

    function _syncClaimable() private {
        for (uint256 i = 0; i < _actors.length; i++) {
            uint256 current = VAULT.claimable(_actors[i]);
            if (current < ghostClaimable[_actors[i]]) sawClaimableDecrease = true;
            ghostClaimable[_actors[i]] = current;
        }
    }
}
