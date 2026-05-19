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
| F-001 | exact_agent_candidate | High | high | codex_1 | Stale Compound exchange rate lets new deposits mint inflated shares and steal accrued yield | codex_1:1.0 Stale Compound exchange rate lets new deposits mint inflated shares and steal accrued yield |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Any accounted asset donation can permanently brick deposits when total supply is zero | codex_1:0.747 A direct token donation can permanently brick the vault when total supply is zero |
| F-003 | rewritten_agent_signal | Medium | high | codex_1,opencode_1 | Public strategy entrypoints can strand idle funds in a non-provider lender and DOS withdrawals | codex_1:0.621 Anyone can move idle funds into a non-provider strategy and make withdrawals revert |
| F-004 | exact_agent_candidate | Low | low | codex_1 | dYdX balances are treated as assets even if the account turns negative | codex_1:0.964 dYdX balances are treated as assets even if the account is negative |

## Rejection Reasons
- low_impact_or_operational: 1
- other: 5
- trust_or_owner_model: 1
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Unprotected approveToken allows infinite token approvals to potentially compromised addresses | Not a standalone vault bug. After constructor the function generally reverts because `safeApprove` forbids non-zero-to-non-zero approvals, and any remaining approval risk depends on trusted external protocol/admin compromise rather than permissionless misuse here. |
| unsupported_or_speculative | opencode_1 | Share calculation uses incorrect pool value leading to incorrect deposit amounts | Using the pre-deposit pool value is the standard share-minting formula; the report's same-block unfairness claim is unsupported by this code. |
| other | opencode_1 | Division by zero in getPricePerFullShare when totalSupply is zero | This is a view helper reverting before initialization, not a realistic protocol-level loss, theft, insolvency, or lockup issue. |
| trust_or_owner_model | opencode_1 | Dynamic Aave address approval in constructor can redirect approvals to attacker-controlled address | This relies on Aave governance/admin compromise or trusted address-provider changes, not a permissionless exploit introduced by the vault itself. |
| other | opencode_1 | Missing return value check on Aave deposit | The declared Aave interface returns no value. A failed deposit would revert rather than silently return false, so there is no unchecked-return vulnerability here. |
| other | opencode_1 | Rounding errors in withdrawal calculations can cause user fund loss | The `add(1)` intentionally over-redeems by at most dust to satisfy the requested withdrawal; it does not by itself create realistic protocol-level loss. |
| unsupported_or_speculative | opencode_1 | Recommend function uses external call that can be manipulated in single transaction | Too speculative as written. The report does not establish how the APR source is derived or that it is flash-loan manipulable in a way that creates concrete vault loss. |
| low_impact_or_operational | opencode_1 | Missing event emissions for critical ownership functions | Operational transparency issue only; not a reportable protocol-level vulnerability under the requested impact standard. |
| other | opencode_1 | Inconsistent balanceOf implementations may cause confusion | Integration ergonomics issue, not a security vulnerability. |
