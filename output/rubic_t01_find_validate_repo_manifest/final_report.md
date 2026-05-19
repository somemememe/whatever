# Audit Report

**Total findings:** 3

## High (1)

### F-001: Unlimited gateway approvals persist indefinitely and let any compromised allowlisted spender drain proxy-held ERC20 balances

**Confidence:** high | **Locations:** `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:66, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:81, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:19, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol:22, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:380`

`routerCall` grants `_gateway` a `type(uint256).max` allowance whenever its current allowance is below `_amountIn`, and that approval is never revoked after the route finishes or when the address is later removed from `availableRouters`. Any allowlisted spender that later becomes malicious or compromised can therefore call `transferFrom` against the proxy at arbitrary future times.

**Impact:** A compromised or retired gateway can steal all proxy-held balances of previously approved tokens, including accumulated Rubic fees, integrator fees, accidentally sent tokens, and any inventory temporarily parked in the proxy.

**Paths:**

- A user executes `routerCall` for token `T`, causing `SmartApprove` to set a max allowance from the proxy to `_gateway` for `T`.

- The route completes successfully, but the approval remains in place indefinitely.

- At any later time, `_gateway` calls `transferFrom(proxy, attacker, amount)` on token `T` and drains whatever balance the proxy currently holds.

- Even if admins later call `removeAvailableRouter(_gateway)`, the stale ERC20 allowance still remains active.

*Round 1 | Agents: codex*

---

## Medium (1)

### F-002: Gateway approval is not bound to the executed router, so callers can arm unrelated allowlisted spenders

**Confidence:** high | **Locations:** `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:61, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:66, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:81, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:85, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:48, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:368`

The contract uses one shared `availableRouters` set for both executable routers and token spenders, and `routerCall` only checks that both `_params.router` and `_gateway` are allowlisted. It never verifies that `_gateway` is actually the spender used by `_params.router`, so a caller can create a lasting allowance to any allowlisted gateway while executing a different route.

**Impact:** One compromised allowlisted integration can be armed by unrelated traffic and later drain proxy-held balances even when users route through a different integration, expanding the blast radius of a single bad whitelist entry.

**Paths:**

- The allowlist contains honest router `A` and compromised spender `B`.

- An attacker or ordinary caller invokes `routerCall` with `_params.router = A` and `_gateway = B`.

- The call executes through router `A`, but `SmartApprove` still grants `B` a max allowance for the bridged token.

- `B` later uses that allowance to drain proxy-held balances of that token.

*Round 1 | Agents: codex*

---

## Low (1)

### F-003: Configured per-token min/max limits are dead code and never enforced on bridge entrypoints

**Confidence:** high | **Locations:** `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:31, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:33, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:119, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:124, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:125, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:343, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol:356, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:61, onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol:96`

The protocol stores `minTokenAmount` and `maxTokenAmount` for each token and exposes admin setters described as transfer requirements, but neither `routerCall` nor `routerCallNative` checks those bounds before accepting and forwarding funds.

**Impact:** Configured safety guardrails can be bypassed completely, allowing dust or oversized routes that admins appear to have disabled. This can lead to downstream bridge failures, stuck user transfers, or economically undesirable routes that the protocol expected to block.

**Paths:**

- An admin configures a minimum or maximum amount for token `T`.

- A caller submits a route for `T` with an amount outside the configured band.

- The proxy accepts the funds and forwards the route anyway because no entrypoint reads `minTokenAmount[T]` or `maxTokenAmount[T]`.

*Round 1 | Agents: codex*

---
