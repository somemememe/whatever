# Merge View - Round 6

## Summary
- total findings: 21
- new findings: 2
- updated existing findings: 1
- rejected candidates: 16

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 18
- existing_rewritten: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-011 | existing_rewritten | Medium | medium | codex_1,opencode_1 | Refund key collisions can overwrite entries or block later refund recording | codex_1:0.523 Refund-slot collision on `externalId` can block later revert/abort refunds |
| F-023 | rewritten_agent_signal | Medium | medium | codex_1,opencode_1 | Exact-output Uniswap approval pattern can DoS strict-approve tokens | codex_1:0.689 Exact-output Uniswap flow can leave residual allowance and DoS strict-approve tokens |
| F-024 | exact_agent_candidate | Low | high | codex_1 | ETH `depositAndCall` overload ignores `amount` and forwards full `msg.value` | codex_1:0.94 ETH `depositAndCall` overload ignores `amount` and bridges full `msg.value` |

## Rejection Reasons
- duplicate_or_subsumed: 5
- factually_incorrect: 2
- other: 9

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | Swap return value is trusted without balance-delta validation | Overlaps existing reserve-drain findings (F-001/F-005/F-009/F-010/F-018); as written it depends on a misbehaving swap router and does not add a distinct exploitable root cause. |
| other | codex_1 | Missing revert-message length guards can revert callback handlers | Current protocol-generated revert messages are >=32 bytes; short-message failure requires atypical external misuse of these contracts as revert targets and does not show meaningful protocol-level exploitability. |
| other | codex_1 | `claimRefund` emits cleared values after deleting storage | Informational event-quality issue only; no direct fund-loss, theft, lockup, or DoS impact. |
| other | codex_1 | Refund entry at `externalId == 0x0` is unclaimable | Relies on non-standard zero externalId callback payloads; normal protocol paths derive non-zero IDs, so impact is largely self-inflicted and low practical risk. |
| factually_incorrect | opencode_1 | GatewaySend.onCall returns incorrect success value causing callback failure | Claim is based on an incorrect interface assumption and does not demonstrate an actual failing execution path in this codebase. |
| other | opencode_1 | GatewaySend.onCall does not validate fromToken transfer quantity | Already covered by existing amount/token trust and transfer-accounting findings (F-005/F-001). |
| duplicate_or_subsumed | opencode_1 | GatewaySend.depositAndCall does not use swapData for output token calculation | Duplicate of the existing asset-binding failure in F-010. |
| duplicate_or_subsumed | opencode_1 | GatewaySend._doMixSwap missing validation for fromToken amount | Duplicate of F-001 (attacker-controlled `fromTokenAmount` and token source mismatch). |
| other | opencode_1 | GatewaySend depositAndCall lacks slippage protection for swap output | Slippage constraints are user-specified in swap params (`minReturnAmount`); this is not a distinct protocol security bug. |
| other | opencode_1 | GatewayTransferNative.onCall fee calculation uses input amount not output amount | Economic/fee-policy concern, not a standalone exploit enabling theft, insolvency, lockup, or permissionless DoS. |
| duplicate_or_subsumed | opencode_1 | GatewayTransferNative withdraw function is public not internal | Already captured in accumulated finding F-008. |
| other | opencode_1 | GatewayTransferNative.withdrawToNativeChain allows arbitrary recipient addresses without validation | Receiver bytes are intentionally user-provided for multi-chain formats; invalid values are user-input risk and already covered where truncation causes loss (F-013/F-003). |
| duplicate_or_subsumed | opencode_1 | GatewayCrossChain._swapAndSendERC20Tokens calculates amountInMax with slippage on quote not actual | Standard exact-output quoting behavior; no distinct exploit beyond already captured allowance/residual and liveness issues. |
| other | opencode_1 | GatewayCrossChain onCall does not validate message length before decoding | Malformed payloads revert; no credible permissionless protocol-harm path beyond rejecting invalid input. |
| factually_incorrect | opencode_1 | GatewayCrossChain claimRefund allows anyone to claim if walletAddress is 20 bytes and caller is bot | Incorrect: for 20-byte wallet addresses payout goes to decoded receiver, not the bot caller. |
| other | opencode_1 | SwapDataHelperLib.decodeCompressedMixSwapParams has unchecked arithmetic in offset calculations | No practical overflow/memory-corruption path shown; out-of-bounds calldata slicing reverts safely under Solidity bounds checks. |
