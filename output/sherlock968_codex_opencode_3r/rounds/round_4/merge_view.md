# Merge View - Round 4

## Summary
- total findings: 15
- new findings: 2
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- existing_preserved: 13
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-014 | rewritten_agent_signal | Medium | medium | codex_1 | Requested subsidy rates can undercut the shared subsidy stream for active programs | codex_1:0.5 Requested (not actual) subsidy flow accounting can zero-out subsidies of other active programs |
| F-016 | rewritten_agent_signal | Medium | low | codex_1 | Non-FLUID program tokens can create unfundable or unwithdrawable locker rewards | codex_1:0.436 Program token is unrestricted while lockers are hardwired to FLUID for pool connection |

## Rejection Reasons
- other: 1
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Batch unit-update signatures use ambiguous packed encoding for dynamic arrays | The batch function requires `programIds.length == newUnits.length`, and both arrays contain fixed-width `uint256` elements. After the fixed `user` prefix and fixed `nonce` suffix, the remaining byte length determines the equal split between the two arrays, so the cited packed-encoding ambiguity does not produce distinct valid contract payloads. The already retained domain-separation issue covers the meaningful signature risk. |
| trust_or_owner_model | codex_1 | Factory ETH withdrawal uses 2300-gas transfer and can hard-lock fees | `withdrawETH()` can fail for a governor contract with an incompatible receive path, but the recipient is the trusted governor itself, the governor can call `setGovernor()` or upgrade the factory implementation, and the affected ETH is a governance fee balance rather than user principal. This is an admin configuration/operational robustness issue, not a realistic permissionless protocol-level vulnerability. |
