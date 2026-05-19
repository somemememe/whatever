# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 2
- updated existing findings: 0
- rejected candidates: 9

## Finding Actions
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Public exchange uses Curve with `min_dy = 0`, enabling flash-loan price manipulation and value extraction | codex_1:0.628 Public swap executes against Curve with zero slippage protection, enabling flash-loan value extraction |
| F-002 | rewritten_agent_signal | High | medium | codex_1,opencode_1 | Anyone can trigger cross-bank issuance and drain `from_bank` liquidity without authorization | opencode_1:0.338 Hardcoded Curve pool address creates centralization risk |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 2
- other: 4
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex_1 | Swapped funds are sent to `to_bank` via raw ERC20 transfer with no deposit/accounting handshake | Speculative. The available source only shows a raw token transfer into `to_bank`; there is no evidence that the destination bank requires an explicit deposit hook or that passive ERC20 receipt is insufficient for its accounting. |
| other | opencode_1 | Unchecked return value from external token bank balance call | Not a standalone vulnerability in this code. It relies on a malicious or broken `from_bank` dependency returning false data, which is outside the demonstrated trust model. |
| other | opencode_1 | Constructor makes unsafe external calls without try-catch | A constructor reverting on bad parameters or incompatible external contracts is expected deployment-time behavior, not a reportable protocol vulnerability. |
| duplicate_or_subsumed | opencode_1 | No validation of exchange output amount before transfer | Duplicate of the missing slippage protection issue. The lack of `min_dy` already captures the harmful acceptance of arbitrarily poor output. |
| low_impact_or_operational | opencode_1 | Hardcoded Curve pool address creates centralization risk | Operational rigidity / maintainability concern, but not a concrete exploitable vulnerability causing protocol-level harm on its own. |
| low_impact_or_operational | opencode_1 | No event logging for doExchange execution | Observability issue only; not a security finding. |
| unsupported_or_speculative | opencode_1 | Potential reentrancy vulnerability in safeApprove pattern | Unsupported. The function has no sensitive intermediate state to exploit via reentrancy, and the report depends on a malicious Curve/token assumption not evidenced here. |
| other | opencode_1 | Unused SafeMath library functions in main contract | Code quality issue only; not a security vulnerability. |
| other | opencode_1 | No deadline parameter in exchange function | Not a distinct vulnerability here. The meaningful economic risk is already covered by the missing slippage protection, and the function is permissionless rather than user-order driven. |
