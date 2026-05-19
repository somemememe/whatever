# Merge View - Round 3

## Summary
- total findings: 17
- new findings: 4
- updated existing findings: 0
- rejected candidates: 11

## Finding Actions
- existing_preserved: 13
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-014 | rewritten_agent_signal | High | medium | codex_1 | GatewaySend direct ERC20 source deposit uses nominal amount and can spend reserves on underfunded transfer-in | codex_1:0.758 GatewaySend source ERC20 flow uses nominal input amount and can spend reserve balances on underfunded deposits |
| F-015 | rewritten_agent_signal | Medium | high | codex_1 | GatewaySend destination finalizes success even when ERC20 payout transfer fails softly | opencode_1:0.47 Gas stipend limitation in refund ETH transfers |
| F-016 | rewritten_agent_signal | Low | high | codex_1 | GatewaySend ETH payout uses `.transfer` and can DoS smart-contract recipients | codex_1:0.756 ETH payouts use `.transfer` (2300 gas) and can be DoS'd for contract recipients |
| F-017 | rewritten_agent_signal | High | high | codex_1 | GatewaySend revert handler lacks native-asset refund path and can strand reverted ETH | codex_1:0.78 GatewaySend revert handler has no native-asset refund branch and may fail ETH revert payouts |

## Rejection Reasons
- duplicate_or_subsumed: 2
- factually_incorrect: 1
- low_impact_or_operational: 1
- other: 6
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | GatewaySend destination `onCall` ignores `transferFrom` result and continues as if funds were received | Duplicate of existing F-005, which already covers untrusted payload accounting plus ignored ERC20 transferFrom result in `GatewaySend.onCall`. |
| low_impact_or_operational | codex_1 | Unbounded receiver bytes are persisted in refund records, enabling revert-callback gas exhaustion | Not reportable as stated: upstream gateway enforces message/revert size caps, and no concrete protocol-wide gas-exhaustion path was substantiated. |
| other | codex_1 | GatewayTransferNative exposes an ETH-sentinel path in `withdrawToNativeChain` that reverts at fee transfer | Subset/variant of existing F-004 (underfunded sentinel path draining reserves); separate liveness framing is not distinct root cause. |
| other | opencode_1 | Missing deadline validation in GatewaySend swap execution | `_doMixSwap` forwards deadline to DODO router, which is expected to enforce it; no independent deadline bypass was demonstrated in this code. |
| other | opencode_1 | No minimum output amount enforcement on source-chain swaps | `minReturnAmount` is part of user-supplied swap params and enforced by the downstream swap; absence of extra wrapper checks is not a standalone vulnerability. |
| other | opencode_1 | Out-of-bounds calldata read in decodePackedMessage | Malformed length fields cause a revert on that call path rather than exploitable memory corruption or cross-user fund impact. |
| other | opencode_1 | Predictable externalId enables front-running on source chains | `externalId` is an identifier/event key, not an authorization primitive; predictability does not create direct theft or protocol manipulation by itself. |
| factually_incorrect | opencode_1 | Gas stipend limitation in refund ETH transfers | Factually incorrect: `TransferHelper.safeTransferETH` uses `.call` without a 2300-gas stipend limit. |
| duplicate_or_subsumed | opencode_1 | Missing access control on GatewayTransferNative.withdraw function | Already captured by existing F-008, where exploitability depends on residual gateway allowances and contract balances. |
| trust_or_owner_model | opencode_1 | Platform fee can be set to zero enabling free withdrawals | Governance/owner-configurable economic parameter, not a security flaw in permissioning or accounting. |
| other | opencode_1 | Incorrect amountIn calculation in swap finalization | The cited check is conservative and may only over-revert in edge cases; no realistic theft, insolvency, or permissionless DoS exploit was shown. |
