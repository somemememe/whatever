# Global Audit Memory

## Scope Touched
- `Contract.sol` — primary focus across the audit so far; exploit path centers on Balancer/Aave/Sturdy interaction during collateral withdrawal and liquidation-adjacent sequencing
- `interface.sol` — reference context for external integrations and local helper/library behavior; sampled rather than deeply audited
- Balancer `exitPool` flow / `receive()` path — important because transient state during exit appears observable and influences downstream accounting
- Aave/Sturdy collateral-management path around `setUserUseReserveAsCollateral` and related withdrawal checks — relevant where solvency decisions depend on in-flight collateral valuation

## Issue Directions Seen
- Read-only reentrancy during Balancer exit causing transient LP overvaluation that is consumed by collateral checks
- Mispricing of `B_STETH_STABLE` / `cB_stETH_STABLE` during `receive()` or other mid-exit states, especially when used as collateral value inputs
- Collateral-disable and withdrawal sequencing issues where temporary valuation inflation can permit removal of real collateral before debt is fully reflected
- Liquidation / withdrawal ordering as a source of bad-debt creation when external protocol state is sampled mid-transition

## Useful Context
- Early exploration included multiple framing variants, but the durable root theme is transient collateral overvaluation during Balancer exit rather than an isolated collateral-toggle bug
- Audit attention has been highly concentrated on `Contract.sol`; helper slices in `interface.sol` were inspected mainly to support integration reasoning
- The most stable cross-round observation is that lender-loss risk comes from downstream solvency logic trusting externally observable, temporarily inflated LP values during a read-only reentrant window
