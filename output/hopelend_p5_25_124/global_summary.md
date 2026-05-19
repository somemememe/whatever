# Global Audit Memory

## Scope Touched
- `Pool.sol`: central entrypoint repeatedly involved in cross-library state/accounting flows
- `FlashLoanLogic.sol`: flashloan callback/post-callback state consistency, debt opening, premium handling
- `BorrowLogic.sol`: debt accounting edge cases, especially isolation-mode / debt-ceiling interactions
- `ValidationLogic.sol`: validation-state drift versus later execution context, config-bound enforcement
- `BridgeLogic.sol`: `unbacked` mint / burn lifecycle and reserve removal interactions
- `PoolLogic.sol`: treasury/vault fee accounting and reserve-level bookkeeping
- `LiquidationLogic.sol`, `GenericLogic.sol`, `EModeLogic.sol`: reviewed as secondary hotspots around liquidation, health-factor, and mode-transition logic, but less validated so far
- proxy / upgradeability files (`InitializableUpgradeabilityProxy.sol`, `BaseImmutableAdminUpgradeabilityProxy.sol`): initialization / admin safety was checked, not yet a sustained issue track

## Issue Directions Seen
- State captured before externalized flashloan flow may be reused after callback in ways that desync with current user mode/config
- Isolation-mode accounting remains a strong direction, especially around rounding, sub-unit amounts, and debt-ceiling enforcement
- Bridge `unbacked` accounting and reserve lifecycle management look structurally fragile
- Fee accounting paths can diverge between bookkeeping/events and actual asset movement
- Configurable flashloan premium splits need bound validation to avoid repayment or distribution breakage
- Broader but so-far unretained directions include liquidation parameter bounds, eMode transition checks, oracle-sensitive paths, and admin/config initialization surfaces

## Useful Context
- Audit attention is concentrated on `Pool.sol` plus core borrow/flashloan/validation/bridge/accounting libraries rather than peripheral modules
- Durable retained findings to date are mostly accounting and state-consistency issues, not classic access-control bugs
- Cross-round pattern: many promising directions arise where validation, cached state, and later execution/accounting are separated across libraries
- Secondary logic modules (`LiquidationLogic.sol`, `GenericLogic.sol`, `EModeLogic.sol`) are touched enough to remain worth contextual awareness, but they have produced less durable signal than the main accounting paths
