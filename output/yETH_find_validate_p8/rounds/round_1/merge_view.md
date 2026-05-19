# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | medium | codex | Liquidity accounting can settle against mixed stale/fresh asset rates | codex:0.662 Liquidity operations appear to settle against stale cached rates |
| F-003 | rewritten_agent_signal | High | low | codex | `remove_liquidity(0)` may expose a free accounting-transition primitive | codex:0.582 `remove_liquidity(0)` appears to be stateful and usable as a free accounting checkpoint |
| F-004 | rewritten_agent_signal | High | medium | codex | Rebasing OETH can change pool balances out-of-band from cached accounting | codex:0.497 Rebasing OETH integration appears unsafely synchronized with pool accounting |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Caller-chosen partial rate updates can create mixed stale/fresh basket valuation | Merged into F-001 because the partial-update behavior and stale-rate settlement are the same pricing-synchronization root cause. |
