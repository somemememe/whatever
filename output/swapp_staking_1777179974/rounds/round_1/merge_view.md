# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 0

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex | Zero-amount withdrawals can permanently disable emergency exits for an entire token | codex:1.0 Zero-amount withdrawals can permanently disable emergency exits for an entire token |
| F-002 | rewritten_agent_signal | High | high | codex | Emergency withdrawals let users recover principal while remaining counted in epoch accounting | codex:0.645 Emergency withdrawals remove principal without clearing staking checkpoints or pool snapshots |
| F-003 | exact_agent_candidate | Medium | medium | codex | Historical pool sizes are retroactively mutable for uninitialized epochs | codex:0.855 Historical pool sizes are retroactively mutable for any epoch left uninitialized |
| F-004 | rewritten_agent_signal | High | high | codex | Arbitrary-token deposits credit the requested amount even when fewer or no tokens are received | codex:0.731 Arbitrary-token deposits credit the requested amount instead of the amount actually received |
| F-005 | rewritten_agent_signal | Medium | medium | codex | Ignored Compound error codes can leave stablecoin accounting in a silently failed state | codex:0.383 Compound error codes are ignored, allowing silent redemption and mint failures to desynchronize accounting |

## Rejection Reasons
- none
