# Audit Report

**Total findings:** 2

## Critical (2)

### F-001: Permissionless `updateTotalAum()` lets attackers snapshot flash-manipulated portfolio value

**Confidence:** high | **Locations:** `makina.sol:92, makina.sol:94, makina.sol:180, makina.sol:181`

The exploit PoC successfully invokes `MACHINE.updateTotalAum()` from an arbitrary external contract immediately after temporarily skewing the underlying Curve markets and re-accounting the affected position. Because the call succeeds without any privileged setup and is placed at the exact point where manipulated prices are live, the protocol can be forced to persist an attacker-controlled inflated AUM.

**Impact:** If total AUM feeds share pricing, minting, redemptions, collateral checks, or treasury solvency logic, an attacker can inflate protocol value for a single transaction and extract real assets against that fake mark, causing protocol-wide fund loss.

**Paths:**

- Flash-loan capital into the referenced Curve pools

- Manipulate DUSD/USDC and MIM/3Crv/3Crv spot conditions upward

- Re-account the affected Caliber position while prices are distorted

- Call `updateTotalAum()` to store the inflated valuation

- Redeem or unwind against real assets before prices normalize

*Round 1 | Agents: codex*

---

### F-002: Arbitrary callers can re-account an existing Caliber position using manipulable live market state

**Confidence:** high | **Locations:** `makina.sol:119, makina.sol:162, makina.sol:174`

The PoC directly constructs an `ICaliberMinimal.Instruction` for a live `positionId` and calls `CALIBER.accountForPosition(...)` from an external attacker contract. The accounting result is then used as part of the exploit flow after Curve pool manipulation, showing that an untrusted caller can force a position to be re-marked using current externally manipulable market state rather than a delayed or manipulation-resistant valuation path.

**Impact:** An attacker can temporarily distort the markets referenced by a tracked position, force the protocol to recognize a fake gain or valuation increase, and then monetize that incorrect accounting through downstream AUM or withdrawal logic, leading to theft of real pool assets.

**Paths:**

- Flash-loan capital into the pools that feed the position valuation

- Temporarily distort DUSD, MIM, and nested LP pricing

- Call `accountForPosition(instruction)` for the targeted live position

- Propagate the inflated accounting result into downstream protocol value calculations

- Exit the manipulation and keep the extracted assets

*Round 1 | Agents: codex*

---
