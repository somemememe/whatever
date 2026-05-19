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
- files touched: `cauldrons/CauldronV4.sol`, `cauldrons/PrivilegedCauldronV4.sol`, `cauldrons/PrivilegedCheckpointCauldronV4.sol`, `interfaces/IBentoBoxV1.sol`, `interfaces/ICheckpointToken.sol`, `interfaces/IOracle.sol`, `interfaces/IStrategy.sol`, `interfaces/ISwapperV2.sol`
- files revisited / highest-attention files: `cauldrons/CauldronV4.sol` was repeatedly chunked, line-numbered, and function-indexed; `interfaces/IOracle.sol` received direct attention as part of oracle-scaling review
- main issue directions investigated: `cook()` action dispatch and solvency-check state handling; oracle rate scaling assumptions vs `IOracle.decimals()`; acceptance of zero/invalid oracle rates; stale-price fallback in borrowing, collateral withdrawal, and liquidation paths
- promising but not retained directions: broader review of privileged cauldron variants and remaining interfaces is visible, but no separate retained issue from those files is supported by the logs

## Cross-Agent Status
- main overlap in file/area attention: only one agent participated; attention is concentrated on `cauldrons/CauldronV4.sol`, with supporting review of `interfaces/IOracle.sol`
- notable differences in attention: no cross-agent divergence this round
- underexplored but suspicious files/functions if clearly supported by the logs: `cauldrons/PrivilegedCauldronV4.sol`, `cauldrons/PrivilegedCheckpointCauldronV4.sol`, and non-oracle interfaces were opened but not deeply revisited; `_additionalCookAction()` / unhandled `cook()` actions and oracle-update paths were the dominant hotspot

## Retained Findings
- retained issues center on two areas: `cook()` can bypass final solvency enforcement via unhandled actions, and oracle handling is unsafe in multiple ways
- the oracle-related retained set covers fixed 18-decimal assumptions, acceptance of zero/invalid rates, and indefinite reuse of stale cached prices
- merged outcome for this round is four retained findings: one `cook()` solvency-bypass issue and three oracle/pricing issues


Output only markdown.
