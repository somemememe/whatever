# Global Audit Memory

## Scope Touched
- `0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol`:
  dominant audit focus; issues cluster around staking/accounting, `targetedPurchase`, Rugged transfer assumptions, and incentive lifecycle/gas behavior
- `targetedPurchase` flow:
  repeatedly examined for pooled-NFT sale semantics, swap/refund handling, and reentrancy-adjacent execution risk
- staking / unstaking / incentive accrual flows:
  repeatedly matter due to NFT custody identity loss, incentive array growth, and zero-stake-period accounting edge cases
- Rugged token transfer paths:
  attention centered on balance/accounting trusting transfer intent without confirming actual asset movement
- `lib/universal-router/.../IUniversalRouter.sol`:
  minor supporting review for router/interface correctness around swap execution

## Issue Directions Seen
- Shared NFT pool design in `Market.sol` appears to erase depositor-specific NFT identity, enabling fixed-price buyout from pooled inventory rather than preserving per-staker custody expectations
- Asset accounting often trusts internal assumptions over verified token movement, especially for Rugged transfers and swap/refund outcomes
- Incentive mechanics show recurring operational-risk themes: unbounded growth, gas-sensitive iteration, and accrual edge cases when no stake exists
- Purchase flow risk direction is less about classic reentrancy and more about execution/accounting mismatches around swaps, refunds, and inventory handling
- Several hypotheses around proxy initialization, duplicate staking, stake validation inversion, and simple missing `nonReentrant` patterns were explored but not durable so far

## Useful Context
- Cross-round attention is highly concentrated on `Market.sol`; broader dependencies and upgradeable support code remain comparatively underexplored
- The strongest retained themes are structural accounting/custody mismatches rather than isolated input-validation bugs
- Refund/loss behavior and stranded-value states recur as a pattern across both purchase and incentive flows
- Multiple agents independently converged on transfer/accounting assumptions and `targetedPurchase` behavior as the most suspicious areas
