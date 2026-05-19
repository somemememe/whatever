# Global Audit Memory

## Scope Touched
- `contracts/GradientMarketMakerPool.sol` — dominant audit surface; recurring hotspots are deposit/withdraw/share math, reward-debt and payout accounting, emergency-withdraw drains, stored counters vs live balances, blocked-token/pair validity checks, and orderbook transfer/repayment settlement hooks
- `contracts/interfaces/IGradientMarketMakerPool.sol` — supporting reference for pool/accounting state, exposed transitions, and settlement-related assumptions
- `contracts/interfaces/IGradientRegistry.sol` — supporting reference for authority wiring, `setRegistry` trust boundaries, active-orderbook rotation, and router-/pair-derived pool existence or reserve lookup dependencies
- `contracts/interfaces/IUniswapV2Pair.sol`, `contracts/interfaces/IUniswapV2Router.sol` — recurring context for reserve-based pricing, pair validation/initialization assumptions, and registry/router coupling
- Deposit/withdraw/reward/emergency-withdraw/orderbook flows — core invariant surface where nominal inputs, minted shares, tracked liquidity, actual balances, receivables, and external reserve reads can diverge
- `receiveFeeDistribution`, `_updatePool`, `transferETHToOrderbook`, `transferTokenToOrderbook`, `receiveETHFromOrderbook`, `receiveTokenFromOrderbook` — repeatedly important invariant-sensitive functions, especially around disturbed balances, rounding, unusual share/liquidity states, repayment reachability, and settlement isolation between pools

## Issue Directions Seen
- Reward accounting remains a primary direction: LP share / reward-debt math can drift, payouts appear insufficiently isolated across pools, and reward deposits can become stranded when liquidity or per-share updates round down
- LP mint/burn logic is highly sensitive to rounding and raw asset-sum formulas, with durable zero-share-mint / donation risk and a stronger shareless-but-live-pool direction when `totalLiquidity > 0` but `totalLPShares == 0`
- Shareless-but-live states remain a cross-flow solvency risk: later repayments or stranded assets can accumulate into a no-owner pool state, letting the next depositor capture prior value
- A broader insolvency direction is durable: owner emergency withdrawals can remove ETH/token balances without synchronizing pool or user accounting, leaving bookkeeping live while the contract is undercollateralized
- Orderbook settlement remains a retained cross-round direction: outbound transfers reduce tracked liquidity without an explicit per-pool receivable, and repayment paths are authorization-sensitive
- A stronger retained variant is clear: orderbook debt is not isolated per pool, so assets borrowed from one pool can be repaid into another, shifting losses across unrelated LP pools and breaking pool-level solvency
- Registry / orderbook rotation remains a durable sub-direction: changing registry or active orderbook can cut the prior orderbook off from `onlyOrderbook` repayment paths, trapping already-borrowed ETH or tokens outside the pool
- Withdrawal completion is fragile around reward payout coupling and burn rounding: final exits can depend on successful ETH reward payment rather than purely on liquidity redemption
- Pool accounting depends heavily on stored token/liquidity counters instead of live balances, preserving desynchronization risk for rebasing, confiscatory, fee-on-transfer, or otherwise balance-mutating tokens
- Deposit sizing and some pool validity checks depend on external Uniswap reserve/router/pair state, keeping manipulation, mispricing, initialization, and registry/router-change breakage risk live

## Useful Context
- Cross-round attention remains concentrated on `contracts/GradientMarketMakerPool.sol`; interface files mainly serve struct, authority, and dependency tracing
- Durable pattern: the contract mixes several accounting notions at once — user-supplied amounts, actual received balances, stored pool counters, LP shares, reward debt, pending rewards, inter-pool settlement claims, and externally sourced reserve prices
- Strongest accumulated signal favors accounting/invariant failures in core liquidity, reward, emergency-drain, and settlement paths over purely governance-style abuse
- Solvency depends not just on live balances but on whether accounting recognizes off-path claims such as orderbook repayments, migration-era receivables, undistributed reward dust, and pool-specific settlement obligations
- External dependency coupling is part of the solvency surface: `poolExists()`, blocked-token gating, reserve reads, pair/router assumptions, registry rewiring, and orderbook rotation affect pricing, validity checks, repayment reachability, and downstream accounting safety
- The most suspicious recurring concentration points remain reward distribution, claim/withdraw flows, LP share initialization/reset edge cases, emergency withdrawal handling, and orderbook transfer/repayment handlers; `transferETHToOrderbook` continues to be an edge-case hotspot even when not yielding retained findings
