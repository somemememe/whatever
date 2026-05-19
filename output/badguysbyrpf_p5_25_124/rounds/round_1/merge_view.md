# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1,opencode_1 | Any allowlisted address can mint the entire public allocation in a single free claim | codex_1:1.0 Any allowlisted address can mint the entire public allocation in a single free claim |
| F-002 | exact_agent_candidate | High | high | codex_1,opencode_1 | Owner can inflate supply beyond `maxsupply` by resetting `reserve` and minting again | codex_1:1.0 Owner can inflate supply beyond `maxsupply` by resetting `reserve` and minting again |
| F-003 | rewritten_agent_signal | Medium | medium | codex_1 | Reentrant `_safeMint` can reuse a stale `_currentIndex` and corrupt ERC721A accounting | codex_1:0.825 Reentrancy in `_safeMint` uses a stale `_currentIndex` and can corrupt ownership/accounting |
| F-004 | rewritten_agent_signal | Low | high | codex_1,opencode_1 | Owner can arbitrarily change metadata and reversibly hide revealed NFTs | codex_1:0.622 Owner can arbitrarily rug metadata by changing URIs and toggling reveal state |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 1
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | Owner Can Add Themselves to Whitelist After Deployment | `setRootHash` is a privileged allowlist-management function. By itself it does not bypass the supply checks or create an independent over-mint path; the meaningful supply-breaking issue is already captured by the mutable `reserve` finding. |
| other | opencode_1 | Withdraw Function Will Fail Due to Incorrect Syntax | `payable(msg.sender).transfer(balance)` is valid Solidity 0.8.x syntax, so this is not a real compile-time or runtime bug. |
| trust_or_owner_model | opencode_1 | Zero Quantity Mint Check Commented Out | The only reachable zero-quantity path is the owner-only `mintReservedTokens(0)`, which does not mint tokens and does not create realistic protocol-level harm. |
