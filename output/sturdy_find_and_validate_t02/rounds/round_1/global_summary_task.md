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
- files touched: `Contract.sol`, `FlawVerifier.sol`, `interface.sol`
- files revisited / highest-attention files: `FlawVerifier.sol` and `Contract.sol` were repeatedly reopened around the exploit path and callback sequence; `interface.sol` was searched for oracle/lending/Balancer-related signatures
- main issue directions investigated: Balancer `exitPool` callback timing around `STURDY_ORACLE.getAssetPrice`, transient LP pricing during reentrancy, and collateral health-check dependence when disabling and later withdrawing `STECRV`
- promising but not retained directions: broader tracing into `interface.sol` for oracle, vault, and lending definitions; these supported context-mapping but did not become separate retained findings in this round

## Cross-Agent Status
- main overlap in file/area attention: single-agent round; attention concentrated on the `Contract.sol` / `FlawVerifier.sol` exploit reproduction path and the Balancer-oracle-lending interaction
- notable differences in attention: no cross-agent differences are visible because only `codex` appears in this round
- underexplored but suspicious files/functions if clearly supported by the logs: `interface.sol` was only used as an interface/signature map for `getAssetPrice`, `setUserUseReserveAsCollateral`, `borrow`, `withdrawCollateral`, and Balancer-related calls; no deeper implementation review is visible in the logs

## Retained Findings
- Retained that the B-stETH-STABLE collateral price can be transiently inflated during Balancer `exitPool` reentrancy, making oracle-based collateral valuation flash-manipulable inside one transaction
- Retained that this temporary price inflation can be used to disable collateral usage for `STECRV`, then withdraw it after normalization, leaving the position undercollateralized and creating bad debt risk


Output only markdown.
