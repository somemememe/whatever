# Audit Report

**Total findings:** 2

## Critical (1)

### F-001: Permissionless time-locked emergency withdrawal lets any EOA drain ROAR and LP reserves

**Confidence:** high | **Locations:** `Roar.sol:50, Roar.sol:51, Roar.sol:53, Roar.sol:59, Roar.sol:69`

`EmergencyWithdraw()` is publicly callable, and after `block.timestamp >= T0` its opaque arithmetic gate is automatically satisfied because `OFF == K * T0`. Any externally owned account can therefore trigger fixed ROAR and Uniswap-pair transfers to `tx.origin` without any ownership, role, or beneficiary check.

**Impact:** Once the preset timestamp is reached, arbitrary users can steal the contract's ROAR and LP holdings in fixed-size chunks. Because the function is never disabled, any later deposits that bring balances back above the hard-coded amounts can also be drained permissionlessly.

**Paths:**

- Wait until unix timestamp `1744770479` (2025-04-16 02:27:59 UTC), then call `EmergencyWithdraw()` from any EOA while the contract holds at least `100000000099978910611013632` ROAR and `26777446972437561344` LP tokens; both transfers are sent to the caller's `tx.origin`.

*Round 1 | Agents: codex*

---

## Medium (1)

### F-003: Hard-coded withdrawal amounts can permanently strand sub-threshold token balances

**Confidence:** high | **Locations:** `Roar.sol:57, Roar.sol:61, Roar.sol:67, Roar.sol:70, Roar.sol:73`

The withdrawal path ignores actual token balances and always attempts to transfer fixed amounts of both assets. If either token balance is below its hard-coded amount, the low-level transfer fails and the whole transaction reverts; if balances are above the constants, repeated calls eventually leave a remainder below the fixed amounts that this function can no longer withdraw.

**Impact:** This emergency path cannot recover arbitrary balances. Contracts holding less than the constants, or balances that are not exact multiples of them, can be left with permanently stuck ROAR and/or LP tokens unless another recovery mechanism exists.

**Paths:**

- Fund the contract with less than `100000000099978910611013632` ROAR or less than `26777446972437561344` LP tokens after the unlock time, then call `EmergencyWithdraw()`; one of the transfer calls returns false and the entire withdrawal reverts.

- Fund the contract with balances above the hard-coded amounts, call `EmergencyWithdraw()` repeatedly, and observe that once the remaining balance drops below the fixed transfer size, the leftover tokens can no longer be withdrawn through this function.

*Round 1 | Agents: codex*

---
