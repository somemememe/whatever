# Round 1 Summary

## Agent: codex_1
- files touched: `WiseLending.sol`, `WiseCore.sol`, `MainHelper.sol`, `WiseLowLevelHelper.sol`, `PoolManager.sol`, `WiseLendingDeclaration.sol`, `TransferHub/CallOptionalReturn.sol`, `TransferHub/TransferHelper.sol`
- files revisited / highest-attention files: `WiseLending.sol`, `WiseCore.sol`, `MainHelper.sol`
- main issue directions investigated: deposit/payback/liquidation transfer accounting, WETH deposit sync behavior, liquidation bookkeeping, isolation-pool liquidation trust boundaries, NFT-position token list cleanup and dusting, borrow gating via `allowBorrow`
- promising but not retained directions: `allowBorrow` enforcement in `PoolManager`/borrow paths remained low-confidence and was not retained after merge

## Agent: opencode_1
- files touched: broad read across all Solidity files, with explicit reads of `WiseLending.sol`, `WiseCore.sol`, `InterfaceHub/IWiseSecurity.sol`, `MainHelper.sol`, `PoolManager.sol`, `WiseLendingDeclaration.sol`, `WiseLowLevelHelper.sol`, `OwnableMaster.sol`, `TransferHub/TransferHelper.sol`, `TransferHub/CallOptionalReturn.sol`, `Babylonian.sol`, `InterfaceHub/IWiseOracleHub.sol`
- files revisited / highest-attention files: `WiseLending.sol`, `WiseCore.sol`, `MainHelper.sol`, `IWiseSecurity.sol`
- main issue directions investigated: liquidation/reentrancy, oracle and liquidation pricing assumptions, share math edge cases, approval/access control, position-lock consistency, allowance handling, LASA/timestamp manipulation
- promising but not retained directions: reentrancy in liquidation, oracle-manipulation/staleness claims, approval/access-control issues, allowance race ideas, LASA manipulation, and other broad economic concerns were proposed but not retained

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `WiseLending.sol`, `WiseCore.sol`, and `MainHelper.sol`, especially deposit/borrow/liquidation/accounting flows
- notable differences in attention: `codex_1` focused on concrete state/accounting mismatches and isolation-pool paths; `opencode_1` spread attention across broader themes such as reentrancy, oracle design, approvals, and LASA behavior
- underexplored but suspicious files/functions if clearly supported by the logs: `PoolManager.sol` borrow gating (`allowBorrow`) was only raised as a low-confidence direction; `IWiseSecurity.sol`-dependent checks were read and referenced but did not produce retained issues this round

## Retained Findings
- retained issues centered on concrete accounting and liquidation defects in the core lending flow
- retained high-severity items were: transfer-in accounting trusting nominal amounts/false-return ERC20s, stale-price WETH minting in `depositExactAmountETHMint`, and verified isolation-pool liquidation terms bypassing normal repayment/liquidation invariants
- retained medium-severity items were: liquidation residual shares being booked under the wrong NFT metadata, and arbitrary NFT dusting combining with `uint8` token-list cleanup to create a potential exit freeze once enough markets are listed
