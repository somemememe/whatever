# Merge View - Round 9

## Summary
- total findings: 29
- new findings: 3
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- existing_preserved: 26
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-027 | rewritten_agent_signal | Medium | medium | codex_1,merge_layer | Cross-chain borrow compares collateral and debt under different chain-local oracle domains | codex_1:0.606 Cross-chain borrow compares values from different oracle domains without normalization/attestation |
| F-028 | rewritten_agent_signal | Medium | high | codex_1,merge_layer | Shared router borrower account can hit Comptroller market-membership cap via permissionless borrow market selection | codex_1:0.644 Shared router account can be market-slot exhausted via permissionless `enterMarkets` calls |
| F-029 | rewritten_agent_signal | Medium | medium | codex_1,merge_layer | Fixed LayerZero receive gas can make valid cross-chain messages unexecutable for large user state | codex_1:0.674 Fixed LayerZero receive gas can make legitimate messages permanently unexecutable |

## Rejection Reasons
- duplicate_or_subsumed: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | Reverting message handlers can amplify single-state mismatch into cross-chain lane DoS | Partially overlaps existing stuck-message findings (e.g., liquidation finalization mismatches/reverts) and over-claims lane-wide blocking without sufficient evidence in this code alone; kept as non-distinct/speculative. |
