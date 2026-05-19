# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 5

## Finding Actions
- exact_agent_candidate: 2
- new_unmatched: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | ERC1155 mint callback reentrancy lets contract stakers mint the same pending points repeatedly | codex_1:1.0 ERC1155 mint callback reentrancy lets contract stakers mint the same pending points repeatedly |
| F-002 | exact_agent_candidate | High | high | codex_1 | Pool accounting becomes insolvent with fee-on-transfer or balance-decreasing stake tokens | codex_1:0.859 Pool accounting is insolvent for fee-on-transfer or balance-mutating stake tokens |
| F-003 | new_unmatched | Medium | high |  | Reward parameter changes retroactively rewrite past emissions for untouched pools | opencode_1:0.367 Missing Event Emission for Shop Setting |

## Rejection Reasons
- factually_incorrect: 1
- low_impact_or_operational: 1
- other: 2
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Reward Theft via Emergency Withdraw Without Pool Update | `emergencyWithdraw()` zeroes both `user.amount` and `user.rewardDebt` before returning funds. The caller has no stake left to claim from any later `accPointsPerShare` change, so this does not let them steal other users' rewards. |
| trust_or_owner_model | opencode_1 | Uninitialized Shop Variable Causes Contract Lock | `shop` being unset at deployment is an initialization requirement, not a permanent lock vulnerability. The owner can set it later through `setShop()`, so this is at most an operational/configuration concern. |
| factually_incorrect | opencode_1 | Missing Pool ID Bounds Check | Dynamic array indexing already reverts on out-of-bounds access in Solidity. That is the standard safeguard here, and the claim about reading stale storage past array bounds is incorrect. |
| other | opencode_1 | Precision Loss in Reward Distribution | Integer truncation dust is expected in share-based reward accounting and no concrete exploit or material protocol harm was shown from these divisions. |
| low_impact_or_operational | opencode_1 | Missing Event Emission for Shop Setting | This is an informational observability issue, not a reportable vulnerability under the requested impact bar. |
