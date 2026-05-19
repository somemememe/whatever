# Merge View - Round 8

## Summary
- total findings: 17
- new findings: 2
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 15
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-025 | rewritten_agent_signal | Medium | high | codex | Mint fee is uncapped, so governance can make new borrows immediately confiscatory | codex:0.727 Runtime mint-fee setter is uncapped and can make new borrows confiscatory |
| F-026 | exact_agent_candidate | Medium | high | codex | Oracle and rate-calculator setters accept invalid addresses and can globally brick the pair | codex:1.0 Oracle and rate-calculator setters accept invalid addresses and can globally brick the pair |

## Rejection Reasons
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Pair finalizes redemptions and liquidations without locally enforcing the offsetting debt burn | Rejected as a trust-boundary issue: these paths are explicitly restricted to the registry-designated redemption and liquidation handlers, and the pair is designed to rely on those privileged system components to burn or process debt externally. A buggy or compromised authorized handler is not a standalone pair-layer vulnerability here. |
