# Merge View - Round 7

## Summary
- total findings: 13
- new findings: 0
- updated existing findings: 1
- rejected candidates: 3

## Finding Actions
- existing_preserved: 12
- existing_rewritten: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-005 | existing_rewritten | Medium | high | codex | Ignored Compound error codes can silently corrupt stablecoin state, brick future deposits, and expose principal to team sweeps | codex:0.488 Silent Compound redeem failures can turn withdrawn principal into team-sweepable “interest” |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 1
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Silent Compound redeem failures can turn withdrawn principal into team-sweepable “interest” | Merged into F-005 as a materially stronger exploit path for the existing ignored-Compound-return-codes finding rather than kept as a separate duplicate. |
| other | codex | The EOA-only referrer restriction is bypassable by contracts in construction | The constructor-time `extcodesize` bypass is real, but this contract only stores referral metadata; no on-chain payout, privilege, or protocol-fund impact is implemented here. |
| trust_or_owner_model | codex | Referral registration can be claimed after prior staking activity by using unsupported tokens first | This only weakens the intended referral-eligibility policy for metadata tracking; with no on-chain referral reward or privileged action wired up, realistic protocol-level harm is too speculative. |
