# Global Audit Memory

## Scope Touched
- `0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol`  
  Core focus across liquidation/redemption behavior, collateral adjustment/accounting, and debt-index / fee-minting paths; secondary attention on `managePosition`, permit, flash-loan callback, oracle, and admin setter surfaces.

## Issue Directions Seen
- Liquidation design around the final position is a persistent concern when redemption is disabled, suggesting potential stuck bad debt at market edges.
- Collateral accounting versus actual token receipt is a durable direction, especially for non-standard or fee-on-transfer style collateral.
- Interest index and fee accrual interactions remain a central theme, including risk of overcharging / overminting against already-indexed debt.
- Recursive coupling between index updates, fee minting, and the manager’s own market is a recurring control-flow concern with possible liveness impact.
- Broader but less-developed directions include `managePosition` reentrancy, permit handling, flash-loan callback safety, oracle dependence, and admin-controlled configuration.

## Useful Context
- Audit attention so far is concentrated almost entirely in `InterestRatePositionManager.f.sol`; surrounding helper surfaces appear less deeply exercised.
- The strongest repeated patterns are accounting correctness and liveness, not generic access control.
- Concrete retained concerns cluster around liquidation edge cases, token accounting assumptions, and self-referential debt/fee machinery.
- `managePosition` and external-integration surfaces were flagged repeatedly but remain comparatively underexplored versus liquidation and fee logic.
