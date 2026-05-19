# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 9

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | Unchecked ERC20 return values can mint unbacked stake receipts or release QWA without burning sQWA | codex_1:1.0 Unchecked ERC20 return values can mint unbacked stake receipts or release QWA without burning sQWA |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Missed-epoch rewards can be captured by late entrants because `rebase()` only catches up one epoch per call | codex_1:0.828 Missed epochs can be stolen by new stakers because `rebase()` only catches up one epoch per call |
| F-003 | exact_agent_candidate | Medium | medium | codex_1 | Predictable epoch boundaries enable just-in-time staking to siphon epoch rewards | codex_1:0.909 Predictable epoch boundaries allow just-in-time staking to siphon each epoch's reward |
| F-004 | rewritten_agent_signal | Medium | low | codex_1 | Nominal-amount accounting can undercollateralize the pool if QWA transfers less than the requested amount | codex_1:0.469 Nominal-amount accounting breaks on fee-on-transfer or deflationary QWA and can leave the pool insolvent |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 5
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | `secondsToNextEpoch()` reverts instead of reporting zero once an epoch is overdue | Real underflow in a view function, but it is an off-chain/integration nuisance only and does not create meaningful protocol-level fund loss, lockup, or exploitable on-chain behavior. |
| trust_or_owner_model | opencode_1 | Missing zero-address validation in constructor | Deployment-time misconfiguration by the privileged deployer, not a permissionless exploit against a live protocol. |
| trust_or_owner_model | opencode_1 | Missing zero-address validation in setDistributor | Setting the distributor to zero only disables distribution until the owner sets a new address again; it is recoverable privileged misconfiguration, not a permanent exploit path. |
| unsupported_or_speculative | opencode_1 | Missing reentrancy guard on stake function | Speculative. The report does not show a concrete reentrant path that breaks staking invariants beyond assuming malicious core token contracts, and this contract keeps almost no internal accounting to corrupt. |
| other | opencode_1 | Unstake with rebase can fail due to insufficient balance check | Not an independent bug. The check only fails when the pool is already undercollateralized for some other reason; `unstake(_rebase=true)` is exposing insolvency rather than creating it. |
| duplicate_or_subsumed | opencode_1 | Anyone can trigger rebase leading to MEV/front-running | Public `rebase()` is expected behavior for this design. The only concrete timing harm here is the separate just-in-time staking reward siphon already captured in F-003. |
| other | opencode_1 | No access control allows anyone to stake to any address | Allowing deposits on behalf of another address is standard and does not by itself create realistic protocol harm. |
| other | opencode_1 | Lack of event emission for setDistributor | Transparency/operability issue only, not a security finding. |
| other | opencode_1 | Potential integer overflow in epoch.end update | Solidity 0.8.19 has checked arithmetic, so overflow reverts instead of wrapping, and the scenario is not realistically reachable. |
