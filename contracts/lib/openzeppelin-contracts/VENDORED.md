# Vendored dependency boundary

This directory contains OpenZeppelin Contracts 5.1.0, pinned as Solidity source for Foundry through
`contracts/remappings.txt`. The upstream JavaScript development toolchain is not installed, executed,
or part of this repository's pnpm workspace. Its root `package.json` and `package-lock.json` are
intentionally omitted so GitHub's dependency graph does not report the unused upstream test and
release dependencies as dependencies of deriv.wtf.

The Solidity version remains identifiable in `CHANGELOG.md` and the version headers in `contracts/`.
