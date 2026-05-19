# Audit Report

**Total findings:** 3

## Critical (2)

### F-001: Permissionless market creation lets attackers register arbitrary redemption assets and exchange-rate providers

**Confidence:** high | **Locations:** `CorkConfig.sol:12211, CorkConfig.sol:12227, ModuleCore.sol:457, ModuleCore.sol:502, ModuleCore.sol:438`

`CorkConfig.initializeModuleCore` and `CorkConfig.issueNewDs` are externally callable without a manager/admin check, while `ModuleCore.initializeModuleCore` accepts arbitrary `pa`, `ra`, and `exchangeRateProvider` values and `issueNewDs` later trusts that stored provider via `PsmLibrary._getLatestRate(state)`. This allows any user to permissionlessly create and roll over a fake market whose redemption asset is a real protocol token (for example, a live DS series) and whose exchange-rate provider is attacker-controlled.

**Impact:** An attacker can spin up counterfeit Cork markets around valuable protocol-held assets, mint fake CT/DS against those assets under attacker-chosen pricing, and use the resulting instruments in swaps or redemptions to steal reserve assets or drain protocol liquidity.

**Paths:**

- attacker -> CorkConfig.initializeModuleCore(pa, realDS, initialArp, expiryInterval, attackerRateProvider)

- attacker -> ModuleCore.getId(...) / CorkConfig.issueNewDs(id, ...)

- protocol -> ModuleCore.issueNewDs() -> PsmLibrary._getLatestRate(state) using attacker-controlled exchangeRateProvider

- attacker uses fake-market CT/DS as inputs to subsequent swap/redemption flows

*Round 1 | Agents: codex, merge-review*

---

### F-002: CorkHook.beforeSwap can be called directly with forged swap context

**Confidence:** high | **Locations:** `CorkHook.sol:beforeSwap`

`CorkHook.beforeSwap` does not authenticate that the caller is the Uniswap v4 `PoolManager`, so an attacker can invoke it directly and supply arbitrary `sender`, `PoolKey`, `SwapParams`, and `hookData`. Because the flash-swap path trusts that context, the attacker can spoof router/pool state and drive privileged swap-side accounting without a real pool-manager-mediated swap.

**Impact:** An attacker can impersonate legitimate swap execution, force the router/hook stack to decompose or transfer protocol assets under attacker-chosen parameters, and extract DS/CT or other reserve-backed value without performing an authorized swap.

**Paths:**

- attacker -> PoolManager.unlock(attackerData) -> attacker-controlled unlock callback

- attacker callback -> direct CorkHook.beforeSwap(forgedSender, forgedPoolKey, forgedSwapParams, forgedHookData)

- hook/router trust spoofed context and move protocol assets to attacker-controlled flow

*Round 1 | Agents: codex, merge-review*

---

## High (1)

### F-006: Near-expiry HIYA manipulation can force newly rolled markets to initialize CT at a severely discounted price

**Confidence:** high | **Locations:** `ModuleCore.sol:2028, ModuleCore.sol:2042, ModuleCore.sol:16695, ModuleCore.sol:16701, ModuleCore.sol:9675`

The rollover pricing path uses accumulated HIYA to choose the initial CT ratio for a new issuance when `isRollover` is true and no market price exists yet. HIYA is recomputed on every trade, and the risk-premium formula `rT = (1/pT)^(1/t) - 1` grows explosively as time-to-maturity approaches zero. Because there is no effective guardrail against tiny, late-expiry trades dominating HIYA, an attacker can execute a small trade just before expiry, massively inflate HIYA, and cause the next term to initialize CT far below fair value.

**Impact:** Attackers can acquire huge amounts of newly issued CT for negligible RA immediately after rollover, inflicting large economic losses on LPs/PSM reserves and creating the missing half of a CT+DS redemption pair for larger drain chains.

**Paths:**

- attacker performs late-expiry swap that updates HIYA

- reserve logic -> recalculateHIYA(...) accumulates manipulated near-expiry premium

- new issuance -> _determineRatio(...) uses manipulated HIYA to derive initial CT ratio

- attacker buys underpriced CT from the fresh market

*Round 1 | Agents: merge-review*

---
