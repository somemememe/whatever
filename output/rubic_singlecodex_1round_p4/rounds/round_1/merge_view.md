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
| F-001 | rewritten_agent_signal | Medium | high | codex | Gateway max allowances persist after router deauthorization | codex:0.37 Gateway approvals are left at `type(uint256).max` and survive router removal |
| F-002 | rewritten_agent_signal | High | medium | codex | ERC20 routes spend the declared amount instead of the amount actually received | codex:0.832 ERC20 routes trust the nominal input amount instead of the amount actually received |
| F-003 | rewritten_agent_signal | Medium | high | codex | Users can impersonate any integrator to obtain its custom fee schedule | codex:0.769 Any caller can impersonate a discounted integrator and inherit its custom fee schedule |
| F-005 | rewritten_agent_signal | Low | medium | merge-review | Configured per-token min/max limits are never enforced | codex:0.277 ERC20 routes trust the nominal input amount instead of the amount actually received |

## Rejection Reasons
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex | Request events can advertise arbitrary bridge parameters that are not bound to actual execution | The issue is event-only in this codebase. `RequestSent` merely echoes user-supplied parameters after a successful call, and no on-chain logic here relies on that event. The claimed harm depends on unspecified off-chain consumers, so it is too speculative to report as a protocol vulnerability. |
