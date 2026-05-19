# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 6
- updated existing findings: 0
- rejected candidates: 0

## Finding Actions
- rewritten_agent_signal: 6

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex | Unchecked ERC20 transfer return values allow phantom deposits and silent failed withdrawals | codex:0.541 Unchecked ERC20 return values let attackers mint phantom stake without transferring tokens |
| F-002 | rewritten_agent_signal | High | high | codex | Deposits credit the requested amount instead of the tokens actually received | codex:0.846 Deposits trust the requested amount instead of the actual tokens received |
| F-003 | rewritten_agent_signal | High | high | codex,merge-review | Emergency withdrawal lets users recover principal while retaining stale epoch stake, and untouched pools are immediately eligible | codex:0.471 Emergency withdrawals remove funds but leave reward checkpoints and pool snapshots untouched |
| F-004 | rewritten_agent_signal | Medium | high | codex | Any small withdrawal can indefinitely grief the emergency-exit timer for an entire token pool | codex:0.845 A dust withdraw can permanently grief the global emergency-exit timer for an entire token pool |
| F-005 | rewritten_agent_signal | Medium | high | codex | Dormant pools become unusable until every missed epoch is initialized one transaction at a time | codex:0.829 Idle pools become unusable because each missed epoch must be initialized one transaction at a time |
| F-006 | rewritten_agent_signal | Medium | high | codex | Ignored Compound error codes can desynchronize stablecoin accounting from real liquidity | codex:0.667 Compound mint/redeem error codes are ignored, so stablecoin accounting can diverge from reality |

## Rejection Reasons
- none
