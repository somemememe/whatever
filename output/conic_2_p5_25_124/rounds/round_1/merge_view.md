# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | First staker after a zero-stake interval can appropriate the entire uncheckpointed reward backlog | codex_1:0.613 First staker after an unstaked period can steal the entire backlog of CRV/CVX/CNC rewards |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Convex extra rewards are claimed to the pool, but the sale path only swaps RewardManager-held balances | codex_1:0.657 All Convex extra rewards are claimed to the pool but sold from the RewardManager, permanently marooning the tokens |
| F-003 | rewritten_agent_signal | Medium | high | codex_1 | Floor-rounded weight rescaling can leave no valid deposit target while rebalancing is active | codex_1:0.483 Rounding down rescaled weights can make post-depeg deposits revert for large pools |
| F-004 | rewritten_agent_signal | Medium | high | codex_1 | Standalone reward-token sales can over-credit CNC because sold CNC is added to the integral without syncing `lastHoldings` | codex_1:0.575 CNC obtained from reward-token sales is added to the integral but left in `lastHoldings`, allowing double distribution |

## Rejection Reasons
- other: 11
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Ineffective Reentrancy Guard Allows Reentrancy Attacks | The reviewed code does not show a concrete callback path that can reenter `depositFor`/`withdraw` and exploit intermediate state; the end-of-function `reentrancyCheck()` alone is not proof of an exploitable reentrancy bug. |
| other | opencode_1 | Division by Zero in ScaledMath Library | A raw division-by-zero revert in a math helper is expected Solidity behavior, and no attacker-controlled in-scope call path was shown that turns this into a distinct protocol vulnerability. |
| other | opencode_1 | Unchecked Return Values from Curve and Uniswap Swaps | Both swap paths enforce explicit `minAmountOut` values and revert on failure/short output at the external protocol level; not separately inspecting return values does not create the claimed loss path here. |
| other | opencode_1 | Unlimited Token Approvals to External Contracts | These approvals are part of the intended trust model toward the configured RewardManager/Convex components, not a standalone vulnerability in the audited code. |
| other | opencode_1 | Unprotected functionDelegateCall to External Handlers | Delegatecalling controller-selected handler contracts is an explicit architectural trust assumption; this is only exploitable if the trusted controller/handler is already malicious or compromised. |
| other | opencode_1 | Race Condition in Reward Claiming Allows Users to Receive Zero Rewards | The claim flow is atomic. Another transaction cannot alter balances between the balance check and transfer inside the same execution, and any real insufficiency would revert rather than silently paying zero. |
| other | opencode_1 | Missing Access Control on ConvexHandler Functions | Direct calls to `ConvexHandlerV3` execute in the handler’s own context and balances. Pool state changes only happen when `ConicEthPool` delegatecalls the handler. |
| other | opencode_1 | Unverified Claimed Amounts from Convex | Failed external reward claims revert, and balance-delta accounting is the normal way this contract measures claimed CRV/CVX. No concrete exploit path was shown. |
| other | opencode_1 | Exchange Rate Calculation Relies on External Oracles | This is a generic oracle-trust observation without a specific manipulation path or code-level flaw unique to this implementation. |
| other | opencode_1 | Lack of Slippage Protection in Deposit/Withdraw | Deposits and withdrawals already expose user-controlled `minLpReceived` / `minUnderlyingReceived` bounds; the candidate does not show a bypass of those protections. |
| other | opencode_1 | Inconsistent _claimingCNC Flag Creates Edge Cases | `_claimingCNC` is intentionally used to exclude transient `claimableCnc(pool)` during CNC claims. No separate exploitable inconsistency was substantiated beyond the distinct sold-CNC double-counting bug captured above. |
| unsupported_or_speculative | opencode_1 | Cached Price Can Become Stale | The cache can certainly age, but this signal was too speculative as written: it did not demonstrate a concrete, realistic false-positive depeg path with measurable protocol harm from the in-scope code alone. |
