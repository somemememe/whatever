# Audit Report

**Total findings:** 4

## High (3)

### F-001: Hard-delisting a live market removes its debt from solvency checks and bricks normal resolution flows

**Confidence:** high | **Locations:** `0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:274, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:378, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:539, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:595, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:676, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:928, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:1272`

`_delistMarket(bToken, true)` deletes `markets[bToken]` without setting `isMarketDelisted[bToken]`. After that, `isMarketListedOrDelisted(bToken)` becomes false, so `getHypotheticalAccountLiquidityInternal` skips the asset entirely, while `redeemAllowed`, `repayBorrowAllowed`, `liquidateBorrowAllowed`, and `seizeAllowed` all reject the market as unlisted.

**Impact:** Outstanding borrows in the hard-delisted market stop counting in account-liquidity checks, so a borrower can withdraw collateral or open fresh borrows elsewhere despite still owing the delisted debt. At the same time, suppliers and liquidators lose the normal redeem/repay/liquidate/seize paths for that market, turning live positions into trapped funds and unrecoverable bad debt.

**Paths:**

- Admin/guardian first set collateral factor to zero and pause mint/borrow/flashloan, then admin calls `_delistMarket(bToken, true)` while borrows or deposits still exist.

- A borrower with debt in that market interacts with another listed market; `getHypotheticalAccountLiquidityInternal` skips the hard-delisted debt and overstates solvency.

- Any normal attempt to redeem, repay, liquidate, or seize against the hard-delisted market reverts with `market not listed`.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-002: `_supportMarket` can list an incompatible BToken from another comptroller as valid collateral

**Confidence:** medium | **Locations:** `0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:140, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:676, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:928, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:1242`

`_supportMarket` only sanity-checks `bToken.isBToken()` and never verifies that the market is actually configured for this comptroller. Once listed, users can `enterMarkets` on that foreign BToken and its balances/prices are trusted in local liquidity checks, but liquidation later relies on `seizeAllowed`'s comptroller-match invariant.

**Impact:** If governance/admin lists a BToken belonging to another comptroller or an otherwise incompatible market, users can borrow against collateral that this comptroller cannot reliably seize. That creates positions that pass borrow checks but can become permanently unliquidatable, leading to bad debt and insolvency.

**Paths:**

- Admin lists BToken `X` via `_supportMarket` even though `X.comptroller()` is not this comptroller.

- A user enters `X` as collateral through `enterMarkets([X])`; local liquidity uses `X.getAccountSnapshot()` and the local oracle price.

- The user borrows from a legitimate local market `Y`; when liquidation is attempted, `seizeAllowed` reverts on `comptroller mismatched` for `X` vs `Y`.

*Round 1 | Agents: codex_1*

---

### F-003: Lowering a credit limit below existing debt preserves credit-account immunity and can freeze bad debt in place

**Confidence:** high | **Locations:** `0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:539, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:595, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:676, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:822, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:1521, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:1539`

Credit limits are enforced only on new borrows. If admin/creditLimitManager reduces `_creditLimits[protocol][market]` below a protocol's already outstanding debt but keeps it above zero, `isCreditAccount` remains true, so `repayBorrowAllowed` blocks third-party repayment and `liquidateBorrowAllowed`/`seizeAllowed` block liquidation even though the account is now over its intended limit.

**Impact:** An impaired or malicious credit account can keep an oversized unsecured debt position that the protocol cannot force-close. The guardian pause path is especially dangerous because `_pauseCreditLimit` sets the limit to `1`, intentionally preserving credit-account status while leaving any larger existing debt dependent on voluntary self-repayment.

**Paths:**

- A protocol borrows under a positive credit limit.

- Admin or `creditLimitManager` lowers that market's credit limit below the already outstanding borrow, or guardian calls `_pauseCreditLimit(protocol, market)` and sets it to `1`.

- The borrower stops cooperating; third-party repay and liquidation are rejected because the account still qualifies as a credit account.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-004: Soft-delisting a collateral-cap market clears its controller-side version flag and skips `unregisterCollateral` on exit

**Confidence:** medium | **Locations:** `0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:201, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:219, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:274, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/Comptroller.sol:1272, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/BTokenInterfaces.sol:139, 0xffadb0bba4379dfabfb20ca6823f6ec439429ec2/lib/blueberry-core/contracts/money-market/BTokenInterfaces.sol:498`

A soft delist sets `isMarketDelisted[bToken] = true` and then `delete markets[bToken]`. That resets `markets[bToken].version` to the default `VANILLA`, so later `exitMarket` no longer recognizes a previously `COLLATERALCAP` market and skips the `unregisterCollateral` hook.

**Impact:** Users can continue unwinding soft-delisted positions, but the separate collateral-cap bookkeeping can remain overstated. Stale `totalCollateralTokens` / `accountCollateralTokens` can exhaust the cap or block later collateral actions, creating protocol-level lockups or long-lived accounting corruption for that market.

**Paths:**

- Admin soft-delists a market that had been listed as `Version.COLLATERALCAP`.

- Because `isMarketDelisted` stays true, users can still redeem and call `exitMarket` after unwinding their position.

- `exitMarket` sees the reset `VANILLA` version and skips `unregisterCollateral`, leaving collateral-cap state stale.

*Round 1 | Agents: codex_1*

---
