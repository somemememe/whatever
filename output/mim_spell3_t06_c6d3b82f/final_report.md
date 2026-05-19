# Audit Report

**Total findings:** 2

## Critical (1)

### F-001: Unhandled `cook` actions reset `CookStatus` and bypass the deferred solvency check after borrow or collateral removal

**Confidence:** high | **Locations:** `cauldrons/CauldronV4.sol:369, cauldrons/CauldronV4.sol:456, cauldrons/CauldronV4.sol:486, cauldrons/CauldronV4.sol:490, cauldrons/CauldronV4.sol:527, cauldrons/CauldronV4.sol:538`

`cook()` relies on a local `CookStatus` flag to defer solvency enforcement until the end of the batch. After `_removeCollateral()` and `_borrow()`, it sets `status.needsSolvencyCheck = true`. However, any action that falls into the final `else` branch assigns `status = returnStatus` from `_additionalCookAction()`. In the base contract `_additionalCookAction()` is an empty virtual function, so it returns a zero-initialized `CookStatus` and clears the pending solvency check instead of reverting. Because `ACTION_ACCRUE` is defined as action `8` but never explicitly handled, sequences like `[ACTION_BORROW, ACTION_ACCRUE]` or `[ACTION_REMOVE_COLLATERAL, ACTION_ACCRUE]` silently clear `needsSolvencyCheck` before the epilogue runs.

**Impact:** A borrower can take out unbacked MIM or pull pledged collateral from an already unsafe position without ever passing the intended solvency check. In practice this can drain available MIM liquidity, increase protocol bad debt, and let attackers stage temporary collateral only long enough to pass intermediate accounting before extracting it again.

**Paths:**

- cook([5,8],[0,0],[abi.encode(amount, attacker), bytes("")])

- cook([4,8],[0,0],[abi.encode(share, attacker), bytes("")])

- cook([5,100],[0,0],[abi.encode(amount, attacker), bytes("")])

- cook([4,100],[0,0],[abi.encode(share, attacker), bytes("")])

*Round 1 | Agents: codex*

---

## High (1)

### F-003: Clone initialization can lock in a failed zero oracle rate, making positions appear solvent

**Confidence:** medium | **Locations:** `cauldrons/CauldronV4.sol:146, cauldrons/CauldronV4.sol:158, cauldrons/CauldronV4.sol:192, cauldrons/CauldronV4.sol:226, cauldrons/CauldronV4.sol:234`

`init()` ignores the success flag from `oracle.get(oracleData)` and unconditionally stores the returned `rate` into `exchangeRate`. If the oracle reports failure with `(false, 0)`, the clone is initialized with `exchangeRate = 0`. Later, `updateExchangeRate()` preserves the cached value whenever the oracle again returns `updated == false`, so the zero rate can persist until the oracle eventually reports success. During that window `_isSolvent()` computes the debt side as `borrowPart * totalBorrow.elastic * _exchangeRate / totalBorrow.base`, which collapses to zero when `_exchangeRate == 0`.

**Impact:** While the cached exchange rate remains zero, any account with even minimal collateral is treated as solvent and can borrow up to the market's available MIM liquidity or remove collateral without the intended debt constraint. A clone deployed during an oracle outage can therefore be immediately drained before a successful oracle refresh restores a nonzero rate.

**Paths:**

- init(...) while oracle.get(oracleData) returns (false, 0)

- addCollateral(attacker, false, dustShare) -> borrow(attacker, maxAvailableMim)

- addCollateral(attacker, true, dustShare) -> cook([5],[0],[abi.encode(maxAvailableMim, attacker)])

*Round 1 | Agents: codex*

---
