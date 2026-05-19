# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 6
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- rewritten_agent_signal: 6

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | First-time same-chain borrow bypasses collateral check | codex_1:0.842 First-time same-chain borrow skips collateral check entirely |
| F-002 | rewritten_agent_signal | Critical | high | codex_1 | Cross-chain borrow trusts stale source collateral snapshot (TOCTOU) | codex_1:0.724 Cross-chain borrow uses stale source-collateral snapshot (TOCTOU), enabling undercollateralized remote debt |
| F-003 | rewritten_agent_signal | Critical | high | codex_1 | Cross-chain debt is excluded from accounting due impossible EID condition | codex_1:0.776 Cross-chain debt is excluded from accounting due wrong EID condition in `borrowWithInterest` |
| F-004 | rewritten_agent_signal | High | high | codex_1 | Source-chain cross-chain debt update drops accrued interest when refreshing borrow index | codex_1:0.573 Source-chain cross-chain debt accrual is overwritten, causing debt under-accounting |
| F-005 | rewritten_agent_signal | Medium | high | codex_1 | Public cross-chain operations are protocol-fee sponsored, enabling native fee griefing | codex_1:0.508 Public users can force protocol to sponsor LayerZero fees and deplete router native balance |
| F-006 | rewritten_agent_signal | Medium | high | codex_1 | Cross-chain liquidation finalization uses inconsistent token identity and impossible lookup parameters | codex_1:0.507 Liquidation settlement handlers use inconsistent token identifiers, likely reverting success/failure processing |

## Rejection Reasons
- other: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing Reentrancy Guards on Critical Functions | Generic pattern only; no concrete, code-supported reentrancy exploit path was established in-scope. Reported severity (Critical) is not justified from provided evidence. |
| unsupported_or_speculative | opencode_1 | Inverted Liquidation Shortfall Check Allows Incorrect Liquidations | `require(borrowedAmount > collateral)` is the expected shortfall condition for liquidation. The candidate is incomplete/truncated and not supported by the actual logic at the cited location. |
