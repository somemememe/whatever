# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 9

## Finding Actions
- exact_agent_candidate: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Unbounded `stakeWeek` lets a staker mint an arbitrarily large bonus and drain the pool | codex_1:1.0 Unbounded `stakeWeek` lets a staker mint an arbitrarily large bonus and drain the pool |
| F-003 | exact_agent_candidate | High | high | codex_1 | Reward emissions are underfunded because `rewardTokens` do not cover bonus liabilities | codex_1:1.0 Reward emissions are underfunded because `rewardTokens` do not cover bonus liabilities |
| F-004 | exact_agent_candidate | High | high | codex_1 | Owner can rug accrued user rewards through `rescueReward` | codex_1:1.0 Owner can rug accrued user rewards through `rescueReward` |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 6
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | Long-lock bonus is claimable immediately without completing the advertised lock | Not clearly a distinct vulnerability from code alone. The contract formula pays a boosted reward stream while principal remains locked; harvesting before maturity changes payout timing, but the main reportable harm is already captured by the uncapped bonus and unfunded bonus-liability findings. |
| other | opencode_1 | Double counting of pending rewards in unstake causes incorrect reward accounting | False positive. `rewardDebt += pending` happens only after the position is fully paid and marked unstaked, so it does not create a second claim path or protocol loss. |
| other | opencode_1 | Hardcoded token address with no validation | Deployment/configuration choice, not an exploitable runtime flaw in the reviewed contract logic. |
| trust_or_owner_model | opencode_1 | No mechanism to extend staking period | Product/governance limitation only; no realistic fund-loss or denial-of-service scenario follows from the code alone. |
| other | opencode_1 | Integer truncation in rewardPerSecond calculation causes precision loss | At most leaves minor undistributed dust due to integer division. This is not material protocol harm. |
| other | opencode_1 | No access control or validation on stakingCount access | Nonexistent indices resolve to zeroed storage and are already harmlessly rejected by the `stakedAmount > 0` check. |
| other | opencode_1 | No pausable mechanism for emergency stop | Generic best-practice suggestion, not a concrete vulnerability. |
| other | opencode_1 | No deadline validation for harvest after staking ends | False positive. `_getMultiplier()` caps reward accrual at `stakingEndTime`, so harvesting after program end only claims already-accrued rewards. |
| trust_or_owner_model | opencode_1 | startStaking is irreversible with no recovery mechanism | Admin UX/governance limitation only; not a security issue by itself. |
