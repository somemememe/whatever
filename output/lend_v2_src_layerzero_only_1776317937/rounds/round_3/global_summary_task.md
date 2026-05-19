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
- `LayerZero/CoreRouter.sol` - same-chain borrow gating, liquidation eligibility math/check wiring, repay-position lookup behavior.
- `LayerZero/CrossChainRouter.sol` - cross-chain borrow/liquidation ordering, validation/finalization atomicity, messaging/fee flow handling.
- `LayerZero/LendStorage.sol` - debt/supply accounting, borrow aggregation invariants, index/exchange-rate application points.
- `LayerZero/interfaces/*.sol` - reviewed for schema/router-storage consistency; still comparatively shallow and low-yield.

## Issue Directions Seen
- Cross-chain liquidation atomicity/order breaks (validation vs execution/finalization timing).
- Solvency/accounting drift from stale snapshots or stale pre-mint rate usage.
- Debt mis-accounting from index reapplication or direction/EID-conditioned aggregation logic.
- Cross-direction borrow aggregation invariant failures causing DoS-style state blockage.
- Repay attribution ambiguity when keyed by `srcEid`/position-selection assumptions.
- ERC20 transfer return-value handling gaps in critical token movement paths.
- Reentrancy/dust/front-run/observability themes were explored repeatedly but not retained so far.

## Useful Context
- Attention remains heavily concentrated on `CoreRouter`, `CrossChainRouter`, and `LendStorage`; retained risk is mostly cross-chain state-transition/accounting integrity, not generic hardening.
- Current retained set is seven substantive issues, dominated by liquidation flow correctness and debt/supply accounting semantics.
- Interface-layer review has been broad but low-depth in root-cause yield; ETH fee-withdraw/accounting observability was flagged once but not retained.


## Latest Round Summary
# Round 3 Summary

## Agent: codex_1
- files touched
  - `LayerZero/CoreRouter.sol`, `LayerZero/CrossChainRouter.sol`, `LayerZero/LendStorage.sol` (plus interface file-name discovery/grep context)
- files revisited / highest-attention files
  - Highest attention on `CoreRouter.sol` and `LendStorage.sol` (claim flow, borrow/redeem paths, liquidity math), with targeted checks in `CrossChainRouter.sol` borrow path
- main issue directions investigated
  - Reward-claim accounting integrity (`claimLend` / `lendAccrued`)
  - Liquidity-check correctness under oracle edge cases (zero price handling)
  - External-call-before-accounting patterns in same-chain `borrow`/`redeem` (reentrancy surface)
- promising but not retained directions
  - Broader cross-chain/accounting patterns were explored, but only three issues were retained after merge

## Agent: opencode_1
- files touched
  - `LayerZero/CoreRouter.sol`, `LayerZero/CrossChainRouter.sol`, `LayerZero/LendStorage.sol`
  - `LayerZero/interaces/LendInterface.sol`, `LayerZero/interaces/LendtrollerInterfaceV2.sol`, `LayerZero/interaces/UniswapAnchoredViewInterface.sol`
  - Round-2 summary file was also read for context
- files revisited / highest-attention files
  - Primary focus appeared on `CoreRouter.sol`, `CrossChainRouter.sol`, `LendStorage.sol`
- main issue directions investigated
  - Borrow collateral checks, cross-chain borrow/repay indexing and routing, liquidation sequencing/validation, native-fee handling, and reentrancy-style concerns
- promising but not retained directions
  - Multiple candidate findings were proposed (including liquidation sequencing, repay routing ambiguity, fee/refund handling, and misc. medium/low issues) but none were retained in the merged round output

## Cross-Agent Status
- main overlap in file/area attention
  - Strong overlap on `CoreRouter.sol` + `LendStorage.sol` liquidity/borrow accounting and `CrossChainRouter.sol` cross-chain borrow/liquidation logic
- notable differences in attention
  - `codex_1` concentrated on fewer, better-substantiated issues that were retained
  - `opencode_1` covered many broader hypotheses, but they did not survive merge
- underexplored but suspicious files/functions if clearly supported by the logs
  - Current status: `CrossChainRouter.sol` liquidation message-ordering and fee-payment/refund paths were flagged by one agent but remain unretained/unconfirmed this round

## Retained Findings
- `F-014` (High): `claimLend` transfers accrued rewards without decrementing stored `lendAccrued`, enabling repeated claims/drain of router-held LEND.
- `F-015` (High): Liquidity checks accept zero oracle prices, creating fail-open borrow authorization when price feeds return `0`.
- `F-016` (Medium): `borrow`/`redeem` update accounting after external calls, leaving a reentrancy window for callback-capable tokens.


Output only markdown.
