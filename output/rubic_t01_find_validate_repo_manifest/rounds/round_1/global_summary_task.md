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
- files touched: `contracts/RubicProxy.sol`, `rubic-bridge-base/contracts/BridgeBase.sol`, `rubic-bridge-base/contracts/libraries/SmartApprove.sol`, `rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol`, `rubic-bridge-base/contracts/errors/Errors.sol`, `rubic-bridge-base/contracts/libraries/FullMath.sol`; the scoped OpenZeppelin files were also enumerated during initial mapping
- files revisited / highest-attention files: `contracts/RubicProxy.sol`, `rubic-bridge-base/contracts/BridgeBase.sol`, and `rubic-bridge-base/contracts/libraries/SmartApprove.sol`
- main issue directions investigated: persistent ERC20 approvals granted to gateways, mismatch between executed router and approved spender within the shared allowlist, and unenforced per-token `minTokenAmount` / `maxTokenAmount` guardrails on bridge entrypoints
- promising but not retained directions: `transferAdmin(address(0))` potentially burning admin control, and route metadata in `BaseCrossChainParams` being emitted without validation against `_data`

## Cross-Agent Status
- main overlap in file/area attention: single-agent round; attention concentrated on `RubicProxy.routerCall`, router allowlisting, approval flow, and `BridgeBase` token-limit / admin state
- notable differences in attention: no cross-agent divergence in this round
- underexplored but suspicious files/functions if clearly supported by the logs: helper files such as `OnlySourceFunctionality.sol`, `Errors.sol`, and `FullMath.sol` were opened but did not receive comparable depth in the visible log

## Retained Findings
- Persistent max approvals to allowlisted gateways were retained as the main high-severity issue because they can outlive route execution and later expose proxy-held ERC20 balances
- The shared allowlist design was retained as a distinct issue because callers can approve an allowlisted spender unrelated to the router actually used
- Configured token min/max bounds were retained as dead-code-style protection gaps because the bridge entrypoints accept out-of-band amounts without enforcing the stored limits


Output only markdown.
