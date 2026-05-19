# Merge View - Round 2

## Summary
- total findings: 13
- new findings: 5
- updated existing findings: 7
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 3
- existing_preserved: 1
- existing_rewritten: 7
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | existing_rewritten | Critical | high | codex_1 | User-controlled swap params can spend arbitrary token balances held by gateway contracts | codex_1:0.44 GatewayCrossChain empty-swap path allows withdrawing arbitrary target token without conversion |
| F-002 | existing_rewritten | Critical | high | codex_1 | Refunds for non-20-byte recipients are claimable by anyone | codex_1:0.372 Recipient bytes are truncated/padded into EVM addresses in payout paths |
| F-003 | existing_rewritten | High | high | codex_1 | Bitcoin/non-EVM revert recipient is truncated to 20 bytes, misdirecting refunds | codex_1:0.453 Recipient bytes are truncated/padded into EVM addresses in payout paths |
| F-004 | existing_rewritten | Critical | high | codex_1 | withdrawToNativeChain trusts nominal input amount and can execute underfunded withdrawals from contract reserves | codex_1:0.823 withdrawToNativeChain trusts nominal deposit amount/token and can execute underfunded withdrawals |
| F-005 | existing_rewritten | Critical | high | codex_1 | GatewaySend destination onCall trusts payload amount/token data and can drain contract reserves | codex_1:0.47 GatewaySend destination execution ignores ERC20 transfer success values |
| F-007 | existing_rewritten | Medium | medium | codex_1 | Balance-based pair existence check can be dust-poisoned into swap-path DoS | codex_1:0.384 GatewaySend source flow does not bind swap output asset to bridged asset |
| F-008 | existing_rewritten | Medium | low | codex_1 | Public `withdraw` can be abused when residual gateway allowances remain | opencode_1:0.336 No deadline enforcement allows Stuck stale swaps |
| F-009 | rewritten_agent_signal | Critical | high | codex_1 | Empty `swapDataZ` path allows cross-asset withdrawals without performing conversion | codex_1:0.565 GatewayCrossChain empty-swap path allows withdrawing arbitrary target token without conversion |
| F-010 | rewritten_agent_signal | Critical | high | codex_1 | GatewaySend source flow does not bind bridged asset to swap output asset | codex_1:0.764 GatewaySend source flow does not bind swap output asset to bridged asset |
| F-011 | exact_agent_candidate | Medium | low | codex_1,opencode_1 | GatewayTransferNative refund records are overwriteable for the same externalId | codex_1:1.0 GatewayTransferNative refund records are overwriteable for the same externalId |
| F-012 | exact_agent_candidate | Medium | high | codex_1 | AccountEncoder.decompressAccounts builds invalid memory layout for `Account[]` | codex_1:0.987 AccountEncoder.decompressAccounts builds invalid memory layout for Account[] |
| F-013 | exact_agent_candidate | Medium | medium | codex_1 | Recipient bytes are silently truncated/padded into EVM addresses in payout paths | codex_1:0.94 Recipient bytes are truncated/padded into EVM addresses in payout paths |

## Rejection Reasons
- factually_incorrect: 1
- other: 5
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | withdrawToNativeChain trusts nominal deposit amount/token and can execute underfunded withdrawals | Merged into existing F-004 as a broader underfunded-input variant (ETH-sentinel bypass plus nominal-amount accounting). |
| other | codex_1 | GatewaySend destination execution ignores ERC20 transfer success values | Merged into F-005; unchecked transfer results are one mechanism of the broader reserve-drain issue. |
| unsupported_or_speculative | opencode_1 | Fee calculation error in _swapAndSendERC20Tokens approves wrong amount leading to potential token theft | As written, excess-theft path is unsupported: gateway spending uses actual swap input (`amounts[0]`) approvals; mismatch primarily causes conservative reverts, not over-withdrawal theft. |
| other | opencode_1 | Missing slippage protection and minReturnAmount validation in swap operations | `minReturnAmount`/`deadline` are passed into external swap routers that enforce them; user-chosen trade parameters are not a protocol-level vulnerability by themselves. |
| other | opencode_1 | Unchecked externalId collision in revert/abort handlers causes refund overwrite | Overbroad as written: GatewayCrossChain now blocks overwrite (`REFUND_INFO_ALREADY_EXISTS`); only GatewayTransferNative side is retained as F-011. |
| factually_incorrect | opencode_1 | GatewayCrossChain claimRefund deletes refundInfo after transfer allowing reentrancy via callback | Incorrect for current code: GatewayCrossChain `claimRefund` deletes storage before external transfer, preventing same-entry reentrancy payout. |
| other | opencode_1 | Missing destination chain (dstChainId) validation allows routing to invalid chains | `dstChainId` is not the primary routing primitive for token withdrawal in these paths; invalid values mainly change branch behavior and lead to reverts/refunds, not direct exploitable asset loss. |
| unsupported_or_speculative | opencode_1 | No deadline enforcement allows stale swaps | Unsupported: deadline is forwarded to swap routers, where expiry checks are expected to occur. |
