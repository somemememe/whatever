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
- files touched: `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol`, `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CErc20.sol`, `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CErc20Immutable.sol`, `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CarefulMath.sol`, `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/InterestRateModel.sol`, `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/ComptrollerInterface.sol`, plus regex pass across all scoped `.sol` files
- files revisited / highest-attention files: `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol` and `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CErc20.sol`
- main issue directions investigated: mint/redeem rounding behavior, exchange-rate derivation from raw cash balance, direct underlying donations inflating exchange rate, transfer/accounting behavior around `doTransferIn` / `doTransferOut`, and external policy-hook dependence via comptroller checks
- promising but not retained directions: standalone finding on donation-driven exchange-rate inflation and a lower-confidence concern about rebasing / flash-mintable underlyings affecting balance-delta accounting

## Agent: opencode_1
- files touched: `../../../output/inversefinance_p5_25_124/rounds/round_1/agent_opencode_1/current_task.md`; no in-scope Solidity file inspection is visible in the log
- files revisited / highest-attention files: none; attention stayed on path discovery and directory listing around `/Users/zhanglongqin/AuditHoundV2/cases/inversefinance/src` and `onchain_auto`
- main issue directions investigated: repository/path resolution only; attempted globbing for Solidity files under `src` and `src/onchain_auto`
- promising but not retained directions: none visible; the run did not progress to contract analysis

## Cross-Agent Status
- main overlap in file/area attention: both agents interacted with the `onchain_auto` scope and spent some effort resolving the actual contract path
- notable differences in attention: `codex_1` performed the substantive contract review centered on `CToken.sol` and `CErc20.sol`, while `opencode_1` did not reach Solidity inspection
- underexplored but suspicious files/functions if clearly supported by the logs: outside the mint/redeem/exchange-rate paths, `CErc20Immutable.sol`, `CTokenInterfaces.sol`, `InterestRateModel.sol`, and `Exponential*.sol` received little visible attention in this round

## Retained Findings
- retained findings focus on the same core state: exchange-rate inflation combined with missing nonzero-result checks in cToken share math
- one retained issue is zero-burn `redeemUnderlying`, where sub-threshold withdrawals can transfer underlying without reducing cToken balance
- the other retained issue is zero-mint `mint`, where sub-threshold deposits can be accepted while minting no cTokens, shifting value to incumbent holders


Output only markdown.
