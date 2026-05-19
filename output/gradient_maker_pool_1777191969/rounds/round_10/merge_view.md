# Merge View - Round 10

## Summary
- total findings: 18
- new findings: 0
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- existing_preserved: 18

## New Or Updated Findings
- none

## Rejection Reasons
- duplicate_or_subsumed: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Orderbook token transfers trust nominal amounts, so taxed tokens can leak collateral on every fill | Partially duplicates F-004, which already captures over-crediting on taxed-token receipts through `receiveTokenFromOrderbook`. The new outbound-leg theory is not a separate supported pool-accounting bug for standard fee-on-transfer tokens because the pool’s own balance usually decreases by the full sent amount. |
| duplicate_or_subsumed | codex | Reward balance is never decremented, permanently overstating pool reward solvency | Subsumed by F-011. The stale `rewardBalance` counter is already one mechanism behind the stronger cross-pool reward-drain finding and does not add a distinct protocol-harm path on its own. |
