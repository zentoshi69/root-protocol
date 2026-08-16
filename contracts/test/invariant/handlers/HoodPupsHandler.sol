// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {HoodPups} from "../../../src/HoodPups.sol";
import {PuppetHashing} from "../../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../../src/types/PuppetTypes.sol";

/// @title HoodPupsHandler
/// @notice Bounded action surface driving `HoodPups` for the stateful invariant campaign.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      WHY A HANDLER RATHER THAN FUZZING THE CONTRACT DIRECTLY: an unguided campaign would spend
///      almost every call bouncing off `AccessControl`, and would essentially never generate the one
///      sequence that matters — a second mint attempt for a Root that already minted. This handler
///      draws Roots from a deliberately SMALL space (`ROOT_SPACE`) so collisions are frequent rather
///      than astronomically unlikely, and it mints only from an address that really holds
///      `MINTER_ROLE`, so the campaign explores the state machine instead of the access modifier.
///
///      GHOST STATE LIVES HERE, NOT IN THE INVARIANT CONTRACT. Forge restores the whole EVM state
///      between invariant runs, and the handler's storage is part of that state; a counter kept in
///      the test contract would leak values from a previous run into the next one and produce
///      failures that no call sequence can reproduce.
///
///      REVERTS ARE EXPECTED AND FINE (`fail_on_revert = false`). What is NOT fine is a call that
///      should have reverted and did not, so the two rules that must never bend — a Root minting
///      twice, and a pause blocking a transfer — are recorded as explicit boolean flags rather than
///      being left to the revert filter.
contract HoodPupsHandler is CommonBase, StdUtils {
    /*//////////////////////////////////////////////////////////////
                                 TARGETS
    //////////////////////////////////////////////////////////////*/

    HoodPups public immutable NFT;

    /// @dev Address holding `DEFAULT_ADMIN_ROLE`; only it can unpause.
    address public immutable ADMIN;

    /// @dev Size of the Root identity space the campaign draws from. Small on purpose: with a
    ///      64-call depth this guarantees repeated attempts on already-minted Roots.
    uint256 public constant ROOT_SPACE = 12;

    /// @dev Token holders and rental users. Plain addresses with no code, so `_safeMint` never
    ///      reaches a receiver hook — receiver behaviour is covered exhaustively in the unit suite,
    ///      and a hostile receiver here would only add noise to the state-machine campaign.
    address[4] public actors =
        [address(uint160(0xA11CE)), address(uint160(0xB0B)), address(uint160(0xCA401)), address(uint160(0xDA5E))];

    /*//////////////////////////////////////////////////////////////
                               GHOST STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Root keys this handler has successfully minted, in mint order.
    bytes32[] public mintedKeys;

    /// @notice Successful mints.
    uint256 public mintCount;

    /// @notice Second-mint attempts made against an already-minted Root.
    uint256 public duplicateAttempts;

    /// @notice Set if a second mint of an already-minted Root ever succeeded. Must stay false.
    bool public duplicateMintSucceeded;

    /// @notice Set if a transfer by the token's own owner failed while minting was paused.
    ///         Must stay false: pausing may block new risk-taking, never a holder's property.
    bool public pauseBlockedATransfer;

    /// @notice Set if `nextTokenId` ever went down across a single action. Must stay false.
    bool public nextTokenIdWentBackwards;

    /// @notice Highest `nextTokenId` observed at the end of any action.
    uint256 public maxObservedNextTokenId;

    /// @notice Per-action call counts, for the campaign summary.
    uint256 public callsMint;
    uint256 public callsDuplicate;
    uint256 public callsTransfer;
    uint256 public callsSetUser;
    uint256 public callsPauseToggle;
    uint256 public callsWarp;

    /// @param nft The collection under test.
    /// @param admin The address holding `DEFAULT_ADMIN_ROLE` on `nft`.
    constructor(HoodPups nft, address admin) {
        NFT = nft;
        ADMIN = admin;
        maxObservedNextTokenId = nft.nextTokenId();
    }

    /*//////////////////////////////////////////////////////////////
                               MONOTONICITY
    //////////////////////////////////////////////////////////////*/

    /// @dev Brackets every action so a decrease in `nextTokenId` is caught inside the very call that
    ///      caused it. Recording only the post-action value would let an action that decremented and
    ///      then re-recorded its own lower value slip past.
    modifier tracksNextTokenId() {
        uint256 before = NFT.nextTokenId();
        _;
        uint256 afterCall = NFT.nextTokenId();

        if (afterCall < before) nextTokenIdWentBackwards = true;
        if (afterCall > maxObservedNextTokenId) maxObservedNextTokenId = afterCall;
    }

    /*//////////////////////////////////////////////////////////////
                                 ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Attempt a mint of a Root drawn from the small shared space.
    /// @dev Whether this is a first or a repeat mint is decided by the campaign, not by the handler:
    ///      that is the point. A repeat MUST revert, and a repeat that returns successfully is
    ///      recorded as a violation rather than being silently swallowed by the revert filter.
    /// @param rootSeed Selects the Root identity.
    /// @param actorSeed Selects the recipient.
    function mint(uint256 rootSeed, uint256 actorSeed) external tracksNextTokenId {
        callsMint++;

        PuppetTypes.RootId memory root = _rootAt(bound(rootSeed, 0, ROOT_SPACE - 1));
        bytes32 key = PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);
        bool alreadyMinted = NFT.rootMinted(key);
        if (alreadyMinted) duplicateAttempts++;

        address recipient = _actor(actorSeed);

        vm.prank(address(this));
        try NFT.mintRooted(recipient, root) returns (uint256 tokenId) {
            if (alreadyMinted) duplicateMintSucceeded = true;
            mintedKeys.push(key);
            mintCount++;
            // A successful mint must be consistent in both directions immediately.
            if (NFT.tokenOfRoot(key) != tokenId) duplicateMintSucceeded = true;
        } catch {
            // Expected whenever the Root already minted, minting is paused, or the recipient is
            // otherwise unusable. Nothing to record: the flags above cover the cases that matter.
        }
    }

    /// @notice Deliberately re-attempt a Root that is already known to have minted.
    /// @dev The random `mint` above will find duplicates on its own, but only after the space fills
    ///      up. This action guarantees the campaign probes the one-mint-per-Root rule from the very
    ///      first successful mint onwards, which is what makes short runs meaningful.
    /// @param seed Selects which already-minted Root to re-attempt.
    function mintDuplicate(uint256 seed) external tracksNextTokenId {
        callsDuplicate++;
        if (mintedKeys.length == 0) return;

        uint256 index = bound(seed, 0, mintedKeys.length - 1);
        PuppetTypes.RootId memory root = _rootAt(index % ROOT_SPACE);
        bytes32 key = PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);
        if (!NFT.rootMinted(key)) return;

        duplicateAttempts++;

        vm.prank(address(this));
        try NFT.mintRooted(_actor(seed), root) returns (uint256) {
            duplicateMintSucceeded = true;
        } catch {
            // Correct: `RootAlreadyMinted`.
        }
    }

    /// @notice Move a token between actors, using its real owner as the caller.
    /// @dev Pausing is checked around the call because "a pause never blocks a transfer" is a
    ///      protocol-level rule, not an ERC-721 one, and it is the rule most likely to be broken by
    ///      a well-meaning future edit that adds a modifier to `_update`.
    /// @param tokenSeed Selects the token.
    /// @param actorSeed Selects the destination.
    function transfer(uint256 tokenSeed, uint256 actorSeed) external tracksNextTokenId {
        callsTransfer++;

        uint256 minted = NFT.nextTokenId() - 1;
        if (minted == 0) return;

        uint256 tokenId = bound(tokenSeed, 1, minted);
        address owner = NFT.ownerOf(tokenId);
        address to = _actor(actorSeed);
        if (to == owner) return;

        bool pausedNow = NFT.mintingPaused();

        vm.prank(owner);
        try NFT.transferFrom(owner, to, tokenId) {
        // Expected: an owner-initiated transfer always succeeds.
        }
        catch {
            // An owner moving their own token to a code-free address has no legitimate reason to
            // fail. If it failed while paused, the pause reached a holder's property.
            if (pausedNow) pauseBlockedATransfer = true;
        }
    }

    /// @notice Set or clear the ERC-4907 user, called by the token's owner.
    /// @param tokenSeed Selects the token.
    /// @param actorSeed Selects the user (or clears, when it lands on the owner).
    /// @param durationSeed Selects the rental length.
    function setUser(uint256 tokenSeed, uint256 actorSeed, uint256 durationSeed) external tracksNextTokenId {
        callsSetUser++;

        uint256 minted = NFT.nextTokenId() - 1;
        if (minted == 0) return;

        uint256 tokenId = bound(tokenSeed, 1, minted);
        address owner = NFT.ownerOf(tokenId);
        address user = _actor(actorSeed);
        // Naming the owner is rejected by design, so use that draw as the "clear it" action.
        if (user == owner) user = address(0);

        uint64 expires = user == address(0) ? 0 : uint64(block.timestamp + bound(durationSeed, 1, 365 days));

        vm.prank(owner);
        try NFT.setUser(tokenId, user, expires) {} catch {}
    }

    /// @notice Toggle the mint pause through the real role holders.
    /// @dev Pausing runs as this handler (`PAUSER_ROLE`); unpausing runs as `ADMIN`
    ///      (`DEFAULT_ADMIN_ROLE`), preserving the production asymmetry inside the campaign.
    ///      The draw is deliberately skewed towards unpausing (1 in 4 pauses). An even split leaves
    ///      the collection paused for roughly half the campaign, which starves the mint path — the
    ///      one that carries the property this whole file exists to test.
    /// @param seed Chooses pause or unpause.
    function togglePause(uint256 seed) external tracksNextTokenId {
        callsPauseToggle++;

        if (seed % 4 == 0) {
            vm.prank(address(this));
            try NFT.pauseMinting() {} catch {}
        } else {
            vm.prank(ADMIN);
            try NFT.unpauseMinting() {} catch {}
        }
    }

    /// @notice Advance the clock so rentals actually lapse mid-campaign.
    /// @param secondsSeed Amount of time to skip.
    function warp(uint256 secondsSeed) external tracksNextTokenId {
        callsWarp++;
        vm.warp(block.timestamp + bound(secondsSeed, 1, 120 days));
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Number of Roots successfully minted by this handler.
    function mintedKeyCount() external view returns (uint256) {
        return mintedKeys.length;
    }

    /// @notice One successfully minted Root key.
    /// @param index Position in mint order.
    function mintedKeyAt(uint256 index) external view returns (bytes32) {
        return mintedKeys[index];
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNALS
    //////////////////////////////////////////////////////////////*/

    /// @dev Deterministic Root identity for a slot in the shared space. Slots 0..3 share a reveal
    ///      txid and differ only by inscription index, which is the collision shape the protocol's
    ///      key derivation exists to separate.
    /// @param slot Index into `ROOT_SPACE`.
    function _rootAt(uint256 slot) internal pure returns (PuppetTypes.RootId memory) {
        if (slot < 4) {
            return PuppetTypes.RootId({
                inscriptionTxid: keccak256("shared-reveal-transaction"), inscriptionIndex: uint32(slot)
            });
        }
        return
            PuppetTypes.RootId({inscriptionTxid: keccak256(abi.encode("root", slot)), inscriptionIndex: uint32(slot)});
    }

    /// @param seed Raw fuzz word.
    /// @return One of the four campaign actors.
    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }
}
