# Audit Report

**Total findings:** 5

## Critical (1)

### F-001: Self-swaps on the same pool token let attackers ratchet pool prices upward without paying net vCash

**Confidence:** high | **Locations:** `0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:697, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:751, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:807, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:854`

Neither quote path nor swap execution rejects `tokenIn == tokenOut` for non-vCash pools. In that case the contract first computes a sell-side price move for the pool, then a buy-side price move against the same pool, and finally applies both updates sequentially to the same `pools[token]` entry. The vCash bookkeeping largely nets out, but the final stored price becomes the inflated buy-side price while the attacker only pays same-token slippage/fees.

**Impact:** An attacker can repeatedly self-swap a listed/official token to inflate its pool price, then swap the now-overpriced token into vCash, WETH, or other assets and drain value from honest pools.

**Paths:**

- Call `swapExactTokenForToken(token, token, amountIn, 0, attacker, deadline)` or `swapTokenForExactToken(token, token, amountInMax, amountOut, attacker, deadline)` repeatedly on a non-vCash pool token.

- After the pool price has been pushed up, swap that token into `vCash`, `WETH`, or another valuable pooled asset at the manipulated price.

*Round 1 | Agents: codex_1*

---

## High (2)

### F-002: Exact-output swaps undercharge fee-on-transfer `tokenIn` amounts

**Confidence:** high | **Locations:** `0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:697, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:854, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:859, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:863, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:867, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:875, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:912`

`swapOut` calls `getAmountIn` before transferring `tokenIn`, so `amountIn` and `tradeVcashValue` are quoted assuming the full pre-transfer amount arrives. `transferAndCheck` may then return a smaller actual amount for fee-on-transfer tokens, but the function does not recompute the quote and still releases the full requested `amountOut` using the stale `tradeVcashValue`.

**Impact:** A transfer-tax or deflationary token used as `tokenIn` can buy too much output for too little actual input, leaving the destination pool undercollateralized and enabling drainage of vCash or other assets.

**Paths:**

- Use `swapTokenForExactToken(feeToken, valuableToken, amountInMax, amountOut, attacker, deadline)` where `feeToken` charges transfer tax.

- The quote is computed from the nominal `amountIn`, but only the post-tax amount reaches `monoXPool`, so the attacker receives excess output.

*Round 1 | Agents: codex_1*

---

### F-003: Anyone can bypass LP withdrawal locks and force-remove another user's liquidity

**Confidence:** high | **Locations:** `0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:443, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:445, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:447, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:452, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:486, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:495, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:501`

`_removeLiquidity` enforces the cooldown and top-holder restrictions against `msg.sender`, but the LP balance that gets withdrawn and burned is taken from `to` via `monoXPool.balanceOf(to, pool.pid)` and `monoXPool.burn(to, pool.pid, liquidityIn)`. A caller can therefore supply any LP holder as `to`; the contract checks the caller's timestamps/holder status, not the actual LP owner whose position is removed.

**Impact:** The advertised 4-hour / 24-hour / 90-day lockups are unenforceable. Project teams or top LPs can bypass them through helper addresses, and arbitrary third parties can forcibly unwind someone else's LP position and remove their market exposure without consent.

**Paths:**

- Victim address `A` holds LP shares for pool `token`.

- Attacker or helper address `B` calls `removeLiquidity(token, liquidity, A, 0, 0)`.

- The contract validates `B`'s `liquidityLastAddedOf` and top-holder status, but burns `A`'s LP tokens and sends the underlying assets/vCash to `A`.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-004: Only `tokenIn` is locked, so a malicious `tokenOut` can reenter before its pool state is updated

**Confidence:** low | **Locations:** `0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:76, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:807, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:838, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:840, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:854, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:885, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:887`

Both `swapIn` and `swapOut` lock only `tokenIn`. When `tokenOut` is an ERC20, the contract performs `safeTransferERC20Token(tokenOut, to, amountOut)` before calling `_updateTokenInfo(tokenOut, ...)`. A malicious listed token used as `tokenOut` can execute arbitrary code during its transfer and reenter Monoswap while its own pool still exposes stale price/reserve state.

**Impact:** If a malicious token is listed, nested calls can be made against inconsistent pool accounting and may allow extraction of excess vCash or other assets before the outer swap finishes synchronizing `tokenOut` state.

**Paths:**

- List or use a malicious ERC20 as a pool token.

- Initiate a swap where that token is `tokenOut`, causing an external token transfer before `pools[tokenOut]` is updated.

- Reenter Monoswap from the token's transfer logic and trade against stale `tokenOut` state.

*Round 1 | Agents: codex_1*

---

### F-005: Relisting an unlisted token overwrites its pool id and strands prior LP positions

**Confidence:** high | **Locations:** `0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:203, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:219, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:288, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:292, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:305, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:452, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:471, 0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:501`

Setting a pool to `UNLISTED` clears `tokenPoolStatus[_token]`, which allows `_createPool` to create a brand new pool for the same token and overwrite `pools[_token]` with a new `pid`. Subsequent liquidity accounting and redemptions resolve the pool id only through `pools[_token].pid`, so LPs who still hold ERC1155 shares for the original pid are no longer routed to their original pool.

**Impact:** If a token is unlisted and later re-listed, holders of the original LP token can lose the ability to redeem through Monoswap, causing permanent fund lockup and broken accounting across two pool ids for the same token.

**Paths:**

- Owner marks a token `UNLISTED`, which resets `tokenPoolStatus[token]` to zero.

- A new pool for the same token is created later with `_createPool`, overwriting `pools[token]` with a fresh `pid`.

- Old LP holders calling `removeLiquidity(token, ...)` are forced onto the new `pid`, leaving the original position stranded.

*Round 1 | Agents: codex_1*

---
