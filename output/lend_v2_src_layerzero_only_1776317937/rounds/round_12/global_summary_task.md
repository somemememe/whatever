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
- `LayerZero/CrossChainRouter.sol` - still the primary hotspot; repeated focus on cross-chain receive/send finalization, non-atomic confirmation paths, and liquidation message/state coupling.
- `LayerZero/CoreRouter.sol` - heavily revisited for borrow/repay/liquidation accounting transitions, close-factor/liquidation flow ordering, and control coupling with router state.
- `LayerZero/LendStorage.sol` - repeatedly checked for debt/principal/index reconciliation and cross-chain bookkeeping consistency.
- `LayerZero/interaces/*.sol` (`LendInterface.sol`, `LendtrollerInterfaceV2.sol`, `UniswapAnchoredViewInterface.sol`) - used mainly as wiring/schema context; semantic invariant modeling remains comparatively shallow.
- Context reads against `Lendtroller.sol` / `LendtrollerG7.sol` continue to anchor collateral/market-membership assumptions.

## Issue Directions Seen
- Cross-chain accounting drift across `CrossChainRouter` <-> `CoreRouter` <-> `LendStorage` (principal, debt, index, exchange-rate/debt math alignment).
- Non-atomic cross-chain lifecycle risk (borrow/repay confirmation gaps, message finalization failure modes, revert/gas-bounded receive-path griefing).
- Liquidation risk directions: shared-router-account socialized exposure, concurrent liquidation race windows, transition cleanup/mapping consistency, close-factor realism vs accrued debt.
- Message/domain attribution and identity binding checks (`srcEid`/`destEid`, token/position binding, collateral-domain coupling).
- Lower-signal recurring direction: reward/helper accounting and claim/access-control assumptions.

## Useful Context
- Round 11 mirrored prior concentration: strongest overlap on `CrossChainRouter.sol`, `CoreRouter.sol`, and `LendStorage.sol`; interface files were touched again but mostly context-level.
- Cross-agent split persisted: one deeper pass on non-atomic/finalization systemic risk, one broader sweep including known issue classes.
- Candidate IDs in the `F-034+` range were generated again in Round 11, but none were retained after merge; this does not lower priority on core cross-chain invariant and receive-path DoS directions.
- `LayerZero/interaces` path typo persists in repo references; file set is still repeatedly consulted but under-modeled relative to router/storage internals.


## Latest Round Summary
# Round 12 Summary

## Agent: codex_1
- files touched: `LayerZero/CoreRouter.sol`, `LayerZero/CrossChainRouter.sol`, `LayerZero/LendStorage.sol`, `LayerZero/interaces/LendInterface.sol`, `LayerZero/interaces/LendtrollerInterfaceV2.sol`, `LayerZero/interaces/UniswapAnchoredViewInterface.sol` (plus brief context read of `../src/Lendtroller.sol`)
- files revisited / highest-attention files: highest attention on `LayerZero/CoreRouter.sol`; secondary attention on `LayerZero/CrossChainRouter.sol`
- main issue directions investigated: repay-path reentrancy/state cleanup ordering, liquidation accounting consistency, borrow collateral-check math/index handling, cross-chain collateral-record matching keys
- promising but not retained directions: proposed F-038 to F-041 (CoreRouter/CrossChainRouter) but none were retained after merge

## Agent: opencode_1
- files touched: all 6 in-scope `LayerZero/**/*.sol` files
- files revisited / highest-attention files: explicit analysis focus tracked for `CoreRouter.sol`, `CrossChainRouter.sol`, and `LendStorage.sol`
- main issue directions investigated: broad pass for “new vulnerabilities” across core router, cross-chain router, and storage logic
- promising but not retained directions: no concrete findings produced (final output was `null`)

## Cross-Agent Status
- main overlap in file/area attention: both agents reviewed the full in-scope LayerZero set, with overlapping attention on `CoreRouter.sol` and `CrossChainRouter.sol`
- notable differences in attention: `codex_1` produced line-specific candidate vulnerabilities and exploit paths; `opencode_1` completed a broad scan but returned no actionable findings
- underexplored but suspicious files/functions if clearly supported by the logs: `LayerZero/LendStorage.sol` appears relatively underdeveloped in documented deep analysis (read by both, but only limited evidenced drill-down)

## Retained Findings
- None retained from this round after merge.


Output only markdown.
