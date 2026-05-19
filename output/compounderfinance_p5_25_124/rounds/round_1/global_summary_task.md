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
- files touched: `0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol`
- files revisited / highest-attention files: `0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol`, especially `deposit()`, `withdraw(uint)`, `withdrawAll()`, `_withdrawSome()`, `withdrawUnderlying()`, and `balanceOf()`
- main issue directions investigated: zero-slippage Curve entry/exit execution; withdrawal sizing vs realized unwind proceeds; model-based `yyCRV` valuation vs executable exit value; controller-accessible generic asset withdrawal path
- promising but not retained directions: `withdraw(IERC20 _asset)` as a controller sweep / vault-bypass path was surfaced in the agent output but not retained after merge

## Agent: opencode_1
- files touched: `0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol`
- files revisited / highest-attention files: `0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol`
- main issue directions investigated: only initial contract read is visible in the logs
- promising but not retained directions: none visible from the logs

## Cross-Agent Status
- main overlap in file/area attention: both agents opened the single in-scope file, `0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol`
- notable differences in attention: `codex_1` performed function-level analysis around Curve interaction, withdrawal math, and accounting; `opencode_1` shows only file intake with no visible issue development
- underexplored but suspicious files/functions if clearly supported by the logs: `withdraw(IERC20 _asset)` remains a visible hotspot from this round because it was investigated by `codex_1` and surfaced as a candidate issue, but it was not retained in the merged set

## Retained Findings
- Retained issues from this round center on the strategy’s Curve/yPool execution and valuation paths in `Contract.sol`
- The merged set keeps: zero-slippage Curve deposit/exit execution enabling MEV extraction; partial-withdraw sizing that can realize less DAI than requested; and `balanceOf()` accounting that marks `yyCRV` to model value rather than executable DAI exit value


Output only markdown.
