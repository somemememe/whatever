# Merge View - Round 8

## Summary
- total findings: 22
- new findings: 1
- updated existing findings: 1
- rejected candidates: 6

## Finding Actions
- existing_preserved: 20
- existing_rewritten: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-011 | existing_rewritten | Medium | high | codex_1,opencode_1 | Refund key collisions and zero-key handling can overwrite entries, block recording, or lock refunds | opencode_1:0.312 GatewaySend onCall does not validate outputAmount >= amount for swap paths |
| F-025 | rewritten_agent_signal | Low | high | codex_1 | GatewayTransferNative refund-claimed event emits zero token/amount due to storage read after delete | codex_1:0.634 Refund-claimed event logs zero token/amount due to emit-after-delete on storage pointer |

## Rejection Reasons
- other: 5
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | GatewayTransferNative onCall charges fee but still swaps gross amount, enabling reserve-subsidized payouts | Already covered by F-001 (same root cause: fee deducted then swap logic still trusts attacker-controlled swap params/nominal amounts and can externalize deficits to reserves). |
| other | codex_1 | GatewayTransferNative revert callbacks can hard-revert on short revertMessage | Low-value malformed-callback scenario; in protocol-generated flows this contract builds revert messages with at least 32 bytes, so this is not a realistic protocol-level exploit path. |
| unsupported_or_speculative | opencode_1 | SwapDataHelperLib decodeCompressedMixSwapParams lacks calldata bounds checks | Claimed out-of-bounds stale-data read is unsupported; malformed inputs mainly cause revert/self-failure, not exploitable cross-user fund impact. |
| other | opencode_1 | SwapDataHelperLib decodeCompressedMixSwapParams offset arithmetic can underflow | No credible underflow path: offset is only incremented, never decremented. |
| other | opencode_1 | GatewaySend onCall lacks reentrancy protection on token transfers | `onCall` is `onlyGateway`; proposed reentrant entry is not realistically reachable by arbitrary recipients, and no concrete state-dependent drain path was shown. |
| other | opencode_1 | GatewaySend onCall does not validate outputAmount >= amount for swap paths | Not a protocol vulnerability by itself; swap slippage/price impact is governed by swap parameters (`minReturnAmount`) and market conditions. |
