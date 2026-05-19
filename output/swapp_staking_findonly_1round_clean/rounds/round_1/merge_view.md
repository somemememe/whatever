# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 0

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex | Unchecked Compound error codes desynchronize stablecoin accounting and can block withdrawals | codex:0.412 A single failed Compound mint can permanently brick future stablecoin deposits |
| F-002 | rewritten_agent_signal | Medium | high | codex | Emergency withdrawals leave epoch checkpoints and pool sizes unchanged | codex:0.577 Emergency withdrawals remove principal without removing epoch stake checkpoints |
| F-003 | exact_agent_candidate | High | medium | codex | Arbitrary ERC20 deposits are credited by the requested amount instead of the actual amount received | codex:0.916 Arbitrary ERC20 deposits are credited by requested amount instead of actual tokens received |
| F-004 | exact_agent_candidate | High | high | codex | A single failed Compound mint can permanently brick future stablecoin deposits for that market | codex:0.907 A single failed Compound mint can permanently brick future stablecoin deposits |

## Rejection Reasons
- none
