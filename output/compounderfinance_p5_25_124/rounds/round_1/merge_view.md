# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Curve deposits and exits execute with zero slippage protection, enabling MEV extraction | codex_1:0.531 Curve entry and exit paths accept arbitrary prices, enabling sandwich theft |
| F-002 | rewritten_agent_signal | Medium | medium | codex_1 | Partial withdrawals can return less DAI than requested because unwind sizing assumes frictionless prices | codex_1:0.488 Partial withdrawals are sized from optimistic spot values and can silently return less than requested |
| F-003 | rewritten_agent_signal | Low | low | codex_1 | Strategy accounting marks yyCRV to model value instead of executable DAI exit value | codex_1:0.428 Reported TVL depends on manipulable external spot values rather than realizable exit value |

## Rejection Reasons
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex_1 | Dust-sweep function can pull principal assets to the controller and bypass vault-only return paths | `controller` is already the strategy's fully privileged trust anchor and is the only caller allowed to trigger partial/full withdrawals. Allowing it to sweep arbitrary tokens is an operational/governance trust-model risk, not a distinct permissionless or unintended escalation in this contract. |
