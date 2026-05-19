# Global Audit Memory

## Scope Touched
- `Comptroller.sol`: central risk surface; market listing/delisting state transitions, policy hooks, liquidity accounting, credit-limit handling, liquidation/repay/seize permissions
- `BToken.sol` / `BTokenInterfaces.sol`: integration boundary with comptroller; collateral-cap hooks and compatibility assumptions between controller and market implementations
- `ComptrollerStorage.sol`: relevant for persistent market/config state tied to delisting, caps, and credit controls
- `Unitroller.sol`: proxy/admin control surface noted but still underexplored relative to comptroller logic
- `money-market/*.sol` broadly: reviewed as surrounding context, but retained issue pressure remains overwhelmingly comptroller-centered

## Issue Directions Seen
- Delisting is the dominant recurring direction: transitions can desynchronize solvency checks from allowed repay/liquidate/seize paths and from collateral-cap bookkeeping
- Market onboarding/support invariants are fragile: comptroller acceptance of incompatible `BToken` instances can break downstream liquidation/seizure assumptions
- Credit-account / credit-limit mechanics look prone to stale privilege or immunity states when limits/config are tightened after debt already exists
- Controller-side versioning and collateral-cap registration state can drift during market configuration changes
- Broader admin-control and operational themes were surveyed repeatedly but not retained: pause controls, caps, flash-loan checks, oracle freshness, liquidation parameter edge cases

## Useful Context
- Cross-round attention concentrated much more on comptroller state-machine behavior than on token internals
- The most durable pattern is configuration changes on live markets producing inconsistent accounting or permission surfaces rather than immediate arithmetic errors
- `BToken` and `Unitroller` were touched enough to matter as dependency/context files, but not yet with the same depth as `Comptroller.sol`
- Several discarded leads still indicate useful perimeter areas, but current retained understanding is that the highest-signal risks come from comptroller-mediated lifecycle and authorization transitions
