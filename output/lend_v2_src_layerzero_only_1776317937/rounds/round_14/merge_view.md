# Merge View - Round 14

## Summary
- total findings: 44
- new findings: 2
- updated existing findings: 42
- rejected candidates: 6

## Finding Actions
- exact_agent_candidate: 1
- existing_rewritten: 42
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | existing_rewritten | Critical | high | codex_1,opencode_1 | First-time same-chain borrow bypasses collateral check | opencode_1:0.379 Borrow index comparison inconsistent across chains in collateral authorization |
| F-002 | existing_rewritten | Critical | high | codex_1,opencode_1 | Cross-chain borrow trusts stale source collateral snapshot (TOCTOU) | opencode_1:0.428 Borrow index comparison inconsistent across chains in collateral authorization |
| F-003 | existing_rewritten | Critical | high | codex_1 | Cross-chain debt is excluded from accounting due impossible EID condition | codex_1:0.444 Cross-chain liquidation accepts unmapped seize markets and can emit unprocessable packets |
| F-004 | existing_rewritten | High | high | codex_1,opencode_1 | Source-chain cross-chain debt update drops accrued interest when refreshing borrow index | opencode_1:0.439 Division by zero in distributeBorrowerLend when borrowIndex is zero |
| F-005 | existing_rewritten | Medium | high | codex_1 | Public cross-chain operations are protocol-fee sponsored, enabling native fee griefing | opencode_1:0.388 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-006 | existing_rewritten | Medium | high | codex_1,opencode_1 | Cross-chain liquidation finalization uses inconsistent token identity and impossible lookup parameters | codex_1:0.534 Cross-chain liquidation accepts unmapped seize markets and can emit unprocessable packets |
| F-007 | existing_rewritten | High | high | codex_1,opencode_1 | Cross-chain liquidation seizes collateral before repayment is enforced | opencode_1:0.584 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-008 | existing_rewritten | High | high | codex_1 | Supply accounting over-credits deposits using pre-mint exchange rate | opencode_1:0.308 Liquidation validation uses seize amount instead of actual repay amount for health check |
| F-009 | existing_rewritten | Medium | high | codex_1 | Same-chain liquidation shortfall check re-applies index growth to already-accrued borrow value | opencode_1:0.393 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-010 | existing_rewritten | Medium | high | codex_1 | Cross-chain borrow aggregation can hard-revert when both direction records coexist | opencode_1:0.446 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-011 | existing_rewritten | Medium | high | codex_1 | Unchecked ERC20 `transfer` can update protocol state without actual token payout | codex_1:0.365 Risk checks use stale market state for non-touched assets |
| F-012 | existing_rewritten | Medium | medium | codex_1,opencode_1 | Cross-chain repay lookup is ambiguous and keyed only by srcEid | opencode_1:0.397 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-013 | existing_rewritten | High | medium | merge_layer,opencode_1 | Cross-chain liquidation health check uses seize amount as synthetic new borrow | opencode_1:0.53 Liquidation validation uses seize amount instead of actual repay amount for health check |
| F-014 | existing_rewritten | High | high | codex_1 | LEND rewards can be claimed repeatedly because accrued balances are never decremented | opencode_1:0.286 Protocol seizure rewards are permanently locked with no withdrawal mechanism |
| F-015 | existing_rewritten | High | medium | codex_1,opencode_1 | Liquidity checks accept zero oracle prices, creating fail-open borrow authorization | codex_1:0.371 Risk checks use stale market state for non-touched assets |
| F-016 | existing_rewritten | Medium | low | codex_1 | Borrow/redeem update accounting after external calls, leaving reentrancy window for callback-capable tokens | opencode_1:0.366 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-017 | existing_rewritten | High | high | codex_1,opencode_1 | Cross-chain repay path incorrectly mutates same-chain borrow storage | opencode_1:0.474 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-018 | existing_rewritten | High | high | codex_1 | Cross-chain liquidation uses seized-collateral quantity as debt repayment amount | opencode_1:0.549 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-019 | existing_rewritten | Medium | low | codex_1 | Liquidation-failure refund attempts token payout without prior escrow | opencode_1:0.405 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-020 | existing_rewritten | High | high | codex_1,merge_layer | Borrowed-asset tracking can be cleared while debt still exists, hiding liabilities from liquidity checks | opencode_1:0.297 Borrow index comparison inconsistent across chains in collateral authorization |
| F-021 | existing_rewritten | High | high | codex_1 | Redeem pays users using stale pre-accrual exchange rate, causing systematic underpayment | codex_1:0.359 Risk checks use stale market state for non-touched assets |
| F-022 | existing_rewritten | Medium | high | codex_1,opencode_1 | Liquidation credits seized collateral without registering liquidator supplied-asset membership | opencode_1:0.396 Liquidation validation uses seize amount instead of actual repay amount for health check |
| F-023 | existing_rewritten | Medium | high | codex_1,opencode_1 | Cross-chain liquidation can send unexecutable seize amount and revert on collateral-chain execution | codex_1:0.553 Cross-chain liquidation accepts unmapped seize markets and can emit unprocessable packets |
| F-024 | existing_rewritten | Medium | low | opencode_1,merge_layer | Unbounded per-user asset-set iteration can gas-DoS risk checks and liquidation paths | opencode_1:0.31 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-025 | existing_rewritten | High | high | codex_1,merge_layer | Cross-chain debt accrual uses local-chain borrow index instead of debt-chain index | opencode_1:0.386 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-026 | existing_rewritten | Medium | high | codex_1,merge_layer | Liquidation close-factor cap uses stale principal instead of accrued debt | opencode_1:0.497 Liquidation validation uses seize amount instead of actual repay amount for health check |
| F-027 | existing_rewritten | Medium | medium | codex_1,merge_layer | Cross-chain borrow compares collateral and debt under different chain-local oracle domains | codex_1:0.447 Cross-chain liquidation accepts unmapped seize markets and can emit unprocessable packets |
| F-028 | existing_rewritten | Medium | high | codex_1,merge_layer | Shared router borrower account can hit Comptroller market-membership cap via permissionless borrow market selection | codex_1:0.382 Cross-chain liquidation accepts unmapped seize markets and can emit unprocessable packets |
| F-029 | existing_rewritten | Medium | medium | codex_1,merge_layer | Fixed LayerZero receive gas can make valid cross-chain messages unexecutable for large user state | opencode_1:0.365 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-030 | existing_rewritten | Medium | low | codex_1,merge_layer | Inbound cross-chain handlers hard-revert on state drift, enabling retry-stuck message DoS | opencode_1:0.358 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-031 | existing_rewritten | Low | medium | codex_1,merge_layer | Same-chain liquidation leaves zero-balance collateral markets in borrower supplied-asset set | codex_1:0.486 Cross-chain liquidation accepts unmapped seize markets and can emit unprocessable packets |
| F-033 | existing_rewritten | Low | high | codex_1,merge_layer | Withdrawability helper can revert on zero denominator | codex_1:0.324 Cross-chain liquidation accepts unmapped seize markets and can emit unprocessable packets |
| F-034 | existing_rewritten | High | medium | codex_1,merge_layer | Cross-chain borrow finalizes fund transfer before source-chain debt registration | opencode_1:0.367 Borrow index comparison inconsistent across chains in collateral authorization |
| F-035 | existing_rewritten | Medium | medium | codex_1,merge_layer | Cross-chain repay consumes funds before remote debt mirror is finalized | opencode_1:0.348 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-036 | existing_rewritten | Medium | low | codex_1,merge_layer | Repay bookkeeping decrements internal debt by nominal amount instead of actual credited repayment | opencode_1:0.422 Liquidation validation uses seize amount instead of actual repay amount for health check |
| F-037 | existing_rewritten | Medium | low | codex_1,merge_layer | Concurrent cross-chain liquidation requests can validate against stale debt and bypass effective close-factor intent | codex_1:0.424 Liquidation seize quantity is computed in one chain domain and enforced in another |
| F-038 | existing_rewritten | High | medium | codex_1,merge_layer | Repay flow is reentrant and can erase newly-created debt via stale full-repay snapshot | codex_1:0.322 Risk checks use stale market state for non-touched assets |
| F-040 | existing_rewritten | Medium | high | codex_1,merge_layer | Borrow authorization double-applies borrow-index growth to already-accrued debt value | opencode_1:0.329 Division by zero in distributeBorrowerLend when borrowIndex is zero |
| F-041 | existing_rewritten | Medium | low | codex_1,merge_layer | Cross-chain collateral record matching omits destination market identity, risking index/debt corruption | opencode_1:0.406 Cross-chain liquidation success handler executes repay with incorrect srcEid mapping |
| F-042 | existing_rewritten | Critical | high | codex_1,merge_layer | Cross-chain borrow authorization uses gross source collateral and ignores existing source-chain liabilities | codex_1:0.439 Cross-chain liquidation accepts unmapped seize markets and can emit unprocessable packets |
| F-043 | existing_rewritten | Medium | medium | codex_1,merge_layer | Controller split-brain risk: storage lendtroller is mutable while routers retain stale controller pointers | opencode_1:0.324 Division by zero in distributeBorrowerLend when borrowIndex is zero |
| F-045 | existing_rewritten | Low | high | codex_1,merge_layer | Protocol seizure-share accounting accumulates without an in-scope realization path | opencode_1:0.494 Protocol seizure rewards are permanently locked with no withdrawal mechanism |
| F-046 | exact_agent_candidate | Medium | medium | codex_1,merge_layer | Risk checks use stale market state for non-touched assets | codex_1:1.0 Risk checks use stale market state for non-touched assets |
| F-047 | rewritten_agent_signal | Medium | low | codex_1,merge_layer | Cross-chain liquidation computes seize amount in debt-chain market domain but enforces it on source-chain market | codex_1:0.577 Cross-chain liquidation accepts unmapped seize markets and can emit unprocessable packets |

## Rejection Reasons
- duplicate_or_subsumed: 5
- factually_incorrect: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | Cross-chain liquidation accepts unmapped seize markets and can emit unprocessable packets | Not added as a separate issue: overlaps existing revert-only liquidation execution/finalization failures (notably F-023 and F-006) and does not introduce distinct incremental protocol harm beyond those paths. |
| duplicate_or_subsumed | opencode_1 | Protocol seizure rewards are permanently locked with no withdrawal mechanism | Duplicate of existing F-045 (same root cause and impact class). |
| factually_incorrect | opencode_1 | Division by zero in distributeBorrowerLend when borrowIndex is zero | Premise is generally incorrect for listed initialized markets: `LToken.borrowIndex` is initialized to `1e18` in `LToken.initialize`, so this is not a realistic protocol-level path without separate invalid-market misconfiguration. |
| duplicate_or_subsumed | opencode_1 | Cross-chain liquidation success handler executes repay with incorrect srcEid mapping | Subsumed by existing F-006; the concrete blocker is the impossible collateral lookup parameters/token identity mismatch, which already captures deterministic finalize failure. |
| duplicate_or_subsumed | opencode_1 | Borrow index comparison inconsistent across chains in collateral authorization | Duplicate/overlap with existing F-003 (impossible EID filter excludes debt) and F-025 (wrong index domain for cross-chain accrual). |
| duplicate_or_subsumed | opencode_1 | Liquidation validation uses seize amount instead of actual repay amount for health check | Duplicate of existing F-013. |
