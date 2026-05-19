# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 13

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Vault NFTs can be bought for the same flat fee regardless of collection or value | codex_1:0.562 Any NFT held by the vault can be bought for the same tiny flat fee |
| F-002 | rewritten_agent_signal | Medium | high | codex_1 | `buyJay()` accepts zero NFTs but still gives the higher 97% mint rate | codex_1:0.45 The NFT-seller mint path works with zero NFTs, bypassing the higher no-NFT buy fee |
| F-003 | rewritten_agent_signal | Medium | high | codex_1,opencode_1 | Reentrant `sell()` calls over-withdraw ETH by pricing later sells before prior dev fees leave the pool | codex_1:0.66 Reentrant sells can over-withdraw ETH because seller payout happens before the dev fee transfer |
| F-005 | exact_agent_candidate | Low | high | codex_1,opencode_1 | Burning the final JAY supply reverts because the post-burn price event divides by zero | codex_1:0.883 Burning the entire remaining supply reverts because the post-burn price event divides by zero |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 1
- other: 8
- trust_or_owner_model: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | Anyone can manipulate the stored JAY-denominated NFT redemption fee by skewing spot reserves before `updateFees()` | Plausible but too speculative as a standalone issue here: the attacker must first distort pool reserves with their own capital, and the incremental harm is largely subsumed by the already-critical flat-fee NFT theft vector. |
| other | opencode_1 | Division by zero in ETHtoJAY pricing function | `ETHtoJAY()` is called in payable contexts where `address(this).balance` already includes `msg.value`, so the denominator is effectively the pre-call balance. With the constructor seeding ETH and no realistic path to a zero pre-balance, the claimed division-by-zero case is not practically reachable. |
| trust_or_owner_model | opencode_1 | No access control on updateFees function | Permissionless fee updates appear intentional, and the function still constrains non-owner updates with the fee-swing check. The generic lack-of-access-control claim is not reportable by itself. |
| other | opencode_1 | No oracle staleness check in price feeds | This could at most delay or skew fee refreshes, but the submission does not establish realistic protocol-level fund loss or lockup from stale ETH/USD data in this design. |
| trust_or_owner_model | opencode_1 | Reentrancy vulnerability in buyJay function | The only external ETH send is to the configurable `dev` address, which is owner-controlled and already privileged. The candidate does not show an untrusted reentrancy path creating additional protocol harm. |
| other | opencode_1 | Unchecked ERC721 transfer return value | Standard ERC721 `transferFrom` and `safeTransferFrom` do not return booleans; they revert on failure. There is no ignored return value vulnerability here. |
| other | opencode_1 | Unlimited token minting allows inflation | Minting against ETH deposits is core protocol behavior, not an unintended unlimited-mint bug. |
| other | opencode_1 | No array length validation in buyNFTs | Mismatched arrays either revert atomically or let the caller overpay themselves. This is user-input validation quality, not a realistic protocol-level exploit. |
| other | opencode_1 | Missing return value check on ERC1155 transfers | ERC1155 `safeTransferFrom` also does not return a boolean. Failures revert, so there is no ignored-return-value issue. |
| other | opencode_1 | No slippage protection on NFT purchases | `buyNFTs()` is not a variable-price swap path; the caller explicitly chooses the NFTs and pays fixed protocol fees. The claimed slippage issue does not fit the code's behavior. |
| trust_or_owner_model | opencode_1 | Owner can change dev wallet before locking | This is an explicit owner privilege provided by design until `lockDevWallet()` is used, not an unintended vulnerability. |
| other | opencode_1 | Potential integer overflow in SafeMath operations | This is not a vulnerability; SafeMath is redundant in Solidity 0.8+ but remains safe. |
| low_impact_or_operational | opencode_1 | Missing event emissions for critical state changes | Lack of events is an observability issue, not a realistic protocol-level security finding under the stated reporting bar. |
