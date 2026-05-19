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
- Deposit/withdraw/reward/emergency-withdraw/orderbook flows — core invariant surface where nominal inputs, minted shares, tracked liquidity, actual balances, receivables, and external reserve reads can diverge
- `receiveFeeDistribution`, `_updatePool`, `transferETHToOrderbook`, `transferTokenToOrderbook`, `receiveETHFromOrderbook`, `receiveTokenFromOrderbook` — repeatedly important invariant-sensitive functions, especially when balances are disturbed, rewards round down, or pools reach unusual share/liquidity states

## Issue Directions Seen
- Reward accounting remains a primary direction: LP share / reward-debt math can drift, payouts appear insufficiently isolated across pools, and reward deposits can become stranded when liquidity or per-share updates round down
- LP mint/burn logic is highly sensitive to rounding and raw asset-sum formulas, with durable zero-share-mint / donation risk and a stronger shareless-but-live-pool direction when `totalLiquidity > 0` but `totalLPShares == 0`
- Shareless-but-live states remain a cross-flow solvency risk: later repayments or stranded assets can accumulate into a no-owner pool state, letting the next depositor capture prior value
- A broader insolvency direction is durable: owner emergency withdrawals can remove ETH/token balances without synchronizing pool or user accounting, leaving bookkeeping live while the contract is undercollateralized
- Orderbook settlement is now a retained cross-round direction: outbound transfers reduce tracked liquidity without an explicit receivable, so later LP entry/exit pricing can misallocate repayment value
- Withdrawal completion is fragile around reward payout coupling and burn rounding: final exits can depend on successful ETH reward payment rather than purely on liquidity redemption
- Pool accounting depends heavily on stored token/liquidity counters instead of live balances, preserving desynchronization risk for rebasing, confiscatory, fee-on-transfer, or otherwise balance-mutating tokens
- Deposit sizing and some pool validity checks depend on external Uniswap reserve/router state, keeping manipulation, mispricing, and registry/router-change breakage risk live
- Registry / authority trust boundaries were repeatedly examined around `setRegistry`, `onlyOrderbook`, and `poolExists`; this remains useful context, though not a leading retained direction

## Useful Context
- Cross-round attention remains concentrated on `GradientMarketMakerPool`; interface files mainly serve struct, authority, and dependency tracing
- Durable pattern: the contract mixes several accounting notions at once — user-supplied amounts, actual received balances, stored pool counters, LP shares, reward debt, pending rewards, and externally sourced reserve prices
- Strongest accumulated signal favors accounting/invariant failures in core liquidity, reward, emergency-drain, and settlement paths over purely governance-style abuse
- Solvency depends not just on live balances but on whether accounting recognizes off-path claims such as orderbook repayments and undistributed reward dust
- External dependency coupling is part of the solvency surface: `poolExists()`, reserve reads, pair/router assumptions, and registry rewiring affect pricing, validity checks, and downstream accounting safety
- The most suspicious recurring concentration points remain reward distribution, claim/withdraw flows, LP share initialization/reset edge cases, emergency withdrawal handling, and orderbook transfer/repayment handlers


## Latest Round Summary
# Round 8 Summary

## Agent: codex
- files touched: `contracts/GradientMarketMakerPool.sol`, `contracts/interfaces/IGradientMarketMakerPool.sol`, `contracts/interfaces/IGradientRegistry.sol`
- files revisited / highest-attention files: `contracts/GradientMarketMakerPool.sol` was read in multiple passes and line-numbered slices; interface files received lighter supporting review
- main issue directions investigated: pool state-flow/accounting, orderbook authorization and repayment paths, registry/orderbook rotation effects, blocked-token behavior around settlement/deposit flows
- promising but not retained directions: unconstrained orderbook settlement pricing (`F-022` in agent output) and blocked-token deposits bypassing the blocklist circuit breaker (`F-024` in agent output)

## Cross-Agent Status
- main overlap in file/area attention: only one agent logged this round; attention was concentrated on `contracts/GradientMarketMakerPool.sol`, especially orderbook transfer/repayment logic
- notable differences in attention: no cross-agent differences are visible for this round
- underexplored but suspicious files/functions if clearly supported by the logs: attention outside `contracts/GradientMarketMakerPool.sol` was limited; interface files were used mainly for context rather than deep review

## Retained Findings
- retained finding `F-023`: changing the registry or active orderbook can lock out the previous orderbook from the `onlyOrderbook`-gated repayment functions, stranding already-borrowed ETH or tokens outside the pool during migration/rotation


Output only markdown.
