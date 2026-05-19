# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 6

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | medium | codex_1 | Unchecked ERC20 return values let stake and unstake proceed even when token transfers silently fail | codex_1:0.756 Unchecked ERC20 return values let staking and unstaking succeed without the token transfer actually succeeding |
| F-002 | exact_agent_candidate | High | medium | codex_1 | Nominal-amount accounting makes the pool insolvent against fee-on-transfer or deflationary tokens | codex_1:1.0 Nominal-amount accounting makes the pool insolvent against fee-on-transfer or deflationary tokens |
| F-003 | exact_agent_candidate | High | medium | codex_1 | Reentrant distributor can apply the same epoch reward multiple times before `epoch.distribute` is refreshed | codex_1:1.0 Reentrant distributor can apply the same epoch reward multiple times before `epoch.distribute` is refreshed |
| F-004 | exact_agent_candidate | Medium | high | codex_1 | Missing validation for zero epoch length allows unbounded same-timestamp rebases after the first epoch | codex_1:0.864 Missing validation for zero epoch length allows unbounded same-block rebases once the first epoch starts |
| F-005 | rewritten_agent_signal | Low | high | codex_1 | `secondsToNextEpoch()` reverts when the epoch is overdue | codex_1:0.541 Overdue epochs make `secondsToNextEpoch()` revert due to underflow |

## Rejection Reasons
- other: 4
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | stake() uses transfer instead of mint - will fail for new stakers | `sTOKEN.transfer(_to, _amount)` is executed by the staking contract, not by the staker. This pattern is compatible with pre-minted receipt-token inventory held by the staking contract, so the code alone does not show that new stakers are unable to stake. |
| trust_or_owner_model | opencode_1 | Owner can set malicious distributor to steal funds during rebase | This is a trusted-owner/admin-power statement, not a distinct vulnerability in the contract logic. If the owner is malicious, they already control distributor configuration by design. |
| other | opencode_1 | Unstake can permanently lock user funds if TOKEN balance is insufficient | The `require` check happens in the same transaction after `sTOKEN.transferFrom`. If it fails, the entire transaction reverts and the prior token transfer is rolled back; user funds are not permanently trapped by this code path. |
| unsupported_or_speculative | opencode_1 | No slippage protection on unstake - users may receive less than expected | `unstake()` is a fixed nominal redemption path, not a price-discovery swap. The cited concern is too speculative without a concrete mechanism showing users can receive an unexpectedly lower amount than `_amount` from this contract. |
| other | opencode_1 | No slippage protection on stake - users may receive less sTOKEN than expected | `stake()` transfers a fixed `_amount` of sTOKEN after taking `_amount` TOKEN. The report does not establish a concrete price movement or rounding path inside this contract that would make the received amount variable. |
| other | opencode_1 | Unused internal function _send() | Dead code is informational only and does not create realistic protocol-level harm on its own. |
