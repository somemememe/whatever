# Global Audit Memory

## Scope Touched
- `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol` — central state machine; repeated focus on accrual, exchange-rate math, and cash/accounting assumptions
- `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20.sol` — transfer wrapper and underlying integration; strongest issue direction is mutable/live-balance token behavior
- `0x12392f67bdf24fae0af363c24ac620a2f67dad86/contracts/CErc20Delegator.sol` — delegatecall and upgrade/admin surface reviewed repeatedly, but no durable issue retained yet
- `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20Delegate.sol` and interface files under both trees — touched as supporting context, with comparatively lighter direct scrutiny

## Issue Directions Seen
- Dependence on raw underlying balance and balance-delta accounting as a recurring vulnerability theme
- Exchange-rate and cash calculations are sensitive to unsolicited balance changes, fee/rebase-style behavior, and negative balance drift
- Core mint/redeem/borrow/repay/liquidation flows inherit risk from transfer semantics of the underlying token
- Upgrade/admin/control-surface directions were examined often, but so far remain weaker than the accounting/underlying-behavior cluster
- Omitted Comptroller verify-hook and generic reentrancy/rounding concerns have appeared repeatedly but have not held up

## Useful Context
- Cross-round attention is concentrated on Compound-style `CToken`/`CErc20` logic rather than peripheral modules
- Retained findings consistently point to assumptions that the underlying token is passive, balance-stable, and freely transferable
- Durable risk picture is less about privileged abuse and more about protocol fragility when underlying token behavior departs from vanilla ERC-20 expectations
- Delegator/implementation paths are notable review surface area, but current signal is mainly contextual rather than finding-backed
