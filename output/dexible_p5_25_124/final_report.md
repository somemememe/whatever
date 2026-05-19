# Audit Report

**Total findings:** 2

## Critical (1)

### F-001: Permissionless `selfSwap()` lets anyone execute arbitrary external calls as Dexible and steal approved user funds

**Confidence:** high | **Locations:** `onchain_auto/0x33e690aea97e4ef25f0d140f1bf044d663091daf/contracts/dexible/Dexible.sol:61, onchain_auto/0x33e690aea97e4ef25f0d140f1bf044d663091daf/contracts/dexible/Dexible.sol:92, onchain_auto/0x33e690aea97e4ef25f0d140f1bf044d663091daf/contracts/dexible/baseContracts/SwapHandler.sol:43, onchain_auto/0x33e690aea97e4ef25f0d140f1bf044d663091daf/contracts/dexible/baseContracts/SwapHandler.sol:46`

`selfSwap()` is publicly callable, and `fill()` forwards each user-supplied route through an unrestricted `router.call(routerData)` from Dexible’s own address. That makes Dexible a public arbitrary-call proxy: an attacker can have Dexible call `ERC20.transferFrom(victim, attacker, amount)` on any token where the victim approved Dexible, or `ERC20.transfer(attacker, amount)` for any ERC20 balance already held by Dexible. The exploit does not require relay access or admin privileges; the attacker only needs to structure the swap so the outer call pays its own minimum fees and otherwise succeeds.

**Impact:** Any external account can steal tokens from arbitrary users who approved Dexible, drain stray/residual ERC20 balances held by Dexible, and generally exercise Dexible’s standing token permissions against third-party contracts. This is a direct theft primitive.

**Paths:**

- Attacker calls `selfSwap()` with an allowed fee token they can use to satisfy the swap’s fee checks and with `tokenOut.amount = 0` so no real swap output is required.

- Inside `fill()`, attacker supplies a route whose `router` is the target ERC20 contract and whose `routerData` encodes `transferFrom(victim, attacker, amount)` (or `transfer(attacker, amount)` to drain Dexible-held balances).

- Dexible executes `router.call(...)` as itself, so the token contract sees `msg.sender == Dexible` and honors Dexible’s existing allowance/balance, transferring funds to the attacker.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (1)

### F-002: Proxy deployment can be left uninitialized, allowing first caller to seize admin and upgrade control

**Confidence:** medium | **Locations:** `onchain_auto/0xde62e1b0edaa55aac5ffbe21984d321706418024/contracts/dexible/DexibleProxy.sol:17, onchain_auto/0xde62e1b0edaa55aac5ffbe21984d321706418024/contracts/dexible/DexibleProxy.sol:24, onchain_auto/0x33e690aea97e4ef25f0d140f1bf044d663091daf/contracts/dexible/Dexible.sol:19, onchain_auto/0x33e690aea97e4ef25f0d140f1bf044d663091daf/contracts/dexible/baseContracts/ConfigBase.sol:15, onchain_auto/0x33e690aea97e4ef25f0d140f1bf044d663091daf/contracts/dexible/baseContracts/ConfigBase.sol:17`

The proxy constructor makes initialization optional via `initData`. If the proxy is deployed with empty or unusable init data, `adminMultiSig` remains unset in proxy storage. `initialize()` is public, and `configure()` skips authorization entirely while `adminMultiSig == address(0)`, so the first external caller can initialize the live proxy with attacker-controlled admin, treasury, relays, vault, and fee configuration.

**Impact:** A missed or failed initialization during deployment enables full protocol takeover: the attacker becomes admin, can whitelist malicious relays, redirect treasury flows, point to attacker-controlled integrations, and control future upgrades.

**Paths:**

- The proxy is deployed with empty `initData`, or the initialization delegatecall is omitted/never succeeds, leaving `adminMultiSig` unset.

- Before the intended operator initializes the proxy, an attacker calls `initialize(config)` through the proxy fallback.

- Because `configure()` only enforces auth after `adminMultiSig` is nonzero, the attacker installs their own admin and system addresses and permanently takes control.

*Round 1 | Agents: codex_1, opencode_1*

---
