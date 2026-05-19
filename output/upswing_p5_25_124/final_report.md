# Audit Report

**Total findings:** 3

## High (1)

### F-001: Zero-value `transferFrom` lets anyone tamper with another user's pressure accounting and force release/halving

**Confidence:** high | **Locations:** `0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol:ERC20.sol:70, 0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol:UpSwing.sol:157, 0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol:UpSwing.sol:165, 0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol:UpSwing.sol:171, 0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol:UpSwing.sol:124`

`ERC20.transferFrom()` calls `_transfer()` before subtracting allowance, and subtracting an allowance by `0` succeeds even when no approval exists. UpSwing's overridden `_transfer()` has non-standard side effects even for zero-amount transfers: `transferFrom(victim, UNIv2, 0)` increments `txCount[victim]`, and `transferFrom(victim, victim, 0)` reaches `releasePressure(victim)`. Because `releasePressure()` either settles the user's pending pressure or halves it when the computed burn exceeds pair liquidity, any third party can permissionlessly mutate another account's pressure lifecycle.

**Impact:** An attacker can grief traders at near-zero cost. Repeated zero-value `transferFrom(victim, UNIv2, 0)` calls can push `txCount[victim]` arbitrarily high, making future sells accrue negligible `sellPressure`. Separately, `transferFrom(victim, victim, 0)` can force an early settlement or a punitive halving of the victim's pending pressure based on current market conditions, and also triggers a liquidity-pool burn/sync when settlement succeeds.

**Paths:**

- After trading is unpaused, call `transferFrom(victim, UNIv2, 0)` repeatedly; no approval is needed because allowance is reduced by zero, but `txCount[victim]` still increments.

- When `victim` has pending pressure, call `transferFrom(victim, victim, 0)`; this invokes `releasePressure(victim)`, which either settles immediately if the computed amount is below pair balance or halves `sellPressure[victim]` if the amount is larger than pair liquidity.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-002: Pressure settlement uses manipulable spot pair balance and total supply instead of sale-time state

**Confidence:** medium | **Locations:** `0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol:UpSwing.sol:100, 0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol:UpSwing.sol:120, 0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol:UpSwing.sol:124, 0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol:UpSwing.sol:176`

`releasePressure()` computes the burn/mint amount from `amountPressure(sellPressure[user])`, and `amountPressure()` reads `balanceOf(UNIv2)` and `totalSupply()` at release time. Neither value is snapshotted when the sell pressure is created, so the eventual payout depends on mutable spot state rather than the state that produced the pressure.

**Impact:** A trader or MEV searcher can change another user's pending burn and Steam payout just before forcing release. Moving UPS into or out of the pair changes `balanceOf(UNIv2)`, and any holder can call `burn()` to reduce `totalSupply()`. Combined with the zero-value forced-release primitive, this makes user payouts and pair burns manipulable at settlement time, enabling unfair reward changes and price manipulation around `sync()`.

**Paths:**

- Let a target accumulate `sellPressure`, then alter the pair's UPS balance via trades or direct token transfers and immediately force `releasePressure(target)` with `transferFrom(target, target, 0)`.

- Burn UPS before forcing another user's release; the reduced `totalSupply()` increases the computed ratio inside `amountPressure()`, changing how much is burned from the pair and minted as Steam.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-003: Sell transfers emit a `Transfer` value that does not match actual balance changes

**Confidence:** high | **Locations:** `0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol:UpSwing.sol:162, 0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol:UpSwing.sol:167, 0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol:UpSwing.sol:173`

In `_transfer()`, sender and recipient balances are updated using the original `amount`, but when `recipient == UNIv2` the local `amount` variable is later reduced by `UPSMath(txCount[sender])` before the `Transfer` event is emitted. The logged event therefore reports a smaller amount than the number of UPS tokens that actually moved.

**Impact:** Off-chain systems and on-chain integrations that infer transfers from events can become desynchronized from real balances, leading to incorrect accounting, analytics, or reward attribution around sells to the pair.

**Paths:**

- Sell UPS to `UNIv2`; storage credits the pair with the full token amount, while the emitted `Transfer` event logs only the discounted post-`UPSMath` amount.

*Round 1 | Agents: codex_1*

---
