# Merge View - Round 3

## Summary
- total findings: 11
- new findings: 3
- updated existing findings: 1
- rejected candidates: 0

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 7
- existing_rewritten: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-003 | existing_rewritten | High | high | codex,merge-review | Emergency withdrawal lets users recover principal while retaining stale epoch stake, and untouched pools are immediately eligible | codex:0.286 Leftover Compound allowance can permanently freeze new stablecoin deposits |
| F-007 | exact_agent_candidate | Medium | low | codex,merge-review | Anyone can reinitialize epoch 0 to zero and corrupt pre-launch stake snapshots | codex:0.857 Anyone can reset epoch 0 to zero and erase pre-launch stake snapshots |
| F-010 | exact_agent_candidate | Low | high | codex,merge-review | Permissionless interest-skimming sweeps accidental stablecoin or cToken transfers to the team wallet | codex:1.0 Permissionless interest-skimming sweeps accidental stablecoin or cToken transfers to the team wallet |
| F-011 | rewritten_agent_signal | Medium | high | codex,merge-review | A failed Compound mint can leave a non-zero allowance that blocks all future stablecoin deposits | codex:0.565 Leftover Compound allowance can permanently freeze new stablecoin deposits |

## Rejection Reasons
- none
