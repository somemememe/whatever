# Global Audit Memory

## Scope Touched
- `LayerZero/CrossChainRouter.sol` - persistent hotspot; cross-chain repay/liquidation handlers, message ordering/processability, packet validation, `_send` fee/refund behavior, and eid/domain binding checks.
- `LayerZero/CoreRouter.sol` - execution ordering around borrow/redeem/liquidation and router↔storage state-transition coherence under accrual timing sensitivity.
- `LayerZero/LendStorage.sol` - borrow-index/principal/debt coherence plus reward/distribution math, withdrawability paths, and division/index edge cases.
- `LayerZero/interaces/*.sol` (`LendInterface.sol`, `LendtrollerInterfaceV2.sol`, related interface wiring) - repeatedly used for schema/assumption validation; still mostly contextual rather than deep logic analysis.
- `Lendtroller.sol` - remains secondary/contextual for collateral-liquidation assumption alignment.

## Issue Directions Seen
- Cross-chain accounting/state drift and ordering hazards (especially DestRepay lifecycle coherence).
- Liquidation consistency risks: mapping correctness, packet validity, source/destination eid or domain mismatches.
- Stale accrual/state-freshness effects on liquidity/risk checks and close-factor realism.
- Repay/liquidation sequencing and transfer-path failure handling (including reentrancy-style ordering concerns).
- Reward/index math hazards: mixed-index accounting, zero-index/division edge cases, accrual-distribution-withdrawal consistency.
- Payable/native fee handling and refund custody correctness in router send/borrow flows.

## Useful Context
- Round 15 again converged on the same core trio (`CrossChainRouter`, `CoreRouter`, `LendStorage`), with strongest overlap on cross-chain liquidation/repay plus reward/index accounting.
- Candidate directions `F-048+` were explored by both agents but not retained after merge; this indicates unresolved ambiguity, not demonstrated safety.
- Cross-agent split was complementary: one side emphasized packet ordering + fee/refund flow, the other reward-withdrawability + transfer robustness.
- `LayerZero/interaces` path typo continues to appear in traces and can still skew search/navigation coverage.
