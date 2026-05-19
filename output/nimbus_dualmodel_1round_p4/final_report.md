# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Swap invariant uses a 10,000-based fee adjustment against a 1,000-based RHS, allowing near-total reserve drainage

**Confidence:** high | **Locations:** `0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:405, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:406, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:407`

`swap()` computes adjusted balances on a 10,000 scale (`balance*10000 - amountIn*15`) but compares them to `reserve0 * reserve1 * 1000**2` instead of `10000**2`. This weakens the constant-product check by 100x, so traders only need to preserve about 1% of the intended invariant.

**Impact:** An attacker can drain roughly 99% of either reserve with only a dust-sized counter-input, causing catastrophic LP loss.

**Paths:**

- Send a minimal amount of `token0` to the pair, then call `swap(0, reserve1 - reserve1/100, attacker, "")`; the weakened K-check still passes.

- Symmetrically, send a minimal amount of `token1`, then call `swap(reserve0 - reserve0/100, 0, attacker, "")`.

*Round 1 | Agents: codex_1*

---

## High (1)

### F-002: Swaps are hard-coupled to an external referral contract, creating a single-point denial of service

**Confidence:** high | **Locations:** `0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:387, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:391, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:392, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:398, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:399`

Every successful swap unconditionally transfers referral fees to `INimbusFactory(factory).nimbusReferralProgram()` and immediately calls `recordFee(...)` on that address. If the configured referral target reverts, is incompatible with one of the pool tokens, or is upgraded to malicious logic, the entire swap reverts.

**Impact:** A broken or malicious referral program can freeze trading for the pair, producing market-wide DoS for that pool.

**Paths:**

- Point `nimbusReferralProgram` to a contract whose `recordFee()` always reverts; every `swap()` that reaches the referral branch reverts.

- Use a token that blocks transfers to the configured referral address; `_safeTransfer(..., referralProgram, refFee)` then reverts and halts all swaps.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-003: Factory can reinitialize an existing pair because initialization is not one-time

**Confidence:** high | **Locations:** `0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:267, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:272, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:273, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:274, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:275`

`initialize()` only checks `msg.sender == factory` and never verifies that `token0` and `token1` are unset. The factory can therefore overwrite the pair's asset addresses after deployment.

**Impact:** If the factory is misused or compromised, an active pool can be rebound to different tokens, permanently stranding the original reserves and breaking LP redemption assumptions.

**Paths:**

- Users deposit liquidity into a live pair.

- The factory calls `initialize(maliciousTokenA, maliciousTokenB)` again, after which future `mint`, `burn`, and `swap` logic references the replacement tokens while the original assets remain trapped in the contract.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-004: Any LP tokens held by the pair are permissionlessly redeemable, including misrouted protocol fees

**Confidence:** high | **Locations:** `0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:296, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:307, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:340, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:346, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:353, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:354, 0xc0a6b8c534fad86df8fa1abb17084a70f86eddc1/Contract.sol:355`

`burn()` always redeems `balanceOf[address(this)]` and never authenticates who transferred or minted those LP tokens into the pair. As a result, any LP balance sitting on the pair contract can be burned by the first external caller and its underlying assets sent to an arbitrary recipient.

**Impact:** LP tokens accidentally sent to the pair can be stolen. If `feeTo` is ever misconfigured to the pair address, protocol fee LP minted by `_mintFee()` also become publicly claimable.

**Paths:**

- A user or integrator transfers LP tokens to the pair in one transaction and plans to call `burn()` later; an attacker frontruns or races with `burn(attacker)` and receives the underlying assets.

- The factory sets `feeTo = address(pair)`, `_mintFee()` mints fee LP to the pair itself, and any caller later invokes `burn(attacker)` to redeem those protocol fees.

*Round 1 | Agents: codex_1, opencode_1*

---
