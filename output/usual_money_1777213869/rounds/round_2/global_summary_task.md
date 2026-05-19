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
# Global Audit Memory

## Scope Touched
- `FlawVerifier.sol` — dominant focus; core risk surface is `executeOnOpportunity()` and its swap/liquidation/probing flow, with issue direction toward treasury custody, open execution, slippage-free swaps, and external-call side effects
- `FlawVerifier.sol` selector/probing helpers and approval paths — repeatedly treated as dangerous because broad approvals combine with blind low-level interaction against external targets
- `Counter.sol` — touched but still comparatively underexplored; only a weak direction around unrestricted state writes has surfaced so far

## Issue Directions Seen
- Treasury/value-flow can become trapped or misdirected, especially where balances accumulate without an evident recovery path
- Main strategy execution may be callable too broadly, exposing treasury operations to permissionless triggering
- Swap paths appear vulnerable to zero-or-weak minimum output handling, pointing to slippage/manipulation extraction risk
- Broad token approvals paired with blind probing/external calls remain a recurring direction for silent destructive side effects
- Secondary storage/state-integrity concerns exist in lesser-reviewed auxiliary contracts, but have not yet matched the confidence or depth of the main strategy issues

## Useful Context
- Audit attention is heavily concentrated on `FlawVerifier.sol`; it is the main contract to carry forward in cross-round reasoning
- The most important recurring pattern is unsafe composition: approvals + probing + swaps + liquidation logic in one execution path
- `Counter.sol` remains low-coverage relative to scope, so absence of findings there should not be treated as strong evidence of safety
- Retained cross-round signal so far is concentrated in four durable themes: trapped assets, over-open execution, slippage exposure, and hazardous external interaction surfaces


## Latest Round Summary
# Round 2 Summary

## Agent: codex
- files touched: `FlawVerifier.sol`, `Counter.sol`
- files revisited / highest-attention files: `FlawVerifier.sol` received the clear majority of attention, especially `executeOnOpportunity()`, `_tryCycle()`, and the probe/liquidation helper paths reached through low-level calls
- main issue directions investigated: hard-coded mainnet endpoint safety; whether execution enforces an end-to-end profitability invariant; reentrancy exposure from arbitrary external calls during active approvals/fund custody; unrestricted mutation in `Counter.sol`
- promising but not retained directions: low-confidence reentrancy/reentrant nested execution around probe/attempt helpers; `Counter.sol` unrestricted state mutation was surfaced but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: only `codex` participated this round, with attention concentrated on `FlawVerifier.sol` execution flow and external-call paths
- notable differences in attention: `Counter.sol` was checked briefly, while `FlawVerifier.sol` was examined in depth via multiple focused reads of its middle and helper sections
- underexplored but suspicious files/functions if clearly supported by the logs: `FlawVerifier.sol` low-level call surfaces tied to probe/attempt helpers remained a live area of scrutiny in the logs, but only the profit-invariant and wrong-chain endpoint issues were retained

## Retained Findings
- `F-005`: retained the wrong-chain deployment risk from hard-coded Ethereum mainnet addresses, especially value-bearing interaction with the fixed `WETH` endpoint without chain/contract validation
- `F-006`: retained the lack of a top-level profit check, where speculative probing and liquidation can complete successfully even if the overall run leaves the contract worse off


Output only markdown.
