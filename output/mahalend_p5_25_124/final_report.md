# Audit Report

**Total findings:** 3

## High (2)

### F-001: Flash-loan debt opening reuses a stale eMode category after the callback

**Confidence:** high | **Locations:** `0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/pool/Pool.sol:397, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/pool/Pool.sol:410, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/pool/Pool.sol:714, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/FlashLoanLogic.sol:101, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/FlashLoanLogic.sol:134, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/ValidationLogic.sol:204, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/GenericLogic.sol:87, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/EModeLogic.sol:59`

`Pool.flashLoan` snapshots `_usersEModeCategory[onBehalfOf]` into `flashParams.userEModeCategory` before the receiver callback runs. During `executeOperation`, a receiver that is also `onBehalfOf` can call `setUserEMode` to disable or downgrade its own eMode. After the callback, `FlashLoanLogic.executeFlashLoan` still passes the stale pre-callback category into `BorrowLogic.executeBorrow`, and `ValidationLogic.validateBorrow` / `GenericLogic.calculateUserAccountData` reuse that stale category for the final collateral and health-factor checks.

**Impact:** A borrower can open debt at the end of a flash loan using obsolete, more favorable eMode parameters after having already switched to a less favorable or disabled mode. This can finalize positions that would fail the normal post-change health-factor validation, creating immediately undercollateralized debt and potential bad debt.

**Paths:**

- Attacker-controlled contract enables a favorable eMode category for itself.

- The contract calls `flashLoan(..., receiverAddress=self, onBehalfOf=self, interestRateModes[i] != 0)`.

- Inside `executeOperation`, the contract calls `setUserEMode(0)` or switches to a weaker category.

- After the callback, the pool still validates the debt opening with the stale cached `userEModeCategory` and mints debt that should no longer be allowed.

*Round 1 | Agents: codex_1*

---

### F-003: Reserve accounting trusts nominal transfer amounts instead of actual received amounts

**Confidence:** high | **Locations:** `0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/SupplyLogic.sol:65, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/SupplyLogic.sol:67, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/SupplyLogic.sol:69, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/BorrowLogic.sol:217, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/BorrowLogic.sol:227, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/BorrowLogic.sol:254, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/FlashLoanLogic.sol:229, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/FlashLoanLogic.sol:242, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/FlashLoanLogic.sol:244, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/LiquidationLogic.sol:169, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/LiquidationLogic.sol:171, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/LiquidationLogic.sol:209, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/BridgeLogic.sol:125, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/BridgeLogic.sol:137`

Core reserve accounting assumes ERC20 transfers are exact and never measures balance deltas before and after token pulls. `executeSupply` updates rates and mints aTokens for `params.amount`; `executeRepay` burns debt and updates rates for `paybackAmount` before pulling tokens; flash-loan repayment books `amountPlusPremium` before the transfer; liquidation burns debt and updates reserve state before receiving `actualDebtToLiquidate`; and `executeBackUnbacked` credits `added` liquidity without verifying the actual amount received.

**Impact:** If a fee-on-transfer, deflationary, rebasing, or otherwise non-standard token is listed as a reserve asset, users can receive too many aTokens, extinguish more debt than they actually repay, under-repay flash loans, or liquidate positions without sending the full debt asset. That can drain liquidity and leave the reserve insolvent.

**Paths:**

- A non-standard token that delivers less than the requested transfer amount is listed as a reserve asset.

- An attacker supplies the asset and receives accounting credit for the nominal amount instead of the net amount received by the aToken.

- Or the attacker repays, liquidates, backs unbacked liquidity, or repays a flash loan with the same token while reserve state assumes the full nominal amount arrived.

- Protocol accounting becomes overstated relative to real balances, enabling reserve drain or bad debt.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-002: Full liquidation with protocol fees can leave the collateral bit permanently stuck on

**Confidence:** high | **Locations:** `0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/LiquidationLogic.sol:193, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/LiquidationLogic.sol:203, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/configuration/UserConfiguration.sol:181, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/ValidationLogic.sol:447, 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/SupplyLogic.sol:259`

During liquidation, the liquidator receives `actualCollateralToLiquidate` and the treasury separately receives `liquidationProtocolFeeAmount`. The collateral bit is cleared only when `actualCollateralToLiquidate == userCollateralBalance`. When a non-zero liquidation protocol fee is charged, a full liquidation instead satisfies `actualCollateralToLiquidate + liquidationProtocolFeeAmount == userCollateralBalance`, so the victim can be left with zero aTokens while `isUsingAsCollateral` stays set.

**Impact:** A fully liquidated account can be left with a permanently stale collateral flag. If that reserve has a non-zero debt ceiling, `getIsolationModeState` can keep treating the user as isolated even with zero balance, blocking future collateral activation and borrowing from that address unless governance/admins intervene.

**Paths:**

- Victim uses an isolated-collateral reserve and the reserve charges a non-zero liquidation protocol fee.

- A liquidator fully liquidates the position.

- The liquidator and treasury together remove the victim’s entire aToken balance, but the code compares only `actualCollateralToLiquidate` against the pre-liquidation balance.

- The victim now has zero balance, cannot call `setUserUseReserveAsCollateral(false)` because of the positive-balance requirement, and remains stuck with the collateral bit enabled.

*Round 1 | Agents: codex_1*

---
