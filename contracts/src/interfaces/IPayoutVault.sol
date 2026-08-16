// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IPayoutVault
/// @notice Pull-payment accounting for every ETH obligation the protocol creates.
/// @dev Settlement must never depend on an arbitrary recipient's fallback succeeding: a seller
///      whose payout address is a contract that reverts on receive would otherwise be able to
///      block a mint permanently. Credits are bookkeeping; ETH moves only on withdrawal.
///
///      Core invariant: `address(this).balance >= totalLiability()`.
interface IPayoutVault {
    error ZeroAddress();
    error ZeroRootKey();
    error ZeroAmount();
    error AmountMismatch(uint256 expected, uint256 provided);
    error ArrayLengthMismatch(uint256 a, uint256 b);
    error InsufficientClaimable(address beneficiary, uint256 requested, uint256 available);
    error InsufficientPendingRoot(bytes32 rootKey, uint256 requested, uint256 available);
    error WithdrawalFailed(address recipient, uint256 amount);
    error ExpiredAuthorization(uint64 deadline, uint256 nowTs);
    error InvalidAuthorizationSignature();
    error InvalidNonce(uint256 expected, uint256 provided);
    error NoExcess();
    error DirectDepositRejected();

    event Credited(address indexed beneficiary, uint256 amount, address indexed creditor);
    event RootCredited(bytes32 indexed rootKey, uint256 amount, address indexed creditor);
    event RootCreditReleased(bytes32 indexed rootKey, address indexed beneficiary, uint256 amount);
    event Withdrawn(address indexed beneficiary, address indexed recipient, uint256 amount);
    event WithdrawnWithAuthorization(
        address indexed beneficiary, address indexed recipient, uint256 amount, uint256 nonce, address relayer
    );
    event ExcessSwept(address indexed recipient, uint256 amount);

    /// @notice ETH `beneficiary` may withdraw right now.
    function claimable(address beneficiary) external view returns (uint256);

    /// @notice ETH held for a Root whose Bitcoin owner is not currently verified.
    function pendingByRoot(bytes32 rootKey) external view returns (uint256);

    /// @notice Sum of every obligation the vault owes.
    function totalLiability() external view returns (uint256);

    /// @notice Next expected gasless-withdrawal nonce for `beneficiary`.
    function withdrawalNonce(address beneficiary) external view returns (uint256);

    /// @notice `address(this).balance - totalLiability()`; only force-sent ETH ends up here.
    function excessBalance() external view returns (uint256);

    /// @notice Credit `beneficiary` with `msg.value`. Requires `CREDITOR_ROLE`.
    function credit(address beneficiary) external payable;

    /// @notice Credit a Root's pending bucket with `msg.value`. Requires `CREDITOR_ROLE`.
    function creditRoot(bytes32 rootKey) external payable;

    /// @notice Credit several beneficiaries in one call. `sum(amounts)` must equal `msg.value`.
    function creditBatch(address[] calldata beneficiaries, uint256[] calldata amounts) external payable;

    /// @notice Move a Root's pending bucket to a newly verified beneficiary's claimable balance.
    /// @dev Pure bookkeeping: no ETH moves and `totalLiability` is unchanged.
    ///      Requires `ROOT_RELEASER_ROLE`.
    function releaseRootCredit(bytes32 rootKey, address beneficiary) external returns (uint256 amount);

    /// @notice Withdraw `amount` of your own claimable balance.
    function withdraw(uint256 amount) external;

    /// @notice Withdraw your entire claimable balance.
    function withdrawAll() external;

    /// @notice Withdraw `amount` of your own balance to another address.
    function withdrawTo(address payable recipient, uint256 amount) external;

    /// @notice Withdraw on a beneficiary's behalf against their EIP-712 signature.
    /// @dev Accepts EOA signatures and ERC-1271 smart-account signatures. This is what lets a
    ///      seller who holds zero ETH for gas still get paid.
    function withdrawWithAuthorization(
        address beneficiary,
        address payable recipient,
        uint256 amount,
        uint256 nonce,
        uint64 deadline,
        bytes calldata signature
    ) external;

    /// @notice Move only unaccounted (force-sent) ETH out. Can never touch a liability.
    function sweepExcess(address payable recipient) external returns (uint256 amount);
}
