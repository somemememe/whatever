# Audit Report

**Total findings:** 2

## Critical (1)

### F-001: Public exchange uses Curve with `min_dy = 0`, enabling flash-loan price manipulation and value extraction

**Confidence:** high | **Locations:** `0x765b8d7cd8ff304f796f4b6fb1bcf78698333f6d/Contract.sol:230, 0x765b8d7cd8ff304f796f4b6fb1bcf78698333f6d/Contract.sol:238`

`doExchange()` is permissionless and calls `curve.exchange_underlying(1, 2, camount, 0)` with no minimum-output check. An attacker can temporarily skew the referenced Curve pool, invoke `doExchange()` while the contract is swapping freshly issued USDC from `from_bank`, and force the trade to clear at an arbitrarily bad rate.

**Impact:** A flash-loan attacker can steal a large fraction of the source bank's economic value in a single transaction. The contract will release USDC from `from_bank`, accept a near-zero amount of USDT, and send that diminished output to `to_bank`, while the attacker captures the manipulated spread when unwinding the pool distortion.

**Paths:**

- Attacker uses a flash loan or other temporary liquidity to move the Curve pool price sharply against USDC->USDT swaps.

- Attacker calls `doExchange(amount)` for a large amount up to the current `from_bank.balance()`.

- The contract invokes `from_bank.issue(address(this), amount)`, approves Curve, and swaps with `min_dy = 0`, accepting the manipulated rate.

- Attacker restores the pool and realizes profit from the price distortion while protocol value has been extracted from `from_bank`.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (1)

### F-002: Anyone can trigger cross-bank issuance and drain `from_bank` liquidity without authorization

**Confidence:** medium | **Locations:** `0x765b8d7cd8ff304f796f4b6fb1bcf78698333f6d/Contract.sol:230, 0x765b8d7cd8ff304f796f4b6fb1bcf78698333f6d/Contract.sol:232, 0x765b8d7cd8ff304f796f4b6fb1bcf78698333f6d/Contract.sol:234, 0x765b8d7cd8ff304f796f4b6fb1bcf78698333f6d/Contract.sol:241`

`doExchange()` has no access control even though it triggers the privileged `from_bank.issue(address(this), amount)` flow and then transfers the swapped proceeds to `to_bank`. Any external account can therefore force arbitrary migrations out of `from_bank` up to its reported balance.

**Impact:** A third party can permissionlessly deplete the source bank's liquid backing and choose the timing of those migrations. Even without profiting directly, this can exhaust `from_bank` liquidity, break redemptions or issuance assumptions tied to that bank, and create a protocol-level denial of service or insolvency condition if liabilities remain associated with `from_bank`.

**Paths:**

- Attacker watches `from_bank.balance()` until meaningful liquidity is available.

- Attacker repeatedly calls `doExchange()` with amounts up to the current reported balance.

- Each call forces `from_bank.issue(...)` and moves the resulting value away from `from_bank` into `to_bank` without any operator or owner authorization.

*Round 1 | Agents: codex_1, opencode_1*

---
