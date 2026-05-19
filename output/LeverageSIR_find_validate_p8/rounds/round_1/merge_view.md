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
| F-001 | rewritten_agent_signal | Critical | high | codex | Funded vault can be initialized by anyone with attacker-chosen market parameters | codex:0.434 Uniswap V3 callback can be abused to make the vault pay arbitrary deltas |
| F-002 | rewritten_agent_signal | Critical | medium | codex | Attacker-controlled token return data is reused as privileged transient callback state | codex:0.739 Untrusted token return data is promoted into privileged transient state |
| F-003 | rewritten_agent_signal | Critical | high | codex | `uniswapV3SwapCallback` can be driven with crafted data to drain arbitrary vault-held tokens | codex:0.573 Uniswap V3 callback can be abused to make the vault pay arbitrary deltas |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Callback settlement asset is attacker-selected, enabling theft of unrelated vault balances | Merged into F-003 rather than kept separate. The attacker-selected settlement token is part of the same callback-validation failure, not a distinct root-cause issue. |
