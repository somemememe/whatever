# Global Audit Memory

## Scope Touched
- `contracts/DepToken.sol` - central hotspot across rounds; repay, redeem, borrow-ledger, and admin/pricer integration paths keep surfacing
- `contracts/DepositWithdraw.sol` - tightly coupled to redemption and liquidity-return behavior; under-delivery and external-call handling matter here
- `contracts/CurveSwap.sol` - recurring source of swap-safety concerns, especially approval exposure and slippage-free Curve interactions in borrow/repay/redeem flows
- Compound integration paths (`DepErc20` / mint / redeem flows) - repeated concern around unchecked return values, failed cash retrieval, and allowance state persisting across failures
- Interface/config surfaces (`*Interfaces.sol`, pricer/registry setters) - reviewed mainly as supporting context for integration and governance/configuration risk

## Issue Directions Seen
- External protocol interaction safety is the dominant theme: Compound mint/redeem failures and Curve swap behavior can leave internal accounting or flow assumptions invalid
- Redemption/cash-management paths are a repeated weakness area, especially when external liquidity retrieval fails, under-delivers, or is not enforced before user-side state changes finalize
- Curve swap protections remain a strong direction: zero-min-output usage and inherited/public approval capability both expose value-loss surfaces
- Return-value / error-handling gaps recur across integrations, including silent failure patterns that can leave stale approvals or broken later flows
- Admin/pricer/governance and borrow-ledger reentrancy/accounting were explored but remain secondary versus the stronger swap and liquidity-path issues

## Useful Context
- Cross-round attention has concentrated on the `DepToken` / `DepositWithdraw` / `CurveSwap` cluster rather than isolated leaf modules
- The most durable pattern is not generic math error but unsafe assumptions around live external integrations and post-call state progression
- Several weaker themes collapsed into a clearer shared direction: external calls that either fail silently or return less than expected can still let the protocol continue as if liquidity actions succeeded
- Pricing and config surfaces were looked at, but the stronger retained signal so far is in operational fund-flow paths rather than oracle-manipulation detail
