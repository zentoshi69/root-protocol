// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test, console} from "forge-std/Test.sol";

import {PayoutVault} from "../../src/PayoutVault.sol";
import {PayoutVaultHandler} from "./handlers/PayoutVaultHandler.sol";

/// @title PayoutVaultInvariant
/// @notice Stateful campaign proving the vault stays solvent and honest under arbitrary orderings
///         of credits, batch credits, Root credits, releases, all four withdrawal paths, forced
///         ETH, excess sweeps and pauses.
/// @dev THE FIVE CLAIMS, in the order they matter:
///
///        1. `address(this).balance >= totalLiability()` — the vault can always pay everyone.
///        2. `totalLiability() == sum(claimable) + sum(pendingByRoot)` — the headline number is not
///           an independent counter that could drift from the buckets it summarises.
///        3. `totalLiability() == credited - withdrawn` — tracked as ghosts, so a release that
///           wrongly touched `totalLiability` is caught even though it moves no ETH.
///        4. No actor's claimable ever falls except in a call that actor authorized — checked after
///           EVERY handler call, against a handler that holds every admin role.
///        5. Forced ETH never becomes a liability, and only forced ETH is ever sweepable.
///
///      The handler is the only fuzz target, so the campaign never wastes depth on calls that
///      bounce off `AccessControl`.
contract PayoutVaultInvariant is StdInvariant, Test {
    PayoutVault internal vault;
    PayoutVaultHandler internal handler;

    address internal admin = address(0xADD117);

    function setUp() public {
        vm.warp(1_760_000_000);

        vault = new PayoutVault(admin);
        handler = new PayoutVaultHandler(vault);

        // The handler is deliberately maximally privileged; see its header for why.
        vm.startPrank(admin);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(handler));
        vault.grantRole(vault.CREDITOR_ROLE(), address(handler));
        vault.grantRole(vault.ROOT_RELEASER_ROLE(), address(handler));
        vault.grantRole(vault.EXCESS_SWEEPER_ROLE(), address(handler));
        vault.grantRole(vault.PAUSER_ROLE(), address(handler));
        vm.stopPrank();

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = PayoutVaultHandler.credit.selector;
        selectors[1] = PayoutVaultHandler.creditRoot.selector;
        selectors[2] = PayoutVaultHandler.creditBatch.selector;
        selectors[3] = PayoutVaultHandler.releaseRoot.selector;
        selectors[4] = PayoutVaultHandler.withdraw.selector;
        selectors[5] = PayoutVaultHandler.withdrawAll.selector;
        selectors[6] = PayoutVaultHandler.withdrawTo.selector;
        selectors[7] = PayoutVaultHandler.withdrawGasless.selector;
        selectors[8] = PayoutVaultHandler.forceEth.selector;
        selectors[9] = PayoutVaultHandler.sweepExcess.selector;
        selectors[10] = PayoutVaultHandler.togglePause.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        // The vault itself is excluded as a sender: a fuzz call originating FROM the vault would
        // model nothing real and could only produce false positives.
        excludeSender(address(vault));
    }

    /*//////////////////////////////////////////////////////////////
                               INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice CLAIM 1. The vault can always pay every obligation it has recorded.
    function invariant_BalanceCoversLiability() public view {
        assertGe(address(vault).balance, vault.totalLiability(), "vault is insolvent");
    }

    /// @notice CLAIM 2. `totalLiability` is exactly the sum of the buckets it summarises.
    function invariant_LiabilityEqualsBucketSums() public view {
        address[] memory actors = handler.actors();
        bytes32[] memory roots = handler.rootKeys();

        uint256 total;
        for (uint256 i = 0; i < actors.length; i++) {
            total += vault.claimable(actors[i]);
        }
        for (uint256 i = 0; i < roots.length; i++) {
            total += vault.pendingByRoot(roots[i]);
        }

        assertEq(vault.totalLiability(), total, "totalLiability drifted from the buckets");
    }

    /// @notice CLAIM 3. Liability is exactly the net of ETH credited in and withdrawn out.
    /// @dev A `releaseRootCredit` that wrongly touched `totalLiability` fails HERE and nowhere
    ///      else, because it moves no ETH and keeps the bucket sums consistent.
    function invariant_LiabilityMatchesNetFlow() public view {
        assertEq(
            vault.totalLiability(),
            handler.ghostCredited() - handler.ghostWithdrawn(),
            "liability is not credits minus withdrawals"
        );
    }

    /// @notice The vault's ETH balance is fully explained by the four flows.
    /// @dev Any wei the vault holds that this equation cannot account for would be a wei that
    ///      appeared from nowhere.
    function invariant_BalanceMatchesNetFlow() public view {
        assertEq(
            address(vault).balance,
            handler.ghostCredited() + handler.ghostForced() - handler.ghostWithdrawn() - handler.ghostSwept(),
            "balance is not explained by credits, forced ETH, withdrawals and sweeps"
        );
    }

    /// @notice The per-bucket mirror agrees with the vault, bucket by bucket.
    function invariant_MirrorMatchesVault() public view {
        address[] memory actors = handler.actors();
        bytes32[] memory roots = handler.rootKeys();

        for (uint256 i = 0; i < actors.length; i++) {
            assertEq(vault.claimable(actors[i]), handler.ghostClaimable(actors[i]), "claimable mirror mismatch");
        }
        for (uint256 i = 0; i < roots.length; i++) {
            assertEq(vault.pendingByRoot(roots[i]), handler.ghostPending(roots[i]), "pending mirror mismatch");
        }
        assertFalse(handler.sawMirrorDesync(), "releaseRootCredit returned an unexpected amount");
    }

    /// @notice CLAIM 4. No user's claimable ever decreased except by their own withdrawal.
    /// @dev Evaluated inside the handler after every single call, not just at the end of a run, so
    ///      a transient dip that is later refilled is still caught.
    function invariant_NoUnauthorizedClaimableDecrease() public view {
        assertFalse(handler.sawUnauthorizedDecrease(), "a balance fell without its owner spending it");
    }

    /// @notice Gasless nonces are monotonic, so no authorization can become replayable.
    function invariant_NoncesNeverGoBackwards() public view {
        assertFalse(handler.sawNonceRegression(), "a withdrawal nonce decreased");
    }

    /// @notice CLAIM 5. Sweepable excess is exactly the unaccounted ETH, never a liability.
    function invariant_ExcessIsExactlyUnaccountedEth() public view {
        uint256 balance = address(vault).balance;
        uint256 liability = vault.totalLiability();
        assertEq(vault.excessBalance(), balance - liability, "excess is not balance minus liability");
        assertLe(handler.ghostSwept(), handler.ghostForced(), "more was swept than was ever force-sent");
    }

    /// @notice Prints how often each action actually executed, so a green campaign cannot quietly
    ///         be a campaign in which nothing happened.
    /// @dev DELIBERATELY LOG-ONLY, NOT AN ASSERTION. Foundry evaluates every `invariant_` function
    ///      after EVERY call in a sequence, including the first, so a coverage assertion such as
    ///      "at least one credit has happened" would fail on any run whose opening call was
    ///      `forceEth`. Coverage is therefore reported and read from the run output (`-vv`) rather
    ///      than asserted. The observed counts are recorded in the phase report.
    function invariant_CallSummary() public view {
        console.log("credit          ", handler.calls("credit"));
        console.log("creditRoot      ", handler.calls("creditRoot"));
        console.log("creditBatch     ", handler.calls("creditBatch"));
        console.log("releaseRoot     ", handler.calls("releaseRoot"));
        console.log("withdraw        ", handler.calls("withdraw"));
        console.log("withdrawAll     ", handler.calls("withdrawAll"));
        console.log("withdrawTo      ", handler.calls("withdrawTo"));
        console.log("withdrawGasless ", handler.calls("withdrawGasless"));
        console.log("forceEth        ", handler.calls("forceEth"));
        console.log("sweepExcess     ", handler.calls("sweepExcess"));
        console.log("pause / unpause ", handler.calls("pause"), handler.calls("unpause"));
    }
}
