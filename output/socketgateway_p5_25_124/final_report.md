# Audit Report

**Total findings:** 7

## Critical (1)

### F-002: Optimism and Arbitrum routes trust attacker-chosen bridge contracts as spenders and call targets

**Confidence:** high | **Locations:** `0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/optimism/l1/NativeOptimism.sol:123, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/optimism/l1/NativeOptimism.sol:209, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/optimism/l1/NativeOptimism.sol:313, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/optimism/l1/NativeOptimism.sol:387, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/optimism/l1/NativeOpStack.sol:119, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/optimism/l1/NativeOpStack.sol:183, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/optimism/l1/NativeOpStack.sol:261, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/arbitrum/l1/NativeArbitrum.sol:108, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/arbitrum/l1/NativeArbitrum.sol:161, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/arbitrum/l1/NativeArbitrum.sol:228`

These routes accept caller-supplied `customBridgeAddress` or `gatewayAddress` values, grant them `type(uint256).max` allowance over gateway-held ERC20s, and on Optimism native paths immediately send gateway ETH to those attacker-chosen contracts via payable bridge calls.

**Impact:** An attacker can install an unlimited approval from the gateway to a malicious contract and steal current or future gateway-held ERC20 balances, or directly divert gateway ETH to a malicious payable contract pretending to be the bridge.

**Paths:**

- Call an Optimism or Arbitrum ERC20 bridge entrypoint with a malicious `customBridgeAddress`/`gatewayAddress` that uses the freshly granted approval to `transferFrom` gateway tokens.

- Use the Optimism native path with a malicious `customBridgeAddress` implementing `depositETHTo` to receive gateway ETH.

- Use the same pattern through `bridgeAfterSwap` or `swapAndBridge` after residual assets already exist in the gateway.

*Round 1 | Agents: codex_1*

---

## High (4)

### F-001: Unrestricted post-swap bridge entrypoints can exfiltrate assets already held by the gateway

**Confidence:** high | **Locations:** `0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/SocketGateway.sol:87, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/SocketGateway.sol:196, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/BridgeImplBase.sol:127, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/across/Across.sol:100, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/connnext/Connext.sol:119, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/refuel/refuel.sol:60, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/cbridge/CelerImpl.sol:125, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/polygon/NativePolygon.sol:77, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/gnosis-native/gnosisNativeImpl.sol:193`

Any user can reach route implementations through `executeRoute`/`executeRoutes`, and many bridge implementations expose an unrestricted external `bridgeAfterSwap(uint256,bytes)` entrypoint that immediately spends tokens or ETH already sitting in the gateway without proving that the specified `amount` came from a swap in the same transaction or from the current caller.

**Impact:** Any stranded balances already resident in the gateway, including dust, refunds, accidental transfers, or partially recovered funds, can be permissionlessly bridged to an attacker-controlled recipient.

**Paths:**

- Call `executeRoute(routeId, abi.encodeWithSelector(bridgeAfterSwap,uint256,bytes))` for a route whose `bridgeAfterSwap` spends gateway-held funds.

- Call `executeRoutes` with one or more `bridgeAfterSwap` payloads to sweep multiple residual assets.

- Wait for refunds, accidental transfers, or other leftovers to accumulate in the gateway, then bridge them to an attacker-controlled destination.

*Round 1 | Agents: codex_1*

---

### F-003: Hop routes forward gateway ETH to caller-chosen contracts

**Confidence:** high | **Locations:** `0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l1/HopImplL1.sol:111, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l1/HopImplL1.sol:161, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l1/HopImplL1.sol:275, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l1/HopImplL1V2.sol:111, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l1/HopImplL1V2.sol:161, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l1/HopImplL1V2.sol:275, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l2/HopImplL2.sol:127, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l2/HopImplL2.sol:179, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l2/HopImplL2.sol:291, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l2/HopImplL2V2.sol:127, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l2/HopImplL2V2.sol:179, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l2/HopImplL2V2.sol:291`

Hop route parameters `l1bridgeAddr` and `hopAMM` are fully caller-controlled, and the native branches invoke those addresses with `{value: amount}` from the gateway context rather than validating them against trusted bridge contracts.

**Impact:** A malicious payable contract can be nominated as the bridge target and receive gateway ETH directly, allowing theft of any ETH balance already present in the gateway or produced by a composed flow.

**Paths:**

- Call a Hop native bridge function with `l1bridgeAddr` or `hopAMM` set to a malicious contract that simply accepts the payable call.

- Trigger the same behavior via `bridgeAfterSwap` or `swapAndBridge` once ETH has reached the gateway.

- Use a fake Hop target that accepts value and performs no real bridge, causing outright loss instead of bridging.

*Round 1 | Agents: codex_1*

---

### F-004: ZkSync composed bridge paths pull ERC20s from the user a second time and trust the wrong token field

**Confidence:** high | **Locations:** `0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/zksync/ZkSyncBridgeImpl.sol:176, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/zksync/ZkSyncBridgeImpl.sol:199, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/zksync/ZkSyncBridgeImpl.sol:248, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/zksync/ZkSyncBridgeImpl.sol:280`

In both ZkSync post-swap entrypoints, the ERC20 branch executes `safeTransferFrom(msg.sender, socketGateway, ...)` even though the swapped output should already be inside the gateway, and `swapAndBridge` chooses the token to pull from calldata (`zkSyncBridgeData.token`) instead of the token returned by the preceding swap.

**Impact:** Users who approved the gateway can be double-charged during swap-plus-bridge flows, and an attacker-controlled calldata payload can make the gateway pull and bridge a different approved token than the asset actually produced by the swap.

**Paths:**

- Run `swapAndBridge` for an ERC20 swap output; after the swap completes, the route pulls `bridgeAmount` from the caller again.

- Supply a `zkSyncBridgeData.token` different from the swap output token so the composed flow debits some other approved asset from the caller.

- Call `bridgeAfterSwap` with an ERC20 token after a prior step already moved funds into the gateway, causing an unnecessary second pull from the caller.

*Round 1 | Agents: codex_1*

---

### F-005: Many direct native bridge entrypoints can spend pre-existing gateway ETH without reconciling `msg.value`

**Confidence:** high | **Locations:** `0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/refuel/refuel.sol:136, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/across/Across.sol:287, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/connnext/Connext.sol:257, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/optimism/l1/NativeOptimism.sol:387, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/optimism/l1/NativeOpStack.sol:309, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l1/HopImplL1.sol:275, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/hop/l2/HopImplL2.sol:291, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/polygon/NativePolygon.sol:226, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/zksync/ZkSyncBridgeImpl.sol:135, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/gnosis-native/gnosisNativeImpl.sol:163, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/bridges/cbridge/CelerImpl.sol:357`

Multiple public native bridge entrypoints trust a caller-supplied `amount` (and sometimes `fees`) and forward that much ETH from the gateway without enforcing that the current transaction supplied matching `msg.value`.

**Impact:** If the gateway already holds ETH from prior dust, refunds, forced transfers, or other leftovers, a later caller can bridge or forward that residual ETH while contributing little or no native value themselves.

**Paths:**

- Wait for the gateway to accumulate ETH.

- Invoke one of the native bridge entrypoints with `msg.value` below the requested bridge amount, or zero if enough ETH is already stranded in the gateway.

- Receive the drained value on the destination chain or via a malicious bridge target on routes that also trust user-supplied bridge addresses.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-006: `swapAndMultiBridge` is permanently unusable because the ratio-aggregation loop never increments

**Confidence:** high | **Locations:** `0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/SocketGateway.sol:121, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/SocketGatewayDeployment.sol:121`

The first loop in `swapAndMultiBridge` omits `++index`, so any call with at least one bridge leg spins until the transaction runs out of gas before any swap or bridge logic can execute.

**Impact:** The advertised multi-bridge flow is completely DOSed and unusable in production.

**Paths:**

- Call `swapAndMultiBridge` with `bridgeRouteIds.length > 0`.

- Execution enters the ratio aggregation loop and never reaches the swap stage because `index` is never incremented.

*Round 1 | Agents: codex_1*

---

### F-007: Built-in routes below ID 385 cannot actually be disabled

**Confidence:** high | **Locations:** `0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/SocketGateway.sol:350, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/SocketGateway.sol:411, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/SocketGatewayDeployment.sol:350, 0xcc5fda5e3ca925bd0bb428c8b2669496ee43067e/src/SocketGatewayDeployment.sol:411`

`disableRoute` only writes the `routes` mapping, but `addressAt` bypasses that mapping for every reserved route ID below 385 and always returns a hardcoded implementation address instead.

**Impact:** If any built-in route is found vulnerable or starts malfunctioning, the owner cannot use the documented disable mechanism to shut it down.

**Paths:**

- Owner calls `disableRoute(routeId)` for a reserved built-in route.

- Subsequent calls still succeed because `addressAt(routeId)` ignores the updated mapping entry for IDs below 385.

*Round 1 | Agents: codex_1*

---
