# Merge View - Round 1

## Summary
- total findings: 7
- new findings: 7
- updated existing findings: 0
- rejected candidates: 17

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Unrestricted post-swap bridge entrypoints can exfiltrate assets already held by the gateway | codex_1:0.619 Any caller can invoke post-swap bridge entrypoints to exfiltrate residual gateway balances |
| F-002 | rewritten_agent_signal | Critical | high | codex_1 | Optimism and Arbitrum routes trust attacker-chosen bridge contracts as spenders and call targets | codex_1:0.511 Optimism/Arbitrum routes let callers nominate arbitrary bridge spender contracts |
| F-003 | exact_agent_candidate | High | high | codex_1 | Hop routes forward gateway ETH to caller-chosen contracts | codex_1:1.0 Hop routes forward gateway ETH to caller-chosen contracts |
| F-004 | rewritten_agent_signal | High | high | codex_1 | ZkSync composed bridge paths pull ERC20s from the user a second time and trust the wrong token field | codex_1:0.844 ZkSync post-swap bridging pulls tokens from the user a second time and trusts the wrong token field |
| F-005 | exact_agent_candidate | High | high | codex_1 | Many direct native bridge entrypoints can spend pre-existing gateway ETH without reconciling `msg.value` | codex_1:0.92 Direct native bridge entrypoints can spend pre-existing gateway ETH without matching `msg.value` |
| F-006 | rewritten_agent_signal | Medium | high | codex_1 | `swapAndMultiBridge` is permanently unusable because the ratio-aggregation loop never increments | codex_1:0.824 Multi-bridge execution is permanently unusable because the ratio loop never increments |
| F-007 | exact_agent_candidate | Medium | high | codex_1 | Built-in routes below ID 385 cannot actually be disabled | codex_1:0.876 Built-in routes 0-384 cannot actually be disabled |

## Rejection Reasons
- other: 12
- trust_or_owner_model: 5

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | All RouteIds 1-384 Map to Same Address - Suspicious Hardcoded Logic | `addressAt()` is clearly generated deployment wiring for reserved routes, but this alone does not show an exploitable integrity break or fund-loss path. |
| trust_or_owner_model | opencode_1 | Delegatecall Allows Arbitrary Code Execution in executeRoute | `executeRoute` is the intended plugin dispatch mechanism; arbitrary execution only follows if the owner installs a malicious route, which is an admin trust assumption rather than a standalone vulnerability. |
| other | opencode_1 | Delegatecall in swapAndMultiBridge Allows Arbitrary Swap Execution | This is the same intended route-dispatch architecture as `executeRoute`, not an independent bug. |
| trust_or_owner_model | opencode_1 | Unlimited Token Approvals via setApprovalForRouters | Owner-managed approvals to known routers are an explicit admin capability; the claim reduces to owner compromise risk. |
| other | opencode_1 | No Access Control on FeesTakerController Functions | These controller methods are meant to be user-callable helpers and spend the caller's own approvals or value, not shared protocol funds. |
| other | opencode_1 | Unrestricted Refund Function in CelerImpl with No Access Control | `refundCelerUser` validates the refund payload, requires the refund receiver to be the gateway, and forwards funds to the stored original user rather than the caller. |
| trust_or_owner_model | opencode_1 | Missing Zero Address Validation in addRoute | This is an owner-only misconfiguration footgun with no realistic protocol-level exploit path. |
| other | opencode_1 | Fallback Function Uses msg.sig for Route Routing | The fallback router is an intentional dispatch mechanism; the report does not show an exploitable path beyond the already-reviewed route implementation bugs. |
| other | opencode_1 | No Slippage Protection in Swap Implementations | The 1inch calldata is generated off-chain and already encodes slippage/min-return constraints; this report does not identify a missing on-chain check beyond that design. |
| other | opencode_1 | ERC20 Approvals Not Reset After Bridge Execution | Persistent approvals to trusted external bridge routers are common integration behavior and the claim depends on later compromise of those trusted routers. |
| other | opencode_1 | ExecuteControllers Allows Sequential Arbitrary Delegatecalls | This is the intended controller-composition entrypoint, not a distinct vulnerability. |
| other | opencode_1 | ExecuteRoutes Allows Sequential Arbitrary Delegatecalls | This is the intended route-composition entrypoint, not a distinct vulnerability. |
| trust_or_owner_model | opencode_1 | Missing Zero Address Validation in addController | This is an owner-only configuration mistake, not a realistic adversarial exploit. |
| other | opencode_1 | SwapAndBridge Uses Delegatecall Without Validation | The bridge contracts are intentionally composing trusted swap routes through the gateway's route table; this is architectural, not a separate bug. |
| trust_or_owner_model | opencode_1 | Rescue Functions Allow Draining All Funds | These are explicit owner-only rescue powers and therefore part of the admin trust model. |
| other | opencode_1 | Precision Loss in Bridge Ratio Calculation | Integer rounding dust is minor and not a reportable protocol-risk issue compared with the real functional bug in the same flow. |
| other | opencode_1 | Unchecked Return Value of Native Transfer in FeesTakerController | The code checks the boolean result and reverts on failure; the candidate does not describe a real bug. |
