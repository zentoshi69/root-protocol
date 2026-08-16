// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {HoodPups} from "../../src/HoodPups.sol";
import {HoodPupsHandler} from "./handlers/HoodPupsHandler.sol";

/// @title HoodPupsInvariantTest
/// @notice Stateful campaign over the HoodPups collection.
/// @dev THE PROPERTY THIS FILE EXISTS FOR: `rootToToken` is injective. One canonical Bitcoin Puppet
///      inscription mints at most one HoodPup, ever, and no two token ids reference the same Root.
///      Everything else asserted here supports that claim or protects a holder's property while the
///      protocol is under stress.
///
///      HOW INJECTIVITY IS PROVEN IN BOTH DIRECTIONS FROM ONE LOOP: for every minted id the campaign
///      asserts `tokenOfRoot(rootKeyOf(id)) == id`. `tokenOfRoot` is a function of the key, so it can
///      return only one id per key. If two distinct ids `a != b` shared a key, the assertion would
///      necessarily fail for at least one of them. Walking every id therefore rules out both "one
///      Root mapped to two tokens" and "two tokens mapped to one Root" without a quadratic sweep.
///
///      HONESTY NOTE: this campaign proves properties of this contract's state machine. It proves
///      nothing about Bitcoin. The handler holds `MINTER_ROLE` and mints freely; in production that
///      role belongs to the escrow, which must first consume a 3-of-5 attestor quorum.
contract HoodPupsInvariantTest is StdInvariant, Test {
    HoodPups internal nft;
    HoodPupsHandler internal handler;

    /// @dev Stands in for the `TimelockController`. Holds `DEFAULT_ADMIN_ROLE`, so it is the only
    ///      party in the campaign that can unpause.
    address internal admin = makeAddr("timelockAdmin");

    function setUp() public {
        vm.warp(1_700_000_000);

        nft = new HoodPups(
            admin, "HoodPups", "HPUP", "https://meta.hoodpups.example/token/", "https://meta.hoodpups.example/c.json"
        );

        handler = new HoodPupsHandler(nft, admin);

        // The handler stands in for the escrow (mint) and the guardian (pause). It deliberately does
        // NOT receive `DEFAULT_ADMIN_ROLE`: unpausing must stay with the timelock even here, so the
        // campaign explores the same pause asymmetry production has.
        vm.startPrank(admin);
        nft.grantRole(nft.MINTER_ROLE(), address(handler));
        nft.grantRole(nft.PAUSER_ROLE(), address(handler));
        vm.stopPrank();

        // Only the handler is fuzzed; letting the campaign call `nft` directly would spend the whole
        // budget failing `AccessControl` checks instead of exploring the state machine.
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = HoodPupsHandler.mint.selector;
        selectors[1] = HoodPupsHandler.mintDuplicate.selector;
        selectors[2] = HoodPupsHandler.transfer.selector;
        selectors[3] = HoodPupsHandler.setUser.selector;
        selectors[4] = HoodPupsHandler.togglePause.selector;
        selectors[5] = HoodPupsHandler.warp.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /*//////////////////////////////////////////////////////////////
                               INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Every minted token maps to exactly one Root, and every Root to exactly one token.
    function invariant_RootToTokenIsInjective() public view {
        uint256 minted = nft.nextTokenId() - 1;

        for (uint256 tokenId = 1; tokenId <= minted; tokenId++) {
            bytes32 key = nft.rootKeyOf(tokenId);
            assertEq(nft.tokenOfRoot(key), tokenId, "root key resolves to a different token");
            assertTrue(nft.rootMinted(key), "minted token whose Root is not marked minted");
        }
    }

    /// @notice No token references the zero Root, and no minted Root can be un-minted.
    /// @dev A zero root key would mean a token exists with no inscription behind it — the state a
    ///      default-initialised `RootId` reaching the mint path would produce.
    function invariant_EveryMintedTokenHasNonzeroRootKey() public view {
        uint256 minted = nft.nextTokenId() - 1;

        for (uint256 tokenId = 1; tokenId <= minted; tokenId++) {
            assertTrue(nft.rootKeyOf(tokenId) != bytes32(0), "token with a zero root key");
            assertTrue(nft.rootOf(tokenId).inscriptionTxid != bytes32(0), "token with a zero reveal txid");
        }
    }

    /// @notice A Root that has minted can never mint again, however the calls are interleaved.
    /// @dev Deliberately does NOT assert that a duplicate has already been attempted. That is a
    ///      coverage claim, not an invariant: it is legitimately false immediately after the first
    ///      successful mint, and asserting it here made the campaign fail on a one-call sequence.
    ///      Coverage is instead guaranteed structurally by `test_HandlerActuallyProbesDuplicates`
    ///      below, and reported per campaign by `invariant_CallSummary`.
    function invariant_NoRootEverMintsTwice() public view {
        assertFalse(handler.duplicateMintSucceeded(), "a Root minted twice");
        assertEq(handler.mintCount(), nft.nextTokenId() - 1, "mint count and id counter disagree");
    }

    /// @notice `nextTokenId` only ever increases, so an id can never be reused.
    /// @dev Both halves are needed. The flag catches a decrease inside the action that caused it;
    ///      the comparison catches a decrease that some later action hid by writing a lower value.
    function invariant_NextTokenIdOnlyIncreases() public view {
        assertFalse(handler.nextTokenIdWentBackwards(), "nextTokenId decreased");
        assertGe(nft.nextTokenId(), handler.maxObservedNextTokenId(), "nextTokenId fell below a prior observation");
        assertGe(nft.nextTokenId(), 1, "ids must start at 1");
    }

    /// @notice Pausing never blocks an owner from moving their own token.
    /// @dev The protocol-wide rule is that a pause may block new risk-taking and nothing else. If a
    ///      future edit adds a pause check to `_update`, this fails.
    function invariant_PauseNeverBlocksTransfers() public view {
        assertFalse(handler.pauseBlockedATransfer(), "a pause blocked an owner's transfer");
    }

    /// @notice Ownership and balances stay coherent for every minted token.
    /// @dev Guards against the ERC-4907 `_update` override corrupting base ERC-721 accounting — the
    ///      one place this contract touches OpenZeppelin's transfer machinery.
    function invariant_EveryMintedTokenHasARealOwner() public view {
        uint256 minted = nft.nextTokenId() - 1;

        for (uint256 tokenId = 1; tokenId <= minted; tokenId++) {
            address owner = nft.ownerOf(tokenId);
            assertTrue(owner != address(0), "token with no owner");
            assertGt(nft.balanceOf(owner), 0, "owner with a zero balance");
        }
    }

    /*//////////////////////////////////////////////////////////////
                            CAMPAIGN SELF-CHECK
    //////////////////////////////////////////////////////////////*/

    /// @notice The handler's duplicate probe really does re-attempt a minted Root and really is
    ///         rejected — driven deterministically, so the invariants above can never be green
    ///         merely because the probe was silently doing nothing.
    /// @dev A stateful campaign is only as good as its handler. This is the guard against the
    ///      classic failure mode where an early `return` in an action makes every run vacuous.
    function test_HandlerActuallyProbesDuplicates() public {
        handler.mint(0, 0);
        assertEq(handler.mintCount(), 1, "the probe mint did not land");

        uint256 attemptsBefore = handler.duplicateAttempts();
        handler.mintDuplicate(0);

        assertEq(handler.duplicateAttempts(), attemptsBefore + 1, "no duplicate attempt was recorded");
        assertFalse(handler.duplicateMintSucceeded(), "the duplicate mint succeeded");
        assertEq(nft.nextTokenId(), 2, "the rejected duplicate consumed an id");
        assertEq(handler.mintCount(), 1, "the rejected duplicate was counted as a mint");
    }

    /// @notice Prints the action mix so a campaign that explored nothing is visible rather than green.
    function invariant_CallSummary() public view {
        console.log("mint            ", handler.callsMint());
        console.log("mintDuplicate   ", handler.callsDuplicate());
        console.log("transfer        ", handler.callsTransfer());
        console.log("setUser         ", handler.callsSetUser());
        console.log("togglePause     ", handler.callsPauseToggle());
        console.log("warp            ", handler.callsWarp());
        console.log("minted tokens   ", nft.nextTokenId() - 1);
        console.log("dup attempts    ", handler.duplicateAttempts());
    }
}
