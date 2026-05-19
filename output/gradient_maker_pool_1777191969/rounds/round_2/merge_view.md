# Merge View - Round 2

## Summary
- total findings: 6
- new findings: 2
- updated existing findings: 1
- rejected candidates: 3

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 3
- existing_rewritten: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-004 | existing_rewritten | High | high | codex | Fee-on-transfer or deflationary tokens are over-credited, creating unbacked LP balances | codex:0.447 Rebasing or confiscatory tokens can desync stored balances and brick exits |
| F-006 | exact_agent_candidate | Medium | high | codex | Small deposits can mint zero LP shares and become permanently stuck | codex:1.0 Small deposits can mint zero LP shares and become permanently stuck |
| F-007 | rewritten_agent_signal | Medium | medium | codex | Rebasing or confiscatory tokens can desynchronize accounting and lock LP exits | codex:0.763 Rebasing or confiscatory tokens can desync stored balances and brick exits |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 1
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Orderbook settlement over-credits taxed tokens and can poison pool solvency | Duplicate of existing finding `F-004`, which already covers over-crediting on both `provideLiquidity` and `receiveTokenFromOrderbook`. |
| trust_or_owner_model | codex | Owner emergency withdrawal is an unbounded rug lever that leaves LP state insolvent | `emergencyWithdraw` / `emergencyWithdrawETH` are explicit `onlyOwner` escape hatches; absent a contrary trust model, this is an acknowledged privileged capability rather than a code vulnerability. |
| other | codex | `minTokenAmount` does not provide the advertised slippage protection | The parameter is indeed redundant and misleading, but by itself it does not create a distinct protocol-level loss or lockup beyond the already-reported reserve-manipulation issue in `F-003`. |
