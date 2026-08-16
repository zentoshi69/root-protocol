// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title MockERC1271Wallet
/// @notice Smart-account stand-in that validates signatures against one configured owner key.
/// @dev TEST-ONLY. Never import this from `src/`.
///
///      This exists for `PayoutVault.withdrawWithAuthorization`: a seller who holds a smart
///      account (Safe, 4337 wallet, or a cold-wallet setup) has no EOA signature to offer, so the
///      vault must accept ERC-1271. A relayer then pays the gas and the seller still gets paid.
///
///      HONESTY NOTE: a real smart account applies its own threshold/owner policy. This mock
///      checks exactly one ECDSA signature, and the `alwaysReject` / `alwaysAccept` switches let a
///      suite drive the two failure directions the vault must survive: a wallet that refuses a
///      valid-looking signature, and a wallet that rubber-stamps anything. The latter is the more
///      important test — it proves the vault's own nonce and deadline checks still bind even when
///      the signature check is worthless.
contract MockERC1271Wallet is IERC1271 {
    /// @dev `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
    bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;

    /// @notice Address whose ECDSA signatures this wallet honours.
    address public owner;
    /// @notice When true, every signature is rejected regardless of validity.
    bool public alwaysReject;
    /// @notice When true, every signature is accepted regardless of validity.
    bool public alwaysAccept;

    /// @notice Total ETH received, so withdrawal-destination tests can assert delivery.
    uint256 public totalReceived;

    /// @param initialOwner Address whose signatures are accepted.
    constructor(address initialOwner) {
        owner = initialOwner;
    }

    /// @notice Change the signing owner.
    /// @param next New owner address.
    function setOwner(address next) external {
        owner = next;
    }

    /// @notice Reject every signature.
    /// @param on True to reject.
    function setAlwaysReject(bool on) external {
        alwaysReject = on;
    }

    /// @notice Accept every signature, including garbage.
    /// @param on True to accept unconditionally.
    function setAlwaysAccept(bool on) external {
        alwaysAccept = on;
    }

    /// @inheritdoc IERC1271
    /// @dev Returns the magic value only on success. Returning `0xffffffff` rather than reverting
    ///      matches how deployed wallets behave and keeps the caller's error path under test.
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue) {
        if (alwaysReject) return 0xffffffff;
        if (alwaysAccept) return MAGIC_VALUE;

        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
        if (err != ECDSA.RecoverError.NoError) return 0xffffffff;
        return recovered == owner ? MAGIC_VALUE : bytes4(0xffffffff);
    }

    receive() external payable {
        totalReceived += msg.value;
    }
}
