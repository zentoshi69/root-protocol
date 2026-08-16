// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {stdError} from "forge-std/StdError.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {FeeRouter} from "../../src/FeeRouter.sol";
import {PayoutVault} from "../../src/PayoutVault.sol";
import {IFeeRouter} from "../../src/interfaces/IFeeRouter.sol";
import {IPayoutVault} from "../../src/interfaces/IPayoutVault.sol";
import {IRootOwnershipRegistry} from "../../src/interfaces/IRootOwnershipRegistry.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";
import {MockRootOwnershipRegistry} from "../mocks/MockRootOwnershipRegistry.sol";

/// @title FeeRouterTest
/// @notice Unit suite for the immutable 50 / 25 / 25 split.
/// @dev EVERY TEST HERE DEFENDS ONE OF THREE SENTENCES:
///
///        1. `sellerAmount + puppetTreasuryAmount + protocolAmount == gross`, for every input,
///           including the four inputs where the percentage terms round to zero.
///        2. The router's own balance is unchanged by a successful route — every wei it was paid
///           left in the same transaction.
///        3. Nothing on this contract can change the percentages, and nothing can move value that
///           is already in flight or already credited.
///
///      The suite is deliberately run against the REAL `PayoutVault` rather than a mock, because
///      the interesting failure mode is the interaction between the two: the vault rejects
///      zero-amount batch entries, and the router's dust arithmetic legitimately produces them.
///      A mock that accepted zeros would have hidden that entirely.
contract FeeRouterTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 FIXTURES
    //////////////////////////////////////////////////////////////*/

    FeeRouter internal router;
    PayoutVault internal vault;
    MockRootOwnershipRegistry internal registry;

    address internal routerAdmin = address(0xADD1);
    address internal vaultAdmin = address(0xADD2);
    address internal escrow = address(0xE5C401);
    address internal puppetTreasury = address(0x9099E7);
    address internal protocolTreasury = address(0x9207);
    address internal seller = address(0x5E11E4);
    address internal solver = address(0x501FE4);
    address internal owner1 = address(0x0FE41);
    address internal owner2 = address(0x0FE42);
    address internal stranger = address(0x57A46E);

    bytes32 internal constant ROOT_A = keccak256("FEEROUTER_ROOT_A");
    bytes32 internal constant ROOT_B = keccak256("FEEROUTER_ROOT_B");

    /// @dev Role ids are cached in `setUp` rather than read inline inside a test body. An external
    ///      getter call placed after `vm.prank` or `vm.expectRevert` CONSUMES the cheat code, and
    ///      the assertion then silently runs against the wrong caller or the wrong call. This cost
    ///      several hours across sibling suites in this repository; it is not re-learned here.
    bytes32 internal routerCallerRole;
    bytes32 internal treasuryAdminRole;
    bytes32 internal defaultAdminRole;
    bytes32 internal vaultCreditorRole;
    bytes32 internal vaultReleaserRole;

    /// @dev A realistic timestamp so the timelock arithmetic is not done against `block.timestamp`
    ///      of 1, where a two-day delay underflows nothing but reads as nonsense in traces.
    uint64 internal constant GENESIS_TS = 1_760_000_000;

    function setUp() public {
        vm.warp(GENESIS_TS);

        vault = new PayoutVault(vaultAdmin);
        registry = new MockRootOwnershipRegistry();
        router = new FeeRouter(routerAdmin, vault, registry, puppetTreasury, protocolTreasury);

        routerCallerRole = router.ROUTER_CALLER_ROLE();
        treasuryAdminRole = router.TREASURY_ADMIN_ROLE();
        defaultAdminRole = router.DEFAULT_ADMIN_ROLE();
        vaultCreditorRole = vault.CREDITOR_ROLE();
        vaultReleaserRole = vault.ROOT_RELEASER_ROLE();

        vm.prank(vaultAdmin);
        vault.grantRole(vaultCreditorRole, address(router));

        vm.prank(routerAdmin);
        router.grantRole(routerCallerRole, escrow);

        vm.deal(escrow, 10_000 ether);
        vm.deal(stranger, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Scans runtime bytecode for a 4-byte selector. Used instead of "call it and expect a
    ///      revert", which is close to vacuous: a call with malformed arguments reverts whether or
    ///      not the function exists. Every use below is paired with a positive control so the scan
    ///      cannot pass by finding nothing at all.
    function _codeContainsSelector(bytes memory code, bytes4 selector) internal pure returns (bool) {
        for (uint256 i = 0; i + 4 <= code.length; i++) {
            if (
                code[i] == selector[0] && code[i + 1] == selector[1] && code[i + 2] == selector[2]
                    && code[i + 3] == selector[3]
            ) {
                return true;
            }
        }
        return false;
    }

    /// @dev Asserts the three shares sum to `gross` and that the split matches the published rule.
    function _assertQuoteIsExact(uint256 gross) internal view {
        (uint256 s, uint256 p, uint256 t) = router.quote(gross);
        assertEq(s + p + t, gross, "conservation broken");
        assertEq(s, gross / 2, "seller is not half, floored");
        assertEq(p, gross / 4, "puppet treasury is not a quarter, floored");
    }

    /// @dev Everything the vault knows about the three destinations, in one struct, so a test can
    ///      diff before and after a route without six local variables.
    struct Books {
        uint256 primary;
        uint256 puppet;
        uint256 protocolT;
        uint256 pendingRoot;
        uint256 liability;
        uint256 vaultBalance;
    }

    function _books(address primary, bytes32 rootKey) internal view returns (Books memory b) {
        b.primary = vault.claimable(primary);
        b.puppet = vault.claimable(router.puppetTreasury());
        b.protocolT = vault.claimable(router.protocolTreasury());
        b.pendingRoot = vault.pendingByRoot(rootKey);
        b.liability = vault.totalLiability();
        b.vaultBalance = address(vault).balance;
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR AND WIRING
    //////////////////////////////////////////////////////////////*/

    function test_ConstructorStoresWiring() public view {
        assertEq(address(router.PAYOUT_VAULT()), address(vault));
        assertEq(address(router.ROOT_REGISTRY()), address(registry));
        assertEq(router.puppetTreasury(), puppetTreasury);
        assertEq(router.protocolTreasury(), protocolTreasury);
    }

    function test_ConstructorGrantsGovernanceRolesOnly() public view {
        assertTrue(router.hasRole(defaultAdminRole, routerAdmin));
        assertTrue(router.hasRole(treasuryAdminRole, routerAdmin));

        // The two contracts that will hold ROUTER_CALLER_ROLE do not exist at deployment time, so
        // granting it here could only ever mean granting it to the deploying EOA.
        assertFalse(router.hasRole(routerCallerRole, routerAdmin));
        assertFalse(router.hasRole(routerCallerRole, address(this)));
        assertFalse(router.hasRole(defaultAdminRole, address(this)));
        assertFalse(router.hasRole(treasuryAdminRole, address(this)));
    }

    function test_ConstructorRejectsZeroAdmin() public {
        vm.expectRevert(IFeeRouter.ZeroAddress.selector);
        new FeeRouter(address(0), vault, registry, puppetTreasury, protocolTreasury);
    }

    function test_ConstructorRejectsZeroVault() public {
        vm.expectRevert(IFeeRouter.ZeroAddress.selector);
        new FeeRouter(routerAdmin, IPayoutVault(address(0)), registry, puppetTreasury, protocolTreasury);
    }

    function test_ConstructorRejectsZeroRegistry() public {
        vm.expectRevert(IFeeRouter.ZeroAddress.selector);
        new FeeRouter(routerAdmin, vault, IRootOwnershipRegistry(address(0)), puppetTreasury, protocolTreasury);
    }

    function test_ConstructorRejectsZeroPuppetTreasury() public {
        vm.expectRevert(IFeeRouter.ZeroAddress.selector);
        new FeeRouter(routerAdmin, vault, registry, address(0), protocolTreasury);
    }

    function test_ConstructorRejectsZeroProtocolTreasury() public {
        vm.expectRevert(IFeeRouter.ZeroAddress.selector);
        new FeeRouter(routerAdmin, vault, registry, puppetTreasury, address(0));
    }

    /// @dev Uses `recordLogs` rather than `expectEmit` because the constructor emits its
    ///      `RoleGranted` events first, and this assertion is about the initialization record being
    ///      present and correct, not about where it sits in the log order.
    function test_ConstructorEmitsRouterInitialized() public {
        vm.recordLogs();
        FeeRouter fresh = new FeeRouter(routerAdmin, vault, registry, puppetTreasury, protocolTreasury);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(fresh)
                    && logs[i].topics[0] == keccak256("RouterInitialized(address,address,address,address,address)")
            ) {
                found = true;
                assertEq(logs[i].topics[1], bytes32(uint256(uint160(routerAdmin))));
                assertEq(logs[i].topics[2], bytes32(uint256(uint160(address(vault)))));
                assertEq(logs[i].topics[3], bytes32(uint256(uint160(address(registry)))));
                (address loggedPuppet, address loggedProtocol) = abi.decode(logs[i].data, (address, address));
                assertEq(loggedPuppet, puppetTreasury);
                assertEq(loggedProtocol, protocolTreasury);
            }
        }
        assertTrue(found, "RouterInitialized was never emitted");
    }

    function test_SupportsInterface() public view {
        assertTrue(router.supportsInterface(type(IFeeRouter).interfaceId));
        assertTrue(router.supportsInterface(type(IAccessControl).interfaceId));
        assertTrue(router.supportsInterface(0x01ffc9a7));
        assertFalse(router.supportsInterface(0xdeadbeef));
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTANTS AND QUOTING
    //////////////////////////////////////////////////////////////*/

    function test_ConstantsAreExactAndSumToDenominator() public view {
        assertEq(router.SELLER_BPS(), 5000);
        assertEq(router.PUPPET_TREASURY_BPS(), 2500);
        assertEq(router.PROTOCOL_BPS(), 2500);
        assertEq(router.BPS_DENOMINATOR(), 10_000);
        assertEq(router.SELLER_BPS() + router.PUPPET_TREASURY_BPS() + router.PROTOCOL_BPS(), router.BPS_DENOMINATOR());
    }

    /// @dev The route tag emitted in `MintRouted` is meant to be readable against the escrow's
    ///      offer records without a translation table. If someone reorders `OfferKind`, this fails
    ///      rather than silently relabelling every historical payout event.
    function test_RouteTagsMatchOfferKindEnum() public view {
        assertEq(router.ROUTE_MINT_EVM(), uint8(PuppetTypes.OfferKind.PAID_EVM));
        assertEq(router.ROUTE_MINT_BTC(), uint8(PuppetTypes.OfferKind.PAID_BTC));
    }

    /// @dev The published split table. Values are LITERALS, not recomputed from the same formula
    ///      the contract uses, so a change to the formula fails here instead of agreeing with
    ///      itself. These are the numbers reproduced in the summary and in the SDK.
    function test_QuoteSplitTable() public view {
        uint256[11] memory grosses =
            [uint256(0), 1, 2, 3, 4, 5, 7, 1 gwei, 0.1 ether, 12_345_678_901_234_567, 999_999_999_999_999_999];
        uint256[11] memory expectedSeller = [
            uint256(0),
            0,
            1,
            1,
            2,
            2,
            3,
            500_000_000,
            50_000_000_000_000_000,
            6_172_839_450_617_283,
            499_999_999_999_999_999
        ];
        uint256[11] memory expectedPuppet = [
            uint256(0),
            0,
            0,
            0,
            1,
            1,
            1,
            250_000_000,
            25_000_000_000_000_000,
            3_086_419_725_308_641,
            249_999_999_999_999_999
        ];
        uint256[11] memory expectedProtocol = [
            uint256(0),
            1,
            1,
            2,
            1,
            2,
            3,
            250_000_000,
            25_000_000_000_000_000,
            3_086_419_725_308_643,
            250_000_000_000_000_001
        ];

        for (uint256 i = 0; i < grosses.length; i++) {
            (uint256 s, uint256 p, uint256 t) = router.quote(grosses[i]);
            assertEq(s, expectedSeller[i], "seller share");
            assertEq(p, expectedPuppet[i], "puppet share");
            assertEq(t, expectedProtocol[i], "protocol share");
            assertEq(s + p + t, grosses[i], "conservation");
        }
    }

    /// @dev The four inputs the rounding rule exists for, plus every value up to 1000, exhaustively.
    function test_QuoteConservationOnEveryTinyValue() public view {
        for (uint256 gross = 0; gross <= 1000; gross++) {
            _assertQuoteIsExact(gross);
        }
    }

    /// @dev The protocol absorbs the dust, and the dust is at most 3 wei — one wei from each of the
    ///      two floors, plus the one that neither floor can express. This is the precise statement
    ///      of "protocol is the remainder, not its own percentage".
    function test_QuoteProtocolAbsorbsAtMostThreeWeiOfDust() public view {
        for (uint256 gross = 0; gross <= 2000; gross++) {
            (uint256 s, uint256 p, uint256 t) = router.quote(gross);
            assertEq(s + p + t, gross, "conservation");
            assertGe(t, p, "protocol must never be below its nominal quarter");
            assertLe(t - p, 3, "dust exceeded 3 wei");
        }
    }

    /// @dev Documents the exact boundary where `gross * 5000` overflows, and how absurdly far past
    ///      any real value it is. The router cannot be reached with such a value: `msg.value` is
    ///      bounded by the chain's supply, and `quote` is pure.
    function test_QuoteOverflowBoundIsUnreachableInPractice() public view {
        uint256 bound = type(uint256).max / router.SELLER_BPS();
        (uint256 s, uint256 p, uint256 t) = router.quote(bound);
        assertEq(s + p + t, bound, "conservation still holds at the boundary");

        // Roughly 1e47 times the wei that will ever exist; recorded so the claim is checkable.
        assertGt(bound, 1e70);
    }

    function test_QuoteOverflowsOneWeiAboveTheBound() public {
        uint256 bound = type(uint256).max / router.SELLER_BPS();
        vm.expectRevert(stdError.arithmeticError);
        router.quote(bound + 1);
    }

    /// @dev "Percentages cannot change" proven structurally: no setter selector exists in the
    ///      deployed runtime bytecode, and the getters still return the same numbers after routing.
    function test_PercentagesHaveNoSetter() public {
        bytes memory code = address(router).code;

        bytes4[6] memory forbidden = [
            bytes4(keccak256("setSellerBps(uint256)")),
            bytes4(keccak256("setPuppetTreasuryBps(uint256)")),
            bytes4(keccak256("setProtocolBps(uint256)")),
            bytes4(keccak256("setSplit(uint256,uint256,uint256)")),
            bytes4(keccak256("setBps(uint256,uint256,uint256)")),
            bytes4(keccak256("setFee(uint256)"))
        ];
        for (uint256 i = 0; i < forbidden.length; i++) {
            assertFalse(_codeContainsSelector(code, forbidden[i]), "a percentage setter selector exists");
        }

        // Positive control: the scan is capable of finding a selector that IS there.
        assertTrue(_codeContainsSelector(code, bytes4(keccak256("quote(uint256)"))), "scan found nothing at all");

        vm.prank(escrow);
        router.routeMintEvm{value: 1 ether}(ROOT_A, seller, 1 ether);

        assertEq(router.SELLER_BPS(), 5000);
        assertEq(router.PUPPET_TREASURY_BPS(), 2500);
        assertEq(router.PROTOCOL_BPS(), 2500);
        assertEq(router.BPS_DENOMINATOR(), 10_000);
    }

    /*//////////////////////////////////////////////////////////////
                             ROUTE: EVM MINT
    //////////////////////////////////////////////////////////////*/

    function test_RouteMintEvmCreditsAllThreeAndConserves() public {
        uint256 gross = 1 ether;
        Books memory before = _books(seller, ROOT_A);

        vm.prank(escrow);
        router.routeMintEvm{value: gross}(ROOT_A, seller, gross);

        Books memory afterBooks = _books(seller, ROOT_A);
        assertEq(afterBooks.primary - before.primary, 0.5 ether, "seller share");
        assertEq(afterBooks.puppet - before.puppet, 0.25 ether, "puppet share");
        assertEq(afterBooks.protocolT - before.protocolT, 0.25 ether, "protocol share");
        assertEq(afterBooks.liability - before.liability, gross, "liability must grow by exactly gross");
        assertEq(afterBooks.vaultBalance - before.vaultBalance, gross, "vault must hold exactly gross more");
        assertEq(address(router).balance, 0, "router retained ETH");
    }

    function test_RouteMintEvmEmitsMintRouted() public {
        uint256 gross = 3 ether;
        vm.expectEmit(true, true, false, true, address(router));
        emit IFeeRouter.MintRouted(ROOT_A, seller, 0, gross, 1.5 ether, 0.75 ether, 0.75 ether);

        vm.prank(escrow);
        router.routeMintEvm{value: gross}(ROOT_A, seller, gross);
    }

    /// @dev "ONE `creditBatch` call" is a settlement-atomicity requirement, not a gas preference: a
    ///      split applied as three separate calls could be left half-applied by an intermediate
    ///      revert. `expectCall` with an explicit count is what actually pins it.
    function test_RouteMintEvmUsesExactlyOneCreditBatchCall() public {
        uint256 gross = 4 ether;

        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = seller;
        beneficiaries[1] = puppetTreasury;
        beneficiaries[2] = protocolTreasury;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 2 ether;
        amounts[1] = 1 ether;
        amounts[2] = 1 ether;

        vm.expectCall(address(vault), gross, abi.encodeCall(IPayoutVault.creditBatch, (beneficiaries, amounts)), 1);

        vm.prank(escrow);
        router.routeMintEvm{value: gross}(ROOT_A, seller, gross);
    }

    /// @dev A 1 wei mint is not a hypothetical: it is exactly the input that would revert if the
    ///      router forwarded zero-amount entries into the vault's batch.
    function test_RouteMintEvmOneWeiGoesEntirelyToProtocol() public {
        vm.prank(escrow);
        router.routeMintEvm{value: 1}(ROOT_A, seller, 1);

        assertEq(vault.claimable(seller), 0);
        assertEq(vault.claimable(puppetTreasury), 0);
        assertEq(vault.claimable(protocolTreasury), 1);
        assertEq(vault.totalLiability(), 1);
        assertEq(address(router).balance, 0);
    }

    function test_RouteMintEvmTwoAndThreeWei() public {
        vm.prank(escrow);
        router.routeMintEvm{value: 2}(ROOT_A, seller, 2);
        assertEq(vault.claimable(seller), 1);
        assertEq(vault.claimable(puppetTreasury), 0);
        assertEq(vault.claimable(protocolTreasury), 1);

        vm.prank(escrow);
        router.routeMintEvm{value: 3}(ROOT_B, seller, 3);
        assertEq(vault.claimable(seller), 2);
        assertEq(vault.claimable(puppetTreasury), 0);
        assertEq(vault.claimable(protocolTreasury), 3);

        assertEq(vault.totalLiability(), 5);
        assertEq(address(router).balance, 0);
    }

    function test_RouteMintEvmRejectsUnderpayment() public {
        vm.prank(escrow);
        vm.expectRevert(abi.encodeWithSelector(IFeeRouter.ValueMismatch.selector, 1 ether, 0.5 ether));
        router.routeMintEvm{value: 0.5 ether}(ROOT_A, seller, 1 ether);
    }

    function test_RouteMintEvmRejectsOverpayment() public {
        vm.prank(escrow);
        vm.expectRevert(abi.encodeWithSelector(IFeeRouter.ValueMismatch.selector, 1 ether, 2 ether));
        router.routeMintEvm{value: 2 ether}(ROOT_A, seller, 1 ether);
    }

    function test_RouteMintEvmRejectsUnauthorizedCaller() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, routerCallerRole)
        );
        router.routeMintEvm{value: 1 ether}(ROOT_A, seller, 1 ether);
    }

    /// @dev Governance holding every admin role is still not a router caller. The escrow's ability
    ///      to create payouts is not something the timelock inherits by being the timelock.
    function test_RouterAdminCannotRoute() public {
        vm.deal(routerAdmin, 1 ether);
        vm.prank(routerAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, routerAdmin, routerCallerRole
            )
        );
        router.routeMintEvm{value: 1 ether}(ROOT_A, seller, 1 ether);
    }

    function test_RouteMintEvmRejectsZeroSeller() public {
        vm.prank(escrow);
        vm.expectRevert(IFeeRouter.ZeroAddress.selector);
        router.routeMintEvm{value: 1 ether}(ROOT_A, address(0), 1 ether);
    }

    function test_RouteMintEvmRejectsZeroRootKey() public {
        vm.prank(escrow);
        vm.expectRevert(FeeRouter.ZeroRootKey.selector);
        router.routeMintEvm{value: 1 ether}(bytes32(0), seller, 1 ether);
    }

    function test_RouteMintEvmRejectsZeroGross() public {
        vm.prank(escrow);
        vm.expectRevert(FeeRouter.ZeroGross.selector);
        router.routeMintEvm{value: 0}(ROOT_A, seller, 0);
    }

    /// @dev End to end: the seller's 50% is genuinely theirs, not a number in an event.
    function test_RouteMintEvmSellerCanActuallyWithdraw() public {
        vm.prank(escrow);
        router.routeMintEvm{value: 8 ether}(ROOT_A, seller, 8 ether);

        uint256 balanceBefore = seller.balance;
        vm.prank(seller);
        vault.withdrawAll();

        assertEq(seller.balance - balanceBefore, 4 ether);
        assertEq(vault.totalLiability(), 4 ether, "the two treasuries still hold their halves");
    }

    /*//////////////////////////////////////////////////////////////
                             ROUTE: BTC MINT
    //////////////////////////////////////////////////////////////*/

    /// @dev THE POINT OF THIS ROUTE. Bob was already paid in native BTC by the solver, off this
    ///      chain. Crediting the seller again here would pay for the same Puppet twice.
    function test_RouteMintBtcCreditsSolverAndNotSeller() public {
        uint256 gross = 2 ether;

        vm.prank(escrow);
        router.routeMintBtc{value: gross}(ROOT_A, solver, gross);

        assertEq(vault.claimable(solver), 1 ether, "solver reimbursement");
        assertEq(vault.claimable(seller), 0, "the Bitcoin seller must NOT be paid twice");
        assertEq(vault.claimable(puppetTreasury), 0.5 ether);
        assertEq(vault.claimable(protocolTreasury), 0.5 ether);
        assertEq(vault.totalLiability(), gross);
        assertEq(address(router).balance, 0);
    }

    function test_RouteMintBtcEmitsRouteTagOne() public {
        uint256 gross = 2 ether;
        vm.expectEmit(true, true, false, true, address(router));
        emit IFeeRouter.MintRouted(ROOT_A, solver, 1, gross, 1 ether, 0.5 ether, 0.5 ether);

        vm.prank(escrow);
        router.routeMintBtc{value: gross}(ROOT_A, solver, gross);
    }

    function test_RouteMintBtcRejectsZeroSolver() public {
        vm.prank(escrow);
        vm.expectRevert(IFeeRouter.ZeroAddress.selector);
        router.routeMintBtc{value: 1 ether}(ROOT_A, address(0), 1 ether);
    }

    function test_RouteMintBtcRejectsWrongValueAndUnauthorized() public {
        vm.prank(escrow);
        vm.expectRevert(abi.encodeWithSelector(IFeeRouter.ValueMismatch.selector, 1 ether, 1));
        router.routeMintBtc{value: 1}(ROOT_A, solver, 1 ether);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, routerCallerRole)
        );
        router.routeMintBtc{value: 1 ether}(ROOT_A, solver, 1 ether);
    }

    function test_RouteMintBtcOneWeiGoesEntirelyToProtocol() public {
        vm.prank(escrow);
        router.routeMintBtc{value: 1}(ROOT_A, solver, 1);

        assertEq(vault.claimable(solver), 0);
        assertEq(vault.claimable(protocolTreasury), 1);
        assertEq(address(router).balance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            ROUTE: RECURRING
    //////////////////////////////////////////////////////////////*/

    function test_RouteRecurringPaysActiveBeneficiary() public {
        registry.setRoot(ROOT_A, owner1, true, 1);

        vm.expectEmit(true, true, false, true, address(router));
        emit IFeeRouter.RecurringRouted(ROOT_A, owner1, true, 4 ether, 2 ether, 1 ether, 1 ether);

        vm.prank(escrow);
        router.routeRecurring{value: 4 ether}(ROOT_A, 4 ether);

        assertEq(vault.claimable(owner1), 2 ether, "active beneficiary gets the Root share directly");
        assertEq(vault.pendingByRoot(ROOT_A), 0, "nothing should be parked");
        assertEq(vault.claimable(puppetTreasury), 1 ether);
        assertEq(vault.claimable(protocolTreasury), 1 ether);
        assertEq(vault.totalLiability(), 4 ether);
        assertEq(address(router).balance, 0);
    }

    /// @dev THE LAG CASE. The registry has seen the inscription move but nobody has proven who
    ///      controls it now. The Root share must not be paid to the previous owner.
    function test_RouteRecurringInactiveRootParksValueInPendingBucket() public {
        registry.setRoot(ROOT_A, owner1, true, 1);
        registry.setActive(ROOT_A, false);

        vm.expectEmit(true, true, false, true, address(router));
        emit IFeeRouter.RecurringRouted(ROOT_A, address(0), false, 4 ether, 2 ether, 1 ether, 1 ether);

        vm.prank(escrow);
        router.routeRecurring{value: 4 ether}(ROOT_A, 4 ether);

        assertEq(vault.claimable(owner1), 0, "the stale owner must not be paid");
        assertEq(vault.pendingByRoot(ROOT_A), 2 ether, "Root share must wait in the pending bucket");
        assertEq(vault.claimable(puppetTreasury), 1 ether, "treasuries are paid in both branches");
        assertEq(vault.claimable(protocolTreasury), 1 ether);
        assertEq(vault.totalLiability(), 4 ether, "parked value is still a liability from the first block");
        assertEq(address(router).balance, 0);
    }

    function test_RouteRecurringNeverActivatedRootParksValue() public {
        // ROOT_B was never touched: beneficiary zero, active false, epoch zero.
        vm.prank(escrow);
        router.routeRecurring{value: 8 ether}(ROOT_B, 8 ether);

        assertEq(vault.pendingByRoot(ROOT_B), 4 ether);
        assertEq(vault.claimable(puppetTreasury), 2 ether);
        assertEq(vault.claimable(protocolTreasury), 2 ether);
        assertEq(address(router).balance, 0);
    }

    /// @dev Defensive: a registry reporting `active` with a zero beneficiary should be unreachable,
    ///      but the router is holding the money at that instant. Parking is recoverable; reverting
    ///      the whole settlement is not.
    function test_RouteRecurringActiveWithZeroBeneficiaryFallsBackToPending() public {
        registry.setRoot(ROOT_A, address(0), true, 7);

        vm.prank(escrow);
        router.routeRecurring{value: 4 ether}(ROOT_A, 4 ether);

        assertEq(vault.pendingByRoot(ROOT_A), 2 ether);
        assertEq(vault.claimable(address(0)), 0, "no value may be burned to address(0)");
        assertEq(address(router).balance, 0);
    }

    /// @dev Below 2 wei the Root share rounds to zero, and the vault rejects zero-value credits.
    ///      The router must skip the `creditRoot` call rather than revert the whole settlement.
    function test_RouteRecurringOneWeiSkipsCreditRootEntirely() public {
        vm.expectCall(address(vault), abi.encodeWithSelector(IPayoutVault.creditRoot.selector), 0);

        vm.prank(escrow);
        router.routeRecurring{value: 1}(ROOT_A, 1);

        assertEq(vault.pendingByRoot(ROOT_A), 0);
        assertEq(vault.claimable(protocolTreasury), 1);
        assertEq(vault.totalLiability(), 1);
        assertEq(address(router).balance, 0);
    }

    function test_RouteRecurringTinyValuesConserveInBothBranches() public {
        registry.setRoot(ROOT_A, owner1, true, 1);

        for (uint256 gross = 1; gross <= 9; gross++) {
            uint256 liabilityBefore = vault.totalLiability();
            vm.prank(escrow);
            router.routeRecurring{value: gross}(ROOT_A, gross);
            assertEq(vault.totalLiability() - liabilityBefore, gross, "active branch conservation");
            assertEq(address(router).balance, 0);

            liabilityBefore = vault.totalLiability();
            vm.prank(escrow);
            router.routeRecurring{value: gross}(ROOT_B, gross);
            assertEq(vault.totalLiability() - liabilityBefore, gross, "pending branch conservation");
            assertEq(address(router).balance, 0);
        }
    }

    /// @dev The whole justification for the pending bucket: the money is not lost, it waits for
    ///      whoever next proves Bitcoin control.
    function test_RouteRecurringPendingIsReleasableToTheNextProvenOwner() public {
        vm.prank(escrow);
        router.routeRecurring{value: 4 ether}(ROOT_A, 4 ether);
        assertEq(vault.pendingByRoot(ROOT_A), 2 ether);

        vm.prank(vaultAdmin);
        vault.grantRole(vaultReleaserRole, address(this));
        vault.releaseRootCredit(ROOT_A, owner2);

        assertEq(vault.pendingByRoot(ROOT_A), 0);
        assertEq(vault.claimable(owner2), 2 ether);

        uint256 balanceBefore = owner2.balance;
        vm.prank(owner2);
        vault.withdrawAll();
        assertEq(owner2.balance - balanceBefore, 2 ether);
    }

    function test_RouteRecurringRejectsBadInputs() public {
        vm.prank(escrow);
        vm.expectRevert(FeeRouter.ZeroRootKey.selector);
        router.routeRecurring{value: 1 ether}(bytes32(0), 1 ether);

        vm.prank(escrow);
        vm.expectRevert(FeeRouter.ZeroGross.selector);
        router.routeRecurring{value: 0}(ROOT_A, 0);

        vm.prank(escrow);
        vm.expectRevert(abi.encodeWithSelector(IFeeRouter.ValueMismatch.selector, 1 ether, 3));
        router.routeRecurring{value: 3}(ROOT_A, 1 ether);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, routerCallerRole)
        );
        router.routeRecurring{value: 1 ether}(ROOT_A, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                          CROSS-ROUTE CONSERVATION
    //////////////////////////////////////////////////////////////*/

    /// @dev The headline property, exercised across all three routes and a spread of awkward
    ///      values: the vault gains exactly `gross` and the router keeps exactly nothing.
    function test_EveryRouteConservesAndLeavesRouterEmpty() public {
        registry.setRoot(ROOT_A, owner1, true, 1);

        uint256[8] memory grosses =
            [uint256(1), 2, 3, 1 gwei, 0.1 ether, 1 ether, 12_345_678_901_234_567, 999_999_999_999_999_999];

        for (uint256 i = 0; i < grosses.length; i++) {
            uint256 gross = grosses[i];

            uint256 liabilityBefore = vault.totalLiability();
            vm.prank(escrow);
            router.routeMintEvm{value: gross}(ROOT_A, seller, gross);
            assertEq(vault.totalLiability() - liabilityBefore, gross, "evm route");
            assertEq(address(router).balance, 0);

            liabilityBefore = vault.totalLiability();
            vm.prank(escrow);
            router.routeMintBtc{value: gross}(ROOT_A, solver, gross);
            assertEq(vault.totalLiability() - liabilityBefore, gross, "btc route");
            assertEq(address(router).balance, 0);

            liabilityBefore = vault.totalLiability();
            vm.prank(escrow);
            router.routeRecurring{value: gross}(ROOT_A, gross);
            assertEq(vault.totalLiability() - liabilityBefore, gross, "recurring active route");
            assertEq(address(router).balance, 0);

            liabilityBefore = vault.totalLiability();
            vm.prank(escrow);
            router.routeRecurring{value: gross}(ROOT_B, gross);
            assertEq(vault.totalLiability() - liabilityBefore, gross, "recurring pending route");
            assertEq(address(router).balance, 0);
        }

        assertEq(address(vault).balance, vault.totalLiability(), "vault solvency after the whole sequence");
    }

    /*//////////////////////////////////////////////////////////////
                          TREASURY GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    function test_SetPuppetTreasury() public {
        address next = address(0xBEEF01);

        vm.expectEmit(true, true, false, true, address(router));
        emit IFeeRouter.TreasuryUpdated(puppetTreasury, next, false);

        vm.prank(routerAdmin);
        router.setPuppetTreasury(next);

        assertEq(router.puppetTreasury(), next);
        assertEq(router.protocolTreasury(), protocolTreasury, "the other treasury must be untouched");
    }

    function test_SetProtocolTreasury() public {
        address next = address(0xBEEF02);

        vm.expectEmit(true, true, false, true, address(router));
        emit IFeeRouter.TreasuryUpdated(protocolTreasury, next, true);

        vm.prank(routerAdmin);
        router.setProtocolTreasury(next);

        assertEq(router.protocolTreasury(), next);
        assertEq(router.puppetTreasury(), puppetTreasury);
    }

    function test_SetTreasuryRejectsZeroAddress() public {
        vm.prank(routerAdmin);
        vm.expectRevert(IFeeRouter.ZeroAddress.selector);
        router.setPuppetTreasury(address(0));

        vm.prank(routerAdmin);
        vm.expectRevert(IFeeRouter.ZeroAddress.selector);
        router.setProtocolTreasury(address(0));
    }

    function test_SetTreasuryRejectsNoOpWrite() public {
        vm.prank(routerAdmin);
        vm.expectRevert(abi.encodeWithSelector(FeeRouter.TreasuryUnchanged.selector, puppetTreasury));
        router.setPuppetTreasury(puppetTreasury);

        vm.prank(routerAdmin);
        vm.expectRevert(abi.encodeWithSelector(FeeRouter.TreasuryUnchanged.selector, protocolTreasury));
        router.setProtocolTreasury(protocolTreasury);
    }

    function test_SetTreasuryRejectsUnauthorized() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, treasuryAdminRole
            )
        );
        router.setPuppetTreasury(address(0xBEEF03));

        // The escrow can route, which is by far the most-used privilege, and still cannot redirect
        // a single wei of protocol revenue.
        vm.prank(escrow);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, escrow, treasuryAdminRole)
        );
        router.setProtocolTreasury(address(0xBEEF04));
    }

    /// @dev Least privilege: holding `DEFAULT_ADMIN_ROLE` is authority over ROLES, not over the
    ///      treasury. An admin that wants to move the treasury must first grant itself the role,
    ///      which is a visible on-chain act.
    function test_DefaultAdminAloneCannotSetTreasury() public {
        vm.prank(routerAdmin);
        router.renounceRole(treasuryAdminRole, routerAdmin);

        vm.prank(routerAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, routerAdmin, treasuryAdminRole
            )
        );
        router.setPuppetTreasury(address(0xBEEF05));

        assertTrue(router.hasRole(defaultAdminRole, routerAdmin), "still the role administrator");
    }

    function test_RoutingAfterTreasuryUpdateGoesToTheNewAddresses() public {
        address newPuppet = address(0xBEEF06);
        address newProtocol = address(0xBEEF07);

        vm.startPrank(routerAdmin);
        router.setPuppetTreasury(newPuppet);
        router.setProtocolTreasury(newProtocol);
        vm.stopPrank();

        vm.prank(escrow);
        router.routeMintEvm{value: 4 ether}(ROOT_A, seller, 4 ether);

        assertEq(vault.claimable(newPuppet), 1 ether);
        assertEq(vault.claimable(newProtocol), 1 ether);
        assertEq(vault.claimable(puppetTreasury), 0, "the old treasury must not keep earning");
        assertEq(vault.claimable(protocolTreasury), 0);
    }

    /// @dev A treasury change cannot claw back value that was already routed: the old treasury's
    ///      balance stays in the vault and remains withdrawable only by the old treasury.
    function test_TreasuryUpdateCannotTouchAlreadyCreditedValue() public {
        vm.prank(escrow);
        router.routeMintEvm{value: 4 ether}(ROOT_A, seller, 4 ether);
        assertEq(vault.claimable(protocolTreasury), 1 ether);

        vm.prank(routerAdmin);
        router.setProtocolTreasury(address(0xBEEF08));

        assertEq(vault.claimable(protocolTreasury), 1 ether, "already-credited value is untouched");

        uint256 balanceBefore = protocolTreasury.balance;
        vm.prank(protocolTreasury);
        vault.withdrawAll();
        assertEq(protocolTreasury.balance - balanceBefore, 1 ether);
    }

    /// @dev The real governance path: a `TimelockController` holds the role, the change is queued
    ///      in public, and it cannot execute before the delay elapses.
    function test_TreasuryUpdateThroughTimelockController() public {
        address governor = address(0x60E12);
        address[] memory proposers = new address[](1);
        proposers[0] = governor;
        address[] memory executors = new address[](1);
        executors[0] = governor;

        TimelockController timelock = new TimelockController(2 days, proposers, executors, address(0));

        vm.startPrank(routerAdmin);
        router.grantRole(treasuryAdminRole, address(timelock));
        router.renounceRole(treasuryAdminRole, routerAdmin);
        vm.stopPrank();

        address next = address(0xBEEF09);
        bytes memory payload = abi.encodeCall(FeeRouter.setProtocolTreasury, (next));

        vm.prank(governor);
        timelock.schedule(address(router), 0, payload, bytes32(0), bytes32(0), 2 days);

        // Executing early must fail; the announcement window is the whole point.
        vm.prank(governor);
        vm.expectRevert();
        timelock.execute(address(router), 0, payload, bytes32(0), bytes32(0));
        assertEq(router.protocolTreasury(), protocolTreasury, "treasury moved before the delay elapsed");

        vm.warp(block.timestamp + 2 days + 1);
        vm.prank(governor);
        timelock.execute(address(router), 0, payload, bytes32(0), bytes32(0));

        assertEq(router.protocolTreasury(), next);

        vm.prank(escrow);
        router.routeMintEvm{value: 4 ether}(ROOT_A, seller, 4 ether);
        assertEq(vault.claimable(next), 1 ether, "post-timelock routing pays the new treasury");
    }

    /*//////////////////////////////////////////////////////////////
                          ETH HANDLING AND SAFETY
    //////////////////////////////////////////////////////////////*/

    function test_RejectsRawEthTransfer() public {
        vm.prank(stranger);
        (bool ok, bytes memory data) = address(router).call{value: 1 ether}("");
        assertFalse(ok, "raw ETH was accepted");
        // Truncating to the leading 4 bytes is the intent: `data` is ABI-encoded revert data and
        // its first word is the error selector.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertTrue(bytes4(data) == IFeeRouter.DirectDepositRejected.selector, "wrong revert reason");
        assertEq(address(router).balance, 0);
    }

    function test_RejectsUnknownSelector() public {
        vm.prank(stranger);
        (bool ok, bytes memory data) = address(router).call{value: 1 ether}(abi.encodeWithSignature("nope()"));
        assertFalse(ok);
        // Truncating to the leading 4 bytes is the intent: `data` is ABI-encoded revert data and
        // its first word is the error selector.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertTrue(bytes4(data) == IFeeRouter.DirectDepositRejected.selector, "wrong revert reason");
        assertEq(address(router).balance, 0);
    }

    /// @dev THE GRIEFING TEST. An absolute `balance == 0` post-condition would let anyone brick the
    ///      protocol forever with one wei of force-sent ETH, because this contract is
    ///      non-upgradeable. The residue check is differential precisely so this passes.
    function test_ForcedEthDoesNotBrickRouting() public {
        vm.deal(address(router), 1 wei);
        assertEq(address(router).balance, 1);

        vm.prank(escrow);
        router.routeMintEvm{value: 4 ether}(ROOT_A, seller, 4 ether);

        assertEq(vault.claimable(seller), 2 ether, "routing must still work with forced ETH present");
        assertEq(address(router).balance, 1, "the forced wei is untouched, and nothing else stayed");

        vm.prank(escrow);
        router.routeRecurring{value: 4 ether}(ROOT_B, 4 ether);
        assertEq(address(router).balance, 1);

        vm.prank(escrow);
        router.routeMintBtc{value: 4 ether}(ROOT_B, solver, 4 ether);
        assertEq(address(router).balance, 1);
    }

    function test_SweepForcedEthIsPermissionlessAndPaysTheProtocolTreasury() public {
        vm.deal(address(router), 3 ether);

        vm.expectEmit(true, true, false, true, address(router));
        emit FeeRouter.ForcedEthSwept(protocolTreasury, 3 ether, stranger);

        vm.prank(stranger);
        uint256 swept = router.sweepForcedEth();

        assertEq(swept, 3 ether);
        assertEq(address(router).balance, 0);
        assertEq(vault.claimable(protocolTreasury), 3 ether);
        assertEq(vault.totalLiability(), 3 ether);
    }

    function test_SweepForcedEthRevertsWhenThereIsNone() public {
        vm.prank(stranger);
        vm.expectRevert(FeeRouter.NoForcedEth.selector);
        router.sweepForcedEth();
    }

    /// @dev The sweep has no destination argument, so its caller cannot aim it. It follows the
    ///      governed treasury address and nothing else.
    function test_SweepForcedEthCannotBeAimedByItsCaller() public {
        vm.prank(routerAdmin);
        router.setProtocolTreasury(address(0xBEEF10));

        vm.deal(address(router), 1 ether);
        vm.prank(stranger);
        router.sweepForcedEth();

        assertEq(vault.claimable(address(0xBEEF10)), 1 ether);
        assertEq(vault.claimable(stranger), 0, "the caller gains nothing");
        assertEq(vault.claimable(protocolTreasury), 0);
    }

    /// @dev The sweep must not be able to scoop settlement value: after a route the router is empty
    ///      of everything except pre-existing forced ETH, so there is nothing in flight to take.
    function test_SweepForcedEthCannotReachSettlementValue() public {
        vm.deal(address(router), 2 wei);

        vm.prank(escrow);
        router.routeMintEvm{value: 10 ether}(ROOT_A, seller, 10 ether);

        vm.prank(stranger);
        uint256 swept = router.sweepForcedEth();

        assertEq(swept, 2, "the sweep saw only the forced wei, not the 10 ether that passed through");
        assertEq(vault.claimable(seller), 5 ether, "the seller's share is untouched");
    }

    /// @dev No owner withdrawal, no rescue-to-arbitrary-address, no upgrade hatch, no ownership.
    ///      Scanned in the deployed runtime bytecode rather than probed by calling, with a positive
    ///      control so a scan that finds nothing at all cannot pass.
    function test_NoOwnerWithdrawalOrUpgradeSurfaceExists() public view {
        bytes memory code = address(router).code;

        bytes4[10] memory forbidden = [
            bytes4(keccak256("withdraw(uint256)")),
            bytes4(keccak256("withdrawTo(address,uint256)")),
            bytes4(keccak256("rescueETH(address,uint256)")),
            bytes4(keccak256("rescue(address,uint256)")),
            bytes4(keccak256("sweepTo(address)")),
            bytes4(keccak256("transferOwnership(address)")),
            bytes4(keccak256("owner()")),
            bytes4(keccak256("upgradeTo(address)")),
            bytes4(keccak256("upgradeToAndCall(address,bytes)")),
            bytes4(keccak256("initialize(address)"))
        ];
        for (uint256 i = 0; i < forbidden.length; i++) {
            assertFalse(_codeContainsSelector(code, forbidden[i]), "a forbidden admin selector exists");
        }

        assertTrue(_codeContainsSelector(code, bytes4(keccak256("sweepForcedEth()"))), "scan found nothing at all");
    }

    /// @dev A long mixed sequence, asserting the router is empty after every single call rather
    ///      than only at the end.
    function test_RouterIsEmptyAfterEverySingleCallInALongSequence() public {
        registry.setRoot(ROOT_A, owner1, true, 1);

        for (uint256 i = 1; i <= 25; i++) {
            uint256 gross = i * 7 + (i % 3);

            vm.prank(escrow);
            router.routeMintEvm{value: gross}(ROOT_A, seller, gross);
            assertEq(address(router).balance, 0, "after evm route");

            vm.prank(escrow);
            router.routeMintBtc{value: gross}(ROOT_B, solver, gross);
            assertEq(address(router).balance, 0, "after btc route");

            vm.prank(escrow);
            router.routeRecurring{value: gross}(i % 2 == 0 ? ROOT_A : ROOT_B, gross);
            assertEq(address(router).balance, 0, "after recurring route");
        }

        assertEq(address(vault).balance, vault.totalLiability(), "vault solvency");
    }
}
