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
- files touched: `Replica.sol`, `NomadBase.sol`, `Message.sol`, `Merkle.sol`, `TypeCasts.sol`, `UpgradeBeaconProxy.sol`, plus supporting reads in `ECDSA.sol`, `Address.sol`, and `OwnableUpgradeable.sol` via cited locations/output
- files revisited / highest-attention files: `Replica.sol` and `NomadBase.sol` received the most attention; `Replica.sol` was read in multiple passes
- main issue directions investigated: proxy initialization safety, updater-signature domain binding/replay scope, message recipient encoding/execution behavior, plus broader root update / processing flow review
- promising but not retained directions: `Failed` state enforcement gaps and updater-rotation orphaning of signed roots were reported by the agent but were not retained after merge

## Agent: opencode_1
- files touched: `Replica.sol`, `NomadBase.sol`, `Merkle.sol`, `Message.sol`, `TypeCasts.sol`, `Version0.sol`, `IMessageRecipient.sol`, `UpgradeBeaconProxy.sol`
- files revisited / highest-attention files: attention was concentrated on `Replica.sol` and `NomadBase.sol`; no explicit revisits are visible in the log
- main issue directions investigated: message validation/execution in `Replica`, proof lifecycle, governance/root confirmation controls, updater trust assumptions, and initialization-time timeout behavior
- promising but not retained directions: origin-domain validation, re-proving / proof reuse, governance root confirmation bypass, single-updater centralization, zero-timeout initialization, ignored `handle()` result, and zero-updater freezing were proposed but not retained

## Cross-Agent Status
- main overlap in file/area attention: both agents centered on `Replica.sol` and `NomadBase.sol`, with shared review of `Message.sol`, `TypeCasts.sol`, and `UpgradeBeaconProxy.sol`
- notable differences in attention: `codex_1` pushed deeper into signature construction/binding and proxy initialization mechanics; `opencode_1` spent more attention on governance controls, proof lifecycle, and operational misconfiguration angles
- underexplored but suspicious files/functions if clearly supported by the logs: no separate underexplored hotspot is clearly supported beyond the core `Replica` / `NomadBase` execution paths, which already dominated attention

## Retained Findings
- retained issues from this round were all sourced from `codex_1`
- the kept findings were: uninitialized beacon-proxy takeover risk, updater-signature replay across deployments sharing domain/updater configuration, and recipient truncation / dispatch-to-wrong-address risk in message processing


Output only markdown.
