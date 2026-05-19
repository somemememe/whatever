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
- title: MasterChef migrator can replace real LP collateral with worthless tokens and steal all staked funds
- claim: `setMigrator()` lets the owner install an arbitrary migrator, and `migrate()` then approves that migrator for the pool's entire LP balance before only checking that the replacement token reports the same `balanceOf(address(this))`. A malicious migrator can pull out the real LP tokens, mint or otherwise return a fake token that reports the same balance, and permanently swap the pool to the worthless replacement.
- impact: All LP tokens in a migrated pool can be stolen, while users are left with accounting claims on fake LP tokens when they later withdraw.
- exploit_paths: ["Owner sets a malicious migrator with `setMigrator()`", "Anyone calls `migrate(pid)`", "MasterChef approves the migrator for the pool's full LP balance", "Migrator transfers out the genuine LP tokens and returns a fake token with a spoofed/minted matching balance", "MasterChef updates `pool.lpToken`, so future withdrawals return the fake asset instead of the original collateral"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

contract FlawVerifier {
    address internal constant TARGET = 0xE11fc0B43ab98Eb91e9836129d1ee7c3Bc95df50;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _hypothesisValidated;

    bool public checkedTarget;
    bool public targetHasCode;
    bool public targetExposesMigratorFlow;
    bool public ownerStageReachable;
    address public observedOwner;
    uint256 public observedPoolLength;
    address public observedMigrator;
    string public exploitPathUsed;
    string public infeasibilityReason;

    constructor() {}

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;
        _hypothesisValidated = false;

        checkedTarget = true;
        targetHasCode = TARGET.code.length != 0;
        targetExposesMigratorFlow = false;
        ownerStageReachable = false;
        observedOwner = address(0);
        observedPoolLength = 0;
        observedMigrator = address(0);
        exploitPathUsed = "none";
        infeasibilityReason = "";

        if (!targetHasCode) {
            infeasibilityReason = "target address has no code at the fork";
            return;
        }

        // Stage 0 sanity check against the supplied target.
        // The finding requires the same contract to expose the MasterChef migrator surface:
        // - owner()
        // - setMigrator(address)
        // - migrator()
        // - poolLength()/poolInfo(uint256)
        // - migrate(uint256)
        //
        // The provided target address resolves to SushiMaker in the supplied source bundle,
        // not MasterChef. If these view selectors are absent on the live target, the exploit
        // path cannot even start against the provided address.
        (bool hasPoolLength, uint256 poolLength_) = _staticUint(TARGET, bytes4(keccak256(bytes("poolLength()"))));
        (bool hasMigrator, address migrator_) = _staticAddress(TARGET, bytes4(keccak256(bytes("migrator()"))));
        (bool hasOwner, address owner_) = _staticAddress(TARGET, bytes4(keccak256(bytes("owner()"))));

        if (hasPoolLength) {
            observedPoolLength = poolLength_;
        }
        if (hasMigrator) {
            observedMigrator = migrator_;
        }
        if (hasOwner) {
            observedOwner = owner_;
        }

        targetExposesMigratorFlow = hasPoolLength && hasMigrator && hasOwner;
        if (!targetExposesMigratorFlow) {
            exploitPathUsed = "none";
            infeasibilityReason = "provided target does not expose MasterChef migrator flow";
            return;
        }

        // Stage 1 from the hypothesis: owner sets a malicious migrator with setMigrator().
        // Without cheating primitives (no prank/storage writes) this verifier can only use
        // legitimate caller rights. If the verifier is not the owner on the fork, the exploit
        // path is blocked before any LP approval or migration can occur.
        if (owner_ != address(this)) {
            exploitPathUsed = "blocked at stage 1: setMigrator() onlyOwner";
            infeasibilityReason = "verifier is not the target owner on the fork";
            return;
        }

        ownerStageReachable = true;

        // If this branch is ever reachable on a different fork/target, an exploit still needs
        // a replacement token that already exists on-chain and can satisfy:
        //   newLpToken.balanceOf(target) == originalLpBalance
        // after the genuine LP collateral has been removed.
        //
        // This attempt intentionally does not fabricate such a token because the harness
        // forbids deploying a custom ERC20 / fake accounting token. No positive-profit route
        // is constructed here beyond the exact privileged migrator path, and on the supplied
        // fork/target the privileged stage is already infeasible.
        exploitPathUsed = "blocked after stage 1 under harness anti-cheat constraints";
        infeasibilityReason = "no existing replacement token is identified by the supplied context";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function target() external pure returns (address) {
        return TARGET;
    }

    function _staticAddress(address target_, bytes4 selector) internal view returns (bool ok, address value) {
        (bool success, bytes memory data) = target_.staticcall(abi.encodeWithSelector(selector));
        if (!success || data.length < 32) {
            return (false, address(0));
        }
        return (true, abi.decode(data, (address)));
    }

    function _staticUint(address target_, bytes4 selector) internal view returns (bool ok, uint256 value) {
        (bool success, bytes memory data) = target_.staticcall(abi.encodeWithSelector(selector));
        if (!success || data.length < 32) {
            return (false, 0);
        }
        return (true, abi.decode(data, (uint256)));
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: migrate(pid), pool.lptoken, withdraw; generated code does not cover paths indexes: 1, 4
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
