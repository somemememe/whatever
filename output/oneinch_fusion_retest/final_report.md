# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Forged interaction offsets can redirect settlement parsing into an attacker-supplied historical settlement suffix

**Confidence:** medium | **Locations:** `FlawVerifier.sol:87, FlawVerifier.sol:89, FlawVerifier.sol:273, FlawVerifier.sol:401, FlawVerifier.sol:407, FlawVerifier.sol:418, FlawVerifier.sol:426`

`_buildForgedSettlementPayload()` constructs nested settlement interactions that terminate in `_buildTerminalCorruptedInteraction()`, where the payload hardcodes attacker-chosen signature/interaction offsets together with a near-max `FAKE_INTERACTION_LENGTH`, then appends a trailer encoding `HISTORICAL_VICTIM`, `USDC`, and `AMOUNT_TO_STEAL`. If the downstream settlement parser trusts those attacker-controlled offsets and lengths when locating the final interaction, parsing can wrap into the appended trailer and treat attacker-supplied historical context as the current order's authenticated final interaction.

**Impact:** A vulnerable settlement parser can be tricked into finalizing against forged historical victim context, enabling direct theft of previously approved USDC from the victim/resolver path rather than merely causing a revert.

**Paths:**

- Call `executeOnOpportunity()` or otherwise reach `_tryReplayCalldataCorruption()` so the contract submits the forged payload to `settleOrders`.

- Use `FAKE_SIGNATURE_LENGTH_OFFSET`, `FAKE_INTERACTION_LENGTH_OFFSET`, and `FAKE_INTERACTION_LENGTH` to push settlement parsing outside the intended interaction blob.

- Have parsing land on the appended `finalOrderInteraction` trailer, which reuses `HISTORICAL_VICTIM` and `AMOUNT_TO_STEAL` without fresh authorization.

*Round 1 | Agents: codex*

---

## High (1)

### F-003: Universal ERC1271 approval plus standing USDT allowance lets anyone drain contract-held USDT

**Confidence:** high | **Locations:** `FlawVerifier.sol:162, FlawVerifier.sol:177, FlawVerifier.sol:234`

`isValidSignature()` unconditionally returns the ERC1271 magic value for any hash and signature, and the contract grants `LIMIT_ORDER_PROTOCOL` a max USDT allowance in both `uniswapV2Call()` and `_prepareMakerCapital()`. Once that approval is in place, anyone can fabricate a limit order naming `address(this)` as maker and have the protocol pull this contract's USDT without any real signature authorization.

**Impact:** An attacker can drain all current and future USDT that lands in the contract through the approved limit-order protocol, resulting in direct asset theft.

**Paths:**

- Trigger `executeOnOpportunity()` once so `_prepareMakerCapital()` installs the unlimited USDT allowance, or reach the same approval path through the flash-swap callback.

- Create an arbitrary limit order with `maker = address(this)` and attacker-favorable terms.

- Fill the order through `LIMIT_ORDER_PROTOCOL`; `isValidSignature()` validates the fake signature and the protocol transfers out this contract's USDT.

*Round 1 | Agents: codex*

---

## Medium (2)

### F-004: Permissionless zero-min-output swaps expose contract balances to sandwich extraction

**Confidence:** high | **Locations:** `FlawVerifier.sol:110, FlawVerifier.sol:229, FlawVerifier.sol:259, FlawVerifier.sol:321`

`executeOnOpportunity()` is permissionless, and every router trade in `_prepareMakerCapital()`, `_swapUsdcForUsdt()`, and `_realizeProfitInWeth()` uses `amountOutMin = 1`. Any observer can manipulate the relevant Uniswap V2 pools immediately before calling or sandwiching execution, forcing the contract to accept almost any exchange rate.

**Impact:** ETH and USDC held by the contract can be converted at ruinous prices, with the attacker recovering the lost value in surrounding AMM trades.

**Paths:**

- Wait until the contract holds ETH or USDC and the one-shot execution path is still available.

- Skew the relevant `WETH/USDT`, `USDC/USDT`, or `USDC/WETH` pool immediately before invoking or sandwiching `executeOnOpportunity()`.

- Let the contract trade with `amountOutMin = 1`, then unwind the price manipulation and capture the spread.

*Round 1 | Agents: codex*

---

### F-005: Any user can permanently consume the one-shot execution path

**Confidence:** high | **Locations:** `FlawVerifier.sol:110, FlawVerifier.sol:116, FlawVerifier.sol:120`

`executeOnOpportunity()` sets `_executed = true` before attempting the flash seed, approvals, forged settlement, or profit realization, and none of the later failure paths resets the flag. After the first call, all subsequent calls only refresh profit and return.

**Impact:** A front-runner or griefing caller can trigger the routine in an unfunded or unfavorable state and permanently block future meaningful execution, preventing retries under better conditions and potentially stranding later-deposited assets because the contract has no recovery path.

**Paths:**

- Call `executeOnOpportunity()` before the intended operator has prepared balances or market conditions.

- Let the later settlement/flash-seed/realization steps fail or do nothing after `_executed` is already set.

- Observe that every later call exits early, so the main path cannot be retried.

*Round 1 | Agents: codex*

---
