# Global Audit Memory

## Scope Touched
- `AlkemiEarn.sol` — concentrated attention on the `supply` → `borrow` → `liquidateBorrow` → `withdraw` path, with `getBorrowBalance` relevant to liquidation/accounting state
- Same-market `aweth` debt/collateral flow — core issue direction is liquidation and post-liquidation withdrawal using the same market asset

## Issue Directions Seen
- Same-market liquidation against the borrower’s own collateral remains the main vulnerability direction
- Immediate post-position liquidation viability is a recurring signal of shortfall/accounting inconsistencies
- Borrower self-liquidation within the same transaction is the strongest manifestation seen so far, especially when followed by withdrawal
- The durable concern is merged liquidation/accounting over-crediting rather than treating “no real shortfall” and “self-liquidation incentive capture” as separate issues

## Useful Context
- Audit attention has so far been narrowly focused on `AlkemiEarn.sol`, especially the liquidation path around lines `68-74`
- No other Solidity files have yet contributed durable cross-round context
- The retained cross-round pattern is that a freshly opened `aweth` position may be self-liquidated in the same market and then withdrawn, implying collateral or balance accounting can become overstated and expose pool funds
