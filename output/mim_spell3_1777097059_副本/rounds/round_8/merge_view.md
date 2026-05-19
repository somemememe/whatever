# Merge View - Round 8

## Summary
- total findings: 20
- new findings: 2
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 18

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-025 | exact_agent_candidate | Medium | medium | codex | Batch liquidations can undercharge repeated partial liquidations through duplicate-user round-down | codex:1.0 Batch liquidations can undercharge repeated partial liquidations through duplicate-user round-down |
| F-026 | exact_agent_candidate | High | low | codex | Fresh clones are first-caller-wins because `init()` has no authorized initializer | codex:1.0 Fresh clones are first-caller-wins because `init()` has no authorized initializer |

## Rejection Reasons
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Privileged debt injection bypasses both global and per-address borrow caps | Rejected as non-distinct from the existing privileged backdoor findings: the same owner-only path already lets the operator assign arbitrary debt and extract backing MIM, so cap bypass does not add a materially separate protocol-harm vector. |
