# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 0

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex | `cook()` solvency enforcement can be cleared by `ACTION_ACCRUE` or any unsupported action | codex:0.811 `cook()` post-action solvency check can be erased with `ACTION_ACCRUE` or any unsupported action |
| F-002 | rewritten_agent_signal | High | medium | codex | Cauldron hardcodes 18-decimal oracle precision and ignores `IOracle.decimals()` | codex:0.416 Oracle precision is hardcoded to `1e18` even though the oracle interface exposes arbitrary decimals |
| F-003 | rewritten_agent_signal | Critical | medium | codex | Zero oracle rates are accepted and make any borrower with nonzero collateral appear solvent | codex:0.611 Unchecked zero/invalid oracle rates can make every collateralized borrower appear solvent |
| F-004 | exact_agent_candidate | High | high | codex | Oracle failures fall back to an unbounded stale price across borrowing, withdrawals, and liquidations | codex:0.955 Oracle failure falls back to an unbounded stale price for borrowing, withdrawals, and liquidations |

## Rejection Reasons
- none
