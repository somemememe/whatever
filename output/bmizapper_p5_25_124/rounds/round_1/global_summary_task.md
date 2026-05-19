You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
No global memory yet.

## Latest Round Summary
# Round 1 Summary

## Agent: codex_1
- files touched: `0x4622aff8e521a444c9301da0efd05f6b482221b8/Contract.sol` (parsed into `BMIZapper.sol`; also observed bundled libs/interfaces)
- files revisited / highest-attention files: `BMIZapper.sol`, especially `zapToBMI`, derivative unwrap branches, mint/refund helpers, and final settlement paths
- main issue directions investigated: whole-contract balance accounting via `balanceOf(address(this))`; unbounded Yearn/Aave unwinds via `withdraw()` / `type(uint256).max`; full-balance BMI/USDC settlement to caller; zero-min Curve swap/liquidity legs; dust-refund handling for supported constituents
- promising but not retained directions: low-level aggregator call path (`.call(_aggregatorData)`) and owner recovery-style full-balance transfers were surfaced during grep but not retained as separate findings in the merged set

## Agent: opencode_1
- files touched: `0x4622aff8e521a444c9301da0efd05f6b482221b8/Contract.sol`
- files revisited / highest-attention files: bundled `ABDKMath64x64.sol` content inside `Contract.sol`
- main issue directions investigated: fixed-point math edge cases in `fromInt`, `fromUInt`, `avg`, `gavg`, `mul`; compiler-version age
- promising but not retained directions: asserted arithmetic-overflow issues in the ABDK math library and a generic outdated-compiler concern, but none were retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents worked from the single scoped file `Contract.sol`
- notable differences in attention: `codex_1` extracted and analyzed `BMIZapper.sol` application logic and token-flow accounting; `opencode_1` stayed on bundled `ABDKMath64x64.sol` math-library code
- underexplored but suspicious files/functions if clearly supported by the logs: `BMIZapper.sol` low-level aggregator execution path around `.call(_aggregatorData)` was explicitly surfaced in log searches but not retained; owner/full-balance recovery helpers were also surfaced but not retained separately

## Retained Findings
- `BMIZapper.sol` has a dominant whole-balance accounting flaw: multiple zap, unwind, mint, and refund paths use the contract’s full token balances or full derivative positions instead of per-call deltas, enabling later callers to capture residual assets
- final settlement similarly transfers the contract’s entire BMI and, with `refundDust`, entire USDC balance to the current caller
- Curve interactions consistently use zero minimum outputs, leaving intermediate legs exposed to adverse execution/slippage manipulation
- `refundDust` misses supported `ySUSD` dust, leaving residual value stranded on the zapper and exposed to recovery or later balance-sweeping issues


Output only markdown.
