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
- files touched: `0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol`
- files revisited / highest-attention files: `0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol`, especially `swap()`, the invariant check around lines 403-405, and downstream reserve consumers `mint()` / `skim()`
- main issue directions investigated: swap invariant arithmetic, referral-fee handling inside `swap()`, reserve/accounting consistency after fee transfers, and referral recipient attribution via caller-controlled `to`
- promising but not retained directions: no additional distinct directions are visible beyond the three retained findings

## Agent: opencode_1
- files touched: `0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol`
- files revisited / highest-attention files: `0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol`, with emphasis on `swap()` and the `NimbusCall` / referral-fee / `skim()` / `sync()` areas
- main issue directions investigated: callback-driven reentrancy framing, flash-loan/external-call risk, referral-program trust assumptions, fee ordering relative to invariant checks, slippage exposure, and permissionless maintenance functions
- promising but not retained directions: `NimbusCall` reentrancy / flash-loan concerns, malicious referral-program model, referral transfer before K-check, lack of slippage parameters, public `skim()` / `sync()`, and the unusual `1994` fee denominator

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `Contract.sol`'s `swap()` flow and the custom referral logic embedded in it
- notable differences in attention: `codex_1` focused on arithmetic correctness and reserve-state corruption, including impacts on `mint()` / `skim()`; `opencode_1` focused more on callback/external-call threat models and user-facing swap mechanics
- underexplored but suspicious files/functions if clearly supported by the logs: no additional files were in scope; within `Contract.sol`, attention was concentrated on `swap()`, while non-swap paths received comparatively less visible scrutiny except where tied to reserve desync effects

## Retained Findings
- retained findings from this round center on `swap()` logic in `Contract.sol`
- the strongest issue is a critical invariant-scaling mismatch that materially weakens the K check and enables near-total reserve drains
- a high-severity accounting flaw was retained where referral-fee transfers are not reflected in reserve updates, causing stored reserves to exceed actual balances and breaking reserve-dependent behavior until `sync()`
- one lower-confidence retained issue concerns likely self-referral farming because referral crediting uses the caller-controlled `to` address rather than an authenticated referrer


Output only markdown.
