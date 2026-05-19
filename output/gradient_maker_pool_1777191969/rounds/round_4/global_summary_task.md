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
- `contracts/GradientMarketMakerPool.sol` — dominant audit surface; core risk areas are deposit/withdraw/share math, reward-debt and payout accounting, stored counters vs live balances, orderbook hooks, and pool lifecycle checks tied to router/pair state
- `contracts/interfaces/IGradientMarketMakerPool.sol` — supporting reference for exposed pool/accounting assumptions and state transitions
- `contracts/interfaces/IGradientRegistry.sol` — supporting reference for authority wiring plus router-derived pool existence / reserve lookup dependencies
- `contracts/interfaces/IUniswapV2Pair.sol`, `contracts/interfaces/IUniswapV2Router.sol` — recurring context for reserve-based pricing and pair validation
- Deposit/withdraw/reward/orderbook flows — repeated hotspot where nominal inputs, minted shares, stored accounting, actual balances, and external reserve reads can diverge

## Issue Directions Seen
- Reward accounting remains a primary direction: LP share / reward-debt math can drift, and reward payouts appear insufficiently isolated across pools
- LP mint/burn logic is sensitive to rounding and raw asset-sum formulas, including the durable zero-share-mint/donation direction for small deposits
- Pool accounting depends heavily on stored token/liquidity counters instead of live balances, preserving desynchronization risk for rebasing, confiscatory, fee-on-transfer, or otherwise balance-mutating tokens
- Deposit sizing and some pool validity checks depend on external Uniswap reserve/router state, keeping manipulation and mispricing risk live
- A newer durable angle is registry/router coupling: existing pools may rely on the current registry router for pair validation/reserve reads rather than their own stored pair, creating breakage/mispricing risk after registry changes
- Orderbook inflow/outflow hooks remain a secondary invariant-drift direction, but still less supported than the main accounting faults

## Useful Context
- Cross-round attention stays concentrated on `GradientMarketMakerPool`; interface files mainly serve struct, authority, and dependency tracing
- Durable pattern: the contract mixes several accounting notions at once — user-supplied amounts, actual received balances, stored pool counters, LP shares, reward debt, and externally sourced reserve prices
- Strongest accumulated signal continues to favor accounting/invariant failures in core liquidity and reward paths over governance-style or admin-only abuse
- Recent retained findings reinforce two cross-round themes: external dependency coupling (registry/router/pair state) is part of the solvency surface, and pool rewards may draw from shared ETH rather than clean per-pool buckets
- Under repeated scrutiny, `poolExists()`, reserve reads, reward claim/withdraw paths, and orderbook transfer handlers remain the most suspicious concentration points


## Latest Round Summary
# Round 4 Summary

## Agent: codex
- files touched: `contracts/GradientMarketMakerPool.sol`; revisited `contracts/interfaces/IGradientMarketMakerPool.sol`, `contracts/interfaces/IGradientRegistry.sol`, and Uniswap interface files for dependency tracing
- files revisited / highest-attention files: strongest focus on `contracts/GradientMarketMakerPool.sol`, especially reward accounting, liquidity/share accounting, and orderbook transfer/repayment functions
- main issue directions investigated: zero-share reward handling; orderbook outbound/inbound settlement invariants; blocklist interactions with settlement; emergency withdrawal powers; user slippage parameter enforcement; broader stored-liquidity vs live-balance/accounting drift themes
- promising but not retained directions: unrestricted orderbook drain due to trusted orderbook primitives (`F-012` in agent output); owner emergency-withdraw rug/backdoor framing (`F-013`); non-functional `minTokenAmount` slippage guard (`F-016`)

## Cross-Agent Status
- main overlap in file/area attention: this round was entirely concentrated on `contracts/GradientMarketMakerPool.sol`, with repeated attention on reward updates and orderbook settlement paths
- notable differences in attention: no cross-agent divergence visible in this round because only `codex` produced logs
- underexplored but suspicious files/functions if clearly supported by the logs: interface files were used mainly for struct/authority tracing, while `receiveFeeDistribution`, `_updatePool`, `transferETHToOrderbook`, `transferTokenToOrderbook`, `receiveETHFromOrderbook`, and `receiveTokenFromOrderbook` received the clearest substantive scrutiny

## Retained Findings
- retained after merge: reward deposits can be accepted and stranded when a pool has recorded liquidity but zero LP shares (`F-014`)
- retained after merge: blocklisting a token can also block the orderbook’s repayment path, leaving assets stranded outside the pool (`F-015`)
- retained after merge: if orderbook withdrawals reduce tracked liquidity to zero, the inbound settlement functions can no longer repay assets, bricking pool restoration (`F-017`)


Output only markdown.
