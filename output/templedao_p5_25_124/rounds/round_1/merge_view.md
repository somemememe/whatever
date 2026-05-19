# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 7

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1,opencode_1 | Untrusted migration source lets anyone mint unbacked stake shares and drain the pool | codex_1:1.0 Untrusted migration source lets anyone mint unbacked stake shares and drain the pool |
| F-002 | rewritten_agent_signal | Medium | low | codex_1 | Stake accounting assumes the contract receives the full requested amount | codex_1:0.447 Reward schedules can be underfunded because reward accounting trusts the requested transfer amount |
| F-003 | exact_agent_candidate | Medium | low | codex_1 | Reward schedules can be underfunded because accounting trusts the requested transfer amount | codex_1:0.963 Reward schedules can be underfunded because reward accounting trusts the requested transfer amount |
| F-004 | rewritten_agent_signal | Low | high | codex_1,opencode_1 | Reward-rate truncation permanently strands dust and can make small reward deposits entirely unclaimable | codex_1:0.784 Reward rounding permanently strands tokens, and small reward deposits can become entirely unclaimable |
| F-005 | exact_agent_candidate | Low | high | codex_1,opencode_1 | Unbounded reward-token list can gas-brick staking, withdrawals, and reward claims | codex_1:0.955 Unbounded reward-token list can gas-brick staking, withdrawals, and claims |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 2
- trust_or_owner_model: 2
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | opencode_1 | Reentrancy via Arbitrary Token Callbacks | Unsupported as a distinct exploit: state changes around reward claims use checks-effects-interactions, and the described callback path does not demonstrate a concrete way to inflate or steal rewards beyond assuming a malicious token configuration. |
| trust_or_owner_model | opencode_1 | Missing Zero Address Validation for Reward Distributor | Owner misconfiguration only; the owner can later set a valid distributor again, so this does not create lasting protocol-level harm. |
| other | opencode_1 | Unprotected Stake for Any Address | Common `stakeFor` behavior and not a realistic protocol vulnerability here; the caller spends their own tokens and rewards still accrue to the beneficiary. |
| duplicate_or_subsumed | opencode_1 | No Validation on Reward Token Addition | Not an independent issue from the accepted findings. Adding arbitrary reward tokens is owner-gated, and the concrete reportable risks are already captured by the underfunded-rewards and unbounded-array findings. |
| other | opencode_1 | Missing Owner Validation in setRewardDistributor | Setting the same distributor again is harmless and has no security impact. |
| unsupported_or_speculative | opencode_1 | Missing Event Emission for Migrator Change | Factually unsupported because `setMigrator()` always emits `MigratorSet`, including when setting the value to `address(0)`. |
| trust_or_owner_model | opencode_1 | Unused Migrator Can Be Set to Zero | Owner-controlled feature toggle only; migration can be re-enabled later by setting a nonzero migrator, so this is not a lasting security issue. |
