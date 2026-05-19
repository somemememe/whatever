# Global Audit Memory

## Scope Touched
- `0xaf274e912243b19b882f02d731dacd7cd13072d0/Contract.sol` - core attention has concentrated on strategy deposit/withdraw flows, Curve/yPool interaction points, and share/value accounting
- `deposit()`, `_withdrawSome()`, `withdraw(uint)`, `withdrawAll()`, `withdrawUnderlying()` - recurring focus area for execution quality, realized unwind proceeds, and withdrawal amount consistency
- `balanceOf()` - recurring focus area for valuation/accounting mismatch between modeled `yyCRV` value and executable exit value
- `withdraw(IERC20 _asset)` - surfaced as a hotspot around controller-accessible arbitrary asset withdrawal/sweep behavior, but not yet retained as an issue

## Issue Directions Seen
- Zero-slippage Curve entry/exit execution as a recurring MEV and adverse-execution direction
- Withdrawal paths where requested amounts can diverge from realized proceeds during unwind
- Strategy accounting that values LP exposure by model/invariant assumptions rather than executable redemption value
- Privileged generic asset withdrawal/sweep paths as a secondary but still notable direction

## Useful Context
- Audit attention is concentrated in a single strategy contract, with most meaningful risk emerging from interaction between Curve liquidity operations and internal accounting
- Durable pattern so far: user-visible balances and withdrawal expectations may rely on optimistic valuation/execution assumptions
- Function-level review has been deeper on withdrawal and valuation paths than on broader auxiliary code, so edge behavior around privileged token recovery remains comparatively less explored
