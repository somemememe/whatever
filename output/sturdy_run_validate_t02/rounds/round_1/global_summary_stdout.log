# Global Audit Memory

## Scope Touched
- `Contract.sol` — core exploit path attention around Balancer `exitPool`, `receive()` callback timing, collateral-state transitions, health checks, and withdrawal/liquidation sequencing
- `FlawVerifier.sol` — used to validate the same transient-collateral / bad-debt path and confirm exploitability assumptions
- `interface.sol` — mainly referenced for `ILendingPool` and other external integration surfaces; relevant as supporting context, not a primary logic hotspot
- Flow: Balancer LP exit callback → transient oracle-based LP valuation → health-factor check while collateral state mutates → collateral disable / withdrawal path that can strand bad debt

## Issue Directions Seen
- Transient overvaluation of Balancer LP collateral during `exitPool` callback windows
- Read-only reentrancy / callback-time state observation around `receive()` affecting oracle reads or health checks
- Oracle price reads (`SturdyOracle.getAssetPrice`) being consumed during manipulable intermediate states rather than settled balances
- Temporary health-factor inflation being turned into a lasting collateral-disable state, then used to withdraw genuinely necessary collateral and leave protocol bad debt
- Liquidation-path interactions appeared adjacent to the exploit flow, but self-liquidation was not retained as an independent direction

## Useful Context
- Audit attention is concentrated on cross-contract sequencing rather than isolated arithmetic bugs
- The durable pattern is a mismatch between transient external-pool state and internal lending-pool collateral accounting
- External interface review has so far been lightweight; most signal comes from how integrations are used in `Contract.sol` rather than from interface definitions themselves
- The main retained theme is not just temporary mispricing, but conversion of that temporary condition into permanent protocol loss state
