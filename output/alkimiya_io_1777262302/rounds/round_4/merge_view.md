# Merge View - Round 4

## Summary
- total findings: 4
- new findings: 1
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-004 | exact_agent_candidate | Medium | medium | codex | Exhaustive 1,800-call bounty sweep can make the recovery transaction unexecutable | codex:1.0 Exhaustive 1,800-call bounty sweep can make the recovery transaction unexecutable |

## Rejection Reasons
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Profit check can be satisfied by preloaded ERC20/WETH balances even when no bounty is recovered | The code does only snapshot ETH, so donated supported tokens can indeed satisfy the threshold, but this does not create a distinct protocol-level harm here: the donated assets are the caller's own funds, there is no privileged success signal or payout to misdirect, and any resulting balances are already permanently locked by F-001. |
