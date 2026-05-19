# Merge View - Round 5

## Summary
- total findings: 16
- new findings: 2
- updated existing findings: 1
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 13
- existing_rewritten: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-006 | existing_rewritten | Medium | high | codex | Stranded assets held directly by the cauldron can be drained through `cook(ACTION_CALL)` | codex:0.286 Clone initialization ignores the oracle success flag and can cache a never-valid exchange rate |
| F-018 | exact_agent_candidate | High | high | codex | A reverting oracle hard-freezes borrowing, collateral withdrawals, and liquidations | codex:1.0 A reverting oracle hard-freezes borrowing, collateral withdrawals, and liquidations |
| F-021 | rewritten_agent_signal | Medium | high | codex | Missing borrow-opening-fee cap can make new borrows confiscatory or unborrowable | codex:0.294 A reverting oracle hard-freezes borrowing, collateral withdrawals, and liquidations |

## Rejection Reasons
- duplicate_or_subsumed: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Clone initialization ignores the oracle success flag and can cache a never-valid exchange rate | Overlaps with existing oracle findings: F-003 already covers failed/zero init seeding a bad cached rate, and F-004 covers later fallback to the cached rate when updates fail. This candidate does not add a distinct root cause or materially new impact. |
