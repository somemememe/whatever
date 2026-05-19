# Merge View - Round 4

## Summary
- total findings: 19
- new findings: 3
- updated existing findings: 0
- rejected candidates: 5

## Finding Actions
- existing_preserved: 16
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-017 | rewritten_agent_signal | High | high | codex_1 | Cross-chain repay path incorrectly mutates same-chain borrow storage | codex_1:0.654 Cross-chain repayment wrongly mutates same-chain borrow state, causing debt double-counting |
| F-018 | rewritten_agent_signal | High | high | codex_1 | Cross-chain liquidation uses seized-collateral quantity as debt repayment amount | codex_1:0.793 Cross-chain liquidation repays wrong amount by reusing seized-collateral quantity as debt repayment |
| F-019 | rewritten_agent_signal | Medium | low | codex_1 | Liquidation-failure refund attempts token payout without prior escrow | opencode_1:0.443 Cross-chain liquidation health check uses stale seize amount as synthetic borrow |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 2
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | Cross-chain liquidation health check uses stale seize amount as synthetic borrow | Duplicate of existing F-013 (same root cause and affected logic). |
| other | opencode_1 | Cross-chain liquidation execute lacks borrower debt validation before seize | Not independently reportable: liquidation initiation on the debt chain already requires an existing cross-chain borrow record and bounded repay amount before sending execute message. |
| other | opencode_1 | Unchecked array bounds in claimLend can cause out-of-gas DOS | Permissionless caller choosing huge arrays mainly self-DoSes their own transaction; no durable protocol-wide DoS state change is created. |
| trust_or_owner_model | opencode_1 | setCrossChainRouter allows immediate router swap without timelock | Governance/trust-model concern (owner power), not a code-level vulnerability under assumed privileged-owner model. |
| unsupported_or_speculative | opencode_1 | Cross-chain repay allows partial repay of already-removed collateral | Insufficient evidence of a concrete exploit path from current code; described inconsistency is speculative without a demonstrated reachable state transition. |
