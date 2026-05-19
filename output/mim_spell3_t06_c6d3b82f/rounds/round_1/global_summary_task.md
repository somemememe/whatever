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
- files touched: `cauldrons/CauldronV4.sol`, `FlawVerifier.sol`, `cauldrons/PrivilegedCauldronV4.sol`, `cauldrons/PrivilegedCheckpointCauldronV4.sol`, and in-scope interface files
- files revisited / highest-attention files: `cauldrons/CauldronV4.sol` received the clear majority of attention; `FlawVerifier.sol` was reviewed but not central to retained issues
- main issue directions investigated: `cook()` action dispatch and deferred solvency enforcement; borrow/remove-collateral state flows; clone initialization and oracle/exchange-rate handling
- promising but not retained directions: separate reporting of collateral-removal abuse via the same `cook` status-reset mechanism was explored, but the merged retained set kept that root cause under the broader solvency-bypass finding

## Cross-Agent Status
- main overlap in file/area attention: all visible work in this round concentrated on `cauldrons/CauldronV4.sol`, especially `cook()`, solvency checks, and oracle rate initialization
- notable differences in attention: no cross-agent differences are visible in the provided logs because only `codex` appears in this round
- underexplored but suspicious files/functions if clearly supported by the logs: `FlawVerifier.sol` and the privileged cauldron variants were opened but not developed into retained issues; `_additionalCookAction()` and action-code handling remained the main suspicious hotspot around batch execution

## Retained Findings
- retained a critical `cook()` batching flaw where unsupported/unhandled actions reset `CookStatus`, clearing deferred solvency checks after borrow or collateral removal
- retained a high-severity initialization/oracle issue where clone setup can cache a zero exchange rate after oracle failure, making debt appear zero until a successful update occurs


Output only markdown.
