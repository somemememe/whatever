# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: `cook()` can erase pending solvency checks via `ACTION_ACCRUE` or any unhandled action

**Confidence:** high | **Locations:** `cauldrons/CauldronV4.sol:369, cauldrons/CauldronV4.sol:456, cauldrons/CauldronV4.sol:479, cauldrons/CauldronV4.sol:486, cauldrons/CauldronV4.sol:488, cauldrons/CauldronV4.sol:527, cauldrons/CauldronV4.sol:539`

`ACTION_ACCRUE` is declared as a supported cook action, but `cook()` never handles it explicitly. It falls through to `_additionalCookAction()`, whose base implementation returns a zero-initialized `CookStatus`; because `cook()` blindly assigns `status = returnStatus`, any trailing `ACTION_ACCRUE` or other unhandled action clears `needsSolvencyCheck` after `_borrow()` or `_removeCollateral()` has already mutated debt/collateral state.

**Impact:** An attacker can borrow available MIM without maintaining collateralization, or remove collateral from an undercollateralized position, because the final solvency gate can be skipped entirely. This can drain market liquidity and leave bad debt.

**Paths:**

- `cook([ACTION_BORROW, ACTION_ACCRUE], ...)` -> `_borrow()` transfers MIM out -> `status.needsSolvencyCheck` is reset to false -> final solvency check is skipped

- `cook([ACTION_REMOVE_COLLATERAL, ACTION_ACCRUE], ...)` -> `_removeCollateral()` transfers collateral out -> `status.needsSolvencyCheck` is reset to false -> insolvent withdrawal persists

- Any future or unknown action that falls into `_additionalCookAction()` on the base contract can likewise clear a previously queued solvency check

*Round 1 | Agents: codex*

---

## High (2)

### F-002: Stale oracle fallback lets solvency-critical actions and liquidations proceed on outdated prices

**Confidence:** medium | **Locations:** `cauldrons/CauldronV4.sol:216, cauldrons/CauldronV4.sol:226, cauldrons/CauldronV4.sol:230, cauldrons/CauldronV4.sol:234, cauldrons/CauldronV4.sol:292, cauldrons/CauldronV4.sol:329, cauldrons/CauldronV4.sol:539, cauldrons/CauldronV4.sol:567, cauldrons/CauldronV4.sol:578`

`updateExchangeRate()` treats `oracle.get()` failure as non-fatal and silently reuses the cached `exchangeRate`. That stale rate is then trusted by the `solvent` modifier, `cook()`'s final solvency check, and `liquidate()`, so the protocol continues making collateralization decisions even when the oracle has stopped updating.

**Impact:** If collateral value falls while the oracle is unavailable, borrowers can still open or expand debt and withdraw collateral using an obsolete favorable quote, creating undercollateralized debt and draining MIM liquidity. Conversely, if the cached rate is too pessimistic after collateral recovers, healthy users can still be liquidated against an outdated low price.

**Paths:**

- Collateral price drops -> `oracle.get()` returns `false` -> attacker calls `borrow()` while cached rate is still high enough to pass solvency

- Collateral price drops -> `oracle.get()` returns `false` -> attacker calls `removeCollateral()` or `cook()` and extracts collateral using the stale quote

- Collateral price rises after a previously low cached quote -> `oracle.get()` keeps failing -> `liquidate()` still uses the stale low rate and can seize collateral from positions that would be solvent at the current market price

*Round 1 | Agents: codex*

---

### F-003: Clone initialization accepts a failed or zero oracle quote and can cache `exchangeRate = 0`

**Confidence:** medium | **Locations:** `cauldrons/CauldronV4.sol:146, cauldrons/CauldronV4.sol:158, cauldrons/CauldronV4.sol:216, cauldrons/CauldronV4.sol:226`

`init()` stores the rate returned by `oracle.get()` without checking the success flag and without rejecting a zero rate. If initialization happens while the oracle is failing or returning `0`, the clone starts with `exchangeRate == 0`; subsequent failed refreshes keep reusing that cached zero value.

**Impact:** While the cached rate remains zero, `_isSolvent()` evaluates the debt side to zero, so a newly deployed market with available MIM liquidity can be drained through effectively uncollateralized borrowing until a successful non-zero oracle update occurs.

**Paths:**

- `init()` runs while `oracle.get()` returns `(false, 0)` or an invalid zero rate -> `exchangeRate` is cached as `0`

- Attacker borrows from the freshly initialized market before any successful non-zero rate update -> solvency checks see zero debt value and pass

- If later `updateExchangeRate()` calls also fail, the cached zero rate persists and extends the drain window

*Round 1 | Agents: codex*

---

## Medium (1)

### F-004: Anyone can claim collateral shares that were transferred directly to the Cauldron and withdraw them

**Confidence:** high | **Locations:** `cauldrons/CauldronV4.sol:241, cauldrons/CauldronV4.sol:249, cauldrons/CauldronV4.sol:251, cauldrons/CauldronV4.sol:265, cauldrons/CauldronV4.sol:273, cauldrons/CauldronV4.sol:292`

When `skim=true`, `addCollateral()` only checks that the Cauldron already holds excess BentoBox shares beyond `totalCollateralShare`. It does not track who originally deposited those shares, so any caller can convert stray collateral already sitting in the Cauldron's BentoBox balance into their own `userCollateralShare`.

**Impact:** Collateral mistakenly sent or deposited directly to the Cauldron's BentoBox balance can be stolen permissionlessly. After crediting themselves with those excess shares, an attacker can call `removeCollateral()` and withdraw the assets because they hold no debt.

**Paths:**

- Victim or integration transfers collateral shares directly to the Cauldron's BentoBox balance instead of crediting a user position

- Attacker calls `addCollateral(attacker, true, excessShare)` to assign those excess shares to themselves

- Attacker calls `removeCollateral(attacker, excessShare)` and withdraws the collateral

*Round 1 | Agents: codex*

---
