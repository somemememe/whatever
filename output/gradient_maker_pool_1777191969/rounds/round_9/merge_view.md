# Merge View - Round 9

## Summary
- total findings: 18
- new findings: 1
- updated existing findings: 1
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 16
- existing_rewritten: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-021 | existing_rewritten | Low | high | codex | Small fee distributions are permanently stranded because reward dust is never carried forward | codex:0.335 Orderbook settlement can replace valuable inventory with arbitrary cheap inventory at any implicit price |
| F-024 | exact_agent_candidate | High | high | codex | Orderbook loans are not isolated per pool, so repayments can be redirected to a different pool | codex:1.0 Orderbook loans are not isolated per pool, so repayments can be redirected to a different pool |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Orderbook settlement can replace valuable inventory with arbitrary cheap inventory at any implicit price | Not kept as a separate issue because the harmful effect is already covered by the existing raw-sum/liquidity-accounting findings, especially F-002 and F-019; this candidate mainly describes another manifestation of the same mispricing rather than a distinct additional bug. |
