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
- files touched: `0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol`
- files revisited / highest-attention files: `Contract.sol`, especially `PointFarm` reward flows around `deposit`, `withdraw`, ERC1155 mint/callback behavior, and pool accounting
- main issue directions investigated: externally reachable state-changing flows; ERC1155 receiver callback reentrancy during reward minting; staking/share accounting against live `balanceOf(address(this))` for non-standard stake tokens
- promising but not retained directions: logs mention additional candidate issue screening, but only the reentrancy and stake-token accounting directions were visibly finalized by this agent

## Agent: opencode_1
- files touched: `0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol`
- files revisited / highest-attention files: `Contract.sol`, with visible attention near pool operation/admin sections and late-file functions such as `pendingPoints`, `deposit`, `withdraw`, `emergencyWithdraw`, `add`, and `setShop`
- main issue directions investigated: emergency-withdraw reward accounting; shop initialization / pool addition gating; pool ID bounds handling; reward precision loss; missing event emission on shop changes
- promising but not retained directions: the emergency-withdraw reward-theft theory, zero-address `shop` lock concern, missing pool ID bounds check, rounding loss, and missing `setShop` event were proposed in output but are not reflected in retained findings

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on the single in-scope `Contract.sol`, especially the `PointFarm` staking/reward accounting surface
- notable differences in attention: `codex_1` focused on concrete exploitability in reward minting and token accounting; `opencode_1` focused more on operational/admin behavior and generic safety checks around pool management and withdrawals
- underexplored but suspicious files/functions if clearly supported by the logs: admin-controlled emission logic around `setMintRules`, `setStartBlock`, and later `updatePool` settlement appears in retained findings but is not clearly represented in the visible per-agent logs

## Retained Findings
- ERC1155 reward minting before debt updates allows callback reentrancy to mint the same pending points repeatedly
- stake accounting is unsafe for fee-on-transfer / balance-decreasing staking tokens, creating insolvency and distorted reward shares
- reward parameter changes can retroactively alter past emissions for untouched pools because global emission setters do not checkpoint pools first


Output only markdown.
