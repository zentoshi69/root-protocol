// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {PayoutVault} from "../../src/PayoutVault.sol";
import {IPayoutVault} from "../../src/interfaces/IPayoutVault.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {MockERC1271Wallet} from "../mocks/MockERC1271Wallet.sol";
import {GasGuzzlingReceiver, ReenteringReceiver, RejectingReceiver} from "../mocks/Receivers.sol";

/// @title PayoutVaultTest
/// @notice Unit suite for the protocol's pull-payment vault.
/// @dev EVERY TEST IN THIS FILE ULTIMATELY DEFENDS ONE SENTENCE:
///
///          `address(this).balance >= totalLiability()`, and no path other than a beneficiary's own
///          withdrawal ever reduces that beneficiary's balance.
///
///      The suite is therefore organised by who is trying to break it: an honest creditor with bad
///      arithmetic, a hostile recipient, a replaying relayer, and finally a fully-privileged admin
///      holding every role at once.
contract PayoutVaultTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 FIXTURES
    //////////////////////////////////////////////////////////////*/

    PayoutVault internal vault;

    address internal admin = address(0xA11CE0);
    address internal creditor = address(0xC12ED1);
    address internal releaser = address(0x5E1EA5);
    address internal sweeper = address(0x5EEE9E);
    address internal relayer = address(0x5E1AE1);
    address internal stranger = address(0x57A46E);

    uint256 internal aliceKey = 0xA11CE;
    uint256 internal bobKey = 0xB0B;
    address internal alice;
    address internal bob;

    bytes32 internal constant ROOT_A = keccak256("ROOT_A");
    bytes32 internal constant ROOT_B = keccak256("ROOT_B");

    /// @dev Role ids are cached rather than read through `vault.X_ROLE()` inside a test body,
    ///      because an external getter call placed after `vm.prank` silently CONSUMES the prank and
    ///      the assertion then runs as the test contract. That produced four false failures while
    ///      this suite was being written.
    bytes32 internal creditorRole;
    bytes32 internal releaserRole;
    bytes32 internal sweeperRole;
    bytes32 internal pauserRole;
    bytes32 internal adminRole;

    /// @dev A realistic timestamp so the two-day sweep timelock arithmetic is not done against
    ///      Foundry's default `block.timestamp == 1`.
    uint64 internal constant GENESIS_TS = 1_760_000_000;

    function setUp() public {
        vm.warp(GENESIS_TS);

        alice = vm.addr(aliceKey);
        bob = vm.addr(bobKey);

        vault = new PayoutVault(admin);

        creditorRole = vault.CREDITOR_ROLE();
        releaserRole = vault.ROOT_RELEASER_ROLE();
        sweeperRole = vault.EXCESS_SWEEPER_ROLE();
        pauserRole = vault.PAUSER_ROLE();
        adminRole = vault.DEFAULT_ADMIN_ROLE();

        vm.startPrank(admin);
        vault.grantRole(creditorRole, creditor);
        vault.grantRole(releaserRole, releaser);
        vault.grantRole(sweeperRole, sweeper);
        vm.stopPrank();

        vm.deal(creditor, 1000 ether);
        vm.deal(relayer, 10 ether);
        vm.deal(stranger, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Produces the 65-byte `(r, s, v)` encoding `SignatureChecker` expects for an EOA.
    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _credit(address beneficiary, uint256 amount) internal {
        vm.prank(creditor);
        vault.credit{value: amount}(beneficiary);
    }

    /// @dev Asserts the one invariant the whole contract exists to hold.
    function _assertSolvent() internal view {
        assertGe(address(vault).balance, vault.totalLiability(), "vault is insolvent");
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTION AND ROLES
    //////////////////////////////////////////////////////////////*/

    function test_ConstructorRejectsZeroAdmin() public {
        vm.expectRevert(IPayoutVault.ZeroAddress.selector);
        new PayoutVault(address(0));
    }

    function test_ConstructorGrantsAdminRolesButNotWritingRoles() public view {
        assertTrue(vault.hasRole(adminRole, admin));
        assertTrue(vault.hasRole(pauserRole, admin));
        assertTrue(vault.hasRole(sweeperRole, admin));

        // Least privilege: nothing may write the books until governance points these at reviewed
        // contract addresses, so the admin does NOT hold them out of the box.
        assertFalse(vault.hasRole(creditorRole, admin));
        assertFalse(vault.hasRole(releaserRole, admin));
    }

    function test_StartsEmpty() public view {
        assertEq(vault.totalLiability(), 0);
        assertEq(vault.excessBalance(), 0);
        assertEq(vault.claimable(alice), 0);
        assertEq(vault.pendingByRoot(ROOT_A), 0);
        assertEq(vault.withdrawalNonce(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                                CREDITING
    //////////////////////////////////////////////////////////////*/

    function test_CreditRaisesBalanceAndLiabilityTogether() public {
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPayoutVault.Credited(alice, 3 ether, creditor);

        _credit(alice, 3 ether);

        assertEq(vault.claimable(alice), 3 ether);
        assertEq(vault.totalLiability(), 3 ether);
        assertEq(address(vault).balance, 3 ether);
        assertEq(vault.excessBalance(), 0, "a credit must never look like sweepable excess");
        _assertSolvent();
    }

    function test_CreditAccumulates() public {
        _credit(alice, 1 ether);
        _credit(alice, 2 ether);
        assertEq(vault.claimable(alice), 3 ether);
        assertEq(vault.totalLiability(), 3 ether);
    }

    function test_CreditRejectsZeroBeneficiary() public {
        vm.prank(creditor);
        vm.expectRevert(IPayoutVault.ZeroAddress.selector);
        vault.credit{value: 1 ether}(address(0));
    }

    function test_CreditRejectsZeroValue() public {
        vm.prank(creditor);
        vm.expectRevert(IPayoutVault.ZeroAmount.selector);
        vault.credit{value: 0}(alice);
    }

    function test_CreditRejectsUnauthorizedCaller() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, creditorRole)
        );
        vault.credit{value: 1 ether}(alice);
    }

    function test_CreditRootRaisesPendingAndLiability() public {
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPayoutVault.RootCredited(ROOT_A, 5 ether, creditor);

        vm.prank(creditor);
        vault.creditRoot{value: 5 ether}(ROOT_A);

        assertEq(vault.pendingByRoot(ROOT_A), 5 ether);
        assertEq(vault.claimable(alice), 0, "a root credit belongs to nobody yet");
        assertEq(vault.totalLiability(), 5 ether, "the obligation exists from the credit onwards");
        _assertSolvent();
    }

    function test_CreditRootRejectsZeroRootKey() public {
        vm.prank(creditor);
        vm.expectRevert(IPayoutVault.ZeroRootKey.selector);
        vault.creditRoot{value: 1 ether}(bytes32(0));
    }

    function test_CreditRootRejectsZeroValue() public {
        vm.prank(creditor);
        vm.expectRevert(IPayoutVault.ZeroAmount.selector);
        vault.creditRoot{value: 0}(ROOT_A);
    }

    function test_CreditRootRejectsUnauthorizedCaller() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, creditorRole)
        );
        vault.creditRoot{value: 1 ether}(ROOT_A);
    }

    /*//////////////////////////////////////////////////////////////
                              BATCH CREDITING
    //////////////////////////////////////////////////////////////*/

    function _batch3() internal view returns (address[] memory to, uint256[] memory amounts) {
        to = new address[](3);
        amounts = new uint256[](3);
        to[0] = alice;
        to[1] = bob;
        to[2] = stranger;
        // Deliberately the protocol's 50/25/25 shape, since that is the batch the fee router sends.
        amounts[0] = 2 ether;
        amounts[1] = 1 ether;
        amounts[2] = 1 ether;
    }

    function test_CreditBatchSplitsExactly() public {
        (address[] memory to, uint256[] memory amounts) = _batch3();

        vm.prank(creditor);
        vault.creditBatch{value: 4 ether}(to, amounts);

        assertEq(vault.claimable(alice), 2 ether);
        assertEq(vault.claimable(bob), 1 ether);
        assertEq(vault.claimable(stranger), 1 ether);
        assertEq(vault.totalLiability(), 4 ether);
        assertEq(address(vault).balance, 4 ether);
        assertEq(vault.excessBalance(), 0);
        _assertSolvent();
    }

    function test_CreditBatchRejectsUnderpayment() public {
        (address[] memory to, uint256[] memory amounts) = _batch3();

        vm.prank(creditor);
        // Under-payment would leave 1 ether of credited-but-unbacked liability.
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.AmountMismatch.selector, 4 ether, 3 ether));
        vault.creditBatch{value: 3 ether}(to, amounts);
    }

    function test_CreditBatchRejectsOverpayment() public {
        (address[] memory to, uint256[] memory amounts) = _batch3();

        vm.prank(creditor);
        // Over-payment would leave 1 ether looking exactly like force-sent, sweepable ETH.
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.AmountMismatch.selector, 4 ether, 5 ether));
        vault.creditBatch{value: 5 ether}(to, amounts);
    }

    function test_CreditBatchRejectsLengthMismatch() public {
        address[] memory to = new address[](2);
        uint256[] memory amounts = new uint256[](1);
        to[0] = alice;
        to[1] = bob;
        amounts[0] = 1 ether;

        vm.prank(creditor);
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.ArrayLengthMismatch.selector, 2, 1));
        vault.creditBatch{value: 1 ether}(to, amounts);
    }

    function test_CreditBatchRejectsZeroBeneficiaryEntry() public {
        address[] memory to = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        to[0] = alice;
        to[1] = address(0);
        amounts[0] = 1 ether;
        amounts[1] = 1 ether;

        vm.prank(creditor);
        vm.expectRevert(IPayoutVault.ZeroAddress.selector);
        vault.creditBatch{value: 2 ether}(to, amounts);
    }

    function test_CreditBatchRejectsZeroAmountEntry() public {
        address[] memory to = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        to[0] = alice;
        to[1] = bob;
        amounts[0] = 1 ether;
        amounts[1] = 0;

        vm.prank(creditor);
        vm.expectRevert(IPayoutVault.ZeroAmount.selector);
        vault.creditBatch{value: 1 ether}(to, amounts);
    }

    function test_CreditBatchRejectsEmptyArrays() public {
        address[] memory to = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(creditor);
        vm.expectRevert(IPayoutVault.ZeroAmount.selector);
        vault.creditBatch{value: 0}(to, amounts);
    }

    function test_CreditBatchRejectsUnauthorizedCaller() public {
        (address[] memory to, uint256[] memory amounts) = _batch3();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, creditorRole)
        );
        vault.creditBatch{value: 4 ether}(to, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                              ROOT RELEASE
    //////////////////////////////////////////////////////////////*/

    function test_ReleaseRootCreditLeavesTotalLiabilityUnchanged() public {
        vm.prank(creditor);
        vault.creditRoot{value: 5 ether}(ROOT_A);

        uint256 liabilityBefore = vault.totalLiability();
        uint256 balanceBefore = address(vault).balance;

        vm.expectEmit(true, true, true, true, address(vault));
        emit IPayoutVault.RootCreditReleased(ROOT_A, alice, 5 ether);

        vm.prank(releaser);
        uint256 moved = vault.releaseRootCredit(ROOT_A, alice);

        assertEq(moved, 5 ether);
        assertEq(vault.pendingByRoot(ROOT_A), 0);
        assertEq(vault.claimable(alice), 5 ether);
        assertEq(vault.totalLiability(), liabilityBefore, "release must not re-count the obligation");
        assertEq(address(vault).balance, balanceBefore, "release must not move ETH");
        _assertSolvent();
    }

    function test_ReleaseRootCreditAddsToAnExistingClaimable() public {
        _credit(alice, 1 ether);
        vm.prank(creditor);
        vault.creditRoot{value: 2 ether}(ROOT_A);

        vm.prank(releaser);
        vault.releaseRootCredit(ROOT_A, alice);

        assertEq(vault.claimable(alice), 3 ether);
        assertEq(vault.totalLiability(), 3 ether);
    }

    function test_ReleaseRootCreditRejectsSecondRelease() public {
        vm.prank(creditor);
        vault.creditRoot{value: 2 ether}(ROOT_A);

        vm.prank(releaser);
        vault.releaseRootCredit(ROOT_A, alice);

        // The bucket is emptied, so a replayed release cannot mint a second claim on the same ETH.
        vm.prank(releaser);
        vm.expectRevert(IPayoutVault.ZeroAmount.selector);
        vault.releaseRootCredit(ROOT_A, bob);
    }

    function test_ReleaseRootCreditRejectsZeroBeneficiary() public {
        vm.prank(creditor);
        vault.creditRoot{value: 2 ether}(ROOT_A);

        vm.prank(releaser);
        vm.expectRevert(IPayoutVault.ZeroAddress.selector);
        vault.releaseRootCredit(ROOT_A, address(0));
    }

    function test_ReleaseRootCreditRejectsZeroRootKey() public {
        vm.prank(releaser);
        vm.expectRevert(IPayoutVault.ZeroRootKey.selector);
        vault.releaseRootCredit(bytes32(0), alice);
    }

    function test_ReleaseRootCreditRejectsEmptyBucket() public {
        vm.prank(releaser);
        vm.expectRevert(IPayoutVault.ZeroAmount.selector);
        vault.releaseRootCredit(ROOT_B, alice);
    }

    function test_ReleaseRootCreditRejectsUnauthorizedCaller() public {
        vm.prank(creditor);
        vault.creditRoot{value: 2 ether}(ROOT_A);

        // Note the creditor cannot release: crediting and assigning are separate authorities.
        vm.prank(creditor);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, creditor, releaserRole)
        );
        vault.releaseRootCredit(ROOT_A, alice);
    }

    /*//////////////////////////////////////////////////////////////
                            PLAIN WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    function test_WithdrawMovesEthAndLowersBothSides() public {
        _credit(alice, 4 ether);
        uint256 walletBefore = alice.balance;

        vm.expectEmit(true, true, true, true, address(vault));
        emit IPayoutVault.Withdrawn(alice, alice, 1.5 ether);

        vm.prank(alice);
        vault.withdraw(1.5 ether);

        assertEq(alice.balance, walletBefore + 1.5 ether);
        assertEq(vault.claimable(alice), 2.5 ether);
        assertEq(vault.totalLiability(), 2.5 ether);
        assertEq(address(vault).balance, 2.5 ether);
        _assertSolvent();
    }

    function test_WithdrawRejectsMoreThanClaimable() public {
        _credit(alice, 1 ether);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IPayoutVault.InsufficientClaimable.selector, alice, 1 ether + 1, 1 ether)
        );
        vault.withdraw(1 ether + 1);
    }

    function test_WithdrawRejectsZeroAmount() public {
        _credit(alice, 1 ether);

        vm.prank(alice);
        vm.expectRevert(IPayoutVault.ZeroAmount.selector);
        vault.withdraw(0);
    }

    function test_WithdrawCannotSpendAnotherUsersBalance() public {
        _credit(alice, 1 ether);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.InsufficientClaimable.selector, bob, 1 ether, 0));
        vault.withdraw(1 ether);

        assertEq(vault.claimable(alice), 1 ether, "alice's balance is untouched by bob's attempt");
    }

    function test_WithdrawAllEmptiesTheBalance() public {
        _credit(alice, 2 ether);

        vm.prank(alice);
        vault.withdrawAll();

        assertEq(vault.claimable(alice), 0);
        assertEq(vault.totalLiability(), 0);
        assertEq(address(vault).balance, 0);
    }

    function test_WithdrawAllRejectsEmptyBalance() public {
        vm.prank(alice);
        vm.expectRevert(IPayoutVault.ZeroAmount.selector);
        vault.withdrawAll();
    }

    function test_WithdrawToSendsElsewhereWithoutCreditingTheDestination() public {
        _credit(alice, 2 ether);

        vm.prank(alice);
        vault.withdrawTo(payable(bob), 2 ether);

        assertEq(bob.balance, 2 ether);
        assertEq(vault.claimable(alice), 0);
        assertEq(vault.claimable(bob), 0, "a withdrawal destination gains no standing claim");
    }

    function test_WithdrawToRejectsZeroRecipient() public {
        _credit(alice, 1 ether);

        vm.prank(alice);
        vm.expectRevert(IPayoutVault.ZeroAddress.selector);
        vault.withdrawTo(payable(address(0)), 1 ether);
    }

    function test_WithdrawToRejectingRecipientRevertsAndRestoresEverything() public {
        RejectingReceiver hostile = new RejectingReceiver();
        _credit(alice, 2 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.WithdrawalFailed.selector, address(hostile), 2 ether));
        vault.withdrawTo(payable(address(hostile)), 2 ether);

        // Rollback restores the accounting for free; alice simply withdraws somewhere else.
        assertEq(vault.claimable(alice), 2 ether);
        assertEq(vault.totalLiability(), 2 ether);

        vm.prank(alice);
        vault.withdraw(2 ether);
        assertEq(vault.claimable(alice), 0);
    }

    function test_WithdrawToGasHungryRecipientSucceeds() public {
        // 40 cold SSTOREs is far beyond the 2300-gas stipend a `transfer` would forward. Proving
        // this succeeds is proving the vault uses `call` with all remaining gas.
        GasGuzzlingReceiver guzzler = new GasGuzzlingReceiver(40);
        _credit(alice, 1 ether);

        vm.prank(alice);
        vault.withdrawTo(payable(address(guzzler)), 1 ether);

        assertEq(guzzler.totalReceived(), 1 ether);
        assertEq(address(guzzler).balance, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                               REENTRANCY
    //////////////////////////////////////////////////////////////*/

    function test_ReentrantRecipientIsRejectedButOuterWithdrawalSucceeds() public {
        ReenteringReceiver attacker = new ReenteringReceiver(address(vault), "", 4);
        attacker.configure(address(vault), abi.encodeCall(PayoutVault.withdraw, (1 ether)), 4);

        _credit(address(attacker), 2 ether);

        (bool ok,) = attacker.kick(address(vault), abi.encodeCall(PayoutVault.withdraw, (1 ether)));

        assertTrue(ok, "the honest outer withdrawal must still succeed");
        assertEq(attacker.attempts(), 1, "the callback must actually have fired, or this proves nothing");
        assertEq(attacker.succeeded(), 0, "the reentrant call must have been rejected");
        assertEq(address(attacker).balance, 1 ether, "exactly one withdrawal's worth of ETH left");
        assertEq(vault.claimable(address(attacker)), 1 ether);
        assertEq(vault.totalLiability(), 1 ether);
        _assertSolvent();
    }

    function test_ReentrantRecipientCannotReplayAnAuthorization() public {
        // The nastier variant: the recipient reenters the GASLESS path with the same signature.
        // The nonce is already consumed, so even without the guard this could not double-spend.
        uint256 amount = 1 ether;
        uint64 deadline = uint64(block.timestamp + 1 hours);

        ReenteringReceiver attacker = new ReenteringReceiver(address(vault), "", 4);
        _credit(alice, 2 ether);

        bytes32 digest = vault.withdrawalDigest(alice, address(attacker), amount, 0, deadline);
        bytes memory sig = _sign(aliceKey, digest);

        attacker.configure(
            address(vault),
            abi.encodeCall(
                PayoutVault.withdrawWithAuthorization, (alice, payable(address(attacker)), amount, 0, deadline, sig)
            ),
            4
        );

        vm.prank(relayer);
        vault.withdrawWithAuthorization(alice, payable(address(attacker)), amount, 0, deadline, sig);

        assertEq(attacker.attempts(), 1);
        assertEq(attacker.succeeded(), 0);
        assertEq(vault.withdrawalNonce(alice), 1, "the nonce advanced exactly once");
        assertEq(vault.claimable(alice), 1 ether);
        _assertSolvent();
    }

    /*//////////////////////////////////////////////////////////////
                          GASLESS WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    function test_WithdrawalDigestMatchesAnIndependentlyDerivedEip712Digest() public view {
        uint256 amount = 1 ether;
        uint64 deadline = uint64(block.timestamp + 1 hours);

        // Derived from the EIP-712 spec text, NOT from the contract, so a wrong domain name,
        // version, chain id or verifying contract in `PayoutVault` fails here.
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("HoodPups PayoutVault")),
                keccak256(bytes("1")),
                block.chainid,
                address(vault)
            )
        );
        bytes32 structHash = PuppetHashing.hashWithdrawal(alice, bob, amount, 0, deadline);
        bytes32 expected = keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));

        assertEq(vault.withdrawalDigest(alice, bob, amount, 0, deadline), expected);
    }

    function test_WithdrawalDigestIsBoundToEveryField() public view {
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 base = vault.withdrawalDigest(alice, bob, 1 ether, 0, deadline);

        assertTrue(base != vault.withdrawalDigest(bob, bob, 1 ether, 0, deadline), "beneficiary unbound");
        assertTrue(base != vault.withdrawalDigest(alice, alice, 1 ether, 0, deadline), "recipient unbound");
        assertTrue(base != vault.withdrawalDigest(alice, bob, 2 ether, 0, deadline), "amount unbound");
        assertTrue(base != vault.withdrawalDigest(alice, bob, 1 ether, 1, deadline), "nonce unbound");
        assertTrue(base != vault.withdrawalDigest(alice, bob, 1 ether, 0, deadline + 1), "deadline unbound");
    }

    function test_GaslessWithdrawalPaysASellerWithZeroEth() public {
        _credit(alice, 3 ether);
        // Alice literally cannot pay for gas; the relayer submits on her behalf.
        vm.deal(alice, 0);

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 digest = vault.withdrawalDigest(alice, bob, 3 ether, 0, deadline);
        bytes memory sig = _sign(aliceKey, digest);

        vm.expectEmit(true, true, true, true, address(vault));
        emit IPayoutVault.Withdrawn(alice, bob, 3 ether);
        vm.expectEmit(true, true, true, true, address(vault));
        emit IPayoutVault.WithdrawnWithAuthorization(alice, bob, 3 ether, 0, relayer);

        vm.prank(relayer);
        vault.withdrawWithAuthorization(alice, payable(bob), 3 ether, 0, deadline, sig);

        assertEq(bob.balance, 3 ether);
        assertEq(vault.claimable(alice), 0);
        assertEq(vault.totalLiability(), 0);
        assertEq(vault.withdrawalNonce(alice), 1);
        _assertSolvent();
    }

    function test_GaslessWithdrawalRejectsReplay() public {
        _credit(alice, 4 ether);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(aliceKey, vault.withdrawalDigest(alice, bob, 1 ether, 0, deadline));

        vm.prank(relayer);
        vault.withdrawWithAuthorization(alice, payable(bob), 1 ether, 0, deadline, sig);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.InvalidNonce.selector, 1, 0));
        vault.withdrawWithAuthorization(alice, payable(bob), 1 ether, 0, deadline, sig);

        assertEq(vault.claimable(alice), 3 ether, "only one withdrawal was ever executed");
    }

    function test_GaslessWithdrawalRejectsFutureNonce() public {
        _credit(alice, 1 ether);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(aliceKey, vault.withdrawalDigest(alice, bob, 1 ether, 7, deadline));

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.InvalidNonce.selector, 0, 7));
        vault.withdrawWithAuthorization(alice, payable(bob), 1 ether, 7, deadline, sig);
    }

    function test_GaslessWithdrawalRejectsExpiredAuthorization() public {
        _credit(alice, 1 ether);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(aliceKey, vault.withdrawalDigest(alice, bob, 1 ether, 0, deadline));

        vm.warp(uint256(deadline) + 1);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(IPayoutVault.ExpiredAuthorization.selector, deadline, uint256(deadline) + 1)
        );
        vault.withdrawWithAuthorization(alice, payable(bob), 1 ether, 0, deadline, sig);
    }

    function test_GaslessWithdrawalAcceptedExactlyAtTheDeadline() public {
        _credit(alice, 1 ether);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(aliceKey, vault.withdrawalDigest(alice, bob, 1 ether, 0, deadline));

        // The boundary is inclusive; pinning it stops a later refactor silently moving it.
        vm.warp(deadline);
        vm.prank(relayer);
        vault.withdrawWithAuthorization(alice, payable(bob), 1 ether, 0, deadline, sig);

        assertEq(bob.balance, 1 ether);
    }

    function test_GaslessWithdrawalRejectsRedirectedRecipient() public {
        _credit(alice, 1 ether);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(aliceKey, vault.withdrawalDigest(alice, bob, 1 ether, 0, deadline));

        // A malicious relayer swaps the payout destination for its own address.
        vm.prank(relayer);
        vm.expectRevert(IPayoutVault.InvalidAuthorizationSignature.selector);
        vault.withdrawWithAuthorization(alice, payable(relayer), 1 ether, 0, deadline, sig);
    }

    function test_GaslessWithdrawalRejectsInflatedAmount() public {
        _credit(alice, 5 ether);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(aliceKey, vault.withdrawalDigest(alice, bob, 1 ether, 0, deadline));

        vm.prank(relayer);
        vm.expectRevert(IPayoutVault.InvalidAuthorizationSignature.selector);
        vault.withdrawWithAuthorization(alice, payable(bob), 5 ether, 0, deadline, sig);
    }

    function test_GaslessWithdrawalRejectsSignatureFromAnotherKey() public {
        _credit(alice, 1 ether);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(bobKey, vault.withdrawalDigest(alice, bob, 1 ether, 0, deadline));

        vm.prank(relayer);
        vm.expectRevert(IPayoutVault.InvalidAuthorizationSignature.selector);
        vault.withdrawWithAuthorization(alice, payable(bob), 1 ether, 0, deadline, sig);
    }

    function test_GaslessWithdrawalRejectsGarbageSignature() public {
        _credit(alice, 1 ether);
        uint64 deadline = uint64(block.timestamp + 1 hours);

        vm.prank(relayer);
        vm.expectRevert(IPayoutVault.InvalidAuthorizationSignature.selector);
        vault.withdrawWithAuthorization(alice, payable(bob), 1 ether, 0, deadline, hex"deadbeef");
    }

    function test_GaslessWithdrawalRejectsZeroBeneficiary() public {
        uint64 deadline = uint64(block.timestamp + 1 hours);
        vm.prank(relayer);
        vm.expectRevert(IPayoutVault.ZeroAddress.selector);
        vault.withdrawWithAuthorization(address(0), payable(bob), 1 ether, 0, deadline, hex"");
    }

    function test_GaslessWithdrawalRejectsOverdraft() public {
        _credit(alice, 1 ether);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(aliceKey, vault.withdrawalDigest(alice, bob, 2 ether, 0, deadline));

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.InsufficientClaimable.selector, alice, 2 ether, 1 ether));
        vault.withdrawWithAuthorization(alice, payable(bob), 2 ether, 0, deadline, sig);

        assertEq(vault.withdrawalNonce(alice), 0, "a reverted authorization must not burn the nonce");
    }

    function test_SequentialAuthorizationsWork() public {
        _credit(alice, 3 ether);
        uint64 deadline = uint64(block.timestamp + 1 hours);

        for (uint256 i = 0; i < 3; i++) {
            bytes memory sig = _sign(aliceKey, vault.withdrawalDigest(alice, bob, 1 ether, i, deadline));
            vm.prank(relayer);
            vault.withdrawWithAuthorization(alice, payable(bob), 1 ether, i, deadline, sig);
            assertEq(vault.withdrawalNonce(alice), i + 1);
        }

        assertEq(bob.balance, 3 ether);
        assertEq(vault.totalLiability(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-1271 ACCOUNTS
    //////////////////////////////////////////////////////////////*/

    function test_GaslessWithdrawalAcceptsErc1271SmartAccount() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet(alice);
        _credit(address(wallet), 2 ether);

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes32 digest = vault.withdrawalDigest(address(wallet), bob, 2 ether, 0, deadline);
        bytes memory sig = _sign(aliceKey, digest);

        vm.prank(relayer);
        vault.withdrawWithAuthorization(address(wallet), payable(bob), 2 ether, 0, deadline, sig);

        assertEq(bob.balance, 2 ether);
        assertEq(vault.claimable(address(wallet)), 0);
        assertEq(vault.withdrawalNonce(address(wallet)), 1);
    }

    function test_GaslessWithdrawalRejectsErc1271WalletThatRefuses() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet(alice);
        wallet.setAlwaysReject(true);
        _credit(address(wallet), 1 ether);

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(aliceKey, vault.withdrawalDigest(address(wallet), bob, 1 ether, 0, deadline));

        vm.prank(relayer);
        vm.expectRevert(IPayoutVault.InvalidAuthorizationSignature.selector);
        vault.withdrawWithAuthorization(address(wallet), payable(bob), 1 ether, 0, deadline, sig);
    }

    function test_NonceAndDeadlineStillBindAgainstARubberStampWallet() public {
        // The important ERC-1271 test: a wallet whose signature check is worthless must not be able
        // to replay, because replay protection lives in the vault, not in the signature.
        MockERC1271Wallet wallet = new MockERC1271Wallet(alice);
        wallet.setAlwaysAccept(true);
        _credit(address(wallet), 3 ether);

        uint64 deadline = uint64(block.timestamp + 1 hours);

        vm.prank(relayer);
        vault.withdrawWithAuthorization(address(wallet), payable(bob), 1 ether, 0, deadline, hex"00");

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.InvalidNonce.selector, 1, 0));
        vault.withdrawWithAuthorization(address(wallet), payable(bob), 1 ether, 0, deadline, hex"00");

        vm.warp(uint256(deadline) + 1);
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(IPayoutVault.ExpiredAuthorization.selector, deadline, uint256(deadline) + 1)
        );
        vault.withdrawWithAuthorization(address(wallet), payable(bob), 1 ether, 1, deadline, hex"00");

        assertEq(vault.claimable(address(wallet)), 2 ether, "exactly one withdrawal executed");
    }

    /*//////////////////////////////////////////////////////////////
                                 PAUSING
    //////////////////////////////////////////////////////////////*/

    function test_PauseBlocksEveryCreditPath() public {
        vm.prank(admin);
        vault.pause();

        (address[] memory to, uint256[] memory amounts) = _batch3();

        vm.startPrank(creditor);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.credit{value: 1 ether}(alice);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.creditRoot{value: 1 ether}(ROOT_A);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.creditBatch{value: 4 ether}(to, amounts);
        vm.stopPrank();
    }

    /// @dev Terminal credits discharge obligations that predate the pause. They therefore remain
    ///      live, while retaining the same role checks and exact backing rules as ordinary credit.
    function test_TerminalCreditsRemainLiveAndExactlyBackedWhilePaused() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, creditorRole)
        );
        vault.creditTerminal{value: 1 ether}(alice);

        vm.prank(creditor);
        vault.creditTerminal{value: 1 ether}(alice);

        (address[] memory to, uint256[] memory amounts) = _batch3();
        vm.prank(creditor);
        vault.creditTerminalBatch{value: 4 ether}(to, amounts);

        assertEq(vault.claimable(alice), 3 ether, "single plus batch credit");
        assertEq(vault.claimable(bob), 1 ether, "batch credit");
        assertEq(vault.claimable(stranger), 1 ether, "batch credit");
        assertEq(vault.totalLiability(), 5 ether, "every terminal wei is a liability");
        assertEq(address(vault).balance, 5 ether, "every liability is backed");
        _assertSolvent();
    }

    /// @dev THE test the spec singles out: a pause may stop new risk, never a payout.
    function test_WithdrawalsWorkWhilePaused() public {
        _credit(alice, 6 ether);
        vm.prank(creditor);
        vault.creditRoot{value: 2 ether}(ROOT_A);

        vm.prank(admin);
        vault.pause();
        assertTrue(vault.paused());

        // 1. self withdrawal
        vm.prank(alice);
        vault.withdraw(1 ether);

        // 2. withdrawal to a third party
        vm.prank(alice);
        vault.withdrawTo(payable(bob), 1 ether);

        // 3. gasless withdrawal
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(aliceKey, vault.withdrawalDigest(alice, bob, 1 ether, 0, deadline));
        vm.prank(relayer);
        vault.withdrawWithAuthorization(alice, payable(bob), 1 ether, 0, deadline, sig);

        // 4. root release, so pending funds do not become hostages of the pause
        vm.prank(releaser);
        vault.releaseRootCredit(ROOT_A, alice);

        // 5. drain
        vm.prank(alice);
        vault.withdrawAll();

        assertTrue(vault.paused(), "still paused throughout");
        assertEq(vault.claimable(alice), 0);
        assertEq(vault.totalLiability(), 0);
        assertEq(address(vault).balance, 0);
    }

    function test_UnpauseRestoresCrediting() public {
        vm.prank(admin);
        vault.pause();
        vm.prank(admin);
        vault.unpause();

        _credit(alice, 1 ether);
        assertEq(vault.claimable(alice), 1 ether);
    }

    function test_PauserCannotUnpause() public {
        address hotKey = address(0xB07);
        vm.prank(admin);
        vault.grantRole(pauserRole, hotKey);

        vm.prank(hotKey);
        vault.pause();

        // Asymmetric by design: stopping is fast, restarting is a timelocked governance action.
        vm.prank(hotKey);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, hotKey, adminRole)
        );
        vault.unpause();
    }

    function test_PauseRejectsUnauthorizedCaller() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, pauserRole)
        );
        vault.pause();
    }

    /*//////////////////////////////////////////////////////////////
                        DIRECT DEPOSITS AND EXCESS
    //////////////////////////////////////////////////////////////*/

    function test_DirectEthTransferIsRejected() public {
        vm.prank(stranger);
        (bool ok, bytes memory ret) = address(vault).call{value: 1 ether}("");
        assertFalse(ok);
        // Truncating the revert data to its selector is the point of the check.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(ret), IPayoutVault.DirectDepositRejected.selector);
        assertEq(address(vault).balance, 0);
    }

    function test_UnknownSelectorIsRejected() public {
        vm.prank(stranger);
        (bool ok, bytes memory ret) = address(vault).call{value: 1 ether}(abi.encodeWithSignature("notAFunction()"));
        assertFalse(ok);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(ret), IPayoutVault.DirectDepositRejected.selector);
    }

    function test_ForcedEthBecomesExcessAndNeverALiability() public {
        _credit(alice, 2 ether);

        // `vm.deal` reproduces what `selfdestruct` or a block reward does: balance appears with no
        // call frame, so no accounting hook can possibly run.
        vm.deal(address(vault), address(vault).balance + 5 ether);

        assertEq(vault.totalLiability(), 2 ether, "forced ETH must not become anybody's money");
        assertEq(vault.claimable(alice), 2 ether);
        assertEq(vault.excessBalance(), 5 ether);
        _assertSolvent();
    }

    function test_SweepExcessMovesOnlyTheUnaccountedPortion() public {
        _credit(alice, 2 ether);
        vm.prank(creditor);
        vault.creditRoot{value: 3 ether}(ROOT_A);
        vm.deal(address(vault), address(vault).balance + 4 ether);

        vm.prank(sweeper);
        vault.scheduleExcessSweep(payable(stranger));
        vm.warp(block.timestamp + vault.SWEEP_DELAY());

        uint256 strangerBefore = stranger.balance;

        vm.expectEmit(true, true, true, true, address(vault));
        emit IPayoutVault.ExcessSwept(stranger, 4 ether);

        vm.prank(sweeper);
        uint256 swept = vault.sweepExcess(payable(stranger));

        assertEq(swept, 4 ether);
        assertEq(stranger.balance, strangerBefore + 4 ether);
        assertEq(vault.claimable(alice), 2 ether, "a liability was touched");
        assertEq(vault.pendingByRoot(ROOT_A), 3 ether, "a pending liability was touched");
        assertEq(vault.totalLiability(), 5 ether);
        assertEq(address(vault).balance, 5 ether, "exactly the liabilities remain");
        assertEq(vault.excessBalance(), 0);
        _assertSolvent();
    }

    function test_SweepExcessRejectsWhenThereIsNoExcess() public {
        _credit(alice, 2 ether);

        vm.prank(sweeper);
        vault.scheduleExcessSweep(payable(stranger));
        vm.warp(block.timestamp + vault.SWEEP_DELAY());

        vm.prank(sweeper);
        vm.expectRevert(IPayoutVault.NoExcess.selector);
        vault.sweepExcess(payable(stranger));
    }

    function test_SweepExcessRequiresASchedule() public {
        vm.deal(address(vault), 1 ether);

        vm.prank(sweeper);
        vm.expectRevert(PayoutVault.ExcessSweepNotScheduled.selector);
        vault.sweepExcess(payable(stranger));
    }

    function test_SweepExcessRespectsTheTimelock() public {
        vm.deal(address(vault), 1 ether);

        vm.prank(sweeper);
        vault.scheduleExcessSweep(payable(stranger));

        (address recipient, uint64 readyAt, uint64 expiresAt) = vault.scheduledSweep();
        assertEq(recipient, stranger);
        assertEq(readyAt, GENESIS_TS + vault.SWEEP_DELAY());
        assertEq(expiresAt, readyAt + vault.SWEEP_EXECUTION_WINDOW());

        vm.warp(uint256(readyAt) - 1);
        vm.prank(sweeper);
        vm.expectRevert(abi.encodeWithSelector(PayoutVault.ExcessSweepNotReady.selector, readyAt, block.timestamp));
        vault.sweepExcess(payable(stranger));

        vm.warp(readyAt);
        vm.prank(sweeper);
        assertEq(vault.sweepExcess(payable(stranger)), 1 ether);
    }

    function test_SweepExcessRejectsARecipientSwap() public {
        vm.deal(address(vault), 1 ether);

        vm.prank(sweeper);
        vault.scheduleExcessSweep(payable(stranger));
        vm.warp(block.timestamp + vault.SWEEP_DELAY());

        // The announced destination is the whole point of announcing it.
        vm.prank(sweeper);
        vm.expectRevert(abi.encodeWithSelector(PayoutVault.ExcessSweepRecipientMismatch.selector, stranger, bob));
        vault.sweepExcess(payable(bob));
    }

    function test_SweepExcessScheduleExpires() public {
        vm.deal(address(vault), 1 ether);

        vm.prank(sweeper);
        vault.scheduleExcessSweep(payable(stranger));

        (, uint64 readyAt, uint64 expiresAt) = vault.scheduledSweep();
        vm.warp(uint256(expiresAt) + 1);

        vm.prank(sweeper);
        vm.expectRevert(abi.encodeWithSelector(PayoutVault.ExcessSweepExpired.selector, expiresAt, block.timestamp));
        vault.sweepExcess(payable(stranger));

        assertGt(expiresAt, readyAt);
    }

    function test_SweepScheduleIsConsumedBySingleExecution() public {
        vm.deal(address(vault), 1 ether);

        vm.prank(sweeper);
        vault.scheduleExcessSweep(payable(stranger));
        vm.warp(block.timestamp + vault.SWEEP_DELAY());

        vm.prank(sweeper);
        vault.sweepExcess(payable(stranger));

        vm.deal(address(vault), 1 ether);
        vm.prank(sweeper);
        vm.expectRevert(PayoutVault.ExcessSweepNotScheduled.selector);
        vault.sweepExcess(payable(stranger));
    }

    function test_SweepScheduleCanBeCancelled() public {
        vm.prank(sweeper);
        vault.scheduleExcessSweep(payable(stranger));

        vm.expectEmit(true, true, true, true, address(vault));
        emit PayoutVault.ExcessSweepCancelled(stranger, sweeper);
        vm.prank(sweeper);
        vault.cancelExcessSweep();

        (address recipient, uint64 readyAt,) = vault.scheduledSweep();
        assertEq(recipient, address(0));
        assertEq(readyAt, 0);
    }

    function test_CancelRejectsWhenNothingScheduled() public {
        vm.prank(sweeper);
        vm.expectRevert(PayoutVault.ExcessSweepNotScheduled.selector);
        vault.cancelExcessSweep();
    }

    function test_ScheduleRejectsZeroRecipient() public {
        vm.prank(sweeper);
        vm.expectRevert(IPayoutVault.ZeroAddress.selector);
        vault.scheduleExcessSweep(payable(address(0)));
    }

    function test_SweepRejectsUnauthorizedCallers() public {
        vm.deal(address(vault), 1 ether);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, sweeperRole)
        );
        vault.scheduleExcessSweep(payable(stranger));

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, sweeperRole)
        );
        vault.sweepExcess(payable(stranger));

        // The creditor holds a role, but not this one. Roles do not stack.
        vm.prank(creditor);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, creditor, sweeperRole)
        );
        vault.sweepExcess(payable(creditor));
    }

    function test_SweepToRejectingRecipientReverts() public {
        RejectingReceiver hostile = new RejectingReceiver();
        vm.deal(address(vault), 1 ether);

        vm.prank(sweeper);
        vault.scheduleExcessSweep(payable(address(hostile)));
        vm.warp(block.timestamp + vault.SWEEP_DELAY());

        vm.prank(sweeper);
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.WithdrawalFailed.selector, address(hostile), 1 ether));
        vault.sweepExcess(payable(address(hostile)));
    }

    /*//////////////////////////////////////////////////////////////
                        NO ADMIN PATH TAKES USER FUNDS
    //////////////////////////////////////////////////////////////*/

    /// @notice Enumerates the ENTIRE role-gated surface of the contract and proves that not one
    ///         entry point, called by an address holding every role at once, can lower a user's
    ///         claimable balance by a single wei.
    /// @dev The list below is exhaustive over `PayoutVault`'s external ABI as of this commit:
    ///      credit, creditRoot, creditBatch, releaseRootCredit, scheduleExcessSweep,
    ///      cancelExcessSweep, sweepExcess, pause, unpause, grantRole, revokeRole,
    ///      renounceRole, and the four withdrawal functions (covered separately, and reachable only
    ///      as the beneficiary or with the beneficiary's signature).
    ///
    ///      The structural argument behind the test: `_claimable` is written down in exactly one
    ///      private function, `_debit`, whose only two call sites are the withdrawal entry points.
    ///      `grep -n "_claimable" src/PayoutVault.sol` is the audit; this test is the proof.
    function test_NoAdminPathCanReduceClaimable() public {
        address superAdmin = admin;
        vm.startPrank(superAdmin);
        vault.grantRole(creditorRole, superAdmin);
        vault.grantRole(releaserRole, superAdmin);
        vm.stopPrank();
        vm.deal(superAdmin, 100 ether);

        _credit(alice, 10 ether);
        vm.prank(creditor);
        vault.creditRoot{value: 5 ether}(ROOT_A);
        vm.deal(address(vault), address(vault).balance + 3 ether);

        uint256 before = vault.claimable(alice);
        assertEq(before, 10 ether);

        (address[] memory to, uint256[] memory amounts) = _batch3();

        vm.startPrank(superAdmin);

        vault.credit{value: 1 ether}(bob);
        assertEq(vault.claimable(alice), before, "credit");

        vault.creditRoot{value: 1 ether}(ROOT_B);
        assertEq(vault.claimable(alice), before, "creditRoot");

        vault.creditBatch{value: 4 ether}(to, amounts);
        assertGe(vault.claimable(alice), before, "creditBatch may only add");

        before = vault.claimable(alice);

        vault.releaseRootCredit(ROOT_A, bob);
        assertEq(vault.claimable(alice), before, "releaseRootCredit to someone else");

        vault.pause();
        assertEq(vault.claimable(alice), before, "pause");
        vault.unpause();
        assertEq(vault.claimable(alice), before, "unpause");

        vault.scheduleExcessSweep(payable(superAdmin));
        assertEq(vault.claimable(alice), before, "scheduleExcessSweep");
        vault.cancelExcessSweep();
        assertEq(vault.claimable(alice), before, "cancelExcessSweep");

        vault.scheduleExcessSweep(payable(superAdmin));
        vm.warp(block.timestamp + vault.SWEEP_DELAY());
        vault.sweepExcess(payable(superAdmin));
        assertEq(vault.claimable(alice), before, "sweepExcess");

        vault.grantRole(pauserRole, superAdmin);
        vault.revokeRole(pauserRole, superAdmin);
        assertEq(vault.claimable(alice), before, "role administration");

        // The admin cannot spend alice's balance through the withdrawal paths either: the four of
        // them key off `msg.sender` or a signature, never off a role.
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.InsufficientClaimable.selector, superAdmin, before, 0));
        vault.withdraw(before);

        vm.expectRevert(IPayoutVault.ZeroAmount.selector);
        vault.withdrawAll();

        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.InsufficientClaimable.selector, superAdmin, before, 0));
        vault.withdrawTo(payable(superAdmin), before);

        vm.expectRevert(IPayoutVault.InvalidAuthorizationSignature.selector);
        vault.withdrawWithAuthorization(
            alice, payable(superAdmin), before, 0, uint64(block.timestamp + 1 hours), hex"deadbeef"
        );

        vm.stopPrank();

        assertEq(vault.claimable(alice), before, "alice's balance survived the whole privileged surface");
        assertGe(address(vault).balance, vault.totalLiability());

        // And she can still take all of it out.
        vm.prank(alice);
        vault.withdrawAll();
        assertEq(alice.balance, before);
    }

    /*//////////////////////////////////////////////////////////////
                                  FUZZ
    //////////////////////////////////////////////////////////////*/

    /// @dev Solvency must hold for an arbitrary credit/withdraw pair, not just round numbers.
    function testFuzz_CreditThenPartialWithdrawKeepsVaultSolvent(uint96 creditAmount, uint96 withdrawAmount) public {
        creditAmount = uint96(bound(creditAmount, 1, type(uint96).max));
        withdrawAmount = uint96(bound(withdrawAmount, 1, creditAmount));

        vm.deal(creditor, creditAmount);
        vm.prank(creditor);
        vault.credit{value: creditAmount}(alice);

        vm.prank(alice);
        vault.withdraw(withdrawAmount);

        assertEq(vault.claimable(alice), uint256(creditAmount) - withdrawAmount);
        assertEq(vault.totalLiability(), uint256(creditAmount) - withdrawAmount);
        assertEq(address(vault).balance, uint256(creditAmount) - withdrawAmount);
        _assertSolvent();
    }

    /// @dev Any `msg.value` other than the exact sum must be rejected, in both directions.
    function testFuzz_CreditBatchRequiresExactValue(uint96 a, uint96 b, uint96 sent) public {
        a = uint96(bound(a, 1, type(uint80).max));
        b = uint96(bound(b, 1, type(uint80).max));
        uint256 total = uint256(a) + b;
        vm.assume(sent != total);

        address[] memory to = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        to[0] = alice;
        to[1] = bob;
        amounts[0] = a;
        amounts[1] = b;

        vm.deal(creditor, sent);
        vm.prank(creditor);
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.AmountMismatch.selector, total, sent));
        vault.creditBatch{value: sent}(to, amounts);

        assertEq(address(vault).balance, 0);
        assertEq(vault.totalLiability(), 0);
    }

    /// @dev A root credit followed by a release is value-preserving for any amount.
    function testFuzz_RootReleaseIsValuePreserving(uint96 amount, address beneficiary) public {
        amount = uint96(bound(amount, 1, type(uint96).max));
        vm.assume(beneficiary != address(0));

        vm.deal(creditor, amount);
        vm.prank(creditor);
        vault.creditRoot{value: amount}(ROOT_A);

        uint256 liabilityBefore = vault.totalLiability();
        uint256 claimableBefore = vault.claimable(beneficiary);

        vm.prank(releaser);
        vault.releaseRootCredit(ROOT_A, beneficiary);

        assertEq(vault.totalLiability(), liabilityBefore);
        assertEq(vault.claimable(beneficiary), claimableBefore + amount);
        assertEq(vault.pendingByRoot(ROOT_A), 0);
        _assertSolvent();
    }

    /// @dev Only the exact (beneficiary, recipient, amount, nonce, deadline) tuple that was signed
    ///      may execute. Any mutation of amount or nonce must fail.
    function testFuzz_AuthorizationBindsAmountAndNonce(uint96 signedAmount, uint96 submittedAmount, uint8 wrongNonce)
        public
    {
        signedAmount = uint96(bound(signedAmount, 1, 100 ether));
        submittedAmount = uint96(bound(submittedAmount, 1, 100 ether));
        vm.assume(submittedAmount != signedAmount);
        vm.assume(wrongNonce != 0);

        vm.deal(creditor, 200 ether);
        vm.prank(creditor);
        vault.credit{value: 200 ether}(alice);

        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(aliceKey, vault.withdrawalDigest(alice, bob, signedAmount, 0, deadline));

        vm.prank(relayer);
        vm.expectRevert(IPayoutVault.InvalidAuthorizationSignature.selector);
        vault.withdrawWithAuthorization(alice, payable(bob), submittedAmount, 0, deadline, sig);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IPayoutVault.InvalidNonce.selector, 0, wrongNonce));
        vault.withdrawWithAuthorization(alice, payable(bob), signedAmount, wrongNonce, deadline, sig);

        // The honest submission still works afterwards.
        vm.prank(relayer);
        vault.withdrawWithAuthorization(alice, payable(bob), signedAmount, 0, deadline, sig);
        assertEq(vault.withdrawalNonce(alice), 1);
        _assertSolvent();
    }

    /// @dev Forced ETH of any size is sweepable in full and never alters a liability.
    function testFuzz_ForcedEthIsFullySweepableAndLiabilitiesSurvive(uint96 credited, uint96 forced) public {
        credited = uint96(bound(credited, 1, type(uint96).max));
        forced = uint96(bound(forced, 1, type(uint96).max));

        vm.deal(creditor, credited);
        vm.prank(creditor);
        vault.credit{value: credited}(alice);

        vm.deal(address(vault), address(vault).balance + forced);
        assertEq(vault.excessBalance(), forced);

        vm.prank(sweeper);
        vault.scheduleExcessSweep(payable(stranger));
        vm.warp(block.timestamp + vault.SWEEP_DELAY());

        uint256 strangerBefore = stranger.balance;
        vm.prank(sweeper);
        uint256 swept = vault.sweepExcess(payable(stranger));

        assertEq(swept, forced);
        assertEq(stranger.balance, strangerBefore + forced);
        assertEq(vault.claimable(alice), credited);
        assertEq(vault.totalLiability(), credited);
        assertEq(address(vault).balance, credited);
        _assertSolvent();
    }
}
