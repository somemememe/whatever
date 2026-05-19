# Merge View - Round 1

## Summary
- total findings: 9
- new findings: 5
- updated existing findings: 0
- rejected candidates: 0

## Finding Actions
- exact_agent_candidate: 4
- existing_preserved: 4
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-005 | exact_agent_candidate | Critical | high | codex | Borrowing rounds debt shares down, letting new borrowers take more underlying than the liability they receive | codex:1.0 Borrowing rounds debt shares down, letting new borrowers take more underlying than the liability they receive |
| F-006 | exact_agent_candidate | Critical | high | codex | Exact-underlying redemptions burn LP shares with floor rounding, allowing lenders to withdraw more assets than their shares cover | codex:1.0 Exact-underlying redemptions burn LP shares with floor rounding, allowing lenders to withdraw more assets than their shares cover |
| F-007 | exact_agent_candidate | High | high | codex | Direct liquidation seizes collateral by value but burns too few collateral shares from the victim | codex:0.963 Liquidation seizes collateral by value but burns too few collateral shares from the victim |
| F-008 | exact_agent_candidate | Critical | high | codex | Batch liquidation collapses two-token settlements into one signed integer, allowing opposite-side liquidations to cancel out | codex:1.0 Batch liquidation collapses two-token settlements into one signed integer, allowing opposite-side liquidations to cancel out |
| F-009 | rewritten_agent_signal | Critical | high | codex | The first borrow of each asset mints 1,000 unowned debt shares to position 0, creating permanent bad debt | codex:0.421 Borrowing rounds debt shares down, letting new borrowers take more underlying than the liability they receive |

## Rejection Reasons
- none
