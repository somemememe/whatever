# Audit Report

**Total findings:** 4

## High (2)

### F-001: Unlimited gateway approvals persist and survive router delisting, enabling drains of proxy-held tokens

**Confidence:** high | **Locations:** `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:81, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:19, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:22, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:24, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:29, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:380, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:382`

`routerCall` grants the caller-chosen `_gateway` a sticky `type(uint256).max` allowance through `SmartApprove` whenever allowance is insufficient. The approval is never revoked after the route, and `removeAvailableRouter` only updates the allowlist without clearing previously granted ERC20 approvals.

**Impact:** Any gateway/router address that is currently allowlisted, or was allowlisted in the past, can continue to pull approved tokens from the proxy if it exposes a public pull/forward primitive or is later compromised. This can drain current and future balances of that token held by the proxy, including accumulated Rubic fees, integrator fees, and other stranded user funds.

**Paths:**

- A user calls `routerCall` with `_gateway` set to an allowlisted spender/controller.

- The proxy executes `smartApprove` and leaves `_gateway` with `type(uint256).max` allowance for the route token.

- The route finishes, but no approval cleanup occurs.

- Even after `removeAvailableRouter(_gateway)`, the old spender can still call `transferFrom(proxy, attacker, amount)` or equivalent and drain proxy-held balances.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-002: Fee-on-transfer tokens are accounted by nominal input instead of actual receipt, allowing reserve drain

**Confidence:** high | **Locations:** `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:69, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:73, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:81, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:83, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:91, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:174, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:181, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:190`

For ERC20 routes, the proxy transfers `_params.srcInputAmount` from the user but never measures how many tokens were actually received. Fees and the gateway approval are both computed from the nominal `srcInputAmount`, not the post-transfer balance delta. With fee-on-transfer or deflationary tokens, `_amountIn` can therefore exceed the tokens really deposited into the proxy.

**Impact:** If the proxy already holds reserves of the same token, a route can consume those existing balances to satisfy the larger nominal allowance and post-call balance check. An attacker can repeatedly use taxed tokens to subsidize their own routes with previously accumulated Rubic fees, integrator fees, or stranded funds of the same token.

**Paths:**

- The attacker chooses a fee-on-transfer token for which the proxy already holds some balance.

- `safeTransferFrom` credits the proxy less than `_params.srcInputAmount`.

- `accrueTokenFees` and `smartApprove` still use the larger nominal amount and approve `_amountIn` to `_gateway`.

- The router/gateway pulls `_amountIn`, taking the shortfall from pre-existing proxy reserves, and the final balance-delta check still passes because it only compares against `_amountIn`.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-004: Caller-controlled integrator address lets anyone impersonate discounted fee plans

**Confidence:** medium | **Locations:** `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:26, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:56, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:174, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:212, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:311, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:71, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:107`

Fee selection trusts the user-supplied `_params.integrator` address directly. The route code loads `integratorToFeeInfo[_params.integrator]` and applies that fee schedule without checking that the caller belongs to, was referred by, or is otherwise authorized to use that integrator's pricing.

**Impact:** If any partner/integrator is configured with cheaper token fees or a lower fixed fee, any unrelated user can route under that partner's pricing and reduce Rubic's fee take permissionlessly. This also corrupts attribution by crediting fee shares to an integrator that did not originate the flow.

**Paths:**

- A manager configures an integrator entry with a discounted `tokenFee` and/or `fixedFeeAmount`.

- An arbitrary user sets `_params.integrator` to that integrator address in `routerCall` or `routerCallNative`.

- The proxy applies the discounted schedule and books the fee split under that integrator without authenticating the relationship.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-003: Configured per-token minimum and maximum route amounts are never enforced

**Confidence:** high | **Locations:** `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:30, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:33, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:343, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:356, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:61, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:96`

The protocol stores per-token `minTokenAmount` and `maxTokenAmount` values and provides admin setters for them, but neither `routerCall` nor `routerCallNative` checks these limits before accepting a route.

**Impact:** Managers cannot rely on the configured min/max values as an on-chain control. Users can route dust amounts or oversized amounts even when operators believe those values are blocked, weakening the protocol's only built-in per-token exposure guard and making other abuse paths easier to seed.

**Paths:**

- A manager configures `minTokenAmount[token]` and/or `maxTokenAmount[token]`.

- A user submits `routerCall` or `routerCallNative` with an amount outside that configured range.

- Execution proceeds normally because no entrypoint reads either mapping.

*Round 1 | Agents: codex_1*

---
