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
| F-001 | rewritten_agent_signal | Critical | high | codex | Proxy selector `0x03b79c24` can transfer custodied `weETH` to an attacker-controlled recipient | codex:0.533 Unauthenticated proxy entrypoint can redirect custodied weETH to an arbitrary receiver |

## Rejection Reasons
- other: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Asset release path appears unbounded by per-user accounting | The local source only proves that the selector released valuable `weETH`; it does not expose the underlying accounting logic, so there is not enough evidence to conclude that per-user share/debt limits were specifically bypassed. |
| other | codex | Sensitive maintenance or recovery selector appears left reachable on the asset-holding proxy | The raw selector call is suspicious, but without the proxied implementation or ABI there is not enough evidence to classify it as a forgotten maintenance/recovery routine rather than some other vulnerable external function. |
