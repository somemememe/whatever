# Audit Report

**Total findings:** 6

## High (2)

### F-001: Reporter-priced assets are live at a hardcoded price of 1 until their first reporter update

**Confidence:** high | **Locations:** `0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:59, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:91, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:114, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:142`

The constructor initializes every REPORTER market with `prices[symbolHash].price = 1`, and both `price()` and `getUnderlyingPrice()` immediately expose that value with no guard proving the first real reporter update has happened. Because FIXED_ETH assets also derive from `prices[ETH_HASH]`, an uninitialized ETH reporter feed can misprice those markets too.

**Impact:** If governance wires this oracle into Compound before every reporter-backed market has validated once, affected assets can be valued near zero instead of at market price. That can make borrows appear almost free, collapse collateral value, trigger bad debt, and create liquidation or theft opportunities during rollout or migration.

**Paths:**

- Deploy the oracle and list it before all reporter feeds call `validate()` once.

- Borrow a reporter-backed asset whose debt is still priced at `1`, so the account is charged almost no borrow value.

- Or use an uninitialized reporter-backed asset as collateral and watch it be valued near zero, making accounts immediately undercollateralized or unusable.

*Round 1 | Agents: codex_1*

---

### F-002: Failover mode turns the Uniswap TWAP from a guardrail into the authoritative price source

**Confidence:** high | **Locations:** `0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:164, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:184, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:355`

Once `failoverActive` is set for a reporter-backed asset, both `validate()` and the permissionless `pokeFailedOverPrice()` path stop using the reporter value entirely and overwrite the stored price with the raw Uniswap-derived anchor price. No anchor-bounds check remains in force because the anchor itself becomes the stored price.

**Impact:** If the configured Uniswap market is thin enough to manipulate over `anchorPeriod`, failover exposes the protocol directly to TWAP manipulation. An attacker can move the TWAP, commit the manipulated value on-chain, and then over-borrow, buy collateral through underpriced liquidations, or leave the protocol with bad debt.

**Paths:**

- The owner activates failover for a market.

- An attacker sustains a manipulated TWAP in the configured Uniswap pool over `anchorPeriod`.

- The attacker or any third party calls `pokeFailedOverPrice()`, or the next reporter callback enters the failover branch in `validate()`, and the manipulated TWAP is stored as the official price.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (3)

### F-003: Extreme but valid TWAP values can overflow intermediate arithmetic and brick oracle updates

**Confidence:** medium | **Locations:** `0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:289, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:301, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:332, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:344`

`getUniswapTwap()` can return values spanning the full Uniswap V3 tick range, but `fetchAnchorPrice()` then performs `twap * conversionFactor` and `(unscaledPriceMantissa * config.baseUnit)` with unchecked Solidity multiplication before division. At sufficiently extreme but still valid ticks, those intermediate products overflow and revert.

**Impact:** A sustained extreme TWAP can deny service to price updates. If the ETH anchor path overflows, `fetchEthPrice()` reverts and reporter validation for every reporter-backed asset fails; failover activation and failover price updates can also revert. If only a token/ETH pool is pushed to an extreme, that market's price path can still be bricked.

**Paths:**

- Manipulate the ETH/USD anchor pool to an extreme valid tick for a full `anchorPeriod`.

- `fetchEthPrice()` overflows inside `fetchAnchorPrice()`, so `validate()` for reporter-backed markets and `activateFailover()` revert.

- Or manipulate a single token/ETH pool to an extreme valid tick so that only that market's `validate()` and `pokeFailedOverPrice()` paths revert.

*Round 1 | Agents: codex_1*

---

### F-004: Stale reporter prices can remain authoritative indefinitely because the oracle tracks neither freshness nor round progression

**Confidence:** medium | **Locations:** `0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:10, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:35, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:151`

Stored prices only record `{price, failoverActive}`; there is no timestamp, answered round, or heartbeat state. `validate()` ignores `previousRoundId`, `previousAnswer`, and `currentRoundId`, so the contract cannot detect stalled feeds, replayed rounds, or delayed-but-still-within-anchor updates.

**Impact:** If a reporter stops updating or lags through a sharp market move, the last accepted price remains live forever until governance manually activates failover. During fast moves, stale collateral values or stale debt values can delay liquidations, enable undercollateralized borrowing, or strand healthy liquidations until the oracle is manually intervened on.

**Paths:**

- A reporter feed stalls during a large price move.

- No freshness check causes the last accepted price to continue being returned by `price()` and `getUnderlyingPrice()` indefinitely.

- Borrowers keep using stale valuations until the owner notices and activates failover.

*Round 1 | Agents: codex_1*

---

### F-006: Duplicate config keys are silently shadowed because all lookups return the first match

**Confidence:** high | **Locations:** `0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapConfig.sol:326, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapConfig.sol:679, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapConfig.sol:717, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapConfig.sol:755, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapConfig.sol:793, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapConfig.sol:1172, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapConfig.sol:1185, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapConfig.sol:1198, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapConfig.sol:1212`

The immutable config table performs no uniqueness checks on `reporter`, `symbolHash`, `cToken`, or `underlying`, while every lookup helper returns the first matching slot. A duplicate key therefore shadows later entries instead of reverting, and all price reads or reporter callbacks for the later market resolve to the first configured market.

**Impact:** A duplicated reporter can route updates to the wrong asset and leave another market permanently stale. Duplicated `cToken`, `underlying`, or `symbolHash` values can make Comptroller price reads, failover operations, and symbol-based reads return the wrong market's price. Because the table is immutable, fixing the mistake requires redeploying and migrating the oracle.

**Paths:**

- Two configs share the same reporter address, so `validate()` always resolves the first market and the later market never receives updates.

- Two configs share the same `cToken`, `underlying`, or `symbolHash`, so `getUnderlyingPrice()`, `price()`, or failover lookups read the first market's config and silently misprice the later market.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-005: Constructor never authenticates that a configured anchor address is the intended Uniswap pool for the asset

**Confidence:** low | **Locations:** `0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:87, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:265, 0x50ce56a3239671ab62f185704caedf626352741e/contracts/Uniswap/UniswapAnchoredView.sol:282`

For REPORTER markets, construction only checks that `uniswapMarket` is non-zero. The runtime logic never verifies factory provenance, token0/token1 membership, quote asset, fee tier, or that the configured address is even the intended ETH pair; it simply calls `observe()` on the supplied address and trusts the manually supplied `isUniswapReversed` flag.

**Impact:** A bad immutable deployment or governance configuration can silently anchor an asset to the wrong market or wrong quote direction, causing failover and anchor checks to operate on unrelated pricing data. Because the config is immutable, recovery requires replacing the oracle rather than correcting the market in place.

**Paths:**

- Deploy a reporter-backed asset with `uniswapMarket` pointing to the wrong pool or with the wrong `isUniswapReversed` setting.

- `validate()` now compares the reporter against an unrelated anchor, potentially rejecting good reports or accepting bad ones.

- If failover is activated, the wrong pool becomes the market's authoritative price source until the oracle is migrated.

*Round 1 | Agents: codex_1*

---
