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
- title: Convex extra rewards are claimed to the pool but sold from the RewardManager, permanently stranding them
- claim: Convex reward claims send CRV, CVX, and all extra rewards to the Conic pool address via `getReward(_conicPool, true)`, but the liquidation path only checks `IERC20(rewardToken).balanceOf(address(this))` inside `RewardManagerV2`. Because the RewardManager never receives those extra tokens and has no path to pull arbitrary extra rewards from the pool, listed extra reward tokens accumulate in the pool and are never swapped into CNC.
- impact: Any non-CRV/CVX Convex reward stream can become permanently stuck, causing ongoing loss of yield and trapping reward value inside the pool contract.
- exploit_paths: ["Register an extra Convex reward token with `addExtraReward`.", "Let a supported Curve position accrue that extra reward on Convex.", "Call `claimPoolEarningsAndSellRewardTokens()` or any path that reaches `_claimPoolEarnings()`: Convex sends the extra reward to the Conic pool, but `_swapRewardTokenForWeth()` reads the RewardManager's own balance and swaps nothing."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IOwnableLike {
    function owner() external view returns (address);
}

interface IRewardManagerLike {
    function owner() external view returns (address);

    function pool() external view returns (address);

    function controller() external view returns (address);

    function listExtraRewards() external view returns (address[] memory);

    function addExtraReward(address reward) external returns (bool);

    function claimPoolEarningsAndSellRewardTokens() external;
}

interface IConicPoolLike {
    function rewardManager() external view returns (address);

    function controller() external view returns (address);

    function allCurvePools() external view returns (address[] memory);
}

interface IControllerLike {
    function curveRegistryCache() external view returns (address);
}

interface ICurveRegistryCacheLike {
    function getRewardPool(address pool_) external view returns (address);
}

interface IBaseRewardPoolLike {
    function extraRewardsLength() external view returns (uint256);

    function extraRewards(uint256 index) external view returns (address);
}

interface IExtraRewardLike {
    function rewardToken() external view returns (address);
}

contract FlawVerifier {
    address public constant TARGET = 0x369cBC5C6f139B1132D3B91B87241B37Fc5B971f;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address public constant CNC = 0x9aE380F0272E2162340a5bB646c354271c0F5cFC;

    enum Outcome {
        NOT_RUN,
        VALIDATED_NO_PROFIT,
        REFUTED_OR_INFEASIBLE
    }

    Outcome public outcome;

    address public rewardManager;
    address public selectedRewardToken;
    address public rewardManagerOwner;
    address public pool;
    address public controller;

    bool public stage1AlreadyConfigured;
    bool public stage1AttemptedRegistration;
    bool public stage1RegistrationSucceeded;
    bool public stage1BlockedByOnlyOwner;

    bool public stage2ObservedConvexExtraRewardToken;
    bool public stage3ClaimExecuted;
    bool public stage3ObservedStranding;
    bool public hypothesisValidated;

    uint256 public poolTokenBalanceBefore;
    uint256 public poolTokenBalanceAfter;
    uint256 public rewardManagerTokenBalanceBefore;
    uint256 public rewardManagerTokenBalanceAfter;
    uint256 public poolCncBalanceBefore;
    uint256 public poolCncBalanceAfter;

    string public exploitPathUsed;
    string public status;

    function executeOnOpportunity() external {
        if (outcome != Outcome.NOT_RUN) {
            return;
        }

        _resolveTopology();
        if (rewardManager == address(0) || pool == address(0) || controller == address(0)) {
            exploitPathUsed =
                "1) resolve target topology 2) discover Conic pool/reward manager/controller";
            status =
                "Exploit path infeasible at this fork: the verifier could not resolve the live Conic pool, reward manager, and controller addresses from the target.";
            outcome = Outcome.REFUTED_OR_INFEASIBLE;
            return;
        }

        rewardManagerOwner = _safeOwner(rewardManager);

        address[] memory convexExtraRewardTokens = _discoverConvexExtraRewardTokens(pool, controller);
        address[] memory configuredExtraRewards = _safeListExtraRewards(rewardManager);

        if (convexExtraRewardTokens.length == 0) {
            exploitPathUsed =
                "1) discover Convex extra rewards from the target Conic pool's registered Curve positions";
            status =
                "Exploit path infeasible at this fork: no current Convex extra reward stream was discoverable for the affected pool.";
            outcome = Outcome.REFUTED_OR_INFEASIBLE;
            return;
        }

        selectedRewardToken = _pickIntersection(convexExtraRewardTokens, configuredExtraRewards);

        if (selectedRewardToken != address(0)) {
            stage1AlreadyConfigured = true;
        } else {
            // Path-strict stage 1 from the finding:
            // the reward token must be listed in RewardManagerV2 before the claim/sell path will
            // attempt liquidation. If governance has not already listed it, an unprivileged caller
            // can only test feasibility by attempting addExtraReward() and observing the onlyOwner
            // gate.
            selectedRewardToken = convexExtraRewardTokens[0];
            stage1AttemptedRegistration = true;
            if (rewardManagerOwner != address(this)) {
                stage1BlockedByOnlyOwner = true;
            }
            try IRewardManagerLike(rewardManager).addExtraReward(selectedRewardToken) returns (bool added) {
                stage1RegistrationSucceeded = added;
                if (added) {
                    stage1AlreadyConfigured = true;
                }
            } catch {}
        }

        if (!stage1AlreadyConfigured && !stage1RegistrationSucceeded) {
            exploitPathUsed =
                "1) discover Convex extra reward token 2) attempt addExtraReward(token) on RewardManagerV2 3) blocked by onlyOwner";
            status =
                "Exploit path infeasible at this fork: stage 1 is access-controlled and an unprivileged verifier cannot register the extra reward token.";
            outcome = Outcome.REFUTED_OR_INFEASIBLE;
            return;
        }

        stage2ObservedConvexExtraRewardToken = true;

        poolTokenBalanceBefore = _balanceOf(selectedRewardToken, pool);
        rewardManagerTokenBalanceBefore = _balanceOf(selectedRewardToken, rewardManager);
        poolCncBalanceBefore = _balanceOf(CNC, pool);

        // Path-strict stage 3 from the finding:
        // claimPoolEarningsAndSellRewardTokens() reaches _claimPoolEarnings(), which claims Convex
        // CRV/CVX and extra rewards to the Conic pool. RewardManagerV2 later checks its own balance
        // inside _swapRewardTokenForWeth(), so extra rewards that landed in the pool are ignored.
        try IRewardManagerLike(rewardManager).claimPoolEarningsAndSellRewardTokens() {
            stage3ClaimExecuted = true;
        } catch {
            exploitPathUsed =
                "1) existing configured extra reward 2) call claimPoolEarningsAndSellRewardTokens() on RewardManagerV2 3) reverted";
            status =
                "Exploit path could not be executed at this fork because the live pool earnings claim call reverted.";
            outcome = Outcome.REFUTED_OR_INFEASIBLE;
            return;
        }

        poolTokenBalanceAfter = _balanceOf(selectedRewardToken, pool);
        rewardManagerTokenBalanceAfter = _balanceOf(selectedRewardToken, rewardManager);
        poolCncBalanceAfter = _balanceOf(CNC, pool);

        if (
            rewardManagerTokenBalanceAfter == 0 &&
            poolTokenBalanceAfter >= poolTokenBalanceBefore &&
            (poolTokenBalanceAfter > poolTokenBalanceBefore || poolTokenBalanceAfter > 0)
        ) {
            stage3ObservedStranding = true;
            hypothesisValidated = true;
            exploitPathUsed = stage1AttemptedRegistration
                ? "1) register/add existing Convex extra reward token 2) let the supported Curve position accrue extra rewards on Convex 3) call claimPoolEarningsAndSellRewardTokens() 4) extra reward remains stranded in the Conic pool"
                : "1) use preconfigured Convex extra reward token 2) let the supported Curve position accrue or retain extra rewards on Convex 3) call claimPoolEarningsAndSellRewardTokens() 4) extra reward remains stranded in the Conic pool";
            status =
                "Hypothesis validated mechanically: the listed extra reward token is present on the pool side after the claim/sell path, while RewardManagerV2 still holds none to liquidate. No attacker-realizable public extraction path was identified at this fork, so realized profit remains zero.";
            outcome = Outcome.VALIDATED_NO_PROFIT;
            return;
        }

        exploitPathUsed =
            "1) existing or attempted extra reward registration 2) claimPoolEarningsAndSellRewardTokens()";
        status =
            "Hypothesis not validated on this fork run: no stranded listed extra reward balance was observed after the claim/sell path.";
        outcome = Outcome.REFUTED_OR_INFEASIBLE;
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external pure returns (uint256) {
        return 0;
    }

    function _resolveTopology() internal {
        address targetRewardManager = _safeRewardManagerFromPool(TARGET);
        address targetController = _safeControllerFromPool(TARGET);

        if (targetRewardManager != address(0) && targetController != address(0)) {
            pool = TARGET;
            rewardManager = targetRewardManager;
            controller = targetController;
            return;
        }

        rewardManager = TARGET;
        pool = _safePoolFromRewardManager(TARGET);
        controller = _safeControllerFromRewardManager(TARGET);
    }

    function _discoverConvexExtraRewardTokens(
        address conicPool,
        address controller_
    ) internal view returns (address[] memory) {
        if (conicPool == address(0) || controller_ == address(0)) {
            return new address[](0);
        }

        address registry = _safeCurveRegistryCache(controller_);
        if (registry == address(0)) {
            return new address[](0);
        }

        address[] memory curvePools = _safeAllCurvePools(conicPool);
        if (curvePools.length == 0) {
            return new address[](0);
        }

        uint256 maxCandidates;
        for (uint256 i; i < curvePools.length; i++) {
            address rewardPool = _safeGetRewardPool(registry, curvePools[i]);
            if (rewardPool == address(0)) continue;
            maxCandidates += _safeExtraRewardsLength(rewardPool);
        }

        if (maxCandidates == 0) {
            return new address[](0);
        }

        address[] memory tmp = new address[](maxCandidates);
        uint256 count;

        for (uint256 i; i < curvePools.length; i++) {
            address rewardPool = _safeGetRewardPool(registry, curvePools[i]);
            if (rewardPool == address(0)) continue;

            uint256 extraLen = _safeExtraRewardsLength(rewardPool);
            for (uint256 j; j < extraLen; j++) {
                address extraRewardContract = _safeExtraRewardContract(rewardPool, j);
                if (extraRewardContract == address(0)) continue;
                address rewardToken_ = _safeRewardToken(extraRewardContract);
                if (
                    rewardToken_ == address(0) ||
                    rewardToken_ == CRV ||
                    rewardToken_ == CVX ||
                    rewardToken_ == CNC ||
                    _contains(tmp, count, rewardToken_)
                ) {
                    continue;
                }
                tmp[count] = rewardToken_;
                count++;
            }
        }

        address[] memory tokens = new address[](count);
        for (uint256 i; i < count; i++) {
            tokens[i] = tmp[i];
        }
        return tokens;
    }

    function _safeListExtraRewards(
        address rewardManager_
    ) internal view returns (address[] memory rewards) {
        if (rewardManager_ == address(0)) {
            return new address[](0);
        }
        try IRewardManagerLike(rewardManager_).listExtraRewards() returns (address[] memory listed) {
            return listed;
        } catch {
            return new address[](0);
        }
    }

    function _safeRewardManagerFromPool(address conicPool) internal view returns (address) {
        if (conicPool == address(0)) {
            return address(0);
        }
        try IConicPoolLike(conicPool).rewardManager() returns (address rewardManager_) {
            return rewardManager_;
        } catch {
            return address(0);
        }
    }

    function _safeControllerFromPool(address conicPool) internal view returns (address) {
        if (conicPool == address(0)) {
            return address(0);
        }
        try IConicPoolLike(conicPool).controller() returns (address controller_) {
            return controller_;
        } catch {
            return address(0);
        }
    }

    function _safePoolFromRewardManager(address rewardManager_) internal view returns (address) {
        if (rewardManager_ == address(0)) {
            return address(0);
        }
        try IRewardManagerLike(rewardManager_).pool() returns (address pool_) {
            return pool_;
        } catch {
            return address(0);
        }
    }

    function _safeControllerFromRewardManager(address rewardManager_) internal view returns (address) {
        if (rewardManager_ == address(0)) {
            return address(0);
        }
        try IRewardManagerLike(rewardManager_).controller() returns (address controller_) {
            return controller_;
        } catch {
            return address(0);
        }
    }

    function _safeAllCurvePools(address conicPool) internal view returns (address[] memory) {
        if (conicPool == address(0)) {
            return new address[](0);
        }
        try IConicPoolLike(conicPool).allCurvePools() returns (address[] memory curvePools) {
            return curvePools;
        } catch {
            return new address[](0);
        }
    }

    function _safeCurveRegistryCache(address controller_) internal view returns (address) {
        if (controller_ == address(0)) {
            return address(0);
        }
        try IControllerLike(controller_).curveRegistryCache() returns (address registry) {
            return registry;
        } catch {
            return address(0);
        }
    }

    function _safeOwner(address ownable) internal view returns (address) {
        if (ownable == address(0)) {
            return address(0);
        }
        try IOwnableLike(ownable).owner() returns (address owner_) {
            return owner_;
        } catch {
            return address(0);
        }
    }

    function _pickIntersection(
        address[] memory lhs,
        address[] memory rhs
    ) internal pure returns (address) {
        for (uint256 i; i < lhs.length; i++) {
            for (uint256 j; j < rhs.length; j++) {
                if (lhs[i] == rhs[j]) {
                    return lhs[i];
                }
            }
        }
        return address(0);
    }

    function _contains(
        address[] memory items,
        uint256 length,
        address needle
    ) internal pure returns (bool) {
        for (uint256 i; i < length; i++) {
            if (items[i] == needle) {
                return true;
            }
        }
        return false;
    }

    function _safeGetRewardPool(address registry, address curvePool) internal view returns (address) {
        try ICurveRegistryCacheLike(registry).getRewardPool(curvePool) returns (address rewardPool) {
            return rewardPool;
        } catch {
            return address(0);
        }
    }

    function _safeExtraRewardsLength(address rewardPool) internal view returns (uint256) {
        try IBaseRewardPoolLike(rewardPool).extraRewardsLength() returns (uint256 length) {
            return length;
        } catch {
            return 0;
        }
    }

    function _safeExtraRewardContract(
        address rewardPool,
        uint256 index
    ) internal view returns (address) {
        try IBaseRewardPoolLike(rewardPool).extraRewards(index) returns (address extraRewardContract) {
            return extraRewardContract;
        } catch {
            return address(0);
        }
    }

    function _safeRewardToken(address extraRewardContract) internal view returns (address) {
        try IExtraRewardLike(extraRewardContract).rewardToken() returns (address rewardToken_) {
            return rewardToken_;
        } catch {
            return address(0);
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        if (token == address(0) || account == address(0)) {
            return 0;
        }
        try IERC20Like(token).balanceOf(account) returns (uint256 balance) {
            return balance;
        } catch {
            return 0;
        }
    }
}

```

forge stdout (tail):
```
 │   ├─ [11916] 0x369cBC5C6f139B1132D3B91B87241B37Fc5B971f::allCurvePools() [staticcall]
    │   │   └─ ← [Return] [0x390f3595bCa2Df7d23783dFd126427CCeb997BF4, 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E, 0x0CD6f267b2086bea681E922E19D40512511BE538, 0xCa978A0528116DDA3cbA9ACD3e68bc6191CA53D0]
    │   ├─ [4841] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::getRewardPool(0x390f3595bCa2Df7d23783dFd126427CCeb997BF4) [staticcall]
    │   │   └─ ← [Return] 0xD1DdB0a0815fD28932fBb194C84003683AF8a824
    │   ├─ [2409] 0xD1DdB0a0815fD28932fBb194C84003683AF8a824::extraRewardsLength() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [4841] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::getRewardPool(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E) [staticcall]
    │   │   └─ ← [Return] 0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA
    │   ├─ [2409] 0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA::extraRewardsLength() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [4841] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::getRewardPool(0x0CD6f267b2086bea681E922E19D40512511BE538) [staticcall]
    │   │   └─ ← [Return] 0x3CfB4B26dc96B124D15A6f360503d028cF2a3c00
    │   ├─ [2409] 0x3CfB4B26dc96B124D15A6f360503d028cF2a3c00::extraRewardsLength() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [4841] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::getRewardPool(0xCa978A0528116DDA3cbA9ACD3e68bc6191CA53D0) [staticcall]
    │   │   └─ ← [Return] 0x80c64E468b774F7F96D4DFCe39caE2dd4C2B7f93
    │   ├─ [2409] 0x80c64E468b774F7F96D4DFCe39caE2dd4C2B7f93::extraRewardsLength() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [841] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::getRewardPool(0x390f3595bCa2Df7d23783dFd126427CCeb997BF4) [staticcall]
    │   │   └─ ← [Return] 0xD1DdB0a0815fD28932fBb194C84003683AF8a824
    │   ├─ [409] 0xD1DdB0a0815fD28932fBb194C84003683AF8a824::extraRewardsLength() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [2660] 0xD1DdB0a0815fD28932fBb194C84003683AF8a824::extraRewards(0) [staticcall]
    │   │   └─ ← [Return] 0xD490178B568b07c6DDbDfBBfaF9043772209Ec01
    │   ├─ [2447] 0xD490178B568b07c6DDbDfBBfaF9043772209Ec01::rewardToken() [staticcall]
    │   │   └─ ← [Return] 0xEde29D17154bEa2A6D01F191a912f541b59997E4
    │   ├─ [841] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::getRewardPool(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E) [staticcall]
    │   │   └─ ← [Return] 0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA
    │   ├─ [409] 0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA::extraRewardsLength() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [2660] 0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA::extraRewards(0) [staticcall]
    │   │   └─ ← [Return] 0xac183F7cd62d5b04Fa40362EB67249A80339541A
    │   ├─ [2447] 0xac183F7cd62d5b04Fa40362EB67249A80339541A::rewardToken() [staticcall]
    │   │   └─ ← [Return] 0xC8dC88896aAC1A94aA42B89D65aa5FD4984CB71d
    │   ├─ [841] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::getRewardPool(0x0CD6f267b2086bea681E922E19D40512511BE538) [staticcall]
    │   │   └─ ← [Return] 0x3CfB4B26dc96B124D15A6f360503d028cF2a3c00
    │   ├─ [409] 0x3CfB4B26dc96B124D15A6f360503d028cF2a3c00::extraRewardsLength() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [2660] 0x3CfB4B26dc96B124D15A6f360503d028cF2a3c00::extraRewards(0) [staticcall]
    │   │   └─ ← [Return] 0x749cFfCb53e008841d7387ba37f9284BDeCEe0A9
    │   ├─ [2447] 0x749cFfCb53e008841d7387ba37f9284BDeCEe0A9::rewardToken() [staticcall]
    │   │   └─ ← [Return] 0x2a81cec24D2fe558E87bdc662d994934d4ca1BaF
    │   ├─ [841] 0x3905A3C1156f67BB55366d7A5a11D1043dcf97c9::getRewardPool(0xCa978A0528116DDA3cbA9ACD3e68bc6191CA53D0) [staticcall]
    │   │   └─ ← [Return] 0x80c64E468b774F7F96D4DFCe39caE2dd4C2B7f93
    │   ├─ [409] 0x80c64E468b774F7F96D4DFCe39caE2dd4C2B7f93::extraRewardsLength() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [2660] 0x80c64E468b774F7F96D4DFCe39caE2dd4C2B7f93::extraRewards(0) [staticcall]
    │   │   └─ ← [Return] 0x44AfC3944B8175583cCF529F1133a681666Eb67b
    │   ├─ [2447] 0x44AfC3944B8175583cCF529F1133a681666Eb67b::rewardToken() [staticcall]
    │   │   └─ ← [Return] 0x9Dd5fe015fc1FbA955331Ef8a653F299E9b064De
    │   ├─ [2849] 0x39f15f704c1F4678f7E6359A58a196228266ff02::listExtraRewards() [staticcall]
    │   │   └─ ← [Return] []
    │   ├─ [654] 0x39f15f704c1F4678f7E6359A58a196228266ff02::addExtraReward(0xEde29D17154bEa2A6D01F191a912f541b59997E4)
    │   │   └─ ← [Revert] Ownable: caller is not the owner
    │   └─ ← [Stop]
    ├─ [328] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [350] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x39f15f704c1F4678f7E6359A58a196228266ff02.addExtraReward
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.99s (1.13s CPU time)

Ran 1 test suite in 3.41s (2.99s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 510138)

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
