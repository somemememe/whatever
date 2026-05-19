# Merge View - Round 5

## Summary
- total findings: 19
- new findings: 4
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- existing_preserved: 15
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-017 | rewritten_agent_signal | Medium | low | codex_1 | Treasury flow underflow clamp can stop funding for unrelated active programs after flow drift | codex_1:0.469 Shared treasury inflow is hard-clamped to zero when a single program decrement exceeds current flow |
| F-018 | rewritten_agent_signal | Low | high | codex_1 | Minimum unlock amount can strand sub-10 SUP locker balances | codex_1:0.631 Hard minimum unlock amount can permanently strand balances below 10 SUP |
| F-019 | rewritten_agent_signal | Medium | high | codex_1 | Liquidity withdrawal applies an extra 5% haircut to caller-provided minimums | codex_1:0.507 Liquidity withdrawal silently weakens caller minima by an extra 5% |
| F-020 | rewritten_agent_signal | Low | high | codex_1 | Factory ETH fees can become stuck when governor is a contract receiver | codex_1:0.566 Factory ETH withdrawal uses `transfer`, risking fee lock if governor is a contract |

## Rejection Reasons
- duplicate_or_subsumed: 4
- low_impact_or_operational: 1
- other: 2
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | Double funding of programs creates cumulative stream conflicts | Duplicate of F-004; the retained finding already covers repeated `startFunding()` overwriting stored details while aggregate streams accumulate and later leave residual flow components. |
| duplicate_or_subsumed | opencode_1 | Pumponomics swap has zero minimum output protection | Duplicate of F-005; retained severity is Medium because the unbounded swap applies to the 1% pump leg rather than the full liquidity provision. |
| duplicate_or_subsumed | opencode_1 | Tax adjustment distribution uses volatile balance without snapshot | The permissionless current-snapshot risk is already captured by F-012. The added deposit-manipulation theory is not independently profitable because depositing FLUID into the controller is a donation unless the attacker already owns the relevant pool units. |
| duplicate_or_subsumed | opencode_1 | Fontaine termination allows anyone in final day window | Duplicate of F-006; retained as Low because funds still go to the recipient and tax pools, with harm limited to timing and snapshot manipulation. |
| low_impact_or_operational | opencode_1 | Liquidity provision missing event emission | Missing events are an observability and indexing concern, not direct protocol-level fund loss, insolvency, lockup, economic manipulation, or permissionless DoS. |
| other | opencode_1 | Vesting contract creation lacks amount validation for zero | `amount == 0` cannot pass `cliffAmount >= amount`, so the alleged zero-amount vest creation reverts. Other bad vesting parameters are admin-controlled input failures rather than an attacker-exploitable protocol issue. |
| trust_or_owner_model | opencode_1 | Locker withdrawal uses transfer instead of call for ETH | `withdrawDustETH()` uses Uniswap `TransferHelper.safeTransferETH`, not Solidity `transfer`; a locker owner contract that refuses ETH can only block its own receipt and does not create protocol-level harm. |
| other | codex_1 | Public initializer takeover risk if proxies are ever deployed without atomic init | This is a generic deployment caveat rather than a concrete in-code exploit path. Implementations disable initializers, and the in-scope BeaconProxy creations are followed by initialization within the same transaction with no external interleaving. |
