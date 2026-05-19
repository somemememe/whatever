# Global Audit Memory

## Scope Touched
- `CToken.sol` in both contract trees: core hotspot for `borrow`/`redeem` state-transition ordering, exchange-rate edge cases, underlying transfer semantics, and broader admin/config surface review
- `CErc20.sol`: ERC20 wrapper path tied to outbound transfer/accounting behavior with non-standard or fee-on-transfer underlyings
- `CErc20Delegator.sol`: proxy/deployment layer with persistent attention on admin initialization and constructor authority assignment
- `CErc20Delegate.sol`: delegate-side initialization and admin/config setter behavior, especially initial exchange-rate and upgrade-time safety
- shared math/error support (`FixedPointMathLib.sol`, `ErrorReporter.sol`): checked as supporting context, not a primary source of retained issues

## Issue Directions Seen
- Reentrancy exposure around `borrowFresh()` / `redeemFresh()` from transfer-out happening before debt or collateral state is finalized
- Zero-supply exchange-rate reset behavior creating value-capture opportunities around stranded underlying or post-empty-market repayments
- Outbound transfer/accounting mismatch when underlyings are deflationary, fee-on-transfer, or otherwise non-standard ERC20s
- Proxy/admin initialization remains a recurring control-plane direction, especially where final authority depends on deployment context
- Admin/config setter surfaces and liquidation/reserve parameters were repeatedly examined as suspicious control points, though not all paths produced retained issues

## Useful Context
- Attention consistently converged on the two `CToken.sol` copies plus the ERC20 wrapper/delegator layer, suggesting the main risk concentration is in core token lifecycle and proxy wiring rather than support libraries
- Cross-agent review split naturally between state-transition/transfer semantics and admin/config correctness; together this points to both asset-flow and authority-flow bugs as the dominant audit themes
- Broad review of accrual, liquidation, reserve, and math behavior produced more candidate concerns than retained issues, so these areas are better treated as secondary follow-up directions than primary confirmed risk clusters
