# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: `redeem()` trusts an arbitrary token contract and can release any ERC20 held by the teller

**Confidence:** high | **Locations:** `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:137, onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:140, onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:141`

`redeem()` never verifies that `token_` is a bond token deployed by this teller. It blindly calls the caller-supplied contract for `expiry()`, `burn(address,uint256)`, and `underlying()`, then transfers `amount_` of whatever ERC20 `underlying()` returns from the teller to the caller.

**Impact:** Any ERC20 balance currently held by the teller can be drained permissionlessly, including payout reserves backing live bonds, tokens deposited through `create()`, and accrued fee balances.

**Paths:**

- Deploy a malicious contract exposing `expiry()`, `burn(address,uint256)`, and `underlying()` with the expected ABI.

- Make `expiry()` return a timestamp in the past, `burn()` a no-op, and `underlying()` return a valuable ERC20 held by the teller.

- Call `redeem(maliciousToken, amount)`.

- The teller accepts the fake token, skips any real burn accounting, and transfers out `amount` of the chosen ERC20.

*Round 1 | Agents: codex_1*

---

## High (2)

### F-002: Purchases into undeployed fixed-expiry markets can complete without minting any bond tokens

**Confidence:** high | **Locations:** `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol:155, onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:83, onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:86`

When a market vests in the future, `_handlePayout()` calls `bondTokens[underlying_][expiry].mint(...)` without checking that the bond token was deployed first. If the mapping entry is still `address(0)`, the external call succeeds against the zero address and no bond tokens are minted.

**Impact:** A buyer can pay quote tokens and the teller can source payout reserves, yet the buyer receives no redeemable position. The payout tokens remain stranded inside the teller with no claim token representing the purchase.

**Paths:**

- A fixed-expiry market is live, but nobody has called `deploy(payoutToken, vesting)` yet.

- A user calls `purchase(...)` for that market.

- `purchase()` collects quote tokens and `_handleTransfers()` ensures payout tokens are available inside the teller.

- `_handlePayout()` executes `bondTokens[underlying_][expiry].mint(...)` on `address(0)`, so no bond tokens are created.

- The transaction returns successfully, leaving the buyer with no asset to redeem.

*Round 1 | Agents: codex_1*

---

### F-003: `redeem()` burns bond tokens before an unchecked ERC20 transfer, allowing permanent loss on false-return payout tokens

**Confidence:** medium | **Locations:** `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:137, onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:140, onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:141`

`redeem()` calls `token_.burn(msg.sender, amount_)` first and then performs a raw `token_.underlying().transfer(msg.sender, amount_)` while ignoring the returned boolean. If the underlying token returns `false` instead of reverting, the redemption call can succeed after the user's bond tokens are burned without delivering the payout.

**Impact:** Bond holders can irreversibly lose their redeemed amount. A malicious or poorly behaved payout token can make purchased bonds effectively worthless at redemption time.

**Paths:**

- A market uses a payout token whose `transfer` returns `false` on teller-to-user transfers.

- A user holds legitimate matured bond tokens for that market.

- The user calls `redeem()`.

- The teller burns the bond tokens, then the payout token returns `false` from `transfer(...)`.

- Because the return value is ignored, the transaction does not revert and the user receives no payout.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-004: `purchase()` prices against one market snapshot but settles against a second snapshot

**Confidence:** low | **Locations:** `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol:141, onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol:147, onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol:173, onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol:175`

`purchase()` reads market configuration from `getMarketInfoForPurchase(id_)`, then calls the external `purchaseBond()`, and later `_handleTransfers()` fetches market info again and uses the second snapshot to determine the owner, callback, payout token, and quote token used for settlement. A registered auctioneer that mutates those fields during `purchaseBond()` can cause settlement to happen against different parameters than the buyer was originally quoted.

**Impact:** A buggy or malicious registered auctioneer could redirect quote tokens to a different owner or callback, switch the payout token used to fund/redempt the purchase, or desynchronize fee accounting from the token actually transferred, breaking buyer assumptions and potentially causing theft or stranded balances.

**Paths:**

- The first `getMarketInfoForPurchase(id_)` call returns benign market metadata for pricing.

- Inside `purchaseBond()`, the auctioneer mutates owner, callback, payout token, or quote token for that market.

- `_handleTransfers()` re-reads the now-changed market info and settles using the updated values instead of the original snapshot.

- The buyer's quote tokens, payout asset, or fee accounting follow the mutated configuration rather than the quoted one.

*Round 1 | Agents: codex_1*

---
