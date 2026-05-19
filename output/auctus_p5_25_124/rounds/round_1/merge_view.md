# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 5

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1,opencode_1 | Unverified ACO tokens let attackers sweep arbitrary writer-held ERC20 balances | codex_1:0.892 Unverified ACO tokens let attackers sweep arbitrary writer-held assets |
| F-002 | exact_agent_candidate | Critical | high | codex_1 | Caller-chosen exchange can steal the writer's entire ETH balance | codex_1:1.0 Caller-chosen exchange can steal the writer's entire ETH balance |
| F-003 | exact_agent_candidate | Critical | high | codex_1 | ETH-collateral writes can be underfunded with protocol-owned ETH | codex_1:1.0 ETH-collateral writes can be underfunded with protocol-owned ETH |
| F-004 | exact_agent_candidate | High | high | codex_1 | Premium settlement pays out whole-contract balances instead of the current trade delta | codex_1:0.857 Premium settlement uses whole-contract balances instead of per-trade deltas |
| F-005 | exact_agent_candidate | High | high | codex_1,opencode_1 | Any WETH balance can permanently brick ETH-strike writes | codex_1:0.88 Any WETH balance can brick ETH-strike writes |

## Rejection Reasons
- other: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing access control on write() function | `write()` being public is not inherently a vulnerability for this pattern. The reportable harm comes from untrusted token/exchange inputs and whole-balance accounting, which are captured in other findings. |
| other | opencode_1 | Unchecked return value on WETH.withdraw | `IWETH.withdraw(uint256)` does not return a value in the referenced interface or canonical WETH9 implementation, so there is no ignored boolean result to check. |
