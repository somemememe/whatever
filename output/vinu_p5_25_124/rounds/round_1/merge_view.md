# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1,opencode_1 | Hidden external controller can selectively block transfers and sells | codex_1:0.986 A hidden external controller can selectively block transfers and sells |
| F-002 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | External controller fully controls transfer debits and credits, enabling confiscation and hidden minting | codex_1:0.58 Transfer balance changes are fully attacker-controlled, enabling confiscation and hidden minting |
| F-003 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Anyone can seize 80% of any holder balance through `addLiquidityETH` and route the stolen tokens to arbitrary recipients | codex_1:0.588 Public liquidity bootstrap can seize 80% of any address balance and mint LP to an arbitrary recipient |

## Rejection Reasons
- duplicate_or_subsumed: 1
- factually_incorrect: 1
- low_impact_or_operational: 1
- other: 5

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | Incorrect UniswapV2Router Interface Causes Transfer Failure | The contract is not necessarily meant to call a standard Uniswap router here; it deliberately points at a custom contract implementing the spoofed signature. Transfers only always fail if `_router` is set to a real router, so the candidate is inaccurate as a standalone issue and is subsumed by the controller backdoor findings. |
| other | opencode_1 | Unlimited Token Approval to Router | This is part of the already-critical unrestricted `addLiquidityETH` exploit path. The overbroad approval helps the theft, but it is not a distinct issue from the arbitrary balance seizure captured in F-003. |
| other | opencode_1 | External Call Before State Update Enables Manipulation | The report describes the symptom, not the root issue. The material vulnerability is that the external controller dictates `subBal` and `addBal` without validation, which is captured in F-002. |
| low_impact_or_operational | codex_1 | Transfer events can be falsified to hide the real balance changes | The misleading event is a direct consequence of the arbitrary debit/credit backdoor in F-002. On its own it is mainly an observability issue and does not warrant a separate protocol-level finding. |
| other | opencode_1 | Missing Zero Address Check in addLiquidityETH | Passing zero addresses is a caller-inflicted configuration error that at worst reverts or self-sabotages the caller's own liquidity setup; it is not a meaningful adversarial vulnerability. |
| other | opencode_1 | Block Timestamp Dependency for Deadline | This is a generic low-signal timestamp observation on a same-block liquidity call and does not create a realistic exploit of protocol funds or availability. |
| factually_incorrect | opencode_1 | Missing Return Value Check for ERC20 approve | `approve` calls the contract's own internal `_approve`, which does not return a value and updates allowance storage directly. The candidate is technically incorrect. |
| other | opencode_1 | Public decode Function Exposes Router Address | The encoded router address is already on-chain state; exposing a pure decode helper is not a material vulnerability. |
