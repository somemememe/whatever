# Merge View - Round 11

## Summary
- total findings: 36
- new findings: 4
- updated existing findings: 0
- rejected candidates: 9

## Finding Actions
- existing_preserved: 32
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-034 | rewritten_agent_signal | High | medium | codex_1,merge_layer | Cross-chain borrow finalizes fund transfer before source-chain debt registration | codex_1:0.553 Cross-chain borrow is fail-open when source-side confirmation cannot be applied |
| F-035 | rewritten_agent_signal | Medium | medium | codex_1,merge_layer | Cross-chain repay consumes funds before remote debt mirror is finalized | opencode_1:0.524 Cross-chain repay allows repaying more than borrowed due to index mismatch |
| F-036 | rewritten_agent_signal | Medium | low | codex_1,merge_layer | Repay bookkeeping decrements internal debt by nominal amount instead of actual credited repayment | codex_1:0.55 Repay accounting assumes nominal amount, not actual amount credited by the underlying market |
| F-037 | rewritten_agent_signal | Medium | low | codex_1,merge_layer | Concurrent cross-chain liquidation requests can validate against stale debt and bypass effective close-factor intent | codex_1:0.67 Cross-chain liquidation requests can bypass effective close-factor limits via in-flight concurrency |

## Rejection Reasons
- duplicate_or_subsumed: 4
- factually_incorrect: 1
- other: 1
- trust_or_owner_model: 1
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Single shared router account socializes liquidation risk across unrelated users | Primarily an architectural pooling model observation; no standalone permissionless exploit was shown in `LayerZero/**` without relying on separate accounting bugs already tracked. |
| unsupported_or_speculative | opencode_1 | Cross-chain borrowIndex can be zero causing division revert | Unsupported: `LToken.initialize` sets `borrowIndex` to `1e18`, so normal listed markets do not start at zero. |
| duplicate_or_subsumed | opencode_1 | Liquidation close-factor uses stale principal instead of accrued debt | Duplicate of existing finding F-026. |
| duplicate_or_subsumed | opencode_1 | supply function uses pre-mint exchange rate for accounting | Duplicate of existing finding F-008. |
| trust_or_owner_model | opencode_1 | No access control on claimLend distribution function | Not reportable as stated: `claimLend` transfers accrued tokens to listed holders, not to the caller; unauthorized callers cannot redirect rewards via this path. |
| duplicate_or_subsumed | opencode_1 | Cross-chain liquidation sends amount instead of seizeTokens to collateral chain | Duplicate root cause already captured (notably F-018; related execution-failure effects also covered elsewhere). |
| factually_incorrect | opencode_1 | borrowWithInterestSame divides by zero when borrowIndex is zero | Incorrect: function guards `borrowIndex != 0` and returns zero otherwise; no direct division-by-zero path. |
| duplicate_or_subsumed | opencode_1 | redeem uses stale exchange rate for transfer calculation | Duplicate of existing finding F-021. |
| unsupported_or_speculative | opencode_1 | Cross-chain repay allows repaying more than borrowed due to index mismatch | Insufficiently supported/incomplete candidate; provided path does not demonstrate bypass of `require(repayAmountFinal <= borrowedAmount)`. |
