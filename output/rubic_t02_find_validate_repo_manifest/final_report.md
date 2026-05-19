# Audit Report

**Total findings:** 4

## High (2)

### F-001: Shared router/gateway allowlist plus sticky max approvals lets allowlisted spenders drain proxy tokens

**Confidence:** high | **Locations:** `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:66, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:81, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:19, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:22, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:30, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:48, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:111, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:368, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:380`

`routerCall` authorizes `_gateway` and `_params.router` from the same shared `availableRouters` set, then `SmartApprove` grants `_gateway` a `type(uint256).max` allowance whenever the current allowance is insufficient. That allowance is never reset after the route finishes, and `removeAvailableRouter` only updates the set membership without revoking existing ERC20 approvals.

**Impact:** Any current or former allowlisted address that can act as a spender for the token can retain permanent pull rights over the proxy and later drain present and future balances of that token, including later user deposits, stuck funds, and accrued fees. The shared allowlist also means adding a router for call execution implicitly makes it eligible to become such a spender.

**Paths:**

- Admin allowlists router/spender address `R` via initialization or `addAvailableRouter`.

- A user executes a successful `routerCall` using `_gateway = R`, causing the proxy to grant `R` an unlimited allowance for the route token.

- The route completes, but the token approval remains in place because neither `routerCall` nor `removeAvailableRouter` clears it.

- At any later time, `R` or a compromised/upgraded controller behind `R` calls `transferFrom(proxy, attacker, amount)` and drains the proxy's balance of that token.

*Round 1 | Agents: codex*

---

### F-003: Fee-on-transfer tokens can make the proxy subsidize routes from pre-existing balances

**Confidence:** high | **Locations:** `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:69, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:73, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:81, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:83, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:91`

`routerCall` computes fees and the downstream spend amount from `_params.srcInputAmount` instead of the tokens actually received by the proxy. For deflationary or fee-on-transfer tokens, `safeTransferFrom` can credit fewer tokens than the nominal amount, but the proxy still approves and expects the larger post-fee `_amountIn`.

**Impact:** If the proxy already holds the same token from prior users, fees, or stuck balances, the missing amount is silently covered from that existing balance. An attacker can repeatedly route a deflationary token and extract value that is partially financed by other assets already sitting in the proxy.

**Paths:**

- The proxy already has balance of token `T` from fees, leftovers, or previously stranded funds.

- An attacker calls `routerCall` with fee-on-transfer token `T` and nominal input `X`.

- The token transfer credits the proxy with only `X - f`, but `_amountIn` is still derived from `X`.

- The allowlisted router/gateway spends `_amountIn` from the proxy, and the shortfall `f` is taken from the proxy's pre-existing `T` balance.

*Round 1 | Agents: codex*

---

## Medium (1)

### F-004: Refunded or unspent native value can be trapped in the proxy

**Confidence:** medium | **Locations:** `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:96, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:109, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:117, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:120`

`routerCallNative` forwards `_amountIn` to the allowlisted router but never verifies how much native value was actually consumed and never refunds ETH that returns to the proxy during the call. The proxy's `receive()` function accepts such refunds, and only the admin can later withdraw them through `sweepTokens(address(0), ...)`.

**Impact:** Whenever a downstream router refunds unused ETH to `msg.sender` or otherwise returns native dust to the proxy, the user permanently loses that value and it becomes admin-sweepable. This can systematically trap refund amounts on native routes.

**Paths:**

- A user calls `routerCallNative` with `msg.value` covering the route plus fees.

- The downstream allowlisted router spends less than the forwarded amount and refunds the unused ETH back to the caller, which is the proxy.

- `routerCallNative` performs no post-call reconciliation and does not return the refund to the user.

- The refunded ETH remains in the proxy until an admin withdraws it with `sweepTokens(address(0), amount)`.

*Round 1 | Agents: codex*

---

## Low (1)

### F-005: Configured per-token min/max amount limits are never enforced

**Confidence:** high | **Locations:** `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:31, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:33, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:343, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:356, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:61, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:96`

The contract stores `minTokenAmount` and `maxTokenAmount` and exposes admin setters for them, but neither `routerCall` nor `routerCallNative` checks those configured bounds before accepting a route.

**Impact:** Operators can believe they have on-chain per-token exposure caps when, in practice, users may submit arbitrarily small or large routes. That defeats the advertised sizing control and can lead to unexpected failed routes, trapped dust, or oversized downstream exposure contrary to protocol configuration.

**Paths:**

- Managers configure `minTokenAmount[T]` and `maxTokenAmount[T]` for token `T`.

- A user submits `routerCall` or `routerCallNative` with an amount outside those bounds.

- The call still executes because the entrypoints never reference the configured mappings.

*Round 1 | Agents: codex*

---
