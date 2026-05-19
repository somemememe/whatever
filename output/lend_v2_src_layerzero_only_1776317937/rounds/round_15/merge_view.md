# Merge View - Round 15

## Summary
- total findings: 46
- new findings: 2
- updated existing findings: 1
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 43
- existing_support_added: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-045 | existing_support_added | Low | high | codex_1,merge_layer,opencode_1 | Protocol seizure-share accounting accumulates without an in-scope realization path | opencode_1:0.575 Protocol seizure rewards accumulate without withdrawal mechanism |
| F-048 | exact_agent_candidate | High | medium | codex_1,merge_layer | Unordered DestRepay packet execution can corrupt source-chain debt accounting | codex_1:1.0 Unordered DestRepay packet execution can corrupt source-chain debt accounting |
| F-049 | rewritten_agent_signal | Low | high | codex_1,merge_layer | borrowCrossChain accepts native value but refunds and custody remain on router | codex_1:0.481 User-provided native value in borrowCrossChain is not refunded to the caller |

## Rejection Reasons
- duplicate_or_subsumed: 4
- other: 2
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | Cross-chain liquidation sends unmapped collateral-market identifiers without validation | Configuration-dependent and largely subsumed by already-tracked cross-chain liquidation finalization/revert issues (F-006/F-023); not retained as a distinct root-cause finding. |
| unsupported_or_speculative | codex_1 | Borrower reward distribution can hard-revert on zero borrow index | Requires `borrowIndex == 0` on a listed market, which is not realistic for standard initialized lTokens; treated as overly speculative. |
| duplicate_or_subsumed | opencode_1 | Cross-chain liquidation success uses incorrect srcEid for borrow lookup | Already captured by F-006 (lookup parameter mismatch and token-identity inconsistency in liquidation finalization). |
| unsupported_or_speculative | opencode_1 | LEND distribution uses mixed borrow indices causing calculation inconsistency | No distinct new exploit path beyond existing cross-chain borrow-index mismatch accounting issues; insufficient standalone protocol-harm evidence. |
| duplicate_or_subsumed | opencode_1 | Cross-chain liquidation uses seize amount as synthetic borrow in health check | Duplicate of F-013. |
| other | opencode_1 | Liquidation failure handler transfers tokens without balance verification | Weaker restatement of already tracked escrow/refund inconsistency (F-019); `safeTransfer` itself reverts on failure. |
| other | opencode_1 | Cross-chain borrow request allows borrowing without entering destination market | Not a protocol bug in this model; borrow market membership is not the missing enforcement root-cause for the reported harms. |
| duplicate_or_subsumed | opencode_1 | Supply function uses pre-mint exchange rate after token transfer | Already captured by F-008. |
