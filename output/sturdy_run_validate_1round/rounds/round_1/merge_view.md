# Merge View - Round 1

## Summary
- total findings: 1
- new findings: 1
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | medium | codex | Read-only reentrancy during Balancer exit transiently overvalues BPT collateral and lets attackers remove real collateral | codex:0.398 Collateral-disable checks can be bypassed under the transient LP mispricing, enabling withdrawal of real collateral |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Balancer LP collateral can be massively overvalued through read-only reentrancy during pool exit | Kept as part of F-001's root cause, but rejected as a standalone issue because the PoC does not separately demonstrate borrowing new assets during the reentrant window; the validated exploit uses the transient overvaluation to bypass collateral-disable checks and withdraw real collateral. |
