# Audit Report

**Total findings:** 6

## Critical (1)

### F-001: Exact-amount borrows and withdrawals can round to zero shares and bypass accounting

**Confidence:** high | **Locations:** `0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:31, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:68, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:144, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:308, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:341, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:423, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:520, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:688, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:841, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:891, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:940`

`calculateLendingShares()` and `calculateBorrowShares()` floor-divide the requested amount by the current share price, but the exact-amount withdraw and borrow flows never require the returned share amount to be nonzero. After interest pushes `pseudoTotalPool > totalDepositShares` or `pseudoTotalBorrowAmount > totalBorrowShares`, a small exact-amount withdrawal can burn 0 lending shares while still transferring tokens out, and a small exact-amount borrow can mint 0 borrow shares while still transferring tokens to the borrower.

**Impact:** An attacker can repeatedly drain pool liquidity with tiny exact-amount borrows that never increase their debt shares. Separately, a lender can repeatedly withdraw small exact amounts without burning deposit shares, stealing value from other lenders and eventually emptying the pool.

**Paths:**

- Wait until a pool's share price exceeds 1 unit so that a small amount maps to 0 shares.

- Call `borrowExactAmount`, `borrowExactAmountETH`, or `borrowOnBehalfExactAmount` with an amount that makes `calculateBorrowShares(...) == 0`.

- Call `withdrawExactAmount`, `withdrawExactAmountETH`, or `withdrawOnBehalfExactAmount` with an amount that makes `calculateLendingShares(...) == 0`, repeating as long as liquidity remains.

*Round 1 | Agents: codex_1*

---

## High (2)

### F-002: Repeated syncs can re-accrue the same interest window whenever fee rounding yields zero

**Confidence:** high | **Locations:** `0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:386, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:418, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:428, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:447`

`_updatePseudoTotalAmounts()` increases `pseudoTotalBorrowAmount` and `pseudoTotalPool` before checking whether `feeAmount == 0`. When that branch is taken, the function returns without updating the pool timestamp. The next `syncPool`/`_preparePool` call therefore reuses the same old timestamp and re-accrues interest for the same elapsed period again.

**Impact:** Anyone can repeatedly call `syncManually()` or other syncing entrypoints to manufacture unbacked pseudo-interest on small or quiet pools. This inflates debts and lender balances without corresponding assets, distorts solvency calculations, and can enable overborrowing or forced liquidations against fictitious value.

**Paths:**

- Reach a state where one accrual step yields `amountInterest > 0` but `feeAmount == 0`.

- Call `syncManually(pool)` repeatedly, for example from a helper contract in one transaction or across same-timestamp syncs.

- Each call re-applies the same accrual interval because the timestamp was never advanced.

*Round 1 | Agents: codex_1*

---

### F-003: depositExactAmountETHMint bypasses WETH pool synchronization and over-mints shares

**Confidence:** high | **Locations:** `0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:202, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:215, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:246, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:295`

The normal ETH deposit path uses `syncPool(WETH_ADDRESS)` before share minting, but `depositExactAmountETHMint()` directly calls `_depositExactAmountETH()` and skips `_preparePool()` entirely. Pending WETH interest accrual and cleanup are therefore ignored when `calculateLendingShares()` determines how many shares to mint.

**Impact:** When the WETH pool has unaccrued interest or pending cleanup, `depositExactAmountETHMint()` mints too many lending shares. The attacker can later redeem the extra shares or use them as inflated collateral, diluting existing lenders.

**Paths:**

- Let the WETH pool accumulate pending interest or unsynchronized balance growth.

- Call `depositExactAmountETHMint()` instead of the synchronized `depositExactAmountETH()` path.

- After a later sync updates the pool state, redeem or borrow against the over-minted shares.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-004: Accounting assumes full token transfers and breaks for fee-on-transfer or deflationary assets

**Confidence:** medium | **Locations:** `0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:279, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:301, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:386, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:401, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:1060, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:1087, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:1101, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:1128, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:731, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:749`

Deposits, solely deposits, repayments, and liquidations all update internal accounting using the nominal `_amount`/`_paybackAmount` and then rely on `_safeTransferFrom()` without checking how many tokens actually arrived. For fee-on-transfer, burn-on-transfer, or negative-rebase assets, the protocol credits more value than it receives.

**Impact:** If such a token is listed, users can mint excess shares/collateral on deposit, reduce debt by more value than they repay, or liquidate positions while underpaying the protocol. The resulting shortfall is socialized to the pool and can leave it insolvent.

**Paths:**

- A fee-on-transfer or otherwise deflationary token is listed as a pool asset.

- Use `depositExactAmount` or `solelyDeposit` to receive credit for the pre-fee amount.

- Use `paybackExactAmount`, `paybackExactShares`, or liquidation to retire debt or seize collateral while sending less value than the accounting assumes.

*Round 1 | Agents: codex_1*

---

### F-006: Position token arrays hard-fail once a position accumulates 256 entries

**Confidence:** medium | **Locations:** `0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:353, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:361, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:537, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:560, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:512, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:1142`

`_prepareTokens()` and `_removePositionData()` use `uint8` indices. Once a position's lending or borrow token array reaches 256 entries, the loop counter overflows and syncing/removal logic reverts. `paybackExactLendingShares()` also never removes emptied lending-token entries, making it possible for stale entries to accumulate toward the limit over time.

**Impact:** An affected NFT can become impossible to sync, withdraw, repay, decollateralize, borrow against, or liquidate, creating a permanent position-level denial of service and potential lockup.

**Paths:**

- Accumulate 256 distinct lending/borrow token entries on one NFT, for example over the protocol's lifetime as more pools are added.

- Use `paybackExactLendingShares()` across many pools so empty lending-token entries are left behind instead of being pruned.

- Any later path that calls `_prepareTokens()` or removal logic on the oversized array reverts.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-005: Illiquid liquidation share payouts are registered on the debtor NFT instead of the liquidator NFT

**Confidence:** high | **Locations:** `0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:590, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:647, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:653, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:537, 0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:1020`

When liquidation cannot pay all collateral out in cash, `_withdrawOrAllocateSharesLiquidation()` correctly credits `shareDifference` to `_nftIdLiquidator`, but mistakenly calls `_addPositionTokenData()` with the debtor `_nftId`. The liquidator receives lending shares without the corresponding token-array entry on their NFT.

**Impact:** A liquidator using a fresh NFT can end up unable to fully withdraw the allocated shares, because the cleanup path later calls `_removePositionData()` against an empty lending-token array and reverts. The payout is effectively stuck until the liquidator first creates the missing token entry by another action.

**Paths:**

- Liquidate a position where the desired collateral payout exceeds liquid pool liquidity, so part of the reward is allocated as lending shares.

- Use a liquidator NFT that does not already track the received token.

- Attempt to fully withdraw the credited shares and hit the inconsistent bookkeeping path.

*Round 1 | Agents: codex_1*

---
