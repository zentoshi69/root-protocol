// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @title Receivers
/// @notice Hostile and awkward ETH / ERC-721 recipients used across the suites.
/// @dev TEST-ONLY. Never import any of these from `src/`.
///
///      These exist to prove a specific class of claim: that no user can wedge the protocol by
///      choosing a payout or mint destination that misbehaves. Settlement must never depend on an
///      arbitrary address's fallback succeeding, and a refund must never be blockable.

/// @notice Rejects every ETH transfer.
/// @dev Models a seller whose payout address is a contract with no payable fallback — the case
///      that forces the protocol to use pull payments rather than pushing ETH at settlement time.
contract RejectingReceiver {
    /// @notice Raised on any incoming ETH.
    error EthRejected();

    receive() external payable {
        revert EthRejected();
    }

    fallback() external payable {
        revert EthRejected();
    }
}

/// @notice Burns gas on receive until it runs out, or up to a configured budget.
/// @dev Models the 2300-stipend trap: a recipient that succeeds under `call{value:}` with full gas
///      but fails under a gas-limited `transfer`/`send`. Suites use it to prove withdrawals
///      forward enough gas, and to prove one greedy recipient cannot drain a batch.
contract GasGuzzlingReceiver {
    /// @notice Number of storage-write iterations to perform on each receive.
    uint256 public burnIterations;

    /// @notice Scratch storage; writing to it is what actually costs the gas.
    mapping(uint256 => uint256) public scratch;

    /// @notice Total ETH received.
    uint256 public totalReceived;

    /// @param initialBurnIterations Iterations to burn per receive.
    constructor(uint256 initialBurnIterations) {
        burnIterations = initialBurnIterations;
    }

    /// @notice Change how much gas each receive burns.
    /// @param next New iteration count. Zero makes this a plain, well-behaved receiver.
    function setBurnIterations(uint256 next) external {
        burnIterations = next;
    }

    receive() external payable {
        totalReceived += msg.value;
        uint256 n = burnIterations;
        for (uint256 i = 0; i < n; i++) {
            scratch[i] = scratch[i] + 1;
        }
    }
}

/// @notice Calls back into a configured target on receive.
/// @dev The canonical reentrancy probe. Point it at, for example, `PayoutVault.withdraw` and
///      assert the guard fires. `attempts`/`succeeded` let a suite distinguish "the callback never
///      ran" from "the callback ran and was correctly rejected" — an important distinction,
///      because a test that silently never reenters proves nothing.
contract ReenteringReceiver {
    /// @notice Contract to call back into.
    address public target;
    /// @notice Calldata to send on the callback.
    bytes public payload;
    /// @notice Maximum number of callbacks to attempt, so a test cannot loop forever.
    uint256 public maxAttempts;
    /// @notice How many callbacks were attempted.
    uint256 public attempts;
    /// @notice How many callbacks returned successfully.
    uint256 public succeeded;
    /// @notice Return/revert data of the most recent callback.
    bytes public lastReturnData;

    /// @param initialTarget Contract to reenter.
    /// @param initialPayload Calldata for the reentrant call.
    /// @param initialMaxAttempts Callback attempt ceiling.
    constructor(address initialTarget, bytes memory initialPayload, uint256 initialMaxAttempts) {
        target = initialTarget;
        payload = initialPayload;
        maxAttempts = initialMaxAttempts;
    }

    /// @notice Reconfigure the callback.
    /// @param nextTarget Contract to reenter.
    /// @param nextPayload Calldata for the reentrant call.
    /// @param nextMaxAttempts Callback attempt ceiling.
    function configure(address nextTarget, bytes calldata nextPayload, uint256 nextMaxAttempts) external {
        target = nextTarget;
        payload = nextPayload;
        maxAttempts = nextMaxAttempts;
    }

    /// @notice Reset the attempt counters between phases of a test.
    function resetCounters() external {
        attempts = 0;
        succeeded = 0;
        delete lastReturnData;
    }

    /// @notice Make the first, non-reentrant call that starts the sequence.
    /// @param callee Contract to call.
    /// @param data Calldata to send.
    /// @return ok Whether the call succeeded.
    /// @return ret Return or revert data.
    function kick(address callee, bytes calldata data) external returns (bool ok, bytes memory ret) {
        (ok, ret) = callee.call(data);
        lastReturnData = ret;
    }

    receive() external payable {
        if (target == address(0) || attempts >= maxAttempts) return;
        attempts++;
        // Deliberately swallow the failure: the guard is expected to revert, and bubbling it up
        // would abort the outer withdrawal and hide which of the two calls actually failed.
        (bool ok, bytes memory ret) = target.call(payload);
        lastReturnData = ret;
        if (ok) succeeded++;
    }
}

/// @notice ERC-721 receiver with selectable good and bad behaviour.
/// @dev `ACCEPT` is the good variant. `WRONG_SELECTOR` and `REVERT_ON_RECEIVE` are the two ways a
///      real receiver breaks `_safeMint`, and a mint path must handle both rather than silently
///      stranding a token at an address that cannot move it.
contract MockERC721Receiver is IERC721Receiver {
    /// @notice How this receiver responds to `onERC721Received`.
    enum Behaviour {
        ACCEPT,
        WRONG_SELECTOR,
        REVERT_ON_RECEIVE
    }

    /// @notice Raised by the `REVERT_ON_RECEIVE` behaviour.
    error ReceiverRejected();

    /// @notice Current behaviour.
    Behaviour public behaviour;

    /// @notice Number of tokens received.
    uint256 public receivedCount;
    /// @notice Operator of the most recent receive.
    address public lastOperator;
    /// @notice Previous holder of the most recent receive.
    address public lastFrom;
    /// @notice Token id of the most recent receive.
    uint256 public lastTokenId;
    /// @notice Data payload of the most recent receive.
    bytes public lastData;

    /// @param initialBehaviour Behaviour to start with.
    constructor(Behaviour initialBehaviour) {
        behaviour = initialBehaviour;
    }

    /// @notice Switch behaviour mid-test.
    /// @param next The behaviour to adopt.
    function setBehaviour(Behaviour next) external {
        behaviour = next;
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4)
    {
        if (behaviour == Behaviour.REVERT_ON_RECEIVE) revert ReceiverRejected();

        receivedCount++;
        lastOperator = operator;
        lastFrom = from;
        lastTokenId = tokenId;
        lastData = data;

        if (behaviour == Behaviour.WRONG_SELECTOR) return bytes4(0xdeadbeef);
        return IERC721Receiver.onERC721Received.selector;
    }
}
