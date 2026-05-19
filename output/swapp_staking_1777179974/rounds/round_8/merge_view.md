# Merge View - Round 8

## Summary
- total findings: 14
- new findings: 1
- updated existing findings: 1
- rejected candidates: 1

## Finding Actions
- existing_preserved: 12
- existing_rewritten: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | existing_rewritten | High | high | codex | Any dust withdrawal can indefinitely block emergency exits for an entire token | codex:1.0 Any dust withdrawal can indefinitely block emergency exits for an entire token |
| F-015 | rewritten_agent_signal | High | high | codex | Withdrawal checkpoint math lets users keep late deposits with inflated same-epoch weight | codex:0.616 Selective same-epoch withdrawals can leave late deposits with near-full epoch weight |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Any dust withdrawal can indefinitely block emergency exits for an entire token | Merged into updated finding `F-001`; this round materially broadened the existing zero-amount griefing issue to include tiny positive withdrawals because the timer is global per token. |
