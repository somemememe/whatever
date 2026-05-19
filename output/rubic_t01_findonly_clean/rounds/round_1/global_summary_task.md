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
- files revisited / highest-attention files: `FlawVerifier.sol` received the main line-by-line review; `interface.sol` was revisited around executable/library regions including `TransferHelper`, `FixedPointMathLib`, `SafeTransferLib`, and `Nonces`
- main issue directions investigated: attacker-controlled `routerCallNative` target/call-data paths, zero-input route execution assumptions, `FlawVerifier` asset-lock behavior, and zero-`amountOutMin` liquidation slippage/MEV exposure
- promising but not retained directions: executable code embedded in `interface.sol` libraries/abstract contracts and related router/provider identifiers were inspected, but no round-retained result came from that pass; a quick `slither` sanity check also produced no additional logged output

## Cross-Agent Status
- main overlap in file/area attention: only one agent participated, with attention concentrated on `FlawVerifier.sol` and selective review of executable sections inside `interface.sol`
- notable differences in attention: not applicable in this round because there was only one agent
- underexplored but suspicious files/functions if clearly supported by the logs: `interface.sol` contains nontrivial executable/library code despite its name, and those sections were only selectively inspected relative to the deeper focus on `FlawVerifier.sol`

## Retained Findings
- None retained from this round after merge.


Output only markdown.
