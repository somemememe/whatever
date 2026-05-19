# Audit Report

**Total findings:** 5

## High (2)

### F-001: Flashloan debt opening reuses a stale eMode snapshot after callback state changes

**Confidence:** medium | **Locations:** `0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/Pool.sol:348-365, 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/FlashLoanLogic.sol:103-155`

`Pool.flashLoan` snapshots `_usersEModeCategory[onBehalfOf]` into `flashParams.userEModeCategory` before calling the receiver. If the receiver is also `onBehalfOf`, it can change its stored eMode during `executeOperation`, but `FlashLoanLogic` later opens debt with the stale pre-callback category. The final borrow therefore validates against an outdated eMode rather than the category left in storage at transaction end.

**Impact:** A receiver can finish the transaction with debt sized for a more favorable eMode than the one actually active on the account, leaving the account immediately undercollateralized under the stored configuration and pushing liquidation/bad-debt risk onto the pool.

**Paths:**

- A user/receiver contract enters a favorable eMode category and calls `flashLoan` with `interestRateModes[i] != 0` on behalf of itself.

- Inside `executeOperation`, it calls `setUserEMode` to switch to category `0` or another weaker category while keeping its current position healthy under the new category.

- After the callback returns, `FlashLoanLogic.executeFlashLoan` calls `BorrowLogic.executeBorrow` with the stale `params.userEModeCategory` captured before the callback.

- The new debt is accepted under the old eMode assumptions even though storage now reflects the weaker category.

*Round 1 | Agents: codex_1*

---

### F-002: Isolation debt ceilings can be bypassed with repeated sub-unit borrows

**Confidence:** high | **Locations:** `0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/ValidationLogic.sol:195-203, 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/BorrowLogic.sol:137-142`

Isolation-mode debt accounting rounds each borrow down to `amount * 10^2 / 10^decimals`. Any borrow smaller than one debt-ceiling accounting unit contributes zero both in the validation check and in `isolationModeTotalDebt` updates, so repeated small borrows never count against the configured ceiling.

**Impact:** An isolated account can accumulate materially more borrow exposure than governance intended while `isolationModeTotalDebt` stays artificially low, weakening the main solvency guard for isolated collateral and increasing bad-debt exposure if that collateral fails.

**Paths:**

- A user enters isolation mode by supplying isolated collateral.

- The user repeatedly borrows a borrowable-in-isolation asset in chunks smaller than `10^(decimals-2)`.

- Each borrow passes `DEBT_CEILING_EXCEEDED` because the tracked increment rounds down to zero.

- The user accumulates debt well above the configured ceiling while on-chain isolation accounting remains understated.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-003: Reserve deletion ignores outstanding unbacked bridge liabilities

**Confidence:** high | **Locations:** `0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/BridgeLogic.sol:73-75, 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/ValidationLogic.sol:628-644, 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/PoolLogic.sol:157-165`

Bridge minting increases `reserve.unbacked`, but `validateDropReserve` only requires zero debt-token supply, zero hToken supply, and zero `accruedToTreasury`. It never requires `reserve.unbacked == 0`, so `executeDropReserve` can delete a reserve while the pool is still owed bridged liquidity.

**Impact:** Dropping the reserve erases the accounting needed to settle outstanding unbacked liquidity, turning a temporary bridge deficit into permanent unresolved insolvency for that market.

**Paths:**

- A bridge mints unbacked hTokens for a reserve, increasing `reserve.unbacked`.

- Those hTokens are later withdrawn/burned so hToken total supply returns to zero, while `reserve.unbacked` remains positive.

- The pool configurator calls `dropReserve`; validation passes because it does not inspect `unbacked`.

- `executeDropReserve` deletes the reserve storage, removing the state that `backUnbacked` would need to settle the liability.

*Round 1 | Agents: codex_1*

---

### F-005: feeToVault is never actually paid despite vault-fee accounting and events

**Confidence:** high | **Locations:** `0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/Pool.sol:389-390, 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/PoolLogic.sol:113-131`

`executeMintToTreasury` always mints the full accrued amount to the reserve treasury via `hToken.mintToTreasury(amountToMint, normalizedIncome)`. When `feeToVault` and `feeToVaultPercent` are set, it only subtracts `amountToVault` from a local variable and emits `CollectedToVault`; it never transfers or mints anything to `feeToVault`.

**Impact:** Revenue that governance configured for the ecosystem vault is silently diverted to the treasury instead of reaching the vault, and emitted events misstate the actual on-chain fee distribution.

**Paths:**

- The pool admin sets a non-zero `feeToVault` and `feeToVaultPercent`.

- `mintToTreasury` mints the full accrued amount to the reserve treasury.

- The function computes `amountToVault` only after minting, emits `CollectedToVault`, and emits `MintedToTreasury` with a reduced local number.

- No hTokens or underlying are ever transferred to `feeToVault`.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-006: Invalid flashloan premium splits can brick flashloan repayment

**Confidence:** high | **Locations:** `0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/Pool.sol:597-605, 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/FlashLoanLogic.sol:229-230`

`updateFlashloanPremiums` does not enforce `flashLoanPremiumToProtocol <= flashLoanPremiumTotal`. If governance sets the protocol share above the total premium, `_handleFlashLoanRepayment` underflows at `premiumToLP = totalPremium - premiumToProtocol` and the repayment path reverts.

**Impact:** A bad premium configuration can disable normal flashloan repayment paths and effectively DoS flashloans until governance fixes the parameters.

**Paths:**

- The pool configurator sets `flashLoanPremiumToProtocol` above `flashLoanPremiumTotal`.

- A user takes a flashloan that follows the repayment path.

- `_handleFlashLoanRepayment` computes a protocol cut larger than the total premium and underflows when deriving the LP share.

- The transaction reverts, preventing flashloans from completing.

*Round 1 | Agents: codex_1*

---
