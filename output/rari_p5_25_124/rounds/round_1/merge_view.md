# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1,opencode_1 | SimplePriceOracle lets any account arbitrarily reprice listed assets | codex_1:0.873 SimplePriceOracle lets any account arbitrarily reprice collateral and debt |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1 | Rewards claims can be reentered before accrued balances are cleared | codex_1:0.526 Reward transfers can silently fail while user accrual is still cleared |
| F-005 | rewritten_agent_signal | Medium | high | codex_1 | A reverting rewards distributor can brick core market actions until the comptroller is upgraded | codex_1:0.44 A single bad rewards distributor can permanently DOS mint, borrow, repay, transfer, and liquidation flows |
| F-006 | rewritten_agent_signal | Medium | high | codex_1 | Unchecked reward-token transfers can erase accrued rewards without payment | codex_1:0.465 Rewards claims are reentrant and can pay the same rewards repeatedly |
| F-007 | rewritten_agent_signal | Medium | high | codex_1 | Reservoir drip accounting advances even when token transfer fails silently | codex_1:0.434 Reservoir can permanently under-distribute rewards on silent transfer failures |

## Rejection Reasons
- duplicate_or_subsumed: 1
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex_1 | Unitroller fallback can hot-swap comptroller logic on any user call | The fallback does auto-switch implementations when autoImplementation is enabled, but the harmful scenario depends on privileged Fuse-admin registry behavior or unspecified future implementation migration requirements; this is too speculative as a standalone vulnerability. |
| trust_or_owner_model | codex_1 | A hardcoded external Fuse admin keeps hidden superuser control over pools and markets | The hardcoded Fuse admin and its rights are explicit in storage and admin checks. Absent evidence that this authority is undisclosed, this is privileged governance design rather than an unintended access-control flaw. |
| duplicate_or_subsumed | opencode_1 | Price Oracle Manipulation Enables Arbitrary Liquidations | Duplicate of the unrestricted SimplePriceOracle setters issue already captured in F-001; forced liquidations are one exploit path of the same root cause. |
