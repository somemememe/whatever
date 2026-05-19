# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | medium | codex | Forged interaction offsets can redirect settlement parsing into an attacker-supplied historical settlement suffix | codex:0.417 Unchecked interaction offsets allow forged calldata to wrap into attacker-controlled settlement context |
| F-003 | rewritten_agent_signal | High | high | codex | Universal ERC1271 approval plus standing USDT allowance lets anyone drain contract-held USDT | codex:0.393 Contract is a universal ERC1271 signer for arbitrary attacker-created orders |
| F-004 | rewritten_agent_signal | Medium | high | codex | Permissionless zero-min-output swaps expose contract balances to sandwich extraction | codex:0.425 Public zero-slippage swaps let MEV attackers extract nearly all traded value |
| F-005 | exact_agent_candidate | Medium | high | codex | Any user can permanently consume the one-shot execution path | codex:0.915 Any user can permanently brick the one-shot execution path |

## Rejection Reasons
- other: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Historical victim authorization is replayable without fresh binding to the current order | Merged into `F-001`: the historical victim-context replay is the concrete consequence of the forged-offset parser-confusion issue, not a separate root cause. |
| unsupported_or_speculative | codex | Resolver hook is an always-successful no-op that validates nothing except caller address | Too speculative as a standalone report: the current codebase never configures or uses this contract as an active resolver in a concrete asset-moving path, so realistic protocol impact is not established. |
