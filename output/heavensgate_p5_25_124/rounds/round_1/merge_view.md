# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 6

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Post-expiry stakes are miscounted as distributable rewards, creating undercollateralized sHATE | codex_1:0.552 Post-expiry stakes are counted as both backing and next-epoch rewards |
| F-002 | exact_agent_candidate | High | high | codex_1 | If staking is multiple epochs behind, the fake reward can be realized immediately | codex_1:0.854 If the contract is multiple epochs behind, the poisoned reward can be realized immediately |
| F-003 | rewritten_agent_signal | Medium | medium | codex_1,opencode_1 | Raw ERC20 interactions assume strict no-fee, full-return token semantics | opencode_1:0.38 Unchecked ERC20 transfer return values in stake() |

## Rejection Reasons
- other: 4
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing reentrancy protection on stake() and unstake() | No exploitable state machine beyond token movements was identified; the scenario depends on malicious or highly non-standard token behavior and is better captured by the ERC20-semantics finding rather than as a separate reentrancy issue. |
| unsupported_or_speculative | opencode_1 | No slippage protection in stake() and unstake() | These functions exchange fixed nominal amounts against the staking contract, not an AMM price curve. The suggested sandwich/front-run path is unsupported by the code. |
| trust_or_owner_model | opencode_1 | Unvalidated distributor address in setDistributor() | `setDistributor()` is an `onlyOwner` configuration hook. A malicious or broken owner-selected distributor is a trust/administration assumption, not a permissionless protocol vulnerability shown by this code. |
| other | opencode_1 | Race condition in unstake() balance check | If the final balance check fails, the entire transaction reverts, including the preceding `sHATE.transferFrom()`. The proposed path does not cause users to lose funds. |
| other | opencode_1 | Missing zero address validation in setDistributor() | `rebase()` explicitly skips distributor interaction when `address(distributor) == address(0)`, so setting zero does not brick staking. |
| other | opencode_1 | Timestamp manipulation in epoch timing | This is only the usual minor `block.timestamp` drift and does not produce realistic protocol-level harm here. |
