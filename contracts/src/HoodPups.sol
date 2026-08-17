// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IERC4907, IHoodPups} from "./interfaces/IHoodPups.sol";
import {PuppetHashing} from "./types/PuppetHashing.sol";
import {PuppetTypes} from "./types/PuppetTypes.sol";

/// @title HoodPups
/// @notice ERC-721 on Robinhood Chain where every token permanently references exactly one
///         canonical Bitcoin Puppet inscription.
/// @dev WHAT A HOODPUP IS, AND WHAT IT IS NOT — READ THIS BEFORE READING ANY OTHER LINE:
///      A HoodPup is a derived Robinhood Chain asset that *references* a Bitcoin inscription. It is
///      not the inscription, it does not custody, wrap, bridge or escrow it, and holding one confers
///      no rights over it. The original Bitcoin Puppet never leaves Bitcoin. This contract has no
///      payable function and no way to hold or move value of any kind.
///
///      TRUST BOUNDARY: nothing here verifies Bitcoin consensus. That a given inscription was
///      genuinely controlled by whoever authorized a mint is asserted upstream by a 3-of-5 quorum of
///      independent attestors, and this contract simply trusts `MINTER_ROLE` to have done that work.
///      It is an attested settlement system, not a trustless bridge.
///
///      THE CENTRAL PROMISE: one canonical inscription mints AT MOST ONE HoodPup, ever. That is
///      enforced by `_tokenOfRoot`, a mapping that is written exactly once per Root and for which no
///      clearing, remapping, burning or administrative override exists anywhere in this file. There
///      is deliberately no `burn`, no `setRootOf`, no rescue hook and no upgrade path: every one of
///      those would be a way to make one inscription produce a second token, which is precisely the
///      guarantee the whole protocol is built on. Auditors should verify this by searching the file
///      for writes to `_tokenOfRoot` — there is one, inside `mintRooted`, guarded by a check that
///      the slot is still empty.
///
///      TOKEN IDS START AT 1. Zero is reserved as the "no such token" sentinel so `tokenOfRoot`
///      can answer "not minted" without a second lookup, and so no caller can mistake a
///      default-initialised storage slot for a real token.
///
///      PAUSING IS NARROW BY DESIGN. `mintingPaused` blocks `mintRooted` and nothing else.
///      Transfers, approvals, ERC-4907 reads and every view keep working while paused, because a
///      holder's property must not depend on the protocol's operational state. There is no
///      `whenNotPaused` modifier anywhere near a transfer path, and the unit suite asserts that.
///
///      NON-UPGRADEABLE by construction: no proxy, no initializer, no `delegatecall`, no
///      `selfdestruct`, no `tx.origin`, and no admin path that can seize, move or destroy a token
///      that a user already holds.
contract HoodPups is IHoodPups, ERC721, AccessControl, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                  ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role permitted to mint a HoodPup for a Root.
    /// @dev Granted to `HoodPupOfferEscrow` only. It is NOT granted at construction: the escrow does
    ///      not exist yet when this contract is deployed, and pre-granting it to the deployer would
    ///      create exactly the EOA-holds-a-privileged-role state the deployment is meant to avoid.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role permitted to set the ERC-4907 user without holding or being approved for a token.
    /// @dev Granted to `TourEngine` only, which sets a user after validating tour rules. This is the
    ///      narrowest possible extra authority: it can change who may *use* a token temporarily, and
    ///      it can never transfer, mint, burn or approve one. A compromised TourEngine can grief
    ///      rental state; it can never take a token away from its owner.
    bytes32 public constant TOUR_ENGINE_ROLE = keccak256("TOUR_ENGINE_ROLE");

    /// @notice Role permitted to change or permanently freeze the metadata URIs.
    /// @dev Separate from `DEFAULT_ADMIN_ROLE` for least privilege: role administration and metadata
    ///      administration are different jobs with different blast radii, and separating them lets a
    ///      deployment move one without widening the other. In production this MUST be held by a
    ///      `TimelockController` under multisig control, which is what makes every metadata change a
    ///      publicly visible, delayed operation rather than a silent storage write.
    bytes32 public constant METADATA_ADMIN_ROLE = keccak256("METADATA_ADMIN_ROLE");

    /// @notice Role permitted to pause minting. Cannot unpause.
    /// @dev Held by the guardian multisig — smaller and faster than the timelock, because pausing
    ///      during an incident must be fast. Unpausing requires `DEFAULT_ADMIN_ROLE` (the timelock),
    ///      because resuming risk-taking must be deliberate. The asymmetry means a compromised
    ///      guardian can only ever cost liveness on the mint path; it can never resume a mint path
    ///      that governance has stopped, and it can never touch a token that already exists.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              EXTRA ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when `mintRooted` is handed a `RootId` whose reveal txid is zero.
    /// @dev A zero txid is not a Bitcoin transaction; it is the shape of a default-initialised
    ///      struct that reached the mint path through a caller bug. Rejecting it costs one comparison
    ///      and prevents that bug from permanently consuming a token id and a `_tokenOfRoot` slot
    ///      that can never be reclaimed, since nothing in this contract can undo a mint.
    error ZeroRootTxid();

    /// @notice Thrown when the mint pause is set to the value it already holds.
    /// @dev Reverting on a no-op is the house rule across this protocol. Here it also carries useful
    ///      operational information: a guardian re-sending `pauseMinting()` during an incident gets
    ///      an unambiguous "already paused" answer instead of a second, indistinguishable
    ///      `MintingPauseUpdated` event that would make the incident timeline ambiguous for indexers.
    /// @param currentlyPaused The pause state already stored.
    error MintPauseUnchanged(bool currentlyPaused);

    /*//////////////////////////////////////////////////////////////
                               EXTRA EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted once, from the constructor, recording the collection's genesis configuration.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE`, `METADATA_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param name The ERC-721 collection name.
    /// @param symbol The ERC-721 collection symbol.
    /// @param firstTokenId The id the first mint will assign, always 1.
    event HoodPupsInitialized(address indexed admin, string name, string symbol, uint256 firstTokenId);

    /*//////////////////////////////////////////////////////////////
                            ERC-4907 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Temporary use rights over one token.
    /// @dev Packed into a single slot: an address and a `uint64` fit in 32 bytes together, so a
    ///      `setUser` writes one slot and the `_update` clear on transfer wipes one slot.
    /// @param user Address currently entitled to use the token.
    /// @param expires Unix timestamp at which that entitlement lapses.
    struct UserInfo {
        address user;
        uint64 expires;
    }

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Next id `mintRooted` will assign. Starts at 1 and only ever increases; there is no code
    ///      path that decrements it, and no burn to make a gap reusable.
    uint256 private _nextTokenId;

    /// @dev Root key => token id. WRITE-ONCE PER KEY. This mapping is the one-mint-per-Root rule.
    mapping(bytes32 rootKey => uint256 tokenId) private _tokenOfRoot;

    /// @dev Token id => the Bitcoin inscription identity it permanently references. Written once, in
    ///      `mintRooted`, and never again by anything.
    mapping(uint256 tokenId => PuppetTypes.RootId root) private _rootOf;

    /// @dev Token id => ERC-4907 temporary user. The only entry here that is cleared automatically
    ///      is on a genuine change of owner; see `_update`.
    mapping(uint256 tokenId => UserInfo info) private _userInfo;

    /// @dev Prefix `tokenURI` builds on. Mutable until `_metadataFrozen` is set, then permanent.
    string private _baseTokenURI;

    /// @dev Collection-level metadata document URI. Mutable until frozen, then permanent.
    string private _collectionURI;

    /// @dev Once true, no URI in this contract can ever change again. There is no unfreeze.
    bool private _metadataFrozen;

    /// @dev Once true, `mintRooted` reverts. Affects nothing else, ever.
    bool private _mintingPaused;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the collection.
    /// @dev `admin` MUST be a `TimelockController` (itself governed by a multisig) in production.
    ///      Nothing in this contract can enforce that, so the deployment script grants the roles to
    ///      the timelock and revokes them from the deployer in the same transaction batch;
    ///      `test_TimelockHandoverFullyRevokesDeployer` proves the revocation path leaves the
    ///      deployer with zero authority.
    ///
    ///      `MINTER_ROLE` and `TOUR_ENGINE_ROLE` are intentionally left ungranted: the escrow and the
    ///      tour engine are deployed after this contract, and granting them later is a separate,
    ///      reviewable governance action.
    ///
    ///      Both URI events are emitted here with an empty `previous`, so an indexer that only
    ///      listens to `BaseURIUpdated` / `ContractURIUpdated` reconstructs the full history without
    ///      needing to special-case genesis.
    /// @param admin Address granted `DEFAULT_ADMIN_ROLE`, `METADATA_ADMIN_ROLE` and `PAUSER_ROLE`.
    /// @param name_ ERC-721 collection name.
    /// @param symbol_ ERC-721 collection symbol.
    /// @param baseURI_ Initial `tokenURI` prefix. May be empty and set later.
    /// @param contractURI_ Initial collection metadata URI. May be empty and set later.
    constructor(
        address admin,
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        string memory contractURI_
    ) ERC721(name_, symbol_) {
        if (admin == address(0)) revert ZeroAddress();

        // Ids start at 1 so that zero is an unambiguous "not minted" answer everywhere.
        _nextTokenId = 1;

        _baseTokenURI = baseURI_;
        _collectionURI = contractURI_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(METADATA_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        emit BaseURIUpdated("", baseURI_);
        emit ContractURIUpdated("", contractURI_);
        emit HoodPupsInitialized(admin, name_, symbol_, 1);
    }

    /*//////////////////////////////////////////////////////////////
                                  MINT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPups
    /// @dev CHECKS-EFFECTS-INTERACTIONS. Every storage write and the protocol-level event happen
    ///      before `_safeMint`, whose `onERC721Received` callback is the only external call in this
    ///      contract. A recipient that reenters therefore observes a fully consistent state: its
    ///      Root is already marked as minted, so it cannot use the callback to mint the same Root
    ///      twice.
    ///
    ///      `nonReentrant` is applied anyway. No value moves here, so the guard is defence in depth
    ///      rather than a correctness requirement, and it costs a storage slot per mint. That trade
    ///      is taken deliberately: this is the function that enforces the protocol's central promise,
    ///      and a future edit that introduces a state write *after* `_safeMint` would silently become
    ///      exploitable without it. Clarity and durability beat the gas here.
    ///
    ///      `_safeMint` (not `_mint`) is used so a contract recipient that cannot handle ERC-721s
    ///      reverts the settlement rather than having its HoodPup permanently stranded at an address
    ///      that can never transfer it. Since a Root can only ever mint once, a stranded token would
    ///      be unrecoverable in the strongest sense: no burn, no remap, no second chance.
    /// @param recipient Address that receives the HoodPup. Must be nonzero and ERC-721 aware.
    /// @param root The Bitcoin inscription this token will permanently reference.
    /// @return tokenId The newly assigned token id.
    function mintRooted(address recipient, PuppetTypes.RootId calldata root)
        external
        onlyRole(MINTER_ROLE)
        nonReentrant
        returns (uint256 tokenId)
    {
        if (_mintingPaused) revert MintingPaused();
        return _mintRooted(recipient, root);
    }

    /// @inheritdoc IHoodPups
    /// @dev The only production holder of `MINTER_ROLE` is the immutable offer escrow, which calls
    ///      this entry point solely to finish a BTC reservation whose solver may already have paid
    ///      irreversible Bitcoin. Ordinary settlement continues through `mintRooted` and remains
    ///      blocked by the incident pause.
    function mintRootedTerminal(address recipient, PuppetTypes.RootId calldata root)
        external
        onlyRole(MINTER_ROLE)
        nonReentrant
        returns (uint256 tokenId)
    {
        return _mintRooted(recipient, root);
    }

    function _mintRooted(address recipient, PuppetTypes.RootId calldata root) private returns (uint256 tokenId) {
        if (recipient == address(0)) revert ZeroAddress();
        if (root.inscriptionTxid == bytes32(0)) revert ZeroRootTxid();

        bytes32 key = PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);

        uint256 existing = _tokenOfRoot[key];
        if (existing != 0) revert RootAlreadyMinted(key, existing);

        tokenId = _nextTokenId;
        // Cannot realistically overflow: one mint per inscription, and the manifest is finite.
        _nextTokenId = tokenId + 1;

        _tokenOfRoot[key] = tokenId;
        _rootOf[tokenId] = root;

        // Emitted before the receiver callback so the protocol-level record of the mint is written
        // ahead of the ERC-721 `Transfer`, and cannot be reordered by anything the recipient does.
        emit RootedMint(tokenId, key, recipient, root.inscriptionTxid, root.inscriptionIndex);

        _safeMint(recipient, tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                             ROOT IDENTITY
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPups
    /// @dev Permanent. Nothing in this contract can make this return false once it has returned true.
    /// @param rootKey The canonical protocol key for an inscription.
    /// @return True if this Root has already produced its one HoodPup.
    function rootMinted(bytes32 rootKey) external view returns (bool) {
        return _tokenOfRoot[rootKey] != 0;
    }

    /// @inheritdoc IHoodPups
    /// @dev Returns zero for an unminted Root rather than reverting, because callers legitimately
    ///      ask this question about Roots that have never minted — that is the entire point of the
    ///      check. Ids start at 1, so zero can never be confused with a real token.
    /// @param rootKey The canonical protocol key for an inscription.
    /// @return The token id for that Root, or zero if it has never minted.
    function tokenOfRoot(bytes32 rootKey) external view returns (uint256) {
        return _tokenOfRoot[rootKey];
    }

    /// @inheritdoc IHoodPups
    /// @dev Reverts for an unknown token instead of returning a zeroed struct, because a zeroed
    ///      `RootId` is a syntactically valid identity and a caller that forgot to check would treat
    ///      it as a real inscription.
    /// @param tokenId The token to look up.
    /// @return The Bitcoin inscription identity this token permanently references.
    function rootOf(uint256 tokenId) external view returns (PuppetTypes.RootId memory) {
        _requireKnown(tokenId);
        return _rootOf[tokenId];
    }

    /// @inheritdoc IHoodPups
    /// @dev Derived from the stored `RootId` through `PuppetHashing` rather than cached in its own
    ///      mapping. One keccak on a view path buys the guarantee that the key returned here can
    ///      never drift from the identity stored in `_rootOf` — a cached copy could, if a future edit
    ///      updated one and not the other.
    /// @param tokenId The token to look up.
    /// @return The canonical root key this token references.
    function rootKeyOf(uint256 tokenId) external view returns (bytes32) {
        _requireKnown(tokenId);
        PuppetTypes.RootId memory root = _rootOf[tokenId];
        return PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);
    }

    /// @inheritdoc IHoodPups
    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    /*//////////////////////////////////////////////////////////////
                                ERC-4907
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC4907
    /// @dev AUTHORIZATION. The owner, an approved operator (`setApprovalForAll`) and the single
    ///      approved address for the token may all set the user, matching the ERC-4907 reference
    ///      implementation's "owner or approved" rule. `TOUR_ENGINE_ROLE` is additionally allowed so
    ///      `TourEngine` can place a token on tour after validating its own rules, without the owner
    ///      having to hand it a blanket ERC-721 approval — which would let it *transfer* the token.
    ///      Granting the narrow role instead of a transfer approval is the entire point.
    ///
    ///      CLEARING. Passing `address(0)` clears the entitlement, and the expiry is forced to zero
    ///      rather than being rejected, so a caller that clears with a stale nonzero `expires` gets
    ///      the obvious outcome instead of a confusing revert. Since `user` is zero the expiry can
    ///      have no effect, so silently normalising it cannot hide a mistake that matters.
    ///
    ///      EXPIRY MUST BE IN THE FUTURE. An expiry at or before `block.timestamp` would create an
    ///      entitlement that is already dead on arrival while still occupying the slot, so callers
    ///      would see `userOf == address(0)` immediately and have no way to tell it apart from a
    ///      failed call. Reverting makes the mistake loud.
    /// @param tokenId Token to grant temporary use of.
    /// @param user Address entitled to use it, or `address(0)` to clear.
    /// @param expires Unix timestamp at which the entitlement lapses. Must be in the future unless
    ///        clearing.
    function setUser(uint256 tokenId, address user, uint64 expires) external {
        _requireKnown(tokenId);

        address owner = ownerOf(tokenId);
        if (!_isAuthorized(owner, msg.sender, tokenId) && !hasRole(TOUR_ENGINE_ROLE, msg.sender)) {
            revert NotOwnerNorApproved(msg.sender, tokenId);
        }

        // The owner already holds every right the user role can confer, so naming them as user is
        // always a mistake — and one that would let a rental marketplace show a token as "rented"
        // to the person who owns it.
        if (user == owner) revert UserIsOwner();

        if (user == address(0)) {
            expires = 0;
        } else if (expires <= block.timestamp) {
            revert ExpiryInPast(expires, block.timestamp);
        }

        _userInfo[tokenId] = UserInfo({user: user, expires: expires});
        emit UpdateUser(tokenId, user, expires);
    }

    /// @inheritdoc IERC4907
    /// @dev Returns `address(0)` once the term has elapsed, and also for a token id that was never
    ///      minted. Deliberately non-reverting: this is the read every integrator puts on a hot path,
    ///      and a view that reverts on an unknown id invites callers to wrap it in a try/catch whose
    ///      failure branch is untested. Zero already means "nobody may use this token", which is the
    ///      correct, fail-closed answer in both cases.
    ///
    ///      The comparison is `>=`, matching the ERC-4907 reference implementation: an entitlement
    ///      expiring at exactly `block.timestamp` is still live for that block. `setUser` refuses to
    ///      create such an entitlement, so this branch only matters for integrators comparing this
    ///      implementation against the reference.
    /// @param tokenId Token to query.
    /// @return The current user, or the zero address.
    function userOf(uint256 tokenId) external view returns (address) {
        UserInfo memory info = _userInfo[tokenId];
        if (uint256(info.expires) >= block.timestamp) return info.user;
        return address(0);
    }

    /// @inheritdoc IERC4907
    /// @dev Returns the raw stored expiry, including one already in the past, so a UI can show
    ///      "expired at" rather than only "not rented". Zero means no entitlement was ever set, or
    ///      the last one was cleared. Non-reverting for the same reason as `userOf`.
    /// @param tokenId Token to query.
    /// @return The stored expiry timestamp, or zero.
    function userExpires(uint256 tokenId) external view returns (uint256) {
        return _userInfo[tokenId].expires;
    }

    /*//////////////////////////////////////////////////////////////
                                METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice The prefix `tokenURI` is built on.
    /// @return The current base URI.
    function baseTokenURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    /// @notice Collection-level metadata document, as consumed by marketplaces.
    /// @return The current contract URI.
    function contractURI() external view returns (string memory) {
        return _collectionURI;
    }

    /// @inheritdoc IHoodPups
    function metadataFrozen() external view returns (bool) {
        return _metadataFrozen;
    }

    /// @notice Replace the `tokenURI` prefix.
    /// @dev Timelocked: `METADATA_ADMIN_ROLE` is held by the `TimelockController` in production, so
    ///      every URI change is queued publicly for the full delay before it can execute. Permanently
    ///      reverts once metadata is frozen.
    ///
    ///      No-op writes are allowed here (unlike the pause flags) because a "change" that resolves
    ///      to the same string is a plausible outcome of a legitimate re-deploy of an off-chain
    ///      metadata service, and rejecting it would strand a timelock proposal for no security gain.
    /// @param next The new base URI.
    function setBaseURI(string calldata next) external onlyRole(METADATA_ADMIN_ROLE) {
        if (_metadataFrozen) revert MetadataFrozen();

        string memory previous = _baseTokenURI;
        _baseTokenURI = next;
        emit BaseURIUpdated(previous, next);
    }

    /// @notice Replace the collection metadata URI.
    /// @dev Same timelocked, freeze-respecting rules as `setBaseURI`.
    /// @param next The new contract URI.
    function setContractURI(string calldata next) external onlyRole(METADATA_ADMIN_ROLE) {
        if (_metadataFrozen) revert MetadataFrozen();

        string memory previous = _collectionURI;
        _collectionURI = next;
        emit ContractURIUpdated(previous, next);
    }

    /// @notice Permanently lock both metadata URIs.
    /// @dev IRREVERSIBLE. There is no unfreeze function, and adding one would defeat the only
    ///      guarantee this call provides: that holders can verify, on chain and forever, that nobody
    ///      — including governance — can repoint their token's metadata afterwards. Calling it twice
    ///      reverts, so a duplicated timelock execution cannot emit a second, misleading
    ///      `MetadataFrozenForever`.
    function freezeMetadata() external onlyRole(METADATA_ADMIN_ROLE) {
        if (_metadataFrozen) revert MetadataFrozen();

        _metadataFrozen = true;
        emit MetadataFrozenForever();
    }

    /// @notice Metadata document for one token.
    /// @dev Built as `baseTokenURI + tokenId` by the inherited ERC-721 implementation. Per-token URIs
    ///      are deliberately not stored: thousands of individually settable strings would be an
    ///      admin-controlled surface with no benefit, since the off-chain document is what actually
    ///      carries the provenance fields (inscription txid/index, root key, token id, tour state,
    ///      and the disclaimer that this contract neither owns nor custodies the Bitcoin
    ///      inscription).
    /// @param tokenId Token to describe.
    /// @return The metadata URI for `tokenId`.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return super.tokenURI(tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              MINT PAUSING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPups
    function mintingPaused() external view returns (bool) {
        return _mintingPaused;
    }

    /// @notice Stop new mints. Affects nothing else.
    /// @dev Held by the guardian multisig so an incident response is fast. It cannot unpause, cannot
    ///      touch metadata, cannot move a token and cannot grant itself anything: `PAUSER_ROLE`'s
    ///      entire authority is this one boolean.
    function pauseMinting() external onlyRole(PAUSER_ROLE) {
        if (_mintingPaused) revert MintPauseUnchanged(true);

        _mintingPaused = true;
        emit MintingPauseUpdated(true);
    }

    /// @notice Allow mints again.
    /// @dev Gated on `DEFAULT_ADMIN_ROLE`, i.e. the timelock, not on `PAUSER_ROLE`. Pausing must be
    ///      fast; resuming risk-taking must be deliberate and publicly visible for the full timelock
    ///      delay. This asymmetry is why a compromised guardian can only cost liveness.
    function unpauseMinting() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_mintingPaused) revert MintPauseUnchanged(false);

        _mintingPaused = false;
        emit MintingPauseUpdated(false);
    }

    /*//////////////////////////////////////////////////////////////
                                 ERC-165
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC-165 interface detection.
    /// @dev Advertises ERC-721, ERC-721 Metadata, ERC-165, AccessControl and ERC-4907.
    ///      It deliberately does NOT advertise `ERC721Enumerable` (`0x780e9d63`), and the contract
    ///      does not inherit it: `totalSupply` / `tokenByIndex` add an O(n) write to every transfer
    ///      to serve data an indexer already has, and — worse — advertising an interface whose
    ///      functions do not exist would make a marketplace call into a revert. The unit suite
    ///      asserts both halves of that claim.
    /// @param interfaceId The ERC-165 identifier being queried.
    /// @return True if this contract implements `interfaceId`.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return interfaceId == type(IERC4907).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev OpenZeppelin 5.x routes every mint, transfer and burn through `_update`. The pre-v5
    ///      `_beforeTokenTransfer` hook does not exist in this version, so this is the only correct
    ///      place to clear ERC-4907 state.
    ///
    ///      The clear is conditioned on the owner ACTUALLY changing, for two reasons. A mint
    ///      (`previousOwner == address(0)`) must not emit a spurious `UpdateUser`, which would make
    ///      every mint look like a rental change to an indexer. And a self-transfer
    ///      (`previousOwner == to`) is not a change of custody, so silently cancelling a live rental
    ///      would be a surprising side effect the standard does not call for.
    ///
    ///      The second condition — that a user is actually recorded — keeps ordinary transfers of
    ///      never-rented tokens from emitting a no-op event. Note that an EXPIRED entitlement is
    ///      still cleared: leaving stale rental state attached to a token under new ownership would
    ///      be a trap for anyone reading `userExpires` directly.
    /// @param to Address receiving the token.
    /// @param tokenId Token being moved.
    /// @param auth Address whose authorization is being checked by the base implementation.
    /// @return previousOwner The owner before this update.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address previousOwner) {
        previousOwner = super._update(to, tokenId, auth);

        if (previousOwner != to && _userInfo[tokenId].user != address(0)) {
            delete _userInfo[tokenId];
            emit UpdateUser(tokenId, address(0), 0);
        }
    }

    /// @dev Prefix for `tokenURI`.
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @dev Existence check that does not depend on ownership.
    ///      Ids are assigned strictly sequentially from 1 and there is no burn, so "minted" is
    ///      exactly "1 <= tokenId < _nextTokenId". Deriving it arithmetically rather than reading
    ///      `_ownerOf` keeps the answer correct even for a token whose owner is momentarily being
    ///      rewritten inside `_update`.
    /// @param tokenId Token to check.
    function _requireKnown(uint256 tokenId) private view {
        if (tokenId == 0 || tokenId >= _nextTokenId) revert UnknownToken(tokenId);
    }
}
