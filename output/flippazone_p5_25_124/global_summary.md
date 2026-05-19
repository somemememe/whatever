# Global Audit Memory

## Scope Touched
- `onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol` (`FlippazOne`): core focus across rounds, especially auction settlement, bidder refund/withdraw paths, `buyNow`, `endAuction`, and `isApprovedForAll` proxy approval behavior

## Issue Directions Seen
- Reentrancy is the dominant direction: bidder refund/withdraw flows send ETH before clearing accounting, and auction finalization may be reentered via `_safeMint` / `onERC721Received`
- Withdrawal/payout helpers show authorization and fund-redirection risk, with public callable paths affecting auction ETH
- Refund handling is brittle: batch refund logic can zero claims despite failed ETH delivery
- Auction lifecycle entrypoints (`startAuction`, `endAuction`, `refundBids`) have drawn recurring scrutiny for permissionlessness/design weakness, though not all variants were retained
- Marketplace/proxy approval trust assumptions in `isApprovedForAll` remain a low-confidence but durable integration-risk direction
- `buyNow` remains an edge-case area, mainly around mint safety and settlement behavior, but with weaker retention than the refund/finalization issues

## Useful Context
- Cross-round attention is highly concentrated in a single contract and mostly around auction state transitions plus ETH movement
- Strongest overlap so far is on refund/withdraw reentrancy; this is the clearest repeated pattern across agents
- `buyNow`, permissionless lifecycle functions, and proxy-registry approval have been unevenly explored and carry lower confidence than the retained payout/reentrancy issues
- The audit picture so far is less about broad codebase coverage and more about repeated pressure on a few high-value auction paths where external calls and state updates interact
