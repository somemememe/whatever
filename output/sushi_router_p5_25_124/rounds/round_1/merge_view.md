# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 15

## Finding Actions
- exact_agent_candidate: 3
- new_unmatched: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1,opencode_1 | Arbitrary V3-style pools can forge callbacks and steal approved user funds | codex_1:1.0 Arbitrary V3-style pools can forge callbacks and steal approved user funds |
| F-002 | exact_agent_candidate | High | high | codex_1 | Public routes can sweep router-held ETH, ERC20, and Bento balances because input accounting ignores contract-owned inventory | codex_1:0.975 Public routes can sweep router-held ERC20 and Bento balances because input accounting ignores contract-owned inventory |
| F-003 | exact_agent_candidate | High | high | codex_1 | Native unwrap pays out the router's entire ETH balance instead of only the requested amount | codex_1:1.0 Native unwrap pays out the router's entire ETH balance instead of only the requested amount |
| F-005 | new_unmatched | High | high |  | `processUserERC20` is not bound to the declared `tokenIn`, allowing malicious routes to pull arbitrary approved assets from the caller | codex_1:0.304 Zero-amount Bento deposits let arbitrary callers capture surplus tokens parked at BentoBox |

## Rejection Reasons
- duplicate_or_subsumed: 1
- factually_incorrect: 1
- low_impact_or_operational: 1
- other: 11
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Zero-amount Bento deposits let arbitrary callers capture surplus tokens parked at BentoBox | This appears to rely on BentoBox's own public skim/deposit-from-vault behavior (`deposit(..., from = address(bentoBox))`), so the router is not introducing a new privilege or theft path. |
| other | opencode_1 | Missing slippage protection in swapUniV2 | The contract enforces a route-level `amountOutMin` at the end of `processRouteInternal`; slippage is not unchecked just because individual hops lack per-hop minimums. |
| other | opencode_1 | No slippage protection for Trident pool swaps | The final `amountOutMin` check applies to Trident routes as well, so this is not a separate missing-slippage bug. |
| other | opencode_1 | No deadline/timestamp validation for route execution | Missing deadlines are a user-experience/control limitation, not a standalone protocol exploit when the caller already chooses whether to submit the transaction and can set `amountOutMin`. |
| other | opencode_1 | Unrestricted arbitrary recipient for BentoBox deposits | Route-controlled recipients are intended behavior by themselves. The reportable issue is the missing binding between external `tokenIn` and the route-selected source asset, which is captured separately. |
| other | opencode_1 | Missing reentrancy protection in swap callbacks | The actionable callback flaw is the arbitrary-pool/authentication issue already kept. No additional exploitable reentrant path is demonstrated beyond that. |
| factually_incorrect | opencode_1 | Unlimited token approvals for external tokens | Incorrect premise: this contract does not grant token approvals in the cited code paths; it only uses transfers and transferFrom. |
| other | opencode_1 | Division truncation leads to precision loss in share distribution | This is bounded rounding dust from integer math and the share-based route format, not realistic protocol-level harm. |
| other | opencode_1 | Missing validation of swapData for Trident pools | `swapData` is intentionally pool-specific opaque calldata. Without an independent authorization failure, arbitrary data alone is not a router vulnerability. |
| other | opencode_1 | Insufficient input validation on 'to' address | A caller choosing a bad recipient is self-inflicted misuse, not a protocol bug. |
| duplicate_or_subsumed | opencode_1 | Manipulable balance check using msg.sender | The stated callback-based manipulation is speculative. The concrete balance-check failure is the internal-inventory and asset-mismatch issues already captured separately. |
| other | opencode_1 | Slot undrain protection uses unchecked subtraction incorrectly | Leaving dust when balance is 1 is an edge effect of the deliberate undrain pattern, not an exploitable vulnerability. |
| other | opencode_1 | Silent failure possible in transferValueAndprocessRoute | This concerns revert-message quality only and does not create realistic loss, theft, lockup, or DoS. |
| trust_or_owner_model | opencode_1 | No validation that tokenOut is different from tokenIn | Swapping a token into itself is a route-construction mistake, not an unauthorized or protocol-level exploit. |
| low_impact_or_operational | opencode_1 | No event emissions for critical operations | Lack of events is an observability issue, not a security vulnerability. |
