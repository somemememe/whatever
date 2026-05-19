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
- `contracts/GradientMarketMakerPool.sol` — dominant audit focus; core risk surface is liquidity provision/withdrawal, LP share mint/burn math, reward-debt tracking, stored pool counters vs live balances, and orderbook transfer/receive hooks
- `contracts/interfaces/IGradientMarketMakerPool.sol` — reviewed mainly to confirm externally visible pool-accounting assumptions and state transitions
- `contracts/interfaces/IGradientRegistry.sol`, `contracts/interfaces/IUniswapV2Pair.sol`, `contracts/interfaces/IUniswapV2Router.sol` — supporting context for registry wiring and reserve-dependent pricing/deposit behavior
- Deposit/withdraw/reward/orderbook flows — recurring hotspot where nominal inputs, minted shares, stored accounting, and actual token balances can diverge

## Issue Directions Seen
- Reward accounting and LP share accounting can drift when deposits, shares, and reward debt are derived from different units or formulas
- LP share mint/burn logic is sensitive to rounding and raw asset sums, including a durable zero-share-mint/donation direction for small deposits
- Pool state relies heavily on stored token/liquidity counters instead of live balances, leaving a persistent desynchronization direction for rebasing, confiscatory, or otherwise balance-mutating tokens
- Deposit sizing depends on external Uniswap spot reserves, keeping manipulation/pricing risk as a recurring direction
- Fee-on-transfer/deflationary token behavior remains relevant because credited accounting may not match assets actually received
- Orderbook inflow/outflow hooks remain a secondary invariant-drift direction, but less supported than the main accounting faults

## Useful Context
- Cross-round attention has stayed concentrated on `GradientMarketMakerPool`; interface files have mostly served as supporting context
- Durable pattern: the contract mixes several accounting notions at once — user-supplied deposit amounts, actual transferred balances, stored pool counters, LP shares, reward debt, and externally sourced reserve prices
- Strongest accumulated signal favors accounting/invariant failures in core liquidity paths over governance-style or admin-only issues
- Recent retained findings strengthen the view that edge-case token behavior and rounding are first-class pool-solvency risks, not just peripheral token-compatibility concerns


## Latest Round Summary
# Round 3 Summary

## Agent: codex
- files touched: `contracts/GradientMarketMakerPool.sol`, `contracts/interfaces/IGradientMarketMakerPool.sol`, `contracts/interfaces/IGradientRegistry.sol`
- files revisited / highest-attention files: highest attention on `contracts/GradientMarketMakerPool.sol`; revisited via state-variable grep across pool and interface definitions
- main issue directions investigated: pool state flow and accounting, reward distribution isolation, authority derived from the registry, and router/pair dependency in pool existence and reserve reads
- promising but not retained directions: owner emergency-withdraw drainability and mutable-registry takeover risk were reported by the agent this round but were not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: only visible agent activity centers on `contracts/GradientMarketMakerPool.sol`, especially reward/accounting logic and pool lifecycle checks
- notable differences in attention: no cross-agent differences are visible in the provided logs for this round
- underexplored but suspicious files/functions if clearly supported by the logs: interfaces were used mainly for struct/authority tracing, while deeper scrutiny stayed concentrated on `poolExists()`, `getReserves()`, reward claim/withdraw paths, and orderbook transfer functions in `contracts/GradientMarketMakerPool.sol`

## Retained Findings
- retained: existing pools can be bricked or mispriced because pair validation and reserve lookup continue using the current registry router instead of the pool’s stored pair
- retained: reward payouts are not isolated per pool, so an undercollateralized reward bucket can consume shared ETH and harm unrelated pools


Output only markdown.
