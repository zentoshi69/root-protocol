// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {PayoutVault} from "../../src/PayoutVault.sol";
import {RootOwnershipRegistry} from "../../src/RootOwnershipRegistry.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";
import {MockOwnershipOracle} from "../mocks/MockOwnershipOracle.sol";
import {RootOwnershipHandler} from "./handlers/RootOwnershipHandler.sol";

/// @title RootOwnershipInvariantTest
/// @notice Stateful campaign over arbitrary orderings of mint recordings, permissionless binds,
///         permissionless invalidations, credits, releases and pauses.
/// @dev THE CLAIMS, in the order they matter:
///
///        1. AT MOST ONE ACTIVE BENEFICIARY PER ROOT. Structurally there is one current-state slot
///           per Root, so the real content of this claim is about HISTORY: every epoch below the
///           current one must be closed, and the current one must be closed too whenever the Root
///           is inactive. If two epochs were ever open at once, this is where it shows.
///        2. EPOCHS ONLY EVER GO UP, and only an activation moves them.
///        3. AN INACTIVE ROOT IS NEVER PAYABLE, and it always carries the spend txid that closed it.
///        4. RECORDED BITCOIN HEIGHT NEVER DECREASES, which is what makes every "not older than"
///           guard in the contract meaningful.
///        5. NO SEQUENCE EVER REDUCES A CREDITED BALANCE. The handler holds every privileged role
///           and has no withdrawal action, so any decrease at all is a bug.
///        6. THE MINT RECORDER IS SINGLE-USE PER ROOT, no matter how the fuzzer orders its calls.
///
///      HONESTY NOTE: the oracle here is `MockOwnershipOracle`, which verifies no signatures. This
///      campaign says nothing about quorum security; it is entirely about the registry's own state
///      machine. See the handler header.
contract RootOwnershipInvariantTest is StdInvariant, Test {
    RootOwnershipRegistry internal registry;
    PayoutVault internal vault;
    MockOwnershipOracle internal oracle;
    RootOwnershipHandler internal handler;

    address internal admin = address(0xADD117);

    function setUp() public {
        vm.warp(1_760_000_000);

        oracle = new MockOwnershipOracle();
        vault = new PayoutVault(admin);
        registry = new RootOwnershipRegistry(admin, address(oracle), address(vault));
        handler = new RootOwnershipHandler(registry, vault);

        vm.startPrank(admin);
        // The handler is deliberately maximally privileged; see its header for why.
        registry.grantRole(registry.MINT_RECORDER_ROLE(), address(handler));
        registry.grantRole(registry.PAUSER_ROLE(), address(handler));
        registry.grantRole(registry.DEFAULT_ADMIN_ROLE(), address(handler));
        vault.grantRole(vault.CREDITOR_ROLE(), address(handler));
        vault.grantRole(vault.ROOT_RELEASER_ROLE(), address(registry));
        vm.stopPrank();

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = RootOwnershipHandler.recordMint.selector;
        selectors[1] = RootOwnershipHandler.bind.selector;
        selectors[2] = RootOwnershipHandler.invalidate.selector;
        selectors[3] = RootOwnershipHandler.creditRootPending.selector;
        selectors[4] = RootOwnershipHandler.creditActor.selector;
        selectors[5] = RootOwnershipHandler.releasePending.selector;
        selectors[6] = RootOwnershipHandler.togglePause.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        // A fuzz call originating FROM one of these would model nothing real.
        excludeSender(address(vault));
        excludeSender(address(registry));
        excludeSender(address(oracle));
    }

    /*//////////////////////////////////////////////////////////////
                               INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice CLAIM 1. No Root ever has two open ownership epochs.
    function invariant_AtMostOneActiveEpochPerRoot() public view {
        bytes32[] memory roots = handler.rootKeys();

        for (uint256 i = 0; i < roots.length; i++) {
            uint64 epoch = registry.epochOf(roots[i]);

            for (uint64 e = 1; e < epoch; e++) {
                PuppetTypes.RootEpochInfo memory info = registry.epochInfo(roots[i], e);
                assertTrue(info.deactivatedAtBlockTimestamp != 0, "a superseded epoch was left open");
            }

            if (epoch != 0 && !registry.isActive(roots[i])) {
                PuppetTypes.RootEpochInfo memory current = registry.epochInfo(roots[i], epoch);
                assertTrue(current.deactivatedAtBlockTimestamp != 0, "inactive Root has an open epoch record");
            }
        }
    }

    /// @notice CLAIM 1, other half. The live beneficiary is exactly the one the current epoch's
    ///         history record names — the two views can never disagree about who is being paid.
    function invariant_CurrentStateMatchesEpochHistory() public view {
        bytes32[] memory roots = handler.rootKeys();

        for (uint256 i = 0; i < roots.length; i++) {
            PuppetTypes.RootState memory s = registry.currentState(roots[i]);
            if (s.epoch == 0) continue;

            PuppetTypes.RootEpochInfo memory info = registry.epochInfo(roots[i], s.epoch);
            assertEq(info.beneficiary, s.beneficiary, "history and state disagree on the beneficiary");
            assertEq(info.outpointHash, s.currentOutpointHash, "history and state disagree on the outpoint");
            assertEq(info.ownerScriptHash, s.ownerScriptHash, "history and state disagree on the script");
            assertEq(info.ownershipDigest, s.ownershipDigest, "history and state disagree on the digest");
        }
    }

    /// @notice CLAIM 2. Epochs never go backwards.
    function invariant_EpochNeverRegresses() public view {
        assertFalse(handler.sawEpochRegression(), "an epoch went backwards");

        bytes32[] memory roots = handler.rootKeys();
        for (uint256 i = 0; i < roots.length; i++) {
            assertGe(registry.epochOf(roots[i]), handler.ghostEpoch(roots[i]), "epoch below its ghost");
        }
    }

    /// @notice CLAIM 3. An inactive Root is never payable and always says why it closed.
    function invariant_InactiveRootIsNotPayable() public view {
        bytes32[] memory roots = handler.rootKeys();

        for (uint256 i = 0; i < roots.length; i++) {
            (, bool active, uint64 epoch) = registry.currentBeneficiary(roots[i]);
            PuppetTypes.RootState memory s = registry.currentState(roots[i]);

            assertEq(active, s.active, "currentBeneficiary and currentState disagree on active");
            assertEq(active, registry.isActive(roots[i]), "isActive disagrees");
            assertEq(epoch, s.epoch, "epoch views disagree");

            if (epoch != 0 && !active) {
                assertTrue(s.invalidatingSpendTxid != bytes32(0), "an epoch closed with no attested spend");
            }
            if (active) {
                assertEq(s.invalidatingSpendTxid, bytes32(0), "a live epoch carries a spend txid");
                assertTrue(s.beneficiary != address(0), "an active Root with no beneficiary");
            }
        }
    }

    /// @notice CLAIM 3, restated as a ghost tripwire evaluated after every single call.
    function invariant_ActiveRootAlwaysHasABeneficiary() public view {
        assertFalse(handler.sawActiveWithoutBeneficiary(), "an active Root had no beneficiary");
    }

    /// @notice CLAIM 4. The recorded Bitcoin height is monotonically non-decreasing.
    function invariant_BitcoinHeightNeverRegresses() public view {
        assertFalse(handler.sawHeightRegression(), "recorded Bitcoin height went backwards");
    }

    /// @notice CLAIM 5. No ordering of privileged calls ever reduces a credited balance.
    function invariant_CreditedBalancesNeverFall() public view {
        assertFalse(handler.sawClaimableDecrease(), "a credited balance was reduced");

        address[] memory actors = handler.actors();
        for (uint256 i = 0; i < actors.length; i++) {
            assertGe(vault.claimable(actors[i]), handler.ghostClaimable(actors[i]), "claimable below its ghost");
        }
    }

    /// @notice CLAIM 6. One canonical inscription is recorded by the mint path at most once.
    function invariant_MintRecorderIsSingleUsePerRoot() public view {
        bytes32[] memory roots = handler.rootKeys();
        for (uint256 i = 0; i < roots.length; i++) {
            assertLe(handler.ghostMintRecordings(roots[i]), 1, "a Root was mint-recorded twice");
        }
    }

    /// @notice The vault stays solvent throughout, since this campaign also moves real ETH.
    function invariant_VaultStaysSolvent() public view {
        assertGe(address(vault).balance, vault.totalLiability(), "vault is insolvent");
    }

    /*//////////////////////////////////////////////////////////////
                          COVERAGE, NOT A CLAIM
    //////////////////////////////////////////////////////////////*/

    /// @notice Drives every handler action once, deterministically.
    /// @dev This is a plain test, NOT an invariant. A coverage claim is legitimately false on a
    ///      one-call shrunk sequence, so asserting it as an invariant would make the campaign fail
    ///      for a reason that has nothing to do with the contract.
    function test_HandlerReachesEveryAction() public {
        handler.recordMint(0, 0, 10);
        handler.creditActor(0, 1 ether);
        handler.creditRootPending(0, 1 ether);
        handler.releasePending(0);
        handler.invalidate(0, 20, false);
        handler.bind(0, 1, 30, false);
        handler.togglePause();
        handler.togglePause();

        assertEq(handler.calls("recordMint.ok"), 1, "mint recorded");
        assertEq(handler.calls("creditActor.ok"), 1, "actor credited");
        assertEq(handler.calls("creditRootPending.ok"), 1, "root credited");
        assertEq(handler.calls("releasePending.ok"), 1, "pending released");
        assertEq(handler.calls("invalidate.ok"), 1, "epoch invalidated");
        assertEq(handler.calls("bind.ok"), 1, "owner rebound");
        assertEq(handler.calls("pause"), 1, "paused");
        assertEq(handler.calls("unpause"), 1, "unpaused");

        assertEq(registry.epochOf(handler.rootKeys()[0]), 2, "two epochs happened");
    }
}
