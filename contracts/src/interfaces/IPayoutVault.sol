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
    /// @notice Emitted alongside `Credited` when the credit is a refund, so indexers can tell a
    ///         buyer being made whole apart from a seller being paid.
    event RefundCredited(address indexed beneficiary, uint256 amount, address indexed creditor);
    /// @notice Emitted alongside `Credited` when an existing cross-chain obligation is finalized.
    /// @dev Terminal credits deliberately remain executable while ordinary liability creation is
    ///      paused. Authorized callers may use them only after the protocol has already incurred
    ///      an irreversible obligation, such as a solver payment or a bond resolution.
    event TerminalCredited(address indexed beneficiary, uint256 amount, address indexed creditor);
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

    /// @notice Credit `beneficiary` with `msg.value`. Requires `CREDITOR_ROLE`. Pausable.
    function credit(address beneficiary) external payable;

    /// @notice Credit a refund. Requires `CREDITOR_ROLE`. Deliberately NOT pausable.
    /// @dev A refund releases an obligation the beneficiary already holds rather than creating a
    ///      new one, so the credit pause must not reach it (protocol invariant I12).
    function creditRefund(address beneficiary) external payable;

    /// @notice Credit an obligation that existed before the current transaction.
    /// @dev Requires `CREDITOR_ROLE`. Deliberately NOT pausable so incident response cannot strand
    ///      a solver after an irreversible Bitcoin payment or block terminal bond accounting.
    function creditTerminal(address beneficiary) external payable;

    /// @notice Credit a Root's pending bucket with `msg.value`. Requires `CREDITOR_ROLE`.
    function creditRoot(bytes32 rootKey) external payable;

    /// @notice Credit several beneficiaries in one call. `sum(amounts)` must equal `msg.value`.
    function creditBatch(address[] calldata beneficiaries, uint256[] calldata amounts) external payable;

    /// @notice Batch form of `creditTerminal`; `sum(amounts)` must equal `msg.value`.
    /// @dev Requires `CREDITOR_ROLE` and deliberately remains live while paused.
    function creditTerminalBatch(address[] calldata beneficiaries, uint256[] calldata amounts) external payable;

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
