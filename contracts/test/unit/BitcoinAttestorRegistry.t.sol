// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {BitcoinAttestorRegistry} from "../../src/BitcoinAttestorRegistry.sol";
import {IBitcoinAttestorRegistry} from "../../src/interfaces/IBitcoinAttestorRegistry.sol";
import {AttestorSet} from "../helpers/AttestorSet.sol";

/// @title EpochBoundConsumer
/// @notice Minimal stand-in for the guard `BitcoinOwnershipOracle` runs before it counts
///         signatures, used here to demonstrate stale-epoch behaviour against the REAL registry.
/// @dev WHY THIS EXISTS RATHER THAN `test/mocks/MockOwnershipOracle.sol`: that mock's own honesty
///      note states it performs NO epoch, policy, quorum or membership checks — it exists to let
///      escrow suites drive attestations without signing. It therefore cannot demonstrate that a
///      mutation invalidates in-flight attestations. This harness reproduces exactly the three
///      lines of the oracle's guard (epoch equality, policy equality, signature count vs
///      threshold) and reads them from the production registry, which is the property under test.
///
///      HONESTY NOTE: `signatureCount` here is a plain number. Nothing is verified
///      cryptographically. A green test in this file proves the registry invalidates context, not
///      that any signature scheme is sound.
contract EpochBoundConsumer {
    /// @notice Thrown when an attestation was signed under a superseded attestor epoch.
    error StaleAttestorEpoch(uint64 signedEpoch, uint64 currentEpoch);
    /// @notice Thrown when an attestation was signed under a superseded verification policy.
    error StalePolicyVersion(uint32 signedVersion, uint32 currentVersion);
    /// @notice Thrown when fewer signatures were gathered than the standing threshold requires.
    error QuorumNotMet(uint256 provided, uint8 required);

    IBitcoinAttestorRegistry public immutable REGISTRY;

    /// @param registry The attestor registry to bind quorum context against.
    constructor(IBitcoinAttestorRegistry registry) {
        REGISTRY = registry;
    }

    /// @notice Revert unless an attestation's bound context still matches the live registry.
    /// @param signedEpoch The `attestorEpoch` folded into the signed digest.
    /// @param signedPolicy The `policyVersion` folded into the signed digest.
    /// @param signatureCount How many distinct attestor signatures were gathered.
    function acceptAttestation(uint64 signedEpoch, uint32 signedPolicy, uint256 signatureCount) external view {
        (uint8 currentThreshold, uint64 epoch, uint32 policy) = REGISTRY.quorumContext();
        if (signedEpoch != epoch) revert StaleAttestorEpoch(signedEpoch, epoch);
        if (signedPolicy != policy) revert StalePolicyVersion(signedPolicy, policy);
        if (signatureCount < currentThreshold) revert QuorumNotMet(signatureCount, currentThreshold);
    }
}

/// @title BitcoinAttestorRegistryTest
/// @notice Unit suite for the production verifier membership registry.
/// @dev The genesis set is built from the shared `AttestorSet` helper so the addresses here are
///      the same deterministic keypairs every other suite signs with; boundary and fuzz cases that
///      need more than five members use synthetic addresses, since no signing happens in this file.
contract BitcoinAttestorRegistryTest is Test {
    /*//////////////////////////////////////////////////////////////
                                FIXTURES
    //////////////////////////////////////////////////////////////*/

    BitcoinAttestorRegistry internal registry;
    AttestorSet internal attestorSet;

    /// @dev Stands in for the deployer EOA that must end up with zero authority.
    address internal deployer = address(this);
    /// @dev Stands in for the `TimelockController` production governance address.
    address internal timelock = makeAddr("timelock");
    address internal stranger = makeAddr("stranger");

    uint64 internal constant GENESIS_EPOCH = 1;
    uint8 internal constant GENESIS_THRESHOLD = 3;
    uint32 internal constant GENESIS_POLICY = 1;

    bytes32 internal constant SEED = keccak256("HOODPUPS_ATTESTOR_REGISTRY_SUITE");

    /// @dev Genesis members and role ids are cached as plain storage rather than re-read from
    ///      `attestorSet` / `registry` inside each test. This is not a style preference: forge's
    ///      `vm.expectRevert` and `vm.prank` both apply to the very NEXT external call, so an
    ///      innocuous `attestorSet.addressAt(0)` written inline as a call argument silently
    ///      consumes the cheat code and makes the assertion vacuous or the caller wrong. Caching
    ///      removes the whole class of mistake. (Observed: four tests failed exactly this way
    ///      before the fix.)
    address[] internal genesisAttestors;
    address internal outsider;
    bytes32 internal adminRole;
    bytes32 internal mutatorRole;

    function setUp() public {
        attestorSet = new AttestorSet(5, SEED);
        genesisAttestors = attestorSet.addresses();
        outsider = attestorSet.outsider();
        registry = new BitcoinAttestorRegistry(deployer, genesisAttestors, GENESIS_THRESHOLD, GENESIS_POLICY);
        adminRole = registry.DEFAULT_ADMIN_ROLE();
        mutatorRole = registry.ATTESTOR_ADMIN_ROLE();
    }

    /*//////////////////////////////////////////////////////////////
                               HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Deterministic, collision-free synthetic attestor addresses for size-boundary work.
    ///      Every caller passes an index below 256, so the sum is nowhere near 2^160.
    function _synthetic(uint256 index) internal pure returns (address) {
        // casting to 'uint160' is safe because the base is a small literal and every call site
        // bounds `index` far below 2^160.
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(0xA11CE0000 + index));
    }

    function _syntheticSet(uint256 size) internal pure returns (address[] memory out) {
        out = new address[](size);
        for (uint256 i = 0; i < size; i++) {
            out[i] = _synthetic(i);
        }
    }

    /// @dev Deploy a registry of arbitrary legal size with this test contract as admin.
    function _deploy(uint256 size, uint8 thresholdValue) internal returns (BitcoinAttestorRegistry) {
        return new BitcoinAttestorRegistry(deployer, _syntheticSet(size), thresholdValue, GENESIS_POLICY);
    }

    function _expectUnauthorized(address caller) internal {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, mutatorRole)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR: HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    function test_ConstructorSetsGenesisState() public view {
        assertEq(registry.attestorCount(), 5, "count");
        assertEq(registry.threshold(), GENESIS_THRESHOLD, "threshold");
        assertEq(registry.attestorEpoch(), GENESIS_EPOCH, "epoch starts at 1");
        assertEq(registry.policyVersion(), GENESIS_POLICY, "policy version");

        address[] memory expected = attestorSet.addresses();
        address[] memory snapshot = registry.attestors();
        assertEq(snapshot.length, expected.length, "snapshot length");
        for (uint256 i = 0; i < expected.length; i++) {
            assertTrue(registry.isAttestor(expected[i]), "member missing");
            assertEq(registry.attestorAt(i), expected[i], "insertion order preserved");
        }
        assertFalse(registry.isAttestor(outsider), "outsider must not be a member");
    }

    function test_ConstructorGrantsBothRolesToAdmin() public view {
        assertTrue(registry.hasRole(adminRole, deployer), "default admin");
        assertTrue(registry.hasRole(mutatorRole, deployer), "attestor admin");
        assertFalse(registry.hasRole(adminRole, stranger), "stranger must hold nothing");
    }

    function test_ConstructorEmitsPerMemberAndSummaryEvents() public {
        address[] memory members = _syntheticSet(5);

        for (uint256 i = 0; i < members.length; i++) {
            vm.expectEmit(true, false, false, true);
            emit IBitcoinAttestorRegistry.AttestorAdded(members[i], 0, 1);
        }
        vm.expectEmit(true, false, false, true);
        emit BitcoinAttestorRegistry.RegistryInitialized(deployer, 5, GENESIS_THRESHOLD, 1, GENESIS_POLICY);

        new BitcoinAttestorRegistry(deployer, members, GENESIS_THRESHOLD, GENESIS_POLICY);
    }

    function test_ConstructorAcceptsMaxAttestors() public {
        BitcoinAttestorRegistry exact = _deploy(5, 5);
        assertEq(exact.attestorCount(), registry.MAX_ATTESTORS(), "five members accepted");
        assertEq(exact.threshold(), 5, "threshold may equal count");
    }

    function test_ProductionConstantsAreTheSpecifiedOnes() public view {
        assertEq(registry.MIN_ATTESTORS(), 5, "MIN_ATTESTORS");
        assertEq(registry.MAX_ATTESTORS(), 5, "MAX_ATTESTORS");
        assertEq(registry.MIN_THRESHOLD(), 3, "MIN_THRESHOLD");
    }

    /*//////////////////////////////////////////////////////////////
                       CONSTRUCTOR: EVERY FAILURE MODE
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_ConstructorAdminIsZero() public {
        vm.expectRevert(IBitcoinAttestorRegistry.ZeroAddress.selector);
        new BitcoinAttestorRegistry(address(0), _syntheticSet(5), GENESIS_THRESHOLD, GENESIS_POLICY);
    }

    function test_RevertWhen_ConstructorPolicyVersionIsZero() public {
        vm.expectRevert(IBitcoinAttestorRegistry.ZeroPolicyVersion.selector);
        new BitcoinAttestorRegistry(deployer, _syntheticSet(5), GENESIS_THRESHOLD, 0);
    }

    function test_RevertWhen_ConstructorCountBelowMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.AttestorCountOutOfRange.selector, uint256(4)));
        new BitcoinAttestorRegistry(deployer, _syntheticSet(4), GENESIS_THRESHOLD, GENESIS_POLICY);
    }

    function test_RevertWhen_ConstructorCountAboveMaximum() public {
        vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.AttestorCountOutOfRange.selector, uint256(6)));
        new BitcoinAttestorRegistry(deployer, _syntheticSet(6), GENESIS_THRESHOLD, GENESIS_POLICY);
    }

    function test_RevertWhen_ConstructorHasZeroAttestor() public {
        address[] memory members = _syntheticSet(5);
        members[3] = address(0);
        vm.expectRevert(IBitcoinAttestorRegistry.ZeroAddress.selector);
        new BitcoinAttestorRegistry(deployer, members, GENESIS_THRESHOLD, GENESIS_POLICY);
    }

    function test_RevertWhen_ConstructorHasDuplicateAttestor() public {
        address[] memory members = _syntheticSet(5);
        members[4] = members[1];
        vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.DuplicateAttestor.selector, members[1]));
        new BitcoinAttestorRegistry(deployer, members, GENESIS_THRESHOLD, GENESIS_POLICY);
    }

    function test_RevertWhen_ConstructorThresholdBelowMinimum() public {
        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinAttestorRegistry.ThresholdOutOfRange.selector, uint8(2), uint256(5))
        );
        new BitcoinAttestorRegistry(deployer, _syntheticSet(5), 2, GENESIS_POLICY);
    }

    function test_RevertWhen_ConstructorThresholdExceedsCount() public {
        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinAttestorRegistry.ThresholdOutOfRange.selector, uint8(6), uint256(5))
        );
        new BitcoinAttestorRegistry(deployer, _syntheticSet(5), 6, GENESIS_POLICY);
    }

    /*//////////////////////////////////////////////////////////////
                              ADD ATTESTOR
    //////////////////////////////////////////////////////////////*/

    function test_AddAttestorCannotDiluteTheFixedFiveMemberSet() public {
        address newcomer = outsider;
        uint64 before = registry.attestorEpoch();

        vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.AttestorCountOutOfRange.selector, uint256(6)));
        registry.addAttestor(newcomer);

        assertFalse(registry.isAttestor(newcomer), "not added");
        assertEq(registry.attestorCount(), 5, "count fixed at five");
        assertEq(registry.attestorEpoch(), before, "rejected growth does not bump epoch");
    }

    function test_RevertWhen_AddingDuplicate() public {
        address existing = genesisAttestors[2];
        vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.DuplicateAttestor.selector, existing));
        registry.addAttestor(existing);
    }

    function test_RevertWhen_AddingZeroAddress() public {
        vm.expectRevert(IBitcoinAttestorRegistry.ZeroAddress.selector);
        registry.addAttestor(address(0));
    }

    function test_RevertWhen_AddingBeyondMaxAttestors() public {
        vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.AttestorCountOutOfRange.selector, uint256(6)));
        registry.addAttestor(_synthetic(32));
        assertEq(registry.attestorCount(), 5, "count untouched by the rejected add");
        assertEq(registry.attestorEpoch(), GENESIS_EPOCH, "rejected mutation must not bump the epoch");
    }

    /*//////////////////////////////////////////////////////////////
                             REMOVE ATTESTOR
    //////////////////////////////////////////////////////////////*/

    function test_RemoveAttestorCannotShrinkTheFixedFiveMemberSet() public {
        address leaving = genesisAttestors[1];
        vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.AttestorCountOutOfRange.selector, uint256(4)));
        registry.removeAttestor(leaving);

        assertTrue(registry.isAttestor(leaving), "member preserved by revert");
        assertEq(registry.attestorCount(), 5, "count fixed at five");
        assertEq(registry.attestorEpoch(), GENESIS_EPOCH, "rejected shrink does not bump epoch");
    }

    function test_RevertWhen_RemovingUnknownAttestor() public {
        address ghost = outsider;
        vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.UnknownAttestor.selector, ghost));
        registry.removeAttestor(ghost);
    }

    /// @dev The floor is checked on the POST-removal count, so a 5-member set is frozen at 5.
    function test_RevertWhen_RemovingWouldDropBelowMinAttestors() public {
        address member = genesisAttestors[0];
        vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.AttestorCountOutOfRange.selector, uint256(4)));
        registry.removeAttestor(member);

        assertEq(registry.attestorCount(), 5, "membership unchanged");
        assertTrue(registry.isAttestor(member), "member restored by the revert");
        assertEq(registry.attestorEpoch(), GENESIS_EPOCH, "rejected mutation must not bump the epoch");
    }

    /*//////////////////////////////////////////////////////////////
                            REPLACE ATTESTOR
    //////////////////////////////////////////////////////////////*/

    /// @dev The atomicity claim in one test: at exactly `MIN_ATTESTORS`, remove-then-add is
    ///      impossible (the intermediate state is 4 members) but `replaceAttestor` succeeds,
    ///      because the count never leaves 5.
    function test_ReplaceAttestorIsAtomicAtMinimumSetSize() public {
        address outgoing = genesisAttestors[3];
        address incoming = outsider;
        uint64 before = registry.attestorEpoch();

        vm.expectEmit(true, true, false, true);
        emit IBitcoinAttestorRegistry.AttestorReplaced(outgoing, incoming, before, before + 1);
        registry.replaceAttestor(outgoing, incoming);

        assertFalse(registry.isAttestor(outgoing), "outgoing gone");
        assertTrue(registry.isAttestor(incoming), "incoming present");
        assertEq(registry.attestorCount(), 5, "count never moved");
        assertEq(registry.attestorEpoch() - before, 1, "one epoch bump, not two");
    }

    function test_RevertWhen_ReplacingUnknownAttestor() public {
        address ghost = outsider;
        vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.UnknownAttestor.selector, ghost));
        registry.replaceAttestor(ghost, _synthetic(99));
    }

    function test_RevertWhen_ReplacementIsZeroAddress() public {
        address member = genesisAttestors[0];
        vm.expectRevert(IBitcoinAttestorRegistry.ZeroAddress.selector);
        registry.replaceAttestor(member, address(0));
    }

    function test_RevertWhen_ReplacementIsAlreadyAMember() public {
        address a = genesisAttestors[0];
        address b = genesisAttestors[1];
        vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.DuplicateAttestor.selector, b));
        registry.replaceAttestor(a, b);
        assertEq(registry.attestorCount(), 5, "set untouched");
    }

    /// @dev Self-replacement would be a pure epoch bump with no membership change, so it is
    ///      rejected by the same duplicate check.
    function test_RevertWhen_ReplacingAnAttestorWithItself() public {
        address a = genesisAttestors[0];
        vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.DuplicateAttestor.selector, a));
        registry.replaceAttestor(a, a);
    }

    /*//////////////////////////////////////////////////////////////
                               THRESHOLD
    //////////////////////////////////////////////////////////////*/

    function test_SetThreshold() public {
        uint64 before = registry.attestorEpoch();

        vm.expectEmit(false, false, false, true);
        emit IBitcoinAttestorRegistry.ThresholdUpdated(GENESIS_THRESHOLD, 4, before, before + 1);
        registry.setThreshold(4);

        assertEq(registry.threshold(), 4, "threshold updated");
        assertEq(registry.attestorEpoch() - before, 1, "epoch bumped exactly once");
    }

    function test_RevertWhen_ThresholdBelowMinimum() public {
        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinAttestorRegistry.ThresholdOutOfRange.selector, uint8(2), uint256(5))
        );
        registry.setThreshold(2);
        assertEq(registry.threshold(), GENESIS_THRESHOLD, "threshold unchanged");
    }

    function test_RevertWhen_ThresholdAboveCount() public {
        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinAttestorRegistry.ThresholdOutOfRange.selector, uint8(6), uint256(5))
        );
        registry.setThreshold(6);
    }

    function test_RevertWhen_ThresholdUnchanged() public {
        vm.expectRevert(abi.encodeWithSelector(BitcoinAttestorRegistry.ThresholdUnchanged.selector, GENESIS_THRESHOLD));
        registry.setThreshold(GENESIS_THRESHOLD);
        assertEq(registry.attestorEpoch(), GENESIS_EPOCH, "no silent epoch bump on a no-op");
    }

    /*//////////////////////////////////////////////////////////////
                             POLICY VERSION
    //////////////////////////////////////////////////////////////*/

    /// @dev Pins the documented model: a policy-only change DOES bump the epoch.
    function test_SetPolicyVersionBumpsEpoch() public {
        uint64 before = registry.attestorEpoch();

        vm.expectEmit(false, false, false, true);
        emit IBitcoinAttestorRegistry.PolicyVersionUpdated(GENESIS_POLICY, 7, before, before + 1);
        registry.setPolicyVersion(7);

        assertEq(registry.policyVersion(), 7, "policy updated");
        assertEq(registry.attestorEpoch() - before, 1, "policy change bumps the epoch exactly once");
    }

    /// @dev Rolling a bad policy back must remain possible; the epoch bump is what keeps it
    ///      replay-safe.
    function test_PolicyVersionMayDecrease() public {
        registry.setPolicyVersion(9);
        registry.setPolicyVersion(2);
        assertEq(registry.policyVersion(), 2, "rollback allowed");
        assertEq(registry.attestorEpoch(), GENESIS_EPOCH + 2, "each change bumped once");
    }

    function test_RevertWhen_PolicyVersionIsZero() public {
        vm.expectRevert(IBitcoinAttestorRegistry.ZeroPolicyVersion.selector);
        registry.setPolicyVersion(0);
    }

    function test_RevertWhen_PolicyVersionUnchanged() public {
        vm.expectRevert(abi.encodeWithSelector(BitcoinAttestorRegistry.PolicyVersionUnchanged.selector, GENESIS_POLICY));
        registry.setPolicyVersion(GENESIS_POLICY);
    }

    /*//////////////////////////////////////////////////////////////
                            EPOCH ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Every permitted mutation kind, once each, moves the epoch exactly once.
    function test_EveryMutationBumpsEpochExactlyOnce() public {
        uint64 epoch = registry.attestorEpoch();

        registry.replaceAttestor(genesisAttestors[0], _synthetic(101));
        assertEq(registry.attestorEpoch() - epoch, 1, "replace");
        epoch = registry.attestorEpoch();

        registry.setThreshold(4);
        assertEq(registry.attestorEpoch() - epoch, 1, "threshold");
        epoch = registry.attestorEpoch();

        registry.setPolicyVersion(2);
        assertEq(registry.attestorEpoch() - epoch, 1, "policy");

        assertEq(registry.attestorEpoch(), GENESIS_EPOCH + 3, "three mutations, three bumps, no more");
    }

    /*//////////////////////////////////////////////////////////////
                    STALE EPOCH / POLICY INTEGRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice An attestation bound to the pre-mutation context must fail after ANY mutation.
    /// @dev This is the property the epoch counter exists for: no window in which a just-removed
    ///      operator's signature still counts.
    function test_AnyMutationInvalidatesInFlightAttestations() public {
        EpochBoundConsumer consumer = new EpochBoundConsumer(registry);

        (uint8 t, uint64 signedEpoch, uint32 signedPolicy) = registry.quorumContext();
        consumer.acceptAttestation(signedEpoch, signedPolicy, t);

        registry.replaceAttestor(genesisAttestors[0], outsider);
        vm.expectRevert(
            abi.encodeWithSelector(
                EpochBoundConsumer.StaleAttestorEpoch.selector, signedEpoch, registry.attestorEpoch()
            )
        );
        consumer.acceptAttestation(signedEpoch, signedPolicy, t);

        // Re-gathering under the new context works again.
        (uint8 t2, uint64 e2, uint32 p2) = registry.quorumContext();
        consumer.acceptAttestation(e2, p2, t2);
    }

    /// @dev Demonstrates the consequence of the chosen policy-version model: a policy-only change
    ///      also kills in-flight signatures, because the epoch moves with it.
    function test_PolicyChangeAloneInvalidatesInFlightAttestations() public {
        EpochBoundConsumer consumer = new EpochBoundConsumer(registry);
        (uint8 t, uint64 signedEpoch, uint32 signedPolicy) = registry.quorumContext();

        registry.setPolicyVersion(GENESIS_POLICY + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                EpochBoundConsumer.StaleAttestorEpoch.selector, signedEpoch, registry.attestorEpoch()
            )
        );
        consumer.acceptAttestation(signedEpoch, signedPolicy, t);
    }

    /// @dev A quorum gathered under the old, lower threshold cannot satisfy the raised one.
    function test_RaisedThresholdRejectsAnUndersizedQuorum() public {
        EpochBoundConsumer consumer = new EpochBoundConsumer(registry);
        registry.setThreshold(5);
        (, uint64 epoch, uint32 policy) = registry.quorumContext();

        vm.expectRevert(abi.encodeWithSelector(EpochBoundConsumer.QuorumNotMet.selector, uint256(3), uint8(5)));
        consumer.acceptAttestation(epoch, policy, 3);

        consumer.acceptAttestation(epoch, policy, 5);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function test_QuorumContextMatchesIndividualGetters() public {
        registry.setThreshold(4);
        registry.setPolicyVersion(11);

        (uint8 t, uint64 e, uint32 p) = registry.quorumContext();
        assertEq(t, registry.threshold(), "threshold");
        assertEq(e, registry.attestorEpoch(), "epoch");
        assertEq(p, registry.policyVersion(), "policy");
    }

    function test_RevertWhen_AttestorAtIndexOutOfRange() public {
        vm.expectRevert(
            abi.encodeWithSelector(BitcoinAttestorRegistry.AttestorIndexOutOfRange.selector, uint256(5), uint256(5))
        );
        registry.attestorAt(5);
    }

    function test_SupportsInterface() public view {
        assertTrue(registry.supportsInterface(type(IBitcoinAttestorRegistry).interfaceId), "registry interface");
        assertTrue(registry.supportsInterface(type(IAccessControl).interfaceId), "access control interface");
        assertFalse(registry.supportsInterface(0xdeadbeef), "unknown interface");
    }

    /*//////////////////////////////////////////////////////////////
                              ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function test_RevertWhen_StrangerMutatesAnything() public {
        address member = genesisAttestors[0];
        vm.startPrank(stranger);

        _expectUnauthorized(stranger);
        registry.addAttestor(_synthetic(200));

        _expectUnauthorized(stranger);
        registry.removeAttestor(member);

        _expectUnauthorized(stranger);
        registry.replaceAttestor(member, _synthetic(200));

        _expectUnauthorized(stranger);
        registry.setThreshold(4);

        _expectUnauthorized(stranger);
        registry.setPolicyVersion(2);

        vm.stopPrank();

        assertEq(registry.attestorEpoch(), GENESIS_EPOCH, "no unauthorized call moved the epoch");
    }

    /// @dev Least privilege made observable: holding `DEFAULT_ADMIN_ROLE` grants role
    ///      administration only, never the power to rotate the verifier set.
    function test_DefaultAdminAloneCannotMutate() public {
        registry.renounceRole(mutatorRole, deployer);
        assertTrue(registry.hasRole(adminRole, deployer), "still role admin");

        _expectUnauthorized(deployer);
        registry.addAttestor(_synthetic(201));

        // ...but it can still grant the rotation role to someone else.
        registry.grantRole(mutatorRole, timelock);
        vm.prank(timelock);
        registry.replaceAttestor(genesisAttestors[0], _synthetic(201));
        assertTrue(registry.isAttestor(_synthetic(201)), "grantee can rotate");
    }

    /// @notice Simulates the production handover: roles move to the timelock and the deployer is
    ///         left with literally zero authority over this contract.
    function test_TimelockHandoverFullyRevokesDeployer() public {
        address member = genesisAttestors[0];

        registry.grantRole(adminRole, timelock);
        registry.grantRole(mutatorRole, timelock);
        registry.renounceRole(mutatorRole, deployer);
        registry.renounceRole(adminRole, deployer);

        assertFalse(registry.hasRole(adminRole, deployer), "deployer lost role administration");
        assertFalse(registry.hasRole(mutatorRole, deployer), "deployer lost mutation rights");
        assertTrue(registry.hasRole(adminRole, timelock), "timelock is role admin");
        assertTrue(registry.hasRole(mutatorRole, timelock), "timelock can rotate");

        _expectUnauthorized(deployer);
        registry.addAttestor(_synthetic(202));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, deployer, adminRole)
        );
        registry.grantRole(mutatorRole, deployer);

        vm.prank(timelock);
        registry.replaceAttestor(member, _synthetic(202));
        assertTrue(registry.isAttestor(_synthetic(202)), "timelock retains full control");
    }

    /*//////////////////////////////////////////////////////////////
                                  FUZZ
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor threshold/count validation holds over the whole input space.
    function testFuzz_ConstructorBoundsHold(uint256 rawCount, uint8 rawThreshold) public {
        uint256 count = bound(rawCount, 1, 40);
        uint8 thresholdValue = uint8(bound(uint256(rawThreshold), 0, 40));

        bool countOk = count == 5;
        bool thresholdOk = thresholdValue >= 3 && uint256(thresholdValue) <= count;

        if (!countOk) {
            vm.expectRevert(abi.encodeWithSelector(IBitcoinAttestorRegistry.AttestorCountOutOfRange.selector, count));
        } else if (!thresholdOk) {
            vm.expectRevert(
                abi.encodeWithSelector(IBitcoinAttestorRegistry.ThresholdOutOfRange.selector, thresholdValue, count)
            );
        }

        BitcoinAttestorRegistry deployed =
            new BitcoinAttestorRegistry(deployer, _syntheticSet(count), thresholdValue, GENESIS_POLICY);

        if (countOk && thresholdOk) {
            assertEq(deployed.attestorCount(), count, "count");
            assertEq(deployed.threshold(), thresholdValue, "threshold");
            assertEq(deployed.attestorEpoch(), GENESIS_EPOCH, "epoch");
        }
    }

    /// @notice Random mutation sequences never break the fixed size or threshold invariants, and the
    ///         epoch advances by exactly the number of accepted mutations.
    /// @dev Rejected attempts are expected and are the point: the assertions below must hold after
    ///      every step whether the call succeeded or reverted.
    function testFuzz_AddRemoveSequenceKeepsInvariants(uint256 seed, uint8 steps) public {
        BitcoinAttestorRegistry target = _deploy(5, 4);
        uint256 stepCount = bound(uint256(steps), 1, 60);
        uint64 accepted = 0;

        for (uint256 i = 0; i < stepCount; i++) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            address candidate = _synthetic(entropy % 48);

            if (entropy % 3 == 0) {
                try target.addAttestor(candidate) {
                    accepted++;
                } catch {}
            } else if (entropy % 3 == 1) {
                try target.removeAttestor(candidate) {
                    accepted++;
                } catch {}
            } else {
                uint8 wanted = uint8(3 + (entropy >> 8) % 30);
                try target.setThreshold(wanted) {
                    accepted++;
                } catch {}
            }

            uint256 count = target.attestorCount();
            assertEq(count, 5, "count remains exactly five");
            assertGe(target.threshold(), 3, "threshold floor");
            assertLe(uint256(target.threshold()), count, "threshold never exceeds count");
            assertEq(target.attestors().length, count, "snapshot matches count");
            assertEq(target.attestorEpoch(), GENESIS_EPOCH + accepted, "one bump per accepted mutation");
        }
    }
}

/// @title AttestorRegistryHandler
/// @notice Stateful-fuzz driver that owns `ATTESTOR_ADMIN_ROLE` and counts accepted mutations.
/// @dev `foundry.toml` sets `fail_on_revert = false`, but every call here is wrapped in
///      `try/catch` anyway so the handler can maintain an exact ghost count of ACCEPTED mutations.
///      That ghost is what turns "epoch increments exactly once per mutation" from a per-test
///      assertion into a stateful invariant.
contract AttestorRegistryHandler {
    BitcoinAttestorRegistry public immutable REGISTRY;

    /// @notice Number of mutations that actually took effect.
    uint256 public acceptedMutations;

    /// @notice Largest attestor count observed across the campaign (always five by invariant).
    uint256 public maxCountSeen;

    constructor(BitcoinAttestorRegistry registry) {
        REGISTRY = registry;
        maxCountSeen = registry.attestorCount();
    }

    /// @dev Fixed pool makes replacements, duplicate adds, and unknown removals collide often.
    function _candidate(uint256 index) private pure returns (address) {
        return address(uint160(0xBEEF0000 + (index % 48)));
    }

    function _observe() private {
        uint256 count = REGISTRY.attestorCount();
        if (count > maxCountSeen) maxCountSeen = count;
    }

    /// @notice Try to add a candidate attestor.
    /// @param index Selector into the fixed candidate pool.
    function addAttestor(uint256 index) external {
        try REGISTRY.addAttestor(_candidate(index)) {
            acceptedMutations++;
        } catch {}
        _observe();
    }

    /// @notice Try to remove a candidate attestor.
    /// @param index Selector into the fixed candidate pool.
    function removeAttestor(uint256 index) external {
        try REGISTRY.removeAttestor(_candidate(index)) {
            acceptedMutations++;
        } catch {}
        _observe();
    }

    /// @notice Try to swap one candidate for another.
    /// @param oldIndex Selector for the outgoing member.
    /// @param newIndex Selector for the incoming member.
    function replaceAttestor(uint256 oldIndex, uint256 newIndex) external {
        try REGISTRY.replaceAttestor(_candidate(oldIndex), _candidate(newIndex)) {
            acceptedMutations++;
        } catch {}
        _observe();
    }

    /// @notice Try to set an arbitrary threshold, including illegal ones.
    /// @param raw Raw fuzz value, deliberately not clamped to the legal range.
    function setThreshold(uint8 raw) external {
        try REGISTRY.setThreshold(raw) {
            acceptedMutations++;
        } catch {}
        _observe();
    }

    /// @notice Try to set an arbitrary policy version, including zero.
    /// @param raw Raw fuzz value.
    function setPolicyVersion(uint32 raw) external {
        try REGISTRY.setPolicyVersion(raw) {
            acceptedMutations++;
        } catch {}
        _observe();
    }
}

/// @title BitcoinAttestorRegistryInvariants
/// @notice Handler-based stateful invariants for the registry.
/// @dev Lives in this file because it targets a contract this agent owns and shares its fixtures;
///      splitting it out would create a file outside this task's ownership.
contract BitcoinAttestorRegistryInvariants is StdInvariant, Test {
    BitcoinAttestorRegistry internal registry;
    AttestorRegistryHandler internal handler;

    function setUp() public {
        address[] memory genesis = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            // casting to 'uint160' is safe because `i` is bounded by the loop to 0..4.
            // forge-lint: disable-next-line(unsafe-typecast)
            genesis[i] = address(uint160(0xBEEF0000 + i));
        }
        registry = new BitcoinAttestorRegistry(address(this), genesis, 3, 1);
        handler = new AttestorRegistryHandler(registry);
        registry.grantRole(registry.ATTESTOR_ADMIN_ROLE(), address(handler));

        // Only the handler drives state; the registry is never called directly by the fuzzer,
        // which would otherwise just produce a wall of AccessControl reverts.
        targetContract(address(handler));
    }

    /// @notice The verifier set can never leave the production size window.
    function invariant_CountStaysWithinProductionBounds() public view {
        uint256 count = registry.attestorCount();
        assertEq(count, 5, "attestor count departed from fixed trust shape");
        assertEq(registry.MIN_ATTESTORS(), registry.MAX_ATTESTORS(), "fixed membership bounds drifted");
    }

    /// @notice Quorum is always both meaningful (>= 3) and reachable (<= count).
    function invariant_ThresholdStaysSafe() public view {
        uint8 t = registry.threshold();
        assertGe(t, registry.MIN_THRESHOLD(), "threshold below floor");
        assertLe(uint256(t), registry.attestorCount(), "threshold exceeds count: quorum unreachable");
    }

    /// @notice The epoch advances by exactly one per accepted mutation, and never otherwise.
    function invariant_EpochTracksAcceptedMutationsExactly() public view {
        assertEq(uint256(registry.attestorEpoch()), 1 + handler.acceptedMutations(), "epoch drifted from mutations");
    }

    /// @notice Policy version is never zero once deployed.
    function invariant_PolicyVersionNeverZero() public view {
        assertTrue(registry.policyVersion() != 0, "policy version fell to zero");
    }

    /// @notice `attestors()`, `attestorCount()`, `attestorAt()` and `isAttestor()` never disagree.
    function invariant_MembershipViewsAgree() public view {
        address[] memory snapshot = registry.attestors();
        assertEq(snapshot.length, registry.attestorCount(), "snapshot length");
        for (uint256 i = 0; i < snapshot.length; i++) {
            assertTrue(snapshot[i] != address(0), "zero address entered the set");
            assertTrue(registry.isAttestor(snapshot[i]), "snapshot member not recognised");
            assertEq(registry.attestorAt(i), snapshot[i], "indexed access disagrees with snapshot");
        }
    }
}
