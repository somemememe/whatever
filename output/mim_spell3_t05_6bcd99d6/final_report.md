# Audit Report

**Total findings:** 3

## Critical (1)

### F-001: `cook()` lets borrowers bypass the post-action solvency check with any unsupported action

**Confidence:** high | **Locations:** `cauldrons/CauldronV4.sol:369, cauldrons/CauldronV4.sol:456, cauldrons/CauldronV4.sol:470, cauldrons/CauldronV4.sol:484, cauldrons/CauldronV4.sol:488, cauldrons/CauldronV4.sol:527, cauldrons/CauldronV4.sol:538`

`cook()` marks `status.needsSolvencyCheck = true` after `ACTION_BORROW` and `ACTION_REMOVE_COLLATERAL`, but any later unhandled action falls through to the empty `_additionalCookAction()` implementation and blindly replaces `status` with a zero-initialized struct. Because `ACTION_ACCRUE` is declared (`8`) yet never handled in the `cook()` dispatcher, a sequence such as `[BORROW, ACCRUE]` or `[REMOVE_COLLATERAL, ACCRUE]` clears the pending solvency check and returns successfully even when `msg.sender` is insolvent.

**Impact:** An attacker can borrow MIM without enough collateral or withdraw collateral from an already undercollateralized position, leaving immediate bad debt and draining the cauldron up to its available MIM liquidity.

**Paths:**

- Call `cook([5,8],[0,0],[abi.encode(int256(amount), attacker), bytes("")])` so `_borrow()` transfers MIM out, sets `needsSolvencyCheck`, then unhandled `ACTION_ACCRUE` zeroes the status and skips the final solvency check.

- Call `cook([4,8],[0,0],[abi.encode(int256(share), attacker), bytes("")])` from an undercollateralized account to remove collateral and then clear the pending solvency check the same way.

- Any unsupported action that reaches `_additionalCookAction()` in the base contract has the same effect; `ACTION_ACCRUE` is simply the easiest built-in trigger.

*Round 1 | Agents: codex*

---

## High (1)

### F-002: Oracle failures silently reuse or seed unsafe cached prices for borrowing, withdrawals, and liquidations

**Confidence:** medium | **Locations:** `cauldrons/CauldronV4.sol:158, cauldrons/CauldronV4.sol:218, cauldrons/CauldronV4.sol:226, cauldrons/CauldronV4.sol:232, cauldrons/CauldronV4.sol:494, cauldrons/CauldronV4.sol:567, interfaces/IOracle.sol:7`

`updateExchangeRate()` does not revert when `oracle.get()` reports failure; it simply returns the previously cached `exchangeRate`. `init()` is even looser and stores the returned `rate` while ignoring the `success` flag entirely. As a result, all safety-critical paths that depend on `updateExchangeRate()` or the cached `exchangeRate`—including the `solvent` modifier used by `borrow()` and `removeCollateral()`, the `cook()` rate check, and `liquidate()`—continue operating on stale or failure-path prices instead of halting.

**Impact:** If the oracle becomes unavailable during an adverse collateral move, borrowers can keep borrowing against an outdated favorable price or remove too much collateral while liquidations are delayed or under-executed, creating bad debt. If initialization happens while `oracle.get()` fails and returns an unsafe rate such as zero, the clone can start life with an invalid cached price that makes solvency checks trivially pass until a later successful update.

**Paths:**

- Collateral price drops, but `oracle.get()` starts returning `(false, staleRate)` or otherwise fails without a fresh quote; a borrower then uses `borrow()` or `removeCollateral()`, and the final solvency check reuses the old favorable rate instead of reverting.

- A liquidator calls `liquidate()` during the same oracle outage; the function explicitly accepts the fallback rate path, so unhealthy accounts may remain insufficiently liquidated or appear solvent under the stale cache.

- During `init()`, `oracle.get()` returns `success = false` with an unsafe rate; the clone still stores that rate in `exchangeRate`, after which early `borrow()` or `cook()` solvency checks rely on the bad cached value until some later successful oracle update occurs.

*Round 1 | Agents: codex*

---

## Medium (1)

### F-003: `addBorrowPosition()` lets the owner assign debt to arbitrary users without sending them any MIM

**Confidence:** high | **Locations:** `cauldrons/PrivilegedCauldronV4.sol:15, cauldrons/PrivilegedCauldronV4.sol:16, cauldrons/PrivilegedCauldronV4.sol:18, cauldrons/PrivilegedCauldronV4.sol:22`

The privileged `addBorrowPosition()` function increases `totalBorrow` and `userBorrowPart[to]` for any target address, but it never transfers borrowed MIM to that user and it bypasses the normal borrow flow's opening-fee accounting and per-address/total borrow-cap checks. The only validation is a solvency check against the currently cached `exchangeRate`.

**Impact:** The master-contract owner, or anyone who compromises that role, can force arbitrary users into debt they never received and push them into liquidation, effectively enabling collateral confiscation rather than merely changing protocol parameters.

**Paths:**

- The owner calls `addBorrowPosition(victim, amount)` one or more times until the victim approaches or crosses the liquidation threshold.

- Once the victim is insolvent, a liquidator can liquidate the account and seize collateral even though the victim never received the newly assigned MIM.

*Round 1 | Agents: codex*

---
