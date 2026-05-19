# Merge View - Round 5

## Summary
- total findings: 3
- new findings: 0
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- existing_preserved: 3

## New Or Updated Findings
- none

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Directly sent ETH or HEX become permanently unrecoverable | Rejected as a generic missing-sweep / accidental-transfer issue rather than a protocol-mediated exploit. Ordinary ETH transfers already revert because the contract has no payable fallback, so only forced ETH and mistaken direct HEX transfers are affected, which does not create meaningful theft, insolvency, or permissionless DoS against protocol users. |
