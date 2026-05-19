# Merge View - Round 1

## Summary
- total findings: 1
- new findings: 1
- updated existing findings: 0
- rejected candidates: 4

## Finding Actions
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex | Interaction-length wraparound can redirect settlement parsing into forged historical-suffix bytes and steal approved funds | codex:0.69 Unchecked interaction-length wraparound can redirect settlement parsing into attacker-controlled trailer bytes |

## Rejection Reasons
- other: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Historical victim context is replayable because trusted settlement suffix data is not freshly authorized | Merged into F-001. The code supports replayable historical-context spoofing only as part of the same parser-redirection exploit; it does not independently demonstrate a standalone archived-calldata replay bug without the length/offset corruption. |
| other | codex | Settlement supports attacker-controlled recursive self-interactions with no depth or reentrancy guard | The nested `CONTINUE_INTERACTION` frames are supported by the scaffold, but they are only shown as delivery mechanics for F-001. The available code does not establish a distinct double-spend, invariant-bypass, or DoS impact from recursion alone. |
| other | codex | Universal ERC1271 approval lets anyone forge orders on behalf of the contract once allowances exist | This is a deliberate property of the attacker-controlled `FlawVerifier` harness, not evidence of a vulnerability in the audited settlement protocol. |
| other | codex | Anyone can trigger external swaps and approvals through the unrestricted execution entrypoint | This is also specific to the proof-of-concept helper contract and does not represent a protocol vulnerability in the target system. |
