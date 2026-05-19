# Merge View - Round 4

## Summary
- total findings: 19
- new findings: 2
- updated existing findings: 0
- rejected candidates: 5

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 17
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-018 | exact_agent_candidate | Critical | high | codex_1 | Swap output asset is not bound to target payout token before withdrawal/transfer | codex_1:1.0 Swap output asset is not bound to target payout token before withdrawal/transfer |
| F-022 | rewritten_agent_signal | Medium | medium | codex_1 | `amountInMax`-based post-swap check can cause avoidable withdrawal reverts | codex_1:0.59 Incorrect `amountInMax`-based sufficiency check introduces avoidable swap-path DoS |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 3
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | GatewayTransferNative.onCall deducts platform fee but swaps using gross amount | Duplicate of F-001 root cause (swap spend parameters are not reconciled to net available balance after fee transfer). |
| unsupported_or_speculative | codex_1 | GatewaySend callback return type is ABI-incompatible with authenticated gateway callback flow | Current implementation returns `bytes4(0)` (`return ""`), which decodes as empty `bytes` for the gateway call path; deterministic callback DoS is not supported by the code as written. |
| other | codex_1 | Unchecked inbound ERC20 transferFrom in GatewaySend.onCall allows underfunded payouts | Already covered by F-005 (destination `onCall` trusts payload values and ignores/does not enforce inbound transfer success semantics). |
| other | codex_1 | Refund claim event emits zero token/amount because storage is deleted before emit | Informational telemetry issue only; does not create protocol-level fund loss/theft/lockup by itself. |
| other | opencode_1 | Deadline parameter not enforced in swap operations | `deadline` is forwarded to DODO `mixSwap`; enforcement is in the router call. No distinct in-scope vulnerability established in these gateway contracts. |
