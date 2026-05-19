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

## Agent: codex_1
- files touched: `onchain_auto/0x1c91af03a390b4c619b444425b3119e553b5b44b/Contract.sol`, `onchain_auto/0x4deca517d6817b6510798b7328f2314d3003abac/Contract.sol`
- files revisited / highest-attention files: highest attention on `onchain_auto/0x1c91af03a390b4c619b444425b3119e553b5b44b/Contract.sol`; revisited governance/registry and claims-related regions, with a targeted read of the proxy contract
- main issue directions investigated: round funding and claim snapshot integrity, same-block reward claiming behavior, stake-removal timing around claims, governance proposal liveness/slot pressure, zero-stake proposal evaluation, and proxy-aware governance code-hash validation
- promising but not retained directions: none clearly visible from the logs beyond the findings that were ultimately retained

## Agent: opencode_1
- files touched: `onchain_auto/0x1c91af03a390b4c619b444425b3119e553b5b44b/Contract.sol`, `onchain_auto/0x4deca517d6817b6510798b7328f2314d3003abac/Contract.sol`
- files revisited / highest-attention files: repeatedly paged through `onchain_auto/0x1c91af03a390b4c619b444425b3119e553b5b44b/Contract.sol` across multiple offsets; lighter attention on the proxy contract
- main issue directions investigated: permissionless reward claiming, guardian/governance privilege surfaces, initialization behavior, registry access control, staking/register validation, and claim math edge cases
- promising but not retained directions: unauthorized reward theft via `claimRewards`, guardian arbitrary execution, broken initialization, registry single-point-of-failure, stake-validation/zero-stake registration issues, division-by-zero in claims, and zero-address guardian transfer were proposed but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `onchain_auto/0x1c91af03a390b4c619b444425b3119e553b5b44b/Contract.sol`, especially rewards/claims and governance-related logic
- notable differences in attention: `codex_1` went deeper on round snapshot mutability, claim-window stake timing, proposal lifecycle, and proxy/code-hash semantics; `opencode_1` spent more attention on broad privilege, initialization, registry, and staking-validation surfaces
- underexplored but suspicious files/functions if clearly supported by the logs: `onchain_auto/0x4deca517d6817b6510798b7328f2314d3003abac/Contract.sol` received comparatively limited direct review, though it mattered to the retained governance proxy/code-hash issue

## Retained Findings
- retained issues centered on reward-round integrity and governance liveness/integrity
- claims/rewards retained: same-block mutable funding snapshots enabling replay/reordering, matured stake-removal actions executable before claim finalization, mutable `fundingAmount` affecting in-progress rounds, and permissionless zero-value claim griefing during temporary ineligibility
- governance retained: dust-stake proposal-slot griefing, zero-total-stake guardian proposals becoming stuck, and code-hash pinning failing to capture proxy implementation upgrades


Output only markdown.
