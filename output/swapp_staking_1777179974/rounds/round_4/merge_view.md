# Merge View - Round 4

## Summary
- total findings: 10
- new findings: 0
- updated existing findings: 1
- rejected candidates: 2

## Finding Actions
- existing_preserved: 9
- existing_rewritten: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-005 | existing_rewritten | Medium | high | codex | Ignored Compound error codes can silently corrupt stablecoin state and brick future deposits | codex:0.541 A single failed Compound mint can permanently brick future stablecoin deposits |

## Rejection Reasons
- duplicate_or_subsumed: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Any dust withdrawal can indefinitely censor emergency exits for all users in a token pool | Duplicate of F-001. The existing finding is stronger because `withdraw(token, 0)` already suffices, so a dust withdrawal variant adds no new reportable issue. |
| unsupported_or_speculative | codex | Hardcoded mainnet token and Compound addresses make cross-chain deployments unsafe | Rejected as a deployment/configuration footgun rather than an intrinsic vulnerability in the audited deployment. The code is clearly written for a specific mainnet address set, and the issue materializes only if operators intentionally deploy it in an unsupported environment. |
