# Audit Report

**Total findings:** 3

## High (2)

### F-001: Thin-market donation inflation lets an attacker steal later deposits

**Confidence:** high | **Locations:** `0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1418, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1430, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1574, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1594, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1618, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:2654`

`exchangeRateStoredInternal()` prices shares from the contract's raw underlying balance via `getCashPrior()`, so direct token donations raise the exchange rate without minting any new cTokens. `mintFresh()` then floors `actualMintAmount / exchangeRate` and does not require `mintTokens > 0`, letting a thin-market attacker who already owns nearly all supply force later minters to receive too few, or even zero, cTokens.

**Impact:** In an empty or very thin market, an attacker can seed a dust position, donate underlying to inflate the exchange rate, then front-run a victim mint so the victim donates assets for negligible or zero shares. The attacker can then redeem their cTokens against the victim's deposit, stealing most or all of it.

**Paths:**

- Mint a dust amount into an empty or near-empty market so the attacker owns essentially all cTokens.

- Transfer underlying directly to the cToken contract, increasing `getCashPrior()` without increasing `totalSupply`.

- Front-run a victim `mint()`; `mintFresh()` reads the inflated exchange rate and floors the victim's minted shares.

- Redeem the attacker's cTokens to withdraw the donated cash plus the victim's deposit.

*Round 1 | Agents: codex_1*

---

### F-002: Borrow and redeem transfer out underlying before updating debt or collateral, enabling cross-market reentrancy with callback tokens

**Confidence:** medium | **Locations:** `0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1282, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1696, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1776, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1779, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1819, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1868, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1871, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:2518, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:2723`

Both `redeemFresh()` and `borrowFresh()` call `doTransferOut()` before writing the reduced cToken balance or increased borrow balance to storage. The reentrancy guard is local to this market instance only, so if the underlying token can trigger callbacks on transfer, the recipient can reenter a different market during the outbound transfer while this market's `getAccountSnapshot()` still reports stale collateral or debt.

**Impact:** If a callback-capable underlying is listed, an attacker can redeem collateral or borrow assets in one market and, during the token callback, enter another market that relies on Comptroller liquidity checks using this market's snapshot. That can allow over-borrowing against collateral already being redeemed or before new debt is recorded, creating protocol bad debt.

**Paths:**

- Use a market whose underlying token can execute code during `transfer` to the borrower/redeemer.

- Call `redeem()` or `borrow()` from a contract wallet.

- During the `doTransferOut()` callback, reenter another market and borrow or redeem there.

- The second market's liquidity check can observe this market's stale snapshot because storage updates happen only after the transfer returns.

- After the callback finishes, the first market finalizes the original redeem/borrow, leaving the account undercollateralized.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-003: Small `redeemUnderlying` calls can withdraw underlying while burning zero cTokens

**Confidence:** high | **Locations:** `0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1696, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1727, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1736, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1756, 0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol:1776`

When redeeming by underlying amount, `redeemFresh()` computes `redeemTokens = divScalarByExpTruncate(redeemAmountIn, exchangeRate)`. If rounding makes `redeemTokens == 0`, the function still proceeds: `redeemAllowed(..., 0)` is queried, `subUInt(accountTokens[redeemer], 0)` succeeds even for an address with no cTokens, and `doTransferOut()` sends `redeemAmountIn` underlying anyway.

**Impact:** Any account can repeatedly drain small amounts of underlying from market cash without owning or burning cTokens. Each call is capped by the current zero-rounding threshold, but the attack is permissionless and repeatable.

**Paths:**

- Choose `redeemAmountIn` small enough that `redeemAmountIn / exchangeRate` truncates to zero cTokens.

- Call `redeemUnderlying(redeemAmountIn)` from an address with zero cToken balance.

- The contract transfers out the requested underlying while burning zero cTokens.

- Repeat until available cash is depleted or the economics stop making sense.

*Round 1 | Agents: codex_1*

---
