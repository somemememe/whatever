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

## Agent: codex
- files touched: `0x37ea5f691bce8459c66ffceeb9cf34ffa32fdadc/contracts/GradientMarketMakerPool.sol`; revisited interfaces `0x37ea5f691bce8459c66ffceeb9cf34ffa32fdadc/contracts/interfaces/IGradientMarketMakerPool.sol`, `0x37ea5f691bce8459c66ffceeb9cf34ffa32fdadc/contracts/interfaces/IGradientRegistry.sol`, `0x37ea5f691bce8459c66ffceeb9cf34ffa32fdadc/contracts/interfaces/IUniswapV2Pair.sol`, `0x37ea5f691bce8459c66ffceeb9cf34ffa32fdadc/contracts/interfaces/IUniswapV2Router.sol`
- files revisited / highest-attention files: `0x37ea5f691bce8459c66ffceeb9cf34ffa32fdadc/contracts/GradientMarketMakerPool.sol` was read in multiple segmented passes and used for exploit math checks
- main issue directions investigated: LP share minting versus `totalLiquidity` during orderbook outflows; reward accounting mismatch between raw deposits and LP shares; token accounting that trusts nominal transfer amounts; emergency withdrawal authority; slippage-check correctness
- promising but not retained directions: owner emergency-drain path and ineffective `minTokenAmount` slippage protection were reported by the agent but not retained after merge

## Agent: merge-review
- files touched: `0x37ea5f691bce8459c66ffceeb9cf34ffa32fdadc/contracts/GradientMarketMakerPool.sol`
- files revisited / highest-attention files: `0x37ea5f691bce8459c66ffceeb9cf34ffa32fdadc/contracts/GradientMarketMakerPool.sol`, especially the orderbook transfer/return and zero-liquidity handling paths
- main issue directions investigated: full orderbook drain leading to `totalLiquidity == 0`, rejected asset returns, blocked withdrawals, and failed recapitalization/share minting
- promising but not retained directions: none clearly visible from the provided materials

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `GradientMarketMakerPool.sol`, especially liquidity accounting around orderbook transfer/return flows
- notable differences in attention: `codex` covered a broader set of accounting themes including rewards, token transfer accounting, and admin/slippage behaviors; `merge-review` retained a focused zero-liquidity brick scenario
- underexplored but suspicious files/functions if clearly supported by the logs: current visible attention is heavily concentrated on `provideLiquidity`, `withdrawLiquidity`, `claimReward`, `transferETHToOrderbook`, `transferTokenToOrderbook`, `receiveETHFromOrderbook`, and `receiveTokenFromOrderbook`; no separate underexplored hotspot is clearly supported beyond this concentration

## Retained Findings
- retained issues center on broken liquidity accounting in `GradientMarketMakerPool.sol`
- one critical finding is LP share inflation when deposits occur while assets are temporarily parked in the orderbook
- retained high-severity issues also include reward accounting inconsistency between deposit balances and LP shares, nominal token-crediting despite short receipt, and a zero-liquidity pool brick when a full orderbook drain makes asset returns revert


Output only markdown.
