# Merge View - Round 5

## Summary
- total findings: 12
- new findings: 2
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 10
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-012 | exact_agent_candidate | Medium | high | codex | Anyone can overwrite an already-initialized epoch-0 pool snapshot | codex:0.985 Anyone can overwrite an already-initialized epoch 0 pool snapshot |
| F-013 | rewritten_agent_signal | Medium | high | codex | Permissionless `getInterest()` can confiscate unrelated stablecoins held by the contract | codex:0.735 Interest sweeping can confiscate non-interest stablecoins held by the contract |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Epoch-0 deposits can receive a multiplier above 100% if deployment predates the configured start by over one epoch | Code supports the math, but the issue is only reachable for deployments made more than one epoch before the fixed `epoch1Start` of June 21, 2021. For any deployment on or after that date, `getCurrentEpoch()` is never 0, so this is not a live or forward-looking reportable issue for the current codebase. |
