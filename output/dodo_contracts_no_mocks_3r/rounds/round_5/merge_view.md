# Merge View - Round 5

## Summary
- total findings: 19
- new findings: 0
- updated existing findings: 2
- rejected candidates: 11

## Finding Actions
- existing_preserved: 17
- existing_rewritten: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | existing_rewritten | Critical | high | codex_1 | User-controlled swap params can spend arbitrary token balances held by gateway contracts | codex_1:0.33 GatewayTransferNative onCall uses pre-fee amount for swap path, letting users externalize fees to reserves |
| F-011 | existing_rewritten | Medium | medium | codex_1,opencode_1 | Refund records can be overwritten in callback handlers | codex_1:0.377 GatewaySend.onCall returns 0x00000000 success code, risking callback status mismatch |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 8
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Revert callback handlers trust revertMessage length and can self-revert on malformed payloads | Protocol-generated revert messages in these paths always include at least the 32-byte externalId; the short-message condition requires malformed trusted-gateway input and is not a realistic standalone exploit. |
| unsupported_or_speculative | codex_1 | GatewaySend.onCall returns 0x00000000 success code, risking callback status mismatch | No gateway-side magic return-value check was identified; claim is speculative and does not show a concrete inconsistent-finality exploit. |
| other | codex_1 | onCall handlers do not authenticate source contract/chain in MessageContext | These endpoints are permissionless by design; absence of source allowlisting is not independently exploitable beyond already-reported payload/accounting validation bugs. |
| other | codex_1 | GatewayTransferNative.claimRefund emits zeroed token/amount after deleting storage | Valid informational logging defect, but no direct fund-loss, theft, insolvency, or liveness impact. |
| duplicate_or_subsumed | opencode_1 | Slippage parameter is configurable but never enforced on swaps | Incorrect: slippage feeds `amountInMax` for `swapTokensForExactTokens`; a separate post-check bug is already captured in F-022. |
| other | opencode_1 | GatewaySend.depositAndCall lacks slippage and minimum output validation | The DODO router call includes and enforces `minReturnAmount`; no missing-min-output exploit was demonstrated. |
| trust_or_owner_model | opencode_1 | Platform fee can be set to zero, enabling owner fund extraction | Setting fee to zero is a governance/configuration choice, not a concrete exploit path. |
| other | opencode_1 | GatewaySend.onCall lacks access control allowing anyone to drain user tokens | Mischaracterized: `onCall` is `onlyGateway`; stated arbitrary-caller path is invalid. |
| other | opencode_1 | GatewayTransferNative.withdrawToNativeChain uses nominal amount for fee calculation before swap | Charging fee on input amount is explicit fee policy, not a security vulnerability by itself. |
| other | opencode_1 | GatewayCrossChain.onCall deducts platform fee before swap, reducing swap efficiency | Economic design preference, not a protocol-security bug. |
| other | opencode_1 | GatewaySend.depositAndCall does not bind output token to destination chain asset | As stated, this is primarily a user-input/supportability issue; reserve-drain consequences from asset/output mismatch are already covered by F-010. |
