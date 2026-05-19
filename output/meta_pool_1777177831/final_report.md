# Audit Report

**Total findings:** 2

## Medium (1)

### F-001: Transparent proxies can retain a second upgrade path when paired with implementation-side upgrade logic

**Confidence:** low | **Locations:** `@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:88, @openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol:29, @openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol:61`

`TransparentUpgradeableProxy` only intercepts admin calls; every non-admin call is delegated to the implementation. Because transparent proxies and implementation-side upgrade patterns such as UUPS mutate the same ERC-1967 implementation slot, any upgrade entrypoint exposed by the implementation remains callable through the proxy by non-admin users and can change the proxy implementation outside the `ProxyAdmin` surface.

**Impact:** A deployment that assumes `ProxyAdmin` is the sole upgrade authority can accidentally leave a parallel upgrade surface reachable through the implementation. If the implementation's upgrade authorization is weak, bypassable, or left uninitialized, an attacker can replace the proxy logic and seize proxy-held assets or permissions.

**Paths:**

- A `TransparentUpgradeableProxy` is deployed pointing at an implementation that exposes `upgradeTo`/`upgradeToAndCall`-style logic.

- A non-admin caller invokes that implementation-defined upgrade function through the proxy, so `TransparentUpgradeableProxy._fallback()` forwards the call instead of handling it as an admin action.

- The implementation-side upgrade routine writes the shared ERC-1967 implementation slot, changing proxy logic without going through `ProxyAdmin`.

*Round 2 | Agents: codex*

---

## Low (1)

### F-002: Payable proxy deployment paths accept ETH with no initializer and can strand native funds in the proxy

**Confidence:** high | **Locations:** `@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:22, @openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:67, @openzeppelin/contracts/proxy/beacon/BeaconProxy.sol:30, @openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol:61, @openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol:160`

`ERC1967Proxy`, `TransparentUpgradeableProxy`, and `BeaconProxy` constructors are payable, but they route setup through `_upgradeToAndCall(..., false)` or `_upgradeBeaconToAndCall(..., false)`, which skip the delegatecall whenever the initializer payload is empty. As a result, deployments with `msg.value > 0` and empty initialization data accept ETH into the proxy address without executing any logic to account for, forward, or refund it.

**Impact:** A deployment script, factory, or operator that accidentally attaches ETH while providing empty init calldata can permanently strand native funds in the proxy. If the implementation does not expose an explicit ETH recovery path, those funds are effectively lost.

**Paths:**

- Deploy `ERC1967Proxy` with non-zero `msg.value` and empty `_data`; constructor accepts ETH but `_upgradeToAndCall(..., false)` performs no delegatecall.

- Deploy `TransparentUpgradeableProxy` with non-zero `msg.value` and empty `_data`; the inherited `ERC1967Proxy` constructor leaves ETH sitting in proxy storage.

- Deploy `BeaconProxy` with non-zero `msg.value` and empty `data`; `_upgradeBeaconToAndCall(..., false)` skips initialization and the ETH remains on the proxy.

*Round 1 | Agents: codex*

---
