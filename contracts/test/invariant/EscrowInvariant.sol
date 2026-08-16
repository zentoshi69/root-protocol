// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {FeeRouter} from "../../src/FeeRouter.sol";
import {HoodPupOfferEscrow} from "../../src/HoodPupOfferEscrow.sol";
import {HoodPups} from "../../src/HoodPups.sol";
import {PayoutVault} from "../../src/PayoutVault.sol";
import {PuppetCollectionRegistry} from "../../src/PuppetCollectionRegistry.sol";
import {RootOwnershipRegistry} from "../../src/RootOwnershipRegistry.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";

import {MerkleFixture} from "../helpers/MerkleFixture.sol";
import {MockOwnershipOracle} from "../mocks/MockOwnershipOracle.sol";
import {EscrowHandler} from "./handlers/EscrowHandler.sol";

/// @title EscrowInvariantTest
/// @notice Stateful campaign over `HoodPupOfferEscrow`'s offer lifecycle and its money.
/// @dev Read `EscrowHandler`'s honesty note first: the ownership oracle here is a mock, so this
///      campaign is evidence about the escrow's state machine and accounting, not about quorum
///      security. Every other contract in the loop is the production one, including the vault the
///      money actually lands in and the ERC-721 that enforces one-Root-one-HoodPup.
///
///      The handler holds `BTC_SETTLEMENT_ROLE`, `PAUSER_ROLE` and `DEFAULT_ADMIN_ROLE` on the
///      escrow, so every claim below is made against the most privileged actor the design allows.
contract EscrowInvariantTest is StdInvariant, Test {
    uint64 private constant MIN_DURATION = 1 hours;
    uint64 private constant MAX_DURATION = 30 days;
    uint256 private constant ROOT_COUNT = 12;

    address private admin = makeAddr("invariantAdmin");
    address private puppetTreasury = makeAddr("invariantPuppetTreasury");
    address private protocolTreasury = makeAddr("invariantProtocolTreasury");

    PuppetCollectionRegistry private collection;
    MockOwnershipOracle private oracle;
    PayoutVault private vault;
    HoodPups private nft;
    RootOwnershipRegistry private rootRegistry;
    FeeRouter private router;
    HoodPupOfferEscrow private escrow;
    EscrowHandler private handler;

    PuppetTypes.RootId[] private roots;
    bytes32[] private leaves;

    function setUp() public {
        vm.warp(1_700_000_000);

        for (uint256 i = 0; i < ROOT_COUNT; i++) {
            roots.push(
                PuppetTypes.RootId({
                    inscriptionTxid: keccak256(abi.encode("FIXTURE-NOT-REAL:invariant-reveal", i / 2)),
                    inscriptionIndex: uint32(i % 2)
                })
            );
        }
        PuppetTypes.RootId[] memory copy = _rootsMemory();
        bytes32[] memory built = MerkleFixture.leavesOf(copy);
        for (uint256 i = 0; i < built.length; i++) {
            leaves.push(built[i]);
        }

        collection = new PuppetCollectionRegistry(
            MerkleFixture.build(leaves), keccak256("invariant-manifest"), "escrow-invariant-v1", leaves.length
        );
        oracle = new MockOwnershipOracle();
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

        bytes32[][] memory proofs = new bytes32[][](ROOT_COUNT);
        for (uint256 i = 0; i < ROOT_COUNT; i++) {
            proofs[i] = MerkleFixture.proof(_leavesMemory(), i);
        }
        handler = new EscrowHandler(escrow, nft, vault, _rootsMemory(), proofs);

        bytes32 creditor = vault.CREDITOR_ROLE();
        bytes32 rootReleaser = vault.ROOT_RELEASER_ROLE();
        bytes32 minter = nft.MINTER_ROLE();
        bytes32 recorder = rootRegistry.MINT_RECORDER_ROLE();
        bytes32 routerCaller = router.ROUTER_CALLER_ROLE();
        bytes32 btcSettlement = escrow.BTC_SETTLEMENT_ROLE();
        bytes32 pauser = escrow.PAUSER_ROLE();
        bytes32 defaultAdmin = escrow.DEFAULT_ADMIN_ROLE();

        vm.startPrank(admin);
        vault.grantRole(creditor, address(router));
        vault.grantRole(creditor, address(escrow));
        vault.grantRole(rootReleaser, address(rootRegistry));
        nft.grantRole(minter, address(escrow));
        rootRegistry.grantRole(recorder, address(escrow));
        router.grantRole(routerCaller, address(escrow));
        // Deliberately maximal: the handler may pause, unpause, reserve, clear and finalize.
        escrow.grantRole(btcSettlement, address(handler));
        escrow.grantRole(pauser, address(handler));
        escrow.grantRole(defaultAdmin, address(handler));
        vm.stopPrank();

        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = EscrowHandler.createPaidEvm.selector;
        selectors[1] = EscrowHandler.createPaidBtc.selector;
        selectors[2] = EscrowHandler.createSelfCast.selector;
        selectors[3] = EscrowHandler.settlePaidEvm.selector;
        selectors[4] = EscrowHandler.settleSelfCast.selector;
        selectors[5] = EscrowHandler.approvePaidBtc.selector;
        selectors[6] = EscrowHandler.markBtcReserved.selector;
        selectors[7] = EscrowHandler.clearBtcReservation.selector;
        selectors[8] = EscrowHandler.expireBtcReservation.selector;
        selectors[9] = EscrowHandler.finalizeBtcSettlement.selector;
        selectors[10] = EscrowHandler.refundExpired.selector;
        selectors[11] = EscrowHandler.refundUnfillable.selector;
        selectors[12] = EscrowHandler.advanceTime.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function _rootsMemory() private view returns (PuppetTypes.RootId[] memory out) {
        out = new PuppetTypes.RootId[](roots.length);
        for (uint256 i = 0; i < roots.length; i++) {
            out[i] = roots[i];
        }
    }

    function _leavesMemory() private view returns (bytes32[] memory out) {
        out = new bytes32[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            out[i] = leaves[i];
        }
    }

    /*//////////////////////////////////////////////////////////////
                          MONEY CONSERVATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Every wei ever escrowed is either refunded, distributed, or still locked.
    /// @dev The headline claim of the whole contract. If this ever fails, either the escrow
    ///      invented money or it lost some.
    function invariant_EveryDepositedWeiIsAccountedFor() public view {
        assertEq(
            handler.ghostDeposited(),
            handler.ghostRefunded() + handler.ghostDistributed() + escrow.lockedEscrowWei(),
            "deposits != refunds + distributions + still-locked"
        );
    }

    /// @notice The escrow's balance is exactly the escrow it still owes.
    /// @dev The campaign never force-sends ETH, so this is equality rather than the weaker
    ///      `balance >= locked` that holds in production once a `selfdestruct` is possible.
    function invariant_EscrowHoldsNoUnaccountedEth() public view {
        assertEq(address(escrow).balance, escrow.lockedEscrowWei(), "escrow balance diverged from its obligations");
    }

    /// @notice Refunded and distributed value is all sitting in the vault, and the vault is solvent.
    function invariant_ReleasedValueIsAllInTheVault() public view {
        assertEq(
            address(vault).balance,
            handler.ghostRefunded() + handler.ghostDistributed(),
            "value left the escrow without reaching the vault"
        );
        assertGe(address(vault).balance, vault.totalLiability(), "vault insolvent");
        assertEq(vault.totalLiability(), address(vault).balance, "vault holds exactly what it owes");
    }

    /// @notice The escrow never claims to owe more than has ever been deposited.
    function invariant_LockedEscrowNeverExceedsDeposits() public view {
        assertLe(escrow.lockedEscrowWei(), handler.ghostDeposited(), "locked exceeds total deposits");
    }

    /// @notice The router is a pass-through and retains nothing between transactions.
    function invariant_RouterRetainsNothing() public view {
        assertEq(address(router).balance, 0, "router retained value");
    }

    /*//////////////////////////////////////////////////////////////
                            THE STATE MACHINE
    //////////////////////////////////////////////////////////////*/

    /// @notice No offer ever settles twice and no offer ever refunds twice.
    function invariant_NoOfferResolvesTwice() public view {
        uint256 n = handler.offerCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 id = handler.offerIds(i);
            assertLe(handler.ghostSettleCount(id), 1, "an offer settled more than once");
            assertLe(handler.ghostRefundCount(id), 1, "an offer refunded more than once");
            assertLe(
                handler.ghostSettleCount(id) + handler.ghostRefundCount(id), 1, "an offer both settled and refunded"
            );
        }
    }

    /// @notice Terminal statuses are sticky: SETTLED and REFUNDED never change again.
    function invariant_TerminalStatusesAreForever() public view {
        uint256 n = handler.offerCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 id = handler.offerIds(i);
            uint8 recorded = handler.ghostTerminalStatus(id);
            if (recorded == 0) continue;
            assertEq(escrow.getOffer(id).status, recorded, "a terminal offer changed status");
        }
    }

    /// @notice A settled offer never returns money to its buyer.
    function invariant_NoSettledOfferEverRefunds() public view {
        uint256 n = handler.offerCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 id = handler.offerIds(i);
            if (handler.ghostSettleCount(id) == 0) continue;
            assertEq(handler.ghostRefundCount(id), 0, "a settled offer was refunded");
            assertEq(escrow.getOffer(id).status, uint8(PuppetTypes.OfferStatus.SETTLED), "not SETTLED");
        }
    }

    /// @notice A BTC offer only ever mints through `finalizeBtcSettlement`.
    /// @dev The approval and reservation steps must move no money and mint nothing, so any
    ///      SETTLED BTC offer that was not finalized would mean an unpaid solver's mint happened.
    function invariant_NoBtcOfferSettlesWithoutFinalization() public view {
        uint256 n = handler.offerCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 id = handler.offerIds(i);
            PuppetTypes.Offer memory o = escrow.getOffer(id);
            if (o.kind != uint8(PuppetTypes.OfferKind.PAID_BTC)) continue;
            if (o.status != uint8(PuppetTypes.OfferStatus.SETTLED)) {
                assertFalse(handler.ghostFinalizedViaBtc(id), "finalized but not SETTLED");
                continue;
            }
            assertTrue(handler.ghostFinalizedViaBtc(id), "a BTC offer settled without finalization");
        }
    }

    /// @notice A reservation never outlives the offer it locks, and a reserved offer always names
    ///         a solver.
    /// @dev This is what guarantees the buyer can always escape: an expired offer therefore always
    ///      has a lapsed reservation, which anybody may release permissionlessly.
    function invariant_ReservationsAreAlwaysBoundedAndAttributed() public view {
        uint256 n = handler.offerCount();
        for (uint256 i = 0; i < n; i++) {
            PuppetTypes.Offer memory o = escrow.getOffer(handler.offerIds(i));
            if (o.status == uint8(PuppetTypes.OfferStatus.BTC_RESERVED)) {
                assertTrue(o.reservedSolver != address(0), "reserved with no solver");
                assertTrue(o.reservationExpiry != 0, "reserved with no window");
                assertLe(o.reservationExpiry, o.expiry, "a reservation outlived its offer");
            } else if (o.status != uint8(PuppetTypes.OfferStatus.SETTLED)) {
                // SETTLED deliberately preserves the reservation fields as the record of who was
                // paid; every other status must have them cleared.
                assertEq(o.reservedSolver, address(0), "a non-reserved offer names a solver");
                assertEq(o.reservationExpiry, 0, "a non-reserved offer carries a window");
            }
        }
    }

    /// @notice An offer's immutable terms are never rewritten after creation.
    function invariant_OfferTermsAreImmutable() public view {
        uint256 n = handler.offerCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 id = handler.offerIds(i);
            PuppetTypes.Offer memory o = escrow.getOffer(id);
            assertEq(
                o.termsHash,
                escrow.computeTermsHash(
                    id, o.kind, o.rootKey, o.buyer, o.recipient, o.grossWei, o.sellerWei, o.sellerSats, o.expiry
                ),
                "an offer's stored terms no longer hash to its stored commitment"
            );
            assertEq(o.sellerWei + o.treasuryWei + o.protocolWei, o.grossWei, "the stored split stopped conserving");
        }
    }

    /*//////////////////////////////////////////////////////////////
                             ROOT UNIQUENESS
    //////////////////////////////////////////////////////////////*/

    /// @notice One canonical Bitcoin Puppet inscription mints at most one HoodPup, ever.
    function invariant_OneRootMintsAtMostOnce() public view {
        uint256 minted;
        for (uint256 i = 0; i < handler.rootCount(); i++) {
            bytes32 key = handler.rootKeyAt(i);
            uint256 tokenId = nft.tokenOfRoot(key);
            if (tokenId == 0) {
                assertFalse(nft.rootMinted(key), "rootMinted disagrees with tokenOfRoot");
                continue;
            }
            minted++;
            assertTrue(nft.rootMinted(key), "rootMinted disagrees with tokenOfRoot");
            assertEq(nft.rootKeyOf(tokenId), key, "the token points back at a different Root");
        }
        // Token ids are sequential from 1 with no burn, so the number of minted Roots and the
        // number of tokens must agree exactly. A Root that minted twice would break this.
        assertEq(nft.nextTokenId(), minted + 1, "token count and minted-Root count disagree");
    }

    /// @notice At most one offer per Root ever reaches SETTLED.
    function invariant_AtMostOneOfferPerRootSettles() public view {
        uint256 n = handler.offerCount();
        for (uint256 i = 0; i < handler.rootCount(); i++) {
            bytes32 key = handler.rootKeyAt(i);
            uint256 settled;
            for (uint256 j = 0; j < n; j++) {
                bytes32 id = handler.offerIds(j);
                PuppetTypes.Offer memory o = escrow.getOffer(id);
                if (o.rootKey == key && o.status == uint8(PuppetTypes.OfferStatus.SETTLED)) settled++;
            }
            assertLe(settled, 1, "two competing offers both settled the same Root");
        }
    }

    /*//////////////////////////////////////////////////////////////
                          COVERAGE (NOT AN INVARIANT)
    //////////////////////////////////////////////////////////////*/

    /// @notice Proof that the campaign actually reaches the interesting states.
    /// @dev Deliberately a deterministic test rather than an invariant. A coverage claim is
    ///      legitimately false on a shrunk single-call sequence, so asserting it as an invariant
    ///      would make the campaign fail for a reason that is not a bug.
    function test_HandlerReachesEveryInterestingState() public {
        // One offer of each kind, each on its OWN Root, so no kind can steal another's mint.
        // Indices: EVM at 3i, BTC at 3i+1, self-cast at 3i+2.
        for (uint256 i = 0; i < 4; i++) {
            handler.createPaidEvm(i, i, 1 ether + i, i);
            handler.createPaidBtc(i + 1, 4 + i, 2 ether + i, i);
            handler.createSelfCast(i + 2, 8 + i, i);
        }
        // A competing offer on every Root, so the unfillable-refund path has real losers.
        for (uint256 i = 0; i < 12; i++) {
            handler.createPaidEvm(2, i, 3 ether + i, i);
        }
        assertEq(handler.offerCount(), 24, "24 offers created");

        for (uint256 i = 0; i < 4; i++) {
            handler.approvePaidBtc(3 * i + 1);
            handler.markBtcReserved(3 * i + 1, i, i);
        }
        // Three finalize; the fourth is deliberately left to lapse so the permissionless
        // reservation-expiry path is exercised too.
        for (uint256 i = 0; i < 3; i++) {
            handler.finalizeBtcSettlement(3 * i + 1);
        }
        for (uint256 i = 0; i < 4; i++) {
            handler.settlePaidEvm(3 * i);
            handler.settleSelfCast(3 * i + 2);
        }

        for (uint256 i = 0; i < 6; i++) {
            handler.advanceTime(type(uint256).max);
        }
        handler.expireBtcReservation(10);
        for (uint256 i = 12; i < 24; i++) {
            handler.refundUnfillable(i);
        }
        for (uint256 i = 0; i < 24; i++) {
            handler.refundExpired(i);
        }

        assertGt(handler.offerCount(), 20, "created a meaningful number of offers");
        assertGt(handler.settlementsSeen(), 0, "settled something");
        assertGt(handler.btcFinalizationsSeen(), 0, "finalized a BTC offer");
        assertGt(handler.reservationsSeen(), 0, "reserved something");
        assertGt(handler.expiredReservationsSeen(), 0, "let a reservation lapse and released it");
        assertGt(handler.refundsSeen(), 0, "refunded something");
        assertGt(handler.unfillableRefundsSeen(), 0, "exercised the competing-offer refund");

        // And the accounting still balances after that whole sequence.
        assertEq(
            handler.ghostDeposited(),
            handler.ghostRefunded() + handler.ghostDistributed() + escrow.lockedEscrowWei(),
            "conservation after the scripted sequence"
        );
    }
}
