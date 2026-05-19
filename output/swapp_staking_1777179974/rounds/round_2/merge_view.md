# Merge View - Round 2

## Summary
- total findings: 8
- new findings: 3
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 5
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-006 | exact_agent_candidate | Medium | high | codex | Dormant pools become non-withdrawable until every skipped epoch is manually backfilled | codex:1.0 Dormant pools become non-withdrawable until every skipped epoch is manually backfilled |
| F-007 | rewritten_agent_signal | Medium | medium | codex | Stablecoin stakers have no on-contract fallback exit if the Compound integration becomes unavailable | codex:0.481 Stablecoin principal has no emergency escape hatch if Compound redemptions stop working |
| F-008 | exact_agent_candidate | Medium | high | codex | Withdraw and emergency-withdraw can silently burn a user's claim when token transfers return false | codex:1.0 Withdraw and emergency-withdraw can silently burn a user's claim when token transfers return false |

## Rejection Reasons
- duplicate_or_subsumed: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Anyone can force team interest withdrawals ahead of users during Compound liquidity stress | Too speculative as a separate finding: callers can only trigger an already-intended transfer of accrued interest to `TEAM_ADDRESS`, and the user-harm scenario depends on external Compound liquidity stress while overlapping with the broader Compound redemption/lockup issues already captured. |
