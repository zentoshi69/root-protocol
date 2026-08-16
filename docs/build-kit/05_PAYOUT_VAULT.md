# CODEX CONTRACT PROMPT 05 — PAYOUT VAULT

Implement a non-custodial accounting vault for ETH credits. Settlement contracts must never depend on arbitrary recipient fallback functions succeeding.

## Contract

Create:

```text
contracts/src/PayoutVault.sol
```

Use OpenZeppelin 5.x `AccessControl`, `EIP712`, `SignatureChecker`, and `ReentrancyGuard`. Do not make it upgradeable.

## Accounting model

Maintain:

```text
claimable[address] -> uint256
pendingByRoot[bytes32] -> uint256
totalLiability -> uint256
withdrawalNonce[address] -> uint256
```

The invariant is:

```text
address(this).balance >= totalLiability
```

All normal credits increase both the relevant balance and `totalLiability`. Withdrawals reduce both before the external call.

## Roles

```text
CREDITOR_ROLE
ROOT_RELEASER_ROLE
EXCESS_SWEEPER_ROLE
```

The pausing design may block new credits in an emergency, but it must never block withdrawals.

## Crediting

Implement:

```text
credit(address beneficiary) payable
creditRoot(bytes32 rootKey) payable
creditBatch(address[] beneficiaries, uint256[] amounts) payable
```

Requirements:

- zero beneficiary rejected;
- zero root key rejected;
- sum of batch amounts exactly equals `msg.value`;
- only `CREDITOR_ROLE` may call;
- explicit events for every credit;
- no raw `receive()` path; unexpected direct ETH should revert when possible.

Forced ETH may still arrive through EVM mechanics. It must not become a user liability.

## Root release

Implement:

```text
releaseRootCredit(bytes32 rootKey, address beneficiary)
```

Only `ROOT_RELEASER_ROLE` may call. Move accounting from `pendingByRoot` to `claimable` without changing `totalLiability` or moving ETH. Reject zero beneficiary.

## Withdrawals

Implement:

```text
withdraw(uint256 amount)
withdrawAll()
withdrawTo(address payable recipient, uint256 amount)
withdrawWithAuthorization(
    address beneficiary,
    address payable recipient,
    uint256 amount,
    uint256 nonce,
    uint64 deadline,
    bytes signature
)
```

For gasless authorization, use EIP-712:

```text
Withdrawal(address beneficiary,address recipient,uint256 amount,uint256 nonce,uint64 deadline)
```

Verify with `SignatureChecker.isValidSignatureNow` so EOAs and ERC-1271 smart accounts work. Increment nonce before transfer. Use checks-effects-interactions and `ReentrancyGuard`.

If the recipient rejects ETH, revert and restore all accounting automatically through transaction rollback.

## Excess ETH

Implement a timelocked `sweepExcess` that can move only:

```text
address(this).balance - totalLiability
```

It must never touch liabilities. Emit the exact amount swept. Document that this exists only for forced/unaccounted ETH.

## Tests and invariants

Cover:

- credit and batch credit;
- exact batch sum;
- root credit/release;
- normal withdrawal;
- gasless withdrawal;
- EIP-1271 mock wallet;
- nonce replay;
- expired signature;
- wrong recipient/amount;
- reentrant recipient;
- rejecting recipient;
- unauthorized credit/release/sweep;
- forced ETH and excess sweep;
- withdrawals available while crediting is paused;
- stateful invariant `balance >= totalLiability`;
- no admin path can reduce a user’s claimable balance.

Run format, build, tests, invariants, and static analysis. Return the final accounting equations in the summary.
