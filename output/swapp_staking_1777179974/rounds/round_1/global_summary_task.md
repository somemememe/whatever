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
- files touched: `Contract.sol`; extracted and inspected `Staking.sol` content surfaced from that wrapper file
- files revisited / highest-attention files: `Staking.sol` with repeated focus on `deposit`, `withdraw`, `emergencyWithdraw`, Compound transfer/redeem helpers, and epoch snapshot helpers
- main issue directions investigated: zero-amount withdrawal effects on global emergency gating; emergency exit accounting drift; historical pool-size snapshot integrity; non-stable token deposit crediting vs actual receipt; ignored Compound return-code handling
- promising but not retained directions: no additional discarded directions are clearly evidenced in the log beyond the retained issue set

## Cross-Agent Status
- main overlap in file/area attention: single-agent round; attention concentrated on `Staking.sol` state-accounting around deposits, withdrawals, emergency exits, and epoch-based balance/pool snapshots
- notable differences in attention: none visible from the logs because only `codex` participated
- underexplored but suspicious files/functions if clearly supported by the logs: no separate hotspot is clearly supported outside the same `Staking.sol` accounting and Compound-integration paths already examined

## Retained Findings
- `withdraw(token, 0)` can keep refreshing the token-wide withdrawal epoch marker and indefinitely block `emergencyWithdraw` for that token
- `emergencyWithdraw` lets users recover principal without fully clearing checkpoint / pool accounting, leaving stale stake visible to epoch-based logic
- `getEpochPoolSize` can return current balances for skipped epochs, making historical pool-size reads mutable instead of fixed
- non-stable `deposit` credits the requested amount without validating the actual tokens received, enabling unbacked stake with fee-on-transfer or malicious ERC-20s
- Compound `mint` / `redeem` / `redeemUnderlying` error codes are ignored, so failed integrations can silently desynchronize internal accounting from real asset state


Output only markdown.
