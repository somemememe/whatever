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
- files touched: `Contract.sol`, `FlawVerifier.sol`, `interface.sol`
- files revisited / highest-attention files: `Contract.sol` and `FlawVerifier.sol`; `interface.sol` was only lightly scanned for contract definitions
- main issue directions investigated: Balancer `exitPool()` callback behavior, transient oracle pricing via `getAssetPrice`, collateral disabling via `setUserUseReserveAsCollateral`, post-disable collateral withdrawal, flash-loan callback authorization, zero-slippage unwind paths, and one-shot execution griefing in `executeOnOpportunity()`
- promising but not retained directions: incomplete flash-loan callback authorization and MEV/slippage exposure on large Balancer/Curve exits

## Agent: opencode_1
- files touched: `Contract.sol`, `FlawVerifier.sol`, `interface.sol`
- files revisited / highest-attention files: `Contract.sol` and `FlawVerifier.sol`, especially around `setUserUseReserveAsCollateral`, `getAssetPrice`, `borrow`, and liquidation-related flow; `interface.sol` was read only partially
- main issue directions investigated: read-only reentrancy during Balancer exit, oracle price inflation during callback, disabling collateral inside the manipulated window, and the follow-on withdrawal/liquidation flow
- promising but not retained directions: generic “unprotected callback” framing on the helper contract, lack of oracle deviation validation, and missing reentrancy guard on exit-pool operations

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on the `Contract.sol` / `FlawVerifier.sol` Balancer-exit callback path, especially `getAssetPrice`, `setUserUseReserveAsCollateral`, and the collateral withdrawal sequence
- notable differences in attention: `codex_1` branched into verifier operational risks like `executeOnOpportunity()` griefing, flash-loan callback authorization, and slippage/MEV paths; `opencode_1` stayed tightly focused on the oracle-manipulation/reentrancy cluster
- underexplored but suspicious files/functions if clearly supported by the logs: `interface.sol` remained largely unexamined by both agents; callback/auth paths such as `executeOperation()` and related unwind code in `FlawVerifier.sol` received narrower attention overall

## Retained Findings
- Retained after merge were the Balancer exit read-only reentrancy issue that temporarily inflates LP collateral valuation, the resulting ability to disable needed collateral during that window and later withdraw it without a fresh solvency check, and a separate verifier-level DoS where anyone can consume the single allowed `executeOnOpportunity()` attempt.


Output only markdown.
