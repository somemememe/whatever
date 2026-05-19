# Merge View - Round 10

## Summary
- total findings: 15
- new findings: 1
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- existing_preserved: 14
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-018 | rewritten_agent_signal | Medium | medium | codex | Permissionless future epoch initialization can freeze stale pool sizes for later reward periods | codex:0.284 Contract referrers can bypass the EOA-only gate during construction |

## Rejection Reasons
- other: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex | Contract referrers can bypass the EOA-only gate during construction | The constructor-time `extcodesize == 0` bypass is real in isolation, but this contract never uses referral state for payouts, permissions, or fund flows. On-chain impact is limited to metadata integrity, so the reported protocol harm is too speculative to keep as a reportable finding. |
| other | codex | Referral eligibility can be claimed retroactively after prior participation | `processReferrals()` only records referral relationships and counts; no reward-distribution or economic logic consumes that state anywhere in the codebase. Without a concrete on-chain value flow tied to referrals, this remains a low-value bookkeeping issue rather than realistic protocol-level harm. |
