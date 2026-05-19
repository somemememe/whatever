# Audit Report

**Total findings:** 5

## Critical (1)

### F-001: SimplePriceOracle lets any account arbitrarily reprice listed assets

**Confidence:** high | **Locations:** `onchain_auto/0xe16db319d9da7ce40b666dd2e365a4b8b3c18217/Contract.sol:1 (SimplePriceOracle.sol)`

SimplePriceOracle exposes setUnderlyingPrice and setDirectPrice as unrestricted public functions, so any external account can overwrite asset prices whenever a pool relies on this oracle.

**Impact:** Attackers can inflate collateral values or deflate borrowed-asset prices to borrow out real liquidity, and they can also invert prices to force liquidations of otherwise healthy accounts. This can directly steal user collateral and leave the pool insolvent.

**Paths:**

- Attacker calls setDirectPrice(asset, attackerPrice) or setUnderlyingPrice(cToken, attackerPrice) on the live oracle.

- The Comptroller consumes the forged price in account-liquidity or liquidation checks.

- Attacker either over-borrows against overpriced collateral or liquidates victims made artificially undercollateralized.

- Attacker exits with real assets or seized collateral before prices are restored.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (4)

### F-004: Rewards claims can be reentered before accrued balances are cleared

**Confidence:** medium | **Locations:** `onchain_auto/0xe16db319d9da7ce40b666dd2e365a4b8b3c18217/Contract.sol:1 (RewardsDistributorDelegate.sol)`

RewardsDistributorDelegate.claimRewards clears compAccrued only after grantCompInternal transfers reward tokens, and the claim path has no reentrancy guard.

**Impact:** If the configured reward token executes hooks or otherwise permits reentrancy during transfer, an attacker-controlled recipient contract can reenter claimRewards and withdraw the same accrued rewards multiple times, draining the distributor's reward inventory.

**Paths:**

- A hook-enabled reward token is configured and rewards accrue to an attacker-controlled contract.

- The attacker calls claimRewards(attackerContract).

- grantCompInternal transfers reward tokens before compAccrued[attackerContract] is updated.

- The recipient callback reenters claimRewards and reuses the still-unchanged accrued balance until rewards are exhausted.

*Round 1 | Agents: codex_1*

---

### F-005: A reverting rewards distributor can brick core market actions until the comptroller is upgraded

**Confidence:** high | **Locations:** `onchain_auto/0xe16db319d9da7ce40b666dd2e365a4b8b3c18217/Contract.sol:1 (Comptroller.sol)`

Comptroller synchronously calls every rewardsDistributor from mint, redeem, borrow, repay, transfer, seize, and liquidation paths, _addRewardsDistributor only checks a boolean marker, and there is no removal function.

**Impact:** Once an incompatible or buggy distributor is added, its revert can cause all hooked user actions across the pool to fail until admins replace the comptroller logic, creating protocol-wide denial of service.

**Paths:**

- Admin adds a distributor whose isRewardsDistributor marker returns true.

- That distributor later reverts or becomes too gas-heavy inside a flywheelPre* hook.

- Each core market action invokes the failing hook before completing.

- Users cannot mint, redeem, borrow, repay, transfer, seize, or liquidate until the comptroller is upgraded.

*Round 1 | Agents: codex_1*

---

### F-006: Unchecked reward-token transfers can erase accrued rewards without payment

**Confidence:** high | **Locations:** `onchain_auto/0xe16db319d9da7ce40b666dd2e365a4b8b3c18217/Contract.sol:1 (RewardsDistributorDelegate.sol)`

grantCompInternal only checks the distributor's balance, ignores the success value of rewardToken.transfer, and claimRewards overwrites compAccrued[holder] with the returned remainder.

**Impact:** If the configured reward token returns false instead of reverting, accrued rewards can be cleared even though no tokens were delivered. Because claimRewards is public, anyone can trigger this loss for affected users once the token enters such a failing state.

**Paths:**

- The distributor is initialized with a token whose transfer can return false on failure.

- Any caller invokes claimRewards(holder).

- grantCompInternal calls transfer, ignores the false return, and returns 0 as if payment succeeded.

- claimRewards stores compAccrued[holder] = 0, permanently deleting the unpaid reward balance.

*Round 1 | Agents: codex_1*

---

### F-007: Reservoir drip accounting advances even when token transfer fails silently

**Confidence:** high | **Locations:** `onchain_auto/0xe16db319d9da7ce40b666dd2e365a4b8b3c18217/Contract.sol:1 (Reservoir.sol)`

Reservoir.drip increments dripped before calling token.transfer and never checks whether the transfer succeeded.

**Impact:** With a false-return token, anyone can call drip() and permanently consume scheduled emissions without funding the target, stranding rewards in the reservoir and underpaying downstream recipients.

**Paths:**

- The reservoir is configured with a token whose transfer can fail silently by returning false.

- A caller invokes drip().

- dripped is increased before transfer success is verified.

- The transfer silently fails, but future emissions treat the missed amount as already paid out.

*Round 1 | Agents: codex_1*

---
