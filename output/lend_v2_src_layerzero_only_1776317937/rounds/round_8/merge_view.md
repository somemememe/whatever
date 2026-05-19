# Merge View - Round 8

## Summary
- total findings: 26
- new findings: 2
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 24
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-025 | exact_agent_candidate | High | high | codex_1,merge_layer | Cross-chain debt accrual uses local-chain borrow index instead of debt-chain index | codex_1:1.0 Cross-chain debt accrual uses local-chain borrow index instead of debt-chain index |
| F-026 | rewritten_agent_signal | Medium | high | codex_1,merge_layer | Liquidation close-factor cap uses stale principal instead of accrued debt | codex_1:0.594 Liquidation limits are computed from stale principal, not current debt with accrued interest |

## Rejection Reasons
- duplicate_or_subsumed: 5
- other: 2
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | Cross-chain borrow lacks source chain verification allowing stale collateral use | Duplicate of existing F-002 (same stale collateral snapshot/TOCTOU root cause and exploit path). |
| other | opencode_1 | LEND reward claim allows permissionless claim for any address array | Not reportable as fund-theft: claims are transferred to the specified holders, not caller; this is generally permissionless-claim behavior and does not add material harm beyond existing F-014. |
| duplicate_or_subsumed | opencode_1 | Cross-chain repay uses wrong chain identifier for same-chain storage | Substantially overlaps existing F-003/F-017 accounting flaws; no distinct new root cause established. |
| duplicate_or_subsumed | opencode_1 | Cross-chain liquidation failure sends tokens without balance verification | Already captured by F-019 (refund without escrow / failure-path payout mismatch). |
| duplicate_or_subsumed | opencode_1 | Cross-chain repay validates only srcEid without verifying borrow position exists on that chain | Duplicate of existing F-012 (repay lookup keyed only by `srcEid`, ambiguous position selection). |
| trust_or_owner_model | opencode_1 | No access control on authorizedContracts - any authorized caller can modify any user state | Trust-model observation, not a protocol bug by itself; privileged authorized contracts are expected to mutate user state. |
| duplicate_or_subsumed | opencode_1 | Oracle price of zero creates fail-open liquidity check enabling unauthorized borrows | Duplicate of existing F-015 (zero-price fail-open in liquidity checks). |
| other | opencode_1 | Cross-chain liquidation uses seize amount as repayment without verifying actual debt exists | Covered by existing F-013/F-018 liquidation variable misuse; reported scenario depends on the same underlying flaw. |
