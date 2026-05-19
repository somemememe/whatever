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
- files touched: `onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol`
- files revisited / highest-attention files: repeated passes over `Contract.sol`, especially `BancorNetwork`, inherited `TokenHandler`, conversion execution, path construction, and ETH/EtherToken handling
- main issue directions investigated: externally callable inherited token helpers; `convertByPath` / `doConversion` value flow; unchecked path-anchor / converter trust; ETH/EtherToken normalization across multi-hop routes
- promising but not retained directions: broader scan of public entrypoints and low-level call/staticcall surfaces did not produce additional retained findings beyond the four merged from this agent

## Agent: opencode_1
- files touched: `onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol`; task file `../../../output/bancor_dualmodel_1round_p4/rounds/round_1/agent_opencode_1/current_task.md`
- files revisited / highest-attention files: `Contract.sol`, with late-file attention around `completeXConversion` and nearby logic
- main issue directions investigated: BancorX completion flow; registry update permissions; affiliate-fee handling; allowance / approve behavior; deprecated wrapper validation
- promising but not retained directions: registry-hijack, affiliate-account validation, approve-race, and deprecated-function concerns were proposed but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents focused on the single in-scope `Contract.sol` and concentrated on externally reachable router flows in `BancorNetwork`
- notable differences in attention: `codex_1` focused on conversion-path execution, token movement primitives, and ETH/EtherToken edge cases; `opencode_1` focused more on `completeXConversion`, registry controls, and fee/approval-related checks
- underexplored but suspicious files/functions if clearly supported by the logs: no additional files existed in scope; within `Contract.sol`, `updateRegistry`, affiliate-fee paths, and deprecated conversion wrappers were examined but remain non-retained in current status

## Retained Findings
- retained set centers on five issues in `Contract.sol`: public inherited token-move helpers enabling direct fund theft; stale `msg.value` forwarding in ETH-consuming conversion hops; user-controlled path anchors redirecting source-token handling; incomplete ETH/EtherToken normalization for internal hops; and `completeXConversion` failing to source bridged funds from BancorX, breaking the intended cross-chain completion flow


Output only markdown.
