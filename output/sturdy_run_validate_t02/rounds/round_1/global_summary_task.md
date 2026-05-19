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
- files revisited / highest-attention files: highest attention on `Contract.sol` and `FlawVerifier.sol`; `interface.sol` was used mainly to inspect `ILendingPool` and related external interfaces
- main issue directions investigated: Balancer `exitPool` callback behavior, read-only reentrancy around `receive()`, transient LP price reads via `SturdyOracle.getAssetPrice`, collateral-state changes during manipulated health checks, and downstream collateral withdrawal / liquidation flow
- promising but not retained directions: a self-liquidation angle (`liquidationCall` with `user == address(this)`) was proposed as a separate profit-amplifying issue, but it was not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: only one agent participated; attention concentrated on the exploit path spanning Balancer exit, oracle reads, collateral toggling, and withdrawal flow in `Contract.sol` / `FlawVerifier.sol`
- notable differences in attention: no cross-agent differences this round
- underexplored but suspicious files/functions if clearly supported by the logs: `interface.sol` received limited attention beyond external interface lookup; within the traced flow, `liquidationCall` appeared in a non-retained line of inquiry

## Retained Findings
- retained findings center on transient overvaluation of Balancer LP collateral during the `exitPool` callback and the ability to convert that temporary health-factor inflation into a permanent collateral-disable state, enabling withdrawal of genuinely needed collateral and leaving bad debt


Output only markdown.
