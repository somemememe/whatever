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
- files touched: `Contract.sol`, `interface.sol`
- files revisited / highest-attention files: `Contract.sol` was the clear focus; `interface.sol` was sampled mainly for integration context and brief local library review
- main issue directions investigated: Balancer exit-flow reentrancy, transient `B_STETH_STABLE` / `cB_stETH_STABLE` pricing during `receive()`, solvency/collateral checks around `setUserUseReserveAsCollateral`, and the withdrawal/liquidation sequence in the exploit harness
- promising but not retained directions: a separate “collateral-disable / real-collateral withdrawal bypass” issue was initially drafted, but the merged retained result kept the broader root cause centered on transient LP overvaluation during read-only reentrancy

## Cross-Agent Status
- main overlap in file/area attention: only one agent participated; attention was concentrated on `Contract.sol`’s exploit path and Balancer/Aave/Sturdy interactions
- notable differences in attention: no cross-agent differences in this round
- underexplored but suspicious files/functions if clearly supported by the logs: `interface.sol` was largely treated as reference-only context; local slices such as `TransferHelper` and `FixedPointMathLib` were briefly inspected but not developed into retained issues

## Retained Findings
- one retained critical finding: read-only reentrancy during `Balancer.exitPool` creates a transiently inflated Balancer LP collateral valuation, which is then used to pass collateral-management checks and remove real collateral, leading to bad debt / lender loss


Output only markdown.
