// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {PayoutVault} from "../../src/PayoutVault.sol";
import {RootOwnershipRegistry} from "../../src/RootOwnershipRegistry.sol";
import {IBitcoinOwnershipOracle} from "../../src/interfaces/IBitcoinOwnershipOracle.sol";
import {IRootOwnershipRegistry} from "../../src/interfaces/IRootOwnershipRegistry.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";
import {AttestorSet} from "../helpers/AttestorSet.sol";
import {MerkleFixture} from "../helpers/MerkleFixture.sol";
import {MockOwnershipOracle} from "../mocks/MockOwnershipOracle.sol";

/// @title RootOwnershipRegistryTest
/// @notice Unit and fuzz suite for `RootOwnershipRegistry`.
/// @dev WHAT THIS SUITE DOES AND DOES NOT PROVE. It runs against `MockOwnershipOracle`, which by
///      its own honesty note performs NO signature recovery, NO quorum counting, NO attestor
///      membership check, NO deadline check and NO collection-membership check. Nothing here is
///      evidence that a 3-of-5 quorum is enforced — that property belongs to
///      `BitcoinOwnershipOracle`'s own suite. What the mock DOES keep honest is the one thing this
///      registry genuinely leans on: permanent, one-time digest consumption. Every replay assertion
///      below rests on that and on nothing else.
///
///      The `PayoutVault` used here is the REAL contract, not a mock, because the money claims in
///      this file ("Bob keeps what he earned", "pending releases to Charlie") are only meaningful
///      against real accounting.
///
///      CHEATCODE DISCIPLINE. `vm.expectRevert` and `vm.prank` bind to the very next external call,
///      and arguments are evaluated BEFORE that call. Every value needed inside an expectation is
///      therefore hoisted into a local first; an inline `registry.MINT_RECORDER_ROLE()` would eat
///      the cheatcode and make the assertion vacuous.
contract RootOwnershipRegistryTest is Test {
    /*//////////////////////////////////////////////////////////////
                                FIXTURES
    //////////////////////////////////////////////////////////////*/

    RootOwnershipRegistry internal registry;
    PayoutVault internal vault;
    MockOwnershipOracle internal oracle;
    AttestorSet internal attestors;

    address internal admin = makeAddr("timelock-admin");
    address internal guardian = makeAddr("guardian-pauser");
    address internal escrow = makeAddr("hoodpup-offer-escrow");
    address internal creditor = makeAddr("fee-router");
    address internal bob = makeAddr("bob-bitcoin-seller");
    address internal charlie = makeAddr("charlie-bitcoin-buyer");
    address internal watcher = makeAddr("permissionless-watcher");

    /// @dev Every fixture txid starts with the ASCII bytes "FIXTURE-NOT-REAL" so none of these
    ///      identities can be mistaken for a real Bitcoin Puppets inscription.
    bytes32 internal constant TXID_A = 0x464958545552452d4e4f542d5245414c00000000000000000000000000000001;
    bytes32 internal constant TXID_B = 0x464958545552452d4e4f542d5245414c00000000000000000000000000000002;

    uint32 internal constant INDEX_A = 0;
    uint32 internal constant INDEX_B = 7;

    bytes32 internal rootKeyA;
    bytes32 internal rootKeyB;

    bytes32 internal outpointOne = PuppetHashing.outpointHash(keccak256("FIXTURE-outpoint-1"), 0);
    bytes32 internal outpointTwo = PuppetHashing.outpointHash(keccak256("FIXTURE-outpoint-2"), 1);
    bytes32 internal outpointThree = PuppetHashing.outpointHash(keccak256("FIXTURE-outpoint-3"), 2);

    bytes32 internal scriptBob = keccak256("FIXTURE-scriptPubKey-bob");
    bytes32 internal scriptCharlie = keccak256("FIXTURE-scriptPubKey-charlie");

    uint64 internal constant HEIGHT_ONE = 880_000;
    uint64 internal constant HEIGHT_TWO = 880_500;
    uint64 internal constant HEIGHT_THREE = 881_000;

    /// @dev Cached role ids. Never read inline inside an expectation; see the contract NatSpec.
    bytes32 internal mintRecorderRole;
    bytes32 internal pauserRole;
    bytes32 internal defaultAdminRole;
    bytes32 internal rootReleaserRole;

    /// @dev A genuine Merkle proof over a two-member fixture. The mock oracle ignores it; it is
    ///      real anyway so the "forwarded verbatim" assertion is about a realistic payload.
    bytes32[] internal proofA;

    function setUp() public {
        vm.warp(1_760_000_000);

        oracle = new MockOwnershipOracle();
        vault = new PayoutVault(admin);
        registry = new RootOwnershipRegistry(admin, address(oracle), address(vault));
        attestors = new AttestorSet(5, "rootreg-suite");

        mintRecorderRole = registry.MINT_RECORDER_ROLE();
        pauserRole = registry.PAUSER_ROLE();
        defaultAdminRole = registry.DEFAULT_ADMIN_ROLE();
        rootReleaserRole = vault.ROOT_RELEASER_ROLE();

        vm.startPrank(admin);
        registry.grantRole(mintRecorderRole, escrow);
        registry.grantRole(pauserRole, guardian);
        vault.grantRole(vault.CREDITOR_ROLE(), creditor);
        vault.grantRole(rootReleaserRole, address(registry));
        vm.stopPrank();

        rootKeyA = PuppetHashing.rootKey(TXID_A, INDEX_A);
        rootKeyB = PuppetHashing.rootKey(TXID_B, INDEX_B);

        PuppetTypes.RootId[] memory roots = new PuppetTypes.RootId[](2);
        roots[0] = PuppetTypes.RootId({inscriptionTxid: TXID_A, inscriptionIndex: INDEX_A});
        roots[1] = PuppetTypes.RootId({inscriptionTxid: TXID_B, inscriptionIndex: INDEX_B});
        proofA = MerkleFixture.proofFromRoots(roots, 0);

        vm.deal(creditor, 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            BUILDER HELPERS
    //////////////////////////////////////////////////////////////*/

    function _bindAttestation(
        bytes32 txid,
        uint32 index,
        address beneficiary,
        bytes32 outpoint,
        bytes32 ownerScript,
        uint64 height,
        bytes32 authorizationId
    ) internal view returns (PuppetTypes.OwnershipAttestation memory a) {
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND);
        a.rootTxid = txid;
        a.rootIndex = index;
        a.contextId = PuppetHashing.rootKey(txid, index);
        a.offerTermsHash = bytes32(0);
        a.currentOutpointHash = outpoint;
        a.ownerScriptHash = ownerScript;
        a.bip322ProofHash = keccak256(abi.encode("FIXTURE-bip322", authorizationId));
        a.buyer = address(0);
        a.recipient = address(0);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.EVM);
        a.evmPayout = beneficiary;
        a.btcPayoutScriptHash = bytes32(0);
        a.sellerSats = 0;
        a.grossWei = 0;
        a.sellerWei = 0;
        a.bitcoinBlockHash = keccak256(abi.encode("FIXTURE-block", height));
        a.bitcoinHeight = height;
        a.authorizationId = authorizationId;
        a.deadline = uint64(block.timestamp + 1 hours);
        a.attestorEpoch = 1;
        a.policyVersion = 1;
    }

    function _spendAttestation(
        bytes32 txid,
        uint32 index,
        bytes32 previousOutpoint,
        uint64 height,
        bytes32 authorizationId
    ) internal view returns (PuppetTypes.RootSpendAttestation memory a) {
        a.rootTxid = txid;
        a.rootIndex = index;
        a.previousOutpointHash = previousOutpoint;
        a.spendingTxid = keccak256(abi.encode("FIXTURE-spend", authorizationId));
        a.bitcoinBlockHash = keccak256(abi.encode("FIXTURE-block", height));
        a.bitcoinHeight = height;
        a.authorizationId = authorizationId;
        a.deadline = uint64(block.timestamp + 1 hours);
        a.attestorEpoch = 1;
        a.policyVersion = 1;
    }

    function _sigsFor(PuppetTypes.OwnershipAttestation memory a) internal view returns (bytes[] memory) {
        return attestors.sign(oracle.hashOwnershipAttestation(a), 3);
    }

    function _sigsFor(PuppetTypes.RootSpendAttestation memory a) internal view returns (bytes[] memory) {
        return attestors.sign(oracle.hashRootSpendAttestation(a), 3);
    }

    /// @dev Bob's genesis epoch, exactly as the escrow would record it after a mint settlement.
    function _recordBobsMint() internal returns (uint64 epoch) {
        vm.prank(escrow);
        epoch = registry.recordMintOwnership(
            rootKeyA,
            bob,
            outpointOne,
            scriptBob,
            keccak256("FIXTURE-mint-ownership-digest"),
            keccak256("FIXTURE-bip322-mint"),
            keccak256("FIXTURE-block-880000"),
            HEIGHT_ONE
        );
    }

    function _creditRoot(bytes32 rootKey, uint256 amount) internal {
        vm.prank(creditor);
        vault.creditRoot{value: amount}(rootKey);
    }

    function _creditBeneficiary(address beneficiary, uint256 amount) internal {
        vm.prank(creditor);
        vault.credit{value: amount}(beneficiary);
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Wiring is immutable and reported honestly.
    function test_ConstructorWiring() public view {
        assertEq(address(registry.ORACLE()), address(oracle), "oracle pointer");
        assertEq(address(registry.PAYOUT_VAULT()), address(vault), "vault pointer");
        assertTrue(registry.hasRole(defaultAdminRole, admin), "admin has default admin");
        assertTrue(registry.hasRole(pauserRole, admin), "admin has pauser");
        assertFalse(registry.paused(), "starts unpaused");
    }

    /// @notice `MINT_RECORDER_ROLE` is not pre-granted to anyone at construction.
    function test_ConstructorGrantsOnlyGovernanceRoles() public {
        RootOwnershipRegistry fresh = new RootOwnershipRegistry(admin, address(oracle), address(vault));

        assertFalse(fresh.hasRole(mintRecorderRole, admin), "admin must not be a mint recorder");
        assertFalse(fresh.hasRole(mintRecorderRole, address(this)), "deployer must not be a mint recorder");
        assertEq(fresh.getRoleAdmin(mintRecorderRole), defaultAdminRole, "role admin");
    }

    /// @notice Each zero constructor argument is rejected.
    function test_ConstructorRejectsZeroAddresses() public {
        vm.expectRevert(IRootOwnershipRegistry.ZeroAddress.selector);
        new RootOwnershipRegistry(address(0), address(oracle), address(vault));

        vm.expectRevert(IRootOwnershipRegistry.ZeroAddress.selector);
        new RootOwnershipRegistry(admin, address(0), address(vault));

        vm.expectRevert(IRootOwnershipRegistry.ZeroAddress.selector);
        new RootOwnershipRegistry(admin, address(oracle), address(0));
    }

    /// @notice The constructor announces its wiring exactly once.
    function test_ConstructorEmitsRegistryInitialized() public {
        vm.expectEmit(true, true, true, true);
        emit RootOwnershipRegistry.RegistryInitialized(admin, address(oracle), address(vault));
        new RootOwnershipRegistry(admin, address(oracle), address(vault));
    }

    /// @notice ERC-165 advertises the registry interface.
    function test_SupportsInterface() public view {
        assertTrue(registry.supportsInterface(type(IRootOwnershipRegistry).interfaceId), "registry interface");
        assertTrue(registry.supportsInterface(type(IAccessControl).interfaceId), "access control interface");
        assertFalse(registry.supportsInterface(0xdeadbeef), "unknown interface");
    }

    /*//////////////////////////////////////////////////////////////
                       ACTIVATION FROM A MINT
    //////////////////////////////////////////////////////////////*/

    /// @notice The escrow's mint recording opens epoch 1 and binds every fact it was handed.
    function test_RecordMintOwnershipCreatesEpochOne() public {
        bytes32 digest = keccak256("FIXTURE-mint-ownership-digest");

        vm.expectEmit(true, true, true, true);
        emit IRootOwnershipRegistry.RootEpochActivated(rootKeyA, 1, bob, outpointOne, scriptBob, HEIGHT_ONE, digest);
        uint64 epoch = _recordBobsMint();

        assertEq(epoch, 1, "first epoch is 1");

        PuppetTypes.RootState memory s = registry.currentState(rootKeyA);
        assertEq(s.epoch, 1, "state epoch");
        assertTrue(s.active, "active");
        assertEq(s.currentOutpointHash, outpointOne, "outpoint");
        assertEq(s.ownerScriptHash, scriptBob, "owner script");
        assertEq(s.beneficiary, bob, "beneficiary");
        assertEq(s.ownershipDigest, digest, "ownership digest");
        assertEq(s.bip322ProofHash, keccak256("FIXTURE-bip322-mint"), "bip322 proof hash");
        assertEq(s.verifiedBitcoinHeight, HEIGHT_ONE, "verified height");
        assertEq(s.lastBitcoinBlockHash, keccak256("FIXTURE-block-880000"), "block hash");
        assertEq(s.invalidatingSpendTxid, bytes32(0), "no spend txid yet");

        (address beneficiary, bool active, uint64 currentEpoch) = registry.currentBeneficiary(rootKeyA);
        assertEq(beneficiary, bob, "currentBeneficiary address");
        assertTrue(active, "currentBeneficiary active");
        assertEq(currentEpoch, 1, "currentBeneficiary epoch");
        assertTrue(registry.isActive(rootKeyA), "isActive");
        assertEq(registry.epochOf(rootKeyA), 1, "epochOf");

        PuppetTypes.RootEpochInfo memory info = registry.epochInfo(rootKeyA, 1);
        assertEq(info.beneficiary, bob, "history beneficiary");
        assertEq(info.outpointHash, outpointOne, "history outpoint");
        assertEq(info.ownerScriptHash, scriptBob, "history script");
        assertEq(info.activatedAtBitcoinHeight, HEIGHT_ONE, "history activation height");
        assertEq(info.activatedAtBlockTimestamp, uint64(block.timestamp), "history activation timestamp");
        assertEq(info.deactivatedAtBitcoinHeight, 0, "history still open");
        assertEq(info.deactivatedAtBlockTimestamp, 0, "history still open");
        assertEq(info.ownershipDigest, digest, "history digest");
    }

    /// @notice Only `MINT_RECORDER_ROLE` may record a mint, and the admin does not hold it.
    function test_RecordMintOwnership_RevertsForUnauthorizedCaller() public {
        bytes32 role = mintRecorderRole;

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, role));
        vm.prank(admin);
        registry.recordMintOwnership(
            rootKeyA,
            bob,
            outpointOne,
            scriptBob,
            keccak256("FIXTURE-d"),
            keccak256("FIXTURE-p"),
            keccak256("FIXTURE-b"),
            1
        );

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), role)
        );
        registry.recordMintOwnership(
            rootKeyA,
            bob,
            outpointOne,
            scriptBob,
            keccak256("FIXTURE-d"),
            keccak256("FIXTURE-p"),
            keccak256("FIXTURE-b"),
            1
        );
    }

    /// @notice A second mint recording against a live Root is refused, not silently applied.
    function test_RecordMintOwnership_RevertsOnDuplicateWhileActive() public {
        _recordBobsMint();

        vm.expectRevert(abi.encodeWithSelector(IRootOwnershipRegistry.RootAlreadyActive.selector, rootKeyA, uint64(1)));
        vm.prank(escrow);
        registry.recordMintOwnership(
            rootKeyA,
            charlie,
            outpointTwo,
            scriptCharlie,
            keccak256("FIXTURE-d2"),
            keccak256("FIXTURE-p2"),
            keccak256("FIXTURE-b2"),
            HEIGHT_TWO
        );

        // The attempted overwrite left nothing behind.
        (address beneficiary,, uint64 epoch) = registry.currentBeneficiary(rootKeyA);
        assertEq(beneficiary, bob, "beneficiary unchanged");
        assertEq(epoch, 1, "epoch unchanged");
    }

    /// @notice A Root whose epoch has been CLOSED still refuses a second mint, with a truthful
    ///         error: it is not "already active", its history has simply already begun.
    function test_RecordMintOwnership_RevertsWhenClosedEpochExists() public {
        _recordBobsMint();
        _invalidateBobsEpoch();

        vm.expectRevert(
            abi.encodeWithSelector(RootOwnershipRegistry.RootEpochAlreadyExists.selector, rootKeyA, uint64(1))
        );
        vm.prank(escrow);
        registry.recordMintOwnership(
            rootKeyA,
            charlie,
            outpointTwo,
            scriptCharlie,
            keccak256("FIXTURE-d2"),
            keccak256("FIXTURE-p2"),
            keccak256("FIXTURE-b2"),
            HEIGHT_THREE
        );
    }

    /// @notice Every structurally empty argument is rejected.
    function test_RecordMintOwnership_RejectsEmptyFacts() public {
        vm.startPrank(escrow);

        vm.expectRevert(IRootOwnershipRegistry.ZeroRootKey.selector);
        registry.recordMintOwnership(
            bytes32(0),
            bob,
            outpointOne,
            scriptBob,
            keccak256("FIXTURE-d"),
            keccak256("FIXTURE-p"),
            keccak256("FIXTURE-b"),
            HEIGHT_ONE
        );

        vm.expectRevert(IRootOwnershipRegistry.InvalidBeneficiary.selector);
        registry.recordMintOwnership(
            rootKeyA,
            address(0),
            outpointOne,
            scriptBob,
            keccak256("FIXTURE-d"),
            keccak256("FIXTURE-p"),
            keccak256("FIXTURE-b"),
            HEIGHT_ONE
        );

        vm.expectRevert(RootOwnershipRegistry.ZeroOutpointHash.selector);
        registry.recordMintOwnership(
            rootKeyA,
            bob,
            bytes32(0),
            scriptBob,
            keccak256("FIXTURE-d"),
            keccak256("FIXTURE-p"),
            keccak256("FIXTURE-b"),
            HEIGHT_ONE
        );

        vm.expectRevert(RootOwnershipRegistry.ZeroScriptHash.selector);
        registry.recordMintOwnership(
            rootKeyA,
            bob,
            outpointOne,
            bytes32(0),
            keccak256("FIXTURE-d"),
            keccak256("FIXTURE-p"),
            keccak256("FIXTURE-b"),
            HEIGHT_ONE
        );

        vm.expectRevert(RootOwnershipRegistry.ZeroOwnershipDigest.selector);
        registry.recordMintOwnership(
            rootKeyA,
            bob,
            outpointOne,
            scriptBob,
            bytes32(0),
            keccak256("FIXTURE-p"),
            keccak256("FIXTURE-b"),
            HEIGHT_ONE
        );

        vm.stopPrank();
    }

    /// @notice The mint path touches the vault not at all, so a vault misconfiguration can never
    ///         make a mint settlement fail.
    function test_RecordMintOwnershipMakesNoVaultCall() public {
        _creditRoot(rootKeyA, 3 ether);

        // Strip the registry of its releaser role AND pause the vault: the mint must still record.
        vm.startPrank(admin);
        vault.revokeRole(rootReleaserRole, address(registry));
        vault.pause();
        vm.stopPrank();

        uint64 epoch = _recordBobsMint();

        assertEq(epoch, 1, "recorded regardless of vault state");
        assertEq(vault.pendingByRoot(rootKeyA), 3 ether, "pending bucket untouched");
        assertEq(vault.claimable(bob), 0, "no credit invented");
    }

    /// @notice Pausing the registry must not brick the escrow's settlement path.
    function test_RecordMintOwnershipWorksWhilePaused() public {
        vm.prank(guardian);
        registry.pauseActivations();

        uint64 epoch = _recordBobsMint();
        assertEq(epoch, 1, "mint recording is not pausable");
    }

    /*//////////////////////////////////////////////////////////////
                       PERMISSIONLESS REBINDING
    //////////////////////////////////////////////////////////////*/

    /// @notice A Root with no history can be activated permissionlessly by a valid bind.
    function test_BindRootOwnerActivatesFirstEpoch() public {
        PuppetTypes.OwnershipAttestation memory a =
            _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-1"));
        bytes[] memory sigs = _sigsFor(a);
        bytes32 digest = oracle.hashOwnershipAttestation(a);

        vm.expectEmit(true, true, true, true);
        emit IRootOwnershipRegistry.RootEpochActivated(rootKeyA, 1, bob, outpointOne, scriptBob, HEIGHT_ONE, digest);
        vm.prank(watcher);
        (uint64 epoch, uint256 released) = registry.bindRootOwner(a, sigs, proofA);

        assertEq(epoch, 1, "epoch");
        assertEq(released, 0, "nothing pending");
        assertEq(registry.currentState(rootKeyA).ownershipDigest, digest, "digest recorded from the oracle");
    }

    /// @notice Anyone at all may submit a bind; there is no allowlist.
    function testFuzz_BindRootOwnerIsPermissionless(address caller) public {
        vm.assume(caller != address(0) && caller != address(vault) && caller != address(registry));
        vm.assume(caller.code.length == 0);

        PuppetTypes.OwnershipAttestation memory a =
            _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-any"));
        bytes[] memory sigs = _sigsFor(a);

        vm.prank(caller);
        (uint64 epoch,) = registry.bindRootOwner(a, sigs, proofA);
        assertEq(epoch, 1, "any caller may bind");
    }

    /// @notice After Bob's epoch is closed, Charlie's bind opens epoch 2.
    function test_BindRootOwnerIncrementsEpochAfterInvalidation() public {
        _recordBobsMint();
        _invalidateBobsEpoch();

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointTwo, scriptCharlie, HEIGHT_THREE, keccak256("FIXTURE-auth-c")
        );
        bytes[] memory sigs = _sigsFor(a);

        vm.prank(charlie);
        (uint64 epoch,) = registry.bindRootOwner(a, sigs, proofA);

        assertEq(epoch, 2, "epoch incremented");
        PuppetTypes.RootState memory s = registry.currentState(rootKeyA);
        assertTrue(s.active, "reactivated");
        assertEq(s.beneficiary, charlie, "new beneficiary");
        assertEq(s.currentOutpointHash, outpointTwo, "new outpoint");
        assertEq(s.invalidatingSpendTxid, bytes32(0), "stale spend txid cleared on a new epoch");
    }

    /// @notice A bind may supersede a STILL-ACTIVE epoch when the inscription demonstrably moved.
    ///         This is the escape hatch that lets Charlie stop the stale-watcher bleed himself.
    function test_BindRootOwnerSupersedesActiveEpoch() public {
        _recordBobsMint();

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointTwo, scriptCharlie, HEIGHT_TWO, keccak256("FIXTURE-auth-sup")
        );
        bytes[] memory sigs = _sigsFor(a);

        vm.expectEmit(true, true, true, true);
        emit RootOwnershipRegistry.RootEpochSuperseded(rootKeyA, 1, bob, 2, HEIGHT_TWO);
        vm.prank(charlie);
        (uint64 epoch,) = registry.bindRootOwner(a, sigs, proofA);

        assertEq(epoch, 2, "epoch");
        assertEq(_beneficiaryOf(rootKeyA), charlie, "beneficiary replaced");

        // The superseded epoch's history record is closed, not rewritten.
        PuppetTypes.RootEpochInfo memory closed = registry.epochInfo(rootKeyA, 1);
        assertEq(closed.beneficiary, bob, "history keeps Bob");
        assertEq(closed.deactivatedAtBitcoinHeight, HEIGHT_TWO, "history closed at the new height");
        assertEq(closed.deactivatedAtBlockTimestamp, uint64(block.timestamp), "history closed now");
    }

    /// @notice The same owner may re-bind after moving their own inscription to a new outpoint.
    function test_BindRootOwnerSameBeneficiaryNewOutpoint() public {
        _recordBobsMint();

        PuppetTypes.OwnershipAttestation memory a =
            _bindAttestation(TXID_A, INDEX_A, bob, outpointTwo, scriptBob, HEIGHT_TWO, keccak256("FIXTURE-auth-move"));
        bytes[] memory sigs = _sigsFor(a);

        vm.prank(bob);
        (uint64 epoch,) = registry.bindRootOwner(a, sigs, proofA);

        assertEq(epoch, 2, "epoch");
        assertEq(_beneficiaryOf(rootKeyA), bob, "still Bob");
    }

    /// @notice Rebinding the SAME outpoint while active is refused: nothing moved on Bitcoin, so
    ///         nothing justifies re-pointing the beneficiary.
    function test_BindRootOwner_RevertsUnchangedOutpointWhileActive() public {
        _recordBobsMint();

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointOne, scriptCharlie, HEIGHT_TWO, keccak256("FIXTURE-auth-x")
        );
        bytes[] memory sigs = _sigsFor(a);

        vm.expectRevert(abi.encodeWithSelector(IRootOwnershipRegistry.UnchangedOutpoint.selector, outpointOne));
        registry.bindRootOwner(a, sigs, proofA);
    }

    /// @notice Once the Root is INACTIVE the unchanged-outpoint restriction lifts.
    function test_BindRootOwnerAllowsSameOutpointOnceInactive() public {
        _recordBobsMint();
        _invalidateBobsEpoch();

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointOne, scriptCharlie, HEIGHT_THREE, keccak256("FIXTURE-auth-same")
        );
        bytes[] memory sigs = _sigsFor(a);

        vm.prank(charlie);
        (uint64 epoch,) = registry.bindRootOwner(a, sigs, proofA);
        assertEq(epoch, 2, "inactive roots accept any outpoint");
    }

    /// @notice A proof of control older than the newest recorded Bitcoin fact is refused.
    function test_BindRootOwner_RevertsStaleBitcoinHeight() public {
        _recordBobsMint();

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointTwo, scriptCharlie, HEIGHT_ONE - 1, keccak256("FIXTURE-auth-stale")
        );
        bytes[] memory sigs = _sigsFor(a);

        vm.expectRevert(
            abi.encodeWithSelector(IRootOwnershipRegistry.StaleBitcoinHeight.selector, HEIGHT_ONE - 1, HEIGHT_ONE)
        );
        registry.bindRootOwner(a, sigs, proofA);
    }

    /// @notice Equal-height updates are accepted only when they identify the same Bitcoin block.
    function test_BindRootOwnerAcceptsEqualBitcoinHeightInTheSameBlock() public {
        _recordBobsMint();

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointTwo, scriptCharlie, HEIGHT_ONE, keccak256("FIXTURE-auth-eq")
        );
        a.bitcoinBlockHash = keccak256("FIXTURE-block-880000");
        bytes[] memory sigs = _sigsFor(a);

        (uint64 epoch,) = registry.bindRootOwner(a, sigs, proofA);
        assertEq(epoch, 2, "same height and same block is accepted");
    }

    /// @notice Two different blocks cannot both be canonical at the same Bitcoin height.
    function test_BindRootOwnerRejectsConflictingBlockAtEqualBitcoinHeight() public {
        _recordBobsMint();

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointTwo, scriptCharlie, HEIGHT_ONE, keccak256("FIXTURE-auth-fork")
        );
        bytes32 recordedBlockHash = keccak256("FIXTURE-block-880000");
        bytes[] memory sigs = _sigsFor(a);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRootOwnershipRegistry.ConflictingBitcoinBlockAtHeight.selector,
                HEIGHT_ONE,
                recordedBlockHash,
                a.bitcoinBlockHash
            )
        );
        registry.bindRootOwner(a, sigs, proofA);
    }

    /// @notice An invalidation advances the recorded height, so a pre-spend proof cannot reinstate
    ///         the old owner afterwards.
    function test_BindRootOwner_RevertsWithPreSpendProofAfterInvalidation() public {
        _recordBobsMint();

        // Spend observed high up the chain.
        PuppetTypes.RootSpendAttestation memory spend =
            _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_THREE, keccak256("FIXTURE-auth-spend"));
        bytes[] memory spendSigs = _sigsFor(spend);
        vm.prank(watcher);
        registry.invalidateRoot(spend, spendSigs, proofA);

        // Bob kept a valid, older attestation from before the sale.
        PuppetTypes.OwnershipAttestation memory a =
            _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_TWO, keccak256("FIXTURE-auth-old"));
        bytes[] memory sigs = _sigsFor(a);

        vm.expectRevert(
            abi.encodeWithSelector(IRootOwnershipRegistry.StaleBitcoinHeight.selector, HEIGHT_TWO, HEIGHT_THREE)
        );
        registry.bindRootOwner(a, sigs, proofA);
    }

    /// @notice Only `ROOT_BIND` reaches this path; the four other purposes are rejected.
    function test_BindRootOwner_RevertsForEveryOtherPurpose() public {
        uint8[4] memory purposes = [
            uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT),
            uint8(PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT),
            uint8(PuppetTypes.AuthorizationPurpose.SELF_CAST),
            uint8(PuppetTypes.AuthorizationPurpose.ROOT_INVALIDATE)
        ];

        for (uint256 i = 0; i < purposes.length; i++) {
            PuppetTypes.OwnershipAttestation memory a =
                _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-p"));
            a.purpose = purposes[i];
            bytes[] memory sigs = _sigsFor(a);

            vm.expectRevert(abi.encodeWithSelector(IRootOwnershipRegistry.UnsupportedPurpose.selector, purposes[i]));
            registry.bindRootOwner(a, sigs, proofA);
        }
    }

    /// @notice A non-EVM payout mode carries no EVM address to bind.
    function test_BindRootOwner_RevertsForNonEvmPayoutMode() public {
        uint8[2] memory modes = [uint8(PuppetTypes.PayoutMode.NONE), uint8(PuppetTypes.PayoutMode.BTC)];

        for (uint256 i = 0; i < modes.length; i++) {
            PuppetTypes.OwnershipAttestation memory a =
                _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-m"));
            a.payoutMode = modes[i];
            bytes[] memory sigs = _sigsFor(a);

            vm.expectRevert(abi.encodeWithSelector(RootOwnershipRegistry.UnsupportedPayoutMode.selector, modes[i]));
            registry.bindRootOwner(a, sigs, proofA);
        }
    }

    /// @notice Every structurally empty field on the bind path is rejected before the oracle call.
    /// @dev Each case rebuilds the attestation from scratch. A memory struct assigned from another
    ///      memory struct is an ALIAS, not a copy, so reusing a `base` local would carry each
    ///      mutation into the next case and silently collapse this into one assertion.
    function test_BindRootOwner_RejectsEmptyFields() public {
        PuppetTypes.OwnershipAttestation memory a =
            _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-e1"));
        a.evmPayout = address(0);
        bytes[] memory sigs = _sigsFor(a);
        vm.expectRevert(IRootOwnershipRegistry.InvalidBeneficiary.selector);
        registry.bindRootOwner(a, sigs, proofA);

        a = _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-e2"));
        a.rootTxid = bytes32(0);
        a.contextId = bytes32(0);
        sigs = _sigsFor(a);
        vm.expectRevert(RootOwnershipRegistry.ZeroRootTxid.selector);
        registry.bindRootOwner(a, sigs, proofA);

        a = _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-e3"));
        a.currentOutpointHash = bytes32(0);
        sigs = _sigsFor(a);
        vm.expectRevert(RootOwnershipRegistry.ZeroOutpointHash.selector);
        registry.bindRootOwner(a, sigs, proofA);

        a = _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-e4"));
        a.ownerScriptHash = bytes32(0);
        sigs = _sigsFor(a);
        vm.expectRevert(RootOwnershipRegistry.ZeroScriptHash.selector);
        registry.bindRootOwner(a, sigs, proofA);

        a = _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-e5"));
        a.authorizationId = bytes32(0);
        sigs = _sigsFor(a);
        vm.expectRevert(RootOwnershipRegistry.ZeroAuthorizationId.selector);
        registry.bindRootOwner(a, sigs, proofA);

        assertEq(registry.epochOf(rootKeyA), 0, "no malformed bind created an epoch");
    }

    /// @notice `contextId` must be zero or the Root's own key; a foreign context is rejected.
    function test_BindRootOwner_ContextIdRules() public {
        PuppetTypes.OwnershipAttestation memory a =
            _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-ctx-0"));
        a.contextId = bytes32(0);
        registry.bindRootOwner(a, _sigsFor(a), proofA);
        assertEq(registry.epochOf(rootKeyA), 1, "zero context accepted");

        PuppetTypes.OwnershipAttestation memory b =
            _bindAttestation(TXID_B, INDEX_B, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-ctx-x"));
        b.contextId = keccak256("some-offer-id");
        bytes[] memory sigs = _sigsFor(b);

        vm.expectRevert(abi.encodeWithSelector(RootOwnershipRegistry.InvalidBindContext.selector, b.contextId));
        registry.bindRootOwner(b, sigs, proofA);
    }

    /// @notice A consumed attestation can never be replayed; the oracle burns the digest.
    function test_BindRootOwner_RevertsOnDigestReplay() public {
        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-replay")
        );
        bytes[] memory sigs = _sigsFor(a);
        bytes32 digest = oracle.hashOwnershipAttestation(a);

        registry.bindRootOwner(a, sigs, proofA);

        // Close the epoch at the SAME Bitcoin height, so the replay below is not stopped early by
        // the height guard and genuinely reaches the oracle's consumption check.
        PuppetTypes.RootSpendAttestation memory spend =
            _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_ONE, keccak256("FIXTURE-auth-replay-close"));
        bytes[] memory spendSigs = _sigsFor(spend);
        vm.prank(watcher);
        registry.invalidateRoot(spend, spendSigs, proofA);

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.DigestAlreadyConsumed.selector, digest));
        registry.bindRootOwner(a, sigs, proofA);
    }

    /// @notice Signatures and the collection proof are forwarded to the oracle untouched.
    function test_BindRootOwnerForwardsSignaturesAndProofVerbatim() public {
        PuppetTypes.OwnershipAttestation memory a =
            _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-fwd"));
        bytes[] memory sigs = attestors.sign(oracle.hashOwnershipAttestation(a), 4);

        vm.prank(watcher);
        registry.bindRootOwner(a, sigs, proofA);

        MockOwnershipOracle.OwnershipRecord memory record = oracle.lastOwnership();
        assertEq(record.signatureCount, 4, "all signatures forwarded");
        assertEq(record.proofLength, proofA.length, "proof forwarded");
        assertEq(record.consumer, address(registry), "registry is the consumer");
        assertEq(record.purpose, uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND), "purpose forwarded");
        assertEq(record.rootKey, rootKeyA, "root key");
    }

    /// @notice If the oracle refuses, nothing at all is recorded.
    function test_BindRootOwner_OracleFailureLeavesNoState() public {
        PuppetTypes.OwnershipAttestation memory a =
            _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-fail"));
        bytes[] memory sigs = _sigsFor(a);

        oracle.setNextCallReverts(true);
        vm.expectRevert(MockOwnershipOracle.MockOracleForcedRevert.selector);
        registry.bindRootOwner(a, sigs, proofA);

        assertEq(registry.epochOf(rootKeyA), 0, "no epoch created");
        assertFalse(registry.isActive(rootKeyA), "not active");
    }

    /// @notice A rootKey disagreement between registry and oracle aborts rather than records.
    /// @dev Driven with `vm.mockCall` because the honest mock derives the key the same way the
    ///      registry does; the guard exists for a future oracle whose hashing has drifted.
    function test_BindRootOwner_RevertsOnOracleRootKeyDisagreement() public {
        PuppetTypes.OwnershipAttestation memory a =
            _bindAttestation(TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-div"));
        bytes[] memory sigs = _sigsFor(a);
        bytes32 wrongKey = keccak256("a-different-root");

        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(IBitcoinOwnershipOracle.consumeOwnership.selector),
            abi.encode(keccak256("digest"), wrongKey)
        );

        vm.expectRevert(abi.encodeWithSelector(IRootOwnershipRegistry.RootMismatch.selector, rootKeyA, wrongKey));
        registry.bindRootOwner(a, sigs, proofA);
        vm.clearMockedCalls();
    }

    /*//////////////////////////////////////////////////////////////
                         PENDING ROOT RELEASE
    //////////////////////////////////////////////////////////////*/

    /// @notice A bind sweeps the Root's pending bucket to the newly proven owner.
    function test_BindRootOwnerReleasesPendingToNewOwner() public {
        _recordBobsMint();
        _invalidateBobsEpoch();
        _creditRoot(rootKeyA, 5 ether);

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointTwo, scriptCharlie, HEIGHT_THREE, keccak256("FIXTURE-auth-rel")
        );
        bytes[] memory sigs = _sigsFor(a);

        vm.expectEmit(true, true, true, true);
        emit IRootOwnershipRegistry.RootPendingReleased(rootKeyA, charlie, 5 ether);
        vm.prank(charlie);
        (, uint256 released) = registry.bindRootOwner(a, sigs, proofA);

        assertEq(released, 5 ether, "released amount reported");
        assertEq(vault.pendingByRoot(rootKeyA), 0, "bucket drained");
        assertEq(vault.claimable(charlie), 5 ether, "Charlie can withdraw it");
    }

    /// @notice An empty pending bucket is the normal case and must not fail the bind.
    function test_BindRootOwnerWithNoPendingReleasesNothing() public {
        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-nopend")
        );
        bytes[] memory sigs = _sigsFor(a);

        vm.recordLogs();
        (, uint256 released) = registry.bindRootOwner(a, sigs, proofA);

        assertEq(released, 0, "nothing released");
        // No RootPendingReleased may be emitted when nothing moved.
        bytes32 topic = IRootOwnershipRegistry.RootPendingReleased.selector;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length == 0) continue;
            assertTrue(logs[i].topics[0] != topic, "no phantom release event");
        }
    }

    /// @notice A bind is atomic with its money routing: if the release cannot happen, no epoch
    ///         opens. The alternative would strand the pending balance with no path out.
    function test_BindRootOwner_RevertsWhenReleaserRoleMissing() public {
        _creditRoot(rootKeyA, 2 ether);

        vm.prank(admin);
        vault.revokeRole(rootReleaserRole, address(registry));

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, bob, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-norole")
        );
        bytes[] memory sigs = _sigsFor(a);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(registry), rootReleaserRole
            )
        );
        registry.bindRootOwner(a, sigs, proofA);

        assertEq(registry.epochOf(rootKeyA), 0, "no epoch opened");
        assertEq(vault.pendingByRoot(rootKeyA), 2 ether, "pending intact");
    }

    /// @notice The standalone forwarder pays only the address already recorded, and only while the
    ///         record is active.
    function test_ReleasePendingRootCreditForwardsToRecordedOwner() public {
        _recordBobsMint();
        _creditRoot(rootKeyA, 1 ether);

        vm.expectEmit(true, true, true, true);
        emit IRootOwnershipRegistry.RootPendingReleased(rootKeyA, bob, 1 ether);
        vm.prank(watcher);
        uint256 amount = registry.releasePendingRootCredit(rootKeyA);

        assertEq(amount, 1 ether, "amount");
        assertEq(vault.claimable(bob), 1 ether, "credited to the recorded owner");
        assertEq(vault.pendingByRoot(rootKeyA), 0, "bucket drained");
    }

    /// @notice It refuses on an inactive Root, where the correct destination is unknown.
    function test_ReleasePendingRootCredit_RevertsWhenInactive() public {
        _recordBobsMint();
        _invalidateBobsEpoch();
        _creditRoot(rootKeyA, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(IRootOwnershipRegistry.RootNotActive.selector, rootKeyA));
        registry.releasePendingRootCredit(rootKeyA);

        vm.expectRevert(abi.encodeWithSelector(IRootOwnershipRegistry.RootNotActive.selector, rootKeyB));
        registry.releasePendingRootCredit(rootKeyB);
    }

    /// @notice It refuses when there is nothing to forward.
    function test_ReleasePendingRootCredit_RevertsWhenEmpty() public {
        _recordBobsMint();

        vm.expectRevert(abi.encodeWithSelector(RootOwnershipRegistry.NoPendingRootBalance.selector, rootKeyA));
        registry.releasePendingRootCredit(rootKeyA);
    }

    /// @notice Forwarding money the protocol already owes is never blocked by a pause.
    function test_ReleasePendingRootCreditWorksWhilePaused() public {
        _recordBobsMint();
        _creditRoot(rootKeyA, 1 ether);

        vm.prank(guardian);
        registry.pauseActivations();

        uint256 amount = registry.releasePendingRootCredit(rootKeyA);
        assertEq(amount, 1 ether, "release is not pausable");
    }

    /*//////////////////////////////////////////////////////////////
                             INVALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @dev Close Bob's epoch 1 with a spend attestation at HEIGHT_TWO.
    function _invalidateBobsEpoch() internal {
        PuppetTypes.RootSpendAttestation memory spend =
            _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_TWO, keccak256("FIXTURE-auth-invalidate"));
        bytes[] memory sigs = _sigsFor(spend);
        vm.prank(watcher);
        registry.invalidateRoot(spend, sigs, proofA);
    }

    /// @notice A valid spend attestation closes the epoch and records the spending txid.
    function test_InvalidateRootClosesEpoch() public {
        _recordBobsMint();

        PuppetTypes.RootSpendAttestation memory spend =
            _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_TWO, keccak256("FIXTURE-auth-inv"));
        bytes[] memory sigs = _sigsFor(spend);

        vm.expectEmit(true, true, true, true);
        emit IRootOwnershipRegistry.RootEpochInvalidated(rootKeyA, 1, bob, spend.spendingTxid, HEIGHT_TWO);
        vm.prank(watcher);
        registry.invalidateRoot(spend, sigs, proofA);

        PuppetTypes.RootState memory s = registry.currentState(rootKeyA);
        assertFalse(s.active, "inactive");
        assertEq(s.epoch, 1, "epoch is not bumped by an invalidation");
        assertEq(s.invalidatingSpendTxid, spend.spendingTxid, "spending txid recorded");
        assertEq(s.verifiedBitcoinHeight, HEIGHT_TWO, "height advanced to the spend");
        assertEq(s.lastBitcoinBlockHash, spend.bitcoinBlockHash, "block hash advanced");

        // Preserved for the audit trail.
        assertEq(s.beneficiary, bob, "historical beneficiary preserved");
        assertEq(s.currentOutpointHash, outpointOne, "spent outpoint preserved");
        assertEq(s.ownerScriptHash, scriptBob, "owner script preserved");

        (address beneficiary, bool active,) = registry.currentBeneficiary(rootKeyA);
        assertEq(beneficiary, bob, "still reported, for history");
        assertFalse(active, "but not payable");

        PuppetTypes.RootEpochInfo memory info = registry.epochInfo(rootKeyA, 1);
        assertEq(info.deactivatedAtBitcoinHeight, HEIGHT_TWO, "history deactivation height");
        assertEq(info.deactivatedAtBlockTimestamp, uint64(block.timestamp), "history deactivation timestamp");
        assertEq(info.beneficiary, bob, "history beneficiary never rewritten");
    }

    /// @notice Anyone may close an epoch; that is what bounds the stale-watcher window.
    function testFuzz_InvalidateRootIsPermissionless(address caller) public {
        vm.assume(caller != address(0) && caller.code.length == 0);
        _recordBobsMint();

        PuppetTypes.RootSpendAttestation memory spend =
            _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_TWO, keccak256("FIXTURE-auth-any-watcher"));
        bytes[] memory sigs = _sigsFor(spend);

        vm.prank(caller);
        registry.invalidateRoot(spend, sigs, proofA);
        assertFalse(registry.isActive(rootKeyA), "any caller may invalidate");
    }

    /// @notice An attestation about a different outpoint cannot close this epoch.
    function test_InvalidateRoot_RevertsOnWrongPreviousOutpoint() public {
        _recordBobsMint();

        PuppetTypes.RootSpendAttestation memory spend =
            _spendAttestation(TXID_A, INDEX_A, outpointThree, HEIGHT_TWO, keccak256("FIXTURE-auth-wrong"));
        bytes[] memory sigs = _sigsFor(spend);

        vm.expectRevert(
            abi.encodeWithSelector(IRootOwnershipRegistry.OutpointMismatch.selector, outpointOne, outpointThree)
        );
        registry.invalidateRoot(spend, sigs, proofA);
        assertTrue(registry.isActive(rootKeyA), "still active");
    }

    /// @notice An inactive or never-activated Root cannot be invalidated.
    function test_InvalidateRoot_RevertsWhenNotActive() public {
        PuppetTypes.RootSpendAttestation memory spend =
            _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_TWO, keccak256("FIXTURE-auth-none"));
        bytes[] memory sigs = _sigsFor(spend);

        vm.expectRevert(abi.encodeWithSelector(IRootOwnershipRegistry.RootNotActive.selector, rootKeyA));
        registry.invalidateRoot(spend, sigs, proofA);
    }

    /// @notice Replaying an invalidation is refused twice over: by the local active check, and — if
    ///         the Root has since been rebound to a different outpoint — by the outpoint match.
    function test_InvalidateRoot_ReplayIsRefused() public {
        _recordBobsMint();

        PuppetTypes.RootSpendAttestation memory spend =
            _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_TWO, keccak256("FIXTURE-auth-replay-inv"));
        bytes[] memory sigs = _sigsFor(spend);
        vm.prank(watcher);
        registry.invalidateRoot(spend, sigs, proofA);

        // Immediate replay: the Root is no longer active.
        vm.expectRevert(abi.encodeWithSelector(IRootOwnershipRegistry.RootNotActive.selector, rootKeyA));
        registry.invalidateRoot(spend, sigs, proofA);

        // After Charlie rebinds to a new outpoint, the old attestation still cannot touch him.
        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointTwo, scriptCharlie, HEIGHT_THREE, keccak256("FIXTURE-auth-c2")
        );
        registry.bindRootOwner(a, _sigsFor(a), proofA);

        vm.expectRevert(
            abi.encodeWithSelector(IRootOwnershipRegistry.OutpointMismatch.selector, outpointTwo, outpointOne)
        );
        registry.invalidateRoot(spend, sigs, proofA);
        assertTrue(registry.isActive(rootKeyA), "Charlie's epoch survives the replay attempt");
    }

    /// @notice A spend observed BELOW the recorded height is refused.
    function test_InvalidateRoot_RevertsOnStaleSpendHeight() public {
        _recordBobsMint();

        PuppetTypes.RootSpendAttestation memory spend =
            _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_ONE - 10, keccak256("FIXTURE-auth-old-spend"));
        bytes[] memory sigs = _sigsFor(spend);

        vm.expectRevert(
            abi.encodeWithSelector(IRootOwnershipRegistry.StaleBitcoinHeight.selector, HEIGHT_ONE - 10, HEIGHT_ONE)
        );
        registry.invalidateRoot(spend, sigs, proofA);
    }

    function test_InvalidateRootRejectsConflictingBlockAtEqualBitcoinHeight() public {
        _recordBobsMint();

        PuppetTypes.RootSpendAttestation memory spend =
            _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_ONE, keccak256("FIXTURE-auth-same-height-fork"));
        bytes[] memory sigs = _sigsFor(spend);
        bytes32 recordedBlockHash = keccak256("FIXTURE-block-880000");

        vm.expectRevert(
            abi.encodeWithSelector(
                IRootOwnershipRegistry.ConflictingBitcoinBlockAtHeight.selector,
                HEIGHT_ONE,
                recordedBlockHash,
                spend.bitcoinBlockHash
            )
        );
        registry.invalidateRoot(spend, sigs, proofA);
        assertTrue(registry.isActive(rootKeyA), "conflicting fork cannot close the epoch");
    }

    /// @notice Structurally empty spend attestations are refused before the oracle is called.
    /// @dev Rebuilt per case for the same memory-aliasing reason as the bind equivalent.
    function test_InvalidateRoot_RejectsEmptyFields() public {
        _recordBobsMint();

        PuppetTypes.RootSpendAttestation memory a =
            _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_TWO, keccak256("FIXTURE-auth-s1"));
        a.rootTxid = bytes32(0);
        bytes[] memory sigs = _sigsFor(a);
        vm.expectRevert(RootOwnershipRegistry.ZeroRootTxid.selector);
        registry.invalidateRoot(a, sigs, proofA);

        a = _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_TWO, keccak256("FIXTURE-auth-s2"));
        a.previousOutpointHash = bytes32(0);
        sigs = _sigsFor(a);
        vm.expectRevert(RootOwnershipRegistry.ZeroOutpointHash.selector);
        registry.invalidateRoot(a, sigs, proofA);

        a = _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_TWO, keccak256("FIXTURE-auth-s3"));
        a.spendingTxid = bytes32(0);
        sigs = _sigsFor(a);
        vm.expectRevert(RootOwnershipRegistry.ZeroSpendingTxid.selector);
        registry.invalidateRoot(a, sigs, proofA);

        a = _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_TWO, keccak256("FIXTURE-auth-s4"));
        a.authorizationId = bytes32(0);
        sigs = _sigsFor(a);
        vm.expectRevert(RootOwnershipRegistry.ZeroAuthorizationId.selector);
        registry.invalidateRoot(a, sigs, proofA);

        assertTrue(registry.isActive(rootKeyA), "no malformed spend closed the epoch");
    }

    /// @notice A rootKey disagreement aborts the invalidation too.
    function test_InvalidateRoot_RevertsOnOracleRootKeyDisagreement() public {
        _recordBobsMint();
        PuppetTypes.RootSpendAttestation memory spend =
            _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_TWO, keccak256("FIXTURE-auth-div-spend"));
        bytes[] memory sigs = _sigsFor(spend);
        bytes32 wrongKey = keccak256("a-different-root");

        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(IBitcoinOwnershipOracle.consumeRootSpend.selector),
            abi.encode(keccak256("digest"), wrongKey)
        );

        vm.expectRevert(abi.encodeWithSelector(IRootOwnershipRegistry.RootMismatch.selector, rootKeyA, wrongKey));
        registry.invalidateRoot(spend, sigs, proofA);
        vm.clearMockedCalls();
    }

    /// @notice An invalidation never touches a balance already credited.
    function test_InvalidateRootPreservesCreditedBalance() public {
        _recordBobsMint();
        _creditBeneficiary(bob, 4 ether);

        _invalidateBobsEpoch();

        assertEq(vault.claimable(bob), 4 ether, "Bob keeps what he earned");

        vm.prank(bob);
        vault.withdrawAll();
        assertEq(bob.balance, 4 ether, "and can still take it out");
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSING
    //////////////////////////////////////////////////////////////*/

    /// @notice A pause stops the two permissionless attestation-consuming paths.
    function test_PauseBlocksBindAndInvalidate() public {
        _recordBobsMint();

        vm.prank(guardian);
        registry.pauseActivations();

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointTwo, scriptCharlie, HEIGHT_TWO, keccak256("FIXTURE-auth-pz")
        );
        bytes[] memory bindSigs = _sigsFor(a);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        registry.bindRootOwner(a, bindSigs, proofA);

        PuppetTypes.RootSpendAttestation memory spend =
            _spendAttestation(TXID_A, INDEX_A, outpointOne, HEIGHT_TWO, keccak256("FIXTURE-auth-pz2"));
        bytes[] memory spendSigs = _sigsFor(spend);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        registry.invalidateRoot(spend, spendSigs, proofA);
    }

    /// @notice A pause alters no recorded state and blocks no view.
    function test_PauseDoesNotAlterState() public {
        _recordBobsMint();
        PuppetTypes.RootState memory before = registry.currentState(rootKeyA);

        vm.prank(guardian);
        registry.pauseActivations();

        PuppetTypes.RootState memory afterPause = registry.currentState(rootKeyA);
        assertEq(keccak256(abi.encode(before)), keccak256(abi.encode(afterPause)), "state is untouched by a pause");
        assertTrue(registry.isActive(rootKeyA), "views keep answering");
        assertEq(registry.epochOf(rootKeyA), 1, "views keep answering");
    }

    /// @notice A registry pause can never block a vault withdrawal.
    function test_PauseNeverBlocksVaultWithdrawals() public {
        _recordBobsMint();
        _creditBeneficiary(bob, 2 ether);

        vm.prank(guardian);
        registry.pauseActivations();

        vm.prank(bob);
        vault.withdraw(2 ether);
        assertEq(bob.balance, 2 ether, "withdrawal unaffected by a registry pause");
    }

    /// @notice The guardian may pause but may not unpause.
    function test_PauseAuthorityIsAsymmetric() public {
        bytes32 pauser = pauserRole;
        bytes32 defaultAdmin = defaultAdminRole;

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, watcher, pauser)
        );
        vm.prank(watcher);
        registry.pauseActivations();

        vm.prank(guardian);
        registry.pauseActivations();
        assertTrue(registry.paused(), "paused");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, guardian, defaultAdmin)
        );
        vm.prank(guardian);
        registry.unpauseActivations();

        vm.prank(admin);
        registry.unpauseActivations();
        assertFalse(registry.paused(), "unpaused by the timelock only");
    }

    /*//////////////////////////////////////////////////////////////
                         NO ADMIN OWNERSHIP PATH
    //////////////////////////////////////////////////////////////*/

    /// @notice No role, including `DEFAULT_ADMIN_ROLE`, can assign or clear a beneficiary.
    /// @dev Scans the deployed runtime bytecode for selectors that would constitute such a path.
    ///      A call-based version of this test would be close to vacuous — a call with malformed
    ///      arguments reverts whether or not the function exists — so this looks for the dispatcher
    ///      entry itself, with a positive control so it cannot pass by finding nothing at all.
    function test_NoAdminPathAssignsOwnership() public view {
        bytes memory runtime = address(registry).code;

        string[8] memory forbidden = [
            "setBeneficiary(bytes32,address)",
            "setRootOwner(bytes32,address)",
            "forceActivate(bytes32,address)",
            "clearRoot(bytes32)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "upgradeToAndCall(address,bytes)",
            "initialize(address)"
        ];
        for (uint256 i = 0; i < forbidden.length; i++) {
            assertFalse(_containsSelector(runtime, bytes4(keccak256(bytes(forbidden[i])))), forbidden[i]);
        }

        // Positive control: the scan does find a selector that genuinely exists.
        assertTrue(_containsSelector(runtime, IRootOwnershipRegistry.currentState.selector), "scanner works");
    }

    /// @notice The admin holds no path to record, rebind, or release on its own authority.
    function test_AdminCannotMoveOwnership() public {
        _recordBobsMint();
        bytes32 role = mintRecorderRole;

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, role));
        vm.prank(admin);
        registry.recordMintOwnership(
            rootKeyA,
            charlie,
            outpointTwo,
            scriptCharlie,
            keccak256("FIXTURE-d"),
            keccak256("FIXTURE-p"),
            keccak256("FIXTURE-b"),
            HEIGHT_TWO
        );

        assertEq(_beneficiaryOf(rootKeyA), bob, "beneficiary unmoved");
    }

    /// @notice Even the mint recorder cannot rebind a live Root; its power is first-epoch only.
    function testFuzz_MintRecorderCannotRebind(address attacker) public {
        vm.assume(attacker != address(0));
        _recordBobsMint();

        vm.expectRevert(abi.encodeWithSelector(IRootOwnershipRegistry.RootAlreadyActive.selector, rootKeyA, uint64(1)));
        vm.prank(escrow);
        registry.recordMintOwnership(
            rootKeyA,
            attacker,
            outpointTwo,
            scriptCharlie,
            keccak256("FIXTURE-d"),
            keccak256("FIXTURE-p"),
            keccak256("FIXTURE-b"),
            HEIGHT_TWO
        );
        assertEq(_beneficiaryOf(rootKeyA), bob, "beneficiary unmoved");
    }

    /*//////////////////////////////////////////////////////////////
                        THE BOB TO CHARLIE STORY
    //////////////////////////////////////////////////////////////*/

    /// @notice The complete narrative this contract exists for, as one transaction sequence.
    /// @dev Bob mints, Bob accrues recurring value, Bob sells the Puppet on Bitcoin, recurring
    ///      value keeps reaching Bob during the stale-watcher window, a watcher closes the epoch,
    ///      further value goes to the Root's pending bucket, Charlie proves control, the pending
    ///      bucket releases to Charlie, and every wei Bob earned before the close is still Bob's.
    function test_EndToEnd_BobSellsToCharlie() public {
        // 1. Bob mints. Epoch 1 opens.
        assertEq(_recordBobsMint(), 1, "epoch 1");
        assertEq(_beneficiaryOf(rootKeyA), bob, "Bob is the beneficiary");

        // 2. Recurring Root value accrues to Bob while he verifiably controls the inscription.
        _creditBeneficiary(bob, 3 ether);
        assertEq(vault.claimable(bob), 3 ether, "Bob accrues");

        // 3. Bob sells on Bitcoin. NOTHING on chain knows yet. This is the stale-watcher window,
        //    and value routed during it still reaches Bob. That is the documented, unavoidable cost
        //    of an attested design.
        _creditBeneficiary(bob, 1 ether);
        assertTrue(registry.isActive(rootKeyA), "registry still names Bob");
        assertEq(vault.claimable(bob), 4 ether, "window value reached Bob");

        // 4. A permissionless watcher submits the spend attestation. The window closes.
        _invalidateBobsEpoch();
        assertFalse(registry.isActive(rootKeyA), "epoch closed");
        assertEq(registry.epochOf(rootKeyA), 1, "still epoch 1, now inactive");

        // 5. FeeRouter now sees an inactive Root and parks value in the pending bucket instead.
        _creditRoot(rootKeyA, 6 ether);
        assertEq(vault.pendingByRoot(rootKeyA), 6 ether, "parked, not paid");
        assertEq(vault.claimable(bob), 4 ether, "Bob receives nothing further");

        // 6. Charlie proves control and opens epoch 2. The pending bucket follows him.
        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointTwo, scriptCharlie, HEIGHT_THREE, keccak256("FIXTURE-auth-charlie")
        );
        bytes[] memory sigs = _sigsFor(a);
        vm.prank(charlie);
        (uint64 epoch, uint256 released) = registry.bindRootOwner(a, sigs, proofA);

        assertEq(epoch, 2, "epoch 2");
        assertEq(released, 6 ether, "the whole pending bucket");
        assertEq(vault.claimable(charlie), 6 ether, "Charlie is paid");
        assertEq(vault.pendingByRoot(rootKeyA), 0, "bucket empty");

        // 7. Bob's earlier earnings were never touched, and he can still withdraw them.
        assertEq(vault.claimable(bob), 4 ether, "Bob keeps every wei he earned");
        vm.prank(bob);
        vault.withdrawAll();
        assertEq(bob.balance, 4 ether, "Bob withdraws");

        // 8. Ongoing value now reaches Charlie.
        _creditBeneficiary(charlie, 2 ether);
        assertEq(vault.claimable(charlie), 8 ether, "Charlie accrues");

        // 9. History is complete and epoch 1 was never rewritten.
        PuppetTypes.RootEpochInfo memory first = registry.epochInfo(rootKeyA, 1);
        assertEq(first.beneficiary, bob, "epoch 1 beneficiary");
        assertEq(first.activatedAtBitcoinHeight, HEIGHT_ONE, "epoch 1 opened");
        assertEq(first.deactivatedAtBitcoinHeight, HEIGHT_TWO, "epoch 1 closed");

        PuppetTypes.RootEpochInfo memory second = registry.epochInfo(rootKeyA, 2);
        assertEq(second.beneficiary, charlie, "epoch 2 beneficiary");
        assertEq(second.activatedAtBitcoinHeight, HEIGHT_THREE, "epoch 2 opened");
        assertEq(second.deactivatedAtBitcoinHeight, 0, "epoch 2 still open");
    }

    /// @notice Historical epoch records are never rewritten by later activity.
    function test_EpochHistoryIsNeverRewritten() public {
        _recordBobsMint();
        PuppetTypes.RootEpochInfo memory firstAfterOpen = registry.epochInfo(rootKeyA, 1);

        _invalidateBobsEpoch();
        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointTwo, scriptCharlie, HEIGHT_THREE, keccak256("FIXTURE-auth-h")
        );
        registry.bindRootOwner(a, _sigsFor(a), proofA);

        PuppetTypes.RootEpochInfo memory firstNow = registry.epochInfo(rootKeyA, 1);
        assertEq(firstNow.beneficiary, firstAfterOpen.beneficiary, "beneficiary");
        assertEq(firstNow.outpointHash, firstAfterOpen.outpointHash, "outpoint");
        assertEq(firstNow.ownerScriptHash, firstAfterOpen.ownerScriptHash, "script");
        assertEq(firstNow.ownershipDigest, firstAfterOpen.ownershipDigest, "digest");
        assertEq(firstNow.activatedAtBitcoinHeight, firstAfterOpen.activatedAtBitcoinHeight, "activation height");
        assertEq(firstNow.activatedAtBlockTimestamp, firstAfterOpen.activatedAtBlockTimestamp, "activation time");
    }

    /// @notice Roots are independent: activity on one never touches another.
    function test_RootsAreIndependent() public {
        _recordBobsMint();

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_B, INDEX_B, charlie, outpointTwo, scriptCharlie, HEIGHT_ONE, keccak256("FIXTURE-auth-b")
        );
        registry.bindRootOwner(a, _sigsFor(a), proofA);

        assertEq(_beneficiaryOf(rootKeyA), bob, "root A untouched");
        assertEq(_beneficiaryOf(rootKeyB), charlie, "root B independent");
        assertEq(registry.epochOf(rootKeyA), 1, "root A epoch");
        assertEq(registry.epochOf(rootKeyB), 1, "root B epoch");
    }

    /*//////////////////////////////////////////////////////////////
                                 FUZZ
    //////////////////////////////////////////////////////////////*/

    /// @notice Epoch transitions over fuzzed Bitcoin heights: the epoch only ever grows, the
    ///         recorded height never decreases, and an inactive Root is never payable.
    function testFuzz_EpochTransitions(uint64 h1, uint64 h2, uint64 h3, bool invalidateFirst) public {
        h1 = uint64(bound(h1, 1, type(uint64).max / 4));
        h2 = uint64(bound(h2, h1, type(uint64).max / 2));
        h3 = uint64(bound(h3, h2, type(uint64).max - 1));

        vm.prank(escrow);
        registry.recordMintOwnership(
            rootKeyA,
            bob,
            outpointOne,
            scriptBob,
            keccak256("FIXTURE-d"),
            keccak256("FIXTURE-p"),
            keccak256("FIXTURE-b"),
            h1
        );
        assertEq(registry.epochOf(rootKeyA), 1, "epoch 1");
        assertEq(registry.currentState(rootKeyA).verifiedBitcoinHeight, h1, "height 1");

        if (invalidateFirst) {
            PuppetTypes.RootSpendAttestation memory spend =
                _spendAttestation(TXID_A, INDEX_A, outpointOne, h2, keccak256("FIXTURE-auth-fz-spend"));
            PuppetTypes.RootState memory beforeSpend = registry.currentState(rootKeyA);
            if (h2 == beforeSpend.verifiedBitcoinHeight) {
                spend.bitcoinBlockHash = beforeSpend.lastBitcoinBlockHash;
            }
            registry.invalidateRoot(spend, _sigsFor(spend), proofA);

            assertFalse(registry.isActive(rootKeyA), "inactive after spend");
            assertEq(registry.epochOf(rootKeyA), 1, "invalidation never bumps the epoch");
            assertEq(registry.currentState(rootKeyA).verifiedBitcoinHeight, h2, "height advanced");
        }

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointTwo, scriptCharlie, h3, keccak256("FIXTURE-auth-fz-bind")
        );
        PuppetTypes.RootState memory beforeBind = registry.currentState(rootKeyA);
        if (h3 == beforeBind.verifiedBitcoinHeight) {
            a.bitcoinBlockHash = beforeBind.lastBitcoinBlockHash;
        }
        registry.bindRootOwner(a, _sigsFor(a), proofA);

        PuppetTypes.RootState memory s = registry.currentState(rootKeyA);
        assertEq(s.epoch, 2, "epoch 2");
        assertTrue(s.active, "active again");
        assertEq(s.beneficiary, charlie, "new beneficiary");
        assertEq(s.verifiedBitcoinHeight, h3, "height monotonic");
        assertTrue(s.verifiedBitcoinHeight >= h1, "height never decreased");
    }

    /// @notice Any Bitcoin height strictly below the recorded one is always refused on a bind.
    function testFuzz_StaleHeightAlwaysRejected(uint64 staleHeight) public {
        _recordBobsMint();
        staleHeight = uint64(bound(staleHeight, 0, HEIGHT_ONE - 1));

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, charlie, outpointTwo, scriptCharlie, staleHeight, keccak256("FIXTURE-auth-fz-s")
        );
        bytes[] memory sigs = _sigsFor(a);

        vm.expectRevert(
            abi.encodeWithSelector(IRootOwnershipRegistry.StaleBitcoinHeight.selector, staleHeight, HEIGHT_ONE)
        );
        registry.bindRootOwner(a, sigs, proofA);
        assertEq(_beneficiaryOf(rootKeyA), bob, "beneficiary unmoved");
    }

    /// @notice No unauthorized address can ever record a mint ownership epoch.
    function testFuzz_UnauthorizedRecorderAlwaysRejected(address caller) public {
        vm.assume(caller != escrow);
        bytes32 role = mintRecorderRole;

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, role));
        vm.prank(caller);
        registry.recordMintOwnership(
            rootKeyA,
            caller,
            outpointOne,
            scriptBob,
            keccak256("FIXTURE-d"),
            keccak256("FIXTURE-p"),
            keccak256("FIXTURE-b"),
            HEIGHT_ONE
        );
        assertEq(registry.epochOf(rootKeyA), 0, "no epoch created");
    }

    /// @notice Whatever the fuzzer picks for the beneficiary, the recorded beneficiary is exactly
    ///         the address inside the attestation and never anything derived from the caller.
    function testFuzz_BeneficiaryComesFromTheAttestation(address beneficiary, address caller) public {
        vm.assume(beneficiary != address(0));
        vm.assume(caller != address(0) && caller.code.length == 0);

        PuppetTypes.OwnershipAttestation memory a = _bindAttestation(
            TXID_A, INDEX_A, beneficiary, outpointOne, scriptBob, HEIGHT_ONE, keccak256("FIXTURE-auth-fz-b")
        );
        bytes[] memory sigs = _sigsFor(a);

        vm.prank(caller);
        registry.bindRootOwner(a, sigs, proofA);

        assertEq(_beneficiaryOf(rootKeyA), beneficiary, "attested beneficiary wins");
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev The beneficiary alone, for assertions that do not care about the flag or the epoch.
    function _beneficiaryOf(bytes32 rootKey) private view returns (address beneficiary) {
        (beneficiary,,) = registry.currentBeneficiary(rootKey);
    }

    /// @dev Naive 4-byte scan over runtime bytecode. Good enough for a dispatcher-entry probe: it
    ///      can produce a false FAILURE from a coincidental byte sequence, never a false pass.
    function _containsSelector(bytes memory runtime, bytes4 selector) private pure returns (bool) {
        if (runtime.length < 4) return false;
        for (uint256 i = 0; i + 4 <= runtime.length; i++) {
            if (
                runtime[i] == selector[0] && runtime[i + 1] == selector[1] && runtime[i + 2] == selector[2]
                    && runtime[i + 3] == selector[3]
            ) {
                return true;
            }
        }
        return false;
    }
}
