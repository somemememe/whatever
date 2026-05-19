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

## Agent: codex
- files touched: `Contract.sol` (used as the container for embedded Solidity sources), with findings reported against `Staking.sol`; also inspected embedded interfaces `CTokenInterface.sol` and `IERC20.sol`
- files revisited / highest-attention files: `Staking.sol` was the clear focus, especially deposit/withdraw/emergency-withdraw flows, epoch accounting, and Compound integration points
- main issue directions investigated: unchecked ERC20 transfer return values; deposit accounting based on requested rather than received amounts; stale epoch snapshots after `emergencyWithdraw`; global emergency-exit timer griefing; dormant-pool epoch initialization DoS; ignored Compound error codes
- promising but not retained directions: broader reward/governance abuse was explored through stale snapshot logic, but the retained result stayed centered on `emergencyWithdraw` leaving epoch state untouched

## Cross-Agent Status
- main overlap in file/area attention: `Staking.sol` emergency-withdraw / epoch-snapshot behavior had confirmed overlap, with retained finding `F-003` attributed to both `codex` and `merge-review`
- notable differences in attention: visible logs show `codex` also covered ERC20 transfer semantics, fee-on-transfer accounting, epoch initialization liveness, and Compound return-code handling; no comparable per-file attention detail is visible for `merge-review`
- underexplored but suspicious files/functions if clearly supported by the logs: `getEpochUserBalance`, `getEpochPoolSize`, `manualEpochInit`, and Compound interaction helpers remained central risk surfaces based on the retained findings and codex review path

## Retained Findings
- six findings were retained from this round, centered on `Staking.sol`
- high-severity retained issues: phantom deposits from unchecked ERC20 returns, over-crediting deposits that receive less than `amount`, and stale epoch stake persisting after `emergencyWithdraw`
- medium-severity retained issues: pool-wide griefing of the emergency timer, dormant-pool lockups from one-by-one epoch backfilling, and ignored Compound error codes desynchronizing stablecoin liquidity/accounting


Output only markdown.
