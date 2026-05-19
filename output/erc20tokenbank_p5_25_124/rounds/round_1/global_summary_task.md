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
- files touched: `0x765b8d7cd8ff304f796f4b6fb1bcf78698333f6d/Contract.sol`
- files revisited / highest-attention files: `0x765b8d7cd8ff304f796f4b6fb1bcf78698333f6d/Contract.sol`, especially `doExchange()` and its `issue -> approve -> exchange_underlying -> transfer` flow
- main issue directions investigated: permissionless triggering of cross-bank issuance/migration; zero-slippage Curve swap and flash-loan price manipulation; destination-bank accounting assumptions after raw ERC20 transfer
- promising but not retained directions: low-confidence concern that sending USDT to `to_bank` via raw transfer may bypass any required deposit/accounting handshake

## Agent: opencode_1
- files touched: `0x765b8d7cd8ff304f796f4b6fb1bcf78698333f6d/Contract.sol`
- files revisited / highest-attention files: `0x765b8d7cd8ff304f796f4b6fb1bcf78698333f6d/Contract.sol`, mainly `doExchange()` and constructor setup around external bank/Curve calls
- main issue directions investigated: missing slippage protection; lack of access control on `doExchange()`; output validation and exchange timing risks; constructor external-call safety; hardcoded Curve dependency
- promising but not retained directions: manipulated or unreliable `from_bank.balance()` responses; constructor revert/griefing scenarios; lack of post-swap output checks; hardcoded pool address; reentrancy via approval/external call pattern

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `Contract.sol` and specifically `doExchange()` as the contract’s primary risk surface
- notable differences in attention: `codex_1` focused on economic extraction and cross-bank asset-migration mechanics; `opencode_1` spread attention across broader implementation hygiene and deployment/runtime robustness themes
- underexplored but suspicious files/functions if clearly supported by the logs: constructor external integrations at `Contract.sol:208-218` and the post-swap transfer/accounting path at `Contract.sol:240-241` were flagged in logs but not retained after merge

## Retained Findings
- permissionless `doExchange()` can force issuance out of `from_bank` and migrate liquidity without authorization
- the same public exchange path uses Curve with `min_dy = 0`, leaving the swap fully exposed to temporary price manipulation and severe value extraction during execution


Output only markdown.
