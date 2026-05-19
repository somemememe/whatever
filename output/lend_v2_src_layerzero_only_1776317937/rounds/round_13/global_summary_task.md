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
# Global Audit Memory

## Scope Touched
- `LayerZero/CoreRouter.sol` - highest recurring focus; repay/liquidation ordering, state cleanup sequencing, and collateral-check math/index handling remain central.
- `LayerZero/CrossChainRouter.sol` - continued hotspot for cross-chain message finalization, receive/send coupling, and collateral-record key/binding consistency.
- `LayerZero/LendStorage.sol` - repeatedly reviewed for debt/principal/index bookkeeping alignment; still comparatively underdeveloped in documented deep drill-down.
- `LayerZero/interaces/*.sol` (`LendInterface.sol`, `LendtrollerInterfaceV2.sol`, `UniswapAnchoredViewInterface.sol`) - repeatedly used as schema/wiring context, limited invariant-level analysis.
- Context anchoring via `Lendtroller.sol` / `LendtrollerG7.sol` persists for collateral membership and liquidation assumption checks.

## Issue Directions Seen
- Cross-chain accounting drift across `CrossChainRouter` <-> `CoreRouter` <-> `LendStorage` (principal/debt/index and collateral-state coherence).
- Non-atomic cross-chain lifecycle risk (borrow/repay confirmation gaps, receive-path failure/griefing, finalization mismatch windows).
- Liquidation consistency risks (close-factor realism vs accrued debt, transition cleanup, concurrent state-race exposure).
- Repay-path reentrancy and state cleanup ordering in router flows.
- Message/domain identity attribution and key binding (`srcEid`/`destEid`, token-position-collateral linkage).

## Useful Context
- Round 12 again concentrated on `CoreRouter.sol` and `CrossChainRouter.sol`; both agents covered full in-scope LayerZero files.
- One agent produced line-level candidates (`F-038` to `F-041`) but none were retained; the other agent’s broad sweep returned no concrete findings.
- No retained findings in Round 12; this is not evidence that core router/cross-chain invariant directions are exhausted.
- `LayerZero/interaces` path typo remains in repo references and continues to appear in audit traces.


## Latest Round Summary
# Round 13 Summary

## Agent: codex_1
- files touched: `LayerZero/CoreRouter.sol`, `LayerZero/CrossChainRouter.sol`, `LayerZero/LendStorage.sol`, `LayerZero/interaces/LendInterface.sol`, `LayerZero/interaces/LendtrollerInterfaceV2.sol`, `LayerZero/interaces/UniswapAnchoredViewInterface.sol`; also referenced `Lendtroller.sol` for context
- files revisited / highest-attention files: highest attention on `LayerZero/CrossChainRouter.sol`, then `LayerZero/CoreRouter.sol` and `LayerZero/LendStorage.sol`
- main issue directions investigated: cross-chain borrow authorization vs liabilities, router/storage lendtroller consistency, LayerZero message fee handling, protocol reward accumulation/realization path, and validation of struct/memory behavior with a local `solc` test
- promising but not retained directions: four candidates (F-042 to F-045) were produced by the agent, but none were retained in round merge

## Agent: opencode_1
- files touched: `LayerZero/CoreRouter.sol`, `LayerZero/CrossChainRouter.sol`, `LayerZero/LendStorage.sol`, `LayerZero/interaces/LendInterface.sol`, `LayerZero/interaces/LendtrollerInterfaceV2.sol`; also read prior `round_12/round_summary.md`
- files revisited / highest-attention files: focused on the three main LayerZero contracts, especially `CrossChainRouter.sol`
- main issue directions investigated: cross-chain repay/liquidation path correctness and liquidation parameter initialization/validation behavior
- promising but not retained directions: proposed two candidates (cross-chain repay path selection; zero `storedBorrowIndex` initialization risk), both unretained

## Cross-Agent Status
- main overlap in file/area attention: strong overlap on `CrossChainRouter.sol`, `CoreRouter.sol`, and `LendStorage.sol`, with cross-chain borrow/repay/liquidation logic as the core focus
- notable differences in attention: `codex_1` did deeper flow tracing and state/config consistency checks (including fee and protocol reward mechanics), while `opencode_1` concentrated on narrower repay/liquidation-path candidates and reviewed prior-round summary
- underexplored but suspicious files/functions if clearly supported by the logs: interface files were only read lightly; no agent log shows deep investigation of interface-level assumptions beyond basic inspection

## Retained Findings
- None retained from this round after merge.


Output only markdown.
