# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 11

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Anyone can drain auction ETH through unrestricted withdrawal functions | codex_1:0.944 Anyone can drain auction funds through unrestricted withdrawal functions |
| F-002 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Refund and bidder-withdraw paths are reentrant and can pay the same bid repeatedly | codex_1:0.375 Hardcoded proxy registry can grant blanket approvals to the wrong operator set |
| F-003 | rewritten_agent_signal | Critical | high | codex_1 | `endAuction` can be reentered to mint multiple NFTs before the auction is marked finished | codex_1:0.558 Auction settlement can be reentered to mint unlimited NFTs |
| F-004 | rewritten_agent_signal | Medium | high | codex_1 | Batch refunds can silently erase a bidder's claim when ETH transfer fails | codex_1:0.645 Failed batch refunds silently erase bidder balances |
| F-005 | rewritten_agent_signal | Medium | low | codex_1 | Hardcoded OpenSea proxy registry can auto-approve the wrong operator set on other deployments | codex_1:0.702 Hardcoded proxy registry can grant blanket approvals to the wrong operator set |

## Rejection Reasons
- duplicate_or_subsumed: 3
- factually_incorrect: 1
- other: 2
- trust_or_owner_model: 3
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Missing access control on startAuction() | Rejected as factually incorrect: `startAuction` is protected by `onlyOwner` at `Contract.sol:1232`. |
| duplicate_or_subsumed | opencode_1 | Missing access control on endAuction() | Rejected: permissionless settlement after expiry is an expected design pattern here and no realistic protocol harm was substantiated beyond the separate reentrancy issue already captured. |
| duplicate_or_subsumed | opencode_1 | Missing access control on refundBids() | Rejected: anyone triggering refunds after the auction ends is not inherently harmful; the actual reportable problems are the reentrancy and failed-transfer accounting bugs already captured. |
| unsupported_or_speculative | opencode_1 | buyNow() can mint NFT to zero address | Rejected as unsupported: `buyNow` sets `highestBidder = _msgSender()` and mints to `_msgSender()`, never to `address(0)`. |
| duplicate_or_subsumed | opencode_1 | Reentrancy vulnerability in ownerWithdraw()/ownerWithdrawTo()/ownerWithdrawAll()/ownerWithdrawAllTo() | Rejected as an independent finding: these functions perform external calls, but the concrete exploitable issue is their missing access control, which is already captured in `F-001`. |
| trust_or_owner_model | opencode_1 | editDuration() lacks zero value validation | Rejected: this is an owner-controlled configuration choice, not a permissionless vulnerability causing realistic protocol-level harm. |
| factually_incorrect | opencode_1 | Potential integer overflow in getBuyNowPrice() | Rejected as incorrect under `pragma solidity ^0.8.15`, where arithmetic overflow reverts automatically. |
| trust_or_owner_model | opencode_1 | editBaseUri() allows changing metadata at any time | Rejected: owner-controlled metadata mutability is a trust/design concern, not a protocol exploit causing the required class of on-chain harm. |
| other | opencode_1 | auctionStarted flag can be reset / auction cannot be restarted | Rejected: inability to restart the one-off auction is a design choice, not a vulnerability. |
| unsupported_or_speculative | opencode_1 | Missing validation on bid function for zero-value bids | Rejected as unsupported: `highestBid` starts at `0.9 ether` and `bid` requires `newBid >= highestBid + minBidStep`, so zero-value bids cannot satisfy the threshold. |
| other | codex_1 | Buy-now settlement can lock the NFT in contracts that cannot handle ERC721s | Rejected: `buyNow` mints to `msg.sender`, so any lockup is self-inflicted by the buyer's chosen contract wallet rather than a protocol flaw creating realistic third-party harm. |
