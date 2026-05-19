# Audit Report

**Total findings:** 3

## Critical (1)

### F-001: Read-only reentrancy during Balancer exit lets LP collateral be valued at a transiently inflated price

**Confidence:** high | **Locations:** `Contract.sol:286, Contract.sol:291, Contract.sol:300, Contract.sol:306, FlawVerifier.sol:531, FlawVerifier.sol:533, FlawVerifier.sol:624, FlawVerifier.sol:625`

The Balancer `exitPool()` call sends ETH to the recipient before pool state has fully normalized, and the callback immediately reads `getAssetPrice(CB_STETH_STABLE)` and calls `setUserUseReserveAsCollateral(CSTECRV, false)`. The verifier explicitly records that the LP price observed in the callback exceeds both the pre-exit and post-exit price, so the lending system can be induced to evaluate account health using a transiently inflated BPT valuation.

**Impact:** A borrower can disable genuinely needed collateral while their account only appears solvent inside the reentrant pricing window. Once execution returns to normal state, the account is undercollateralized, enabling bad debt and downstream collateral theft/liquidation abuse.

**Paths:**

- Join Balancer pool with wstETH/WETH

- Deposit B-stETH-STABLE and steCRV as collateral

- Borrow WETH

- Call Balancer `exitPool()`

- In the ETH callback, oracle reads inflated B-stETH-STABLE price

- Call `setUserUseReserveAsCollateral(CSTECRV, false)` while health checks rely on the inflated value

*Round 1 | Agents: codex_1, opencode_1*

---

## High (1)

### F-002: Collateral withdrawal succeeds after manipulated collateral disable without a fresh solvency check

**Confidence:** medium | **Locations:** `Contract.sol:306, Contract.sol:311, Contract.sol:318, FlawVerifier.sol:535, FlawVerifier.sol:539, FlawVerifier.sol:625`

After steCRV is disabled as collateral inside the transient oracle-manipulation window, the exploit flow waits for `exitPool()` to finish, records the normalized post-exit LP price, and then successfully calls `withdrawCollateral(STECRV, ...)` while WETH debt is still open. That behavior indicates the withdrawal path is not re-evaluating whole-account solvency once the asset has been marked non-collateral.

**Impact:** An attacker can extract real collateral after using the manipulated valuation window to remove it from the health-factor calculation, leaving the protocol with an undercollateralized position and realizable bad debt.

**Paths:**

- Disable steCRV as collateral during the Balancer exit callback

- Let the Balancer exit finish so the LP price returns to normal

- Withdraw the full steCRV position while WETH debt remains outstanding

- Liquidate the residual position, externalizing the loss to the protocol

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (1)

### F-003: Anyone can permanently consume the verifier's only execution attempt

**Confidence:** high | **Locations:** `FlawVerifier.sol:155, FlawVerifier.sol:156, FlawVerifier.sol:157`

`executeOnOpportunity()` is permissionless and sets the global `attempted` flag before trying the flash-loan sequence. Any arbitrary caller can invoke it first, permanently causing all later calls to revert with `already-attempted`, regardless of whether the first run succeeded.

**Impact:** A third party can front-run or grief the intended operator and permanently brick the verifier's one-shot execution path, creating a zero-cost permissionless DoS against the contract.

**Paths:**

- Attacker calls `executeOnOpportunity()` before the intended operator

- `attempted` is set to `true`

- All future executions revert with `already-attempted`

*Round 1 | Agents: codex_1*

---
