# Merge View - Round 6

## Summary
- total findings: 13
- new findings: 1
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 12

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-014 | exact_agent_candidate | Medium | high | codex | Unexpected cToken transfers are misclassified as protocol yield and can be swept to the team | codex:1.0 Unexpected cToken transfers are misclassified as protocol yield and can be swept to the team |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Hardcoded mainnet token and Compound addresses are used without any chain validation | This is primarily a deployment-configuration risk rather than a permissionless exploit in the intended mainnet deployment. The hardcoded addresses appear to be an explicit design assumption, and no in-protocol attack follows if the contract is deployed where those addresses are correct. |
