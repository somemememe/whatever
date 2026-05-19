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
- `LayerZero/CrossChainRouter.sol` - still the top hotspot; cross-chain borrow/repay/liquidation routing, message finalization coupling, domain/key binding, and fee-handling paths repeatedly scrutinized.
- `LayerZero/CoreRouter.sol` - repay/liquidation ordering, state cleanup sequencing, collateral-check math/index interactions, and router-to-storage consistency remain central.
- `LayerZero/LendStorage.sol` - recurring focus for principal/debt/index bookkeeping coherence (including borrow-index initialization assumptions), but still less deeply exhausted than router logic.
- `LayerZero/interaces/*.sol` (`LendInterface.sol`, `LendtrollerInterfaceV2.sol`, `UniswapAnchoredViewInterface.sol`) - repeatedly used as wiring/schema context; invariant-level interface assumption testing remains light.
- `Lendtroller.sol` - continued context anchor for collateral membership/liquidation assumptions; mostly reference-level use.

## Issue Directions Seen
- Cross-chain accounting drift across `CrossChainRouter` <-> `CoreRouter` <-> `LendStorage` (liabilities/principal/debt/index coherence).
- Non-atomic cross-chain lifecycle risk (borrow/repay/liquidation confirmation gaps, receive-path mismatch/failure windows).
- Liquidation consistency risks (path selection, parameter initialization/validation, close-factor realism vs accrued debt, cleanup transitions).
- Repay-path ordering/reentrancy-style cleanup risks in router flows.
- Message/domain identity attribution and collateral-position key binding (`srcEid`/`destEid` linkage correctness).
- Economic/config side paths worth continued pressure: LayerZero message fee handling and protocol reward accumulation/realization interactions.

## Useful Context
- Round 13 again concentrated on `CrossChainRouter.sol`, `CoreRouter.sol`, and `LendStorage.sol`, with strongest overlap on `CrossChainRouter.sol`.
- Candidate findings were generated in both rounds (`F-038` to `F-045` overall across R12-R13) but none retained; this indicates unresolved ambiguity, not safety.
- One agent emphasized deeper flow/config consistency (including fee/reward mechanics and struct-memory behavior checks), while another emphasized narrower repay/liquidation candidates.
- `LayerZero/interaces` path typo persists in repo/audit traces and can affect quick navigation/search consistency.


## Latest Round Summary
# Round 14 Summary

## Agent: codex_1
- files touched: `LayerZero/CoreRouter.sol`, `LayerZero/CrossChainRouter.sol`, `LayerZero/LendStorage.sol`
- files revisited / highest-attention files: repeated deep reads in `CoreRouter.sol` (borrow/redeem/liquidation paths) and `CrossChainRouter.sol` (cross-chain borrow/liquidation handlers)
- main issue directions investigated: stale accrual/state use in liquidity checks; cross-chain liquidation market mapping validation; cross-chain seize-amount domain consistency
- promising but not retained directions: proposed F-046/F-047/F-048 set (stale market-state risk checks, unmapped seize market packet failure, cross-domain seize mismatch)

## Agent: opencode_1
- files touched: `LayerZero/CoreRouter.sol`, `LayerZero/CrossChainRouter.sol`, `LayerZero/LendStorage.sol`, `LayerZero/interaces/LendtrollerInterfaceV2.sol`, `LayerZero/interaces/LendInterface.sol`
- files revisited / highest-attention files: `LendStorage.sol` and `CrossChainRouter.sol` via multiple targeted greps/offset reads (`findCrossChain`, `currentEid`, `storedBorrowIndex`, rewards/distribution, liquidation handlers)
- main issue directions investigated: cross-chain record/key consistency (`srcEid`/`destEid`), reward accounting/withdrawability, division-by-zero surfaces, liquidation validation semantics
- promising but not retained directions: proposed F-046..F-050 set (protocol reward lock, borrower distribution div-by-zero, liquidation success `srcEid` mismatch, cross-chain borrow-index inconsistency, seize-vs-repay validation mismatch)

## Cross-Agent Status
- main overlap in file/area attention: both concentrated on `CrossChainRouter.sol` liquidation/borrow handlers and `LendStorage.sol` accounting-liquidity logic
- notable differences in attention: codex_1 emphasized stale accrual and packet/processability in cross-chain liquidation; opencode_1 emphasized reward/distribution edge cases and chain-ID/index matching logic breadth
- underexplored but suspicious files/functions if clearly supported by the logs: interface files had minimal attention overall; most depth stayed in router/storage execution paths rather than interface-contract assumptions

## Retained Findings
- None retained from this round after merge.


Output only markdown.
