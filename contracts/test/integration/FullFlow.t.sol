// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployConfig, DeployLib, DeployParams, Deployment} from "../../script/Deploy.s.sol";
import {IBtcSolverSettlement} from "../../src/interfaces/IBtcSolverSettlement.sol";
import {IHoodPupOfferEscrow} from "../../src/interfaces/IHoodPupOfferEscrow.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";
import {AttestorSet} from "../helpers/AttestorSet.sol";
import {MerkleFixture} from "../helpers/MerkleFixture.sol";

/// @title FullFlowTest
/// @notice The only suite that deploys all ten contracts together and runs real end-to-end flows.
///
/// @dev Every other suite tests one contract against mocks, which is right for isolating logic and
///      useless for catching wiring. This one deliberately uses **no mocks at all** and calls
///      `DeployLib.deployAll` / `grantRoles` — the same code path a real deployment takes — so a
///      missing role grant or a mismatched constructor argument fails here rather than on a testnet.
///
///      What that buys, concretely: the per-contract suites all passed while nothing had ever
///      checked that the escrow can actually call FeeRouter, that FeeRouter can actually credit
///      PayoutVault, or that the oracle will accept a digest the escrow computes.
contract FullFlowTest is Test {
    Deployment internal d;
    AttestorSet internal attestors;

    address internal constant TIMELOCK = address(0x71E10C);
    address internal constant GUARDIAN = address(0x6A11);
    address internal constant PUPPET_TREASURY = address(0x7EA1);
    address internal constant PROTOCOL_TREASURY = address(0x7EA2);
    address internal constant ALICE = address(0xA11CE); // buyer + recipient
    address internal constant BOB = address(0xB0B); // Bitcoin Puppet holder
    address internal constant BOB_PAYOUT = address(0xB0B9A1D); // where Bob signed to be paid
    address internal constant SOLVER = address(0x501E4);
    address internal constant RELAYER = address(0xAE1A);

    /// Two sibling inscriptions sharing a reveal txid, so the fixture also proves index separation.
    bytes32 internal constant TXID_A = keccak256("integration-reveal-tx-a");
    bytes32 internal constant TXID_B = keccak256("integration-reveal-tx-b");

    PuppetTypes.RootId internal rootA = PuppetTypes.RootId({inscriptionTxid: TXID_A, inscriptionIndex: 0});
    PuppetTypes.RootId internal rootB = PuppetTypes.RootId({inscriptionTxid: TXID_A, inscriptionIndex: 1});
    PuppetTypes.RootId internal rootC = PuppetTypes.RootId({inscriptionTxid: TXID_B, inscriptionIndex: 0});

    bytes32[] internal leaves;
    bytes32 internal merkleRoot;

    uint256 internal constant GROSS = 1 ether;
    uint256 internal constant SELLER_WEI = 0.5 ether;
    uint64 internal constant SELLER_SATS = 250_000;
    bytes32 internal constant BTC_PAYOUT_SCRIPT = keccak256("integration-bob-btc-script");

    function setUp() public {
        attestors = new AttestorSet(5, keccak256("integration"));

        PuppetTypes.RootId[] memory roots = new PuppetTypes.RootId[](3);
        roots[0] = rootA;
        roots[1] = rootB;
        roots[2] = rootC;
        leaves = MerkleFixture.leavesOf(roots);
        merkleRoot = MerkleFixture.build(leaves);

        DeployParams memory p = DeployParams({
            admin: address(this),
            merkleRoot: merkleRoot,
            manifestHash: keccak256("integration-manifest"),
            manifestVersion: "integration-v1",
            manifestLeafCount: 3,
            attestors: attestors.addresses(),
            threshold: 3,
            puppetTreasury: PUPPET_TREASURY,
            protocolTreasury: PROTOCOL_TREASURY,
            baseURI: "https://example.invalid/hoodpups/",
            contractURI: "https://example.invalid/hoodpups.json"
        });

        d = DeployLib.deployAll(p, DeployConfig.forChain(31_337, true));
        DeployLib.grantRoles(d);
        DeployLib.verifyRoles(d);

        vm.deal(ALICE, 100 ether);
        vm.deal(SOLVER, 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                          WIRING AND GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    function test_DeploymentWiringIsComplete() public view {
        // verifyRoles already ran in setUp; this asserts the negative side — nothing extra was
        // granted that the role matrix does not account for.
        assertFalse(d.oracle.hasRole(d.oracle.OWNERSHIP_CONSUMER_ROLE(), address(d.solver)));
        assertFalse(d.oracle.hasRole(d.oracle.PAYMENT_CONSUMER_ROLE(), address(d.escrow)));
        assertFalse(d.hoodPups.hasRole(d.hoodPups.MINTER_ROLE(), address(d.tourEngine)));
        assertFalse(d.payoutVault.hasRole(d.payoutVault.CREDITOR_ROLE(), address(d.tourEngine)));
        assertEq(d.escrow.btcSettlementCoordinator(), address(d.solver));
    }

    function test_AdminHandoverRevokesTheDeployerEverywhere() public {
        DeployLib.transferAdminToTimelock(d, TIMELOCK, GUARDIAN, address(this));
        // The expensive mistake: an EOA keeping admin on a contract that can never be upgraded.
        DeployLib.assertDeployerRevoked(d, address(this));
        assertTrue(d.escrow.hasRole(0x00, TIMELOCK));
        // The guardian may pause and nothing else — a compromised guardian costs liveness only.
        assertTrue(d.escrow.hasRole(d.escrow.PAUSER_ROLE(), GUARDIAN));
        assertFalse(d.escrow.hasRole(0x00, GUARDIAN));
    }

    function test_DeploymentRefusesAnUnknownChain() public {
        // Routed through an external wrapper: internal library calls are inlined, so vm.expectRevert
        // has no call boundary to catch and reports "didn't revert at a lower depth".
        vm.expectRevert(abi.encodeWithSelector(DeployConfig.UnsupportedChain.selector, uint256(1)));
        this.exposedForChain(1, true);
    }

    function test_DeploymentRequiresAnExplicitLocalOverride() public {
        vm.expectRevert(abi.encodeWithSelector(DeployConfig.LocalOverrideRequired.selector, uint256(31_337)));
        this.exposedForChain(31_337, false);
    }

    /// @dev External so `vm.expectRevert` sees a real call frame.
    function exposedForChain(uint256 chainId, bool allowLocal) external pure {
        DeployConfig.forChain(chainId, allowLocal);
    }

    /*//////////////////////////////////////////////////////////////
                        THE PAID EVM SETTLEMENT PATH
    //////////////////////////////////////////////////////////////*/

    /// @notice Alice escrows, Bob's quorum-attested authorization settles, everyone is paid.
    function test_PaidEvmFlow_EndToEnd() public {
        bytes32 offerId = _createEvmOffer(rootA);

        uint256 escrowBefore = address(d.escrow).balance;
        assertEq(escrowBefore, GROSS, "escrow should hold the deposit");

        _settleEvm(offerId, rootA);

        // 1. The HoodPup exists, exactly once, and belongs to Alice.
        bytes32 key = PuppetHashing.rootKey(rootA);
        assertTrue(d.hoodPups.rootMinted(key));
        uint256 tokenId = d.hoodPups.tokenOfRoot(key);
        assertEq(d.hoodPups.ownerOf(tokenId), ALICE);

        // 2. The split is exact, and went to the address BOB SIGNED — not to Bob's own address.
        assertEq(d.payoutVault.claimable(BOB_PAYOUT), 0.5 ether, "seller share");
        assertEq(d.payoutVault.claimable(PUPPET_TREASURY), 0.25 ether, "puppet treasury");
        assertEq(d.payoutVault.claimable(PROTOCOL_TREASURY), 0.25 ether, "protocol treasury");
        assertEq(d.payoutVault.claimable(BOB), 0, "Bob's own address is not the payout address");

        // 3. Conservation across the whole system.
        assertEq(address(d.escrow).balance, 0, "escrow retains nothing");
        assertEq(address(d.feeRouter).balance, 0, "router retains nothing");
        assertEq(address(d.payoutVault).balance, GROSS, "vault holds it all");
        assertEq(d.payoutVault.totalLiability(), GROSS, "liability equals the deposit");

        // 4. The Root ownership epoch was recorded as part of the same transaction.
        (address beneficiary, bool active, uint64 epoch) = d.rootRegistry.currentBeneficiary(key);
        assertEq(beneficiary, BOB_PAYOUT);
        assertTrue(active);
        assertEq(epoch, 1);
    }

    function test_SellerCanWithdrawWhatTheyWereCredited() public {
        _settleEvm(_createEvmOffer(rootA), rootA);

        uint256 before = BOB_PAYOUT.balance;
        vm.prank(BOB_PAYOUT);
        d.payoutVault.withdrawAll();
        assertEq(BOB_PAYOUT.balance - before, 0.5 ether);
        assertEq(d.payoutVault.claimable(BOB_PAYOUT), 0);
        // The vault stays solvent for everyone else.
        assertGe(address(d.payoutVault).balance, d.payoutVault.totalLiability());
    }

    /// @notice One Root, two buyers. Exactly one HoodPup; the loser gets their ETH back.
    function test_CompetingOffers_OneMintsAndTheOtherRefunds() public {
        address rival = address(0x217A1);
        vm.deal(rival, 10 ether);

        bytes32 winner = _createEvmOffer(rootA);
        bytes32 loser = _createEvmOfferFrom(rival, rootA);

        _settleEvm(winner, rootA);

        // The Root is spent. The rival's offer is now unfillable and refundable immediately —
        // they should not have to wait out the expiry for an offer that can never settle.
        d.escrow.refundUnfillable(loser);
        assertEq(d.payoutVault.claimable(rival), GROSS, "rival refunded in full");

        assertEq(d.hoodPups.nextTokenId(), 2, "exactly one token minted");
    }

    function test_ExpiredOfferRefundsAndRefundsSurvivePause() public {
        bytes32 offerId = _createEvmOffer(rootA);

        // Pause everything a guardian can pause. PAUSER_ROLE is not held by the deployer by
        // default — pausing is the guardian's job, so the test grants it explicitly rather than
        // assuming the admin can do it.
        d.escrow.grantRole(d.escrow.PAUSER_ROLE(), GUARDIAN);
        d.payoutVault.grantRole(d.payoutVault.PAUSER_ROLE(), GUARDIAN);
        d.oracle.grantRole(d.oracle.PAUSER_ROLE(), GUARDIAN);
        vm.startPrank(GUARDIAN);
        d.escrow.pauseSettlement();
        d.payoutVault.pause();
        d.oracle.pause();
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);
        // Protocol invariant I12: pausing must never block a refund or a withdrawal.
        d.escrow.refundExpired(offerId);
        assertEq(d.payoutVault.claimable(ALICE), GROSS);

        uint256 before = ALICE.balance;
        vm.prank(ALICE);
        d.payoutVault.withdrawAll();
        assertEq(ALICE.balance - before, GROSS, "withdrawal works while fully paused");
    }

    /*//////////////////////////////////////////////////////////////
                  TERMINAL BTC SETTLEMENT AND EXPIRY
    //////////////////////////////////////////////////////////////*/

    /// @notice Once a solver has reserved, every incident pause may be raised without turning the
    ///         controls into a way to strand an irreversible Bitcoin payment or its bond.
    function test_BtcSettlementCompletesWhileEveryIncidentPauseIsActive() public {
        bytes32 offerId = _createBtcOffer(rootA);
        _approveBtc(offerId, rootA);

        uint256 bond = d.solver.minimumBondWei();
        vm.prank(SOLVER);
        d.solver.reserve{value: bond}(offerId);

        _pauseEveryBtcDependency();

        PuppetTypes.BitcoinPaymentAttestation memory payment = _paymentAttestation(offerId);
        bytes[] memory signatures = attestors.sign(d.oracle.hashBitcoinPaymentAttestation(payment), 3);
        vm.prank(SOLVER);
        uint256 tokenId = d.solver.settle(offerId, payment, signatures);

        bytes32 rootKey = PuppetHashing.rootKey(rootA);
        assertEq(d.hoodPups.ownerOf(tokenId), ALICE, "reserved recipient receives the HoodPup");
        assertEq(d.escrow.activeBtcOfferForRoot(rootKey), bytes32(0), "Root mutex released atomically");
        assertEq(
            d.escrow.getOffer(offerId).status,
            uint8(PuppetTypes.OfferStatus.SETTLED),
            "escrow reaches its terminal state"
        );
        assertEq(
            d.solver.reservationOf(offerId).status,
            uint8(IBtcSolverSettlement.ReservationStatus.SETTLED),
            "bond record reaches its terminal state"
        );
        assertEq(d.payoutVault.claimable(SOLVER), bond + SELLER_WEI, "bond plus seller reimbursement");
        assertEq(d.payoutVault.claimable(BOB_PAYOUT), 0, "Bitcoin seller is not paid twice");
        assertEq(d.payoutVault.claimable(PUPPET_TREASURY), 0.25 ether, "Puppet treasury share");
        assertEq(d.payoutVault.claimable(PROTOCOL_TREASURY), 0.25 ether, "protocol treasury share");
        assertEq(d.payoutVault.totalLiability(), GROSS + bond, "every terminal wei remains exactly backed");
    }

    function test_OnlyOneBtcOfferForARootCanBeReserved() public {
        address rival = address(0x217A1);
        vm.deal(rival, 10 ether);

        bytes32 first = _createBtcOffer(rootA);
        _approveBtc(first, rootA);
        bytes32 second = _createBtcOfferFrom(rival, rootA);
        _approveBtc(second, rootA);

        uint256 bond = d.solver.minimumBondWei();
        vm.prank(SOLVER);
        d.solver.reserve{value: bond}(first);

        vm.prank(SOLVER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHoodPupOfferEscrow.RootReservationActive.selector, PuppetHashing.rootKey(rootA), first
            )
        );
        d.solver.reserve{value: bond}(second);

        assertEq(d.escrow.activeBtcOfferForRoot(PuppetHashing.rootKey(rootA)), first, "first reservation owns Root");
        assertEq(
            d.solver.reservationOf(second).status,
            uint8(IBtcSolverSettlement.ReservationStatus.NONE),
            "failed second reservation leaves no bond record"
        );
        assertEq(d.solver.totalActiveBondWei(), bond, "only one bond is active");
    }

    /// @notice The solver contract is the only reservation-expiry coordinator. It clears both
    ///         state machines, releases the Root mutex, distributes the bond and restores refunds.
    function test_BtcExpirySynchronizesBothStateMachinesWhilePaused() public {
        bytes32 offerId = _createBtcOffer(rootA);
        _approveBtc(offerId, rootA);

        uint256 bond = d.solver.minimumBondWei();
        vm.prank(SOLVER);
        d.solver.reserve{value: bond}(offerId);
        IBtcSolverSettlement.Reservation memory reservation = d.solver.reservationOf(offerId);

        _pauseEveryBtcDependency();
        vm.warp(uint256(reservation.reservationExpiry) + 1);
        d.solver.expireReservation(offerId);

        bytes32 rootKey = PuppetHashing.rootKey(rootA);
        assertEq(
            d.solver.reservationOf(offerId).status,
            uint8(IBtcSolverSettlement.ReservationStatus.EXPIRED),
            "solver state expired"
        );
        assertEq(
            d.escrow.getOffer(offerId).status, uint8(PuppetTypes.OfferStatus.BTC_APPROVED), "escrow state released"
        );
        assertEq(d.escrow.activeBtcOfferForRoot(rootKey), bytes32(0), "Root mutex released");
        assertEq(d.payoutVault.claimable(ALICE), bond / 2, "buyer receives configured slash share");
        assertEq(d.payoutVault.claimable(PROTOCOL_TREASURY), bond - (bond / 2), "slash conserves bond");

        PuppetTypes.Offer memory offer = d.escrow.getOffer(offerId);
        vm.warp(uint256(offer.expiry) + 1);
        d.escrow.refundExpired(offerId);
        assertEq(d.payoutVault.claimable(ALICE), GROSS + (bond / 2), "buyer can reclaim escrow while paused");
        assertEq(address(d.solver).balance, 0, "no bond residue");
        assertEq(address(d.escrow).balance, 0, "no escrow residue");
    }

    /*//////////////////////////////////////////////////////////////
                       REPLAY AND UNIQUENESS ACROSS CONTRACTS
    //////////////////////////////////////////////////////////////*/

    function test_AnAttestationCannotBeReplayed() public {
        bytes32 offerId = _createEvmOffer(rootA);
        PuppetTypes.OwnershipAttestation memory a = _ownershipAttestation(offerId, rootA);
        bytes32 digest = d.oracle.hashOwnershipAttestation(a);
        bytes[] memory sigs = attestors.sign(digest, 3);
        bytes32[] memory proof = MerkleFixture.proofForLeaf(leaves, PuppetHashing.collectionLeaf(rootA));

        vm.prank(RELAYER);
        d.escrow.settlePaidEvm(offerId, a, sigs, proof);

        // A second offer for the same Root, then the same attestation again: both the consumed
        // digest and the minted Root should stop it, independently.
        vm.prank(RELAYER);
        vm.expectRevert();
        d.escrow.settlePaidEvm(offerId, a, sigs, proof);

        assertTrue(d.oracle.isDigestConsumed(digest));
    }

    function test_QuorumIsEnforcedEndToEnd() public {
        bytes32 offerId = _createEvmOffer(rootA);
        PuppetTypes.OwnershipAttestation memory a = _ownershipAttestation(offerId, rootA);
        bytes32 digest = d.oracle.hashOwnershipAttestation(a);
        bytes32[] memory proof = MerkleFixture.proofForLeaf(leaves, PuppetHashing.collectionLeaf(rootA));

        // Signature sets are built BEFORE arming expectRevert. AttestorSet is a contract, so
        // building them inline would make an external call during argument evaluation — after the
        // expectation is armed — and that call's successful return consumes the expectation
        // instead of the settlement doing so.
        bytes[] memory tooFew = attestors.sign(digest, 2);
        bytes[] memory descending = attestors.signUnsorted(digest, 3);
        bytes[] memory withOutsider = attestors.signWithOutsider(digest, 2);
        bytes[] memory honest = attestors.sign(digest, 3);

        // Two of five is not a quorum.
        vm.prank(RELAYER);
        vm.expectRevert();
        d.escrow.settlePaidEvm(offerId, a, tooFew, proof);

        // Three valid signatures in descending order is not a quorum either — the oracle requires
        // strictly ascending recovered signers, which is what makes duplicates impossible.
        vm.prank(RELAYER);
        vm.expectRevert();
        d.escrow.settlePaidEvm(offerId, a, descending, proof);

        // A non-member signature cannot be laundered into an otherwise-valid set.
        vm.prank(RELAYER);
        vm.expectRevert();
        d.escrow.settlePaidEvm(offerId, a, withOutsider, proof);

        // The honest quorum still works.
        vm.prank(RELAYER);
        d.escrow.settlePaidEvm(offerId, a, honest, proof);
        assertTrue(d.hoodPups.rootMinted(PuppetHashing.rootKey(rootA)));
    }

    /// @notice The payout binding: an attacker cannot redirect the seller share.
    function test_PayoutAddressIsBoundToTheSignature() public {
        bytes32 offerId = _createEvmOffer(rootA);
        PuppetTypes.OwnershipAttestation memory honest = _ownershipAttestation(offerId, rootA);
        bytes32 honestDigest = d.oracle.hashOwnershipAttestation(honest);
        bytes[] memory sigs = attestors.sign(honestDigest, 3);
        bytes32[] memory proof = MerkleFixture.proofForLeaf(leaves, PuppetHashing.collectionLeaf(rootA));

        // Swap the payout address after the quorum signed. The digest changes, so the signatures
        // no longer recover to attestors and the quorum check fails.
        PuppetTypes.OwnershipAttestation memory tampered = honest;
        tampered.evmPayout = address(0xBADBAD);
        assertTrue(d.oracle.hashOwnershipAttestation(tampered) != honestDigest, "digest must change");

        vm.prank(RELAYER);
        vm.expectRevert();
        d.escrow.settlePaidEvm(offerId, tampered, sigs, proof);
    }

    /// @notice Sibling inscriptions are genuinely distinct Roots, all the way through settlement.
    function test_SiblingInscriptionsMintSeparateHoodPups() public {
        _settleEvm(_createEvmOffer(rootA), rootA);
        _settleEvm(_createEvmOffer(rootB), rootB);

        assertTrue(d.hoodPups.rootMinted(PuppetHashing.rootKey(rootA)));
        assertTrue(d.hoodPups.rootMinted(PuppetHashing.rootKey(rootB)));
        assertTrue(
            d.hoodPups.tokenOfRoot(PuppetHashing.rootKey(rootA)) != d.hoodPups.tokenOfRoot(PuppetHashing.rootKey(rootB))
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _createEvmOffer(PuppetTypes.RootId memory root) internal returns (bytes32) {
        return _createEvmOfferFrom(ALICE, root);
    }

    function _createBtcOffer(PuppetTypes.RootId memory root) internal returns (bytes32) {
        return _createBtcOfferFrom(ALICE, root);
    }

    function _createBtcOfferFrom(address buyer, PuppetTypes.RootId memory root) internal returns (bytes32) {
        bytes32[] memory proof = MerkleFixture.proofForLeaf(leaves, PuppetHashing.collectionLeaf(root));
        vm.prank(buyer);
        return
            d.escrow.createPaidBtcOffer{value: GROSS}(root, buyer, SELLER_SATS, uint64(block.timestamp + 7 days), proof);
    }

    function _approveBtc(bytes32 offerId, PuppetTypes.RootId memory root) internal {
        PuppetTypes.OwnershipAttestation memory a = _btcOwnershipAttestation(offerId, root);
        bytes[] memory signatures = attestors.sign(d.oracle.hashOwnershipAttestation(a), 3);
        bytes32[] memory proof = MerkleFixture.proofForLeaf(leaves, PuppetHashing.collectionLeaf(root));
        vm.prank(RELAYER);
        d.escrow.approvePaidBtc(offerId, a, signatures, proof);
    }

    function _pauseEveryBtcDependency() internal {
        d.escrow.grantRole(d.escrow.PAUSER_ROLE(), GUARDIAN);
        d.payoutVault.grantRole(d.payoutVault.PAUSER_ROLE(), GUARDIAN);
        d.oracle.grantRole(d.oracle.PAUSER_ROLE(), GUARDIAN);
        d.hoodPups.grantRole(d.hoodPups.PAUSER_ROLE(), GUARDIAN);
        d.solver.grantRole(d.solver.PAUSER_ROLE(), GUARDIAN);

        vm.startPrank(GUARDIAN);
        d.escrow.pauseSettlement();
        d.payoutVault.pause();
        d.oracle.pause();
        d.hoodPups.pauseMinting();
        d.solver.pause();
        vm.stopPrank();
    }

    function _createEvmOfferFrom(address buyer, PuppetTypes.RootId memory root) internal returns (bytes32) {
        bytes32[] memory proof = MerkleFixture.proofForLeaf(leaves, PuppetHashing.collectionLeaf(root));
        vm.prank(buyer);
        return d.escrow.createPaidEvmOffer{value: GROSS}(root, buyer, uint64(block.timestamp + 7 days), proof);
    }

    function _settleEvm(bytes32 offerId, PuppetTypes.RootId memory root) internal {
        PuppetTypes.OwnershipAttestation memory a = _ownershipAttestation(offerId, root);
        bytes[] memory sigs = attestors.sign(d.oracle.hashOwnershipAttestation(a), 3);
        bytes32[] memory proof = MerkleFixture.proofForLeaf(leaves, PuppetHashing.collectionLeaf(root));
        // Submitted by a relayer, not by Alice or Bob — neither should need gas to settle.
        vm.prank(RELAYER);
        d.escrow.settlePaidEvm(offerId, a, sigs, proof);
    }

    /// @dev Built from the offer the escrow actually stored, so a mismatch between what the escrow
    ///      recorded and what an attestor would sign shows up as a failing settlement.
    function _ownershipAttestation(bytes32 offerId, PuppetTypes.RootId memory root)
        internal
        view
        returns (PuppetTypes.OwnershipAttestation memory a)
    {
        PuppetTypes.Offer memory offer = d.escrow.getOffer(offerId);

        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT);
        a.rootTxid = root.inscriptionTxid;
        a.rootIndex = root.inscriptionIndex;
        a.contextId = offerId;
        a.offerTermsHash = offer.termsHash;
        a.currentOutpointHash = PuppetHashing.outpointHash(keccak256("bob-utxo"), 0);
        a.ownerScriptHash = keccak256(hex"5120aabbccddeeff00112233445566778899aabbccddeeff001122334455667788");
        a.bip322ProofHash = keccak256("bob-bip322-proof");
        a.buyer = offer.buyer;
        a.recipient = offer.recipient;
        a.payoutMode = uint8(PuppetTypes.PayoutMode.EVM);
        a.evmPayout = BOB_PAYOUT;
        a.grossWei = offer.grossWei;
        a.sellerWei = offer.sellerWei;
        a.bitcoinBlockHash = keccak256("bitcoin-tip");
        a.bitcoinHeight = 880_000;
        a.authorizationId = keccak256(abi.encode("auth", offerId));
        a.deadline = uint64(block.timestamp + 1 hours);
        a.attestorEpoch = d.attestorRegistry.attestorEpoch();
        a.policyVersion = d.attestorRegistry.policyVersion();
    }

    function _btcOwnershipAttestation(bytes32 offerId, PuppetTypes.RootId memory root)
        internal
        view
        returns (PuppetTypes.OwnershipAttestation memory a)
    {
        a = _ownershipAttestation(offerId, root);
        a.purpose = uint8(PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT);
        a.payoutMode = uint8(PuppetTypes.PayoutMode.BTC);
        a.evmPayout = address(0);
        a.btcPayoutScriptHash = BTC_PAYOUT_SCRIPT;
        a.sellerSats = SELLER_SATS;
    }

    function _paymentAttestation(bytes32 offerId)
        internal
        view
        returns (PuppetTypes.BitcoinPaymentAttestation memory a)
    {
        PuppetTypes.Offer memory offer = d.escrow.getOffer(offerId);
        a.contextId = offerId;
        a.ownershipDigest = offer.ownershipDigest;
        a.solver = SOLVER;
        a.bitcoinTxid = keccak256(abi.encode("integration-payment", offerId));
        a.outputIndex = 1;
        a.recipientScriptHash = offer.btcPayoutScriptHash;
        a.amountSats = offer.sellerSats;
        a.bitcoinBlockHash = keccak256("integration-payment-block");
        a.bitcoinHeight = 880_001;
        a.authorizationId = keccak256(abi.encode("integration-payment-auth", offerId));
        a.deadline = uint64(block.timestamp + 1 hours);
        a.attestorEpoch = d.attestorRegistry.attestorEpoch();
        a.policyVersion = d.attestorRegistry.policyVersion();
    }
}
