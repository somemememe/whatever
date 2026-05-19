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
- files touched: `LeverageSIR.sol`
- files revisited / highest-attention files: `LeverageSIR.sol`, especially the exploit path around `initialize`, `mint`, CREATE2 deployment, and `uniswapV3SwapCallback`
- main issue directions investigated: attacker-controlled vault initialization via fabricated Uniswap market; privileged transient-state poisoning from token return data during `mint`; forged/crafted `uniswapV3SwapCallback` flows draining vault-held assets
- promising but not retained directions: a separate callback-settlement-token issue was explored, but it was not retained independently after merge because it overlaps with the broader callback-drain path

## Cross-Agent Status
- main overlap in file/area attention: only one agent participated; attention was concentrated on `LeverageSIR.sol` and the core exploit chain
- notable differences in attention: none within this round because there was only one agent
- underexplored but suspicious files/functions if clearly supported by the logs: no separate underexplored file surfaced; current attention stayed centered on `LeverageSIR.sol`’s `initialize`, `mint`, and `uniswapV3SwapCallback` path

## Retained Findings
- retained critical issues center on three linked primitives: permissionless initialization of a funded vault with attacker-chosen market parameters, reuse of untrusted token return data as privileged transient callback state, and a callback path that can then be driven with crafted data to drain arbitrary vault-held tokens


Output only markdown.
