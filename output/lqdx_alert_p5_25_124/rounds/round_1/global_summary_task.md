You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
No global memory yet.

## Latest Round Summary
# Round 1 Summary

## Agent: codex_1
- files touched: `0x364f17a23ae4350319b7491224d10df5796190bc/contracts/LiquidXv2Zap.sol`
- files revisited / highest-attention files: `LiquidXv2Zap.sol`, especially `deposit()`, `withdraw()`, `_depositSwap()`, `_addBalance()`, `withdrawToken()`, and operator-setting paths
- main issue directions investigated: arbitrary `tokenOut` on withdrawal, missing caller authorization for `account`, zero-minimum half-swap sandwichability, operator drainability of custodial basket assets, and broken native-ETH withdrawal flow
- promising but not retained directions: none clearly visible in the log beyond the retained findings set

## Agent: opencode_1
- files touched: `0x364f17a23ae4350319b7491224d10df5796190bc/contracts/LiquidXv2Zap.sol` (after an initial failed read on a wrong path)
- files revisited / highest-attention files: `LiquidXv2Zap.sol`, with repeated attention on `withdrawToken()`, `_depositSwap()`, `deposit()`, `withdraw()`, `_calculateSwapAmount()`, `receive()`, and `setOperatorSetter()`
- main issue directions investigated: operator asset drain, zero-slippage swap exposure, basket/withdraw authorization concerns, deadline/slippage handling, arithmetic edge cases, and ETH/accounting edge cases
- promising but not retained directions: identical-token input validation, overflow in `_calculateSwapAmount()`, operator withdrawal from user baskets, `block.timestamp` deadline usage, callback-based balance manipulation, refund underflow, untracked `receive()` ETH, and reward-claim handling

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `LiquidXv2Zap.sol` withdrawal/deposit flows, especially `_depositSwap()` slippage exposure and `withdrawToken()` operator-controlled asset movement
- notable differences in attention: `codex_1` centered on concrete fund-theft and broken-flow issues tied to basket custody, arbitrary `tokenOut`, and missing `account` authorization; `opencode_1` cast a wider net over validation, arithmetic, admin-role, and accounting edge cases, many of which were not retained
- underexplored but suspicious files/functions if clearly supported by the logs: within the only in-scope file, `_calculateSwapAmount()`, `receive()`, and `setOperatorSetter()` were flagged by one agent but not retained after merge

## Retained Findings
- retained issues from this round center on `LiquidXv2Zap.sol` allowing withdrawal-time theft via arbitrary `tokenOut`, unauthorized use of third-party approvals in `deposit()`/`withdraw()`, sandwichable deposit half-swaps due to `amountOutMin = 0`, operator-drainable custodial basket/residual assets through `withdrawToken()`, and a broken native-ETH withdrawal path for non-WETH pairs


Output only markdown.
