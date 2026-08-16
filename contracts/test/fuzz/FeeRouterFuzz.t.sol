// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {FeeRouter} from "../../src/FeeRouter.sol";
import {PayoutVault} from "../../src/PayoutVault.sol";
import {IFeeRouter} from "../../src/interfaces/IFeeRouter.sol";
import {MockRootOwnershipRegistry} from "../mocks/MockRootOwnershipRegistry.sol";

/// @title FeeRouterFuzzTest
/// @notice Property tests for the 50 / 25 / 25 split and the router's zero-retention rule.
/// @dev FOUR PROPERTIES, asserted on every run:
///
///        C1  `seller + puppetTreasury + protocol == gross`, exactly, with no tolerance.
///        C2  `address(router).balance` is unchanged by a successful route.
///        C3  `vault.totalLiability()` grows by exactly `gross`.
///        C4  `address(vault).balance == vault.totalLiability()` — the vault stays solvent, which
///            is the property the router could most easily break by under- or over-forwarding.
///
///      WHY THE RANGES ARE BOUNDED THE WAY THEY ARE.
///
///        `quote` is pure and is fuzzed over its ENTIRE valid domain, `[0, type(uint256).max /
///        SELLER_BPS]`. Above that the checked multiplication reverts; there is no arithmetic to
///        test there, only Solidity's own overflow guard, which is not this contract's property.
///
///        The routing tests bound `gross` to `[1, 1e27]` wei — one billion ether. `msg.value` is
///        bounded in reality by the chain's entire ETH supply, and 1e27 is roughly eight times
///        every ether that exists on Ethereum today, so the range covers every value the router can
///        physically be handed and then some. It is capped rather than left open for two concrete
///        reasons: `vm.deal` above that models nothing real, and the tests accumulate liabilities
///        across the three routes, so an unbounded upper end would make the ASSERTIONS overflow
///        before the contract did — a fuzzer finding a bug in the test harness is not a finding.
///
///        The lower end is 1, not 0: a zero gross is a rejected input with its own unit test
///        (`ZeroGross`), and mixing "must revert" and "must conserve" into one property would make
///        a failure ambiguous.
contract FeeRouterFuzzTest is Test {
    FeeRouter internal router;
    PayoutVault internal vault;
    MockRootOwnershipRegistry internal registry;

    address internal routerAdmin = address(0xADD1);
    address internal vaultAdmin = address(0xADD2);
    address internal escrow = address(0xE5C401);
    address internal puppetTreasury = address(0x9099E7);
    address internal protocolTreasury = address(0x9207);

    bytes32 internal constant ROOT_A = keccak256("FUZZ_ROOT_A");

    bytes32 internal routerCallerRole;
    bytes32 internal treasuryAdminRole;

    /// @dev One billion ether. See the contract-level note for why this is the ceiling.
    uint256 internal constant MAX_GROSS = 1e27;

    function setUp() public {
        vault = new PayoutVault(vaultAdmin);
        registry = new MockRootOwnershipRegistry();
        router = new FeeRouter(routerAdmin, vault, registry, puppetTreasury, protocolTreasury);

        routerCallerRole = router.ROUTER_CALLER_ROLE();
        treasuryAdminRole = router.TREASURY_ADMIN_ROLE();

        // Cached before the prank: an inline getter call would consume the cheat code and the grant
        // would silently run as this test contract, which has no admin role.
        bytes32 creditorRole = vault.CREDITOR_ROLE();

        vm.prank(vaultAdmin);
        vault.grantRole(creditorRole, address(router));

        vm.prank(routerAdmin);
        router.grantRole(routerCallerRole, escrow);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Keeps a fuzzed payout address from colliding with a fixture, so per-address assertions
    ///      stay unambiguous. Collisions are not a hazard for the contract — the vault simply adds
    ///      to the same bucket — they would only make a failure message lie about which share moved.
    function _assumeDistinctPayee(address who) internal view {
        vm.assume(who != address(0));
        vm.assume(who != puppetTreasury && who != protocolTreasury);
        vm.assume(who != address(vault) && who != address(router) && who != address(registry));
        vm.assume(who != escrow);
    }

    /// @dev C2 + C3 + C4 in one place, so no route test can forget one of them.
    function _assertRouterEmptyAndVaultSolvent(uint256 liabilityBefore, uint256 gross, uint256 expectedRouterBalance)
        internal
        view
    {
        assertEq(address(router).balance, expectedRouterBalance, "C2: router retained settlement ETH");
        assertEq(vault.totalLiability() - liabilityBefore, gross, "C3: liability did not grow by exactly gross");
        assertEq(address(vault).balance, vault.totalLiability(), "C4: vault is not exactly solvent");
    }

    /*//////////////////////////////////////////////////////////////
                                 QUOTING
    //////////////////////////////////////////////////////////////*/

    /// @dev C1 over the entire domain `quote` accepts. This is THE property the protocol's economic
    ///      promise rests on: no wei is ever created or destroyed by the split.
    function testFuzz_QuoteConservesOverTheWholeValidDomain(uint256 gross) public view {
        gross = bound(gross, 0, type(uint256).max / router.SELLER_BPS());

        (uint256 sellerAmount, uint256 puppetAmount, uint256 protocolAmount) = router.quote(gross);

        assertEq(sellerAmount + puppetAmount + protocolAmount, gross, "C1: conservation broken");
    }

    /// @dev The bps arithmetic must be exactly a half and a quarter, floored — not merely "close".
    ///      An independent statement of the same rule, so a change to the constants fails here even
    ///      if it happened to preserve conservation.
    function testFuzz_QuoteIsExactlyHalfAndQuarterFloored(uint256 gross) public view {
        gross = bound(gross, 0, type(uint256).max / router.SELLER_BPS());

        (uint256 sellerAmount, uint256 puppetAmount, uint256 protocolAmount) = router.quote(gross);

        assertEq(sellerAmount, gross / 2, "seller is not floor(gross/2)");
        assertEq(puppetAmount, gross / 4, "puppet treasury is not floor(gross/4)");
        assertEq(protocolAmount, gross - gross / 2 - gross / 4, "protocol is not the remainder");
    }

    /// @dev The protocol absorbs the rounding dust and the dust is tiny and bounded: the protocol
    ///      share never falls below its nominal quarter, and never exceeds it by more than 2 wei.
    ///      This is what makes "protocol takes the remainder" a rounding rule rather than a fee.
    function testFuzz_QuoteDustIsBoundedAndFavoursNobodyElse(uint256 gross) public view {
        gross = bound(gross, 0, type(uint256).max / router.SELLER_BPS());

        (uint256 sellerAmount, uint256 puppetAmount, uint256 protocolAmount) = router.quote(gross);

        assertGe(protocolAmount, puppetAmount, "protocol dipped below its nominal share");
        assertLe(protocolAmount - puppetAmount, 2, "dust exceeded 2 wei");
        assertLe(sellerAmount, gross / 2, "seller received more than its nominal share");
        assertLe(puppetAmount, gross / 4, "puppet treasury received more than its nominal share");
    }

    /*//////////////////////////////////////////////////////////////
                             ROUTING: MINTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_RouteMintEvmConservesAndRetainsNothing(uint256 gross, address seller) public {
        _assumeDistinctPayee(seller);
        gross = bound(gross, 1, MAX_GROSS);

        (uint256 sellerAmount, uint256 puppetAmount, uint256 protocolAmount) = router.quote(gross);
        uint256 liabilityBefore = vault.totalLiability();

        vm.deal(escrow, gross);
        vm.prank(escrow);
        router.routeMintEvm{value: gross}(ROOT_A, seller, gross);

        assertEq(vault.claimable(seller), sellerAmount, "seller credited the wrong amount");
        assertEq(vault.claimable(puppetTreasury), puppetAmount, "puppet treasury credited the wrong amount");
        assertEq(vault.claimable(protocolTreasury), protocolAmount, "protocol credited the wrong amount");
        assertEq(sellerAmount + puppetAmount + protocolAmount, gross, "C1: conservation broken on the EVM route");
        _assertRouterEmptyAndVaultSolvent(liabilityBefore, gross, 0);
    }

    function testFuzz_RouteMintBtcPaysSolverAndNeverTheSeller(uint256 gross, address solver, address seller) public {
        _assumeDistinctPayee(solver);
        _assumeDistinctPayee(seller);
        vm.assume(solver != seller);
        gross = bound(gross, 1, MAX_GROSS);

        (uint256 solverAmount, uint256 puppetAmount, uint256 protocolAmount) = router.quote(gross);
        uint256 liabilityBefore = vault.totalLiability();

        vm.deal(escrow, gross);
        vm.prank(escrow);
        router.routeMintBtc{value: gross}(ROOT_A, solver, gross);

        assertEq(vault.claimable(solver), solverAmount, "solver reimbursement is wrong");
        // Bob was already paid in native BTC. Paying him again here would pay twice for one Puppet.
        assertEq(vault.claimable(seller), 0, "the Bitcoin seller was paid a second time");
        assertEq(vault.claimable(puppetTreasury), puppetAmount);
        assertEq(vault.claimable(protocolTreasury), protocolAmount);
        assertEq(solverAmount + puppetAmount + protocolAmount, gross, "C1: conservation broken on the BTC route");
        _assertRouterEmptyAndVaultSolvent(liabilityBefore, gross, 0);
    }

    /*//////////////////////////////////////////////////////////////
                           ROUTING: RECURRING
    //////////////////////////////////////////////////////////////*/

    function testFuzz_RouteRecurringActiveBeneficiary(uint256 gross, address beneficiary, uint64 epoch) public {
        _assumeDistinctPayee(beneficiary);
        gross = bound(gross, 1, MAX_GROSS);

        registry.setRoot(ROOT_A, beneficiary, true, epoch);

        (uint256 rootAmount, uint256 puppetAmount, uint256 protocolAmount) = router.quote(gross);
        uint256 liabilityBefore = vault.totalLiability();

        vm.deal(escrow, gross);
        vm.prank(escrow);
        router.routeRecurring{value: gross}(ROOT_A, gross);

        assertEq(vault.claimable(beneficiary), rootAmount, "active beneficiary credited the wrong amount");
        assertEq(vault.pendingByRoot(ROOT_A), 0, "nothing should be parked for an active Root");
        assertEq(vault.claimable(puppetTreasury), puppetAmount);
        assertEq(vault.claimable(protocolTreasury), protocolAmount);
        assertEq(rootAmount + puppetAmount + protocolAmount, gross, "C1: conservation broken on the active route");
        _assertRouterEmptyAndVaultSolvent(liabilityBefore, gross, 0);
    }

    /// @dev The lag branch. The previously recorded owner must receive nothing, and the Root share
    ///      must be preserved in full for whoever next proves Bitcoin control.
    function testFuzz_RouteRecurringInactiveRootParksTheRootShare(uint256 gross, address staleOwner) public {
        _assumeDistinctPayee(staleOwner);
        gross = bound(gross, 1, MAX_GROSS);

        registry.setRoot(ROOT_A, staleOwner, false, 3);

        (uint256 rootAmount, uint256 puppetAmount, uint256 protocolAmount) = router.quote(gross);
        uint256 liabilityBefore = vault.totalLiability();

        vm.deal(escrow, gross);
        vm.prank(escrow);
        router.routeRecurring{value: gross}(ROOT_A, gross);

        assertEq(vault.claimable(staleOwner), 0, "a Root whose owner may have changed paid the stale owner");
        assertEq(vault.pendingByRoot(ROOT_A), rootAmount, "the Root share was not preserved in full");
        assertEq(vault.claimable(puppetTreasury), puppetAmount, "treasuries must be paid in both branches");
        assertEq(vault.claimable(protocolTreasury), protocolAmount);
        assertEq(rootAmount + puppetAmount + protocolAmount, gross, "C1: conservation broken on the pending route");
        _assertRouterEmptyAndVaultSolvent(liabilityBefore, gross, 0);
    }

    /*//////////////////////////////////////////////////////////////
                              REJECTED INPUTS
    //////////////////////////////////////////////////////////////*/

    /// @dev The router splits what it was actually paid. Any disagreement between the named gross
    ///      and the attached value is rejected, in both directions, with no tolerance band.
    function testFuzz_AnyValueMismatchReverts(uint256 gross, uint256 sent, address seller) public {
        _assumeDistinctPayee(seller);
        gross = bound(gross, 1, MAX_GROSS);
        sent = bound(sent, 0, MAX_GROSS);
        vm.assume(sent != gross);

        vm.deal(escrow, sent);
        vm.prank(escrow);
        vm.expectRevert(abi.encodeWithSelector(IFeeRouter.ValueMismatch.selector, gross, sent));
        router.routeMintEvm{value: sent}(ROOT_A, seller, gross);

        assertEq(address(router).balance, 0, "a rejected route left ETH behind");
        assertEq(vault.totalLiability(), 0, "a rejected route created a liability");
    }

    function testFuzz_UnauthorizedCallerCanNeverRoute(address caller, uint256 gross, address seller) public {
        _assumeDistinctPayee(seller);
        vm.assume(caller != escrow);
        vm.assume(caller != address(vault) && caller != address(router) && caller != address(registry));
        gross = bound(gross, 1, MAX_GROSS);

        vm.deal(caller, gross);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, routerCallerRole)
        );
        router.routeMintEvm{value: gross}(ROOT_A, seller, gross);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, routerCallerRole)
        );
        router.routeMintBtc{value: gross}(ROOT_A, seller, gross);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, routerCallerRole)
        );
        router.routeRecurring{value: gross}(ROOT_A, gross);

        assertEq(vault.totalLiability(), 0, "an unauthorized caller created a liability");
    }

    /*//////////////////////////////////////////////////////////////
                           ADVERSARIAL CONDITIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev THE GRIEFING PROPERTY. Anyone can force ETH into any contract with `selfdestruct`. If
    ///      the residue check were absolute (`balance == 0`) instead of differential, one wei would
    ///      permanently brick every route on a non-upgradeable contract. The split must be
    ///      completely unaffected by whatever is sitting in the router.
    function testFuzz_ForcedEthCannotAffectOrBlockASplit(uint256 gross, uint256 forced, address seller) public {
        _assumeDistinctPayee(seller);
        gross = bound(gross, 1, MAX_GROSS);
        forced = bound(forced, 1, MAX_GROSS);

        vm.deal(address(router), forced);

        (uint256 sellerAmount, uint256 puppetAmount, uint256 protocolAmount) = router.quote(gross);
        uint256 liabilityBefore = vault.totalLiability();

        vm.deal(escrow, gross);
        vm.prank(escrow);
        router.routeMintEvm{value: gross}(ROOT_A, seller, gross);

        assertEq(vault.claimable(seller), sellerAmount, "forced ETH changed the seller's share");
        assertEq(vault.claimable(puppetTreasury), puppetAmount);
        assertEq(vault.claimable(protocolTreasury), protocolAmount);
        // The forced wei is still there and untouched: the route neither consumed it nor kept any
        // of its own value alongside it.
        _assertRouterEmptyAndVaultSolvent(liabilityBefore, gross, forced);
    }

    /// @dev Governance may repoint the treasuries, but it can never change how much they receive.
    ///      The percentages are bytecode; only the destinations are storage.
    function testFuzz_TreasuryUpdatesNeverChangeTheSplit(uint256 gross, address newPuppet, address newProtocol) public {
        _assumeDistinctPayee(newPuppet);
        _assumeDistinctPayee(newProtocol);
        vm.assume(newPuppet != newProtocol);
        gross = bound(gross, 1, MAX_GROSS);

        vm.startPrank(routerAdmin);
        router.setPuppetTreasury(newPuppet);
        router.setProtocolTreasury(newProtocol);
        vm.stopPrank();

        (uint256 sellerAmount, uint256 puppetAmount, uint256 protocolAmount) = router.quote(gross);
        uint256 liabilityBefore = vault.totalLiability();

        address seller = address(0x5E11E4);
        vm.deal(escrow, gross);
        vm.prank(escrow);
        router.routeMintEvm{value: gross}(ROOT_A, seller, gross);

        assertEq(vault.claimable(newPuppet), puppetAmount, "the new treasury received a different share");
        assertEq(vault.claimable(newProtocol), protocolAmount);
        assertEq(vault.claimable(puppetTreasury), 0, "the old treasury kept earning");
        assertEq(vault.claimable(protocolTreasury), 0);
        assertEq(sellerAmount + puppetAmount + protocolAmount, gross, "C1: conservation broken after a repoint");
        assertEq(router.SELLER_BPS(), 5000, "a treasury update moved a percentage");
        assertEq(router.PUPPET_TREASURY_BPS(), 2500);
        assertEq(router.PROTOCOL_BPS(), 2500);
        _assertRouterEmptyAndVaultSolvent(liabilityBefore, gross, 0);
    }

    /// @dev A SEQUENCE, not a single call: the router must be empty after every one of five mixed
    ///      routes, and the vault must be exactly solvent at every step. A router that retained
    ///      dust on one path in five would pass every single-call test above and fail here.
    function testFuzz_RouterHoldsNothingAcrossAMixedSequence(uint96[5] memory rawGrosses, address payee) public {
        _assumeDistinctPayee(payee);
        registry.setRoot(ROOT_A, payee, true, 1);

        uint256 expectedLiability;

        for (uint256 i = 0; i < rawGrosses.length; i++) {
            uint256 gross = bound(uint256(rawGrosses[i]), 1, MAX_GROSS);
            vm.deal(escrow, gross);

            if (i % 3 == 0) {
                vm.prank(escrow);
                router.routeMintEvm{value: gross}(ROOT_A, payee, gross);
            } else if (i % 3 == 1) {
                vm.prank(escrow);
                router.routeMintBtc{value: gross}(ROOT_A, payee, gross);
            } else {
                vm.prank(escrow);
                router.routeRecurring{value: gross}(keccak256(abi.encode("unbound-root", i)), gross);
            }

            expectedLiability += gross;

            assertEq(address(router).balance, 0, "C2: router retained ETH mid-sequence");
            assertEq(vault.totalLiability(), expectedLiability, "C3: liability drifted from the sum of grosses");
            assertEq(address(vault).balance, vault.totalLiability(), "C4: vault solvency broke mid-sequence");
        }
    }
}
