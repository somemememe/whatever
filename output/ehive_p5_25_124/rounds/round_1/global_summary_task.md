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
- files touched: `0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol`
- files revisited / highest-attention files: `Contract.sol`, especially `startTrading()`, fee/liquidity paths around `swapBack()` / `_addLiquidity()`, ownership / `teamOROwner` controls, and staking functions `stake()`, `claim()`, `unstake()`, `userEarned()`
- main issue directions investigated: LP-token custody and liquidity withdrawal risk; staking reward-cap enforcement; staking-disablement destroying pending yield; lingering privilege via `_swapFeeReceiver`; zero-slippage fee swaps / MEV exposure; incorrect reward view accounting in `userEarned()`
- promising but not retained directions: none clearly visible from this agent’s log beyond the retained set

## Agent: opencode_1
- files touched: `0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol`
- files revisited / highest-attention files: `Contract.sol` only, with broad pass across token, fee, Uniswap, and staking logic
- main issue directions investigated: staking cap / claim behavior; zero-fee transfer failure path; zero-slippage swap behavior; `userEarned()` address mix-up
- promising but not retained directions: APR / reward-rate concerns; generic SafeMath zero-denominator concern; router max approval; `tx.origin` transfer-delay bypass; validator index / zero-amount staking checks; zero-address fee receiver handling

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `Contract.sol` staking flows and fee/swap mechanics, with overlap on reward-cap breakage, zero-slippage swaps, and `userEarned()`
- notable differences in attention: `codex_1` spent more attention on privileged-control and liquidity-custody risks; `opencode_1` covered a broader checklist of configuration, validation, and anti-bot / approval themes
- underexplored but suspicious files/functions if clearly supported by the logs: no additional files exist in scope; within `Contract.sol`, validator-index handling and APR / reward-math paths were raised by one agent but not retained after merge

## Retained Findings
- Retained issues center on privileged liquidity custody, broken staking reward-cap enforcement, privileged cancellation of pending staking rewards, lingering team powers after ownership changes, fee-zero trading DoS, predictable zero-slippage fee swaps, and incorrect third-party reward reporting via `userEarned()`


Output only markdown.
