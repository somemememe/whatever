# Merge View - Round 1

## Summary
- total findings: 8
- new findings: 8
- updated existing findings: 0
- rejected candidates: 14

## Finding Actions
- exact_agent_candidate: 5
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | User-controlled swap params can spend arbitrary token balances held by gateway contracts | codex_1:1.0 User-controlled swap params can spend arbitrary token balances held by gateway contracts |
| F-002 | exact_agent_candidate | Critical | high | codex_1 | Refunds for non-20-byte recipients are claimable by anyone | codex_1:1.0 Refunds for non-20-byte recipients are claimable by anyone |
| F-003 | exact_agent_candidate | High | high | codex_1 | Bitcoin/non-EVM revert recipient is truncated to 20 bytes, misdirecting refunds | codex_1:1.0 Bitcoin/non-EVM revert recipient is truncated to 20 bytes, misdirecting refunds |
| F-004 | exact_agent_candidate | Critical | high | codex_1 | ETH sentinel path in `withdrawToNativeChain` allows unfunded withdrawal of contract-held tokens | codex_1:0.884 ETH sentinel path in `withdrawToNativeChain` allows free withdrawal of escrowed tokens |
| F-005 | rewritten_agent_signal | High | medium | codex_1 | GatewaySend destination payout uses payload amount/token flags instead of reconciled delivered assets | codex_1:0.333 Destination payout amount in `GatewaySend.onCall` is fully trusted from payload |
| F-006 | exact_agent_candidate | Medium | medium | codex_1,opencode_1 | Reentrancy in `GatewayTransferNative.claimRefund` allows repeated refund claims | codex_1:0.914 Reentrancy in `GatewayTransferNative.claimRefund` allows repeated refund withdrawal |
| F-007 | rewritten_agent_signal | Medium | medium | codex_1 | Balance-based pair existence check can be dust-poisoned into swap-path DoS | codex_1:0.675 Pair existence detection is balance-based and can be dust-poisoned into swap DoS |
| F-008 | rewritten_agent_signal | Medium | low | codex_1 | Public `withdraw` can be abused when residual gateway allowances remain | codex_1:0.649 Public `withdraw` in GatewayTransferNative can abuse leftover gateway allowances |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 4
- trust_or_owner_model: 8
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Owner Can Drain All Contract Funds via superWithdraw | Privileged `onlyOwner` emergency withdrawal capability; this is trust/governance centralization, not an unauthorized exploit path. |
| trust_or_owner_model | opencode_1 | Owner Can Set Malicious DODORouteProxy to Steal User Funds | Depends on malicious owner action; treated as admin trust assumption rather than a permissionless vulnerability. |
| trust_or_owner_model | opencode_1 | Owner Can Set Malicious DODOApprove to Steal User Tokens | Depends on malicious owner action; not a non-privileged exploit. |
| trust_or_owner_model | opencode_1 | Owner Can Set Excessive FeePercent Degrading User Swaps | Owner-governed parameter risk; policy/centralization issue, not a code-level exploit by external attackers. |
| trust_or_owner_model | opencode_1 | Owner Can Set Excessive Slippage Causing User Loss | Owner-controlled configuration risk rather than unauthorized exploit. |
| trust_or_owner_model | opencode_1 | Arbitrary Gateway Address Can Be Set by Owner | Admin trust assumption; requires privileged owner compromise or malicious governance. |
| other | opencode_1 | Missing Deadline Validation in Uniswap Swaps | No concrete theft or protocol-level exploit demonstrated; fixed short deadline mostly affects execution reliability/reverts. |
| other | opencode_1 | AccountEncoder.decompressAccounts Lacks Bounds Checking | Primarily malformed-input/self-DoS behavior; no clear permissionless fund-loss path established. |
| unsupported_or_speculative | opencode_1 | SwapDataHelperLib Uses Unchecked Arithmetic Without Validation | Claim is too speculative and not tied to a concrete exploit causing realistic protocol harm. |
| trust_or_owner_model | opencode_1 | Missing Zero Address Validation in setDODORouteProxy GatewaySend.sol | Owner misconfiguration hardening issue only; not an external exploit vector. |
| duplicate_or_subsumed | opencode_1 | Inconsistent CEI Pattern Between claimRefund Implementations | Not a distinct issue; the actionable vulnerability is already captured as reentrancy in `GatewayTransferNative.claimRefund`. |
| trust_or_owner_model | opencode_1 | Inconsistent Zero Address Validation in setEddyTreasurySafe | Configuration consistency concern without a direct non-privileged attack path. |
| other | opencode_1 | Unsafe Type Casting from Bytes to Address | Informational pattern note; no standalone exploitable protocol harm demonstrated beyond accepted findings. |
| other | opencode_1 | External ID Collision Risk in _calcExternalId | No practical collision exploit shown under actual nonce progression and usage. |
