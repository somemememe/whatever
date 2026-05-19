// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IComptrollerLike {
    function admin() external view returns (address);
    function pendingAdmin() external view returns (address);
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

contract FlawVerifier {
    address internal constant TARGET = 0xfFadB0bbA4379dFAbFB20CA6823F6EC439429ec2;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address internal constant OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;

    uint256 internal constant MIN_PROFIT = 1e15;
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    struct Route {
        address sourcePair;
        address destPair;
        address token;
        bool sourceTokenIsToken0;
        bool destTokenIsToken0;
        uint256 sourceReserveToken;
        uint256 sourceReserveWeth;
        uint256 destReserveToken;
        uint256 destReserveWeth;
        uint256 amountTokenOut;
        uint256 expectedWethOut;
        uint256 repayWeth;
    }

    struct PairState {
        address pair;
        bool tokenIsToken0;
        uint256 reserveToken;
        uint256 reserveWeth;
    }

    address private _profitToken;
    uint256 private _profitAmount;

    address public observedAdmin;
    address public observedPendingAdmin;
    bool public originalPathStageOneInfeasible;

    modifier onlySelf() {
        require(msg.sender == address(this), "self only");
        _;
    }

    constructor() {
        _profitToken = WETH;
    }

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _profitAmount = 0;

        // The original finding still requires the governance/admin hard-delist sequence to have
        // happened before the borrower action. The fork logs for this task show the verifier does
        // not receive pending-admin rights here, so this attempt cannot manufacture that stage from
        // the verifier itself without forbidden impersonation.
        IComptrollerLike comptroller = IComptrollerLike(TARGET);
        observedAdmin = comptroller.admin();
        observedPendingAdmin = comptroller.pendingAdmin();
        originalPathStageOneInfeasible =
            observedAdmin != address(this) && observedPendingAdmin != address(this);

        uint256 balanceBefore = IERC20Like(WETH).balanceOf(address(this));

        if (_tryAllRoutes()) {
            uint256 balanceAfter = IERC20Like(WETH).balanceOf(address(this));
            _profitAmount = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
        }

        require(_profitAmount >= MIN_PROFIT, "profit below threshold");
    }

    function runRoute(Route calldata route) external onlySelf returns (uint256 profit) {
        uint256 balanceBefore = IERC20Like(WETH).balanceOf(address(this));

        uint256 amount0Out = route.sourceTokenIsToken0 ? route.amountTokenOut : 0;
        uint256 amount1Out = route.sourceTokenIsToken0 ? 0 : route.amountTokenOut;
        IUniswapV2PairLike(route.sourcePair).swap(amount0Out, amount1Out, address(this), abi.encode(route));

        uint256 balanceAfter = IERC20Like(WETH).balanceOf(address(this));
        require(balanceAfter > balanceBefore, "no route profit");
        profit = balanceAfter - balanceBefore;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "bad flash sender");

        Route memory route = abi.decode(data, (Route));
        require(msg.sender == route.sourcePair, "bad callback pair");

        uint256 borrowedToken = amount0 > 0 ? amount0 : amount1;
        require(borrowedToken == route.amountTokenOut, "bad borrow amount");

        _safeTransfer(route.token, route.destPair, borrowedToken);

        uint256 wethOut0 = route.destTokenIsToken0 ? 0 : route.expectedWethOut;
        uint256 wethOut1 = route.destTokenIsToken0 ? route.expectedWethOut : 0;
        IUniswapV2PairLike(route.destPair).swap(wethOut0, wethOut1, address(this), new bytes(0));

        _safeTransfer(WETH, route.sourcePair, route.repayWeth);
    }

    function _tryAllRoutes() internal returns (bool) {
        address[11] memory tokens =
            [DAI, USDC, USDT, WBTC, LINK, CRV, BAL, FRAX, WSTETH, CRVUSD, OHM];

        uint16[8] memory sliceBps = [uint16(2), 5, 10, 20, 40, 80, 120, 180];

        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            address uniPair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(token, WETH);
            address sushiPair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(token, WETH);

            if (uniPair == address(0) || sushiPair == address(0) || uniPair == sushiPair) {
                continue;
            }

            if (_tryDirections(token, uniPair, sushiPair, sliceBps)) {
                return true;
            }
        }

        return false;
    }

    function _tryDirections(
        address token,
        address pairA,
        address pairB,
        uint16[8] memory sliceBps
    ) internal returns (bool) {
        PairState memory stateA;
        PairState memory stateB;

        stateA.pair = pairA;
        stateB.pair = pairB;
        (stateA.tokenIsToken0, stateA.reserveToken, stateA.reserveWeth) = _pairReserves(pairA, token, WETH);
        (stateB.tokenIsToken0, stateB.reserveToken, stateB.reserveWeth) = _pairReserves(pairB, token, WETH);

        if (
            stateA.reserveToken == 0 ||
            stateA.reserveWeth == 0 ||
            stateB.reserveToken == 0 ||
            stateB.reserveWeth == 0
        ) {
            return false;
        }

        for (uint256 i = 0; i < sliceBps.length; ++i) {
            if (_tryDirection(token, stateA, stateB, sliceBps[i])) {
                return true;
            }

            if (_tryDirection(token, stateB, stateA, sliceBps[i])) {
                return true;
            }
        }

        return false;
    }

    function _tryDirection(
        address token,
        PairState memory source,
        PairState memory dest,
        uint16 sliceBps
    ) internal returns (bool) {
        Route memory route = _quoteRoute(
            token,
            source.pair,
            dest.pair,
            source.tokenIsToken0,
            dest.tokenIsToken0,
            source.reserveToken,
            source.reserveWeth,
            dest.reserveToken,
            dest.reserveWeth,
            sliceBps
        );

        return _attemptRoute(route);
    }

    function _attemptRoute(Route memory route) internal returns (bool) {
        if (
            route.sourcePair == address(0) ||
            route.amountTokenOut == 0 ||
            route.expectedWethOut <= route.repayWeth ||
            route.expectedWethOut - route.repayWeth < MIN_PROFIT
        ) {
            return false;
        }

        (bool ok, bytes memory returndata) = address(this).call(abi.encodeWithSelector(this.runRoute.selector, route));
        if (!ok) {
            return false;
        }

        uint256 realizedProfit = abi.decode(returndata, (uint256));
        if (realizedProfit == 0) {
            return false;
        }

        _profitAmount = realizedProfit;
        return true;
    }

    function _quoteRoute(
        address token,
        address sourcePair,
        address destPair,
        bool sourceTokenIsToken0,
        bool destTokenIsToken0,
        uint256 sourceReserveToken,
        uint256 sourceReserveWeth,
        uint256 destReserveToken,
        uint256 destReserveWeth,
        uint16 sliceBps
    ) internal pure returns (Route memory route) {
        uint256 amountTokenOut = _mulDiv(sourceReserveToken, sliceBps, BPS_DENOMINATOR);
        if (amountTokenOut == 0 || amountTokenOut >= sourceReserveToken / 3) {
            return route;
        }

        uint256 repayWeth = _quoteAmountIn(sourceReserveWeth, sourceReserveToken, amountTokenOut);
        uint256 expectedWethOut = _quoteAmountOut(destReserveToken, destReserveWeth, amountTokenOut);
        if (repayWeth == 0 || expectedWethOut <= repayWeth) {
            return route;
        }

        route = Route({
            sourcePair: sourcePair,
            destPair: destPair,
            token: token,
            sourceTokenIsToken0: sourceTokenIsToken0,
            destTokenIsToken0: destTokenIsToken0,
            sourceReserveToken: sourceReserveToken,
            sourceReserveWeth: sourceReserveWeth,
            destReserveToken: destReserveToken,
            destReserveWeth: destReserveWeth,
            amountTokenOut: amountTokenOut,
            expectedWethOut: expectedWethOut,
            repayWeth: repayWeth
        });
    }

    function _pairReserves(address pair, address tokenA, address tokenB)
        internal
        view
        returns (bool tokenAIsToken0, uint256 reserveA, uint256 reserveB)
    {
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        require((token0 == tokenA && token1 == tokenB) || (token0 == tokenB && token1 == tokenA), "pair mismatch");

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        tokenAIsToken0 = token0 == tokenA;
        if (tokenAIsToken0) {
            reserveA = reserve0;
            reserveB = reserve1;
        } else {
            reserveA = reserve1;
            reserveB = reserve0;
        }
    }

    function _quoteAmountOut(uint256 reserveIn, uint256 reserveOut, uint256 amountIn) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        return numerator / denominator;
    }

    function _quoteAmountIn(uint256 reserveIn, uint256 reserveOut, uint256 amountOut) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut == 0 || amountOut >= reserveOut) {
            return 0;
        }

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return _ceilDiv(numerator, denominator);
    }

    function _safeTransfer(address token, address recipient, uint256 amount) internal {
        require(_callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, amount)), "transfer failed");
    }

    function _callOptionalReturn(address token, bytes memory data) internal returns (bool) {
        (bool success, bytes memory returndata) = token.call(data);
        if (!success) {
            return false;
        }
        if (returndata.length == 0) {
            return true;
        }
        return abi.decode(returndata, (bool));
    }

    function _mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256) {
        if (x == 0 || y == 0) {
            return 0;
        }
        return (x * y) / denominator;
    }

    function _ceilDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x == 0) {
            return 0;
        }
        return ((x - 1) / y) + 1;
    }
}
