# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex | Unsupported `cook` actions silently clear the deferred solvency check | codex:1.0 Unsupported `cook` actions silently clear the deferred solvency check |
| F-002 | exact_agent_candidate | Critical | high | codex | A zero oracle rate is treated as valid, making dust-collateralized debt appear solvent and unliquidatable | codex:0.873 A zero oracle rate is treated as valid, making dust-collateralized debt appear fully solvent |
| F-003 | exact_agent_candidate | High | high | codex | `init()` ignores the oracle success flag and can seed a poisoned cached price at deployment | codex:0.917 `init()` ignores the oracle success flag and can seed a poisoned cached price |
| F-004 | rewritten_agent_signal | Medium | medium | codex | Borrowing, collateral withdrawals, and liquidation decisions continue against stale prices when oracle updates fail | codex:0.65 Risk actions continue against stale cached prices whenever the oracle update fails |

## Rejection Reasons
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex | Public clone initialization is first-come-first-served if deployment is ever non-atomic | This depends on an out-of-scope, non-atomic clone deployment flow that is not shown in the in-scope code. The available interface strongly suggests clone deployment takes init data in the same transaction, so the reported race is too speculative to keep as a protocol finding. |
