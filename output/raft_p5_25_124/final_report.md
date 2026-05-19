# Audit Report

**Total findings:** 4

## High (4)

### F-001: The final position in a collateral market is permanently exempt from liquidation

**Confidence:** high | **Locations:** `0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:3485, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:3486, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4265`

`liquidate` reverts with `CannotLiquidateLastPosition()` whenever a position's debt equals that market's entire debt supply. In `InterestRatePositionManager`, `redeemCollateral` is hard-disabled, so the last borrower for a collateral type has no remaining permissionless close-out path even after becoming undercollateralized.

**Impact:** A sole or last borrower in a market can leave unrecoverable bad debt after the collateral price falls. Because neither liquidation nor redemption can remove that position, the market can remain permanently underbacked.

**Paths:**

- Open the only live position for a collateral market and borrow R.

- Let the collateral value fall below the market MCR.

- Any `liquidate(position)` call reverts because `entireDebt == totalDebt`.

- `redeemCollateral` is disabled in `InterestRatePositionManager`, so no alternative permissionless recovery path remains.

*Round 1 | Agents: codex_1*

---

### F-002: Collateral accounting credits nominal deposits instead of actual received balances

**Confidence:** medium | **Locations:** `0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:3871, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:3872, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:3895, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4014, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4015`

When collateral is increased, the position is credited with `collateralChange` before the contract verifies how many tokens were actually received. Solvency checks use the synthetic `raftCollateralToken` balance, while the true backing is only reflected later if/when `setIndex` is called from the manager's real token balance.

**Impact:** If a listed collateral token is fee-on-transfer, rebasing, or otherwise non-standard, borrowers can receive full collateral credit while the manager receives less real collateral. That lets users mint R against overstated collateral and can leave the protocol insolvent or cause later withdrawals/liquidations to fail once balances are reconciled.

**Paths:**

- Use a collateral token whose `transferFrom` delivers less than the requested amount.

- Call `managePosition(..., collateralChange, true, debtChange, true, ...)`.

- `raftCollateralToken.mint(position, collateralChange)` gives full accounting credit before the transfer completes.

- `_checkValidPosition` accepts the inflated position collateral, enabling borrowing against collateral the protocol never actually received.

*Round 1 | Agents: codex_1*

---

### F-003: Interest accrual over-mints fees by charging on already-indexed debt

**Confidence:** high | **Locations:** `0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4198, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4199, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4203, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4205`

`_unpaidFees()` computes fees as `totalSupply().mulDown(currentIndex_ - storedIndex)`, but `totalSupply()` already uses `currentIndex()`. The fee calculation therefore charges the index delta against debt that has already been fully indexed, instead of charging only the actual increase since `storedIndex`.

**Impact:** The protocol systematically mints too much R to the fee recipient and creates too much corresponding self-debt. Borrowers are overcharged, supply inflation exceeds the configured interest rate, and the accounting error compounds as the stored index grows.

**Paths:**

- Let an `InterestRateDebtToken` accrue from `storedIndex` to `currentIndex_`.

- Trigger `updateIndexAndPayFees()` through `mint`, `burn`, or a direct call.

- For example, debt growing from 100 to 110 should produce 10 of fees, but the implementation mints 11.

- The excess is repeated on every fee payment, causing persistent over-minting.

*Round 1 | Agents: codex_1*

---

### F-004: Fee minting can recurse into the manager's self-market debt token and brick interest updates

**Confidence:** low | **Locations:** `0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4180, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4182, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4205, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4095, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4098, 0x9ab6b21cdf116f611110b048987e58894786c244/contracts/InterestRates/InterestRatePositionManager.f.sol:4256`

`updateIndexAndPayFees()` calls `mintFees()` before updating `storedIndexUpdatedAt` and `storedIndex`. `mintFees()` mints R by opening or expanding the manager's self-collateralized position via `_mintR()`. If the self-market's debt token is itself an `InterestRateDebtToken` with pending fees, that nested `mint` reenters `updateIndexAndPayFees()` against unchanged state and recomputes the same unpaid fees again.

**Impact:** A deployment that uses an interest-bearing debt token for the manager's self-market can hit unbounded recursive fee minting once that self-market accrues fees. At that point fee payments, debt minting, debt burning, and any path that updates indexes can revert from recursion or out-of-gas, effectively freezing affected markets.

**Paths:**

- Configure the manager's self-collateral market (`IERC20(this)`) with an `InterestRateDebtToken` as its debt token.

- Allow that self-market debt token to accrue positive unpaid fees.

- Trigger any operation that reaches `updateIndexAndPayFees()` on an interest-bearing market.

- `mintFees` calls `_mintR`, which reenters `managePosition` on the self-market and invokes another debt-token `mint` before the outer call updates its stored index, repeating the same fee calculation.

*Round 1 | Agents: codex_1*

---
