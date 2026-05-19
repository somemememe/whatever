# Merge View - Round 1

## Summary
- total findings: 1
- new findings: 1
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | medium | codex | Pair self-transfer via `skim(pair)` appears to inflate SBR balances and enables AMM liquidity theft | codex:0.675 Pair self-transfer via `skim(pair)` can mint or duplicate SBR balances |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Manipulated pair balance can be locked in with `sync()` and dumped to drain ETH liquidity | Merged into `F-001` as an exploitation step and impact amplifier of the same underlying balance-inflation bug, not a distinct root-cause finding. |
