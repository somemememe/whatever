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
- files touched: `contracts/RubicProxy.sol`, `rubic-bridge-base/contracts/BridgeBase.sol`, `rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol`, `rubic-bridge-base/contracts/libraries/SmartApprove.sol`, `rubic-bridge-base/contracts/libraries/FullMath.sol`, `rubic-bridge-base/contracts/errors/Errors.sol`, `src/FlawVerifier.sol`
- files revisited / highest-attention files: `contracts/RubicProxy.sol`, `rubic-bridge-base/contracts/BridgeBase.sol`, `rubic-bridge-base/contracts/libraries/SmartApprove.sol`, `src/FlawVerifier.sol`
- main issue directions investigated: sticky max approvals to gateways and post-delist drainability; ERC20 amount accounting vs actual receipt for fee-on-transfer tokens; unenforced `minTokenAmount` / `maxTokenAmount`; caller-controlled integrator fee selection; native-route metadata mismatch in emitted params
- promising but not retained directions: native-route event/metadata mismatch around `routerCallNative` / `eventEmitter` was reported but not merged

## Agent: opencode_1
- files touched: `src/FlawVerifier.sol`, `rubic-bridge-base/contracts/BridgeBase.sol`, `contracts/RubicProxy.sol`, `rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol`, `rubic-bridge-base/contracts/libraries/SmartApprove.sol`, `rubic-bridge-base/contracts/errors/Errors.sol`
- files revisited / highest-attention files: no clear revisits shown in the log; highest attention was on `contracts/RubicProxy.sol`, `rubic-bridge-base/contracts/BridgeBase.sol`, `rubic-bridge-base/contracts/libraries/SmartApprove.sol`, `src/FlawVerifier.sol`
- main issue directions investigated: persistent unlimited approvals; router removal without approval cleanup; approval abuse framed through `FlawVerifier`; additional review of admin sweep and observability-style issues
- promising but not retained directions: separate approval-themed findings were collapsed during merge; `FlawVerifier` flash-loan framing, missing approval events, `sweepTokens`, and minor validation/comment issues were not retained

## Cross-Agent Status
- main overlap in file/area attention: both agents centered on `contracts/RubicProxy.sol`, `rubic-bridge-base/contracts/BridgeBase.sol`, and `rubic-bridge-base/contracts/libraries/SmartApprove.sol`, with strongest overlap on persistent approval risk from `routerCall`
- notable differences in attention: `codex_1` broadened into amount-accounting, route-limit enforcement, and integrator-fee trust issues; `opencode_1` stayed concentrated on approval persistence and auxiliary/admin-style concerns, using `src/FlawVerifier.sol` more as exploit framing
- underexplored but suspicious files/functions if clearly supported by the logs: `routerCallNative` / `OnlySourceFunctionality.eventEmitter` received limited follow-up after one low-confidence metadata issue; `sweepTokens` was looked at by one agent but did not survive merge

## Retained Findings
- sticky unlimited approvals to caller-chosen gateways remain live after routing and even after router delisting, creating a drain path for proxy-held tokens
- ERC20 routing uses nominal `srcInputAmount` rather than actual received balance, enabling fee-on-transfer tokens to consume existing proxy reserves
- configured per-token min/max route amounts are stored but not enforced by the public routing entrypoints
- fee selection trusts the user-supplied integrator address, allowing arbitrary users to reuse discounted integrator fee schedules


Output only markdown.
