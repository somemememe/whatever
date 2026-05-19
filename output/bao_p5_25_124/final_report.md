# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Borrow and redeem transfer underlying before updating debt/collateral, enabling cross-market reentrancy

**Confidence:** high | **Locations:** `0xb0f8fe96b4880adbdede0ddf446bd1e7ef122c4e/contracts/markets/CToken.sol:1661, 0xb0f8fe96b4880adbdede0ddf446bd1e7ef122c4e/contracts/markets/CToken.sol:1753, 0xdb3401bef8f66e7f6cd95984026c26a4f47eee84/contracts/CToken/CToken.sol:1661, 0xdb3401bef8f66e7f6cd95984026c26a4f47eee84/contracts/CToken/CToken.sol:1753, 0xdb3401bef8f66e7f6cd95984026c26a4f47eee84/contracts/CToken/CErc20.sol:227`

`redeemFresh()` and `borrowFresh()` call `doTransferOut()` before writing the new cToken balance or borrow principal to storage. The per-market `nonReentrant` guard only blocks reentry into the same market, so a callback-capable underlying can reenter a different market while the Comptroller still observes the old collateral or old debt snapshot through `redeemAllowed`/`borrowAllowed` checks.

**Impact:** A user can redeem collateral or borrow from one market, reenter during the outbound token transfer, and then over-borrow from another market against collateral that is in the process of leaving or before the first borrow is recorded. This can drain liquidity from other markets and leave the protocol with bad debt.

**Paths:**

- Call `redeem()` on a market whose underlying triggers a recipient callback, then use the callback to borrow from a different market before `accountTokens[redeemer]` and `totalSupply` are reduced.

- Call `borrow()` on a market whose underlying triggers a recipient callback, then use the callback to borrow from a different market before `accountBorrows[borrower]` and `totalBorrows` are increased.

*Round 1 | Agents: codex_1*

---

## High (1)

### F-002: Proxy constructor hands permanent admin rights to `tx.origin`

**Confidence:** high | **Locations:** `0xb0f8fe96b4880adbdede0ddf446bd1e7ef122c4e/contracts/markets/CErc20Delegator.sol:33, 0xb0f8fe96b4880adbdede0ddf446bd1e7ef122c4e/contracts/markets/CErc20Delegator.sol:49`

The delegator constructor uses `admin = msg.sender` only during initialization, but then overwrites the final admin with `tx.origin`. Any deployment routed through a factory, Safe module, relayer, or other intermediate contract therefore assigns full market control to the originating EOA rather than the intended deployer/governance contract.

**Impact:** The unintended EOA can immediately take over the market by changing the implementation, comptroller, reserve settings, or other admin-controlled parameters, which can be used to steal funds or brick the pool.

**Paths:**

- Deploy the market through a factory or governance wrapper; the wrapper contract performs deployment, but the signer EOA becomes `admin` because the constructor stores `tx.origin`.

- The unexpected EOA then calls admin-only functions such as `_setImplementation`, `_setComptroller`, or `_reduceReserves` to seize control of the market.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-004: Transfer-out accounting is incompatible with fee-on-transfer or deflationary underlyings

**Confidence:** medium | **Locations:** `0xdb3401bef8f66e7f6cd95984026c26a4f47eee84/contracts/CToken/CErc20.sol:191, 0xdb3401bef8f66e7f6cd95984026c26a4f47eee84/contracts/CToken/CErc20.sol:227, 0xb0f8fe96b4880adbdede0ddf446bd1e7ef122c4e/contracts/markets/CToken.sol:1661, 0xb0f8fe96b4880adbdede0ddf446bd1e7ef122c4e/contracts/markets/CToken.sol:1753, 0xdb3401bef8f66e7f6cd95984026c26a4f47eee84/contracts/CToken/CToken.sol:1661, 0xdb3401bef8f66e7f6cd95984026c26a4f47eee84/contracts/CToken/CToken.sol:1753`

`doTransferIn()` measures the actual amount received by comparing pre/post balances, but `doTransferOut()` blindly assumes the requested `amount` is what leaves the market and what the receiver gets. If the underlying charges fees or otherwise changes balances on outbound transfers, borrow and redeem accounting diverges from the real token movement.

**Impact:** Borrowers and redeemers can receive less than the amount the protocol books, and tokens that debit extra from the sender on transfer-out can create hidden insolvency because the market loses more cash than its accounting records.

**Paths:**

- List a fee-on-transfer underlying, then borrow `borrowAmount`; the market records the full debt increase even if the borrower receives less.

- Redeem cTokens against a fee-on-transfer underlying; the protocol burns cTokens for the full `redeemAmount` even if the user receives less, and sender-side fees can drain additional unaccounted cash from the pool.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-003: Zero-supply reset lets the next minter capture stranded underlying

**Confidence:** medium | **Locations:** `0xb0f8fe96b4880adbdede0ddf446bd1e7ef122c4e/contracts/markets/CToken.sol:1307, 0xb0f8fe96b4880adbdede0ddf446bd1e7ef122c4e/contracts/markets/CToken.sol:1314, 0xdb3401bef8f66e7f6cd95984026c26a4f47eee84/contracts/CToken/CToken.sol:1307, 0xdb3401bef8f66e7f6cd95984026c26a4f47eee84/contracts/CToken/CToken.sol:1314`

When `totalSupply == 0`, `exchangeRateStoredInternal()` hard-resets the exchange rate to `initialExchangeRateMantissa` and ignores any underlying already sitting in the market. After supply reaches zero, any unsolicited underlying balance left in the contract is not accounted for in the mint price, so the next minter can become the sole claimant to that stranded value.

**Impact:** Accidentally transferred tokens, rebasing gains, or other stray underlying that lands in a zero-supply market can be captured by the first account that mints after the reset.

**Paths:**

- Wait until `totalSupply` reaches zero.

- Before any honest supplier remints, have underlying be transferred or rebased into the market address.

- Mint a small amount at the bootstrap exchange rate, then redeem later as the only cToken holder to extract the stranded underlying.

*Round 1 | Agents: codex_1*

---
