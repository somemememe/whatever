# Merge View - Round 1

## Summary
- total findings: 1
- new findings: 1
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex | Public `routerCallNative` lets callers execute arbitrary token `transferFrom` calls through the proxy and steal approved funds | codex:0.395 User-controlled router target and raw calldata let attackers steal from any address that approved the proxy |

## Rejection Reasons
- other: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Integrator identity appears spoofable, allowing public callers to inherit privileged routing permissions | The reproduction hard-codes one `integrator` value, but the available code does not show that `integrator` is authenticated, permission-gating, or even consulted by the vulnerable path. The demonstrated theft is fully explained by arbitrary router target plus arbitrary calldata forwarding, so integrator spoofing is not independently supported. |
| other | codex | Declared swap/bridge parameters are not enforced against actual token movement | The evidence only shows that these fields can be nonsensical while the arbitrary external call still succeeds. That is a symptom of the core arbitrary-call bug, not a distinct root cause with separate incremental impact, so it is merged into F-001 rather than kept as a separate finding. |
