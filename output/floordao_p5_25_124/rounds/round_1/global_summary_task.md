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
- files touched: `contracts/Staking.sol`; `contracts/interfaces/{IDistributor,IERC20,IFloorAuthority,IgFLOOR,IsFLOOR}.sol`; `contracts/libraries/{SafeERC20,SafeMath}.sol`; `contracts/types/FloorAccessControlled.sol`
- files revisited / highest-attention files: `contracts/Staking.sol` with repeated focus on `stake`, `claim`, `rebase`, `wrap`, `unwrap`, `toggleLock`, `supplyInWarmup`, `secondsToNextEpoch`
- main issue directions investigated: warmup liabilities omitted from rebase accounting; wrapped `gFLOOR` liabilities depending on external `circulatingSupply()` semantics; warmup expiry reset / third-party lockup griefing; lock-flag behavior; forced claim asset form; overdue-epoch helper underflow
- promising but not retained directions: lock/comment inversion, third-party forced asset-form selection on claim, `secondsToNextEpoch()` underflow behavior

## Agent: opencode_1
- files touched: `contracts/Staking.sol`; all scoped interfaces, libraries, and `types/FloorAccessControlled.sol`
- files revisited / highest-attention files: `contracts/Staking.sol`
- main issue directions investigated: warmup/forfeit reward treatment; mutable warmup length effects; unstake reserve and slippage concerns; zero-amount `stake`; `toggleLock` behavior; `wrap`/`unwrap` allowance handling
- promising but not retained directions: forfeit-only loss framing, retroactive `warmupPeriod` claim-timing theory, generic unstake insolvency/slippage claims, allowance/UX-only wrap issues

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `contracts/Staking.sol`, especially warmup staking/claim flow and lock-related behavior
- notable differences in attention: `codex_1` went deeper on rebase liability accounting and wrapper-backed solvency; `opencode_1` spent more attention on user-flow, config, and validation edge cases
- underexplored but suspicious files/functions if clearly supported by the logs: non-`Staking.sol` files were only read at surface level; `wrap`/`unwrap`, `forfeit`, and `setWarmupLength` received limited or one-sided follow-up compared with warmup/rebase paths

## Retained Findings
- Retained from this round: warmup deposits are rebased and later claimable but not subtracted as liabilities during `rebase()`, creating a critical insolvency path; wrapper solvency depends on external `sFLOOR.circulatingSupply()` semantics for `gFLOOR` backing; warmup positions can be indefinitely delayed because added stakes reset aggregate expiry, with zero-amount/dust stake behavior and lock-state confusion contributing to the griefing surface.


Output only markdown.
