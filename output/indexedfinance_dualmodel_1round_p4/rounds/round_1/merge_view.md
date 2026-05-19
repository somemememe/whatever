# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Manipulable market-cap inputs let anyone force bad constituents and weights during permissionless rebalances | codex_1:0.281 Permissionless rebalances trust manipulable thin-liquidity market caps |
| F-002 | rewritten_agent_signal | Medium | medium | codex_1 | Instantaneous `totalSupply()` reads let supply-manipulable tokens spoof market cap and weights | codex_1:0.791 Instantaneous `totalSupply()` reads let flash-mintable or rebase tokens spoof market cap |
| F-003 | rewritten_agent_signal | Low | medium | codex_1 | Permissionless minimum-balance updates can grief newly added tokens via manipulable value estimates | codex_1:0.544 Permissionless rebalances trust manipulable thin-liquidity market caps |
| F-004 | rewritten_agent_signal | High | low | codex_1 | Uninitialized owner proxies are first-call ownable if deployment does not atomically initialize them | codex_1:0.308 First caller can seize an uninitialized controller proxy |

## Rejection Reasons
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex_1 | Category ID truncation can silently bind a pool to the wrong category | Requires the owner to create more than 65,535 categories before preparing a new pool; this is an extremely remote administrative edge case rather than a realistic protocol exploit path. |
