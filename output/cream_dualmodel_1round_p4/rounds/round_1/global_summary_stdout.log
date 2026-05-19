# Global Audit Memory

## Scope Touched
- `0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CTokenCheckRepay.sol` — recurring hotspot for repay/liquidation flow diffs versus base `CToken`, including health-check placement and flash-loan-adjacent behavior
- `0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CCollateralCapErc20CheckRepay.sol` — main surface for collateral-cap accounting, flash-loan logic, and reserve-sync side paths
- `0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CCollateralCapErc20CheckRepayDelegate.sol` + `0x2db6c82ce72c8d7d770ba1b5f5ed0b6e075066d6/contracts/CErc20Delegator.sol` — upgrade/delegation context, especially initialization and storage/backfill implications
- `0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CToken.sol` — baseline implementation used for modified-flow diffing
- Supporting interfaces/storage (`ComptrollerStorage.sol`, `ComptrollerInterface.sol`, `CTokenInterfaces.sol`, `Exponential.sol`, `ERC3156FlashBorrowerInterface.sol`) — checked mainly to validate surrounding assumptions rather than as primary bug sources

## Issue Directions Seen
- Modified repay/liquidation paths remain a key audit direction, especially where post-repayment solvency checks diverge from base Compound-style flows
- Collateral-cap upgrades are a durable risk area: legacy balances and delayed account initialization can leave accounting out of sync with configured caps
- Flash-loan integration semantics matter beyond pure accounting, particularly receiver trust in caller-controlled `initiator` values
- Upgradeable/delegated market wiring is a recurring lens for finding state migration and initialization mismatches
- Several adjacent directions were investigated but not retained so far: flash-loan reentrancy/state windows, `gulp()` reserve-sync effects, admin setter/access-control patterns, and ERC-3156 callback compatibility edge cases

## Useful Context
- Cross-round attention strongly concentrates on `CTokenCheckRepay.sol` and `CCollateralCapErc20CheckRepay.sol`; these are the primary contracts anchoring the audit
- The most durable confirmed issue themes so far are upgrade-time collateral accounting gaps and flash-loan integration trust assumptions, not generic math or interface mistakes
- `CErc20Delegator` and delegate initialization paths matter mainly as context for how new collateral-cap logic is introduced into existing markets with legacy state
- Broader supporting contracts helped frame assumptions, but the audit signal is currently strongest in flow deltas and upgrade/state-transition behavior
