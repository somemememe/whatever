# Global Audit Memory

## Scope Touched
- `contracts/LinearPool.sol`: central hotspot for state/accounting integrity, pause/emergency-exit lifecycle, virtual supply, fee/target behavior, and transient pricing surfaces
- `@balancer-labs/v2-pool-utils/contracts/BasePool.sol`: shared base logic repeatedly relevant for joins/exits, rate exposure, and authorization-linked behavior
- `contracts/aave/AaveLinearPool.sol`: wrapper valuation assumptions and dependence on external Aave-style rate sources
- `contracts/LinearMath.sol`: math edge cases around nominal conversions and precision surfaced as a secondary direction
- `@balancer-labs/v2-pool-utils/contracts/rates/PriceRateCache.sol`: reviewed as part of rate/valuation path, still a useful supporting context file
- `@balancer-labs/v2-pool-utils/contracts/BasePoolAuthorization.sol`: reviewed around permission surface, but without retained issue so far

## Issue Directions Seen
- Emergency-exit and pause/unpause flows can desynchronize virtual-supply-based accounting from actual pool state
- `getRate()` and related rate surfaces may expose transient or settlement-sensitive state during joins/exits
- Linear pool safety depends heavily on wrapper/rate-source economic consistency, especially for Aave-backed pools
- Fee-target updates, initialization paths, and math conversion boundaries are recurring secondary review directions around `LinearPool`

## Useful Context
- Cross-round attention is concentrated on the `LinearPool` / `BasePool` / `AaveLinearPool` cluster; most promising directions originate there
- The strongest durable pattern is coupling between pool accounting state, externally consumed pricing/rates, and recovery/emergency control flow
- Supporting files like `LinearMath`, `PriceRateCache`, and authorization helpers have appeared mainly as enablers or validation points for the core linear-pool themes rather than as standalone issue centers
