# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Unconditional revert in redeem policy freezes all redemptions, exits, and cToken transfers | codex_1:0.658 Hard-coded revert in redeem policy freezes redemptions and market exits |
| F-002 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Unconditional revert in repay policy disables repayments and liquidation repayments | codex_1:0.797 Hard-coded revert in repay policy disables both repayments and liquidations |
| F-003 | rewritten_agent_signal | Medium | low | codex_1 | `accountAssets` is no longer capped, enabling gas-based DoS of liquidity and liquidation checks | codex_1:0.495 Missing `maxAssets` enforcement enables gas-based liquidation and liquidity-check denial of service |
| F-004 | rewritten_agent_signal | Medium | low | codex_1 | Collateral-cap registration runs before membership checks, so repeated market entry can corrupt external collateral bookkeeping | codex_1:0.379 Collateral-cap hook ordering makes collateral accounting depend on idempotent cToken implementations |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Redundant and Potentially Confusing Revert in redeemVerify | `redeemVerify`'s zero-token sanity check is a defensive invariant, not a realistic protocol-harming vulnerability; normal redeem flows should not reach it with inconsistent parameters, and any revert rolls back atomically. |
