# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 0
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- existing_preserved: 2

## New Or Updated Findings
- none

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Reentrancy across `withdraw()` and `deposit()` lets a callback token drain the same pool repeatedly | Not a standalone issue here. `withdraw()` already deducts balance before the external call, so there is no same-balance double-withdraw against honest tokens. The proposed loop still relies on the same malicious/soft-failing token behavior already captured by F-001, making it derivative rather than incremental protocol risk. |
| other | codex | Anyone can permissionlessly create staking markets for arbitrary attacker-controlled tokens | Permissionless token/epoch initialization alone is not sufficient harm. Any loss path still depends on the unsafe token-transfer assumptions already covered by F-001/F-003, and no cross-pool or unavoidable harm beyond the attacker-chosen token market is shown. |
