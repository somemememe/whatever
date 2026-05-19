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
- files touched: `FlawVerifier.sol`, `interface.sol`
- files revisited / highest-attention files: `FlawVerifier.sol` received the deepest line-by-line review; `interface.sol` was repeatedly scanned for non-interface/code-bearing blocks and specific helper libraries
- main issue directions investigated: public exploit flow in `FlawVerifier.sol` around `routerCallNative`, victim ranking, and `transferFrom` calldata construction; reusable risk surfaces in `interface.sol` such as transfer helpers, approve wrappers, ETH send helpers, unsafe math helpers, and clone deployment helpers
- promising but not retained directions: `interface.sol` helper-library concerns were surfaced around non-contract token calls, allowance-race approvals, gas-forwarding ETH sends, divide-by-zero-tolerant math, and clone implementation validation, but these did not survive merge as retained findings for this round

## Cross-Agent Status
- main overlap in file/area attention: only one agent participated, with strongest focus on `FlawVerifier.sol` and the `routerCallNative` abuse path
- notable differences in attention: no cross-agent divergence this round
- underexplored but suspicious files/functions if clearly supported by the logs: `interface.sol` contains multiple code-bearing helper sections that were scanned as potential footguns, but no merged finding from those areas was retained this round

## Retained Findings
- retained finding centers on the Rubic proxy abuse demonstrated through `routerCallNative`: attacker-controlled `router` and calldata let the proxy act as an approved spender and drain victims who still have live token allowances to the proxy


Output only markdown.
