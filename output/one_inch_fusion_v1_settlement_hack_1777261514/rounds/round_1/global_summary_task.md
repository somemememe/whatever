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
- files touched: `FlawVerifier.sol`, `Counter.sol`
- files revisited / highest-attention files: `FlawVerifier.sol` received repeated line-numbered passes, especially the replay / nested interaction sections around `executeOnOpportunity`, `_tryReplayCalldataCorruption`, `_buildReplayOrder`, and `_drainSettlementToken`
- main issue directions investigated: caller-supplied `interaction` bytes not matching signed order payloads; self-targeted settlement reentry and `allowedSender = SETTLEMENT` bypass; forged dynamic offset/length metadata causing calldata corruption and historical order replay; fake ERC20 maker asset behavior causing payout of real settlement-held tokens
- promising but not retained directions: `Counter.sol` was checked and flagged during the round for unrestricted public state mutation, but that issue was not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: only `codex` appears in this round, with attention concentrated on `FlawVerifier.sol`
- notable differences in attention: none visible from the logs for this round; `Counter.sol` received only a brief final pass compared with the deep tracing on `FlawVerifier.sol`
- underexplored but suspicious files/functions if clearly supported by the logs: `Counter.sol` was minimally reviewed; within `FlawVerifier.sol`, helper flows tied to `_buildReplayOrder` and `_drainSettlementToken` were central attention points, while the rest of the file appears less explored by comparison

## Retained Findings
- retained issues from this round all center on `FlawVerifier.sol` and the settlement path: unsigned external interaction data being executed, settlement self-reentry enabling `allowedSender` bypass, unsafe dynamic offset/length parsing enabling calldata corruption and replay, and fake-token accounting assumptions that let real settlement inventory be drained


Output only markdown.
