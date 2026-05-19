# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | claimEarned pays fixed rewards immediately and can be repeated indefinitely for the same stake | codex_1:0.466 claimEarned can be called infinitely and does not enforce lock expiry |
| F-002 | exact_agent_candidate | High | high | codex_1 | Rewards claimed via claimEarned are paid again during unstake | codex_1:0.921 Rewards claimed through claimEarned are paid again during unstake |
| F-003 | rewritten_agent_signal | High | high | codex_1 | Owner can arbitrarily sweep staked tokens and leave the pool insolvent | codex_1:0.582 Owner can arbitrarily drain the staking pool via penaltyWithdraw |
| F-004 | rewritten_agent_signal | Medium | low | codex_1 | Core staking flows ignore ERC20 return values and can mutate accounting after failed token transfers | codex_1:0.589 User-facing token transfers ignore ERC20 return values and can silently corrupt accounting |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 1
- other: 5
- trust_or_owner_model: 1
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Double counting bug in claimEarned totalRewards calculation | Confirmed, but totalRewards and related counters are not used to gate payouts or permissions anywhere in the contract; this is bookkeeping corruption only, not realistic protocol-level harm on its own. |
| unsupported_or_speculative | opencode_1 | claimEarned missing nonReentrant modifier | Speculative and not needed to exploit the contract. The reportable issue is the missing reward-settlement logic itself; adding nonReentrant would not prevent the observed drain. |
| low_impact_or_operational | opencode_1 | Stake amount can be reduced to zero without updating stakesCount | Inaccurate or stale counting can waste gas and misreport pool metadata, but it does not create realistic fund loss, lockup, or protocol insolvency. |
| other | opencode_1 | earnedToken rewards are not time-proportional | The contract implements fixed-plan rewards paid on maturity, not linear vesting. Using apr as a label is misleading, but the code is internally consistent with fixed-per-plan payouts. |
| trust_or_owner_model | opencode_1 | Owner can permanently disable staking plans with no recovery | This is an owner-controlled configuration choice for new deposits, not an exploitable vulnerability affecting existing funds. |
| unsupported_or_speculative | opencode_1 | emergencyWithdraw allows withdrawal during lock period | The function name and logic indicate an intentional early-exit path. It does deduct 20% from the withdrawn amount, so the claim that users exit with no penalty is unsupported. |
| other | opencode_1 | No event emitted for critical state changes | Transparency issue only; not a reportable protocol-level vulnerability. |
| other | opencode_1 | Uninitialized staking struct pushed to array | Solidity initializes the new struct to zero values before explicit field assignment. No exploitable behavior follows from this pattern here. |
| other | opencode_1 | Missing input validation for _stakingId in claimEarned | plans is a mapping, so out-of-range ids do not create unsafe memory access; invalid ids simply reference empty/default storage and do not create material harm. |
| duplicate_or_subsumed | opencode_1 | Unused penalty state variable | penalty is used in emergencyWithdraw. The commented burn transfer is better understood as part of the broader owner-custody issue already captured by penaltyWithdraw, not a separate standalone bug. |
