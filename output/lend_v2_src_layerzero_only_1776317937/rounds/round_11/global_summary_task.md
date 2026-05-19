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
- `LayerZero/CrossChainRouter.sol` - persistent highest-attention surface; repeated scrutiny on receive/send execution, revert behavior, gas-bounded handling, and cross-chain liquidation mapping/state-drift paths.
- `LayerZero/CoreRouter.sol` - revisited for repay/liquidation control coupling, liquidation state cleanup, asset-membership consistency, and helper-path arithmetic.
- `LayerZero/LendStorage.sol` - continued focus on debt/supply/index/principal bookkeeping consistency across cross-chain transitions.
- `LayerZero/interaces/*.sol` (repo path typo), incl. `LendInterface.sol`, `LendtrollerInterfaceV2.sol`, `UniswapAnchoredViewInterface.sol`, plus `LTokenInterfaces.sol` - repeatedly referenced for wiring/schema context; semantic invariant scrutiny remains lighter than router/storage internals.
- Context alignment checks continued against `Lendtroller.sol` / `LendtrollerG7.sol` assumptions around market-entry/collateral-domain behavior.

## Issue Directions Seen
- Cross-chain accounting/invariant drift across `CrossChainRouter` <-> `CoreRouter` <-> `LendStorage` (principal/debt/index synchronization).
- Receive-path DoS/grief vectors: revert-on-missing-state handling, fixed receive-gas vs variable-cost handlers, and shared execution bottlenecks.
- Liquidation edge directions: repay-limit realism vs accrued debt, ordering/coupling in transitions, cleanup correctness, and membership/mapping consistency.
- Message/domain attribution risks (`srcEid`/`destEid`, position/token identity binding, collateral-domain validation coupling).
- Secondary recurring direction with lower signal: reward/helper accounting correctness (`lendAccrued`, withdraw helper math).

## Useful Context
- Round 10 again touched all in-scope LayerZero contracts; attention remained concentrated on `CrossChainRouter`, then `CoreRouter`/`LendStorage`.
- Cross-agent pattern persisted: one narrower deep pass on receive-path/state-accounting failure modes, one broader sweep with many candidates.
- Round 10 produced many candidates (F-030+ range) but none retained after merge; this is consistent with prior round outcome and does not reduce risk priority on core cross-chain invariants/DoS mechanics.
- Interface-layer files are repeatedly touched but still comparatively under-modeled at semantic/invariant level versus core router/storage flows.


## Latest Round Summary
# Round 11 Summary

## Agent: codex_1
- files touched
  - `LayerZero/CrossChainRouter.sol`, `LayerZero/CoreRouter.sol`, `LayerZero/LendStorage.sol`, `LayerZero/interaces/LendInterface.sol`, `LayerZero/interaces/LendtrollerInterfaceV2.sol`, `LayerZero/interaces/UniswapAnchoredViewInterface.sol` (plus context reads of `Lendtroller.sol` / `LendtrollerG7.sol`)
- files revisited / highest-attention files
  - Highest attention on `CrossChainRouter.sol`; repeated validation against `CoreRouter.sol` and `LendStorage.sol`
- main issue directions investigated
  - Non-atomic cross-chain state transitions (borrow/repay confirmation gaps)
  - Debt/accounting reconciliation edge cases
  - Shared-router-account liquidation/socialized-risk model
  - Concurrent cross-chain liquidation/close-factor race windows
- promising but not retained directions
  - Candidate set `F-034` to `F-038` was produced, but none were retained after merge

## Agent: opencode_1
- files touched
  - `LayerZero/CoreRouter.sol`, `LayerZero/CrossChainRouter.sol`, `LayerZero/LendStorage.sol`, and all three `LayerZero/interaces/*.sol` files
- files revisited / highest-attention files
  - Main analysis focus was `CoreRouter.sol`, `CrossChainRouter.sol`, `LendStorage.sol`
- main issue directions investigated
  - Cross-chain borrow/repay/liquidation accounting and index handling
  - Exchange-rate and debt-calculation correctness
  - Reward-claim access/control assumptions
- promising but not retained directions
  - Reported `F-034`+ candidates, including several directions already known from prior findings; none retained in this round

## Cross-Agent Status
- main overlap in file/area attention
  - Strong overlap on `CrossChainRouter.sol` and `CoreRouter.sol` cross-chain accounting/liquidation flows; both also reviewed `LendStorage.sol`
- notable differences in attention
  - `codex_1` emphasized message-finalization/non-atomic flow failure modes and shared-account systemic risk; `opencode_1` produced a broader mixed candidate set including some already-known issue classes
- underexplored but suspicious files/functions if clearly supported by the logs
  - `LayerZero/interaces/*.sol` remained comparatively light-touch context review versus router/storage internals

## Retained Findings
- None retained from Round 11 after merge.


Output only markdown.
