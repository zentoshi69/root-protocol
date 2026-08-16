// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {BitcoinAttestorRegistry} from "../../src/BitcoinAttestorRegistry.sol";
import {BitcoinOwnershipOracle} from "../../src/BitcoinOwnershipOracle.sol";
import {BtcSolverSettlement} from "../../src/BtcSolverSettlement.sol";
import {PayoutVault} from "../../src/PayoutVault.sol";
import {PuppetCollectionRegistry} from "../../src/PuppetCollectionRegistry.sol";
import {IBitcoinAttestorRegistry} from "../../src/interfaces/IBitcoinAttestorRegistry.sol";
import {IBitcoinOwnershipOracle} from "../../src/interfaces/IBitcoinOwnershipOracle.sol";
import {IBtcSolverSettlement} from "../../src/interfaces/IBtcSolverSettlement.sol";
import {IHoodPupOfferEscrow} from "../../src/interfaces/IHoodPupOfferEscrow.sol";
import {IHoodPups} from "../../src/interfaces/IHoodPups.sol";
import {IPayoutVault} from "../../src/interfaces/IPayoutVault.sol";
import {IPuppetCollectionRegistry} from "../../src/interfaces/IPuppetCollectionRegistry.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";
import {AttestorSet} from "../helpers/AttestorSet.sol";
import {MerkleFixture} from "../helpers/MerkleFixture.sol";
import {MockHoodPups} from "../mocks/MockHoodPups.sol";

/*//////////////////////////////////////////////////////////////
                       TEST-ONLY ESCROW STAND-IN
//////////////////////////////////////////////////////////////*/

/// @title MockOfferEscrow
/// @notice Minimal `IHoodPupOfferEscrow` stand-in for the solver settlement suites.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      WHY IT LIVES IN A `.t.sol` FILE. `test/mocks/` is owned by another agent in this build and
///      `HoodPupOfferEscrow.sol` itself is being written concurrently, so this suite builds against
///      the FROZEN `IHoodPupOfferEscrow` interface instead. Inheriting the interface (rather than
///      just matching selectors) is deliberate: if a signature this contract calls ever drifts, the
///      mock stops compiling instead of silently reverting at run time.
///
///      HONESTY NOTE — READ BEFORE TRUSTING A GREEN TEST THAT USES THIS:
///      this mock does NOT model offer creation rules, expiry windows, the 50/25/25 split, refunds,
///      pausing, `FeeRouter` routing, `RootOwnershipRegistry` recording, or attestation validation
///      on the ownership side. Nothing here is evidence about `HoodPupOfferEscrow`'s correctness.
///
///      What it DOES keep faithful, because `BtcSolverSettlement` genuinely depends on it:
///        * the three BTC hooks are role gated, so "only the settlement contract may reserve /
///          clear / finalize" is a real property here;
///        * `markBtcReserved` requires `BTC_APPROVED` and `clearBtcReservation` /
///          `finalizeBtcSettlement` require `BTC_RESERVED`, so illegal orderings revert;
///        * `finalizeBtcSettlement` mints through `MockHoodPups`, which enforces one HoodPup per
///          Root, so a Root minted by any other path makes settlement revert exactly as production
///          would;
///        * the seller share is credited to the SOLVER through the real `PayoutVault`, so the bond
///          credit and the seller reimbursement are separately observable and cannot be confused.
contract MockOfferEscrow is IHoodPupOfferEscrow {
    /// @notice Raised by the parts of the interface this mock deliberately does not model.
    error NotImplementedInMock();
    /// @notice Raised when a BTC hook is called by anything but the wired settlement contract.
    error NotBtcSettlement(address caller);
    /// @notice Raised when the forced-failure switch is armed on `finalizeBtcSettlement`.
    error MockFinalizeForcedRevert();
    /// @notice Raised when the forced-failure switch is armed on `markBtcReserved`.
    error MockMarkReservedForcedRevert();

    /// @notice Reentrancy probe modes used by the reentrancy tests.
    enum Attack {
        NONE,
        EXPIRE,
        RESERVE
    }

    MockHoodPups public immutable HOODPUPS;
    IPayoutVault public immutable VAULT;

    address public btcSettlement;

    mapping(bytes32 => PuppetTypes.Offer) private _offers;
    mapping(bytes32 => PuppetTypes.RootId) private _rootIds;

    uint256 private _seedNonce;

    bool public finalizeReverts;
    bool public markReservedReverts;
    Attack public attackOnFinalize;

    uint256 public markReservedCount;
    uint256 public clearCount;
    uint256 public finalizeCount;

    /// @notice Payment digest handed to the most recent `finalizeBtcSettlement`.
    bytes32 public lastPaymentDigest;
    /// @notice Solver named in the most recent `finalizeBtcSettlement`.
    address public lastFinalizeSolver;

    constructor(MockHoodPups hoodPups_, IPayoutVault vault_) {
        HOODPUPS = hoodPups_;
        VAULT = vault_;
    }

    /*//////////////////////////////////////////////////////////////
                             TEST MUTATORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Wire the address allowed to drive the three BTC hooks.
    function setBtcSettlement(address settlement) external {
        btcSettlement = settlement;
    }

    /// @notice Make `finalizeBtcSettlement` revert, so atomic-rollback behaviour is testable.
    function setFinalizeReverts(bool on) external {
        finalizeReverts = on;
    }

    /// @notice Make `markBtcReserved` revert, so reserve-time rollback is testable.
    function setMarkReservedReverts(bool on) external {
        markReservedReverts = on;
    }

    /// @notice Arm a reentrant call back into the settlement contract from inside finalization.
    function setAttackOnFinalize(Attack mode) external {
        attackOnFinalize = mode;
    }

    /// @notice Overwrite an offer's status directly, to reach states this mock cannot otherwise
    ///         produce (REFUNDED, SETTLED-by-another-path, and so on).
    function forceStatus(bytes32 offerId, uint8 status) external {
        _offers[offerId].status = status;
    }

    /// @notice Overwrite an offer's approved BTC terms, to build deliberately malformed offers.
    function forceBtcTerms(bytes32 offerId, bytes32 ownershipDigest, bytes32 btcPayoutScriptHash, uint64 sellerSats)
        external
    {
        _offers[offerId].ownershipDigest = ownershipDigest;
        _offers[offerId].btcPayoutScriptHash = btcPayoutScriptHash;
        _offers[offerId].sellerSats = sellerSats;
    }

    /// @notice Create an offer already in `BTC_APPROVED`, funded with its gross escrow.
    /// @dev `msg.value` is the buyer's escrow. `sellerWei` of it is what the solver collects on
    ///      settlement; the remainder stands in for the treasury and protocol shares, which this
    ///      mock does not route anywhere.
    function seedApprovedBtcOffer(
        address buyer,
        address recipient,
        PuppetTypes.RootId calldata root,
        uint256 sellerWei,
        uint64 sellerSats,
        uint64 expiry,
        bytes32 ownershipDigest,
        bytes32 btcPayoutScriptHash
    ) external payable returns (bytes32 offerId) {
        offerId = keccak256(abi.encode("MOCK_OFFER", address(this), buyer, _seedNonce++));
        bytes32 key = PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);

        PuppetTypes.Offer storage o = _offers[offerId];
        o.buyer = buyer;
        o.recipient = recipient;
        o.rootKey = key;
        o.rootTxid = root.inscriptionTxid;
        o.rootIndex = root.inscriptionIndex;
        o.grossWei = msg.value;
        o.sellerWei = sellerWei;
        o.sellerSats = sellerSats;
        o.createdAt = uint64(block.timestamp);
        o.expiry = expiry;
        o.kind = uint8(PuppetTypes.OfferKind.PAID_BTC);
        o.status = uint8(PuppetTypes.OfferStatus.BTC_APPROVED);
        o.ownershipDigest = ownershipDigest;
        o.btcPayoutScriptHash = btcPayoutScriptHash;

        _rootIds[offerId] = root;

        emit BtcOfferApproved(offerId, ownershipDigest, btcPayoutScriptHash, sellerSats);
    }

    /*//////////////////////////////////////////////////////////////
                                BTC HOOKS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    function markBtcReserved(bytes32 offerId, address solver, uint64 reservationExpiry) external {
        _onlySettlement();
        if (markReservedReverts) revert MockMarkReservedForcedRevert();

        PuppetTypes.Offer storage o = _offers[offerId];
        if (o.status != uint8(PuppetTypes.OfferStatus.BTC_APPROVED)) {
            revert InvalidOfferStatus(offerId, o.status, uint8(PuppetTypes.OfferStatus.BTC_APPROVED));
        }

        o.status = uint8(PuppetTypes.OfferStatus.BTC_RESERVED);
        o.reservedSolver = solver;
        o.reservationExpiry = reservationExpiry;
        markReservedCount++;

        emit BtcReserved(offerId, solver, reservationExpiry);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function clearBtcReservation(bytes32 offerId) external {
        _onlySettlement();

        PuppetTypes.Offer storage o = _offers[offerId];
        if (o.status != uint8(PuppetTypes.OfferStatus.BTC_RESERVED)) {
            revert InvalidOfferStatus(offerId, o.status, uint8(PuppetTypes.OfferStatus.BTC_RESERVED));
        }

        address solver = o.reservedSolver;
        o.status = uint8(PuppetTypes.OfferStatus.BTC_APPROVED);
        o.reservedSolver = address(0);
        o.reservationExpiry = 0;
        clearCount++;

        emit BtcReservationCleared(offerId, solver);
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function finalizeBtcSettlement(bytes32 offerId, address solver, bytes32 paymentDigest)
        external
        returns (uint256 tokenId)
    {
        _onlySettlement();
        if (finalizeReverts) revert MockFinalizeForcedRevert();

        PuppetTypes.Offer storage o = _offers[offerId];
        if (o.status != uint8(PuppetTypes.OfferStatus.BTC_RESERVED)) {
            revert InvalidOfferStatus(offerId, o.status, uint8(PuppetTypes.OfferStatus.BTC_RESERVED));
        }
        if (solver != o.reservedSolver) revert NotReservedSolver(solver, o.reservedSolver);

        if (attackOnFinalize == Attack.EXPIRE) {
            IBtcSolverSettlement(msg.sender).expireReservation(offerId);
        } else if (attackOnFinalize == Attack.RESERVE) {
            IBtcSolverSettlement(msg.sender).reserve{value: 1 ether}(offerId);
        }

        o.status = uint8(PuppetTypes.OfferStatus.SETTLED);
        finalizeCount++;
        lastPaymentDigest = paymentDigest;
        lastFinalizeSolver = solver;

        tokenId = HOODPUPS.mintRooted(o.recipient, _rootIds[offerId]);

        // Bob was already paid in BTC, so the seller share goes to the solver.
        if (address(VAULT) != address(0) && o.sellerWei != 0) {
            VAULT.credit{value: o.sellerWei}(solver);
        }

        emit OfferSettled(offerId, o.rootKey, tokenId, o.recipient, solver, o.grossWei, o.kind);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    function getOffer(bytes32 offerId) external view returns (PuppetTypes.Offer memory) {
        return _offers[offerId];
    }

    /*//////////////////////////////////////////////////////////////
                     UNMODELLED INTERFACE SURFACE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPupOfferEscrow
    function nextOfferId(address) external pure returns (bytes32) {
        revert NotImplementedInMock();
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function buyerNonce(address) external pure returns (uint256) {
        revert NotImplementedInMock();
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function computeTermsHash(bytes32, uint8, bytes32, address, address, uint256, uint256, uint64, uint64)
        external
        pure
        returns (bytes32)
    {
        revert NotImplementedInMock();
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function createPaidEvmOffer(PuppetTypes.RootId calldata, address, uint64, bytes32[] calldata)
        external
        payable
        returns (bytes32)
    {
        revert NotImplementedInMock();
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function createPaidBtcOffer(PuppetTypes.RootId calldata, address, uint64, uint64, bytes32[] calldata)
        external
        payable
        returns (bytes32)
    {
        revert NotImplementedInMock();
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function createSelfCastOffer(PuppetTypes.RootId calldata, address, uint64, bytes32[] calldata)
        external
        pure
        returns (bytes32)
    {
        revert NotImplementedInMock();
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function settlePaidEvm(bytes32, PuppetTypes.OwnershipAttestation calldata, bytes[] calldata, bytes32[] calldata)
        external
        pure
        returns (uint256)
    {
        revert NotImplementedInMock();
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function settleSelfCast(bytes32, PuppetTypes.OwnershipAttestation calldata, bytes[] calldata, bytes32[] calldata)
        external
        pure
        returns (uint256)
    {
        revert NotImplementedInMock();
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function approvePaidBtc(bytes32, PuppetTypes.OwnershipAttestation calldata, bytes[] calldata, bytes32[] calldata)
        external
        pure
    {
        revert NotImplementedInMock();
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function refundExpired(bytes32) external pure {
        revert NotImplementedInMock();
    }

    /// @inheritdoc IHoodPupOfferEscrow
    function refundUnfillable(bytes32) external pure {
        revert NotImplementedInMock();
    }

    function _onlySettlement() private view {
        if (msg.sender != btcSettlement) revert NotBtcSettlement(msg.sender);
    }
}

/// @title ContractSolver
/// @notice A solver that is a contract and CANNOT receive ETH.
/// @dev Exists to prove the bond comes back as a `PayoutVault` credit rather than a push: a solver
///      with no `receive` would otherwise be unable to settle at all.
contract ContractSolver {
    IBtcSolverSettlement private immutable SETTLEMENT;

    constructor(IBtcSolverSettlement settlement) {
        SETTLEMENT = settlement;
    }

    /// @notice Post a bond for `offerId`.
    function doReserve(bytes32 offerId) external payable {
        SETTLEMENT.reserve{value: msg.value}(offerId);
    }

    /// @notice Settle `offerId`.
    function doSettle(
        bytes32 offerId,
        PuppetTypes.BitcoinPaymentAttestation calldata attestation,
        bytes[] calldata signatures
    ) external returns (uint256) {
        return SETTLEMENT.settle(offerId, attestation, signatures);
    }

    // Deliberately no receive() and no fallback().
}

/*//////////////////////////////////////////////////////////////
                              THE SUITE
//////////////////////////////////////////////////////////////*/

/// @title BtcSolverSettlementTest
/// @notice Unit and fuzz suite for `BtcSolverSettlement`.
/// @dev WHAT IS REAL HERE AND WHAT IS NOT. The oracle, the attestor registry, the collection
///      registry and the payout vault are the PRODUCTION contracts, not mocks. That matters: it
///      makes "a stale attestor epoch cannot settle", "a stale policy version cannot settle", "an
///      expired deadline cannot settle", "two of five is not a quorum", "an outsider signature does
///      not count" and "one Bitcoin output settles at most one offer" genuine claims about the real
///      verification path rather than claims about a permissive stub. Only the escrow is mocked,
///      because it is being written concurrently; see `MockOfferEscrow`'s honesty note for exactly
///      what that mock does and does not model.
///
///      CHEAT-CODE HAZARD, learned the hard way in three sibling suites: `vm.expectRevert` and
///      `vm.prank` bind to the very NEXT external call, and function arguments are evaluated BEFORE
///      the call they are passed to. An inline `attestors.sign(...)` or `settlement.PAUSER_ROLE()`
///      in an argument position therefore CONSUMES the cheat code and makes the assertion vacuous.
///      Every signature array, role id and digest in this file is hoisted into a local or a cached
///      field before the guarded call.
contract BtcSolverSettlementTest is Test {
    /*//////////////////////////////////////////////////////////////
                                FIXTURES
    //////////////////////////////////////////////////////////////*/

    BtcSolverSettlement internal settlement;
    MockOfferEscrow internal escrow;
    MockHoodPups internal hoodPups;
    BitcoinOwnershipOracle internal oracle;
    BitcoinAttestorRegistry internal attestorRegistry;
    PuppetCollectionRegistry internal collectionRegistry;
    PayoutVault internal vault;
    AttestorSet internal attestors;

    address internal admin = address(0xAD0111);
    address internal guardian = address(0x6A12DD);
    address internal protocolSlashRecipient = address(0x9207);
    address internal buyer = address(0xB0FFEE);
    address internal recipient = address(0xB0B111);
    address internal solver = address(0x501FE1);
    address internal otherSolver = address(0x501FE2);
    address internal relayer = address(0xBEEF01);

    uint256 internal constant MIN_BOND = 0.5 ether;
    uint64 internal constant RESERVATION_DURATION = 6 hours;
    uint16 internal constant BUYER_SLASH_BPS = 7000;

    uint256 internal constant GROSS_WEI = 4 ether;
    uint256 internal constant SELLER_WEI = 2 ether;
    uint64 internal constant SELLER_SATS = 3_141_592;

    bytes32 internal constant OWNERSHIP_DIGEST = keccak256("FIXTURE_OWNERSHIP_DIGEST");
    bytes32 internal constant SELLER_SCRIPT_HASH = keccak256("FIXTURE_SELLER_SCRIPTPUBKEY");

    /// @dev Hoisted role ids and offer expiry, so no cheat code is ever consumed by an argument.
    bytes32 internal configAdminRole;
    bytes32 internal pauserRole;
    bytes32 internal defaultAdminRole;
    uint64 internal offerExpiry;

    PuppetTypes.RootId internal rootA;
    PuppetTypes.RootId internal rootB;

    function setUp() public {
        vm.warp(1_760_000_000);

        rootA = PuppetTypes.RootId({inscriptionTxid: _fixtureTxid("root-a"), inscriptionIndex: 0});
        rootB = PuppetTypes.RootId({inscriptionTxid: _fixtureTxid("root-b"), inscriptionIndex: 7});

        attestors = new AttestorSet(5, keccak256("HOODPUPS_SOLVER_SUITE_SEED"));

        PuppetTypes.RootId[] memory members = new PuppetTypes.RootId[](2);
        members[0] = rootA;
        members[1] = rootB;
        collectionRegistry = new PuppetCollectionRegistry(
            MerkleFixture.buildFromRoots(members), keccak256("solver-suite-manifest"), "solver-suite-v1", members.length
        );

        attestorRegistry = new BitcoinAttestorRegistry(admin, attestors.sortedAddresses(), 3, 1);
        oracle = new BitcoinOwnershipOracle(
            admin,
            IPuppetCollectionRegistry(address(collectionRegistry)),
            IBitcoinAttestorRegistry(address(attestorRegistry))
        );
        vault = new PayoutVault(admin);
        hoodPups = new MockHoodPups();
        escrow = new MockOfferEscrow(hoodPups, IPayoutVault(address(vault)));

        settlement = new BtcSolverSettlement(
            admin,
            IHoodPupOfferEscrow(address(escrow)),
            IBitcoinOwnershipOracle(address(oracle)),
            IPayoutVault(address(vault)),
            MIN_BOND,
            RESERVATION_DURATION,
            BUYER_SLASH_BPS,
            protocolSlashRecipient
        );

        escrow.setBtcSettlement(address(settlement));

        vm.startPrank(admin);
        oracle.grantRole(oracle.PAYMENT_CONSUMER_ROLE(), address(settlement));
        vault.grantRole(vault.CREDITOR_ROLE(), address(settlement));
        vault.grantRole(vault.CREDITOR_ROLE(), address(escrow));
        settlement.grantRole(settlement.PAUSER_ROLE(), guardian);
        vm.stopPrank();

        configAdminRole = settlement.CONFIG_ADMIN_ROLE();
        pauserRole = settlement.PAUSER_ROLE();
        defaultAdminRole = settlement.DEFAULT_ADMIN_ROLE();
        offerExpiry = uint64(block.timestamp) + 3 days;

        vm.deal(solver, 100 ether);
        vm.deal(otherSolver, 100 ether);
        vm.deal(relayer, 100 ether);
        vm.deal(buyer, 100 ether);
        vm.deal(address(this), 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    function test_ConstructorStoresConfigurationAndWiring() public view {
        assertEq(settlement.minimumBondWei(), MIN_BOND, "minimum bond");
        assertEq(settlement.reservationDuration(), RESERVATION_DURATION, "reservation duration");
        assertEq(settlement.buyerSlashBps(), BUYER_SLASH_BPS, "buyer slash bps");
        assertEq(settlement.protocolSlashRecipient(), protocolSlashRecipient, "protocol slash recipient");
        assertEq(address(settlement.ESCROW()), address(escrow), "escrow");
        assertEq(address(settlement.ORACLE()), address(oracle), "oracle");
        assertEq(address(settlement.PAYOUT_VAULT()), address(vault), "vault");
        assertEq(settlement.BPS_DENOMINATOR(), 10_000, "bps denominator");
    }

    function test_ConstructorGrantsExactlyThreeGovernanceRoles() public view {
        assertTrue(settlement.hasRole(defaultAdminRole, admin), "admin lacks DEFAULT_ADMIN_ROLE");
        assertTrue(settlement.hasRole(configAdminRole, admin), "admin lacks CONFIG_ADMIN_ROLE");
        assertTrue(settlement.hasRole(pauserRole, admin), "admin lacks PAUSER_ROLE");

        // No EOA owner is baked in anywhere: the deployer holds nothing.
        assertFalse(settlement.hasRole(defaultAdminRole, address(this)), "deployer holds admin");
        assertFalse(settlement.hasRole(configAdminRole, address(this)), "deployer holds config");
        assertFalse(settlement.hasRole(pauserRole, address(this)), "deployer holds pauser");
    }

    function test_ConstructorRejectsEveryZeroAddress() public {
        vm.expectRevert(IBtcSolverSettlement.ZeroAddress.selector);
        new BtcSolverSettlement(
            address(0),
            IHoodPupOfferEscrow(address(escrow)),
            IBitcoinOwnershipOracle(address(oracle)),
            IPayoutVault(address(vault)),
            MIN_BOND,
            RESERVATION_DURATION,
            BUYER_SLASH_BPS,
            protocolSlashRecipient
        );

        vm.expectRevert(IBtcSolverSettlement.ZeroAddress.selector);
        new BtcSolverSettlement(
            admin,
            IHoodPupOfferEscrow(address(0)),
            IBitcoinOwnershipOracle(address(oracle)),
            IPayoutVault(address(vault)),
            MIN_BOND,
            RESERVATION_DURATION,
            BUYER_SLASH_BPS,
            protocolSlashRecipient
        );

        vm.expectRevert(IBtcSolverSettlement.ZeroAddress.selector);
        new BtcSolverSettlement(
            admin,
            IHoodPupOfferEscrow(address(escrow)),
            IBitcoinOwnershipOracle(address(0)),
            IPayoutVault(address(vault)),
            MIN_BOND,
            RESERVATION_DURATION,
            BUYER_SLASH_BPS,
            protocolSlashRecipient
        );

        vm.expectRevert(IBtcSolverSettlement.ZeroAddress.selector);
        new BtcSolverSettlement(
            admin,
            IHoodPupOfferEscrow(address(escrow)),
            IBitcoinOwnershipOracle(address(oracle)),
            IPayoutVault(address(0)),
            MIN_BOND,
            RESERVATION_DURATION,
            BUYER_SLASH_BPS,
            protocolSlashRecipient
        );

        vm.expectRevert(IBtcSolverSettlement.ZeroAddress.selector);
        new BtcSolverSettlement(
            admin,
            IHoodPupOfferEscrow(address(escrow)),
            IBitcoinOwnershipOracle(address(oracle)),
            IPayoutVault(address(vault)),
            MIN_BOND,
            RESERVATION_DURATION,
            BUYER_SLASH_BPS,
            address(0)
        );
    }

    function test_ConstructorRejectsUnsafeEconomics() public {
        // Hoisted: an inline `settlement.MIN_RESERVATION_DURATION()` would consume the cheat code.
        uint64 tooShort = settlement.MIN_RESERVATION_DURATION() - 1;
        uint64 tooLong = settlement.MAX_RESERVATION_DURATION() + 1;

        // A free reservation is a free denial of service on every BTC offer.
        vm.expectRevert(IBtcSolverSettlement.InvalidConfiguration.selector);
        _deployWith(0, RESERVATION_DURATION, BUYER_SLASH_BPS);

        vm.expectRevert(IBtcSolverSettlement.InvalidConfiguration.selector);
        _deployWith(MIN_BOND, tooShort, BUYER_SLASH_BPS);

        vm.expectRevert(IBtcSolverSettlement.InvalidConfiguration.selector);
        _deployWith(MIN_BOND, tooLong, BUYER_SLASH_BPS);

        vm.expectRevert(IBtcSolverSettlement.InvalidConfiguration.selector);
        _deployWith(MIN_BOND, RESERVATION_DURATION, 10_001);
    }

    function test_ConstructorAcceptsBothReservationDurationBounds() public {
        BtcSolverSettlement low = _deployWith(MIN_BOND, settlement.MIN_RESERVATION_DURATION(), BUYER_SLASH_BPS);
        BtcSolverSettlement high = _deployWith(MIN_BOND, settlement.MAX_RESERVATION_DURATION(), BUYER_SLASH_BPS);
        assertEq(low.reservationDuration(), 1 hours, "min bound rejected");
        assertEq(high.reservationDuration(), 30 days, "max bound rejected");
    }

    function test_ConstructorEmitsSettlementDeployed() public {
        vm.recordLogs();
        BtcSolverSettlement fresh = _deployWith(MIN_BOND, RESERVATION_DURATION, BUYER_SLASH_BPS);

        // The constructor emits three RoleGranted events first, so scan rather than expectEmit.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == BtcSolverSettlement.SettlementDeployed.selector) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), admin, "admin in event");
            }
        }
        assertTrue(found, "SettlementDeployed not emitted");
        assertEq(fresh.minimumBondWei(), MIN_BOND, "fresh deployment misconfigured");
    }

    /*//////////////////////////////////////////////////////////////
                                RESERVE
    //////////////////////////////////////////////////////////////*/

    function test_ReserveSucceedsAndSnapshotsTerms() public {
        bytes32 offerId = _seedOffer(rootA);

        vm.expectEmit(true, true, false, true, address(settlement));
        emit IBtcSolverSettlement.Reserved(
            offerId, solver, 1 ether, uint64(block.timestamp) + RESERVATION_DURATION, BUYER_SLASH_BPS
        );

        vm.prank(solver);
        settlement.reserve{value: 1 ether}(offerId);

        IBtcSolverSettlement.Reservation memory r = settlement.reservationOf(offerId);
        assertEq(r.solver, solver, "solver");
        assertEq(r.bondWei, 1 ether, "bond");
        assertEq(r.reservedAt, uint64(block.timestamp), "reservedAt");
        assertEq(r.reservationExpiry, uint64(block.timestamp) + RESERVATION_DURATION, "expiry");
        assertEq(r.buyerSlashBpsSnapshot, BUYER_SLASH_BPS, "slash snapshot");
        assertEq(r.status, uint8(IBtcSolverSettlement.ReservationStatus.ACTIVE), "status");

        assertEq(settlement.totalActiveBondWei(), 1 ether, "active liability");
        assertEq(settlement.totalBondsPosted(), 1 ether, "posted");
        assertEq(address(settlement).balance, 1 ether, "held ETH");
        assertTrue(settlement.bondBooksBalance(), "books");

        // The escrow really did move to BTC_RESERVED, naming this solver.
        PuppetTypes.Offer memory offer = escrow.getOffer(offerId);
        assertEq(offer.status, uint8(PuppetTypes.OfferStatus.BTC_RESERVED), "escrow status");
        assertEq(offer.reservedSolver, solver, "escrow solver");
        assertEq(escrow.markReservedCount(), 1, "markBtcReserved call count");
    }

    function test_ReserveAcceptsExactMinimumAndRejectsOneWeiLess() public {
        bytes32 offerId = _seedOffer(rootA);

        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.InsufficientBond.selector, MIN_BOND - 1, MIN_BOND));
        settlement.reserve{value: MIN_BOND - 1}(offerId);

        vm.prank(solver);
        settlement.reserve{value: MIN_BOND}(offerId);
        assertEq(settlement.reservationOf(offerId).bondWei, MIN_BOND, "exact minimum rejected");
    }

    function test_ReserveKeepsOverpaymentAsBond() public {
        bytes32 offerId = _seedOffer(rootA);

        vm.prank(solver);
        settlement.reserve{value: 9 ether}(offerId);

        assertEq(settlement.reservationOf(offerId).bondWei, 9 ether, "overpayment not kept as bond");
        assertEq(settlement.totalActiveBondWei(), 9 ether, "liability");
        assertEq(address(settlement).balance, 9 ether, "no wei retained elsewhere");
    }

    function test_ReserveRevertsWhenAlreadyReserved() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        vm.prank(otherSolver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.AlreadyReserved.selector, offerId, solver));
        settlement.reserve{value: 1 ether}(offerId);
    }

    function test_ReserveRevertsForEveryNonApprovedOfferStatus() public {
        uint8[4] memory bad = [
            uint8(PuppetTypes.OfferStatus.NONE),
            uint8(PuppetTypes.OfferStatus.OPEN),
            uint8(PuppetTypes.OfferStatus.SETTLED),
            uint8(PuppetTypes.OfferStatus.REFUNDED)
        ];

        for (uint256 i = 0; i < bad.length; i++) {
            bytes32 offerId = _seedOffer(rootA);
            escrow.forceStatus(offerId, bad[i]);

            vm.prank(solver);
            vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.OfferNotBtcApproved.selector, offerId, bad[i]));
            settlement.reserve{value: 1 ether}(offerId);
        }
    }

    function test_ReserveRevertsWhenEscrowSaysReservedButWeDoNot() public {
        // State divergence: the escrow believes the offer is reserved, this contract does not.
        // Reserving anyway would let two solvers believe they own the same offer.
        bytes32 offerId = _seedOffer(rootA);
        escrow.forceStatus(offerId, uint8(PuppetTypes.OfferStatus.BTC_RESERVED));

        vm.prank(solver);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBtcSolverSettlement.OfferNotBtcApproved.selector, offerId, uint8(PuppetTypes.OfferStatus.BTC_RESERVED)
            )
        );
        settlement.reserve{value: 1 ether}(offerId);
    }

    function test_ReserveExpiryBoundaryIsInclusive() public {
        bytes32 offerId = _seedOffer(rootA);

        vm.warp(offerExpiry);
        vm.prank(solver);
        settlement.reserve{value: 1 ether}(offerId);
        assertEq(
            settlement.reservationOf(offerId).status,
            uint8(IBtcSolverSettlement.ReservationStatus.ACTIVE),
            "offer must be live through its whole expiry second"
        );

        bytes32 second = _seedOffer(rootB);
        vm.warp(offerExpiry + 1);
        vm.prank(otherSolver);
        vm.expectRevert(abi.encodeWithSelector(BtcSolverSettlement.OfferExpired.selector, second, offerExpiry));
        settlement.reserve{value: 1 ether}(second);
    }

    function test_ReserveRejectsStructurallyUnpayableOffers() public {
        bytes32 noDigest = _seedOffer(rootA);
        escrow.forceBtcTerms(noDigest, bytes32(0), SELLER_SCRIPT_HASH, SELLER_SATS);
        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(BtcSolverSettlement.IncompleteBtcOffer.selector, noDigest));
        settlement.reserve{value: 1 ether}(noDigest);

        bytes32 noScript = _seedOffer(rootA);
        escrow.forceBtcTerms(noScript, OWNERSHIP_DIGEST, bytes32(0), SELLER_SATS);
        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(BtcSolverSettlement.IncompleteBtcOffer.selector, noScript));
        settlement.reserve{value: 1 ether}(noScript);

        bytes32 noSats = _seedOffer(rootA);
        escrow.forceBtcTerms(noSats, OWNERSHIP_DIGEST, SELLER_SCRIPT_HASH, 0);
        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(BtcSolverSettlement.IncompleteBtcOffer.selector, noSats));
        settlement.reserve{value: 1 ether}(noSats);
    }

    function test_ReserveRevertsWhenPaused() public {
        bytes32 offerId = _seedOffer(rootA);

        vm.prank(guardian);
        settlement.pause();

        vm.prank(solver);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        settlement.reserve{value: 1 ether}(offerId);
    }

    function test_ReserveRollsBackCompletelyWhenEscrowRejects() public {
        bytes32 offerId = _seedOffer(rootA);
        escrow.setMarkReservedReverts(true);

        vm.prank(solver);
        vm.expectRevert(MockOfferEscrow.MockMarkReservedForcedRevert.selector);
        settlement.reserve{value: 1 ether}(offerId);

        assertEq(
            settlement.reservationOf(offerId).status,
            uint8(IBtcSolverSettlement.ReservationStatus.NONE),
            "reservation survived a failed escrow call"
        );
        assertEq(settlement.totalBondsPosted(), 0, "bond recorded despite rollback");
        assertEq(address(settlement).balance, 0, "wei retained despite rollback");
    }

    function test_ReserveRevertsOnceAnotherOfferSettledTheSameRoot() public {
        bytes32 first = _seedOffer(rootA);
        _reserve(first, solver, 1 ether);
        _settle(first, solver, _fixtureTxid("payment-1"), 0);

        bytes32 competing = _seedOffer(rootA);
        bytes32 rootKey = PuppetHashing.rootKey(rootA.inscriptionTxid, rootA.inscriptionIndex);

        vm.prank(otherSolver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.RootAlreadyMinted.selector, rootKey));
        settlement.reserve{value: 1 ether}(competing);
    }

    function test_ReserveRevertsOnAnOfferThatAlreadySettled() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        _settle(offerId, solver, _fixtureTxid("payment-1"), 0);

        bytes32 rootKey = PuppetHashing.rootKey(rootA.inscriptionTxid, rootA.inscriptionIndex);
        vm.prank(otherSolver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.RootAlreadyMinted.selector, rootKey));
        settlement.reserve{value: 1 ether}(offerId);
    }

    function test_NoAdminPathCanChooseOrEvictASolver() public view {
        bytes32[8] memory forbidden = [
            keccak256("setSolver(bytes32,address)"),
            keccak256("assignSolver(bytes32,address)"),
            keccak256("forceExpire(bytes32)"),
            keccak256("forgiveSlash(bytes32)"),
            keccak256("cancelReservation(bytes32)"),
            keccak256("withdraw(uint256)"),
            keccak256("upgradeTo(address)"),
            keccak256("initialize(address)")
        ];

        bytes memory code = address(settlement).code;
        for (uint256 i = 0; i < forbidden.length; i++) {
            assertFalse(_containsSelector(code, bytes4(forbidden[i])), "forbidden selector present in bytecode");
        }

        // Positive control: the scan is capable of finding something that IS there.
        assertTrue(
            _containsSelector(code, bytes4(keccak256("reservationOf(bytes32)"))),
            "bytecode scan found nothing at all, so the negative results mean nothing"
        );
    }

    function test_NoPriceOracleSurfaceExists() public view {
        // Not decoration: a BTC/ETH feed appearing here would silently reintroduce oracle
        // manipulation into a settlement path that is deliberately built without one.
        bytes32[6] memory forbidden = [
            keccak256("latestAnswer()"),
            keccak256("latestRoundData()"),
            keccak256("getPrice()"),
            keccak256("setPriceOracle(address)"),
            keccak256("btcPerEth()"),
            keccak256("quoteSats(uint256)")
        ];

        bytes memory code = address(settlement).code;
        for (uint256 i = 0; i < forbidden.length; i++) {
            assertFalse(_containsSelector(code, bytes4(forbidden[i])), "a price oracle surface exists");
        }
        assertTrue(_containsSelector(code, bytes4(keccak256("minimumBondWei()"))), "positive control failed");
    }

    /*//////////////////////////////////////////////////////////////
                                 SETTLE
    //////////////////////////////////////////////////////////////*/

    function test_SettleHappyPath() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        bytes32 txid = _fixtureTxid("payment-happy");
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment(offerId, solver, txid, 1, SELLER_SATS);
        bytes32 digest = oracle.hashBitcoinPaymentAttestation(a);
        bytes[] memory sigs = attestors.sign(digest, 3);

        vm.expectEmit(true, true, true, true, address(settlement));
        emit IBtcSolverSettlement.Settled(offerId, solver, digest, txid, 1, SELLER_SATS, SELLER_SCRIPT_HASH, 1 ether);

        vm.prank(solver);
        uint256 tokenId = settlement.settle(offerId, a, sigs);

        assertEq(tokenId, 1, "token id");
        assertEq(hoodPups.mintCount(), 1, "mint did not happen");
        assertEq(hoodPups.ownerOf(tokenId), recipient, "minted to the wrong address");

        IBtcSolverSettlement.Reservation memory r = settlement.reservationOf(offerId);
        assertEq(r.status, uint8(IBtcSolverSettlement.ReservationStatus.SETTLED), "status");

        // Bond back plus the seller share, both as vault credits.
        assertEq(vault.claimable(solver), 1 ether + SELLER_WEI, "solver credit");
        assertEq(settlement.totalActiveBondWei(), 0, "liability not cleared");
        assertEq(settlement.totalBondsReturned(), 1 ether, "returned ledger");
        assertEq(settlement.totalBondsSlashed(), 0, "nothing should be slashed");
        assertEq(address(settlement).balance, 0, "settlement retained wei");
        assertTrue(settlement.bondBooksBalance(), "books");

        // The payment output is burned globally.
        assertTrue(oracle.isPaymentOutputConsumed(txid, 1), "payment output not consumed");
        assertTrue(oracle.isDigestConsumed(digest), "digest not consumed");
        assertEq(escrow.lastPaymentDigest(), digest, "escrow got the wrong digest");
    }

    function test_SettleRevertsWithoutAnActiveReservation() public {
        bytes32 offerId = _seedOffer(rootA);
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment(offerId, solver, _fixtureTxid("p"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.NoActiveReservation.selector, offerId));
        settlement.settle(offerId, a, sigs);
    }

    function test_SettleRevertsForARelayerThatIsNotTheSolver() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        PuppetTypes.BitcoinPaymentAttestation memory a = _payment(offerId, solver, _fixtureTxid("p"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.NotReservedSolver.selector, relayer, solver));
        settlement.settle(offerId, a, sigs);
    }

    function test_SettleRevertsWhenTheAttestationNamesAnotherSolver() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        // A perfectly valid 3-of-5 quorum, over an attestation that reimburses somebody else.
        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, otherSolver, _fixtureTxid("p"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.NotReservedSolver.selector, otherSolver, solver));
        settlement.settle(offerId, a, sigs);
    }

    function test_SettleReservationExpiryBoundaryIsInclusive() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        uint64 expiry = settlement.reservationOf(offerId).reservationExpiry;

        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("boundary"), 0, SELLER_SATS);

        vm.warp(expiry);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);
        vm.prank(solver);
        settlement.settle(offerId, a, sigs);
        assertEq(
            settlement.reservationOf(offerId).status,
            uint8(IBtcSolverSettlement.ReservationStatus.SETTLED),
            "settlement must be allowed through the whole expiry second"
        );
    }

    function test_SettleRevertsOneSecondAfterReservationExpiry() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        uint64 expiry = settlement.reservationOf(offerId).reservationExpiry;

        vm.warp(uint256(expiry) + 1);
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment(offerId, solver, _fixtureTxid("late"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.ReservationExpired.selector, offerId, expiry));
        settlement.settle(offerId, a, sigs);
    }

    function test_SettleSucceedsAfterOfferExpiryWhileTheReservationIsLive() public {
        // THE GRACE WINDOW. A solver that paid real BTC just before the offer lapsed must still be
        // able to collect; the buyer is protected because the escrow stays BTC_RESERVED meanwhile.
        bytes32 offerId = _seedOffer(rootA);
        vm.warp(offerExpiry);
        _reserve(offerId, solver, 1 ether);

        vm.warp(uint256(offerExpiry) + 1 hours);
        assertGt(block.timestamp, escrow.getOffer(offerId).expiry, "offer should be past its own expiry");

        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("grace"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.prank(solver);
        settlement.settle(offerId, a, sigs);
        assertEq(vault.claimable(solver), 1 ether + SELLER_WEI, "solver was not made whole inside the grace window");
    }

    function test_SettleRejectsEveryMismatchedPaymentField() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        // contextId
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment(offerId, solver, _fixtureTxid("f1"), 0, SELLER_SATS);
        a.contextId = keccak256("some other offer");
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);
        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.PaymentFieldMismatch.selector, "contextId"));
        settlement.settle(offerId, a, sigs);

        // ownershipDigest
        a = _payment(offerId, solver, _fixtureTxid("f2"), 0, SELLER_SATS);
        a.ownershipDigest = keccak256("a different ownership fact");
        sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);
        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.PaymentFieldMismatch.selector, "ownershipDigest"));
        settlement.settle(offerId, a, sigs);

        // recipientScriptHash — the solver paid the wrong Bitcoin script.
        a = _payment(offerId, solver, _fixtureTxid("f3"), 0, SELLER_SATS);
        a.recipientScriptHash = keccak256("the solver's own change address");
        sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);
        vm.prank(solver);
        vm.expectRevert(
            abi.encodeWithSelector(IBtcSolverSettlement.PaymentFieldMismatch.selector, "recipientScriptHash")
        );
        settlement.settle(offerId, a, sigs);

        // amountSats — one satoshi short.
        a = _payment(offerId, solver, _fixtureTxid("f4"), 0, SELLER_SATS - 1);
        sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);
        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.PaymentFieldMismatch.selector, "amountSats"));
        settlement.settle(offerId, a, sigs);

        // amountSats — one satoshi over. Exactness cuts both ways so the recorded fact is the fact.
        a = _payment(offerId, solver, _fixtureTxid("f5"), 0, SELLER_SATS + 1);
        sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);
        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.PaymentFieldMismatch.selector, "amountSats"));
        settlement.settle(offerId, a, sigs);

        // Nothing above touched the books.
        assertEq(settlement.totalActiveBondWei(), 1 ether, "a rejected settlement moved the ledgers");
        assertEq(hoodPups.mintCount(), 0, "a rejected settlement minted");
    }

    function test_OneBitcoinOutputCannotSettleTwoOffers() public {
        bytes32 txid = _fixtureTxid("reused-output");

        bytes32 first = _seedOffer(rootA);
        _reserve(first, solver, 1 ether);
        _settle(first, solver, txid, 3);

        // A different offer, a different Root, a different solver — the same Bitcoin output.
        bytes32 second = _seedOffer(rootB);
        _reserve(second, otherSolver, 1 ether);
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment(second, otherSolver, txid, 3, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);
        bytes32 key = PuppetHashing.paymentOutputKey(txid, 3);

        vm.prank(otherSolver);
        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.PaymentOutputAlreadyConsumed.selector, key));
        settlement.settle(second, a, sigs);
    }

    function test_DifferentVoutOfTheSameTxidStaysIndependent() public {
        bytes32 txid = _fixtureTxid("two-outputs");

        bytes32 first = _seedOffer(rootA);
        _reserve(first, solver, 1 ether);
        _settle(first, solver, txid, 0);

        bytes32 second = _seedOffer(rootB);
        _reserve(second, otherSolver, 1 ether);
        _settle(second, otherSolver, txid, 1);

        assertEq(hoodPups.mintCount(), 2, "two distinct outputs must settle two offers");
    }

    function test_SettleRevertsOnStaleAttestorEpoch() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("stale"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        // A real production mutation on the real registry bumps the epoch under the in-flight
        // signatures. Every attestation collected before it becomes worthless.
        vm.prank(admin);
        attestorRegistry.addAttestor(address(0xADD1));

        vm.prank(solver);
        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinOwnershipOracle.StaleAttestorEpoch.selector, uint64(1), uint64(2))
        );
        settlement.settle(offerId, a, sigs);
    }

    function test_SettleRevertsOnStalePolicyVersion() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("policy"), 0, SELLER_SATS);
        a.attestorEpoch = 2; // will be the epoch after the policy bump
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.prank(admin);
        attestorRegistry.setPolicyVersion(9);

        vm.prank(solver);
        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinOwnershipOracle.StalePolicyVersion.selector, uint32(1), uint32(9))
        );
        settlement.settle(offerId, a, sigs);
    }

    function test_SettleRevertsOnExpiredAttestationDeadline() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("deadline"), 0, SELLER_SATS);
        a.deadline = uint64(block.timestamp) + 10;
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.warp(block.timestamp + 11);
        vm.prank(solver);
        vm.expectRevert(
            abi.encodeWithSelector(IBitcoinOwnershipOracle.DeadlineExpired.selector, a.deadline, block.timestamp)
        );
        settlement.settle(offerId, a, sigs);
    }

    function test_SettleRevertsBelowQuorumAndOnOutsiderSignatures() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("quorum"), 0, SELLER_SATS);
        bytes32 digest = oracle.hashBitcoinPaymentAttestation(a);

        bytes[] memory two = attestors.sign(digest, 2);
        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.InsufficientSignatures.selector, 2, uint8(3)));
        settlement.settle(offerId, a, two);

        bytes[] memory withOutsider = attestors.signWithOutsider(digest, 2);
        address outsider = attestors.outsider();
        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.SignerNotAttestor.selector, outsider));
        settlement.settle(offerId, a, withOutsider);
    }

    function test_SettleWorksWhileReservationsArePaused() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        vm.prank(guardian);
        settlement.pause();

        _settle(offerId, solver, _fixtureTxid("paused-settle"), 0);
        assertEq(vault.claimable(solver), 1 ether + SELLER_WEI, "a pause blocked an already-paid solver");
    }

    function test_SettleRevertsWhenTheOracleIsPaused() public {
        // The incident lever the specification asks for lives on the oracle, where the risk is.
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        vm.prank(admin);
        oracle.pause();

        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("oracle-paused"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.prank(solver);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        settlement.settle(offerId, a, sigs);
    }

    function test_SettleRevertsWithoutThePaymentConsumerRole() public {
        bytes32 role = oracle.PAYMENT_CONSUMER_ROLE();
        vm.prank(admin);
        oracle.revokeRole(role, address(settlement));

        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("norole"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.prank(solver);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(settlement), role)
        );
        settlement.settle(offerId, a, sigs);
    }

    function test_NoReimbursementWhenMintFinalizationFails() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        escrow.setFinalizeReverts(true);

        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("rollback"), 0, SELLER_SATS);
        bytes32 digest = oracle.hashBitcoinPaymentAttestation(a);
        bytes[] memory sigs = attestors.sign(digest, 3);

        vm.prank(solver);
        vm.expectRevert(MockOfferEscrow.MockFinalizeForcedRevert.selector);
        settlement.settle(offerId, a, sigs);

        // Everything rolled back, including the oracle consumption.
        assertEq(vault.claimable(solver), 0, "solver was reimbursed without a mint");
        assertFalse(oracle.isDigestConsumed(digest), "digest burned by a failed settlement");
        assertFalse(oracle.isPaymentOutputConsumed(_fixtureTxid("rollback"), 0), "output burned by a failed settlement");
        assertEq(
            settlement.reservationOf(offerId).status,
            uint8(IBtcSolverSettlement.ReservationStatus.ACTIVE),
            "reservation was closed by a failed settlement"
        );
        assertEq(settlement.totalActiveBondWei(), 1 ether, "bond liability moved");
        assertEq(address(settlement).balance, 1 ether, "bond left the contract");

        // And the solver can retry once the failure is cleared, with the SAME attestation.
        escrow.setFinalizeReverts(false);
        vm.prank(solver);
        settlement.settle(offerId, a, sigs);
        assertEq(vault.claimable(solver), 1 ether + SELLER_WEI, "retry after rollback failed");
    }

    function test_NoReimbursementWhenTheRootWasMintedByAnotherPath() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        // A competing settlement path (an ETH offer, a self-cast) got there first.
        hoodPups.mintRooted(address(0xDEAD), rootA);

        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("raced"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.prank(solver);
        vm.expectPartialRevert(IHoodPups.RootAlreadyMinted.selector);
        settlement.settle(offerId, a, sigs);

        assertEq(vault.claimable(solver), 0, "solver reimbursed for an impossible mint");
        assertEq(settlement.totalActiveBondWei(), 1 ether, "books moved on a failed settlement");
    }

    function test_SettleCannotHappenTwice() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        _settle(offerId, solver, _fixtureTxid("once"), 0);

        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("twice"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.NoActiveReservation.selector, offerId));
        settlement.settle(offerId, a, sigs);
    }

    function test_ASolverContractThatCannotReceiveEthStillGetsPaid() public {
        ContractSolver cs = new ContractSolver(IBtcSolverSettlement(address(settlement)));

        bytes32 offerId = _seedOffer(rootA);
        cs.doReserve{value: 1 ether}(offerId);

        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, address(cs), _fixtureTxid("contract-solver"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);
        cs.doSettle(offerId, a, sigs);

        assertEq(address(cs).balance, 0, "ETH was pushed to a contract that cannot receive it");
        assertEq(vault.claimable(address(cs)), 1 ether + SELLER_WEI, "credit missing");
    }

    function test_ReentrantEscrowCannotReenterAnyValuePath() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("reentrant"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        escrow.setAttackOnFinalize(MockOfferEscrow.Attack.EXPIRE);
        vm.prank(solver);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        settlement.settle(offerId, a, sigs);

        escrow.setAttackOnFinalize(MockOfferEscrow.Attack.RESERVE);
        vm.prank(solver);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        settlement.settle(offerId, a, sigs);

        assertEq(settlement.totalActiveBondWei(), 1 ether, "reentrancy attempt moved the books");
    }

    /*//////////////////////////////////////////////////////////////
                          EXPIRY AND SLASHING
    //////////////////////////////////////////////////////////////*/

    function test_ExpireReservationSlashesAndReleasesTheOffer() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        uint64 expiry = settlement.reservationOf(offerId).reservationExpiry;

        uint256 expectedBuyer = (1 ether * uint256(BUYER_SLASH_BPS)) / 10_000;
        uint256 expectedProtocol = 1 ether - expectedBuyer;

        vm.warp(uint256(expiry) + 1);
        vm.expectEmit(true, true, false, true, address(settlement));
        emit IBtcSolverSettlement.ReservationExpiredAndSlashed(
            offerId, solver, 1 ether, expectedBuyer, expectedProtocol
        );

        vm.prank(relayer);
        settlement.expireReservation(offerId);

        assertEq(
            settlement.reservationOf(offerId).status, uint8(IBtcSolverSettlement.ReservationStatus.EXPIRED), "status"
        );
        assertEq(vault.claimable(buyer), expectedBuyer, "buyer compensation");
        assertEq(vault.claimable(protocolSlashRecipient), expectedProtocol, "protocol share");
        assertEq(vault.claimable(solver), 0, "a slashed solver kept part of its bond");
        assertEq(expectedBuyer + expectedProtocol, 1 ether, "conservation");

        assertEq(settlement.totalActiveBondWei(), 0, "liability");
        assertEq(settlement.totalBondsSlashed(), 1 ether, "slashed ledger");
        assertEq(address(settlement).balance, 0, "wei retained");
        assertTrue(settlement.bondBooksBalance(), "books");

        // The offer is back in BTC_APPROVED, so it is reservable and refundable again.
        assertEq(escrow.getOffer(offerId).status, uint8(PuppetTypes.OfferStatus.BTC_APPROVED), "escrow not released");
        assertEq(escrow.clearCount(), 1, "clearBtcReservation call count");
    }

    function test_ExpireBoundaryIsExclusiveOfTheExpirySecond() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        uint64 expiry = settlement.reservationOf(offerId).reservationExpiry;

        vm.warp(expiry);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.ReservationNotExpired.selector, offerId, expiry));
        settlement.expireReservation(offerId);

        vm.warp(uint256(expiry) + 1);
        settlement.expireReservation(offerId);
        assertEq(
            settlement.reservationOf(offerId).status,
            uint8(IBtcSolverSettlement.ReservationStatus.EXPIRED),
            "one second past expiry must be enough"
        );
    }

    function test_ExpireRevertsForEveryNonActiveStatus() public {
        bytes32 never = _seedOffer(rootA);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.NoActiveReservation.selector, never));
        settlement.expireReservation(never);

        // Both offers are seeded BEFORE the long warp, because an offer past its own expiry can
        // no longer be reserved at all and the test would stop testing what it claims to.
        bytes32 settled = _seedOffer(rootB);
        bytes32 expired = _seedOffer(rootA);
        _reserve(settled, solver, 1 ether);
        _reserve(expired, solver, 1 ether);
        _settle(settled, solver, _fixtureTxid("expire-settled"), 0);

        vm.warp(block.timestamp + 100 days);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.NoActiveReservation.selector, settled));
        settlement.expireReservation(settled);

        settlement.expireReservation(expired);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.NoActiveReservation.selector, expired));
        settlement.expireReservation(expired);
    }

    function test_ExpireWorksWhileReservationsArePaused() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        vm.prank(guardian);
        settlement.pause();

        vm.warp(block.timestamp + RESERVATION_DURATION + 1);
        settlement.expireReservation(offerId);
        assertEq(
            vault.claimable(buyer),
            (1 ether * uint256(BUYER_SLASH_BPS)) / 10_000,
            "a pause blocked a buyer's refund path"
        );
    }

    function test_ExpireUsesTheSnapshotNotTheLiveConfiguration() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 2 ether);
        uint64 originalExpiry = settlement.reservationOf(offerId).reservationExpiry;

        // Governance changes everything it can, after the fact.
        vm.startPrank(admin);
        settlement.setBuyerSlashBps(10_000);
        settlement.setReservationDuration(settlement.MIN_RESERVATION_DURATION());
        settlement.setMinimumBondWei(50 ether);
        vm.stopPrank();

        // The window is still the one snapshotted at reservation, not the new shorter one.
        vm.warp(uint256(block.timestamp) + settlement.MIN_RESERVATION_DURATION() + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IBtcSolverSettlement.ReservationNotExpired.selector, offerId, originalExpiry)
        );
        settlement.expireReservation(offerId);

        vm.warp(uint256(originalExpiry) + 1);
        settlement.expireReservation(offerId);

        // And the split is the one snapshotted, not the new 100%-to-buyer rule.
        assertEq(
            vault.claimable(buyer),
            (2 ether * uint256(BUYER_SLASH_BPS)) / 10_000,
            "buyer share was retroactively raised"
        );
        assertEq(
            vault.claimable(protocolSlashRecipient), 2 ether - (2 ether * uint256(BUYER_SLASH_BPS)) / 10_000, "protocol"
        );
    }

    function test_ConfigChangeCannotShortenALiveSolverWindow() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        uint64 expiry = settlement.reservationOf(offerId).reservationExpiry;

        uint64 shortest = settlement.MIN_RESERVATION_DURATION();
        vm.prank(admin);
        settlement.setReservationDuration(shortest);

        assertEq(settlement.reservationOf(offerId).reservationExpiry, expiry, "snapshot was mutated");

        vm.warp(uint256(expiry) - 1);
        _settle(offerId, solver, _fixtureTxid("still-valid"), 0);
        assertEq(vault.claimable(solver), 1 ether + SELLER_WEI, "the solver lost its window to a config change");
    }

    function test_SlashSplitTableConservesExactly() public {
        uint16[6] memory bpsTable = [uint16(0), 1, 3333, 7000, 9999, 10_000];

        for (uint256 i = 0; i < bpsTable.length; i++) {
            BtcSolverSettlement s = _freshDeploymentWith(bpsTable[i]);
            bytes32 offerId = _seedOfferOn(s, rootA);

            uint256 bond = 1 ether + i; // deliberately not a round number
            vm.deal(solver, bond);
            vm.prank(solver);
            s.reserve{value: bond}(offerId);

            vm.warp(block.timestamp + RESERVATION_DURATION + 1);
            uint256 buyerBefore = vault.claimable(buyer);
            uint256 protocolBefore = vault.claimable(protocolSlashRecipient);
            s.expireReservation(offerId);

            uint256 buyerDelta = vault.claimable(buyer) - buyerBefore;
            uint256 protocolDelta = vault.claimable(protocolSlashRecipient) - protocolBefore;

            assertEq(buyerDelta, (bond * bpsTable[i]) / 10_000, "buyer share");
            assertEq(buyerDelta + protocolDelta, bond, "conservation broken: dust was created or lost");
            assertEq(address(s).balance, 0, "wei retained after slashing");
            assertTrue(s.bondBooksBalance(), "books");
        }
    }

    function test_ReReservationAfterTimeoutByANewSolver() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        vm.warp(block.timestamp + RESERVATION_DURATION + 1);
        settlement.expireReservation(offerId);

        // A second solver rescues the offer.
        _reserve(offerId, otherSolver, 2 ether);
        IBtcSolverSettlement.Reservation memory r = settlement.reservationOf(offerId);
        assertEq(r.solver, otherSolver, "re-reservation did not take");
        assertEq(r.bondWei, 2 ether, "bond");
        assertEq(r.status, uint8(IBtcSolverSettlement.ReservationStatus.ACTIVE), "status");

        _settle(offerId, otherSolver, _fixtureTxid("rescue"), 0);
        assertEq(vault.claimable(otherSolver), 2 ether + SELLER_WEI, "rescuing solver was not paid");

        // The first solver's slash is untouched by the rescue.
        assertEq(vault.claimable(solver), 0, "slashed solver clawed value back");
        assertEq(settlement.totalBondsPosted(), 3 ether, "posted ledger");
        assertEq(settlement.totalBondsSlashed(), 1 ether, "slashed ledger");
        assertEq(settlement.totalBondsReturned(), 2 ether, "returned ledger");
        assertTrue(settlement.bondBooksBalance(), "books");
    }

    function test_NoDiscretionaryForgivenessExistsForAdmins() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        vm.warp(block.timestamp + RESERVATION_DURATION + 1);

        // Even holding every role, the admin has exactly one thing it can do here, and it is the
        // same thing anybody else can do: expire the reservation on the published terms.
        vm.prank(admin);
        settlement.expireReservation(offerId);

        assertEq(vault.claimable(solver), 0, "an admin path returned a slashed bond");
        assertEq(
            vault.claimable(buyer), (1 ether * uint256(BUYER_SLASH_BPS)) / 10_000, "buyer share changed by the caller"
        );
    }

    /*//////////////////////////////////////////////////////////////
                      CONFIGURATION AND ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function test_ConfigSettersRequireConfigAdminRole() public {
        vm.startPrank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, relayer, configAdminRole)
        );
        settlement.setMinimumBondWei(1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, relayer, configAdminRole)
        );
        settlement.setReservationDuration(2 hours);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, relayer, configAdminRole)
        );
        settlement.setBuyerSlashBps(1);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, relayer, configAdminRole)
        );
        settlement.setProtocolSlashRecipient(relayer);
        vm.stopPrank();
    }

    function test_DefaultAdminAloneCannotChangeConfiguration() public {
        // Least privilege: the two duties are separable, and this proves they really are separate.
        vm.prank(admin);
        settlement.revokeRole(configAdminRole, admin);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, configAdminRole)
        );
        settlement.setMinimumBondWei(1 ether);
    }

    function test_ConfigSettersRejectNoOpWrites() public {
        vm.startPrank(admin);
        vm.expectRevert(BtcSolverSettlement.ConfigUnchanged.selector);
        settlement.setMinimumBondWei(MIN_BOND);

        vm.expectRevert(BtcSolverSettlement.ConfigUnchanged.selector);
        settlement.setReservationDuration(RESERVATION_DURATION);

        vm.expectRevert(BtcSolverSettlement.ConfigUnchanged.selector);
        settlement.setBuyerSlashBps(BUYER_SLASH_BPS);

        vm.expectRevert(BtcSolverSettlement.ConfigUnchanged.selector);
        settlement.setProtocolSlashRecipient(protocolSlashRecipient);
        vm.stopPrank();
    }

    function test_ConfigSettersEnforceTheirBounds() public {
        vm.startPrank(admin);
        vm.expectRevert(IBtcSolverSettlement.InvalidConfiguration.selector);
        settlement.setMinimumBondWei(0);

        vm.expectRevert(IBtcSolverSettlement.InvalidConfiguration.selector);
        settlement.setReservationDuration(59 minutes);

        vm.expectRevert(IBtcSolverSettlement.InvalidConfiguration.selector);
        settlement.setReservationDuration(31 days);

        vm.expectRevert(IBtcSolverSettlement.InvalidConfiguration.selector);
        settlement.setBuyerSlashBps(10_001);

        vm.expectRevert(IBtcSolverSettlement.ZeroAddress.selector);
        settlement.setProtocolSlashRecipient(address(0));
        vm.stopPrank();
    }

    function test_ConfigSettersEmitTheirEvents() public {
        vm.startPrank(admin);

        vm.expectEmit(false, false, false, true, address(settlement));
        emit BtcSolverSettlement.MinimumBondUpdated(MIN_BOND, 3 ether);
        settlement.setMinimumBondWei(3 ether);

        vm.expectEmit(false, false, false, true, address(settlement));
        emit BtcSolverSettlement.ReservationDurationUpdated(RESERVATION_DURATION, 12 hours);
        settlement.setReservationDuration(12 hours);

        vm.expectEmit(false, false, false, true, address(settlement));
        emit BtcSolverSettlement.BuyerSlashBpsUpdated(BUYER_SLASH_BPS, 5000);
        settlement.setBuyerSlashBps(5000);

        vm.expectEmit(true, true, false, false, address(settlement));
        emit BtcSolverSettlement.ProtocolSlashRecipientUpdated(protocolSlashRecipient, relayer);
        settlement.setProtocolSlashRecipient(relayer);

        vm.stopPrank();
    }

    function test_PauseIsGuardianAndUnpauseIsTimelock() public {
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, relayer, pauserRole)
        );
        settlement.pause();

        vm.prank(guardian);
        settlement.pause();
        assertTrue(settlement.paused(), "not paused");

        // The guardian may stop risk but may not restart it.
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, guardian, defaultAdminRole)
        );
        settlement.unpause();

        vm.prank(admin);
        settlement.unpause();
        assertFalse(settlement.paused(), "still paused");
    }

    function test_TimelockHandoverFullyRevokesTheDeployerlessAdmin() public {
        address timelock = address(0x71E10C);

        vm.startPrank(admin);
        settlement.grantRole(defaultAdminRole, timelock);
        settlement.grantRole(configAdminRole, timelock);
        settlement.renounceRole(configAdminRole, admin);
        settlement.renounceRole(pauserRole, admin);
        settlement.renounceRole(defaultAdminRole, admin);
        vm.stopPrank();

        assertFalse(settlement.hasRole(defaultAdminRole, admin), "old admin retained admin");
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, configAdminRole)
        );
        settlement.setMinimumBondWei(9 ether);

        vm.prank(timelock);
        settlement.setMinimumBondWei(9 ether);
        assertEq(settlement.minimumBondWei(), 9 ether, "timelock cannot govern");
    }

    /*//////////////////////////////////////////////////////////////
                          ETH HANDLING AND VIEWS
    //////////////////////////////////////////////////////////////*/

    function test_DirectDepositsAreRejected() public {
        (bool okPlain,) = address(settlement).call{value: 1 ether}("");
        assertFalse(okPlain, "a bare transfer was accepted");

        (bool okData,) = address(settlement).call{value: 1 ether}(hex"deadbeef");
        assertFalse(okData, "an unknown selector with value was accepted");

        assertEq(address(settlement).balance, 0, "unattributable wei is being held");
    }

    function test_ForcedEthIsSweepableAndCannotTouchABond() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        vm.deal(address(settlement), address(settlement).balance + 0.75 ether);
        assertEq(settlement.forcedEthBalance(), 0.75 ether, "forced eth view");

        // Permissionless, no destination argument, and it can never reach the bond.
        vm.prank(relayer);
        uint256 swept = settlement.sweepForcedEth();

        assertEq(swept, 0.75 ether, "swept amount");
        assertEq(vault.claimable(protocolSlashRecipient), 0.75 ether, "forced eth credit");
        assertEq(settlement.totalActiveBondWei(), 1 ether, "bond liability changed");
        assertEq(address(settlement).balance, 1 ether, "the bond itself was swept");

        vm.expectRevert(BtcSolverSettlement.NoForcedEth.selector);
        settlement.sweepForcedEth();
    }

    function test_ForcedEthDoesNotBlockSettlementOrExpiry() public {
        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        vm.deal(address(settlement), address(settlement).balance + 5 ether);

        _settle(offerId, solver, _fixtureTxid("forced"), 0);
        assertEq(vault.claimable(solver), 1 ether + SELLER_WEI, "forced eth broke settlement");
        assertEq(address(settlement).balance, 5 ether, "forced eth was consumed by settlement");
        assertTrue(settlement.bondBooksBalance(), "books");
    }

    function test_SupportsInterface() public view {
        assertTrue(settlement.supportsInterface(type(IBtcSolverSettlement).interfaceId), "own interface");
        assertTrue(settlement.supportsInterface(0x01ffc9a7), "erc165");
        assertFalse(settlement.supportsInterface(0xffffffff), "invalid id");
    }

    function test_ReservationOfNeverRevertsForAnUnknownOffer() public view {
        IBtcSolverSettlement.Reservation memory r = settlement.reservationOf(keccak256("never existed"));
        assertEq(r.solver, address(0), "solver");
        assertEq(r.bondWei, 0, "bond");
        assertEq(r.status, uint8(IBtcSolverSettlement.ReservationStatus.NONE), "status");
    }

    function test_LedgerViewsTrackTheAccountingEquation() public {
        assertTrue(settlement.bondBooksBalance(), "empty books");

        bytes32 settled = _seedOffer(rootA);
        _reserve(settled, solver, 1 ether);
        bytes32 slashed = _seedOffer(rootB);
        _reserve(slashed, otherSolver, 3 ether);
        bytes32 live = _seedOffer(rootB);

        assertEq(settlement.totalBondsPosted(), 4 ether, "posted");
        assertEq(settlement.totalActiveBondWei(), 4 ether, "active");

        _settle(settled, solver, _fixtureTxid("ledger"), 0);
        vm.warp(block.timestamp + RESERVATION_DURATION + 1);
        settlement.expireReservation(slashed);

        _reserve(live, solver, 2 ether);

        assertEq(settlement.totalBondsPosted(), 6 ether, "posted");
        assertEq(settlement.totalActiveBondWei(), 2 ether, "active");
        assertEq(settlement.totalBondsReturned(), 1 ether, "returned");
        assertEq(settlement.totalBondsSlashed(), 3 ether, "slashed");
        assertTrue(settlement.bondBooksBalance(), "books");
        assertEq(address(settlement).balance, settlement.totalActiveBondWei(), "held ETH equals liability");
    }

    /*//////////////////////////////////////////////////////////////
                                  FUZZ
    //////////////////////////////////////////////////////////////*/

    /// @notice Any bond at or above the minimum is returned in full on settlement, never rounded.
    function testFuzz_BondIsReturnedInFullOnSettlement(uint96 extra) public {
        uint256 bond = MIN_BOND + uint256(extra);
        vm.deal(solver, bond);

        bytes32 offerId = _seedOffer(rootA);
        vm.prank(solver);
        settlement.reserve{value: bond}(offerId);

        _settle(offerId, solver, _fixtureTxid("fuzz-bond"), 0);

        assertEq(vault.claimable(solver), bond + SELLER_WEI, "bond not returned in full");
        assertEq(settlement.totalActiveBondWei(), 0, "liability");
        assertTrue(settlement.bondBooksBalance(), "books");
    }

    /// @notice The slash split conserves the bond exactly for every bond size and every bps value.
    function testFuzz_SlashConservesEveryWei(uint96 extra, uint16 bps) public {
        bps = uint16(bound(bps, 0, 10_000));
        uint256 bond = MIN_BOND + uint256(extra);

        BtcSolverSettlement s = _freshDeploymentWith(bps);
        bytes32 offerId = _seedOfferOn(s, rootA);

        vm.deal(solver, bond);
        vm.prank(solver);
        s.reserve{value: bond}(offerId);

        vm.warp(block.timestamp + RESERVATION_DURATION + 1);
        uint256 buyerBefore = vault.claimable(buyer);
        uint256 protocolBefore = vault.claimable(protocolSlashRecipient);
        s.expireReservation(offerId);

        uint256 buyerDelta = vault.claimable(buyer) - buyerBefore;
        uint256 protocolDelta = vault.claimable(protocolSlashRecipient) - protocolBefore;

        assertEq(buyerDelta, (bond * bps) / 10_000, "buyer share");
        assertEq(buyerDelta + protocolDelta, bond, "conservation");
        assertEq(address(s).balance, 0, "wei retained");
        assertTrue(s.bondBooksBalance(), "books");
    }

    /// @notice Anyone at all may expire a stale reservation; the outcome never depends on who.
    function testFuzz_ExpiryIsPermissionlessAndCallerIndependent(address caller) public {
        vm.assume(caller != address(0));
        vm.assume(caller != address(vault) && caller != address(settlement) && caller != address(escrow));
        vm.assume(caller.code.length == 0);

        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);
        vm.warp(block.timestamp + RESERVATION_DURATION + 1);

        vm.prank(caller);
        settlement.expireReservation(offerId);

        assertEq(
            vault.claimable(buyer), (1 ether * uint256(BUYER_SLASH_BPS)) / 10_000, "buyer share depended on the caller"
        );
        assertEq(vault.claimable(caller), 0, "the caller paid itself");
    }

    /// @notice No caller other than the reserved solver can ever drive a settlement.
    function testFuzz_OnlyTheReservedSolverCanSettle(address caller) public {
        vm.assume(caller != solver && caller != address(0));
        vm.assume(caller.code.length == 0);

        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        PuppetTypes.BitcoinPaymentAttestation memory a =
            _payment(offerId, solver, _fixtureTxid("fuzz-caller"), 0, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.NotReservedSolver.selector, caller, solver));
        settlement.settle(offerId, a, sigs);
    }

    /// @notice Any bond below the configured minimum is rejected, at every value.
    function testFuzz_BondsBelowTheMinimumAreAlwaysRejected(uint256 value) public {
        value = bound(value, 0, MIN_BOND - 1);
        bytes32 offerId = _seedOffer(rootA);
        vm.deal(solver, MIN_BOND);

        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.InsufficientBond.selector, value, MIN_BOND));
        settlement.reserve{value: value}(offerId);
    }

    /// @notice Any satoshi amount other than the offer's exact `sellerSats` is rejected.
    function testFuzz_OnlyTheExactSatoshiAmountSettles(uint64 sats) public {
        vm.assume(sats != SELLER_SATS);
        vm.assume(sats != 0); // zero is rejected by the oracle first, on a different rule

        bytes32 offerId = _seedOffer(rootA);
        _reserve(offerId, solver, 1 ether);

        PuppetTypes.BitcoinPaymentAttestation memory a = _payment(offerId, solver, _fixtureTxid("fuzz-sats"), 0, sats);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);

        vm.prank(solver);
        vm.expectRevert(abi.encodeWithSelector(IBtcSolverSettlement.PaymentFieldMismatch.selector, "amountSats"));
        settlement.settle(offerId, a, sigs);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Every fixture txid begins with the ASCII bytes "FIXTURE-NOT-REAL" so nothing in this
    ///      file can ever be mistaken for a real Bitcoin transaction or inscription.
    function _fixtureTxid(string memory tag) internal pure returns (bytes32) {
        // casting to 'bytes16' is safe because the truncation IS the point: the first 16 bytes are
        // the literal marker and only the low 16 bytes of the digest are needed to separate fixtures.
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes32(abi.encodePacked(bytes16("FIXTURE-NOT-REAL"), bytes16(keccak256(bytes(tag)))));
    }

    function _seedOffer(PuppetTypes.RootId memory root) internal returns (bytes32) {
        return _seedOfferOn(settlement, root);
    }

    /// @dev Seeds a BTC_APPROVED offer and wires `target` as the escrow's settlement contract, so
    ///      the fresh-deployment tests exercise a real role gate rather than an open door.
    function _seedOfferOn(BtcSolverSettlement target, PuppetTypes.RootId memory root) internal returns (bytes32) {
        escrow.setBtcSettlement(address(target));
        return escrow.seedApprovedBtcOffer{value: GROSS_WEI}(
            buyer, recipient, root, SELLER_WEI, SELLER_SATS, offerExpiry, OWNERSHIP_DIGEST, SELLER_SCRIPT_HASH
        );
    }

    function _reserve(bytes32 offerId, address who, uint256 bond) internal {
        vm.deal(who, who.balance + bond);
        vm.prank(who);
        settlement.reserve{value: bond}(offerId);
    }

    function _settle(bytes32 offerId, address who, bytes32 txid, uint32 vout) internal returns (uint256 tokenId) {
        PuppetTypes.BitcoinPaymentAttestation memory a = _payment(offerId, who, txid, vout, SELLER_SATS);
        bytes[] memory sigs = attestors.sign(oracle.hashBitcoinPaymentAttestation(a), 3);
        vm.prank(who);
        tokenId = settlement.settle(offerId, a, sigs);
    }

    function _payment(bytes32 offerId, address who, bytes32 txid, uint32 vout, uint64 sats)
        internal
        view
        returns (PuppetTypes.BitcoinPaymentAttestation memory)
    {
        (, uint64 epoch, uint32 policy) = attestorRegistry.quorumContext();
        return PuppetTypes.BitcoinPaymentAttestation({
            contextId: offerId,
            ownershipDigest: OWNERSHIP_DIGEST,
            solver: who,
            bitcoinTxid: txid,
            outputIndex: vout,
            recipientScriptHash: SELLER_SCRIPT_HASH,
            amountSats: sats,
            bitcoinBlockHash: _fixtureTxid("btc-block"),
            bitcoinHeight: 900_000,
            authorizationId: keccak256(abi.encode(offerId, txid, vout, who)),
            deadline: uint64(block.timestamp) + 1 days,
            attestorEpoch: epoch,
            policyVersion: policy
        });
    }

    function _deployWith(uint256 bond, uint64 duration, uint16 bps) internal returns (BtcSolverSettlement) {
        return new BtcSolverSettlement(
            admin,
            IHoodPupOfferEscrow(address(escrow)),
            IBitcoinOwnershipOracle(address(oracle)),
            IPayoutVault(address(vault)),
            bond,
            duration,
            bps,
            protocolSlashRecipient
        );
    }

    /// @dev A fresh settlement contract with a different slash policy, fully wired.
    function _freshDeploymentWith(uint16 bps) internal returns (BtcSolverSettlement s) {
        s = _deployWith(MIN_BOND, RESERVATION_DURATION, bps);
        vm.startPrank(admin);
        oracle.grantRole(oracle.PAYMENT_CONSUMER_ROLE(), address(s));
        vault.grantRole(vault.CREDITOR_ROLE(), address(s));
        vm.stopPrank();
    }

    /// @dev Naive 4-byte scan of runtime bytecode. It can produce a false FAILURE from a
    ///      coincidental byte sequence but never a false pass, which is the safe direction for a
    ///      "this function does not exist" claim. Every use pairs it with a positive control.
    function _containsSelector(bytes memory code, bytes4 selector) internal pure returns (bool) {
        if (code.length < 4) return false;
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
}
