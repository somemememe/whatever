# Audit Report

**Total findings:** 4

## High (2)

### F-001: Derivative unwinds and mint accounting use whole-contract balances instead of the current zap's deltas

**Confidence:** high | **Locations:** `BMIZapper.sol:270, BMIZapper.sol:282, BMIZapper.sol:284, BMIZapper.sol:287, BMIZapper.sol:310, BMIZapper.sol:326, BMIZapper.sol:434, BMIZapper.sol:454, BMIZapper.sol:489, BMIZapper.sol:533, BMIZapper.sol:556, BMIZapper.sol:571, BMIZapper.sol:581`

Multiple paths process the zapper's entire holdings rather than the amount attributable to the current caller. Yearn inputs call `withdraw()` with no share amount, Yearn-CRV paths forward `IERC20(crvToken).balanceOf(address(this))` and then `IERC20(USDC).balanceOf(address(this))`, Aave withdrawals use `type(uint256).max`, and the mint helpers repeatedly read `balanceOf(address(this))` for primitives and BMI constituents. Any residual derivative, primitive, or constituent tokens already sitting on the zapper are therefore pulled into the current caller's mint/refund flow.

**Impact:** A later caller can permissionlessly capture assets left on the zapper from prior users, accidental transfers, failed integrations, or unrefunded dust. This enables direct theft of contract-held Yearn shares, aTokens, Curve LP tokens, USDC, and BMI constituent tokens.

**Paths:**

- Residual `yUSDC` or `yCRV` shares exist on the zapper; an attacker submits a dust zap with the same token; `withdraw()` at lines 270/282 unwraps the entire share balance and the resulting assets are minted into BMI for the attacker.

- Residual `aUSDC` exists on the zapper; an attacker calls `zapToBMI` with a dust `aUSDC` amount; `withdraw(_fromUnderlying, type(uint256).max, ...)` at line 310 redeems the full aToken position and converts it for the attacker.

- Residual USDC or supported BMI constituents remain on the zapper; any later zap reaches lines 326/434/454/489/533/556/571/581 and folds those whole balances into the new caller's mint/refund outcome.

*Round 1 | Agents: codex_1*

---

### F-002: Final settlement transfers the zapper's entire BMI and USDC balances to the current caller

**Confidence:** high | **Locations:** `BMIZapper.sol:335, BMIZapper.sol:337, BMIZapper.sol:342, BMIZapper.sol:344`

`zapToBMI` does not track how much BMI or USDC was created during the current call. After processing, it transfers `IERC20(BMI).balanceOf(address(this))` to `msg.sender`, and when `refundDust` is enabled it also unwinds/refunds based on full constituent balances and then transfers the contract's entire USDC balance.

**Impact:** Any BMI or USDC already present on the contract can be drained by an arbitrary caller with minimal input. With `refundDust=true`, leftover refundable constituent value can likewise be converted and paid to the current caller.

**Paths:**

- BMI is accidentally sent to the zapper; an attacker calls `zapToBMI` with a minimal supported amount; line 335 reads the full BMI balance and line 337 transfers all of it to the attacker.

- USDC dust accumulates on the zapper from prior activity; an attacker calls `zapToBMI(..., refundDust=true)`; line 344 transfers the entire USDC balance regardless of who created it.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-003: Curve swap and liquidity legs hardcode zero minimum-output protection

**Confidence:** high | **Locations:** `BMIZapper.sol:365, BMIZapper.sol:381, BMIZapper.sol:385, BMIZapper.sol:391, BMIZapper.sol:396, BMIZapper.sol:487, BMIZapper.sol:531, BMIZapper.sol:551, BMIZapper.sol:553, BMIZapper.sol:569`

Every Curve `remove_liquidity_one_coin`, `exchange`, and `add_liquidity` call passes a minimum output of `0`, so each Curve leg accepts any execution price.

**Impact:** A sandwich attacker or temporary pool manipulator can push the zap through severely unfavorable Curve prices and extract value from users. The end-of-call `_minBMIRecv` check is only a coarse aggregate bound and does not protect each intermediate Curve leg or the dust-refund path.

**Paths:**

- An attacker moves the relevant Curve pool immediately before a victim zap; the zero-min Curve call executes at a manipulated price; the victim still settles if the final BMI stays above their loose `_minBMIRecv`, while the attacker captures the induced slippage.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-004: `refundDust` does not unwind supported `ySUSD` constituent dust

**Confidence:** high | **Locations:** `BMIZapper.sol:340, BMIZapper.sol:342, BMIZapper.sol:483, BMIZapper.sol:576, BMIZapper.sol:579, BMIZapper.sol:580`

`_toBMIConstituent` can mint `ySUSD` and deposit into the Yearn vault, but `refundDust` only calls `_fromBMIConstituentToUSDC`, which unwraps tokens only when `_isYearnCRV(_fromToken)` is true. `ySUSD` is supported as a constituent yet is never converted back to USDC during dust refunds.

**Impact:** Users requesting `refundDust` can still end up with residual `ySUSD` stuck on the zapper. That value becomes custodial to the owner via `recoverERC20`, and in this codebase can also be stolen later through the whole-balance accounting issue.

**Paths:**

- A zap buys slightly more `ySUSD` than `IBasket.mint(amountToMint)` consumes due to weighting or rounding; `refundDust=true` runs, but the leftover `ySUSD` is skipped by `_fromBMIConstituentToUSDC` and remains on the contract.

*Round 1 | Agents: codex_1*

---
