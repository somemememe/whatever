# Global Audit Memory

## Scope Touched
- `MetaSwapUtils.sol` in both deployments: dominant focus across rounds; MetaSwap pricing, cached `baseVirtualPrice`, `swapUnderlying()` accounting, and old-vs-new base-LP handling are the main issue-bearing surfaces
- `SwapUtils.sol` in both deployments: recurring attention on pool balance accounting, admin-fee accrual, and raw token-balance drift being interpreted as withdrawable fees
- Older deployment `0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17`: risk appears more concentrated here, especially around legacy MetaSwap accounting and one-token/base-LP pricing paths
- `Swap.sol`, `MetaSwap.sol`, `AmplificationUtils.sol`, `LPToken.sol`: reviewed mainly for admin controls, initialization, fee/A changes, approvals, and withdrawal mechanics, but not central to retained issues so far

## Issue Directions Seen
- MetaSwap accounting mismatches remain the strongest theme: `swapUnderlying()` crediting, base-LP valuation, one-token withdrawal math, and differences between legacy and newer MetaSwap flows
- Stale or cached base-pool virtual price is the clearest cross-deployment recurring direction
- Admin-fee logic is a repeated concern, especially where fee accrual depends on raw balance drift rather than explicit swap-generated fee accounting
- Legacy implementation appears more exposed to phantom value creation or mispricing than the newer variant
- Admin setters, initialization, approvals, and reentrancy were investigated as secondary directions, but have not produced durable retained issues

## Useful Context
- Cross-agent overlap is strongest on `MetaSwapUtils.sol` and `SwapUtils.sol`; these are the core contracts for accumulated audit context
- The retained issue set is accounting-heavy rather than access-control-heavy
- The most durable pattern is that externally observable token balances and cached pricing inputs can diverge from intended internal accounting assumptions
- Attention has distinguished shared concerns affecting both deployments from sharper legacy-only risk in the older `0x88cc4a...` codebase
