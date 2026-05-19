# Audit Report

**Total findings:** 4

## Critical (2)

### F-001: Owner receives the entire liquidity position and can later rug the pool

**Confidence:** high | **Locations:** `0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:320, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:325, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:326`

`openTrading()` creates the pair and adds liquidity with `owner()` as the LP recipient, so the deployer retains full custody of the liquidity tokens backing the market. Because the LP is not burned or locked, the owner can later remove the pool's ETH and token reserves at will.

**Impact:** After users buy in, the owner can withdraw liquidity and collapse the market, leaving holders with severely impaired or worthless tokens and no reliable exit liquidity.

**Paths:**

- Owner transfers launch tokens into the token contract so `balanceOf(address(this))` is non-zero.

- Owner calls `openTrading()` and `addLiquidityETH(..., owner(), ...)` mints the LP position to the owner.

- Owner later removes liquidity from the Uniswap pair using the LP tokens they control.

- Pool reserves are drained and holders are left with an illiquid or near-worthless token.

*Round 1 | Agents: codex_1*

---

### F-002: Owner-controlled blacklist can freeze individual holders or halt the entire market

**Confidence:** high | **Locations:** `0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:224, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:225, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:304, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:310, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:316`

For every non-owner transfer, `_transfer()` enforces `require(!bots[from] && !bots[to])`, while `addBots()` lets the owner arbitrarily blacklist any address. This lets the owner freeze specific holders from transferring or selling, and also lets them blacklist the pair itself to brick all buys and sells.

**Impact:** The owner can trap selected users' funds or disable the market entirely. In practice this acts as a honeypot/freeze switch that can permanently block exits until the owner decides to remove the blacklist entry.

**Paths:**

- Owner calls `addBots([victim])` to blacklist a holder.

- Any later `transfer()` or sell from that holder reverts because `bots[from]` is true.

- Alternatively, after launch the owner blacklists the Uniswap pair address.

- All buys and sells touching the pair revert because `bots[to]` or `bots[from]` becomes true.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (1)

### F-003: A hidden 70% transfer tax confiscates ordinary transfers after the first buy

**Confidence:** high | **Locations:** `0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:135, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:227, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:230, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:234, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:241, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:261, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:295`

Once `_buyCount > 0`, `_transfer()` first sets `taxAmount = amount * _transferTax / 100`, and `_transferTax` is initialized to `70`. That punitive rate applies to ordinary wallet-to-wallet and wallet-to-contract transfers unless the transfer is later reclassified as a buy or sell; only the owner can disable it through `removeTransferTax()`.

**Impact:** After the first public buy, users moving tokens between wallets or into third-party contracts lose 70% of the amount to the token contract, creating a severe hidden value-extraction mechanism. Those confiscated tokens can then be swapped to ETH and paid out to the tax wallet.

**Paths:**

- A first buy from the pair increments `_buyCount` above zero.

- A holder later transfers tokens to another wallet, a vault, or another contract address that is not the pair.

- The transfer falls through with the default `_transferTax` of 70%, so only 30% reaches the recipient.

- The confiscated 70% accrues in the contract and can later be monetized through auto-swap or `manualSwap()`.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (1)

### F-004: Global three-sells-per-block rule enables sell-path denial of service

**Confidence:** medium | **Locations:** `0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:245, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:247, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:250, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:256, 0xe5c6f5fef89b64f36bfccb063962820136bac42f/Contract.sol:257`

When a sell triggers the fee-swap path, the contract enforces a global `sellCount < 3` limit per block before allowing the transaction to proceed. The counter is shared across all users, so once three sells have consumed the quota, later qualifying sells in the same block revert with `Only 3 sells per block!`.

**Impact:** A bot or MEV searcher can occupy the per-block sell quota with small sells and cause later users' exits to fail in that block. During volatile conditions this can delay or deny sells long enough to worsen losses or let the attacker prioritize their own exits.

**Paths:**

- Tax balance exceeds `_taxSwapThreshold`, `swapEnabled` is true, and `_buyCount > _preventSwapBefore`, so sell-triggered swaps are active.

- An attacker submits three small sells early in a block.

- Each sell increments the shared `sellCount` until it reaches 3.

- Any later qualifying sell in the same block reverts on `require(sellCount < 3)`.

*Round 1 | Agents: codex_1*

---
