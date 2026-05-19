# Audit Report

**Total findings:** 4

## High (2)

### F-001: Manipulable market-cap inputs let anyone force bad constituents and weights during permissionless rebalances

**Confidence:** high | **Locations:** `0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSortedTokenCategories.sol:206, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSortedTokenCategories.sol:235, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSortedTokenCategories.sol:252, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSqrtController.sol:437, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSqrtController.sol:486, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/lib/MCapSqrtLibrary.sol:29, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/lib/MCapSqrtLibrary.sol:64`

Constituent selection and target weights are derived directly from `totalSupply * Uniswap TWAP price`, with no on-chain liquidity floor, depth check, or anti-manipulation guard. Because `orderCategoryTokensByMarketCap`, `reindexPool`, and `reweighPool` are all permissionless, an attacker can move a thin token's WETH TWAP over the oracle window, sort that token into the top set or inflate its relative market cap, and then force the pool to adopt the manipulated composition/weights.

**Impact:** The pool can be induced to add or overweight a low-liquidity asset at an artificial valuation, after which the attacker can arbitrage against the pool and extract more valuable assets from LPs.

**Paths:**

- Get a thin-liquidity category token listed in a tracked category

- Manipulate its WETH TWAP over the long oracle window used by category sorting and weight calculation

- Call `orderCategoryTokensByMarketCap` to push it up the category ranking

- Call `reindexPool` or `reweighPool` while the manipulated TWAP is still in effect

- Trade against the pool's distorted holdings/weights to extract value

*Round 1 | Agents: codex_1*

---

### F-004: Uninitialized owner proxies are first-call ownable if deployment does not atomically initialize them

**Confidence:** low | **Locations:** `0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/OwnableProxy.sol:82, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSortedTokenCategories.sol:105, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSqrtController.sol:191`

The controller/category ownership model relies on public `initialize()` entrypoints that simply call `_initializeOwnership()`, which succeeds when the proxy's storage still has `_owner == address(0)`. The implementation contract is locked in its constructor, but a newly deployed proxy is not. If operational deployment does not initialize the proxy in the same transaction, any external account can initialize first and seize ownership.

**Impact:** A successful first-call initialization takeover gives the attacker full owner authority over category curation and pool administration, including preparing pools, setting fees/recipients, and delegating governance from managed pools.

**Paths:**

- A proxy for `MarketCapSortedTokenCategories` or `MarketCapSqrtController` is deployed without atomic initialization

- Before the intended admin initializes it, an attacker calls the public `initialize()` function

- `_initializeOwnership()` sets the attacker as owner of the proxy

- The attacker uses owner-only functions to control categories and managed pools

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-002: Instantaneous `totalSupply()` reads let supply-manipulable tokens spoof market cap and weights

**Confidence:** medium | **Locations:** `0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSortedTokenCategories.sol:235, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSortedTokenCategories.sol:252, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/lib/MCapSqrtLibrary.sol:29, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/lib/MCapSqrtLibrary.sol:44, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/lib/MCapSqrtLibrary.sol:64`

Both category ranking and rebalance weights read `IERC20(token).totalSupply()` at execution time instead of using any snapshot or time-averaged supply metric. If a listed token can temporarily inflate supply through flash minting, rebasing, or privileged minting, it can report a much larger market cap during sorting/rebalance than its durable economic value warrants.

**Impact:** A supply-manipulable token can temporarily enter the index or receive a much larger target weight, causing the pool to absorb a distorted composition that can then be exploited or leaves LPs holding a fundamentally overvalued asset.

**Paths:**

- Temporarily inflate the supply of a listed token via flash mint, rebase, or privileged mint

- Call `orderCategoryTokensByMarketCap` while the inflated supply is visible

- Call `reindexPool` or `reweighPool` before the supply returns to normal

- Exploit the pool's distorted holdings or unwind after the fake market cap signal disappears

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-003: Permissionless minimum-balance updates can grief newly added tokens via manipulable value estimates

**Confidence:** medium | **Locations:** `0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSqrtController.sol:402, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSqrtController.sol:405, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSqrtController.sol:406, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSqrtController.sol:411, 0x120c6956d292b800a835cb935c9dd326bdb4e011/temp-contracts/MarketCapSqrtController.sol:619`

`updateMinimumBalance` is callable by anyone for any tracked pool token that is not yet ready. It resets the pool's required minimum balance from `_estimatePoolValue(pool)` plus a short-window TWAP for the token, and `_estimatePoolValue` itself trusts `pool.extrapolatePoolValueFromToken()` combined with a short oracle window. An attacker who can skew the reference valuation around the update can permissionlessly raise the target balance for an unready token.

**Impact:** A newly added token can be kept unready longer than intended, delaying completion of a reindex and griefing the pool's transition into its target composition.

**Paths:**

- Wait for a reindex to add a token that is still unready

- Manipulate the short-window valuation feeding `_estimatePoolValue` and/or the token's short TWAP

- Call `updateMinimumBalance(pool, token)` while the manipulated value is in effect

- Repeat as needed to keep the token's readiness threshold artificially high

*Round 1 | Agents: codex_1*

---
