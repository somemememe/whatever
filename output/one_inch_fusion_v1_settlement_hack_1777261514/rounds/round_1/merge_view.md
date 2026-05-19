# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex | Settlement executes caller-supplied interaction bytes that are not bound to the signed order payload | codex:0.802 Settlement execution accepts attacker-supplied interaction bytes outside the signed order payload |
| F-002 | rewritten_agent_signal | Critical | high | codex | Self-targeted settlement interactions allow reentrancy that satisfies `allowedSender = SETTLEMENT` | codex:0.49 Settlement can be reentered through self-targeted interactions, bypassing `allowedSender` restrictions |
| F-003 | rewritten_agent_signal | Critical | high | codex | Unchecked dynamic offset and length parsing enables calldata corruption and replay of historical orders | codex:0.67 Overflowable signature/interaction length handling enables calldata corruption and historical order replay |
| F-004 | rewritten_agent_signal | Critical | high | codex | Settlement releases real taker assets when a malicious maker token lies about transfers and balances | codex:0.362 `Counter` exposes unrestricted state mutation to all callers |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | `Counter` exposes unrestricted state mutation to all callers | `Counter.sol` is an isolated toy/example contract with no protocol funds, permissions, or integrations in this repo, so public setters on its single variable do not represent a realistic protocol-level vulnerability. |
