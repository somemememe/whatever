# Merge View - Round 7

## Summary
- total findings: 7
- new findings: 0
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- existing_preserved: 7

## New Or Updated Findings
- none

## Rejection Reasons
- duplicate_or_subsumed: 2
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Any single liquidation failure reverts the entire recovery and freezes unrelated assets | Rejected as duplicative of existing DoS findings. The contract is atomic by design; the reportable risk comes from concrete failure sources already captured in F-005 and F-009 rather than the generic fact that one reverting liquidation rolls back the transaction. |
| duplicate_or_subsumed | codex | Ignored `startPool`/`endPool` results allow false-positive recovery executions | Rejected as subsumed by F-007. Ignoring the low-level call results only becomes harmful because the profit gate can be satisfied with preloaded assets; that false-positive execution path is already covered by the existing finding. |
| other | codex | Counter state is fully attacker-controlled | Rejected as non-reportable in this context. `Counter.sol` is a trivial standalone sample contract with intentionally public mutators, and no protocol asset, privilege, or integration-dependent harm is evidenced in the repository. |
