# Merge View - Round 12

## Summary
- total findings: 39
- new findings: 3
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 3
- existing_preserved: 36

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-038 | exact_agent_candidate | High | medium | codex_1,merge_layer | Repay flow is reentrant and can erase newly-created debt via stale full-repay snapshot | codex_1:1.0 Repay flow is reentrant and can erase newly-created debt via stale full-repay snapshot |
| F-040 | exact_agent_candidate | Medium | high | codex_1,merge_layer | Borrow authorization double-applies borrow-index growth to already-accrued debt value | codex_1:1.0 Borrow authorization double-applies borrow-index growth to already-accrued debt value |
| F-041 | exact_agent_candidate | Medium | low | codex_1,merge_layer | Cross-chain collateral record matching omits destination market identity, risking index/debt corruption | codex_1:1.0 Cross-chain collateral record matching omits destination market identity, risking index/debt corruption |

## Rejection Reasons
- duplicate_or_subsumed: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | Same-chain liquidation credits seized collateral without adding liquidator supplied-asset membership | Duplicate of existing F-022 (same root cause and locations); no materially distinct exploit primitive beyond the already captured collateral-visibility distortion. |
