# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 5

## Finding Actions
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Whitelist free mint can be stolen by passing an arbitrary whitelisted address | codex_1:0.484 Anyone can steal another user's whitelist mint by supplying an arbitrary `_user` |
| F-002 | rewritten_agent_signal | Critical | high | codex_1 | Contract callers can revert losing mints and keep only winning outcomes | codex_1:0.832 A wrapper contract can revert every losing mint and keep only winning outcomes |
| F-003 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Prize randomness is block-level and predictable enough for builders to cherry-pick winning blocks | codex_1:0.552 Prize randomness is derived from block fields that are predictable, proposer-influenceable, and constant for the whole block |
| F-004 | rewritten_agent_signal | Medium | low | codex_1,opencode_1 | Hardcoded `send` recipient can permanently brick winner payouts and withdrawals | codex_1:0.563 Immutable `send`-based payout target can permanently brick withdrawals and winning mints |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 3
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | opencode_1 | Reentrancy and Silent Failure in ETH Transfers | `send()` results are checked with `require`, so failures revert the whole transaction rather than silently leaving inconsistent state. The claimed reentrancy angle is not supported because `send()` forwards only 2300 gas and `_safeMint` also has an explicit reentrancy guard around minting. |
| other | opencode_1 | Incorrect Price Calculation in freeMint | The lucky payout in `freeMint` appears to be the intended game mechanic, not a code defect that causes protocol-level harm by itself. |
| other | opencode_1 | Missing Access Control on addBonusPool Function | A public payable top-up function is not a vulnerability on its own; allowing anyone to donate ETH to the bonus pool does not create a realistic exploit path. |
| duplicate_or_subsumed | opencode_1 | Unused withdrawAddress Update Functionality | Lack of a setter is not independently reportable as an exploit. The only plausible harm is the separate `send()`-based bricking issue already captured in F-004. |
| other | opencode_1 | Missing Event Emission in Critical Functions | Missing events may hinder off-chain monitoring but do not create realistic protocol-level harm such as theft, insolvency, lockup, or permissionless DoS. |
