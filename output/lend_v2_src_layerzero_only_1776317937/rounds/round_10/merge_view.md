# Merge View - Round 10

## Summary
- total findings: 32
- new findings: 3
- updated existing findings: 0
- rejected candidates: 11

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 29
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-030 | exact_agent_candidate | Medium | low | codex_1,merge_layer | Inbound cross-chain handlers hard-revert on state drift, enabling retry-stuck message DoS | codex_1:0.91 Inbound cross-chain handlers hard-revert on state drift, enabling route-level message DoS |
| F-031 | rewritten_agent_signal | Low | medium | codex_1,merge_layer | Same-chain liquidation leaves zero-balance collateral markets in borrower supplied-asset set | codex_1:0.62 Same-chain liquidation does not clear fully-seized collateral market membership |
| F-033 | exact_agent_candidate | Low | high | codex_1,merge_layer | Withdrawability helper can revert on zero denominator | codex_1:1.0 Withdrawability helper can revert on zero denominator |

## Rejection Reasons
- duplicate_or_subsumed: 4
- factually_incorrect: 1
- low_impact_or_operational: 1
- other: 1
- trust_or_owner_model: 2
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | Cross-chain borrow does not re-validate collateral at execution on destination chain | Duplicate of existing F-002 (stale collateral snapshot / TOCTOU). |
| duplicate_or_subsumed | opencode_1 | Cross-chain liquidation validates health AFTER message sent, causing stale execution | Not a distinct new root cause; stale/liquidation-data issues are already captured (F-013/F-018), and the write-up misstates current execution checks. |
| duplicate_or_subsumed | opencode_1 | Same-chain borrow calculation rounds to zero enabling collateral bypass | Insufficient code support for the claimed rounding-to-zero path; major borrow bypass already captured by F-001. |
| factually_incorrect | opencode_1 | Full repayment clears borrow records before verifying repay success | Factually incorrect ordering: external repay is required first (`repayBorrow` at line 490), then storage removal occurs. |
| duplicate_or_subsumed | opencode_1 | Supply uses stale exchange rate for lToken calculation allowing underminting | Duplicate root cause of existing F-008 (stale pre-mint exchange rate accounting mismatch). |
| unsupported_or_speculative | opencode_1 | Cross-chain liquidation doesn't verify collateral chain liquidity before sending | Claim unsupported: seize path updates internal accounting, not collateral-chain token cash transfers requiring liquidity precheck. |
| other | opencode_1 | borrowForCrossChain missing zero address validation for borrower | Low-value/unreachable in normal trusted-message flow; borrower is sourced from initiating user address, not arbitrary zero address. |
| unsupported_or_speculative | opencode_1 | repayBorrow accepts any lToken without underlying existence validation | Unsupported-loss claim: invalid token address paths revert during SafeERC20 call execution rather than silently losing funds. |
| low_impact_or_operational | opencode_1 | LiquidateSeizeUpdate doesn't return actual seized amount to liquidator | Not a security vulnerability; observability/API ergonomics only. |
| trust_or_owner_model | opencode_1 | Constructors accept any storage/oracle without contract validation | Deployment-time trust/admin configuration concern, not a protocol runtime exploit under normal governance assumptions. |
| trust_or_owner_model | codex_1 | Cross-chain liquidation message can be built with zero destination lToken and guaranteed fail on receiver | Primarily owner/mapping misconfiguration hardening issue; lacks a strong permissionless exploit path beyond self-failing operations. |
