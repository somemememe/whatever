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
- files revisited / highest-attention files: `Contract.sol` received the main line-by-line review, especially the `RubicProxy1` / `RubicProxy2` `routerCallNative` interface areas and the exploit setup in `ContractTest`; `interface.sol` was used mainly as supporting interface context
- main issue directions investigated: caller-controlled `router` and raw calldata in `routerCallNative`; whether the proxy can be abused as an ERC20 spender against prior allowances; treatment of caller-supplied `integrator`; zero-input / zero-recipient native-call behavior as an arbitrary-call primitive
- promising but not retained directions: integrator impersonation via calldata-supplied `integrator`; zero-input native-call misuse as a generic arbitrary-call gadget

## Cross-Agent Status
- main overlap in file/area attention: only one agent contributed this round, so attention was concentrated on `Contract.sol` and the `routerCallNative` path
- notable differences in attention: no cross-agent differences are available this round
- underexplored but suspicious files/functions if clearly supported by the logs: `interface.sol` was inspected but not a primary implementation focus; `routerCallNative` across both proxy variants remained the dominant hotspot

## Retained Findings
- retained after merge: a critical issue where `routerCallNative` lets the caller choose both external target and calldata, enabling theft of ERC20 funds from any victim who previously approved the Rubic proxy, by making the proxy execute attacker-crafted `transferFrom` calls


Output only markdown.
