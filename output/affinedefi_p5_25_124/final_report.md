# Audit Report

**Total findings:** 5

## High (2)

### F-001: Curve near-par minimum output plus swallowed divest reverts can permissionlessly DoS strategy exits

**Confidence:** high | **Locations:** `0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:160, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:181, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:214, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:261, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:313`

The strategy unwinds stETH through Curve with a near-par `min_dy` derived from the stETH input amount (`slippageBps` defaults to 10 bps), not from a live market quote. If the stETH/ETH pool moves beyond that threshold, Curve reverts. Vault withdrawals then silently convert that revert into a zero-asset divest because `AffineVault._divest()` catches all `strategy.divest()` failures and returns 0.

**Impact:** An attacker can front-run withdrawal, liquidation, rebalance, or strategy-removal transactions with a sufficiently large stETH->ETH trade, force the unwind swap to revert, and make the vault unable to source WETH from the strategy for that transaction. Organic stETH discounts can trigger the same failure mode, leaving capital temporarily stuck exactly when exits are needed.

**Paths:**

- Attacker or market movement pushes the stETH/ETH Curve execution price below the strategy's near-par `min_dy` threshold

- A vault withdrawal, liquidation, rebalance, or removal reaches `_endPosition()` or dec-leverage rebalancing and calls `CURVE.exchange(...)` with that stale threshold

- Curve reverts because actual ETH output is below `min_dy`

- `AffineVault._divest()` catches the revert and returns 0, so the vault cannot pull the requested WETH from the strategy

*Round 1 | Agents: codex_1, opencode_1*

---

### F-002: Balancer flash-loan fees are ignored, so any nonzero fee bricks flash-loan-dependent flows

**Confidence:** high | **Locations:** `0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/interfaces/balancer/IFlashLoanRecipient.sol:10, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:82, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:106`

Balancer's flash-loan callback requires repayment of principal plus `feeAmounts`, but `receiveFlashLoan()` discards `feeAmounts` and always transfers back only `ethBorrowed`.

**Impact:** If Balancer governance ever enables a nonzero flash-loan fee for this market, every invest, divest, rebalance, and upgrade flow that relies on `_flashLoan()` reverts. Because the strategy needs flash loans to unwind Aave debt, withdrawals and upgrades can become effectively frozen.

**Paths:**

- Balancer flash-loan fees become nonzero

- Any strategy action enters `receiveFlashLoan()`

- The callback repays only `amounts[0]` instead of `amounts[0] + feeAmounts[0]`

- Balancer reverts the entire transaction, bricking the flash-loan-dependent flow

*Round 1 | Agents: codex_1*

---

## Medium (3)

### F-003: `totalLockedValue()` underflows instead of flooring at zero, blocking distressed-strategy recovery flows

**Confidence:** medium | **Locations:** `0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:234, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:191, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:302, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:372, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:492`

Strategy TVL is computed as `_collateral() - _debt()` with no lower bound. If debt ever reaches or exceeds collateral, `totalLockedValue()` reverts from arithmetic underflow, and the vault directly calls this function in remove, withdraw, harvest, and rebalance paths.

**Impact:** When the leveraged Aave position is distressed, the vault can lose the ability to account for losses, remove the strategy, rebalance around it, or update its stored balances. Recovery operations fail precisely in the scenario where they are needed most.

**Paths:**

- Interest accrual, liquidation, or adverse market moves push strategy debt to collateral or above

- `LidoLevV3.totalLockedValue()` underflows and reverts

- Vault flows that read strategy TVL during harvest, removal, withdrawal bookkeeping, or rebalancing also revert

- Operators cannot cleanly account for or unwind the distressed strategy

*Round 1 | Agents: codex_1*

---

### F-004: TVL and divest sizing treat stETH collateral as if it exits at par, overstating withdrawable WETH during discounts

**Confidence:** medium | **Locations:** `0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:151, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:153, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:156, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:229, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:234`

The strategy values collateral with `getStETHByWstETH()` and sizes divest flash loans from that nominal stETH amount, but actual exits realize WETH only through Curve at the prevailing stETH/ETH market price. During a discount, both TVL and the proportional debt-repayment math are optimistic.

**Impact:** The vault can overstate holdings and request too little debt repayment to free a target amount of WETH. Even when divests do not revert, withdrawals and liquidations can come back short relative to requested assets, and losses remain understated until explicitly recognized.

**Paths:**

- stETH trades below ETH while the strategy still marks collateral at Lido's internal stETH conversion rate

- `totalLockedValue()` and `_getDivestFlashLoanAmounts()` use the inflated par valuation

- A divest repays too little debt and unlocks too little net WETH for the requested withdrawal amount

- Vault accounting and withdrawal planning assume more withdrawable WETH than the strategy can actually realize

*Round 1 | Agents: codex_1*

---

### F-005: `createAaveDebt()` authorizes any active strategy, enabling cross-strategy debt siphoning if another strategy is compromised

**Confidence:** low | **Locations:** `0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:330, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:334, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:335, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:339, 0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:343`

`createAaveDebt()` is meant for the upgrade handshake, but it authorizes callers only by checking that `msg.sender` is any active strategy in the same vault. It does not bind the call to a governance-approved upgrade or to the specific old strategy transferring collateral.

**Impact:** If another active strategy in the same vault is ever compromised or malicious, it can ask this strategy to borrow WETH against its own Aave collateral and transfer the borrowed WETH out to the caller, spreading one strategy compromise into losses for this one.

**Paths:**

- A different active strategy in the vault becomes malicious or compromised

- That strategy calls `createAaveDebt()` on this LidoLevV3 instance

- This contract borrows WETH against its own Aave position and transfers the borrowed WETH to the calling strategy

- The attacker-controlled strategy keeps the WETH while this strategy is left with the new debt

*Round 1 | Agents: opencode_1*

---
