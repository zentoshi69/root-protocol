// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PuppetTypes} from "../types/PuppetTypes.sol";

/// @notice EIP-4907 rental / temporary-user standard.
interface IERC4907 {
    /// @notice Emitted when the user of an NFT or its expiry changes.
    event UpdateUser(uint256 indexed tokenId, address indexed user, uint64 expires);

    /// @notice Grant temporary use rights without transferring ownership.
    function setUser(uint256 tokenId, address user, uint64 expires) external;

    /// @notice Current user, or the zero address once the term has elapsed.
    function userOf(uint256 tokenId) external view returns (address);

    /// @notice Timestamp at which the current user's rights lapse.
    function userExpires(uint256 tokenId) external view returns (uint256);
}

/// @title IHoodPups
/// @notice ERC-721 where each token permanently references exactly one Bitcoin Puppet inscription.
/// @dev A HoodPup is a derived Robinhood Chain asset. It is NOT the Bitcoin inscription, it does
///      not custody it, and holding one confers no rights over it.
interface IHoodPups is IERC4907 {
    error ZeroAddress();
    error RootAlreadyMinted(bytes32 rootKey, uint256 tokenId);
    error UnknownToken(uint256 tokenId);
    error MintingPaused();
    error MetadataFrozen();
    error NotOwnerNorApproved(address caller, uint256 tokenId);
    error UserIsOwner();
    error ExpiryInPast(uint64 expires, uint256 nowTs);

    event RootedMint(
        uint256 indexed tokenId, bytes32 indexed rootKey, address indexed recipient, bytes32 rootTxid, uint32 rootIndex
    );
    event BaseURIUpdated(string previous, string next);
    event ContractURIUpdated(string previous, string next);
    event MetadataFrozenForever();
    event MintingPauseUpdated(bool paused);

    /// @notice Mint the single HoodPup for `root`. Requires `MINTER_ROLE`.
    function mintRooted(address recipient, PuppetTypes.RootId calldata root) external returns (uint256 tokenId);

    /// @notice Mint for an already-active BTC solver reservation even while ordinary minting is paused.
    /// @dev Requires `MINTER_ROLE`. The authorized escrow exposes this only after consuming the
    ///      matching Bitcoin-payment attestation, so this resolves existing risk rather than
    ///      accepting a new mint obligation.
    function mintRootedTerminal(address recipient, PuppetTypes.RootId calldata root) external returns (uint256 tokenId);

    /// @notice True once a Root has produced its HoodPup. Permanent.
    function rootMinted(bytes32 rootKey) external view returns (bool);

    /// @notice Token id for a Root, or zero. Ids start at 1 so zero is unambiguous.
    function tokenOfRoot(bytes32 rootKey) external view returns (uint256);

    /// @notice The Bitcoin inscription a token references.
    function rootOf(uint256 tokenId) external view returns (PuppetTypes.RootId memory);

    /// @notice Canonical root key a token references.
    function rootKeyOf(uint256 tokenId) external view returns (bytes32);

    /// @notice Next id that will be assigned.
    function nextTokenId() external view returns (uint256);

    /// @notice True while `mintRooted` is disabled. Transfers are never affected.
    function mintingPaused() external view returns (bool);

    /// @notice True once metadata URIs are permanently locked.
    function metadataFrozen() external view returns (bool);
}
