# Merge View - Round 3

## Summary
- total findings: 4
- new findings: 0
- updated existing findings: 0
- rejected candidates: 4

## Finding Actions
- existing_preserved: 4

## New Or Updated Findings
- none

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Caller-controlled payer/source address can make settlement spend its own inventory or third-party approvals | The trailing encoded address is demonstrably attacker-controlled, but the available source does not establish that it is the payer/source field rather than another settlement parameter. The realistic harm from attacker-controlled call targets and settlement self-calls is already captured by F-001/F-002, so this candidate is too speculative as a distinct issue. |
| other | codex | Anyone can trigger the exploit routine against the contract's prefunded 1M native balance | This is an access-control issue in the PoC verifier contract, not a protocol vulnerability in the settlement system under audit. |
| other | codex | All token conversions use zero slippage protection and are trivially sandwichable | This concerns the verifier's post-exploit swap helpers, not the protocol under audit. It does not show a reportable flaw in the settlement contracts. |
| other | codex | No withdrawal or recovery path permanently locks the prefunded ETH and all proceeds | This is also specific to the PoC verifier harness rather than the settlement protocol, so it is out of scope for the protocol-level findings list. |
