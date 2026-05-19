# Merge View - Round 9

## Summary
- total findings: 14
- new findings: 0
- updated existing findings: 2
- rejected candidates: 2

## Finding Actions
- existing_preserved: 12
- existing_rewritten: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | existing_rewritten | High | high | codex | Any dust or zero-amount withdrawal by any historical staker can indefinitely block emergency exits for an entire token | codex:0.482 Former stakers can block emergency exits forever with zero-amount withdrawals |
| F-008 | existing_rewritten | Medium | high | codex | Withdraw and emergency-withdraw can burn a user's full claim even when outbound tokens fail or short-pay | codex:0.481 Arbitrary-token exits burn full claims even when the user receives fewer tokens |

## Rejection Reasons
- other: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Former stakers can block emergency exits forever with zero-amount withdrawals | Merged into F-001 as a material improvement. It is the same root cause: global `lastWithdrawEpochId` plus zero-amount `withdraw()` calls keeping `emergencyWithdraw()` unavailable; the updated finding now explicitly captures that former stakers with leftover checkpoints can do this without holding any stake. |
| other | codex | Arbitrary-token exits burn full claims even when the user receives fewer tokens | Merged into F-008 as a material improvement. The updated finding now covers both zero-payout `false` returns and short-paying fee-on-transfer/deflationary outbound transfers that still burn the user's full recorded claim. |
