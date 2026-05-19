# Merge View - Round 2

## Summary
- total findings: 13
- new findings: 7
- updated existing findings: 1
- rejected candidates: 9

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 5
- existing_support_added: 1
- merge_synthesized: 1
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-006 | existing_support_added | Medium | high | codex_1,opencode_1 | Cross-chain liquidation finalization uses inconsistent token identity and impossible lookup parameters | opencode_1:0.575 Cross-chain liquidation success handler uses incorrect EID parameter for lookup |
| F-007 | exact_agent_candidate | High | high | codex_1 | Cross-chain liquidation seizes collateral before repayment is enforced | codex_1:0.915 Cross-chain liquidation seizes collateral before repayment is guaranteed |
| F-008 | exact_agent_candidate | High | high | codex_1 | Supply accounting over-credits deposits using pre-mint exchange rate | codex_1:0.938 Supply accounting over-credits deposits by using pre-mint stale exchange rate |
| F-009 | rewritten_agent_signal | Medium | high | codex_1 | Same-chain liquidation shortfall check re-applies index growth to already-accrued borrow value | codex_1:0.731 Same-chain liquidation shortfall check double-applies borrow index growth |
| F-010 | rewritten_agent_signal | Medium | high | codex_1 | Cross-chain borrow aggregation can hard-revert when both direction records coexist | codex_1:0.571 Cross-chain debt accounting can be permanently DoSed when both borrow/collateral arrays exist |
| F-011 | rewritten_agent_signal | Medium | high | codex_1 | Unchecked ERC20 `transfer` can update protocol state without actual token payout | codex_1:0.675 Unchecked ERC20 `transfer` usage can create debt/withdrawal without payout |
| F-012 | rewritten_agent_signal | Medium | medium | codex_1 | Cross-chain repay lookup is ambiguous and keyed only by srcEid | opencode_1:0.468 Cross-chain collateral update loses precision on index refresh |
| F-013 | merge_synthesized | High | medium | merge_layer | Cross-chain liquidation health check uses seize amount as synthetic new borrow | codex_1:0.547 Cross-chain liquidation seizes collateral before repayment is guaranteed |

## Rejection Reasons
- low_impact_or_operational: 2
- other: 4
- unsupported_or_speculative: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing reentrancy guards on critical entry points | Generic missing-guard observation without a concrete reentrant path to protocol-level fund loss; ERC20 calls shown do not by themselves demonstrate exploitable reentrancy here. |
| other | opencode_1 | Cross-chain liquidation validation can be front-run on destination chain | This is normal liquidation competition behavior, not a protocol integrity bug; no unique exploit against protocol funds/state was shown. |
| low_impact_or_operational | opencode_1 | No minimum liquidation amount check enables dust attacks | No realistic protocol-level harm beyond optional gas inefficiency; dust liquidations are generally permissible design choices. |
| unsupported_or_speculative | opencode_1 | Repay functions trust caller approval without verification | `safeTransferFrom` already enforces allowance/balance by reverting atomically; claimed partial-state inconsistency is not supported. |
| other | opencode_1 | borrowForCrossChain transfers tokens before recording borrow position | In this flow, later failures revert the full transaction (including the subcall token transfer), so no persistent no-debt payout window was validated. |
| other | opencode_1 | getHypotheticalAccountLiquidityCollateral may double-count same-chain and cross-chain borrows | Summing same-chain and cross-chain debts is expected when both exist; candidate did not show actual same-debt duplication in storage semantics. |
| unsupported_or_speculative | opencode_1 | Cross-chain collateral update loses precision on index refresh | Integer truncation dust from standard fixed-point division is minimal and not shown to create material exploitability beyond negligible rounding. |
| unsupported_or_speculative | opencode_1 | borrowCrossChain allows zero-value LayerZero messages due to check order | Claim is not supported by code path; borrow amount must be non-zero and message fee/gas handling is not tied to borrow amount in the alleged way. |
| low_impact_or_operational | opencode_1 | withdrawEth lacks event logging for accounting transparency | Operational observability issue only; not a reportable security vulnerability under protocol-harm criteria. |
