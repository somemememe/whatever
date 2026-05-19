# Audit Report

**Total findings:** 3

## Critical (1)

### F-002: Initial LP tokens are minted to the owner, enabling an unrestricted liquidity rug pull

**Confidence:** high | **Locations:** `0x8390a1da07e376ef7add4be859ba74fb83aa02d5/Contract.sol:312, 0x8390a1da07e376ef7add4be859ba74fb83aa02d5/Contract.sol:317`

When `openTrading()` adds the initial Uniswap liquidity, it passes `owner()` as the LP recipient, so the resulting LP tokens are fully controlled by the owner rather than burned or locked.

**Impact:** The owner can remove the pool liquidity at any time, withdraw the paired ETH and token-side liquidity, and collapse the market. Holders are left with effectively untradeable tokens and little or no recoverable value.

**Paths:**

- Owner transfers tokens and ETH into the token contract, then calls `openTrading()`.

- `addLiquidityETH(..., owner(), ...)` mints the LP position directly to the owner-controlled address.

- The owner later removes liquidity off-contract and drains the pool.

*Round 1 | Agents: codex_1*

---

## High (1)

### F-001: Owner-controlled blacklist can freeze holders and disable trading

**Confidence:** high | **Locations:** `0x8390a1da07e376ef7add4be859ba74fb83aa02d5/Contract.sol:218, 0x8390a1da07e376ef7add4be859ba74fb83aa02d5/Contract.sol:219, 0x8390a1da07e376ef7add4be859ba74fb83aa02d5/Contract.sol:296, 0x8390a1da07e376ef7add4be859ba74fb83aa02d5/Contract.sol:302`

For every transfer where neither side is the owner, `_transfer` reverts if either endpoint is marked in `bots`, and the owner can add arbitrary addresses to that blacklist at any time through `addBots`.

**Impact:** The owner can selectively trap buyers after they purchase by making their tokens unsellable and non-transferable to ordinary addresses. Blacklisting the LP pair or router can also halt trading for the whole market, creating a honeypot or market-wide denial of service that strands user funds.

**Paths:**

- Owner calls `addBots([victim])` after the victim buys.

- When the victim later tries to transfer or sell, `_transfer` hits `require(!bots[from] && !bots[to])` and reverts.

- Owner can alternatively blacklist the pair or router address so ordinary sells and buys start failing market-wide.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (1)

### F-003: Sells can become permanently unexecutable if the immutable tax wallet rejects ETH transfers

**Confidence:** medium | **Locations:** `0x8390a1da07e376ef7add4be859ba74fb83aa02d5/Contract.sol:157, 0x8390a1da07e376ef7add4be859ba74fb83aa02d5/Contract.sol:241, 0x8390a1da07e376ef7add4be859ba74fb83aa02d5/Contract.sol:244, 0x8390a1da07e376ef7add4be859ba74fb83aa02d5/Contract.sol:292, 0x8390a1da07e376ef7add4be859ba74fb83aa02d5/Contract.sol:293`

Triggered sell-side tax swaps forward all ETH to the immutable `_taxWallet` via Solidity `transfer`. If that wallet is a contract that rejects ETH or needs more than 2300 gas to receive it, the transfer reverts and the entire sell reverts.

**Impact:** Once taxed tokens accumulate past the swap threshold and sells enter the swap path, affected deployments can lock holders into the token because every qualifying sell transaction fails. The tax wallet is immutable, so this failure mode cannot be repaired in-contract.

**Paths:**

- The token is deployed by a contract account or factory that becomes `_taxWallet` and cannot accept a 2300-gas `transfer`.

- Trading accumulates more than `_taxSwapThreshold` and `_buyCount` exceeds `_preventSwapBefore`.

- A later sell triggers `swapTokensForEth`, then `sendETHToFee`, and the `transfer` revert aborts the whole sell.

*Round 1 | Agents: codex_1*

---
