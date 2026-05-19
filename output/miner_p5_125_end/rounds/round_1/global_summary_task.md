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
- files touched: `0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol`
- files revisited / highest-attention files: `Contract.sol`, especially the mixed approval / transfer area around `approve`, `transferFrom`, `safeTransferFrom`, and ownership / approval helpers
- main issue directions investigated: ERC20/NFT semantic overloading, NFT-path `transferFrom` behavior, stale `getApproved` handling across safe transfers, and approval confusion between fungible allowances and NFT approvals
- promising but not retained directions: none clearly shown in the visible log beyond the retained issues

## Agent: opencode_1
- files touched: `0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol`
- files revisited / highest-attention files: `Contract.sol` only; visible log shows a full read plus a later read from offset `1423`
- main issue directions investigated: burn / `_update` accounting, mixed `transferFrom` semantics, `approve` dual behavior, max-wallet / transfer-delay enforcement, and ERC20/NFT ID ambiguity
- promising but not retained directions: several broader claims around max-wallet bypass, transfer-delay bypass, `_burnBatch` search behavior, and generic ID-space ambiguity were explored in output but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on the single in-scope `Contract.sol`, with clear overlap on the mixed ERC20/NFT interface surface around `approve` and `transferFrom`
- notable differences in attention: `codex_1` focused more tightly on approval persistence and concrete exploit paths in transfer logic; `opencode_1` ranged more broadly into `_update`, burn/mint accounting, max-wallet, and transfer-delay mechanics
- underexplored but suspicious files/functions if clearly supported by the logs: the burn/mint hook path around `_update`, `_afterTokenTransfer`, and transfer-delay enforcement remains a current hotspot, supported by retained issue `F-004` but with limited explicit step-by-step investigation visible in the logs

## Retained Findings
- Retained issues centered on the hybrid ERC20/NFT transfer and approval design in `Contract.sol`
- Confirmed outcomes included double fungible debiting on NFT-style `transferFrom`, stale per-token approvals surviving safe transfer paths, small ERC20 approvals being reinterpreted as NFT approvals, and transfer-delay self-reverts when one ERC20 transfer both burns and mints NFT units


Output only markdown.
