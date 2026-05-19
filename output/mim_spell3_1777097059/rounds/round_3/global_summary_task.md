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
- `cauldrons/CauldronV4.sol` remains the primary audit surface, especially `cook()` dispatch/call forwarding, final solvency enforcement, liquidation accounting, initialization, and `withdrawFees()`
- `interfaces/IOracle.sol` continues to matter as supporting infrastructure for rate validity, freshness, and decimal-scaling assumptions that affect borrow, withdraw, and liquidation paths
- `cauldrons/PrivilegedCheckpointCauldronV4.sol` has become a more meaningful secondary surface due to checkpoint-token liquidation hook behavior and possible reentrancy/state-staleness interaction during liquidation
- `cauldrons/PrivilegedCauldronV4.sol` and supporting interfaces (`IBentoBoxV1`, `ICheckpointToken`, `ISwapperV2`, `IStrategy`) have mostly served as contextual surfaces rather than independent issue centers

## Issue Directions Seen
- `cook()` remains a recurring hotspot: flexible action dispatch, arbitrary external call capability, ETH forwarding/handling, and whether auxiliary actions can bypass or undermine intended safety checks
- Oracle integration is a durable cross-cutting concern, especially zero/invalid rates, stale cached prices, and mismatches between assumed and reported decimals
- Value-destination safety has emerged as another pattern: configuration-dependent recipients and contract-held assets can create loss or drain scenarios when sinks are unset or loosely controlled
- Liquidation logic continues to look promising for edge cases involving accounting consistency, hook-driven state changes, and reentrancy around externalized checkpoint behavior

## Useful Context
- Audit attention is still concentrated in `CauldronV4`, with most durable themes linking back to flexible control flow plus external dependency trust
- The strongest repeated pattern is that user-critical safety depends on post-action assumptions holding across external interactions, not just within isolated internal math
- Oracle risk and hook/callback risk both present as “state may be valid syntactically but unsafe semantically” rather than simple access-control failures
- Privileged variants remain less explored overall, but `PrivilegedCheckpointCauldronV4` now stands out more than `PrivilegedCauldronV4` because its liquidation hook creates a distinct external-interaction surface


## Latest Round Summary
# Round 3 Summary

## Agent: codex
- files touched: `cauldrons/CauldronV4.sol`, `cauldrons/PrivilegedCauldronV4.sol`, `cauldrons/PrivilegedCheckpointCauldronV4.sol`, `interfaces/IBentoBoxV1.sol`, `interfaces/ICheckpointToken.sol`, `interfaces/IOracle.sol`, `interfaces/IStrategy.sol`, `interfaces/ISwapperV2.sol`
- files revisited / highest-attention files: `cauldrons/CauldronV4.sol` received the deepest line-by-line review, especially borrow/accrual, skim, external-call, and fee/supply withdrawal areas; `cauldrons/PrivilegedCauldronV4.sol` got focused follow-up around `addBorrowPosition()`
- main issue directions investigated: privileged debt assignment and downstream MIM extraction; whether injected debt accrues historical interest incorrectly; skim-mode use of shared BentoBox balances for collateral and repayment
- promising but not retained directions: nearby external-call / checkpoint-hook variants were checked through external-call enumeration and `PrivilegedCheckpointCauldronV4.sol`, but did not become retained findings in this round

## Cross-Agent Status
- main overlap in file/area attention: only one agent log is present; attention centered on `cauldrons/CauldronV4.sol` and its interaction with `PrivilegedCauldronV4.sol`, especially debt accounting, accrual timing, and skim flows
- notable differences in attention: no cross-agent differences are visible because only `codex` appears in the round logs
- underexplored but suspicious files/functions if clearly supported by the logs: `cauldrons/PrivilegedCheckpointCauldronV4.sol` and the interface files were scanned more lightly than the core debt/skim paths in `CauldronV4.sol`

## Retained Findings
- retained findings from this round focus on three themes: privileged debt can be assigned to users without sending them MIM and paired with owner-side MIM withdrawal; the same privileged debt injection can accrue retroactive interest if added before `accrue()`; and public skim buckets can let third parties capture pre-staged collateral or MIM shares in non-atomic workflows


Output only markdown.
