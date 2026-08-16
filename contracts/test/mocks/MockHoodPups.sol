// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC4907, IHoodPups} from "../../src/interfaces/IHoodPups.sol";
import {PuppetHashing} from "../../src/types/PuppetHashing.sol";
import {PuppetTypes} from "../../src/types/PuppetTypes.sol";

/// @title MockHoodPups
/// @notice Minimal `IHoodPups` implementation for FeeRouter, escrow and tour suites.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      HONESTY NOTE: this is NOT an ERC-721. There are no transfers, no approvals, no
///      `safeTransferFrom` receiver callbacks and no metadata. Suites that care about ERC-721
///      semantics (or about `safeMint` reaching an `onERC721Received` hook) must use the real
///      `HoodPups` contract; those behaviours cannot be proven against this mock.
///
///      It DOES keep the one rule the whole protocol rests on: one canonical Bitcoin Puppet
///      inscription mints at most one HoodPup, ever. `mintRooted` reverts `RootAlreadyMinted` on
///      a second attempt, exactly like production, because a mock that let a Root mint twice
///      would let a broken escrow pass its tests.
contract MockHoodPups is IHoodPups {
    struct MintCall {
        address recipient;
        bytes32 rootKey;
        uint256 tokenId;
        address caller;
    }

    mapping(bytes32 => uint256) private _tokenOfRoot;
    mapping(uint256 => PuppetTypes.RootId) private _rootOf;
    mapping(uint256 => bytes32) private _rootKeyOf;
    mapping(uint256 => address) private _ownerOf;

    mapping(uint256 => address) private _user;
    mapping(uint256 => uint64) private _userExpires;

    uint256 private _nextTokenId = 1;
    bool private _mintingPaused;
    bool private _metadataFrozen;

    /// @notice Number of successful mints, for call-count assertions.
    uint256 public mintCount;

    MintCall private _lastMint;

    /*//////////////////////////////////////////////////////////////
                             TEST MUTATORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Toggle the mint pause. Never affects any read path.
    /// @param paused True to make `mintRooted` revert `MintingPaused`.
    function setMintingPaused(bool paused) external {
        _mintingPaused = paused;
        emit MintingPauseUpdated(paused);
    }

    /// @notice Permanently freeze metadata, so freeze-related assertions have something to read.
    function freezeMetadata() external {
        _metadataFrozen = true;
        emit MetadataFrozenForever();
    }

    /// @notice Details of the most recent successful mint.
    function lastMint() external view returns (MintCall memory) {
        return _lastMint;
    }

    /// @notice Nominal owner of a token. Convenience only; this mock is not a real ERC-721.
    /// @param tokenId Token to look up.
    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _ownerOf[tokenId];
        if (owner == address(0)) revert UnknownToken(tokenId);
        return owner;
    }

    /*//////////////////////////////////////////////////////////////
                                MINTING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPups
    /// @dev NOT role gated in the mock; the real contract requires `MINTER_ROLE`.
    function mintRooted(address recipient, PuppetTypes.RootId calldata root) external returns (uint256 tokenId) {
        if (_mintingPaused) revert MintingPaused();
        return _mintRooted(recipient, root);
    }

    /// @inheritdoc IHoodPups
    function mintRootedTerminal(address recipient, PuppetTypes.RootId calldata root)
        external
        returns (uint256 tokenId)
    {
        return _mintRooted(recipient, root);
    }

    function _mintRooted(address recipient, PuppetTypes.RootId calldata root) private returns (uint256 tokenId) {
        if (recipient == address(0)) revert ZeroAddress();

        bytes32 key = PuppetHashing.rootKey(root.inscriptionTxid, root.inscriptionIndex);
        uint256 existing = _tokenOfRoot[key];
        if (existing != 0) revert RootAlreadyMinted(key, existing);

        tokenId = _nextTokenId++;
        _tokenOfRoot[key] = tokenId;
        _rootOf[tokenId] = root;
        _rootKeyOf[tokenId] = key;
        _ownerOf[tokenId] = recipient;

        mintCount++;
        _lastMint = MintCall({recipient: recipient, rootKey: key, tokenId: tokenId, caller: msg.sender});

        emit RootedMint(tokenId, key, recipient, root.inscriptionTxid, root.inscriptionIndex);
    }

    /*//////////////////////////////////////////////////////////////
                              ROOT QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IHoodPups
    function rootMinted(bytes32 rootKey) external view returns (bool) {
        return _tokenOfRoot[rootKey] != 0;
    }

    /// @inheritdoc IHoodPups
    function tokenOfRoot(bytes32 rootKey) external view returns (uint256) {
        return _tokenOfRoot[rootKey];
    }

    /// @inheritdoc IHoodPups
    function rootOf(uint256 tokenId) external view returns (PuppetTypes.RootId memory) {
        if (_ownerOf[tokenId] == address(0)) revert UnknownToken(tokenId);
        return _rootOf[tokenId];
    }

    /// @inheritdoc IHoodPups
    function rootKeyOf(uint256 tokenId) external view returns (bytes32) {
        if (_ownerOf[tokenId] == address(0)) revert UnknownToken(tokenId);
        return _rootKeyOf[tokenId];
    }

    /// @inheritdoc IHoodPups
    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    /// @inheritdoc IHoodPups
    function mintingPaused() external view returns (bool) {
        return _mintingPaused;
    }

    /// @inheritdoc IHoodPups
    function metadataFrozen() external view returns (bool) {
        return _metadataFrozen;
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-4907 USER ROLE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC4907
    /// @dev Only the nominal owner may set a user here. Approval semantics are not modelled.
    function setUser(uint256 tokenId, address user, uint64 expires) external {
        address owner = _ownerOf[tokenId];
        if (owner == address(0)) revert UnknownToken(tokenId);
        if (msg.sender != owner) revert NotOwnerNorApproved(msg.sender, tokenId);
        if (user == owner) revert UserIsOwner();
        if (expires != 0 && expires <= block.timestamp) revert ExpiryInPast(expires, block.timestamp);

        _user[tokenId] = user;
        _userExpires[tokenId] = expires;
        emit UpdateUser(tokenId, user, expires);
    }

    /// @inheritdoc IERC4907
    function userOf(uint256 tokenId) external view returns (address) {
        return _userExpires[tokenId] >= block.timestamp ? _user[tokenId] : address(0);
    }

    /// @inheritdoc IERC4907
    function userExpires(uint256 tokenId) external view returns (uint256) {
        return _userExpires[tokenId];
    }
}
