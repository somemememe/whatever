# Audit Report

**Total findings:** 5

## Critical (1)

### F-001: Transferable share tokens let users separate debt from collateral across addresses

**Confidence:** medium | **Locations:** `0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/interfaces/IShareToken.sol:8, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/interfaces/INotificationReceiver.sol:5, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:190, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:196, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:335, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:339, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:417, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:453, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:575, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/lib/Solvency.sol:180, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/lib/Solvency.sol:257`

The protocol treats share-token `balanceOf(user)` as the sole source of truth for collateral ownership, debt ownership, borrow eligibility, deposit eligibility, withdrawal amount, repay amount, and solvency. `IShareToken` is an ERC20-style interface and the notification interface is explicitly transfer-oriented. If the deployed share-token implementations preserve that transferability, a user can move collateral shares or debt shares to another address without any solvency check, breaking the same-account collateral/debt invariant the silo relies on.

**Impact:** A borrower can strip collateral out of the indebted account or push debt shares onto a different address, then withdraw or re-borrow while leaving naked debt behind. If share transfers are enabled in production, this is a direct bad-debt and insolvency vector.

**Paths:**

- Account A deposits collateral and borrows another asset.

- A transfers its collateral share tokens to account B, or transfers its debt share tokens to account B.

- Because `borrowPossible`, `depositPossible`, withdrawals, repayments, and solvency all read current share balances only, the protocol now attributes collateral and debt to different addresses.

- Account B withdraws the transferred collateral, or account A appears debt-free enough to withdraw/re-borrow, leaving the silo with uncollectible debt.

*Round 1 | Agents: codex_1*

---

## High (2)

### F-002: Deposits and repayments trust nominal `_amount` instead of actual tokens received

**Confidence:** high | **Locations:** `0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:328, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:333, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:338, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:342, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:443, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:450, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:453, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:205, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/interfaces/ISiloRepository.sol:140, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/interfaces/ISiloRepository.sol:149`

`_deposit` mints shares and increases deposit totals by `_amount` before/without checking the real balance delta, and `_repay` reduces `totalBorrowAmount` by `repaidAmount` after pulling that nominal amount with `safeTransferFrom`. Liquidity, however, is derived from the silo's actual ERC20 balance. For fee-on-transfer, deflationary, or negative-rebasing assets, the silo can mint collateral shares for tokens it never received or burn debt for tokens it never actually collected.

**Impact:** If such an asset is ever listed, users can borrow against phantom collateral, underpay debt, and drive the pool into insolvency or withdrawal failure. The repository comments say these assets are unsupported, but the contracts do not enforce that restriction on-chain.

**Paths:**

- A fee-on-transfer token is listed as a silo or bridge asset.

- A user deposits 100 units; the silo receives less, but `totalDeposits` and the user's shares are still credited for 100.

- The user borrows against the overstated collateral, leaving a deficit in real assets.

- Similarly, a borrower can repay 100 nominal units of a fee-on-transfer debt asset, the silo receives less, but debt accounting is reduced by the full 100.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-005: Flash liquidation lets the liquidator set an arbitrary liquidation penalty by redepositing seized collateral

**Confidence:** high | **Locations:** `0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/Silo.sol:39, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:324, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:463, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:481, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:484, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:498, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:501, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:519, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:528, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/interfaces/IFlashLiquidationReceiver.sol:6`

`_flashUserLiquidation` burns all of the borrower's collateral shares and transfers all collateral to the liquidator before the callback. During `siloLiquidationCallback`, the liquidator can reenter `depositFor` because only the separate liquidation guard is active. The callback is not required to repay the advertised `shareAmountsToRepay`; the only post-condition is that `isSolvent(_user)` must be true. This lets the liquidator redeposit only part of the seized collateral back to the borrower, repay only the minimum additional debt needed to pass the solvency check, and keep the rest of the seized collateral as an uncapped bonus.

**Impact:** Insolvent users can lose substantially more collateral than any configured liquidation fee or intended close-factor-like penalty. The protocol remains solvent, but liquidators can extract arbitrary extra value from borrowers during liquidation.

**Paths:**

- A user becomes insolvent and a liquidator calls `flashLiquidate`.

- The silo seizes all collateral and transfers it to the liquidator before the callback.

- Inside `siloLiquidationCallback`, the liquidator calls `depositFor` to return only enough seized collateral to the borrower and repays only the residual debt needed for `isSolvent(user)` to pass.

- The transaction succeeds because the final check is solvency-only, while the liquidator keeps the remainder of the seized collateral.

*Round 1 | Agents: opencode_1*

---

## Medium (1)

### F-004: A reverting interest model on any synced asset can brick solvency-dependent flows for unrelated users

**Confidence:** high | **Locations:** `0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:42, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:170, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:380, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:423, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:476, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/lib/Solvency.sol:201, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/lib/Solvency.sol:213, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/lib/Solvency.sol:270`

`isSolvent` iterates over all assets ever synced into `_allSiloAssets`, including removed bridge assets. In `Solvency.getBorrowAmounts`, the code calls `getRcomp` for every asset before checking whether the user has any debt in that asset. If the repository returns a broken model, a removed asset's model starts reverting, or `getCompoundInterestRate` fails for any one synced asset, every `isSolvent` call reverts even for users with zero exposure to that asset.

**Impact:** Withdrawals, post-borrow validation, and liquidations can all become unavailable silo-wide because they depend on `isSolvent`. A single bad asset/model configuration can therefore create a broad denial of service for otherwise unrelated users.

**Paths:**

- A bridge asset is synced into the silo and later removed or misconfigured, but it remains in `_allSiloAssets`.

- Its interest-model lookup or `getCompoundInterestRate` path starts reverting.

- Any call path that reaches `isSolvent` now reverts while iterating that unrelated asset, blocking withdrawals, borrow finalization, and liquidations for affected users.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-003: Public `depositFor` enables permissionless dusting that blocks victims from borrowing the dusted asset

**Confidence:** high | **Locations:** `0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/Silo.sol:39, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:196, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:199, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:200, 0xcb3b879ab11f825885d5add8bf3672596d35197c/contracts/BaseSilo.sol:324`

`depositFor` is publicly callable, not router-restricted. `borrowPossible` rejects a borrower whenever they hold any regular or collateral-only share token for that asset. An attacker can therefore mint a tiny unwanted position for an arbitrary victim and force later borrows of that asset to revert until the victim spends gas to unwind it.

**Impact:** This is a permissionless griefing vector against users and integrators. An attacker can dust many addresses across many assets and block same-asset borrowing until each victim discovers and removes the dusted position.

**Paths:**

- An attacker calls `depositFor(asset, victim, 1, false)` or `depositFor(asset, victim, 1, true)` using their own tokens.

- The victim now has a nonzero collateral-share balance for `asset`.

- A later `borrow(asset, amount)` by the victim reverts with `BorrowNotPossible()` until the victim withdraws the unwanted dust.

*Round 1 | Agents: codex_1*

---
