# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex | Old proxy credits fee-on-transfer inputs at the user-declared amount, allowing theft from pre-existing token balances | codex:1.0 Old proxy credits fee-on-transfer inputs at the user-declared amount, allowing theft from pre-existing token balances |
| F-002 | exact_agent_candidate | High | high | codex | Old proxy leaves permanent max approvals to gateways, exposing all future balances to gateway compromise or abuse | codex:1.0 Old proxy leaves permanent max approvals to gateways, exposing all future balances to gateway compromise or abuse |
| F-003 | exact_agent_candidate | Low | high | codex | Any caller can impersonate a privileged integrator and inherit its custom fee schedule | codex:1.0 Any caller can impersonate a privileged integrator and inherit its custom fee schedule |
| F-006 | rewritten_agent_signal | Medium | medium | merge-review | Native router calls do not refund or account for unspent ETH returned to the proxy | codex:0.303 Configured min/max token limits are dead code and never enforced at the entrypoints |

## Rejection Reasons
- other: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Router and gateway are authorized independently, so approvals can be combined with an unrelated whitelisted call target | Exploitability depends on external whitelisted routers exposing arbitrary forwarding or multicall behavior; the scoped code alone does not establish a concrete permissionless abuse path. |
| other | codex | Configured min/max token limits are dead code and never enforced at the entrypoints | The mappings are indeed unused, but the demonstrated effect is mainly operator misconfiguration and policy drift; the scoped code does not show a concrete theft, permanent lockup, or permissionless DoS outcome. |
