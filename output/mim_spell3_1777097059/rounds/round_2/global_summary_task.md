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
- `cauldrons/CauldronV4.sol` is the central audit surface so far, especially `cook()` dispatch/final solvency interactions and oracle-dependent borrow, withdraw, and liquidation paths
- `interfaces/IOracle.sol` matters as a supporting surface for rate validity and scaling assumptions, especially around `decimals()` and cached price behavior
- `cauldrons/PrivilegedCauldronV4.sol` and `cauldrons/PrivilegedCheckpointCauldronV4.sol` were opened but remain secondary/underexplored compared with the main cauldron flow
- Supporting interfaces (`IBentoBoxV1`, `ICheckpointToken`, `IStrategy`, `ISwapperV2`) were referenced mainly for context rather than as independent issue centers

## Issue Directions Seen
- `cook()` action dispatch is a recurring hotspot, particularly whether unhandled or auxiliary actions can alter state without triggering the intended final solvency check
- Oracle integration is a major theme: fixed-decimal assumptions versus oracle-reported decimals, acceptance of zero/invalid rates, and unsafe handling of stale cached prices
- Pricing safety concerns appear to cut across multiple user-critical paths rather than a single function, especially borrowing, collateral withdrawal, and liquidation

## Useful Context
- Audit attention is highly concentrated in `CauldronV4`, with oracle handling emerging as the main cross-cutting dependency
- The strongest retained pattern so far is interaction risk between control-flow flexibility (`cook()`) and post-action safety enforcement
- Another durable pattern is weak trust assumptions around oracle outputs: freshness, nonzero validity, and scaling are all treated as potentially unsafe
- Privileged cauldron variants have been noticed but not yet developed into separate durable issue themes


## Latest Round Summary
# Round 2 Summary

## Agent: codex
- files touched: `cauldrons/CauldronV4.sol`, `cauldrons/PrivilegedCauldronV4.sol`, `cauldrons/PrivilegedCheckpointCauldronV4.sol`, `interfaces/IBentoBoxV1.sol`, `interfaces/IOracle.sol`, `interfaces/ICheckpointToken.sol`, `interfaces/ISwapperV2.sol`
- files revisited / highest-attention files: `cauldrons/CauldronV4.sol` was the main focus, with repeated line-level review around `cook()` helpers, liquidation logic, initialization, and `withdrawFees()`; `cauldrons/PrivilegedCheckpointCauldronV4.sol` got targeted follow-up for liquidation-hook behavior
- main issue directions investigated: fee withdrawal destination safety before `feeTo` is configured; ETH handling in payable `cook()` / arbitrary call forwarding; liquidation accounting edge cases and stale-state/reentrancy risks from checkpoint hooks
- promising but not retained directions: a batch-liquidation rounding / “ghost debt” theory in `CauldronV4.liquidate()` was drafted as `F-007` in the agent output but was not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: round activity was concentrated in `cauldrons/CauldronV4.sol`, especially `cook()`, liquidation flow, and fee withdrawal logic
- notable differences in attention: no cross-agent differences are visible in the provided logs because only `codex` appears for this round
- underexplored but suspicious files/functions if clearly supported by the logs: `cauldrons/PrivilegedCauldronV4.sol` and the interface files were only briefly scanned relative to the deeper review of `CauldronV4.sol` and `PrivilegedCheckpointCauldronV4.sol`

## Retained Findings
- retained issues from this round center on three themes: permissionless fee withdrawal can send accrued fees to an unset zero recipient; stranded native ETH in the cauldron can be drained via `cook(ACTION_CALL)`; and the checkpoint-token hook in `PrivilegedCheckpointCauldronV4` introduces a low-confidence but high-impact reentrancy risk during liquidation accounting


Output only markdown.
