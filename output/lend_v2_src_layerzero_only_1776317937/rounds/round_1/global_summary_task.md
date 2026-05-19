You maintain a concise global audit memory for future audit agents.

Update the existing global memory using the latest round summary.

This memory is optional context only. It is not the canonical finding list,
not proof that any area is safe, and not an execution plan for the next agent.
Do not repeat full findings; findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows touched, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen so far

## Useful Context
- concise observations that may help future auditors avoid starting cold

Rules:
- keep it compact
- preserve useful prior context
- remove duplicated or stale detail
- do not claim an area is safe just because it was touched
- do not give step-by-step instructions for the next audit round

## Existing Global Memory
No global memory yet.

## Latest Round Summary
# Round 1 Summary

## Agent: codex_1
- files touched: `LayerZero/CoreRouter.sol`, `LayerZero/CrossChainRouter.sol`, `LayerZero/LendStorage.sol`, and all three `LayerZero/interaces/*.sol` files
- files revisited / highest-attention files: strongest focus on `LayerZero/CrossChainRouter.sol`, then `LayerZero/LendStorage.sol`, then `LayerZero/CoreRouter.sol`
- main issue directions investigated: same-chain borrow collateral gating, cross-chain borrow validation timing (stale snapshot), cross-chain debt/accounting inclusion logic, borrow-index/debt accrual updates, LayerZero fee funding model, cross-chain liquidation finalization/message token identity
- promising but not retained directions: none clearly separate from retained set (all major reported directions were retained after merge, with wording/severity normalization)

## Agent: opencode_1
- files touched: `LayerZero/CoreRouter.sol`, `LayerZero/CrossChainRouter.sol`, `LayerZero/LendStorage.sol`, and all three `LayerZero/interaces/*.sol` files
- files revisited / highest-attention files: broad read across all scoped files; no clear deep revisit trail in the log
- main issue directions investigated: missing reentrancy guard pattern across router entrypoints; liquidation condition correctness in `CoreRouter`
- promising but not retained directions: broad “missing reentrancy guards” claim and “inverted liquidation shortfall check” claim were proposed but not retained in merged findings

## Cross-Agent Status
- main overlap in file/area attention: both agents centered on `CoreRouter`, `CrossChainRouter`, and `LendStorage` as primary risk surfaces
- notable differences in attention: `codex_1` concentrated on concrete cross-chain state/accounting/message-flow exploits; `opencode_1` emphasized generic defensive patterns and a liquidation check hypothesis
- underexplored but suspicious files/functions if clearly supported by the logs: interface files were only lightly inspected; `CoreRouter` liquidation-check region (around the line flagged by `opencode_1`) remains a touched-but-unretained hotspot in current status

## Retained Findings
- six findings were retained, dominated by cross-chain solvency/accounting failures and one same-chain borrow gate bypass
- retained criticals: initial borrow collateral-bypass path, stale-collateral TOCTOU in cross-chain borrow, and cross-chain debt exclusion from accounting due EID condition logic
- retained non-criticals: debt under-accounting on cross-chain borrow-index refresh, protocol-funded LayerZero fee griefing, and cross-chain liquidation finalization mismatch/lookup inconsistency


Output only markdown.
