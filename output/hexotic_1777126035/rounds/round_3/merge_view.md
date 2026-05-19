# Merge View - Round 3

## Summary
- total findings: 3
- new findings: 1
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- existing_preserved: 2
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-003 | rewritten_agent_signal | High | medium | codex | The OTC blindly binds to a hardcoded HEX address, so a wrong-chain deployment can settle against attacker-controlled token code | codex:0.507 Hardcoded HEX address is never validated against the deployment chain or expected bytecode |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | HEX escrow records the requested amount instead of the amount actually received | Not reportable as a standalone issue here because the token is hardcoded to HEX rather than user-selectable; the short-transfer or fee-on-transfer failure mode only becomes exploitable if the contract is bound to unexpected token code, which is captured by F-003. |
| duplicate_or_subsumed | codex | Trade settlement trusts ERC20 return values instead of verifying token balance changes | Rejected as a separate finding because the contract does not accept arbitrary ERC20s. The realistic exploit requires the hardcoded `hexAddress` to point to non-HEX or attacker-controlled code, so this behavior is subsumed by F-003 rather than standing alone. |
