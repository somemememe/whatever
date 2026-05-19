# Round 1 Summary

## Agent: codex_1
- files touched: `Comptroller.sol`, `BToken.sol`, `BTokenInterfaces.sol`; file map also enumerated the rest of `money-market/*.sol`
- files revisited / highest-attention files: `Comptroller.sol` by far; `BTokenInterfaces.sol` used to validate collateral-cap hooks
- main issue directions investigated: delisting behavior and liquidity accounting, market-listing invariants in `_supportMarket`, credit-limit handling for credit accounts, collateral-cap version / exit-market bookkeeping
- promising but not retained directions: market self-reporting via `updateBTokenVersion` changing Comptroller-side behavior

## Agent: opencode_1
- files touched: `BToken.sol`, `Comptroller.sol`, `BTokenInterfaces.sol`, `ComptrollerStorage.sol`, `Exponential.sol`, `Unitroller.sol`
- files revisited / highest-attention files: `Comptroller.sol` (read multiple times, including later-offset revisit)
- main issue directions investigated: delisting and allowed-operation behavior, flash loan policy checks, credit-limit and admin/guardian control paths, liquidation incentive / liquidation flow assumptions, oracle freshness, supply/borrow caps
- promising but not retained directions: flash-loan check gaps, soft-delisted markets still allowing operations, zero liquidation incentive, guardian pause permanence, stale-price risk, cap-to-zero lockups, miscellaneous BToken liquidation/interest-accrual concerns

## Cross-Agent Status
- main overlap in file/area attention: `Comptroller.sol`, especially market delisting and how policy hooks affect liquidity, repayment, liquidation, and seizure
- notable differences in attention: `codex_1` concentrated on Comptroller state-machine / configuration invariants; `opencode_1` surveyed a broader set of operational and admin-control themes across flash loans, caps, oracle use, and pause controls
- underexplored but suspicious files/functions if clearly supported by the logs: `BToken.sol` and `Unitroller.sol` were read by both/one agent but produced no retained findings; retained findings remained overwhelmingly Comptroller-centered

## Retained Findings
- Hard-delisting a live market can remove its debt from solvency checks while also blocking normal repay/liquidate/seize flows, creating trapped positions and bad debt.
- `_supportMarket` can accept an incompatible BToken from another comptroller, allowing collateral that later may not be seizable/liquidatable under local rules.
- Lowering a credit limit below existing debt does not reconcile the position and can preserve credit-account immunity, freezing oversized unsecured debt in place.
- Soft-delisting a collateral-cap market clears controller-side version state and can skip `unregisterCollateral`, leaving stale collateral-cap accounting.
