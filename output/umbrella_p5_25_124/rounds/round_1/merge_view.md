# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Unchecked arithmetic in `withdraw()` lets any caller drain staking tokens | codex_1:0.841 Unchecked subtraction in `withdraw()` lets any caller drain arbitrary staking tokens |
| F-002 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Rewards are scheduled against a farm-local counter, so the shared token mint cap can make accrued rewards permanently unclaimable | codex_1:0.758 Rewards are scheduled against a shared lifetime mint cap, so accrued rewards can become permanently unclaimable |
| F-003 | exact_agent_candidate | Medium | low | codex_1 | Stake accounting credits the requested amount instead of the tokens actually received | codex_1:0.959 Stake accounting trusts the requested amount instead of the tokens actually received |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing Balance Check in withdraw() Enables Exploit | Merged into F-001 as the same root cause and exploit path; keeping it separate would double-count the underflow/drain issue. |
| unsupported_or_speculative | opencode_1 | RescueToken Allows Owner to Steal Staking Tokens | Not supported by the code. For staking tokens, `rescueToken()` enforces that post-transfer balance stays at least `_totalSupply`; if `_amount` exceeds the actual balance, the ERC20 `transfer` reverts, so there is no demonstrated drain path. |
| duplicate_or_subsumed | opencode_1 | getReward() Mints Tokens Without Checking Reward Token Supply | This is a symptom of the shared mint-cap insolvency already captured in F-002, not a separate root cause. |
