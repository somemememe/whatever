# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Per-token approvals are not cleared on owner or operator transfers, allowing stale approved addresses to steal NFTs | codex_1:0.821 Per-token approvals are never cleared on owner/operator transfers, enabling theft by stale approved addresses |
| F-002 | rewritten_agent_signal | Low | high | codex_1,opencode_1 | ERC165 advertises enumerable and receiver interfaces that the contract does not actually honor | codex_1:0.748 ERC165 advertises interfaces the contract does not actually implement |
| F-003 | exact_agent_candidate | Low | high | codex_1 | Approval events log the caller instead of the actual token owner | codex_1:0.885 Approval events emit the caller instead of the token owner |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 7
- trust_or_owner_model: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Incomplete require statement causes compilation failure | Rejected. `require(_holder != address(0));` is valid Solidity syntax and compiles normally. |
| other | opencode_1 | Unchecked return values in restore function | Rejected. Both ERC20 `transferFrom` calls in `restore()` are wrapped in `require`, so restoration cannot proceed if either payment fails. |
| trust_or_owner_model | opencode_1 | Missing token existence validation in burn function | Rejected. `burn()` uses a mapping, not an array; out-of-range IDs do not read garbage. For unset IDs `ownership[id]` is `address(0)`, so the owner check fails for any real caller. |
| trust_or_owner_model | opencode_1 | Missing token existence validation in restore function | Rejected. Mapping reads for unset IDs return `address(0)`, so `require(DEAD_ADDRESS == ownership[id])` fails. There is no out-of-bounds read primitive here. |
| other | opencode_1 | Missing zero-address validation in constructor | Rejected. This is deployer misconfiguration risk, not a permissionless protocol vulnerability. |
| duplicate_or_subsumed | opencode_1 | Incorrect event parameter ordering in Transfer event | Rejected. `emit Transfer(_from, _to, _tokenId)` uses the correct ERC721 argument order, and the candidate's duplicate-event rationale is not a vulnerability. |
| trust_or_owner_model | opencode_1 | Curator role is not immutable and can be renounced | Rejected. The current source has no `renounceOwnership()` path in the audited contract, and curator reassignment is an intentional privileged admin action rather than a security flaw. |
| other | opencode_1 | Missing SafeMath for arithmetic operations | Rejected. The contract uses Solidity `^0.8.11`, which has built-in checked arithmetic. |
| trust_or_owner_model | opencode_1 | Token ID range not validated in approve function | Rejected. `approve()` already checks `_tokenId < max`, and non-minted tokens cannot be approved because the authorization check fails when `ownership[_tokenId]` is zero. |
| other | opencode_1 | Missing validation in tokenOfOwnerByIndex | Merged into F-002. The function is indeed broken, but the reportable issue is the broader false `IERC721Enumerable` support claim and resulting integration breakage. |
| other | opencode_1 | onERC721Received reverts instead of returning selector | Merged into F-002. Reverting is only reportable here because `supportsInterface()` advertises receiver support. |
| other | opencode_1 | Missing Return Values in ERC721 Interface Functions | Rejected. The candidate misstates the code: `supportsInterface()` returns true for both `IERC721Enumerable` and `IERC721TokenReceiver`. |
