# Global Audit Memory

## Scope Touched
- `cauldrons/CauldronV4.sol` — primary audit hotspot; repeated attention on `cook()` batching, action dispatch, deferred solvency tracking, and initialization/exchange-rate paths
- `cauldrons/PrivilegedCauldronV4.sol` / `cauldrons/PrivilegedCheckpointCauldronV4.sol` — touched as related variants of the core cauldron flow, but not yet a source of distinct retained issues
- `FlawVerifier.sol` — reviewed peripherally; not central to the durable issue set so far
- clone initialization and oracle/exchange-rate setup flows — recurring concern area tied to startup-state correctness and debt accounting

## Issue Directions Seen
- Batch-execution risk in `cook()`: unhandled or unsupported action codes can disturb `CookStatus` and defeat deferred solvency enforcement after risky state changes
- Root-cause pattern around borrow / collateral-removal sequencing: solvency-sensitive operations remain dangerous when later batch steps can neutralize pending checks
- Initialization/oracle fragility: failed oracle reads during clone setup can leave a cached zero exchange rate, distorting debt perception until refreshed
- Action-dispatch edge cases, especially `_additionalCookAction()` and status-reset behavior, remain the most promising control-flow surface

## Useful Context
- The audit has concentrated heavily on one contract, `cauldrons/CauldronV4.sol`, with `cook()` as the dominant cross-round focal point
- Collateral-removal abuse and borrow abuse currently collapse into the same broader solvency-bypass mechanism rather than separate independent patterns
- Privileged cauldron variants and `FlawVerifier.sol` have been seen but remain underexplored compared with the base cauldron execution path
- Durable themes so far are deferred-check invalidation and bad initialization state, rather than isolated arithmetic or access-control bugs
