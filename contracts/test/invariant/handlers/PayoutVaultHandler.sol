// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {PayoutVault} from "../../../src/PayoutVault.sol";

/// @title PayoutVaultHandler
/// @notice Bounded random driver for `PayoutVault`'s stateful invariant campaign.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      WHY A HANDLER AT ALL: pointing the fuzzer straight at the vault would spend almost every
///      call bouncing off `AccessControl` and `InsufficientClaimable`, and the campaign would prove
///      nothing but that the modifiers exist. This handler holds every role and bounds its inputs
///      so that the large majority of calls actually mutate state, which is where the interesting
///      sequences live.
///
///      IT HOLDS EVERY ROLE ON PURPOSE. `DEFAULT_ADMIN_ROLE`, `CREDITOR_ROLE`,
///      `ROOT_RELEASER_ROLE`, `EXCESS_SWEEPER_ROLE` and `PAUSER_ROLE` are all granted to this
///      contract. The campaign therefore asserts its invariants against a maximally-privileged
///      adversary, which is the only version of the claim worth making: "no admin path can reduce a
///      user's balance" is uninteresting if the fuzzer never had the admin keys.
///
///      MIRROR ACCOUNTING. Every successful mutation is replayed into a ghost mirror
///      (`ghostClaimable`, `ghostPending`, and the four flow totals). The invariants compare the
///      vault's own numbers against the mirror rather than against themselves, so a bug that
///      corrupts a bucket and `totalLiability` consistently is still caught.
///
///      HONESTY NOTE: `vm.deal` is used for two things — funding this handler, and simulating
///      forced ETH arriving at the vault. Forced ETH is the real mechanic (`selfdestruct`
///      beneficiary payments and block rewards cannot be refused); the cheat is only how the test
///      reproduces it without a self-destructing helper.
contract PayoutVaultHandler is CommonBase, StdUtils {
    /*//////////////////////////////////////////////////////////////
                                FIXTURES
    //////////////////////////////////////////////////////////////*/

    PayoutVault public immutable VAULT;

    /// @dev Where swept excess goes. Deliberately not an actor, so a sweep can never be confused
    ///      with a payout in the accounting.
    address payable public constant SWEEP_SINK = payable(address(0xBEEF));

    uint256 private constant ACTOR_COUNT = 4;
    uint256 private constant ROOT_COUNT = 3;

    /// @dev Actors are key-derived so the gasless path can be exercised with real signatures.
    uint256[] private _actorKeys;
    address[] private _actors;
    bytes32[] private _rootKeys;

    /*//////////////////////////////////////////////////////////////
                             GHOST ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Mirror of `PayoutVault.claimable`, maintained only from successful calls.
    mapping(address => uint256) public ghostClaimable;

    /// @notice Mirror of `PayoutVault.pendingByRoot`.
    mapping(bytes32 => uint256) public ghostPending;

    /// @notice Total wei ever credited in (both `credit`/`creditBatch` and `creditRoot`).
    uint256 public ghostCredited;

    /// @notice Total wei ever withdrawn out through any of the four withdrawal paths.
    uint256 public ghostWithdrawn;

    /// @notice Total wei ever force-sent to the vault with no accounting hook.
    uint256 public ghostForced;

    /// @notice Total wei ever removed by `sweepExcess`.
    uint256 public ghostSwept;

    /// @notice Set if any actor's claimable ever fell without that actor spending it themselves.
    /// @dev This is the "no admin path takes user funds" tripwire, evaluated after EVERY call
    ///      rather than only at the end of a run.
    bool public sawUnauthorizedDecrease;

    /// @notice Highest gasless nonce observed per actor, to prove nonces never go backwards.
    mapping(address => uint256) public ghostHighestNonce;

    /// @notice Set if a nonce was ever observed to decrease.
    bool public sawNonceRegression;

    /// @notice Set if `releaseRootCredit` returned an amount other than the mirrored bucket.
    bool public sawMirrorDesync;

    /// @notice Per-action call counters, printed by the invariant suite's summary.
    mapping(bytes32 => uint256) public calls;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    /// @param vault The vault under test.
    constructor(PayoutVault vault) {
        VAULT = vault;

        for (uint256 i = 0; i < ACTOR_COUNT; i++) {
            uint256 key = uint256(keccak256(abi.encode("HOODPUPS_VAULT_ACTOR", i)));
            // Fold into a valid secp256k1 range; `vm.sign` reverts opaquely otherwise.
            key = (key % (type(uint128).max)) + 1;
            _actorKeys.push(key);
            _actors.push(vm.addr(key));
        }

        for (uint256 i = 0; i < ROOT_COUNT; i++) {
            _rootKeys.push(keccak256(abi.encode("HOODPUPS_VAULT_ROOT", i)));
        }

        vm.deal(address(this), 1_000_000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Actor addresses the campaign credits and withdraws for.
    function actors() external view returns (address[] memory) {
        return _actors;
    }

    /// @notice Root keys the campaign credits and releases.
    function rootKeys() external view returns (bytes32[] memory) {
        return _rootKeys;
    }

    /// @notice Sum of the mirrored claimable balances.
    function ghostClaimableSum() external view returns (uint256 total) {
        for (uint256 i = 0; i < _actors.length; i++) {
            total += ghostClaimable[_actors[i]];
        }
    }

    /// @notice Sum of the mirrored pending-by-root balances.
    function ghostPendingSum() external view returns (uint256 total) {
        for (uint256 i = 0; i < _rootKeys.length; i++) {
            total += ghostPending[_rootKeys[i]];
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ACTIONS: CREDIT
    //////////////////////////////////////////////////////////////*/

    /// @notice Credit one actor.
    /// @param actorSeed Selects the beneficiary.
    /// @param amount Wei to credit; bounded to a sane range.
    function credit(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        amount = bound(amount, 1, 100 ether);
        _fund(amount);

        _before();
        try VAULT.credit{value: amount}(actor) {
            ghostClaimable[actor] += amount;
            ghostCredited += amount;
            calls["credit"]++;
        } catch {}
        _after(address(0));
    }

    /// @notice Credit a Root's pending bucket.
    /// @param rootSeed Selects the Root key.
    /// @param amount Wei to credit.
    function creditRoot(uint256 rootSeed, uint256 amount) external {
        bytes32 key = _root(rootSeed);
        amount = bound(amount, 1, 100 ether);
        _fund(amount);

        _before();
        try VAULT.creditRoot{value: amount}(key) {
            ghostPending[key] += amount;
            ghostCredited += amount;
            calls["creditRoot"]++;
        } catch {}
        _after(address(0));
    }

    /// @notice Credit two actors in one batch with an exact split.
    /// @param actorSeed Selects the first beneficiary; the second is the next actor along.
    /// @param amountA Wei for the first beneficiary.
    /// @param amountB Wei for the second beneficiary.
    function creditBatch(uint256 actorSeed, uint256 amountA, uint256 amountB) external {
        address first = _actor(actorSeed);
        address second = _actor(actorSeed + 1);
        if (first == second) return;

        amountA = bound(amountA, 1, 50 ether);
        amountB = bound(amountB, 1, 50 ether);
        uint256 total = amountA + amountB;
        _fund(total);

        address[] memory to = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        to[0] = first;
        to[1] = second;
        amounts[0] = amountA;
        amounts[1] = amountB;

        _before();
        try VAULT.creditBatch{value: total}(to, amounts) {
            ghostClaimable[first] += amountA;
            ghostClaimable[second] += amountB;
            ghostCredited += total;
            calls["creditBatch"]++;
        } catch {}
        _after(address(0));
    }

    /// @notice Release a Root's pending bucket to an actor.
    /// @param rootSeed Selects the Root key.
    /// @param actorSeed Selects the beneficiary.
    function releaseRoot(uint256 rootSeed, uint256 actorSeed) external {
        bytes32 key = _root(rootSeed);
        address actor = _actor(actorSeed);
        uint256 pending = ghostPending[key];

        _before();
        try VAULT.releaseRootCredit(key, actor) returns (uint256 moved) {
            ghostPending[key] = 0;
            ghostClaimable[actor] += moved;
            // NOTE: no flow total moves here. A release is a transfer between two liability
            // buckets, so `ghostCredited` and `ghostWithdrawn` must both stay put — which is
            // exactly what makes `invariant_LiabilityMatchesNetFlow` a real check on it.
            //
            // The return value is cross-checked against the mirror with a FLAG rather than a
            // revert: `fail_on_revert = false` would swallow a revert here and hide the desync.
            if (moved != pending) sawMirrorDesync = true;
            calls["releaseRoot"]++;
        } catch {}
        _after(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            ACTIONS: WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice An actor withdraws part of their own balance to themselves.
    /// @param actorSeed Selects the actor.
    /// @param amount Wei to withdraw, bounded to their balance.
    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        uint256 available = ghostClaimable[actor];
        if (available == 0) return;
        amount = bound(amount, 1, available);

        _before();
        vm.prank(actor);
        try VAULT.withdraw(amount) {
            ghostClaimable[actor] -= amount;
            ghostWithdrawn += amount;
            calls["withdraw"]++;
        } catch {}
        _after(actor);
    }

    /// @notice An actor drains their whole balance.
    /// @param actorSeed Selects the actor.
    function withdrawAll(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        uint256 available = ghostClaimable[actor];
        if (available == 0) return;

        _before();
        vm.prank(actor);
        try VAULT.withdrawAll() {
            ghostClaimable[actor] = 0;
            ghostWithdrawn += available;
            calls["withdrawAll"]++;
        } catch {}
        _after(actor);
    }

    /// @notice An actor withdraws to a different actor's address.
    /// @param actorSeed Selects the spender.
    /// @param destSeed Selects the destination.
    /// @param amount Wei to withdraw.
    function withdrawTo(uint256 actorSeed, uint256 destSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        address dest = _actor(destSeed);
        uint256 available = ghostClaimable[actor];
        if (available == 0) return;
        amount = bound(amount, 1, available);

        _before();
        vm.prank(actor);
        try VAULT.withdrawTo(payable(dest), amount) {
            ghostClaimable[actor] -= amount;
            ghostWithdrawn += amount;
            calls["withdrawTo"]++;
        } catch {}
        // Only the SPENDER is allowed to have lost balance. A destination that gained ETH in its
        // wallet must not have lost vault balance.
        _after(actor);
    }

    /// @notice A relayer submits an actor's signed authorization.
    /// @param actorSeed Selects the signing beneficiary.
    /// @param destSeed Selects the payout destination.
    /// @param amount Wei to withdraw.
    function withdrawGasless(uint256 actorSeed, uint256 destSeed, uint256 amount) external {
        uint256 index = _index(actorSeed, _actors.length);
        address actor = _actors[index];
        address dest = _actor(destSeed);
        uint256 available = ghostClaimable[actor];
        if (available == 0) return;
        amount = bound(amount, 1, available);

        uint256 nonce = VAULT.withdrawalNonce(actor);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 digest = VAULT.withdrawalDigest(actor, dest, amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_actorKeys[index], digest);

        _before();
        // The relayer is this handler, which holds every role — proving a privileged relayer still
        // cannot alter the terms it was handed.
        try VAULT.withdrawWithAuthorization(actor, payable(dest), amount, nonce, deadline, abi.encodePacked(r, s, v)) {
            ghostClaimable[actor] -= amount;
            ghostWithdrawn += amount;
            calls["withdrawGasless"]++;
        } catch {}
        _after(actor);
    }

    /*//////////////////////////////////////////////////////////////
                       ACTIONS: FORCED ETH AND ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Force ETH into the vault with no accounting call, as `selfdestruct` would.
    /// @param amount Wei to force in.
    function forceEth(uint256 amount) external {
        amount = bound(amount, 1, 10 ether);

        _before();
        vm.deal(address(VAULT), address(VAULT).balance + amount);
        ghostForced += amount;
        calls["forceEth"]++;
        _after(address(0));
    }

    /// @notice Schedule, mature and execute an excess sweep.
    /// @dev Bundled into one action because the timelock means a fuzzer that called the three steps
    ///      independently would essentially never land them in the right order within one run.
    ///      Time only ever moves forward, which is also what the real chain does.
    function sweepExcess() external {
        _before();
        try VAULT.scheduleExcessSweep(SWEEP_SINK) {} catch {}
        vm.warp(block.timestamp + VAULT.SWEEP_DELAY());
        try VAULT.sweepExcess(SWEEP_SINK) returns (uint256 amount) {
            ghostSwept += amount;
            calls["sweepExcess"]++;
        } catch {}
        _after(address(0));
    }

    /// @notice Flip the pause flag.
    /// @dev Present so the campaign covers "the vault is paused for part of the run". Withdrawals
    ///      must keep working across it, which shows up as the flow totals continuing to move.
    /// @param seed Chooses pause or unpause.
    function togglePause(uint256 seed) external {
        _before();
        if (seed % 2 == 0) {
            try VAULT.pause() {
                calls["pause"]++;
            } catch {}
        } else {
            try VAULT.unpause() {
                calls["unpause"]++;
            } catch {}
        }
        _after(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL BOOKKEEPING
    //////////////////////////////////////////////////////////////*/

    /// @dev Snapshot of every actor's claimable, taken immediately before a mutating call.
    uint256[ACTOR_COUNT] private _claimableBefore;

    function _before() private {
        for (uint256 i = 0; i < _actors.length; i++) {
            _claimableBefore[i] = VAULT.claimable(_actors[i]);
        }
    }

    /// @dev The tripwire. `allowedSpender` is the ONE address permitted to have lost balance in
    ///      the call that just ran, because it authorized the spend itself. Every other actor's
    ///      balance must be greater than or equal to what it was.
    /// @param allowedSpender Actor that just withdrew, or the zero address for non-withdrawals.
    function _after(address allowedSpender) private {
        for (uint256 i = 0; i < _actors.length; i++) {
            address actor = _actors[i];
            if (actor == allowedSpender) continue;
            if (VAULT.claimable(actor) < _claimableBefore[i]) sawUnauthorizedDecrease = true;
        }

        for (uint256 i = 0; i < _actors.length; i++) {
            address actor = _actors[i];
            uint256 nonce = VAULT.withdrawalNonce(actor);
            if (nonce < ghostHighestNonce[actor]) sawNonceRegression = true;
            ghostHighestNonce[actor] = nonce;
        }
    }

    /// @dev Keeps the handler solvent enough to credit; never touches the vault's balance.
    /// @param amount Wei the next credit needs.
    function _fund(uint256 amount) private {
        if (address(this).balance < amount) vm.deal(address(this), amount + 1_000 ether);
    }

    function _index(uint256 seed, uint256 length) private pure returns (uint256) {
        return seed % length;
    }

    function _actor(uint256 seed) private view returns (address) {
        return _actors[_index(seed, _actors.length)];
    }

    function _root(uint256 seed) private view returns (bytes32) {
        return _rootKeys[_index(seed, _rootKeys.length)];
    }
}
