# Merge View - Round 2

## Summary
- total findings: 4
- new findings: 0
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- existing_preserved: 4

## New Or Updated Findings
- none

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Settlement appears to honor an interaction-supplied token payer that is different from the signed maker | Rejected as a distinct issue because the PoC evidence is better explained by the already-reported calldata-corruption/historical-order-replay bug. The victim address embedded in the crafted suffix does not cleanly demonstrate a separate payer/source-of-funds trust boundary independent of F-003. |
| unsupported_or_speculative | codex | Resolver/callback execution appears satisfiable by a no-op contract or even a no-code address | Rejected as unsupported. The PoC only shows that an empty `NoopResolver` is sufficient in the exploit path, but not that resolver execution is intended to prove maker-side payment or that code-existence checks are a required security invariant. This looks derivative of the fake-token validation failure in F-004, not a standalone root cause. |
| duplicate_or_subsumed | codex | Settlement appears to spend raw contract token balances instead of order-scoped escrow/accounting | Rejected as a separate finding because it is an impact/restatement of F-004. The PoC drains live `SETTLEMENT` balances only after bypassing maker-side asset validation with `FakeMakerToken`; the reportable root cause is the bogus maker-asset accounting, while omnibus settlement inventory is the resulting blast radius already captured in F-004. |
