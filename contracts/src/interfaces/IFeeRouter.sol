// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IFeeRouter
/// @notice The immutable 50 / 25 / 25 economic split.
/// @dev Percentages are compile-time constants with no setter and no upgrade path. Only the two
///      treasury destination addresses are governable, and only through the timelock.
interface IFeeRouter {
    error ZeroAddress();
    error ValueMismatch(uint256 expected, uint256 provided);
    error RoutingResidue(uint256 residue);
    error DirectDepositRejected();

    event MintRouted(
        bytes32 indexed rootKey,
        address indexed sellerOrSolver,
        uint8 route,
        uint256 gross,
        uint256 sellerAmount,
        uint256 puppetTreasuryAmount,
        uint256 protocolAmount
    );
    event RecurringRouted(
        bytes32 indexed rootKey,
        address indexed beneficiary,
        bool beneficiaryActive,
        uint256 gross,
        uint256 rootAmount,
        uint256 puppetTreasuryAmount,
        uint256 protocolAmount
    );
    event TreasuryUpdated(address indexed previous, address indexed next, bool isProtocol);

    /// @notice 5000.
    function SELLER_BPS() external view returns (uint256);
    /// @notice 2500.
    function PUPPET_TREASURY_BPS() external view returns (uint256);
    /// @notice 2500.
    function PROTOCOL_BPS() external view returns (uint256);
    /// @notice 10000.
    function BPS_DENOMINATOR() external view returns (uint256);

    /// @notice Current Bitcoin Puppets ecosystem treasury address.
    function puppetTreasury() external view returns (address);
    /// @notice Current protocol treasury address.
    function protocolTreasury() external view returns (address);

    /// @notice Split `gross` into its three parts.
    /// @dev Seller and treasury are floor-divided; protocol absorbs the rounding remainder, so
    ///      `seller + puppetTreasuryAmount + protocolAmount == gross` holds for every input.
    function quote(uint256 gross)
        external
        pure
        returns (uint256 sellerAmount, uint256 puppetTreasuryAmount, uint256 protocolAmount);

    /// @notice Route a completed EVM-payout mint. Requires `ROUTER_CALLER_ROLE`.
    function routeMintEvm(bytes32 rootKey, address seller, uint256 gross) external payable;

    /// @notice Route a completed native-BTC mint; the seller share reimburses the solver.
    /// @dev Bob was already paid in BTC off chain, so the 50% share belongs to the solver that
    ///      fronted it. Requires `ROUTER_CALLER_ROLE`.
    function routeMintBtc(bytes32 rootKey, address solver, uint256 gross) external payable;

    /// @notice Route recurring Root-linked value. Requires `ROUTER_CALLER_ROLE`.
    /// @dev Root share goes to the active beneficiary, or to the Root's pending bucket when no
    ///      owner is currently verified.
    function routeRecurring(bytes32 rootKey, uint256 gross) external payable;
}
