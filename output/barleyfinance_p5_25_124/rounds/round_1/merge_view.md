# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Unrestricted first-time referral initialization lets an attacker seize reward routing and brick reward-dependent share updates | opencode_1:0.37 Unrestricted Rescue Functions Allow Draining of Protocol Assets |
| F-002 | exact_agent_candidate | High | high | codex_1 | Anyone can front-run a user’s first claim and permanently bind attacker-controlled referrers | codex_1:0.957 Anyone can front-run a user's first claim and permanently assign attacker-controlled referrers |
| F-003 | rewritten_agent_signal | Medium | medium | codex_1 | Dust supply causes the automatic fee path to execute a zero-input swap and can freeze transfers/sells | codex_1:0.775 Dust total supply makes the auto-fee path call a zero-amount swap and can freeze transfers |
| F-004 | exact_agent_candidate | Medium | low | codex_1 | Repeated failed reward swaps can wrap slippage math and strand protocol DAI fees | codex_1:0.872 Repeated failed reward swaps can underflow slippage math and strand DAI fees |

## Rejection Reasons
- other: 10
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Bond mints redeemable index tokens before collecting the full basket, enabling malicious-asset reentrancy | Reentrancy is theoretically possible, but no concrete path was shown to extract net value or leave the index undercollateralized: if the outer `bond()` later fails the whole transaction reverts, and if it succeeds the full basket is still collected. |
| trust_or_owner_model | opencode_1 | Unrestricted Rescue Functions Allow Draining of Protocol Assets | `rescueERC20()` and `rescueETH()` send funds to `Ownable(address(V3_TWAP_UTILS)).owner()`, not to the caller. Anyone can trigger an admin rescue, but that is not an attacker-controlled drain. |
| other | opencode_1 | Unrestricted Staking Pool Token Transfers Bypass Stake Restrictions | The restriction only limits who may be minted staking receipts in `stake()`. Transferring receipt tokens later does not mint extra stake or create a realistic protocol-level loss scenario. |
| other | opencode_1 | Division by Zero in WeightedIndex Constructor | This is a deployment-time misconfiguration only, not an exploitable vulnerability in a live protocol. |
| other | opencode_1 | Uniswap V2 Price Manipulation via Flash Loans | The reserve-derived price helpers are only exposed through view functions; `bond()` and `debond()` do not use these prices for settlement. |
| other | opencode_1 | Flash Loan Callback Without Reentrancy Protection | No concrete unsafe state dependency was identified. The callback must restore the borrowed token balance before returning, and the report did not show a profitable reentrant path. |
| other | opencode_1 | Insufficient Slippage Protection on Token Swap | This is ordinary slippage/MEV exposure around an allowed swap, not a distinct code bug with a demonstrated protocol-breaking path. |
| other | opencode_1 | No Validation of Token Decimals in WeightedIndex | This depends on deploying an index with malicious or highly non-standard token metadata and does not present a realistic permissionless exploit against an already deployed index. |
| other | opencode_1 | Unchecked Return Value in ETH Transfer | The contract does check the result of the ETH send and reverts on failure via `require(_sent, 'SENT')`. |
| other | opencode_1 | Potential Integer Overflow in Price Calculations | The cited math is in view-only pricing helpers, not in settlement logic, and no realistic overflow exploit path was demonstrated for standard reserve and decimal ranges. |
| other | opencode_1 | Missing Zero-Address Validation in Constructor | This is a deployment/configuration risk rather than a live, permissionless vulnerability. |
| trust_or_owner_model | opencode_1 | Missing Access Control on StakingPoolToken Admin Functions | If restrictions are disabled at deployment, the inability to later enable them is a governance/design limitation, not a realistic protocol-harm vulnerability. |
