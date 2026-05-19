# Merge View - Round 2

## Summary
- total findings: 4
- new findings: 2
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 2
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-002 | rewritten_agent_signal | Medium | high | codex | Rewards claimed while no borrow shares exist become permanently stranded in the pair | codex:0.288 Accrued reward tokens can be stolen after any zero-debt period |
| F-004 | exact_agent_candidate | High | high | codex | Convex pool migration mishandles the sentinel `pid == 0` and can orphan all collateral | codex:1.0 Convex pool migration mishandles the sentinel `pid == 0` and can orphan all collateral |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Redemption protocol fees are double-counted unless the external handler burns the full input amount | The mismatch hinges on how the out-of-scope redemption handler burns debt. The pair comments are inconsistent, but the code in this repo alone does not show an actual double-mint; this is an external integration assumption rather than a concrete protocol bug here. |
