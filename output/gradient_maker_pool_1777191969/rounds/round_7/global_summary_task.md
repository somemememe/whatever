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
# Global Audit Memory

## Scope Touched
- `contracts/GradientMarketMakerPool.sol` — dominant audit surface; recurring hotspots are deposit/withdraw/share math, reward-debt and payout accounting, emergency-withdraw drains, stored counters vs live balances, and orderbook settlement/repayment hooks
- `contracts/interfaces/IGradientMarketMakerPool.sol` — supporting reference for pool/accounting state, exposed transitions, and settlement-related assumptions
- `contracts/interfaces/IGradientRegistry.sol` — supporting reference for authority wiring, `setRegistry` trust boundaries, and router-derived pool existence / reserve lookup dependencies
- `contracts/interfaces/IUniswapV2Pair.sol`, `contracts/interfaces/IUniswapV2Router.sol` — recurring context for reserve-based pricing, pair validation, and registry/router coupling
- Deposit/withdraw/reward/emergency-withdraw/orderbook flows — core invariant surface where nominal inputs, minted shares, tracked liquidity, actual balances, and external reserve reads can diverge
- `receiveFeeDistribution`, `_updatePool`, `transferETHToOrderbook`, `transferTokenToOrderbook`, `receiveETHFromOrderbook`, `receiveTokenFromOrderbook` — repeatedly important invariant-sensitive functions, especially when balances are disturbed or pools reach unusual states

## Issue Directions Seen
- Reward accounting remains a primary direction: LP share / reward-debt math can drift, payouts appear insufficiently isolated across pools, and reward deposits can become stranded when accounting records liquidity but LP share supply is zero
- LP mint/burn logic is highly sensitive to rounding and raw asset-sum formulas, with a durable zero-share-mint / donation direction and a stronger shareless-but-live-pool direction when `totalLiquidity > 0` but `totalLPShares == 0`
- Shareless-but-live states remain a cross-flow solvency risk: later repayments or stranded assets can accumulate into a no-owner pool state, letting the next depositor capture prior value
- A broader insolvency direction is now durable: owner emergency withdrawals can remove ETH/token balances without synchronizing pool or user accounting, leaving the system operational in bookkeeping while undercollateralized in reality
- Pool accounting depends heavily on stored token/liquidity counters instead of live balances, preserving desynchronization risk for rebasing, confiscatory, fee-on-transfer, or otherwise balance-mutating tokens
- Deposit sizing and some pool validity checks depend on external Uniswap reserve/router state, keeping manipulation, mispricing, and registry/router-change breakage risk live
- Orderbook settlement remains a strong direction: outbound/inbound hooks can strand assets if accounting hits edge states, and repayment/restoration relies on fragile accounting invariants rather than purely live balances
- Registry / authority trust boundaries were repeatedly examined around `setRegistry`, `onlyOrderbook`, and `poolExists`; this remains useful context, though it has not matured into a retained issue direction

## Useful Context
- Cross-round attention remains concentrated on `GradientMarketMakerPool`; interface files mainly serve struct, authority, and dependency tracing
- Durable pattern: the contract mixes several accounting notions at once — user-supplied amounts, actual received balances, stored pool counters, LP shares, reward debt, and externally sourced reserve prices
- Strongest accumulated signal favors accounting/invariant failures in core liquidity, reward, emergency-drain, and settlement paths over purely governance-style abuse
- External dependency coupling is part of the solvency surface: `poolExists()`, reserve reads, pair/router assumptions, and registry rewiring affect pricing, validity checks, and downstream accounting safety
- The most suspicious recurring concentration points remain reward distribution, claim/withdraw flows, LP share initialization/reset edge cases, emergency withdrawal handling, and orderbook transfer/repayment handlers


## Latest Round Summary
# Round 7 Summary

## Agent: codex
- files touched: `contracts/GradientMarketMakerPool.sol`; `contracts/interfaces/IGradientMarketMakerPool.sol`; grep-level review of `contracts/interfaces/*.sol` and referenced OpenZeppelin imports
- files revisited / highest-attention files: `contracts/GradientMarketMakerPool.sol` received the clear majority of attention, with repeated passes over deposit/share minting, withdrawal, rewards, and orderbook transfer/repayment sections
- main issue directions investigated: LP share/accounting invariants; reward accrual and payout edge cases; withdrawal completion/rounding behavior; orderbook outflow/repayment effects on pool state and liquidity pricing
- promising but not retained directions: general orphaned state / invariant checks across `rewardBalance`, `accRewardPerShare`, `totalLiquidity`, `totalLPShares`, `pendingReward`, `rewardDebt`, `uniswapPair`, and blocked-token/orderbook gates were probed, but only three issues were retained

## Cross-Agent Status
- main overlap in file/area attention: this round’s attention concentrated on `contracts/GradientMarketMakerPool.sol`, especially liquidity accounting, reward logic, and orderbook interaction paths
- notable differences in attention: no cross-agent variation in this round; only `codex` is present in the logs
- underexplored but suspicious files/functions if clearly supported by the logs: interface files were only used for structure/context, while substantive review stayed centered on pool state transitions in `GradientMarketMakerPool.sol`; admin/router/pair-related code appears lower-attention than deposit/withdraw/reward/orderbook paths in this round

## Retained Findings
- `F-019`: orderbook-borrowed inventory is removed from tracked liquidity without a receivable, letting late LPs mint against a depressed denominator and capture repayment value
- `F-020`: full withdrawal is hard-coupled to a successful ETH reward payment, and rounding on partial burns can force users into that reverting path for their final exit
- `F-021`: fee-distribution rounding dust is not carried forward, so small reward deposits can become permanently stranded in the contract


Output only markdown.
