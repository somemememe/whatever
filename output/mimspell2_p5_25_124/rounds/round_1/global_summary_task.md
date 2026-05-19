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
- files touched: `src/cauldrons/CauldronV4.sol`; targeted searches also included `lib/BoringSolidity/contracts/ERC20.sol`
- files revisited / highest-attention files: `src/cauldrons/CauldronV4.sol` dominated attention, with repeated line-level review around oracle updates, `cook`, strategy release, fee paths, and interest-rate changes
- main issue directions investigated: oracle initialization and stale-price caching; solvency/liquidation behavior under oracle failure; `cook` exchange-rate bounds; permissionless strategy release via `cook`; interest accrual semantics when changing rates
- promising but not retained directions: fee withdrawal / fee recipient handling, `reduceSupply`, blacklist/callee controls, and other balance/accounting paths were explicitly searched but not retained in merged findings

## Agent: opencode_1
- files touched: all 14 in-scope Solidity files were read, including `src/cauldrons/CauldronV4.sol`, all listed interfaces, and the BoringSolidity support contracts/libraries
- files revisited / highest-attention files: `src/cauldrons/CauldronV4.sol` was the clear focus; other files appear to have been scanned once for context
- main issue directions investigated: liquidation flow and swapper handling; `repayForAll`; `reduceSupply`; oracle-price usage; reentrancy; fee/admin controls; approval/configuration risks
- promising but not retained directions: several CauldronV4 hypotheses around liquidation, repayment, access control, reentrancy, fee redirection, unlimited approval, and zero-interest configuration were proposed but not retained after merge; the stale-oracle direction overlapped with a retained finding

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `src/cauldrons/CauldronV4.sol`, especially oracle/exchange-rate handling and its effect on solvency and liquidation
- notable differences in attention: `codex_1` went deeper on oracle-cache behavior, `cook` bounds, strategy release, and interest accrual timing; `opencode_1` spread attention across liquidation, repayment, access control, reentrancy, and support files
- underexplored but suspicious files/functions if clearly supported by the logs: non-Cauldron support files were read but saw limited follow-up; within `CauldronV4.sol`, functions such as `liquidate`, `repayForAll`, `withdrawFees`, and `reduceSupply` drew attention from at least one agent but did not produce retained findings this round

## Retained Findings
- Retained issues centered on `CauldronV4.sol` oracle and accounting logic: invalid oracle data can poison the initial exchange-rate cache, oracle failures can freeze critical checks on stale prices, and the `cook` max-rate guard is inverted
- Additional retained results were a permissionless collateral-strategy release path in `cook` under certain BentoBox-owner setups, and retroactive debt repricing when interest is changed without first accruing


Output only markdown.
