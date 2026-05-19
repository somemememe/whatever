# Audit Report

**Total findings:** 6

## High (2)

### F-001: MetaSwap underlying swaps over-credit fee-on-transfer meta tokens

**Confidence:** high | **Locations:** `onchain_auto/0x824dcd7b044d60df2e89b1bb888e66d8bcf41491/contracts/meta/MetaSwapUtils.sol:776, onchain_auto/0x824dcd7b044d60df2e89b1bb888e66d8bcf41491/contracts/meta/MetaSwapUtils.sol:792, onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:744, onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:761`

`swapUnderlying()` measures the actual amount received into `v.dx`, but when the sold asset is a meta-level pooled token it still prices the trade from the caller-supplied `dx` instead of the post-fee `v.dx`. A fee-on-transfer or burnable meta token therefore lets the caller receive output for tokens the pool never received.

**Impact:** If a meta pool ever lists a deflationary meta token, an attacker can repeatedly swap that token into other assets and drain real pool reserves.

**Paths:**

- MetaSwap.swapUnderlying -> MetaSwapUtils.swapUnderlying with `tokenIndexFrom < baseLPTokenIndex`

- Sell a fee-on-transfer meta token so actual receipt is `v.dx < dx`, but AMM math still credits `dx`

- Receive full-priced output backed by insufficient input

*Round 1 | Agents: codex_1*

---

### F-002: Older MetaSwap direct swaps misprice the base LP token leg

**Confidence:** high | **Locations:** `onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:400, onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:412, onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:424`

In the older `0x88cc4a...` MetaSwap implementation, `_calculateSwap()` treats the last pooled token like an ordinary token even though its `xp` balance is stored as `balance * baseVirtualPrice`. Swaps into the base-LP slot therefore pay out too many base LP tokens whenever the base pool virtual price exceeds 1e18.

**Impact:** An attacker can buy underpriced base LP tokens from the meta pool and redeem them in the base pool for excess underlying value, draining the meta pool.

**Paths:**

- MetaSwap.swap / calculateSwap with `tokenIndexTo == baseLPTokenIndex` on `0x88cc4a...`

- Swap a meta token into underpriced base LP tokens

- Redeem the LP tokens in the base pool for more underlying than paid in

*Round 1 | Agents: codex_1*

---

## Medium (3)

### F-003: Older MetaSwap one-token withdrawals into the base LP leg fabricate admin fees

**Confidence:** high | **Locations:** `onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:206, onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:276, onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:1031`

For `tokenIndex == last` in the older `0x88cc4a...` MetaSwap code, `_calculateWithdrawOneToken()` derives `dySwapFee` by comparing scaled `currentY/newY` values against an already unscaled `dy`. `removeLiquidityOneToken()` then subtracts more from `self.balances[last]` than it actually transfers or burns, manufacturing phantom admin fees.

**Impact:** Each one-sided withdrawal into the base-LP slot creates surplus base LP tokens that the owner can later collect via `withdrawAdminFees()`, siphoning value from remaining LPs and skewing later accounting.

**Paths:**

- MetaSwap.removeLiquidityOneToken with `tokenIndex == baseLPTokenIndex` on `0x88cc4a...`

- Balance accounting subtracts an overstated admin-fee amount from the stored base-LP balance

- Owner later calls `withdrawAdminFees()` to extract the fabricated surplus

*Round 1 | Agents: codex_1*

---

### F-004: Unexpected token balance drift is treated as owner-withdrawable admin fees

**Confidence:** medium | **Locations:** `onchain_auto/0x824dcd7b044d60df2e89b1bb888e66d8bcf41491/contracts/SwapUtils.sol:642, onchain_auto/0x824dcd7b044d60df2e89b1bb888e66d8bcf41491/contracts/SwapUtils.sol:1027, onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/SwapUtils.sol:642, onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/SwapUtils.sol:1027`

The contracts define admin fees as `token.balanceOf(address(this)) - self.balances[i]`. Any balance change that happens outside the protocol's own accounting, such as positive rebases, yield accrual, reward top-ups, or accidental direct transfers, becomes owner-withdrawable surplus instead of accruing to LPs; negative balance drift leaves recorded balances above reality and can break later operations.

**Impact:** Pools are unsafe for asynchronously rebasing or drifting tokens: externally accrued value can be confiscated by the owner, while negative drift can leave LPs undercollateralized or cause swaps/withdrawals and fee withdrawals to revert.

**Paths:**

- Positive external balance drift -> `getAdminBalance` / `withdrawAdminFees` treats the drift as admin fees

- Negative external balance drift -> recorded balances exceed actual holdings, causing later transfers or accounting to fail

*Round 1 | Agents: codex_1*

---

### F-006: Older MetaSwap underlying swaps into base tokens fabricate base-LP admin fees

**Confidence:** medium | **Locations:** `onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:795, onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:802, onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:810`

In the older `0x88cc4a...` `swapUnderlying()` path, when the output is a base-pool underlying token, `dyFee` is computed before the base-LP amount is scaled down by `baseVirtualPrice`. The subsequent `dyAdminFee` therefore remains denominated in virtual-price-scaled LP units, so the contract subtracts too much from the stored base-LP balance and creates fictitious admin fees.

**Impact:** Permissionless swaps into base underlying tokens can accumulate unbacked base-LP 'admin fees' that the owner can later withdraw, siphoning value from LPs and distorting pool accounting.

**Paths:**

- `swapUnderlying()` on `0x88cc4a...` with `tokenIndexTo >= baseLPTokenIndex` and at least one side in the meta pool

- Code scales `v.dy` down by `baseVirtualPrice` after computing `dyFee`, but computes `dyAdminFee` from the unscaled `dyFee`

- Stored base-LP balance is reduced too far, leaving a withdrawable surplus for the owner

*Round 1 | Agents: *

---

## Low (1)

### F-005: MetaSwap prices the base LP leg from a 10-minute stale virtual-price cache

**Confidence:** low | **Locations:** `onchain_auto/0x824dcd7b044d60df2e89b1bb888e66d8bcf41491/contracts/meta/MetaSwapUtils.sol:145, onchain_auto/0x824dcd7b044d60df2e89b1bb888e66d8bcf41491/contracts/meta/MetaSwapUtils.sol:1204, onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:145, onchain_auto/0x88cc4aa0dd6cf126b00c012dda9f6f4fd9388b17/contracts/meta/MetaSwapUtils.sol:1168`

MetaSwap reuses `metaSwapStorage.baseVirtualPrice` until the 10-minute cache expires, and state-changing meta-pool math prices the base-LP leg from that cached value instead of an always-fresh base-pool virtual price.

**Impact:** If the base pool virtual price moves materially during the cache window, the meta pool can execute swaps or liquidity actions at stale exchange rates, leaking value to arbitrageurs or otherwise mispricing LP entries/exits.

**Paths:**

- Base pool virtual price changes materially before cache expiry

- MetaSwap swap / addLiquidity / removeLiquidityOneToken / removeLiquidityImbalance executes using cached `baseVirtualPrice`

- Counterparties trade against stale pricing and LPs absorb the difference

*Round 1 | Agents: codex_1, opencode_1*

---
