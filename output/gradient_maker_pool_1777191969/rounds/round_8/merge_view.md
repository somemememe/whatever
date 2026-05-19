# Merge View - Round 8

## Summary
- total findings: 17
- new findings: 1
- updated existing findings: 2
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 14
- existing_rewritten: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-015 | existing_rewritten | Medium | medium | codex | Blocking a token freezes the orderbook repayment path while the pool can still accept fresh liquidity | codex:0.414 Blocked tokens still accept fresh liquidity because deposits bypass the blocklist circuit breaker |
| F-021 | existing_rewritten | Low | high | codex | Small fee distributions are permanently stranded because reward dust is never carried forward | codex:0.427 Changing the registry/orderbook can permanently strand assets already borrowed by the old orderbook |
| F-023 | exact_agent_candidate | Medium | high | codex | Changing the registry or orderbook can strand assets already borrowed by the previous orderbook | codex:0.866 Changing the registry/orderbook can permanently strand assets already borrowed by the old orderbook |

## Rejection Reasons
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Orderbook settlements are unconstrained, so borrowed pool assets can be repaid at an arbitrary bad price | Rejected as a separate finding because settlement is already fully trusted to the authorized `orderbook` contract, which can withdraw inventory directly; without the orderbook implementation or stronger on-chain price invariants promised by this contract, this is primarily a trust-model observation rather than a distinct reportable bug in the pool. |
