# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 0

## Finding Actions
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex | Shared router/gateway allowlist plus sticky max approvals lets allowlisted spenders drain proxy tokens | codex:0.365 Gateway approvals are infinite and never revoked, surviving even router removal |
| F-003 | rewritten_agent_signal | High | high | codex | Fee-on-transfer tokens can make the proxy subsidize routes from pre-existing balances | codex:0.634 Deflationary or fee-on-transfer tokens can drain pre-existing proxy balances |
| F-004 | rewritten_agent_signal | Medium | medium | codex | Refunded or unspent native value can be trapped in the proxy | codex:0.42 Configured per-token min/max limits are dead code and can be bypassed entirely |
| F-005 | rewritten_agent_signal | Low | high | codex | Configured per-token min/max amount limits are never enforced | codex:0.691 Configured per-token min/max limits are dead code and can be bypassed entirely |

## Rejection Reasons
- none
