# Merge View - Round 6

## Summary
- total findings: 24
- new findings: 4
- updated existing findings: 1
- rejected candidates: 6

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 19
- existing_support_added: 1
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-015 | existing_support_added | High | medium | codex_1,opencode_1 | Liquidity checks accept zero oracle prices, creating fail-open borrow authorization | opencode_1:0.395 Oracle price returns zero without revert, creating silent liquidity bypass |
| F-021 | exact_agent_candidate | High | high | codex_1 | Redeem pays users using stale pre-accrual exchange rate, causing systematic underpayment | codex_1:1.0 Redeem pays users using stale pre-accrual exchange rate, causing systematic underpayment |
| F-022 | exact_agent_candidate | Medium | high | codex_1,opencode_1 | Liquidation credits seized collateral without registering liquidator supplied-asset membership | codex_1:0.867 Liquidation seizes collateral into accounting without registering liquidator supplied-asset membership |
| F-023 | rewritten_agent_signal | Medium | high | codex_1,opencode_1 | Cross-chain liquidation can send unexecutable seize amount and revert on collateral-chain execution | opencode_1:0.541 Cross-chain liquidation execute fails silently and sends incorrect failure message |
| F-024 | rewritten_agent_signal | Medium | low | opencode_1,merge_layer | Unbounded per-user asset-set iteration can gas-DoS risk checks and liquidation paths | opencode_1:0.447 User-supplied asset iteration may cause out-of-gas for users with many assets |

## Rejection Reasons
- duplicate_or_subsumed: 3
- other: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | Reentrancy vulnerability in claimLEND function allows double extraction | Non-distinct and low value: reward-drain root cause is already captured by F-014 (accrued rewards never decremented), and the reentrancy precondition depends on a malicious callback-capable LEND token. |
| other | opencode_1 | Division by zero when borrowIndex is zero in cross-chain borrow handler | No concrete reachable path shown in protocol flow: cross-chain borrow records are initialized/updated with current market borrowIndex, so zero-index division appears to require corrupted state outside normal execution. |
| duplicate_or_subsumed | opencode_1 | Oracle price returns zero without revert, creating silent liquidity bypass | Duplicate of existing F-015. |
| other | opencode_1 | Cross-chain liquidation execute fails silently and sends incorrect failure message | Covered by existing liquidation-path findings (F-007, F-018, F-019); candidate combines multiple already-reported issues without a distinct new root cause. |
| duplicate_or_subsumed | opencode_1 | Cross-chain repay does not verify srcEid validity before processing | Largely a duplicate/reframing of existing repayment-record selection ambiguity in F-012; incorrect `_srcEid` input naturally reverts and is not a separate exploit primitive. |
| other | opencode_1 | No deadline checks on cross-chain operations allowing stale execution | General design concern without distinct exploit path beyond already-captured stale-snapshot TOCTOU risk in F-002. |
