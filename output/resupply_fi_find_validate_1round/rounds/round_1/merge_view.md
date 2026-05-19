# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 4
- updated existing findings: 0
- rejected candidates: 0

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 2
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-004 | exact_agent_candidate | High | high | codex | Convex pool migration can hide live collateral and freeze withdrawals/redemptions | codex:1.0 Convex pool migration can hide live collateral and freeze withdrawals/redemptions |
| F-005 | rewritten_agent_signal | High | medium | codex | Invalidating the write-off reward disables redemption loss socialization | codex:0.568 The write-off token can be invalidated like a normal reward, disabling redemption loss accounting |
| F-006 | rewritten_agent_signal | Medium | high | codex | Reverting reward hook or reward `balanceOf` can brick checkpointed core operations | codex:0.752 Any reverting reward hook or reward token can brick core lending operations |
| F-007 | rewritten_agent_signal | Medium | low | codex | Interest accrual past the `uint128` debt cap silently skips the elapsed period | codex:0.333 Interest overflow silently forgives an entire accrual period |

## Rejection Reasons
- none
