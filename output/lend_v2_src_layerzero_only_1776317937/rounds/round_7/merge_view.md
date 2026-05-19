# Merge View - Round 7

## Summary
- total findings: 24
- new findings: 0
- updated existing findings: 0
- rejected candidates: 15

## Finding Actions
- existing_preserved: 24

## New Or Updated Findings
- none

## Rejection Reasons
- duplicate_or_subsumed: 9
- factually_incorrect: 2
- other: 1
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Liquidity checks under-account debt by not accruing interest on all borrowed markets | Not a distinct reportable bug here; this is the protocol’s lazy-accrual accounting model (borrowIndex-based stored state) and no concrete invariant break beyond known design behavior was demonstrated. |
| duplicate_or_subsumed | codex_1 | Same-chain liquidation credits seized collateral without registering liquidator supplied-asset membership | Duplicate of existing F-022. |
| unsupported_or_speculative | codex_1 | Cross-chain liquidation does not validate mapped remote collateral market before dispatch | Insufficiently distinct/protocol-harmful versus existing liquidation breakage and fee-grief findings (F-005, F-006, F-023); missing mapping primarily causes the initiated liquidation flow itself to fail. |
| duplicate_or_subsumed | codex_1 | Hard-reverting receive handlers allow permissionless cross-chain message-lane griefing | Too speculative as a standalone issue because impact depends on deployment-specific ordered-lane semantics; concrete revert-rooted liquidation failures are already captured in existing findings. |
| duplicate_or_subsumed | opencode_1 | borrowForCrossChain bypasses collateral verification entirely | Destination borrow path is gated by CrossChainRouter and collateral checks occur in `_handleBorrowCrossChainRequest`; the real issue is stale snapshot trust, already captured by F-002. |
| factually_incorrect | opencode_1 | Liquidation executes seize before repayment verification completes | Incorrect for same-chain flow: repayment and seize are in one transaction, so seize failure reverts the entire transaction atomically. |
| duplicate_or_subsumed | opencode_1 | LEND rewards claimed without decrementing accrued balance | Duplicate of existing F-014. |
| duplicate_or_subsumed | opencode_1 | supply function uses pre-mint exchange rate vulnerable to atomic front-running | Duplicate of existing F-008. |
| trust_or_owner_model | opencode_1 | setAuthorizedContract allows owner to grant arbitrary contract full storage access | Privileged-admin trust model/governance risk, not a permissionless protocol vulnerability under stated assumptions. |
| factually_incorrect | opencode_1 | withdrawEth uses low-level call without proper error propagation | Factually incorrect: `withdrawEth` checks call result with `require(success, "ETH transfer failed")`. |
| duplicate_or_subsumed | opencode_1 | Cross-chain liquidation health check uses synthetic seize amount as new borrow | Duplicate of existing F-013 (and related F-018 context). |
| duplicate_or_subsumed | opencode_1 | Cross-chain repay incorrectly mutates same-chain borrow storage | Duplicate of existing F-017. |
| duplicate_or_subsumed | opencode_1 | Cross-chain liquidation failure refund lacks prior escrow verification | Duplicate of existing F-019. |
| trust_or_owner_model | opencode_1 | No deadline/timelock on Owner-admin functions enables instant fund movement | Governance/operational hardening suggestion, not a direct in-scope protocol logic vulnerability. |
| duplicate_or_subsumed | opencode_1 | Cross-chain liquidation seize amount used directly as repayment amount | Duplicate of existing F-018. |
