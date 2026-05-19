# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 17

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | First staker after a zero-stake interval can capture all rewards accrued while nobody was staked | codex_1:0.757 First staker after a zero-stake interval can steal all previously accrued rewards |
| F-002 | exact_agent_candidate | High | high | codex_1 | Selling extra rewards double-counts the received CNC and can make reward accounting insolvent | codex_1:1.0 Selling extra rewards double-counts the received CNC and can make reward accounting insolvent |
| F-003 | rewritten_agent_signal | Medium | high | merge_review | Extra reward tokens are claimed to the pool but sold only from the reward manager, leaving accrued extras trapped | codex_1:0.437 Unsupported extra reward tokens are sold with zero slippage protection |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1 | Rebalancing rewards can be farmed with temporary capital because only deposits are rewarded | codex_1:0.8 Rebalancing rewards can be flash-loan farmed because only deposits are rewarded |

## Rejection Reasons
- other: 13
- trust_or_owner_model: 3
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Unsupported extra reward tokens are sold with zero slippage protection | The normal accrual path does not place extra rewards in `RewardManagerV2` at all; they are claimed to the pool, so the described permissionless sale of accrued extras is not the primary reachable issue. The reportable problem is custody/lockup of extra rewards. |
| unsupported_or_speculative | codex_1 | The ETH omnipool remains exposed to callback/read-only reentrancy during Curve operations | The code lacks an upfront guard, but no concrete reachable callback/reentry path is shown here, and a revert from the post-operation reentrancy check would unwind the whole transaction. This remains too speculative as a standalone finding from the provided code. |
| other | opencode_1 | Missing Reentrancy Guard in Deposit and Withdraw Functions | Same underlying concern as the reentrancy signal above, but without a demonstrated callback vector. The after-the-fact check would revert the transaction rather than leave a profitable nested call standing. |
| other | opencode_1 | Unprotected handleDepeggedCurvePool Allows Anyone to Modify Pool Weights | This is intentional emergency behavior: the function is permissionless but gated by `isRegisteredCurvePool`, nonzero weight, and `_isDepegged`. No exploit beyond triggering the intended response was established. |
| other | opencode_1 | Unprotected handleInvalidConvexPid Allows Anyone to Modify Pool Weights | Also intentional emergency behavior. The function is deliberately permissionless and only succeeds when the registry reports the Convex PID has been shut down. |
| trust_or_owner_model | opencode_1 | Unlimited Token Approvals to External Contracts | This is a standard trust assumption around approved protocol dependencies. The report depends on external contracts or privileged controller addresses becoming malicious, rather than a permissionless flaw in this code. |
| trust_or_owner_model | opencode_1 | Depeg Threshold Can Be Manipulated by Owner | Owner-configurable parameters within bounded ranges are governance/trust-model choices, not a standalone vulnerability. |
| other | opencode_1 | Unsafe Delegatecall to External Handlers | The delegatecall target is a controller-managed protocol component. Risk here is the trusted-handler model itself, not a permissionless exploit introduced by this code. |
| other | opencode_1 | Insufficient Slippage Protection in Withdraw Function | `minUnderlyingReceived` is explicitly user-supplied protection. Users setting it to zero is an acknowledged footgun, not a protocol bug. |
| other | opencode_1 | No Access Control on updateWeights Except via Controller | `onlyController` is the intended access control. The candidate reduces to controller-compromise risk, which is outside the protocol's permissionless threat model. |
| other | opencode_1 | Missing Pausable Mechanism for Emergency Response | Absence of a pause switch is a design choice/best-practice gap, not a concrete exploit or protocol failure on its own. |
| other | opencode_1 | Race Condition in ClaimEarnings Function | EVM execution is serialized. Another user's claim cannot interleave between local state reads and transfers absent a demonstrated reentrancy vector, which was not established. |
| trust_or_owner_model | opencode_1 | Fee Enabling Has Weak Preconditions | This is an owner-controlled economic parameter with an explicit max cap, not a code-level vulnerability. |
| other | opencode_1 | Integer Division Truncation in Reward Calculations | Minor rounding dust from integer division is expected in fixed-point accounting and is not materially reportable here. |
| other | opencode_1 | Block Timestamp Dependence for Cache Expiry | Using `block.timestamp` for a 3-day cache-expiry check is standard and any miner manipulation window is immaterial to protocol safety. |
| other | opencode_1 | No Maximum Deposit/Withdrawal Limits | The protocol already relies on user-specified slippage checks and pool mechanics; lack of explicit per-tx caps is not itself a vulnerability. |
| other | opencode_1 | Potential Call Stack Depth in Loops | No realistic path was shown for stack-depth failure from these bounded loops, and the candidate does not demonstrate protocol-level harm. |
