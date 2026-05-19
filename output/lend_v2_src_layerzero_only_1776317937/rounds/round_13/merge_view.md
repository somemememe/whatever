# Merge View - Round 13

## Summary
- total findings: 42
- new findings: 3
- updated existing findings: 1
- rejected candidates: 3

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 38
- existing_support_added: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-017 | existing_support_added | High | high | codex_1,opencode_1 | Cross-chain repay path incorrectly mutates same-chain borrow storage | opencode_1:0.637 Cross-chain repay uses wrong liquidation path for same-chain borrow |
| F-042 | exact_agent_candidate | Critical | high | codex_1,merge_layer | Cross-chain borrow authorization uses gross source collateral and ignores existing source-chain liabilities | codex_1:0.956 Cross-chain borrow authorization uses gross source collateral and ignores source-chain liabilities |
| F-043 | rewritten_agent_signal | Medium | medium | codex_1,merge_layer | Controller split-brain risk: storage lendtroller is mutable while routers retain stale controller pointers | codex_1:0.768 Lendtroller split-brain risk: storage controller is mutable but router controllers are fixed |
| F-045 | exact_agent_candidate | Low | high | codex_1,merge_layer | Protocol seizure-share accounting accumulates without an in-scope realization path | codex_1:0.937 Protocol seizure-share accounting accumulates without an in-scope withdrawal/realization path |

## Rejection Reasons
- duplicate_or_subsumed: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | LayerZero send fee is hardcoded to full router ETH balance on every outbound message | Not a distinct new issue; fee sponsorship/drain vector is already captured in F-005. The stronger one-call full-drain claim is implementation-dependent and speculative because LayerZero endpoint overpayment is typically refunded to the configured refund address. |
| duplicate_or_subsumed | opencode_1 | Cross-chain repay uses wrong liquidation path for same-chain borrow | Duplicate of existing F-017 (same root cause: cross-chain repay invokes `_isSameChain=false` path and mutates same-chain borrow storage). |
| unsupported_or_speculative | opencode_1 | Cross-chain liquidation uses zero storedBorrowIndex in validation params | Non-reportable/speculative: `storedBorrowIndex` is initialized in memory but must be populated before use; `require(found, "No matching borrow position")` prevents downstream use of zero in current code path. |
