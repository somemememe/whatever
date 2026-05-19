# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 0
- updated existing findings: 4
- rejected candidates: 3

## Finding Actions
- existing_rewritten: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | existing_rewritten | Critical | high | codex | Matured rewards can be claimed repeatedly by splitting withdrawals | codex:0.467 Pool cap tracks only principal, so fixed reward promises can make the pool insolvent even without withdrawal games |
| F-002 | existing_rewritten | High | high | codex | Rewards are paid from the same token pool that backs user principal, so fixed reward promises can make the pool insolvent | codex:0.638 Pool cap tracks only principal, so fixed reward promises can make the pool insolvent even without withdrawal games |
| F-003 | existing_rewritten | Medium | medium | codex | Fee-on-transfer or deflationary tokens make internal balances exceed real assets | codex:0.426 Swallowed extension failures can silently desynchronize staking balances from the external share ledger |
| F-004 | existing_rewritten | High | medium | codex | Owner emergency withdrawal can seize all staked funds | codex:0.4 Owner-configurable external hook can permanently brick deposits and withdrawals through gas exhaustion |

## Rejection Reasons
- other: 1
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Owner-configurable external hook can permanently brick deposits and withdrawals through gas exhaustion | The hook call is wrapped in `try/catch`, so ordinary reverts are explicitly tolerated. The stronger claim that it can permanently brick operations via gas exhaustion is too speculative here and is also weaker than the owner's already-explicit ability to drain funds via `emergencyWithdraw()`. |
| unsupported_or_speculative | codex | Swallowed extension failures can silently desynchronize staking balances from the external share ledger | The staking contract itself does not rely on `vaultExtension` for core accounting or withdrawal authorization. Any concrete harm depends on unseen downstream integrations, so the impact is too speculative for a reportable protocol-level finding from this code alone. |
| other | codex | Maturity checks are inconsistent, so rewards appear claimable one second before withdrawals actually unlock | This is a minor UX/integration inconsistency at the exact maturity timestamp, but it does not create realistic fund loss, lockup beyond one second, insolvency, or permissionless denial of service. |
