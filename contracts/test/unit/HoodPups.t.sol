// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {HoodPups} from "../../src/HoodPups.sol";
import {IERC4907, IHoodPups} from "../../src/interfaces/IHoodPups.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";
import {MockERC721Receiver} from "../mocks/Receivers.sol";

/// @notice A contract with no fallback and no `onERC721Received`.
/// @dev TEST-ONLY. `Receivers.sol` has no such variant: `RejectingReceiver` has a reverting
///      `fallback`, which bubbles ITS error rather than OpenZeppelin's `ERC721InvalidReceiver`. This
///      one reverts with empty return data, which is the case that exercises the "receiver is not
///      ERC-721 aware at all" branch of `_checkOnERC721Received`.
contract NonReceiver {}

/// @title HoodPupsTest
/// @notice Unit suite for the production HoodPups ERC-721.
/// @dev The properties under test here are the ones the protocol's central promise rests on:
///      one Root mints at most one token forever, ids are unambiguous, pausing cannot touch a
///      token a user already holds, and metadata can be locked beyond governance's reach.
///
///      HONESTY NOTE: nothing in this file verifies any Bitcoin fact. `minter` is simply an address
///      holding `MINTER_ROLE`, standing in for the escrow that would, in production, have consumed a
///      3-of-5 attestor quorum before calling. A green suite here proves this contract's rules, not
///      that any inscription was really controlled by anyone.
contract HoodPupsTest is Test {
    /*//////////////////////////////////////////////////////////////
                                FIXTURES
    //////////////////////////////////////////////////////////////*/

    HoodPups internal nft;

    /// @dev Stands in for the `TimelockController` that holds governance in production.
    address internal admin = makeAddr("timelockAdmin");
    /// @dev Stands in for the guardian multisig: may pause, may never unpause.
    address internal guardian = makeAddr("guardian");
    /// @dev Stands in for `HoodPupOfferEscrow`, the only holder of `MINTER_ROLE`.
    address internal minter = makeAddr("escrowMinter");
    /// @dev Stands in for `TourEngine`, the only holder of `TOUR_ENGINE_ROLE`.
    address internal tourEngine = makeAddr("tourEngine");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal stranger = makeAddr("stranger");

    string internal constant NAME = "HoodPups";
    string internal constant SYMBOL = "HPUP";
    string internal constant BASE_URI = "https://meta.hoodpups.example/token/";
    string internal constant CONTRACT_URI = "https://meta.hoodpups.example/collection.json";

    /// @dev ERC-4907's canonical ERC-165 identifier, pinned as a literal so a refactor of the
    ///      interface file that changed a selector would fail here rather than silently ship a
    ///      collection that marketplaces no longer recognise as rentable.
    bytes4 internal constant ERC4907_INTERFACE_ID = 0xad092b5c;
    /// @dev `IERC721Enumerable`. This contract must never advertise it.
    bytes4 internal constant ERC721_ENUMERABLE_INTERFACE_ID = 0x780e9d63;

    /// @dev `keccak256("UpdateUser(uint256,address,uint64)")`, used for absence assertions.
    bytes32 internal constant UPDATE_USER_TOPIC = keccak256("UpdateUser(uint256,address,uint64)");

    /*//////////////////////////////////////////////////////////////
                             CACHED ROLE IDS
    //////////////////////////////////////////////////////////////*/

    /// @dev Read once in `setUp` and reused everywhere.
    ///      WHY THIS EXISTS: `vm.expectRevert` binds to the very next call, and arguments are
    ///      evaluated AFTER it is armed, so encoding an expectation with a live `nft.MINTER_ROLE()`
    ///      call inside it aims the expectation at that getter, which of course does not revert.
    ///      That mistake caused a real failure while writing this suite, so every role id is hoisted
    ///      out of every expectation instead.
    bytes32 internal DEFAULT_ADMIN;
    bytes32 internal MINTER;
    bytes32 internal TOUR_ENGINE;
    bytes32 internal METADATA_ADMIN;
    bytes32 internal PAUSER;

    function setUp() public {
        // A realistic wall-clock timestamp, so expiry arithmetic is not run against genesis.
        vm.warp(1_700_000_000);

        nft = new HoodPups(admin, NAME, SYMBOL, BASE_URI, CONTRACT_URI);

        DEFAULT_ADMIN = nft.DEFAULT_ADMIN_ROLE();
        MINTER = nft.MINTER_ROLE();
        TOUR_ENGINE = nft.TOUR_ENGINE_ROLE();
        METADATA_ADMIN = nft.METADATA_ADMIN_ROLE();
        PAUSER = nft.PAUSER_ROLE();

        vm.startPrank(admin);
        nft.grantRole(MINTER, minter);
        nft.grantRole(TOUR_ENGINE, tourEngine);
        nft.grantRole(PAUSER, guardian);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Deterministic, distinct inscription identity per `salt`.
    function _root(uint256 salt) internal pure returns (PuppetTypes.RootId memory) {
        return PuppetTypes.RootId({
            inscriptionTxid: keccak256(abi.encode("inscription-reveal-txid", salt)), inscriptionIndex: uint32(salt)
        });
    }

    function _mint(address to, uint256 salt) internal returns (uint256 tokenId) {
        vm.prank(minter);
        tokenId = nft.mintRooted(to, _root(salt));
    }

    /// @dev True if any recorded log is an ERC-4907 `UpdateUser`.
    function _sawUpdateUser(Vm.Log[] memory logs) internal view returns (bool) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(nft) && logs[i].topics.length > 0 && logs[i].topics[0] == UPDATE_USER_TOPIC)
            {
                return true;
            }
        }
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice A zero admin would deploy a collection nobody can ever administer.
    function test_ConstructorRejectsZeroAdmin() public {
        vm.expectRevert(IHoodPups.ZeroAddress.selector);
        new HoodPups(address(0), NAME, SYMBOL, BASE_URI, CONTRACT_URI);
    }

    /// @notice Genesis state: ids start at 1, nothing is paused, nothing is frozen.
    function test_ConstructorSetsGenesisState() public view {
        assertEq(nft.name(), NAME, "name");
        assertEq(nft.symbol(), SYMBOL, "symbol");
        assertEq(nft.nextTokenId(), 1, "ids start at 1");
        assertFalse(nft.mintingPaused(), "not paused at genesis");
        assertFalse(nft.metadataFrozen(), "not frozen at genesis");
        assertEq(nft.baseTokenURI(), BASE_URI, "base uri");
        assertEq(nft.contractURI(), CONTRACT_URI, "contract uri");
    }

    /// @notice Governance roles are granted; the two protocol roles deliberately are not.
    /// @dev `MINTER_ROLE` and `TOUR_ENGINE_ROLE` belong to contracts deployed after this one. If the
    ///      constructor pre-granted either to the deployer, the deployment would pass through a state
    ///      in which an EOA could mint — exactly what the role handover is designed to prevent.
    function test_ConstructorGrantsOnlyGovernanceRoles() public view {
        assertTrue(nft.hasRole(DEFAULT_ADMIN, admin), "admin");
        assertTrue(nft.hasRole(METADATA_ADMIN, admin), "metadata admin");
        assertTrue(nft.hasRole(PAUSER, admin), "pauser");

        assertFalse(nft.hasRole(MINTER, admin), "admin must not mint");
        assertFalse(nft.hasRole(TOUR_ENGINE, admin), "admin must not be tour engine");
        assertFalse(nft.hasRole(DEFAULT_ADMIN, address(this)), "deployer holds nothing");
    }

    /// @notice Genesis emits both URI events with an empty `previous` so indexers need no special case.
    function test_ConstructorEmitsGenesisEvents() public {
        vm.expectEmit(false, false, false, true);
        emit IHoodPups.BaseURIUpdated("", BASE_URI);
        vm.expectEmit(false, false, false, true);
        emit IHoodPups.ContractURIUpdated("", CONTRACT_URI);
        vm.expectEmit(true, false, false, true);
        emit HoodPups.HoodPupsInitialized(admin, NAME, SYMBOL, 1);

        new HoodPups(admin, NAME, SYMBOL, BASE_URI, CONTRACT_URI);
    }

    /*//////////////////////////////////////////////////////////////
                                  MINT
    //////////////////////////////////////////////////////////////*/

    /// @notice The authorized mint path writes every lookup consistently and emits `RootedMint`.
    function test_MintRootedByMinter() public {
        PuppetTypes.RootId memory root = _root(1);
        bytes32 key = PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);

        vm.expectEmit(true, true, true, true);
        emit IHoodPups.RootedMint(1, key, alice, root.inscriptionTxid, root.inscriptionIndex);

        vm.prank(minter);
        uint256 tokenId = nft.mintRooted(alice, root);

        assertEq(tokenId, 1, "first id");
        assertEq(nft.ownerOf(tokenId), alice, "owner");
        assertEq(nft.balanceOf(alice), 1, "balance");
        assertEq(nft.nextTokenId(), 2, "next id advanced");
        assertTrue(nft.rootMinted(key), "root marked minted");
        assertEq(nft.tokenOfRoot(key), tokenId, "root -> token");
        assertEq(nft.rootKeyOf(tokenId), key, "token -> key");
        assertEq(nft.rootOf(tokenId).inscriptionTxid, root.inscriptionTxid, "txid");
        assertEq(nft.rootOf(tokenId).inscriptionIndex, root.inscriptionIndex, "index");
    }

    /// @notice Nobody without `MINTER_ROLE` can mint — including full governance.
    function test_MintRootedRevertsForUnauthorizedCaller() public {
        bytes32 role = MINTER;

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, role)
        );
        vm.prank(stranger);
        nft.mintRooted(alice, _root(1));

        // The timelock admin can grant `MINTER_ROLE`, which is a visible, delayed action. It cannot
        // shortcut that and mint directly.
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, role));
        vm.prank(admin);
        nft.mintRooted(alice, _root(1));
    }

    /// @notice THE central promise: one canonical inscription mints at most one HoodPup, ever.
    function test_MintRootedRevertsOnSecondMintOfSameRoot() public {
        PuppetTypes.RootId memory root = _root(7);
        bytes32 key = PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);

        vm.prank(minter);
        uint256 tokenId = nft.mintRooted(alice, root);

        // Same recipient.
        vm.expectRevert(abi.encodeWithSelector(IHoodPups.RootAlreadyMinted.selector, key, tokenId));
        vm.prank(minter);
        nft.mintRooted(alice, root);

        // Different recipient — the rule is about the Root, not about who is asking.
        vm.expectRevert(abi.encodeWithSelector(IHoodPups.RootAlreadyMinted.selector, key, tokenId));
        vm.prank(minter);
        nft.mintRooted(bob, root);

        // Still true after the token has changed hands.
        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);
        vm.expectRevert(abi.encodeWithSelector(IHoodPups.RootAlreadyMinted.selector, key, tokenId));
        vm.prank(minter);
        nft.mintRooted(carol, root);

        assertEq(nft.nextTokenId(), 2, "no failed attempt consumed an id");
    }

    /// @notice Two inscriptions revealed by the same Bitcoin transaction are different Roots.
    function test_DifferentInscriptionIndexIsADifferentRoot() public {
        bytes32 txid = keccak256("shared-reveal-transaction");
        PuppetTypes.RootId memory first = PuppetTypes.RootId({inscriptionTxid: txid, inscriptionIndex: 0});
        PuppetTypes.RootId memory second = PuppetTypes.RootId({inscriptionTxid: txid, inscriptionIndex: 1});

        vm.startPrank(minter);
        uint256 firstId = nft.mintRooted(alice, first);
        uint256 secondId = nft.mintRooted(bob, second);
        vm.stopPrank();

        assertEq(firstId, 1, "first id");
        assertEq(secondId, 2, "second id");
        assertTrue(nft.rootKeyOf(firstId) != nft.rootKeyOf(secondId), "keys differ");
        assertEq(nft.ownerOf(firstId), alice, "first owner");
        assertEq(nft.ownerOf(secondId), bob, "second owner");
    }

    /// @notice Ids are assigned strictly sequentially from 1, with no gaps and no reuse.
    function test_TokenIdsAreSequentialFromOne() public {
        for (uint256 i = 1; i <= 5; i++) {
            uint256 id = _mint(alice, i);
            assertEq(id, i, "sequential id");
            assertEq(nft.nextTokenId(), i + 1, "next id");
        }
    }

    /// @notice Minting to the zero address is rejected before any state is written.
    function test_MintRootedRejectsZeroRecipient() public {
        vm.expectRevert(IHoodPups.ZeroAddress.selector);
        vm.prank(minter);
        nft.mintRooted(address(0), _root(1));

        assertEq(nft.nextTokenId(), 1, "no id consumed");
    }

    /// @notice A zero reveal txid is a default-initialised struct, not an inscription.
    function test_MintRootedRejectsZeroTxid() public {
        PuppetTypes.RootId memory empty = PuppetTypes.RootId({inscriptionTxid: bytes32(0), inscriptionIndex: 0});

        vm.expectRevert(HoodPups.ZeroRootTxid.selector);
        vm.prank(minter);
        nft.mintRooted(alice, empty);

        assertEq(nft.nextTokenId(), 1, "no id consumed");
        assertFalse(nft.rootMinted(PuppetHashing.rootKey(bytes32(0), 0)), "no slot burned");
    }

    /// @notice Unminted Roots answer "not minted" without reverting.
    function test_LookupsForUnmintedRootAreZero() public view {
        bytes32 key = PuppetHashing.rootKey(_root(99).inscriptionTxid, _root(99).inscriptionIndex);
        assertFalse(nft.rootMinted(key), "not minted");
        assertEq(nft.tokenOfRoot(key), 0, "zero token id");
    }

    /// @notice Token-keyed identity views revert rather than returning a plausible zeroed struct.
    function test_RootViewsRevertForUnknownToken() public {
        _mint(alice, 1);

        vm.expectRevert(abi.encodeWithSelector(IHoodPups.UnknownToken.selector, uint256(0)));
        nft.rootOf(0);

        vm.expectRevert(abi.encodeWithSelector(IHoodPups.UnknownToken.selector, uint256(2)));
        nft.rootOf(2);

        vm.expectRevert(abi.encodeWithSelector(IHoodPups.UnknownToken.selector, uint256(2)));
        nft.rootKeyOf(2);
    }

    /// @notice The contract's key derivation is `PuppetHashing.rootKey`, not a local re-implementation.
    function test_RootKeyOfMatchesSharedHashingLibrary() public {
        PuppetTypes.RootId memory root = _root(3);
        uint256 tokenId = _mint(alice, 3);

        assertEq(nft.rootKeyOf(tokenId), PuppetHashing.rootKey(root), "matches library overload");
        assertEq(
            nft.rootKeyOf(tokenId),
            keccak256(abi.encode(PuppetHashing.COLLECTION_ID, root.inscriptionTxid, root.inscriptionIndex)),
            "matches the documented preimage"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              SAFE MINTING
    //////////////////////////////////////////////////////////////*/

    /// @notice A well-behaved contract recipient receives the callback with the right arguments.
    function test_SafeMintReachesAcceptingReceiver() public {
        MockERC721Receiver receiver = new MockERC721Receiver(MockERC721Receiver.Behaviour.ACCEPT);

        vm.prank(minter);
        uint256 tokenId = nft.mintRooted(address(receiver), _root(1));

        assertEq(nft.ownerOf(tokenId), address(receiver), "owner");
        assertEq(receiver.receivedCount(), 1, "callback ran");
        // `_safeMint` reports `_msgSender()` as the operator, i.e. the escrow that called
        // `mintRooted` — not the collection contract.
        assertEq(receiver.lastOperator(), minter, "operator is the minting caller");
        assertEq(receiver.lastFrom(), address(0), "from is zero on a mint");
        assertEq(receiver.lastTokenId(), tokenId, "token id");
    }

    /// @notice A receiver that reverts aborts the whole mint, and its error is bubbled unchanged.
    /// @dev Failing loudly matters more here than in a normal collection: a Root can only mint once,
    ///      so a token stranded at an address that cannot move it would be unrecoverable forever.
    function test_MintRevertsWhenReceiverReverts() public {
        MockERC721Receiver receiver = new MockERC721Receiver(MockERC721Receiver.Behaviour.REVERT_ON_RECEIVE);

        vm.expectRevert(MockERC721Receiver.ReceiverRejected.selector);
        vm.prank(minter);
        nft.mintRooted(address(receiver), _root(1));

        assertEq(nft.nextTokenId(), 1, "the whole mint reverted, no id consumed");
        assertFalse(nft.rootMinted(PuppetHashing.rootKey(_root(1))), "root is still mintable");
    }

    /// @notice A receiver returning the wrong magic value is rejected.
    function test_MintRevertsWhenReceiverReturnsWrongSelector() public {
        MockERC721Receiver receiver = new MockERC721Receiver(MockERC721Receiver.Behaviour.WRONG_SELECTOR);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(receiver)));
        vm.prank(minter);
        nft.mintRooted(address(receiver), _root(1));
    }

    /// @notice A contract that is not ERC-721 aware at all is rejected.
    function test_MintRevertsForNonReceiverContract() public {
        NonReceiver plain = new NonReceiver();

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(plain)));
        vm.prank(minter);
        nft.mintRooted(address(plain), _root(1));
    }

    /*//////////////////////////////////////////////////////////////
                               TRANSFERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Ordinary transfers work and leave the Root binding untouched.
    function test_TransferMovesOwnershipAndKeepsRootBinding() public {
        uint256 tokenId = _mint(alice, 1);
        bytes32 key = nft.rootKeyOf(tokenId);

        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);

        assertEq(nft.ownerOf(tokenId), bob, "new owner");
        assertEq(nft.balanceOf(alice), 0, "old balance");
        assertEq(nft.balanceOf(bob), 1, "new balance");
        assertEq(nft.rootKeyOf(tokenId), key, "root binding is immutable");
        assertEq(nft.tokenOfRoot(key), tokenId, "reverse lookup unchanged");
    }

    /// @notice An approved operator can move a token, as ERC-721 requires.
    function test_ApprovedOperatorCanTransfer() public {
        uint256 tokenId = _mint(alice, 1);

        vm.prank(alice);
        nft.setApprovalForAll(carol, true);

        vm.prank(carol);
        nft.safeTransferFrom(alice, bob, tokenId);

        assertEq(nft.ownerOf(tokenId), bob, "operator transfer");
    }

    /*//////////////////////////////////////////////////////////////
                             MINT PAUSING
    //////////////////////////////////////////////////////////////*/

    /// @notice Pausing blocks minting and NOTHING else. This is the row of the pause table that
    ///         matters most: a holder's property must not depend on the protocol's operational state.
    function test_PauseBlocksMintingOnly() public {
        uint256 tokenId = _mint(alice, 1);

        vm.expectEmit(false, false, false, true);
        emit IHoodPups.MintingPauseUpdated(true);
        vm.prank(guardian);
        nft.pauseMinting();
        assertTrue(nft.mintingPaused(), "paused");

        vm.expectRevert(IHoodPups.MintingPaused.selector);
        vm.prank(minter);
        nft.mintRooted(bob, _root(2));

        // Everything a holder can do must still work.
        vm.prank(alice);
        nft.approve(carol, tokenId);
        assertEq(nft.getApproved(tokenId), carol, "approve works while paused");

        vm.prank(alice);
        nft.setUser(tokenId, bob, uint64(block.timestamp + 1 days));
        assertEq(nft.userOf(tokenId), bob, "setUser works while paused");

        vm.prank(carol);
        nft.transferFrom(alice, carol, tokenId);
        assertEq(nft.ownerOf(tokenId), carol, "transfer works while paused");

        // Views keep answering.
        assertEq(nft.tokenOfRoot(nft.rootKeyOf(tokenId)), tokenId, "views work while paused");
        assertEq(nft.tokenURI(tokenId), string.concat(BASE_URI, "1"), "tokenURI works while paused");
    }

    /// @notice The guardian may pause and may never unpause; the timelock admin does the reverse.
    /// @dev The asymmetry is the whole design: a compromised guardian can only cost liveness.
    function test_GuardianCanPauseButNeverUnpause() public {
        vm.prank(guardian);
        nft.pauseMinting();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, guardian, DEFAULT_ADMIN)
        );
        vm.prank(guardian);
        nft.unpauseMinting();

        assertTrue(nft.mintingPaused(), "still paused");

        vm.expectEmit(false, false, false, true);
        emit IHoodPups.MintingPauseUpdated(false);
        vm.prank(admin);
        nft.unpauseMinting();

        assertFalse(nft.mintingPaused(), "unpaused by the timelock");

        uint256 tokenId = _mint(alice, 5);
        assertEq(nft.ownerOf(tokenId), alice, "minting resumed");
    }

    /// @notice A repeated pause or unpause reverts rather than emitting a duplicate event.
    function test_PauseNoOpsRevert() public {
        vm.expectRevert(abi.encodeWithSelector(HoodPups.MintPauseUnchanged.selector, false));
        vm.prank(admin);
        nft.unpauseMinting();

        vm.prank(guardian);
        nft.pauseMinting();

        vm.expectRevert(abi.encodeWithSelector(HoodPups.MintPauseUnchanged.selector, true));
        vm.prank(guardian);
        nft.pauseMinting();
    }

    /// @notice Pausing is role gated.
    function test_PauseRequiresPauserRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, PAUSER)
        );
        vm.prank(stranger);
        nft.pauseMinting();
    }

    /*//////////////////////////////////////////////////////////////
                                ERC-4907
    //////////////////////////////////////////////////////////////*/

    /// @notice The owner can grant temporary use rights, and the term is readable.
    function test_SetUserByOwner() public {
        uint256 tokenId = _mint(alice, 1);
        uint64 expires = uint64(block.timestamp + 7 days);

        vm.expectEmit(true, true, false, true);
        emit IERC4907.UpdateUser(tokenId, bob, expires);
        vm.prank(alice);
        nft.setUser(tokenId, bob, expires);

        assertEq(nft.userOf(tokenId), bob, "user");
        assertEq(nft.userExpires(tokenId), expires, "expiry");
        assertEq(nft.ownerOf(tokenId), alice, "ownership is untouched by a rental");
    }

    /// @notice `userOf` goes to zero once the term elapses; the raw expiry stays readable.
    function test_UserLapsesAtExpiry() public {
        uint256 tokenId = _mint(alice, 1);
        uint64 expires = uint64(block.timestamp + 1 days);

        vm.prank(alice);
        nft.setUser(tokenId, bob, expires);

        vm.warp(expires);
        assertEq(nft.userOf(tokenId), bob, "still live in the expiry block itself");

        vm.warp(uint256(expires) + 1);
        assertEq(nft.userOf(tokenId), address(0), "lapsed");
        assertEq(nft.userExpires(tokenId), expires, "raw expiry still readable for UIs");
    }

    /// @notice An operator approved for all tokens may set the user.
    function test_SetUserByApprovedForAllOperator() public {
        uint256 tokenId = _mint(alice, 1);

        vm.prank(alice);
        nft.setApprovalForAll(carol, true);

        vm.prank(carol);
        nft.setUser(tokenId, bob, uint64(block.timestamp + 1 days));

        assertEq(nft.userOf(tokenId), bob, "operator set the user");
    }

    /// @notice The single-token approved address may set the user.
    function test_SetUserBySingleTokenApproval() public {
        uint256 tokenId = _mint(alice, 1);

        vm.prank(alice);
        nft.approve(carol, tokenId);

        vm.prank(carol);
        nft.setUser(tokenId, bob, uint64(block.timestamp + 1 days));

        assertEq(nft.userOf(tokenId), bob, "approved address set the user");
    }

    /// @notice A stranger cannot set the user.
    function test_SetUserRevertsForStranger() public {
        uint256 tokenId = _mint(alice, 1);

        vm.expectRevert(abi.encodeWithSelector(IHoodPups.NotOwnerNorApproved.selector, stranger, tokenId));
        vm.prank(stranger);
        nft.setUser(tokenId, stranger, uint64(block.timestamp + 1 days));
    }

    /// @notice `TOUR_ENGINE_ROLE` can set the user without any ERC-721 approval — and that is the
    ///         point: the tour engine must never need transfer rights to run a tour.
    function test_TourEngineRoleCanSetUserWithoutApproval() public {
        uint256 tokenId = _mint(alice, 1);
        uint64 expires = uint64(block.timestamp + 3 days);

        vm.prank(tourEngine);
        nft.setUser(tokenId, bob, expires);

        assertEq(nft.userOf(tokenId), bob, "tour engine set the user");

        // The narrow role confers nothing else.
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, tourEngine, tokenId));
        vm.prank(tourEngine);
        nft.transferFrom(alice, tourEngine, tokenId);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, tourEngine, MINTER)
        );
        vm.prank(tourEngine);
        nft.mintRooted(bob, _root(2));
    }

    /// @notice Naming the owner as user is always a mistake and is rejected.
    function test_SetUserRevertsWhenUserIsOwner() public {
        uint256 tokenId = _mint(alice, 1);

        vm.expectRevert(IHoodPups.UserIsOwner.selector);
        vm.prank(alice);
        nft.setUser(tokenId, alice, uint64(block.timestamp + 1 days));
    }

    /// @notice A term that is already over on arrival is rejected loudly.
    function test_SetUserRevertsForExpiryInPast() public {
        uint256 tokenId = _mint(alice, 1);

        vm.expectRevert(
            abi.encodeWithSelector(IHoodPups.ExpiryInPast.selector, uint64(block.timestamp), block.timestamp)
        );
        vm.prank(alice);
        nft.setUser(tokenId, bob, uint64(block.timestamp));

        vm.expectRevert(
            abi.encodeWithSelector(IHoodPups.ExpiryInPast.selector, uint64(block.timestamp - 1), block.timestamp)
        );
        vm.prank(alice);
        nft.setUser(tokenId, bob, uint64(block.timestamp - 1));
    }

    /// @notice Clearing with the zero address normalises the expiry rather than reverting.
    function test_ClearUserWithZeroAddress() public {
        uint256 tokenId = _mint(alice, 1);

        vm.prank(alice);
        nft.setUser(tokenId, bob, uint64(block.timestamp + 1 days));

        vm.expectEmit(true, true, false, true);
        emit IERC4907.UpdateUser(tokenId, address(0), 0);
        vm.prank(alice);
        // A stale nonzero expiry is silently normalised to zero: with no user it can have no effect.
        nft.setUser(tokenId, address(0), uint64(block.timestamp + 999 days));

        assertEq(nft.userOf(tokenId), address(0), "cleared");
        assertEq(nft.userExpires(tokenId), 0, "expiry normalised to zero");
    }

    /// @notice `setUser` on a token that does not exist reverts.
    function test_SetUserRevertsForUnknownToken() public {
        vm.expectRevert(abi.encodeWithSelector(IHoodPups.UnknownToken.selector, uint256(1)));
        vm.prank(alice);
        nft.setUser(1, bob, uint64(block.timestamp + 1 days));
    }

    /// @notice The ERC-4907 views never revert, so integrators need no try/catch.
    function test_UserViewsDoNotRevertForUnknownToken() public view {
        assertEq(nft.userOf(12_345), address(0), "no user");
        assertEq(nft.userExpires(12_345), 0, "no expiry");
    }

    /// @notice A genuine change of owner clears the rental and emits the standard event.
    function test_TransferClearsUser() public {
        uint256 tokenId = _mint(alice, 1);

        vm.prank(alice);
        nft.setUser(tokenId, carol, uint64(block.timestamp + 30 days));

        vm.expectEmit(true, true, false, true);
        emit IERC4907.UpdateUser(tokenId, address(0), 0);
        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);

        assertEq(nft.userOf(tokenId), address(0), "user cleared");
        assertEq(nft.userExpires(tokenId), 0, "expiry cleared");
    }

    /// @notice Stale, already-expired rental state is cleared too, so it cannot mislead the new owner.
    function test_TransferClearsExpiredUserState() public {
        uint256 tokenId = _mint(alice, 1);
        uint64 expires = uint64(block.timestamp + 1 days);

        vm.prank(alice);
        nft.setUser(tokenId, carol, expires);

        vm.warp(uint256(expires) + 1);
        assertEq(nft.userExpires(tokenId), expires, "stale expiry still stored before the transfer");

        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);

        assertEq(nft.userExpires(tokenId), 0, "stale expiry wiped on transfer");
    }

    /// @notice A mint must not emit a spurious `UpdateUser`.
    function test_MintEmitsNoUpdateUser() public {
        vm.recordLogs();
        _mint(alice, 1);
        assertFalse(_sawUpdateUser(vm.getRecordedLogs()), "mint emitted UpdateUser");
    }

    /// @notice Transferring a never-rented token emits no `UpdateUser` either.
    function test_TransferOfNeverRentedTokenEmitsNoUpdateUser() public {
        uint256 tokenId = _mint(alice, 1);

        vm.recordLogs();
        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);

        assertFalse(_sawUpdateUser(vm.getRecordedLogs()), "no-op UpdateUser emitted");
    }

    /// @notice A self-transfer is not a change of custody and must not cancel a live rental.
    function test_SelfTransferKeepsUser() public {
        uint256 tokenId = _mint(alice, 1);
        uint64 expires = uint64(block.timestamp + 5 days);

        vm.prank(alice);
        nft.setUser(tokenId, bob, expires);

        vm.recordLogs();
        vm.prank(alice);
        nft.transferFrom(alice, alice, tokenId);

        assertFalse(_sawUpdateUser(vm.getRecordedLogs()), "self-transfer cleared the user");
        assertEq(nft.userOf(tokenId), bob, "user survives a self-transfer");
        assertEq(nft.userExpires(tokenId), expires, "expiry survives a self-transfer");
        assertEq(nft.ownerOf(tokenId), alice, "owner unchanged");
    }

    /*//////////////////////////////////////////////////////////////
                                METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice `tokenURI` is `baseTokenURI + tokenId`; no per-token strings are stored.
    function test_TokenURIIsBuiltFromBaseURI() public {
        uint256 first = _mint(alice, 1);
        uint256 second = _mint(bob, 2);

        assertEq(nft.tokenURI(first), string.concat(BASE_URI, "1"), "first");
        assertEq(nft.tokenURI(second), string.concat(BASE_URI, "2"), "second");

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(3)));
        nft.tokenURI(3);
    }

    /// @notice The metadata admin can repoint both URIs, and both changes are logged with the
    ///         previous value so an indexer can reconstruct the full history.
    function test_MetadataAdminCanUpdateUris() public {
        uint256 tokenId = _mint(alice, 1);
        string memory nextBase = "ipfs://bafyfrozen/";
        string memory nextContract = "ipfs://bafyfrozen/collection.json";

        vm.expectEmit(false, false, false, true);
        emit IHoodPups.BaseURIUpdated(BASE_URI, nextBase);
        vm.prank(admin);
        nft.setBaseURI(nextBase);

        vm.expectEmit(false, false, false, true);
        emit IHoodPups.ContractURIUpdated(CONTRACT_URI, nextContract);
        vm.prank(admin);
        nft.setContractURI(nextContract);

        assertEq(nft.baseTokenURI(), nextBase, "base uri");
        assertEq(nft.contractURI(), nextContract, "contract uri");
        assertEq(nft.tokenURI(tokenId), string.concat(nextBase, "1"), "tokenURI follows the base uri");
    }

    /// @notice Metadata mutation is role gated, and `DEFAULT_ADMIN_ROLE` alone is not enough.
    function test_MetadataMutationRequiresMetadataAdminRole() public {
        bytes32 role = METADATA_ADMIN;

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, role)
        );
        vm.prank(stranger);
        nft.setBaseURI("ipfs://evil/");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, role)
        );
        vm.prank(stranger);
        nft.setContractURI("ipfs://evil.json");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, guardian, role)
        );
        vm.prank(guardian);
        nft.freezeMetadata();
    }

    /// @notice Freezing is permanent: no setter works afterwards, and there is no unfreeze.
    function test_FreezeMetadataIsIrreversible() public {
        uint256 tokenId = _mint(alice, 1);

        vm.expectEmit(false, false, false, true);
        emit IHoodPups.MetadataFrozenForever();
        vm.prank(admin);
        nft.freezeMetadata();
        assertTrue(nft.metadataFrozen(), "frozen");

        vm.expectRevert(IHoodPups.MetadataFrozen.selector);
        vm.prank(admin);
        nft.setBaseURI("ipfs://after-the-freeze/");

        vm.expectRevert(IHoodPups.MetadataFrozen.selector);
        vm.prank(admin);
        nft.setContractURI("ipfs://after-the-freeze.json");

        // A duplicated timelock execution must not emit a second `MetadataFrozenForever`.
        vm.expectRevert(IHoodPups.MetadataFrozen.selector);
        vm.prank(admin);
        nft.freezeMetadata();

        // There is no unfreeze function at all, at any selector governance could reach.
        (bool ok,) = address(nft).call(abi.encodeWithSignature("unfreezeMetadata()"));
        assertFalse(ok, "an unfreeze path exists");

        // Reads are unaffected, and minting still works: freezing metadata is not a pause.
        assertEq(nft.tokenURI(tokenId), string.concat(BASE_URI, "1"), "tokenURI still readable");
        assertEq(_mint(bob, 2), 2, "minting unaffected by a metadata freeze");
    }

    /*//////////////////////////////////////////////////////////////
                          ERC-165 AND ABSENT CODE
    //////////////////////////////////////////////////////////////*/

    /// @notice Exactly the interfaces this collection implements are advertised.
    function test_SupportsExpectedInterfaces() public view {
        assertTrue(nft.supportsInterface(type(IERC165).interfaceId), "ERC-165");
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId), "ERC-721");
        assertTrue(nft.supportsInterface(type(IERC721Metadata).interfaceId), "ERC-721 Metadata");
        assertTrue(nft.supportsInterface(type(IAccessControl).interfaceId), "AccessControl");
        assertTrue(nft.supportsInterface(type(IERC4907).interfaceId), "ERC-4907");

        // Pinned literals, so a change to the interface files cannot silently move an id.
        assertEq(type(IERC165).interfaceId, bytes4(0x01ffc9a7), "ERC-165 id");
        assertEq(type(IERC721).interfaceId, bytes4(0x80ac58cd), "ERC-721 id");
        assertEq(type(IERC721Metadata).interfaceId, bytes4(0x5b5e139f), "ERC-721 Metadata id");
        assertEq(type(IERC4907).interfaceId, ERC4907_INTERFACE_ID, "ERC-4907 id");

        assertFalse(nft.supportsInterface(bytes4(0xffffffff)), "the ERC-165 invalid id must be false");
        assertFalse(nft.supportsInterface(bytes4(0xdeadbeef)), "unknown id");
    }

    /// @notice ERC-721 Enumerable is neither advertised nor implemented.
    /// @dev Both halves matter. Advertising an interface whose functions do not exist would make a
    ///      marketplace call straight into a revert, and implementing it would put an O(n) write on
    ///      every transfer to serve data an indexer already has.
    function test_DoesNotAdvertiseOrImplementEnumerable() public {
        _mint(alice, 1);

        assertFalse(nft.supportsInterface(ERC721_ENUMERABLE_INTERFACE_ID), "enumerable advertised");

        (bool totalSupplyOk,) = address(nft).call(abi.encodeWithSignature("totalSupply()"));
        assertFalse(totalSupplyOk, "totalSupply exists");

        (bool tokenByIndexOk,) = address(nft).call(abi.encodeWithSignature("tokenByIndex(uint256)", uint256(0)));
        assertFalse(tokenByIndexOk, "tokenByIndex exists");

        (bool ownerIndexOk,) =
            address(nft).call(abi.encodeWithSignature("tokenOfOwnerByIndex(address,uint256)", alice, uint256(0)));
        assertFalse(ownerIndexOk, "tokenOfOwnerByIndex exists");
    }

    /// @notice There is no burn and no administrative remap of a Root, at any reachable selector.
    /// @dev These are the functions whose existence would break "one Root, one HoodPup, forever".
    function test_NoBurnAndNoRootRemapExist() public {
        uint256 tokenId = _mint(alice, 1);

        (bool burnOk,) = address(nft).call(abi.encodeWithSignature("burn(uint256)", tokenId));
        assertFalse(burnOk, "a burn path exists");

        (bool remapOk,) = address(nft).call(abi.encodeWithSignature("setRootOf(uint256,bytes32)", tokenId, bytes32(0)));
        assertFalse(remapOk, "a root remap path exists");

        (bool clearOk,) = address(nft).call(abi.encodeWithSignature("clearRoot(bytes32)", nft.rootKeyOf(tokenId)));
        assertFalse(clearOk, "a root clearing path exists");

        assertEq(nft.ownerOf(tokenId), alice, "token untouched");
    }

    /*//////////////////////////////////////////////////////////////
                             ROLE HANDOVER
    //////////////////////////////////////////////////////////////*/

    /// @notice After handover the deploying EOA retains zero authority over the collection.
    /// @dev Models the deployment script's grant-then-revoke batch. The order is load bearing:
    ///      revoking before granting would brick administration permanently, because there is no
    ///      recovery path — and that absence is deliberate, since a recovery path is a backdoor.
    function test_TimelockHandoverFullyRevokesDeployer() public {
        address deployer = address(this);
        HoodPups fresh = new HoodPups(deployer, NAME, SYMBOL, BASE_URI, CONTRACT_URI);

        fresh.grantRole(DEFAULT_ADMIN, admin);
        fresh.grantRole(METADATA_ADMIN, admin);
        fresh.grantRole(PAUSER, guardian);

        fresh.renounceRole(METADATA_ADMIN, deployer);
        fresh.renounceRole(PAUSER, deployer);
        fresh.renounceRole(DEFAULT_ADMIN, deployer);

        assertFalse(fresh.hasRole(DEFAULT_ADMIN, deployer), "deployer is still admin");
        assertFalse(fresh.hasRole(METADATA_ADMIN, deployer), "deployer still owns metadata");
        assertFalse(fresh.hasRole(PAUSER, deployer), "deployer can still pause");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, deployer, METADATA_ADMIN)
        );
        fresh.setBaseURI("ipfs://deployer-still-in-control/");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, deployer, DEFAULT_ADMIN)
        );
        fresh.grantRole(MINTER, deployer);

        // Governance still works from the timelock.
        vm.prank(admin);
        fresh.setBaseURI("ipfs://governed/");
        assertEq(fresh.baseTokenURI(), "ipfs://governed/", "timelock retains control");
    }

    /*//////////////////////////////////////////////////////////////
                                  FUZZ
    //////////////////////////////////////////////////////////////*/

    /// @notice Any two distinct inscription indices under one reveal txid are distinct Roots, and
    ///         both can mint; re-minting either is impossible.
    function testFuzz_RootIdentityIsInjective(bytes32 txid, uint32 indexA, uint32 indexB) public {
        vm.assume(txid != bytes32(0));
        vm.assume(indexA != indexB);

        PuppetTypes.RootId memory rootA = PuppetTypes.RootId({inscriptionTxid: txid, inscriptionIndex: indexA});
        PuppetTypes.RootId memory rootB = PuppetTypes.RootId({inscriptionTxid: txid, inscriptionIndex: indexB});

        vm.startPrank(minter);
        uint256 idA = nft.mintRooted(alice, rootA);
        uint256 idB = nft.mintRooted(bob, rootB);
        vm.stopPrank();

        assertTrue(idA != idB, "distinct ids");
        assertTrue(nft.rootKeyOf(idA) != nft.rootKeyOf(idB), "distinct keys");
        assertEq(nft.tokenOfRoot(nft.rootKeyOf(idA)), idA, "A round trips");
        assertEq(nft.tokenOfRoot(nft.rootKeyOf(idB)), idB, "B round trips");

        vm.expectRevert(abi.encodeWithSelector(IHoodPups.RootAlreadyMinted.selector, nft.rootKeyOf(idA), idA));
        vm.prank(minter);
        nft.mintRooted(carol, rootA);
    }

    /// @notice Over an arbitrary run of mints, ids stay sequential and every lookup round trips.
    function testFuzz_SequentialIdsAndRoundTripLookups(uint8 count) public {
        uint256 n = uint256(count) % 24 + 1;

        for (uint256 i = 1; i <= n; i++) {
            uint256 id = _mint(alice, i);
            assertEq(id, i, "sequential");

            bytes32 key = nft.rootKeyOf(id);
            assertTrue(key != bytes32(0), "nonzero root key");
            assertEq(nft.tokenOfRoot(key), id, "round trip");
            assertTrue(nft.rootMinted(key), "marked minted");
        }

        assertEq(nft.nextTokenId(), n + 1, "next id");
        assertEq(nft.balanceOf(alice), n, "balance");
    }

    /// @notice The expiry boundary holds for every possible `uint64`: strictly future terms are
    ///         accepted, everything else reverts, and the accepted term is live at that instant.
    function testFuzz_SetUserExpiryBoundary(uint64 expires) public {
        uint256 tokenId = _mint(alice, 1);

        if (expires <= block.timestamp) {
            vm.expectRevert(abi.encodeWithSelector(IHoodPups.ExpiryInPast.selector, expires, block.timestamp));
            vm.prank(alice);
            nft.setUser(tokenId, bob, expires);
            assertEq(nft.userOf(tokenId), address(0), "no user recorded");
        } else {
            vm.prank(alice);
            nft.setUser(tokenId, bob, expires);
            assertEq(nft.userOf(tokenId), bob, "user recorded");
            assertEq(nft.userExpires(tokenId), expires, "expiry recorded");
        }
    }

    /// @notice Any EOA recipient can receive a mint, and the Root binding is identical regardless.
    function testFuzz_MintToArbitraryEoaRecipient(address recipient, uint256 salt) public {
        vm.assume(recipient != address(0));
        // `_safeMint` only invokes the receiver hook for accounts with code; excluding contracts
        // keeps this fuzz about the recipient address itself rather than about callback behaviour,
        // which the dedicated receiver tests already cover.
        vm.assume(recipient.code.length == 0);

        PuppetTypes.RootId memory root = _root(salt);
        vm.assume(root.inscriptionTxid != bytes32(0));

        vm.prank(minter);
        uint256 tokenId = nft.mintRooted(recipient, root);

        assertEq(nft.ownerOf(tokenId), recipient, "owner");
        assertEq(nft.rootKeyOf(tokenId), PuppetHashing.rootKey(root), "key");
        assertEq(nft.tokenOfRoot(PuppetHashing.rootKey(root)), tokenId, "reverse lookup");
    }
}
