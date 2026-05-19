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
- `Staking.sol` — primary focus across deposit, withdraw, `emergencyWithdraw`, epoch accounting, and liquidity-routing behavior
- Epoch read/write surfaces (`getEpochUserBalance`, `getEpochPoolSize`, `manualEpochInit`) — recurring concern around snapshot correctness, initialization liveness, and dormant-pool behavior
- Compound integration helpers / `CTokenInterface.sol` — attention on external protocol return-code handling and accounting/liquidity sync
- ERC20 interaction layer / `IERC20.sol` — transfer semantics matter, especially unchecked return values and fee-on-transfer / short-receipt behavior

## Issue Directions Seen
- Deposit accounting can diverge from actual assets received, especially when crediting requested amounts instead of real token inflow
- External token / protocol calls are a persistent risk surface when return values or error codes are ignored
- Epoch-based accounting is fragile around exceptional exits, with stale user or pool snapshots surviving `emergencyWithdraw`
- Emergency controls expose griefing/liveness risk when shared timers or global state can be repeatedly reset
- Lazy or iterative epoch backfilling creates dormant-pool DoS / lockup potential

## Useful Context
- Most retained issues cluster in `Staking.sol`; epoch bookkeeping and emergency paths are the highest-signal areas so far
- Cross-agent overlap was strongest on stale epoch state after `emergencyWithdraw`, suggesting that surface is both nontrivial and durable
- The audit has repeatedly converged on accounting desynchronization themes: user balances, pool totals, and external liquidity can fall out of sync
- Compound-facing logic and epoch helper functions remain suspicious supporting surfaces rather than isolated one-off details


## Latest Round Summary
# Round 2 Summary

## Agent: codex
- files touched: `Contract.sol` only; the agent extracted and analyzed embedded sources, with primary focus on `Staking.sol`
- files revisited / highest-attention files: `Staking.sol`, especially `deposit()`, `withdraw()`, `manualEpochInit()`, `getEpochPoolSize()`, and `currentEpochMultiplier()`
- main issue directions investigated: epoch initialization behavior, pool-size snapshot/accounting drift, current-balance fallback for historical epochs, bootstrap multiplier handling, and surrounding fund-flow paths for stable vs non-stable assets
- promising but not retained directions: `manualEpochInit()` epoch-0 overwrite/reset path (`F-007` in agent output) and uncapped bootstrap multiplier before `epoch1Start` (`F-010` in agent output) were explored by the agent but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: retained findings center on `Staking.sol` pool-size accounting around `deposit()`, `withdraw()`, and `getEpochPoolSize()`, especially how non-stable balances and epoch snapshots are derived
- notable differences in attention: only codex process logs are visible here; merge-level retention narrowed the round to accounting/snapshot issues and excluded codex’s epoch-0 reset and bootstrap-multiplier directions
- underexplored but suspicious files/functions if clearly supported by the logs: `manualEpochInit()` and `currentEpochMultiplier()` remain visible investigation hotspots from this round’s logs, but they were not retained findings

## Retained Findings
- `F-008`: non-stable pool-size accounting can be poisoned by direct transfers or rebases because epoch size snapshots use live token balance rather than tracked stake
- `F-009`: uninitialized historical epochs can read mutable current balances instead of fixed historical snapshots, making past denominators non-deterministic until backfilled


Output only markdown.
