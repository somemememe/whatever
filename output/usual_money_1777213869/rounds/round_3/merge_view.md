# Merge View - Round 3

## Summary
- total findings: 6
- new findings: 0
- updated existing findings: 1
- rejected candidates: 3

## Finding Actions
- existing_preserved: 5
- existing_rewritten: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-004 | existing_rewritten | Medium | low | codex | Blind low-level probing with persistent approvals can self-inflict irreversible token loss | codex:0.329 Profit signals are spoofable because anyone can inject ETH/WETH during execution |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 1
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Untrusted external calls can recursively reenter the public strategy entrypoint | Reentrancy requires one of the fixed hard-coded callees to actively call back into `executeOnOpportunity()`, but the verifier source alone does not show such behavior; this is too speculative and largely overlaps the existing unrestricted-entry and blind-call findings. |
| trust_or_owner_model | codex | Profit signals are spoofable because anyone can inject ETH/WETH during execution | Masking a loss here requires the attacker to donate ETH/WETH to the verifier, which subsidizes rather than extracts value, and no on-chain payout or privileged state transition depends on the local balance-delta heuristic. |
| other | codex | Unbounded returndata copies let a malicious target brick execution with a return-data bomb | A returndata bomb would require a malicious/nonstandard callee at one of the fixed addresses; on the intended chain those endpoints are canonical, while arbitrary-contract-at-fixed-address risk on the wrong chain is already covered by F-005. |
