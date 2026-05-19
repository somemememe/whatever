# Merge View - Round 3

## Summary
- total findings: 16
- new findings: 3
- updated existing findings: 6
- rejected candidates: 5

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 7
- existing_support_added: 6
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | existing_support_added | Critical | high | codex_1,opencode_1 | First-time same-chain borrow bypasses collateral check | opencode_1:0.569 First-time borrower can borrow with zero collateral due to bypassed liquidity check |
| F-002 | existing_support_added | Critical | high | codex_1,opencode_1 | Cross-chain borrow trusts stale source collateral snapshot (TOCTOU) | opencode_1:0.543 Cross-chain borrow collateral validation uses stale snapshot allowing over-borrowing |
| F-004 | existing_support_added | High | high | codex_1,opencode_1 | Source-chain cross-chain debt update drops accrued interest when refreshing borrow index | opencode_1:0.471 Cross-chain borrow position update uses stale index before new borrow accrues interest |
| F-007 | existing_support_added | High | high | codex_1,opencode_1 | Cross-chain liquidation seizes collateral before repayment is enforced | opencode_1:0.542 Liquidator receives shares before borrower debt is reduced on source chain |
| F-012 | existing_support_added | Medium | medium | codex_1,opencode_1 | Cross-chain repay lookup is ambiguous and keyed only by srcEid | opencode_1:0.443 Cross-chain repay accepts any srcEid without validating match to stored borrow |
| F-013 | existing_support_added | High | medium | merge_layer,opencode_1 | Cross-chain liquidation health check uses seize amount as synthetic new borrow | opencode_1:0.519 Cross-chain borrow collateral validation uses stale snapshot allowing over-borrowing |
| F-014 | exact_agent_candidate | High | high | codex_1 | LEND rewards can be claimed repeatedly because accrued balances are never decremented | codex_1:1.0 LEND rewards can be claimed repeatedly because accrued balances are never decremented |
| F-015 | rewritten_agent_signal | High | medium | codex_1 | Liquidity checks accept zero oracle prices, creating fail-open borrow authorization | codex_1:0.644 Liquidity checks trust zero oracle prices, enabling borrow-limit bypass when price feed returns 0 |
| F-016 | rewritten_agent_signal | Medium | low | codex_1 | Borrow/redeem update accounting after external calls, leaving reentrancy window for callback-capable tokens | codex_1:0.679 State updates happen after external token interactions, allowing reentrancy on callback-capable tokens |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 1
- other: 1
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | Native fee payment has no refund mechanism causing permanent loss | Not supported: `_lzSend` uses LayerZero fee flow with refund address `address(this)`, so overpayment is not inherently permanently lost; primary fee issue is already captured by sponsored-fee griefing (F-005). |
| other | opencode_1 | Division by zero possible in liquidation collateral calculation | Low-plausibility state corruption scenario: active borrow positions are created with non-zero `borrowIndex`; no credible in-scope path found to reach liquidation with debt and `borrowIndex == 0`. |
| trust_or_owner_model | opencode_1 | ethWithdrawal function lacks reentrancy protection | `withdrawEth` is `onlyOwner`, transfers full balance, and has no vulnerable post-call state mutation; no realistic exploit path shown. |
| low_impact_or_operational | opencode_1 | Missing events for critical accounting state changes | Operational/auditability concern, not a protocol-level security vulnerability. |
| unsupported_or_speculative | opencode_1 | Borrow index can be manipulated through flash loan before cross-chain borrow | Speculative and unsupported: no concrete mechanism shown to profitably manipulate Compound-style `borrowIndex` in this code path. |
