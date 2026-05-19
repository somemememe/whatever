# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 2
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex | Permissionless time-locked emergency withdrawal lets any EOA drain ROAR and LP reserves | codex:0.692 Unrestricted emergency withdrawal lets any EOA drain both token balances |
| F-003 | rewritten_agent_signal | Medium | high | codex | Hard-coded withdrawal amounts can permanently strand sub-threshold token balances | codex:0.605 Hard-coded payout amounts can permanently lock residual funds or strand surpluses |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | The arithmetic guard is a disguised hardcoded unlock that always passes after a preset date | This is the mechanism that makes F-001 exploitable, but it does not create distinct protocol harm beyond the permissionless drain already captured there. |
| other | codex | Using tx.origin as the beneficiary misroutes withdrawals and enables phishing-style abuse | `tx.origin` is poor practice, but here it does not add a separate exploitable loss beyond F-001 because the function is already permissionless and always pays the top-level caller. |
