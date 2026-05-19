# Merge View - Round 1

## Summary
- total findings: 1
- new findings: 1
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex | Caller-controlled router target and calldata let anyone drain third-party ERC20 allowances | codex:1.0 Caller-controlled router target and calldata let anyone drain third-party ERC20 allowances |

## Rejection Reasons
- other: 1
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Integrator identity is caller-supplied, enabling impersonation of trusted integrators | The local source only shows that an `integrator` address is passed through calldata in the exploit harness; it does not demonstrate that this value is authenticated, privileged, or materially changes authorization. The harmful behavior is already explained by the arbitrary router call itself. |
| other | codex | The native-call entrypoint can be invoked with zero input and zero recipient checks, turning it into a free arbitrary-call gadget | This is not a distinct root cause from the confirmed arbitrary-call bug. The zeroed asset/recipient fields shown in the PoC are consequences of the same issue and do not independently demonstrate additional protocol harm beyond the allowance-drain finding. |
