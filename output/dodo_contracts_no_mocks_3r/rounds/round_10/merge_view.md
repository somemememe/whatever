# Merge View - Round 10

## Summary
- total findings: 21
- new findings: 1
- updated existing findings: 1
- rejected candidates: 8

## Finding Actions
- existing_preserved: 19
- existing_support_added: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-025 | existing_support_added | Low | high | codex_1,opencode_1 | GatewayTransferNative refund-claimed event emits zero token/amount due to storage read after delete | opencode_1:0.581 GatewayTransferNative claimRefund reads storage after delete risking zero amount |
| F-031 | rewritten_agent_signal | Low | high | codex_1,merge_reviewer | Same-token WZETA payouts skip unwrap and deliver wrapped tokens instead of native ZETA | codex_1:0.704 Same-token WZETA payouts skip the unwrap path and deliver the wrong asset |

## Rejection Reasons
- duplicate_or_subsumed: 3
- factually_incorrect: 1
- other: 3
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex_1 | Receive-side callbacks spend nominal amounts instead of actual received balances | Not supported for the ZEVM handlers because `GatewayZEVM.depositAndCall` mints/deposits the exact ZRC20 amount to the target before `onCall`; the `GatewaySend` portion is also masked by F-026 because authenticated deliveries fully revert at the ABI boundary. |
| duplicate_or_subsumed | codex_1 | Native-input withdrawals can bypass platform fees during swap execution | Duplicate of F-004, which already captures the native-input fee-accounting bypass and full-`msg.value` swap spend on `withdrawToNativeChain`. |
| other | codex_1 | GatewaySend silently treats failed ERC20 payouts as successful | Masked by F-026: `GatewaySend.onCall` currently reverts at the gateway ABI boundary, so silent ERC20 `transfer` false-returns cannot persist in the deployed flow. |
| other | codex_1 | ETH payouts use 2300-gas transfer and can DoS contract recipients | Masked by F-026: the `GatewaySend.onCall` path is already bricked, so this payout behavior is not independently reachable in the current code. |
| factually_incorrect | opencode_1 | GatewaySend onCall allows arbitrary token amount from user-provided allowance | Incorrect root cause: `GatewaySend.onCall` pulls from the gateway, not from end users, and only receives whatever allowance/balance the gateway execution provides; the path is also already bricked by F-026. |
| other | opencode_1 | GatewaySend externalId uses block.timestamp which can be manipulated by validators | Not reportable: `externalId` also includes contract address, sender, and a monotonic nonce, so minor timestamp skew does not create a realistic collision or theft path. |
| duplicate_or_subsumed | opencode_1 | GatewayTransferNative.withdraw lacks access control and is publicly callable | Duplicate of F-008, which already keeps the only supported exploit condition: abuse of the public `withdraw` entrypoint when residual gateway allowance remains. |
| duplicate_or_subsumed | opencode_1 | GatewayTransferNative claimRefund reads storage after delete risking zero amount | Duplicate of F-025; incorporated by adding `opencode_1` as supporting source for the existing event-integrity finding. |
