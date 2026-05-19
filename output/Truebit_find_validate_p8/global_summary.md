# Global Audit Memory

## Scope Touched
- `Truebit.sol` — sole in-scope contract across reviewed rounds; attention concentrates on the buy/sell quote path and reserve interaction
- `Truebit.sol` pricing hotspots — purchase and redemption math around the retained issue area (`~50`, `~134`, `~190`) repeatedly matter as the main exploit surface

## Issue Directions Seen
- Bonding-curve / quote-calculation flaws, especially integer-rounding behavior that can misprice large purchases
- Buy-then-redeem drain patterns where underpriced minting can be converted back into ETH from reserves
- General external/privileged flow review has occurred, but pricing logic remains the only durable high-signal direction so far

## Useful Context
- Audit activity to date is highly concentrated: one contract (`Truebit.sol`) and one dominant risk area (purchase/sale pricing logic)
- Cross-round memory should treat the quote path as the established hotspot, even when individual agent outputs do not consistently retain it
- No other durable suspicious modules or divergent investigation tracks have emerged yet
