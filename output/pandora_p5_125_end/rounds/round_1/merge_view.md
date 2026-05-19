# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 7

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Unchecked ERC20 arithmetic lets arbitrary callers drain approved-none balances | codex_1:0.649 Unchecked allowance arithmetic lets anyone steal arbitrary ERC20 balances |
| F-002 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Transfer gate becomes a honeypot by permanently blocking sells to the chosen pool address after 50 blocks | codex_1:0.717 Hidden honeypot permanently blocks sells to the pool after 50 blocks |
| F-003 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Buyers only get a two-block window to sell back to the pool | codex_1:0.457 Hidden honeypot permanently blocks sells to the pool after 50 blocks |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 2
- trust_or_owner_model: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | safeTransferFrom lacks authorization verification | Incorrect. Both `safeTransferFrom` overloads delegate to `transferFrom`, and the NFT branch of `transferFrom` enforces owner/approval/operator authorization before moving the token. |
| trust_or_owner_model | opencode_1 | Ownership revocation permanently locks contract | `revokeOwnership()` is an intentional renounce-ownership pattern. It may freeze admin functionality, but that is not a protocol vulnerability or user-funds issue by itself. |
| trust_or_owner_model | opencode_1 | Missing zero address validation in setWhitelist | Owner-only configuration issue with no realistic standalone exploit path or protocol-level harm. |
| duplicate_or_subsumed | opencode_1 | Burn/mint loops may exceed gas limits for large transfers | Under normal operation the native supply is only 200 tokens, so the burn/mint loops are bounded. Pathological huge-loop behavior depends on the separate unchecked-arithmetic bug already captured in F-001. |
| trust_or_owner_model | opencode_1 | ownerOf reverts instead of returning address(0) for non-existent IDs | False premise. Standard ERC721 `ownerOf` behavior is to revert for nonexistent tokens, not return `address(0)`. |
| other | opencode_1 | Unverified token allocation to owner at deployment | Initial token allocation/distribution policy is a project design choice, not a smart-contract vulnerability. |
| other | codex_1 | Monotonic minted counter causes permanent ERC20/ERC721 type confusion | Code support exists, but the misclassification threshold is measured in raw 18-decimal base units. At this 200-token scale it only affects dust-sized amounts, making the impact too weak to keep as a reportable protocol issue. |
