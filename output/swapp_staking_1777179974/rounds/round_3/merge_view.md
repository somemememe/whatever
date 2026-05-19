# Merge View - Round 3

## Summary
- total findings: 10
- new findings: 2
- updated existing findings: 1
- rejected candidates: 1

## Finding Actions
- existing_preserved: 7
- existing_rewritten: 1
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-006 | existing_rewritten | Medium | high | codex | Skipped epochs and the hardcoded 2021 epoch start can brick dormant or never-before-used pools | codex:0.757 The hardcoded June 2021 epoch start can brick fresh deployments and never-before-used pools |
| F-010 | rewritten_agent_signal | Medium | high | codex | Non-stable pool snapshots trust raw contract balances instead of tracked user stake | codex:0.536 Raw token balances can poison non-stable pool snapshots and make accounting diverge from user stakes |
| F-011 | rewritten_agent_signal | Medium | low | codex | Permissionless interest sweeps can front-run stablecoin withdrawals and worsen liquidity shortfalls | codex:0.503 Anyone can front-run stablecoin withdrawals by redeeming Compound interest to the team first |

## Rejection Reasons
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex | Fee-on-transfer withdrawals burn the full stake even when the user receives less | Rejected as a separate issue because the claimed shortfall comes from the token's own outbound transfer tax/burn semantics, while the contract balance also decreases by the full nominal amount. The material protocol-specific unsupported-token problems are already covered by F-004 and F-008. |
