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
- `contracts/GradientMarketMakerPool.sol` — dominant audit surface; recurring hotspots are deposit/withdraw/share math, reward-debt and payout accounting, stored counters vs live balances, and orderbook settlement/repayment hooks
- `contracts/interfaces/IGradientMarketMakerPool.sol` — supporting reference for exposed pool/accounting assumptions and state transitions
- `contracts/interfaces/IGradientRegistry.sol` — supporting reference for authority wiring plus router-derived pool existence / reserve lookup dependencies
- `contracts/interfaces/IUniswapV2Pair.sol`, `contracts/interfaces/IUniswapV2Router.sol` — recurring context for reserve-based pricing, pair validation, and registry/router coupling
- Deposit/withdraw/reward/orderbook flows — repeated hotspot where nominal inputs, minted shares, tracked liquidity, actual balances, and external reserve reads can diverge
- `receiveFeeDistribution`, `_updatePool`, `transferETHToOrderbook`, `transferTokenToOrderbook`, `receiveETHFromOrderbook`, `receiveTokenFromOrderbook` — repeatedly scrutinized as the clearest invariant-sensitive functions

## Issue Directions Seen
- Reward accounting remains the strongest direction: LP share / reward-debt math can drift, payouts appear insufficiently isolated across pools, and reward deposits can become stranded when accounting records liquidity but LP share supply is zero
- LP mint/burn logic is sensitive to rounding and raw asset-sum formulas, including the durable zero-share-mint / donation direction for small deposits
- Pool accounting depends heavily on stored token/liquidity counters instead of live balances, preserving desynchronization risk for rebasing, confiscatory, fee-on-transfer, or otherwise balance-mutating tokens
- Deposit sizing and some pool validity checks depend on external Uniswap reserve/router state, keeping manipulation, mispricing, and registry/router-change breakage risk live
- Orderbook settlement is now a stronger secondary direction: outbound/inbound hooks can strand assets if tracked liquidity hits zero, and repayment/restoration relies on fragile accounting invariants rather than purely live balances
- Token blocklist behavior intersects with settlement paths, creating a durable direction where assets sent out through orderbook flows may be unable to return to the pool

## Useful Context
- Cross-round attention stays concentrated on `GradientMarketMakerPool`; interface files mainly serve struct, authority, and dependency tracing
- Durable pattern: the contract mixes several accounting notions at once — user-supplied amounts, actual received balances, stored pool counters, LP shares, reward debt, and externally sourced reserve prices
- Strongest accumulated signal still favors accounting/invariant failures in core liquidity, reward, and settlement paths over governance-style or admin-only abuse
- External dependency coupling is part of the solvency surface: `poolExists()`, reserve reads, and router/pair assumptions affect pricing, validity checks, and downstream accounting safety
- Under repeated scrutiny, reward distribution, claim/withdraw flows, and orderbook transfer/repayment handlers remain the most suspicious concentration points


## Latest Round Summary
# Round 5 Summary

## Agent: codex
- files touched: `contracts/GradientMarketMakerPool.sol`, `contracts/interfaces/IGradientMarketMakerPool.sol`, `contracts/interfaces/IGradientRegistry.sol`
- files revisited / highest-attention files: heavy repeated review of `contracts/GradientMarketMakerPool.sol`; secondary attention on the two interfaces for structs and authorization / blocked-token hooks
- main issue directions investigated: LP share minting around `totalLPShares == 0`; shareless-but-live pool states; orderbook repayment entry points (`receiveETHFromOrderbook`, `receiveTokenFromOrderbook`); owner emergency withdrawal powers; blocked-token gating consistency between deposits and settlement flows
- promising but not retained directions: owner emergency sweep as a rug vector; blocked tokens still accepting new liquidity despite blocked settlement paths

## Cross-Agent Status
- main overlap in file/area attention: this round concentrated almost entirely on `contracts/GradientMarketMakerPool.sol`, especially liquidity provision, LP share accounting, and orderbook repayment handling
- notable differences in attention: no cross-agent differences visible in the provided logs because only `codex` appears for this round
- underexplored but suspicious files/functions if clearly supported by the logs: current attention was concentrated on pool state transitions; interfaces were used mainly for context rather than deep standalone review

## Retained Findings
- retained: a high-severity share-accounting issue where a pool can have `totalLiquidity > 0` but `totalLPShares == 0`, allowing later orderbook repayments to accrue into a no-owner state and the next depositor to mint all shares and seize stranded or repaid assets


Output only markdown.
