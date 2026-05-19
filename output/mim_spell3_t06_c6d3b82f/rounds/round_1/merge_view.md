# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 2
- updated existing findings: 0
- rejected candidates: 0

## Finding Actions
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex | Unhandled `cook` actions reset `CookStatus` and bypass the deferred solvency check after borrow or collateral removal | codex:0.562 Unhandled `cook` actions clear the final solvency check, enabling unbacked MIM borrows |
| F-003 | rewritten_agent_signal | High | medium | codex | Clone initialization can lock in a failed zero oracle rate, making positions appear solvent | codex:0.55 Clone initialization ignores oracle failure and can lock in a zero exchange rate |

## Rejection Reasons
- none
