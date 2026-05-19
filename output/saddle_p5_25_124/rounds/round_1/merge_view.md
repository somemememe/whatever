# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 6
- updated existing findings: 0
- rejected candidates: 7

## Finding Actions
- exact_agent_candidate: 5
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | MetaSwap underlying swaps over-credit fee-on-transfer meta tokens | codex_1:1.0 MetaSwap underlying swaps over-credit fee-on-transfer meta tokens |
| F-002 | exact_agent_candidate | High | high | codex_1 | Older MetaSwap direct swaps misprice the base LP token leg | codex_1:1.0 Older MetaSwap direct swaps misprice the base LP token leg |
| F-003 | exact_agent_candidate | Medium | high | codex_1 | Older MetaSwap one-token withdrawals into the base LP leg fabricate admin fees | codex_1:1.0 Older MetaSwap one-token withdrawals into the base LP leg fabricate admin fees |
| F-004 | exact_agent_candidate | Medium | medium | codex_1 | Unexpected token balance drift is treated as owner-withdrawable admin fees | codex_1:1.0 Unexpected token balance drift is treated as owner-withdrawable admin fees |
| F-005 | exact_agent_candidate | Low | low | codex_1,opencode_1 | MetaSwap prices the base LP leg from a 10-minute stale virtual-price cache | codex_1:1.0 MetaSwap prices the base LP leg from a 10-minute stale virtual-price cache |
| F-006 | rewritten_agent_signal | Medium | medium |  | Older MetaSwap underlying swaps into base tokens fabricate base-LP admin fees | codex_1:0.697 Older MetaSwap one-token withdrawals into the base LP leg fabricate admin fees |

## Rejection Reasons
- other: 5
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Owner Can Set Extreme Swap Fees Without User Consent | This is a bounded owner/governance privilege, not an implementation flaw; users still protect themselves with `minDy`/slippage checks and deadlines. |
| other | opencode_1 | Amplification Coefficient (A) Ramp Can Be Manipulated to Steal Liquidity | Changing `A` is an explicit admin capability with enforced bounds and ramp delays; no concrete code bug or unintended bypass was shown. |
| other | opencode_1 | Unlimited Token Approvals to BaseSwap in MetaSwap | Approving the trusted base pool is required for normal operation; if MetaSwap were already compromised, pool funds are already at risk without relying on this approval pattern. |
| other | opencode_1 | Missing Reentrancy Guard on MetaSwapUtils.swapUnderlying | The external entrypoint `MetaSwap.swapUnderlying` is protected by `nonReentrant`; the library function itself is not directly callable. |
| other | opencode_1 | Division Loss in StableSwap Invariant Calculation | This points to normal integer-rounding limitations and comments about precision, but does not establish a realistic exploit or protocol-level harm path. |
| trust_or_owner_model | opencode_1 | Missing Access Control on withdrawAdminFees Allows Theft of Pool Funds | `withdrawAdminFees` is gated by `onlyOwner`, and the proposed balance-manipulation path via `rampA` is unsupported by the code. |
| other | opencode_1 | No Oracle Integration Enables Flash Loan Price Manipulation | This is a generic AMM property rather than a protocol-specific vulnerability in the implementation under review. |
