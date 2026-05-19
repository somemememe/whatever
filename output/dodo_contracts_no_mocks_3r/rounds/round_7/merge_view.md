# Merge View - Round 7

## Summary
- total findings: 21
- new findings: 0
- updated existing findings: 0
- rejected candidates: 11

## Finding Actions
- existing_preserved: 21

## New Or Updated Findings
- none

## Rejection Reasons
- duplicate_or_subsumed: 4
- factually_incorrect: 1
- low_impact_or_operational: 1
- other: 4
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | GatewaySend destination execution uses nominal `amount` without validating actual ERC20 intake | Duplicate of existing F-005 root cause: destination `onCall` trusts payload amount/token and does not reconcile actual intake; soft-fail/under-receipt variants are already covered. |
| duplicate_or_subsumed | codex_1 | Native-input fee transfer silently no-ops when `_ETH_ADDRESS_` is used as token address | Subsumed by F-004 sentinel-input underfunding/theft path; standalone fee-accounting symptom is not a distinct reportable root cause. |
| low_impact_or_operational | codex_1 | Refund-claimed event logs zero token/amount due storage-delete ordering | Observability-only issue; does not create realistic protocol-level fund loss, theft, lockup, or DoS by itself. |
| other | codex_1 | Packed-message parser can read token addresses outside declared `crossChainData` length | No additional exploit impact beyond already attacker-controlled payload/token fields in existing critical findings (notably F-005). |
| other | codex_1 | TransferNative revert handlers lack minimum `revertMessage` length checks | Low-confidence/non-realistic trigger: callbacks are `onlyGateway` and this contract’s own revert-message construction always prefixes at least 32 bytes. |
| duplicate_or_subsumed | opencode_1 | RefundInfo entry can be overwritten causing loss of refund claims | Already captured by F-011 (refund key collision/overwrite/poisoning); this candidate does not add a new independent root cause. |
| other | opencode_1 | onCall does not validate fromToken and toToken are legitimate ZRC20 tokens | Not a distinct vulnerability in this context; payload-controlled token misuse and reserve-drain consequences are already covered by F-005/F-001/F-018. |
| factually_incorrect | opencode_1 | Platform fees deducted before swap validation; swap failure causes permanent fee loss | Incorrect: if downstream swap reverts, the entire transaction (including prior fee transfer) reverts atomically. |
| unsupported_or_speculative | opencode_1 | No slippage protection on output amount in onCall cross-chain receive path | Unsupported: DODO swap path carries user-specified min-return parameters; this is not a distinct protocol bug as stated. |
| duplicate_or_subsumed | opencode_1 | decodeMessage allows empty swapDataZ but onCall path lacks empty-handling in some branches | Duplicate of existing F-009/F-018 coverage of empty-swap and asset-binding failures. |
| other | opencode_1 | ExternalId generation uses predictable components enabling collision attacks | No practical collision exploit demonstrated: hash input is coupled to caller identity and evolving nonce; front-run collision path is not substantiated. |
