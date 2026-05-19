# Merge View - Round 1

## Summary
- total findings: 1
- new findings: 1
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex | Same-market self-liquidation of a freshly opened position can over-credit collateral and drain the pool | codex:0.373 Liquidation accepts the same market as both debt and collateral |

## Rejection Reasons
- other: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Liquidation appears to succeed without a real shortfall | Merged into F-001. The lack of a genuine shortfall is part of the same same-market self-liquidation exploit path, not a distinct issue. |
| other | codex | Borrowers can liquidate their own positions and internalize liquidation incentives | Merged into F-001. Self-liquidation is one required condition of the broader liquidation-accounting flaw rather than a separate reportable bug on this record. |
