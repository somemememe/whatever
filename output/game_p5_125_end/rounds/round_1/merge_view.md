# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 7

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Previous-bid refund is an unguarded external call that enables both reentrancy theft and auction lockup | codex_1:0.928 Previous-bid refund is an unguarded external call that enables both theft-by-reentrancy and auction lockup |
| F-002 | rewritten_agent_signal | Critical | high | codex_1,merge_review | `makeBid()` lacks auction-state gating, enabling premature settlement and invalid post-settlement bids | codex_1:0.367 Auction settlement can be triggered before the game ends |
| F-003 | rewritten_agent_signal | High | high | codex_1 | Replacement bids only need to exceed 5% of the current bid, allowing the winning price to be ratcheted down to dust | codex_1:0.848 Outbids only need to exceed 5% of the current bid, so the winning price can be ratcheted downward toward dust |
| F-004 | exact_agent_candidate | High | high | codex_1,opencode_1 | Claims transfer token rewards to the zero address instead of the claimant | codex_1:0.93 Claims send token rewards to the zero address instead of the claimant |
| F-005 | exact_agent_candidate | Medium | medium | codex_1 | Unchecked ERC20 return values can allow free writes and silent token-payout failures | codex_1:0.916 Unchecked ERC20 return values can allow free writes or silent token-claim failures |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 1
- other: 2
- trust_or_owner_model: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Owner can set malicious token to steal user funds | This depends on the owner deliberately configuring a malicious external token; that is a trust/configuration assumption about the chosen asset, not a protocol bug in `Game.sol`. |
| trust_or_owner_model | opencode_1 | Owner can set malicious NFT contract to steal NFT | This is likewise an owner-chosen malicious dependency rather than an exploitable flaw in the game logic itself. |
| trust_or_owner_model | opencode_1 | Incorrect share calculation causes incorrect ETH payouts | `chunksWritenCount` tracks the number of chunks that have ever been initialized, and `_ownersShare` transfers one share from the old owner to the new owner on overwrite, so the sum of all live shares equals `chunksWritenCount`. |
| other | opencode_1 | Sum of all claim shares does not equal total, funds locked | For the same reason, the intended denominator is consistent with the live share total; only normal integer-division dust may remain, which is not a material vulnerability here. |
| duplicate_or_subsumed | opencode_1 | No reentrancy guard on ether transfers | The generic claim-side reentrancy concern is not substantiated by an exploit path beyond the specific refundable-bid reentrancy already captured in F-001; `claim()` sets `isClaimed` before sending ETH. |
| low_impact_or_operational | opencode_1 | Empty input array causes unnecessary token transfer | An empty `writeChunks()` call is at most a user footgun/gas waste and does not create realistic protocol-level harm. |
| other | opencode_1 | No way to recover mistakenly sent ETH or tokens | Missing rescue functionality for accidental transfers is not treated as a reportable vulnerability in this audit context. |
