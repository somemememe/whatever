# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 6

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Medium | medium | codex_1,merge_reviewer | Caller-controlled allowance targets can leave persistent approvals that later drain stranded tokens | codex_1:0.663 Caller-controlled approvals create persistent drain rights over stranded tokens |
| F-002 | exact_agent_candidate | Medium | high | codex_1,opencode_1,merge_reviewer | Unchecked ERC20 return values allow silent transfer and approval failures | codex_1:1.0 Unchecked ERC20 return values allow silent transfer and approval failures |
| F-003 | exact_agent_candidate | Medium | medium | codex_1,opencode_1,merge_reviewer | Non-zero-to-non-zero approvals can permanently brick zero-first tokens on common routes | codex_1:0.994 Non-zero-to-non-zero approvals can permanently brick zero-first tokens on common routers |
| F-004 | exact_agent_candidate | Low | high | codex_1,opencode_1,merge_reviewer | Native-ETH zaps accept overpayment and trap the surplus for governance | codex_1:1.0 Native-ETH zaps accept overpayment and trap the surplus for governance |
| F-005 | rewritten_agent_signal | Medium | low | codex_1,opencode_1,merge_reviewer | zapOut uses the requested withdrawal amount instead of the amount actually delivered by the batcher | codex_1:0.704 zapOut trusts the nominal withdrawal amount instead of measuring what the batcher actually delivered |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 1
- other: 2
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing slippage protection for batcher withdrawal in zapOut | Final-output slippage is already user-bounded by `minAmountOut`; the reportable edge case is the separate stale-balance subsidy issue captured in F-005, not a generic lack of slippage protection. |
| trust_or_owner_model | opencode_1 | No zero-address validation for governance in sweep | This only turns a governance misconfiguration into governance self-harm; it is not a permissionless or protocol-level exploit in the zapper itself. |
| low_impact_or_operational | opencode_1 | Missing event emissions for governance operations | Observability issue only; no realistic fund-loss, theft, lockup, or DoS impact. |
| duplicate_or_subsumed | opencode_1 | Unchecked call return values in zap function | The low-level call success flag is checked, and swap success is further bounded by balance-delta plus `minAmountOut`; the meaningful risk from a no-op target is the persistent arbitrary approval issue already captured in F-001/F-003. |
| other | opencode_1 | Floating pragma allows incompatible compiler versions | Informational build-hygiene concern, not a concrete protocol-level vulnerability. |
| trust_or_owner_model | opencode_1 | No access control on critical functions | `sweep()` is explicitly restricted to `vault.governance()`; a compromised governance key is an out-of-scope trust assumption, not a missing access control bug. |
