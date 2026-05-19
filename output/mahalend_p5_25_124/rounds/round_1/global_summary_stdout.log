# Global Audit Memory

## Scope Touched
- `Pool.sol`: central entrypoint tying together supply/borrow/flash-loan/liquidation flows; repeated focus on cross-flow accounting and state transitions
- `FlashLoanLogic.sol`: high-attention area for callback-driven state reuse, especially debt-opening paths and pre/post-callback validation assumptions
- `BorrowLogic.sol`: borrow validation and debt-accounting interactions, including isolation-mode and eMode-sensitive checks
- `SupplyLogic.sol`: reserve/accounting assumptions around credited amounts versus actual token receipts
- `LiquidationLogic.sol`: repeated scrutiny on liquidation math, collateral-flag cleanup, and protocol-fee side effects after full position unwinds
- `ValidationLogic.sol`: core risk-gating layer; important for stale-context validation, oracle/account checks, and configuration edge cases
- `GenericLogic.sol`: shared health-factor / account-state computations repeatedly treated as a key dependency for borrow and liquidation correctness
- `BridgeLogic.sol`: included in transfer-accounting review, especially unbacked/backing flows that may rely on nominal token amounts
- `ReserveLogic.sol`: secondary hotspot for reserve state initialization/accounting assumptions, though no retained issue yet
- `EModeLogic.sol` and `UserConfiguration.sol`: relevant to category/state reuse and collateral-bit persistence after balances reach zero
- math/config helpers (`PoolLogic.sol`, `DataTypes.sol`, `WadRayMath.sol`, `PercentageMath.sol`, `Helpers.sol`): supporting context for rounding, config interpretation, and shared state layout

## Issue Directions Seen
- Stale risk-context use across multi-step flows, especially where flash-loan callbacks can alter user state before debt validation completes
- Cross-flow reserve solvency risk when logic assumes nominal transfer amounts rather than actual received tokens
- Liquidation cleanup inconsistencies around collateral flags, zero balances, protocol fees, and isolation-mode side effects
- Shared account/risk logic is a recurring choke point: health-factor, eMode, oracle, and config assumptions propagate into multiple entrypoints
- Precision, liquidation math, and reserve/config edge cases were repeatedly explored, but most remained unretained so far
- Reentrancy and callback surface around flash-loans drew attention, but durable concern is more about state invalidation than generic reentry alone

## Useful Context
- Audit attention has concentrated on core pool accounting and risk logic rather than peripheral modules
- The strongest cross-round pattern is interactions between user-configuration bits, shared validation logic, and callback-enabled flow composition
- Listed-token behavior matters materially: several reviewed paths appear safest only if assets transfer exactly the nominal amount
- Several broad themes were screened and mostly deprioritized: generic oracle manipulation, dust/rounding-only abuse, stable-rate rebalance abuse, timestamp games, reserve reinitialization, and admin-rescue centralization
- Underexplored but still relevant areas include `ReserveLogic.sol` and liquidation math/config branches that received attention without producing a merged finding
