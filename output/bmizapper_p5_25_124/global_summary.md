# Global Audit Memory

## Scope Touched
- `0x4622aff8e521a444c9301da0efd05f6b482221b8/Contract.sol` (`BMIZapper.sol` logic bundled here): primary audit surface; attention centered on `zapToBMI`, derivative unwrap/mint helpers, refund logic, and final settlement, with repeated concern around contract-wide balance usage instead of per-call accounting
- `BMIZapper.sol` Curve swap/liquidity legs: recurring slippage/adverse-execution direction due to zero minimums on external pool interactions
- `BMIZapper.sol` low-level aggregator execution path (`.call(_aggregatorData)`): surfaced as suspicious but not retained; remains an underexplored integration edge
- bundled `ABDKMath64x64.sol`: reviewed for arithmetic edge cases, but not a retained issue direction so far

## Issue Directions Seen
- Whole-contract balance accounting is the dominant pattern: zap, unwind, mint, refund, and settlement paths appear to sweep current contract balances or full positions rather than caller-specific deltas
- Final settlement/refund behavior compounds the above by transferring entire `BMI` and sometimes entire `USDC` balances to the active caller
- Derivative unwind paths use unbounded/full-position exits (`withdraw()` / `type(uint256).max` style behavior), fitting the same balance-scope weakness
- Curve interactions repeatedly accept zero minimum outputs, leaving swap/liquidity legs exposed to slippage or execution manipulation
- Dust/refund coverage is incomplete for supported assets, creating stranded residual balances that feed later sweep/capture issues

## Useful Context
- The audit has concentrated almost entirely on a single bundled source file, with application-level token-flow/accounting issues proving more durable than library-level math concerns
- Cross-round signal is strongest where residual asset accumulation and later-caller capture interact across functions rather than within any single call path
- `ySUSD` dust was specifically noted as missed by `refundDust`, reinforcing the broader residual-balance theme
- Aggregator-call and owner/recovery-style full-balance paths were surfaced during exploration but were not retained separately; they remain secondary context rather than established directions
