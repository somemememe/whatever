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
- files touched: `onchain_auto/0xbb02a884621fb8f5bfd263a67f58b65df5b090f3/Contract.sol`
- files revisited / highest-attention files: repeated chunked reads of `onchain_auto/0xbb02a884621fb8f5bfd263a67f58b65df5b090f3/Contract.sol`, especially the Cauldron region around `init()`, `_isSolvent()`, `updateExchangeRate()`, `borrow()`, `cook()`, and `liquidate()`
- main issue directions investigated: fresh-market initialization and zero `exchangeRate`; stale cached oracle use in solvency-critical paths; `cook()` exchange-rate bound logic; payable / arbitrary-call behavior in `cook()` enabling stranded asset sweeps
- promising but not retained directions: broad grep/mapping of owner/oracle/call patterns was used for triage, but the retained output stayed concentrated on the exchange-rate / solvency / `cook()` surfaces

## Agent: opencode_1
- files touched: `../../../output/kashi_p5_25_124/rounds/round_1/agent_opencode_1/current_task.md`, `onchain_auto/0xbb02a884621fb8f5bfd263a67f58b65df5b090f3/Contract.sol`
- files revisited / highest-attention files: `onchain_auto/0xbb02a884621fb8f5bfd263a67f58b65df5b090f3/Contract.sol`, including a later read near the liquidation / tail-function region
- main issue directions investigated: `init()` access control, liquidation reentrancy/slippage, oracle validation, unrestricted `cook()` calls, interest math overflow, and tail admin/accounting functions
- promising but not retained directions: most proposed issues were not kept after merge; the only visible overlap with retained results was the stray-asset sweep angle through permissionless `cook()` / arbitrary call behavior

## Cross-Agent Status
- main overlap in file/area attention: both agents focused on the single in-scope Cauldron file, with overlap around `cook()` and the broader `init()` / oracle / liquidation control flow
- notable differences in attention: `codex_1` concentrated on concrete solvency and exchange-rate state transitions and produced all retained oracle / rate findings; `opencode_1` spread attention across liquidation mechanics, generic oracle concerns, and tail admin/accounting surfaces
- underexplored but suspicious files/functions if clearly supported by the logs: no additional files were explored; within the same contract, `liquidate()` and the tail admin/accounting functions received one-agent attention but did not produce retained findings in this round

## Retained Findings
- fresh markets remain borrowable before any nonzero `exchangeRate` is seeded, enabling drain risk from the zero-rate default
- solvency-sensitive actions rely on a cached oracle rate that can be arbitrarily stale, affecting borrow, collateral removal, and liquidation outcomes
- `cook()` max-rate protection is inverted, so the supposed upper-bound guard only passes when the rate is already above the caller’s ceiling
- permissionless `cook()` execution can sweep stranded ETH and directly transferred tokens held by the Cauldron


Output only markdown.
