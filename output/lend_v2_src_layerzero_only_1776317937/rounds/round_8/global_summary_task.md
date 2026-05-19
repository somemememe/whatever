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
- `LayerZero/CoreRouter.sol` - repeatedly high-attention for same-chain vs cross-chain borrow/supply/redeem/liquidation state transitions and accounting order effects.
- `LayerZero/CrossChainRouter.sol` - primary hotspot for cross-chain repay/borrow/liquidation message semantics, receive-path behavior, and amount/key forwarding correctness.
- `LayerZero/LendStorage.sol` - central bookkeeping surface for debt/supply aggregation, liquidity visibility, and asset-membership tracking.
- `LayerZero/interaces/*.sol` (repo typo path) + `LTokenInterfaces.sol` - mostly touched as wiring/schema context; semantic invariant coverage remains relatively light.
- `LayerZero/**/*.sol` grep/pattern sweeps - broad checks (auth/require/transfer/oracle/admin/pause/deadline surfaces) were run, but strongest signal still concentrated in router/storage flow accounting.

## Issue Directions Seen
- Accrual/order-of-operations mismatches (especially redeem/liquidity timing) causing accounting drift.
- Cross-chain attribution/write-target consistency risks (token identity and `srcEid`/`destEid` mapping-key correctness) that can desync debt/collateral state.
- Liquidation pipeline coupling risks: repay vs seize semantics, execution-time amount validity, and storage transition consistency.
- Asset-membership desync vs real balances/debts, including liquidation-related membership update gaps.
- Receive-path hard revert behavior as a potential message-lane grief/DoS direction.
- Unbounded asset-set iteration as recurring gas-DoS pressure for liquidity-sensitive operations.
- Lower-signal recurring probes: generic reentrancy, zero/div-by-zero, broad admin-control concerns.

## Useful Context
- Highest-yield method remains end-to-end state-flow tracing across `CrossChainRouter` <-> `CoreRouter` <-> `LendStorage`; broad checklist scans produced more overlap than new retained signal.
- Round 7 added deeper attention on cross-chain handler/revert behavior and endpoint/key consistency, but no new retained findings after merge.
- Interface-area coverage is still comparatively shallow relative to core router/storage internals and may hide invariant mismatches.
- Current retained signal profile remains: a small set of accounting/cross-chain consistency invariants with repeated overlap across agents.


## Latest Round Summary
# Round 8 Summary

## Agent: codex_1
- files touched: `LayerZero/CoreRouter.sol`, `LayerZero/CrossChainRouter.sol`, `LayerZero/LendStorage.sol`, and all three `LayerZero/interaces/*.sol` files
- files revisited / highest-attention files: strongest focus on `CoreRouter.sol` (liquidation path) and `LendStorage.sol` + `CrossChainRouter.sol` cross-chain debt accounting paths
- main issue directions investigated: cross-chain debt/index consistency across chains; liquidation limit math using stored principal vs accrued debt
- promising but not retained directions: submitted two new candidates (`F-025`, `F-026`) but none were retained after merge

## Agent: opencode_1
- files touched: all six in-scope LayerZero Solidity files, with repeated spot reads in `CrossChainRouter.sol` and `CoreRouter.sol`
- files revisited / highest-attention files: `CrossChainRouter.sol` received most repeated targeted reads; secondary attention on `CoreRouter.sol`
- main issue directions investigated: cross-chain borrow/repay/liquidation integrity, reward-claim authorization, chain-ID/position matching, authorized-contract trust boundaries, oracle/price handling
- promising but not retained directions: produced a broad set of candidate findings (`F-025` to `F-032` in that run), including stale cross-chain state and liquidation/repay mismatches, but none were retained

## Cross-Agent Status
- main overlap in file/area attention: both concentrated on `CrossChainRouter.sol` + `LendStorage.sol` interactions and liquidation/repay accounting paths
- notable differences in attention: `codex_1` was narrower and deeper on two concrete mechanisms; `opencode_1` explored a wider checklist-style surface including access control and reward-claim behavior
- underexplored but suspicious files/functions if clearly supported by the logs: no clearly isolated underexplored hotspot emerged from this round’s logs; attention stayed concentrated on cross-chain accounting/liquidation flows

## Retained Findings
- None retained from Round 8 after merge.


Output only markdown.
