# Global Audit Memory

## Scope Touched
- `ConicPoolV2.sol`: central surface for pool offboarding/depeg handling, allocation selection and rounding behavior, and Convex-pool invalidation paths
- `RewardManagerV2.sol`: core reward liquidation/accounting surface, especially token custody assumptions, zero-staker reward accrual, and swap/min-out handling
- `ConvexHandlerV3.sol`: relevant to reward-claim flow correctness and interaction mismatches with downstream accounting
- Supporting interfaces/libs reviewed around the core path: `IConicPool`, `IController`, `ILpTokenStaker`, `IInflationManager`, `IOracle`, `ScaledMath`, `CurvePoolUtils`, token/router base contracts

## Issue Directions Seen
- Reward-flow mismatches between where Convex rewards are claimed, where liquidation expects balances, and how accounting credits users
- Reward accounting around empty-staker intervals remains a strong direction; custody/accrual state can advantage later entrants
- CVX-specific accounting is sensitive because entitlement may be booked from estimates before actual claim output is known
- Permissionless safety actions around depeg/offboarding are tightly coupled to oracle freshness and cached pricing assumptions
- Allocation math for deposits/withdrawals has an edge-case direction where rounding can leave no valid pool choice and cause reverts
- Secondary directions that received attention but were not retained: swap slippage/min-out paths, `handleInvalidConvexPid()` access control, delegatecall/reentrancy framing, approval-risk patterns, helper/math edge cases

## Useful Context
- Cross-round attention concentrated heavily on `ConicPoolV2`, `RewardManagerV2`, and `ConvexHandlerV3`; those contracts define the main economic and control-flow risk surface
- The strongest recurring theme is inconsistency across contract boundaries: claim destination, token custody, oracle/cache timing, and accounting snapshots do not obviously share one source of truth
- Audit coverage included a wider checklist on access control and swap safety, but retained signal so far is mostly in reward-accounting and permissionless pool-management behavior
