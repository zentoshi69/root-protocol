// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {BitcoinAttestorRegistry} from "../../src/BitcoinAttestorRegistry.sol";
import {BitcoinOwnershipOracle} from "../../src/BitcoinOwnershipOracle.sol";
import {FeeRouter} from "../../src/FeeRouter.sol";
import {HoodPupOfferEscrow} from "../../src/HoodPupOfferEscrow.sol";
import {HoodPups} from "../../src/HoodPups.sol";
import {PayoutVault} from "../../src/PayoutVault.sol";
import {PuppetCollectionRegistry} from "../../src/PuppetCollectionRegistry.sol";
import {RootOwnershipRegistry} from "../../src/RootOwnershipRegistry.sol";

import {IBitcoinOwnershipOracle} from "../../src/interfaces/IBitcoinOwnershipOracle.sol";
import {IHoodPupOfferEscrow} from "../../src/interfaces/IHoodPupOfferEscrow.sol";
import {IPuppetCollectionRegistry} from "../../src/interfaces/IPuppetCollectionRegistry.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";

import {AttestorSet} from "../helpers/AttestorSet.sol";
import {MerkleFixture} from "../helpers/MerkleFixture.sol";
import {MockERC721Receiver, RejectingReceiver} from "../mocks/Receivers.sol";

/*//////////////////////////////////////////////////////////////
                      IN-FILE TEST FIXTURES
//////////////////////////////////////////////////////////////*/

/// @notice ERC-721 recipient that reenters the escrow from `onERC721Received`.
/// @dev The escrow's only untrusted external call is `_safeMint`'s receiver callback. This probe
///      makes that callback actually fire and try to run a second escrow entry point, so the
///      reentrancy tests can distinguish "the guard held" from "the callback never happened".
contract ReenteringMintRecipient is IERC721Receiver {
    address public escrow;
    bytes public payload;
    uint256 public attempts;
    uint256 public succeeded;
    bytes public lastReturnData;

    constructor(address escrow_) {
        escrow = escrow_;
    }

    function configure(bytes calldata nextPayload) external {
        payload = nextPayload;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (payload.length != 0) {
            attempts++;
            // Swallowed on purpose: bubbling the guard's revert would abort the outer settlement
            // and hide which of the two calls actually failed.
            (bool ok, bytes memory ret) = escrow.call(payload);
            lastReturnData = ret;
            if (ok) succeeded++;
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}

/*//////////////////////////////////////////////////////////////
                            THE FIXTURE
//////////////////////////////////////////////////////////////*/

/// @title EscrowFixture
/// @notice Full protocol deployment used by the escrow unit and fuzz suites.
/// @dev EVERY CONTRACT HERE IS THE REAL ONE. No mock oracle, no mock vault, no mock NFT. The
///      escrow's whole job is to make six other contracts agree inside one transaction, so a
///      permissive stand-in for any of them would hide exactly the class of bug this suite exists
///      to find — a role that was never granted, a payout the vault refuses, a quorum the oracle
///      rejects, a receiver the ERC-721 cannot reach.
///
///      The one thing the suite therefore inherits is real quorum verification: attestations are
///      signed by three of five deterministic keys and are checked by `BitcoinOwnershipOracle`
///      against the real `BitcoinAttestorRegistry`. That means a green run here IS evidence about
///      quorum handling, not just about the escrow's own branches.
abstract contract EscrowFixture is Test {
    /*//////////////////////////////////////////////////////////////
                              PARTICIPANTS
    //////////////////////////////////////////////////////////////*/

    address internal admin = makeAddr("timelockAdmin");
    address internal guardian = makeAddr("guardian");
    address internal buyer = makeAddr("buyer");
    address internal otherBuyer = makeAddr("otherBuyer");
    address internal recipient = makeAddr("recipient");
    address internal sellerPayout = makeAddr("bobEvmPayout");
    address internal solver = makeAddr("bondedSolver");
    address internal btcSettlement = makeAddr("btcSolverSettlementContract");
    address internal puppetTreasury = makeAddr("puppetTreasury");
    address internal protocolTreasury = makeAddr("protocolTreasury");
    address internal relayer = makeAddr("relayer");

    /*//////////////////////////////////////////////////////////////
                              DEPLOYMENTS
    //////////////////////////////////////////////////////////////*/

    AttestorSet internal attestors;
    BitcoinAttestorRegistry internal attestorRegistry;
    PuppetCollectionRegistry internal collection;
    BitcoinOwnershipOracle internal oracle;
    PayoutVault internal vault;
    HoodPups internal nft;
    RootOwnershipRegistry internal rootRegistry;
    FeeRouter internal router;
    HoodPupOfferEscrow internal escrow;

    /*//////////////////////////////////////////////////////////////
                            MANIFEST FIXTURE
    //////////////////////////////////////////////////////////////*/

    /// @dev Five manifest members plus one deliberate non-member. Members 0 and 1 share a reveal
    ///      txid and differ only by inscription index, so every identity check is forced to respect
    ///      the index rather than the txid alone.
    PuppetTypes.RootId[] internal roots;
    PuppetTypes.RootId internal outsiderRoot;
    bytes32[] internal leaves;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint64 internal constant MIN_DURATION = 1 hours;
    uint64 internal constant MAX_DURATION = 30 days;
    uint64 internal constant BTC_HEIGHT = 880_000;
    uint256 internal constant PRICE = 1 ether;

    bytes32 internal constant OUTPOINT = keccak256("FIXTURE-NOT-REAL:outpoint");
    bytes32 internal constant SCRIPT_HASH = keccak256("FIXTURE-NOT-REAL:scriptPubKey");
    bytes32 internal constant PROOF_HASH = keccak256("FIXTURE-NOT-REAL:bip322");
    bytes32 internal constant BTC_BLOCK = keccak256("FIXTURE-NOT-REAL:blockhash");
    bytes32 internal constant BTC_PAYOUT_SCRIPT = keccak256("FIXTURE-NOT-REAL:bobBtcScript");

    /// @dev Cached role ids. Reading `x.ROLE()` inline as an argument after `vm.prank` /
    ///      `vm.expectRevert` consumes the cheat code on the getter call, which silently makes the
    ///      assertion vacuous. Every role id in this file is hoisted for that reason.
    bytes32 internal roleBtcSettlement;
    bytes32 internal rolePauser;
    bytes32 internal roleDefaultAdmin;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        vm.warp(1_700_000_000);

        _buildManifest();

        attestors = new AttestorSet(5, keccak256("HOODPUPS_ESCROW_SUITE_V1"));

        attestorRegistry = new BitcoinAttestorRegistry(admin, attestors.sortedAddresses(), 3, 1);
        collection = new PuppetCollectionRegistry(
            MerkleFixture.build(leaves), keccak256("escrow-fixture-manifest"), "escrow-fixture-v1", leaves.length
        );
        oracle = new BitcoinOwnershipOracle(admin, collection, attestorRegistry);
        vault = new PayoutVault(admin);
        nft = new HoodPups(admin, "HoodPups", "HPUP", "ipfs://base/", "ipfs://collection");
        rootRegistry = new RootOwnershipRegistry(admin, address(oracle), address(vault));
        router = new FeeRouter(admin, vault, rootRegistry, puppetTreasury, protocolTreasury);
        escrow = new HoodPupOfferEscrow(
            admin,
            address(collection),
            address(oracle),
            address(nft),
            address(router),
            address(vault),
            address(rootRegistry),
            MIN_DURATION,
            MAX_DURATION
        );

        roleBtcSettlement = escrow.BTC_SETTLEMENT_ROLE();
        rolePauser = escrow.PAUSER_ROLE();
        roleDefaultAdmin = escrow.DEFAULT_ADMIN_ROLE();

        _wireRoles();

        vm.deal(buyer, 1000 ether);
        vm.deal(otherBuyer, 1000 ether);
        vm.deal(relayer, 10 ether);
    }

    /// @dev Deployment step that the real deploy script must reproduce. Everything here is a
    ///      post-deploy grant; every one of these contracts deliberately ships with the consumer
    ///      roles unassigned, so an omission shows up as a settlement that reverts, not as a
    ///      silent privilege.
    function _wireRoles() private {
        uint8[] memory escrowPurposes = new uint8[](3);
        escrowPurposes[0] = uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT);
        escrowPurposes[1] = uint8(PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT);
        escrowPurposes[2] = uint8(PuppetTypes.AuthorizationPurpose.SELF_CAST);

        uint8[] memory registryPurposes = new uint8[](2);
        registryPurposes[0] = uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND);
        registryPurposes[1] = uint8(PuppetTypes.AuthorizationPurpose.ROOT_INVALIDATE);

        vm.startPrank(admin);
        vault.grantRole(vault.CREDITOR_ROLE(), address(router));
        vault.grantRole(vault.CREDITOR_ROLE(), address(escrow));
        vault.grantRole(vault.ROOT_RELEASER_ROLE(), address(rootRegistry));
        nft.grantRole(nft.MINTER_ROLE(), address(escrow));
        rootRegistry.grantRole(rootRegistry.MINT_RECORDER_ROLE(), address(escrow));
        router.grantRole(router.ROUTER_CALLER_ROLE(), address(escrow));
        oracle.grantOwnershipConsumer(address(escrow), escrowPurposes);
        oracle.grantOwnershipConsumer(address(rootRegistry), registryPurposes);
        oracle.grantRole(oracle.ROOT_SPEND_CONSUMER_ROLE(), address(rootRegistry));
        escrow.grantRole(roleBtcSettlement, btcSettlement);
        escrow.grantRole(rolePauser, guardian);
        vm.stopPrank();
    }

    function _buildManifest() private {
        bytes32 sharedTxid = keccak256("FIXTURE-NOT-REAL:reveal-shared");
        roots.push(PuppetTypes.RootId({inscriptionTxid: sharedTxid, inscriptionIndex: 0}));
        roots.push(PuppetTypes.RootId({inscriptionTxid: sharedTxid, inscriptionIndex: 1}));
        roots.push(PuppetTypes.RootId({inscriptionTxid: keccak256("FIXTURE-NOT-REAL:reveal-c"), inscriptionIndex: 0}));
        roots.push(PuppetTypes.RootId({inscriptionTxid: keccak256("FIXTURE-NOT-REAL:reveal-d"), inscriptionIndex: 7}));
        roots.push(PuppetTypes.RootId({inscriptionTxid: keccak256("FIXTURE-NOT-REAL:reveal-e"), inscriptionIndex: 3}));
        outsiderRoot =
            PuppetTypes.RootId({inscriptionTxid: keccak256("FIXTURE-NOT-REAL:not-in-manifest"), inscriptionIndex: 0});

        PuppetTypes.RootId[] memory copy = new PuppetTypes.RootId[](roots.length);
        for (uint256 i = 0; i < roots.length; i++) {
            copy[i] = roots[i];
        }
        bytes32[] memory built = MerkleFixture.leavesOf(copy);
        for (uint256 i = 0; i < built.length; i++) {
            leaves.push(built[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FIXTURE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _proof(uint256 index) internal view returns (bytes32[] memory) {
        bytes32[] memory copy = new bytes32[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            copy[i] = leaves[i];
        }
        return MerkleFixture.proof(copy, index);
    }

    function _rootKey(uint256 index) internal view returns (bytes32) {
        return PuppetHashing.rootKey(roots[index].inscriptionTxid, roots[index].inscriptionIndex);
    }

    function _createEvm(address who, uint256 index, uint256 price, address to) internal returns (bytes32) {
        vm.prank(who);
        return
            escrow.createPaidEvmOffer{value: price}(roots[index], to, uint64(block.timestamp) + 1 days, _proof(index));
    }

    function _createEvm(uint256 index) internal returns (bytes32) {
        return _createEvm(buyer, index, PRICE, recipient);
    }

    function _createBtc(uint256 index, uint64 sats) internal returns (bytes32) {
        vm.prank(buyer);
        return escrow.createPaidBtcOffer{value: PRICE}(
            roots[index], recipient, sats, uint64(block.timestamp) + 1 days, _proof(index)
        );
    }

    function _createSelfCast(address who, uint256 index) internal returns (bytes32) {
        vm.prank(who);
        return escrow.createSelfCastOffer(roots[index], who, uint64(block.timestamp) + 1 days, _proof(index));
    }

    /*//////////////////////////////////////////////////////////////
                          ATTESTATION BUILDERS
    //////////////////////////////////////////////////////////////*/

    function _baseAttestation(bytes32 offerId) internal view returns (PuppetTypes.OwnershipAttestation memory a) {
        PuppetTypes.Offer memory o = escrow.getOffer(offerId);
        a = PuppetTypes.OwnershipAttestation({
            purpose: 0,
            rootTxid: o.rootTxid,
            rootIndex: o.rootIndex,
            contextId: offerId,
            offerTermsHash: o.termsHash,
            currentOutpointHash: OUTPOINT,
            ownerScriptHash: SCRIPT_HASH,
            bip322ProofHash: PROOF_HASH,
            buyer: o.buyer,
            recipient: o.recipient,
            payoutMode: 0,
            evmPayout: address(0),
            btcPayoutScriptHash: bytes32(0),
            sellerSats: o.sellerSats,
            grossWei: o.grossWei,
            sellerWei: o.sellerWei,
            bitcoinBlockHash: BTC_BLOCK,
            bitcoinHeight: BTC_HEIGHT,
            authorizationId: keccak256(abi.encode("authorization", offerId)),
            deadline: uint64(block.timestamp) + 1 hours,
            attestorEpoch: attestorRegistry.attestorEpoch(),
            policyVersion: attestorRegistry.policyVersion()
        });
    }

    function _evmAttestation(bytes32 offerId, address payout)
        internal
        view
        returns (PuppetTypes.OwnershipAttestation memory a)
    {
        a = _baseAttestation(offerId);
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.EVM);
        a.evmPayout = payout;
    }

    function _btcAttestation(bytes32 offerId) internal view returns (PuppetTypes.OwnershipAttestation memory a) {
        a = _baseAttestation(offerId);
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.BTC);
        a.btcPayoutScriptHash = BTC_PAYOUT_SCRIPT;
    }

    function _selfCastAttestation(bytes32 offerId) internal view returns (PuppetTypes.OwnershipAttestation memory a) {
        a = _baseAttestation(offerId);
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.SELF_CAST);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.NONE);
    }

    function _sign(PuppetTypes.OwnershipAttestation memory a) internal view returns (bytes[] memory) {
        return attestors.sign(oracle.hashOwnershipAttestation(a), 3);
    }

    function _signN(PuppetTypes.OwnershipAttestation memory a, uint256 n) internal view returns (bytes[] memory) {
        return attestors.sign(oracle.hashOwnershipAttestation(a), n);
    }

    /*//////////////////////////////////////////////////////////////
                            COMPOSITE FLOWS
    //////////////////////////////////////////////////////////////*/

    function _settleEvm(bytes32 offerId, uint256 rootIndex) internal returns (uint256 tokenId) {
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(rootIndex);
        vm.prank(relayer);
        return escrow.settlePaidEvm(offerId, a, sigs, p);
    }

    function _approveBtc(bytes32 offerId, uint256 rootIndex) internal {
        PuppetTypes.OwnershipAttestation memory a = _btcAttestation(offerId);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(rootIndex);
        vm.prank(relayer);
        escrow.approvePaidBtc(offerId, a, sigs, p);
    }

    function _reserve(bytes32 offerId, uint64 window) internal {
        vm.prank(btcSettlement);
        escrow.markBtcReserved(offerId, solver, uint64(block.timestamp) + window);
    }

    function _status(bytes32 offerId) internal view returns (uint8) {
        return escrow.getOffer(offerId).status;
    }

    /// @dev First four bytes of revert data, as an error selector.
    function _selectorOf(bytes memory data) internal pure returns (bytes4 sel) {
        require(data.length >= 4, "no selector");
        sel = bytes4(bytes.concat(data[0], data[1], data[2], data[3]));
    }

    /// @dev Scan runtime bytecode for a 4-byte selector. Used only with a positive control, so a
    ///      scan that finds nothing at all cannot be mistaken for a passing security claim.
    function _hasSelector(bytes memory code, bytes4 sel) internal pure returns (bool) {
        for (uint256 i = 0; i + 4 <= code.length; i++) {
            if (code[i] == sel[0] && code[i + 1] == sel[1] && code[i + 2] == sel[2] && code[i + 3] == sel[3]) {
                return true;
            }
        }
        return false;
    }
}

/*//////////////////////////////////////////////////////////////
                            THE SUITE
//////////////////////////////////////////////////////////////*/

contract HoodPupOfferEscrowTest is EscrowFixture {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    function test_ConstructorStoresImmutableWiring() public view {
        assertEq(address(escrow.collectionRegistry()), address(collection), "collection");
        assertEq(address(escrow.ownershipOracle()), address(oracle), "oracle");
        assertEq(address(escrow.hoodPups()), address(nft), "nft");
        assertEq(address(escrow.feeRouter()), address(router), "router");
        assertEq(address(escrow.payoutVault()), address(vault), "vault");
        assertEq(address(escrow.rootOwnershipRegistry()), address(rootRegistry), "rootRegistry");
        assertEq(escrow.minimumOfferDuration(), MIN_DURATION, "min");
        assertEq(escrow.maximumOfferDuration(), MAX_DURATION, "max");
        assertEq(escrow.lockedEscrowWei(), 0, "locked starts empty");
        assertEq(escrow.MAX_RESERVATION_WINDOW(), 24 hours, "reservation ceiling");
    }

    function test_ConstructorGrantsOnlyGovernanceRoles() public view {
        assertTrue(escrow.hasRole(roleDefaultAdmin, admin), "admin");
        assertTrue(escrow.hasRole(rolePauser, admin), "pauser");
        // BTC_SETTLEMENT_ROLE is never granted at construction; the fixture grants it explicitly
        // afterwards, which is exactly what the deployment batch must do.
        assertFalse(escrow.hasRole(roleBtcSettlement, admin), "settlement role not pre-granted to admin");
        assertFalse(escrow.hasRole(roleDefaultAdmin, address(this)), "deployer holds nothing");
        assertFalse(escrow.hasRole(rolePauser, address(this)), "deployer holds nothing");
    }

    function test_ConstructorRejectsEveryZeroAddress() public {
        address[7] memory args = [
            admin,
            address(collection),
            address(oracle),
            address(nft),
            address(router),
            address(vault),
            address(rootRegistry)
        ];
        for (uint256 slot = 0; slot < 7; slot++) {
            address[7] memory a = args;
            a[slot] = address(0);
            vm.expectRevert(IHoodPupOfferEscrow.ZeroAddress.selector);
            new HoodPupOfferEscrow(a[0], a[1], a[2], a[3], a[4], a[5], a[6], MIN_DURATION, MAX_DURATION);
        }
    }

    function test_ConstructorRejectsInvalidDurationBounds() public {
        vm.expectRevert(
            abi.encodeWithSelector(IHoodPupOfferEscrow.DurationBoundsInvalid.selector, uint64(0), MAX_DURATION)
        );
        new HoodPupOfferEscrow(
            admin,
            address(collection),
            address(oracle),
            address(nft),
            address(router),
            address(vault),
            address(rootRegistry),
            0,
            MAX_DURATION
        );

        vm.expectRevert(
            abi.encodeWithSelector(IHoodPupOfferEscrow.DurationBoundsInvalid.selector, uint64(2 days), uint64(1 days))
        );
        new HoodPupOfferEscrow(
            admin,
            address(collection),
            address(oracle),
            address(nft),
            address(router),
            address(vault),
            address(rootRegistry),
            2 days,
            1 days
        );
    }

    function test_ConstructorEmitsEscrowInitialized() public {
        vm.recordLogs();
        HoodPupOfferEscrow fresh = new HoodPupOfferEscrow(
            admin,
            address(collection),
            address(oracle),
            address(nft),
            address(router),
            address(vault),
            address(rootRegistry),
            MIN_DURATION,
            MAX_DURATION
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == HoodPupOfferEscrow.EscrowInitialized.selector) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), admin, "admin in event");
            }
        }
        assertTrue(found, "EscrowInitialized emitted");
        assertEq(fresh.lockedEscrowWei(), 0, "fresh escrow empty");
    }

    function test_SupportsInterface() public view {
        assertTrue(escrow.supportsInterface(type(IHoodPupOfferEscrow).interfaceId), "own interface");
        assertTrue(escrow.supportsInterface(type(IAccessControl).interfaceId), "access control");
        assertFalse(escrow.supportsInterface(bytes4(0xdeadbeef)), "unknown");
    }

    /*//////////////////////////////////////////////////////////////
                             OFFER CREATION
    //////////////////////////////////////////////////////////////*/

    function test_CreatePaidEvmOfferStoresExactTerms() public {
        bytes32 expectedId = escrow.nextOfferId(buyer);
        bytes32 offerId = _createEvm(0);
        assertEq(offerId, expectedId, "id matches nextOfferId");

        PuppetTypes.Offer memory o = escrow.getOffer(offerId);
        assertEq(o.buyer, buyer, "buyer");
        assertEq(o.recipient, recipient, "recipient");
        assertEq(o.rootKey, _rootKey(0), "rootKey");
        assertEq(o.rootTxid, roots[0].inscriptionTxid, "txid");
        assertEq(o.rootIndex, roots[0].inscriptionIndex, "index");
        assertEq(o.grossWei, PRICE, "gross");
        assertEq(o.sellerWei, PRICE / 2, "seller 50%");
        assertEq(o.treasuryWei, PRICE / 4, "puppet treasury 25%");
        assertEq(o.protocolWei, PRICE - PRICE / 2 - PRICE / 4, "protocol remainder");
        assertEq(o.sellerWei + o.treasuryWei + o.protocolWei, o.grossWei, "split conserves gross");
        assertEq(o.sellerSats, 0, "no sats on an EVM offer");
        assertEq(o.kind, uint8(PuppetTypes.OfferKind.PAID_EVM), "kind");
        assertEq(o.status, uint8(PuppetTypes.OfferStatus.OPEN), "OPEN");
        assertEq(o.createdAt, uint64(block.timestamp), "createdAt");
        assertEq(o.ownershipDigest, bytes32(0), "no digest yet");
        assertEq(o.reservedSolver, address(0), "no solver yet");

        assertEq(address(escrow).balance, PRICE, "escrow holds the ETH");
        assertEq(escrow.lockedEscrowWei(), PRICE, "locked accounting");
        assertEq(escrow.buyerNonce(buyer), 1, "nonce advanced");
    }

    function test_CreatePaidEvmOfferEmitsOfferCreated() public {
        bytes32 offerId = escrow.nextOfferId(buyer);
        bytes32 key = _rootKey(2);
        uint64 expiry = uint64(block.timestamp) + 1 days;
        bytes32 terms = escrow.computeTermsHash(
            offerId, uint8(PuppetTypes.OfferKind.PAID_EVM), key, buyer, recipient, PRICE, PRICE / 2, 0, expiry
        );

        vm.expectEmit(true, true, true, true, address(escrow));
        emit IHoodPupOfferEscrow.OfferCreated(
            offerId, key, buyer, recipient, uint8(PuppetTypes.OfferKind.PAID_EVM), PRICE, PRICE / 2, 0, expiry, terms
        );
        vm.prank(buyer);
        escrow.createPaidEvmOffer{value: PRICE}(roots[2], recipient, expiry, _proof(2));
    }

    function test_CreatePaidBtcOfferStoresSats() public {
        bytes32 offerId = _createBtc(1, 50_000);
        PuppetTypes.Offer memory o = escrow.getOffer(offerId);
        assertEq(o.kind, uint8(PuppetTypes.OfferKind.PAID_BTC), "kind");
        assertEq(o.sellerSats, 50_000, "sats");
        assertEq(o.grossWei, PRICE, "gross");
        assertEq(o.sellerWei, PRICE / 2, "seller share still 50%");
    }

    function test_CreateSelfCastOfferHoldsNoMoney() public {
        bytes32 offerId = _createSelfCast(buyer, 3);
        PuppetTypes.Offer memory o = escrow.getOffer(offerId);
        assertEq(o.kind, uint8(PuppetTypes.OfferKind.SELF_CAST), "kind");
        assertEq(o.grossWei, 0, "no gross");
        assertEq(o.sellerWei, 0, "no seller share");
        assertEq(o.treasuryWei, 0, "no treasury share");
        assertEq(o.protocolWei, 0, "no protocol share");
        assertEq(o.buyer, buyer, "buyer is the self-caster");
        assertEq(o.recipient, buyer, "recipient is the self-caster");
        assertEq(address(escrow).balance, 0, "escrow holds nothing");
        assertEq(escrow.lockedEscrowWei(), 0, "locked unchanged");
    }

    function test_CreateRejectsNonMemberRoot() public {
        bytes32 key = PuppetHashing.rootKey(outsiderRoot.inscriptionTxid, outsiderRoot.inscriptionIndex);
        bytes32[] memory borrowed = _proof(0);
        vm.expectRevert(abi.encodeWithSelector(IPuppetCollectionRegistry.NotCollectionMember.selector, key));
        vm.prank(buyer);
        escrow.createPaidEvmOffer{value: PRICE}(outsiderRoot, recipient, uint64(block.timestamp) + 1 days, borrowed);
    }

    function test_CreateRejectsSiblingProof() public {
        // Members 0 and 1 share a reveal txid and differ only by inscription index, so one's proof
        // must never verify the other.
        bytes32[] memory wrongProof = _proof(0);
        bytes32 key = _rootKey(1);
        vm.expectRevert(abi.encodeWithSelector(IPuppetCollectionRegistry.NotCollectionMember.selector, key));
        vm.prank(buyer);
        escrow.createPaidEvmOffer{value: PRICE}(roots[1], recipient, uint64(block.timestamp) + 1 days, wrongProof);
    }

    function test_CreateRejectsZeroRecipient() public {
        bytes32[] memory p = _proof(0);
        vm.expectRevert(IHoodPupOfferEscrow.ZeroAddress.selector);
        vm.prank(buyer);
        escrow.createPaidEvmOffer{value: PRICE}(roots[0], address(0), uint64(block.timestamp) + 1 days, p);
    }

    function test_CreateRejectsZeroRootTxid() public {
        PuppetTypes.RootId memory empty = PuppetTypes.RootId({inscriptionTxid: bytes32(0), inscriptionIndex: 0});
        bytes32[] memory p = _proof(0);
        vm.expectRevert(HoodPupOfferEscrow.ZeroRootTxid.selector);
        vm.prank(buyer);
        escrow.createPaidEvmOffer{value: PRICE}(empty, recipient, uint64(block.timestamp) + 1 days, p);
    }

    function test_CreateRejectsExpiryOutsideWindow() public {
        uint64 minAllowed = uint64(block.timestamp) + MIN_DURATION;
        uint64 maxAllowed = uint64(block.timestamp) + MAX_DURATION;
        bytes32[] memory p = _proof(0);

        vm.expectRevert(
            abi.encodeWithSelector(IHoodPupOfferEscrow.InvalidExpiry.selector, minAllowed - 1, minAllowed, maxAllowed)
        );
        vm.prank(buyer);
        escrow.createPaidEvmOffer{value: PRICE}(roots[0], recipient, minAllowed - 1, p);

        bytes32[] memory p2 = _proof(0);
        vm.expectRevert(
            abi.encodeWithSelector(IHoodPupOfferEscrow.InvalidExpiry.selector, maxAllowed + 1, minAllowed, maxAllowed)
        );
        vm.prank(buyer);
        escrow.createPaidEvmOffer{value: PRICE}(roots[0], recipient, maxAllowed + 1, p2);
    }

    function test_CreateAcceptsBothExpiryBoundariesExactly() public {
        uint64 minAllowed = uint64(block.timestamp) + MIN_DURATION;
        uint64 maxAllowed = uint64(block.timestamp) + MAX_DURATION;

        vm.prank(buyer);
        bytes32 a = escrow.createPaidEvmOffer{value: PRICE}(roots[0], recipient, minAllowed, _proof(0));
        vm.prank(buyer);
        bytes32 b = escrow.createPaidEvmOffer{value: PRICE}(roots[1], recipient, maxAllowed, _proof(1));

        assertEq(escrow.getOffer(a).expiry, minAllowed, "min boundary accepted");
        assertEq(escrow.getOffer(b).expiry, maxAllowed, "max boundary accepted");
    }

    function test_CreateRejectsZeroValueOnPaidOffers() public {
        bytes32[] memory p = _proof(0);
        vm.expectRevert(IHoodPupOfferEscrow.PaidOfferRequiresValue.selector);
        vm.prank(buyer);
        escrow.createPaidEvmOffer{value: 0}(roots[0], recipient, uint64(block.timestamp) + 1 days, p);

        bytes32[] memory p2 = _proof(0);
        vm.expectRevert(IHoodPupOfferEscrow.PaidOfferRequiresValue.selector);
        vm.prank(buyer);
        escrow.createPaidBtcOffer{value: 0}(roots[0], recipient, 1000, uint64(block.timestamp) + 1 days, p2);
    }

    function test_CreateBtcRejectsZeroSats() public {
        bytes32[] memory p = _proof(0);
        vm.expectRevert(IHoodPupOfferEscrow.BtcOfferRequiresSats.selector);
        vm.prank(buyer);
        escrow.createPaidBtcOffer{value: PRICE}(roots[0], recipient, 0, uint64(block.timestamp) + 1 days, p);
    }

    function test_CreateSelfCastRequiresCallerIsRecipient() public {
        bytes32[] memory p = _proof(0);
        vm.expectRevert(
            abi.encodeWithSelector(IHoodPupOfferEscrow.SelfCastRecipientMismatch.selector, buyer, recipient)
        );
        vm.prank(buyer);
        escrow.createSelfCastOffer(roots[0], recipient, uint64(block.timestamp) + 1 days, p);
    }

    function test_CreateRejectsAlreadyMintedRoot() public {
        bytes32 first = _createEvm(0);
        _settleEvm(first, 0);

        bytes32[] memory p = _proof(0);
        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.RootAlreadyMinted.selector, _rootKey(0)));
        vm.prank(otherBuyer);
        escrow.createPaidEvmOffer{value: PRICE}(roots[0], recipient, uint64(block.timestamp) + 1 days, p);
    }

    function test_OfferIdsAreUniquePerBuyerAndDeterministic() public {
        bytes32 a = _createEvm(buyer, 0, PRICE, recipient);
        bytes32 b = _createEvm(buyer, 1, PRICE, recipient);
        bytes32 c = _createEvm(otherBuyer, 2, PRICE, recipient);
        assertTrue(a != b && b != c && a != c, "ids distinct");

        assertEq(a, PuppetHashing.offerId(block.chainid, address(escrow), buyer, 0), "id 0 reproducible off chain");
        assertEq(b, PuppetHashing.offerId(block.chainid, address(escrow), buyer, 1), "id 1 reproducible off chain");
        assertEq(c, PuppetHashing.offerId(block.chainid, address(escrow), otherBuyer, 0), "other buyer starts at 0");
        assertEq(escrow.nextOfferId(buyer), PuppetHashing.offerId(block.chainid, address(escrow), buyer, 2), "next");
    }

    function test_ComputeTermsHashMatchesPuppetHashing() public view {
        bytes32 id = keccak256("some-offer");
        bytes32 key = _rootKey(0);
        assertEq(
            escrow.computeTermsHash(id, 1, key, buyer, recipient, 3 ether, 1.5 ether, 42, 999),
            PuppetHashing.offerTermsHash(
                block.chainid, address(escrow), id, 1, key, buyer, recipient, 3 ether, 1.5 ether, 42, 999
            ),
            "terms hash reproducible by the SDK and the attestors"
        );
    }

    function test_StoredTermsHashCoversTheStoredOffer() public {
        bytes32 offerId = _createBtc(1, 77_000);
        PuppetTypes.Offer memory o = escrow.getOffer(offerId);
        assertEq(
            o.termsHash,
            escrow.computeTermsHash(
                offerId, o.kind, o.rootKey, o.buyer, o.recipient, o.grossWei, o.sellerWei, o.sellerSats, o.expiry
            ),
            "stored terms hash is over the stored terms"
        );
    }

    function test_CompetingOffersForOneRootAreAllowed() public {
        bytes32 a = _createEvm(buyer, 0, 1 ether, recipient);
        bytes32 b = _createEvm(otherBuyer, 0, 5 ether, recipient);
        assertTrue(a != b, "two live offers");
        assertEq(_status(a), uint8(PuppetTypes.OfferStatus.OPEN), "a open");
        assertEq(_status(b), uint8(PuppetTypes.OfferStatus.OPEN), "b open");
        assertEq(escrow.lockedEscrowWei(), 6 ether, "both escrows locked");
    }

    function test_ThereIsNoCancelFunction() public view {
        bytes memory code = address(escrow).code;
        // A buyer-cancellable offer would let a buyer bait a cold-wallet signature and withdraw.
        assertFalse(_hasSelector(code, bytes4(keccak256("cancelOffer(bytes32)"))), "cancelOffer");
        assertFalse(_hasSelector(code, bytes4(keccak256("withdrawOffer(bytes32)"))), "withdrawOffer");
        assertFalse(_hasSelector(code, bytes4(keccak256("cancel(bytes32)"))), "cancel");
        // Positive control: the scan does find a function that genuinely exists.
        assertTrue(_hasSelector(code, IHoodPupOfferEscrow.refundExpired.selector), "positive control");
    }

    /*//////////////////////////////////////////////////////////////
                            EVM SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    function test_SettlePaidEvmFullPath() public {
        bytes32 offerId = _createEvm(0);
        uint256 tokenId = _settleEvm(offerId, 0);

        PuppetTypes.Offer memory o = escrow.getOffer(offerId);
        assertEq(o.status, uint8(PuppetTypes.OfferStatus.SETTLED), "SETTLED");
        assertTrue(o.ownershipDigest != bytes32(0), "digest recorded");

        // The HoodPup exists and belongs to the recipient the buyer named.
        assertEq(nft.ownerOf(tokenId), recipient, "recipient owns the HoodPup");
        assertEq(nft.tokenOfRoot(_rootKey(0)), tokenId, "root maps to the token");
        assertTrue(nft.rootMinted(_rootKey(0)), "root minted");

        // The money landed as 50 / 25 / 25 inside the vault, not as a push transfer.
        assertEq(vault.claimable(sellerPayout), PRICE / 2, "seller 50%");
        assertEq(vault.claimable(puppetTreasury), PRICE / 4, "puppet treasury 25%");
        assertEq(vault.claimable(protocolTreasury), PRICE - PRICE / 2 - PRICE / 4, "protocol 25%");
        assertEq(vault.totalLiability(), PRICE, "every wei accounted for");
        assertEq(address(vault).balance, PRICE, "vault holds it");

        // The escrow kept nothing.
        assertEq(address(escrow).balance, 0, "escrow drained");
        assertEq(escrow.lockedEscrowWei(), 0, "locked accounting cleared");

        // The Root's first ownership epoch names the address the Bitcoin holder signed.
        (address beneficiary, bool active, uint64 epoch) = rootRegistry.currentBeneficiary(_rootKey(0));
        assertEq(beneficiary, sellerPayout, "beneficiary is the signed payout address");
        assertTrue(active, "epoch active");
        assertEq(epoch, 1, "first epoch");
        PuppetTypes.RootState memory s = rootRegistry.currentState(_rootKey(0));
        assertEq(s.currentOutpointHash, OUTPOINT, "attested outpoint recorded");
        assertEq(s.ownerScriptHash, SCRIPT_HASH, "attested script recorded");
        assertEq(s.ownershipDigest, o.ownershipDigest, "same digest the escrow consumed");
        assertEq(s.verifiedBitcoinHeight, BTC_HEIGHT, "attested height recorded");
    }

    function test_SettlePaidEvmEmitsSettlementEvents() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit IHoodPupOfferEscrow.OwnershipApproved(offerId, digest, a.purpose, sellerPayout);
        vm.expectEmit(true, true, true, true, address(escrow));
        emit IHoodPupOfferEscrow.OfferSettled(
            offerId, _rootKey(0), 1, recipient, sellerPayout, PRICE, uint8(PuppetTypes.OfferKind.PAID_EVM)
        );
        vm.prank(relayer);
        escrow.settlePaidEvm(offerId, a, sigs, p);
    }

    function test_SettlementPaysTheSignedAddressNotTheBuyerOrRecipient() public {
        address rogue = makeAddr("rogueAddress");
        bytes32 offerId = _createEvm(0);
        _settleEvm(offerId, 0);

        assertEq(vault.claimable(sellerPayout), PRICE / 2, "signed payout paid");
        assertEq(vault.claimable(buyer), 0, "buyer paid nothing");
        assertEq(vault.claimable(recipient), 0, "recipient paid nothing");
        assertEq(vault.claimable(relayer), 0, "submitter paid nothing");
        assertEq(vault.claimable(rogue), 0, "nobody else paid");
    }

    function test_SettlementIsPermissionless() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        address stranger = makeAddr("randomStranger");

        vm.prank(stranger);
        uint256 tokenId = escrow.settlePaidEvm(offerId, a, sigs, p);
        assertEq(nft.ownerOf(tokenId), recipient, "a stranger's submission still mints to the named recipient");
    }

    function test_SettleTwiceReverts() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        vm.prank(relayer);
        escrow.settlePaidEvm(offerId, a, sigs, p);

        vm.expectRevert(
            abi.encodeWithSelector(
                IHoodPupOfferEscrow.InvalidOfferStatus.selector,
                offerId,
                uint8(PuppetTypes.OfferStatus.SETTLED),
                uint8(PuppetTypes.OfferStatus.OPEN)
            )
        );
        vm.prank(relayer);
        escrow.settlePaidEvm(offerId, a, sigs, p);
    }

    function test_SettleUnknownOfferReverts() public {
        bytes32 ghost = keccak256("never-created");
        PuppetTypes.OwnershipAttestation memory a = _baseAttestation(ghost);
        bytes[] memory sigs = new bytes[](0);
        bytes32[] memory p = _proof(0);
        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.UnknownOffer.selector, ghost));
        escrow.settlePaidEvm(ghost, a, sigs, p);
    }

    function test_SettlePaidEvmRejectsWrongOfferKind() public {
        bytes32 offerId = _createBtc(0, 50_000);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                HoodPupOfferEscrow.UnexpectedOfferKind.selector,
                offerId,
                uint8(PuppetTypes.OfferKind.PAID_BTC),
                uint8(PuppetTypes.OfferKind.PAID_EVM)
            )
        );
        escrow.settlePaidEvm(offerId, a, sigs, p);
    }

    function test_SettleSelfCastRejectsWrongOfferKind() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _selfCastAttestation(offerId);
        a.grossWei = 0;
        a.sellerWei = 0;
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                HoodPupOfferEscrow.UnexpectedOfferKind.selector,
                offerId,
                uint8(PuppetTypes.OfferKind.PAID_EVM),
                uint8(PuppetTypes.OfferKind.SELF_CAST)
            )
        );
        escrow.settleSelfCast(offerId, a, sigs, p);
    }

    function test_SettleRejectsWrongPurpose() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHoodPupOfferEscrow.UnexpectedPurpose.selector,
                uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND),
                uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT)
            )
        );
        escrow.settlePaidEvm(offerId, a, sigs, p);
    }

    /*//////////////////////////////////////////////////////////////
                     ONE MUTATED FIELD AT A TIME
    //////////////////////////////////////////////////////////////*/

    /// @dev The core "the terms I saw are the terms that execute" table. Each case changes exactly
    ///      ONE attested field, re-signs a genuine 3-of-5 quorum over the mutated struct — so the
    ///      quorum itself is never the reason the call fails — and asserts the specific named
    ///      mismatch. A single shared helper would be tempting here, but the assertions differ per
    ///      field and an incorrect one would silently pass, so each case is written out.
    function _mutatedEvmSettleReverts(PuppetTypes.OwnershipAttestation memory a, bytes32 offerId, string memory field)
        private
    {
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.AttestationFieldMismatch.selector, field));
        escrow.settlePaidEvm(offerId, a, sigs, p);
    }

    function test_MutatedContextIdRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        a.contextId = keccak256("another-offer");
        _mutatedEvmSettleReverts(a, offerId, "contextId");
    }

    function test_MutatedTermsHashRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        a.offerTermsHash = keccak256("different-terms");
        _mutatedEvmSettleReverts(a, offerId, "offerTermsHash");
    }

    function test_MutatedRootTxidRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        a.rootTxid = roots[2].inscriptionTxid;
        _mutatedEvmSettleReverts(a, offerId, "rootTxid");
    }

    function test_MutatedRootIndexRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        // The sibling inscription: same reveal txid, different index. It is a real manifest member,
        // which is exactly why the index must be checked independently of the txid.
        a.rootIndex = 1;
        _mutatedEvmSettleReverts(a, offerId, "rootIndex");
    }

    function test_MutatedBuyerRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        a.buyer = otherBuyer;
        _mutatedEvmSettleReverts(a, offerId, "buyer");
    }

    function test_MutatedRecipientRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        a.recipient = makeAddr("attackerRecipient");
        _mutatedEvmSettleReverts(a, offerId, "recipient");
    }

    function test_MutatedGrossWeiRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        a.grossWei = PRICE + 1;
        _mutatedEvmSettleReverts(a, offerId, "grossWei");
    }

    function test_MutatedSellerWeiRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        // A seller share above the stored 50% is the exact shape of a fee-split bypass attempt.
        a.sellerWei = PRICE;
        _mutatedEvmSettleReverts(a, offerId, "sellerWei");
    }

    function test_MutatedSellerSatsRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        a.sellerSats = 1;
        _mutatedEvmSettleReverts(a, offerId, "sellerSats");
    }

    function test_MutatedPayoutModeRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.BTC);
        _mutatedEvmSettleReverts(a, offerId, "payoutMode");
    }

    function test_ZeroEvmPayoutRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, address(0));
        _mutatedEvmSettleReverts(a, offerId, "evmPayout");
    }

    function test_EvmSettlementRejectsStrayBtcScriptHash() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        a.btcPayoutScriptHash = BTC_PAYOUT_SCRIPT;
        _mutatedEvmSettleReverts(a, offerId, "btcPayoutScriptHash");
    }

    function test_ZeroOutpointRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        a.currentOutpointHash = bytes32(0);
        _mutatedEvmSettleReverts(a, offerId, "currentOutpointHash");
    }

    function test_ZeroOwnerScriptHashRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        a.ownerScriptHash = bytes32(0);
        _mutatedEvmSettleReverts(a, offerId, "ownerScriptHash");
    }

    function test_AnAttestationForOneOfferCannotSettleAnother() public {
        bytes32 first = _createEvm(buyer, 0, PRICE, recipient);
        bytes32 second = _createEvm(otherBuyer, 1, PRICE, recipient);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(first, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(1);
        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.AttestationFieldMismatch.selector, "contextId"));
        escrow.settlePaidEvm(second, a, sigs, p);
    }

    /*//////////////////////////////////////////////////////////////
                       QUORUM AND EXPIRY BOUNDARIES
    //////////////////////////////////////////////////////////////*/

    function test_SubThresholdQuorumRejected() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _signN(a, 2);
        bytes32[] memory p = _proof(0);
        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.InsufficientSignatures.selector, 2, 3));
        escrow.settlePaidEvm(offerId, a, sigs, p);
    }

    function test_SettlementIsLiveThroughTheExpirySecondAndDeadAfterIt() public {
        bytes32 offerId = _createEvm(0);
        uint64 expiry = escrow.getOffer(offerId).expiry;

        // One second before expiry, and exactly at expiry, settlement is legal. The attestation is
        // rebuilt after each warp because its own deadline is relative to the current timestamp.
        vm.warp(expiry - 1);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        uint256 snapshot = vm.snapshotState();
        escrow.settlePaidEvm(offerId, a, sigs, p);
        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.SETTLED), "settles one second early");
        vm.revertToState(snapshot);

        vm.warp(expiry);
        PuppetTypes.OwnershipAttestation memory b = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigsB = _sign(b);
        bytes32[] memory pB = _proof(0);
        uint256 snapshot2 = vm.snapshotState();
        escrow.settlePaidEvm(offerId, b, sigsB, pB);
        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.SETTLED), "settles exactly at expiry");
        vm.revertToState(snapshot2);

        vm.warp(uint256(expiry) + 1);
        PuppetTypes.OwnershipAttestation memory c = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigsC = _sign(c);
        bytes32[] memory pC = _proof(0);
        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.OfferExpired.selector, offerId, expiry));
        escrow.settlePaidEvm(offerId, c, sigsC, pC);
    }

    function test_RefundOpensExactlyWhereSettlementCloses() public {
        bytes32 offerId = _createEvm(0);
        uint64 expiry = escrow.getOffer(offerId).expiry;

        vm.warp(expiry);
        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.OfferNotExpired.selector, offerId, expiry));
        escrow.refundExpired(offerId);

        vm.warp(uint256(expiry) + 1);
        escrow.refundExpired(offerId);
        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.REFUNDED), "refundable one second later");
    }

    function test_SettleRevertsOnceACompetitorMintedTheRoot() public {
        bytes32 winner = _createEvm(buyer, 0, PRICE, recipient);
        bytes32 loser = _createEvm(otherBuyer, 0, 2 ether, recipient);

        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(loser, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);

        _settleEvm(winner, 0);

        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.RootAlreadyMinted.selector, _rootKey(0)));
        escrow.settlePaidEvm(loser, a, sigs, p);
    }

    /*//////////////////////////////////////////////////////////////
                          ATOMIC FAILURE PATHS
    //////////////////////////////////////////////////////////////*/

    function test_AtomicRollbackWhenTheMintRecipientRejectsTheToken() public {
        MockERC721Receiver hostile = new MockERC721Receiver(MockERC721Receiver.Behaviour.REVERT_ON_RECEIVE);
        bytes32 offerId = _createEvm(buyer, 0, PRICE, address(hostile));
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);

        vm.expectRevert(MockERC721Receiver.ReceiverRejected.selector);
        escrow.settlePaidEvm(offerId, a, sigs, p);

        // Everything rolled back together: the offer is still open and still refundable, no money
        // moved, and crucially the quorum's authorization was NOT burned.
        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.OPEN), "still OPEN");
        assertEq(address(escrow).balance, PRICE, "escrow still holds the ETH");
        assertEq(escrow.lockedEscrowWei(), PRICE, "locked accounting intact");
        assertEq(vault.totalLiability(), 0, "nothing credited");
        assertFalse(oracle.isDigestConsumed(digest), "authorization not burned");
        assertFalse(nft.rootMinted(_rootKey(0)), "no mint");
        assertEq(rootRegistry.epochOf(_rootKey(0)), 0, "no ownership epoch");
    }

    function test_AtomicRollbackWhenRoutingIsNotAuthorized() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        bytes32 routerCaller = router.ROUTER_CALLER_ROLE();

        vm.prank(admin);
        router.revokeRole(routerCaller, address(escrow));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(escrow), routerCaller
            )
        );
        escrow.settlePaidEvm(offerId, a, sigs, p);

        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.OPEN), "still OPEN");
        assertEq(address(escrow).balance, PRICE, "escrow intact");
        assertFalse(oracle.isDigestConsumed(digest), "authorization not burned");
        assertEq(rootRegistry.epochOf(_rootKey(0)), 0, "the earlier registry write rolled back too");
    }

    function test_AtomicRollbackWhenOwnershipRecordingIsNotAuthorized() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        bytes32 recorder = rootRegistry.MINT_RECORDER_ROLE();

        vm.prank(admin);
        rootRegistry.revokeRole(recorder, address(escrow));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(escrow), recorder)
        );
        escrow.settlePaidEvm(offerId, a, sigs, p);

        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.OPEN), "still OPEN");
        assertEq(vault.totalLiability(), 0, "nothing credited");
        assertFalse(nft.rootMinted(_rootKey(0)), "no mint");
    }

    function test_AtomicRollbackWhenMintingIsNotAuthorized() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        bytes32 minter = nft.MINTER_ROLE();

        vm.prank(admin);
        nft.revokeRole(minter, address(escrow));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(escrow), minter)
        );
        escrow.settlePaidEvm(offerId, a, sigs, p);

        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.OPEN), "still OPEN");
        assertEq(vault.totalLiability(), 0, "the routing rolled back with the mint");
        assertEq(rootRegistry.epochOf(_rootKey(0)), 0, "the registry write rolled back too");
        assertEq(address(escrow).balance, PRICE, "escrow intact");
    }

    function test_ReplayingAConsumedAuthorizationIsImpossible() public {
        // Two competing offers deliberately given the SAME attested facts is impossible by
        // construction (contextId differs), so the honest replay to test is the same attestation
        // re-submitted after a refund.
        bytes32 offerId = _createEvm(0);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);

        escrow.settlePaidEvm(offerId, a, sigs, p);
        assertTrue(oracle.isDigestConsumed(digest), "consumed exactly once");

        vm.expectRevert(abi.encodeWithSelector(IBitcoinOwnershipOracle.DigestAlreadyConsumed.selector, digest));
        oracle.verifyOwnership(a, sigs, p);
    }

    /*//////////////////////////////////////////////////////////////
                              REENTRANCY
    //////////////////////////////////////////////////////////////*/

    function test_ReentrantSettlementFromTheMintCallbackIsBlocked() public {
        ReenteringMintRecipient probe = new ReenteringMintRecipient(address(escrow));
        bytes32 offerId = _createEvm(buyer, 0, PRICE, address(probe));

        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        probe.configure(abi.encodeCall(IHoodPupOfferEscrow.settlePaidEvm, (offerId, a, sigs, p)));

        escrow.settlePaidEvm(offerId, a, sigs, p);

        assertEq(probe.attempts(), 1, "the callback really fired");
        assertEq(probe.succeeded(), 0, "and the reentrant settlement was rejected");
        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.SETTLED), "settled exactly once");
        assertEq(vault.totalLiability(), PRICE, "the split was applied exactly once");
    }

    function test_ReentrantRefundFromTheMintCallbackIsBlocked() public {
        ReenteringMintRecipient probe = new ReenteringMintRecipient(address(escrow));
        bytes32 offerId = _createEvm(buyer, 0, PRICE, address(probe));

        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        probe.configure(abi.encodeCall(IHoodPupOfferEscrow.refundUnfillable, (offerId)));

        escrow.settlePaidEvm(offerId, a, sigs, p);

        assertEq(probe.attempts(), 1, "the callback really fired");
        assertEq(probe.succeeded(), 0, "a settled offer cannot be refunded from inside its own mint");
        assertEq(vault.claimable(buyer), 0, "buyer got no refund");
        assertEq(address(escrow).balance, 0, "escrow paid out exactly once");
    }

    function test_ReentrantOfferCreationFromTheMintCallbackIsBlocked() public {
        ReenteringMintRecipient probe = new ReenteringMintRecipient(address(escrow));
        bytes32 offerId = _createEvm(buyer, 0, PRICE, address(probe));

        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        probe.configure(
            abi.encodeCall(
                IHoodPupOfferEscrow.createPaidEvmOffer, (roots[1], address(probe), uint64(block.timestamp) + 1 days, p)
            )
        );

        escrow.settlePaidEvm(offerId, a, sigs, p);

        assertEq(probe.attempts(), 1, "the callback really fired");
        assertEq(probe.succeeded(), 0, "creation is inside the same guard");
    }

    /*//////////////////////////////////////////////////////////////
                          SELF-CAST SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    function test_SettleSelfCastMintsAndMovesNoMoney() public {
        address holder = makeAddr("bitcoinHolder");
        bytes32 offerId = _createSelfCast(holder, 2);
        PuppetTypes.OwnershipAttestation memory a = _selfCastAttestation(offerId);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(2);

        vm.prank(relayer);
        uint256 tokenId = escrow.settleSelfCast(offerId, a, sigs, p);

        assertEq(nft.ownerOf(tokenId), holder, "holder owns it");
        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.SETTLED), "SETTLED");
        assertEq(vault.totalLiability(), 0, "no money anywhere");
        assertEq(address(escrow).balance, 0, "escrow empty");
        assertEq(address(router).balance, 0, "router untouched");
    }

    /// @dev DOCUMENTED MODEL. A self-cast attestation carries `PayoutMode.NONE`, so there is no
    ///      holder-signed EVM address to record as the Root beneficiary. This test pins the chosen
    ///      behaviour — record nothing, invent nothing — and shows that Root-linked value which
    ///      accrues before a beneficiary exists is PARKED in the Root's pending bucket rather than
    ///      lost, which is what makes "bind later" a safe answer rather than a hopeful one.
    ///
    ///      The second half of the story — the holder actually claiming that bucket through
    ///      `RootOwnershipRegistry.bindRootOwner` — is currently blocked by a contradiction between
    ///      two contracts this suite does not own. See
    ///      `test_KNOWN_DEFECT_RootBindIsUnreachableAgainstTheRealOracle`.
    function test_SelfCastRecordsNoRootBeneficiaryAndValueIsParkedNotLost() public {
        address holder = makeAddr("bitcoinHolder");
        bytes32 offerId = _createSelfCast(holder, 2);
        PuppetTypes.OwnershipAttestation memory a = _selfCastAttestation(offerId);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(2);
        escrow.settleSelfCast(offerId, a, sigs, p);

        bytes32 key = _rootKey(2);
        assertEq(rootRegistry.epochOf(key), 0, "no epoch was invented from a zero payout field");
        {
            (address beneficiary,,) = rootRegistry.currentBeneficiary(key);
            assertEq(beneficiary, address(0), "no beneficiary was invented");
        }

        // Root-linked value that arrives before the bind is parked, not lost. It belongs to no
        // address yet and is released to whoever next proves Bitcoin control.
        _parkRootValue(key, 4 ether);
        assertEq(vault.pendingByRoot(key), 4 ether, "parked in the Root's pending bucket");
        assertEq(vault.claimable(holder), 0, "and it is nobody's balance in the meantime");
        assertEq(vault.claimable(recipient), 0, "in particular it is not the recipient's");
    }

    /// @dev BLOCKING CROSS-CONTRACT DEFECT, PINNED HERE SO THE INTEGRATION PHASE CANNOT MISS IT.
    ///      Neither contract involved is owned by this suite, so nothing is fixed here — only
    ///      demonstrated.
    ///
    ///      `RootOwnershipRegistry.bindRootOwner` requires a `ROOT_BIND` attestation with
    ///      `payoutMode == PayoutMode.EVM` and a non-zero `evmPayout`, because `evmPayout` IS the
    ///      new Root beneficiary — there is no other field it could come from.
    ///      `BitcoinOwnershipOracle._requireValidPayoutShape` maps every non-paying purpose,
    ///      `ROOT_BIND` included, to `PayoutMode.NONE` and rejects a non-zero `evmPayout`.
    ///
    ///      The two rules are mutually exclusive, so `bindRootOwner` reverts `InvalidPayoutShape`
    ///      for every possible input and the permissionless rebinding path does not exist. That
    ///      matters far beyond this escrow: it is also the only way a self-cast or BTC mint ever
    ///      acquires a Root beneficiary, and the only way a Root's pending bucket is ever released.
    function test_KNOWN_DEFECT_RootBindIsUnreachableAgainstTheRealOracle() public {
        address holder = makeAddr("bitcoinHolder");
        bytes32 offerId = _createSelfCast(holder, 2);
        bytes32 key = _rootKey(2);

        PuppetTypes.OwnershipAttestation memory bind = _baseAttestation(offerId);
        bind.purpose = uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND);
        bind.contextId = key;
        bind.offerTermsHash = bytes32(0);
        bind.payoutMode = uint8(PuppetTypes.PayoutMode.EVM);
        bind.evmPayout = holder;
        bind.grossWei = 0;
        bind.sellerWei = 0;
        bind.sellerSats = 0;
        bind.authorizationId = keccak256("bind-after-self-cast");
        bytes[] memory sigs = _sign(bind);
        bytes32[] memory p = _proof(2);

        // The shape the registry demands is the shape the oracle refuses.
        vm.expectRevert(IBitcoinOwnershipOracle.InvalidPayoutShape.selector);
        rootRegistry.bindRootOwner(bind, sigs, p);

        // And the shape the oracle demands is the shape the registry refuses, so there is no
        // third option: the function is unreachable, not merely awkward to call.
        PuppetTypes.OwnershipAttestation memory noneMode = bind;
        noneMode.payoutMode = uint8(PuppetTypes.PayoutMode.NONE);
        noneMode.evmPayout = address(0);
        bytes[] memory sigs2 = _sign(noneMode);
        bytes32[] memory p2 = _proof(2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RootOwnershipRegistry.UnsupportedPayoutMode.selector, uint8(PuppetTypes.PayoutMode.NONE)
            )
        );
        rootRegistry.bindRootOwner(noneMode, sigs2, p2);
    }

    /// @dev Credit a Root's pending bucket directly, standing in for recurring protocol value.
    function _parkRootValue(bytes32 key, uint256 amount) private {
        bytes32 creditor = vault.CREDITOR_ROLE();
        vm.prank(admin);
        vault.grantRole(creditor, address(this));
        vm.deal(address(this), amount);
        vault.creditRoot{value: amount}(key);
    }

    function test_SelfCastRejectsAnyPayoutFields() public {
        address holder = makeAddr("bitcoinHolder");
        bytes32 offerId = _createSelfCast(holder, 2);

        PuppetTypes.OwnershipAttestation memory a = _selfCastAttestation(offerId);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.EVM);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(2);
        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.AttestationFieldMismatch.selector, "payoutMode"));
        escrow.settleSelfCast(offerId, a, sigs, p);

        PuppetTypes.OwnershipAttestation memory b = _selfCastAttestation(offerId);
        b.evmPayout = makeAddr("sneakyPayout");
        bytes[] memory sigsB = _sign(b);
        bytes32[] memory pB = _proof(2);
        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.AttestationFieldMismatch.selector, "evmPayout"));
        escrow.settleSelfCast(offerId, b, sigsB, pB);

        PuppetTypes.OwnershipAttestation memory c = _selfCastAttestation(offerId);
        c.btcPayoutScriptHash = BTC_PAYOUT_SCRIPT;
        bytes[] memory sigsC = _sign(c);
        bytes32[] memory pC = _proof(2);
        vm.expectRevert(
            abi.encodeWithSelector(IHoodPupOfferEscrow.AttestationFieldMismatch.selector, "btcPayoutScriptHash")
        );
        escrow.settleSelfCast(offerId, c, sigsC, pC);
    }

    /*//////////////////////////////////////////////////////////////
                        BTC APPROVAL AND SOLVING
    //////////////////////////////////////////////////////////////*/

    function test_ApprovePaidBtcStoresProofWithoutMintingOrPaying() public {
        bytes32 offerId = _createBtc(0, 50_000);
        PuppetTypes.OwnershipAttestation memory a = _btcAttestation(offerId);
        bytes32 digest = oracle.hashOwnershipAttestation(a);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit IHoodPupOfferEscrow.BtcOfferApproved(offerId, digest, BTC_PAYOUT_SCRIPT, 50_000);
        vm.prank(relayer);
        escrow.approvePaidBtc(offerId, a, sigs, p);

        PuppetTypes.Offer memory o = escrow.getOffer(offerId);
        assertEq(o.status, uint8(PuppetTypes.OfferStatus.BTC_APPROVED), "BTC_APPROVED");
        assertEq(o.ownershipDigest, digest, "digest stored");
        assertEq(o.btcPayoutScriptHash, BTC_PAYOUT_SCRIPT, "script hash stored");

        assertFalse(nft.rootMinted(_rootKey(0)), "NO mint before a solver pays");
        assertEq(vault.totalLiability(), 0, "NO ETH moved");
        assertEq(address(escrow).balance, PRICE, "escrow still holds the buyer's ETH");
        assertEq(escrow.lockedEscrowWei(), PRICE, "still locked");
        assertEq(rootRegistry.epochOf(_rootKey(0)), 0, "no ownership epoch from a BTC payout mode");
    }

    function test_ApprovePaidBtcFieldChecks() public {
        bytes32 offerId = _createBtc(0, 50_000);

        PuppetTypes.OwnershipAttestation memory a = _btcAttestation(offerId);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.EVM);
        bytes[] memory s1 = _sign(a);
        bytes32[] memory p1 = _proof(0);
        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.AttestationFieldMismatch.selector, "payoutMode"));
        escrow.approvePaidBtc(offerId, a, s1, p1);

        PuppetTypes.OwnershipAttestation memory b = _btcAttestation(offerId);
        b.btcPayoutScriptHash = bytes32(0);
        bytes[] memory s2 = _sign(b);
        bytes32[] memory p2 = _proof(0);
        vm.expectRevert(
            abi.encodeWithSelector(IHoodPupOfferEscrow.AttestationFieldMismatch.selector, "btcPayoutScriptHash")
        );
        escrow.approvePaidBtc(offerId, b, s2, p2);

        PuppetTypes.OwnershipAttestation memory c = _btcAttestation(offerId);
        c.evmPayout = makeAddr("sneakyEvmPayout");
        bytes[] memory s3 = _sign(c);
        bytes32[] memory p3 = _proof(0);
        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.AttestationFieldMismatch.selector, "evmPayout"));
        escrow.approvePaidBtc(offerId, c, s3, p3);

        PuppetTypes.OwnershipAttestation memory d = _btcAttestation(offerId);
        d.sellerSats = 49_999;
        bytes[] memory s4 = _sign(d);
        bytes32[] memory p4 = _proof(0);
        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.AttestationFieldMismatch.selector, "sellerSats"));
        escrow.approvePaidBtc(offerId, d, s4, p4);
    }

    function test_MarkBtcReservedHappyPath() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);

        uint64 window = uint64(block.timestamp) + 2 hours;
        vm.expectEmit(true, true, false, true, address(escrow));
        emit IHoodPupOfferEscrow.BtcReserved(offerId, solver, window);
        vm.prank(btcSettlement);
        escrow.markBtcReserved(offerId, solver, window);

        PuppetTypes.Offer memory o = escrow.getOffer(offerId);
        assertEq(o.status, uint8(PuppetTypes.OfferStatus.BTC_RESERVED), "BTC_RESERVED");
        assertEq(o.reservedSolver, solver, "solver recorded");
        assertEq(o.reservationExpiry, window, "window recorded");
    }

    function test_MarkBtcReservedRequiresTheSettlementRole() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        uint64 window = uint64(block.timestamp) + 2 hours;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), roleBtcSettlement
            )
        );
        escrow.markBtcReserved(offerId, solver, window);
    }

    function test_MarkBtcReservedRejectsUnboundedAndBackwardsWindows() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        uint64 offerExpiry = escrow.getOffer(offerId).expiry;
        uint64 windowCap = uint64(block.timestamp) + escrow.MAX_RESERVATION_WINDOW();
        uint64 ceiling = windowCap < offerExpiry ? windowCap : offerExpiry;

        // A window in the past would be dead on arrival.
        vm.expectRevert(
            abi.encodeWithSelector(
                HoodPupOfferEscrow.ReservationWindowInvalid.selector,
                uint64(block.timestamp),
                uint64(block.timestamp),
                ceiling
            )
        );
        vm.prank(btcSettlement);
        escrow.markBtcReserved(offerId, solver, uint64(block.timestamp));

        // A window past the ceiling would let one solver freeze a buyer's escrow indefinitely.
        vm.expectRevert(
            abi.encodeWithSelector(
                HoodPupOfferEscrow.ReservationWindowInvalid.selector, type(uint64).max, uint64(block.timestamp), ceiling
            )
        );
        vm.prank(btcSettlement);
        escrow.markBtcReserved(offerId, solver, type(uint64).max);

        // And never past the offer's own expiry, which is what keeps refunds always reachable.
        vm.expectRevert(
            abi.encodeWithSelector(
                HoodPupOfferEscrow.ReservationWindowInvalid.selector, offerExpiry + 1, uint64(block.timestamp), ceiling
            )
        );
        vm.prank(btcSettlement);
        escrow.markBtcReserved(offerId, solver, offerExpiry + 1);
    }

    function test_MarkBtcReservedRejectsZeroSolverAndWrongStatus() public {
        bytes32 offerId = _createBtc(0, 50_000);
        uint64 window = uint64(block.timestamp) + 2 hours;

        vm.expectRevert(
            abi.encodeWithSelector(
                IHoodPupOfferEscrow.InvalidOfferStatus.selector,
                offerId,
                uint8(PuppetTypes.OfferStatus.OPEN),
                uint8(PuppetTypes.OfferStatus.BTC_APPROVED)
            )
        );
        vm.prank(btcSettlement);
        escrow.markBtcReserved(offerId, solver, window);

        _approveBtc(offerId, 0);
        vm.expectRevert(IHoodPupOfferEscrow.ZeroAddress.selector);
        vm.prank(btcSettlement);
        escrow.markBtcReserved(offerId, address(0), window);
    }

    function test_ClearBtcReservationReturnsToApproved() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        _reserve(offerId, 2 hours);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit IHoodPupOfferEscrow.BtcReservationCleared(offerId, solver);
        vm.prank(btcSettlement);
        escrow.clearBtcReservation(offerId);

        PuppetTypes.Offer memory o = escrow.getOffer(offerId);
        assertEq(o.status, uint8(PuppetTypes.OfferStatus.BTC_APPROVED), "back to approved");
        assertEq(o.reservedSolver, address(0), "solver cleared");
        assertEq(o.reservationExpiry, 0, "window cleared");
    }

    function test_ClearBtcReservationRequiresTheSettlementRole() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        _reserve(offerId, 2 hours);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), roleBtcSettlement
            )
        );
        escrow.clearBtcReservation(offerId);
    }

    /// @dev The escape hatch that makes "a buyer's escrow can never be trapped" true even if
    ///      `BtcSolverSettlement` is paused, broken, or has had its role revoked.
    function test_ExpireBtcReservationIsPermissionlessOnceTheWindowLapses() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        _reserve(offerId, 2 hours);
        uint64 window = escrow.getOffer(offerId).reservationExpiry;

        vm.expectRevert(abi.encodeWithSelector(HoodPupOfferEscrow.ReservationNotLapsed.selector, offerId, window));
        escrow.expireBtcReservation(offerId);

        // Even at exactly the reservation expiry the solver still owns the window.
        vm.warp(window);
        vm.expectRevert(abi.encodeWithSelector(HoodPupOfferEscrow.ReservationNotLapsed.selector, offerId, window));
        escrow.expireBtcReservation(offerId);

        vm.warp(uint256(window) + 1);
        vm.prank(makeAddr("anyKeeper"));
        escrow.expireBtcReservation(offerId);
        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.BTC_APPROVED), "released by a stranger");
    }

    function test_ABrokenSolverContractCannotTrapTheBuyersEscrow() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        _reserve(offerId, 2 hours);

        // The solver contract goes dark: its role is revoked and it can no longer clear anything.
        vm.prank(admin);
        escrow.revokeRole(roleBtcSettlement, btcSettlement);
        // Governance also pauses the escrow, which is the worst realistic combination.
        vm.prank(guardian);
        escrow.pauseSettlement();

        uint64 offerExpiry = escrow.getOffer(offerId).expiry;
        vm.warp(uint256(offerExpiry) + 1);

        // Because a reservation can never outlive the offer, an expired offer always has a lapsed
        // reservation, so the permissionless release is always available.
        escrow.expireBtcReservation(offerId);
        escrow.refundExpired(offerId);

        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.REFUNDED), "refunded");
        assertEq(vault.claimable(buyer), PRICE, "buyer made whole while paused and role-less");
    }

    function test_FinalizeBtcSettlementReimbursesTheSolverNotTheSeller() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        _reserve(offerId, 2 hours);

        vm.expectEmit(true, true, true, true, address(escrow));
        emit HoodPupOfferEscrow.BtcSettlementFinalized(offerId, solver, keccak256("paymentDigest"));
        vm.prank(btcSettlement);
        uint256 tokenId = escrow.finalizeBtcSettlement(offerId, solver, keccak256("paymentDigest"));

        assertEq(nft.ownerOf(tokenId), recipient, "recipient owns the HoodPup");
        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.SETTLED), "SETTLED");

        // Bob was paid in native BTC off chain, so the 50% share reimburses the solver that
        // fronted it. Paying an EVM seller address here would pay for the same Puppet twice.
        assertEq(vault.claimable(solver), PRICE / 2, "solver reimbursed");
        assertEq(vault.claimable(sellerPayout), 0, "no ETH to Bob");
        assertEq(vault.claimable(buyer), 0, "no ETH to the buyer");
        assertEq(vault.claimable(puppetTreasury), PRICE / 4, "puppet treasury 25%");
        assertEq(vault.claimable(protocolTreasury), PRICE - PRICE / 2 - PRICE / 4, "protocol 25%");
        assertEq(address(escrow).balance, 0, "escrow drained");
        assertEq(escrow.lockedEscrowWei(), 0, "locked accounting cleared");

        // No holder-signed EVM address exists on a BTC payout, so no beneficiary was invented.
        assertEq(rootRegistry.epochOf(_rootKey(0)), 0, "no Root epoch inferred from a BTC payout");
    }

    function test_FinalizeRequiresTheExactReservedSolver() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        _reserve(offerId, 2 hours);
        address impostor = makeAddr("impostorSolver");

        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.NotReservedSolver.selector, impostor, solver));
        vm.prank(btcSettlement);
        escrow.finalizeBtcSettlement(offerId, impostor, keccak256("paymentDigest"));
    }

    function test_FinalizeRequiresAReservationAndARole() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IHoodPupOfferEscrow.InvalidOfferStatus.selector,
                offerId,
                uint8(PuppetTypes.OfferStatus.BTC_APPROVED),
                uint8(PuppetTypes.OfferStatus.BTC_RESERVED)
            )
        );
        vm.prank(btcSettlement);
        escrow.finalizeBtcSettlement(offerId, solver, keccak256("paymentDigest"));

        _reserve(offerId, 2 hours);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), roleBtcSettlement
            )
        );
        escrow.finalizeBtcSettlement(offerId, solver, keccak256("paymentDigest"));
    }

    function test_FinalizeRejectsLapsedReservationAndZeroDigest() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        _reserve(offerId, 2 hours);

        vm.expectRevert(IHoodPupOfferEscrow.ZeroValue.selector);
        vm.prank(btcSettlement);
        escrow.finalizeBtcSettlement(offerId, solver, bytes32(0));

        uint64 window = escrow.getOffer(offerId).reservationExpiry;
        vm.warp(uint256(window) + 1);
        vm.expectRevert(abi.encodeWithSelector(HoodPupOfferEscrow.ReservationLapsed.selector, offerId, window));
        vm.prank(btcSettlement);
        escrow.finalizeBtcSettlement(offerId, solver, keccak256("paymentDigest"));
    }

    function test_FinalizeRejectsARootAnotherOfferAlreadyMinted() public {
        bytes32 btcOffer = _createBtc(0, 50_000);
        _approveBtc(btcOffer, 0);
        _reserve(btcOffer, 2 hours);

        bytes32 evmOffer = _createEvm(otherBuyer, 0, PRICE, recipient);
        _settleEvm(evmOffer, 0);

        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.RootAlreadyMinted.selector, _rootKey(0)));
        vm.prank(btcSettlement);
        escrow.finalizeBtcSettlement(btcOffer, solver, keccak256("paymentDigest"));
    }

    function test_NoBtcOfferMintsBeforeFinalization() public {
        bytes32 offerId = _createBtc(0, 50_000);
        assertFalse(nft.rootMinted(_rootKey(0)), "not minted at creation");
        _approveBtc(offerId, 0);
        assertFalse(nft.rootMinted(_rootKey(0)), "not minted at approval");
        _reserve(offerId, 2 hours);
        assertFalse(nft.rootMinted(_rootKey(0)), "not minted at reservation");
        vm.prank(btcSettlement);
        escrow.clearBtcReservation(offerId);
        assertFalse(nft.rootMinted(_rootKey(0)), "not minted when a reservation is cleared");
        _reserve(offerId, 2 hours);
        vm.prank(btcSettlement);
        escrow.finalizeBtcSettlement(offerId, solver, keccak256("paymentDigest"));
        assertTrue(nft.rootMinted(_rootKey(0)), "minted only at finalization");
    }

    /*//////////////////////////////////////////////////////////////
                                REFUNDS
    //////////////////////////////////////////////////////////////*/

    function test_RefundExpiredCreditsOnlyTheBuyer() public {
        bytes32 offerId = _createEvm(0);
        vm.warp(uint256(escrow.getOffer(offerId).expiry) + 1);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit IHoodPupOfferEscrow.OfferRefunded(offerId, buyer, PRICE, false);
        vm.prank(makeAddr("altruisticKeeper"));
        escrow.refundExpired(offerId);

        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.REFUNDED), "REFUNDED");
        assertEq(vault.claimable(buyer), PRICE, "buyer credited in full");
        assertEq(vault.claimable(recipient), 0, "recipient credited nothing");
        assertEq(vault.claimable(sellerPayout), 0, "seller credited nothing");
        assertEq(address(escrow).balance, 0, "escrow drained");
        assertEq(escrow.lockedEscrowWei(), 0, "locked accounting cleared");

        // The refund is a vault credit, not a push. The buyer pulls it.
        uint256 before = buyer.balance;
        vm.prank(buyer);
        vault.withdrawAll();
        assertEq(buyer.balance - before, PRICE, "buyer withdrew the full escrow");
    }

    function test_RefundExpiredWorksFromBtcApproved() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        vm.warp(uint256(escrow.getOffer(offerId).expiry) + 1);
        escrow.refundExpired(offerId);
        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.REFUNDED), "REFUNDED");
        assertEq(vault.claimable(buyer), PRICE, "buyer credited");
    }

    function test_RefundExpiredRejectsAReservedOffer() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        _reserve(offerId, 2 hours);
        vm.warp(uint256(escrow.getOffer(offerId).expiry) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IHoodPupOfferEscrow.InvalidOfferStatus.selector,
                offerId,
                uint8(PuppetTypes.OfferStatus.BTC_RESERVED),
                uint8(PuppetTypes.OfferStatus.OPEN)
            )
        );
        escrow.refundExpired(offerId);
    }

    function test_RefundUnfillableFromEveryNonTerminalStatus() public {
        // Three losing offers, one per non-terminal status, then a competitor takes the Root.
        bytes32 openOffer = _createEvm(buyer, 0, 1 ether, recipient);
        bytes32 approvedOffer = _createBtc(0, 50_000);
        _approveBtc(approvedOffer, 0);
        vm.prank(otherBuyer);
        bytes32 reservedOffer = escrow.createPaidBtcOffer{value: 3 ether}(
            roots[0], recipient, 60_000, uint64(block.timestamp) + 1 days, _proof(0)
        );
        _approveBtc(reservedOffer, 0);
        _reserve(reservedOffer, 2 hours);

        bytes32 winner = _createEvm(otherBuyer, 0, 9 ether, recipient);
        _settleEvm(winner, 0);

        escrow.refundUnfillable(openOffer);
        escrow.refundUnfillable(approvedOffer);
        // A reserved offer IS refundable once the Root is minted: finalization is structurally
        // impossible from that point, so the reservation protects nobody. The dead reservation is
        // released first so the terminal record never carries a solver that means nothing.
        vm.expectEmit(true, true, false, true, address(escrow));
        emit IHoodPupOfferEscrow.BtcReservationCleared(reservedOffer, solver);
        escrow.refundUnfillable(reservedOffer);
        PuppetTypes.Offer memory closed = escrow.getOffer(reservedOffer);
        assertEq(closed.reservedSolver, address(0), "dead reservation released");
        assertEq(closed.reservationExpiry, 0, "dead window released");

        assertEq(_status(openOffer), uint8(PuppetTypes.OfferStatus.REFUNDED), "open refunded");
        assertEq(_status(approvedOffer), uint8(PuppetTypes.OfferStatus.REFUNDED), "approved refunded");
        assertEq(_status(reservedOffer), uint8(PuppetTypes.OfferStatus.REFUNDED), "reserved refunded");
        assertEq(vault.claimable(buyer), 1 ether + 1 ether, "buyer's two losing escrows returned");
        assertEq(vault.claimable(otherBuyer), 3 ether, "other buyer's losing escrow returned");
        assertEq(escrow.lockedEscrowWei(), 0, "nothing left locked");
        assertEq(address(escrow).balance, 0, "escrow drained");
    }

    function test_RefundUnfillableRequiresTheRootToBeMinted() public {
        bytes32 offerId = _createEvm(0);
        vm.expectRevert(abi.encodeWithSelector(IHoodPupOfferEscrow.RootNotMinted.selector, _rootKey(0)));
        escrow.refundUnfillable(offerId);
    }

    function test_RefundsAreTerminalAndCannotRepeat() public {
        bytes32 offerId = _createEvm(0);
        vm.warp(uint256(escrow.getOffer(offerId).expiry) + 1);
        escrow.refundExpired(offerId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IHoodPupOfferEscrow.InvalidOfferStatus.selector,
                offerId,
                uint8(PuppetTypes.OfferStatus.REFUNDED),
                uint8(PuppetTypes.OfferStatus.OPEN)
            )
        );
        escrow.refundExpired(offerId);

        assertEq(vault.claimable(buyer), PRICE, "credited exactly once");
    }

    function test_SettledOffersCanNeverBeRefunded() public {
        bytes32 offerId = _createEvm(0);
        _settleEvm(offerId, 0);
        vm.warp(uint256(escrow.getOffer(offerId).expiry) + 10 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                IHoodPupOfferEscrow.InvalidOfferStatus.selector,
                offerId,
                uint8(PuppetTypes.OfferStatus.SETTLED),
                uint8(PuppetTypes.OfferStatus.OPEN)
            )
        );
        escrow.refundExpired(offerId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IHoodPupOfferEscrow.InvalidOfferStatus.selector,
                offerId,
                uint8(PuppetTypes.OfferStatus.SETTLED),
                uint8(PuppetTypes.OfferStatus.OPEN)
            )
        );
        escrow.refundUnfillable(offerId);

        assertEq(vault.claimable(buyer), 0, "a settled offer never returns money to the buyer");
    }

    function test_RefundedOffersCanNeverSettle() public {
        bytes32 offerId = _createEvm(0);
        vm.warp(uint256(escrow.getOffer(offerId).expiry) + 1);
        escrow.refundExpired(offerId);

        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(offerId, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p = _proof(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHoodPupOfferEscrow.InvalidOfferStatus.selector,
                offerId,
                uint8(PuppetTypes.OfferStatus.REFUNDED),
                uint8(PuppetTypes.OfferStatus.OPEN)
            )
        );
        escrow.settlePaidEvm(offerId, a, sigs, p);
    }

    function test_SelfCastRefundClosesTheRowWithNoMoney() public {
        address holder = makeAddr("bitcoinHolder");
        bytes32 offerId = _createSelfCast(holder, 2);
        vm.warp(uint256(escrow.getOffer(offerId).expiry) + 1);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit IHoodPupOfferEscrow.OfferRefunded(offerId, holder, 0, false);
        escrow.refundExpired(offerId);

        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.REFUNDED), "REFUNDED");
        assertEq(vault.totalLiability(), 0, "no money existed to move");
    }

    function test_ABuyerThatRejectsEthStillGetsRefunded() public {
        RejectingReceiver hostileBuyer = new RejectingReceiver();
        vm.deal(address(hostileBuyer), 10 ether);
        vm.prank(address(hostileBuyer));
        bytes32 offerId =
            escrow.createPaidEvmOffer{value: PRICE}(roots[0], recipient, uint64(block.timestamp) + 1 days, _proof(0));

        vm.warp(uint256(escrow.getOffer(offerId).expiry) + 1);
        escrow.refundExpired(offerId);

        // Pull payment means a buyer whose address reverts on receive cannot make their own refund
        // — and therefore this offer's closure — permanently impossible.
        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.REFUNDED), "closed cleanly");
        assertEq(vault.claimable(address(hostileBuyer)), PRICE, "credited, awaiting a pull");
    }

    /*//////////////////////////////////////////////////////////////
                          THE COMPETING-OFFER STORY
    //////////////////////////////////////////////////////////////*/

    function test_TwoCompetingOffersOneWinsTheOtherIsImmediatelyRefundable() public {
        bytes32 lowball = _createEvm(buyer, 0, 1 ether, recipient);
        address betterRecipient = makeAddr("betterRecipient");
        bytes32 generous = _createEvm(otherBuyer, 0, 5 ether, betterRecipient);
        assertEq(escrow.lockedEscrowWei(), 6 ether, "both escrows held");

        // Bob signs the generous one. Nothing about the lowball offer changes yet.
        uint256 tokenId = _settleEvm(generous, 0);
        assertEq(nft.ownerOf(tokenId), betterRecipient, "the winning recipient got it");
        assertEq(vault.claimable(sellerPayout), 2.5 ether, "Bob's 50% of the winning offer");
        assertEq(_status(lowball), uint8(PuppetTypes.OfferStatus.OPEN), "the loser is untouched, not seized");

        // The loser's buyer does not have to wait for expiry.
        escrow.refundUnfillable(lowball);
        assertEq(vault.claimable(buyer), 1 ether, "loser refunded in full");
        assertEq(escrow.lockedEscrowWei(), 0, "escrow holds nothing");
        assertEq(address(escrow).balance, 0, "escrow balance zero");

        // Conservation across the whole story: 6 ether in, 6 ether accounted for.
        assertEq(
            vault.claimable(buyer) + vault.claimable(sellerPayout) + vault.claimable(puppetTreasury)
                + vault.claimable(protocolTreasury),
            6 ether,
            "every deposited wei is either refunded or distributed"
        );
        assertEq(vault.totalLiability(), 6 ether, "and the vault agrees");
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSING
    //////////////////////////////////////////////////////////////*/

    function test_PauseBlocksCreationAndSettlement() public {
        bytes32 openOffer = _createEvm(0);
        bytes32 btcOffer = _createBtc(1, 50_000);
        PuppetTypes.OwnershipAttestation memory a = _evmAttestation(openOffer, sellerPayout);
        bytes[] memory sigs = _sign(a);
        bytes32[] memory p0 = _proof(0);
        PuppetTypes.OwnershipAttestation memory b = _btcAttestation(btcOffer);
        bytes[] memory sigsB = _sign(b);
        bytes32[] memory p1 = _proof(1);
        bytes32[] memory p2 = _proof(2);

        vm.prank(guardian);
        escrow.pauseSettlement();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(buyer);
        escrow.createPaidEvmOffer{value: PRICE}(roots[2], recipient, uint64(block.timestamp) + 1 days, p2);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(buyer);
        escrow.createPaidBtcOffer{value: PRICE}(roots[2], recipient, 1000, uint64(block.timestamp) + 1 days, p2);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(buyer);
        escrow.createSelfCastOffer(roots[2], buyer, uint64(block.timestamp) + 1 days, p2);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.settlePaidEvm(openOffer, a, sigs, p0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.approvePaidBtc(btcOffer, b, sigsB, p1);
    }

    function test_PauseBlocksTheAuthorizedBtcHooksThatTakeOnRisk() public {
        bytes32 offerId = _createBtc(0, 50_000);
        _approveBtc(offerId, 0);
        uint64 window = uint64(block.timestamp) + 2 hours;

        vm.prank(guardian);
        escrow.pauseSettlement();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(btcSettlement);
        escrow.markBtcReserved(offerId, solver, window);
    }

    function test_RefundsAndReleasesStayLiveWhilePaused() public {
        bytes32 expiredOffer = _createEvm(buyer, 0, PRICE, recipient);
        bytes32 loser = _createEvm(otherBuyer, 1, 2 ether, recipient);
        bytes32 reserved = _createBtc(2, 50_000);
        _approveBtc(reserved, 2);
        _reserve(reserved, 2 hours);

        // Mint root 1 out from under the loser so `refundUnfillable` has a real trigger.
        bytes32 winner = _createEvm(buyer, 1, 3 ether, recipient);
        _settleEvm(winner, 1);

        vm.prank(guardian);
        escrow.pauseSettlement();
        assertTrue(escrow.paused(), "paused");

        vm.warp(uint256(escrow.getOffer(expiredOffer).expiry) + 1);

        escrow.refundExpired(expiredOffer);
        escrow.refundUnfillable(loser);
        vm.prank(btcSettlement);
        escrow.clearBtcReservation(reserved);
        escrow.refundExpired(reserved);

        // `expiredOffer` and `reserved` were both opened by `buyer`; `loser` by `otherBuyer`.
        assertEq(vault.claimable(buyer), PRICE + PRICE, "expired and reserved refunds paid while paused");
        assertEq(vault.claimable(otherBuyer), 2 ether, "unfillable refund paid while paused");
        assertEq(escrow.lockedEscrowWei(), 0, "everything released");

        // And a pause cannot stop a withdrawal from the vault either.
        vm.prank(buyer);
        vault.withdrawAll();
        assertEq(vault.claimable(buyer), 0, "withdrawn while the escrow is paused");
    }

    function test_GuardianPausesButOnlyTheTimelockUnpauses() public {
        vm.prank(guardian);
        escrow.pauseSettlement();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, guardian, roleDefaultAdmin)
        );
        vm.prank(guardian);
        escrow.unpauseSettlement();

        vm.prank(admin);
        escrow.unpauseSettlement();
        assertFalse(escrow.paused(), "unpaused by the timelock");
    }

    function test_OnlyThePauserCanPause() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, buyer, rolePauser)
        );
        vm.prank(buyer);
        escrow.pauseSettlement();
    }

    /*//////////////////////////////////////////////////////////////
                         VALUE-HANDLING SAFETY
    //////////////////////////////////////////////////////////////*/

    function test_DirectEthTransfersAreRejected() public {
        vm.deal(address(this), 1 ether);
        (bool ok, bytes memory ret) = address(escrow).call{value: 1 ether}("");
        assertFalse(ok, "plain transfer rejected");
        assertEq(_selectorOf(ret), HoodPupOfferEscrow.DirectDepositRejected.selector, "named error");

        (bool ok2, bytes memory ret2) = address(escrow).call{value: 1 ether}(hex"12345678");
        assertFalse(ok2, "unknown selector rejected");
        assertEq(_selectorOf(ret2), HoodPupOfferEscrow.DirectDepositRejected.selector, "named error on fallback");
        assertEq(address(escrow).balance, 0, "nothing stuck");
    }

    function test_ForcedEthNeverBecomesAnybodysEscrow() public {
        bytes32 offerId = _createEvm(0);
        // ETH that arrives without a transaction (a block reward or a `selfdestruct`) cannot be
        // refused. It must never be treated as escrow, and it must never block a settlement.
        vm.deal(address(escrow), address(escrow).balance + 5 ether);

        assertEq(escrow.lockedEscrowWei(), PRICE, "forced ETH is not counted as escrow");
        _settleEvm(offerId, 0);

        assertEq(vault.totalLiability(), PRICE, "only the real escrow was distributed");
        assertEq(address(escrow).balance, 5 ether, "the forced ETH is stranded, harmless and unclaimable");
        assertEq(escrow.lockedEscrowWei(), 0, "and the accounting is clean");
    }

    function test_LockedEscrowTracksEveryDepositAndRelease() public {
        assertEq(escrow.lockedEscrowWei(), 0, "starts empty");
        bytes32 a = _createEvm(buyer, 0, 1 ether, recipient);
        assertEq(escrow.lockedEscrowWei(), 1 ether, "one offer");
        bytes32 b = _createEvm(otherBuyer, 1, 2 ether, recipient);
        assertEq(escrow.lockedEscrowWei(), 3 ether, "two offers");
        _createSelfCast(makeAddr("holder3"), 2);
        assertEq(escrow.lockedEscrowWei(), 3 ether, "a self-cast adds nothing");

        _settleEvm(a, 0);
        assertEq(escrow.lockedEscrowWei(), 2 ether, "settlement releases");
        vm.warp(uint256(escrow.getOffer(b).expiry) + 1);
        escrow.refundExpired(b);
        assertEq(escrow.lockedEscrowWei(), 0, "refund releases");
        assertEq(address(escrow).balance, 0, "and the balance agrees");
    }

    /// @dev HONEST LIMITATION, PINNED SO IT CANNOT REGRESS SILENTLY. `PayoutVault.credit` is
    ///      `whenNotPaused`, so pausing the VAULT blocks the escrow from crediting a refund. The
    ///      escrow's own pause does not do this — see `test_RefundsAndReleasesStayLiveWhilePaused`.
    ///      No money is lost: the offer stays refundable forever and the same call succeeds once
    ///      the vault resumes. Integration should decide whether `credit` ought to be pausable at
    ///      all; this test records today's behaviour either way.
    /// @notice A paused vault must NOT defer a refund — invariant I12 requires it to go through.
    /// @dev This previously asserted the opposite: that a paused vault made `refundExpired` revert,
    ///      leaving the offer refundable later ("deferred, never lost"). That is a defensible
    ///      design, and it is not the one the protocol promises. The build specification requires
    ///      that "refunds and withdrawals must remain available during an emergency pause",
    ///      invariant I12 says the same, and `docs/INCIDENT_RESPONSE.md` tells users in as many
    ///      words that they can still get their money out while the protocol is paused.
    ///
    ///      The conflict was invisible to this suite and to PayoutVault's: `credit` is correctly
    ///      pausable, `withdraw` is correctly not, and refunds correctly survive an ESCROW pause.
    ///      Only wiring both contracts together and pausing the VAULT exposed it — see
    ///      `test/integration/FullFlow.t.sol`. The fix is `PayoutVault.creditRefund`, which is
    ///      `CREDITOR_ROLE`-gated but deliberately not pausable, because a refund releases an
    ///      obligation the buyer already holds rather than creating a new one.
    function test_APausedVaultStillLetsARefundThrough() public {
        bytes32 offerId = _createEvm(0);
        vm.warp(uint256(escrow.getOffer(offerId).expiry) + 1);

        vm.prank(admin);
        vault.pause();

        escrow.refundExpired(offerId);
        assertEq(_status(offerId), uint8(PuppetTypes.OfferStatus.REFUNDED), "refund completes while paused");
        assertEq(vault.claimable(buyer), PRICE, "buyer is made whole immediately");
        assertEq(address(escrow).balance, 0, "escrow released the deposit");

        // And the buyer can actually take it out, because withdrawals are not pausable either.
        uint256 before = buyer.balance;
        vm.prank(buyer);
        vault.withdrawAll();
        assertEq(buyer.balance - before, PRICE, "withdrawable during the same pause");
    }

    /// @notice The pause still does what it is for: no NEW obligations while it is on.
    /// @dev Making refunds non-pausable must not accidentally make everything non-pausable.
    function test_APausedVaultStillBlocksNonRefundCredits() public {
        vm.prank(admin);
        vault.pause();

        // The pranked sender is the one that pays, so fund the escrow rather than this contract.
        vm.deal(address(escrow), 1 ether);
        vm.prank(address(escrow));
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.credit{value: 1 ether}(buyer);
    }

    function test_NoAdminPathCanSeizeOrRedirectEscrow() public view {
        bytes memory code = address(escrow).code;
        bytes4[10] memory forbidden = [
            bytes4(keccak256("setPayoutVault(address)")),
            bytes4(keccak256("setFeeRouter(address)")),
            bytes4(keccak256("setOracle(address)")),
            bytes4(keccak256("sweep(address)")),
            bytes4(keccak256("sweepEscrow(address)")),
            bytes4(keccak256("rescueEth(address,uint256)")),
            bytes4(keccak256("transferOwnership(address)")),
            bytes4(keccak256("upgradeTo(address)")),
            bytes4(keccak256("upgradeToAndCall(address,bytes)")),
            bytes4(keccak256("initialize(address)"))
        ];
        for (uint256 i = 0; i < forbidden.length; i++) {
            assertFalse(_hasSelector(code, forbidden[i]), "forbidden admin surface present");
        }
        // Positive control: the scan does find something that genuinely exists, so it cannot pass
        // by finding nothing at all.
        assertTrue(_hasSelector(code, IHoodPupOfferEscrow.getOffer.selector), "positive control");
    }

    function test_TheAdminCannotChangeAnOffersTermsOrTakeItsMoney() public {
        bytes32 offerId = _createEvm(0);
        PuppetTypes.Offer memory before = escrow.getOffer(offerId);

        // The most privileged possible actor does everything the contract lets them do.
        vm.startPrank(admin);
        escrow.grantRole(roleBtcSettlement, admin);
        escrow.grantRole(rolePauser, admin);
        escrow.pauseSettlement();
        escrow.unpauseSettlement();
        vm.stopPrank();

        PuppetTypes.Offer memory current = escrow.getOffer(offerId);
        assertEq(current.grossWei, before.grossWei, "gross unchanged");
        assertEq(current.recipient, before.recipient, "recipient unchanged");
        assertEq(current.termsHash, before.termsHash, "terms unchanged");
        assertEq(current.status, before.status, "status unchanged");
        assertEq(address(escrow).balance, PRICE, "the escrow is untouched");
    }

    /*//////////////////////////////////////////////////////////////
                          FULL NARRATIVE PATHS
    //////////////////////////////////////////////////////////////*/

    /// @dev End to end, with a real quorum, across all three offer kinds and three roots. This is
    ///      the test that would fail first if any of the seven contracts stopped agreeing.
    function test_EndToEnd_AllThreeKindsSettleAgainstThreeRoots() public {
        // 1. Alice buys root 0 for ETH; Bob elects an EVM payout.
        bytes32 evmOffer = _createEvm(buyer, 0, 4 ether, recipient);
        uint256 evmToken = _settleEvm(evmOffer, 0);

        // 2. Another buyer buys root 1 in native BTC through a bonded solver.
        vm.prank(otherBuyer);
        bytes32 btcOffer = escrow.createPaidBtcOffer{value: 8 ether}(
            roots[1], recipient, 250_000, uint64(block.timestamp) + 1 days, _proof(1)
        );
        _approveBtc(btcOffer, 1);
        _reserve(btcOffer, 4 hours);
        vm.prank(btcSettlement);
        uint256 btcToken = escrow.finalizeBtcSettlement(btcOffer, solver, keccak256("btc-payment"));

        // 3. The Bitcoin controller of root 2 self-casts for free.
        address holder = makeAddr("selfCaster");
        bytes32 freeOffer = _createSelfCast(holder, 2);
        PuppetTypes.OwnershipAttestation memory sc = _selfCastAttestation(freeOffer);
        bytes[] memory scSigs = _sign(sc);
        bytes32[] memory scProof = _proof(2);
        uint256 freeToken = escrow.settleSelfCast(freeOffer, sc, scSigs, scProof);

        // Three distinct HoodPups, three distinct Roots, three distinct owners.
        assertEq(nft.ownerOf(evmToken), recipient, "evm mint");
        assertEq(nft.ownerOf(btcToken), recipient, "btc mint");
        assertEq(nft.ownerOf(freeToken), holder, "self cast mint");
        assertTrue(evmToken != btcToken && btcToken != freeToken, "distinct tokens");

        // Money: 4 + 8 = 12 ether in, split 50/25/25 with the seller share going to Bob on the EVM
        // path and to the solver on the BTC path.
        assertEq(vault.claimable(sellerPayout), 2 ether, "Bob 50% of 4");
        assertEq(vault.claimable(solver), 4 ether, "solver 50% of 8");
        assertEq(vault.claimable(puppetTreasury), 1 ether + 2 ether, "puppet treasury 25% of each");
        assertEq(vault.claimable(protocolTreasury), 1 ether + 2 ether, "protocol 25% of each");
        assertEq(vault.totalLiability(), 12 ether, "conservation");
        assertEq(address(escrow).balance, 0, "escrow drained");
        assertEq(escrow.lockedEscrowWei(), 0, "nothing locked");

        // Only the EVM path recorded a Root beneficiary, because only it carried a signed address.
        assertEq(rootRegistry.epochOf(_rootKey(0)), 1, "evm path recorded an epoch");
        assertEq(rootRegistry.epochOf(_rootKey(1)), 0, "btc path did not");
        assertEq(rootRegistry.epochOf(_rootKey(2)), 0, "self cast did not");
    }

    /// @dev One Root mints once, no matter how many offers chase it or in what order.
    function test_OneRootMintsOnceAcrossFiveCompetingOffers() public {
        bytes32[] memory offerIds = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            address who = i % 2 == 0 ? buyer : otherBuyer;
            offerIds[i] = _createEvm(who, 0, (i + 1) * 1 ether, recipient);
        }
        assertEq(escrow.lockedEscrowWei(), 15 ether, "all five escrows held");

        _settleEvm(offerIds[2], 0);
        assertEq(nft.nextTokenId(), 2, "exactly one token exists");

        for (uint256 i = 0; i < 5; i++) {
            if (i == 2) continue;
            escrow.refundUnfillable(offerIds[i]);
        }

        assertEq(nft.nextTokenId(), 2, "still exactly one token");
        assertEq(escrow.lockedEscrowWei(), 0, "all losers refunded");
        assertEq(address(escrow).balance, 0, "escrow drained");
        assertEq(vault.totalLiability(), 15 ether, "every deposited wei is accounted for");
    }
}
