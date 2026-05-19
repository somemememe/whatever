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
- files touched: `Counter.sol`, `FlawVerifier.sol`
- files revisited / highest-attention files: `FlawVerifier.sol` dominated review, with repeated line-level revisits around `executeOnOpportunity()` (`FlawVerifier.sol:110`), `isValidSignature()` / `resolveOrders()` (`FlawVerifier.sol:162-167`), `_prepareMakerCapital()` (`FlawVerifier.sol:221-235`), swap paths, and the forged settlement payload / terminal interaction builder (`FlawVerifier.sol:87-90`, `FlawVerifier.sol:401-439`)
- main issue directions investigated: forged settlement parsing via attacker-controlled offsets/lengths and historical trailer data; unconditional ERC1271 authorization combined with unlimited USDT approval; permissionless low-min-output swap execution; one-shot execution path griefing / permanent consumption
- promising but not retained directions: a separate “historical victim authorization replay” angle was explored but merged into the retained forged-settlement parsing issue; a low-confidence `resolveOrders()` no-op / weak resolver-validation direction was investigated but not retained

## Cross-Agent Status
- main overlap in file/area attention: only one agent participated; attention concentrated on `FlawVerifier.sol`, especially execution entrypoints, approval/auth logic, swap routines, and settlement-payload construction
- notable differences in attention: `Counter.sol` received only surface inspection, while nearly all substantive effort went to `FlawVerifier.sol`
- underexplored but suspicious files/functions if clearly supported by the logs: `resolveOrders()` and `Counter.sol` remained comparatively lightly explored; `resolveOrders()` was specifically flagged during investigation but did not survive merge as a retained finding

## Retained Findings
- retained issues center on four distinct themes in `FlawVerifier.sol`: forged interaction-offset settlement parsing that can redirect finalization into attacker-supplied historical context; universal ERC1271 approval plus standing USDT allowance enabling contract-held USDT drain; permissionless near-zero-min-output swaps exposing balances to sandwich extraction; and a public one-shot execution path that any caller can permanently consume/grief


Output only markdown.
