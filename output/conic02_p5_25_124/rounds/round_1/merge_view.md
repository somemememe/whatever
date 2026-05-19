# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 18

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | Convex extra rewards are claimed to the pool but sold from the RewardManager, permanently stranding them | codex_1:1.0 Convex extra rewards are claimed to the pool but sold from the RewardManager, permanently stranding them |
| F-002 | rewritten_agent_signal | High | high | codex_1 | The first staker after a zero-staker period can capture all rewards accrued while nobody was staked | codex_1:0.337 All rewards accrued during zero-staker periods can be stolen by the next staker |
| F-003 | rewritten_agent_signal | Medium | medium | codex_1 | RewardManager pre-books CVX with single-cliff math that can exceed what Convex will actually mint | codex_1:0.68 RewardManager books estimated CVX before claim using cliff math that can overstate actual minting |
| F-004 | rewritten_agent_signal | Medium | low | codex_1,opencode_1 | Permissionless depeg handling can offboard healthy pools because it relies on a stale price cache | codex_1:0.599 Permissionless depeg handling relies on a stale price cache that is only refreshed on weight updates |
| F-005 | exact_agent_candidate | Low | high | codex_1 | Small deposits and withdrawals can revert because allocation rounding leaves no selectable pool | codex_1:0.964 Small deposits and withdrawals can revert because target-allocation rounding leaves no selectable pool |

## Rejection Reasons
- low_impact_or_operational: 1
- other: 12
- trust_or_owner_model: 4
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing Access Control on handleInvalidConvexPid | Permissionless access is intentional here and still gated by `isShutdownPid(pid)`, so this is not an authorization bug by itself. |
| unsupported_or_speculative | opencode_1 | Slippage Protection Bypass via Unsupported Tokens | Under the current reward-claim path, Convex extra rewards are sent to the pool rather than the RewardManager, so the reported unsupported-token swap path is not reachable in normal protocol operation. |
| other | opencode_1 | No Deadline on DEX Swaps | The Sushi swap already uses `block.timestamp` as a deadline, and the Curve `exchange` interface used here does not expose a separate deadline parameter. |
| trust_or_owner_model | opencode_1 | Potential Reentrancy via functionDelegateCall | This depends on a malicious or compromised handler contract configured by trusted governance/controller components; no same-trust-boundary reentrancy path was substantiated. |
| other | opencode_1 | Unchecked Curve Pool Exchange Return Values | Curve `exchange` returns an amount and reverts on failure; the code is not ignoring a boolean success flag. |
| other | opencode_1 | Division by Zero in ScaledMath.divDown | This is a generic library property, not a concrete exploitable protocol issue from the reviewed call sites. |
| other | opencode_1 | Reward Calculation Vulnerable to MEV/Front-Running | `claimableRewards` is a view function and the report did not establish a permissionless way to reduce pool-held rewards before claims. |
| low_impact_or_operational | opencode_1 | Lack of Event Emitting for Critical State Changes | Missing events are an observability issue, not a protocol-impacting vulnerability. |
| trust_or_owner_model | opencode_1 | Centralization Risk - Owner Has Excessive Privileges | This is a governance/trust-model concern rather than a code vulnerability. |
| trust_or_owner_model | opencode_1 | Insufficient Validation in addCurvePool | This is again an owner-governance quality concern; it does not show a permissionless or unintended exploit path. |
| other | opencode_1 | Missing Zero Address Check in setExtraRewardsCurvePool | `address(0)` is explicitly supported and means 'do not use a Curve pool', falling back to the Sushi path. |
| other | opencode_1 | Infinite Approval for External Contracts | This is a standard trust assumption toward protocol-controlled components, not a standalone vulnerability. |
| other | opencode_1 | Lack of Input Validation in updateWeights | The reported issue is a policy preference about extreme controller-set weights, not a concrete bug. |
| other | opencode_1 | Potential Integer Overflow in ScaledMath.mulDown | Solidity 0.8.x already reverts on overflow; no practical overflow exploit was shown. |
| other | opencode_1 | Missing Sanity Checks in withdraw | Withdrawals are bounded by actual balances and protected by `minUnderlyingReceived`; the report did not demonstrate a silent loss beyond user-accepted slippage. |
| other | opencode_1 | Anyone Can Trigger poolCheckpoint | `poolCheckpoint()` only updates accounting state and does not transfer rewards to the caller; no theft path was substantiated. |
| trust_or_owner_model | opencode_1 | Lack of Access Control on setFeePercentage | The function is `onlyOwner` and capped; this is a governance-policy complaint, not missing access control. |
| other | opencode_1 | Unprotected receive() Function Allows ETH Stuck | For non-WETH pools the `receive()` function reverts, so ETH is not silently trapped through the path described. |
