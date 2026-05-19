# Merge View - Round 7

## Summary
- total findings: 15
- new findings: 3
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 12
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-021 | exact_agent_candidate | High | high | codex | Interest overflow silently forgives accrued debt and permanently skips the elapsed interval | codex:1.0 Interest overflow silently forgives accrued debt and permanently skips the elapsed interval |
| F-022 | exact_agent_candidate | Medium | high | codex | Invalidating a reward token strands already accrued user rewards and pair-held balances | codex:1.0 Invalidating a reward token strands already accrued user rewards and pair-held balances |
| F-023 | rewritten_agent_signal | High | high | codex | Constructor bypasses the liquidation-fee and protocol-redemption-fee caps enforced by runtime setters | codex:0.277 Invalidating a reward token strands already accrued user rewards and pair-held balances |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Redemptions ignore pair insolvency and let early redeemers drain distressed collateral at par | `redeemCollateral()` intentionally redeems at the oracle exchange rate and explicitly socializes the collateral loss via `redemptionWriteOff`; absent contrary spec or upstream registry logic, this reads as a protocol design choice rather than a clear implementation flaw. |
