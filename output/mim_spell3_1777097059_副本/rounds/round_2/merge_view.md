# Merge View - Round 2

## Summary
- total findings: 7
- new findings: 3
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- existing_preserved: 4
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-005 | rewritten_agent_signal | Medium | medium | codex | Permissionless `withdrawFees()` can send accrued fees to an unset `feeTo` address | codex:0.522 Anyone can burn accrued fees before `feeTo` is configured |
| F-006 | rewritten_agent_signal | Medium | high | codex | Stranded ETH in the cauldron can be drained through `cook(ACTION_CALL)` | codex:0.672 Any ETH stranded in the cauldron can be stolen with `cook()` |
| F-008 | rewritten_agent_signal | High | low | codex | Checkpoint-token reentrancy before state updates can corrupt privileged liquidation accounting | codex:0.795 Checkpoint-token reentrancy can corrupt liquidation accounting |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Batch liquidation can leave unrecoverable ghost debt through per-user rounding | Each `toElastic(..., false)` round-down is bounded to less than 1 unit of underlying debt amount, so the aggregate loss is dust-level wei rounding rather than realistic protocol-level harm. |
