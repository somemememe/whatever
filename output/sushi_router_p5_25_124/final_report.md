# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Arbitrary V3-style pools can forge callbacks and steal approved user funds

**Confidence:** high | **Locations:** `0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:315, 0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:340-347, 0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:360, 0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:386-393`

`swapUniV3` and `swapTridentCL` accept arbitrary pool addresses from the route, then authenticate callbacks only by checking `msg.sender == lastCalledPool`. The callbacks also trust the caller-controlled `data` blob to choose both `tokenIn` and `from`. A malicious pool can therefore be inserted into a route, call the callback with forged `(token, victim)` data, and make the router execute `safeTransferFrom(victim, maliciousPool, amount)` for any ERC20 the victim has approved to the router. The same primitive can pull router-held ERC20s by forging `from = address(this)`.

**Impact:** Any address that has approved the router can be drained without participating in the attack. Router-held ERC20 balances can also be stolen. This is direct theft, not just bad pricing or a malicious route causing the caller to lose their own intended input.

**Paths:**

- Attacker deploys a fake contract implementing the UniswapV3 or TridentCL `swap` entrypoint.

- Attacker submits a route whose V3/CL hop points to that fake pool.

- After `lastCalledPool` is set, the fake pool invokes `uniswapV3SwapCallback` or `tridentCLSwapCallback` with positive deltas and forged `abi.encode(token, victim)` data.

- The callback transfers the victim's approved tokens, or router-held tokens, directly to the attacker-controlled pool.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (3)

### F-002: Public routes can sweep router-held ETH, ERC20, and Bento balances because input accounting ignores contract-owned inventory

**Confidence:** high | **Locations:** `0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:101-116, 0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:124-140, 0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:181-193`

The router exposes commands that spend assets already owned by `address(this)`: `processNative`, `processMyERC20`, and `processInsideBento`. However, the final invariant only checks the caller-declared `tokenIn`/`amountIn` condition, not whether the route actually consumed caller-owned funds. For native input, `amountIn` is not tied to `msg.value`, so an attacker can simply declare enough input to satisfy the check without contributing ETH. As a result, any residual ETH, ERC20 balances, or Bento shares held by the router can be routed to attacker-controlled recipients.

**Impact:** Any dust, accidental transfers, leftover swap balances, or otherwise stranded ETH/ERC20/Bento assets on the router are permissionlessly stealable. This can drain protocol-owned inventory or user funds that become stuck on the router.

**Paths:**

- Attacker waits for the router to hold ETH, ERC20 tokens, or Bento shares.

- Attacker calls `processRoute` with a route starting from command `3`, `1`, or `5` so the router spends its own inventory rather than the caller's.

- For ETH, the attacker sets a large enough `amountIn` without sending `msg.value`, so the final input check still passes.

- The route forwards the consumed inventory to attacker-controlled recipients or sinks.

*Round 1 | Agents: codex_1*

---

### F-003: Native unwrap pays out the router's entire ETH balance instead of only the requested amount

**Confidence:** high | **Locations:** `0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:218-231`

In the unwrap branch of `wrapNative`, the contract always executes `payable(to).transfer(address(this).balance)` after the optional WETH withdrawal. That sends every wei currently held by the router, not the specific `amountIn` being unwrapped.

**Impact:** Any ETH already present on the router can be siphoned to the current unwrap recipient. A crafted route can drain all router ETH, and even an otherwise legitimate small unwrap will accidentally overpay the recipient with unrelated ETH sitting in the contract.

**Paths:**

- Attacker or an ordinary user reaches `wrapNative` in unwrap mode with `to` set to a chosen recipient.

- The function optionally unwraps only a small amount of WETH, or none at all in fake mode.

- `transfer(address(this).balance)` sends the router's full ETH balance to that recipient.

*Round 1 | Agents: codex_1*

---

### F-005: `processUserERC20` is not bound to the declared `tokenIn`, allowing malicious routes to pull arbitrary approved assets from the caller

**Confidence:** high | **Locations:** `0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:101-116, 0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:147-149, 0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:240-260, 0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:278-280, 0x044b75f554b886a065b9567891e45c79542d7357/contracts/RouteProcessor2.sol:298-299`

`processRouteInternal` validates only the externally supplied `tokenIn` balance change, but command `2` (`processUserERC20`) reads an independent token address from the route and then spends `amountIn` of that route-selected asset from `msg.sender`. The route can therefore pull any ERC20 approved to the router via `safeTransferFrom`, or any Bento shares approved to the router via `bentoBox.transfer`, while the final invariant still checks a different asset or even native coin.

**Impact:** A compromised route builder or malicious frontend can steal the caller's approved ERC20s or Bento shares instead of the asset the user intended to trade. This does not require fake V3 callbacks; ordinary route steps like `bentoBridge`, `swapUniV2`, or `swapTrident` are sufficient sinks.

**Paths:**

- Victim approves the router for token `A` or grants BentoBox master-contract approval for shares of token `A`.

- Attacker supplies a route using command `2` with route-selected token `A`, while the external call advertises a different `tokenIn` or uses `NATIVE_ADDRESS`.

- The route spends `amountIn` of token `A` from the caller and forwards it to an attacker-controlled recipient, for example through `bentoBridge`.

- The final balance check passes because it only measures the externally declared `tokenIn`, not the actual asset the route consumed.

*Round 1 | Agents: *

---
