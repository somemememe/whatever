# Merge View - Round 9

## Summary
- total findings: 20
- new findings: 1
- updated existing findings: 18
- rejected candidates: 14

## Finding Actions
- existing_preserved: 1
- existing_rewritten: 18
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | existing_rewritten | Critical | high | codex_1 | User-controlled swap params can spend arbitrary token balances held by gateway contracts | opencode_1:0.367 onRevert uses .transfer for ETH which can DoS smart contract receivers |
| F-002 | existing_rewritten | Critical | high | codex_1 | Refunds for non-20-byte recipients are claimable by anyone | opencode_1:0.342 External call to DODORouteProxy lacks reentrancy protection |
| F-003 | existing_rewritten | High | high | codex_1 | Bitcoin/non-EVM revert recipient is truncated to 20 bytes, misdirecting refunds | opencode_1:0.336 No event emitted for critical withdrawToNativeChain state change |
| F-004 | existing_rewritten | Critical | high | codex_1 | withdrawToNativeChain trusts nominal input amount and can execute underfunded withdrawals from contract reserves | codex_1:0.46 GatewaySend destination settlement trusts nominal ERC20 pull amounts and can spend reserves on taxed or soft-failing tokens |
| F-007 | existing_rewritten | Medium | medium | codex_1 | Balance-based pair existence check can be dust-poisoned into swap-path DoS | opencode_1:0.403 No deadline check in Uniswap swap allowing stale trades |
| F-008 | existing_rewritten | Medium | low | codex_1,opencode_1 | Public `withdraw` can be abused when residual gateway allowances remain | opencode_1:0.365 Public withdraw function in GatewayTransferNative lacks access control and can be abused |
| F-009 | existing_rewritten | Critical | high | codex_1 | Empty `swapDataZ` path allows cross-asset withdrawals without performing conversion | opencode_1:0.367 No event emitted for critical withdrawToNativeChain state change |
| F-010 | existing_rewritten | Critical | high | codex_1 | GatewaySend source flow does not bind bridged asset to swap output asset | opencode_1:0.532 GatewaySend depositAndCall does not verify swap output or return funds on swap failure |
| F-011 | existing_rewritten | Medium | high | codex_1,opencode_1 | Refund key collisions and zero-key handling can overwrite entries, block recording, or lock refunds | opencode_1:0.389 Platform fee calculation ignores token decimals causing severe undercharging |
| F-012 | existing_rewritten | Medium | high | codex_1 | AccountEncoder.decompressAccounts builds invalid memory layout for `Account[]` | opencode_1:0.375 Message decoding lacks bounds checking allowing out-of-bounds read |
| F-013 | existing_rewritten | Medium | medium | codex_1 | Recipient bytes are silently truncated or padded into EVM addresses in the local payout path | opencode_1:0.321 No event emitted for critical withdrawToNativeChain state change |
| F-014 | existing_rewritten | High | medium | codex_1 | GatewaySend direct ERC20 source deposit uses nominal amount and can spend reserves on underfunded transfer-in | codex_1:0.603 GatewaySend destination settlement trusts nominal ERC20 pull amounts and can spend reserves on taxed or soft-failing tokens |
| F-017 | existing_rewritten | High | high | codex_1 | GatewaySend revert handler lacks native-asset refund path and can strand reverted ETH | codex_1:0.477 GatewayTransferNative local-delivery swaps spend the pre-fee amount and can siphon reserves |
| F-018 | existing_rewritten | Critical | high | codex_1 | Swap output asset is not bound to target payout token before withdrawal/transfer | opencode_1:0.387 GatewaySend onCall uses message amount instead of actual token balance |
| F-022 | existing_rewritten | Medium | medium | codex_1 | `amountInMax`-based post-swap check can cause avoidable withdrawal reverts | opencode_1:0.434 No deadline check in Uniswap swap allowing stale trades |
| F-023 | existing_rewritten | Medium | medium | codex_1,opencode_1 | Exact-output Uniswap approval pattern can DoS strict-approve tokens | opencode_1:0.426 No deadline check in Uniswap swap allowing stale trades |
| F-024 | existing_rewritten | Low | high | codex_1,merge_reviewer | GatewaySend ETH input flows ignore `amount` and consume full `msg.value` | opencode_1:0.465 GatewaySend onCall uses message amount instead of actual token balance |
| F-025 | existing_rewritten | Low | high | codex_1 | GatewayTransferNative refund-claimed event emits zero token/amount due to storage read after delete | opencode_1:0.518 GatewayTransferNative.claimRefund reads storage after delete allowing double-claim with reentrancy |
| F-026 | rewritten_agent_signal | High | high | merge_reviewer | GatewaySend `onCall` return type is ABI-incompatible with ZetaChain `Callable` | opencode_1:0.427 GatewaySend depositAndCall does not verify swap output or return funds on swap failure |

## Rejection Reasons
- duplicate_or_subsumed: 2
- low_impact_or_operational: 1
- other: 9
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | GatewayTransferNative local-delivery swaps spend the pre-fee amount and can siphon reserves | Merged into existing F-001; this is the already-accepted pre-fee branch of the broader attacker-controlled swap-parameter reserve-drain issue. |
| other | codex_1 | GatewaySend destination settlement trusts nominal ERC20 pull amounts and can spend reserves on taxed or soft-failing tokens | Not kept separately because authenticated `GatewaySend.onCall` execution is presently bricked by F-026, so this destination-side settlement path is unreachable in the current integration. |
| unsupported_or_speculative | codex_1 | Cross-chain withdrawal logic never binds `dstChainId` to `targetZRC20` and can route funds through the wrong chain-specific path | Rejected as a user-controlled misconfiguration issue; the actual destination route is determined by `targetZRC20`, and the code support here is insufficient for a cross-user exploit, reserve drain, or permissionless protocol-level DoS. |
| other | codex_1 | Native-input `withdrawToNativeChain` lets callers bypass platform fees by decoupling `amount` from `msg.value` | Merged into F-004; it is another consequence of the same nominal-amount-versus-actual-funding bug in `withdrawToNativeChain`. |
| other | opencode_1 | GatewaySend depositAndCall does not verify swap output or return funds on swap failure | Rejected; swap failure reverts the whole transaction, and low output is governed by user-supplied DODO parameters rather than a distinct protocol bug. |
| other | opencode_1 | GatewaySend onCall uses message amount instead of actual token balance | Not kept separately because authenticated `GatewaySend.onCall` execution is presently bricked by F-026, so this destination-side path is unreachable in the current integration. |
| other | opencode_1 | GatewayTransferNative.claimRefund reads storage after delete allowing double-claim with reentrancy | Rejected as an inaccurate conflation of two existing issues: reentrancy before delete is already F-006, while post-delete storage reads only affect event data and are already F-025. |
| other | opencode_1 | Platform fee calculation ignores token decimals causing severe undercharging | Rejected; fee calculation on raw token units is standard and does not inherently mis-handle decimals. |
| duplicate_or_subsumed | opencode_1 | Public withdraw function in GatewayTransferNative lacks access control and can be abused | Merged into existing F-008; this is the same public-withdraw-plus-residual-allowance issue already captured. |
| other | opencode_1 | No deadline check in Uniswap swap allowing stale trades | Rejected; the code passes `block.timestamp + MAX_DEADLINE` at execution time, so this is not a separate stale-deadline bug. |
| duplicate_or_subsumed | opencode_1 | onRevert uses .transfer for ETH which can DoS smart contract receivers | Rejected as incorrect; the relevant bug is the missing native-refund branch already captured by F-017, not use of Solidity `.transfer` in `onRevert`. |
| low_impact_or_operational | opencode_1 | No event emitted for critical withdrawToNativeChain state change | Rejected as non-reportable operational telemetry rather than protocol-level security harm. |
| other | opencode_1 | Message decoding lacks bounds checking allowing out-of-bounds read | Rejected; malformed short payloads revert during slicing or produce unusable zero values, with no supported theft, lockup, or cross-user exploit path. |
| trust_or_owner_model | opencode_1 | External call to DODORouteProxy lacks reentrancy protection | Rejected; `DODORouteProxy` is an owner-configured trusted integration here, and no concrete reentrant state-corruption path beyond already-reported issues is supported by the code. |
