# Audit Report

**Total findings:** 5

## Critical (2)

### F-001: Previous-bid refund is an unguarded external call that enables both reentrancy theft and auction lockup

**Confidence:** high | **Locations:** `0x52d69c67536f55efefe02941868e5e762538dbd6/contracts/game/Game.sol:232-241, 0x52d69c67536f55efefe02941868e5e762538dbd6/contracts/game/Game.sol:244-246`

`makeBid()` refunds the current `bidAddress` via `_sendEther()` before updating `bidAddress` and `bidEther`, and the whole bid reverts if that refund fails. Because the refund is a raw call, the incumbent bidder can reenter `makeBid()` while the old bid state is still in place, or simply revert to block all later bids.

**Impact:** A malicious highest-bidder contract can repeatedly collect refunds against the same stale `bidEther`, draining value from later bidders and leaving the auction undercollateralized. The same push-refund pattern also lets a reverting bidder permanently prevent anyone from outbidding them, so the NFT can be won cheaply or the auction can be frozen entirely.

**Paths:**

- Attacker becomes highest bidder from a contract; when a victim later calls `makeBid()`, the refund callback reenters `makeBid()` before `bidAddress`/`bidEther` are updated and receives additional payouts based on the stale bid.

- Attacker becomes highest bidder from a contract whose fallback always reverts; every later `makeBid()` attempt reverts inside `_sendEther()`, so no one can replace the attacker.

*Round 1 | Agents: codex_1*

---

### F-002: `makeBid()` lacks auction-state gating, enabling premature settlement and invalid post-settlement bids

**Confidence:** high | **Locations:** `0x52d69c67536f55efefe02941868e5e762538dbd6/contracts/game/Game.sol:219-225, 0x52d69c67536f55efefe02941868e5e762538dbd6/contracts/game/Game.sol:232-241, 0x52d69c67536f55efefe02941868e5e762538dbd6/contracts/game/Game.sol:249-256, 0x52d69c67536f55efefe02941868e5e762538dbd6/contracts/game/Game.sol:268-276`

`makeBid()` can be called even before the game ends, after the auction has expired, and after the NFT has already been claimed. Meanwhile, `claimNft()` and `claim()` only check `isAuctionEnd()`, so the first bid can start an auction timer long before gameplay ends and later settlement can execute while writes are still enabled.

**Impact:** An attacker can start the auction clock with a tiny bid, wait for `auctionEndTime` to expire, and transfer the NFT plus snapshot claim totals while the game is still ongoing. That lets current owners cash out against a temporary ownership state, while tokens and ETH paid by later writers fall outside the snapshot and become undistributable. The same missing gating also accepts bids after settlement; once the NFT is already transferred, any new final highest bid has no valid settlement path and can remain trapped in the contract unless someone later outbids it.

**Paths:**

- Place a bid immediately after deployment or during active gameplay, wait until `auctionEndTime` expires, then call `claimNft()` or `claim()` even though `isWriteEnable()` is still true.

- After `claimNft()` has already transferred the NFT, a user can still call `makeBid()` and become the new highest bidder; if nobody later replaces them, that bid remains stuck because `claimNft()` can never execute again.

*Round 1 | Agents: codex_1, merge_review*

---

## High (2)

### F-003: Replacement bids only need to exceed 5% of the current bid, allowing the winning price to be ratcheted down to dust

**Confidence:** high | **Locations:** `0x52d69c67536f55efefe02941868e5e762538dbd6/contracts/game/Game.sol:228-233, 0x52d69c67536f55efefe02941868e5e762538dbd6/contracts/game/Game.sol:237-238`

`newBidEtherMin()` returns only `(bidEther * 5) / 100`, and `makeBid()` compares `msg.value` directly against that amount instead of requiring `msg.value >= bidEther + step`. Each new highest bidder therefore only needs to post slightly more than 5% of the previous bid, not more than the previous bid itself.

**Impact:** A bidder can temporarily post a large bid, then outbid themselves from another address with a much smaller payment and recover almost all of the original amount through the refund path. Repeating this process drives the live bid toward 1 wei, so the NFT can be won for effectively nothing and chunk owners/dev only share the final reduced bid.

**Paths:**

- Attacker bids a large amount to take control of the auction, then uses controlled addresses to place successive bids just above `bidEther * 5 / 100` until the final payable bid is negligible.

*Round 1 | Agents: codex_1*

---

### F-004: Claims transfer token rewards to the zero address instead of the claimant

**Confidence:** high | **Locations:** `0x52d69c67536f55efefe02941868e5e762538dbd6/contracts/game/Game.sol:268-281`

`claim()` sends the claimant's token share with `token.transfer(address(0), ...)` instead of transferring to `msg.sender`.

**Impact:** With standard ERC20 implementations that reject zero-address transfers, every claim reverts and both ETH and token rewards remain locked because the earlier ETH send is rolled back. If the configured token permits transfers to `address(0)`, the entire token prize pool is burned instead of being distributed to winners.

**Paths:**

- After auction end, any eligible account calling `claim()` reaches `token.transfer(address(0), share)` rather than receiving its token payout.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (1)

### F-005: Unchecked ERC20 return values can allow free writes and silent token-payout failures

**Confidence:** medium | **Locations:** `0x52d69c67536f55efefe02941868e5e762538dbd6/contracts/game/Game.sol:77-80, 0x52d69c67536f55efefe02941868e5e762538dbd6/contracts/game/Game.sol:277-280`

`writeChunks()` and `claim()` ignore the boolean return values from `token.transferFrom()` and `token.transfer()`. If the configured token signals failure by returning `false` instead of reverting, the game still proceeds as if payment or payout succeeded.

**Impact:** A false-returning token lets writers update chunks, take ownership, and extend the game without actually paying the token cost. On the claim path, a claimant can be marked claimed and receive only ETH while the token transfer silently fails.

**Paths:**

- Configure a token whose `transferFrom()` returns `false`; `writeChunks()` still updates ownership, prices, and `_gameEndTime` even though no tokens were moved.

- Configure a token whose `transfer()` returns `false`; `claim()` completes after setting `isClaimed[msg.sender] = true`, but the caller receives no token payout.

*Round 1 | Agents: codex_1*

---
